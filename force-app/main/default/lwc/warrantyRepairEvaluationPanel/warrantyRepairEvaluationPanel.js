import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getWarrantyRepairEvaluations from '@salesforce/apex/WarrantyRepairEvaluationsController.getWarrantyRepairEvaluations';
import getWarrantyRepairEvaluationForm from '@salesforce/apex/WarrantyRepairEvaluationsController.getWarrantyRepairEvaluationForm';
import saveWarrantyRepairEvaluation from '@salesforce/apex/WarrantyRepairEvaluationsController.saveWarrantyRepairEvaluation';
import labelDescribeReasonForReturn from '@salesforce/label/c.WRE_DescribeReasonForReturn';
import labelSignsOfDamageWearFailure from '@salesforce/label/c.WRE_SignsOfDamageWearFailure';
import labelConfirmedCustomerReportedIssue from '@salesforce/label/c.WRE_ConfirmedCustomerReportedIssue';
import labelIssueRelatedToPreviousRepair from '@salesforce/label/c.WRE_IssueRelatedToPreviousRepair';
import labelPreviousWorkPerformed from '@salesforce/label/c.WRE_PreviousWorkPerformed';
import labelWorkPerformedAndRecommendation from '@salesforce/label/c.WRE_WorkPerformedAndRecommendation';
import labelCorrectiveActionTaken from '@salesforce/label/c.WRE_CorrectiveActionTaken';
import labelCorrectiveActionAdditionalDetails from '@salesforce/label/c.WRE_CorrectiveActionAdditionalDetails';
import labelLotNumber from '@salesforce/label/c.WRE_LotNumber';

const YES_VALUE = 'Yes';
const LONG_TEXT_FIELDS = [
    'reasonForReturn',
    'previousWorkPerformed',
    'workPerformedAndRecommendation',
    'correctiveActionAdditionalDetails'
];

export default class WarrantyRepairEvaluationPanel extends LightningElement {
    labelDescribeReasonForReturn = labelDescribeReasonForReturn;
    labelSignsOfDamageWearFailure = labelSignsOfDamageWearFailure;
    labelConfirmedCustomerReportedIssue = labelConfirmedCustomerReportedIssue;
    labelIssueRelatedToPreviousRepair = labelIssueRelatedToPreviousRepair;
    labelPreviousWorkPerformed = labelPreviousWorkPerformed;
    labelWorkPerformedAndRecommendation = labelWorkPerformedAndRecommendation;
    labelCorrectiveActionTaken = labelCorrectiveActionTaken;
    labelCorrectiveActionAdditionalDetails = labelCorrectiveActionAdditionalDetails;
    labelLotNumber = labelLotNumber;

    _workOrderId;
    _initialRows;
    _workOrderLineItemId;
    _allowMultipleEvaluations = false;
    _maxEvaluationCount = 1;
    _embeddedInModal = false;

    @track rows = [];
    @track form;
    isLoadingList = false;
    isLoadingForm = false;
    isSaving = false;
    showForm = false;
    formError = '';
    listError = '';

    @api
    get workOrderId() {
        return this._workOrderId;
    }
    set workOrderId(value) {
        const previous = this._workOrderId;
        this._workOrderId = value;
        if (value && value !== previous) {
            this.bootstrapRows();
        }
    }

    /**
     * Optional Product Serviced WOLI Id — stamps new WREs and filters the related list (GW-3400).
     */
    @api
    get workOrderLineItemId() {
        return this._workOrderLineItemId;
    }
    set workOrderLineItemId(value) {
        const previous = this._workOrderLineItemId;
        this._workOrderLineItemId = value || null;
        if (this._workOrderId && value !== previous) {
            this.bootstrapRows();
        }
    }

    /**
     * When true (Instrument Evaluation), New stays available after the first WRE exists.
     * Device Evaluation leaves this false so New hides once a row exists.
     */
    @api
    get allowMultipleEvaluations() {
        return this._allowMultipleEvaluations === true;
    }
    set allowMultipleEvaluations(value) {
        this._allowMultipleEvaluations = value === true;
    }

    /**
     * Maximum WRE rows allowed for the current context (IE non-asset line quantity).
     */
    @api
    get maxEvaluationCount() {
        return this._maxEvaluationCount;
    }
    set maxEvaluationCount(value) {
        const parsed = Number(value);
        this._maxEvaluationCount =
            Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : 1;
    }

    /**
     * When true (Instrument Evaluation modal), suppresses the DE-style list title on asset /
     * single-qty paths. IE no-asset with line Qty > 1 still shows the related list in-modal.
     */
    @api
    get embeddedInModal() {
        return this._embeddedInModal === true;
    }
    set embeddedInModal(value) {
        this._embeddedInModal = value === true;
    }

    /**
     * Optional preloaded rows from Device Evaluation workspace to avoid an extra round-trip.
     */
    @api
    get initialRows() {
        return this._initialRows;
    }
    set initialRows(value) {
        this._initialRows = value;
        if (Array.isArray(value) && !this.showForm) {
            this.rows = this.filterRowsForContext(value.map((row) => ({ ...row })));
        }
    }

    get hasRows() {
        return Array.isArray(this.rows) && this.rows.length > 0;
    }

    get displayedRows() {
        return (this.rows || []).map((row) => ({
            ...row,
            evaluationDateDisplay: this.formatDate(row.evaluationDate)
        }));
    }

    get showNewButton() {
        if (this.isLoadingList || this.showForm) {
            return false;
        }
        const maxCount = this._maxEvaluationCount || 1;
        if (this.allowMultipleEvaluations) {
            return (this.rows || []).length < maxCount;
        }
        return !this.hasRows;
    }

    /** Instrument Evaluation opens the panel per Item Summary line (modal). */
    get isInstrumentEvaluationContext() {
        return this._workOrderLineItemId != null;
    }

    /** IE no-asset modal when line Qty > 1 — table + New in modal (Josh / GW-3938). */
    get showListInInstrumentEvaluationModal() {
        return (
            this.embeddedInModal &&
            this.allowMultipleEvaluations &&
            (this._maxEvaluationCount || 1) > 1
        );
    }

    /** Device Eval related list; IE no-asset multi-qty modal when WREs already exist. */
    get showListSection() {
        if (!this.hasRows) {
            return false;
        }
        if (this.isInstrumentEvaluationContext) {
            return this.showListInInstrumentEvaluationModal;
        }
        return !this.embeddedInModal;
    }

    /** Device Eval empty state: New button only, left-aligned — no title or empty message. */
    get showStandaloneNewButton() {
        return (
            this.showNewButton &&
            !this.hasRows &&
            !this.isInstrumentEvaluationContext &&
            !this.embeddedInModal
        );
    }

    /** DE list header; IE no-asset multi-qty modal when rows exist. */
    get showNewButtonInListHeader() {
        return (
            this.showNewButton &&
            this.hasRows &&
            ((!this.isInstrumentEvaluationContext && !this.embeddedInModal) ||
                this.showListInInstrumentEvaluationModal)
        );
    }

    get showListHeaderTitle() {
        return !this.embeddedInModal;
    }

    get listHeaderClassName() {
        return this.showListHeaderTitle
            ? 'wre-panel__header'
            : 'wre-panel__header wre-panel__header--actions-only';
    }

    /** IE only — combobox when multiple WREs and list is hidden (single-qty path). */
    get showInstrumentEvaluationSwitcher() {
        return (
            this.isInstrumentEvaluationContext &&
            this.hasRows &&
            this.rows.length > 1 &&
            !this.isLoadingList &&
            !this.showListSection
        );
    }

    get instrumentEvaluationSwitcherOptions() {
        return (this.rows || []).map((row) => ({
            label: row.name || 'Warranty Repair Evaluation',
            value: row.id
        }));
    }

    get instrumentEvaluationSwitcherValue() {
        if (this.form?.id) {
            return this.form.id;
        }
        return this.rows.length > 0 ? this.rows[0].id : null;
    }

    get wreFormClassName() {
        return this.isInstrumentEvaluationContext && !this.showListSection
            ? 'wre-form wre-form--instrument-evaluation'
            : 'wre-form';
    }

    get isBusy() {
        return this.isLoadingList || this.isLoadingForm || this.isSaving;
    }

    get formTitle() {
        return this.form?.id
            ? `Edit Warranty Repair Evaluation ${this.form.name || ''}`.trim()
            : 'New Warranty Repair Evaluation';
    }

    get isCorrectiveActionDetailsRequired() {
        return this.form?.correctiveActionTaken === YES_VALUE;
    }

    get isNcrFieldsRequired() {
        return this.form?.componentNcrCreated === YES_VALUE;
    }

    get isSerialNumberRequired() {
        return this.isAssetBasedPreviousRepairFieldRequired;
    }

    /**
     * Instrument non-asset WREs: previous-repair context fields stay editable but optional.
     */
    get isAssetBasedPreviousRepairFieldRequired() {
        return this.form?.serialNumberRequired === true;
    }

    get labelDeviceOrInstrumentType() {
        return this.form?.useInstrumentTypeLabel === true ? 'Instrument Type' : 'Device Type';
    }

    get showNcrDetails() {
        return this.isNcrFieldsRequired;
    }

    get workOrderDisplay() {
        return this.form?.workOrderNumber || this.form?.workOrderId || '—';
    }

    get parentWorkOrderDisplay() {
        return this.form?.parentWorkOrderNumber || this.form?.parentWorkOrderId || '—';
    }

    get relatedReturnOrderDisplay() {
        return this.form?.relatedReturnOrderNumber || this.form?.relatedReturnOrderId || '—';
    }

    get dateReceivedDisplay() {
        return this.formatDate(this.form?.dateReceived);
    }

    get itemCountDisplay() {
        const value = this.form?.itemCount;
        return value === null || value === undefined || value === '' ? '—' : String(value);
    }

    get customerNumberDisplay() {
        return this.form?.customerNumber || '—';
    }

    connectedCallback() {
        this.bootstrapRows();
    }

    renderedCallback() {
        if (!this.showForm || !this.form) {
            this._appliedLongTextFormKey = null;
            return;
        }
        const formKey = this.form.id || 'new';
        if (this._appliedLongTextFormKey === formKey) {
            return;
        }
        this._appliedLongTextFormKey = formKey;
        LONG_TEXT_FIELDS.forEach((field) => {
            const textarea = this.template.querySelector(`textarea[data-field="${field}"]`);
            if (textarea) {
                textarea.value = this.form[field] || '';
            }
        });
    }

    /**
     * Opens New or edit for the current WOLI context. Item Summary passes a record Id to edit;
     * a null Id means the user clicked New and should land on a blank form (Josh / GW-3938).
     */
    @api
    async openPreferredForm(preferredRecordId) {
        if (!this._workOrderId) {
            return;
        }
        await this.refreshRows();
        if (preferredRecordId) {
            await this.loadForm(preferredRecordId);
            return;
        }
        await this.loadForm(null);
    }

    bootstrapRows() {
        if (!this._workOrderId) {
            return;
        }
        if (Array.isArray(this._initialRows) && !this._workOrderLineItemId) {
            this.rows = this.filterRowsForContext(this._initialRows.map((row) => ({ ...row })));
            return;
        }
        this.refreshRows();
    }

    filterRowsForContext(rows) {
        const list = Array.isArray(rows) ? rows : [];
        if (!this._workOrderLineItemId) {
            return list;
        }
        return list.filter((row) => row.workOrderLineItemId === this._workOrderLineItemId);
    }

    async refreshRows() {
        if (!this._workOrderId) {
            return;
        }
        this.isLoadingList = true;
        this.listError = '';
        try {
            const result = await getWarrantyRepairEvaluations({
                workOrderId: this._workOrderId,
                workOrderLineItemId: this._workOrderLineItemId || null
            });
            this.rows = Array.isArray(result) ? result : [];
        } catch (error) {
            this.listError = this.reduceError(error);
            this.rows = [];
        } finally {
            this.isLoadingList = false;
        }
    }

    async handleNewClick() {
        await this.loadForm(null);
    }

    async handleInstrumentEvaluationSwitcherChange(event) {
        const recordId = event.detail?.value;
        if (!recordId || recordId === this.form?.id) {
            return;
        }
        await this.loadForm(recordId);
    }

    async handleNameClick(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) {
            return;
        }
        await this.loadForm(recordId);
    }

    async loadForm(recordId) {
        if (!this._workOrderId) {
            return;
        }
        this.isLoadingForm = true;
        this.formError = '';
        this.showForm = true;
        try {
            const loaded = await getWarrantyRepairEvaluationForm({
                workOrderId: this._workOrderId,
                recordId,
                workOrderLineItemId: this._workOrderLineItemId || null
            });
            this.form = this.normalizeLoadedForm(loaded);
            if (loaded?.maxEvaluationCount != null) {
                this._maxEvaluationCount = loaded.maxEvaluationCount;
            }
        } catch (error) {
            this.formError = this.reduceError(error);
            this.form = null;
        } finally {
            this.isLoadingForm = false;
        }
    }

    handleCancelForm() {
        const shouldCloseEmbeddedModal = this.embeddedInModal && !this.hasRows;
        this.showForm = false;
        this.form = null;
        this.formError = '';
        if (shouldCloseEmbeddedModal) {
            this.dispatchEvent(new CustomEvent('wreclose'));
        }
    }

    handleFieldChange(event) {
        if (!this.form) {
            return;
        }
        const field = event.currentTarget?.dataset?.field;
        if (!field) {
            return;
        }
        let value = event.detail?.value;
        if (value === undefined) {
            value = event.currentTarget.value;
        }
        this.form = { ...this.form, [field]: value };
    }

    handleUserPickerChange(event) {
        if (!this.form) {
            return;
        }
        const field = event.currentTarget?.dataset?.field;
        if (!field) {
            return;
        }
        const recordId = event.detail?.recordId || null;
        this.form = { ...this.form, [field]: recordId };
    }

    normalizeLoadedForm(loaded) {
        if (!loaded) {
            return null;
        }
        return {
            id: loaded.id,
            name: loaded.name,
            workOrderId: loaded.workOrderId || this._workOrderId,
            workOrderLineItemId:
                loaded.workOrderLineItemId || this._workOrderLineItemId || null,
            workOrderNumber: loaded.workOrderNumber,
            parentWorkOrderId: loaded.parentWorkOrderId,
            parentWorkOrderNumber: loaded.parentWorkOrderNumber,
            relatedReturnOrderId: loaded.relatedReturnOrderId,
            relatedReturnOrderNumber: loaded.relatedReturnOrderNumber,
            customerNumber: loaded.customerNumber,
            dateReceived: loaded.dateReceived,
            itemCount: loaded.itemCount,
            reasonForReturn: loaded.reasonForReturn,
            signsOfDamageWearFailure: loaded.signsOfDamageWearFailure,
            originalReturnOrder: loaded.originalReturnOrder,
            previousRepairQcTechnicianId: loaded.previousRepairQcTechnicianId,
            previousRepairDate: loaded.previousRepairDate,
            deviceType: loaded.deviceType,
            manufacturerOfTheDeviceInstrument: loaded.manufacturerOfTheDeviceInstrument,
            modelNumberOfTheDeviceInstrument: loaded.modelNumberOfTheDeviceInstrument,
            serialNumberOfTheDeviceInstrument: loaded.serialNumberOfTheDeviceInstrument,
            disposition: loaded.disposition,
            confirmedCustomerReportedIssue: loaded.confirmedCustomerReportedIssue,
            issueRelatedToPreviousRepair: loaded.issueRelatedToPreviousRepair,
            previousWorkPerformed: loaded.previousWorkPerformed,
            workPerformedAndRecommendation: loaded.workPerformedAndRecommendation,
            technicianPerformingWorkId: loaded.technicianPerformingWorkId,
            technicianSignOffDate: loaded.technicianSignOffDate,
            teamLeaderId: loaded.teamLeaderId,
            teamLeaderSignOffDate: loaded.teamLeaderSignOffDate,
            autoclaved: loaded.autoclaved,
            correctiveActionTaken: loaded.correctiveActionTaken,
            correctiveActionAdditionalDetails: loaded.correctiveActionAdditionalDetails,
            contributingFactor: loaded.contributingFactor,
            componentNcrCreated: loaded.componentNcrCreated,
            ncrNumber: loaded.ncrNumber,
            partNumber: loaded.partNumber,
            lotNumber: loaded.lotNumber,
            serialNumberRequired: loaded.serialNumberRequired === true,
            useInstrumentTypeLabel: loaded.useInstrumentTypeLabel === true,
            maxEvaluationCount: loaded.maxEvaluationCount,
            signsOfDamageOptions: loaded.signsOfDamageOptions,
            dispositionOptions: loaded.dispositionOptions,
            yesNoOptions: loaded.yesNoOptions,
            autoclavedOptions: loaded.autoclavedOptions,
            contributingFactorOptions: loaded.contributingFactorOptions
        };
    }

    coalesceFieldValue(domValue, formValue) {
        if (domValue === undefined || domValue === null) {
            return formValue;
        }
        if (typeof domValue === 'string' && domValue.trim() === '') {
            return formValue;
        }
        return domValue;
    }

    readComponentValue(fieldEl) {
        if (!fieldEl) {
            return undefined;
        }
        if (fieldEl.tagName === 'LIGHTNING-RECORD-PICKER') {
            return fieldEl.value || null;
        }
        return fieldEl.value;
    }

    readEditableFieldsFromDom() {
        const values = {};
        this.template.querySelectorAll('[data-field]').forEach((fieldEl) => {
            const key = fieldEl.dataset.field;
            if (!key) {
                return;
            }
            values[key] = this.readComponentValue(fieldEl);
        });
        return values;
    }

    /**
     * @description Reads current input values into draft state before validate/save.
     */
    syncFormFromDom() {
        if (!this.form) {
            return;
        }
        const domValues = this.readEditableFieldsFromDom();
        const merged = { ...this.form };
        Object.keys(domValues).forEach((key) => {
            merged[key] = this.coalesceFieldValue(domValues[key], merged[key]);
        });
        this.form = merged;
    }

    async handleSave() {
        if (!this.form || this.isSaving) {
            return;
        }
        this.syncFormFromDom();
        const payload = this.buildSavePayload();
        this.isSaving = true;
        this.formError = '';
        try {
            const updatedRows = await saveWarrantyRepairEvaluation({
                workOrderId: this._workOrderId,
                formJson: JSON.stringify(payload)
            });
            this.rows = Array.isArray(updatedRows) ? updatedRows : [];
            this.showForm = false;
            this.form = null;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Warranty Repair Evaluation saved.',
                    variant: 'success'
                })
            );
            this.dispatchEvent(
                new CustomEvent('wresaved', {
                    detail: { rows: this.rows }
                })
            );
        } catch (error) {
            this.formError = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    /**
     * @description Sends editable field values only; Work Order Id comes from the panel context.
     */
    buildSavePayload() {
        const form = this.form || {};
        const domValues = this.readEditableFieldsFromDom();
        const field = (key) => this.coalesceFieldValue(domValues[key], form[key]);
        return {
            id: form.id,
            workOrderId: form.workOrderId || this._workOrderId,
            workOrderLineItemId:
                form.workOrderLineItemId || this._workOrderLineItemId || null,
            parentWorkOrderId: form.parentWorkOrderId,
            relatedReturnOrderId: form.relatedReturnOrderId,
            customerNumber: form.customerNumber,
            dateReceived: form.dateReceived,
            itemCount: form.itemCount,
            reasonForReturn: field('reasonForReturn'),
            signsOfDamageWearFailure: field('signsOfDamageWearFailure'),
            originalReturnOrder: field('originalReturnOrder'),
            previousRepairQcTechnicianId: field('previousRepairQcTechnicianId'),
            previousRepairDate: field('previousRepairDate'),
            deviceType: field('deviceType'),
            manufacturerOfTheDeviceInstrument: field('manufacturerOfTheDeviceInstrument'),
            modelNumberOfTheDeviceInstrument: field('modelNumberOfTheDeviceInstrument'),
            serialNumberOfTheDeviceInstrument: field('serialNumberOfTheDeviceInstrument'),
            disposition: field('disposition'),
            confirmedCustomerReportedIssue: field('confirmedCustomerReportedIssue'),
            issueRelatedToPreviousRepair: field('issueRelatedToPreviousRepair'),
            previousWorkPerformed: field('previousWorkPerformed'),
            workPerformedAndRecommendation: field('workPerformedAndRecommendation'),
            technicianPerformingWorkId: field('technicianPerformingWorkId'),
            technicianSignOffDate: field('technicianSignOffDate'),
            teamLeaderId: field('teamLeaderId'),
            teamLeaderSignOffDate: field('teamLeaderSignOffDate'),
            autoclaved: field('autoclaved'),
            correctiveActionTaken: field('correctiveActionTaken'),
            correctiveActionAdditionalDetails: field('correctiveActionAdditionalDetails'),
            contributingFactor: field('contributingFactor'),
            componentNcrCreated: field('componentNcrCreated'),
            ncrNumber: field('ncrNumber'),
            partNumber: field('partNumber'),
            lotNumber: field('lotNumber')
        };
    }

    formatDate(value) {
        if (!value) {
            return '—';
        }
        try {
            const date = typeof value === 'string' ? new Date(`${value}T00:00:00`) : new Date(value);
            if (Number.isNaN(date.getTime())) {
                return String(value);
            }
            return date.toLocaleDateString();
        } catch (e) {
            return String(value);
        }
    }

    reduceError(error) {
        if (!error) {
            return 'Unexpected error.';
        }
        if (typeof error === 'string') {
            return error;
        }
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error.body?.message) {
            return error.body.message;
        }
        if (error.message) {
            return error.message;
        }
        return 'Unexpected error.';
    }
}