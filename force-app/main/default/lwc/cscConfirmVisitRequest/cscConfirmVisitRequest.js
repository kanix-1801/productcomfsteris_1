import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import confirmVisit from '@salesforce/apex/CscVisitStatusAction.confirmVisit';
import CONFIRM_SUCCESS_TITLE from '@salesforce/label/c.CSC_Confirm_Success_Title';
import CONFIRM_SUCCESS_MESSAGE from '@salesforce/label/c.CSC_Confirm_Success_Message';
import CONFIRM_ERROR_TITLE from '@salesforce/label/c.CSC_Confirm_Error_Title';
import CONFIRM_ERROR_MESSAGE from '@salesforce/label/c.CSC_Confirm_Error_Message';

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
                    title: CONFIRM_SUCCESS_TITLE,
                    message: CONFIRM_SUCCESS_MESSAGE,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: CONFIRM_ERROR_TITLE,
                    message: error?.body?.message ?? CONFIRM_ERROR_MESSAGE,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isRunning = false;
        }
    }
}