import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCapitalSubcaseRows from '@salesforce/apex/CBM_DeleteCapitalSubcasesService.getCapitalSubcaseRows';
import deleteAllCapitalSubcases from '@salesforce/apex/CBM_DeleteCapitalSubcasesService.deleteAllCapitalSubcases';
import { refreshApex } from '@salesforce/apex';

export default class CbmDeleteCapitalSubcases extends LightningElement {
    @api recordId;

    capitalSubcases = [];
    wiredResult;
    reason = '';
    showConfirm = false;
    isBusy = false;

    columns = [
        {
            label: 'Case Number',
            fieldName: 'recordUrl',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'caseNumber' },
                target: '_blank'
            }
        },
        { label: 'Subject', fieldName: 'subject' },
        { label: 'Status', fieldName: 'status' },
        {
            label: 'Created',
            fieldName: 'createdDate',
            type: 'date',
            typeAttributes: {
                year: 'numeric',
                month: 'short',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit'
            }
        }
    ];

    @wire(getCapitalSubcaseRows, { parentCaseId: '$recordId' })
    wiredSubs(result) {
        this.wiredResult = result;
        if (result.data) {
            this.capitalSubcases = result.data;
        } else if (result.error) {
            this.toast('Error', this.pickMessage(result.error), 'error');
        }
    }

    get hasRows() {
        return (this.capitalSubcases?.length || 0) > 0;
    }

    get disableDelete() {
        return this.isBusy || !this.hasRows;
    }

    handleReasonChange(event) {
        this.reason = event.target.value;
    }

    handleDeleteClick() {
        this.showConfirm = true;
    }

    handleCancel() {
        this.showConfirm = false;
    }

    async handleConfirmDelete() {
        this.isBusy = true;
        try {
            const message = await deleteAllCapitalSubcases({
                parentCaseId: this.recordId,
                reason: this.reason
            });

            this.toast('Success', message, 'success');
            this.showConfirm = false;

            await refreshApex(this.wiredResult);
        } catch (e) {
            this.toast('Error', this.pickMessage(e), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }

    pickMessage(e) {
        return e?.body?.message || e?.message || 'Unexpected error';
    }
}