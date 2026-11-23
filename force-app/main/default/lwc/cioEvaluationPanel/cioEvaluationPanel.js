import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEvaluations from '@salesforce/apex/CIOEvaluationsController.getEvaluations';
import getFormContext from '@salesforce/apex/CIOEvaluationsController.getFormContext';
import CioEvaluationForm from 'c/cioEvaluationForm';

/**
 * GW-4749 - Complete CIO Questionnaire button, popup, and saved-record table.
 */
export default class CioEvaluationPanel extends LightningElement {
    @api parentWorkOrderId;

    @track rows = [];
    isLoading = false;
    isOpening = false;
    errorMessage = '';
    _workOrderId;

    @api
    get workOrderId() {
        return this._workOrderId;
    }
    set workOrderId(value) {
        const previous = this._workOrderId;
        this._workOrderId = value;
        if (value && value !== previous) {
            this.loadRows();
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get showCompleteButton() {
        return !this.isLoading && !this.hasRows;
    }

    get displayRows() {
        return this.rows.map((row) => ({
            ...row,
            dateDisplay: this.formatDate(row.evaluationDate)
        }));
    }

    async loadRows() {
        if (!this._workOrderId) {
            this.rows = [];
            return;
        }
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const rows = await getEvaluations({ workOrderId: this._workOrderId });
            this.rows = rows || [];
        } catch (error) {
            this.rows = [];
            this.errorMessage = this.resolveError(error, 'Unable to load CIO Evaluations.');
        } finally {
            this.isLoading = false;
        }
    }

    async handleCompleteClick() {
        await this.openForm();
    }

    async handleEditClick(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) {
            return;
        }
        await this.openForm(recordId);
    }

    async openForm(recordId) {
        if (this.isOpening || !this._workOrderId) {
            return;
        }
        this.isOpening = true;
        this.errorMessage = '';
        try {
            const context = await getFormContext({ workOrderId: this._workOrderId });
            const result = await CioEvaluationForm.open({
                size: 'medium',
                description: 'Continuous Improvement Opportunity questionnaire',
                workOrderId: this._workOrderId,
                parentWorkOrderId: context?.parentWorkOrderId || this.parentWorkOrderId,
                recordId: recordId || null,
                recordTypeId: context?.recordTypeId,
                technicianId: context?.technicianId,
                evaluationDate: context?.evaluationDate
            });
            if (result === 'saved') {
                await this.loadRows();
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Saved',
                        message: 'CIO Questionnaire was saved.',
                        variant: 'success'
                    })
                );
            }
        } catch (error) {
            this.errorMessage = this.resolveError(error, 'Unable to open the CIO Questionnaire.');
        } finally {
            this.isOpening = false;
        }
    }

    formatDate(value) {
        if (!value) {
            return '';
        }
        const parts = String(value).split('-');
        if (parts.length !== 3) {
            return value;
        }
        return `${parts[1]}/${parts[2]}/${parts[0]}`;
    }

    resolveError(error, fallback) {
        return error?.body?.message || error?.message || fallback;
    }
}