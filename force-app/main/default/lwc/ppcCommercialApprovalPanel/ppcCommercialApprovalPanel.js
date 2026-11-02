import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, getRecordNotifyChange } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import STAGE_NAME from '@salesforce/schema/Opportunity.StageName';
import DEAL_APPROVAL_STATUS from '@salesforce/schema/Opportunity.DealApprovalStatus__c';
import getApprovalContext from '@salesforce/apex/PpcCommercialApprovalService.getApprovalContext';
import decide from '@salesforce/apex/PpcCommercialApprovalService.decide';

/**
 * Record-page panel for Pay Per Click commercial approval.
 * Shows the current approval state and, for the assigned approver, Approve and Reject.
 * Submit itself stays on the Submit Deal for Approval action. This component only
 * loads the approval context and records the approver's decision.
 */
const MODE_SUBMIT = 'Submit';
const MODE_PENDING_APPROVER = 'PendingApprover';
const MODE_PENDING_VIEWER = 'PendingViewer';
const MODE_APPROVED = 'Approved';
const MODE_REJECTED = 'Rejected';

export default class PpcCommercialApprovalPanel extends LightningElement {
    /** Opportunity Id from the record page. */
    @api recordId;

    context;
    decisionComments = '';
    showRejectModal = false;
    isLoading = false;
    isApproving = false;
    isRejecting = false;
    lastKnownStatus;

    /** Reloads the panel when Deal Approval Status changes on the Opportunity. */
    @wire(getRecord, { recordId: '$recordId', fields: [STAGE_NAME, DEAL_APPROVAL_STATUS] })
    wiredOpportunity(result) {
        if (!result.data) {
            return;
        }
        const status = getFieldValue(result.data, DEAL_APPROVAL_STATUS);
        if (status !== this.lastKnownStatus) {
            this.lastKnownStatus = status;
            this.loadContext();
        }
    }

    connectedCallback() {
        this.loadContext();
    }

    /** Panel is hidden unless this Opportunity is in the Pay Per Click approval process. */
    get isVisible() {
        return this.context?.showPanel === true;
    }

    get isBusy() {
        return this.isLoading || this.isApproving || this.isRejecting;
    }

    /** Approve and Reject are shown only to the approver whose decision is pending. */
    get showDecideActions() {
        return this.context?.canDecide === true && this.context?.mode === MODE_PENDING_APPROVER;
    }

    get hasHistory() {
        return (this.context?.history ?? []).length > 0;
    }

    get historyRows() {
        return this.toRows(this.context?.history);
    }

    get isRejectDisabled() {
        return this.isBusy || !this.decisionComments?.trim();
    }

    get bannerTitle() {
        switch (this.context?.mode) {
            case MODE_PENDING_APPROVER:
                return 'Approval requested';
            case MODE_PENDING_VIEWER:
                return 'Pending commercial approval';
            case MODE_APPROVED:
                return 'Commercially approved';
            case MODE_REJECTED:
                return 'Commercial approval rejected';
            case MODE_SUBMIT:
                return 'Ready for commercial approval';
            default:
                return 'Commercial approval';
        }
    }

    get bannerMessage() {
        switch (this.context?.mode) {
            case MODE_PENDING_APPROVER:
                return 'Review the Opportunity and financial assessment, then approve or reject. A rejection reason is required if you reject.';
            case MODE_PENDING_VIEWER:
                return 'The selected approver users review this Opportunity in parallel.';
            case MODE_APPROVED:
                return 'The required commercial approvers have approved. The decision is stored on this Opportunity.';
            case MODE_REJECTED:
                return 'The Opportunity was returned for rework. Update it, then submit again.';
            case MODE_SUBMIT:
                return 'Use Submit Deal for Approval to choose the approver users.';
            default:
                return '';
        }
    }

    get bannerIcon() {
        if (this.context?.mode === MODE_APPROVED) {
            return 'utility:success';
        }
        if (this.context?.mode === MODE_REJECTED) {
            return 'utility:error';
        }
        return 'utility:warning';
    }

    get bannerIconVariant() {
        if (this.context?.mode === MODE_APPROVED) {
            return 'success';
        }
        if (this.context?.mode === MODE_REJECTED) {
            return 'error';
        }
        return 'warning';
    }

    get notificationClass() {
        const variant =
            this.context?.mode === MODE_APPROVED
                ? 'slds-scoped-notification_success'
                : this.context?.mode === MODE_REJECTED
                  ? 'slds-scoped-notification_error'
                  : 'slds-scoped-notification_warning';
        return `slds-scoped-notification ${variant} slds-m-bottom_small`;
    }

    toRows(approvers) {
        return (approvers ?? []).map((approver, index) => ({
            ...approver,
            requiredLabel: approver.required ? 'Yes' : 'No',
            rowKey: approver.id || `${approver.userId}-${index}`
        }));
    }

    /** Loads banner text, approver history, and whether the current user can decide. */
    async loadContext() {
        if (!this.recordId) {
            return;
        }
        this.isLoading = true;
        try {
            this.context = await getApprovalContext({ opportunityId: this.recordId });
            this.lastKnownStatus = this.context?.dealApprovalStatus;
        } catch (error) {
            this.toast('Error loading commercial approval', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleDecisionCommentsChange(event) {
        this.decisionComments = event.detail.value;
    }

    handleOpenRejectModal() {
        this.showRejectModal = true;
    }

    handleCloseRejectModal() {
        this.showRejectModal = false;
    }

    /** Records an approval for the current approver and refreshes the Opportunity. */
    async handleApproveClick() {
        this.isApproving = true;
        try {
            this.context = await decide({
                approverRecordId: this.context.currentApproverRecordId,
                decision: 'Approved',
                comments: this.decisionComments
            });
            this.lastKnownStatus = this.context?.dealApprovalStatus;
            this.toast('Approved', 'Your approval was recorded.', 'success');
            this.notifyRecordChange();
        } catch (error) {
            this.toast('Unable to approve', this.reduceErrors(error), 'error');
        } finally {
            this.isApproving = false;
        }
    }

    /** Records a rejection. A rejection reason is required before this can run. */
    async handleReject() {
        this.isRejecting = true;
        try {
            this.context = await decide({
                approverRecordId: this.context.currentApproverRecordId,
                decision: 'Rejected',
                comments: this.decisionComments
            });
            this.showRejectModal = false;
            this.decisionComments = '';
            this.lastKnownStatus = this.context?.dealApprovalStatus;
            this.toast('Rejected', 'The Opportunity was returned to the owner for rework.', 'success');
            this.notifyRecordChange();
        } catch (error) {
            this.toast('Unable to reject', this.reduceErrors(error), 'error');
        } finally {
            this.isRejecting = false;
        }
    }

    notifyRecordChange() {
        getRecordNotifyChange([{ recordId: this.recordId }]);
        this.dispatchEvent(new RefreshEvent());
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceErrors(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        if (error.body?.message) {
            return error.body.message;
        }
        if (error.message) {
            return error.message;
        }
        return 'Unknown error';
    }
}