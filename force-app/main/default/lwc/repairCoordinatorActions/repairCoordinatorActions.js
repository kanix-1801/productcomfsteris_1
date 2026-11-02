import { LightningElement, wire } from 'lwc';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    setTabLabel
} from 'lightning/platformWorkspaceApi';
import processScan from '@salesforce/apex/RepairCoordinatorActionsController.processScan';
import assignCandidate from '@salesforce/apex/RepairCoordinatorActionsController.assignCandidate';
import removeRack from '@salesforce/apex/RepairCoordinatorActionsController.removeRack';
import removeServiceTeam from '@salesforce/apex/RepairCoordinatorActionsController.removeServiceTeam';

const MODE_MENU = 'menu';
const MODE_ASSIGN = 'assign';
const TAB_LABEL_MENU = 'Repair Coordinator Actions';
const TAB_LABEL_ASSIGN = 'Assign Work Order';

/**
 * GW-5231 - Repair Coordinator action menu and barcode-driven Work Order assignments.
 */
export default class RepairCoordinatorActions extends LightningElement {
    mode = MODE_MENU;
    scanValue = '';
    workspace;
    candidates = [];
    selectedRecordIds = [];
    errorMessage = '';
    successMessage = '';
    isBusy = false;
    isConsoleNavigation = false;
    _shouldFocusScan = false;

    /**
     * GW-5231 - Tracks whether the host is Lightning Console so tab labels can be updated.
     * @param {object} result IsConsoleNavigation wire result
     */
    @wire(IsConsoleNavigation)
    wiredIsConsoleNavigation(result) {
        this.isConsoleNavigation = result?.data === true;
        this.updateWorkspaceTab();
    }

    /**
     * GW-5231 - Applies the action-menu tab title when the tab first loads.
     */
    connectedCallback() {
        this.updateWorkspaceTab();
    }

    /**
     * GW-5231 - Returns true while the action menu is displayed.
     */
    get isMenu() {
        return this.mode === MODE_MENU;
    }

    /**
     * GW-5231 - Returns true after a Work Order has been scanned.
     */
    get hasWorkOrder() {
        return Boolean(this.workspace?.workOrderId);
    }

    /**
     * GW-5231 - Returns true when the current Work Order has a Rack.
     */
    get hasRack() {
        return Boolean(this.workspace?.rackId);
    }

    /**
     * GW-5231 - Returns true when the current Work Order has a Service Team.
     */
    get hasServiceTeam() {
        return Boolean(this.workspace?.serviceTeamId);
    }

    /**
     * GW-5231 - Returns the Rack name or the empty-state label.
     */
    get rackDisplay() {
        return this.workspace?.rackName || 'Not assigned';
    }

    /**
     * GW-5231 - Returns the Service Team name or the empty-state label.
     */
    get serviceTeamDisplay() {
        return this.workspace?.serviceTeamName || 'Not assigned';
    }

    /**
     * GW-5231 - Styles the Rack value as assigned or as an empty placeholder.
     */
    get rackValueClass() {
        return this.hasRack
            ? 'assignment-row__value'
            : 'assignment-row__value assignment-row__value_empty';
    }

    /**
     * GW-5231 - Styles the Service Team value as assigned or as an empty placeholder.
     */
    get serviceTeamValueClass() {
        return this.hasServiceTeam
            ? 'assignment-row__value'
            : 'assignment-row__value assignment-row__value_empty';
    }

    /**
     * GW-5231 - Returns true while the ambiguous candidate modal is open.
     */
    get showCandidateModal() {
        return this.candidates.length > 0;
    }

    /**
     * GW-5231 - Decorates candidates with their selected state for the multi-select modal.
     */
    get candidateRows() {
        return this.candidates.map((candidate) => {
            const isSelected = this.selectedRecordIds.includes(candidate.recordId);
            return {
                ...candidate,
                isSelected,
                buttonClass: isSelected
                    ? 'candidate-button candidate-button_selected'
                    : 'candidate-button'
            };
        });
    }

    /**
     * GW-5231 - Blocks Assign until at least one candidate is selected.
     */
    get isAssignDisabled() {
        return this.isBusy || this.selectedRecordIds.length === 0;
    }

    /**
     * GW-5231 - Restores scanner focus after rendering or completing an action.
     */
    renderedCallback() {
        if (!this._shouldFocusScan || this.mode !== MODE_ASSIGN || this.showCandidateModal) {
            return;
        }
        this._shouldFocusScan = false;
        this.focusScanField();
    }

    /**
     * GW-5231 - Opens the Assign Work Order scanning experience.
     */
    openAssignWorkOrder() {
        this.mode = MODE_ASSIGN;
        this.clearMessages();
        this.requestScanFocus();
        this.updateWorkspaceTab();
    }

    /**
     * GW-5231 - Clears the session and returns to the action menu.
     */
    returnToMenu() {
        this.mode = MODE_MENU;
        this.scanValue = '';
        this.workspace = undefined;
        this.candidates = [];
        this.selectedRecordIds = [];
        this.clearMessages();
        this.updateWorkspaceTab();
    }

    /**
     * GW-5231 - Stores typed or scanned barcode input.
     * @param {InputEvent} event input event
     */
    handleScanInput(event) {
        this.scanValue = event.target.value;
        this.clearMessages();
    }

    /**
     * GW-5231 - Processes the barcode on Enter/scanner line-feed without a button click.
     * @param {KeyboardEvent} event keydown event
     */
    handleScanKeyDown(event) {
        if (event.key !== 'Enter') {
            return;
        }
        event.preventDefault();
        this.processCurrentScan();
    }

    /**
     * GW-5231 - Sends the current barcode and Work Order context to Apex.
     */
    async processCurrentScan() {
        const value = (this.scanValue || '').trim();
        if (!value || this.isBusy) {
            if (!value) {
                this.errorMessage = 'Scan Barcode is required.';
                this.requestScanFocus();
            }
            return;
        }

        this.isBusy = true;
        this.clearMessages();
        try {
            const result = await processScan({
                currentWorkOrderId: this.workspace?.workOrderId,
                scanValue: value
            });
            this.applyResult(result);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.scanValue = '';
            this.isBusy = false;
            this.requestScanFocus();
        }
    }

    /**
     * GW-5231 - Adds or removes a candidate from the pending assignment selection.
     *           A Work Order holds one Rack and one Service Team, so picking a second
     *           candidate of the same type replaces the earlier pick.
     * @param {MouseEvent} event candidate button click
     */
    toggleCandidate(event) {
        if (this.isBusy) {
            return;
        }
        const { recordId, assignmentType } = event.currentTarget.dataset;
        if (this.selectedRecordIds.includes(recordId)) {
            this.selectedRecordIds = this.selectedRecordIds.filter((id) => id !== recordId);
            return;
        }
        const sameTypeIds = this.candidates
            .filter((candidate) => candidate.assignmentType === assignmentType)
            .map((candidate) => candidate.recordId);
        this.selectedRecordIds = [
            ...this.selectedRecordIds.filter((id) => !sameTypeIds.includes(id)),
            recordId
        ];
    }

    /**
     * GW-5231 - Assigns every selected Rack / Service Team to the current Work Order.
     *           Calls run one at a time because each assignment updates the same Work Order.
     */
    async assignSelectedCandidates() {
        if (this.isAssignDisabled) {
            return;
        }
        const selections = this.candidates.filter((candidate) =>
            this.selectedRecordIds.includes(candidate.recordId)
        );
        this.isBusy = true;
        this.clearMessages();
        try {
            const messages = [];
            let result;
            for (const selection of selections) {
                // eslint-disable-next-line no-await-in-loop
                result = await assignCandidate({
                    workOrderId: this.workspace?.workOrderId,
                    assignmentType: selection.assignmentType,
                    assignmentId: selection.recordId
                });
                if (result?.message) {
                    messages.push(result.message);
                }
            }
            this.selectedRecordIds = [];
            this.candidates = [];
            this.applyResult(result);
            if (messages.length > 0) {
                this.successMessage = messages.join(' ');
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isBusy = false;
            this.requestScanFocus();
        }
    }

    /**
     * GW-5231 - Closes the ambiguity modal without changing the Work Order.
     */
    closeCandidateModal() {
        this.candidates = [];
        this.selectedRecordIds = [];
        this.requestScanFocus();
    }

    /**
     * GW-5231 - Clears Rack__c on the current Work Order.
     */
    async removeRackAssignment() {
        await this.removeAssignment(removeRack);
    }

    /**
     * GW-5231 - Clears ServiceTeam__c on the current Work Order.
     */
    async removeServiceTeamAssignment() {
        await this.removeAssignment(removeServiceTeam);
    }

    /**
     * GW-5231 - Runs one assignment removal and refreshes the displayed state.
     * @param {Function} removalAction imported Apex removal method
     */
    async removeAssignment(removalAction) {
        if (this.isBusy || !this.workspace?.workOrderId) {
            return;
        }
        this.isBusy = true;
        this.clearMessages();
        try {
            const result = await removalAction({
                workOrderId: this.workspace.workOrderId
            });
            this.applyResult(result);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isBusy = false;
            this.requestScanFocus();
        }
    }

    /**
     * GW-5231 - Applies the latest server state and opens choices when needed.
     * @param {object} result Apex scan result
     */
    applyResult(result) {
        this.workspace = result;
        this.candidates = result?.candidates || [];
        this.selectedRecordIds = [];
        this.successMessage = result?.message || '';
    }

    /**
     * GW-5231 - Schedules focus after Lightning finishes rendering.
     */
    requestScanFocus() {
        this._shouldFocusScan = true;
    }

    /**
     * GW-5231 - Places focus in the barcode field for the next scan.
     */
    focusScanField() {
        const input = this.template.querySelector('[data-id="barcode-input"]');
        input?.focus();
    }

    /**
     * GW-5231 - Sets the browser and console tab titles for the current screen.
     */
    async updateWorkspaceTab() {
        const label = this.mode === MODE_ASSIGN ? TAB_LABEL_ASSIGN : TAB_LABEL_MENU;
        document.title = label;

        if (!this.isConsoleNavigation) {
            return;
        }

        try {
            const tabInfo = await getFocusedTabInfo();
            if (!tabInfo?.tabId) {
                return;
            }
            await setTabLabel(tabInfo.tabId, label);
        } catch (error) {
            // Non-console hosts may not support workspace APIs; page title still updates.
        }
    }

    /**
     * GW-5231 - Clears inline status messages before the next action.
     */
    clearMessages() {
        this.errorMessage = '';
        this.successMessage = '';
    }

    /**
     * GW-5231 - Normalizes Lightning/Apex errors for inline display.
     * @param {object} error Lightning error payload
     * @return {string} user-facing error message
     */
    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}