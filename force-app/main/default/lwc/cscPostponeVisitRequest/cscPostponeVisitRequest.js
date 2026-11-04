import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import postponeVisit from '@salesforce/apex/CscVisitStatusAction.postponeVisit';
import POSTPONE_SUCCESS_TITLE from '@salesforce/label/c.CSC_Postpone_Success_Title';
import POSTPONE_SUCCESS_MESSAGE from '@salesforce/label/c.CSC_Postpone_Success_Message';
import POSTPONE_ERROR_TITLE from '@salesforce/label/c.CSC_Postpone_Error_Title';
import POSTPONE_ERROR_MESSAGE from '@salesforce/label/c.CSC_Postpone_Error_Message';

/**
 * GC-3579: Headless quick action that postpones a visit. CSC Administrator only.
 * Apex rejects a pending approval, then sets Status to Postponed and clears the active dates.
 */
export default class CscPostponeVisitRequest extends LightningElement {
    @api recordId;

    isRunning = false;

    @api
    async invoke() {
        if (this.isRunning) {
            return;
        }

        this.isRunning = true;

        try {
            await postponeVisit({ recordId: this.recordId });
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: POSTPONE_SUCCESS_TITLE,
                    message: POSTPONE_SUCCESS_MESSAGE,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: POSTPONE_ERROR_TITLE,
                    message: reduceError(error, POSTPONE_ERROR_MESSAGE),
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