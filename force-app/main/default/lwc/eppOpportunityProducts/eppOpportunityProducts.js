import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchProducts from '@salesforce/apex/EPPProductController.searchProducts';
import getOpportunityProducts from '@salesforce/apex/EPPProductController.getOpportunityProducts';
import createOpportunityProducts from '@salesforce/apex/EPPProductController.createOpportunityProducts';
import getDealerContext from '@salesforce/apex/DealerOpportunityProductController.getDealerContext';
import searchDealerProducts from '@salesforce/apex/DealerOpportunityProductController.searchProducts';
import getDealerProducts from '@salesforce/apex/DealerOpportunityProductController.getProducts';
import createDealerProducts from '@salesforce/apex/DealerOpportunityProductController.createProducts';
import deleteDealerProduct from '@salesforce/apex/DealerOpportunityProductController.deleteProduct';

/**
 * GC-3431 - Reusable EPP product section. App Builder places this component once
 * for Capital and once for Consumables by setting productMode.
 * GC-3047 - Product Mode Dealer uses DealerOpportunityProductController only.
 */
export default class EppOpportunityProducts extends NavigationMixin(LightningElement) {
    @api recordId;
    @api productMode = 'Capital';

    @track existingProducts = [];
    @track searchResults = [];
    @track selectedProducts = [];
    @track errorMessage = '';

    searchKey = '';
    dealerContext;
    isModalOpen = false;
    dealerEntryStep = false;
    isDetailModalOpen = false;
    isDetailEdit = false;
    selectedLineId;
    selectedProductId;
    selectedProductName;
    selectedProductUrl;
    isLoading = false;

    frequencyOptions = [
        { label: 'Weekly', value: 'Weekly' },
        { label: 'Monthly', value: 'Monthly' },
        { label: 'Annual', value: 'Annual' },
        { label: 'One Time', value: 'One Time' }
    ];

    eppProductColumns = [
        { label: 'Product Name', fieldName: 'productName', wrapText: true },
        { label: 'Product Code', fieldName: 'productCode' },
        { label: 'Product Family', fieldName: 'productFamily' },
        { label: 'Business Unit', fieldName: 'businessUnit' },
        { label: 'List Price', fieldName: 'listPrice', type: 'currency' }
    ];

    dealerStatusOptions = [
        { label: 'Open', value: 'Open' },
        { label: 'Closed Won', value: 'Closed Won' },
        { label: 'Closed Lost', value: 'Closed Lost' },
        { label: 'Closed Cancelled', value: 'Closed Cancelled' },
        { label: 'Closed Did Not Participate/Bid', value: 'Closed Did Not Participate/Bid' }
    ];

    dealerConfidenceOptions = [
        { label: 'Pipeline', value: 'Pipeline' },
        { label: 'Budget', value: 'Budget' },
        { label: 'Upside', value: 'Upside' },
        { label: 'Make It', value: 'Make It' },
        { label: 'Won', value: 'Won' },
        { label: 'Lost', value: 'Lost' }
    ];

    connectedCallback() {
        this.loadExistingProducts();
    }

    get isConsumable() {
        return this.productMode === 'Consumable';
    }

    get isDealer() {
        return this.productMode === 'Dealer';
    }

    get isCapital() {
        return !this.isConsumable && !this.isDealer;
    }

    get productColumns() {
        if (!this.isDealer) {
            return this.eppProductColumns;
        }
        return [
            { label: 'Product Name', fieldName: 'productName', wrapText: true },
            { label: 'Product Code', fieldName: 'productCode' },
            { label: 'Sales Category Code', fieldName: 'salesCategoryCode' },
            { label: 'Product Family', fieldName: 'productFamily' },
            { label: 'Business Unit', fieldName: 'businessUnit' },
            {
                label: 'List Price',
                fieldName: 'listPrice',
                type: 'currency',
                typeAttributes: {
                    currencyCode: { fieldName: 'currencyCode' },
                    minimumFractionDigits: 2
                }
            },
            {
                label: 'Recently Added',
                fieldName: 'recentlyAdded',
                type: 'boolean',
                initialWidth: 150
            }
        ];
    }

    get sectionTitle() {
        if (this.isDealer) {
            return 'Products';
        }
        return this.isConsumable ? 'EPP Consumables' : 'EPP Capital Equipment';
    }

    get addButtonLabel() {
        if (this.isDealer) {
            return 'Add Products';
        }
        return this.isConsumable ? 'Add Consumables' : 'Add Capital Equipment';
    }

    get modalTitle() {
        if (this.isDealer && this.dealerEntryStep) {
            return 'Enter Unit Price';
        }
        return this.addButtonLabel;
    }

    get hideProductSearch() {
        return this.isDealer && this.dealerEntryStep;
    }

    get showSelectedProducts() {
        if (!this.hasSelectedProducts) {
            return false;
        }
        return !this.isDealer || this.dealerEntryStep;
    }

    get showNoSearchResults() {
        return !this.hasSearchResults && !this.isLoading;
    }

    get showCardSpinner() {
        return this.isLoading && !this.isModalOpen && !this.isDetailModalOpen;
    }

    get dealerTotalPriceLabel() {
        return `Total (${this.opportunityCurrencyCode})`;
    }

    get opportunityCurrencyCode() {
        return (this.dealerContext && this.dealerContext.currencyCode) || 'USD';
    }

    get dealerCurrencyOptions() {
        const currencies = (this.dealerContext && this.dealerContext.currencies) || [];
        if (currencies.length) {
            return currencies.map((rate) => ({ label: rate.isoCode, value: rate.isoCode }));
        }
        return [{ label: this.opportunityCurrencyCode, value: this.opportunityCurrencyCode }];
    }

    get defaultDealerCurrency() {
        const usd = this.dealerCurrencyOptions.find((option) => option.value === 'USD');
        return usd ? usd.value : this.opportunityCurrencyCode;
    }

    get showDealerNext() {
        return this.isDealer && !this.dealerEntryStep;
    }

    get showAddProducts() {
        return !this.showDealerNext;
    }

    get isNextDisabled() {
        return !this.hasSelectedProducts || this.isLoading;
    }

    get detailModalTitle() {
        const action = this.isDetailEdit ? 'Edit' : 'View';
        if (this.isDealer) {
            return `${action} Product`;
        }
        const productType = this.isConsumable ? 'EPP Consumable' : 'EPP Capital Equipment';
        return `${action} ${productType}`;
    }

    get hasExistingProducts() {
        return this.existingProducts.length > 0;
    }

    get hasSearchResults() {
        return this.searchResults.length > 0;
    }

    get hasSelectedProducts() {
        return this.selectedProducts.length > 0;
    }

    get selectedProductIds() {
        return this.selectedProducts.map(product => product.pricebookEntryId);
    }

    get isSaveDisabled() {
        return !this.hasSelectedProducts || this.isLoading;
    }

    get existingColumns() {
        const shared = [
            {
                label: 'Product',
                fieldName: 'productUrl',
                type: 'url',
                wrapText: true,
                initialWidth: 240,
                typeAttributes: {
                    label: { fieldName: 'productName' },
                    target: '_self'
                }
            },
            { label: 'Item Number', fieldName: 'productCode', initialWidth: 130 },
            { label: 'Product Family', fieldName: 'productFamily', initialWidth: 150 },
            { label: 'Business Unit', fieldName: 'businessUnit', initialWidth: 140 },
            { label: 'Quantity', fieldName: 'quantity', type: 'number', initialWidth: 110 }
        ];

        const rowActionColumn = {
            type: 'action',
            typeAttributes: {
                rowActions: [
                    { label: 'View details', name: 'view' },
                    { label: 'Edit', name: 'edit' }
                ]
            }
        };

        if (this.isDealer) {
            return [
                { label: 'Product', fieldName: 'productName', wrapText: true, initialWidth: 220 },
                { label: 'Item Number', fieldName: 'productCode', initialWidth: 130 },
                { label: 'Quantity', fieldName: 'quantity', type: 'number', initialWidth: 110 },
                { label: 'Unit Price', fieldName: 'unitPrice', type: 'number', initialWidth: 120, typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 } },
                { label: 'Currency', fieldName: 'currencyCode', initialWidth: 110 },
                { label: 'Total Price', fieldName: 'totalPrice', type: 'number', initialWidth: 130, typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 } },
                { label: 'Status', fieldName: 'status', initialWidth: 160 },
                { label: 'Forecast Confidence', fieldName: 'confidenceLevel', initialWidth: 170 },
                this.dateColumn('Expected Order Date', 'expectedOrderDate'),
                this.dateColumn('Expected Ship Date', 'expectedShipDate'),
                { label: 'Comments', fieldName: 'comments', wrapText: true, initialWidth: 180 },
                {
                    type: 'action',
                    typeAttributes: {
                        rowActions: [
                            { label: 'View details', name: 'view' },
                            { label: 'Edit', name: 'edit' },
                            { label: 'Delete', name: 'delete' }
                        ]
                    }
                }
            ];
        }

        if (this.isConsumable) {
            return [
                ...shared,
                { label: 'Frequency', fieldName: 'consumptionFrequency', initialWidth: 120 },
                { label: 'Standard / Oracle Price', fieldName: 'unitPrice', type: 'currency', initialWidth: 170 },
                {
                    label: 'Elevated / EPP Pricing',
                    fieldName: 'elevatedEPPPricingApplicable',
                    type: 'boolean',
                    initialWidth: 165
                },
                { label: 'EPP Price', fieldName: 'eppPrice', type: 'currency', initialWidth: 130 },
                this.dateColumn('Commitment Start Date', 'commitmentStartDate'),
                this.dateColumn('Commitment End Date', 'commitmentEndDate'),
                {
                    label: 'Annual Committed Revenue',
                    fieldName: 'annualCommittedRevenue',
                    type: 'currency',
                    initialWidth: 190
                },
                {
                    label: 'Contract-Term Revenue',
                    fieldName: 'contractTermRevenue',
                    type: 'currency',
                    initialWidth: 180
                },
                rowActionColumn
            ];
        }

        return [
            ...shared,
            this.dateColumn('Placement Start Date', 'placementStartDate'),
            this.dateColumn('Placement End Date', 'placementEndDate'),
            rowActionColumn
        ];
    }

    dateColumn(label, fieldName) {
        return {
            label,
            fieldName,
            type: 'date',
            initialWidth: 170,
            typeAttributes: {
                day: 'numeric',
                month: 'short',
                year: 'numeric',
                timeZone: 'UTC'
            }
        };
    }

    async loadExistingProducts() {
        if (!this.recordId) {
            return;
        }

        if (this.isDealer) {
            try {
                await this.loadDealerProducts();
            } catch (error) {
                this.showError(error);
            }
            return;
        }

        try {
            this.isLoading = true;
            const lines = await getOpportunityProducts({
                opportunityId: this.recordId,
                isConsumable: this.isConsumable
            });
            this.existingProducts = lines.map(line => ({
                ...line,
                productUrl: `/lightning/r/Product2/${line.productId}/view`
            }));
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleRowAction(event) {
        const actionName = event.detail.action.name;
        if (this.isDealer && actionName === 'delete') {
            await this.removeDealerLine(event.detail.row.opportunityLineItemId);
            return;
        }
        const row = event.detail.row;
        this.selectedLineId = row.opportunityLineItemId;
        this.selectedProductId = row.productId;
        this.selectedProductName = row.productName;
        this.selectedProductUrl = this.isDealer && row.productId
            ? await this.productPageUrl(row.productId)
            : null;
        this.isDetailEdit = actionName === 'edit';
        this.isDetailModalOpen = true;
    }

    closeDetailModal() {
        if (!this.isLoading) {
            this.isDetailModalOpen = false;
            this.selectedLineId = null;
            this.selectedProductId = null;
            this.selectedProductName = null;
            this.selectedProductUrl = null;
        }
    }

    openSelectedProduct(event) {
        if (!this.selectedProductId) {
            event.preventDefault();
            return;
        }
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.selectedProductId,
                objectApiName: 'Product2',
                actionName: 'view'
            }
        });
    }

    productPageUrl(productId) {
        return this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId: productId,
                objectApiName: 'Product2',
                actionName: 'view'
            }
        });
    }

    async handleDetailSuccess() {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Opportunity Product saved',
            message: 'The EPP Opportunity Product was updated.',
            variant: 'success'
        }));
        this.isDetailModalOpen = false;
        this.selectedLineId = null;
        this.selectedProductId = null;
        this.selectedProductName = null;
        this.selectedProductUrl = null;
        await this.loadExistingProducts();
    }

    handleDetailError(event) {
        const message = event.detail && event.detail.message
            ? event.detail.message
            : 'The Opportunity Product could not be saved.';
        this.dispatchEvent(new ShowToastEvent({
            title: 'Unable to save',
            message,
            variant: 'error'
        }));
    }

    async openModal() {
        this.isModalOpen = true;
        this.dealerEntryStep = false;
        this.errorMessage = '';
        this.searchKey = '';
        this.searchResults = [];
        this.selectedProducts = [];
        this.isLoading = true;
        try {
            if (this.isDealer) {
                await this.loadDealerContext();
            }
            await this.handleSearch();
        } catch (error) {
            this.showError(error);
            this.isLoading = false;
        }
    }

    closeModal() {
        if (!this.isLoading) {
            this.isModalOpen = false;
            this.dealerEntryStep = false;
            this.errorMessage = '';
        }
    }

    handleSearchKeyChange(event) {
        this.searchKey = event.target.value;
    }

    handleSearchKeyPress(event) {
        if (event.key === 'Enter') {
            this.handleSearch();
        }
    }

    async handleSearch() {
        if (this.isDealer) {
            await this.searchDealerCatalog();
            return;
        }
        try {
            this.isLoading = true;
            this.errorMessage = '';
            this.searchResults = await searchProducts({
                opportunityId: this.recordId,
                isConsumable: this.isConsumable,
                searchKey: this.searchKey
            });
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleProductSelection(event) {
        const selectedRows = event.detail.selectedRows || [];
        this.selectedProducts = selectedRows.map(row => {
            const current = this.selectedProducts.find(
                product => product.pricebookEntryId === row.pricebookEntryId
            );
            if (current) {
                return current;
            }
            if (this.isDealer) {
                return this.newDealerSelection(row);
            }
            return {
                ...row,
                quantity: 1,
                unitPrice: row.listPrice,
                placementStartDate: null,
                placementEndDate: null,
                consumptionFrequency: null,
                elevatedEPPPricingApplicable: false,
                eppPrice: null,
                commitmentStartDate: null,
                commitmentEndDate: null
            };
        });
    }

    handleLineFieldChange(event) {
        const entryId = event.currentTarget.dataset.entryid;
        const fieldName = event.currentTarget.dataset.field;
        const fieldType = event.currentTarget.dataset.type;
        let value;

        if (fieldType === 'checkbox') {
            value = event.target.checked;
        } else if (fieldType === 'date' || fieldType === 'text') {
            value = event.target.value ? event.target.value : null;
        } else {
            value = event.target.value === '' ? null : Number(event.target.value);
        }

        this.selectedProducts = this.selectedProducts.map(product => {
            if (product.pricebookEntryId !== entryId) {
                return product;
            }
            const updated = { ...product, [fieldName]: value };
            if (fieldName === 'elevatedEPPPricingApplicable' && value !== true) {
                updated.eppPrice = null;
            }
            if (this.isDealer && fieldName === 'currencyCode' && value) {
                updated.unitPrice = this.convertDealerAmount(product.unitPrice, product.priceCurrency, value);
                updated.priceCurrency = value;
                updated.currencyCode = value;
            }
            if (this.isDealer && (fieldName === 'quantity' || fieldName === 'unitPrice' || fieldName === 'currencyCode')) {
                updated.lineTotal = this.dealerOpportunityTotal(
                    updated.quantity,
                    updated.unitPrice,
                    updated.priceCurrency
                );
                updated.lineTotalLabel = this.formatDealerMoney(updated.lineTotal, this.opportunityCurrencyCode);
            }
            return updated;
        });
    }

    removeSelectedProduct(event) {
        const entryId = event.currentTarget.dataset.entryid;
        this.selectedProducts = this.selectedProducts.filter(
            product => product.pricebookEntryId !== entryId
        );
    }

    goToDealerPricing() {
        if (!this.hasSelectedProducts) {
            this.errorMessage = 'Select at least one product.';
            return;
        }
        this.errorMessage = '';
        this.dealerEntryStep = true;
    }

    backToProductSearch() {
        this.errorMessage = '';
        this.dealerEntryStep = false;
    }

    async handleSave() {
        if (this.isDealer) {
            await this.saveDealerProducts();
            return;
        }
        const inputs = [...this.template.querySelectorAll('[data-validate="true"]')];
        const allValid = inputs.reduce(
            (valid, input) => input.reportValidity() && valid,
            true
        );
        if (!allValid) {
            this.errorMessage = this.isConsumable
                ? 'Complete quantity, frequency, commitment dates, and EPP Price when elevated pricing is selected.'
                : 'Complete quantity and placement dates for every selected equipment product.';
            return;
        }

        const productInputs = this.selectedProducts.map(product => ({
            pricebookEntryId: product.pricebookEntryId,
            quantity: Number(product.quantity),
            unitPrice: product.listPrice === null || product.listPrice === undefined
                ? null
                : Number(product.listPrice),
            placementStartDate: product.placementStartDate,
            placementEndDate: product.placementEndDate,
            consumptionFrequency: product.consumptionFrequency,
            elevatedEPPPricingApplicable: product.elevatedEPPPricingApplicable === true,
            eppPrice: product.elevatedEPPPricingApplicable !== true
                || product.eppPrice === null
                || product.eppPrice === undefined
                ? null
                : Number(product.eppPrice),
            commitmentStartDate: product.commitmentStartDate,
            commitmentEndDate: product.commitmentEndDate
        }));

        try {
            this.isLoading = true;
            this.errorMessage = '';
            const createdCount = await createOpportunityProducts({
                opportunityId: this.recordId,
                isConsumable: this.isConsumable,
                productInputsJson: JSON.stringify(productInputs)
            });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Products added',
                message: `${createdCount} ${this.productMode.toLowerCase()} product(s) were added.`,
                variant: 'success'
            }));
            this.isModalOpen = false;
            await this.loadExistingProducts();
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadDealerContext() {
        this.dealerContext = await getDealerContext({ opportunityId: this.recordId });
    }

    async loadDealerProducts() {
        this.isLoading = true;
        try {
            this.existingProducts = await getDealerProducts({ opportunityId: this.recordId });
        } finally {
            this.isLoading = false;
        }
    }

    async searchDealerCatalog() {
        try {
            this.isLoading = true;
            this.errorMessage = '';
            this.searchResults = await searchDealerProducts({
                opportunityId: this.recordId,
                searchKey: this.searchKey
            });
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    newDealerSelection(row) {
        const context = this.dealerContext || {};
        const quantity = 1;
        const entryCurrency = this.defaultDealerCurrency;
        const unitPrice = this.convertDealerAmount(row.listPrice, this.opportunityCurrencyCode, entryCurrency);
        const lineTotal = this.dealerOpportunityTotal(quantity, unitPrice, entryCurrency);
        return {
            ...row,
            quantity,
            unitPrice,
            priceCurrency: entryCurrency,
            lineTotal,
            lineTotalLabel: this.formatDealerMoney(lineTotal, this.opportunityCurrencyCode),
            currencyCode: entryCurrency,
            status: 'Open',
            confidenceLevel: context.forecastConfidence || 'Pipeline',
            expectedOrderDate: context.closeDate || null,
            expectedShipDate: context.expectedShipDate || null,
            comments: null
        };
    }

    dealerRate(isoCode) {
        const currencies = (this.dealerContext && this.dealerContext.currencies) || [];
        return currencies.find((rate) => rate.isoCode === isoCode);
    }

    convertDealerAmount(amount, fromIso, toIso) {
        if (amount === null || amount === undefined || fromIso === toIso) {
            return this.roundDealerAmount(amount, toIso);
        }
        const fromRate = this.dealerRate(fromIso);
        const toRate = this.dealerRate(toIso);
        if (!fromRate || !toRate || !fromRate.conversionRate) {
            return this.roundDealerAmount(amount, toIso);
        }
        const converted = (Number(amount) * Number(toRate.conversionRate)) / Number(fromRate.conversionRate);
        return this.roundDealerAmount(converted, toIso);
    }

    roundDealerAmount(amount, isoCode) {
        if (amount === null || amount === undefined || Number.isNaN(Number(amount))) {
            return null;
        }
        const rate = this.dealerRate(isoCode);
        const places = rate && rate.decimalPlaces !== null && rate.decimalPlaces !== undefined
            ? rate.decimalPlaces
            : 2;
        const factor = 10 ** places;
        return Math.round((Number(amount) + Number.EPSILON) * factor) / factor;
    }

    formatDealerMoney(amount, isoCode) {
        if (amount === null || amount === undefined) {
            return '';
        }
        const rate = this.dealerRate(isoCode);
        const places = rate && rate.decimalPlaces !== null && rate.decimalPlaces !== undefined
            ? rate.decimalPlaces
            : 2;
        return `${Number(amount).toFixed(places)} ${isoCode}`;
    }

    dealerOpportunityTotal(quantity, unitPrice, priceCurrency) {
        const unitInOpportunityCurrency = this.convertDealerAmount(
            unitPrice,
            priceCurrency,
            this.opportunityCurrencyCode
        );
        return this.dealerLineTotal(quantity, unitInOpportunityCurrency);
    }

    dealerLineTotal(quantity, unitPrice) {
        if (quantity === null || quantity === undefined || unitPrice === null || unitPrice === undefined) {
            return null;
        }
        return Number(quantity) * Number(unitPrice);
    }

    async saveDealerProducts() {
        const inputs = [...this.template.querySelectorAll('[data-validate="true"]')];
        const allValid = inputs.reduce(
            (valid, input) => input.reportValidity() && valid,
            true
        );
        if (!allValid) {
            this.errorMessage = 'Enter quantity and unit price for every selected product.';
            return;
        }
        const productInputs = this.selectedProducts.map(product => ({
            pricebookEntryId: product.pricebookEntryId,
            quantity: Number(product.quantity),
            unitPrice: Number(product.unitPrice),
            currencyCode: product.priceCurrency || product.currencyCode,
            status: product.status,
            confidenceLevel: product.confidenceLevel,
            expectedOrderDate: product.expectedOrderDate || null,
            expectedShipDate: product.expectedShipDate || null,
            comments: product.comments
        }));
        try {
            this.isLoading = true;
            this.errorMessage = '';
            const createdCount = await createDealerProducts({
                opportunityId: this.recordId,
                productInputsJson: JSON.stringify(productInputs)
            });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Products added',
                message: `${createdCount} product(s) were added.`,
                variant: 'success'
            }));
            this.isModalOpen = false;
            await this.loadDealerProducts();
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async removeDealerLine(opportunityLineItemId) {
        try {
            this.isLoading = true;
            await deleteDealerProduct({
                opportunityId: this.recordId,
                opportunityLineItemId
            });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Product removed',
                message: 'The product line was removed.',
                variant: 'success'
            }));
            await this.loadDealerProducts();
        } catch (error) {
            this.showError(error);
            this.isLoading = false;
        }
    }

    showError(error) {
        this.errorMessage =
            error && error.body && error.body.message
                ? error.body.message
                : 'Unexpected error occurred.';
    }
}