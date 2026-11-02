import { LightningElement, api } from 'lwc';
import { updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import ID_FIELD from '@salesforce/schema/CSC_Visit_Request__c.Id';
import STATUS_FIELD from '@salesforce/schema/CSC_Visit_Request__c.Status__c';
import SUBMIT_SUCCESS_TITLE from '@salesforce/label/c.CSC_Submit_Success_Title';
import SUBMIT_SUCCESS_MESSAGE from '@salesforce/label/c.CSC_Submit_Success_Message';
import SUBMIT_ERROR_TITLE from '@salesforce/label/c.CSC_Submit_Error_Title';
import SUBMIT_ERROR_MESSAGE from '@salesforce/label/c.CSC_Submit_Error_Message';

/**
 * GC-2601: Headless quick action that submits a CSC Visit Request.
 * Validation is left to CSC_002 and CSC_009 so the rules stay declarative,
 * and whatever message they return is shown in the toast.
 */
export default class CscSubmitVisitRequest extends LightningElement {
    @api recordId;

    isRunning = false;

    @api
    async invoke() {
        if (this.isRunning) {
            return;
        }

        this.isRunning = true;

        try {
            await updateRecord({
                fields: {
                    [ID_FIELD.fieldApiName]: this.recordId,
                    [STATUS_FIELD.fieldApiName]: 'Requested'
                }
            });

            // The save has committed by this point. Toast right away and add
            // no further awaits: the save refreshes the record, which hides
            // this Draft-only action and tears the component down, and a
            // detached component can no longer dispatch a toast.
            this.dispatchEvent(
                new ShowToastEvent({
                    title: SUBMIT_SUCCESS_TITLE,
                    message: SUBMIT_SUCCESS_MESSAGE,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: SUBMIT_ERROR_TITLE,
                    message: reduceError(error, SUBMIT_ERROR_MESSAGE),
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