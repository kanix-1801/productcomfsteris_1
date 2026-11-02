import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import cancelVisit from '@salesforce/apex/CscVisitStatusAction.cancelVisit';
import CANCEL_SUCCESS_TITLE from '@salesforce/label/c.CSC_Cancel_Success_Title';
import CANCEL_SUCCESS_MESSAGE from '@salesforce/label/c.CSC_Cancel_Success_Message';
import CANCEL_ERROR_TITLE from '@salesforce/label/c.CSC_Cancel_Error_Title';
import CANCEL_ERROR_MESSAGE from '@salesforce/label/c.CSC_Cancel_Error_Message';

/**
 * GC-2601 / GC-3518: Headless quick action that cancels a visit.
 * Apex removes a pending approval before changing Status.
 */
export default class CscCancelVisitRequest extends LightningElement {
    @api recordId;

    isRunning = false;

    @api
    async invoke() {
        if (this.isRunning) {
            return;
        }

        this.isRunning = true;

        try {
            await cancelVisit({ recordId: this.recordId });
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: CANCEL_SUCCESS_TITLE,
                    message: CANCEL_SUCCESS_MESSAGE,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: CANCEL_ERROR_TITLE,
                    message: reduceError(error, CANCEL_ERROR_MESSAGE),
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isRunning = false;
        }
    }
}

/**
 * Pulls the readable text out of a Lightning Data Service error. Validation
 * rules arrive under output.errors, field level problems under fieldErrors.
 */
function reduceError(error, fallbackMessage) {
    const output = error?.body?.output;

    const messages = [
        ...(output?.errors ?? []).map((e) => e.message),
        ...Object.values(output?.fieldErrors ?? {}).flatMap((errors) =>
            errors.map((e) => e.message)
        )
    ].filter(Boolean);

    if (messages.length) {
        return messages.join(' ');
    }

    return error?.body?.message ?? fallbackMessage;
}