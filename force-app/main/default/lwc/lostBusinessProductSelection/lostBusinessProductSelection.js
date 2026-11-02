import { LightningElement, api, track } from 'lwc';
import { FlowNavigationBackEvent, FlowNavigationNextEvent } from 'lightning/flowSupport';
import getOriginatingProducts from '@salesforce/apex/LostBusinessProductController.getOriginatingProducts';
import getConsumptionFrequencyOptions from '@salesforce/apex/LostBusinessProductController.getConsumptionFrequencyOptions';
import searchProducts from '@salesforce/apex/LostBusinessProductController.searchProducts';
import createLostBusinessProducts from '@salesforce/apex/LostBusinessProductController.createLostBusinessProducts';

const NUMERIC_LINE_FIELDS = ['quantity', 'unitPrice'];

/**
 * @author PWC Developer
 * @date 2026/10/30
 *
 * @description
 * GC-3574 - Product selection screen for Opportunity - Create - LostBusinessDetailScreen.
 *
 * When the originating opportunity has products, those products are shown selected. The rep can
 * clear and reselect them, and can change Quantity and Consumption Frequency. When it has no
 * products, the screen searches the active catalogue the same way Log Free Goods does.
 * Save creates Opportunity Products on the Lost Business opportunity only.
 *
 * The flow screen hides its own footer, so this component owns Back and Submit.
 */
export default class LostBusinessProductSelection extends LightningElement {
    // Lost Business opportunity created earlier in the flow.
    @api lostBusinessOpportunityId;

    // Originating opportunity whose products are offered for copy.
    @api originatingOpportunityId;

    @track isLoading = true;
    @track loadFailed = false;
    userHasChangedCopySelection = false;
    @track errorMessage = '';
    isSaved = false;

    // True when the originating opportunity has no products and the catalogue search is shown.
    @track isCatalogMode = false;

    @track copyableRows = [];
    @track unavailableRows = [];
    @track selectedCopyRecords = [];
    @track selectedSourceLineIds = [];

    @track productSearchKey = '';
    @track productData = [];
    @track allProductData = [];
    @track hasSearchRun = false;
    @track selectedProductIds = [];
    @track selectedProductRecords = [];
    @track productPageNumber = 1;
    @track productPageSize = 25;
    @track productTotalPages = 1;
    @track productTotalRecords = 0;
    isSearchResultsCollapsed = false;
    isOriginatingProductsCollapsed = false;
    isSelectedProductsCollapsed = false;

    consumptionFrequencyOptions = [];

    pageSizeOptions = [
        { label: '25', value: '25' },
        { label: '50', value: '50' },
        { label: '100', value: '100' },
        { label: '150', value: '150' }
    ];

    copyColumns = [
        { label: 'Product Name', fieldName: 'productName', wrapText: true },
        { label: 'Product / SKU', fieldName: 'productSku', wrapText: true },
        { label: 'Quantity', fieldName: 'quantity', type: 'number' },
        { label: 'Consumption Frequency', fieldName: 'consumptionFrequency', wrapText: true },
        {
            label: 'Unit Price',
            fieldName: 'unitPrice',
            type: 'number',
            typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 }
        }
    ];

    productColumns = [
        { label: 'Product Name', fieldName: 'productName', wrapText: true },
        { label: 'Product / SKU', fieldName: 'productCode', wrapText: true }
    ];

    connectedCallback() {
        this.loadFrequencyOptions();
        this.loadOriginatingProducts();
    }

    /**
     * Loads Consumption Frequency from Apex. The catalogue screen has no originating lines
     * to copy values from, so the dropdown depends on this list.
     */
    async loadFrequencyOptions() {
        try {
            const options = await getConsumptionFrequencyOptions();
            this.syncFrequencyOptions(options || []);
        } catch (error) {
            this.showError(error);
        }
    }

    get hasError() { return !!this.errorMessage; }
    get showCopyMode() { return !this.isLoading && !this.loadFailed && !this.isCatalogMode; }
    get showCatalogMode() { return !this.isLoading && !this.loadFailed && this.isCatalogMode; }
    get hasCopyableRows() { return this.copyableRows.length > 0; }
    get hasUnavailableRows() { return this.unavailableRows.length > 0; }
    get hasSelectedCopyRecords() { return this.selectedCopyRecords.length > 0; }
    get maxCopySelection() { return Math.max(this.copyableRows.length, 1); }
    get hasProductResults() { return this.productData.length > 0; }
    get hasSelectedProducts() { return this.selectedProductRecords.length > 0; }
    get showNoResults() { return this.hasSearchRun && this.productTotalRecords === 0; }
    get productPageSizeValue() { return String(this.productPageSize); }
    get disablePreviousProductPage() { return this.productPageNumber <= 1; }
    get disableNextProductPage() { return this.productPageNumber >= this.productTotalPages; }
    get isSaveDisabled() { return this.isLoading || this.isSaved || this.loadFailed; }
    get isBackDisabled() { return this.isLoading || this.isSaved; }

    get selectedProductsHeading() {
        const count = this.isCatalogMode
            ? this.selectedProductRecords.length
            : this.selectedCopyRecords.length;
        return count === 1 ? '1 product selected' : count + ' products selected';
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

    get originatingToggleIcon() {
        return this.isOriginatingProductsCollapsed ? 'utility:chevrondown' : 'utility:chevronup';
    }

    get originatingToggleLabel() {
        return this.isOriginatingProductsCollapsed
            ? 'Show products from the originating opportunity'
            : 'Hide products from the originating opportunity';
    }

    get originatingBodyClass() {
        return this.isOriginatingProductsCollapsed ? 'slds-hide' : '';
    }

    get selectedProductsToggleIcon() {
        return this.isSelectedProductsCollapsed ? 'utility:chevrondown' : 'utility:chevronup';
    }

    get selectedProductsToggleLabel() {
        return this.isSelectedProductsCollapsed ? 'Show selected products' : 'Hide selected products';
    }

    get selectedProductsBodyClass() {
        const baseClass = 'slds-p-horizontal_medium slds-p-bottom_medium selected-products-scroll';
        return this.isSelectedProductsCollapsed ? baseClass + ' slds-hide' : baseClass;
    }

    /**
     * Loads originating products and chooses copy mode or catalogue mode.
     */
    async loadOriginatingProducts() {
        try {
            this.isLoading = true;
            this.loadFailed = false;
            this.clearError();

            const rows = await getOriginatingProducts({
                originatingOpportunityId: this.originatingOpportunityId
            });
            const productRows = rows || [];
            this.isCatalogMode = productRows.length === 0;
            this.copyableRows = productRows.filter(row => row.copyable);
            this.unavailableRows = productRows.filter(row => !row.copyable);
            this.syncFrequencyOptions(this.consumptionFrequencyOptions);
            this.selectedCopyRecords = this.copyableRows.map(row => this.buildCopyRecord(row));
            this.selectedSourceLineIds = this.selectedCopyRecords.map(record => record.sourceLineItemId);
        } catch (error) {
            this.loadFailed = true;
            this.isCatalogMode = false;
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleCopySelection(event) {
        const selectedRows = event.detail.selectedRows || [];
        // The datatable can raise an empty selection while it applies the initial selected rows.
        // Ignore that first empty event so the products stay selected. A later clear is kept.
        if (!this.userHasChangedCopySelection
            && selectedRows.length === 0
            && this.copyableRows.length > 0) {
            this.userHasChangedCopySelection = true;
            return;
        }
        this.userHasChangedCopySelection = true;

        const previousById = new Map(
            this.selectedCopyRecords.map(record => [record.sourceLineItemId, record])
        );

        this.selectedCopyRecords = selectedRows.map(row => {
            return previousById.get(row.sourceLineItemId) || this.buildCopyRecord(row);
        });
        this.selectedSourceLineIds = this.selectedCopyRecords.map(record => record.sourceLineItemId);
    }

    handleCopyFieldChange(event) {
        this.applyLineFieldChange(event, 'selectedCopyRecords');
    }

    handleProductSearchChange(event) { this.productSearchKey = event.target.value; }

    handleProductSearchEnter(event) {
        if (event.key === 'Enter') {
            this.handleSearchProducts();
        }
    }

    handleToggleSearchResults() {
        this.isSearchResultsCollapsed = !this.isSearchResultsCollapsed;
    }

    handleToggleOriginatingProducts() {
        this.isOriginatingProductsCollapsed = !this.isOriginatingProductsCollapsed;
    }

    handleToggleSelectedProducts() {
        this.isSelectedProductsCollapsed = !this.isSelectedProductsCollapsed;
    }

    /**
     * Searches the active catalogue. The full result set is held in memory and paginated client side.
     */
    async handleSearchProducts() {
        try {
            this.isLoading = true;
            this.clearError();
            const result = await searchProducts({
                searchKey: this.productSearchKey,
                lostBusinessOpportunityId: this.lostBusinessOpportunityId
            });

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

    refreshProductPage() {
        const startIndex = (this.productPageNumber - 1) * this.productPageSize;
        const endIndex = Math.min(startIndex + this.productPageSize, this.productTotalRecords);
        this.productData = this.allProductData.slice(startIndex, endIndex);
        this.selectedProductIds = this.selectedProductRecords.map(record => record.productId);
    }

    /**
     * Merges the current page selection into the master list so selections survive pagination.
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

            const sourceRecord =
                this.allProductData.find(product => product.productId === row.productId) || row;
            this.selectedProductRecords = [
                ...this.selectedProductRecords,
                this.buildCatalogRecord(sourceRecord)
            ];
        });

        this.selectedProductIds = this.selectedProductRecords.map(record => record.productId);
    }

    handleCatalogFieldChange(event) {
        this.applyLineFieldChange(event, 'selectedProductRecords');
    }

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
     * Returns to the Lost Business detail screen. The opportunity has already been created.
     */
    handleBack() {
        this.dispatchEvent(new FlowNavigationBackEvent());
    }

    /**
     * Creates the selected Opportunity Products, then lets the flow show the success toast and
     * open the new opportunity. Finishing with nothing selected is allowed.
     */
    async handleSave() {
        if (this.isSaveDisabled || !this.validateSelectedProducts()) {
            return;
        }

        const productInputs = this.isCatalogMode
            ? this.selectedProductRecords.map(record => ({
                productId: String(record.productId),
                quantity: Number(record.quantity),
                unitPrice: record.unitPrice,
                consumptionFrequency: record.consumptionFrequency || null
            }))
            : this.selectedCopyRecords.map(record => ({
                sourceLineItemId: String(record.sourceLineItemId),
                quantity: Number(record.quantity),
                consumptionFrequency: record.consumptionFrequency || null
            }));

        try {
            this.isLoading = true;
            this.clearError();

            if (productInputs.length > 0) {
                await createLostBusinessProducts({
                    lostBusinessOpportunityId: this.lostBusinessOpportunityId,
                    originatingOpportunityId: this.originatingOpportunityId,
                    productInputsJson: JSON.stringify(productInputs)
                });
            }

            this.isSaved = true;
            this.dispatchEvent(new FlowNavigationNextEvent());
        } catch (error) {
            this.showError(error);
            this.isLoading = false;
        }
    }

    /**
     * Confirms every selected product has a quantity above zero. An empty selection can be saved.
     *
     * @returns {boolean} True when the selection is ready to save.
     */
    validateSelectedProducts() {
        const selectedRecords = this.isCatalogMode ? this.selectedProductRecords : this.selectedCopyRecords;

        if (selectedRecords.length === 0) {
            this.clearError();
            return true;
        }

        const quantityInputs = [...this.template.querySelectorAll('[data-validate="quantity"]')];
        const isValid = quantityInputs.reduce(
            (validSoFar, input) => input.reportValidity() && validSoFar,
            true
        );
        const hasMissingQuantity = selectedRecords.some(
            record => !record.quantity || record.quantity <= 0
        );

        if (!isValid || hasMissingQuantity) {
            this.setError('Enter a quantity greater than zero for every selected product.');
            return false;
        }

        this.clearError();
        return true;
    }

    applyLineFieldChange(event, collectionName) {
        const recordId = event.currentTarget.dataset.productid;
        const fieldName = event.currentTarget.dataset.field;
        const rawValue = event.detail && event.detail.value !== undefined
            ? event.detail.value
            : event.target.value;
        const idField = collectionName === 'selectedCopyRecords' ? 'sourceLineItemId' : 'productId';

        this[collectionName] = this[collectionName].map(record =>
            record[idField] === recordId
                ? this.withFrequencyChoices({
                    ...record,
                    [fieldName]: this.normaliseLineFieldValue(fieldName, rawValue)
                })
                : record
        );
    }

    buildCopyRecord(sourceRecord) {
        return this.withFrequencyChoices({
            sourceLineItemId: sourceRecord.sourceLineItemId,
            productName: sourceRecord.productName,
            productSku: sourceRecord.productSku,
            quantity: sourceRecord.quantity,
            consumptionFrequency: sourceRecord.consumptionFrequency,
            unitPrice: sourceRecord.unitPrice
        });
    }

    buildCatalogRecord(sourceRecord) {
        return this.withFrequencyChoices({
            productId: sourceRecord.productId,
            productName: sourceRecord.productName,
            productCode: sourceRecord.productCode,
            quantity: null,
            unitPrice: sourceRecord.unitPrice,
            consumptionFrequency: null
        });
    }

    /**
     * Keeps the org picklist and any frequency already stored on a copied product.
     */
    syncFrequencyOptions(picklistOptions) {
        const optionByValue = new Map();

        (picklistOptions || []).forEach(option => {
            if (option && option.value) {
                optionByValue.set(option.value, { label: option.label || option.value, value: option.value });
            }
        });

        this.copyableRows.forEach(row => {
            if (row.consumptionFrequency && !optionByValue.has(row.consumptionFrequency)) {
                optionByValue.set(row.consumptionFrequency, {
                    label: row.consumptionFrequency,
                    value: row.consumptionFrequency
                });
            }
        });

        this.consumptionFrequencyOptions = [...optionByValue.values()];
        this.selectedCopyRecords = this.selectedCopyRecords.map(record => this.withFrequencyChoices(record));
        this.selectedProductRecords = this.selectedProductRecords.map(record => this.withFrequencyChoices(record));
    }

    withFrequencyChoices(record) {
        const currentValue = record.consumptionFrequency || '';
        const frequencyChoices = [
            {
                key: 'blank',
                label: 'Select an Option',
                value: '',
                selected: currentValue === ''
            },
            ...this.consumptionFrequencyOptions.map(option => ({
                key: option.value,
                label: option.label,
                value: option.value,
                selected: option.value === currentValue
            }))
        ];

        return { ...record, frequencyChoices };
    }

    normaliseLineFieldValue(fieldName, rawValue) {
        if (rawValue === '' || rawValue === undefined) {
            return NUMERIC_LINE_FIELDS.includes(fieldName) ? null : (rawValue === '' ? '' : null);
        }

        if (NUMERIC_LINE_FIELDS.includes(fieldName)) {
            return Number(rawValue);
        }

        return rawValue;
    }

    setError(message) {
        this.errorMessage = message;
    }

    clearError() {
        this.errorMessage = '';
    }

    showError(error) {
        let message = 'Unexpected error occurred.';

        if (error && error.body && error.body.message) {
            message = error.body.message;
        }

        this.setError(message);
    }
}