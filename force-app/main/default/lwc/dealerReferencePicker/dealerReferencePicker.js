import { LightningElement, api, track } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import searchValues from '@salesforce/apex/DealerReferencePickerController.search';

const SEARCH_DELAY_MS = 250;
const BLUR_CLOSE_DELAY_MS = 200;
const HELP_TEXT =
    'Choose an existing name, or Add a new one. A new name is saved only when the opportunity is created.';
const PENDING_PREFIX = 'pending:';
const PEER_OPEN_EVENT = 'dealerrefpicker:open';

let pickerSeq = 0;

/**
 * #GC-3598 Flow screen picker for DealerReferenceValue__c.
 *
 * Behavior:
 * - Focus/open → show up to 50 matches in a 5-row scrollable list
 * - Click existing option → select (pill) and allow remove
 * - Blur / peer open / Escape / outside → close list without selecting
 * - Type a new name → select that name. The record is created when the Opportunity is saved.
 */
export default class DealerReferencePicker extends LightningElement {
    @api label;
    @api typeValue;
    @api placeholder;

    helpText = HELP_TEXT;

    _required = false;
    _allowMultiple = false;

    @api
    get required() {
        return this._required;
    }
    set required(value) {
        this._required = value === true || value === 'true';
    }

    @api
    get allowMultiple() {
        return this._allowMultiple;
    }
    set allowMultiple(value) {
        this._allowMultiple = value === true || value === 'true';
    }

    @track selections = [];
    @track options = [];
    @track searchTerm = '';
    @track isLoading = false;
    @track errorMessage = '';
    @track dropdownOpen = false;

    _selectedId = '';
    _selectedLabel = '';
    _selectedIds = '';
    _selectedLabels = '';
    _searchTimeout;
    _blurTimeout;
    _instanceId;
    _wantsOpen = false;
    _suppressBlurClose = false;

    @api
    get selectedId() {
        return this._selectedId;
    }
    set selectedId(value) {
        const next = value || '';
        if (!next && this.selections.length > 0) {
            return;
        }
        this._selectedId = next;
        this.hydrateFromOutputs();
    }

    @api
    get selectedLabel() {
        return this._selectedLabel;
    }
    set selectedLabel(value) {
        const next = value || '';
        if (!next && this.selections.length > 0) {
            return;
        }
        this._selectedLabel = next;
        this.hydrateFromOutputs();
    }

    @api
    get selectedIds() {
        return this._selectedIds;
    }
    set selectedIds(value) {
        const next = value || '';
        if (!next && this.selections.length > 0) {
            return;
        }
        this._selectedIds = next;
        this.hydrateFromOutputs();
    }

    @api
    get selectedLabels() {
        return this._selectedLabels;
    }
    set selectedLabels(value) {
        const next = value || '';
        if (!next && this.selections.length > 0) {
            return;
        }
        this._selectedLabels = next;
        this.hydrateFromOutputs();
    }

    get formElementClass() {
        return this.errorMessage ? 'picker-root has-error' : 'picker-root';
    }

    get comboboxClass() {
        return this.dropdownOpen ? 'combobox is-open' : 'combobox';
    }

    get inputShellClass() {
        return this.errorMessage ? 'input-shell has-error' : 'input-shell';
    }

    get multiInputShellClass() {
        return this.errorMessage
            ? 'input-shell input-shell_multi has-error'
            : 'input-shell input-shell_multi';
    }

    get resolvedPlaceholder() {
        if (this.placeholder) {
            return this.placeholder;
        }
        return this.allowMultiple ? 'Search to add…' : 'Type to search…';
    }

    get trimmedSearchTerm() {
        return (this.searchTerm || '').trim();
    }

    get selectionItems() {
        return this.selections;
    }

    get typedOption() {
        const term = this.trimmedSearchTerm;
        if (!term || this.isLoading) {
            return null;
        }
        const exactInOptions = this.options.some(
            (option) => (option.name || '').toLowerCase() === term.toLowerCase()
        );
        const exactSelected = this.selections.some(
            (item) => (item.name || '').toLowerCase() === term.toLowerCase()
        );
        if (exactInOptions || exactSelected) {
            return null;
        }
        return {
            id: PENDING_PREFIX + encodeURIComponent(term),
            name: term
        };
    }

    get displayOptions() {
        const rows = this.options.map((option) => ({
            id: option.id,
            name: option.name,
            label: option.name,
            optionClass: 'option-label'
        }));
        const typed = this.typedOption;
        if (typed) {
            rows.unshift({
                id: typed.id,
                name: typed.name,
                label: `Add "${typed.name}"`,
                optionClass: 'option-label option-label_add'
            });
        }
        return rows;
    }

    get hasSingleSelection() {
        return !this.allowMultiple && this.selections.length === 1;
    }

    get singleSelectionId() {
        return this.hasSingleSelection ? this.selections[0].id : '';
    }

    get singleSelectionName() {
        return this.hasSingleSelection ? this.selections[0].name : '';
    }

    get showDropdown() {
        return this._wantsOpen && this.dropdownOpen && (!this.hasSingleSelection || this.allowMultiple);
    }

    get showEmptyState() {
        return this.showDropdown && !this.isLoading && this.displayOptions.length === 0;
    }

    connectedCallback() {
        this._instanceId = `drp-${++pickerSeq}-${Date.now()}`;
        this._boundPeerOpen = (event) => this.handlePeerOpen(event);
        window.addEventListener(PEER_OPEN_EVENT, this._boundPeerOpen);
        // Flow fields render after this component. Copy their font once they exist.
        this._styleTimer = window.setTimeout(() => this.syncStandardStyles(), 300);
    }

    renderedCallback() {
        if (!this._styledFromStandard) {
            this.syncStandardStyles();
        }
    }

    disconnectedCallback() {
        window.removeEventListener(PEER_OPEN_EVENT, this._boundPeerOpen);
        window.clearTimeout(this._searchTimeout);
        window.clearTimeout(this._blurTimeout);
        window.clearTimeout(this._styleTimer);
    }

    /**
     * Expected Ship Date is a standard Flow input. Read its real font and box size
     * and apply those to this picker so the portal theme is not guessed.
     */
    syncStandardStyles() {
        if (this._styledFromStandard) {
            return;
        }
        const sample = this.findStandardInput();
        if (!sample) {
            return;
        }
        const inputStyle = window.getComputedStyle(sample);
        const host = this.template.host;
        host.style.setProperty('--picker-input-font-family', inputStyle.fontFamily);
        host.style.setProperty('--picker-input-font-size', inputStyle.fontSize);
        host.style.setProperty('--picker-input-font-weight', inputStyle.fontWeight);
        host.style.setProperty('--picker-input-line-height', inputStyle.lineHeight);
        host.style.setProperty('--picker-input-color', inputStyle.color);
        host.style.setProperty('--picker-input-height', inputStyle.height);
        host.style.setProperty('--picker-input-radius', inputStyle.borderRadius);
        host.style.setProperty('--picker-input-border-color', inputStyle.borderTopColor);
        host.style.setProperty('--picker-input-border-width', inputStyle.borderTopWidth);

        const boxStyle = this.findRoundedFieldBox(sample);
        if (boxStyle) {
            host.style.setProperty('--picker-input-radius', boxStyle.borderTopLeftRadius);
            host.style.setProperty('--picker-input-border-color', boxStyle.borderTopColor);
            host.style.setProperty('--picker-input-border-width', boxStyle.borderTopWidth);
            host.style.setProperty('--picker-input-height', boxStyle.height);
        }

        const fieldSpacing = this.measureStandardFieldSpacing(sample);
        if (fieldSpacing) {
            host.style.setProperty('--picker-field-spacing', fieldSpacing);
        }

        const root = sample.getRootNode();
        const label = root && root.querySelector ? root.querySelector('.slds-form-element__label, label') : null;
        if (label) {
            const labelStyle = window.getComputedStyle(label);
            host.style.setProperty('--picker-label-font-family', labelStyle.fontFamily);
            host.style.setProperty('--picker-label-font-size', labelStyle.fontSize);
            host.style.setProperty('--picker-label-font-weight', labelStyle.fontWeight);
            host.style.setProperty('--picker-label-line-height', labelStyle.lineHeight);
            host.style.setProperty('--picker-label-color', labelStyle.color);
        }
        this._styledFromStandard = true;
    }

    /**
     * The date field's rounded border sits on the outer box, not the inner input.
     * Use that box so the picker corners match Expected Ship Date.
     */
    findRoundedFieldBox(start) {
        let node = start;
        for (let depth = 0; depth < 8 && node; depth += 1) {
            if (node !== start && node.nodeType === 1) {
                const style = window.getComputedStyle(node);
                const radius = parseFloat(style.borderTopLeftRadius) || 0;
                const border = parseFloat(style.borderTopWidth) || 0;
                const height = parseFloat(style.height) || 0;
                if (radius >= 2 && radius <= 16 && border >= 1 && height >= 24 && height <= 56) {
                    return style;
                }
            }
            node = this.parentAcrossShadow(node);
        }
        return null;
    }

    /**
     * Gap under a standard Flow field (Expected Ship Date / Description).
     * Ignore tiny theme spacing and page-level margins.
     */
    measureStandardFieldSpacing(start) {
        let node = start;
        let best = 0;
        for (let depth = 0; depth < 16 && node; depth += 1) {
            if (node.nodeType === 1) {
                const style = window.getComputedStyle(node);
                const gap = (parseFloat(style.marginBottom) || 0) + (parseFloat(style.paddingBottom) || 0);
                if (gap >= 24 && gap <= 48 && gap > best) {
                    best = gap;
                }
            }
            node = this.parentAcrossShadow(node);
        }
        return best ? `${Math.round(best)}px` : null;
    }

    parentAcrossShadow(node) {
        if (!node) {
            return null;
        }
        if (node.parentElement) {
            return node.parentElement;
        }
        const root = node.getRootNode && node.getRootNode();
        return root && root.host ? root.host : null;
    }

    findStandardInput() {
        const queue = [document];
        const seen = new Set();
        let visited = 0;
        while (queue.length && visited < 2500) {
            const root = queue.shift();
            if (!root || seen.has(root) || !root.querySelectorAll) {
                continue;
            }
            seen.add(root);
            const inputs = root.querySelectorAll('input');
            for (const input of inputs) {
                visited += 1;
                if (input.classList && input.classList.contains('search-input')) {
                    continue;
                }
                const type = (input.getAttribute('type') || 'text').toLowerCase();
                if (type === 'hidden' || type === 'checkbox' || type === 'radio' || type === 'button') {
                    continue;
                }
                const style = window.getComputedStyle(input);
                if (style.display === 'none' || style.visibility === 'hidden' || style.fontSize === '0px') {
                    continue;
                }
                return input;
            }
            const elements = root.querySelectorAll('*');
            for (const element of elements) {
                visited += 1;
                if (element.shadowRoot) {
                    queue.push(element.shadowRoot);
                }
            }
        }
        return null;
    }

    handlePeerOpen(event) {
        if (event.detail?.instanceId === this._instanceId) {
            return;
        }
        this.closeDropdown();
    }

    notifyOpened() {
        window.dispatchEvent(
            new CustomEvent(PEER_OPEN_EVENT, {
                detail: { instanceId: this._instanceId }
            })
        );
    }

    openDropdown() {
        this._wantsOpen = true;
        this.dropdownOpen = true;
        this.notifyOpened();
    }

    closeDropdown() {
        this._wantsOpen = false;
        this.dropdownOpen = false;
        this._suppressBlurClose = false;
        window.clearTimeout(this._blurTimeout);
        window.clearTimeout(this._searchTimeout);
    }

    /**
     * Keep input focus when pressing an option so blur does not close before click.
     */
    handleOptionMouseDown(event) {
        event.preventDefault();
        this._suppressBlurClose = true;
        window.clearTimeout(this._blurTimeout);
    }

    @api
    validate() {
        if (this.required && this.selections.length === 0) {
            this.errorMessage = `${this.label || 'This field'} is required.`;
            return {
                isValid: false,
                errorMessage: this.errorMessage
            };
        }
        this.errorMessage = '';
        return { isValid: true };
    }

    handleFocus() {
        this.errorMessage = '';
        window.clearTimeout(this._blurTimeout);
        this.openDropdown();
        this.scheduleSearch();
    }

    handleBlur() {
        window.clearTimeout(this._blurTimeout);
        this._blurTimeout = window.setTimeout(() => {
            if (!this._suppressBlurClose) {
                this.closeDropdown();
            }
            this._suppressBlurClose = false;
        }, BLUR_CLOSE_DELAY_MS);
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value || '';
        this.errorMessage = '';
        this.openDropdown();
        this.scheduleSearch();
    }

    handleSearchKeyDown(event) {
        if (event.key === 'Escape') {
            this.closeDropdown();
            event.target?.blur?.();
            return;
        }
        if (event.key === 'Enter' && this.typedOption) {
            event.preventDefault();
            this.addSelection(this.typedOption);
        }
    }

    scheduleSearch() {
        window.clearTimeout(this._searchTimeout);
        this._searchTimeout = window.setTimeout(() => {
            this.runSearch();
        }, SEARCH_DELAY_MS);
    }

    async runSearch() {
        if (!this.typeValue) {
            this.errorMessage = 'Picker type is not configured.';
            return;
        }
        if (!this._wantsOpen) {
            return;
        }
        const requestTerm = this.trimmedSearchTerm;
        this.isLoading = true;
        try {
            const results = await searchValues({
                typeValue: this.typeValue,
                searchTerm: requestTerm
            });
            if (!this._wantsOpen) {
                return;
            }
            const selectedIds = new Set(this.selections.map((item) => String(item.id)));
            this.options = (results || [])
                .filter((row) => row && row.id && !selectedIds.has(String(row.id)))
                .map((row) => ({
                    id: String(row.id),
                    name: row.name
                }));
            this.dropdownOpen = true;
        } catch (error) {
            if (!this._wantsOpen) {
                return;
            }
            this.options = [];
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleSelectOption(event) {
        event.preventDefault();
        event.stopPropagation();
        this._suppressBlurClose = false;

        const optionEl = event.currentTarget;
        const id = optionEl.getAttribute('data-record-id');
        const name = optionEl.getAttribute('data-record-name');
        if (!id) {
            this.errorMessage = 'Could not read the selected value. Try again.';
            return;
        }
        this.addSelection({ id: String(id), name: name || id });
    }

    handlePillRemove(event) {
        event.stopPropagation();
        const id = event.detail?.name || event.target?.name;
        this.removeSelection(id);
    }

    removeSelection(id) {
        if (!id) {
            return;
        }
        this.selections = this.selections.filter((item) => String(item.id) !== String(id));
        this.publishOutputs();
        this.searchTerm = '';
        this.closeDropdown();
        this.options = [];
    }

    addSelection(item) {
        if (!item || !item.id) {
            return;
        }
        const normalized = {
            id: String(item.id),
            name: item.name || String(item.id)
        };
        if (this.allowMultiple) {
            if (!this.selections.some((existing) => String(existing.id) === normalized.id)) {
                this.selections = [...this.selections, normalized];
            }
            this.searchTerm = '';
            this.options = [];
            this.errorMessage = '';
            this.publishOutputs();
            this.openDropdown();
            this.scheduleSearch();
            return;
        }

        this.selections = [normalized];
        this.searchTerm = '';
        this.options = [];
        this.errorMessage = '';
        this.publishOutputs();
        this.closeDropdown();
    }

    hydrateFromOutputs() {
        if (this.allowMultiple && this._selectedIds) {
            const ids = this._selectedIds.split(';').map((part) => part.trim()).filter(Boolean);
            const labels = (this._selectedLabels || '').split(';').map((part) => part.trim());
            if (ids.length) {
                this.selections = ids.map((id, index) => ({
                    id: String(id),
                    name: labels[index] || id
                }));
            }
            return;
        }
        if (this._selectedId) {
            const existingName =
                this.selections.find((item) => String(item.id) === String(this._selectedId))?.name ||
                this._selectedLabel ||
                this._selectedId;
            this.selections = [
                {
                    id: String(this._selectedId),
                    name: existingName
                }
            ];
        }
    }

    publishOutputs() {
        const ids = this.selections.map((item) => item.id);
        const labels = this.selections.map((item) => item.name);
        this._selectedId = ids[0] || '';
        this._selectedLabel = labels[0] || '';
        this._selectedIds = ids.join(';');
        this._selectedLabels = labels.join(';');

        this.dispatchEvent(new FlowAttributeChangeEvent('selectedId', this._selectedId));
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedLabel', this._selectedLabel));
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedIds', this._selectedIds));
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedLabels', this._selectedLabels));
    }

    reduceError(error) {
        if (!error) {
            return 'Unexpected error.';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }
        if (error.body && typeof error.body.message === 'string') {
            return error.body.message;
        }
        // AuraHandledException often surfaces as statusText / message only
        if (typeof error.body === 'string') {
            return error.body;
        }
        return error.message || 'Unexpected error.';
    }
}