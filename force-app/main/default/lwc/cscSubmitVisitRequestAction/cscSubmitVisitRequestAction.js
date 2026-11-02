import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

/**
 * GC-2601: Runs the Submit CSC Visit Request flow and closes the quick action
 * panel as soon as the flow finishes, so no "flow finished" screen is shown.
 */
export default class CscSubmitVisitRequestAction extends LightningElement {
    @api recordId;

    flowApiName = 'Submit_CSC_Visit_Request';

    get isReady() {
        return this.recordId;
    }

    get flowInputVariables() {
        return [
            {
                name: 'recordId',
                type: 'String',
                value: this.recordId
            }
        ];
    }

    handleStatusChange(event) {
        const status = event.detail.status;

        if (
            status === 'FINISHED' ||
            status === 'FINISHED_SCREEN' ||
            status === 'ERROR'
        ) {
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            this.dispatchEvent(new CloseActionScreenEvent());
        }
    }
}