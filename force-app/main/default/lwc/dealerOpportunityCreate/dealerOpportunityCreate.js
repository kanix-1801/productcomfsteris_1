import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getCreateContext from '@salesforce/apex/DealerOpportunityController.getCreateContext';
import createOpportunity from '@salesforce/apex/DealerOpportunityController.createOpportunity';

export default class DealerOpportunityCreate extends NavigationMixin(LightningElement) {
    @api isOpen = false;
    context = { partnerUser: true, currencies: [], stages: [] };
    name = '';
    stageName = '';
    endCustomerName = '';
    description = '';
    country = '';
    amount;
    currencyCode = 'USD';
    closeDate;
    expectedShipDate;
    installationDate;
    accountId;
    errorMessage;
    isSaving = false;

    connectedCallback() {
        getCreateContext()
            .then((context) => {
                this.context = context;
                this.currencyCode = context.defaultCurrency || 'USD';
                this.accountId = context.dealerAccountId;
            })
            .catch((error) => {
                this.errorMessage = errorMessage(error);
            });
    }

    get currencyOptions() {
        return this.context.currencies || [];
    }

    get stageOptions() {
        return (this.context.stages || []).map((stage) => ({ label: stage, value: stage }));
    }

    handleName(event) { this.name = event.target.value; }
    handleStage(event) { this.stageName = event.detail.value; }
    handleCustomer(event) { this.endCustomerName = event.target.value; }
    handleDescription(event) { this.description = event.target.value; }
    handleCountry(event) { this.country = event.target.value; }
    handleAmount(event) { this.amount = event.target.value; }
    handleCurrency(event) { this.currencyCode = event.detail.value; }
    handleCloseDate(event) { this.closeDate = event.target.value; }
    handleShipDate(event) { this.expectedShipDate = event.target.value; }
    handleInstallationDate(event) { this.installationDate = event.target.value; }

    handleAccount(event) {
        this.accountId = event.detail.recordId;
    }

    close() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    closeFromBackdrop() {
        this.close();
    }

    stopClose(event) {
        event.stopPropagation();
    }

    save() {
        if (!this.stageName) {
            this.errorMessage = 'Stage is required.';
            return;
        }
        this.errorMessage = null;
        this.isSaving = true;
        const request = {
            name: this.name,
            stageName: this.stageName,
            endCustomerName: this.endCustomerName,
            description: this.description,
            country: this.country,
            amount: this.amount === '' || this.amount === undefined ? null : Number(this.amount),
            currencyCode: this.currencyCode,
            closeDate: this.closeDate,
            expectedShipDate: this.expectedShipDate,
            installationDate: this.installationDate,
            accountId: this.accountId
        };
        createOpportunity({ requestJson: JSON.stringify(request) })
            .then((opportunityId) => {
                this.dispatchEvent(new CustomEvent('created', { detail: { opportunityId } }));
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: opportunityId,
                        objectApiName: 'Opportunity',
                        actionName: 'view'
                    }
                });
            })
            .catch((error) => {
                this.errorMessage = errorMessage(error);
            })
            .finally(() => {
                this.isSaving = false;
            });
    }
}

function errorMessage(error) {
    return error?.body?.message || 'Unable to create the opportunity.';
}