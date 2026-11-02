import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getWorkspace from '@salesforce/apex/QuoteApproveRejectController.getWorkspace';
import saveDecisions from '@salesforce/apex/QuoteApproveRejectController.saveDecisions';
import saveComment from '@salesforce/apex/QuoteApproveRejectController.saveComment';

const STATUS_APPROVED = 'Approved';
const STATUS_REJECTED = 'Rejected';

export default class ApproveRejectQuote extends LightningElement {
    isLoading = true;
    isSaving = false;
    workspace;
    errorMessage;
    commentLineId;
    commentDraft = '';
    showCommentModal = false;

    workOrderId;
    hasLoadStarted = false;
    hasExpandedModal = false;

    /**
     * The quick action framework can set recordId after the component is constructed,
     * so the load waits for the first non-empty value instead of running in connectedCallback.
     */
    @api
    get recordId() {
        return this.workOrderId;
    }

    set recordId(value) {
        this.workOrderId = value;
        this.loadWorkspaceOnce();
    }

    @wire(CurrentPageReference)
    handlePageReference(pageReference) {
        if (this.workOrderId || !pageReference?.attributes?.recordId) {
            return;
        }
        this.workOrderId = pageReference.attributes.recordId;
        this.loadWorkspaceOnce();
    }

    renderedCallback() {
        this.expandActionModal();
    }

    /**
     * The quick action modal lives outside this component's shadow root, so its width is
     * stretched here instead of through the component stylesheet.
     */
    expandActionModal() {
        if (this.hasExpandedModal) {
            return;
        }
        const container = this.template.host?.closest?.('.slds-modal__container');
        if (!container) {
            return;
        }
        container.style.width = '95vw';
        container.style.maxWidth = '95vw';

        const content = container.querySelector('.slds-modal__content');
        if (content) {
            content.style.maxHeight = '80vh';
        }
        this.hasExpandedModal = true;
    }

    loadWorkspaceOnce() {
        if (!this.workOrderId || this.hasLoadStarted) {
            return;
        }
        this.hasLoadStarted = true;
        this.loadWorkspace();
    }

    get hasWorkspace() {
        return this.workspace != null && !this.errorMessage;
    }

    get lines() {
        return this.workspace?.lines || [];
    }

    get displayLines() {
        return this.lines.map((line) => {
            const isApproved = line.selectedDecision === STATUS_APPROVED;
            const isRejected = line.selectedDecision === STATUS_REJECTED;
            return {
                ...line,
                estimatePriceDisplay: this.formatCurrency(line.estimatePrice),
                turnTimeDisplay: line.turnTime == null ? '' : String(line.turnTime),
                scheduledShipDateDisplay: line.scheduledShipDate || '',
                isApproved,
                isRejected,
                approveCellClass: isApproved
                    ? 'decision-cell decision-cell_approve selected'
                    : 'decision-cell decision-cell_approve',
                rejectCellClass: isRejected
                    ? 'decision-cell decision-cell_reject selected'
                    : 'decision-cell decision-cell_reject'
            };
        });
    }

    get hasLines() {
        return this.lines.length > 0;
    }

    get hasNoLines() {
        return !this.hasLines;
    }

    get estimateTotalDisplay() {
        return this.formatCurrency(this.workspace?.estimateTotal);
    }

    get isBusy() {
        return this.isLoading || this.isSaving;
    }

    async loadWorkspace() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            this.workspace = await getWorkspace({ workOrderId: this.workOrderId });
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            this.workspace = undefined;
        } finally {
            this.isLoading = false;
        }
    }

    handleApproveAll() {
        this.applyDecisionToAll(STATUS_APPROVED);
    }

    handleRejectAll() {
        this.applyDecisionToAll(STATUS_REJECTED);
    }

    handleApproveRow(event) {
        this.setLineDecision(
            event.currentTarget.dataset.id,
            event.currentTarget.checked ? STATUS_APPROVED : null
        );
    }

    handleRejectRow(event) {
        this.setLineDecision(
            event.currentTarget.dataset.id,
            event.currentTarget.checked ? STATUS_REJECTED : null
        );
    }

    applyDecisionToAll(status) {
        if (!this.workspace?.lines) {
            return;
        }
        this.workspace = {
            ...this.workspace,
            lines: this.workspace.lines.map((line) => ({
                ...line,
                selectedDecision: status
            }))
        };
    }

    setLineDecision(quoteLineItemId, status) {
        this.workspace = {
            ...this.workspace,
            lines: this.workspace.lines.map((line) =>
                line.quoteLineItemId === quoteLineItemId
                    ? { ...line, selectedDecision: status }
                    : line
            )
        };
    }

    openCommentModal(event) {
        const quoteLineItemId = event.currentTarget.dataset.id;
        const line = this.lines.find((item) => item.quoteLineItemId === quoteLineItemId);
        this.commentLineId = quoteLineItemId;
        this.commentDraft = line?.quoteComments || '';
        this.showCommentModal = true;
    }

    closeCommentModal() {
        this.showCommentModal = false;
        this.commentLineId = undefined;
        this.commentDraft = '';
    }

    handleCommentChange(event) {
        this.commentDraft = event.target.value;
    }

    handleCommentKeyDown(event) {
        if (event.key === 'Escape') {
            this.closeCommentModal();
        }
    }

    async handleCommentSave() {
        this.isSaving = true;
        try {
            const saved = await saveComment({
                quoteLineItemId: this.commentLineId,
                comments: this.commentDraft
            });
            this.workspace = {
                ...this.workspace,
                lines: this.workspace.lines.map((line) =>
                    line.quoteLineItemId === this.commentLineId
                        ? {
                              ...line,
                              quoteComments: saved,
                              hasComments: saved != null && saved !== ''
                          }
                        : line
                )
            };
            this.closeCommentModal();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to save comment',
                    message: this.reduceError(error),
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    async handleSave() {
        const decisions = this.lines
            .filter(
                (line) =>
                    line.selectedDecision === STATUS_APPROVED ||
                    line.selectedDecision === STATUS_REJECTED
            )
            .map((line) => ({
                quoteLineItemId: line.quoteLineItemId,
                status: line.selectedDecision
            }));

        if (decisions.length === 0) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Nothing to save',
                    message: 'Select Approve or Reject on at least one line before saving.',
                    variant: 'warning'
                })
            );
            return;
        }

        this.isSaving = true;
        try {
            this.workspace = await saveDecisions({
                workOrderId: this.workOrderId,
                decisions
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Quote updated',
                    message: 'Approve/Reject decisions were saved.',
                    variant: 'success'
                })
            );
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to save',
                    message: this.reduceError(error),
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    formatCurrency(value) {
        if (value == null) {
            return '$0.00';
        }
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(value);
    }

    reduceError(error) {
        if (typeof error === 'string') {
            return error;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}