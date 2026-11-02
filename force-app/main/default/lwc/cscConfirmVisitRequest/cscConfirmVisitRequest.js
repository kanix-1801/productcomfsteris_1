import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import confirmVisit from '@salesforce/apex/CscVisitStatusAction.confirmVisit';

/**
 * GC-3518: Headless quick action that moves an Approved visit to Confirmed.
 */
export default class CscConfirmVisitRequest extends LightningElement {
    @api recordId;

    isRunning = false;

    @api
    async invoke() {
        if (this.isRunning) {
            return;
        }

        this.isRunning = true;
        try {
            await confirmVisit({ recordId: this.recordId });
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Visit confirmed',
                    message: 'The visit status is now Confirmed.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Visit not confirmed',
                    message: error?.body?.message ?? 'The visit could not be confirmed.',
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isRunning = false;
        }
    }
}