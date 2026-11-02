import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

/**
 * GC-2601: Closes the quick action modal when a screen flow finishes so the
 * user never sees the default "Your flow finished" panel.
 */
export default class CscFlowCloseAction extends LightningElement {
    @api recordId;

    connectedCallback() {
        if (this.recordId) {
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        }

        this.dispatchEvent(new CloseActionScreenEvent());
    }
}