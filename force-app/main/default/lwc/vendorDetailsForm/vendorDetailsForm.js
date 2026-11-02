import { LightningElement, api, track } from 'lwc';

/**
 * GW-4616 / GW-5865 - Shared Vendor details form for Instrument / Device Evaluation.
 * Editable: Vendor, Instructions to Vendor, STERIS Purchase Order to Vendor,
 * Vendor Notes, Vendor Reference Number, Vendor Cost.
 * Read-only: Date Shipped to Vendor (default today), Tracking Number.
 * When lockVendorHeaderFields is true (IE Vendor WO with Return Order), Vendor and
 * Instructions to Vendor are read-only; Notes, PO, Reference Number, and Cost stay editable.
 */
export default class VendorDetailsForm extends LightningElement {
    @track _vendorAccountId;
    @track instructionsToVendor = '';
    @track sterisPurchaseOrderToVendor = '';
    @track shippedToVendorDate;
    @track trackingNumber = '';
    @track vendorNotes = '';
    @track vendorReferenceNumber = '';
    @track vendorCost;
    formError = '';
    _lockVendorHeaderFields = false;

    @api
    get lockVendorHeaderFields() {
        return this._lockVendorHeaderFields === true;
    }
    set lockVendorHeaderFields(value) {
        this._lockVendorHeaderFields = value === true;
    }

    @api
    get vendorAccountId() {
        return this._vendorAccountId;
    }
    set vendorAccountId(value) {
        this._vendorAccountId = value || null;
    }

    @api
    get value() {
        return this.buildValue();
    }
    set value(raw) {
        const data = raw || {};
        this._vendorAccountId = data.vendorAccountId || null;
        this.instructionsToVendor = data.instructionsToVendor || '';
        this.sterisPurchaseOrderToVendor = data.sterisPurchaseOrderToVendor || '';
        this.shippedToVendorDate = data.shippedToVendorDate || this.todayIsoDate();
        this.trackingNumber = data.trackingNumber || '';
        this.vendorNotes = data.vendorNotes || '';
        this.vendorReferenceNumber = data.vendorReferenceNumber || '';
        this.vendorCost = data.vendorCost;
    }

    connectedCallback() {
        if (!this.shippedToVendorDate) {
            this.shippedToVendorDate = this.todayIsoDate();
        }
    }

    get vendorPickerValue() {
        return this._vendorAccountId || null;
    }

    /**
     * @returns {{valid: boolean, message?: string, value?: object}}
     */
    @api
    validate() {
        this.formError = '';
        if (!this._vendorAccountId) {
            this.formError = 'Vendor is required.';
            return { valid: false, message: this.formError };
        }
        if (!this.instructionsToVendor || !String(this.instructionsToVendor).trim()) {
            this.formError = 'Instructions to Vendor is required.';
            return { valid: false, message: this.formError };
        }
        return { valid: true, value: this.buildValue() };
    }

    get isVendorPickerDisabled() {
        return this.lockVendorHeaderFields;
    }

    get isInstructionsDisabled() {
        return this.lockVendorHeaderFields;
    }

    @api
    getValue() {
        return this.buildValue();
    }

    handleVendorChange(event) {
        this._vendorAccountId = event.detail?.recordId || null;
        this.dispatchChange();
    }

    handleInstructionsChange(event) {
        this.instructionsToVendor = this.readEventValue(event);
        this.dispatchChange();
    }

    handleSterisPurchaseOrderChange(event) {
        this.sterisPurchaseOrderToVendor = this.readEventValue(event);
        this.dispatchChange();
    }

    handleVendorNotesChange(event) {
        this.vendorNotes = this.readEventValue(event);
        this.dispatchChange();
    }

    handleVendorReferenceNumberChange(event) {
        this.vendorReferenceNumber = this.readEventValue(event);
        this.dispatchChange();
    }

    handleVendorCostChange(event) {
        const raw = this.readEventValue(event);
        if (raw === null || raw === undefined || String(raw).trim() === '') {
            this.vendorCost = null;
        } else {
            const parsed = Number(raw);
            this.vendorCost = Number.isFinite(parsed) ? parsed : null;
        }
        this.dispatchChange();
    }

    readEventValue(event) {
        return event.detail?.value ?? event.target?.value ?? '';
    }

    buildValue() {
        return {
            vendorAccountId: this._vendorAccountId || null,
            instructionsToVendor: this.instructionsToVendor || '',
            sterisPurchaseOrderToVendor: this.sterisPurchaseOrderToVendor || '',
            shippedToVendorDate: this.shippedToVendorDate || this.todayIsoDate(),
            trackingNumber: this.trackingNumber || '',
            vendorNotes: this.vendorNotes || '',
            vendorReferenceNumber: this.vendorReferenceNumber || '',
            vendorCost: this.vendorCost
        };
    }

    dispatchChange() {
        this.dispatchEvent(
            new CustomEvent('vendorchange', {
                detail: this.buildValue()
            })
        );
    }

    todayIsoDate() {
        const today = new Date();
        const month = String(today.getMonth() + 1).padStart(2, '0');
        const day = String(today.getDate()).padStart(2, '0');
        return `${today.getFullYear()}-${month}-${day}`;
    }
}