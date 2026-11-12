import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import currentUserId from '@salesforce/user/Id';
import initializeEvaluation from '@salesforce/apex/DeviceEvaluationController.initializeEvaluation';
import stageEvaluationPhoto from '@salesforce/apex/DeviceEvaluationController.stageEvaluationPhoto';
import renameStagedEvaluationPhoto from '@salesforce/apex/DeviceEvaluationController.renameStagedEvaluationPhoto';
import deleteStagedEvaluationPhoto from '@salesforce/apex/DeviceEvaluationController.deleteStagedEvaluationPhoto';
import removeEvaluationPhoto from '@salesforce/apex/DeviceEvaluationController.removeEvaluationPhoto';
import saveEvaluation from '@salesforce/apex/DeviceEvaluationController.saveEvaluation';
import completeEvaluation from '@salesforce/apex/DeviceEvaluationController.completeEvaluation';
import returnToEvaluation from '@salesforce/apex/DeviceEvaluationController.returnToEvaluation';
import addRepairSignature from '@salesforce/apex/DeviceEvaluationController.addRepairSignature';
import signAllRepairCodes from '@salesforce/apex/DeviceEvaluationController.signAllRepairCodes';
import removeRepairSignature from '@salesforce/apex/DeviceEvaluationController.removeRepairSignature';
import finalizeDeviceEvaluationAfterPricing from '@salesforce/apex/DeviceEvaluationController.finalizeDeviceEvaluationAfterPricing';

const MODE_SCAN = 'scan';
const MODE_EVALUATION = 'evaluation';
const MODE_SUMMARY = 'summary';
const BROWSER_TAB_LABEL = 'Device Evaluation';
const FILE_ACCEPT = '.jpg,.jpeg,.png,.gif,.bmp,.webp,.mp4,.mov,.pdf,.doc,.docx,.xls,.xlsx';
const SCAN_FIELD_LABEL = 'Work Order Id / Number';
const SCAN_FIELD_PLACEHOLDER = 'Scan or enter Work Order Id / Number';
const TAB_WO_DETAILS = 'wo-details';
const TAB_VENDOR = 'vendor-information';
const TAB_ASSET = 'asset';
const TAB_PREFERENCES = 'preferences';
const TAB_NOTES = 'notes';
const TAB_WRE = 'warranty-repair-evaluation';
const TAB_MODIFIER_CODES = 'modifier-codes';
const TAB_CATEGORY = 'category';
const TAB_WORK_PERFORMED = 'work-performed';
const TAB_PRODUCT_REQUESTS = 'product-requests';
const SUBSTATUS_SHIP_TO_VENDOR = 'Ship to Vendor';
const STATUS_EVALUATE = 'Evaluate';
const STATUS_REPAIR = 'Repair';
const ESTIMATE_REQUIRED = 'Estimate Required';
const ESTIMATE_ORDER_ACKNOWLEDGEMENT = 'Order Acknowledgement';
const ESTIMATE_PRE_APPROVED = 'Pre-Approved';
const REPAIR_UNSIGNED_MESSAGE =
    'You cannot complete repair until all repair codes have been signed.';
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
const SHIP_TO_VENDOR_NEXT_MESSAGE =
    "Repair cannot be completed if sending to a Vendor. Please 'Save & Close' to commit your changes";
const PHOTO_REQUIRED_MESSAGE =
    "Photos are required for this item. Please upload photos, or if unable to do so, check that you are ‘Unable to Take Photo’.";
const SUMMARY_GROUP_PRICING = 'Pricing Codes';
const PRICING_CODE_TYPES = new Set(['Category Code', 'Special Pricing']);
const SIGNABLE_CODE_TYPES = new Set(['Category Code', 'Service Code']);
const CODE_TYPE_OBSERVATION = 'Observation Code';
const CONDITION_OK = 'Ok';
const USAGE_COUNT_PRODUCT_LINES = new Set(['FLEXIBLE SCOPE', 'ENDOCAM']);
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

export default class DeviceEvaluation extends LightningElement {
    mode = MODE_SCAN;
    workOrderNumber = '';
    isLoading = false;
    errorMessage = '';
    workspaceError = '';
    activeTab = TAB_WO_DETAILS;
    fileAccept = FILE_ACCEPT;

    @track evaluation;
    @track selectedProductIdSet = new Set();
    lastPersistedProductIds = [];
    /** Staged/linked photos awaiting Complete attach to Repair Code WOLIs. */
    @track stagedPhotos = [];
    @track cameraOptions = [];
    @track deletingDocumentIds = new Set();
    @track thumbnailFallbackIds = new Set();

    selectedCameraId = '';
    isCameraStarting = false;
    isCameraActive = false;
    isCapturing = false;
    isUploadingFiles = false;
    isPhotoModalOpen = false;
    photoModalProductId = '';
    photoModalProductCode = '';
    photoModalProductName = '';
    isCompleting = false;
    isSaving = false;
    cameraError = '';
    mediaStream;
    videoEl;
    canvasEl;

    _resizeBound;
    _heightFrame;

    get isScanMode() {
        return this.mode === MODE_SCAN;
    }

    get workOrderId() {
        return this.evaluation?.workOrderId;
    }

    get assetId() {
        return this.evaluation?.assetId;
    }

    get hasProductLink() {
        return Boolean(this.evaluation?.productId);
    }

    get productRecordUrl() {
        const productId = this.evaluation?.productId;
        return productId ? `/${productId}` : null;
    }

    get productDisplayName() {
        return this.evaluation?.productName || this.evaluation?.productId || '';
    }

    get isEvaluationMode() {
        return this.mode === MODE_EVALUATION;
    }

    get isSummaryMode() {
        return this.mode === MODE_SUMMARY;
    }

    get isWorkspaceMode() {
        return this.isEvaluationMode || this.isSummaryMode;
    }

    get rootClass() {
        return this.isWorkspaceMode
            ? 'device-evaluation-root device-evaluation-root_eval'
            : 'device-evaluation-root device-evaluation-root_scan slds-p-around_medium';
    }

    get contentContainerClass() {
        return this.isWorkspaceMode ? 'evaluation-content' : 'slds-p-around_medium';
    }

    get warrantyRepairEvaluations() {
        return this.evaluation?.warrantyRepairEvaluations || [];
    }

    get isRepairStatus() {
        return this.evaluation?.status === STATUS_REPAIR;
    }

    get showRepairCostHeader() {
        return this.isEvaluationMode && this.isRepairStatus;
    }

    get currentRepairCostDisplay() {
        return this.formatRepairCost(this.evaluation?.originalNetTotalPrice);
    }

    get updatedRepairCostDisplay() {
        return this.formatRepairCost(this.evaluation?.newNetTotalPrice);
    }

    formatRepairCost(value) {
        const amount = value == null || value === '' ? 0 : Number(value);
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(Number.isNaN(amount) ? 0 : amount);
    }

    get isCompleteDisabled() {
        return this.isCompleting || this.isSaving;
    }

    get isActionBusy() {
        return this.isCompleting || this.isSaving;
    }

    get scanFieldLabel() {
        return SCAN_FIELD_LABEL;
    }

    get scanFieldPlaceholder() {
        return SCAN_FIELD_PLACEHOLDER;
    }

    get showContaminatedWarning() {
        const subStatus = this.evaluation?.subStatus;
        return typeof subStatus === 'string' && subStatus.toLowerCase().includes('contaminat');
    }

    /**
     * GW-4750 - True when the Work Order has a Continuous Improvement Opportunity.
     */
    get showCioIndicator() {
        return this.evaluation?.continuousImprovementOpportunity === true;
    }

    /**
     * GW-5696 - True when the Work Order is marked Ship Complete.
     */
    get showShipCompleteIndicator() {
        return this.evaluation?.shipComplete === true;
    }

    get contaminationValue() {
        return this.evaluation?.contamination;
    }

    get woInfoStatus() {
        return this.displayWoInfoText(this.evaluation?.status);
    }

    get woInfoRepairWarranty() {
        return this.displayWoInfoText(this.evaluation?.repairWarranty);
    }

    get woInfoDescription() {
        return this.displayWoInfoText(this.evaluation?.description);
    }

    get woInfoEstimateRequired() {
        return this.displayWoInfoText(this.evaluation?.estimateRequired);
    }

    get woInfoCustomerPo() {
        return this.displayWoInfoText(this.evaluation?.customerPO);
    }

    displayWoInfoText(value) {
        return value == null || value === '' ? '' : String(value);
    }

    get assetInfoName() {
        return this.displayWoInfoText(this.evaluation?.assetName);
    }

    get assetInfoSerialNumber() {
        return this.displayWoInfoText(this.evaluation?.serialNumber);
    }

    get assetInfoManufacturer() {
        return this.displayWoInfoText(this.evaluation?.manufacturer);
    }

    get assetInfoModel() {
        return this.displayWoInfoText(this.evaluation?.model);
    }

    get assetInfoProductLine() {
        return this.displayWoInfoText(this.evaluation?.productLine);
    }

    get subStatusOptions() {
        const options = this.evaluation?.subStatusOptions || [];
        return options.map((option) => ({
            label: option.label,
            value: option.value
        }));
    }

    get turnTimeInputValue() {
        const turnTime = this.evaluation?.turnTime;
        return turnTime === null || turnTime === undefined ? '' : String(turnTime);
    }

    get usageCountInputValue() {
        return this.evaluation?.usageCount == null ? '' : String(this.evaluation.usageCount);
    }

    get usageCountDateInput() {
        const value = this.evaluation?.usageCountDate;
        if (!value) {
            return '';
        }
        if (typeof value === 'string') {
            return value.substring(0, 10);
        }
        return value;
    }

    get usageCountDateDisplay() {
        const value = this.usageCountDateInput;
        if (!value) {
            return '—';
        }
        const parts = String(value).split('-');
        if (parts.length !== 3) {
            return value;
        }
        const year = Number(parts[0]);
        const month = Number(parts[1]);
        const day = Number(parts[2]);
        if (!year || !month || !day) {
            return value;
        }
        return new Date(year, month - 1, day).toLocaleDateString(undefined, {
            year: 'numeric',
            month: 'short',
            day: 'numeric'
        });
    }

    get showUsageCountFields() {
        // Visible only when WO.Product Line (ProductLine_f__c) is Flexible Scope or Endocam
        const productLine = this.evaluation?.workOrderProductLine;
        if (!productLine || typeof productLine !== 'string') {
            return false;
        }
        return USAGE_COUNT_PRODUCT_LINES.has(productLine.trim().toUpperCase());
    }

    get evaluationNotesSummaryDisplay() {
        return this.displayText(this.evaluation?.evaluationNotes);
    }

    get internalEvaluationNotesSummaryDisplay() {
        return this.displayText(this.evaluation?.internalEvaluationNotes);
    }

    get internalSpecialistNotesSummaryDisplay() {
        return this.displayText(this.evaluation?.internalSpecialistEvaluationNotes);
    }

    get hasCategoryCodes() {
        return (this.evaluation?.categoryCodes || []).length > 0;
    }

    get hasAttachedFiles() {
        return this.selectedStagedPhotos.length > 0;
    }

    get photoModalTitle() {
        const code = this.photoModalProductCode || 'Repair code';
        return `Photos — ${code}`;
    }

    /** Photos kept for currently selected repair codes (summary + photo-required checks). */
    get selectedStagedPhotos() {
        return (this.stagedPhotos || []).filter((file) =>
            this.selectedProductIdSet.has(file.productId)
        );
    }

    get modalStagedPhotos() {
        return this.decoratePhotoRows(
            (this.stagedPhotos || []).filter(
                (file) => file.productId === this.photoModalProductId
            )
        );
    }

    get hasModalStagedPhotos() {
        return this.modalStagedPhotos.length > 0;
    }

    get displayAttachedFiles() {
        return this.decoratePhotoRows(this.selectedStagedPhotos);
    }

    get isPhotoModalBusy() {
        return this.isUploadingFiles || this.isCapturing;
    }

    get selectedCount() {
        return this.selectedProductIdSet.size;
    }

    get summaryGroups() {
        const selectedCards = this.collectSelectedCards();
        const groupsByName = new Map();

        selectedCards.forEach((card) => {
            const groupName = PRICING_CODE_TYPES.has(card.codeType)
                ? SUMMARY_GROUP_PRICING
                : card.evalCategory || 'Other';
            if (!groupsByName.has(groupName)) {
                groupsByName.set(groupName, {
                    groupName,
                    groupKey: groupName,
                    rows: []
                });
            }
            groupsByName.get(groupName).rows.push({
                productId: card.productId,
                productCode: card.productCode,
                productName: card.productName,
                codeType: card.codeType,
                evalCategory: card.evalCategory || groupName,
                signaturesDisplay: this.signatureNamesForProduct(card.productId)
            });
        });

        const groups = Array.from(groupsByName.values());
        groups.sort((left, right) => {
            if (left.groupName === SUMMARY_GROUP_PRICING) {
                return -1;
            }
            if (right.groupName === SUMMARY_GROUP_PRICING) {
                return 1;
            }
            return left.groupName.localeCompare(right.groupName);
        });
        return groups;
    }

    get hasSummarySelections() {
        return this.summaryGroups.length > 0;
    }

    get categoryCards() {
        return this.decorateCards(this.evaluation?.categoryCodes || []);
    }

    /**
     * Observation codes across all dynamic tabs where Product Condition = Ok.
     */
    get okObservationProductIds() {
        const ids = [];
        (this.evaluation?.evalCategoryTabs || []).forEach((tab) => {
            (tab.observationCodes || []).forEach((card) => {
                if (
                    card?.productId &&
                    String(card.condition || '').trim().toLowerCase() === CONDITION_OK.toLowerCase()
                ) {
                    ids.push(card.productId);
                }
            });
        });
        return ids;
    }

    get hasOkObservationCodes() {
        return this.okObservationProductIds.length > 0;
    }

    get areAllOkObservationCodesSelected() {
        const okIds = this.okObservationProductIds;
        if (okIds.length === 0) {
            return false;
        }
        return okIds.every((productId) => this.selectedProductIdSet.has(productId));
    }

    get showServiceBomTabs() {
        return true;
    }

    get showReturnToEval() {
        return (
            this.isEvaluationMode &&
            this.evaluation?.status === STATUS_REPAIR &&
            this.evaluation?.estimateRequired === ESTIMATE_REQUIRED
        );
    }

    get showWorkPerformedTab() {
        return this.evaluation?.status === STATUS_REPAIR;
    }

    get isRepairStatus() {
        return this.evaluation?.status === STATUS_REPAIR;
    }

    /**
     * @description Photos gate copy for Complete / Next — Evaluation vs Repair.
     * @returns {string}
     */
    getPhotoRequiredMessage() {
        return this.isRepairStatus
            ? "Photos are required for this repair. Please upload photos, or if unable to do so, check that you are ‘Unable to Take Photo’."
            : "Photos are required for this evaluation. Please upload photos, or if unable to do so, check that you are ‘Unable to Take Photo’.";
    }

    /**
     * @description Apex failure fallback for Complete — Evaluation vs Repair.
     * @returns {string}
     */
    getCompleteFailureMessage() {
        return this.isRepairStatus
            ? 'Unable to complete Device Repair.'
            : 'Unable to complete Device Evaluation.';
    }

    get workPerformedSignableRows() {
        return this.collectSelectedCards()
            .filter((card) => SIGNABLE_CODE_TYPES.has(card.codeType))
            .map((card) => this.decorateWorkPerformedSignRow(card));
    }

    get hasWorkPerformedSignableRows() {
        return this.workPerformedSignableRows.length > 0;
    }

    get workPerformedObservationRows() {
        return this.collectSelectedCards()
            .filter((card) => card.codeType === CODE_TYPE_OBSERVATION)
            .map((card) => {
                const photoCount = (this.stagedPhotos || []).filter(
                    (file) => file.productId === card.productId
                ).length;
                return {
                    ...card,
                    photoCount,
                    photoCountLabel: String(photoCount)
                };
            });
    }

    get hasWorkPerformedObservationRows() {
        return this.workPerformedObservationRows.length > 0;
    }

    get isSignAllDisabled() {
        return (
            this.isActionBusy ||
            !this.workPerformedSignableRows.some((row) => row.showSignButton)
        );
    }

    get signableProductIds() {
        return this.workPerformedSignableRows.map((row) => row.productId);
    }

    get showMarkAllOk() {
        return this.showServiceBomTabs && this.hasOkObservationCodes;
    }

    get dynamicTabs() {
        const tabs = this.evaluation?.evalCategoryTabs || [];
        return tabs.map((tab) => {
            const observationCodes = this.decorateCards(tab.observationCodes || []);
            const serviceCodes = this.decorateCards(tab.serviceCodes || []);
            return {
                ...tab,
                observationCodes,
                serviceCodes,
                hasObservationCodes: observationCodes.length > 0,
                hasServiceCodes: serviceCodes.length > 0
            };
        });
    }

    get navItems() {
        const fixed = [
            { label: 'Work Order Details', value: TAB_WO_DETAILS }
        ];
        if (this.showVendorTab) {
            fixed.push({ label: 'Vendor Information', value: TAB_VENDOR });
        }
        fixed.push(
            { label: 'Asset Information', value: TAB_ASSET },
            { label: 'Customer Preferences', value: TAB_PREFERENCES },
            { label: 'Evaluation Notes', value: TAB_NOTES },
            { label: 'Warranty Repair Evaluation', value: TAB_WRE }
        );
        if (this.showWorkPerformedTab) {
            fixed.push({ label: 'Product Requests', value: TAB_PRODUCT_REQUESTS });
            fixed.push({ label: 'Work Performed', value: TAB_WORK_PERFORMED });
        }
        fixed.push({ label: 'Modifier Codes', value: TAB_MODIFIER_CODES });
        if (this.showServiceBomTabs) {
            fixed.push({ label: 'Pricing Codes', value: TAB_CATEGORY });
        }
        const dynamic = this.showServiceBomTabs
            ? this.dynamicTabs.map((tab) => ({
                  label: tab.categoryName,
                  value: tab.tabValue
              }))
            : [];
        return [...fixed, ...dynamic].map((item) => {
            const isActive = item.value === this.activeTab;
            return {
                ...item,
                itemClass: isActive
                    ? 'slds-nav-vertical__item slds-is-active'
                    : 'slds-nav-vertical__item',
                ariaCurrent: isActive ? 'page' : null
            };
        });
    }

    get isWoDetailsTab() {
        return this.activeTab === TAB_WO_DETAILS;
    }

    get isVendorTab() {
        return this.activeTab === TAB_VENDOR;
    }

    get showVendorTab() {
        return (
            this.evaluation?.subStatus === SUBSTATUS_SHIP_TO_VENDOR ||
            !!this.evaluation?.vendorAccountId
        );
    }

    get vendorFormValue() {
        return {
            vendorAccountId: this.evaluation?.vendorAccountId || null,
            instructionsToVendor: this.evaluation?.instructionsToVendor || '',
            sterisPurchaseOrderToVendor:
                this.evaluation?.sterisPurchaseOrderToVendor || '',
            shippedToVendorDate:
                this.evaluation?.shippedToVendorDate || this.todayIsoDate(),
            trackingNumber: this.evaluation?.trackingNumber || '',
            vendorNotes: this.evaluation?.vendorNotes || '',
            vendorReferenceNumber: this.evaluation?.vendorReferenceNumber || '',
            vendorCost: this.evaluation?.vendorCost
        };
    }

    get isAssetTab() {
        return this.activeTab === TAB_ASSET;
    }

    get isPreferencesTab() {
        return this.activeTab === TAB_PREFERENCES;
    }

    get isNotesTab() {
        return this.activeTab === TAB_NOTES;
    }

    get isWreTab() {
        return this.activeTab === TAB_WRE;
    }

    get isCategoryTab() {
        return this.activeTab === TAB_CATEGORY;
    }

    get isModifierCodesTab() {
        return this.activeTab === TAB_MODIFIER_CODES;
    }

    get isProductRequestsTab() {
        return this.activeTab === TAB_PRODUCT_REQUESTS;
    }

    get isWorkPerformedTab() {
        return this.activeTab === TAB_WORK_PERFORMED;
    }

    get isDynamicCategoryTab() {
        return (
            !this.isWoDetailsTab &&
            !this.isAssetTab &&
            !this.isPreferencesTab &&
            !this.isNotesTab &&
            !this.isWreTab &&
            !this.isCategoryTab &&
            !this.isWorkPerformedTab &&
            !this.isProductRequestsTab &&
            !this.isModifierCodesTab
        );
    }

    get activeDynamicTab() {
        return this.dynamicTabs.find((tab) => tab.tabValue === this.activeTab);
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

    connectedCallback() {
        this._resizeBound = () => this.scheduleWorkspaceHeightSync();
        window.addEventListener('resize', this._resizeBound);
        this.updateBrowserTitle();
    }

    /**
     * Sets the OS/browser window title (e.g. "00000519 | Device Evaluation").
     * @param {string} [workOrderNumber] Work Order number when evaluation is open
     */
    updateBrowserTitle(workOrderNumber) {
        const wo = (workOrderNumber || '').toString().trim();
        document.title = wo ? `${wo} | ${BROWSER_TAB_LABEL}` : BROWSER_TAB_LABEL;
    }

    renderedCallback() {
        if (this.activeTab === TAB_PRODUCT_REQUESTS && this.evaluation?.status !== STATUS_REPAIR) {
            this.activeTab = TAB_WO_DETAILS;
        }
        this.classList.toggle('is-evaluation', this.isWorkspaceMode);
        this.syncSubStatusSelectValue();
        this.scheduleWorkspaceHeightSync();
    }

    syncSubStatusSelectValue() {
        const selectEl = this.template.querySelector('.sticky-field__control_select');
        if (!selectEl) {
            return;
        }
        const current =
            this.evaluation?.subStatus == null ? '' : String(this.evaluation.subStatus);
        if (selectEl.value !== current) {
            selectEl.value = current;
        }
    }

    disconnectedCallback() {
        this.stopCameraStream();
        this.classList.remove('is-evaluation');
        this.clearWorkspaceHeight();
        if (this._resizeBound) {
            window.removeEventListener('resize', this._resizeBound);
        }
        if (this._heightFrame) {
            cancelAnimationFrame(this._heightFrame);
            this._heightFrame = undefined;
        }
    }

    /**
     * Lock host height to remaining visible space so LEX does not scroll
     * header + panel together. Only .workspace-panel / .workspace-nav scroll.
     */
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
        if (!this.isWorkspaceMode) {
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
        this.style.setProperty('--de-available-height', px);
        this.style.height = px;
        this.style.maxHeight = px;
        this.style.overflow = 'hidden';
    }

    clearWorkspaceHeight() {
        this.style.removeProperty('--de-available-height');
        this.style.height = '';
        this.style.maxHeight = '';
        this.style.overflow = '';
    }

    findScrollParent() {
        let node = this.parentElement;
        while (node && node !== document.body) {
            const style = window.getComputedStyle(node);
            const overflowY = style.overflowY;
            if (
                (overflowY === 'auto' || overflowY === 'scroll' || overflowY === 'overlay') &&
                node.clientHeight > 0
            ) {
                return node;
            }
            node = node.parentElement;
        }
        return document.documentElement;
    }

    collectSelectedCards() {
        const cards = [];
        (this.evaluation?.categoryCodes || []).forEach((card) => {
            if (this.selectedProductIdSet.has(card.productId)) {
                cards.push(card);
            }
        });
        (this.evaluation?.evalCategoryTabs || []).forEach((tab) => {
            (tab.observationCodes || []).forEach((card) => {
                if (this.selectedProductIdSet.has(card.productId)) {
                    cards.push(card);
                }
            });
            (tab.serviceCodes || []).forEach((card) => {
                if (this.selectedProductIdSet.has(card.productId)) {
                    cards.push(card);
                }
            });
        });
        return cards;
    }

    async ensurePhotosReady() {
        const photosRequired = this.evaluation?.photosRequired === true;
        const unable = this.evaluation?.unableToTakePhoto === true;
        if (photosRequired && !unable && this.selectedStagedPhotos.length === 0) {
            this.workspaceError = this.getPhotoRequiredMessage();
            return false;
        }
        this.workspaceError = '';
        return true;
    }

    buildEvaluationPayload() {
        return {
            workOrderId: this.evaluation.workOrderId,
            subStatus: this.evaluation.subStatus,
            unableToTakePhoto: this.evaluation.unableToTakePhoto === true,
            turnTime: this.evaluation.turnTime,
            usageCount: this.evaluation.usageCount,
            evaluationNotes: this.evaluation.evaluationNotes,
            internalEvaluationNotes: this.evaluation.internalEvaluationNotes,
            internalSpecialistEvaluationNotes:
                this.evaluation.internalSpecialistEvaluationNotes,
            selectedProductIds: Array.from(this.selectedProductIdSet),
            // Only selected-card photos are attached; orphans are discarded on Cancel/Complete.
            stagedPhotos: this.selectedStagedPhotos
                .filter((file) => file.contentDocumentId && file.productId)
                .map((file) => ({
                    contentDocumentId: file.contentDocumentId,
                    productId: file.productId
                })),
            vendorDetailsJson: JSON.stringify({
                vendorAccountId: this.evaluation?.vendorAccountId || null,
                instructionsToVendor: this.evaluation?.instructionsToVendor || '',
                sterisPurchaseOrderToVendor:
                    this.evaluation?.sterisPurchaseOrderToVendor || '',
                vendorNotes: this.evaluation?.vendorNotes || '',
                vendorReferenceNumber: this.evaluation?.vendorReferenceNumber || '',
                vendorCost: this.evaluation?.vendorCost,
                shippedToVendorDate:
                    this.evaluation?.shippedToVendorDate || this.todayIsoDate(),
                trackingNumber: this.evaluation?.trackingNumber || ''
            })
        };
    }

    handleVendorFormChange(event) {
        if (!this.evaluation) {
            return;
        }
        const detail = event.detail || {};
        this.evaluation = {
            ...this.evaluation,
            vendorAccountId: detail.vendorAccountId || null,
            instructionsToVendor: detail.instructionsToVendor || '',
            sterisPurchaseOrderToVendor: detail.sterisPurchaseOrderToVendor || '',
            shippedToVendorDate: detail.shippedToVendorDate,
            trackingNumber: detail.trackingNumber || '',
            vendorNotes: detail.vendorNotes || '',
            vendorReferenceNumber: detail.vendorReferenceNumber || '',
            vendorCost: detail.vendorCost
        };
    }

    decoratePhotoRows(files) {
        return (files || []).map((file) => {
            const extension = (file.fileExtension || '').toLowerCase();
            const contentDocumentId = file.contentDocumentId;
            const isImage =
                file.isImage === true ||
                IMAGE_EXTENSIONS.has(extension) ||
                IMAGE_EXTENSIONS.has((file.fileType || '').toLowerCase());
            // Prefer version download for staged photos — THUMB renditions often aren't ready yet.
            const preferDownload = this.thumbnailFallbackIds.has(contentDocumentId) || !file.isLinked;
            const previewUrl = preferDownload
                ? file.imageDownloadUrl || file.thumbnailUrl || file.downloadUrl
                : file.thumbnailUrl || file.imageDownloadUrl || file.downloadUrl;
            const showThumbnail =
                isImage && !!previewUrl && !this.thumbnailFallbackIds.has(`gone:${contentDocumentId}`);
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
                    : 'photo-title-input',
                productCodeDisplay: file.productCode || '—',
                productNameDisplay: file.productName || '—'
            };
        });
    }

    async persistEvaluationDraft() {
        // Keep unlinked photos for unselected cards across Quick Save / Save & Close.
        // applyWorkspace reloads only server-linked files and would otherwise drop them.
        const preservedUnlinked = (this.stagedPhotos || []).filter(
            (file) =>
                !file.isLinked &&
                file.contentDocumentId &&
                !this.selectedProductIdSet.has(file.productId)
        );
        if (!this.hasRequiredContamination()) {
            throw new Error(CONTAMINATION_REQUIRED_MESSAGE);
        }
        const workspace = await saveEvaluation({
            ...this.buildEvaluationPayload(),
            contaminationJson: JSON.stringify(this.buildContaminationPayload())
        });
        this.applyWorkspace(workspace, true);
        if (preservedUnlinked.length > 0) {
            const linkedIds = new Set(
                (this.stagedPhotos || []).map((file) => file.contentDocumentId)
            );
            const toRestore = preservedUnlinked.filter(
                (file) => !linkedIds.has(file.contentDocumentId)
            );
            if (toRestore.length > 0) {
                this.stagedPhotos = [...(this.stagedPhotos || []), ...toRestore];
            }
        }
        return workspace;
    }

    get needsRepairPricing() {
        return (
            this.isRepairStatus &&
            (this.evaluation?.estimateRequired === 'Estimate Required' ||
                this.evaluation?.customerPORequired === true)
        );
    }

    async persistThenPrice({ applyCompletion }) {
        const restoreProductIds = [...(this.lastPersistedProductIds || [])];
        const originalNetTotal = this.evaluation?.originalNetTotalPrice;
        await this.persistEvaluationDraft();
        if (applyCompletion === true || this.needsRepairPricing) {
            try {
                const priced = await finalizeDeviceEvaluationAfterPricing({
                    workOrderId: this.evaluation.workOrderId,
                    originalNetTotal,
                    applyCompletion: applyCompletion === true,
                    restoreProductIds,
                    subStatus: this.evaluation.subStatus
                });
                this.applyWorkspace(priced, true);
                if (priced?.requoteWarning) {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Repair cost increased',
                            message: priced.requoteWarning,
                            variant: 'warning',
                            mode: 'sticky'
                        })
                    );
                }
            } catch (error) {
                this.lastPersistedProductIds = [...restoreProductIds];
                this.selectedProductIdSet = new Set(restoreProductIds);
                if (this.evaluation) {
                    this.evaluation = {
                        ...this.evaluation,
                        selectedProductIds: [...restoreProductIds]
                    };
                }
                throw error;
            }
        }
    }

    async handleQuickSave() {
        if (this.isActionBusy || !this.evaluation?.workOrderId) {
            return;
        }
        this.isSaving = true;
        this.workspaceError = '';
        try {
            await this.persistThenPrice({ applyCompletion: false });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Saved',
                    message: `Work Order ${this.evaluation.workOrderNumber} evaluation progress was saved.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to save Device Evaluation.'
            );
        } finally {
            this.isSaving = false;
        }
    }

    async handleSaveAndClose() {
        if (this.isActionBusy || !this.evaluation?.workOrderId) {
            return;
        }
        this.isSaving = true;
        this.workspaceError = '';
        try {
            await this.persistThenPrice({ applyCompletion: false });
            const workOrderNumber = this.evaluation.workOrderNumber;
            this.handleClosePhotoModal();
            this.resetToScan();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Saved',
                    message: `Work Order ${workOrderNumber} evaluation progress was saved.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to save Device Evaluation.'
            );
        } finally {
            this.isSaving = false;
        }
    }

    async handleReturnToEval() {
        if (this.isActionBusy || !this.evaluation?.workOrderId) {
            return;
        }
        this.syncDraftNotesFromDom();
        this.isSaving = true;
        this.workspaceError = '';
        try {
            await returnToEvaluation(this.buildEvaluationPayload());
            const workOrderNumber = this.evaluation.workOrderNumber;
            this.handleClosePhotoModal();
            this.resetToScan();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Returned to Eval',
                    message: `Work Order ${workOrderNumber} was returned to Evaluate.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to return the Work Order to Evaluate.'
            );
        } finally {
            this.isSaving = false;
        }
    }

    async handleCancel() {
        if (this.isActionBusy || !this.evaluation?.workOrderId) {
            return;
        }
        this.handleClosePhotoModal();
        // Cancel abandons the session — remove all unlinked staged photos.
        await this.discardUnlinkedStagedPhotos();
        this.resetToScan();
    }

    async handleNext() {
        if (this.isActionBusy) {
            return;
        }
        // Capture draft textarea values before leaving evaluation (change may not
        // have fired if Next is clicked while a notes field still has focus).
        this.syncDraftNotesFromDom();
        const photosOk = await this.ensurePhotosReady();
        if (!photosOk) {
            return;
        }
        if (this.hasUnsignedRepairCodes()) {
            this.workspaceError = REPAIR_UNSIGNED_MESSAGE;
            return;
        }
        if (this.isShipToVendorSubStatus()) {
            this.workspaceError = SHIP_TO_VENDOR_NEXT_MESSAGE;
            return;
        }
        this.mode = MODE_SUMMARY;
        this.handleClosePhotoModal();
    }

    handleContinueEvaluation() {
        this.mode = MODE_EVALUATION;
        this.workspaceError = '';
    }

    async handleComplete() {
        if (this.isActionBusy || !this.evaluation?.workOrderId) {
            return;
        }

        const photosOk = await this.ensurePhotosReady();
        if (!photosOk) {
            this.mode = MODE_EVALUATION;
            return;
        }
        if (this.hasUnsignedRepairCodes()) {
            this.workspaceError = REPAIR_UNSIGNED_MESSAGE;
            this.mode = MODE_EVALUATION;
            return;
        }
        if (this.isShipToVendorSubStatus()) {
            this.workspaceError = SHIP_TO_VENDOR_NEXT_MESSAGE;
            this.mode = MODE_EVALUATION;
            return;
        }

        if (!this.hasRequiredContamination()) {
            this.workspaceError = CONTAMINATION_REQUIRED_MESSAGE;
            this.mode = MODE_EVALUATION;
            return;
        }

        this.isCompleting = true;
        this.workspaceError = '';
        try {
            await this.persistThenPrice({ applyCompletion: true });
            // Drop unlinked photos for cards that were not selected at Complete.
            await this.discardUnlinkedStagedPhotos({
                onlyUnselectedProducts: true
            });

            const completedNumber = this.evaluation.workOrderNumber;
            const wasRepair = this.isRepairStatus;
            this.stagedPhotos = [];
            this.resetToScan();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: wasRepair ? 'Repair complete' : 'Evaluation complete',
                    message: wasRepair
                        ? `Work Order ${completedNumber} repair was completed.`
                        : `Work Order ${completedNumber} evaluation was completed.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                this.getCompleteFailureMessage()
            );
        } finally {
            this.isCompleting = false;
        }
    }

    resetToScan() {
        this.handleClosePhotoModal();
        this.mode = MODE_SCAN;
        this.evaluation = undefined;
        this.stagedPhotos = [];
        this.lastPersistedProductIds = [];
        this.selectedProductIdSet = new Set();
        this.deletingDocumentIds = new Set();
        this.thumbnailFallbackIds = new Set();
        this.workspaceError = '';
        this.errorMessage = '';
        this.workOrderNumber = '';
        this.activeTab = TAB_WO_DETAILS;
        this.updateBrowserTitle();
    }

    decorateCards(cards) {
        return cards.map((card) => {
            const selected = this.selectedProductIdSet.has(card.productId);
            return {
                ...card,
                selected,
                buttonClass: selected ? 'code-card code-card_selected' : 'code-card',
                checkboxClass: selected
                    ? 'code-card__checkbox code-card__checkbox_checked'
                    : 'code-card__checkbox'
            };
        });
    }

    handleScanValueChange(event) {
        this.workOrderNumber = event.detail?.value || '';
        this.errorMessage = '';
    }

    async handleScanContinue(event) {
        const input = (event.detail?.value || this.workOrderNumber || '').trim();
        if (!input || this.isLoading) {
            return;
        }
        this.workOrderNumber = input;
        await this.startEvaluationFromScan();
    }

    async startEvaluationFromScan() {
        this.isLoading = true;
        this.errorMessage = '';
        this.workspaceError = '';
        this.handleClosePhotoModal();

        try {
            const result = await initializeEvaluation({
                workOrderNumber: this.workOrderNumber.trim()
            });
            this.applyWorkspace(result, true);
            this.thumbnailFallbackIds = new Set();
            this.deletingDocumentIds = new Set();
            this.mode = MODE_EVALUATION;
            this.activeTab = TAB_WO_DETAILS;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Evaluation started',
                    message: `Work Order ${result.workOrderNumber} is ready for Device Evaluation.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.resolveErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    applyWorkspace(workspace, resetSelection) {
        this.evaluation = workspace;
        this.updateBrowserTitle(workspace?.workOrderNumber);
        this.ensureActiveTabIsVisible();
        if (resetSelection) {
            this.lastPersistedProductIds = [...(workspace.selectedProductIds || [])];
            this.selectedProductIdSet = new Set(workspace.selectedProductIds || []);
            // Already-linked WOLI photos (re-open after prior Complete / Quick Save).
            this.stagedPhotos = (workspace.attachedFiles || []).map((file) => ({
                ...file,
                isLinked: true
            }));
        }
    }

    handleWarrantyRepairEvaluationSaved(event) {
        const rows = event?.detail?.rows;
        if (!this.evaluation || !Array.isArray(rows)) {
            return;
        }
        this.evaluation = {
            ...this.evaluation,
            warrantyRepairEvaluations: rows
        };
    }

    ensureActiveTabIsVisible() {
        if (this.isWorkPerformedTab) {
            if (!this.showWorkPerformedTab) {
                this.activeTab = TAB_WO_DETAILS;
            }
            return;
        }
        if (this.showServiceBomTabs) {
            return;
        }
        if (this.isCategoryTab || this.isDynamicCategoryTab) {
            this.activeTab = TAB_WO_DETAILS;
        }
    }

    decorateRepairSignature(signature) {
        return {
            ...signature,
            canRemove: signature?.userId === currentUserId
        };
    }

    decorateWorkPerformedSignRow(card) {
        const signatures = (this.evaluation?.repairSignatures || [])
            .filter((signature) => signature.productId === card.productId)
            .map((signature) => this.decorateRepairSignature(signature));
        const currentUserAlreadySigned = signatures.some(
            (signature) => signature.userId === currentUserId
        );
        return {
            ...card,
            signatures,
            hasSignatures: signatures.length > 0,
            showSignButton: !currentUserAlreadySigned
        };
    }

    signatureNamesForProduct(productId) {
        const names = (this.evaluation?.repairSignatures || [])
            .filter((signature) => signature.productId === productId)
            .map((signature) => signature.userName)
            .filter((name) => !!name);
        return names.length > 0 ? names.join(', ') : '—';
    }

    hasUnsignedRepairCodes() {
        return (
            this.evaluation?.status === STATUS_REPAIR &&
            this.workPerformedSignableRows.some((row) => !row.hasSignatures)
        );
    }

    isShipToVendorSubStatus() {
        return this.evaluation?.subStatus === SUBSTATUS_SHIP_TO_VENDOR;
    }

    async runRepairSignatureAction(action) {
        this.isSaving = true;
        this.workspaceError = '';
        try {
            const signatures = await action();
            this.evaluation = {
                ...this.evaluation,
                repairSignatures: signatures || []
            };
        } catch (error) {
            this.workspaceError = this.resolveErrorMessage(
                error,
                'Unable to update repair signatures.'
            );
        } finally {
            this.isSaving = false;
        }
    }

    async handleSignRepairCode(event) {
        event.preventDefault();
        event.stopPropagation();
        const productId = event.currentTarget.dataset.productId;
        if (!productId || this.isActionBusy) {
            return;
        }
        await this.runRepairSignatureAction(() =>
            addRepairSignature({
                ...this.buildEvaluationPayload(),
                productId
            })
        );
    }

    async handleSignAllRepairCodes() {
        if (this.isSignAllDisabled) {
            return;
        }
        await this.runRepairSignatureAction(() =>
            signAllRepairCodes({
                ...this.buildEvaluationPayload(),
                productIds: this.signableProductIds
            })
        );
    }

    async handleRemoveRepairSignature(event) {
        event.preventDefault();
        event.stopPropagation();
        const signatureId = event.currentTarget.dataset.signatureId;
        if (!signatureId || this.isActionBusy || !this.evaluation?.workOrderId) {
            return;
        }
        await this.runRepairSignatureAction(() =>
            removeRepairSignature({
                workOrderId: this.evaluation.workOrderId,
                signatureId
            })
        );
    }

    handleNavClick(event) {
        event.preventDefault();
        const nextTab = event.currentTarget.dataset.tab;
        // Drop focus so iOS/Safari does not leave a second "selected" highlight.
        if (typeof event.currentTarget.blur === 'function') {
            event.currentTarget.blur();
        }
        if (!nextTab || nextTab === this.activeTab) {
            return;
        }
        this.activeTab = nextTab;
    }

    async handleTakePhotoClick(event) {
        event.preventDefault();
        event.stopPropagation();
        const productId = event.currentTarget.dataset.productId;
        if (!productId) {
            return;
        }
        this.photoModalProductId = productId;
        this.photoModalProductCode = event.currentTarget.dataset.productCode || '';
        this.photoModalProductName = event.currentTarget.dataset.productName || '';
        this.isPhotoModalOpen = true;
        this.cameraError = '';
        await this.loadCameras();
    }

    handleClosePhotoModal() {
        this.stopCameraStream();
        this.isPhotoModalOpen = false;
        this.cameraError = '';
        this.photoModalProductId = '';
        this.photoModalProductCode = '';
        this.photoModalProductName = '';
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
        this.stagedPhotos = (this.stagedPhotos || []).map((file) =>
            file.contentDocumentId === contentDocumentId
                ? { ...file, editTitle: value }
                : file
        );
    }

    async handleSaveStagedPhotoTitle(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        if (!contentDocumentId) {
            return;
        }
        const staged = (this.stagedPhotos || []).find(
            (file) => file.contentDocumentId === contentDocumentId
        );
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
            this.stagedPhotos = (this.stagedPhotos || []).map((file) => {
                if (file.contentDocumentId !== contentDocumentId) {
                    return file;
                }
                return {
                    ...file,
                    title: updated.title,
                    editTitle: updated.title,
                    lastModifiedDate: updated.lastModifiedDate
                };
            });
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

    handleChooseFilesClick() {
        const input = this.template.querySelector('[data-id="staged-file-input"]');
        if (input) {
            input.click();
        }
    }

    async handleStagedFileSelected(event) {
        const files = Array.from(event.target.files || []);
        event.target.value = '';
        if (!files.length || !this.photoModalProductId) {
            return;
        }
        this.isUploadingFiles = true;
        this.cameraError = '';
        try {
            let uploaded = 0;
            for (const file of files) {
                const base64Data = await this.readFileAsDataUrl(file);
                const result = await stageEvaluationPhoto({
                    productId: this.photoModalProductId,
                    base64Data,
                    fileName: file.name
                });
                if (result?.file) {
                    this.addStagedPhoto(result.file);
                    uploaded += 1;
                }
            }
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Upload staged',
                    message:
                        uploaded === 1
                            ? '1 file staged for this repair code. Saved on Quick Save / Complete.'
                            : `${uploaded} files staged for this repair code. Saved on Quick Save / Complete.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.cameraError = this.resolveErrorMessage(error, 'Unable to stage uploaded files.');
        } finally {
            this.isUploadingFiles = false;
        }
    }

    readFileAsDataUrl(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(new Error('Unable to read the selected file.'));
            reader.readAsDataURL(file);
        });
    }

    addStagedPhoto(fileRow) {
        const enriched = {
            ...fileRow,
            productName: fileRow.productName || this.photoModalProductName || '',
            editTitle: fileRow.title || '',
            isLinked: false
        };
        const next = [...(this.stagedPhotos || [])];
        const existingIndex = next.findIndex(
            (row) => row.contentDocumentId === fileRow.contentDocumentId
        );
        if (existingIndex >= 0) {
            next[existingIndex] = enriched;
        } else {
            next.push(enriched);
        }
        this.stagedPhotos = next;
    }

    /**
     * Deletes unlinked staged ContentDocuments and removes them from local state.
     * @param {{ onlyUnselectedProducts?: boolean }} options
     *        When onlyUnselectedProducts is true, keeps photos for currently selected cards.
     *        Otherwise discards all unlinked staged photos (Cancel).
     */
    async discardUnlinkedStagedPhotos(options = {}) {
        const onlyUnselected = options.onlyUnselectedProducts === true;
        const remaining = [];
        const toDelete = [];
        (this.stagedPhotos || []).forEach((file) => {
            const keepForReselect =
                onlyUnselected && this.selectedProductIdSet.has(file.productId);
            if (keepForReselect || file.isLinked) {
                remaining.push(file);
                return;
            }
            if (file.contentDocumentId) {
                toDelete.push(file.contentDocumentId);
            }
        });
        this.stagedPhotos = remaining;
        await Promise.all(
            toDelete.map((contentDocumentId) =>
                deleteStagedEvaluationPhoto({ contentDocumentId }).catch(() => {
                    // Best-effort cleanup of unlinked staged files.
                })
            )
        );
    }

    handleThumbnailError(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        if (!contentDocumentId) {
            return;
        }
        const next = new Set(this.thumbnailFallbackIds);
        // First failure: retry with version download URL. Second: hide preview.
        if (!next.has(contentDocumentId)) {
            next.add(contentDocumentId);
        } else {
            next.add(`gone:${contentDocumentId}`);
        }
        this.thumbnailFallbackIds = next;
    }

    async handleDeleteFile(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        const title = event.currentTarget.dataset.title || 'this file';
        if (!contentDocumentId) {
            return;
        }
        const staged = (this.stagedPhotos || []).find(
            (file) => file.contentDocumentId === contentDocumentId
        );
        const repairCodeProductId = staged?.productId || this.photoModalProductId;
        const isSavedPhoto = staged?.isLinked === true;
        const confirmMessage = isSavedPhoto
            ? `Remove saved photo "${title}" from this repair code?`
            : `Remove staged photo "${title}"?`;

        const confirmed = await LightningConfirm.open({
            message: confirmMessage,
            variant: 'header',
            label: 'Delete photo',
            theme: 'error'
        });
        if (!confirmed) {
            return;
        }

        const deleting = new Set(this.deletingDocumentIds);
        deleting.add(contentDocumentId);
        this.deletingDocumentIds = deleting;
        this.workspaceError = '';
        this.cameraError = '';

        try {
            if (staged?.isLinked === true && repairCodeProductId && this.workOrderId) {
                await removeEvaluationPhoto({
                    workOrderId: this.workOrderId,
                    productId: repairCodeProductId,
                    contentDocumentId
                });
            } else {
                await deleteStagedEvaluationPhoto({ contentDocumentId });
            }
            this.stagedPhotos = (this.stagedPhotos || []).filter(
                (file) => file.contentDocumentId !== contentDocumentId
            );
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Photo removed',
                    message: `"${title}" was removed.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            const message = this.resolveErrorMessage(error, 'Unable to delete the photo.');
            if (this.isPhotoModalOpen) {
                this.cameraError = message;
            } else {
                this.workspaceError = message;
            }
        } finally {
            const remaining = new Set(this.deletingDocumentIds);
            remaining.delete(contentDocumentId);
            this.deletingDocumentIds = remaining;
        }
    }

    handleContaminationChange(event) {
        if (!this.evaluation) {
            return;
        }
        const field = event.detail?.field;
        if (!field) {
            return;
        }
        this.evaluation = {
            ...this.evaluation,
            contamination: {
                ...(this.evaluation.contamination || {}),
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
        const source = this.evaluation?.contamination || {};
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
        const nextValue =
            event?.detail?.value != null ? event.detail.value : event?.target?.value;
        this.evaluation = {
            ...this.evaluation,
            subStatus: nextValue === '' ? null : nextValue
        };
    }

    handleUnableToTakePhotoChange(event) {
        this.evaluation = {
            ...this.evaluation,
            unableToTakePhoto: event.target.checked === true
        };
    }

    handleTurnTimeInputChange(event) {
        const raw = event.target.value;
        this.evaluation = {
            ...this.evaluation,
            turnTime: raw === '' || raw === null || raw === undefined ? null : Number(raw)
        };
    }

    handleUsageCountInputChange(event) {
        const usageCount = event.target.value;
        this.evaluation = {
            ...this.evaluation,
            usageCount,
            usageCountDate: usageCount ? this.todayIsoDate() : null
        };
    }

    handleNotesChange(event) {
        const field = event.detail?.field;
        if (!this.evaluation || !field) {
            return;
        }
        this.evaluation = {
            ...this.evaluation,
            [field]: event.detail.value
        };
    }

    /**
     * @description Reads current note textarea values from the shared notes LWC.
     */
    syncDraftNotesFromDom() {
        const notesCmp = this.template.querySelector('c-repair-center-eval-notes');
        if (!this.evaluation || !notesCmp || typeof notesCmp.getDraftNotes !== 'function') {
            return;
        }
        this.evaluation = {
            ...this.evaluation,
            ...notesCmp.getDraftNotes()
        };
    }

    displayText(value) {
        if (value === null || value === undefined || String(value).trim() === '') {
            return '—';
        }
        return String(value);
    }

    handleMarkAllOkToggle(event) {
        const okIds = this.okObservationProductIds;
        if (okIds.length === 0) {
            return;
        }
        const turnOn = event.target.checked === true;
        const next = new Set(this.selectedProductIdSet);
        if (turnOn) {
            okIds.forEach((productId) => next.add(productId));
        } else {
            okIds.forEach((productId) => next.delete(productId));
        }
        this.selectedProductIdSet = next;
    }

    handleCardClick(event) {
        const productId = event.currentTarget.dataset.productId;
        if (productId) {
            this.toggleSelection(productId);
        }
    }

    handleCardKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            const productId = event.currentTarget.dataset.productId;
            if (productId) {
                this.toggleSelection(productId);
            }
        }
    }

    toggleSelection(productId) {
        const next = new Set(this.selectedProductIdSet);
        if (next.has(productId)) {
            next.delete(productId);
            this.selectedProductIdSet = next;
            // Keep staged photos; Take Photo / summary show them again if re-selected.
            return;
        }
        next.add(productId);
        this.selectedProductIdSet = next;
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
            if (!this.photoModalProductId) {
                throw new Error('Select a repair code before capturing a photo.');
            }
            const dataUrl = this.canvasEl.toDataURL('image/jpeg', 0.92);
            const fileName = `DeviceEval-${this.todayIsoDate()}-${Date.now()}.jpg`;

            const result = await stageEvaluationPhoto({
                productId: this.photoModalProductId,
                base64Data: dataUrl,
                fileName
            });
            if (result?.file) {
                this.addStagedPhoto(result.file);
            }
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Photo staged',
                    message:
                        result.message ||
                        'Photo staged for this repair code. It is saved on Quick Save, Save & Close, or Complete.',
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

    resolveErrorMessage(error, fallbackMessage) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body) && error.body.length > 0 && error.body[0].message) {
            return error.body[0].message;
        }
        if (error?.message) {
            return error.message;
        }
        return fallbackMessage || 'Unable to complete Device Evaluation action. Please try again.';
    }
}