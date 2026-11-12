/**
 * @description GW-5892 / GW-6600: Field Service quote editor (Quote "Edit Quote" action).
 *              Header strip + Time (Labor/Travel), Parts and Expenses tabs. Changes stay local until Save All;
 *              lines show New / Modified badges as in the debrief.
 * @see FieldServiceQuoteController
 */
import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getQuote from '@salesforce/apex/FieldServiceQuoteController.getQuote';
import saveQuote from '@salesforce/apex/FieldServiceQuoteController.saveQuote';
import getProductInfo from '@salesforce/apex/FieldServiceQuoteController.getProductInfo';
import {
    RATE_OPTIONS,
    TRAVEL_TYPE_ACTUAL,
    buildLaborRateOptionsFromRateList,
    buildTravelTypeOptionsFromRateList,
    defaultTravelType
} from 'c/fsRateListOptions';

const LINE_TYPE = { PARTS: 'Parts', LABOR: 'Labor', TRAVEL: 'Travel', EXPENSE: 'Expense' };
const TAB = { TIME: 'time', PARTS: 'parts', EXPENSES: 'expenses' };
const TAB_LINE_TYPES = {
    [TAB.TIME]: [LINE_TYPE.LABOR, LINE_TYPE.TRAVEL],
    [TAB.PARTS]: [LINE_TYPE.PARTS],
    [TAB.EXPENSES]: [LINE_TYPE.EXPENSE]
};
const STATE = { SAVED: 'saved', NEW: 'new', MODIFIED: 'modified' };
const CALCULATE_PRICING_FLOW = 'Quote_SCR_Calculate_Pricing';
const PRICING_BADGE_CLASS = {
    Priced: 'slds-badge slds-theme_success',
    'Repricing Required': 'slds-badge slds-theme_warning',
    'Pricing Error': 'slds-badge slds-theme_error'
};

let keySequence = 0;
const nextKey = () => `new-${++keySequence}`;

export default class FieldServiceQuoteEditor extends LightningElement {
    _recordId;
    _loadedRecordId;

    /**
     * @description Screen quick actions set recordId after connectedCallback, so load when it arrives.
     */
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value && value !== this._loadedRecordId) {
            this._loadedRecordId = value;
            this.load();
        }
    }

    isLoading = true;
    isSaving = false;
    errorMessage;
    activeTab = TAB.TIME;
    editingKey;
    showPricingFlow = false;

    view;
    header = {};
    originalHeader = {};
    lines = [];
    deletedLineIds = [];

    // ---------------------------------------------------------------- data

    async load() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            this.applyView(await getQuote({ quoteId: this.recordId }));
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    applyView(view) {
        this.view = view;
        this.header = {
            status: view.header.status,
            contactId: view.header.contactId,
            shipToId: view.header.shipToId,
            ownerId: view.header.ownerId
        };
        this.originalHeader = { ...this.header };
        this.lines = (view.lines || []).map((line) => ({ ...line, key: line.id, state: STATE.SAVED }));
        this.deletedLineIds = [];
        this.editingKey = undefined;
    }

    // ---------------------------------------------------------------- header

    get h() {
        return this.view?.header || {};
    }

    get statusOptions() {
        return this.view?.statusOptions || [];
    }

    get contactFilter() {
        const accountId = this.h.accountId;
        return accountId
            ? { criteria: [{ fieldPath: 'AccountId', operator: 'eq', value: accountId }] }
            : undefined;
    }

    get userFilter() {
        return { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] };
    }

    get productFilter() {
        return { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] };
    }

    get rateListLabel() {
        const parts = [this.h.rateListName || 'No Rate List', this.h.currencyIsoCode].filter(Boolean);
        return parts.join(' · ');
    }

    get pricingLabel() {
        return this.h.pricingStatus || 'Not Priced';
    }

    get pricingBadgeClass() {
        return PRICING_BADGE_CLASS[this.h.pricingStatus] || 'slds-badge';
    }

    get quoteTotalLabel() {
        return this.h.totalPrice === null || this.h.totalPrice === undefined
            ? '—'
            : this.formatCurrency(this.h.totalPrice);
    }

    handleHeaderChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.recordId !== undefined ? event.detail.recordId : event.detail.value;
        this.header = { ...this.header, [field]: value || null };
    }

    // ---------------------------------------------------------------- tabs & lines

    get timeTabLabel() {
        return `Time (${this.countFor(TAB.TIME)})`;
    }

    get partsTabLabel() {
        return `Parts (${this.countFor(TAB.PARTS)})`;
    }

    get expensesTabLabel() {
        return `Expenses (${this.countFor(TAB.EXPENSES)})`;
    }

    countFor(tab) {
        return this.lines.filter((line) => TAB_LINE_TYPES[tab].includes(line.lineType)).length;
    }

    get timeLines() {
        return this.decorate(TAB.TIME);
    }

    get partLines() {
        return this.decorate(TAB.PARTS);
    }

    get expenseLines() {
        return this.decorate(TAB.EXPENSES);
    }

    get hasTimeLines() {
        return this.countFor(TAB.TIME) > 0;
    }

    get hasPartLines() {
        return this.countFor(TAB.PARTS) > 0;
    }

    get hasExpenseLines() {
        return this.countFor(TAB.EXPENSES) > 0;
    }

    get canOverridePrice() {
        return this.view?.canOverridePrice === true;
    }

    get laborRateOptions() {
        return buildLaborRateOptionsFromRateList(this.view?.rateList);
    }

    get travelTypeOptions() {
        return buildTravelTypeOptionsFromRateList(this.view?.rateList);
    }

    get travelTypeHelp() {
        const options = this.travelTypeOptions;
        if (!options.length) {
            return 'The Rate List has no travel amounts.';
        }
        const offered = options
            .map((o) => (o.value === TRAVEL_TYPE_ACTUAL ? o.label : `${o.label} (${this.formatCurrency(o.amount)})`))
            .join(', ');
        return `Options from the Rate List: ${offered}. Zones without an amount are not offered.`;
    }

    get expenseTypeOptions() {
        return this.view?.expenseTypeOptions || [];
    }

    get timeLineTypeOptions() {
        return [
            { label: 'Labor', value: LINE_TYPE.LABOR },
            { label: 'Travel', value: LINE_TYPE.TRAVEL }
        ];
    }

    decorate(tab) {
        return this.lines
            .filter((line) => TAB_LINE_TYPES[tab].includes(line.lineType))
            .map((line) => {
                const isLabor = line.lineType === LINE_TYPE.LABOR;
                const isTravel = line.lineType === LINE_TYPE.TRAVEL;
                const isZoneTravel = isTravel && line.travelType && line.travelType !== TRAVEL_TYPE_ACTUAL;
                const total = this.computeTotal(line);
                return {
                    ...line,
                    isEditing: line.key === this.editingKey,
                    isNew: line.state === STATE.NEW,
                    isModified: line.state === STATE.MODIFIED,
                    isLabor,
                    isTravel,
                    isZoneTravel,
                    isSaved: line.state !== STATE.NEW,
                    laborVariant: isLabor ? 'brand' : 'neutral',
                    travelVariant: isTravel ? 'brand' : 'neutral',
                    rateOptions: isLabor ? this.laborRateOptions : RATE_OPTIONS,
                    rateDisabled: isZoneTravel,
                    ratePlaceholder: isZoneTravel ? 'Not used for zone travel' : 'Select a rate',
                    quantityDisabled: isZoneTravel,
                    quantityLabel: isLabor || (isTravel && !isZoneTravel) ? 'Quantity (hours)' : 'Quantity',
                    unitPriceDisabled: !(this.canOverridePrice || line.lineType === LINE_TYPE.EXPENSE),
                    title: this.lineTitle(line),
                    subtitle: [line.description, total === null ? null : this.formatCurrency(total)]
                        .filter(Boolean)
                        .join(' · '),
                    computedTotal: total,
                    cardClass: `slds-box slds-box_x-small slds-m-bottom_x-small line-card line-${line.state}`
                };
            });
    }

    lineTitle(line) {
        const hours = line.quantity ? `${Number(line.quantity).toFixed(1)} h` : null;
        switch (line.lineType) {
            case LINE_TYPE.LABOR:
                return ['Labor', line.rate, hours].filter(Boolean).join(' · ');
            case LINE_TYPE.TRAVEL:
                return line.travelType === TRAVEL_TYPE_ACTUAL
                    ? ['Travel', line.travelType, line.rate, hours].filter(Boolean).join(' · ')
                    : ['Travel', line.travelType].filter(Boolean).join(' · ');
            case LINE_TYPE.EXPENSE:
                return ['Expense', line.expenseType, line.quantity ? `Qty ${line.quantity}` : null]
                    .filter(Boolean)
                    .join(' · ');
            default:
                return [line.productName || 'New part', line.productCode, line.quantity ? `Qty ${line.quantity}` : null]
                    .filter(Boolean)
                    .join(' · ');
        }
    }

    computeTotal(line) {
        if (line.unitPrice === null || line.unitPrice === undefined || !line.quantity) {
            return line.totalPrice ?? null;
        }
        const discount = Number(line.discount || 0);
        return Number(line.quantity) * Number(line.unitPrice) * (1 - discount / 100);
    }

    handleTabActive(event) {
        this.activeTab = event.target.value;
        this.editingKey = undefined;
    }

    handleAddTimeLine() {
        const rateList = this.view?.rateList;
        this.addLine({
            lineType: LINE_TYPE.LABOR,
            quantity: 1,
            rate: this.laborRateOptions[0]?.value || null,
            travelType: defaultTravelType(rateList) || null
        });
    }

    handleAddPart() {
        this.addLine({ lineType: LINE_TYPE.PARTS, quantity: 1 });
    }

    handleAddExpense() {
        const product = this.view?.expenseProduct;
        if (!product) {
            this.toast('Expense part missing', 'The expense part has no price in this quote price book.', 'error');
            return;
        }
        this.addLine({
            lineType: LINE_TYPE.EXPENSE,
            quantity: 1,
            product2Id: product.product2Id,
            productName: product.productName,
            productCode: product.productCode,
            listPrice: product.listPrice,
            unitPrice: product.listPrice
        });
    }

    addLine(values) {
        const key = nextKey();
        this.lines = [
            ...this.lines,
            {
                id: null,
                key,
                state: STATE.NEW,
                discount: null,
                description: null,
                isManualPrice: false,
                ...values
            }
        ];
        this.editingKey = key;
    }

    handleEditLine(event) {
        const key = event.currentTarget.dataset.key;
        this.editingKey = this.editingKey === key ? undefined : key;
    }

    handleDoneEditing() {
        this.editingKey = undefined;
    }

    handleDeleteLine(event) {
        const key = event.currentTarget.dataset.key;
        const line = this.lines.find((l) => l.key === key);
        if (!line) {
            return;
        }
        if (line.id) {
            this.deletedLineIds = [...this.deletedLineIds, line.id];
        }
        this.lines = this.lines.filter((l) => l.key !== key);
        if (this.editingKey === key) {
            this.editingKey = undefined;
        }
    }

    handleLineTypeChange(event) {
        const key = event.currentTarget.dataset.key;
        const lineType = event.currentTarget.dataset.value;
        this.updateLine(key, (line) => {
            const next = { ...line, lineType };
            if (lineType === LINE_TYPE.LABOR) {
                next.rate = this.laborRateOptions.some((o) => o.value === line.rate)
                    ? line.rate
                    : this.laborRateOptions[0]?.value || null;
            } else {
                next.travelType = line.travelType || defaultTravelType(this.view?.rateList) || null;
                next.rate = next.travelType === TRAVEL_TYPE_ACTUAL ? line.rate || 'Standard' : null;
                if (next.travelType !== TRAVEL_TYPE_ACTUAL) {
                    next.quantity = 1;
                }
            }
            return next;
        });
    }

    handleLineFieldChange(event) {
        const key = event.target.dataset.key;
        const field = event.target.dataset.field;
        let value = event.target.type === 'checkbox' ? event.target.checked : event.detail.value;
        if (['quantity', 'unitPrice', 'discount'].includes(field)) {
            value = value === '' || value === null || value === undefined ? null : Number(value);
        }
        this.updateLine(key, (line) => {
            const next = { ...line, [field]: value };
            if (field === 'travelType') {
                if (value !== TRAVEL_TYPE_ACTUAL) {
                    next.quantity = 1;
                    next.rate = null;
                } else if (!next.rate) {
                    next.rate = 'Standard';
                }
            }
            if (field === 'unitPrice' && this.canOverridePrice && line.lineType !== LINE_TYPE.EXPENSE) {
                next.isManualPrice = true;
            }
            return next;
        });
    }

    async handleProductChange(event) {
        const key = event.target.dataset.key;
        const productId = event.detail.recordId;
        if (!productId) {
            this.updateLine(key, (line) => ({
                ...line,
                product2Id: null,
                productName: null,
                productCode: null,
                listPrice: null,
                unitPrice: null
            }));
            return;
        }
        try {
            const product = await getProductInfo({ quoteId: this.recordId, productId });
            this.updateLine(key, (line) => ({
                ...line,
                product2Id: product.product2Id,
                productName: product.productName,
                productCode: product.productCode,
                listPrice: product.listPrice,
                unitPrice: product.listPrice
            }));
        } catch (error) {
            this.toast('Product not available', this.reduceError(error), 'error');
        }
    }

    updateLine(key, updater) {
        this.lines = this.lines.map((line) => {
            if (line.key !== key) {
                return line;
            }
            const next = updater(line);
            if (next.state === STATE.SAVED) {
                next.state = STATE.MODIFIED;
            }
            return next;
        });
    }

    // ---------------------------------------------------------------- footer

    get headerChangeCount() {
        return Object.keys(this.header).filter((field) => this.header[field] !== this.originalHeader[field]).length;
    }

    get unsavedChangeCount() {
        const lineChanges = this.lines.filter((line) => line.state !== STATE.SAVED).length;
        return lineChanges + this.deletedLineIds.length + this.headerChangeCount;
    }

    get unsavedChangesLabel() {
        const count = this.unsavedChangeCount;
        if (!count) {
            return 'No unsaved changes';
        }
        return count === 1 ? '1 unsaved change' : `${count} unsaved changes`;
    }

    get saveDisabled() {
        return this.isSaving || this.isLoading || this.unsavedChangeCount === 0;
    }

    get calculateDisabled() {
        return this.isSaving || this.isLoading || this.unsavedChangeCount > 0;
    }

    get calculateTitle() {
        return this.unsavedChangeCount > 0 ? 'Save All before calculating pricing' : 'Calculate Pricing';
    }

    get pricingFlowInputs() {
        return [{ name: 'recordId', type: 'SObject', value: { Id: this.recordId } }];
    }

    get pricingFlowName() {
        return CALCULATE_PRICING_FLOW;
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleCalculatePricing() {
        this.showPricingFlow = true;
    }

    handleClosePricingFlow() {
        this.showPricingFlow = false;
    }

    async handlePricingFlowStatus(event) {
        if (event.detail.status === 'FINISHED' || event.detail.status === 'FINISHED_SCREEN') {
            this.showPricingFlow = false;
            await this.load();
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        }
    }

    async handleSaveAll() {
        const invalid = this.validateLines();
        if (invalid) {
            this.toast('Fix the highlighted line', invalid, 'error');
            return;
        }
        this.isSaving = true;
        try {
            const payload = {
                ...this.header,
                lines: this.lines
                    .filter((line) => line.state !== STATE.SAVED)
                    .map((line) => ({
                        id: line.id,
                        lineType: line.lineType,
                        product2Id: line.product2Id,
                        quantity: line.quantity,
                        rate: line.rate,
                        travelType: line.travelType,
                        expenseType: line.expenseType,
                        unitPrice: line.unitPrice,
                        discount: line.discount,
                        description: line.description,
                        isManualPrice: line.isManualPrice
                    })),
                deletedLineIds: this.deletedLineIds
            };
            const view = await saveQuote({ quoteId: this.recordId, payloadJson: JSON.stringify(payload) });
            this.applyView(view);
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            this.toast('Quote saved', 'All changes were saved.', 'success');
        } catch (error) {
            this.toast('Quote not saved', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    /**
     * @description Client-side checks mirroring FieldServiceQuoteController.validateLine.
     * @return {string|undefined} First error, opening the offending line
     */
    validateLines() {
        for (const line of this.lines) {
            if (line.state === STATE.SAVED) {
                continue;
            }
            let message;
            if (!line.quantity || line.quantity <= 0) {
                message = 'Quantity must be greater than zero.';
            } else if (line.lineType === LINE_TYPE.LABOR && !line.rate) {
                message = 'Rate is required for Labor lines.';
            } else if (line.lineType === LINE_TYPE.TRAVEL && !line.travelType) {
                message = 'Travel Type is required for Travel lines.';
            } else if (line.lineType === LINE_TYPE.TRAVEL && line.travelType === TRAVEL_TYPE_ACTUAL && !line.rate) {
                message = 'Rate is required for Actual Travel.';
            } else if (line.lineType === LINE_TYPE.PARTS && !line.id && !line.product2Id) {
                message = 'Select a product for each Parts line.';
            } else if (line.lineType === LINE_TYPE.EXPENSE && !line.expenseType) {
                message = 'Expense Type is required for Expense lines.';
            }
            if (message) {
                this.activeTab = Object.keys(TAB_LINE_TYPES).find((tab) => TAB_LINE_TYPES[tab].includes(line.lineType));
                this.editingKey = line.key;
                return message;
            }
        }
        return undefined;
    }

    // ---------------------------------------------------------------- utils

    formatCurrency(value) {
        if (value === null || value === undefined) {
            return '';
        }
        try {
            return new Intl.NumberFormat(undefined, {
                style: 'currency',
                currency: this.h.currencyIsoCode || 'USD'
            }).format(value);
        } catch (e) {
            return String(value);
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }
}