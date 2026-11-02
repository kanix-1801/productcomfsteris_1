/** 
 * @description ES Service Product Configurator: Asset lookup that searches Name, Serial Number, and PFCL. 
 */
import { LightningElement, api } from 'lwc';
import searchAssets from '@salesforce/apex/EsServiceProductConfigController.searchAssets';

const MIN_CHARS = 2;
const DEBOUNCE_MS = 300;

export default class EsServiceProductConfigAssetLookup extends LightningElement {
    @api label = 'Asset';
    @api required = false;
    @api accountId;
    @api selectedId;
    @api selectedName;

    searchText = '';
    results = [];
    isOpen = false;
    isSearching = false;
    activeIndex = -1;
    searchError;

    debounceTimer;
    requestCounter = 0;

    get hasSelection() {
        return !!this.selectedId;
    }

    get comboboxClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click${this.isOpen ? ' slds-is-open' : ''}`;
    }

    get ariaExpanded() {
        return this.isOpen ? 'true' : 'false';
    }

    get options() {
        return this.results.map((r, i) => ({
            ...r,
            optionId: `asset-option-${i}`,
            isActive: i === this.activeIndex ? 'true' : 'false',
            cssClass: `slds-media slds-listbox__option slds-listbox__option_entity slds-listbox__option_has-meta${
                i === this.activeIndex ? ' slds-has-focus' : ''
            }`,
            meta: [r.serialNumber, r.pfcl].filter(Boolean).join(' · ')
        }));
    }

    get activeOptionId() {
        return this.activeIndex >= 0 ? `asset-option-${this.activeIndex}` : null;
    }

    get showHint() {
        return this.searchText.trim().length < MIN_CHARS;
    }

    get showNoResults() {
        return !this.showHint && !this.isSearching && !this.searchError && this.results.length === 0;
    }

    get hasResults() {
        return this.results.length > 0;
    }

    // ---------- Search ----------

    handleInput(event) {
        this.searchText = event.target.value;
        this.activeIndex = -1;
        this.searchError = null;
        this.isOpen = true;
        clearTimeout(this.debounceTimer);
        if (this.searchText.trim().length < MIN_CHARS) {
            this.results = [];
            this.isSearching = false;
            return;
        }
        this.isSearching = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.debounceTimer = setTimeout(() => this.runSearch(this.searchText), DEBOUNCE_MS);
    }

    async runSearch(text) {
        const requestId = ++this.requestCounter;
        try {
            const rows = await searchAssets({ accountId: this.accountId, searchText: text });
            if (requestId !== this.requestCounter) {
                return; // a newer search has started
            }
            this.results = rows || [];
        } catch (e) {
            if (requestId !== this.requestCounter) {
                return;
            }
            this.results = [];
            this.searchError = e?.body?.message || 'Search failed.';
        } finally {
            if (requestId === this.requestCounter) {
                this.isSearching = false;
            }
        }
    }

    handleFocus() {
        if (this.searchText) {
            this.isOpen = true;
        }
    }

    handleBlur() {
        this.isOpen = false;
        this.activeIndex = -1;
    }

    // ---------- Keyboard ----------

    handleKeyDown(event) {
        const count = this.results.length;
        switch (event.key) {
            case 'ArrowDown':
                event.preventDefault();
                this.isOpen = true;
                if (count) {
                    this.activeIndex = (this.activeIndex + 1) % count;
                }
                break;
            case 'ArrowUp':
                event.preventDefault();
                if (count) {
                    this.activeIndex = this.activeIndex <= 0 ? count - 1 : this.activeIndex - 1;
                }
                break;
            case 'Enter':
                if (this.isOpen && this.activeIndex >= 0) {
                    event.preventDefault();
                    this.select(this.results[this.activeIndex]);
                }
                break;
            case 'Escape':
                if (this.isOpen) {
                    event.preventDefault();
                    event.stopPropagation(); // keep the modal open
                    this.isOpen = false;
                    this.activeIndex = -1;
                }
                break;
            default:
        }
    }

    // ---------- Selection ----------

    // mousedown (not click) so the choice registers before the input loses focus.
    handleOptionMouseDown(event) {
        event.preventDefault();
        const id = event.currentTarget.dataset.id;
        const option = this.results.find((r) => r.id === id);
        if (option) {
            this.select(option);
        }
    }

    select(option) {
        this.isOpen = false;
        this.activeIndex = -1;
        this.searchText = '';
        this.results = [];
        this.dispatchEvent(
            new CustomEvent('select', { detail: { assetId: option.id, assetName: option.name } })
        );
    }

    handleClear() {
        this.dispatchEvent(new CustomEvent('select', { detail: { assetId: null, assetName: null } }));
        setTimeout(() => this.template.querySelector('input[data-id="search"]')?.focus(), 0);
    }

    disconnectedCallback() {
        clearTimeout(this.debounceTimer);
    }
}