import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import printBinTag from '@salesforce/apex/WorkOrderBinTagPrintController.printBinTag';

/**
 * GW-4637 - Work Order action that prints Instruments bin tags and Devices travel tags.
 */
export default class PrintBinTagAction extends LightningElement {
    _recordId;
    started = false;
    isLoading = true;
    errorMessage = '';
    successMessage = '';

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value && !this.started) {
            this.started = true;
            this.runPrint();
        }
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get hasSuccess() {
        return !!this.successMessage;
    }

    async runPrint() {
        this.isLoading = true;
        this.errorMessage = '';
        this.successMessage = '';
        try {
            const message = await printBinTag({ workOrderId: this._recordId });
            this.successMessage = message;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Bin tag printed',
                    message,
                    variant: 'success'
                })
            );
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.errorMessage = this.pickMessage(error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Bin tag print failed',
                    message: this.errorMessage,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    pickMessage(error) {
        return error?.body?.message || error?.message || 'Unable to print bin tag.';
    }
}