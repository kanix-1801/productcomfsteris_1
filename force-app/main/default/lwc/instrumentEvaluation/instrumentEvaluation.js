/**
 * GW-3400 - Instrument Evaluation: draft Add Items / Item Summary / Asset Repair Codes.
 */
import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import currentUserId from '@salesforce/user/Id';
import USER_NAME_FIELD from '@salesforce/schema/User.Name';
import initializeEvaluation from '@salesforce/apex/InstrumentEvaluationController.initializeEvaluation';
import saveWorkOrderFields from '@salesforce/apex/InstrumentEvaluationController.saveWorkOrderFields';
import getEvalCategories from '@salesforce/apex/InstrumentEvaluationController.getEvalCategories';
import getProductsForEvalCategory from '@salesforce/apex/InstrumentEvaluationController.getProductsForEvalCategory';
import getRepairCodesForProduct from '@salesforce/apex/InstrumentEvaluationController.getRepairCodesForProduct';
import completeDraftItems from '@salesforce/apex/InstrumentEvaluationController.completeDraftItems';
import saveDraftItems from '@salesforce/apex/InstrumentEvaluationController.saveDraftItems';
import returnToEvaluation from '@salesforce/apex/InstrumentEvaluationController.returnToEvaluation';
import getEvaluationItems from '@salesforce/apex/InstrumentEvaluationController.getEvaluationItems';
import getReturnOrderLineAssignment from '@salesforce/apex/InstrumentEvaluationController.getReturnOrderLineAssignment';
import getRepairSignatures from '@salesforce/apex/InstrumentEvaluationController.getRepairSignatures';
import addRepairSignature from '@salesforce/apex/InstrumentEvaluationController.addRepairSignature';
import signAllRepairCodes from '@salesforce/apex/InstrumentEvaluationController.signAllRepairCodes';
import removeRepairSignature from '@salesforce/apex/InstrumentEvaluationController.removeRepairSignature';
import stageEvaluationPhoto from '@salesforce/apex/DeviceEvaluationController.stageEvaluationPhoto';
import renameStagedEvaluationPhoto from '@salesforce/apex/DeviceEvaluationController.renameStagedEvaluationPhoto';
import deleteStagedEvaluationPhoto from '@salesforce/apex/DeviceEvaluationController.deleteStagedEvaluationPhoto';
import removeEvaluationPhoto from '@salesforce/apex/InstrumentEvaluationController.removeEvaluationPhoto';
import getWarrantyRepairEvaluations from '@salesforce/apex/DeviceEvaluationController.getWarrantyRepairEvaluations';

const MODE_SCAN = 'scan';
const BROWSER_TAB_LABEL = 'Instrument Evaluation & Repair';
const CONTAMINATION_REQUIRED_MESSAGE =
    'Please navigate to the Contamination Information section under the Work Order Details tab and specify what is contaminated.';
const CONTAMINATION_CHECKBOX_FIELDS = [
    'isInsertionTubeChannelDistalEnd',
    'isElevatorIrrigationChannel',
    'isAuxiliaryWaterPort',
    'isBiopsyPort',
    'isAirWaterPort',
    'isSuctionPort',
    'isLightGuideTubes',
    'isAirWaterConnectors',
    'isEyePiece',
    'isShaft',
    'isPowerCord',
    'isInstrument',
    'isLockingMechanism',
    'isFootPedal',
    'isOphthalmic'
];
const IMAGE_EXTENSIONS = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp']);
const DOC_TYPE_BY_EXTENSION = {
    pdf: 'doctype:pdf',
    doc: 'doctype:word',
    docx: 'doctype:word',
    xls: 'doctype:excel',
    xlsx: 'doctype:excel',
    csv: 'doctype:csv',
    txt: 'doctype:txt',
    mp4: 'doctype:video',
    mov: 'doctype:video',
    png: 'doctype:image',
    jpg: 'doctype:image',
    jpeg: 'doctype:image',
    gif: 'doctype:image',
    webp: 'doctype:image',
    bmp: 'doctype:image'
};
const MODE_WORKSPACE = 'workspace';
const MODE_SUMMARY = 'summary';
const TAB_WO_DETAILS = 'workOrderDetails';
const TAB_ASSET = 'assetInformation';
const TAB_ADD_ITEMS = 'addItems';
const TAB_REPAIR_CODES = 'repairCodes';
const TAB_PREFERENCES = 'customerPreferences';
const TAB_NOTES = 'evaluationNotes';
const TAB_ITEM_SUMMARY = 'itemSummary';
const TAB_WORK_PERFORMED = 'workPerformed';
const WIZARD_CATEGORY = 'category';
const WIZARD_PRODUCT = 'product';
const MODAL_ADD = 'add';
const MODAL_EDIT = 'edit';
const MODAL_CLONE = 'clone';
const SCAN_FIELD_LABEL = 'Work Order Id / Number';
const SCAN_FIELD_PLACEHOLDER = 'Scan or enter Work Order Id / Number';
const ADD_ITEMS_BLOCKED_MESSAGE =
    'Items cannot be added during Repair when a re-estimate is required. If changes are needed, please Return to Eval so updates can be made and a new estimate sent for approval.';
const MODAL_CODES_LOCKED_MESSAGE =
    'Item Quantity and Repair Codes cannot be edited during Repair when a re-estimate is required. If changes are needed, please Return to Eval so updates can be made and a new estimate sent for approval.';
const ESTIMATE_OA = 'Order Acknowledgement';
const ESTIMATE_PRE_APPROVED = 'Pre-Approved';
const ESTIMATE_REQUIRED = 'Estimate Required';
const STATUS_EVALUATE_QUOTE = 'Evaluate & Quote';
const STATUS_REPAIR = 'Repair';
const WOLI_STATUS_APPROVED = 'Approved';
const WOLI_STATUS_WAITING_APPROVAL = 'Waiting for Approval';
const WOLI_STATUS_REJECTED = 'Rejected';
const REPAIR_UNSIGNED_MESSAGE =
    'You cannot complete repair until all repair codes have been signed.';
const RO_LINE_REQUIRED_MESSAGE =
    'Please identify the RO line each item corresponds to before completing evaluation/repair.';
const FILE_ACCEPT = '.jpg,.jpeg,.png,.gif,.bmp,.webp,.mp4,.mov,.pdf,.doc,.docx,.xls,.xlsx';
const PHOTO_TARGET_MODAL = 'modal';
const PHOTO_TARGET_ASSET = 'asset';

export default class InstrumentEvaluation extends LightningElement {
    mode = MODE_SCAN;
    workOrderInput = '';
    isLoading = false;
    errorMessage = '';
    workspaceError = '';
    selectedTab = TAB_WO_DETAILS;
    turnTimeInputValue = '';
    quantityReceivedInputValue = '';
    @track workspace;
    @track draftEntries = [];
    @track warrantyRepairRows = [];
    wizardStep = WIZARD_CATEGORY;
    evalCategories = [];
    products = [];
    categoryCodes = [];
    serviceCodes = [];
    selectedEvalCategory = '';
    selectedProduct = null;
    selectedRepairCodeIds = [];
    itemQuantity = 1;
    modalOpen = false;
    modalMode = MODAL_ADD;
    modalEntryId = null;
    modalProduct = null;
    modalQuantity = 1;
    modalSelectedCodeIds = [];
    modalCategoryCodes = [];
    wreModalOpen = false;
    wreModalWoliId = null;
    wreModalAllowMultiple = false;
    wreModalMaxCount = 1;
    vendorModalOpen = false;
    vendorModalEntryId = null;
    @track vendorModalValue = {};
    modalVendorProcessingRequired = false;
    modalVendorWorkOrderLocked = false;
    modalServiceCodes = [];
    @track modalPhotos = [];
    modalError = '';
    modalBusy = false;
    deleteConfirmEntryId = null;
    assetSelectedCodeIds = [];
    @track assetPhotos = [];
    assetError = '';
    draftsCommitted = false;
    @track repairSignatures = [];
    /** Client-only signatures for draft repair codes (no WOLI yet). Persisted on Save/Complete. */
    @track stagedRepairSignatures = [];
    currentUserName = '';
    roLineModalOpen = false;
    roLineModalEntryId = null;
    roLineReturnOrderNumber = '';
    @track roLineOptions = [];
    roLineModalError = '';

    fileAccept = FILE_ACCEPT;
    isPhotoModalOpen = false;
    photoModalTarget = PHOTO_TARGET_MODAL;
    @track cameraOptions = [];
    @track deletingDocumentIds = new Set();
    @track thumbnailFallbackIds = new Set();
    selectedCameraId = '';
    cameraError = '';
    isCameraStarting = false;
    isCameraActive = false;
    isCapturing = false;
    isUploadingFiles = false;
    mediaStream;
    videoEl;
    canvasEl;

    _resizeBound;
    _heightFrame;
    _entrySeq = 0;

    /**
     * GW-3400 - Registers resize listeners used to lock workspace height.
     */
    connectedCallback() {
        this._resizeBound = () => this.scheduleWorkspaceHeightSync();
        window.addEventListener('resize', this._resizeBound);
        this.updateBrowserTitle();
    }

    /**
     * Sets the OS/browser window title (e.g. "00000927 | Instrument Evaluation & Repair").
     * @param {string} [workOrderNumber] Work Order number when evaluation is open
     */
    updateBrowserTitle(workOrderNumber) {
        const wo = (workOrderNumber || '').toString().trim();
        document.title = wo ? `${wo} | ${BROWSER_TAB_LABEL}` : BROWSER_TAB_LABEL;
    }

    @wire(getRecord, { recordId: currentUserId, fields: [USER_NAME_FIELD] })
    wiredCurrentUser({ data }) {
        if (data?.fields?.Name?.value) {
            this.currentUserName = data.fields.Name.value;
        }
    }

    /**
     * GW-3400 - Syncs sticky-header height and Sub Status after each render.
     */
    renderedCallback() {
        this.classList.toggle('is-evaluation', this.isEvaluationShellMode);
        this.syncSubStatusSelectValue();
        this.scheduleWorkspaceHeightSync();
    }

    /**
     * GW-3400 - Clears height listeners when the host is destroyed.
     */
    disconnectedCallback() {
        this.classList.remove('is-evaluation');
        this.stopCameraStream();
        this.clearWorkspaceHeight();
        if (this._resizeBound) {
            window.removeEventListener('resize', this._resizeBound);
        }
        if (this._heightFrame) {
            cancelAnimationFrame(this._heightFrame);
            this._heightFrame = undefined;
        }
    }

    get scanFieldLabel() {
        return SCAN_FIELD_LABEL;
    }

    get scanFieldPlaceholder() {
        return SCAN_FIELD_PLACEHOLDER;
    }

    get isScanMode() {
        return this.mode === MODE_SCAN;
    }

    get isWorkspaceMode() {
        return this.mode === MODE_WORKSPACE;
    }

    get isSummaryMode() {
        return this.mode === MODE_SUMMARY;
    }

    /** Workspace chrome (tabs or Evaluation Summary). */
    get isEvaluationShellMode() {
        return this.isWorkspaceMode || this.isSummaryMode;
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

    get isBusy() {
        return this.isLoading;
    }

    get rootClass() {
        return this.isEvaluationShellMode
            ? 'instrument-evaluation-root instrument-evaluation-root_eval'
            : 'instrument-evaluation-root instrument-evaluation-root_scan slds-p-around_medium';
    }

    get workOrderId() {
        return this.workspace?.workOrderId;
    }

    get assetId() {
        return this.workspace?.assetId;
    }

    get hasProductLink() {
        return Boolean(this.workspace?.productId);
    }

    get productRecordUrl() {
        return this.workspace?.productId ? `/${this.workspace.productId}` : '';
    }

    get productDisplayName() {
        return this.workspace?.productName || 'Product';
    }

    get subStatusOptions() {
        return this.workspace?.subStatusOptions || [];
    }

    get showContaminatedWarning() {
        const subStatus = this.workspace?.subStatus;
        return typeof subStatus === 'string' && subStatus.toLowerCase().includes('contaminat');
    }

    get contaminationValue() {
        return this.workspace?.contamination;
    }

    get woInfoStatus() {
        return this.displayWoInfoText(this.workspace?.status);
    }

    get woInfoRepairWarranty() {
        return this.displayWoInfoText(this.workspace?.repairWarranty);
    }

    get woInfoDescription() {
        return this.displayWoInfoText(this.workspace?.description);
    }

    get woInfoEstimateRequired() {
        return this.displayWoInfoText(this.workspace?.estimateRequired);
    }

    get woInfoCustomerPo() {
        return this.displayWoInfoText(this.workspace?.customerPo);
    }

    displayWoInfoText(value) {
        return value == null || value === '' ? '' : String(value);
    }

    get hasAsset() {
        return this.workspace?.hasAsset === true;
    }

    get canAddItems() {
        return this.workspace?.canAddItems === true;
    }

    get canEditEntries() {
        if (!this.workspace) {
            return false;
        }
        if (this.workspace.status === STATUS_EVALUATE_QUOTE) {
            return true;
        }
        const estimate = this.workspace.estimateRequired;
        return estimate === ESTIMATE_OA || estimate === ESTIMATE_PRE_APPROVED;
    }

    get cloneEnabled() {
        return this.canEditEntries && this.hasAsset !== true;
    }

    get isWoDetailsTab() {
        return this.selectedTab === TAB_WO_DETAILS;
    }

    get isAssetTab() {
        return this.selectedTab === TAB_ASSET;
    }

    get isPreferencesTab() {
        return this.selectedTab === TAB_PREFERENCES;
    }

    get isNotesTab() {
        return this.selectedTab === TAB_NOTES;
    }

    get isAddItemsTab() {
        return this.selectedTab === TAB_ADD_ITEMS;
    }

    get isRepairCodesTab() {
        return this.selectedTab === TAB_REPAIR_CODES;
    }

    get isItemSummaryTab() {
        return this.selectedTab === TAB_ITEM_SUMMARY;
    }

    get isWorkPerformedTab() {
        return this.selectedTab === TAB_WORK_PERFORMED;
    }

    get isRepairStatus() {
        return this.workspace?.status === STATUS_REPAIR;
    }

    /**
     * @description Noun for Complete copy — Repair vs Evaluation (& Quote / Ready for Repair).
     * @returns {string}
     */
    get completeContextNoun() {
        return this.isRepairStatus ? 'repair' : 'evaluation';
    }

    /**
     * @description Photos gate copy for Complete / Next — Evaluation vs Repair.
     * @returns {string}
     */
    getPhotosRequiredMessage() {
        return this.isRepairStatus
            ? 'The customer requires photos for this repair. Please upload at least one photo on any item, or if unable to do so, check that you are ‘Unable to Take Photo’.'
            : 'The customer requires photos for this evaluation. Please upload at least one photo on any item, or if unable to do so, check that you are ‘Unable to Take Photo’.';
    }

    /**
     * @description Apex failure fallback for Complete — Evaluation vs Repair.
     * @returns {string}
     */
    getCompleteFailureMessage() {
        return this.isRepairStatus
            ? 'Unable to complete Instrument Repair.'
            : 'Unable to complete Instrument Evaluation.';
    }

    /**
     * GW-5335 - Status a Repair Code WOLI will receive on save, mirroring
     * WorkOrderLineItemsService.resolveRepairCodeWoliStatus.
     */
    get statusForUnsavedRepairCodes() {
        return this.workspace?.estimateRequired === ESTIMATE_REQUIRED
            ? WOLI_STATUS_WAITING_APPROVAL
            : WOLI_STATUS_APPROVED;
    }

    /**
     * GW-5335 - Persisted WOLI Status, or the status the code will get once saved.
     * @param {object} code Repair code entry
     * @returns {string}
     */
    resolveRepairCodeStatus(code) {
        return code?.status || this.statusForUnsavedRepairCodes;
    }

    /**
     * GW-5335 - Persisted Product Serviced Status, or the status the item will get once saved.
     * @param {object} entry Item Summary draft entry
     * @returns {string}
     */
    resolveItemStatus(entry) {
        return entry?.status || this.statusForUnsavedRepairCodes;
    }

    /**
     * GW-5335 - Team Member names signed against this item's repair codes.
     * @param {object} entry Item Summary draft entry
     * @returns {string}
     */
    signatureNamesForEntry(entry) {
        const repairCodes = entry?.repairCodes || [];
        const woliIds = new Set(
            repairCodes.map((code) => code.workOrderLineItemId).filter((id) => !!id)
        );
        const names = [];
        const seen = new Set();
        [...(this.repairSignatures || []), ...(this.stagedRepairSignatures || [])].forEach(
            (signature) => {
                const matchesPersisted =
                    signature?.workOrderLineItemId &&
                    woliIds.has(signature.workOrderLineItemId);
                const matchesStaged =
                    !signature?.workOrderLineItemId &&
                    signature?.entryId === entry?.entryId &&
                    repairCodes.some(
                        (code) => code.productId === signature.repairCodeProductId
                    );
                if (!matchesPersisted && !matchesStaged) {
                    return;
                }
                const name = signature.userName;
                if (name && !seen.has(name)) {
                    seen.add(name);
                    names.push(name);
                }
            }
        );
        return names.length > 0 ? names.join(', ') : '—';
    }

    get showReturnToEval() {
        return (
            this.isWorkspaceMode &&
            this.workspace?.status === STATUS_REPAIR &&
            this.workspace?.estimateRequired === ESTIMATE_REQUIRED
        );
    }

    get showAddItemsBlocked() {
        return this.isAddItemsTab && this.canAddItems !== true;
    }

    get showAddItemsWizard() {
        return this.isAddItemsTab && this.canAddItems === true;
    }

    get showRepairCodesBlocked() {
        return this.isRepairCodesTab && this.canAddItems !== true;
    }

    get showRepairCodesEditor() {
        return this.isRepairCodesTab && this.canAddItems === true;
    }

    /**
     * GW-3400 - Asset path allows only one Item Summary line for the WO asset product.
     */
    get hasAssetSummaryEntry() {
        return !!this.assetSummaryEntry;
    }

    /**
     * GW-3400 - Existing Item Summary draft/persisted row for the Work Order asset product.
     */
    get assetSummaryEntry() {
        if (this.hasAsset !== true || !this.workspace?.productId) {
            return null;
        }
        return (
            (this.draftEntries || []).find(
                (entry) => entry.productId === this.workspace.productId
            ) || null
        );
    }

    get assetPrimaryLabel() {
        return this.hasAssetSummaryEntry ? 'Update Item' : 'Add to Summary';
    }

    get isAssetPrimaryDisabled() {
        return this.isBusy;
    }

    /**
     * When the asset line is on Summary but status/estimate blocks code edits (photos still OK).
     */
    get assetCodesLocked() {
        return this.hasAssetSummaryEntry === true && this.canEditEntries !== true;
    }

    get assetAlreadyOnSummaryMessage() {
        if (this.assetCodesLocked) {
            return 'This asset item is already on Item Summary. Codes are locked; you can still update photos.';
        }
        return 'This asset item is already on Item Summary. Update codes or photos here.';
    }

    get addItemsBlockedMessage() {
        return ADD_ITEMS_BLOCKED_MESSAGE;
    }

    get modalCodesLockedMessage() {
        return MODAL_CODES_LOCKED_MESSAGE;
    }

    get isCategoryStep() {
        return this.wizardStep === WIZARD_CATEGORY;
    }

    get isProductStep() {
        return this.wizardStep === WIZARD_PRODUCT;
    }

    get evalCategoryCards() {
        return this.toGridCards(
            this.evalCategories,
            (row) => row.evalCategory,
            (row) => row.evalCategory,
            (row) => (row.evalRank ? `Rank ${row.evalRank}` : ''),
            this.selectedEvalCategory
        );
    }

    get productCards() {
        const selectedProductId =
            this.modalOpen === true ? this.modalProduct?.productId : this.selectedProduct?.productId;
        return (this.products || []).map((row) => {
            const entryCount = this.countEntriesForProduct(row.productId);
            const badge = entryCount > 0 ? `${entryCount} entries on this WO` : '';
            return {
                cardId: row.productId,
                title: row.productCode || '',
                name: [row.productName || '', badge].filter(Boolean).join(' — '),
                selected: row.productId === selectedProductId
            };
        });
    }

    get repairCodeCards() {
        return this.toGridCards(
            [...(this.categoryCodes || []), ...(this.serviceCodes || [])],
            (row) => row.productId,
            (row) => row.productCode,
            (row) => row.productName,
            this.assetSelectedCodeIds
        );
    }

    get modalRepairCodeCards() {
        return this.toGridCards(
            [...(this.modalCategoryCodes || []), ...(this.modalServiceCodes || [])],
            (row) => row.productId,
            (row) => row.productCode,
            (row) => row.productName,
            this.modalSelectedCodeIds
        );
    }

    get modalTitle() {
        return this.modalMode === MODAL_EDIT ? 'Edit Item Entry' : 'Add Item to Work Order';
    }

    get modalChipLabel() {
        return this.modalMode === MODAL_EDIT ? 'Editing existing entry' : 'Adding new entry';
    }

    get modalChipClass() {
        return this.modalMode === MODAL_EDIT ? 'mode-chip mode-chip_edit' : 'mode-chip mode-chip_add';
    }

    get modalPrimaryLabel() {
        if (this.modalDuplicateEntry) {
            return 'Update Existing Line';
        }
        // Stages into Item Summary only; Quick Save / Save & Close / Complete persist.
        return this.modalMode === MODAL_EDIT ? 'Update Item' : 'Add to Summary';
    }

    get modalProductLabel() {
        if (!this.modalProduct) {
            return '';
        }
        return [this.modalProduct.productCode, this.modalProduct.productName]
            .filter(Boolean)
            .join(' — ');
    }

    get modalCodesLocked() {
        return this.modalMode === MODAL_EDIT && this.canEditEntries !== true;
    }

    get modalQuantityDisabled() {
        return this.modalBusy || this.modalCodesLocked || this.hasAsset === true;
    }

    get showEditVendorDetailsButton() {
        if (this.modalVendorProcessingRequired !== true) {
            return false;
        }
        const vendor = this.vendorModalValue || {};
        return (
            !!vendor.vendorAccountId &&
            !!String(vendor.instructionsToVendor || '').trim()
        );
    }

    get modalDuplicateEntry() {
        if (!this.modalProduct?.productId || this.modalSelectedCodeIds.length === 0) {
            return null;
        }
        return this.findDuplicateEntry(
            this.modalProduct.productId,
            this.modalSelectedCodeIds,
            this.modalMode === MODAL_EDIT ? this.modalEntryId : null
        );
    }

    get modalDuplicateWarning() {
        const dup = this.modalDuplicateEntry;
        if (!dup) {
            return '';
        }
        return (
            `An entry for this item with the same repair codes already exists (qty ${dup.quantity}). ` +
            'Saving will replace that line’s quantity with the value entered here.'
        );
    }

    get showModalDuplicateWarning() {
        return Boolean(this.modalDuplicateWarning);
    }

    get hasDraftEntries() {
        return (this.draftEntries || []).length > 0;
    }

    get emptySummaryMessage() {
        if (this.hasAsset) {
            return 'No items on this work order yet. Use Repair Codes to add the asset instrument and repair codes.';
        }
        return 'No items on this work order yet. Use Add Items to select the first instrument.';
    }

    get missingItemsCompleteMessage() {
        const noun = this.completeContextNoun;
        if (this.hasAsset) {
            return `Add the asset instrument from Repair Codes before completing the ${noun}.`;
        }
        return `Add at least one instrument from Add Items before completing the ${noun}.`;
    }

    get repairCategoryDisplay() {
        const value = this.workspace?.repairCategory;
        if (value === null || value === undefined || String(value).trim() === '') {
            return '—';
        }
        return String(value);
    }

    get modalVendorCheckboxDisabled() {
        return this.modalBusy || this.modalVendorWorkOrderLocked === true;
    }

    get vendorModalLockHeaderFields() {
        if (!this.vendorModalEntryId) {
            return false;
        }
        const entry = (this.draftEntries || []).find(
            (row) => row.entryId === this.vendorModalEntryId
        );
        return entry?.vendorWorkOrderLocked === true;
    }

    /**
     * @description True when the Item Summary delete action must stay disabled (Josh / GW-4502).
     * @param {object} entry Draft summary entry
     * @returns {boolean}
     */
    entryHasSavedWarrantyRepairEvaluation(entry) {
        if (!entry?.productServicedId) {
            return false;
        }
        return (this.warrantyRepairRows || []).some(
            (row) => row.workOrderLineItemId === entry.productServicedId
        );
    }

    /**
     * @description True when delete is blocked: asset WO (single default line), WRE, or
     *              locked Vendor WO (Vendor Return Order exists). Josh / GW-4502 / GW-5298.
     * @param {object} entry Draft summary entry
     * @returns {boolean}
     */
    isSummaryEntryDeleteBlocked(entry) {
        if (this.hasAsset === true) {
            return true;
        }
        if (!entry) {
            return false;
        }
        return (
            entry.vendorWorkOrderLocked === true ||
            this.entryHasSavedWarrantyRepairEvaluation(entry)
        );
    }

    get summaryRows() {
        return this.decorateSummaryRows(this.draftEntries);
    }

    decorateSummaryRows(entries) {
        return (entries || []).map((entry) => {
            const status = this.resolveItemStatus(entry);
            const actionsLocked = status === WOLI_STATUS_REJECTED;
            const warrantyRepairLinks = this.buildWarrantyRepairLinks(entry).map((link) => ({
                ...link,
                clickable: actionsLocked ? false : link.clickable
            }));
            const deleteBlocked = this.isSummaryEntryDeleteBlocked(entry);
            return {
                ...entry,
                status,
                actionsLocked,
                signaturesDisplay: this.signatureNamesForEntry(entry),
                repairCodeLines: (entry.repairCodes || []).map((code, index) => ({
                    key: `${entry.entryId}-${code.productId || index}`,
                    label: code.productName || code.productCode || ''
                })),
                photoCount: (entry.photos || []).length,
                roLinesLabel: entry.returnOrderLineItems || 'Assign',
                roLinesDisabled: actionsLocked || this.isBusy,
                showDeleteConfirm: this.deleteConfirmEntryId === entry.entryId,
                cloneDisabled: actionsLocked || !this.cloneEnabled || this.isBusy,
                modifyDisabled: actionsLocked || this.isBusy,
                deleteDisabled:
                    actionsLocked || !this.canEditEntries || this.isBusy || deleteBlocked,
                warrantyRepairLinks,
                warrantyRepairClickable: warrantyRepairLinks.some((link) => link.clickable),
                vendorProcessingLabel:
                    entry.vendorProcessingRequired === true ? 'Yes' : 'No',
                vendorActionLabel:
                    entry.vendorProcessingRequired === true ? 'Edit Vendor' : 'Set Vendor',
                vendorDisabled: actionsLocked || this.isBusy,
                showRemoveVendor:
                    actionsLocked !== true &&
                    this.hasAsset !== true &&
                    entry.vendorProcessingRequired === true &&
                    entry.vendorWorkOrderLocked !== true
            };
        });
    }

    get roLineModalTitle() {
        return this.roLineReturnOrderNumber || 'Return Order Lines';
    }

    get hasRoLineOptions() {
        return (this.roLineOptions || []).length > 0;
    }

    /**
     * GW-3400 / GW-3891 - Warranty Repair column is always available on Instrument Evaluation.
     */
    get showWarrantyRepairColumn() {
        return true;
    }

    /**
     * GW-3400 - Read-only Item Summary rows for Evaluation Summary (no actions).
     */
    get reviewSummaryRows() {
        return this.decorateSummaryRows(this.draftEntries);
    }

    /**
     * GW-3400 - Flattened staged photos across draft entries for Evaluation Summary.
     */
    get reviewSummaryPhotos() {
        const rows = [];
        (this.draftEntries || []).forEach((entry) => {
            const itemLabel = [entry.productCode, entry.productName].filter(Boolean).join(' — ');
            (entry.photos || []).forEach((photo, index) => {
                const contentDocumentId = photo.contentDocumentId;
                const extension = (
                    photo.fileExtension ||
                    this.extensionFromTitle(photo.title) ||
                    ''
                ).toLowerCase();
                const isImage =
                    photo.isImage === true ||
                    IMAGE_EXTENSIONS.has(extension) ||
                    IMAGE_EXTENSIONS.has((photo.fileType || '').toLowerCase()) ||
                    // Camera/upload staging always produces images; titles omit the extension.
                    !!photo.imageDownloadUrl ||
                    !!photo.thumbnailUrl;
                const preferDownload =
                    this.thumbnailFallbackIds.has(contentDocumentId) ||
                    photo.isLinked !== true;
                const previewUrl = preferDownload
                    ? photo.imageDownloadUrl || photo.thumbnailUrl || photo.downloadUrl
                    : photo.imageDownloadUrl || photo.thumbnailUrl || photo.downloadUrl;
                const showThumbnail =
                    isImage &&
                    !!previewUrl &&
                    !this.thumbnailFallbackIds.has(`gone:${contentDocumentId}`);
                rows.push({
                    key: `${entry.entryId}-${contentDocumentId || index}`,
                    contentDocumentId,
                    itemLabel,
                    title: photo.title || 'Photo',
                    showThumbnail,
                    thumbnailUrl: previewUrl || ''
                });
            });
        });
        return rows;
    }

    get hasReviewSummaryPhotos() {
        return this.reviewSummaryPhotos.length > 0;
    }

    get evaluationNotesSummaryDisplay() {
        return this.displayText(this.workspace?.evaluationNotes);
    }

    get internalEvaluationNotesSummaryDisplay() {
        return this.displayText(this.workspace?.internalEvaluationNotes);
    }

    get internalSpecialistNotesSummaryDisplay() {
        return this.displayText(this.workspace?.internalSpecialistEvaluationNotes);
    }

    get showAddItemFromSummary() {
        return this.hasAsset !== true && this.canAddItems === true;
    }

    get assetProductLabel() {
        return [this.workspace?.productCode, this.workspace?.productName]
            .filter(Boolean)
            .join(' — ');
    }

    get assetQuantityHint() {
        return 'Quantity is fixed at 1 when the Work Order has an Asset.';
    }

    get photoModalTitle() {
        if (this.photoModalTarget === PHOTO_TARGET_MODAL) {
            const code = this.modalProduct?.productCode || this.modalProduct?.name || 'Item';
            return `Photos — ${code}`;
        }
        return 'Photos — Asset item';
    }

    get displayModalPhotos() {
        return this.decoratePhotoRows(this.modalPhotos);
    }

    get displayAssetPhotos() {
        return this.decoratePhotoRows(this.assetPhotos);
    }

    get photoModalPhotos() {
        return this.decoratePhotoRows(
            this.photoModalTarget === PHOTO_TARGET_MODAL
                ? this.modalPhotos || []
                : this.assetPhotos || []
        );
    }

    get hasPhotoModalPhotos() {
        return this.photoModalPhotos.length > 0;
    }

    get hasDisplayModalPhotos() {
        return (this.modalPhotos || []).length > 0;
    }

    get hasDisplayAssetPhotos() {
        return (this.assetPhotos || []).length > 0;
    }

    get isPhotoModalBusy() {
        return this.isUploadingFiles || this.isCapturing;
    }

    get isCameraBusy() {
        return this.isCameraStarting || this.isCameraActive || !this.selectedCameraId;
    }

    get isCaptureDisabled() {
        return !this.isCameraActive || this.isCapturing;
    }

    get isStopCameraDisabled() {
        return !this.isCameraActive;
    }

    get photoStageProductId() {
        return this.photoModalTarget === PHOTO_TARGET_MODAL
            ? this.modalProduct?.productId
            : this.workspace?.productId;
    }

    /**
     * GW-3400 - Left-nav items; Asset path uses Repair Codes instead of Add Items.
     * Order: WO Details → Asset (if any) → Preferences → Evaluation Notes →
     *        Add Items / Repair Codes → Item Summary → Work Performed.
     */
    get navItems() {
        const items = [{ label: 'Work Order Details', value: TAB_WO_DETAILS }];
        if (this.hasAsset) {
            items.push({ label: 'Asset Information', value: TAB_ASSET });
        }
        items.push({ label: 'Customer Preferences', value: TAB_PREFERENCES });
        items.push({ label: 'Evaluation Notes', value: TAB_NOTES });
        if (this.hasAsset) {
            items.push({ label: 'Repair Codes', value: TAB_REPAIR_CODES });
        } else {
            items.push({ label: 'Add Items', value: TAB_ADD_ITEMS });
        }
        items.push({ label: 'Item Summary', value: TAB_ITEM_SUMMARY });
        // Work Performed after Item Summary; only when Status = Repair.
        if (this.showWorkPerformedTab) {
            items.push({ label: 'Work Performed', value: TAB_WORK_PERFORMED });
        }
        return items;
    }

    get showWorkPerformedTab() {
        return this.isRepairStatus;
    }

    handleScanValueChange(event) {
        this.workOrderInput = event.detail?.value || '';
        this.errorMessage = '';
    }

    async handleScanContinue(event) {
        const input = (event.detail?.value || this.workOrderInput || '').trim();
        if (!input) {
            return;
        }
        this.workOrderInput = input;
        await this.loadWorkspace(input);
    }

    handleNavSelect(event) {
        const nextTab = event.detail?.value;
        if (!nextTab) {
            return;
        }
        this.selectedTab = nextTab;
        if (nextTab === TAB_ADD_ITEMS) {
            this.resetAddItemsDrillDown(true);
        } else if (nextTab === TAB_REPAIR_CODES) {
            this.resetAssetEditor(false);
            if (this.workspace?.productId) {
                this.loadRepairCodes(this.workspace.productId).then(() => {
                    this.syncAssetEditorFromSummaryEntry();
                });
            } else {
                this.syncAssetEditorFromSummaryEntry();
            }
        }
    }

    handleEvalCategorySelect(event) {
        const evalCategory = event.detail?.cardId;
        if (!evalCategory) {
            return;
        }
        this.selectedEvalCategory = evalCategory;
        this.loadProducts(evalCategory);
    }

    async handleProductSelect(event) {
        const productId = event.detail?.cardId;
        const product = (this.products || []).find((row) => row.productId === productId);
        if (!product) {
            return;
        }
        this.selectedProduct = product;
        await this.openItemModal(MODAL_ADD, {
            product,
            quantity: 1,
            selectedCodeIds: [],
            photos: [],
            entryId: null
        });
    }

    handleWizardPrevious() {
        if (this.wizardStep === WIZARD_PRODUCT) {
            this.resetAddItemsDrillDown(false);
        }
    }

    handleGoAddItems() {
        this.selectedTab = TAB_ADD_ITEMS;
        this.resetAddItemsDrillDown(true);
    }

    handleModalQuantityChange(event) {
        const quantity = event.detail?.quantity;
        this.modalQuantity = quantity == null ? 1 : quantity;
    }

    handleModalCodeToggle(event) {
        if (this.modalCodesLocked) {
            return;
        }
        const productId = event.detail?.cardId;
        if (!productId) {
            return;
        }
        const selected = new Set(this.modalSelectedCodeIds);
        if (selected.has(productId)) {
            selected.delete(productId);
        } else {
            selected.add(productId);
        }
        this.modalSelectedCodeIds = [...selected];
    }

    handleAssetCodeToggle(event) {
        if (this.assetCodesLocked) {
            return;
        }
        const productId = event.detail?.cardId;
        if (!productId) {
            return;
        }
        const selected = new Set(this.assetSelectedCodeIds);
        if (selected.has(productId)) {
            selected.delete(productId);
        } else {
            selected.add(productId);
        }
        this.assetSelectedCodeIds = [...selected];
        // When the asset line is already on Item Summary, keep draft/Work Performed in sync
        // immediately. Salesforce persist still waits for Quick Save / Save & Close / Complete;
        // Cancel abandons the session without writing those staged edits.
        if (this.hasAssetSummaryEntry) {
            this.applyAssetSelectionToSummaryEntry();
        }
    }

    /**
     * GW-3400 - Pushes current Repair Codes selection onto the asset Item Summary draft row
     *              so Work Performed signature lines appear/disappear in-session.
     */
    applyAssetSelectionToSummaryEntry() {
        const existing = this.assetSummaryEntry;
        if (!existing) {
            return;
        }
        this.assetError = '';
        const repairCodes = this.resolveSelectedCodes(
            this.assetSelectedCodeIds,
            this.categoryCodes,
            this.serviceCodes,
            existing.repairCodes || []
        );
        this.draftEntries = (this.draftEntries || []).map((entry) =>
            entry.entryId === existing.entryId
                ? {
                      ...entry,
                      repairCodes,
                      isDirty:
                          entry.isPersisted === true ||
                          !!entry.productServicedId ||
                          entry.isDirty === true
                  }
                : entry
        );
        this.draftsCommitted = false;
        this.pruneStagedSignaturesToDraftEntries();
    }

    handleModalCancel() {
        this.closeItemModal();
    }

    async handleModalSave() {
        await this.saveItemModal();
    }

    async handleAssetAddToSummary() {
        await this.saveAssetEntry();
    }

    handleSummaryModify(event) {
        const entryId = event.currentTarget?.dataset?.entryId;
        const entry = this.draftEntries.find((row) => row.entryId === entryId);
        if (!entry) {
            return;
        }
        this.openItemModal(MODAL_EDIT, {
            product: {
                productId: entry.productId,
                productCode: entry.productCode,
                productName: entry.productName
            },
            quantity: entry.quantity,
            selectedCodeIds: (entry.repairCodes || []).map((code) => code.productId),
            photos: [...(entry.photos || [])],
            entryId: entry.entryId,
            vendorProcessingRequired: entry.vendorProcessingRequired === true,
            vendorWorkOrderLocked: entry.vendorWorkOrderLocked === true,
            vendorAccountId: entry.vendorAccountId,
            instructionsToVendor: entry.instructionsToVendor,
            sterisPurchaseOrderToVendor: entry.sterisPurchaseOrderToVendor,
            vendorNotes: entry.vendorNotes,
            vendorReferenceNumber: entry.vendorReferenceNumber,
            vendorCost: entry.vendorCost,
            shippedToVendorDate: entry.shippedToVendorDate,
            trackingNumber: entry.trackingNumber
        });
    }

    async handleRoLinesClick(event) {
        const entryId = event.currentTarget?.dataset?.entryId;
        const entry = (this.draftEntries || []).find((row) => row.entryId === entryId);
        if (!entry?.productServicedId || !this.workspace?.workOrderId) {
            this.workspaceError =
                'Save the Product Serviced item before assigning Return Order Lines.';
            return;
        }
        this.isLoading = true;
        this.workspaceError = '';
        try {
            const assignment = await getReturnOrderLineAssignment({
                workOrderId: this.workspace.workOrderId,
                productServicedId: entry.productServicedId
            });
            this.roLineModalEntryId = entryId;
            this.roLineReturnOrderNumber = assignment?.returnOrderNumber || '';
            this.roLineOptions = (assignment?.options || []).map((option) => ({
                ...option,
                selectLabel: `Select ${option.lineItemNumber || 'Return Order Line'}`,
                selected: option.selected === true
            }));
            this.roLineModalError = '';
            this.roLineModalOpen = true;
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to load Return Order Line Items.'
            );
        } finally {
            this.isLoading = false;
        }
    }

    handleRoLineToggle(event) {
        const lineItemId = event.target?.dataset?.lineItemId;
        const selected = event.target?.checked === true;
        this.roLineOptions = (this.roLineOptions || []).map((option) =>
            option.id === lineItemId ? { ...option, selected } : option
        );
    }

    handleRoLineModalCancel() {
        this.closeRoLineModal();
    }

    async handleRoLineModalSave() {
        const selectedOptions = (this.roLineOptions || []).filter(
            (option) => option.selected === true
        );
        const selectedIds = selectedOptions.map((option) => option.id);
        const selectedNumbers = selectedOptions
            .map((option) => option.lineItemNumber)
            .filter(Boolean);
        this.draftEntries = (this.draftEntries || []).map((entry) =>
            entry.entryId === this.roLineModalEntryId
                ? {
                      ...entry,
                      returnOrderLineItemIds: selectedIds,
                      returnOrderLineItems: selectedNumbers.join(', '),
                      isDirty: true
                  }
                : entry
        );
        this.draftsCommitted = false;
        this.closeRoLineModal();
        await this.autoSaveSummaryDraftItems({
            successMessage: 'Return Order Lines saved.'
        });
    }

    closeRoLineModal() {
        this.roLineModalOpen = false;
        this.roLineModalEntryId = null;
        this.roLineReturnOrderNumber = '';
        this.roLineOptions = [];
        this.roLineModalError = '';
    }

    handleSummaryClone(event) {
        if (!this.cloneEnabled) {
            return;
        }
        const entryId = event.currentTarget?.dataset?.entryId;
        const entry = this.draftEntries.find((row) => row.entryId === entryId);
        if (!entry) {
            return;
        }
        this.openItemModal(MODAL_CLONE, {
            product: {
                productId: entry.productId,
                productCode: entry.productCode,
                productName: entry.productName
            },
            quantity: 1,
            selectedCodeIds: [],
            photos: [],
            entryId: null
        });
    }

    handleSummaryDeleteAsk(event) {
        const entryId = event.currentTarget?.dataset?.entryId || null;
        const entry = (this.draftEntries || []).find((row) => row.entryId === entryId);
        if (this.isSummaryEntryDeleteBlocked(entry)) {
            return;
        }
        this.deleteConfirmEntryId = entryId;
    }

    handleSummaryDeleteCancel() {
        this.deleteConfirmEntryId = null;
    }

    async handleSummaryDeleteConfirm(event) {
        const entryId = event.currentTarget?.dataset?.entryId;
        const entry = (this.draftEntries || []).find((row) => row.entryId === entryId);
        if (this.isSummaryEntryDeleteBlocked(entry)) {
            this.deleteConfirmEntryId = null;
            return;
        }
        this.draftEntries = (this.draftEntries || []).filter((row) => row.entryId !== entryId);
        this.stagedRepairSignatures = (this.stagedRepairSignatures || []).filter(
            (signature) => signature.entryId !== entryId
        );
        this.deleteConfirmEntryId = null;
        this.draftsCommitted = false;

        // Josh: deleting the Item Summary row must remove IE WOLI + Vendor WOLI immediately,
        // and cancel the Vendor WO when it has no remaining Product Serviced lines.
        if (!entry?.productServicedId || !this.workspace?.workOrderId) {
            return;
        }
        this.isLoading = true;
        this.workspaceError = '';
        try {
            const snapshot = this.getDraftItemsToPersist({ includeAllEntries: true });
            await saveDraftItems({
                workOrderId: this.workspace.workOrderId,
                draftItems: snapshot.map((row) => this.toDraftItemPayload(row)),
                reconcileRemovedLines: true
            });
            await this.hydratePersistedEvaluationState(this.workspace.workOrderId);
            this.draftsCommitted = true;
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to delete the Item Summary row.'
            );
            // Restore the row locally so the user can retry or Quick Save.
            this.draftEntries = [...(this.draftEntries || []), entry];
        } finally {
            this.isLoading = false;
        }
    }

    async handleModalTakePhotoClick() {
        await this.openPhotoModal(PHOTO_TARGET_MODAL);
    }

    async handleAssetTakePhotoClick() {
        await this.openPhotoModal(PHOTO_TARGET_ASSET);
    }

    /**
     * GW-3400 - Decorates staged photos for the DE-style files table (thumb, title edit, type).
     */
    decoratePhotoRows(files) {
        return (files || []).map((file) => {
            const extension = (
                file.fileExtension ||
                this.extensionFromTitle(file.title) ||
                ''
            ).toLowerCase();
            const contentDocumentId = file.contentDocumentId;
            const isImage =
                file.isImage === true ||
                IMAGE_EXTENSIONS.has(extension) ||
                IMAGE_EXTENSIONS.has((file.fileType || '').toLowerCase());
            const preferDownload =
                this.thumbnailFallbackIds.has(contentDocumentId) || file.isLinked !== true;
            const previewUrl = preferDownload
                ? file.imageDownloadUrl || file.thumbnailUrl || file.downloadUrl
                : file.imageDownloadUrl || file.thumbnailUrl || file.downloadUrl;
            const showThumbnail =
                isImage &&
                !!previewUrl &&
                !this.thumbnailFallbackIds.has(`gone:${contentDocumentId}`);
            const editTitle = file.editTitle != null ? file.editTitle : file.title || '';
            const savedTitle = file.title || '';
            const isRenaming = this.deletingDocumentIds.has(`rename:${contentDocumentId}`);
            const isTitleDirty = editTitle.trim() !== savedTitle.trim();
            return {
                ...file,
                fileExtension: extension || (file.fileType || '').toLowerCase() || '—',
                showThumbnail,
                thumbnailUrl: previewUrl,
                docTypeIcon: DOC_TYPE_BY_EXTENSION[extension] || 'doctype:image',
                isDeleting: this.deletingDocumentIds.has(contentDocumentId),
                isRenaming,
                editTitle,
                isTitleDirty,
                isSaveTitleDisabled: !isTitleDirty || isRenaming,
                titleSaveVariant: isTitleDirty ? 'brand' : 'border-filled',
                titleSaveTitle: isTitleDirty ? 'Save title' : 'No title changes to save',
                titleSaveClass: isTitleDirty
                    ? 'photo-title-save photo-title-save_dirty'
                    : 'photo-title-save photo-title-save_clean',
                titleInputClass: isTitleDirty
                    ? 'photo-title-input photo-title-input_dirty'
                    : 'photo-title-input'
            };
        });
    }

    extensionFromTitle(title) {
        if (!title || title.indexOf('.') < 0) {
            return '';
        }
        return title.split('.').pop();
    }

    handleThumbnailError(event) {
        const contentDocumentId = event.currentTarget?.dataset?.docId;
        if (!contentDocumentId) {
            return;
        }
        const next = new Set(this.thumbnailFallbackIds);
        if (!next.has(contentDocumentId)) {
            next.add(contentDocumentId);
        } else {
            next.add(`gone:${contentDocumentId}`);
        }
        this.thumbnailFallbackIds = next;
    }

    handleStagedPhotoTitleChange(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        const value =
            event.detail && event.detail.value != null
                ? event.detail.value
                : event.target.value || '';
        if (!contentDocumentId) {
            return;
        }
        this.patchPhotoById(contentDocumentId, (photo) => ({ ...photo, editTitle: value }));
    }

    async handleSaveStagedPhotoTitle(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        if (!contentDocumentId) {
            return;
        }
        const staged = this.findPhotoById(contentDocumentId);
        const newTitle = (staged?.editTitle || staged?.title || '').trim();
        if (!newTitle) {
            this.cameraError = 'Photo title is required.';
            return;
        }

        const renaming = new Set(this.deletingDocumentIds);
        renaming.add(`rename:${contentDocumentId}`);
        this.deletingDocumentIds = renaming;
        this.cameraError = '';
        try {
            const updated = await renameStagedEvaluationPhoto({
                contentDocumentId,
                newTitle
            });
            this.patchPhotoById(contentDocumentId, (photo) => ({
                ...photo,
                title: updated.title,
                editTitle: updated.title,
                lastModifiedDate: updated.lastModifiedDate
            }));
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Title updated',
                    message: `Photo renamed to "${updated.title}".`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.cameraError = this.resolveErrorMessage(error, 'Unable to rename photo.');
        } finally {
            const remaining = new Set(this.deletingDocumentIds);
            remaining.delete(`rename:${contentDocumentId}`);
            this.deletingDocumentIds = remaining;
        }
    }

    findPhotoById(contentDocumentId) {
        return (
            (this.modalPhotos || []).find((photo) => photo.contentDocumentId === contentDocumentId) ||
            (this.assetPhotos || []).find((photo) => photo.contentDocumentId === contentDocumentId)
        );
    }

    patchPhotoById(contentDocumentId, mapper) {
        const inModal = (this.modalPhotos || []).some(
            (photo) => photo.contentDocumentId === contentDocumentId
        );
        if (inModal) {
            this.modalPhotos = (this.modalPhotos || []).map((photo) =>
                photo.contentDocumentId === contentDocumentId ? mapper(photo) : photo
            );
            return;
        }
        this.assetPhotos = (this.assetPhotos || []).map((photo) =>
            photo.contentDocumentId === contentDocumentId ? mapper(photo) : photo
        );
    }

    async handleModalPhotoDelete(event) {
        const contentDocumentId = event.currentTarget?.dataset?.docId;
        await this.deleteStagedPhoto(contentDocumentId, true);
    }

    async handleAssetPhotoDelete(event) {
        const contentDocumentId = event.currentTarget?.dataset?.docId;
        await this.deleteStagedPhoto(contentDocumentId, false);
    }

    async handlePhotoModalDelete(event) {
        const contentDocumentId = event.currentTarget?.dataset?.docId;
        await this.deleteStagedPhoto(
            contentDocumentId,
            this.photoModalTarget === PHOTO_TARGET_MODAL
        );
    }

    handleContaminationChange(event) {
        if (!this.workspace) {
            return;
        }
        const field = event.detail?.field;
        if (!field) {
            return;
        }
        this.workspace = {
            ...this.workspace,
            contamination: {
                ...(this.workspace.contamination || {}),
                [field]: event.detail.value
            }
        };
    }

    hasRequiredContamination() {
        if (!this.showContaminatedWarning) {
            return true;
        }
        const contamination = this.buildContaminationPayload();
        const hasLocation = CONTAMINATION_CHECKBOX_FIELDS.some(
            (field) => contamination[field] === true
        );
        const other = contamination.contaminationOther;
        return hasLocation || (typeof other === 'string' && other.trim() !== '');
    }

    buildContaminationPayload() {
        const source = this.workspace?.contamination || {};
        const payload = {};
        CONTAMINATION_CHECKBOX_FIELDS.forEach((field) => {
            payload[field] = source[field] === true;
        });
        const other = source.contaminationOther;
        payload.contaminationOther =
            typeof other === 'string' && other.trim() !== '' ? other.trim() : null;
        return payload;
    }

    handleSubStatusChange(event) {
        if (!this.workspace) {
            return;
        }
        const value = event.target.value;
        this.workspace = {
            ...this.workspace,
            subStatus: value === '' || value == null ? null : value
        };
    }

    handleUnableToTakePhotoChange(event) {
        if (!this.workspace) {
            return;
        }
        this.workspace = {
            ...this.workspace,
            unableToTakePhoto: event.target.checked === true
        };
    }

    handleTurnTimeInputChange(event) {
        this.turnTimeInputValue = event.target.value;
    }

    handleQuantityReceivedInputChange(event) {
        this.quantityReceivedInputValue = event.target.value;
    }

    handleNotesChange(event) {
        const field = event.detail?.field;
        if (!this.workspace || !field) {
            return;
        }
        this.workspace = {
            ...this.workspace,
            [field]: event.detail.value
        };
    }

    displayText(value) {
        if (value === null || value === undefined || String(value).trim() === '') {
            return '—';
        }
        return String(value);
    }

    handleCancel() {
        this.resetToScan();
    }

    async handleQuickSave() {
        const saved = await this.persistEvaluationProgress({ closeAfter: false });
        if (saved) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Saved',
                    message: 'Instrument evaluation progress was saved.',
                    variant: 'success'
                })
            );
        }
    }

    async handleSaveAndClose() {
        const saved = await this.persistEvaluationProgress({ closeAfter: true });
        if (saved) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Saved',
                    message: 'Instrument evaluation progress was saved.',
                    variant: 'success'
                })
            );
        }
    }

    /**
     * GW-3400 - Runs Complete-ready validations (items, photos, signatures when Status = Repair),
     *              then opens Evaluation Summary (read-only). Does not persist — Quick Save,
     *              Save & Close, and Complete write to Salesforce.
     */
    async handleNext() {
        this.workspaceError = '';
        if (!this.hasDraftEntries) {
            this.workspaceError = this.missingItemsCompleteMessage;
            this.selectedTab = this.hasAsset ? TAB_REPAIR_CODES : TAB_ADD_ITEMS;
            return;
        }
        if (!this.ensureReturnOrderLinesAssigned()) {
            this.selectedTab = TAB_ITEM_SUMMARY;
            return;
        }
        if (!this.ensureQuantityReceivedMatchesItems()) {
            this.selectedTab = TAB_ITEM_SUMMARY;
            return;
        }
        if (!this.ensurePhotosReady()) {
            return;
        }
        if (this.hasUnsignedRepairCodes()) {
            this.workspaceError = REPAIR_UNSIGNED_MESSAGE;
            this.selectedTab = this.showWorkPerformedTab
                ? TAB_WORK_PERFORMED
                : TAB_ITEM_SUMMARY;
            return;
        }
        this.mode = MODE_SUMMARY;
    }

    /**
     * GW-3400 - Returns from Evaluation Summary to the main eval workspace (Item Summary).
     */
    handleContinueEvaluation() {
        this.workspaceError = '';
        this.mode = MODE_WORKSPACE;
        this.selectedTab = TAB_ITEM_SUMMARY;
    }

    /**
     * GW-3400 - From Evaluation Summary: persists any unsaved items + signatures, applies
     *              Complete Status / Sub Status, then exits to scan.
     */
    async handleComplete() {
        this.workspaceError = '';
        const headerSaved = await this.persistWorkOrderFields({
            suppressToast: true,
            manageLoading: false
        });
        if (!headerSaved) {
            return;
        }
        if (!this.hasDraftEntries) {
            this.workspaceError = this.missingItemsCompleteMessage;
            this.mode = MODE_WORKSPACE;
            this.selectedTab = this.hasAsset ? TAB_REPAIR_CODES : TAB_ADD_ITEMS;
            return;
        }
        if (!this.ensureReturnOrderLinesAssigned()) {
            this.mode = MODE_WORKSPACE;
            this.selectedTab = TAB_ITEM_SUMMARY;
            return;
        }
        if (!this.ensureQuantityReceivedMatchesItems()) {
            this.mode = MODE_WORKSPACE;
            this.selectedTab = TAB_ITEM_SUMMARY;
            return;
        }
        if (!this.ensurePhotosReady()) {
            this.mode = MODE_WORKSPACE;
            this.selectedTab = TAB_ITEM_SUMMARY;
            return;
        }
        if (this.hasUnsignedRepairCodes()) {
            this.workspaceError = REPAIR_UNSIGNED_MESSAGE;
            this.mode = MODE_WORKSPACE;
            this.selectedTab = this.showWorkPerformedTab
                ? TAB_WORK_PERFORMED
                : TAB_ITEM_SUMMARY;
            return;
        }

        this.isLoading = true;
        this.workspaceError = '';
        const unpersistedSnapshot = this.getDraftItemsToPersist({ includeAllEntries: true });
        const stagedSnapshot = [...(this.stagedRepairSignatures || [])];
        try {
            const productServicedIds = await completeDraftItems({
                workOrderId: this.workspace.workOrderId,
                draftItems: unpersistedSnapshot.map((entry) => this.toDraftItemPayload(entry))
            });
            await this.persistStagedSignaturesAfterComplete(
                this.workspace.workOrderId,
                unpersistedSnapshot,
                productServicedIds,
                stagedSnapshot
            );
            this.draftsCommitted = true;
            this.stagedRepairSignatures = [];
            const completedNumber = this.workspace?.workOrderNumber;
            const wasRepair = this.isRepairStatus;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: wasRepair ? 'Repair complete' : 'Evaluation complete',
                    message: wasRepair
                        ? `Work Order ${completedNumber} repair was completed.`
                        : `Work Order ${completedNumber} evaluation was completed.`,
                    variant: 'success'
                })
            );
            this.resetToScan();
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                this.getCompleteFailureMessage()
            );
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Quick Save / Save & Close: header fields + unsaved WOLIs + staged signatures.
     * Does not change Status / Sub Status.
     * @param {{closeAfter: boolean}} options Whether to return to scan after save
     * @returns {Promise<boolean>} True when save succeeded
     */
    async persistEvaluationProgress({ closeAfter }) {
        if (!this.workspace?.workOrderId || this.isBusy) {
            return false;
        }
        this.isLoading = true;
        this.workspaceError = '';
        const unpersistedSnapshot = this.getDraftItemsToPersist({ includeAllEntries: true });
        const stagedSnapshot = [...(this.stagedRepairSignatures || [])];
        try {
            const headerSaved = await this.persistWorkOrderFields({
                suppressToast: true,
                manageLoading: false
            });
            if (!headerSaved) {
                return false;
            }
            const productServicedIds = await saveDraftItems({
                workOrderId: this.workspace.workOrderId,
                draftItems: unpersistedSnapshot.map((entry) => this.toDraftItemPayload(entry)),
                reconcileRemovedLines: true
            });
            await this.persistStagedSignaturesAfterComplete(
                this.workspace.workOrderId,
                unpersistedSnapshot,
                productServicedIds,
                stagedSnapshot
            );
            this.stagedRepairSignatures = [];
            await this.hydratePersistedEvaluationState(this.workspace.workOrderId);
            if (closeAfter) {
                this.resetToScan();
            }
            return true;
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to save Instrument Evaluation progress.'
            );
            return false;
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Draft entries for persist: all rows when reconciling Item Summary deletes, otherwise
     * only dirty or brand-new rows for partial auto-save.
     * @param {{includeAllEntries?: boolean}} options Persist options
     * @returns {object[]}
     */
    getDraftItemsToPersist({ includeAllEntries = false } = {}) {
        return (this.draftEntries || [])
            .filter(
                (entry) =>
                    includeAllEntries === true ||
                    entry.isDirty === true ||
                    (!entry.productServicedId && entry.isPersisted !== true)
            )
            .map((entry) => ({
                entryId: entry.entryId,
                productServicedId: entry.productServicedId || null,
                productId: entry.productId,
                quantity: entry.quantity,
                returnOrderLineItemIds: entry.returnOrderLineItemIds,
                returnOrderLineItems: entry.returnOrderLineItems || '',
                repairCodes: (entry.repairCodes || []).map((code) => ({
                    productId: code.productId,
                    workOrderLineItemId: code.workOrderLineItemId
                })),
                photos: entry.photos,
                vendorProcessingRequired: entry.vendorProcessingRequired,
                vendorAccountId: entry.vendorAccountId,
                instructionsToVendor: entry.instructionsToVendor,
                sterisPurchaseOrderToVendor: entry.sterisPurchaseOrderToVendor,
                vendorNotes: entry.vendorNotes,
                vendorReferenceNumber: entry.vendorReferenceNumber,
                vendorCost: entry.vendorCost,
                shippedToVendorDate: entry.shippedToVendorDate,
                trackingNumber: entry.trackingNumber
            }));
    }

    /**
     * Maps a draft snapshot entry to the Apex DraftItemInput shape.
     * @param {object} entry Draft snapshot entry
     * @returns {object}
     */
    toDraftItemPayload(entry) {
        return {
            productServicedId: entry.productServicedId || null,
            productId: entry.productId,
            quantity: entry.quantity,
            returnOrderLineItemIds: entry.returnOrderLineItemIds,
            repairCodeProductIds: (entry.repairCodes || []).map((code) => code.productId),
            contentDocumentIds: (entry.photos || []).map((photo) => photo.contentDocumentId),
            vendorProcessingRequired: entry.vendorProcessingRequired === true,
            vendorAccountId: entry.vendorAccountId || null,
            instructionsToVendor: entry.instructionsToVendor || '',
            sterisPurchaseOrderToVendor: entry.sterisPurchaseOrderToVendor || '',
            vendorNotes: entry.vendorNotes || '',
            vendorReferenceNumber: entry.vendorReferenceNumber || '',
            vendorCost: entry.vendorCost,
            shippedToVendorDate: entry.shippedToVendorDate || null,
            trackingNumber: entry.trackingNumber || ''
        };
    }

    async handleReturnToEval() {
        if (!this.workspace?.workOrderId || this.isBusy) {
            return;
        }
        const saved = await this.persistEvaluationProgress({ closeAfter: false });
        if (!saved) {
            return;
        }
        this.isLoading = true;
        this.workspaceError = '';
        try {
            const workOrderNumber = this.workspace.workOrderNumber;
            await returnToEvaluation({ workOrderId: this.workspace.workOrderId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Returned to Eval',
                    message: workOrderNumber
                        ? `Work Order ${workOrderNumber} was returned to Evaluate & Quote.`
                        : 'Work Order was returned to Evaluate & Quote.',
                    variant: 'success'
                })
            );
            this.resetToScan();
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to return Work Order to evaluation.'
            );
        } finally {
            this.isLoading = false;
        }
    }

    async loadWorkspace(workOrderInput) {
        this.isLoading = true;
        this.errorMessage = '';
        this.workspaceError = '';
        try {
            const workspace = await initializeEvaluation({ workOrderInput });
            this.applyWorkspace(workspace);
            this.draftEntries = [];
            this.warrantyRepairRows = [];
            this.draftsCommitted = false;
            this.repairSignatures = [];
            this.stagedRepairSignatures = [];
            this.mode = MODE_WORKSPACE;
            this.selectedTab = TAB_WO_DETAILS;
            this.resetAddItemsDrillDown(false);
            this.resetAssetEditor(false);
            await this.hydratePersistedEvaluationState(workspace?.workOrderId);
            if (workspace?.hasAsset === true && workspace.productId) {
                this.ensureAssetSummaryEntry();
                await this.loadRepairCodes(workspace.productId);
                this.syncAssetEditorFromSummaryEntry();
            }
        } catch (error) {
            this.errorMessage = this.resolveErrorMessage(error, 'Unable to start Instrument Evaluation.');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * GW-3400 - Loads persisted Product Serviced / Repair Codes into Item Summary and signatures
     *              for Work Performed (needed when Status = Repair).
     * @param {string} workOrderId Work Order Id
     */
    async hydratePersistedEvaluationState(workOrderId) {
        if (!workOrderId) {
            return;
        }
        const [items, signatures, warrantyRepairRows] = await Promise.all([
            getEvaluationItems({ workOrderId }),
            getRepairSignatures({ workOrderId }),
            getWarrantyRepairEvaluations({
                workOrderId,
                workOrderLineItemId: null
            })
        ]);
        this.repairSignatures = signatures || [];
        this.warrantyRepairRows = warrantyRepairRows || [];
        const mapped = (items || []).map((item) =>
            this.mapPersistedItemToDraftEntry(item)
        );
        if (mapped.length > 0) {
            this.draftEntries = mapped;
            this.draftsCommitted = true;
        }
        if (this.isRepairCodesTab) {
            this.syncAssetEditorFromSummaryEntry();
        }
    }

    /**
     * GW-3400 / GW-3891 - Per-WRE links for Item Summary (Josh: open the clicked WRE directly).
     * @param {object} entry Draft entry
     * @returns {Array<{key: string, label: string, clickable: boolean, recordId: string|null}>}
     */
    buildWarrantyRepairLinks(entry) {
        const entryKey = entry?.entryId || 'entry';
        if (!entry?.productServicedId) {
            return [
                {
                    key: `${entryKey}-wre-save`,
                    label: 'Save item first',
                    clickable: false,
                    recordId: null
                }
            ];
        }
        const matches = (this.warrantyRepairRows || []).filter(
            (row) => row.workOrderLineItemId === entry.productServicedId
        );
        const lineQuantity = Number(entry.quantity);
        const maxCount =
            this.hasAsset !== true && Number.isFinite(lineQuantity) && lineQuantity > 0
                ? Math.floor(lineQuantity)
                : 1;
        const allowMore = this.hasAsset !== true && matches.length < maxCount;
        const clickable = !this.isBusy;

        if (matches.length === 0) {
            return [
                {
                    key: `${entryKey}-wre-new`,
                    label: 'New',
                    clickable,
                    recordId: null
                }
            ];
        }

        const links = matches.map((row, index) => ({
            key: `${entryKey}-wre-${row.id || index}`,
            label: row.name || 'Edit',
            clickable,
            recordId: row.id
        }));

        if (allowMore) {
            links.push({
                key: `${entryKey}-wre-new`,
                label: 'New',
                clickable,
                recordId: null
            });
        }

        return links;
    }

    async handleWarrantyRepairClick(event) {
        event.preventDefault();
        if (this.isBusy) {
            return;
        }
        const entryId = event.currentTarget?.dataset?.entryId;
        const wreRecordId = event.currentTarget?.dataset?.wreId;
        const preferredRecordId =
            wreRecordId && String(wreRecordId).trim() !== '' ? wreRecordId : null;
        const entry = (this.draftEntries || []).find((row) => row.entryId === entryId);
        if (!entry?.productServicedId) {
            return;
        }
        this.wreModalWoliId = entry.productServicedId;
        this.wreModalAllowMultiple = this.hasAsset !== true;
        const lineQuantity = Number(entry.quantity);
        this.wreModalMaxCount =
            this.hasAsset !== true && Number.isFinite(lineQuantity) && lineQuantity > 0
                ? Math.floor(lineQuantity)
                : 1;
        this.wreModalOpen = true;
        // Allow the panel to mount, then open the selected WRE or New / list.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            const panel = this.template.querySelector(
                'c-warranty-repair-evaluation-panel'
            );
            if (panel && typeof panel.openPreferredForm === 'function') {
                panel.openPreferredForm(preferredRecordId);
            }
        }, 0);
    }

    handleWreModalClose() {
        this.wreModalOpen = false;
        this.wreModalWoliId = null;
        this.wreModalAllowMultiple = false;
        this.wreModalMaxCount = 1;
    }

    async handleWreSaved() {
        if (!this.workspace?.workOrderId) {
            return;
        }
        try {
            const rows = await getWarrantyRepairEvaluations({
                workOrderId: this.workspace.workOrderId,
                workOrderLineItemId: null
            });
            this.warrantyRepairRows = rows || [];
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to refresh Warranty Repair Evaluations.'
            );
            return;
        }
        // Close modal after save when in-panel list is hidden (asset or no-asset Qty=1).
        const shouldCloseModal =
            this.hasAsset === true || (this.wreModalMaxCount || 1) <= 1;
        if (shouldCloseModal) {
            this.handleWreModalClose();
        }
    }

    /**
     * GW-3400 - Maps an Apex EvaluationItem into the LWC draft-entry shape.
     * @param {object} item Persisted evaluation item
     * @returns {object} Draft entry
     */
    mapPersistedItemToDraftEntry(item) {
        this._entrySeq = (this._entrySeq || 0) + 1;
        return {
            entryId: item.productServicedId || `persisted-${Date.now()}-${this._entrySeq}`,
            productServicedId: item.productServicedId,
            status: item.status,
            productId: item.productId,
            productCode: item.productCode || '',
            productName: item.productName || '',
            quantity: item.quantity,
            returnOrderLineItemIds: null,
            returnOrderLineItems: item.returnOrderLineItems || '',
            repairCodes: (item.repairCodes || []).map((code) => ({
                productId: code.productId,
                workOrderLineItemId: code.workOrderLineItemId,
                status: code.status,
                productCode: code.productCode,
                productName: code.productName,
                codeType: code.codeType
            })),
            photos: (item.photos || [])
                .filter((photo) => photo?.contentDocumentId)
                .map((photo) => ({
                    contentDocumentId: photo.contentDocumentId,
                    title: photo.title || 'Photo',
                    editTitle: photo.title || 'Photo',
                    thumbnailUrl: photo.thumbnailUrl || '',
                    imageDownloadUrl: photo.imageDownloadUrl || photo.thumbnailUrl || '',
                    downloadUrl: photo.downloadUrl || '',
                    fileExtension: photo.fileExtension || '',
                    isImage: photo.isImage === true,
                    isLinked: true
                })),
            vendorProcessingRequired: item.vendorProcessingRequired === true,
            vendorAccountId: item.vendorAccountId || null,
            instructionsToVendor: item.instructionsToVendor || '',
            sterisPurchaseOrderToVendor: item.sterisPurchaseOrderToVendor || '',
            vendorNotes: item.vendorNotes || '',
            vendorReferenceNumber: item.vendorReferenceNumber || '',
            vendorCost: item.vendorCost,
            shippedToVendorDate: item.shippedToVendorDate || null,
            trackingNumber: item.trackingNumber || '',
            vendorWorkOrderLocked: item.vendorWorkOrderLocked === true,
            vendorWorkOrderId: item.vendorWorkOrderId || null,
            isPersisted: true,
            isDirty: false
        };
    }

    async runRepairSignatureAction(action) {
        this.isLoading = true;
        this.workspaceError = '';
        try {
            const signatures = await action();
            this.repairSignatures = signatures || [];
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to update repair signatures.'
            );
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Drops staged signatures that no longer match a draft repair code.
     */
    pruneStagedSignaturesToDraftEntries() {
        const validKeys = new Set();
        (this.draftEntries || []).forEach((entry) => {
            (entry.repairCodes || []).forEach((code) => {
                if (code?.productId) {
                    validKeys.add(this.buildSignRowKey(entry.entryId, code.productId));
                }
            });
        });
        this.stagedRepairSignatures = (this.stagedRepairSignatures || []).filter((signature) =>
            validKeys.has(
                this.buildSignRowKey(signature.entryId, signature.repairCodeProductId)
            )
        );
    }

    /**
     * Builds a stable key for a draft repair-code row (entry + code product).
     * @param {string} entryId Draft entry Id
     * @param {string} repairCodeProductId Repair code Product2 Id
     * @returns {string}
     */
    buildSignRowKey(entryId, repairCodeProductId) {
        return `${entryId || ''}::${repairCodeProductId || ''}`;
    }

    /**
     * After Complete creates WOLIs, writes staged signatures for the current user.
     * @param {string} workOrderId Work Order Id
     * @param {object[]} draftSnapshot Draft entries used for Complete
     * @param {string[]} productServicedIds Created Product Serviced Ids in draft order
     * @param {object[]} stagedSnapshot Staged signatures captured before Complete
     */
    async persistStagedSignaturesAfterComplete(
        workOrderId,
        draftSnapshot,
        productServicedIds,
        stagedSnapshot
    ) {
        const currentUserStaged = (stagedSnapshot || []).filter(
            (signature) => signature.userId === currentUserId
        );
        if (!workOrderId || !currentUserStaged.length) {
            return;
        }
        const items = await getEvaluationItems({ workOrderId });
        const itemsByProductServicedId = new Map(
            (items || [])
                .filter((item) => item?.productServicedId)
                .map((item) => [item.productServicedId, item])
        );
        const woliIdsToSign = [];
        (draftSnapshot || []).forEach((entry, index) => {
            const productServicedId =
                entry.productServicedId || (productServicedIds || [])[index];
            const item = itemsByProductServicedId.get(productServicedId);
            if (!item) {
                return;
            }
            const stagedForEntry = currentUserStaged.filter(
                (signature) => signature.entryId === entry.entryId
            );
            stagedForEntry.forEach((signature) => {
                const code = (item.repairCodes || []).find(
                    (row) => row.productId === signature.repairCodeProductId
                );
                if (code?.workOrderLineItemId) {
                    woliIdsToSign.push(code.workOrderLineItemId);
                }
            });
        });
        if (!woliIdsToSign.length) {
            return;
        }
        this.repairSignatures = await signAllRepairCodes({
            workOrderId,
            workOrderLineItemIds: woliIdsToSign
        });
    }

    async handleSignRepairCode(event) {
        const dataset = event.currentTarget?.dataset || {};
        const workOrderLineItemId = dataset.woliId || null;
        const entryId = dataset.entryId || null;
        const repairCodeProductId = dataset.codeProductId || null;
        if (this.isBusy || !this.workspace?.workOrderId) {
            return;
        }
        // Persisted Repair Code WOLI: write signature immediately.
        if (workOrderLineItemId) {
            await this.runRepairSignatureAction(() =>
                addRepairSignature({
                    workOrderId: this.workspace.workOrderId,
                    workOrderLineItemId
                })
            );
            return;
        }
        // Draft-only: stage until Complete creates the WOLI.
        if (!entryId || !repairCodeProductId) {
            return;
        }
        const alreadyStaged = (this.stagedRepairSignatures || []).some(
            (signature) =>
                signature.entryId === entryId &&
                signature.repairCodeProductId === repairCodeProductId &&
                signature.userId === currentUserId
        );
        if (alreadyStaged) {
            return;
        }
        this.stagedRepairSignatures = [
            ...(this.stagedRepairSignatures || []),
            {
                id: `staged-${entryId}-${repairCodeProductId}-${currentUserId}`,
                entryId,
                repairCodeProductId,
                workOrderLineItemId: null,
                productId: repairCodeProductId,
                userId: currentUserId,
                userName: this.currentUserName || 'Current User'
            }
        ];
    }

    async handleSignAllRepairCodes() {
        if (this.isSignAllDisabled || !this.workspace?.workOrderId) {
            return;
        }
        const persistedIds = this.signableWorkOrderLineItemIds;
        const draftRows = this.workPerformedSignableRows.filter(
            (row) => row.showSignButton && !row.workOrderLineItemId
        );
        if (persistedIds.length) {
            await this.runRepairSignatureAction(() =>
                signAllRepairCodes({
                    workOrderId: this.workspace.workOrderId,
                    workOrderLineItemIds: persistedIds
                })
            );
        }
        if (!draftRows.length) {
            return;
        }
        const existingKeys = new Set(
            (this.stagedRepairSignatures || [])
                .filter((signature) => signature.userId === currentUserId)
                .map((signature) =>
                    this.buildSignRowKey(signature.entryId, signature.repairCodeProductId)
                )
        );
        const additions = [];
        draftRows.forEach((row) => {
            const key = this.buildSignRowKey(row.entryId, row.productId);
            if (existingKeys.has(key)) {
                return;
            }
            existingKeys.add(key);
            additions.push({
                id: `staged-${row.entryId}-${row.productId}-${currentUserId}`,
                entryId: row.entryId,
                repairCodeProductId: row.productId,
                workOrderLineItemId: null,
                productId: row.productId,
                userId: currentUserId,
                userName: this.currentUserName || 'Current User'
            });
        });
        if (additions.length) {
            this.stagedRepairSignatures = [
                ...(this.stagedRepairSignatures || []),
                ...additions
            ];
        }
    }

    decorateRepairSignature(signature) {
        return {
            ...signature,
            canRemove: signature?.userId === currentUserId
        };
    }

    async handleRemoveRepairSignature(event) {
        const signatureId = event.currentTarget?.dataset?.signatureId;
        if (!signatureId || this.isBusy || !this.workspace?.workOrderId) {
            return;
        }
        if (String(signatureId).startsWith('staged-')) {
            this.stagedRepairSignatures = (this.stagedRepairSignatures || []).filter(
                (signature) => signature.id !== signatureId
            );
            return;
        }
        await this.runRepairSignatureAction(() =>
            removeRepairSignature({
                workOrderId: this.workspace.workOrderId,
                signatureId
            })
        );
    }

    async persistWorkOrderFields(options = {}) {
        if (!this.workspace?.workOrderId) {
            return false;
        }
        this.syncQuantityReceivedFromDom();
        if (!this.hasRequiredContamination()) {
            this.workspaceError = CONTAMINATION_REQUIRED_MESSAGE;
            return false;
        }
        const suppressToast = options.suppressToast === true;
        const manageLoading = options.manageLoading !== false;
        if (manageLoading) {
            this.isLoading = true;
        }
        this.workspaceError = '';
        try {
            const workspace = await saveWorkOrderFields({
                workOrderId: this.workspace.workOrderId,
                subStatus: this.workspace.subStatus,
                unableToTakePhoto: this.workspace.unableToTakePhoto === true,
                turnTime: this.parseTurnTime(this.turnTimeInputValue),
                quantityReceived: this.parseQuantityReceived(this.quantityReceivedInputValue),
                evaluationNotes: this.workspace.evaluationNotes,
                internalEvaluationNotes: this.workspace.internalEvaluationNotes,
                internalSpecialistEvaluationNotes: this.workspace.internalSpecialistEvaluationNotes,
                contaminationJson: JSON.stringify(this.buildContaminationPayload())
            });
            this.applyWorkspace(workspace);
            if (!suppressToast) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Saved',
                        message: 'Work Order fields were saved.',
                        variant: 'success'
                    })
                );
            }
            return true;
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to save Instrument Evaluation.'
            );
            return false;
        } finally {
            if (manageLoading) {
                this.isLoading = false;
            }
        }
    }

    applyWorkspace(workspace) {
        this.workspace = workspace || {};
        this.updateBrowserTitle(workspace?.workOrderNumber);
        this.turnTimeInputValue =
            workspace?.turnTime == null ? '' : String(workspace.turnTime);
        this.quantityReceivedInputValue =
            workspace?.quantityReceived == null ? '' : String(workspace.quantityReceived);
        if (this.selectedTab === TAB_ASSET && workspace?.hasAsset !== true) {
            this.selectedTab = TAB_WO_DETAILS;
        }
        if (this.selectedTab === TAB_REPAIR_CODES && workspace?.hasAsset !== true) {
            this.selectedTab = TAB_WO_DETAILS;
        }
        if (this.selectedTab === TAB_ADD_ITEMS && workspace?.hasAsset === true) {
            this.selectedTab = TAB_WO_DETAILS;
        }
        if (this.selectedTab === TAB_WORK_PERFORMED && workspace?.status !== STATUS_REPAIR) {
            this.selectedTab = TAB_ITEM_SUMMARY;
        }
    }

    async resetAddItemsDrillDown(reloadCategories) {
        this.wizardStep = WIZARD_CATEGORY;
        this.selectedEvalCategory = '';
        this.selectedProduct = null;
        this.products = [];
        if (reloadCategories === true && this.canAddItems) {
            await this.loadEvalCategories();
        }
    }

    resetAssetEditor(clearPhotos) {
        this.itemQuantity = 1;
        this.assetSelectedCodeIds = [];
        this.assetError = '';
        if (clearPhotos === true) {
            this.assetPhotos = [];
        }
    }

    async loadEvalCategories() {
        if (!this.workspace?.workOrderId) {
            return;
        }
        this.isLoading = true;
        this.workspaceError = '';
        try {
            this.evalCategories = (await getEvalCategories({
                workOrderId: this.workspace.workOrderId
            })) || [];
            this.wizardStep = WIZARD_CATEGORY;
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to load evaluation categories.'
            );
        } finally {
            this.isLoading = false;
        }
    }

    async loadProducts(evalCategory) {
        if (!this.workspace?.workOrderId || !evalCategory) {
            return;
        }
        this.isLoading = true;
        this.workspaceError = '';
        try {
            this.products = (await getProductsForEvalCategory({
                workOrderId: this.workspace.workOrderId,
                evalCategory
            })) || [];
            this.wizardStep = WIZARD_PRODUCT;
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to load evaluation products.'
            );
        } finally {
            this.isLoading = false;
        }
    }

    async loadRepairCodes(productId) {
        if (!this.workspace?.workOrderId) {
            return;
        }
        this.isLoading = true;
        this.workspaceError = '';
        try {
            const codes = await getRepairCodesForProduct({
                workOrderId: this.workspace.workOrderId,
                productId
            });
            this.categoryCodes = codes?.categoryCodes || [];
            this.serviceCodes = codes?.serviceCodes || [];
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(error, 'Unable to load repair codes.');
        } finally {
            this.isLoading = false;
        }
    }

    async openItemModal(mode, options) {
        this.modalBusy = true;
        this.modalError = '';
        this.modalMode = mode;
        this.modalEntryId = options.entryId || null;
        this.modalProduct = options.product;
        this.modalQuantity = options.quantity == null ? '' : options.quantity;
        this.modalSelectedCodeIds = [...(options.selectedCodeIds || [])];
        this.modalPhotos = [...(options.photos || [])];
        this.modalVendorProcessingRequired = options.vendorProcessingRequired === true;
        this.modalVendorWorkOrderLocked = options.vendorWorkOrderLocked === true;
        this.vendorModalValue = {
            vendorAccountId: options.vendorAccountId || null,
            instructionsToVendor: options.instructionsToVendor || '',
            sterisPurchaseOrderToVendor: options.sterisPurchaseOrderToVendor || '',
            vendorNotes: options.vendorNotes || '',
            vendorReferenceNumber: options.vendorReferenceNumber || '',
            vendorCost: options.vendorCost,
            shippedToVendorDate: options.shippedToVendorDate || null,
            trackingNumber: options.trackingNumber || ''
        };
        this.modalOpen = true;
        try {
            const codes = await getRepairCodesForProduct({
                workOrderId: this.workspace.workOrderId,
                productId: options.product.productId
            });
            this.modalCategoryCodes = codes?.categoryCodes || [];
            this.modalServiceCodes = codes?.serviceCodes || [];
        } catch (error) {
            this.modalError = this.resolveErrorMessage(error, 'Unable to load repair codes.');
        } finally {
            this.modalBusy = false;
        }
    }

    closeItemModal() {
        this.modalOpen = false;
        this.modalError = '';
        this.modalProduct = null;
        this.selectedProduct = null;
        this.modalEntryId = null;
        this.modalSelectedCodeIds = [];
        this.modalPhotos = [];
        this.modalCategoryCodes = [];
        this.modalServiceCodes = [];
        this.modalVendorProcessingRequired = false;
        this.modalVendorWorkOrderLocked = false;
        this.vendorModalValue = {};
    }

    handleModalVendorProcessingChange(event) {
        const checked = event.target.checked === true;
        if (!checked && this.modalVendorWorkOrderLocked) {
            this.modalError =
                'Vendor processing cannot be removed because a Vendor Return Order exists on the Vendor Work Order.';
            event.target.checked = true;
            return;
        }
        this.modalVendorProcessingRequired = checked;
        if (checked) {
            this.vendorModalEntryId = this.modalEntryId;
            const shared = this.getPreferredSharedVendorDetails(this.vendorModalValue);
            if (shared) {
                this.vendorModalValue = { ...shared };
            }
            this.vendorModalOpen = true;
        } else {
            this.vendorModalValue = {};
        }
    }

    /**
     * GW-4616 - Reopens the vendor details popup while Vendor Processing Required stays checked.
     */
    handleEditVendorDetails() {
        if (!this.modalVendorProcessingRequired || this.modalBusy) {
            return;
        }
        this.vendorModalEntryId = this.modalEntryId;
        const shared = this.getPreferredSharedVendorDetails(this.vendorModalValue);
        if (shared) {
            this.vendorModalValue = { ...shared };
        }
        this.vendorModalOpen = true;
    }

    handleSummaryVendorClick(event) {
        const entryId = event.currentTarget?.dataset?.entryId;
        const entry = (this.draftEntries || []).find((row) => row.entryId === entryId);
        if (!entry) {
            return;
        }
        this.vendorModalEntryId = entryId;
        const fromEntry = this.mapVendorFieldsFromValue(entry);
        const shared = this.getPreferredSharedVendorDetails(fromEntry);
        this.vendorModalValue = shared ? { ...shared } : fromEntry;
        this.vendorModalOpen = true;
    }

    async handleSummaryRemoveVendor(event) {
        if (event) {
            event.preventDefault();
            event.stopPropagation();
        }
        if (this.isBusy || this.hasAsset === true) {
            return;
        }
        const entryId = event.currentTarget?.dataset?.entryId;
        const entry = (this.draftEntries || []).find((row) => row.entryId === entryId);
        if (!entry || entry.vendorProcessingRequired !== true || entry.vendorWorkOrderLocked === true) {
            return;
        }
        const hadVendorWorkOrder = !!entry.vendorWorkOrderId;
        const productServicedId = entry.productServicedId;

        // Josh bug A: Set Vendor is local until save. Do not auto-save when never linked.
        if (!hadVendorWorkOrder || !productServicedId) {
            this.applyVendorClearedToDraftEntry(entryId, false);
            return;
        }

        // Do not clear draftEntries before the async save — removing the clicked
        // Remove Vendor button in the same turn can remount the LWC back to scan.
        this.isLoading = true;
        this.workspaceError = '';
        try {
            const clearedPayload = this.toDraftItemPayload({
                ...entry,
                vendorProcessingRequired: false,
                ...this.emptyVendorFields(),
                vendorWorkOrderId: null
            });
            await saveDraftItems({
                workOrderId: this.workspace.workOrderId,
                draftItems: [clearedPayload],
                reconcileRemovedLines: false
            });
            this.applyVendorClearedToDraftEntry(entryId, false);
            await this.hydratePersistedEvaluationState(this.workspace.workOrderId);
            this.selectedTab = TAB_ITEM_SUMMARY;
            this.draftsCommitted = true;
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to remove vendor from this item.'
            );
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Clears vendor fields on one Item Summary row without navigating away.
     * @param {string} entryId Draft entry Id
     * @param {boolean} markDirty Whether the row still needs a later Quick Save
     */
    applyVendorClearedToDraftEntry(entryId, markDirty) {
        this.draftEntries = (this.draftEntries || []).map((row) =>
            row.entryId === entryId
                ? {
                      ...row,
                      vendorProcessingRequired: false,
                      ...this.emptyVendorFields(),
                      vendorWorkOrderId: null,
                      isDirty: markDirty === true
                  }
                : row
        );
    }

    handleVendorModalCancel() {
        this.vendorModalOpen = false;
        if (this.modalOpen && this.modalVendorProcessingRequired) {
            const hasVendor =
                this.vendorModalValue?.vendorAccountId &&
                this.vendorModalValue?.instructionsToVendor;
            if (!hasVendor) {
                this.modalVendorProcessingRequired = false;
                this.vendorModalValue = {};
            }
        }
        this.vendorModalEntryId = null;
    }

    handleVendorModalSave() {
        const form = this.template.querySelector('c-vendor-details-form');
        if (!form || typeof form.validate !== 'function') {
            return;
        }
        const result = form.validate();
        if (!result.valid) {
            return;
        }
        const value = result.value || form.getValue();
        this.vendorModalValue = { ...value };
        // Josh (GW-4616): one set of vendor header fields per vendor — show/edit from any line,
        // stage once, persist on the Vendor WO (not divergent per WOLI).
        if (this.vendorModalEntryId && !this.modalOpen) {
            this.applySharedVendorDetailsToDrafts(this.vendorModalEntryId, value);
        } else {
            this.modalVendorProcessingRequired = true;
            this.applySharedVendorDetailsToDrafts(this.modalEntryId, value);
        }
        this.vendorModalOpen = false;
        this.vendorModalEntryId = null;
    }

    /**
     * Propagates vendor header fields to the target draft line and every other vendor-flagged
     * line that uses the same Vendor Account.
     */
    applySharedVendorDetailsToDrafts(targetEntryId, value) {
        const fields = this.mapVendorFieldsFromValue(value);
        const vendorId = fields.vendorAccountId;
        if (!vendorId) {
            return;
        }
        this.draftEntries = (this.draftEntries || []).map((entry) => {
            const isTarget = targetEntryId && entry.entryId === targetEntryId;
            const sameVendor =
                entry.vendorProcessingRequired === true && entry.vendorAccountId === vendorId;
            if (!isTarget && !sameVendor) {
                return entry;
            }
            if (entry.vendorWorkOrderLocked === true) {
                return {
                    ...entry,
                    sterisPurchaseOrderToVendor: fields.sterisPurchaseOrderToVendor,
                    vendorNotes: fields.vendorNotes,
                    vendorReferenceNumber: fields.vendorReferenceNumber,
                    vendorCost: fields.vendorCost,
                    isDirty: true
                };
            }
            return {
                ...entry,
                vendorProcessingRequired: true,
                ...fields,
                isDirty: true
            };
        });
    }

    /**
     * Prefers existing staged details for the same vendor (or the only vendor group in play).
     */
    getPreferredSharedVendorDetails(seed) {
        const seedFields = this.mapVendorFieldsFromValue(seed);
        if (seedFields.vendorAccountId) {
            const forVendor = this.getSharedVendorDetails(seedFields.vendorAccountId);
            if (forVendor) {
                return forVendor;
            }
            return seedFields.instructionsToVendor ? seedFields : null;
        }
        return this.getSingleSharedVendorDetailsIfUnique();
    }

    getSharedVendorDetails(vendorAccountId) {
        if (!vendorAccountId) {
            return null;
        }
        const match = (this.draftEntries || []).find(
            (entry) =>
                entry.vendorProcessingRequired === true &&
                entry.vendorAccountId === vendorAccountId &&
                String(entry.instructionsToVendor || '').trim()
        );
        return match ? this.mapVendorFieldsFromValue(match) : null;
    }

    getSingleSharedVendorDetailsIfUnique() {
        const vendorIds = new Set();
        let sample = null;
        (this.draftEntries || []).forEach((entry) => {
            if (entry.vendorProcessingRequired === true && entry.vendorAccountId) {
                vendorIds.add(entry.vendorAccountId);
                if (!sample && String(entry.instructionsToVendor || '').trim()) {
                    sample = entry;
                }
            }
        });
        if (vendorIds.size !== 1 || !sample) {
            return null;
        }
        return this.mapVendorFieldsFromValue(sample);
    }

    mapVendorFieldsFromValue(value) {
        const data = value || {};
        return {
            vendorAccountId: data.vendorAccountId || null,
            instructionsToVendor: data.instructionsToVendor || '',
            sterisPurchaseOrderToVendor: data.sterisPurchaseOrderToVendor || '',
            vendorNotes: data.vendorNotes || '',
            vendorReferenceNumber: data.vendorReferenceNumber || '',
            vendorCost: data.vendorCost,
            shippedToVendorDate: data.shippedToVendorDate || null,
            trackingNumber: data.trackingNumber || ''
        };
    }

    emptyVendorFields() {
        return {
            vendorAccountId: null,
            instructionsToVendor: '',
            sterisPurchaseOrderToVendor: '',
            vendorNotes: '',
            vendorReferenceNumber: '',
            vendorCost: null,
            shippedToVendorDate: null,
            trackingNumber: ''
        };
    }

    async saveItemModal() {
        this.modalError = '';
        const quantity = Number(this.modalQuantity);
        if (!Number.isFinite(quantity) || quantity < 1) {
            this.modalError = 'Quantity must be at least 1.';
            return;
        }
        if (!this.modalProduct?.productId) {
            this.modalError = 'Product is required.';
            return;
        }
        // Asset path allows an Item Summary line with no repair codes yet.
        if ((this.modalSelectedCodeIds || []).length === 0 && this.hasAsset !== true) {
            this.modalError = 'Select at least one repair code.';
            return;
        }
        if (this.modalVendorProcessingRequired === true) {
            const vendor = this.vendorModalValue || {};
            if (!vendor.vendorAccountId || !String(vendor.instructionsToVendor || '').trim()) {
                this.modalError =
                    'Complete Vendor details when Vendor Processing Required is checked.';
                this.vendorModalOpen = true;
                return;
            }
        }
        if (this.modalCodesLocked) {
            // Photos-only save while quantity/codes are locked.
            this.draftEntries = (this.draftEntries || []).map((entry) =>
                entry.entryId === this.modalEntryId
                    ? { ...entry, photos: [...this.modalPhotos], isDirty: true }
                    : entry
            );
            this.workspaceError = '';
            this.closeItemModal();
            this.selectedTab = TAB_ITEM_SUMMARY;
            await this.autoSaveSummaryDraftItems({
                successMessage: 'Item updated and saved.'
            });
            return;
        }

        const previousCodes =
            this.modalMode === MODAL_EDIT && this.modalEntryId
                ? (this.draftEntries || []).find((entry) => entry.entryId === this.modalEntryId)
                      ?.repairCodes || []
                : [];
        const repairCodes = this.resolveSelectedCodes(
            this.modalSelectedCodeIds,
            this.modalCategoryCodes,
            this.modalServiceCodes,
            previousCodes
        );
        const duplicate = this.modalDuplicateEntry;
        if (duplicate) {
            this.draftEntries = (this.draftEntries || [])
                .filter((entry) => entry.entryId !== this.modalEntryId)
                .map((entry) =>
                    entry.entryId === duplicate.entryId
                        ? {
                              ...entry,
                              quantity,
                              photos: [...this.modalPhotos],
                              isDirty: entry.isPersisted === true || !!entry.productServicedId
                          }
                        : entry
                );
        } else if (this.modalMode === MODAL_EDIT && this.modalEntryId) {
            this.draftEntries = (this.draftEntries || []).map((entry) =>
                entry.entryId === this.modalEntryId
                    ? {
                          ...entry,
                          quantity,
                          repairCodes,
                          photos: [...this.modalPhotos],
                          vendorProcessingRequired: this.modalVendorProcessingRequired === true,
                          ...this.mapVendorFieldsFromValue(
                              this.modalVendorProcessingRequired
                                  ? this.vendorModalValue
                                  : this.emptyVendorFields()
                          ),
                          isDirty: entry.isPersisted === true || !!entry.productServicedId
                      }
                    : entry
            );
        } else {
            this.draftEntries = [
                ...(this.draftEntries || []),
                this.buildDraftEntry({
                    product: this.modalProduct,
                    quantity,
                    repairCodes,
                    photos: [...this.modalPhotos],
                    vendorProcessingRequired: this.modalVendorProcessingRequired === true,
                    vendorFields: this.modalVendorProcessingRequired
                        ? this.vendorModalValue
                        : this.emptyVendorFields()
                })
            ];
        }
        if (this.modalVendorProcessingRequired === true && this.vendorModalValue?.vendorAccountId) {
            const targetId =
                this.modalMode === MODAL_EDIT && this.modalEntryId
                    ? this.modalEntryId
                    : (this.draftEntries || [])[this.draftEntries.length - 1]?.entryId;
            this.applySharedVendorDetailsToDrafts(targetId, this.vendorModalValue);
        }
        this.draftsCommitted = false;
        this.workspaceError = '';
        this.pruneStagedSignaturesToDraftEntries();
        const returnToAddItems = this.modalMode === MODAL_ADD;
        const wasEdit = this.modalMode === MODAL_EDIT;
        this.closeItemModal();
        if (returnToAddItems) {
            this.resetAddItemsDrillDown(false);
            if (!(this.evalCategories || []).length && this.canAddItems) {
                this.loadEvalCategories();
            }
            this.selectedTab = TAB_ADD_ITEMS;
        } else {
            this.selectedTab = TAB_ITEM_SUMMARY;
        }
        await this.autoSaveSummaryDraftItems({
            successMessage: wasEdit ? 'Item updated and saved.' : 'Item added and saved.'
        });
    }

    async saveAssetEntry() {
        this.assetError = '';
        if (!this.workspace?.productId) {
            this.assetError = 'Asset Product is required.';
            return;
        }
        const existing = this.assetSummaryEntry;
        if (existing && this.assetCodesLocked) {
            this.draftEntries = (this.draftEntries || []).map((entry) =>
                entry.entryId === existing.entryId
                    ? {
                          ...entry,
                          photos: [...this.assetPhotos],
                          isDirty: entry.isPersisted === true || !!entry.productServicedId
                      }
                    : entry
            );
            this.draftsCommitted = false;
            this.workspaceError = '';
            this.pruneStagedSignaturesToDraftEntries();
            this.resetAssetEditor(true);
            this.selectedTab = TAB_ITEM_SUMMARY;
            await this.autoSaveSummaryDraftItems({
                successMessage: 'Item updated and saved.'
            });
            return;
        }

        const product = {
            productId: this.workspace.productId,
            productCode: this.workspace.productCode,
            productName: this.workspace.productName
        };
        const repairCodes = this.resolveSelectedCodes(
            this.assetSelectedCodeIds,
            this.categoryCodes,
            this.serviceCodes,
            existing?.repairCodes || []
        );
        if (existing) {
            this.draftEntries = (this.draftEntries || []).map((entry) =>
                entry.entryId === existing.entryId
                    ? {
                          ...entry,
                          quantity: 1,
                          repairCodes,
                          photos: [...this.assetPhotos],
                          isDirty: entry.isPersisted === true || !!entry.productServicedId
                      }
                    : entry
            );
        } else {
            const duplicate = this.findDuplicateEntry(
                product.productId,
                this.assetSelectedCodeIds,
                null
            );
            if (duplicate) {
                this.draftEntries = (this.draftEntries || []).map((entry) =>
                    entry.entryId === duplicate.entryId
                        ? {
                              ...entry,
                              quantity: 1,
                              photos: [...this.assetPhotos],
                              isDirty: entry.isPersisted === true || !!entry.productServicedId
                          }
                        : entry
                );
            } else {
                this.draftEntries = [
                    ...(this.draftEntries || []),
                    this.buildDraftEntry({
                        product,
                        quantity: 1,
                        repairCodes,
                        photos: [...this.assetPhotos]
                    })
                ];
            }
        }
        this.draftsCommitted = false;
        this.workspaceError = '';
        this.pruneStagedSignaturesToDraftEntries();
        this.resetAssetEditor(true);
        this.selectedTab = TAB_ITEM_SUMMARY;
        await this.autoSaveSummaryDraftItems({
            successMessage: existing ? 'Item updated and saved.' : 'Item added and saved.'
        });
    }

    /**
     * Persists unsaved Item Summary rows after Add to Summary without changing Status / Sub Status.
     * @param {{successMessage?: string}} options Optional success toast after a successful save
     */
    async autoSaveSummaryDraftItems({ successMessage } = {}) {
        if (!this.workspace?.workOrderId || this.isLoading) {
            return false;
        }
        const unpersistedSnapshot = this.getDraftItemsToPersist();
        if (!unpersistedSnapshot.length) {
            return true;
        }
        this.isLoading = true;
        try {
            const productServicedIds = await saveDraftItems({
                workOrderId: this.workspace.workOrderId,
                draftItems: unpersistedSnapshot.map((entry) => this.toDraftItemPayload(entry)),
                reconcileRemovedLines: false
            });
            await this.applySavedDraftSnapshot(unpersistedSnapshot, productServicedIds);
            this.draftsCommitted = true;
            if (successMessage) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Saved',
                        message: successMessage,
                        variant: 'success'
                    })
                );
            }
            return true;
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to save Item Summary changes.'
            );
            return false;
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Merges persisted Product Serviced rows into local draft entries after auto-save.
     * @param {object[]} draftSnapshot Entries sent to saveDraftItems
     * @param {string[]} productServicedIds Returned Product Serviced Ids in draft order
     */
    async applySavedDraftSnapshot(draftSnapshot, productServicedIds) {
        if (!this.workspace?.workOrderId || !draftSnapshot?.length) {
            return;
        }
        const items = await getEvaluationItems({ workOrderId: this.workspace.workOrderId });
        const itemsByProductServicedId = new Map(
            (items || [])
                .filter((item) => item?.productServicedId)
                .map((item) => [item.productServicedId, item])
        );
        const snapshotEntryIds = new Set(draftSnapshot.map((entry) => entry.entryId));
        this.draftEntries = (this.draftEntries || []).map((entry) => {
            if (!snapshotEntryIds.has(entry.entryId)) {
                return entry;
            }
            const snapshotIndex = draftSnapshot.findIndex((row) => row.entryId === entry.entryId);
            const productServicedId =
                draftSnapshot[snapshotIndex].productServicedId ||
                (productServicedIds || [])[snapshotIndex];
            const persisted = itemsByProductServicedId.get(productServicedId);
            if (!persisted) {
                return {
                    ...entry,
                    productServicedId,
                    isPersisted: true,
                    isDirty: false
                };
            }
            return {
                ...this.mapPersistedItemToDraftEntry(persisted),
                entryId: entry.entryId
            };
        });
        try {
            const warrantyRepairRows = await getWarrantyRepairEvaluations({
                workOrderId: this.workspace.workOrderId,
                workOrderLineItemId: null
            });
            this.warrantyRepairRows = warrantyRepairRows || [];
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to refresh Warranty Repair evaluations.'
            );
        }
    }

    /**
     * Prefills Repair Codes editor from the existing Item Summary asset line.
     */
    syncAssetEditorFromSummaryEntry() {
        const entry = this.assetSummaryEntry;
        if (!entry) {
            return;
        }
        this.assetSelectedCodeIds = (entry.repairCodes || [])
            .map((code) => code.productId)
            .filter(Boolean);
        this.assetPhotos = [...(entry.photos || [])];
        this.assetError = '';
    }

    buildDraftEntry({ product, quantity, repairCodes, photos, vendorProcessingRequired, vendorFields }) {
        this._entrySeq += 1;
        const vendor = this.mapVendorFieldsFromValue(vendorFields);
        return {
            entryId: `draft-${Date.now()}-${this._entrySeq}`,
            productId: product.productId,
            productCode: product.productCode || '',
            productName: product.productName || '',
            quantity,
            returnOrderLineItemIds: null,
            returnOrderLineItems: '',
            repairCodes: repairCodes || [],
            photos: photos || [],
            vendorProcessingRequired: vendorProcessingRequired === true,
            vendorWorkOrderLocked: false,
            ...vendor
        };
    }

    resolveSelectedCodes(selectedIds, categoryCodes, serviceCodes, existingCodes) {
        const byId = new Map();
        [...(categoryCodes || []), ...(serviceCodes || [])].forEach((row) => {
            if (row?.productId) {
                byId.set(row.productId, row);
            }
        });
        const existingByProductId = new Map();
        (existingCodes || []).forEach((code) => {
            if (code?.productId) {
                existingByProductId.set(code.productId, code);
            }
        });
        return (selectedIds || [])
            .map((id) => byId.get(id))
            .filter(Boolean)
            .map((row) => {
                const existing = existingByProductId.get(row.productId);
                return {
                    productId: row.productId,
                    productCode: row.productCode,
                    productName: row.productName,
                    codeType: row.codeType,
                    workOrderLineItemId: existing?.workOrderLineItemId || null,
                    status: existing?.status
                };
            });
    }

    findDuplicateEntry(productId, codeIds, excludeEntryId) {
        const target = [...(codeIds || [])].map(String).sort().join('|');
        if (!target) {
            return null;
        }
        return (this.draftEntries || []).find((entry) => {
            if (excludeEntryId && entry.entryId === excludeEntryId) {
                return false;
            }
            if (entry.productId !== productId) {
                return false;
            }
            const current = (entry.repairCodes || [])
                .map((code) => String(code.productId))
                .sort()
                .join('|');
            return current === target;
        });
    }

    countEntriesForProduct(productId) {
        return (this.draftEntries || []).filter((entry) => entry.productId === productId).length;
    }

    ensurePhotosReady() {
        if (this.workspace?.photosRequired !== true || this.workspace?.unableToTakePhoto === true) {
            return true;
        }
        const hasAnyPhoto = (this.draftEntries || []).some(
            (entry) => (entry.photos || []).length > 0
        );
        if (!hasAnyPhoto) {
            this.workspaceError = this.getPhotosRequiredMessage();
            this.selectedTab = TAB_ITEM_SUMMARY;
            return false;
        }
        return true;
    }

    /**
     * GW-3400 / GW-5335 - Work Performed rows from Item Summary repair codes.
     * All selected codes stay visible; Sign is only offered when Status is Approved.
     */
    get workPerformedSignableRows() {
        const persisted = this.repairSignatures || [];
        const staged = this.stagedRepairSignatures || [];
        const rows = [];
        (this.draftEntries || []).forEach((entry) => {
            (entry.repairCodes || []).forEach((code, codeIndex) => {
                if (!code?.productId) {
                    return;
                }
                const status = this.resolveRepairCodeStatus(code);
                const woliId = code.workOrderLineItemId || null;
                const rowKey = woliId
                    ? woliId
                    : this.buildSignRowKey(entry.entryId, code.productId) ||
                      `${entry.entryId}-${codeIndex}`;
                const persistedForRow = woliId
                    ? persisted.filter(
                          (signature) => signature.workOrderLineItemId === woliId
                      )
                    : [];
                const stagedForRow = staged.filter(
                    (signature) =>
                        signature.entryId === entry.entryId &&
                        signature.repairCodeProductId === code.productId
                );
                const rowSignatures = [...persistedForRow, ...stagedForRow].map((signature) =>
                    this.decorateRepairSignature(signature)
                );
                const currentUserAlreadySigned = rowSignatures.some(
                    (signature) => signature.userId === currentUserId
                );
                rows.push({
                    rowKey,
                    entryId: entry.entryId,
                    workOrderLineItemId: woliId,
                    productId: code.productId,
                    itemNumber: entry.productCode || '',
                    itemDescription: entry.productName || '',
                    quantity: entry.quantity,
                    repairCodeName: code.productName || code.productCode || '',
                    status,
                    signatures: rowSignatures,
                    hasSignatures: rowSignatures.length > 0,
                    showSignButton:
                        status === WOLI_STATUS_APPROVED && !currentUserAlreadySigned,
                    signDisabled: this.isBusy || currentUserAlreadySigned
                });
            });
        });
        return rows;
    }

    get hasWorkPerformedSignableRows() {
        return this.workPerformedSignableRows.length > 0;
    }

    get isSignAllDisabled() {
        return (
            this.isBusy ||
            !this.workPerformedSignableRows.some((row) => row.showSignButton)
        );
    }

    get signableWorkOrderLineItemIds() {
        return this.workPerformedSignableRows
            .filter((row) => row.workOrderLineItemId && row.showSignButton)
            .map((row) => row.workOrderLineItemId);
    }

    /**
     * GW-3400 / GW-5335 - When Status = Repair, every Approved Work Performed repair-code
     *              row must have at least one signature (persisted or staged).
     */
    hasUnsignedRepairCodes() {
        if (!this.isRepairStatus) {
            return false;
        }
        return this.workPerformedSignableRows.some(
            (row) => row.status === WOLI_STATUS_APPROVED && !row.hasSignatures
        );
    }

    /**
     * GW-3400 - Opens the Device Evaluation-style camera / upload modal.
     * @param {string} target PHOTO_TARGET_MODAL or PHOTO_TARGET_ASSET
     */
    async openPhotoModal(target) {
        this.photoModalTarget = target;
        const productId = this.photoStageProductId;
        if (!productId) {
            const message = 'A product is required before taking photos.';
            if (target === PHOTO_TARGET_MODAL) {
                this.modalError = message;
            } else {
                this.assetError = message;
            }
            return;
        }
        this.isPhotoModalOpen = true;
        this.cameraError = '';
        await this.loadCameras();
    }

    handleClosePhotoModal() {
        this.stopCameraStream();
        this.isPhotoModalOpen = false;
        this.cameraError = '';
    }

    handleChooseFilesClick() {
        const input = this.template.querySelector('[data-id="staged-file-input"]');
        if (input) {
            input.click();
        }
    }

    async handleStagedFileSelected(event) {
        const files = Array.from(event.target.files || []);
        event.target.value = '';
        if (!files.length) {
            return;
        }
        this.isUploadingFiles = true;
        this.cameraError = '';
        try {
            await this.stagePhotoFiles(files, this.photoModalTarget === PHOTO_TARGET_MODAL);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Upload staged',
                    message:
                        files.length === 1
                            ? '1 file staged for this item.'
                            : `${files.length} files staged for this item.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.cameraError = this.resolveErrorMessage(error, 'Unable to stage uploaded files.');
        } finally {
            this.isUploadingFiles = false;
        }
    }

    async stagePhotoFiles(files, forModal) {
        const productId = forModal
            ? this.modalProduct?.productId
            : this.workspace?.productId;
        if (!productId || !files?.length) {
            return;
        }
            for (const file of files) {
                const base64Data = await this.readFileAsDataUrl(file);
                const result = await stageEvaluationPhoto({
                    productId,
                    base64Data,
                    fileName: file.name
                });
            this.appendStagedPhoto(result, file.name, forModal);
        }
    }

    appendStagedPhoto(result, fallbackTitle, forModal) {
        const file = result.file || {};
        const title = file.title || fallbackTitle;
        const extensionFromName = (
            file.fileExtension ||
            this.extensionFromTitle(fallbackTitle) ||
            this.extensionFromTitle(title) ||
            ''
        ).toLowerCase();
        const resolvedExtension = IMAGE_EXTENSIONS.has(extensionFromName)
            ? extensionFromName
            : extensionFromName || 'jpg';
        const photo = {
            contentDocumentId: result.contentDocumentId || file.contentDocumentId,
            title,
            editTitle: title,
            thumbnailUrl: file.imageDownloadUrl || file.thumbnailUrl || '',
            imageDownloadUrl: file.imageDownloadUrl || file.thumbnailUrl || '',
            downloadUrl: file.downloadUrl || '',
            fileExtension: resolvedExtension,
            fileType: file.fileType || resolvedExtension,
            isImage: true,
            isLinked: false
        };
        if (!photo.contentDocumentId) {
            return;
        }
        if (forModal) {
            this.modalPhotos = [...(this.modalPhotos || []), photo];
        } else {
            this.assetPhotos = [...(this.assetPhotos || []), photo];
            this.applyAssetPhotosToSummaryEntry();
        }
    }

    /**
     * GW-3400 - Keeps Item Summary photos in sync when capturing from the asset Repair Codes tab.
     */
    applyAssetPhotosToSummaryEntry() {
        const existing = this.assetSummaryEntry;
        if (!existing) {
            return;
        }
        this.draftEntries = (this.draftEntries || []).map((entry) =>
            entry.entryId === existing.entryId
                ? {
                      ...entry,
                      photos: [...(this.assetPhotos || [])],
                      isDirty:
                          entry.isPersisted === true ||
                          !!entry.productServicedId ||
                          entry.isDirty === true
                  }
                : entry
        );
        this.draftsCommitted = false;
    }

    async loadCameras() {
        this.cameraError = '';
        if (
            !navigator.mediaDevices ||
            typeof navigator.mediaDevices.getUserMedia !== 'function'
        ) {
            this.cameraOptions = [];
            this.cameraError =
                'This browser does not support camera capture. Use Chrome, Edge, Firefox, or Safari.';
            return;
        }

        try {
            const permissionStream = await navigator.mediaDevices.getUserMedia({
                video: true,
                audio: false
            });
            permissionStream.getTracks().forEach((track) => track.stop());

            const devices = await navigator.mediaDevices.enumerateDevices();
            const videoInputs = devices.filter((device) => device.kind === 'videoinput');
            this.cameraOptions = videoInputs.map((device, index) => ({
                label: device.label || `Camera ${index + 1}`,
                value: device.deviceId
            }));
            if (this.cameraOptions.length > 0 && !this.selectedCameraId) {
                this.selectedCameraId = this.cameraOptions[0].value;
            }
            if (this.cameraOptions.length === 0) {
                this.cameraError = 'No cameras were found on this device.';
            }
        } catch (error) {
            this.cameraOptions = [];
            this.cameraError = this.resolveErrorMessage(
                error,
                'Unable to access cameras. Check browser permissions.'
            );
        }
    }

    handleCameraChange(event) {
        this.selectedCameraId = event.detail.value;
    }

    async handleStartCamera() {
        this.cameraError = '';
        if (!this.selectedCameraId) {
            this.cameraError = 'Select a camera before starting.';
            return;
        }
        this.isCameraStarting = true;
        try {
            this.stopCameraStream();
            this.mediaStream = await this.openCameraStream(this.selectedCameraId);
            this.isCameraActive = true;
            // Wait a tick so the manual DOM video element is available.
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this.bindVideoElement(), 0);
        } catch (error) {
            this.isCameraActive = false;
            this.cameraError = this.resolveErrorMessage(
                error,
                'Failed to start the selected camera.'
            );
        } finally {
            this.isCameraStarting = false;
        }
    }

    async openCameraStream(deviceId) {
        try {
            return await navigator.mediaDevices.getUserMedia({
                audio: false,
                video: {
                    deviceId: { exact: deviceId },
                    width: { ideal: 1280 },
                    height: { ideal: 720 }
                }
            });
        } catch (error) {
            return navigator.mediaDevices.getUserMedia({
                audio: false,
                video: true
            });
        }
    }

    bindVideoElement() {
        this.videoEl = this.template.querySelector('video');
        this.canvasEl = this.template.querySelector('canvas');
        if (this.videoEl && this.mediaStream) {
            this.videoEl.srcObject = this.mediaStream;
            const playPromise = this.videoEl.play();
            if (playPromise && typeof playPromise.catch === 'function') {
                playPromise.catch(() => {
                    // Autoplay can fail briefly; capture still works if a frame is available.
                });
            }
        }
    }

    handleStopCamera() {
        this.stopCameraStream();
    }

    stopCameraStream() {
        if (this.mediaStream) {
            this.mediaStream.getTracks().forEach((track) => track.stop());
            this.mediaStream = undefined;
        }
        if (this.videoEl) {
            this.videoEl.srcObject = null;
        }
        this.isCameraActive = false;
        this.isCameraStarting = false;
    }

    async handleCapturePhoto() {
        if (!this.isCameraActive || this.isCapturing) {
            return;
        }
        this.cameraError = '';
        this.isCapturing = true;

        try {
            if (!this.videoEl) {
                this.bindVideoElement();
            }
            if (!this.videoEl || !this.canvasEl) {
                throw new Error('Camera preview is not ready.');
            }

            const width = this.videoEl.videoWidth || 1280;
            const height = this.videoEl.videoHeight || 720;
            this.canvasEl.width = width;
            this.canvasEl.height = height;
            const context = this.canvasEl.getContext('2d');
            context.drawImage(this.videoEl, 0, 0, width, height);
            const productId = this.photoStageProductId;
            if (!productId) {
                throw new Error('A product is required before capturing a photo.');
            }
            const dataUrl = this.canvasEl.toDataURL('image/jpeg', 0.92);
            const fileName = `InstrumentEval-${this.todayIsoDate()}-${Date.now()}.jpg`;

            const result = await stageEvaluationPhoto({
                productId,
                base64Data: dataUrl,
                fileName
            });
            this.appendStagedPhoto(
                result,
                fileName,
                this.photoModalTarget === PHOTO_TARGET_MODAL
            );
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Photo staged',
                    message: result.message || 'Photo staged for this item.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.cameraError = this.resolveErrorMessage(error, 'Unable to capture photo.');
        } finally {
            this.isCapturing = false;
        }
    }

    todayIsoDate() {
        const today = new Date();
        const month = String(today.getMonth() + 1).padStart(2, '0');
        const day = String(today.getDate()).padStart(2, '0');
        return `${today.getFullYear()}-${month}-${day}`;
    }

    async deleteStagedPhoto(contentDocumentId, forModal) {
        if (!contentDocumentId) {
            return;
        }
        const deleting = new Set(this.deletingDocumentIds);
        deleting.add(contentDocumentId);
        this.deletingDocumentIds = deleting;
        try {
            const photo = forModal
                ? (this.modalPhotos || []).find(
                      (row) => row.contentDocumentId === contentDocumentId
                  )
                : (this.assetPhotos || []).find(
                      (row) => row.contentDocumentId === contentDocumentId
                  );
            const productServicedId = forModal
                ? (this.draftEntries || []).find(
                      (entry) => entry.entryId === this.modalEntryId
                  )?.productServicedId
                : this.assetSummaryEntry?.productServicedId;

            if (photo?.isLinked === true && productServicedId && this.workspace?.workOrderId) {
                await removeEvaluationPhoto({
                    workOrderId: this.workspace.workOrderId,
                    productServicedId,
                    contentDocumentId
                });
            } else {
                await deleteStagedEvaluationPhoto({ contentDocumentId });
            }

            if (forModal) {
                this.modalPhotos = (this.modalPhotos || []).filter(
                    (row) => row.contentDocumentId !== contentDocumentId
                );
                if (this.modalEntryId) {
                    this.draftEntries = (this.draftEntries || []).map((entry) =>
                        entry.entryId === this.modalEntryId
                            ? {
                                  ...entry,
                                  photos: (entry.photos || []).filter(
                                      (row) => row.contentDocumentId !== contentDocumentId
                                  ),
                                  isDirty:
                                      entry.isPersisted === true ||
                                      !!entry.productServicedId ||
                                      entry.isDirty === true
                              }
                            : entry
                    );
                    this.draftsCommitted = false;
                }
            } else {
                this.assetPhotos = (this.assetPhotos || []).filter(
                    (row) => row.contentDocumentId !== contentDocumentId
                );
                this.applyAssetPhotosToSummaryEntry();
            }
        } catch (error) {
            const message = this.resolveErrorMessage(error, 'Unable to delete photo.');
            if (this.isPhotoModalOpen) {
                this.cameraError = message;
            } else if (forModal) {
                this.modalError = message;
            } else {
                this.assetError = message;
            }
        } finally {
            const remaining = new Set(this.deletingDocumentIds);
            remaining.delete(contentDocumentId);
            this.deletingDocumentIds = remaining;
        }
    }

    /**
     * GW-3400 - Ensures the asset Work Order has an Item Summary draft line immediately
     *              (repair codes optional; can be added later on the Repair Codes tab).
     */
    ensureAssetSummaryEntry() {
        if (this.hasAsset !== true || !this.workspace?.productId) {
            return;
        }
        if (this.assetSummaryEntry) {
            return;
        }
        this.draftEntries = [
            ...(this.draftEntries || []),
            this.buildDraftEntry({
                product: {
                    productId: this.workspace.productId,
                    productCode: this.workspace.productCode,
                    productName: this.workspace.productName
                },
                quantity: 1,
                repairCodes: [],
                photos: []
            })
        ];
        this.draftsCommitted = false;
    }

    readFileAsDataUrl(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(reader.error || new Error('Unable to read file.'));
            reader.readAsDataURL(file);
        });
    }

    toGridCards(rows, idFn, titleFn, nameFn, selectedValue) {
        const selectedIds = Array.isArray(selectedValue)
            ? new Set(selectedValue)
            : new Set(selectedValue ? [selectedValue] : []);
        return (rows || []).map((row) => {
            const cardId = idFn(row);
            return {
                cardId,
                title: titleFn(row) || '',
                name: nameFn(row) || '',
                selected: selectedIds.has(cardId)
            };
        });
    }

    parseTurnTime(value) {
        const trimmed = (value || '').trim();
        if (!trimmed) {
            return null;
        }
        const parsed = Number(trimmed);
        return Number.isFinite(parsed) ? parsed : null;
    }

    parseQuantityReceived(value) {
        const trimmed = (value || '').trim();
        if (!trimmed) {
            return null;
        }
        const parsed = Number(trimmed);
        return Number.isFinite(parsed) ? parsed : null;
    }

    /**
     * @description Pulls Quantity Received from the sticky header input before validate/save.
     *              Avoids LWC controlled-input drift where the visible value can differ from
     *              quantityReceivedInputValue (Josh intermittent Next mismatch).
     */
    syncQuantityReceivedFromDom() {
        const inputEl = this.template.querySelector('#header-quantity-received');
        if (!inputEl || inputEl.value == null) {
            return;
        }
        const domValue = String(inputEl.value);
        if (domValue !== this.quantityReceivedInputValue) {
            this.quantityReceivedInputValue = domValue;
        }
    }

    /**
     * @description Normalizes item / received quantities for whole-number comparison.
     * @param {number} value Parsed quantity
     * @returns {number}
     */
    normalizeQuantityForCompare(value) {
        return Math.round(Number(value));
    }

    /**
     * GW-5324 - Evaluate & Quote and Repair require an RO Line mapping on every summary item.
     * @returns {boolean} True when the current status does not require mappings or all are assigned
     */
    ensureReturnOrderLinesAssigned() {
        if (
            this.workspace?.status !== STATUS_EVALUATE_QUOTE &&
            this.workspace?.status !== STATUS_REPAIR
        ) {
            return true;
        }
        const hasMissingAssignment = (this.draftEntries || []).some(
            (entry) => !String(entry.returnOrderLineItems || '').trim()
        );
        if (hasMissingAssignment) {
            this.workspaceError = RO_LINE_REQUIRED_MESSAGE;
            return false;
        }
        return true;
    }

    /**
     * GW-3400 - Quantity Received is required and must equal the sum of Item Summary quantities.
     * @returns {boolean} True when valid
     */
    ensureQuantityReceivedMatchesItems() {
        this.syncQuantityReceivedFromDom();
        const quantityReceived = this.parseQuantityReceived(this.quantityReceivedInputValue);
        const noun = this.completeContextNoun;
        if (quantityReceived == null || quantityReceived < 0) {
            this.workspaceError = `Quantity Received is required before completing the ${noun}.`;
            return false;
        }
        let totalItemQuantity = 0;
        (this.draftEntries || []).forEach((entry) => {
            const qty = Number(entry?.quantity);
            if (Number.isFinite(qty)) {
                totalItemQuantity += qty;
            }
        });
        if (
            this.normalizeQuantityForCompare(totalItemQuantity) !==
            this.normalizeQuantityForCompare(quantityReceived)
        ) {
            this.workspaceError =
                `Total item quantity must equal Quantity Received before completing the ${noun}. ` +
                `(items: ${totalItemQuantity}, received: ${quantityReceived}).`;
            return false;
        }
        return true;
    }

    resetToScan() {
        this.mode = MODE_SCAN;
        this.workspace = undefined;
        this.workspaceError = '';
        this.errorMessage = '';
        this.selectedTab = TAB_WO_DETAILS;
        this.turnTimeInputValue = '';
        this.quantityReceivedInputValue = '';
        this.workOrderInput = '';
        this.draftEntries = [];
        this.warrantyRepairRows = [];
        this.wreModalOpen = false;
        this.wreModalWoliId = null;
        this.wreModalAllowMultiple = false;
        this.wreModalMaxCount = 1;
        this.draftsCommitted = false;
        this.repairSignatures = [];
        this.stagedRepairSignatures = [];
        this.resetAddItemsDrillDown(false);
        this.resetAssetEditor(true);
        this.evalCategories = [];
        this.closeItemModal();
        this.closeRoLineModal();
        this.clearWorkspaceHeight();
        this.classList.remove('is-evaluation');
        this.updateBrowserTitle();
    }

    syncSubStatusSelectValue() {
        const selectEl = this.template.querySelector('.sticky-field__control_select');
        const current = this.workspace?.subStatus == null ? '' : String(this.workspace.subStatus);
        if (!selectEl || selectEl.value === current) {
            return;
        }
        selectEl.value = current;
    }

    scheduleWorkspaceHeightSync() {
        if (this._heightFrame) {
            cancelAnimationFrame(this._heightFrame);
        }
        this._heightFrame = requestAnimationFrame(() => {
            this._heightFrame = requestAnimationFrame(() => {
                this._heightFrame = undefined;
                this.syncWorkspaceHeight();
            });
        });
    }

    syncWorkspaceHeight() {
        if (!this.isEvaluationShellMode) {
            this.clearWorkspaceHeight();
            return;
        }
        const hostRect = this.getBoundingClientRect();
        const scrollParent = this.findScrollParent();
        let available;
        if (scrollParent && scrollParent !== document.documentElement) {
            const parentRect = scrollParent.getBoundingClientRect();
            available = Math.floor(parentRect.bottom - hostRect.top - 4);
        } else {
            available = Math.floor(window.innerHeight - hostRect.top - 12);
        }
        available = Math.max(available, 280);
        const px = `${available}px`;
        this.style.setProperty('--eval-available-height', px);
        this.style.height = px;
        this.style.maxHeight = px;
        this.style.overflow = 'hidden';
    }

    clearWorkspaceHeight() {
        this.style.removeProperty('--eval-available-height');
        this.style.height = '';
        this.style.maxHeight = '';
        this.style.overflow = '';
    }

    findScrollParent() {
        let node = this.parentElement;
        while (node && node !== document.body) {
            const style = window.getComputedStyle(node);
            const overflowY = style.overflowY;
            if (overflowY === 'auto' || overflowY === 'scroll') {
                return node;
            }
            node = node.parentElement;
        }
        return document.documentElement;
    }

    resolveErrorMessage(error, fallback) {
        const bodyMessage = error?.body?.message;
        const message = error?.message;
        return bodyMessage || message || fallback;
    }
}