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
import loadSignatureOverride from '@salesforce/apex/RepairCoordinatorActionsController.loadSignatureOverride';
import addRepairSignature from '@salesforce/apex/RepairCoordinatorActionsController.addRepairSignature';
import removeRepairSignature from '@salesforce/apex/RepairCoordinatorActionsController.removeRepairSignature';
import searchSignatureTechnicians from '@salesforce/apex/RepairCoordinatorActionsController.searchSignatureTechnicians';

const MODE_MENU = 'menu';
const MODE_ASSIGN = 'assign';
const MODE_SUMMARY = 'summary';
const MODE_OVERRIDE = 'override';
const TAB_LABEL_MENU = 'Repair Coordinator Actions';
const TAB_LABEL_ASSIGN = 'Assign Work Order';
const TAB_LABEL_SUMMARY = 'View Work Order Summary';
const TAB_LABEL_OVERRIDE = 'Override Repair Signatures';
const LAYOUT_DEVICE = 'device';

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
    signatureWorkspace;
    showAddSignature = false;
    signatureLineItemId;
    technicianUserId;
    technicianName = '';
    technicianSearch = '';
    technicianOptions = [];
    modalError = '';

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
     * GW-5287 - Returns true while Assign Work Order is displayed.
     */
    get isAssign() {
        return this.mode === MODE_ASSIGN;
    }

    /**
     * GW-5287 - Returns true while View Work Order Summary is displayed.
     */
    get isSummary() {
        return this.mode === MODE_SUMMARY;
    }

    /**
     * GW-5310 - Returns true while Override Repair Signatures is displayed.
     */
    get isOverride() {
        return this.mode === MODE_OVERRIDE;
    }

    /**
     * GW-5310 - Returns true after a Work Order with signatures has been loaded.
     */
    get hasSignatureWorkOrder() {
        return Boolean(this.signatureWorkspace?.workOrderId);
    }

    /**
     * GW-5310 - Device Work Orders use the Device Evaluation Work Performed columns.
     */
    get isDeviceTable() {
        return (
            this.signatureWorkspace?.tableLayout === LAYOUT_DEVICE &&
            this.workPerformedRows.length > 0
        );
    }

    /**
     * GW-5310 - Instrument Work Orders use the Instrument Evaluation Work Performed columns.
     */
    get isInstrumentTable() {
        return (
            this.hasSignatureWorkOrder &&
            this.signatureWorkspace?.tableLayout !== LAYOUT_DEVICE &&
            this.workPerformedRows.length > 0
        );
    }

    /**
     * GW-5310 - Repair Code rows for the loaded Work Order.
     */
    get workPerformedRows() {
        return this.signatureWorkspace?.rows || [];
    }

    /**
     * GW-5310 - Save stays disabled until a Repair Center technician is selected.
     */
    get isSaveSignatureDisabled() {
        return this.isBusy || !this.technicianUserId;
    }

    /**
     * GW-5310 - Widens the page when the Work Performed table is on screen.
     */
    get pageShellClass() {
        return this.isOverride ? 'page-shell page-shell_wide' : 'page-shell';
    }

    /**
     * GW-5310 - Returns true when the technician search returned choices.
     */
    get hasTechnicianOptions() {
        return this.technicianOptions.length > 0;
    }

    /**
     * GW-5310 - Returns true when the loaded Work Order has no Repair Code lines.
     */
    get hasNoRepairCodes() {
        return this.hasSignatureWorkOrder && this.workPerformedRows.length === 0;
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
        const scanMode = this.mode === MODE_ASSIGN || this.mode === MODE_OVERRIDE;
        if (!this._shouldFocusScan || !scanMode || this.showCandidateModal || this.showAddSignature) {
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
     * GW-5287 - Opens the View Work Order Summary experience.
     */
    openViewWorkOrderSummary() {
        this.mode = MODE_SUMMARY;
        this.clearMessages();
        this.updateWorkspaceTab();
    }

    /**
     * GW-5310 - Opens the Override Repair Signatures scanning experience.
     */
    openOverrideSignatures() {
        this.mode = MODE_OVERRIDE;
        this.signatureWorkspace = undefined;
        this.closeAddSignature();
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
        this.signatureWorkspace = undefined;
        this.closeAddSignature();
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

        if (this.mode === MODE_OVERRIDE) {
            await this.processSignatureScan(value);
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
     * GW-5310 - Loads Work Performed for the scanned Work Order, or shows the validation error.
     * @param {string} value scanned Work Order Id or number
     */
    async processSignatureScan(value) {
        this.isBusy = true;
        this.clearMessages();
        this.closeAddSignature();
        try {
            this.signatureWorkspace = await loadSignatureOverride({ scanValue: value });
        } catch (error) {
            this.signatureWorkspace = undefined;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.scanValue = '';
            this.isBusy = false;
            this.requestScanFocus();
        }
    }

    /**
     * GW-5310 - Deletes the Team Member signature and refreshes the table.
     * @param {MouseEvent} event trash button click
     */
    async handleRemoveSignature(event) {
        const signatureId = event.currentTarget.dataset.signatureId;
        if (this.isBusy || !signatureId || !this.signatureWorkspace?.workOrderId) {
            return;
        }
        this.isBusy = true;
        this.clearMessages();
        try {
            this.signatureWorkspace = await removeRepairSignature({
                workOrderId: this.signatureWorkspace.workOrderId,
                signatureId
            });
        } catch (error) {
            const message = this.reduceError(error);
            if (message === 'The selected Work Order does not contain signatures for override.') {
                this.signatureWorkspace = undefined;
            }
            this.errorMessage = message;
        } finally {
            this.isBusy = false;
            this.requestScanFocus();
        }
    }

    /**
     * GW-5310 - Opens the technician lookup for one Repair Code line.
     * @param {MouseEvent} event Add Signature click
     */
    async openAddSignature(event) {
        if (this.isBusy) {
            return;
        }
        this.signatureLineItemId = event.currentTarget.dataset.lineId;
        this.technicianUserId = undefined;
        this.technicianName = '';
        this.technicianSearch = '';
        this.technicianOptions = [];
        this.modalError = '';
        this.showAddSignature = true;
        await this.searchTechnicians('');
    }

    /**
     * GW-5310 - Closes the technician popup without saving.
     */
    closeAddSignature() {
        this.showAddSignature = false;
        this.signatureLineItemId = undefined;
        this.technicianUserId = undefined;
        this.technicianName = '';
        this.technicianSearch = '';
        this.technicianOptions = [];
        this.modalError = '';
    }

    /**
     * GW-5310 - Stores technician search text and refreshes the filtered list.
     * @param {InputEvent} event search input
     */
    async handleTechnicianSearch(event) {
        this.technicianSearch = event.target.value;
        this.technicianUserId = undefined;
        this.technicianName = '';
        await this.searchTechnicians(this.technicianSearch);
    }

    /**
     * GW-5310 - Selects a technician from the Repair Center results.
     * @param {MouseEvent} event result click
     */
    selectTechnician(event) {
        this.technicianUserId = event.currentTarget.dataset.userId;
        this.technicianName = event.currentTarget.dataset.userName;
        this.technicianSearch = this.technicianName;
        this.technicianOptions = [];
        this.modalError = '';
    }

    /**
     * GW-5310 - Creates the Team Member signature and refreshes the line.
     */
    async saveSignature() {
        if (this.isSaveSignatureDisabled) {
            this.modalError = 'Technician is required.';
            return;
        }
        this.isBusy = true;
        this.modalError = '';
        try {
            this.signatureWorkspace = await addRepairSignature({
                workOrderId: this.signatureWorkspace.workOrderId,
                workOrderLineItemId: this.signatureLineItemId,
                technicianUserId: this.technicianUserId
            });
            this.closeAddSignature();
            this.requestScanFocus();
        } catch (error) {
            this.modalError = this.reduceError(error);
        } finally {
            this.isBusy = false;
        }
    }

    /**
     * GW-5310 - Loads technicians whose Service Resource Repair Center matches the Work Order.
     * @param {string} searchTerm name filter
     */
    async searchTechnicians(searchTerm) {
        if (!this.signatureWorkspace?.workOrderId) {
            this.technicianOptions = [];
            return;
        }
        try {
            const options = await searchSignatureTechnicians({
                workOrderId: this.signatureWorkspace.workOrderId,
                searchTerm
            });
            this.technicianOptions = (options || []).map((option) => ({
                ...option,
                userId: option.userId,
                name: option.name
            }));
        } catch (error) {
            this.technicianOptions = [];
            this.modalError = this.reduceError(error);
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
        let label = TAB_LABEL_MENU;
        if (this.mode === MODE_ASSIGN) {
            label = TAB_LABEL_ASSIGN;
        } else if (this.mode === MODE_SUMMARY) {
            label = TAB_LABEL_SUMMARY;
        } else if (this.mode === MODE_OVERRIDE) {
            label = TAB_LABEL_OVERRIDE;
        }

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