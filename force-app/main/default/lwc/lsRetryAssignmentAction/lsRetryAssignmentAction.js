import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';

/**
 * GCL-4: Utility component to invoke the Life Sciences Retry TAS Assignment Flow
 * for a Life Sciences Prospect Account.
 *
 * As Sales Leaders, I want Salesforce to trigger real-time TAS validation when a new
 * Prospect Account is created so that rep assignments and territory visibility are
 * established immediately.
 *
 * Healthcare continues to use the tasRetryAssignmentAction component.
 */
export default class LsRetryAssignmentAction extends LightningElement {
    @api recordId;

    flowApiName = 'LSRetryTASAssignment';

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