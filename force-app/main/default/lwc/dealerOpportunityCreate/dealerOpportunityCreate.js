import { LightningElement, api } from 'lwc';
import getCreateContext from '@salesforce/apex/DealerOpportunityController.getCreateContext';
import finalizeCreatedOpportunity from '@salesforce/apex/DealerOpportunityController.finalizeCreatedOpportunity';

export default class DealerOpportunityCreate extends LightningElement {
    @api isOpen = false;
    recordTypeId;
    errorMessage;
    isFinalizing = false;

    connectedCallback() {
        getCreateContext()
            .then((context) => {
                this.recordTypeId = context.recordTypeId;
            })
            .catch((error) => {
                this.errorMessage = errorMessage(error);
            });
    }

    handleSuccess(event) {
        const opportunityId = event.detail.id;
        this.errorMessage = null;
        this.isFinalizing = true;
        finalizeCreatedOpportunity({ opportunityId })
            .then(() => {
                this.dispatchEvent(new CustomEvent('created', { detail: { opportunityId } }));
            })
            .catch((error) => {
                this.errorMessage = errorMessage(error);
            })
            .finally(() => {
                this.isFinalizing = false;
            });
    }

    handleError(event) {
        const detail = event.detail;
        this.errorMessage = detail?.detail || detail?.message || 'Unable to create the opportunity.';
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
}

function errorMessage(error) {
    return error?.body?.message || 'Unable to create the opportunity.';
}