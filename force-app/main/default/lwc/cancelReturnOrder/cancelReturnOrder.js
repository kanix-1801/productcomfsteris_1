import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import getCancelContext from '@salesforce/apex/CancelReturnOrderController.getCancelContext';
import cancelReturnOrder from '@salesforce/apex/CancelReturnOrderController.cancelReturnOrder';

export default class CancelReturnOrder extends LightningElement {
    @api recordId;

    context;
    cancelReason;
    cancelReasonNotes;
    isLoading = true;
    isSaving = false;
    loadError;

    @wire(getCancelContext, { returnOrderId: '$recordId' })
    wiredCancelContext({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.context = data;
            this.loadError = undefined;
        } else if (error) {
            this.context = undefined;
            this.loadError =
                error.body?.message ||
                error.message ||
                'Unable to load Return Order cancel details.';
        }
    }

    get cancelReasonOptions() {
        return this.context?.cancelReasonOptions ?? [];
    }

    get showForm() {
        return this.context?.canCancel === true;
    }

    get showBlockedState() {
        return this.context && this.context.canCancel === false;
    }

    get returnOrderLabel() {
        return this.context?.returnOrderNumber || this.recordId;
    }

    get isSubmitDisabled() {
        return this.isSaving || !this.cancelReason;
    }

    handleCancelReasonChange(event) {
        this.cancelReason = event.detail.value;
    }

    handleCancelReasonNotesChange(event) {
        this.cancelReasonNotes = event.detail.value;
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleConfirmCancel() {
        if (!this.cancelReason) {
            this.showToast(
                'Validation',
                'Cancel Reason is required.',
                'error'
            );
            return;
        }

        this.isSaving = true;
        try {
            await cancelReturnOrder({
                returnOrderId: this.recordId,
                cancelReason: this.cancelReason,
                cancelReasonNotes: this.cancelReasonNotes
            });

            getRecordNotifyChange([{ recordId: this.recordId }]);
            this.showToast(
                'Success',
                'Return Order canceled successfully.',
                'success'
            );
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.showToast(
                'Error',
                error.body?.message ||
                    error.message ||
                    'Unable to cancel Return Order.',
                'error'
            );
        } finally {
            this.isSaving = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}