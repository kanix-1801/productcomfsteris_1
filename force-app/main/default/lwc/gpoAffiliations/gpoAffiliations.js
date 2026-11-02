import { LightningElement, api } from 'lwc';
import getGpoAffiliations from '@salesforce/apex/GpoAffiliationsController.getGpoAffiliations';

const COLUMNS = [
    { label: 'Contract', fieldName: 'contract' },
    { label: 'Contract Name', fieldName: 'contractName' },
    { label: 'Status', fieldName: 'status' },
    { label: 'Contract Type', fieldName: 'contractType' },
    { label: 'Effective date', fieldName: 'effectiveDate', type: 'date' },
    { label: 'Expiration date', fieldName: 'expirationDate', type: 'date' }
];

export default class GpoAffiliations extends LightningElement {
    @api recordId;

    columns = COLUMNS;
    gpoAffiliations = [];
    error;

    connectedCallback() {
        this.loadGpoAffiliations();
    }

    async loadGpoAffiliations() {
        if (!this.recordId) {
            this.gpoAffiliations = [];
            return;
        }

        try {
            this.gpoAffiliations = await getGpoAffiliations({
                accountId: this.recordId
            });
            this.error = undefined;
        } catch (error) {
            this.gpoAffiliations = [];
            this.error = error;
        }
    }

    get hasRecords() {
        return this.gpoAffiliations.length > 0;
    }

    get hasError() {
        return this.error !== undefined;
    }
}