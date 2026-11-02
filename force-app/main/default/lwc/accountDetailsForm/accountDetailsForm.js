import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const ACCOUNT_FIELDS = [
    'Name',
    'AccountSource',
    'Phone',
    'ParentId',
    'Industry',
    'Type',
    'Status__c',
    'OwnerId'
];

export default class AccountDetailsForm extends LightningElement {
    @api recordId;

    /**
     * When true, form uses view mode (e.g. Customer 360 visibility).
     * Must default to false per LWC boolean rules.
     */
   readOnly = true;

    accountFields = ACCOUNT_FIELDS;

    get hasRecordId() {
        return Boolean(this.recordId);
    }

    get formMode() {
        return this.readOnly === true || this.readOnly === 'true' ? 'view' : 'edit';
    }

    handleSuccess() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Account was saved.',
                variant: 'success'
            })
        );
    }

    handleError(event) {
        const message = event.detail?.message || 'Unable to save account.';
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error saving account',
                message,
                variant: 'error'
            })
        );
    }
}