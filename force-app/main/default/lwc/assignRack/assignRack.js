import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    setTabLabel
} from 'lightning/platformWorkspaceApi';
import assignRack from '@salesforce/apex/AssignRackController.assignRack';

const TAB_LABEL = 'Assign Rack';

export default class AssignRack extends LightningElement {
    workOrderInput = '';
    rackInput = '';
    isLoading = false;
    errorMessage = '';
    isConsoleNavigation = false;
    _focusOnRender = true;

    @wire(IsConsoleNavigation)
    wiredIsConsoleNavigation(result) {
        this.isConsoleNavigation = result?.data === true;
        this.updateWorkspaceTab();
    }

    connectedCallback() {
        this.updateWorkspaceTab();
    }

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

    focusRackField() {
        const input = this.template.querySelector('[data-id="rack-input"]');
        if (input) {
            input.focus();
        }
    }

    /**
     * GW-5783 - Sets the browser and console tab titles for the Assign Rack tab.
     */
    async updateWorkspaceTab() {
        document.title = TAB_LABEL;

        if (!this.isConsoleNavigation) {
            return;
        }

        try {
            const tabInfo = await getFocusedTabInfo();
            if (!tabInfo?.tabId) {
                return;
            }
            await setTabLabel(tabInfo.tabId, TAB_LABEL);
        } catch (error) {
            // Non-console hosts may not support workspace APIs; page title still updates.
        }
    }

    handleWorkOrderChange(event) {
        this.workOrderInput = event.target.value;
        this.errorMessage = '';
    }

    handleRackChange(event) {
        this.rackInput = event.target.value;
        this.errorMessage = '';
    }

    handleWorkOrderKeyDown(event) {
        if (event.key !== 'Enter') {
            return;
        }
        event.preventDefault();
        this.workOrderInput = (event.target.value || '').trim();
        if (!this.workOrderInput) {
            return;
        }
        // If Rack already populated, assign immediately; otherwise move focus to Rack.
        if (this.rackInput && this.rackInput.trim()) {
            this.handleContinue();
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => this.focusRackField(), 0);
    }

    handleRackKeyDown(event) {
        if (event.key !== 'Enter') {
            return;
        }
        event.preventDefault();
        this.rackInput = (event.target.value || '').trim();
        if (!this.rackInput) {
            return;
        }

        // If Work Order is empty, keep Rack and move focus to Work Order.
        if (!this.workOrderInput || !this.workOrderInput.trim()) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            window.setTimeout(() => this.focusWorkOrderField(), 0);
            return;
        }

        this.handleContinue();
    }

    async handleContinue() {
        if (this.isContinueDisabled) {
            return;
        }

        const workOrderValue = (this.workOrderInput || '').trim();
        const rackValue = (this.rackInput || '').trim();
        this.workOrderInput = workOrderValue;
        this.rackInput = rackValue;

        if (!workOrderValue || !rackValue) {
            this.errorMessage = 'Work Order and Rack are required.';
            this._focusOnRender = true;
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';
        try {
            const result = await assignRack({
                workOrderInput: workOrderValue,
                rackInput: rackValue
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Rack Assigned',
                    message: `Work Order ${result.workOrderNumber} has been updated.`,
                    variant: 'success'
                })
            );
            this.resetToInitialScreen();
        } catch (error) {
            this.resetFieldsKeepError(this.resolveErrorMessage(error));
        } finally {
            this.isLoading = false;
        }
    }

    resetToInitialScreen() {
        this.workOrderInput = '';
        this.rackInput = '';
        this.errorMessage = '';
        this._focusOnRender = true;
    }

    resetFieldsKeepError(message) {
        this.workOrderInput = '';
        this.rackInput = '';
        this.errorMessage = message;
        this._focusOnRender = true;
    }

    resolveErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'Unable to assign rack. Please try again.';
    }
}