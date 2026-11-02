import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    setTabLabel
} from 'lightning/platformWorkspaceApi';
import USER_ID from '@salesforce/user/Id';
import initializeInspection from '@salesforce/apex/QualityInspectionController.initializeInspection';
import saveInspection from '@salesforce/apex/QualityInspectionController.saveInspection';
import saveNcr from '@salesforce/apex/QualityInspectionController.saveNcr';
import getOptions from '@salesforce/apex/QualityInspectionController.getOptions';
import getNcrReasonOptions from '@salesforce/apex/QualityInspectionController.getNcrReasonOptions';
import getNcrLocationOptions from '@salesforce/apex/QualityInspectionController.getNcrLocationOptions';
import getRiskTexts from '@salesforce/apex/QualityInspectionController.getRiskTexts';
import occurrenceRiskTable from '@salesforce/resourceUrl/QualityInspectionOccurrenceRiskTable';
import severityRiskTable from '@salesforce/resourceUrl/QualityInspectionSeverityRiskTable';

const EMPTY_OPTIONS = Object.freeze([]);
const EMPTY_RISK_TEXTS = Object.freeze({ severityTexts: {}, occurrenceTexts: {} });
const TAB_LABEL = 'Quality Inspection';
const SCAN_FIELD_LABEL = 'Work Order Id / Number';
const SCAN_FIELD_PLACEHOLDER = 'Scan or enter Work Order Id / Number';
const QC_FAIL_NCR_REQUIRED_MESSAGE = 'An NCR is required to set Sub Status = QC Fail';
const NCR_MODAL_CREATE = 'create';
const NCR_MODAL_ADD_LINE = 'addLine';
const NCR_MODAL_EDIT_LINE = 'editLine';
const NCR_MODAL_EDIT_HEADER = 'editHeader';

export default class QualityInspection extends LightningElement {
    workOrderInput = '';
    workspace;
    options = {};
    riskTexts = EMPTY_RISK_TEXTS;
    isBusy = false;
    errorMessage = '';
    showNcrModal = false;
    showRiskHelp = false;
    riskHelpTitle = '';
    riskHelpImage;
    riskHelpAlt = '';
    ncrForm;
    ncrModalMode;
    ncrFileReportId;
    showWoliPicker = false;
    woliPickerError = '';
    dependentNcrReasonOptions = [];
    dependentNcrLocationOptions = [];
    isConsoleNavigation = false;

    @wire(IsConsoleNavigation)
    wiredIsConsoleNavigation(result) {
        this.isConsoleNavigation = result?.data === true;
        this.updateWorkspaceTab();
    }

    connectedCallback() {
        this.updateWorkspaceTab();
    }

    renderedCallback() {
        this.resizeRiskJustification();
    }

    @wire(getRiskTexts)
    handleRiskTexts({ data, error }) {
        if (data) {
            this.riskTexts = data;
        } else if (error) {
            this.showError('Unable to load risk justification text', error);
        }
    }

    @wire(getOptions)
    handleOptions({ data, error }) {
        if (data) {
            this.options = data;
        } else if (error) {
            this.showError('Unable to load form options', error);
        }
    }

    get isScanScreen() {
        return !this.workspace;
    }

    get rootClass() {
        return this.isScanScreen
            ? 'quality-inspection-root quality-inspection-root_scan slds-p-around_medium'
            : 'quality-inspection-root';
    }

    get scanFieldLabel() {
        return SCAN_FIELD_LABEL;
    }

    get scanFieldPlaceholder() {
        return SCAN_FIELD_PLACEHOLDER;
    }

    get isInspectionScreen() {
        return Boolean(this.workspace);
    }

    /**
     * GW-4750 - True when the Work Order has a Continuous Improvement Opportunity.
     */
    get showCioIndicator() {
        return this.workspace?.continuousImprovementOpportunity === true;
    }

    /**
     * GW-5696 - True when the Work Order is marked Ship Complete.
     */
    get showShipCompleteIndicator() {
        return this.workspace?.shipComplete === true;
    }

    get hasNcrLines() {
        return Boolean(this.workspace?.ncrLines?.length);
    }

    get hasNcrs() {
        return Boolean(this.workspace?.ncrs?.length || this.workspace?.hasNcr);
    }

    get ncrFileReportIdsKey() {
        return (this.workspace?.ncrs || [])
            .map((report) => report.reportId)
            .filter((reportId) => reportId)
            .join(',');
    }

    get hasInstrumentLines() {
        return Boolean(this.workspace?.instrumentLines?.length);
    }

    get modalTitle() {
        if (this.ncrModalMode === NCR_MODAL_EDIT_HEADER) {
            return 'Edit NCR';
        }
        if (this.ncrModalMode === NCR_MODAL_EDIT_LINE || this.ncrForm?.lineId) {
            return 'Edit NCR Line';
        }
        if (this.ncrModalMode === NCR_MODAL_ADD_LINE) {
            return 'Create NCR Line';
        }
        return 'Create NCR';
    }

    get showNcrHeaderSection() {
        return (
            this.ncrModalMode === NCR_MODAL_CREATE ||
            this.ncrModalMode === NCR_MODAL_EDIT_HEADER
        );
    }

    get showNcrLineSection() {
        return this.ncrModalMode !== NCR_MODAL_EDIT_HEADER;
    }

    get showWorkOrderLineItemPicker() {
        return (
            this.ncrModalMode === NCR_MODAL_CREATE &&
            this.workspace?.showInstrumentInformation === true
        );
    }

    get availableWoliRows() {
        const selectedId = this.ncrForm?.workOrderLineItemId;
        const usedLineIds = new Set(
            (this.workspace?.ncrs || [])
                .map((report) => report.workOrderLineItemId)
                .filter((lineId) => lineId && String(lineId) !== String(selectedId))
                .map((lineId) => String(lineId))
        );
        return (this.workspace?.instrumentLines || [])
            .filter((line) => !usedLineIds.has(String(line.lineId)))
            .map((line) => ({
                ...line,
                quantityDisplay: line.quantity == null ? '' : String(line.quantity),
                repairSummary: line.repairSummary || [],
                rowClass:
                    selectedId && String(line.lineId) === String(selectedId)
                        ? 'slds-is-selected'
                        : ''
            }));
    }

    get hasAvailableWoliRows() {
        return this.availableWoliRows.length > 0;
    }

    get selectedWoliDisplay() {
        const line = this.selectedInstrumentLine;
        if (!line) {
            return '';
        }
        return [line.lineNumber, line.productName].filter(Boolean).join(' — ');
    }

    get woliPickerFieldClass() {
        return this.woliPickerError
            ? 'slds-form-element slds-has-error woli-picker-field'
            : 'slds-form-element woli-picker-field';
    }

    get selectedInstrumentLine() {
        const selectedId = this.ncrForm?.workOrderLineItemId;
        if (!selectedId) {
            return null;
        }
        return (
            (this.workspace?.instrumentLines || []).find(
                (line) => String(line.lineId) === String(selectedId)
            ) || null
        );
    }

    get selectedNcrReport() {
        const reportId = this.ncrForm?.reportId;
        if (!reportId) {
            return null;
        }
        return (
            (this.workspace?.ncrs || []).find(
                (report) => String(report.reportId) === String(reportId)
            ) || null
        );
    }

    get ncrModalAssetName() {
        if (this.workspace?.showAssetInformation) {
            return this.workspace.assetName || '';
        }
        return '';
    }

    get ncrModalSerialNumber() {
        return (
            this.selectedNcrReport?.serialNumber ||
            this.selectedInstrumentLine?.serialNumber ||
            (this.workspace?.showAssetInformation ? this.workspace.serialNumber : '') ||
            ''
        );
    }

    get ncrModalProductName() {
        return (
            this.selectedNcrReport?.productName ||
            this.selectedInstrumentLine?.productName ||
            (this.workspace?.showAssetInformation ? this.workspace.productName : '') ||
            ''
        );
    }

    get ncrModalProductLine() {
        return (
            this.ncrForm?.productLine ||
            this.selectedNcrReport?.productLine ||
            this.selectedInstrumentLine?.productLine ||
            this.workspace?.productLine ||
            ''
        );
    }

    get ncrModalModel() {
        return (
            this.selectedNcrReport?.model ||
            this.selectedInstrumentLine?.model ||
            (this.workspace?.showAssetInformation ? this.workspace.model : '') ||
            ''
        );
    }

    get ncrModalManufacturer() {
        return (
            this.selectedNcrReport?.manufacturer ||
            this.selectedInstrumentLine?.manufacturer ||
            (this.workspace?.showAssetInformation ? this.workspace.manufacturer : '') ||
            ''
        );
    }

    get subStatusOptions() {
        return this.options.subStatus || EMPTY_OPTIONS;
    }

    get ncrSourceOptions() {
        return this.options.ncrSource || EMPTY_OPTIONS;
    }

    get repairRelatedOptions() {
        return this.options.repairRelated || EMPTY_OPTIONS;
    }

    get ncrReasonOptions() {
        return this.dependentNcrReasonOptions;
    }

    get ncrLocationOptions() {
        return this.dependentNcrLocationOptions;
    }

    get ncrStatusOptions() {
        return this.options.ncrStatus || EMPTY_OPTIONS;
    }

    get severityOptions() {
        return this.options.severityRating || EMPTY_OPTIONS;
    }

    get severityJustificationOptions() {
        return this.options.severityJustification || EMPTY_OPTIONS;
    }

    get occurrenceOptions() {
        return this.options.occurrenceRating || EMPTY_OPTIONS;
    }

    get isNewNcr() {
        return this.ncrModalMode === NCR_MODAL_CREATE;
    }

    get departmentOptions() {
        return this.workspace?.departmentOptions || EMPTY_OPTIONS;
    }

    get workOrderLineItemDisplayName() {
        return (
            this.selectedNcrReport?.workOrderLineItemName ||
            this.selectedInstrumentLine?.lineNumber ||
            this.selectedInstrumentLine?.productName ||
            this.workspace?.defaultWorkOrderLineItemProductName ||
            this.workspace?.productName ||
            ''
        );
    }

    get calculatedRiskRating() {
        const severity = this.ncrForm?.severityRating;
        const occurrence = this.ncrForm?.occurrenceRating;
        if (!severity || !occurrence) {
            return '';
        }
        if (
            (severity === 'Low' && occurrence !== 'High') ||
            (severity === 'Medium' && occurrence === 'Low')
        ) {
            return 'Low';
        }
        if (
            (severity === 'Low' && occurrence === 'High') ||
            (severity === 'Medium' && occurrence === 'Medium') ||
            (severity === 'High' && occurrence === 'Low')
        ) {
            return 'Medium';
        }
        return 'High';
    }

    get formRiskRatingClass() {
        const rating = this.calculatedRiskRating;
        if (rating === 'Low') {
            return 'risk-rating-input risk-rating-input_low';
        }
        if (rating === 'Medium') {
            return 'risk-rating-input risk-rating-input_medium';
        }
        if (rating === 'High') {
            return 'risk-rating-input risk-rating-input_high';
        }
        return 'risk-rating-input';
    }

    riskRatingClassName(rating) {
        if (rating === 'Low') {
            return 'risk-low';
        }
        if (rating === 'Medium') {
            return 'risk-medium';
        }
        if (rating === 'High') {
            return 'risk-high';
        }
        return '';
    }

    applyWorkspace(workspace) {
        const ncrs = workspace?.ncrs || (workspace?.ncr ? [workspace.ncr] : []);
        const reportIds = new Set(ncrs.map((report) => report.reportId).filter((id) => id));
        if (!this.ncrFileReportId || !reportIds.has(this.ncrFileReportId)) {
            this.ncrFileReportId = ncrs[0]?.reportId || null;
        }
        if (!workspace?.ncrLines) {
            this.workspace = {
                ...workspace,
                ncrs,
                instrumentLines: workspace?.instrumentLines || []
            };
            return;
        }
        this.workspace = {
            ...workspace,
            ncrs,
            instrumentLines: workspace.instrumentLines || [],
            ncrLines: workspace.ncrLines.map((line) => ({
                ...line,
                riskRatingClass: this.riskRatingClassName(line.riskRating)
            }))
        };
    }

    resizeRiskJustification() {
        const field = this.template.querySelector('.risk-justification');
        if (!field) {
            return;
        }
        const text = this.calculatedRiskJustification || '';
        if (field.value !== text) {
            field.value = text;
        }
        field.style.height = 'auto';
        field.style.height = `${field.scrollHeight}px`;
    }

    get calculatedRiskJustification() {
        const severity = this.ncrForm?.severityRating;
        const occurrence = this.ncrForm?.occurrenceRating;
        if (!severity || !occurrence) {
            return this.ncrForm?.riskJustification || '';
        }
        const severityKey = `${severity}|${this.ncrForm.severityJustification}`;
        const severityText = this.riskTexts?.severityTexts?.[severityKey] || '';
        const occurrenceText = this.riskTexts?.occurrenceTexts?.[occurrence] || '';
        return (
            `Severity = ${severity} - ${this.ncrForm.severityJustification || ''}; ${severityText}` +
            ` Occurrence = ${occurrence}; ${occurrenceText}`
        );
    }

    handleScanChange(event) {
        this.workOrderInput = event.detail?.value || '';
        this.errorMessage = '';
    }

    handleScanContinue(event) {
        const input = (event.detail?.value || this.workOrderInput || '').trim();
        if (!input || this.isBusy) {
            return;
        }
        this.workOrderInput = input;
        this.handleContinue();
    }

    async handleContinue() {
        this.isBusy = true;
        this.errorMessage = '';
        try {
            this.applyWorkspace(
                await initializeInspection({
                    workOrderInput: this.workOrderInput.trim()
                })
            );
            this.updateWorkspaceTab();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isBusy = false;
        }
    }

    handleWorkspaceChange(event) {
        this.workspace = {
            ...this.workspace,
            [event.target.name]: event.target.value
        };
    }

    handleNcrHeaderChange(event) {
        const fieldName = event.target.name;
        this.workspace = {
            ...this.workspace,
            ncr: {
                ...this.workspace.ncr,
                [fieldName]: event.target.value
            }
        };
    }

    handleCancel() {
        this.returnToScan();
    }

    async handleQuickSave() {
        await this.saveWorkspace(false);
    }

    async handleSaveAndClose() {
        await this.saveWorkspace(true);
    }

    async saveWorkspace(closeAfterSave, ncrInput = null) {
        if (
            this.workspace.subStatus === 'QC Fail' &&
            !this.workspace.hasNcr &&
            !(this.workspace.ncrs || []).length
        ) {
            this.showError('Unable to save Quality Inspection', QC_FAIL_NCR_REQUIRED_MESSAGE);
            return;
        }
        this.isBusy = true;
        try {
            this.applyWorkspace(
                await saveInspection({
                    workOrderId: this.workspace.workOrderId,
                    subStatus: this.workspace.subStatus,
                    pressureGaugeSerialNumber: this.workspace.pressureGaugeSerialNumber,
                    inspectionNotes: this.workspace.inspectionNotes,
                    ncrInput
                })
            );
            this.showToast('Saved', 'Quality Inspection was saved.', 'success');
            if (closeAfterSave) {
                this.returnToScan();
            }
        } catch (error) {
            this.showError('Unable to save Quality Inspection', error);
        } finally {
            this.isBusy = false;
        }
    }

    returnToScan() {
        this.workspace = null;
        this.workOrderInput = '';
        this.errorMessage = '';
        this.showNcrModal = false;
        this.showRiskHelp = false;
        this.ncrForm = null;
        this.ncrModalMode = null;
        this.ncrFileReportId = null;
        this.showWoliPicker = false;
        this.woliPickerError = '';
        this.updateWorkspaceTab();
    }

    /**
     * Sets the browser title and Lightning console tab label.
     * Scan screen: "Quality Inspection". Open WO: "00001107 | Quality Inspection".
     */
    async updateWorkspaceTab() {
        const workOrderNumber = (this.workspace?.workOrderNumber || '').toString().trim();
        const label = workOrderNumber ? `${workOrderNumber} | ${TAB_LABEL}` : TAB_LABEL;
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

    handleNcrTakePhoto(event) {
        const reportId = event.currentTarget.dataset.id;
        if (!reportId) {
            return;
        }
        this.ncrFileReportId = reportId;
        // Wait one tick so c-ncr-file-list binds the capture report Id.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            const fileList = this.template.querySelector('c-ncr-file-list');
            if (fileList) {
                fileList.openCamera();
            }
        }, 0);
    }

    buildEmptyNcrLineForm(report) {
        const instrumentLine = this.selectedInstrumentForReport(report);
        return {
            reportId: report?.reportId || null,
            workOrderLineItemId:
                report?.workOrderLineItemId ||
                this.workspace.defaultWorkOrderLineItemId ||
                null,
            reportNumber: report?.reportNumber || '',
            headerNcrStatus: report?.ncrStatus || 'Open',
            departmentId: report?.departmentId || this.workspace.serviceTeamId || '',
            lineId: null,
            repairRelated: '',
            ncrDate: this.today(),
            initiatedById: USER_ID,
            qualityInspectorId: USER_ID,
            productLine:
                report?.productLine ||
                instrumentLine?.productLine ||
                this.workspace.productLine ||
                '',
            ncrReason: '',
            ncrLocationContext: '',
            comments: '',
            ncrSource: '',
            ncrStatus: 'Open',
            severityRating: '',
            severityJustification: '',
            occurrenceRating: '',
            quantityRejected: null,
            capaNumber: '',
            ncrOwner: 'Internal',
            ncrDescription: '',
            workOrderLineItemName: report?.workOrderLineItemName || '',
            serialNumber: report?.serialNumber || instrumentLine?.serialNumber || '',
            productName: report?.productName || instrumentLine?.productName || '',
            model: report?.model || instrumentLine?.model || '',
            manufacturer: report?.manufacturer || instrumentLine?.manufacturer || ''
        };
    }

    selectedInstrumentForReport(report) {
        const lineId = report?.workOrderLineItemId;
        if (!lineId) {
            return null;
        }
        return (
            (this.workspace?.instrumentLines || []).find((line) => line.lineId === lineId) ||
            null
        );
    }

    findNcrReport(reportId) {
        return (this.workspace?.ncrs || []).find((report) => report.reportId === reportId);
    }

    async openNewNcrModal() {
        this.ncrModalMode = NCR_MODAL_CREATE;
        this.ncrForm = this.buildEmptyNcrLineForm(null);
        if (this.workspace?.showInstrumentInformation === true) {
            this.ncrForm = {
                ...this.ncrForm,
                workOrderLineItemId: null
            };
            this.woliPickerError = '';
        }
        const instrumentLine = this.selectedInstrumentLine;
        if (instrumentLine) {
            this.ncrForm = {
                ...this.ncrForm,
                productLine: instrumentLine.productLine || this.ncrForm.productLine
            };
        }
        await this.loadNcrReasonOptions();
        this.showNcrModal = true;
    }

    async openAddNcrLineModal(event) {
        const report = this.findNcrReport(event.currentTarget.dataset.id);
        if (!report) {
            return;
        }
        this.ncrModalMode = NCR_MODAL_ADD_LINE;
        this.ncrForm = this.buildEmptyNcrLineForm(report);
        await this.loadNcrReasonOptions();
        this.showNcrModal = true;
    }

    async openEditNcrHeaderModal(event) {
        const report = this.findNcrReport(event.currentTarget.dataset.id);
        if (!report) {
            return;
        }
        this.ncrModalMode = NCR_MODAL_EDIT_HEADER;
        this.ncrForm = {
            ...report,
            headerNcrStatus: report.ncrStatus || 'Open',
            departmentId: report.departmentId || this.workspace.serviceTeamId || ''
        };
        this.showNcrModal = true;
    }

    async openEditNcrModal(event) {
        const line = this.workspace.ncrLines.find(
            (candidate) => candidate.lineId === event.currentTarget.dataset.id
        );
        const report = this.findNcrReport(line?.reportId) || this.workspace.ncr;
        this.ncrModalMode = NCR_MODAL_EDIT_LINE;
        this.ncrForm = {
            ...report,
            ...line,
            headerNcrStatus: report?.ncrStatus || 'Open',
            ncrOwner: 'Internal'
        };
        await this.loadNcrReasonOptions();
        await this.loadNcrLocationOptions();
        this.showNcrModal = true;
    }

    closeNcrModal() {
        this.showNcrModal = false;
        this.showWoliPicker = false;
        this.woliPickerError = '';
        this.ncrForm = null;
        this.ncrModalMode = null;
    }

    openWoliPicker() {
        this.woliPickerError = '';
        this.showWoliPicker = true;
    }

    closeWoliPicker() {
        this.showWoliPicker = false;
    }

    handleWoliSelectClick(event) {
        event.stopPropagation();
        this.selectWorkOrderLineItem(event.currentTarget.dataset.id);
    }

    handleWoliRowClick(event) {
        this.selectWorkOrderLineItem(event.currentTarget.dataset.id);
    }

    async selectWorkOrderLineItem(lineId) {
        if (!lineId) {
            return;
        }
        this.ncrForm = {
            ...this.ncrForm,
            workOrderLineItemId: lineId,
            ncrReason: '',
            ncrLocationContext: ''
        };
        const instrumentLine = this.selectedInstrumentLine;
        this.ncrForm = {
            ...this.ncrForm,
            productLine: instrumentLine?.productLine || this.workspace.productLine || ''
        };
        this.dependentNcrLocationOptions = [];
        this.woliPickerError = '';
        this.showWoliPicker = false;
        await this.loadNcrReasonOptions();
    }

    async handleNcrChange(event) {
        const fieldName = event.target.name;
        this.ncrForm = {
            ...this.ncrForm,
            [fieldName]: event.target.value
        };
        if (fieldName === 'workOrderLineItemId') {
            const instrumentLine = this.selectedInstrumentLine;
            this.ncrForm = {
                ...this.ncrForm,
                productLine: instrumentLine?.productLine || this.workspace.productLine || '',
                ncrReason: '',
                ncrLocationContext: ''
            };
            this.dependentNcrLocationOptions = [];
            await this.loadNcrReasonOptions();
        } else if (fieldName === 'productLine') {
            this.ncrForm = {
                ...this.ncrForm,
                ncrReason: '',
                ncrLocationContext: ''
            };
            this.dependentNcrLocationOptions = [];
            await this.loadNcrReasonOptions();
        } else if (fieldName === 'ncrReason') {
            this.ncrForm = {
                ...this.ncrForm,
                ncrLocationContext: ''
            };
            await this.loadNcrLocationOptions();
        }
    }

    async loadNcrReasonOptions() {
        if (!this.ncrForm?.productLine) {
            this.dependentNcrReasonOptions = [];
            return;
        }
        try {
            this.dependentNcrReasonOptions = await getNcrReasonOptions({
                productLine: this.ncrForm.productLine
            });
        } catch (error) {
            this.showError('Unable to load NCR Reasons', error);
        }
    }

    async loadNcrLocationOptions() {
        if (!this.ncrForm?.ncrReason) {
            this.dependentNcrLocationOptions = [];
            return;
        }
        try {
            this.dependentNcrLocationOptions = await getNcrLocationOptions({
                ncrReason: this.ncrForm.ncrReason
            });
        } catch (error) {
            this.showError('Unable to load NCR Locations', error);
        }
    }

    handleInitiatedByChange(event) {
        this.ncrForm = {
            ...this.ncrForm,
            initiatedById: event.detail.recordId
        };
    }

    handleInspectorChange(event) {
        this.ncrForm = {
            ...this.ncrForm,
            qualityInspectorId: event.detail.recordId
        };
    }

    async handleNcrSave() {
        const inputs = [...this.template.querySelectorAll('.ncr-required')];
        const isValid = inputs.reduce(
            (valid, input) => input.reportValidity() && valid,
            true
        );
        if (!isValid) {
            return;
        }
        if (this.showWorkOrderLineItemPicker && !this.ncrForm?.workOrderLineItemId) {
            this.woliPickerError = 'Complete this field.';
            return;
        }
        if (this.ncrModalMode === NCR_MODAL_EDIT_HEADER) {
            await this.saveWorkspace(false, {
                reportId: this.ncrForm.reportId,
                ncrType: this.ncrForm.ncrType,
                ncrStatus: this.ncrForm.ncrStatus || this.ncrForm.headerNcrStatus,
                departmentId: this.ncrForm.departmentId || ''
            });
            this.closeNcrModal();
            return;
        }
        this.isBusy = true;
        const requestedSubStatus = this.workspace.subStatus;
        const isCreateHeader = this.ncrModalMode === NCR_MODAL_CREATE;
        try {
            const savedWorkspace = await saveNcr({
                workOrderId: this.workspace.workOrderId,
                reportInput: {
                    reportId: isCreateHeader ? null : this.ncrForm.reportId,
                    workOrderLineItemId: this.ncrForm.workOrderLineItemId,
                    ncrStatus: isCreateHeader ? 'Open' : null,
                    departmentId: isCreateHeader ? this.ncrForm.departmentId || '' : null
                },
                inspectionDraft: {
                    subStatus: requestedSubStatus,
                    pressureGaugeSerialNumber: this.workspace.pressureGaugeSerialNumber,
                    inspectionNotes: this.workspace.inspectionNotes
                },
                lineInput: {
                    lineId: this.ncrForm.lineId,
                    repairRelated: this.ncrForm.repairRelated,
                    ncrDate: this.ncrForm.ncrDate,
                    initiatedById: this.ncrForm.initiatedById,
                    qualityInspectorId: this.ncrForm.qualityInspectorId,
                    productLine: this.ncrForm.productLine,
                    ncrReason: this.ncrForm.ncrReason,
                    ncrLocationContext: this.ncrForm.ncrLocationContext,
                    comments: this.ncrForm.comments,
                    ncrSource: this.ncrForm.ncrSource,
                    ncrStatus: this.ncrForm.ncrStatus,
                    severityRating: this.ncrForm.severityRating,
                    severityJustification: this.ncrForm.severityJustification,
                    occurrenceRating: this.ncrForm.occurrenceRating,
                    quantityRejected: this.ncrForm.quantityRejected,
                    capaNumber: this.ncrForm.capaNumber,
                    ncrOwner: 'Internal',
                    ncrDescription: this.ncrForm.ncrDescription
                }
            });
            this.applyWorkspace(savedWorkspace);
            this.closeNcrModal();
            if (requestedSubStatus === 'QC Pass' && savedWorkspace.subStatus !== 'QC Pass') {
                this.showToast(
                    'NCR saved',
                    'The NCR line was saved. QC Pass was not applied because an NCR line is still Open.',
                    'warning'
                );
            } else {
                this.showToast('Saved', 'NCR information was saved.', 'success');
            }
        } catch (error) {
            this.showError('Unable to save NCR information', error);
        } finally {
            this.isBusy = false;
        }
    }

    openSeverityRiskHelp() {
        this.openRiskHelp(
            'Risk Analysis Table 2',
            severityRiskTable,
            'Severity risk analysis table'
        );
    }

    openOccurrenceRiskHelp() {
        this.openRiskHelp(
            'Risk Analysis Table',
            occurrenceRiskTable,
            'Occurrence risk analysis table'
        );
    }

    openRiskHelp(title, imageUrl, altText) {
        this.riskHelpTitle = title;
        this.riskHelpImage = imageUrl;
        this.riskHelpAlt = altText;
        this.showRiskHelp = true;
    }

    closeRiskHelp() {
        this.showRiskHelp = false;
    }

    today() {
        return new Date().toISOString().slice(0, 10);
    }

    showError(title, error) {
        this.showToast(title, this.reduceError(error), 'error', 'sticky');
    }

    showToast(title, message, variant, mode = 'dismissible') {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode }));
    }

    reduceError(error) {
        if (typeof error === 'string' && error.trim()) {
            return error;
        }
        return (
            error?.body?.message ||
            error?.body?.pageErrors?.[0]?.message ||
            error?.message ||
            'An unexpected error occurred.'
        );
    }
}