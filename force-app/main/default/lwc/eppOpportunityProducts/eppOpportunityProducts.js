import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchProducts from '@salesforce/apex/EPPProductController.searchProducts';
import getOpportunityProducts from '@salesforce/apex/EPPProductController.getOpportunityProducts';
import createOpportunityProducts from '@salesforce/apex/EPPProductController.createOpportunityProducts';

/**
 * GC-3431 - Reusable EPP product section. App Builder places this component once
 * for Capital and once for Consumables by setting productMode.
 */
export default class EppOpportunityProducts extends LightningElement {
    @api recordId;
    @api productMode = 'Capital';

    @track existingProducts = [];
    @track searchResults = [];
    @track selectedProducts = [];
    @track errorMessage = '';

    searchKey = '';
    isModalOpen = false;
    isDetailModalOpen = false;
    isDetailEdit = false;
    selectedLineId;
    isLoading = false;

    frequencyOptions = [
        { label: 'Weekly', value: 'Weekly' },
        { label: 'Monthly', value: 'Monthly' },
        { label: 'Annual', value: 'Annual' },
        { label: 'One Time', value: 'One Time' }
    ];

    productColumns = [
        { label: 'Product Name', fieldName: 'productName', wrapText: true },
        { label: 'Product Code', fieldName: 'productCode' },
        { label: 'Product Family', fieldName: 'productFamily' },
        { label: 'Business Unit', fieldName: 'businessUnit' },
        { label: 'List Price', fieldName: 'listPrice', type: 'currency' }
    ];

    connectedCallback() {
        this.loadExistingProducts();
    }

    get isConsumable() {
        return this.productMode === 'Consumable';
    }

    get sectionTitle() {
        return this.isConsumable ? 'EPP Consumables' : 'EPP Capital Equipment';
    }

    get addButtonLabel() {
        return this.isConsumable ? 'Add Consumables' : 'Add Capital Equipment';
    }

    get modalTitle() {
        return this.addButtonLabel;
    }

    get detailModalTitle() {
        const action = this.isDetailEdit ? 'Edit' : 'View';
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

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        this.selectedLineId = event.detail.row.opportunityLineItemId;
        this.isDetailEdit = actionName === 'edit';
        this.isDetailModalOpen = true;
    }

    closeDetailModal() {
        if (!this.isLoading) {
            this.isDetailModalOpen = false;
            this.selectedLineId = null;
        }
    }

    async handleDetailSuccess() {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Opportunity Product saved',
            message: 'The EPP Opportunity Product was updated.',
            variant: 'success'
        }));
        this.isDetailModalOpen = false;
        this.selectedLineId = null;
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
        this.errorMessage = '';
        this.searchKey = '';
        this.searchResults = [];
        this.selectedProducts = [];
        await this.handleSearch();
    }

    closeModal() {
        if (!this.isLoading) {
            this.isModalOpen = false;
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
            return current || {
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
            return updated;
        });
    }

    removeSelectedProduct(event) {
        const entryId = event.currentTarget.dataset.entryid;
        this.selectedProducts = this.selectedProducts.filter(
            product => product.pricebookEntryId !== entryId
        );
    }

    async handleSave() {
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

    showError(error) {
        this.errorMessage =
            error && error.body && error.body.message
                ? error.body.message
                : 'Unexpected error occurred.';
    }
}