/**
 * GW-2891 - Divide Instruments LWC: scan a parent Work Order, capture bins, and reconcile children.
 */
import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import REPAIR_CATEGORY_FIELD from '@salesforce/schema/WorkOrder.RepairCategory__c';
import initializeDivide from '@salesforce/apex/DivideInstrumentsController.initializeDivide';
import completeDivide from '@salesforce/apex/DivideInstrumentsController.completeDivide';

const MODE_SCAN = 'scan';
const MODE_WORKSPACE = 'workspace';
const BROWSER_TAB_LABEL = 'Divide Instruments';
const QTY_MISMATCH_MESSAGE =
    'Your total quantity does not match the quantity received.  ' +
    'Please make the necessary corrections before proceeding';
const CATEGORY_REQUIRED_MESSAGE = 'Repair Category is required.';
const QTY_RANGE_MESSAGE = 'Qty must be a whole number between 1 and 99.';
const TURN_TIME_RANGE_MESSAGE = 'Turn Time must be a whole number between 1 and 99.';
const SCAN_FIELD_LABEL = 'Work Order Id / Number';
const SCAN_FIELD_PLACEHOLDER = 'Scan or enter Work Order Id / Number';

export default class DivideInstruments extends LightningElement {
    mode = MODE_SCAN;
    workOrderIdInput = '';
    isLoading = false;
    errorMessage = '';
    workspaceError = '';
    workspace;
    instrumentsRecordTypeId;
    @track bins = [];
    quantityReceived;
    repairCategoryOptions = [];
    _binLeaveTimeoutId;

    @wire(getPicklistValues, {
        recordTypeId: '$instrumentsRecordTypeId',
        fieldApiName: REPAIR_CATEGORY_FIELD
    })
    /**
     * GW-2891 - Loads Repair Category picklist values for the Instruments record type.
     */
    wiredRepairCategories({ data, error }) {
        if (data && data.values) {
            this.repairCategoryOptions = data.values.map((entry) => ({
                label: entry.label,
                value: entry.value
            }));
        } else if (error) {
            this.repairCategoryOptions = [];
        }
    }

    /**
     * GW-2891 - Sets the browser/OS window title on load.
     */
    connectedCallback() {
        this.updateBrowserTitle();
    }

    /**
     * Sets the OS/browser window title (e.g. "00000927 | Divide Instruments").
     * @param {string} [workOrderNumber] Work Order number when divide workspace is open
     */
    updateBrowserTitle(workOrderNumber) {
        const wo = (workOrderNumber || '').toString().trim();
        document.title = wo ? `${wo} | ${BROWSER_TAB_LABEL}` : BROWSER_TAB_LABEL;
    }

    /**
     * GW-2891 - Clears the bin blur timeout when the component is destroyed.
     */
    disconnectedCallback() {
        window.clearTimeout(this._binLeaveTimeoutId);
    }

    /**
     * GW-2891 - True while the scan field is shown.
     */
    get isScanMode() {
        return this.mode === MODE_SCAN;
    }

    /**
     * GW-2891 - True while bin capture is shown.
     */
    get isWorkspaceMode() {
        return this.mode === MODE_WORKSPACE;
    }

    /**
     * GW-4750 - True when the Work Order has a Continuous Improvement Opportunity.
     */
    get showCioIndicator() {
        return this.workspace?.continuousImprovementOpportunity === true;
    }

    /**
     * GW-2891 - True while an Apex call is in progress.
     */
    get isBusy() {
        return this.isLoading;
    }

    /**
     * GW-2891 - Root CSS class for scan vs workspace layout.
     */
    get rootClass() {
        return this.isWorkspaceMode
            ? 'divide-root divide-root_workspace'
            : 'divide-root divide-root_scan slds-p-around_medium';
    }

    /**
     * GW-2891 - Parent Work Order Id from the loaded workspace.
     */
    get workOrderId() {
        return this.workspace?.workOrderId;
    }

    /**
     * GW-2891 - Estimate Required value shown on the workspace.
     */
    get estimateRequiredDisplay() {
        return this.workspace?.estimateRequired || '';
    }

    /**
     * GW-2891 - Repair Warranty value shown on the workspace.
     */
    get repairWarrantyDisplay() {
        return this.workspace?.repairWarranty || '';
    }

    /**
     * GW-2891 - Customer PO value shown on the workspace.
     */
    get customerPoDisplay() {
        return this.workspace?.customerPo || '';
    }

    /**
     * GW-2891 - Quantity Received input value, or blank when unset.
     */
    get quantityReceivedInputValue() {
        if (this.quantityReceived === null || this.quantityReceived === undefined) {
            return '';
        }
        return String(this.quantityReceived);
    }

    /**
     * GW-2891 - Scan field label (Work Order Id / Number).
     */
    get scanFieldLabel() {
        return SCAN_FIELD_LABEL;
    }

    /**
     * GW-2891 - Scan field placeholder text.
     */
    get scanFieldPlaceholder() {
        return SCAN_FIELD_PLACEHOLDER;
    }

    /**
     * GW-2891 - Stores the scan field value as the user types.
     * @param {CustomEvent} event valuechange from repairCenterScanInput
     */
    handleScanValueChange(event) {
        this.workOrderIdInput = event.detail.value;
        this.errorMessage = '';
    }

    /**
     * GW-2891 - Starts Divide Instruments from the scan Continue action.
     * @param {CustomEvent} event continue from repairCenterScanInput
     */
    handleScanContinue(event) {
        const value = event.detail?.value || this.workOrderIdInput;
        this.startDivide(value);
    }

    /**
     * GW-2891 - Calls Apex initializeDivide and loads bins for the scanned Work Order.
     * @param {string} workOrderInput Work Order Id or Number
     */
    async startDivide(workOrderInput) {
        if (this.isLoading) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const result = await initializeDivide({ workOrderInput });
            this.workspace = result;
            this.instrumentsRecordTypeId = result.instrumentsRecordTypeId;
            this.quantityReceived = result.quantityReceived;
            this.bins = this.buildBinsFromWorkspace(result.existingBins);
            this.mode = MODE_WORKSPACE;
            this.updateBrowserTitle(result.workOrderNumber);
            if (!this.bins.length) {
                this.addBin();
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * GW-2891 - Updates Quantity Received from the workspace input.
     * @param {Event} event lightning-input change
     */
    handleQuantityReceivedChange(event) {
        const raw = event.target.value;
        this.quantityReceived = raw === '' || raw === null ? null : Number(raw);
        this.workspaceError = '';
    }

    /**
     * GW-2891 - Maps existing child Work Orders from Apex into bin rows.
     * @param {Array} existingBins Bin drafts from initializeDivide
     * @returns {Array} Bin rows for the repeater
     */
    buildBinsFromWorkspace(existingBins) {
        if (!existingBins?.length) {
            return [];
        }
        return existingBins.map((bin, index) => ({
            key: bin.childWorkOrderId || `${Date.now()}-${index}`,
            childWorkOrderId: bin.childWorkOrderId || null,
            repairCategory: bin.repairCategory || '',
            quantity: bin.quantity ?? null,
            turnTime: bin.turnTime ?? null,
            showErrors: false
        }));
    }

    /**
     * GW-2891 - Prepends an empty bin row after validating existing rows
     * so the new fields stay near the + Add button.
     */
    addBin() {
        if (this.bins.length) {
            this.showErrorsAndReportAllBins();
        }
        const nextKey = `${Date.now()}-${this.bins.length}`;
        this.bins = [
            {
                key: nextKey,
                childWorkOrderId: null,
                repairCategory: '',
                quantity: null,
                turnTime: null,
                showErrors: false
            },
            ...this.bins
        ];
    }

    /**
     * GW-2891 - Removes the bin row for the clicked remove button.
     * @param {Event} event click on remove
     */
    handleRemoveBin(event) {
        const key = event.currentTarget.dataset.key;
        this.bins = this.bins.filter((bin) => bin.key !== key);
    }

    /**
     * GW-2891 - Updates Repair Category on a bin row.
     * @param {CustomEvent} event combobox change
     */
    handleBinCategoryChange(event) {
        const key = event.currentTarget.dataset.key;
        this.updateBin(key, 'repairCategory', event.detail.value);
        this.reportBinValidityIfShown(key);
    }

    /**
     * GW-2891 - Updates Qty on a bin row.
     * @param {Event} event input change
     */
    handleBinQtyChange(event) {
        const key = event.currentTarget.dataset.key;
        this.updateBin(key, 'quantity', this.toNumber(event.target.value));
        this.reportBinValidityIfShown(key);
    }

    /**
     * GW-2891 - Updates Turn Time on a bin row.
     * @param {Event} event input change
     */
    handleBinTurnTimeChange(event) {
        const key = event.currentTarget.dataset.key;
        this.updateBin(key, 'turnTime', this.toNumber(event.target.value));
        this.reportBinValidityIfShown(key);
    }

    /**
     * GW-2891 - Shows required-field errors after the user leaves a bin row.
     * @param {FocusEvent} event focusout on the bin
     */
    handleBinFocusOut(event) {
        const binElement = event.currentTarget;
        const key = binElement.dataset.key;
        const nextTarget = event.relatedTarget;
        if (nextTarget && binElement.contains(nextTarget)) {
            return;
        }
        window.clearTimeout(this._binLeaveTimeoutId);
        this._binLeaveTimeoutId = window.setTimeout(() => {
            if (this.isFocusInsideBin(binElement)) {
                return;
            }
            this.setBinShowErrors(key, true);
            this.reportBinValidity(key);
        }, 250);
    }

    /**
     * GW-2891 - True when keyboard focus is still inside the given bin row.
     * @param {Element} binElement Bin wrapper element
     * @returns {boolean}
     */
    isFocusInsideBin(binElement) {
        if (!binElement) {
            return false;
        }
        const active = this.template.activeElement;
        return Boolean(active && binElement.contains(active));
    }

    /**
     * GW-2891 - Toggles inline error display for one bin row.
     * @param {string} key Bin row key
     * @param {boolean} showErrors Whether to show field errors
     */
    setBinShowErrors(key, showErrors) {
        this.bins = this.bins.map((bin) => {
            if (bin.key !== key) {
                return bin;
            }
            return { ...bin, showErrors };
        });
    }

    /**
     * GW-2891 - Re-reports native validity only after the bin has already shown errors.
     * @param {string} key Bin row key
     */
    reportBinValidityIfShown(key) {
        const bin = this.bins.find((item) => item.key === key);
        if (!bin?.showErrors) {
            return;
        }
        Promise.resolve().then(() => {
            this.reportBinValidity(key);
        });
    }

    /**
     * GW-2891 - Sets custom validity on Repair Category, Qty, and Turn Time for one bin.
     * @param {string} key Bin row key
     */
    reportBinValidity(key) {
        if (!key) {
            return;
        }
        const bin = this.bins.find((item) => item.key === key);
        if (!bin) {
            return;
        }
        const categoryInput = this.queryBinField(key, 'repairCategory');
        const qtyInput = this.queryBinField(key, 'quantity');
        const turnTimeInput = this.queryBinField(key, 'turnTime');
        this.applyFieldValidity(
            categoryInput,
            bin.showErrors && !bin.repairCategory ? CATEGORY_REQUIRED_MESSAGE : ''
        );
        this.applyFieldValidity(
            qtyInput,
            bin.showErrors && !this.isWholeNumberInRange(bin.quantity) ? QTY_RANGE_MESSAGE : ''
        );
        this.applyFieldValidity(
            turnTimeInput,
            bin.showErrors && !this.isWholeNumberInRange(bin.turnTime) ? TURN_TIME_RANGE_MESSAGE : ''
        );
    }

    /**
     * GW-2891 - Finds a bin input by row key and field name.
     * @param {string} key Bin row key
     * @param {string} field Field data attribute
     * @returns {Element|null}
     */
    queryBinField(key, field) {
        return this.template.querySelector(`[data-key="${CSS.escape(key)}"][data-field="${field}"]`);
    }

    /**
     * GW-2891 - Applies a custom validity message and reports it on the input.
     * @param {Element} element Input element
     * @param {string} message Validity message, or blank to clear
     */
    applyFieldValidity(element, message) {
        if (!element || typeof element.setCustomValidity !== 'function') {
            return;
        }
        element.setCustomValidity(message);
        element.reportValidity();
    }

    /**
     * GW-2891 - Marks every bin to show errors and reports validity.
     */
    showErrorsAndReportAllBins() {
        this.bins = this.bins.map((bin) => ({ ...bin, showErrors: true }));
        this.bins.forEach((bin) => {
            this.reportBinValidity(bin.key);
        });
    }

    /**
     * GW-2891 - Updates one field on a bin row.
     * @param {string} key Bin row key
     * @param {string} field Field name
     * @param {*} value New value
     */
    updateBin(key, field, value) {
        this.bins = this.bins.map((bin) => {
            if (bin.key !== key) {
                return bin;
            }
            return { ...bin, [field]: value };
        });
        this.workspaceError = '';
    }

    /**
     * GW-2891 - Converts an input string to a number, or null when blank.
     * @param {string} value Raw input
     * @returns {number|null}
     */
    toNumber(value) {
        if (value === '' || value === null || value === undefined) {
            return null;
        }
        return Number(value);
    }

    /**
     * GW-2891 - Returns the first bin validation message, or null when all bins are valid.
     * @returns {string|null}
     */
    validateBins() {
        if (!this.bins.length) {
            return 'Add at least one bin before completing.';
        }
        for (let index = 0; index < this.bins.length; index += 1) {
            const bin = this.bins[index];
            const binLabel = `Bin ${index + 1}`;
            if (!bin.repairCategory) {
                return `${binLabel}: ${CATEGORY_REQUIRED_MESSAGE}`;
            }
            if (!this.isWholeNumberInRange(bin.quantity)) {
                return `${binLabel}: ${QTY_RANGE_MESSAGE}`;
            }
            if (!this.isWholeNumberInRange(bin.turnTime)) {
                return `${binLabel}: ${TURN_TIME_RANGE_MESSAGE}`;
            }
        }
        return null;
    }

    /**
     * GW-2891 - True when value is a whole number from 1 to 99.
     * @param {*} value Qty or Turn Time
     * @returns {boolean}
     */
    isWholeNumberInRange(value) {
        if (value === null || value === undefined || Number.isNaN(value)) {
            return false;
        }
        if (!Number.isInteger(value)) {
            return false;
        }
        return value >= 1 && value <= 99;
    }

    /**
     * GW-2891 - Validates bins and Quantity Received, then calls Apex completeDivide.
     */
    async handleComplete() {
        if (this.isLoading || !this.workspace?.workOrderId) {
            return;
        }
        this.showErrorsAndReportAllBins();
        const fieldError = this.validateBins();
        if (fieldError) {
            this.workspaceError = fieldError;
            return;
        }
        const binTotal = this.bins.reduce((sum, bin) => sum + (bin.quantity || 0), 0);
        if (binTotal !== Number(this.quantityReceived)) {
            this.workspaceError = QTY_MISMATCH_MESSAGE;
            return;
        }
        this.isLoading = true;
        this.workspaceError = '';
        try {
            const result = await completeDivide({
                workOrderId: this.workspace.workOrderId,
                quantityReceived: this.quantityReceived,
                bins: this.bins.map((bin) => ({
                    childWorkOrderId: bin.childWorkOrderId || null,
                    repairCategory: bin.repairCategory,
                    quantity: bin.quantity,
                    turnTime: bin.turnTime
                }))
            });
            this.workspace = result;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Divide Instruments',
                    message: result.labelsWarning || 'Child Work Orders were created.',
                    variant: result.labelsWarning ? 'warning' : 'success'
                })
            );
            this.mode = MODE_SCAN;
            this.workOrderIdInput = '';
            this.bins = [];
            this.updateBrowserTitle();
        } catch (error) {
            this.workspaceError = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * GW-2891 - Extracts a user-visible message from an Apex / LWC error.
     * @param {*} error Aura or JS error
     * @returns {string}
     */
    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body) && error.body.length && error.body[0].message) {
            return error.body[0].message;
        }
        return error?.message || 'An unexpected error occurred.';
    }
}