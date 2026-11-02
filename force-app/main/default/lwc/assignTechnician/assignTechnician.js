import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import assignTechnician from '@salesforce/apex/AssignTechnicianController.assignTechnician';

const STATUS_BLOCKED_MESSAGE =
    'Only Work Orders that have advanced to Ready for Repair can be assigned to a Technician';

export default class AssignTechnician extends LightningElement {
    workOrderInput = '';
    isLoading = false;
    errorMessage = '';
    _focusOnRender = true;

    get isContinueDisabled() {
        return this.isLoading;
    }

    renderedCallback() {
        if (!this._focusOnRender || this.isLoading) {
            return;
        }
        this._focusOnRender = false;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => this.focusWorkOrderField(), 0);
    }

    focusWorkOrderField() {
        const input = this.template.querySelector('[data-id="work-order-input"]');
        if (input) {
            input.focus();
        }
    }

    handleWorkOrderChange(event) {
        this.workOrderInput = event.target.value;
        this.errorMessage = '';
    }

    handleWorkOrderKeyDown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.handleContinue();
        }
    }

    async handleContinue() {
        if (this.isContinueDisabled) {
            return;
        }

        const workOrderValue = (this.workOrderInput || '').trim();
        this.workOrderInput = workOrderValue;
        if (!workOrderValue) {
            this.errorMessage = 'Work Order is required.';
            this._focusOnRender = true;
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';
        try {
            const result = await assignTechnician({
                workOrderInput: workOrderValue
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Technician Assigned',
                    message: `Work Order ${result.workOrderNumber} is now assigned to you.`,
                    variant: 'success'
                })
            );
            this.resetToInitialScreen();
        } catch (error) {
            const message = this.resolveErrorMessage(error);
            if (message === STATUS_BLOCKED_MESSAGE) {
                this.workOrderInput = '';
                this.errorMessage = message;
                this._focusOnRender = true;
            } else {
                this.errorMessage = message;
                this._focusOnRender = true;
            }
        } finally {
            this.isLoading = false;
        }
    }

    resetToInitialScreen() {
        this.workOrderInput = '';
        this.errorMessage = '';
        this._focusOnRender = true;
    }

    resolveErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'Unable to assign technician. Please try again.';
    }
}