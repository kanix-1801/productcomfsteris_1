import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { FlowNavigationBackEvent, FlowNavigationNextEvent } from 'lightning/flowSupport';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import searchProducts from '@salesforce/apex/FreeGoodTaskController.searchProducts';
import createTaskProducts from '@salesforce/apex/FreeGoodTaskController.createTaskProducts';
import FREE_GOODS_TASK_PRODUCT from '@salesforce/schema/Free_Goods_Task_Product__c';
import CONSUMPTION_FREQUENCY_FIELD from '@salesforce/schema/Free_Goods_Task_Product__c.ConsumptionFrequency__c';
import STATUS_FIELD from '@salesforce/schema/Free_Goods_Task_Product__c.Status__c';
import CONFIDENCE_LEVEL_FIELD from '@salesforce/schema/Free_Goods_Task_Product__c.ConfidenceLevel__c';

const NUMERIC_LINE_FIELDS = ['quantity', 'salesPrice'];

/**
 * @author PWC Developer
 * @date 2026/08/17
 *
 * @description
 * GC-3230 - Add Products to the Task screen for the Task - Create - FreeGoodsDetailScreen flow.
 *
 * Runs as the final step after the flow has created the Free Goods Task. The rep searches the active
 * product catalogue, selects one or more products, enters Quantity plus optional line fields, and on
 * save the component creates one Free Goods Task Product record per product, linked to the Task through
 * the TaskId__c field and to the Account through the Account__c lookup. The same Apex call flags the
 * originating Opportunity when the flow was launched from one. The component then navigates to the new
 * Task and finishes the flow, which closes the quick action modal.
 *
 * The flow screen hides its own footer, so this component owns the Back and Save and Finish buttons.
 */
export default class FreeGoodTaskQuickAction extends NavigationMixin(LightningElement) {
    // 18 digit Id of the Task created earlier in the flow.
    @api taskId;

    // Account the free goods are being delivered to.
    @api accountId;

    // Originating Opportunity. Blank when the flow was launched from an Account.
    @api opportunityId;

    // Loading indicator and saved flag. isSaved also blocks a second submit after a successful save.
    @track isLoading = false;
    isSaved = false;

    // Validation and save failures are shown in a banner at the top of the component rather than a
    // toast, because a toast auto dismisses before the rep can scroll to the field that failed.
    @track errorMessage = '';

    // Product search results and full client-side dataset.
    @track productSearchKey = '';
    @track productData = [];
    @track allProductData = [];
    @track hasSearchRun = false;

    // Datatable selected product IDs for the current page and the master selection across all pages.
    @track selectedProductIds = [];
    @track selectedProductRecords = [];

    // Client-side pagination state for the product search results.
    @track productPageNumber = 1;
    @track productPageSize = 25;
    @track productTotalPages = 1;
    @track productTotalRecords = 0;

    // Search results stay in the DOM when collapsed so datatable selection is not lost.
    isSearchResultsCollapsed = false;

    // Record type used to load restricted picklist values for the selected-product line fields.
    recordTypeId;

    consumptionFrequencyOptions = [];
    statusOptions = [];
    confidenceLevelOptions = [];

    @wire(getObjectInfo, { objectApiName: FREE_GOODS_TASK_PRODUCT })
    wiredObjectInfo({ data }) {
        if (data) {
            this.recordTypeId = data.defaultRecordTypeId;
        }
    }

    @wire(getPicklistValues, { recordTypeId: '$recordTypeId', fieldApiName: CONSUMPTION_FREQUENCY_FIELD })
    wiredConsumptionFrequency({ data }) {
        this.consumptionFrequencyOptions = this.mapPicklistOptions(data);
    }

    @wire(getPicklistValues, { recordTypeId: '$recordTypeId', fieldApiName: STATUS_FIELD })
    wiredStatus({ data }) {
        this.statusOptions = this.mapPicklistOptions(data);
    }

    @wire(getPicklistValues, { recordTypeId: '$recordTypeId', fieldApiName: CONFIDENCE_LEVEL_FIELD })
    wiredConfidenceLevel({ data }) {
        this.confidenceLevelOptions = this.mapPicklistOptions(data);
    }

    // Page size options dropdown.
    pageSizeOptions = [
        { label: '25', value: '25' },
        { label: '50', value: '50' },
        { label: '100', value: '100' },
        { label: '150', value: '150' }
    ];

    // Product search results table columns.
    productColumns = [
        { label: 'Product Name', fieldName: 'productName', wrapText: true },
        { label: 'Product Code', fieldName: 'productCode' },
        { label: 'Product Family', fieldName: 'productFamily' },
        { label: 'Description', fieldName: 'productDescription', wrapText: true }
    ];

    get hasProductResults() { return this.productData.length > 0; }
    get hasSelectedProducts() { return this.selectedProductRecords.length > 0; }
    get selectedProductCount() { return this.selectedProductRecords.length; }
    get showNoResults() { return this.hasSearchRun && this.productTotalRecords === 0; }
    get hasError() { return !!this.errorMessage; }

    get productPageSizeValue() { return String(this.productPageSize); }
    get disablePreviousProductPage() { return this.productPageNumber <= 1; }
    get disableNextProductPage() { return this.productPageNumber >= this.productTotalPages; }

    // Nothing can be saved until at least one product is selected, and the save cannot be repeated
    // once it has succeeded or while it is in flight.
    get isSaveDisabled() {
        return this.selectedProductRecords.length === 0 || this.isLoading || this.isSaved;
    }

    get isBackDisabled() { return this.isLoading || this.isSaved; }

    get selectedProductsHeading() {
        return 'Selected Products (' + this.selectedProductCount + ')';
    }

    get searchResultsToggleIcon() {
        return this.isSearchResultsCollapsed ? 'utility:chevrondown' : 'utility:chevronup';
    }

    get searchResultsToggleLabel() {
        return this.isSearchResultsCollapsed ? 'Show search results' : 'Hide search results';
    }

    get searchResultsBodyClass() {
        return this.isSearchResultsCollapsed ? 'slds-hide' : '';
    }

    handleToggleSearchResults() {
        this.isSearchResultsCollapsed = !this.isSearchResultsCollapsed;
    }

    handleProductSearchChange(event) { this.productSearchKey = event.target.value; }

    handleProductSearchEnter(event) {
        if (event.key === 'Enter') {
            this.handleSearchProducts();
        }
    }

    /**
     * Searches the active product catalogue by product name or product code. The full result set is
     * held in memory and paginated client side.
     */
    async handleSearchProducts() {
        try {
            this.isLoading = true;
            this.clearError();
            const result = await searchProducts({ searchKey: this.productSearchKey });

            this.allProductData = result || [];
            this.productTotalRecords = this.allProductData.length;
            this.productTotalPages = Math.max(Math.ceil(this.productTotalRecords / this.productPageSize), 1);
            this.productPageNumber = 1;
            this.hasSearchRun = true;
            this.isSearchResultsCollapsed = false;

            this.refreshProductPage();
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Slices the current page out of the full result set and re-applies the master selection.
     */
    refreshProductPage() {
        const startIndex = (this.productPageNumber - 1) * this.productPageSize;
        const endIndex = Math.min(startIndex + this.productPageSize, this.productTotalRecords);
        this.productData = this.allProductData.slice(startIndex, endIndex);
        this.selectedProductIds = this.selectedProductRecords.map(record => record.productId);
    }

    /**
     * Merges the current page selection into the master list so selections survive pagination
     * and repeated searches.
     */
    handleProductSelection(event) {
        const selectedRows = event.detail.selectedRows;
        const visibleProductIds = this.productData.map(row => row.productId);
        const selectedVisibleProductIds = selectedRows.map(row => row.productId);

        this.selectedProductRecords = this.selectedProductRecords.filter(record => {
            const isVisible = visibleProductIds.includes(record.productId);
            const isStillSelected = selectedVisibleProductIds.includes(record.productId);
            return !isVisible || isStillSelected;
        });

        selectedRows.forEach(row => {
            const alreadyExists = this.selectedProductRecords.some(
                record => record.productId === row.productId
            );

            if (alreadyExists) {
                return;
            }

            // Rebuild from the Apex result rather than the datatable row so the selection is always
            // a plain object with the fields the save payload needs.
            const sourceRecord =
                this.allProductData.find(product => product.productId === row.productId) || row;

            this.selectedProductRecords = [
                ...this.selectedProductRecords,
                this.buildSelectedProductRecord(sourceRecord)
            ];
        });

        this.selectedProductIds = this.selectedProductRecords.map(record => record.productId);
    }

    /**
     * Captures a line field entered against a selected product.
     */
    handleLineFieldChange(event) {
        const productId = event.currentTarget.dataset.productid;
        const fieldName = event.currentTarget.dataset.field;
        const rawValue = event.detail && event.detail.value !== undefined
            ? event.detail.value
            : event.target.value;

        this.selectedProductRecords = this.selectedProductRecords.map(record =>
            record.productId === productId
                ? { ...record, [fieldName]: this.normaliseLineFieldValue(fieldName, rawValue) }
                : record
        );
    }

    /**
     * Removes a product from the selection and clears it from the datatable.
     */
    handleRemoveSelectedProduct(event) {
        const productIdToRemove = event.currentTarget.dataset.productid;
        this.selectedProductRecords = this.selectedProductRecords.filter(
            record => record.productId !== productIdToRemove
        );
        this.selectedProductIds = this.selectedProductRecords.map(record => record.productId);
    }

    // Client-side pagination handlers.
    handlePreviousProductPage() {
        if (this.productPageNumber > 1) {
            this.productPageNumber--;
            this.refreshProductPage();
        }
    }

    handleNextProductPage() {
        if (this.productPageNumber < this.productTotalPages) {
            this.productPageNumber++;
            this.refreshProductPage();
        }
    }

    handleProductPageSizeChange(event) {
        this.productPageSize = Number(event.detail.value);
        this.productTotalPages = Math.max(Math.ceil(this.productTotalRecords / this.productPageSize), 1);
        this.productPageNumber = 1;
        this.refreshProductPage();
    }

    /**
     * Returns the rep to the Free Goods detail screen so the Task fields can be corrected. The Task
     * has already been created by this point, so Back only reopens the form, it does not undo it.
     */
    handleBack() {
        this.dispatchEvent(new FlowNavigationBackEvent());
    }

    /**
     * Final action on the flow. Validates the quantities, creates the Free Goods Task Product records
     * and flags the originating Opportunity, then reports both outcomes in a single toast, navigates
     * to the new Task and advances the flow so the quick action modal closes.
     */
    async handleSave() {
        if (this.isSaveDisabled || !this.validateSelectedProducts()) {
            return;
        }

        const productInputs = this.selectedProductRecords
            .filter(record => record.productId)
            .map(record => ({
                productId: String(record.productId),
                lineDescription: record.lineDescription || null,
                quantity: Number(record.quantity),
                salesPrice: record.salesPrice,
                consumptionFrequency: record.consumptionFrequency || null,
                status: record.status || null,
                confidenceLevel: record.confidenceLevel || null,
                expectedShipDate: record.expectedShipDate || null,
                contractValue: record.contractValue || null,
                productDetails: record.productDetails || null,
                comments: record.comments || null
            }));

        if (productInputs.length !== this.selectedProductRecords.length) {
            this.setError('Some selected products could not be resolved. Search again and reselect them.');
            return;
        }

        try {
            this.isLoading = true;
            this.clearError();

            const createdCount = await createTaskProducts({
                taskId: this.taskId,
                accountId: this.accountId,
                opportunityId: this.opportunityId,
                productInputsJson: JSON.stringify(productInputs)
            });

            this.isSaved = true;

            this.showToast(
                'Free Goods Task created',
                'The Task was created successfully and ' + createdCount +
                    ' product(s) were added. Opening the Task now.',
                'success'
            );

            this.navigateToTask();

            // NEXT rather than FINISH: the Add Products screen still connects to Set Output Task Id,
            // so the runtime only offers BACK and NEXT. That assignment is the last element, so
            // advancing ends the flow and closes the modal.
            this.dispatchEvent(new FlowNavigationNextEvent());
        } catch (error) {
            this.showError(error);
            this.isLoading = false;
        }
    }

    /**
     * Opens the newly created Task in the current tab. Navigating from the component rather than the
     * flow keeps the rep in the same tab and dismisses the quick action modal.
     */
    navigateToTask() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.taskId,
                objectApiName: 'Task',
                actionName: 'view'
            }
        });
    }

    /**
     * Confirms at least one product is selected and every selected product has a quantity
     * above zero and a consumption frequency. Line Description stays optional.
     *
     * @returns {boolean} True when the product selection is complete.
     */
    validateSelectedProducts() {
        if (this.selectedProductRecords.length === 0) {
            this.setError('Select at least one product before saving.');
            return false;
        }

        const quantityInputs = [...this.template.querySelectorAll('[data-validate="quantity"]')];
        const isValid = quantityInputs.reduce(
            (validSoFar, input) => input.reportValidity() && validSoFar,
            true
        );

        const hasMissingQuantity = this.selectedProductRecords.some(
            record => !record.quantity || record.quantity <= 0
        );

        if (!isValid || hasMissingQuantity) {
            this.setError('Enter a quantity greater than zero for every selected product.');
            return false;
        }

        const frequencyInputs = [...this.template.querySelectorAll('[data-validate="consumptionFrequency"]')];
        const frequenciesAreValid = frequencyInputs.reduce(
            (validSoFar, input) => input.reportValidity() && validSoFar,
            true
        );

        const hasMissingFrequency = this.selectedProductRecords.some(
            record => !record.consumptionFrequency
        );

        if (!frequenciesAreValid || hasMissingFrequency) {
            this.setError('Select a Consumption Frequency for every selected product.');
            return false;
        }

        this.clearError();
        return true;
    }

    // Show any toast message
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // Surface a failure in the banner at the top of the component.
    setError(message) {
        this.errorMessage = message;
    }

    clearError() {
        this.errorMessage = '';
    }

    // Show any error message
    showError(error) {
        let message = 'Unexpected error occurred.';

        if (error && error.body && error.body.message) {
            message = error.body.message;
        }

        this.setError(message);
    }

    /**
     * Builds the in-memory row for a newly selected product, including optional line fields.
     *
     * @param {object} sourceRecord Product search result used to seed the row.
     * @returns {object} Selected product row for the Add Products screen.
     */
    buildSelectedProductRecord(sourceRecord) {
        return {
            productId: sourceRecord.productId,
            productName: sourceRecord.productName,
            productCode: sourceRecord.productCode,
            lineDescription: '',
            quantity: null,
            salesPrice: null,
            consumptionFrequency: null,
            status: null,
            confidenceLevel: null,
            expectedShipDate: null,
            contractValue: '',
            productDetails: '',
            comments: ''
        };
    }

    /**
     * Converts picklist metadata into combobox options.
     *
     * @param {object} picklistData uiObjectInfoApi picklist payload.
     * @returns {Array<{label: string, value: string}>} Combobox options.
     */
    mapPicklistOptions(picklistData) {
        if (!picklistData || !picklistData.values) {
            return [];
        }

        return picklistData.values.map(entry => ({
            label: entry.label,
            value: entry.value
        }));
    }

    /**
     * Normalises a line-field value before it is stored on the selected product row.
     *
     * @param {string} fieldName Property name on the selected product row.
     * @param {*} rawValue Value raised by the input.
     * @returns {*} Value to persist on the row.
     */
    normaliseLineFieldValue(fieldName, rawValue) {
        if (rawValue === '' || rawValue === undefined) {
            return NUMERIC_LINE_FIELDS.includes(fieldName) ? null : (rawValue === '' ? '' : null);
        }

        if (NUMERIC_LINE_FIELDS.includes(fieldName)) {
            return Number(rawValue);
        }

        return rawValue;
    }
}