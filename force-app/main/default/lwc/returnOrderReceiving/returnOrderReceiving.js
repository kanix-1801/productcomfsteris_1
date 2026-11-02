import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getRecentCreatedReturnOrders from '@salesforce/apex/ReturnOrderReceivingController.getRecentCreatedReturnOrders';
import findReturnOrderByNumber from '@salesforce/apex/ReturnOrderReceivingController.findReturnOrderByNumber';
import validateReturnOrderForReceiving from '@salesforce/apex/ReturnOrderReceivingController.validateReturnOrderForReceiving';
import getActiveInternalUsers from '@salesforce/apex/ReturnOrderReceivingController.getActiveInternalUsers';
import getRepairCenterLocations from '@salesforce/apex/ReturnOrderReceivingController.getRepairCenterLocations';
import redirectLineItem from '@salesforce/apex/ReturnOrderReceivingController.redirectLineItem';
import getAccountAssetsForCorrection from '@salesforce/apex/ReturnOrderReceivingController.getAccountAssetsForCorrection';
import getProductsForLineCorrection from '@salesforce/apex/ReturnOrderReceivingController.getProductsForLineCorrection';
import getItemTypeOptions from '@salesforce/apex/ReturnOrderReceivingController.getItemTypeOptions';
import getItemTypeProductLineMappings from '@salesforce/apex/ReturnOrderReceivingController.getItemTypeProductLineMappings';
import getAccessoryTypeOptions from '@salesforce/apex/ReturnOrderReceivingController.getAccessoryTypeOptions';
import getAccessoryConditionOptions from '@salesforce/apex/ReturnOrderReceivingController.getAccessoryConditionOptions';
import getReceivingContext from '@salesforce/apex/ReturnOrderReceivingController.getReceivingContext';
import receiveReturnOrder from '@salesforce/apex/ReturnOrderReceivingController.receiveReturnOrder';
import getSerializedChildWorkOrderCount from '@salesforce/apex/ReturnOrderReceivingController.getSerializedChildWorkOrderCount';
import getProductDetails from '@salesforce/apex/CreateReturnOrderController.getProductDetails';
import getDepartmentsForAccount from '@salesforce/apex/CreateReturnOrderController.getDepartmentsForAccount';
import getAssetsForAccount from '@salesforce/apex/CreateReturnOrderController.getAssetsForAccount';
import getProductsForReturnOrderLine from '@salesforce/apex/CreateReturnOrderController.getProductsForReturnOrderLine';

const AD_HOC_SEARCH_CONTROL = 'adhoc';
const PAGE_SCAN = 'scan';
const PAGE_RECEIVE = 'receive';
const STEP_LINE_MODIFY = 'lineModify';
const STEP_LINE_ACCESSORIES = 'lineAccessories';
const REPAIR_CENTER_CORRECT_YES = 'Yes';
const REPAIR_CENTER_CORRECT_NO = 'No';
const REDIRECT_SCOPE_ALL = 'all';
const REDIRECT_SCOPE_SELECTED = 'selected';
const CONTAMINATED_YES = 'Yes';
const CONTAMINATED_NO = 'No';
const RO_TYPE_SERIALIZED = 'Serialized';
const RO_TYPE_INSTRUMENTS = 'Instruments';
const RO_TYPE_OTHER = 'Other';
const ESTIMATE_REQUIRED_QUOTE_VALUE = 'Estimate Required';
const YES_NO_OPTIONS = [
    { label: 'Yes', value: 'Yes' },
    { label: 'No', value: 'No' }
];
const ACCEPTED_MEDIA_TYPES =
    '.png,.jpg,.jpeg,.gif,.bmp,.webp,.heic,.mp4,.mov,.avi,.wmv,.mkv,.webm,.m4v,.3gp';

export default class ReturnOrderReceiving extends NavigationMixin(LightningElement) {
    _recordId;
    _recordContextInitialized = false;
    _initCheckComplete = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.resolveInitialPage();
    }

    currentPage;
    embeddedOnRecordPage = false;
    activeReturnOrderId;
    returnOrderNumberInput = '';
    scanErrorMessage;
    recentReturnOrders = [];
    isRecentReturnOrdersLoading = true;
    isLookupLoading = false;

    receivingContext;
    lineItems = [];
    isLoading = false;
    isSubmitting = false;
    errorMessage;
    isInitializingContext = true;

    userOptions = [];
    repairCenterOptions = [];
    selectedReceiverId;
    selectedRepairCenterId;
    selectedRepairCenterCorrect;
    selectedRedirectScope;
    selectedReceivedDateTime;
    selectedIsContaminated;
    instrumentQuantityReturned;
    instrumentQuantityReceived;
    photoAttachments = [];
    selectAllLines = false;

    showModal = false;
    isModalLoading = false;
    modalStep;

    selectedLineItemId;
    correctionSerialNumber = '';
    correctionModel = '';
    correctionProductId;
    correctionItemType;
    correctionProductLine = '';
    correctionHospitalTrayName = '';
    correctionQuantityReturned;
    productOptions = [];
    itemTypeOptions = [];
    itemTypeToProductLine = {};
    accessoryTypeOptions = [];
    accessoryConditionOptions = [];
    accessoryDraftRows = [];
    accountAssetOptions = [];
    accountAssetsById = {};
    departmentOptions = [];
    disinfectedOptions = [];
    estimateRequiredOptions = [];
    selectedCorrectionAssetId;
    correctionDepartmentId;
    adHocDisinfected = '';
    adHocContactId;
    adHocEstimateRequired = '';
    adHocEstimateContactId;
    adHocRepairWarranty = '';
    adHocWarrantyNotes = '';
    adHocPreviousReturnOrder = '';
    adHocCustomerPo = '';
    adHocCustomerReference = '';
    adHocReportedProblem = '';
    adHocModRequest = false;
    adHocIsLoanerAsset = false;
    adHocLoanerRequested = false;
    adHocAccountAssets = [];
    adHocAssetSearchText = '';
    showAdHocAssetResults = false;
    adHocAssetSearchDropdownStyle = '';
    adHocProductSearchText = '';
    adHocProductOptions = [];
    showAdHocProductResults = false;
    adHocProductSearchDropdownStyle = '';
    adHocSearchViewportListenersAttached = false;
    _boundRepositionAdHocSearch;
    isAddingAdHocSerializedItem = false;
    adHocLineCounter = 0;

    contaminatedOptions = [
        { label: 'Yes', value: CONTAMINATED_YES },
        { label: 'No', value: CONTAMINATED_NO }
    ];

    repairCenterCorrectOptions = [
        { label: 'Yes', value: REPAIR_CENTER_CORRECT_YES },
        { label: 'No', value: REPAIR_CENTER_CORRECT_NO }
    ];

    redirectScopeOptions = [
        { label: 'Yes, redirect all lines', value: REDIRECT_SCOPE_ALL },
        { label: 'No, only this line', value: REDIRECT_SCOPE_SELECTED }
    ];

    wiredRecentReturnOrdersResult;
    wiredReceivingContextResult;

    connectedCallback() {
        Promise.resolve().then(() => {
            this._initCheckComplete = true;
            this.resolveInitialPage();
        });
    }

    resolveInitialPage() {
        if (this._recordId) {
            this.initializeFromRecord(this._recordId);
            return;
        }

        if (!this._initCheckComplete || this._recordContextInitialized) {
            return;
        }

        this.isInitializingContext = false;
        this.currentPage = PAGE_SCAN;
        this.isLoading = false;
    }

    initializeFromRecord(returnOrderId) {
        if (this._recordContextInitialized && this.activeReturnOrderId === returnOrderId) {
            return;
        }

        this._recordContextInitialized = true;
        this.isInitializingContext = false;
        this.embeddedOnRecordPage = true;
        this.activeReturnOrderId = returnOrderId;
        this.currentPage = PAGE_RECEIVE;
        this.isLoading = true;
        this.errorMessage = undefined;
        this.scanErrorMessage = undefined;
    }

    @wire(getRecentCreatedReturnOrders)
    wiredRecentReturnOrders(result) {
        if (this._recordId || this.embeddedOnRecordPage) {
            this.isRecentReturnOrdersLoading = false;
            return;
        }

        this.wiredRecentReturnOrdersResult = result;
        const { data, error } = result;

        if (data) {
            this.recentReturnOrders = data.map((row) => this.decorateReturnOrderSummary(row));
            this.isRecentReturnOrdersLoading = false;
        } else if (error) {
            this.isRecentReturnOrdersLoading = false;
        }
    }

    @wire(getReceivingContext, { returnOrderId: '$activeReturnOrderIdForWire' })
    wiredReceivingContext(result) {
        if (!this.isReceivePage) {
            return;
        }

        this.wiredReceivingContextResult = result;
        const { data, error } = result;

        if (data) {
            this.receivingContext = data;
            this.lineItems = (data.lineItems || []).map((line) =>
                this.decorateLineItem(line, data.returnOrderType)
            );
            this.selectedReceiverId = data.currentUserId;
            this.selectedReceivedDateTime = this.getDefaultReceivedDateTime();
            this.selectedIsContaminated = data.defaultIsContaminated
                ? CONTAMINATED_YES
                : CONTAMINATED_NO;
            this.instrumentQuantityReturned = data.headerQuantityReturned;
            this.instrumentQuantityReceived = data.defaultInstrumentQuantityReceived;
            this.disinfectedOptions = (data.disinfectedOptions || []).map((option) => ({
                label: option.label,
                value: option.value
            }));
            this.estimateRequiredOptions = (data.estimateRequiredOptions || []).map(
                (option) => ({
                    label: option.label,
                    value: option.value
                })
            );
            this.selectedRepairCenterCorrect = REPAIR_CENTER_CORRECT_YES;
            this.selectedRepairCenterId = undefined;
            this.selectedRedirectScope = undefined;
            this.errorMessage = undefined;
            this.isLoading = false;
            this.loadUserAndRepairCenterOptions();
        } else if (error) {
            this.errorMessage =
                error.body?.message || error.message || 'Unable to load return order receiving context.';
            this.isLoading = false;
        }
    }

    get activeReturnOrderIdForWire() {
        return this.isReceivePage ? this.activeReturnOrderId : undefined;
    }

    get acceptedMediaTypes() {
        return ACCEPTED_MEDIA_TYPES;
    }

    get isScanPage() {
        return !this.isInitializingContext && this.currentPage === PAGE_SCAN;
    }

    get isReceivePage() {
        return !this.isInitializingContext && this.currentPage === PAGE_RECEIVE;
    }

    get showBackToScan() {
        return this.isReceivePage && !this.embeddedOnRecordPage;
    }

    get hasRecentReturnOrders() {
        return this.recentReturnOrders.length > 0;
    }

    get hasLineItems() {
        return this.lineItems.length > 0;
    }

    get isSerializedType() {
        return this.receivingContext?.returnOrderType === RO_TYPE_SERIALIZED;
    }

    get isInstrumentsType() {
        return this.receivingContext?.returnOrderType === RO_TYPE_INSTRUMENTS;
    }

    get isOtherType() {
        return this.receivingContext?.returnOrderType === RO_TYPE_OTHER;
    }

    get showAssetColumn() {
        return this.isSerializedType;
    }

    get showStandardLineItemsTable() {
        return !this.isInstrumentsType;
    }

    get showLineSelectionColumn() {
        return !this.isInstrumentsType;
    }

    get showActionsColumn() {
        return this.isSerializedType || this.isOtherType;
    }

    get showProductLineColumn() {
        return this.isOtherType;
    }

    get showSerialNumberColumn() {
        return !this.isInstrumentsType;
    }

    get showStatusColumn() {
        return false;
    }

    get showHospitalTrayColumn() {
        return this.isOtherType;
    }

    get showQuantityReturnedColumn() {
        return this.isOtherType;
    }

    get quantityColumnLabel() {
        return this.isOtherType ? 'QTY Returned' : 'Quantity Received';
    }

    get showLineItemsSelectionHint() {
        return !this.isInstrumentsType;
    }

    get hasReceivableLines() {
        if (this.isInstrumentsType) {
            return this.lineItems.some((line) => line.selectable);
        }
        return this.hasSelectedLines;
    }

    get continueButtonLabel() {
        return this.isSerializedType ? 'Create Work Orders' : 'Create Work Order';
    }

    get showInstrumentQuantityField() {
        return this.isInstrumentsType;
    }

    get selectedLineCount() {
        return this.lineItems.filter((line) => line.selected).length;
    }

    get hasSelectedLines() {
        return this.selectedLineCount > 0;
    }

    get lineItemsSelectionHintClass() {
        const baseClass = 'line-items-selection-hint slds-text-body_small slds-m-bottom_small';
        return this.hasSelectedLines ? baseClass : `${baseClass} line-items-selection-hint_required`;
    }

    get hasPhotoAttachments() {
        return this.photoAttachments.length > 0;
    }

    get isLookupDisabled() {
        return this.isLookupLoading || !this.returnOrderNumberInput?.trim();
    }

    get showReceiveForm() {
        return !this.isLoading && !this.isSubmitting;
    }

    get isContinueDisabled() {
        if (
            this.isSubmitting ||
            !this.selectedIsContaminated ||
            !this.selectedReceiverId ||
            !this.selectedReceivedDateTime ||
            !this.hasReceivableLines
        ) {
            return true;
        }

        if (!this.selectedRepairCenterCorrect) {
            return true;
        }

        if (this.showAlternateRepairCenterPicker && !this.selectedRepairCenterId) {
            return true;
        }

        if (this.showRedirectScopeQuestion && !this.selectedRedirectScope) {
            return true;
        }

        return false;
    }

    get isContaminatedYes() {
        return this.selectedIsContaminated === CONTAMINATED_YES;
    }

    get isRepairCenterCorrect() {
        return this.selectedRepairCenterCorrect === REPAIR_CENTER_CORRECT_YES;
    }

    get isRepairCenterIncorrect() {
        return this.selectedRepairCenterCorrect === REPAIR_CENTER_CORRECT_NO;
    }

    get showAlternateRepairCenterPicker() {
        return this.isRepairCenterIncorrect;
    }

    get showRedirectScopeQuestion() {
        return (
            this.showAlternateRepairCenterPicker &&
            (this.receivingContext?.openLineItemCount || 0) > 1
        );
    }

    get redirectScopeMessage() {
        const count = this.receivingContext?.openLineItemCount || 0;
        return `Do you want to redirect all ${count} open line items on this return order?`;
    }

    get displayRepairCenterAddress() {
        return this.receivingContext?.repairCenterAddress || 'Address not available';
    }

    get selectedLineItem() {
        return this.lineItems.find((line) => line.lineItemId === this.selectedLineItemId);
    }

    get hasAccountAssetOptions() {
        return this.accountAssetOptions.length > 0;
    }

    get isLineModifyStep() {
        return this.modalStep === STEP_LINE_MODIFY;
    }

    get isLineAccessoriesStep() {
        return this.modalStep === STEP_LINE_ACCESSORIES;
    }

    get isSerializedModifyModal() {
        return this.isLineModifyStep && this.isSerializedType;
    }

    get isSerializedAddItemModal() {
        return this.isSerializedModifyModal && this.isAddingAdHocSerializedItem;
    }

    get yesNoOptions() {
        return YES_NO_OPTIONS;
    }

    get contactRecordFilter() {
        const accountId = this.receivingContext?.accountId;
        if (!accountId) {
            return null;
        }

        return {
            criteria: [
                {
                    fieldPath: 'AccountId',
                    operator: 'eq',
                    value: accountId
                }
            ]
        };
    }

    get isContactSearchDisabled() {
        return !this.receivingContext?.accountId;
    }

    get showAdHocEstimateContact() {
        return this.adHocEstimateRequired === ESTIMATE_REQUIRED_QUOTE_VALUE;
    }

    get showAdHocRepairWarrantyYes() {
        return this.adHocRepairWarranty === 'Yes';
    }

    get adHocWarrantyNotesRequired() {
        return (
            this.adHocRepairWarranty === 'Yes' &&
            !String(this.adHocPreviousReturnOrder || '').trim()
        );
    }

    get adHocWarrantyNotesHelpText() {
        return this.adHocWarrantyNotesRequired
            ? 'Required when Previous Return Order is not provided.'
            : '';
    }

    get modalContainerClass() {
        return this.isSerializedAddItemModal
            ? 'slds-modal__container slds-modal_large adhoc-serialized-modal'
            : 'slds-modal__container';
    }

    get modalSectionClass() {
        return this.isSerializedAddItemModal
            ? 'slds-modal slds-fade-in-open slds-modal_large'
            : 'slds-modal slds-fade-in-open';
    }

    get adHocFilteredAssetOptions() {
        return this.filterAdHocAccountAssets(this.adHocAssetSearchText);
    }

    get adHocAssetSearchLookupClass() {
        return this.showAdHocAssetResults
            ? 'product-search-lookup slds-form-element product-search-lookup--open'
            : 'product-search-lookup slds-form-element';
    }

    get isAdHocAssetSearchDisabled() {
        return !this.receivingContext?.accountId || !this.adHocAccountAssets.length;
    }

    get adHocProductSearchLookupClass() {
        return this.showAdHocProductResults
            ? 'product-search-lookup slds-form-element product-search-lookup--open'
            : 'product-search-lookup slds-form-element';
    }

    get isAdHocProductSearchDisabled() {
        return false;
    }

    get adHocProductPickerPlaceholder() {
        return 'Search or select product';
    }

    get adHocSearchControlKey() {
        return AD_HOC_SEARCH_CONTROL;
    }

    get showSelectedLineItemDetails() {
        return this.selectedLineItem && !this.isAddingAdHocSerializedItem;
    }

    get isSerializedAccessoriesModal() {
        return this.isLineAccessoriesStep && this.isSerializedType;
    }

    get modalTitle() {
        if (this.isLineAccessoriesStep) {
            return 'Add Accessories';
        }
        if (this.isSerializedAddItemModal) {
            return 'Add Serialized Item to Receive';
        }
        return 'Modify Line Item';
    }

    get isOtherModifyModal() {
        return this.isLineModifyStep && this.isOtherType;
    }

    get showFooterPrimary() {
        return this.isLineModifyStep || this.isLineAccessoriesStep;
    }

    get footerPrimaryButtonLabel() {
        if (this.isLineAccessoriesStep) {
            return 'Save Accessories';
        }
        if (this.isSerializedAddItemModal) {
            return 'Add Line';
        }
        return 'Save Changes';
    }

    get isNextDisabled() {
        if (this.isModalLoading) {
            return true;
        }
        if (this.isLineModifyStep) {
            if (this.isOtherModifyModal) {
                const originalItemType = this.selectedLineItem?.itemType;
                const itemTypeChanged =
                    this.correctionItemType &&
                    this.correctionItemType !== originalItemType;
                if (
                    !this.correctionItemType ||
                    this.correctionQuantityReturned === null ||
                    this.correctionQuantityReturned === undefined ||
                    this.correctionQuantityReturned === ''
                ) {
                    return true;
                }
                if (itemTypeChanged && !this.correctionProductId) {
                    return true;
                }
                return false;
            }
            if (this.isSerializedAddItemModal) {
                return (
                    !this.correctionSerialNumber?.trim() ||
                    !this.correctionModel?.trim() ||
                    !this.correctionProductId ||
                    !this.correctionDepartmentId ||
                    !this.adHocDisinfected ||
                    !this.adHocContactId ||
                    !this.adHocEstimateRequired ||
                    (this.showAdHocEstimateContact && !this.adHocEstimateContactId) ||
                    !this.adHocReportedProblem?.trim()
                );
            }
            return !this.correctionSerialNumber?.trim() || !this.correctionModel?.trim();
        }
        if (this.isLineAccessoriesStep) {
            if (!this.accessoryDraftRows.length) {
                return true;
            }
            return this.accessoryDraftRows.some(
                (row) =>
                    !row.accessoryType ||
                    !row.condition ||
                    !row.storageLocation?.trim() ||
                    row.quantity === null ||
                    row.quantity === undefined ||
                    row.quantity === '' ||
                    Number(row.quantity) < 1
            );
        }
        return true;
    }

    createAccessoryRow(existingRow) {
        return {
            rowId:
                existingRow?.rowId ||
                `acc-${Date.now()}-${Math.floor(Math.random() * 100000)}`,
            accessoryType: existingRow?.accessoryType || undefined,
            condition: existingRow?.condition || undefined,
            storageLocation: existingRow?.storageLocation || '',
            quantity:
                existingRow?.quantity != null && existingRow?.quantity !== ''
                    ? Number(existingRow.quantity)
                    : 1
        };
    }

    getDefaultReceivedDateTime() {
        return new Date().toISOString();
    }

    normalizeReceivedDateTime(value) {
        if (!value) {
            return null;
        }

        const dateValue = new Date(value);
        if (Number.isNaN(dateValue.getTime())) {
            return null;
        }

        return dateValue.toISOString();
    }

    formatCreatedDate(value) {
        if (!value) {
            return '';
        }
        return new Date(value).toLocaleString();
    }

    decorateReturnOrderSummary(row) {
        return {
            ...row,
            createdDateDisplay: this.formatCreatedDate(row.createdDate)
        };
    }

    decorateLineItem(line, returnOrderType) {
        const isSerializedType = returnOrderType === RO_TYPE_SERIALIZED;
        const isInstrumentsType = returnOrderType === RO_TYPE_INSTRUMENTS;
        const isOtherType = returnOrderType === RO_TYPE_OTHER;
        const lineItemId = line.lineItemId || line.id;
        return {
            lineItemId,
            lineNumber: line.lineNumber,
            status: line.status,
            assetId: line.assetId,
            assetName: line.assetName,
            serialNumber: line.serialNumber,
            productId: line.productId,
            productName: line.productName,
            productLine: line.productLine,
            hospitalTrayName: line.hospitalTrayName,
            itemDescription: line.itemDescription,
            itemType: line.itemType,
            quantityReturned: line.quantityReturned,
            quantityReceived: line.quantityReceived,
            selectable: line.selectable,
            model: line.model,
            departmentId: line.departmentId,
            lineType: line.lineType,
            rowClass: line.rowClass,
            recordUrl: `/${lineItemId}`,
            assetUrl: line.assetId ? `/${line.assetId}` : null,
            productUrl: line.productId ? `/${line.productId}` : null,
            selected: isInstrumentsType ? line.selectable === true : line.selectable === true,
            quantityReceivedReadOnly:
                isInstrumentsType ||
                isSerializedType ||
                isOtherType ||
                line.selectable !== true,
            hasCorrections: false,
            correctionSerialNumber: line.serialNumber,
            correctionModel: line.model,
            correctionDepartmentId: line.departmentId,
            correctionProductLine: line.productLine,
            correctionProductId: line.productId,
            correctionItemType: line.itemType,
            correctionHospitalTrayName: line.hospitalTrayName,
            correctionQuantityReturned: line.quantityReturned,
            selectedCorrectionAssetId: line.assetId,
            accessories: (line.accessories || []).map((accessory) => ({ ...accessory })),
            accessoryCount: (line.accessories || []).length,
            hasSavedAccessories: (line.accessories || []).length > 0,
            isAdHocLine: line.isAdHocLine === true,
            adHocLineKey: line.adHocLineKey || null,
            contactId: line.contactId,
            estimateRequired: line.estimateRequired,
            estimateContactId: line.estimateContactId,
            repairWarranty: line.repairWarranty,
            warrantyNotes: line.warrantyNotes,
            previousReturnOrder: line.previousReturnOrder,
            customerPo: line.customerPo,
            customerReference: line.customerReference,
            reportedProblem: line.reportedProblem,
            modRequest: line.modRequest === true,
            disinfected: line.disinfected,
            isLoanerAsset: line.isLoanerAsset === true,
            loanerRequested: line.loanerRequested === true
        };
    }

    getFirstReturnOrderLineItemTemplate() {
        return (
            this.lineItems.find((line) => !line.isAdHocLine && line.lineItemId) || null
        );
    }

    applyAdHocTemplateDefaults(templateLine) {
        const template = templateLine || {};
        this.adHocDisinfected = template.disinfected || '';
        this.adHocContactId = template.contactId || undefined;
        this.adHocEstimateRequired = template.estimateRequired || '';
        this.adHocEstimateContactId = template.estimateContactId || undefined;
        this.adHocRepairWarranty = template.repairWarranty || '';
        this.adHocWarrantyNotes = template.warrantyNotes || '';
        this.adHocPreviousReturnOrder = template.previousReturnOrder || '';
        this.adHocCustomerPo = template.customerPo || '';
        this.adHocCustomerReference = template.customerReference || '';
        this.adHocReportedProblem = template.reportedProblem || '';
        this.adHocModRequest = template.modRequest === true;
        this.adHocIsLoanerAsset = template.isLoanerAsset === true;
        this.adHocLoanerRequested = template.loanerRequested === true;
    }

    resetAdHocDeviceFields() {
        this.correctionSerialNumber = '';
        this.correctionModel = '';
        this.correctionProductId = undefined;
        this.selectedCorrectionAssetId = undefined;
        this.correctionDepartmentId = undefined;
        this.correctionProductLine = '';
        this.adHocAssetSearchText = '';
        this.showAdHocAssetResults = false;
        this.adHocAssetSearchDropdownStyle = '';
        this.adHocProductSearchText = '';
        this.adHocProductOptions = [];
        this.showAdHocProductResults = false;
        this.adHocProductSearchDropdownStyle = '';
        this.productOptions = [];
    }

    resetAdHocServiceFields() {
        this.correctionProductLine = '';
        this.adHocDisinfected = '';
        this.adHocContactId = undefined;
        this.adHocEstimateRequired = '';
        this.adHocEstimateContactId = undefined;
        this.adHocRepairWarranty = '';
        this.adHocWarrantyNotes = '';
        this.adHocPreviousReturnOrder = '';
        this.adHocCustomerPo = '';
        this.adHocCustomerReference = '';
        this.adHocReportedProblem = '';
        this.adHocModRequest = false;
        this.adHocIsLoanerAsset = false;
        this.adHocLoanerRequested = false;
    }

    buildAdHocSerializedLineItem({
        adHocLineKey,
        lineNumber,
        serialNumber,
        model,
        productId,
        productName,
        productLine,
        assetId,
        assetName,
        departmentId,
        contactId,
        estimateRequired,
        estimateContactId,
        repairWarranty,
        warrantyNotes,
        previousReturnOrder,
        customerPo,
        customerReference,
        reportedProblem,
        modRequest,
        disinfected,
        isLoanerAsset,
        loanerRequested
    }) {
        return {
            lineItemId: adHocLineKey,
            adHocLineKey,
            lineNumber,
            status: 'Ad Hoc',
            assetId,
            assetName,
            serialNumber,
            productId,
            productName,
            productLine,
            hospitalTrayName: null,
            itemDescription: null,
            itemType: null,
            quantityReturned: 1,
            quantityReceived: 1,
            selectable: true,
            model,
            departmentId,
            lineType: RO_TYPE_SERIALIZED,
            rowClass: 'row-adhoc',
            recordUrl: null,
            assetUrl: assetId ? `/${assetId}` : null,
            productUrl: productId ? `/${productId}` : null,
            selected: true,
            quantityReceivedReadOnly: true,
            hasCorrections: false,
            correctionSerialNumber: serialNumber,
            correctionModel: model,
            correctionDepartmentId: departmentId,
            correctionProductLine: productLine,
            correctionProductId: productId,
            correctionItemType: null,
            correctionHospitalTrayName: null,
            correctionQuantityReturned: 1,
            selectedCorrectionAssetId: assetId,
            contactId,
            estimateRequired,
            estimateContactId,
            repairWarranty,
            warrantyNotes,
            previousReturnOrder,
            customerPo,
            customerReference,
            reportedProblem,
            modRequest: modRequest === true,
            disinfected,
            isLoanerAsset: isLoanerAsset === true,
            loanerRequested: loanerRequested === true,
            accessories: [],
            accessoryCount: 0,
            hasSavedAccessories: false,
            isAdHocLine: true
        };
    }

    resolveProductLabel(productId) {
        if (!productId) {
            return null;
        }
        const productOption = this.productOptions.find((option) => option.value === productId);
        return productOption?.label || null;
    }

    async loadDepartmentOptions() {
        const accountId = this.receivingContext?.accountId;
        if (!accountId) {
            this.departmentOptions = [];
            return;
        }

        try {
            const departments = await getDepartmentsForAccount({ accountId });
            this.departmentOptions = (departments || []).map((department) => ({
                label: department.label,
                value: department.value
            }));
        } catch (error) {
            this.showToast(
                'Error',
                error.body?.message || error.message || 'Unable to load departments.',
                'error'
            );
            this.departmentOptions = [];
        }
    }

    async loadUserAndRepairCenterOptions() {
        try {
            const [users, repairCenters] = await Promise.all([
                getActiveInternalUsers(),
                getRepairCenterLocations()
            ]);
            this.userOptions = users.map((user) => ({
                label: user.label,
                value: user.value
            }));
            this.repairCenterOptions = repairCenters
                .filter((repairCenter) => repairCenter.value !== this.receivingContext?.repairCenterId)
                .map((repairCenter) => ({
                    label: repairCenter.label,
                    value: repairCenter.value
                }));
        } catch (error) {
            this.showToast(
                'Error',
                error.body?.message || error.message || 'Unable to load receive options.',
                'error'
            );
        }
    }

    handleReturnOrderNumberChange(event) {
        this.returnOrderNumberInput = event.detail.value;
        this.scanErrorMessage = undefined;
    }

    handleReturnOrderNumberKeyUp(event) {
        if (event.key === 'Enter') {
            this.handleLookupReturnOrder();
        }
    }

    async handleLookupReturnOrder() {
        const returnOrderNumber = this.returnOrderNumberInput?.trim();
        if (!returnOrderNumber) {
            this.scanErrorMessage = 'Return order number is required.';
            return;
        }

        this.isLookupLoading = true;
        this.scanErrorMessage = undefined;

        try {
            const returnOrderId = await findReturnOrderByNumber({ returnOrderNumber });
            await this.openReturnOrder(returnOrderId);
        } catch (error) {
            this.handleScanValidationError(error);
        } finally {
            this.isLookupLoading = false;
        }
    }

    async handleSelectRecentReturnOrder(event) {
        const returnOrderId =
            event.currentTarget.dataset.id || event.target.closest('[data-id]')?.dataset.id;
        if (!returnOrderId) {
            return;
        }

        this.isLookupLoading = true;
        this.scanErrorMessage = undefined;

        try {
            await validateReturnOrderForReceiving({ returnOrderId });
            await this.openReturnOrder(returnOrderId);
        } catch (error) {
            this.handleScanValidationError(error);
        } finally {
            this.isLookupLoading = false;
        }
    }

    handleScanValidationError(error) {
        this.scanErrorMessage =
            error.body?.message ||
            error.message ||
            'Unable to open this return order. Enter another return order number.';
        this.returnOrderNumberInput = '';
        this.currentPage = PAGE_SCAN;
        this.activeReturnOrderId = undefined;
        this.lineItems = [];
        this.receivingContext = undefined;
        this.refreshRecentReturnOrders();
    }

    async openReturnOrder(returnOrderId) {
        this.activeReturnOrderId = returnOrderId;
        this.currentPage = PAGE_RECEIVE;
        this.isLoading = true;
        this.errorMessage = undefined;
        this.scanErrorMessage = undefined;
        this.photoAttachments = [];
        this.selectAllLines = false;
    }

    handleBackToScan() {
        this.currentPage = PAGE_SCAN;
        this.activeReturnOrderId = undefined;
        this.lineItems = [];
        this.receivingContext = undefined;
        this.errorMessage = undefined;
        this.scanErrorMessage = undefined;
        this.returnOrderNumberInput = '';
        this.isLoading = false;
        this.refreshRecentReturnOrders();
    }

    async refreshRecentReturnOrders() {
        if (this.wiredRecentReturnOrdersResult) {
            await refreshApex(this.wiredRecentReturnOrdersResult);
        }
    }

    async refreshReceivingContext() {
        if (this.wiredReceivingContextResult) {
            await refreshApex(this.wiredReceivingContextResult);
        }
    }

    handleContaminatedChange(event) {
        this.selectedIsContaminated = event.detail.value;
    }

    handleReceiverChange(event) {
        this.selectedReceiverId = event.detail.value;
    }

    handleReceivedDateTimeChange(event) {
        this.selectedReceivedDateTime = event.detail.value;
    }

    handleInstrumentQuantityReceivedChange(event) {
        this.instrumentQuantityReceived = event.detail.value;
    }

    handleInstrumentQuantityStepUp() {
        const currentValue = Number(this.instrumentQuantityReceived);
        const nextValue = Number.isNaN(currentValue) ? 1 : currentValue + 1;
        this.instrumentQuantityReceived = nextValue;
    }

    handleInstrumentQuantityStepDown() {
        const currentValue = Number(this.instrumentQuantityReceived);
        const nextValue = Number.isNaN(currentValue) ? 0 : Math.max(0, currentValue - 1);
        this.instrumentQuantityReceived = nextValue;
    }

    syncInstrumentHeaderQuantity() {
        if (!this.isInstrumentsType) {
            return;
        }

        const total = this.lineItems.reduce((sum, line) => {
            const quantity =
                line.quantityReceived != null && line.quantityReceived !== ''
                    ? Number(line.quantityReceived)
                    : 0;
            return sum + (Number.isNaN(quantity) ? 0 : quantity);
        }, 0);

        this.instrumentQuantityReceived = total;
    }

    handleSelectAllLinesChange(event) {
        this.selectAllLines = event.target.checked;
        this.lineItems = this.lineItems.map((line) => ({
            ...line,
            selected: line.selectable ? this.selectAllLines : line.selected
        }));
        this.syncInstrumentHeaderQuantity();
    }

    handleLineSelectionChange(event) {
        const lineId = event.target.dataset.id;
        const isChecked = event.target.checked;
        this.lineItems = this.lineItems.map((line) =>
            line.lineItemId === lineId ? { ...line, selected: isChecked } : line
        );
        this.selectAllLines =
            this.lineItems.filter((line) => line.selectable).length > 0 &&
            this.lineItems.filter((line) => line.selectable).every((line) => line.selected);
        this.syncInstrumentHeaderQuantity();
    }

    handleLineQuantityChange(event) {
        const lineId = event.target.dataset.id;
        const value = event.detail.value;
        this.lineItems = this.lineItems.map((line) =>
            line.lineItemId === lineId ? { ...line, quantityReceived: value } : line
        );
        this.syncInstrumentHeaderQuantity();
    }

    handlePhotoUploadFinished(event) {
        const uploadedFiles = event.detail.files || [];
        if (uploadedFiles.length === 0) {
            return;
        }

        const newAttachments = uploadedFiles.map((file) => ({
            contentDocumentId: file.documentId,
            name: file.name
        }));
        this.photoAttachments = [...this.photoAttachments, ...newAttachments];
    }

    handleRemovePhoto(event) {
        const contentDocumentId = event.currentTarget.dataset.documentId;
        if (!contentDocumentId) {
            return;
        }

        this.photoAttachments = this.photoAttachments.filter(
            (attachment) => attachment.contentDocumentId !== contentDocumentId
        );
    }

    async handleAddSerializedItemClick() {
        this.isAddingAdHocSerializedItem = true;
        this.selectedLineItemId = null;
        this.modalStep = STEP_LINE_MODIFY;
        this.showModal = true;
        this.isModalLoading = true;

        this.resetAdHocDeviceFields();
        this.applyAdHocTemplateDefaults(this.getFirstReturnOrderLineItemTemplate());

        try {
            await Promise.all([
                this.loadAdHocAccountAssets(),
                this.loadDepartmentOptions()
            ]);
        } finally {
            this.isModalLoading = false;
        }
    }

    async handleModifyLineClick(event) {
        event.stopPropagation();
        const lineItemId = event.currentTarget.dataset.id;
        const line = this.lineItems.find((item) => item.lineItemId === lineItemId);
        if (!line) {
            return;
        }

        this.selectedLineItemId = lineItemId;
        this.isAddingAdHocSerializedItem = false;

        this.modalStep = STEP_LINE_MODIFY;
        this.showModal = true;
        this.isModalLoading = true;

        this.correctionSerialNumber = line.correctionSerialNumber || line.serialNumber || '';
        this.correctionModel = line.correctionModel || line.model || '';
        this.correctionProductId =
            line.correctionProductId || line.productId || undefined;
        this.selectedCorrectionAssetId = line.selectedCorrectionAssetId || line.assetId || undefined;

        try {
            if (this.isOtherType) {
                this.correctionItemType = line.correctionItemType || line.itemType || undefined;
                this.correctionProductLine =
                    line.correctionProductLine || line.productLine || '';
                this.correctionHospitalTrayName =
                    line.correctionHospitalTrayName || line.hospitalTrayName || '';
                this.correctionQuantityReturned =
                    line.correctionQuantityReturned ?? line.quantityReturned;

                await Promise.all([
                    this.loadOtherCorrectionOptions(),
                    this.loadProductOptions(
                        this.correctionProductLine,
                        this.correctionProductId,
                        false
                    )
                ]);
            } else {
                await Promise.all([
                    this.loadAccountAssetOptions(),
                    this.loadProductOptions(
                        line.productLine,
                        this.correctionProductId,
                        true
                    )
                ]);
            }
        } finally {
            this.isModalLoading = false;
        }
    }

    async handleAddAccessoriesClick(event) {
        event.stopPropagation();
        const lineItemId = event.currentTarget.dataset.id;
        const line = this.lineItems.find((item) => item.lineItemId === lineItemId);
        if (!line) {
            return;
        }

        this.selectedLineItemId = lineItemId;
        this.modalStep = STEP_LINE_ACCESSORIES;
        this.showModal = true;
        this.isModalLoading = true;

        const existingRows = (line.accessories || []).map((accessory) =>
            this.createAccessoryRow(accessory)
        );
        this.accessoryDraftRows =
            existingRows.length > 0 ? existingRows : [this.createAccessoryRow()];

        try {
            const [accessoryTypeOptions, accessoryConditionOptions] = await Promise.all([
                getAccessoryTypeOptions(),
                getAccessoryConditionOptions()
            ]);
            this.accessoryTypeOptions = (accessoryTypeOptions || []).map((option) => ({
                label: option.label,
                value: option.value
            }));
            this.accessoryConditionOptions = (accessoryConditionOptions || []).map(
                (option) => ({
                    label: option.label,
                    value: option.value
                })
            );
        } finally {
            this.isModalLoading = false;
        }
    }

    handleAddAccessoryRowClick() {
        this.accessoryDraftRows = [
            ...this.accessoryDraftRows,
            this.createAccessoryRow()
        ];
    }

    handleRemoveAccessoryRowClick(event) {
        const rowId = event.currentTarget.dataset.rowId;
        if (!rowId) {
            return;
        }
        const remainingRows = this.accessoryDraftRows.filter((row) => row.rowId !== rowId);
        this.accessoryDraftRows =
            remainingRows.length > 0 ? remainingRows : [this.createAccessoryRow()];
    }

    handleAccessoryFieldChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const field = event.currentTarget.dataset.field;
        if (!rowId || !field) {
            return;
        }

        let value = event.detail.value;
        if (field === 'quantity') {
            value =
                value === null || value === undefined || value === ''
                    ? value
                    : Number(value);
        }

        this.accessoryDraftRows = this.accessoryDraftRows.map((row) =>
            row.rowId === rowId ? { ...row, [field]: value } : row
        );
    }

    async loadOtherCorrectionOptions() {
        try {
            const [itemTypeOptions, mappings] = await Promise.all([
                getItemTypeOptions(),
                getItemTypeProductLineMappings()
            ]);
            this.itemTypeOptions = (itemTypeOptions || []).map((option) => ({
                label: option.label,
                value: option.value
            }));
            this.itemTypeToProductLine = (mappings || []).reduce((map, mapping) => {
                map[mapping.itemType] = mapping.productLine;
                return map;
            }, {});
        } catch (error) {
            this.itemTypeOptions = [];
            this.itemTypeToProductLine = {};
        }
    }

    async loadProductOptions(productLine, additionalProductId, requireServiceAssetType = true) {
        if (!productLine) {
            this.productOptions = [];
            return;
        }

        try {
            const products = await getProductsForLineCorrection({
                productLine,
                additionalProductId: additionalProductId || null,
                requireServiceAssetType
            });
            this.productOptions = (products || []).map((product) => ({
                label: product.label,
                value: product.value
            }));
        } catch (error) {
            this.productOptions = [];
        }
    }

    buildAssetDisplayLabel(asset) {
        if (!asset) {
            return '';
        }
        const parts = [
            asset.serialNumber,
            asset.productName,
            asset.model
        ].filter((part) => Boolean(String(part || '').trim()));
        return parts.length > 0 ? parts.join(' · ') : asset.id;
    }

    filterAdHocAccountAssets(searchTerm) {
        const term = String(searchTerm || '').trim().toLowerCase();
        const filtered = !term
            ? this.adHocAccountAssets
            : this.adHocAccountAssets.filter((asset) => {
                  const productName = String(asset.productName || '').toLowerCase();
                  const model = String(asset.model || '').toLowerCase();
                  const serial = String(asset.serialNumber || '').toLowerCase();
                  return (
                      productName.includes(term) ||
                      model.includes(term) ||
                      serial.includes(term)
                  );
              });
        return filtered.slice(0, 20).map((asset) => ({
            label: this.buildAssetDisplayLabel(asset),
            value: asset.serialNumber || asset.id
        }));
    }

    findAdHocAssetByValue(assetValue) {
        if (!assetValue) {
            return null;
        }
        return (
            this.adHocAccountAssets.find(
                (asset) => (asset.serialNumber || asset.id) === assetValue
            ) || null
        );
    }

    applyAdHocAssetToForm(asset) {
        if (!asset) {
            this.selectedCorrectionAssetId = undefined;
            this.adHocAssetSearchText = '';
            this.correctionSerialNumber = '';
            this.correctionProductId = undefined;
            this.adHocProductSearchText = '';
            this.correctionModel = '';
            this.correctionProductLine = '';
            return;
        }

        this.selectedCorrectionAssetId = asset.id;
        this.correctionSerialNumber = asset.serialNumber || '';
        this.correctionModel = asset.model || '';
        this.correctionProductId = asset.product2Id || undefined;
        this.correctionProductLine = asset.productLine || '';
        this.adHocProductSearchText = asset.productName || '';
        if (asset.departmentId) {
            this.correctionDepartmentId = asset.departmentId;
        }
        this.adHocAssetSearchText = this.buildAssetDisplayLabel(asset);
    }

    async loadAdHocAccountAssets() {
        const accountId = this.receivingContext?.accountId;
        if (!accountId) {
            this.adHocAccountAssets = [];
            return;
        }

        try {
            this.adHocAccountAssets = (await getAssetsForAccount({ accountId })) || [];
        } catch (error) {
            this.adHocAccountAssets = [];
            this.showToast(
                'Error',
                error.body?.message || error.message || 'Unable to load account assets.',
                'error'
            );
        }
    }

    handleAdHocAssetSearchFocus() {
        if (this.isAdHocAssetSearchDisabled) {
            return;
        }
        this.showAdHocAssetResults = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.updateAdHocAssetSearchDropdownPosition();
            this.ensureAdHocSearchViewportListeners();
        }, 0);
    }

    handleAdHocAssetSearchInput(event) {
        this.adHocAssetSearchText = event.target.value || '';
        this.showAdHocAssetResults = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.updateAdHocAssetSearchDropdownPosition();
            this.ensureAdHocSearchViewportListeners();
        }, 0);
    }

    handleAdHocAssetSearchBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.showAdHocAssetResults = false;
            this.adHocAssetSearchDropdownStyle = '';
            this.removeAdHocSearchViewportListenersIfIdle();
        }, 200);
    }

    handleAdHocAssetOptionSelect(event) {
        event.preventDefault();
        const assetValue = event.currentTarget.dataset.value || '';
        const asset = this.findAdHocAssetByValue(assetValue);
        this.applyAdHocAssetToForm(asset);
        this.showAdHocAssetResults = false;
        this.adHocAssetSearchDropdownStyle = '';
        this.removeAdHocSearchViewportListenersIfIdle();
    }

    updateAdHocAssetSearchDropdownPosition() {
        const control = this.template.querySelector(
            `[data-asset-search-control="${AD_HOC_SEARCH_CONTROL}"]`
        );
        if (!control) {
            return;
        }

        const rect = control.getBoundingClientRect();
        const top = Math.round(rect.bottom + 2);
        const left = Math.round(rect.left);
        const width = Math.max(Math.round(rect.width), 280);
        this.adHocAssetSearchDropdownStyle = `top: ${top}px; left: ${left}px; width: ${width}px;`;
    }

    async loadAdHocProductOptions(searchTerm, showResults = true) {
        try {
            const products = await getProductsForReturnOrderLine({
                productLine: this.correctionProductLine || '',
                requireServiceAssetType: true,
                searchTerm: searchTerm || ''
            });
            this.adHocProductOptions = (products || []).map((product) => ({
                label: product.label,
                value: product.value,
                model: product.model || '',
                name: product.name || ''
            }));
            this.showAdHocProductResults = showResults;
            if (showResults) {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                window.setTimeout(() => {
                    this.updateAdHocProductSearchDropdownPosition();
                    this.ensureAdHocSearchViewportListeners();
                }, 0);
            }
        } catch (error) {
            this.adHocProductOptions = [];
            this.showToast(
                'Error',
                error.body?.message || error.message || 'Unable to load products.',
                'error'
            );
        }
    }

    scheduleAdHocProductSearch(searchTerm) {
        if (this.adHocProductSearchTimer) {
            clearTimeout(this.adHocProductSearchTimer);
        }
        this.adHocProductSearchTimer = window.setTimeout(() => {
            this.loadAdHocProductOptions(searchTerm, true);
        }, 300);
    }

    handleAdHocProductSearchFocus() {
        if (this.isAdHocProductSearchDisabled) {
            return;
        }
        this.loadAdHocProductOptions(this.adHocProductSearchText || '', true);
    }

    handleAdHocProductSearchInput(event) {
        this.adHocProductSearchText = event.target.value || '';
        this.correctionProductId = undefined;
        this.correctionModel = '';
        this.correctionProductLine = '';
        this.showAdHocProductResults = true;
        this.scheduleAdHocProductSearch(this.adHocProductSearchText);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.updateAdHocProductSearchDropdownPosition();
            this.ensureAdHocSearchViewportListeners();
        }, 0);
    }

    handleAdHocProductSearchBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.showAdHocProductResults = false;
            this.adHocProductSearchDropdownStyle = '';
            this.removeAdHocSearchViewportListenersIfIdle();
        }, 200);
    }

    async handleAdHocProductOptionSelect(event) {
        event.preventDefault();
        const productId = event.currentTarget.dataset.value || '';
        const selectedOption = this.adHocProductOptions.find(
            (option) => option.value === productId
        );
        this.correctionProductId = productId || undefined;
        this.adHocProductSearchText = selectedOption?.label || selectedOption?.name || '';
        if (selectedOption?.model) {
            this.correctionModel = selectedOption.model;
        }
        this.showAdHocProductResults = false;
        this.adHocProductSearchDropdownStyle = '';
        this.removeAdHocSearchViewportListenersIfIdle();

        if (productId) {
            try {
                const product = await getProductDetails({
                    productId,
                    requireServiceAssetType: true
                });
                if (product?.Model__c && !this.correctionModel) {
                    this.correctionModel = product.Model__c;
                }
                if (product?.ProductLine__c) {
                    this.correctionProductLine = product.ProductLine__c;
                }
            } catch (error) {
                // Keep selected product even if detail lookup fails.
            }
        }
    }

    updateAdHocProductSearchDropdownPosition() {
        const control = this.template.querySelector(
            `[data-product-search-control="${AD_HOC_SEARCH_CONTROL}"]`
        );
        if (!control) {
            return;
        }

        const rect = control.getBoundingClientRect();
        const top = Math.round(rect.bottom + 2);
        const left = Math.round(rect.left);
        const width = Math.max(Math.round(rect.width), 280);
        this.adHocProductSearchDropdownStyle = `top: ${top}px; left: ${left}px; width: ${width}px;`;
    }

    ensureAdHocSearchViewportListeners() {
        if (this.adHocSearchViewportListenersAttached) {
            return;
        }

        this.adHocSearchViewportListenersAttached = true;
        this._boundRepositionAdHocSearch = () => {
            if (this.showAdHocAssetResults) {
                this.updateAdHocAssetSearchDropdownPosition();
            }
            if (this.showAdHocProductResults) {
                this.updateAdHocProductSearchDropdownPosition();
            }
        };
        window.addEventListener('scroll', this._boundRepositionAdHocSearch, true);
        window.addEventListener('resize', this._boundRepositionAdHocSearch);
    }

    removeAdHocSearchViewportListenersIfIdle() {
        if (this.showAdHocAssetResults || this.showAdHocProductResults) {
            return;
        }

        if (!this.adHocSearchViewportListenersAttached || !this._boundRepositionAdHocSearch) {
            return;
        }

        window.removeEventListener('scroll', this._boundRepositionAdHocSearch, true);
        window.removeEventListener('resize', this._boundRepositionAdHocSearch);
        this.adHocSearchViewportListenersAttached = false;
    }

    async loadAccountAssetOptions() {
        const accountId = this.receivingContext?.accountId;
        if (!accountId) {
            this.accountAssetOptions = [];
            this.accountAssetsById = {};
            return;
        }

        try {
            const assets = await getAccountAssetsForCorrection({ accountId });
            this.accountAssetsById = {};
            this.accountAssetOptions = (assets || []).map((asset) => {
                this.accountAssetsById[asset.id] = asset;
                return {
                    label: asset.label,
                    value: asset.id
                };
            });

            if (
                this.selectedCorrectionAssetId &&
                this.accountAssetsById[this.selectedCorrectionAssetId]
            ) {
                this.applySelectedAssetToCorrectionFields(this.selectedCorrectionAssetId);
            }
        } catch (error) {
            this.accountAssetOptions = [];
            this.accountAssetsById = {};
        }
    }

    applySelectedAssetToCorrectionFields(assetId) {
        const asset = this.accountAssetsById[assetId];
        if (!asset) {
            return;
        }

        this.correctionSerialNumber = asset.serialNumber || '';
        if (asset.model) {
            this.correctionModel = asset.model;
        }
    }

    async applyProductModelToCorrectionFields(productId) {
        if (!productId) {
            return;
        }

        try {
            const product = await getProductDetails({
                productId,
                requireServiceAssetType: true
            });
            if (product?.Model__c) {
                this.correctionModel = product.Model__c;
            }
        } catch (error) {
            // Keep the current model when product details cannot be loaded.
        }
    }

    async handleCorrectionAssetChange(event) {
        this.selectedCorrectionAssetId = event.detail.value || undefined;
        if (this.selectedCorrectionAssetId) {
            this.applySelectedAssetToCorrectionFields(this.selectedCorrectionAssetId);
            const asset = this.accountAssetsById[this.selectedCorrectionAssetId];
            if (asset?.productLine) {
                await this.loadProductOptions(
                    asset.productLine,
                    this.correctionProductId,
                    true
                );
            }
        }
    }

    handleCorrectionSerialChange(event) {
        this.correctionSerialNumber = event.detail.value;
    }

    handleCorrectionModelChange(event) {
        this.correctionModel = event.detail.value;
    }

    handleCorrectionDepartmentChange(event) {
        this.correctionDepartmentId = event.detail.value || undefined;
    }

    handleAdHocDisinfectedChange(event) {
        this.adHocDisinfected = event.detail.value;
    }

    handleAdHocContactChange(event) {
        this.adHocContactId = event.detail.recordId || undefined;
    }

    handleAdHocEstimateRequiredChange(event) {
        this.adHocEstimateRequired = event.detail.value;
        if (this.adHocEstimateRequired !== ESTIMATE_REQUIRED_QUOTE_VALUE) {
            this.adHocEstimateContactId = undefined;
        }
    }

    handleAdHocEstimateContactChange(event) {
        this.adHocEstimateContactId = event.detail.recordId || undefined;
    }

    handleAdHocRepairWarrantyChange(event) {
        this.adHocRepairWarranty = event.detail.value;
    }

    handleAdHocWarrantyNotesChange(event) {
        this.adHocWarrantyNotes = event.detail.value;
    }

    handleAdHocPreviousReturnOrderChange(event) {
        this.adHocPreviousReturnOrder = event.detail.value;
    }

    handleAdHocCustomerPoChange(event) {
        this.adHocCustomerPo = event.detail.value;
    }

    handleAdHocCustomerReferenceChange(event) {
        this.adHocCustomerReference = event.detail.value;
    }

    handleAdHocReportedProblemChange(event) {
        this.adHocReportedProblem = event.detail.value;
    }

    handleAdHocModRequestChange(event) {
        this.adHocModRequest = event.detail.checked;
    }

    handleAdHocIsLoanerAssetChange(event) {
        this.adHocIsLoanerAsset = event.detail.checked;
    }

    handleAdHocLoanerRequestedChange(event) {
        this.adHocLoanerRequested = event.detail.checked;
    }

    appendAdHocServiceFieldsToLineInput(lineInput, line) {
        lineInput.contactId = line.contactId || null;
        lineInput.estimateRequired = line.estimateRequired || null;
        lineInput.estimateContactId = line.estimateContactId || null;
        lineInput.repairWarranty = line.repairWarranty || null;
        lineInput.warrantyNotes = line.warrantyNotes || null;
        lineInput.previousReturnOrder = line.previousReturnOrder || null;
        lineInput.customerPo = line.customerPo || null;
        lineInput.customerReference = line.customerReference || null;
        lineInput.reportedProblem = line.reportedProblem || null;
        lineInput.modRequest = line.modRequest === true;
        lineInput.disinfected = line.disinfected || null;
        lineInput.isLoanerAsset = line.isLoanerAsset === true;
        lineInput.loanerRequested = line.loanerRequested === true;
        return lineInput;
    }

    async handleCorrectionProductChange(event) {
        this.correctionProductId = event.detail.value || undefined;
        await this.applyProductModelToCorrectionFields(this.correctionProductId);
    }

    handleCorrectionItemTypeChange(event) {
        this.correctionItemType = event.detail.value || undefined;
        this.correctionProductLine =
            this.itemTypeToProductLine[this.correctionItemType] || '';
        this.correctionProductId = undefined;
        if (this.correctionProductLine) {
            this.loadProductOptions(this.correctionProductLine, null, false);
        } else {
            this.productOptions = [];
        }
    }

    handleCorrectionHospitalTrayChange(event) {
        this.correctionHospitalTrayName = event.detail.value;
    }

    handleCorrectionQuantityReturnedChange(event) {
        this.correctionQuantityReturned = event.detail.value;
    }

    handleRepairCenterChange(event) {
        this.selectedRepairCenterId = event.detail.value;
    }

    handleRepairCenterCorrectChange(event) {
        this.selectedRepairCenterCorrect = event.detail.value;
        if (event.detail.value === REPAIR_CENTER_CORRECT_YES) {
            this.selectedRepairCenterId = undefined;
            this.selectedRedirectScope = undefined;
        }
    }

    handleRedirectScopeChange(event) {
        this.selectedRedirectScope = event.detail.value;
    }

    handleCancelModal() {
        this.closeModal();
    }

    async handleModalNext() {
        if (this.isLineModifyStep) {
            this.saveLineCorrections();
        } else if (this.isLineAccessoriesStep) {
            this.saveLineAccessories();
        }
    }

    async handleContinue() {
        if (!this.hasReceivableLines) {
            this.showToast(
                'Selection required',
                this.isInstrumentsType
                    ? 'No line items are available to receive.'
                    : 'Please select at least one line item to receive.',
                'error'
            );
            return;
        }

        if (this.isRepairCenterCorrect) {
            await this.submitReceive();
            return;
        }

        if (this.isRepairCenterIncorrect) {
            const redirectAll =
                (this.receivingContext?.openLineItemCount || 0) > 1
                    ? this.selectedRedirectScope === REDIRECT_SCOPE_ALL
                    : false;
            await this.submitRedirect(redirectAll);
        }
    }

    saveLineCorrections() {
        if (this.isSerializedAddItemModal) {
            this.adHocLineCounter += 1;
            const adHocLineKey = `adhoc-${this.adHocLineCounter}`;
            const selectedAsset = this.selectedCorrectionAssetId
                ? this.adHocAccountAssets.find(
                      (asset) => asset.id === this.selectedCorrectionAssetId
                  ) ||
                  this.accountAssetsById[this.selectedCorrectionAssetId]
                : null;
            const productName =
                this.adHocProductSearchText ||
                this.resolveProductLabel(this.correctionProductId);

            this.lineItems = [
                ...this.lineItems,
                this.buildAdHocSerializedLineItem({
                    adHocLineKey,
                    lineNumber: `Ad Hoc ${this.adHocLineCounter}`,
                    serialNumber: this.correctionSerialNumber?.trim(),
                    model: this.correctionModel?.trim(),
                    productId: this.correctionProductId,
                    productName,
                    productLine: selectedAsset?.productLine || this.correctionProductLine || null,
                    assetId: this.selectedCorrectionAssetId,
                    assetName: selectedAsset?.label || null,
                    departmentId: this.correctionDepartmentId,
                    contactId: this.adHocContactId,
                    estimateRequired: this.adHocEstimateRequired,
                    estimateContactId: this.adHocEstimateContactId,
                    repairWarranty: this.adHocRepairWarranty,
                    warrantyNotes: this.adHocWarrantyNotes,
                    previousReturnOrder: this.adHocPreviousReturnOrder,
                    customerPo: this.adHocCustomerPo,
                    customerReference: this.adHocCustomerReference,
                    reportedProblem: this.adHocReportedProblem,
                    modRequest: this.adHocModRequest,
                    disinfected: this.adHocDisinfected,
                    isLoanerAsset: this.adHocIsLoanerAsset,
                    loanerRequested: this.adHocLoanerRequested
                })
            ];
            this.showToast(
                'Line added',
                'The serialized item was added to the receive list.',
                'success'
            );
            this.closeModal();
            return;
        }

        this.lineItems = this.lineItems.map((line) => {
            if (line.lineItemId !== this.selectedLineItemId) {
                return line;
            }

            if (this.isOtherType) {
                const quantityReturned =
                    this.correctionQuantityReturned != null &&
                    this.correctionQuantityReturned !== ''
                        ? Number(this.correctionQuantityReturned)
                        : line.quantityReturned;

                return {
                    ...line,
                    hasCorrections: true,
                    correctionItemType: this.correctionItemType,
                    correctionProductLine: this.correctionProductLine || line.productLine,
                    correctionProductId: this.correctionProductId,
                    correctionSerialNumber: this.correctionSerialNumber?.trim(),
                    correctionHospitalTrayName: this.correctionHospitalTrayName?.trim(),
                    correctionQuantityReturned: quantityReturned,
                    itemType: this.correctionItemType || line.itemType,
                    productLine: this.correctionProductLine || line.productLine,
                    productId: this.correctionProductId || line.productId,
                    serialNumber: this.correctionSerialNumber?.trim() || line.serialNumber,
                    hospitalTrayName:
                        this.correctionHospitalTrayName?.trim() || line.hospitalTrayName,
                    quantityReturned,
                    quantityReceived: quantityReturned
                };
            }

            return {
                ...line,
                hasCorrections: true,
                correctionSerialNumber: this.correctionSerialNumber?.trim(),
                correctionModel: this.correctionModel?.trim(),
                correctionProductId: this.correctionProductId,
                selectedCorrectionAssetId: this.selectedCorrectionAssetId,
                serialNumber: this.correctionSerialNumber?.trim() || line.serialNumber,
                model: this.correctionModel?.trim() || line.model,
                productId: this.correctionProductId || line.productId,
                productName:
                    this.resolveProductLabel(this.correctionProductId) || line.productName,
                assetId: this.selectedCorrectionAssetId || line.assetId,
                assetName: this.selectedCorrectionAssetId
                    ? this.accountAssetsById[this.selectedCorrectionAssetId]?.label ||
                      line.assetName
                    : line.assetName
            };
        });
        this.closeModal();
    }

    saveLineAccessories() {
        const accessories = this.accessoryDraftRows
            .filter(
                (row) =>
                    row.accessoryType && row.condition && row.storageLocation?.trim()
            )
            .map((row) => ({
                rowId: row.rowId,
                accessoryType: row.accessoryType,
                condition: row.condition,
                storageLocation: row.storageLocation?.trim() || '',
                quantity:
                    row.quantity != null && row.quantity !== '' ? Number(row.quantity) : 1
            }));

        this.lineItems = this.lineItems.map((line) =>
            line.lineItemId === this.selectedLineItemId
                ? {
                      ...line,
                      accessories,
                      accessoryCount: accessories.length,
                      hasSavedAccessories: accessories.length > 0
                  }
                : line
        );
        this.showToast(
            'Accessories saved',
            accessories.length
                ? `${accessories.length} accessory line(s) will be added to the work order when you receive this line.`
                : 'Accessory lines cleared for this line item.',
            'success'
        );
        this.closeModal();
    }

    buildLineInputs() {
        const linesToReceive = this.isInstrumentsType
            ? this.lineItems.filter((line) => line.selectable && line.lineItemId)
            : this.lineItems.filter((line) => line.selected && line.lineItemId);

        return linesToReceive.map((line) => {
            const quantityReturned =
                line.correctionQuantityReturned != null
                    ? Number(line.correctionQuantityReturned)
                    : line.quantityReturned != null
                      ? Number(line.quantityReturned)
                      : null;

            const lineInput = {
                quantityReceived: this.isOtherType
                    ? quantityReturned
                    : line.quantityReceived != null
                      ? Number(line.quantityReceived)
                      : null,
                hasCorrections: line.hasCorrections === true,
                serialNumber: this.isOtherType
                    ? line.correctionSerialNumber || line.serialNumber || null
                    : line.correctionSerialNumber || line.serialNumber || null,
                model: line.correctionModel || line.model || null,
                departmentId: line.correctionDepartmentId || line.departmentId || null,
                productLine: line.correctionProductLine || line.productLine || null,
                productId: line.correctionProductId || line.productId || null,
                selectedAssetId: line.selectedCorrectionAssetId || line.assetId || null,
                itemType: line.correctionItemType || line.itemType || null,
                hospitalTrayName:
                    line.correctionHospitalTrayName || line.hospitalTrayName || null,
                quantityReturned,
                accessories: (line.accessories || [])
                    .filter(
                        (accessory) =>
                            accessory.accessoryType &&
                            accessory.condition &&
                            accessory.storageLocation?.trim()
                    )
                    .map((accessory) => ({
                        accessoryType: accessory.accessoryType,
                        condition: accessory.condition,
                        storageLocation: accessory.storageLocation || null,
                        quantity:
                            accessory.quantity != null ? Number(accessory.quantity) : 1
                    }))
            };

            if (line.isAdHocLine) {
                lineInput.isAdHocSerializedLine = true;
                lineInput.adHocLineKey = line.adHocLineKey || line.lineItemId;
                return this.appendAdHocServiceFieldsToLineInput(lineInput, line);
            }

            lineInput.lineItemId = String(line.lineItemId);
            return lineInput;
        });
    }

    async submitReceive() {
        this.isSubmitting = true;

        try {
            const lineInputs = this.buildLineInputs();
            if (!lineInputs.length) {
                this.showToast(
                    'Selection required',
                    'Please select at least one line item to receive.',
                    'error'
                );
                return;
            }

            const result = await receiveReturnOrder({
                returnOrderId: this.activeReturnOrderId,
                receiverId: this.selectedReceiverId,
                receivedDateTime: this.normalizeReceivedDateTime(this.selectedReceivedDateTime),
                isContaminated: this.isContaminatedYes,
                instrumentQuantityReceived: this.isInstrumentsType
                    ? Number(this.instrumentQuantityReceived)
                    : null,
                lineInputsJson: JSON.stringify(lineInputs),
                contentDocumentIds: this.photoAttachments.map(
                    (attachment) => attachment.contentDocumentId
                )
            });

            const workOrderId = result.navigationWorkOrderId || result.primaryWorkOrderId;
            const expectedChildCount = result.expectedSerializedChildCount;
            let childrenReady = true;
            if (workOrderId && expectedChildCount > 1) {
                childrenReady = await this.waitForSerializedChildWorkOrders(
                    workOrderId,
                    expectedChildCount
                );
            }

            this.showToast(
                'Success',
                childrenReady
                    ? result.returnOrderReceived
                        ? 'Return order received successfully.'
                        : 'Selected line items received successfully.'
                    : 'Return order received. Remaining work orders are still being created.',
                'success',
                childrenReady ? 'dismissable' : 'sticky'
            );

            if (workOrderId) {
                this.navigateToWorkOrder(workOrderId);
            } else {
                await this.refreshReceivingContext();
            }
        } catch (error) {
            this.showToast(
                'Error',
                error.body?.message || error.message || 'Unable to complete receiving.',
                'error'
            );
        } finally {
            this.isSubmitting = false;
        }
    }

    async waitForSerializedChildWorkOrders(parentWorkOrderId, expectedChildCount) {
        const maxAttempts = 15;
        for (let attempt = 0; attempt < maxAttempts; attempt++) {
            let childCount = 0;
            try {
                childCount = await getSerializedChildWorkOrderCount({ parentWorkOrderId });
            } catch (error) {
                childCount = 0;
            }
            if (childCount >= expectedChildCount) {
                return true;
            }
            await new Promise((resolve) => {
                setTimeout(resolve, 2000);
            });
        }
        return false;
    }

    async submitRedirect(redirectAllOpenLines) {
        this.isSubmitting = true;
        this.isModalLoading = true;

        const firstSelectedLine = this.lineItems.find((line) => line.selected);
        if (!firstSelectedLine) {
            this.isSubmitting = false;
            this.isModalLoading = false;
            return;
        }

        try {
            const result = await redirectLineItem({
                lineItemId: firstSelectedLine.lineItemId,
                repairCenterId: this.selectedRepairCenterId,
                redirectAllOpenLines
            });
            this.showToast(
                'Success',
                redirectAllOpenLines
                    ? `Return order ${result.returnOrderNumber} created with all open line items.`
                    : `Return order ${result.returnOrderNumber} created.`,
                'success'
            );
            this.closeModal();
            this.navigateToRecord(result.returnOrderId);
        } catch (error) {
            this.showToast(
                'Error',
                error.body?.message || error.message || 'Unable to complete the redirect.',
                'error'
            );
        } finally {
            this.isSubmitting = false;
            this.isModalLoading = false;
        }
    }

    closeModal() {
        this.showModal = false;
        this.modalStep = undefined;
        this.isAddingAdHocSerializedItem = false;
        this.selectedLineItemId = undefined;
        this.correctionSerialNumber = '';
        this.correctionModel = '';
        this.correctionProductId = undefined;
        this.correctionItemType = undefined;
        this.correctionProductLine = '';
        this.correctionHospitalTrayName = '';
        this.correctionQuantityReturned = undefined;
        this.correctionDepartmentId = undefined;
        this.resetAdHocServiceFields();
        this.productOptions = [];
        this.itemTypeOptions = [];
        this.itemTypeToProductLine = {};
        this.accountAssetOptions = [];
        this.accountAssetsById = {};
        this.selectedCorrectionAssetId = undefined;
        this.accessoryDraftRows = [];
        this.accessoryTypeOptions = [];
        this.accessoryConditionOptions = [];
        this.adHocAccountAssets = [];
        this.adHocAssetSearchText = '';
        this.showAdHocAssetResults = false;
        this.adHocAssetSearchDropdownStyle = '';
        this.adHocProductSearchText = '';
        this.adHocProductOptions = [];
        this.showAdHocProductResults = false;
        this.adHocProductSearchDropdownStyle = '';
        this.removeAdHocSearchViewportListenersIfIdle();
    }

    disconnectedCallback() {
        this.removeAdHocSearchViewportListenersIfIdle();
    }

    navigateToRecord(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'ReturnOrder',
                actionName: 'view'
            }
        });
    }

    navigateToWorkOrder(workOrderId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: workOrderId,
                objectApiName: 'WorkOrder',
                actionName: 'view'
            }
        });
    }

    showToast(title, message, variant, mode) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant,
                mode: mode || 'dismissable'
            })
        );
    }
}