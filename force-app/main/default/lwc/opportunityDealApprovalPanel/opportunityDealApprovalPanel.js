import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, getRecordNotifyChange } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import STAGE_NAME from '@salesforce/schema/Opportunity.StageName';
import DEAL_APPROVAL_STATUS from '@salesforce/schema/Opportunity.DealApprovalStatus__c';
import getApprovalContext from '@salesforce/apex/OppDealApprovalController.getApprovalContext';
import decide from '@salesforce/apex/OppDealApprovalController.decide';

const MODE_SUBMIT = 'Submit';
const MODE_PENDING_APPROVER = 'PendingApprover';
const MODE_PENDING_VIEWER = 'PendingViewer';
const MODE_APPROVED = 'Approved';
const MODE_REJECTED = 'Rejected';

export default class OpportunityDealApprovalPanel extends LightningElement {
    @api recordId;

    context;
    decisionComments = '';
    showRejectModal = false;
    isLoading = false;
    isApproving = false;
    isRejecting = false;
    lastKnownStatus;

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

    get isVisible() {
        return this.context?.showPanel === true;
    }

    get isBusy() {
        return this.isLoading || this.isApproving || this.isRejecting;
    }

    get showDecideActions() {
        return this.context?.canDecide === true && this.context?.mode === MODE_PENDING_APPROVER;
    }

    get hasApprovers() {
        return (this.context?.approvers ?? []).length > 0;
    }

    get approverRows() {
        return (this.context?.approvers ?? []).map((approver, index) => ({
            ...approver,
            rowKey: approver.id || `${approver.userId}-${index}`,
            requiredLabel: approver.required ? 'Yes' : 'No'
        }));
    }

    get rejectionReason() {
        return this.context?.rejectionReason;
    }

    get submissionComments() {
        return this.context?.submissionComments;
    }

    get isRejectDisabled() {
        return this.isBusy || !this.decisionComments?.trim();
    }

    get bannerTitle() {
        switch (this.context?.mode) {
            case MODE_PENDING_APPROVER:
                return 'Approval requested';
            case MODE_PENDING_VIEWER:
                return 'Deal pending approval';
            case MODE_APPROVED:
                return 'Deal internally approved';
            case MODE_REJECTED:
                return 'Deal rejected';
            case MODE_SUBMIT:
                return 'Ready for formal approval';
            default:
                return 'Deal approval';
        }
    }

    get bannerMessage() {
        switch (this.context?.mode) {
            case MODE_PENDING_APPROVER:
                return 'Review the deal and approve or reject. A rejection reason is required if you reject.';
            case MODE_PENDING_VIEWER:
                return 'The Opportunity is locked while designated approvers complete their review in parallel.';
            case MODE_APPROVED:
                return 'All required approvers have approved. This Opportunity may progress to Customer Negotiation.';
            case MODE_REJECTED:
                return 'The deal was returned for rework. Use Submit Deal for Approval after updates.';
            case MODE_SUBMIT:
                return 'Use Submit Deal for Approval to route Deal Desk, BU Leaders, and any additional approvers.';
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

    async loadContext() {
        if (!this.recordId) {
            return;
        }

        this.isLoading = true;
        try {
            this.context = await getApprovalContext({ opportunityId: this.recordId });
            this.lastKnownStatus = this.context?.dealApprovalStatus;
        } catch (error) {
            this.toast('Error loading deal approval', this.reduceErrors(error), 'error');
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
            this.toast('Rejected', 'The deal was returned to the Opportunity Owner for rework.', 'success');
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