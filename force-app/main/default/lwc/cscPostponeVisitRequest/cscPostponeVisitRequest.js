import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import postponeVisit from '@salesforce/apex/CscVisitStatusAction.postponeVisit';

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
                    title: 'Visit postponed',
                    message: 'The visit status is now Postponed. Use Change Date to select a new date.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Visit not postponed',
                    message: reduceError(error, 'The visit could not be postponed.'),
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