import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';

/**
 * GC-3091: Utility component to invoke the Retry TAS Assignment Flow for a Prospect Account.
 */
export default class TasRetryAssignmentAction extends LightningElement {
    @api recordId;

    flowApiName = 'RetryTASAssignment';

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
            this.dispatchEvent(new CloseActionScreenEvent());

            setTimeout(() => {
                window.location.reload();
            }, 500);
        }
    }
}