import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    setTabLabel
} from 'lightning/platformWorkspaceApi';
import resolveScanInput from '@salesforce/apex/ReceivingController.resolveScanInput';
import getReceivingShellContext from '@salesforce/apex/ReceivingController.getReceivingShellContext';
import getWorkOrderReceivingShellContext from '@salesforce/apex/ReceivingController.getWorkOrderReceivingShellContext';
import saveWorkOrderQuantityReceived from '@salesforce/apex/ReceivingController.saveWorkOrderQuantityReceived';
import submitVendorWorkOrderReceiving from '@salesforce/apex/ReceivingController.submitVendorWorkOrderReceiving';
import stageModFormPhoto from '@salesforce/apex/ReceivingController.stageModFormPhoto';
import deleteModFormPhoto from '@salesforce/apex/ReceivingController.deleteModFormPhoto';
import renameModFormPhoto from '@salesforce/apex/ReceivingController.renameModFormPhoto';
import stageReceivingPhoto from '@salesforce/apex/ReceivingController.stageReceivingPhoto';
import attachReceivingPhotos from '@salesforce/apex/ReceivingController.attachReceivingPhotos';
import deleteReceivingPhoto from '@salesforce/apex/ReceivingController.deleteReceivingPhoto';
import renameReceivingPhoto from '@salesforce/apex/ReceivingController.renameReceivingPhoto';
import applySerialOverride from '@salesforce/apex/ReceivingController.applySerialOverride';
import applyWorkOrderSerialOverride from '@salesforce/apex/ReceivingController.applyWorkOrderSerialOverride';
import submitWorkOrderRerunResiTest from '@salesforce/apex/ReceivingController.submitWorkOrderRerunResiTest';
import getRepairCenterOptions from '@salesforce/apex/ReceivingController.getRepairCenterOptions';
import getInternalAccountOptions from '@salesforce/apex/ReceivingController.getInternalAccountOptions';
import getVendorAccountOptions from '@salesforce/apex/ReceivingController.getVendorAccountOptions';
import canCreateNewOrderApex from '@salesforce/apex/ReceivingController.canCreateNewOrder';
import buildCreateOrderPlan from '@salesforce/apex/ReceivingController.buildCreateOrderPlan';
import submitCreateOrder from '@salesforce/apex/ReceivingController.submitCreateOrder';
import createWorkOrdersForCreateOrder from '@salesforce/apex/ReceivingController.createWorkOrdersForCreateOrder';
import finishReceivingItem from '@salesforce/apex/ReceivingController.finishReceivingItem';
import reprintWorkOrderTravelTag from '@salesforce/apex/ReceivingController.reprintWorkOrderTravelTag';
import getAssetsByIds from '@salesforce/apex/CreateReturnOrderController.getAssetsByIds';
import getProductDetails from '@salesforce/apex/CreateReturnOrderController.getProductDetails';

const PAGE_SCAN = 'scan';
const PAGE_RECEIVE = 'receive';
const PAGE_CREATE_NEW_ORDER = 'createNewOrder';
const CREATE_ORDER_STEP_ACCOUNT = '1';
const CREATE_ORDER_STEP_ADD_ITEM = '2';
const CREATE_ORDER_STEP_PRODUCT = '3';
const CREATE_ORDER_STEP_SUMMARY = '4';
const CREATE_ORDER_STEP_CONFIRMATION = '5';
const CREATE_ORDER_ITEM_TYPE_SERIALIZED = 'serialized';
const CREATE_ORDER_ITEM_TYPE_OPTIONS = [
    {
        key: CREATE_ORDER_ITEM_TYPE_SERIALIZED,
        itemType: CREATE_ORDER_ITEM_TYPE_SERIALIZED,
        typeLabel: 'Serialized',
        description: 'Flexible, Rigid, Power, Video, Ultrasound, Endocam',
        enabled: true
    },
    {
        key: 'tray',
        itemType: 'tray',
        typeLabel: 'Tray (TBD)',
        description: 'TBD',
        enabled: false
    },
    {
        key: 'loose-instruments',
        itemType: 'loose-instruments',
        typeLabel: 'Loose Instruments (TBD)',
        description: 'TBD',
        enabled: false
    }
];
const CREATE_ORDER_PROGRESS_STEPS = [
    { label: '', value: '1' },
    { label: '', value: '2' },
    { label: '', value: '3' },
    { label: '', value: '4' },
    { label: '', value: '5' }
];
/** sessionStorage key — Create New Order eligibility (repair-center gate). */
const CAN_CREATE_NEW_ORDER_CACHE_KEY = 'receiving.canCreateNewOrder';
const PATH_WORK_ORDER = 'WorkOrder';
const BROWSER_TAB_LABEL = 'Receiving';

/**
 * GW-4348 / GW-5996 - Read cached Create New Order eligibility for instant paint.
 * @returns {boolean|undefined} Cached true/false, or undefined when unknown
 */
function readCanCreateNewOrderCache() {
    try {
        const cached = sessionStorage.getItem(CAN_CREATE_NEW_ORDER_CACHE_KEY);
        if (cached === 'true') {
            return true;
        }
        if (cached === 'false') {
            return false;
        }
    } catch (e) {
        // sessionStorage may be unavailable (private mode / iframe restrictions)
    }
    return undefined;
}

/**
 * GW-4348 / GW-5996 - Persist Create New Order eligibility for this browser session.
 * @param {boolean} canCreate Whether the user can create a new order
 */
function writeCanCreateNewOrderCache(canCreate) {
    try {
        sessionStorage.setItem(
            CAN_CREATE_NEW_ORDER_CACHE_KEY,
            canCreate === true ? 'true' : 'false'
        );
    } catch (e) {
        // Ignore storage failures; wire result still drives the UI.
    }
}
const SCAN_FIELD_LABEL = 'Return Order / Work Order Id / Number';
const SCAN_FIELD_PLACEHOLDER = 'Scan or enter Return Order / Work Order Id / Number';
const MOD_FORM_ACCEPT = 'image/*,.jpg,.jpeg,.png,.heic,.webp';
const MOD_REQUEST_PHOTO_FILE_NAME = 'Mod Request.jpg';
const TYPE_SERIALIZED = 'Serialized';
const TYPE_OTHER_SERIALIZED = 'Other (Serialized)';
const TYPE_OTHER_NON_SERIALIZED = 'Other (Non-Serialized)';
const TYPE_INSTRUMENTS = 'Instruments';
const REASON_CODE_SERIAL_MISMATCH = 'Serial Number Mismatch';
const REASON_CODE_MODEL_MISMATCH = 'Model Mismatch';
const REASON_CODE_REPAIR_EXCHANGE_MODEL_MISMATCH = 'Repair Exchange Model Mismatch';
const REASON_CODE_QUANTITY_MISMATCH = 'Quantity Mismatch';
const BADGE_LABEL_WORK_ORDER_CREATED = 'Work Order Created';
const BADGE_LABEL_REDIRECT = 'Redirect';
// Blue, yellow, red, then purple and green. Alphabetical within each color.
const BADGE_COLOR_ORDER = {
    info: 0,
    warning: 1,
    alert: 2,
    redirect: 3,
    complete: 4
};
const RETURN_TO_RECORD_DELAY_MS = 800;
const ITEM_PANEL_VERIFICATION = 'verification';
const ITEM_PANEL_ACTIONS = 'actions';
const ITEM_PANEL_CUSTOMER_CARE = 'customerCare';
const ITEM_PANEL_ACCESSORIES = 'accessories';
const ITEM_PANEL_OUTSIDE_VENDOR = 'outsideVendor';
const ITEM_PANEL_INTERNAL_REPAIR = 'internalRepair';
const ITEM_PANEL_OVERRIDE = 'override';
const ITEM_PANEL_REDIRECT = 'redirect';
const ITEM_PANEL_RERUN_RESI = 'rerunResi';
const ACTION_KEY_CUSTOMER_CARE = 'customerCare';
const ACTION_KEY_OVERRIDE = 'override';
const ACTION_KEY_ACCESSORIES = 'accessories';
const ACTION_KEY_OUTSIDE_VENDOR = 'outsideVendor';
const ACTION_KEY_INTERNAL_REPAIR = 'internalRepair';
const ACTION_KEY_REDIRECT = 'redirect';
const ACTION_KEY_TAKE_PIC = 'takePic';
const ACTION_KEY_RERUN_RESI = 'rerunResi';
const ACTION_KEY_TRAVEL_TAG = 'travelTag';
const OVERRIDE_SERIAL_CHARACTER_LIMIT = 2;
const OVERRIDE_SERIAL_ERROR =
    'Only 2 characters may be changed when overriding a Serial Number. ' +
    'Please contact Customer Care below for additional changes.';
const PHOTO_MODE_MOD_FORM = 'modForm';
const PHOTO_MODE_TAKE_PIC = 'takePic';
const REASON_CODE_MISSING_RETURN_ORDER = 'Missing Return Order';
// SLDS icons matched to the GW-5492 Actions mockup (Return Order path).
const RECEIVING_ACTION_OPTIONS = [
    {
        key: 'customerCare',
        label: 'Contact Customer Care',
        description: 'Resolve serial number, model, or other receipt discrepancies.',
        iconName: 'utility:questions_and_answers'
    },
    {
        key: ACTION_KEY_OVERRIDE,
        label: 'Override',
        description: 'Correct the serial number or model information received.',
        iconName: 'utility:edit_form'
    },
    {
        key: ACTION_KEY_ACCESSORIES,
        label: 'Add Case or Accessories',
        description: 'Record any cases or accessories received.',
        iconName: 'utility:new'
    },
    {
        key: ACTION_KEY_REDIRECT,
        label: 'Redirect Repair Center',
        description: 'Route item(s) to the appropriate STERIS Repair Center location.',
        iconName: 'utility:truck'
    },
    {
        key: ACTION_KEY_OUTSIDE_VENDOR,
        label: 'Outside Vendor',
        description: 'Send item(s) to an external vendor for repair services.',
        iconName: 'utility:replace'
    },
    {
        key: ACTION_KEY_INTERNAL_REPAIR,
        label: 'Internal Repair',
        description: 'Process the item through the internal STERIS repair workflow.',
        iconName: 'utility:custom_apps'
    },
    {
        key: ACTION_KEY_TAKE_PIC,
        label: 'Take a Picture',
        description: 'Capture and upload photos of the received contents.',
        iconName: 'utility:photo'
    }
];
// GW-5968 - Work Order Actions (all WO RTs except RepairCenterOther / Vendor).
const WORK_ORDER_ACTION_OPTIONS = [
    {
        key: ACTION_KEY_RERUN_RESI,
        label: 'Rerun Resi-Test',
        description: 'Rerun the Resi-Test for previously received Orders and add disinfection code.',
        iconName: 'utility:path_experiment'
    },
    {
        key: ACTION_KEY_OVERRIDE,
        label: 'Override',
        description: 'Correct the serial number or model information received.',
        iconName: 'utility:edit_form'
    },
    {
        key: ACTION_KEY_TAKE_PIC,
        label: 'Take a Pic',
        description: 'Capture and upload photos of the received contents.',
        iconName: 'utility:photo'
    },
    {
        key: ACTION_KEY_TRAVEL_TAG,
        label: 'Re-print Travel Tag',
        description: 'Print the Travel Tag.',
        iconName: 'utility:print'
    }
];
/** WOLI AccessoryType__c values (WorkOrderLineItem) — labels match org picklist. */
const ACCESSORY_TYPE_OPTIONS = [
    { label: 'AW Cleaning Adapter', value: 'AW_Cleaning_Adapter' },
    { label: 'Brushes/Forceps', value: 'Brushes_Forceps' },
    { label: 'Bullet', value: 'Bullet' },
    { label: 'Button/Valves', value: 'Button_Valves' },
    { label: 'Cap Ring', value: 'Cap_Ring' },
    { label: 'Case', value: 'Case' },
    { label: 'Channel Plug', value: 'Channel_Plug' },
    { label: 'ETO cap', value: 'ETO_cap' },
    { label: 'Injection Tube', value: 'Injection_Tube' },
    { label: 'Light Guide Adapter', value: 'Light_Guide_Adapter' },
    { label: 'Light Source Adapter', value: 'Light_Source_Adapter' },
    { label: 'Other', value: 'Other' },
    { label: 'RFID tag', value: 'RFID_tag' },
    { label: 'Storz', value: 'Storz' },
    { label: 'Tray', value: 'Tray' },
    { label: 'Trumpet (safelight adapter)', value: 'Trumpet_safelight_adapter' },
    { label: 'Water/Soaking Cap', value: 'Water_Soaking_Cap' },
    { label: 'Wolf', value: 'Wolf' }
].sort((a, b) => a.label.localeCompare(b.label));
const ACCESSORY_TYPE_LABEL_BY_VALUE = ACCESSORY_TYPE_OPTIONS.reduce((map, option) => {
    map[option.value] = option.label;
    return map;
}, {});
const CUSTOMER_CARE_REASON_OPTIONS = [
    { label: REASON_CODE_SERIAL_MISMATCH, value: REASON_CODE_SERIAL_MISMATCH },
    { label: REASON_CODE_MODEL_MISMATCH, value: REASON_CODE_MODEL_MISMATCH },
    {
        label: REASON_CODE_REPAIR_EXCHANGE_MODEL_MISMATCH,
        value: REASON_CODE_REPAIR_EXCHANGE_MODEL_MISMATCH
    },
    { label: 'Item Mismatch', value: 'Item Mismatch' },
    { label: REASON_CODE_QUANTITY_MISMATCH, value: REASON_CODE_QUANTITY_MISMATCH },
    { label: 'Ownership Mismatch', value: 'Ownership Mismatch' },
    { label: 'Missing Return Order', value: REASON_CODE_MISSING_RETURN_ORDER },
    { label: 'Other', value: 'Other' }
];
const CUSTOMER_CARE_REASON_LABELS = new Set(
    CUSTOMER_CARE_REASON_OPTIONS.map((option) => option.value)
);
const DISINFECTED_ADD_ITEM_OPTIONS = [
    { label: 'Yes', value: 'Clean' },
    { label: 'No', value: 'Contaminated' }
];

export default class Receiving extends NavigationMixin(LightningElement) {
    @wire(IsConsoleNavigation) isConsoleNavigation;

    @wire(getRepairCenterOptions)
    wiredRepairCenterOptions({ data, error }) {
        if (data) {
            this.repairCenterOptions = data.map((option) => ({
                label: option.label,
                value: option.value
            }));
        } else if (error) {
            this.repairCenterOptions = [];
        }
    }

    @wire(getInternalAccountOptions)
    wiredInternalAccountOptions({ data, error }) {
        if (data) {
            this.internalAccountOptions = data.map((option) => ({
                label: option.label,
                value: option.value
            }));
        } else if (error) {
            this.internalAccountOptions = [];
        }
    }

    @wire(getVendorAccountOptions)
    wiredVendorAccountOptions({ data, error }) {
        if (data) {
            this.vendorAccountOptions = data.map((option) => ({
                label: option.label,
                value: option.value
            }));
        } else if (error) {
            this.vendorAccountOptions = [];
        }
    }

    @wire(canCreateNewOrderApex)
    wiredCanCreateNewOrder({ data, error }) {
        if (data === true) {
            this.canCreateNewOrder = true;
            writeCanCreateNewOrderCache(true);
        } else if (data === false || error) {
            this.canCreateNewOrder = false;
            writeCanCreateNewOrderCache(false);
        }
    }

    _recordId;
    _initializedFromRecord = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.initializeFromRecordId();
    }

    currentPage = PAGE_SCAN;
    scanInput = '';
    scanErrorMessage;
    isLoading = false;
    isResolving = false;
    /** @type {boolean|undefined} undefined = wire pending (no cache) */
    canCreateNewOrder = readCanCreateNewOrderCache();
    createOrderCurrentStep = CREATE_ORDER_STEP_ACCOUNT;
    createOrderHeader = {};
    createOrderSelectedItemType = '';
    createOrderItemsSnapshot = { items: [] };
    createOrderItemsMounted = false;
    createOrderSummaryGroups = [];
    createOrderConfirmationOrders = [];
    isCreateOrderSubmitting = false;
    activeReturnOrderId;
    activeWorkOrderId;
    /** ContentDocument Ids already linked to the scanned Work Order. */
    committedWorkOrderPhotoIds = new Set();
    shellContext;
    itemUiState = {};

    isModFormBusy = false;
    isOverrideSubmitting = false;
    isRerunResiSubmitting = false;
    isTravelTagPrinting = false;
    isFinishReceivingBusy = false;
    repairCenterOptions = [];
    internalAccountOptions = [];
    vendorAccountOptions = [];
    isModFormDropActive = false;
    modFormError;
    isModFormCameraOpen = false;
    modFormCameraItemKey;
    photoModalMode = PHOTO_MODE_MOD_FORM;
    selectedCameraId;
    cameraOptions = [];
    cameraError;
    isCameraStarting = false;
    isCameraActive = false;
    isCapturing = false;
    mediaStream;
    videoEl;
    canvasEl;
    renamingDocumentIds = new Set();
    deletingDocumentIds = new Set();
    thumbnailFallbackIds = new Set();

    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        this._pageReference = pageRef;
        this.updateWorkspaceTab();
    }

    connectedCallback() {
        document.title = BROWSER_TAB_LABEL;
        this.updateWorkspaceTab();
        this.initializeFromRecordId();
    }

    get rootClass() {
        const classes = ['receiving-root'];
        if (this.showReceivePage) {
            classes.push('receiving-root_receive');
            if (!this.entryReturnOrderId) {
                classes.push('receiving-root_tab');
            }
            return classes.join(' ');
        }
        if (this.showCreateNewOrderPage) {
            classes.push('receiving-root_create-order', 'slds-p-around_medium');
            return classes.join(' ');
        }
        classes.push('receiving-root_scan', 'slds-p-around_medium');
        if (this.showCreateNewOrderButton) {
            classes.push('receiving-root_scan-with-create');
        }
        return classes.join(' ');
    }

    get showScanPage() {
        return !this.isLoading && this.currentPage === PAGE_SCAN;
    }

    get showCreateNewOrderPage() {
        return !this.isLoading && this.currentPage === PAGE_CREATE_NEW_ORDER;
    }

    /**
     * Show Create New Order when eligible, or while eligibility is still loading
     * (disabled). Hide only after Apex/cache confirms the user is ineligible.
     */
    get showCreateNewOrderButton() {
        return this.canCreateNewOrder !== false;
    }

    get isCreateNewOrderButtonDisabled() {
        return this.isScanBusy || this.canCreateNewOrder !== true;
    }

    get showCreateOrderAccountStep() {
        return this.createOrderCurrentStep === CREATE_ORDER_STEP_ACCOUNT;
    }

    get showCreateOrderAddItemStep() {
        return this.createOrderCurrentStep === CREATE_ORDER_STEP_ADD_ITEM;
    }

    get showCreateOrderProductStep() {
        return this.createOrderCurrentStep === CREATE_ORDER_STEP_PRODUCT;
    }

    get showCreateOrderSummaryStep() {
        return this.createOrderCurrentStep === CREATE_ORDER_STEP_SUMMARY;
    }

    get showCreateOrderConfirmationStep() {
        return this.createOrderCurrentStep === CREATE_ORDER_STEP_CONFIRMATION;
    }

    get showCreateOrderAccountSummary() {
        return (
            this.showCreateNewOrderPage &&
            !this.showCreateOrderAccountStep &&
            !this.showCreateOrderConfirmationStep &&
            Boolean(this.createOrderAccountName)
        );
    }

    get showCreateOrderAddItemMenu() {
        return this.showCreateOrderProductStep || this.showCreateOrderSummaryStep;
    }

    get showCreateOrderCancelButton() {
        return !this.showCreateOrderConfirmationStep;
    }

    get showCreateOrderAddItemBack() {
        return this.showCreateOrderAddItemStep;
    }

    get showCreateOrderItemsHost() {
        return this.createOrderItemsMounted === true;
    }

    get createOrderItemsHostClass() {
        return this.showCreateOrderProductStep
            ? 'create-order-items-host'
            : 'create-order-items-host slds-hide';
    }

    get showCreateOrderAccountNext() {
        return this.showCreateOrderAccountStep;
    }

    get showCreateOrderProductFooter() {
        return this.showCreateOrderProductStep;
    }

    get showCreateOrderSummaryFooter() {
        return this.showCreateOrderSummaryStep;
    }

    get showCreateOrderConfirmationFooter() {
        return this.showCreateOrderConfirmationStep;
    }

    get createOrderCardTitle() {
        if (this.showCreateOrderConfirmationStep) {
            return 'Order(s) Created';
        }
        if (this.showCreateOrderSummaryStep) {
            return 'Review Order(s)';
        }
        return 'Create Order';
    }

    get isCreateOrderSummaryNextDisabled() {
        return (
            this.isCreateOrderSubmitting ||
            !(this.createOrderSummaryGroups || []).length
        );
    }

    get createOrderAccountId() {
        return this.createOrderHeader?.accountId || '';
    }

    get createOrderAddItemMenuOptions() {
        return CREATE_ORDER_ITEM_TYPE_OPTIONS.map((option) => ({
            ...option,
            value: option.itemType,
            label: option.typeLabel,
            disabled: option.enabled !== true
        }));
    }

    get createOrderProgressSteps() {
        return CREATE_ORDER_PROGRESS_STEPS;
    }

    get createOrderItemTypeOptions() {
        return CREATE_ORDER_ITEM_TYPE_OPTIONS.map((option) => {
            const isEnabled = option.enabled === true;
            return {
                ...option,
                isEnabled,
                isDisabled: !isEnabled,
                rowClass: isEnabled
                    ? 'slds-hint-parent create-order-item-type-table__row'
                    : 'slds-hint-parent create-order-item-type-table__row create-order-item-type-table__row--disabled'
            };
        });
    }

    get createOrderAccountName() {
        return this.createOrderHeader?.accountName || '';
    }

    get createOrderAccountMetaDisplay() {
        const header = this.createOrderHeader || {};
        const parts = [
            header.salesRepName,
            header.operatingUnitLabel || header.operatingUnit,
            header.legacyCustomerId
        ].filter((part) => Boolean(part));
        return parts.join(' \u2022 ');
    }

    get isCreateOrderAccountNextDisabled() {
        const header = this.createOrderHeader || {};
        return !(header.accountId && header.operatingUnit && header.salesRepId);
    }

    get showReceivePage() {
        return !this.isLoading && this.currentPage === PAGE_RECEIVE && !!this.shellContext;
    }

    get isScanBusy() {
        return this.isResolving || this.isLoading;
    }

    get scanFieldLabel() {
        return SCAN_FIELD_LABEL;
    }

    get scanFieldPlaceholder() {
        return SCAN_FIELD_PLACEHOLDER;
    }

    get receiveCardTitle() {
        if (this.shellContext?.headerTitle) {
            return this.shellContext.headerTitle;
        }
        if (this.isWorkOrderPath) {
            return 'Work Order';
        }
        const orderNumber = this.shellContext?.returnOrderNumber || '';
        return orderNumber ? `Receive Order ${orderNumber}` : 'Receive Order';
    }

    /**
     * GW-6070 - Show the Ship Complete pill beside the Work Order number
     * after a Work Order scan when Ship Complete is true.
     */
    get showShipCompleteBadge() {
        return this.isWorkOrderPath && this.shellContext?.shipComplete === true;
    }

    get isWorkOrderPath() {
        return this.shellContext?.pathType === PATH_WORK_ORDER;
    }

    get isReturnOrderPath() {
        return !this.isWorkOrderPath;
    }

    get isVendorWorkOrder() {
        return this.isWorkOrderPath && this.shellContext?.isVendorWorkOrder === true;
    }

    get showStandardItemList() {
        return !this.isVendorWorkOrder;
    }

    get showAddItemButton() {
        return this.isReturnOrderPath;
    }

    get accountMetaDisplay() {
        const salesRep = this.shellContext?.salesRepName || '—';
        const operatingUnit = this.shellContext?.operatingUnit || '—';
        const legacyCustomerId = this.shellContext?.legacyCustomerId || '—';
        return `${salesRep} \u2022 ${operatingUnit} \u2022 ${legacyCustomerId}`;
    }

    get hasKeyIndicators() {
        return !!(this.shellContext?.isCio || this.shellContext?.isCreditHold);
    }

    get keyIndicatorsDisplay() {
        const indicators = [];
        if (this.shellContext?.isCio) {
            indicators.push('CIO');
        }
        if (this.shellContext?.isCreditHold) {
            indicators.push('Credit Hold');
        }
        return indicators.join(' | ');
    }

    get hasItems() {
        return (this.shellContext?.items || []).length > 0;
    }

    get displayItems() {
        const items = this.shellContext?.items || [];
        return items.map((item) => this.toDisplayItem(item));
    }

    get customerCareReasonOptions() {
        return CUSTOMER_CARE_REASON_OPTIONS;
    }

    get accessoryTypeOptions() {
        return ACCESSORY_TYPE_OPTIONS;
    }

    get disinfectedAddItemOptions() {
        return DISINFECTED_ADD_ITEM_OPTIONS;
    }

    get isSerializedStyleAddItem() {
        const returnOrderType = this.shellContext?.returnOrderType;
        return (
            returnOrderType === TYPE_SERIALIZED || returnOrderType === TYPE_OTHER_SERIALIZED
        );
    }

    get finishedItemCount() {
        return (this.shellContext?.items || []).filter((item) =>
            this.isItemFinishedReceiving(item)
        ).length;
    }

    get showCancelButton() {
        if (this.isVendorWorkOrder) {
            return false;
        }
        return this.hasItems === false || this.finishedItemCount === 0;
    }

    get showReceiveNextOrderButton() {
        if (this.isVendorWorkOrder) {
            return false;
        }
        const items = this.shellContext?.items || [];
        if (items.length === 0) {
            return false;
        }
        // GW-5968 - WO path footer always offers Receive Next Order on screen 2.
        if (this.isWorkOrderPath) {
            return true;
        }
        return this.finishedItemCount === items.length;
    }

    get showFinishReceivingOnActions() {
        return this.isReturnOrderPath;
    }

    get vendorDisplayItems() {
        return (this.shellContext?.items || []).map((item) => {
            const state = this.getItemState(item.itemKey);
            const vendorVerified = state.vendorVerified !== false;
            return {
                ...item,
                vendorVerified,
                vendorToggleLabel: `Verify item ${item.itemNumber}`
            };
        });
    }

    get showVendorSubmitButton() {
        if (!this.isVendorWorkOrder || !this.hasItems) {
            return false;
        }
        return (this.shellContext?.items || []).every((item) => {
            const state = this.getItemState(item.itemKey);
            return state.vendorVerified !== false;
        });
    }

    get hasAccountForAssetPicker() {
        return !!this.shellContext?.accountId;
    }

    get accountAssetFilter() {
        return {
            criteria: [
                {
                    fieldPath: 'AccountId',
                    operator: 'eq',
                    value: this.shellContext?.accountId || '000000000000000AAA'
                }
            ]
        };
    }

    get modFormAccept() {
        return MOD_FORM_ACCEPT;
    }

    get isTakePicMode() {
        return this.photoModalMode === PHOTO_MODE_TAKE_PIC;
    }

    get modFormPhotoModalTitle() {
        if (!this.isTakePicMode) {
            return 'Mod Form Photos';
        }
        const item = (this.shellContext?.items || []).find(
            (row) => row.itemKey === this.modFormCameraItemKey
        );
        const label = item?.productCode || item?.displayTitle || 'Item';
        return `Photos — ${label}`;
    }

    get photoModalSubtitle() {
        if (this.isTakePicMode) {
            return 'Files are staged for this item and saved when you Finish Receiving.';
        }
        return 'Capture with the camera or upload files. Photos are attached to the Return Order when saved.';
    }

    get photoModalEmptyMessage() {
        return this.isTakePicMode ? 'No photos for this item yet.' : 'No Mod Form photos yet.';
    }

    get isModFormPhotoModalBusy() {
        return this.isModFormBusy || this.isCapturing;
    }

    get isStartCameraDisabled() {
        return (
            this.isCameraStarting ||
            this.isCameraActive ||
            !this.selectedCameraId ||
            this.isModFormBusy
        );
    }

    get isCaptureDisabled() {
        return !this.isCameraActive || this.isCapturing || this.isModFormBusy;
    }

    get isStopCameraDisabled() {
        return !this.isCameraActive || this.isCameraStarting;
    }

    get modFormModalPhotos() {
        if (!this.modFormCameraItemKey) {
            return [];
        }
        const photos = this.photosForOpenModal(this.modFormCameraItemKey);
        return photos.map((file) => {
            const contentDocumentId = file.contentDocumentId;
            const editTitle = file.editTitle != null ? file.editTitle : file.title || '';
            const savedTitle = file.title || '';
            const isRenaming = this.renamingDocumentIds.has(contentDocumentId);
            const isDeleting = this.deletingDocumentIds.has(contentDocumentId);
            const isTitleDirty = editTitle.trim() !== savedTitle.trim();
            const previewUrl = file.imageDownloadUrl || file.thumbnailUrl;
            const showThumbnail =
                !!previewUrl && !this.thumbnailFallbackIds.has(contentDocumentId);
            return {
                ...file,
                fileExtension: file.fileExtension || '—',
                showThumbnail,
                thumbnailUrl: previewUrl,
                editTitle,
                isRenaming,
                isDeleting,
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

    get hasModFormModalPhotos() {
        return this.modFormModalPhotos.length > 0;
    }

    handleScanValueChange(event) {
        this.scanInput = event.detail?.value || '';
        this.scanErrorMessage = undefined;
    }

    async handleScanContinue(event) {
        const value = (event.detail?.value || this.scanInput || '').trim();
        if (!value || this.isResolving) {
            return;
        }
        this.isResolving = true;
        this.scanErrorMessage = undefined;
        try {
            const result = await resolveScanInput({ scanInput: value });
            if (result?.pathType === PATH_WORK_ORDER) {
                await this.openWorkOrder(result.workOrderId);
            } else {
                await this.openReturnOrder(result.returnOrderId);
            }
        } catch (error) {
            this.scanErrorMessage = this.normalizeError(error);
        } finally {
            this.isResolving = false;
        }
    }

    /**
     * GW-4348 / GW-5996 - Open Create New Order wizard shell from Receiving scan.
     */
    handleCreateNewOrder() {
        if (this.canCreateNewOrder !== true || this.isScanBusy) {
            return;
        }
        this.scanErrorMessage = undefined;
        this.resetCreateOrderWizardState();
        this.currentPage = PAGE_CREATE_NEW_ORDER;
    }

    /**
     * GW-4348 / GW-5996 - Cancel Create New Order and return to Receiving scan.
     */
    handleCancelCreateNewOrder() {
        this.resetCreateOrderWizardState();
        this.resetToScanPage();
    }

    handleCreateOrderAccountChange(event) {
        this.createOrderHeader = {
            ...(event.detail || {})
        };
    }

    handleCreateOrderAccountNext() {
        const accountInfo = this.refs?.createOrderAccountInfo;
        if (accountInfo && typeof accountInfo.validate === 'function' && !accountInfo.validate()) {
            return;
        }
        if (accountInfo && typeof accountInfo.getValues === 'function') {
            this.createOrderHeader = accountInfo.getValues();
        }
        if (this.isCreateOrderAccountNextDisabled) {
            return;
        }
        this.createOrderSelectedItemType = '';
        this.createOrderCurrentStep = CREATE_ORDER_STEP_ADD_ITEM;
    }

    /**
     * GW-4348 / GW-5996 - Add Item step: Serialized advances; Tray / Loose Instruments disabled.
     */
    handleCreateOrderSelectItemType(event) {
        event.preventDefault();
        const itemType = event.currentTarget?.dataset?.itemType;
        if (!itemType || itemType !== CREATE_ORDER_ITEM_TYPE_SERIALIZED) {
            return;
        }
        this.openCreateOrderProductStep({ ensureItem: true });
    }

    /**
     * GW-4348 / GW-5996 - Product step Add Item menu (Serialized only for now).
     */
    handleCreateOrderAddItemMenuSelect(event) {
        const itemType = event.detail?.value;
        if (!itemType || itemType !== CREATE_ORDER_ITEM_TYPE_SERIALIZED) {
            return;
        }
        this.createOrderSelectedItemType = itemType;
        this.createOrderItemsMounted = true;
        this.createOrderCurrentStep = CREATE_ORDER_STEP_PRODUCT;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            const itemsCmp = this.refs?.createOrderItems;
            if (itemsCmp && typeof itemsCmp.addSerializedItem === 'function') {
                itemsCmp.addSerializedItem();
            }
        }, 0);
    }

    openCreateOrderProductStep({ ensureItem = false } = {}) {
        this.createOrderSelectedItemType = CREATE_ORDER_ITEM_TYPE_SERIALIZED;
        this.createOrderItemsMounted = true;
        this.createOrderCurrentStep = CREATE_ORDER_STEP_PRODUCT;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            const itemsCmp = this.refs?.createOrderItems;
            if (!itemsCmp) {
                return;
            }
            if (ensureItem && typeof itemsCmp.ensureSerializedItem === 'function') {
                itemsCmp.ensureSerializedItem();
            }
        }, 0);
    }

    handleCreateOrderBack() {
        if (this.isCreateOrderSubmitting) {
            return;
        }
        if (this.showCreateOrderSummaryStep) {
            this.createOrderCurrentStep = CREATE_ORDER_STEP_PRODUCT;
            return;
        }
        if (this.showCreateOrderProductStep) {
            this.createOrderCurrentStep = CREATE_ORDER_STEP_ADD_ITEM;
            return;
        }
        if (this.showCreateOrderAddItemStep) {
            this.returnToCreateOrderAccountStep();
        }
    }

    /**
     * GW-5996 - Add Item Back returns to Account Information and restores the values
     * entered before Next. The form remounts, so apply the saved header after render.
     */
    returnToCreateOrderAccountStep() {
        const header = { ...(this.createOrderHeader || {}) };
        this.createOrderCurrentStep = CREATE_ORDER_STEP_ACCOUNT;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            const accountInfo = this.refs?.createOrderAccountInfo;
            if (accountInfo && typeof accountInfo.applyValues === 'function') {
                accountInfo.applyValues(header);
            }
        }, 0);
    }

    async handleCreateOrderProductNext() {
        const itemsCmp = this.refs?.createOrderItems;
        if (itemsCmp && typeof itemsCmp.validate === 'function' && !itemsCmp.validate()) {
            return;
        }
        if (itemsCmp && typeof itemsCmp.getValues === 'function') {
            this.createOrderItemsSnapshot = itemsCmp.getValues();
        }

        this.isCreateOrderSubmitting = true;
        try {
            const groups = await buildCreateOrderPlan({
                headerJson: JSON.stringify(this.buildCreateOrderHeaderPayload()),
                itemsJson: JSON.stringify(this.createOrderItemsSnapshot?.items || [])
            });
            this.createOrderSummaryGroups = groups || [];
            this.createOrderCurrentStep = CREATE_ORDER_STEP_SUMMARY;
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to build order summary',
                    message: this.normalizeError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isCreateOrderSubmitting = false;
        }
    }

    async handleCreateOrderSummaryNext() {
        if (this.isCreateOrderSummaryNextDisabled) {
            return;
        }

        this.isCreateOrderSubmitting = true;
        try {
            // RO create first; WO create is one Apex transaction per RO so Work Order
            // before-save Flow limits are not exceeded across multiple orders.
            const result = await submitCreateOrder({
                headerJson: JSON.stringify(this.buildCreateOrderHeaderPayload()),
                itemsJson: JSON.stringify(this.createOrderItemsSnapshot?.items || [])
            });

            const returnOrderIds = result?.returnOrderIds || [];
            if (!returnOrderIds.length) {
                throw new Error('No return orders were created.');
            }

            const summaryGroups = this.createOrderSummaryGroups || [];
            const confirmationOrders = [];
            for (let index = 0; index < returnOrderIds.length; index += 1) {
                const created = await createWorkOrdersForCreateOrder({
                    returnOrderId: returnOrderIds[index]
                });
                const group = summaryGroups[index] || {};
                const workOrderId = created?.workOrderId;
                if (!workOrderId) {
                    continue;
                }
                confirmationOrders.push({
                    rowKey: workOrderId,
                    workOrderId,
                    workOrderNumber: created.workOrderNumber || workOrderId,
                    productLine: group.productLine || '',
                    repairCenterName: group.repairCenterName || ''
                });
            }

            if (!confirmationOrders.length) {
                throw new Error('No Work Orders were created.');
            }

            this.createOrderConfirmationOrders = confirmationOrders;
            this.createOrderCurrentStep = CREATE_ORDER_STEP_CONFIRMATION;
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to create orders',
                    message: this.normalizeError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isCreateOrderSubmitting = false;
        }
    }

    buildCreateOrderHeaderPayload() {
        const header = this.createOrderHeader || {};
        return {
            accountId: header.accountId || '',
            operatingUnit: header.operatingUnit || '',
            salesRepId: header.salesRepId || '',
            creationSource: 'Salesforce'
        };
    }

    resetCreateOrderWizardState() {
        const accountInfo = this.refs?.createOrderAccountInfo;
        if (accountInfo && typeof accountInfo.reset === 'function') {
            accountInfo.reset();
        }
        const itemsCmp = this.refs?.createOrderItems;
        if (itemsCmp && typeof itemsCmp.reset === 'function') {
            itemsCmp.reset();
        }
        this.createOrderCurrentStep = CREATE_ORDER_STEP_ACCOUNT;
        this.createOrderHeader = {};
        this.createOrderSelectedItemType = '';
        this.createOrderItemsSnapshot = { items: [] };
        this.createOrderSummaryGroups = [];
        this.createOrderConfirmationOrders = [];
        this.createOrderItemsMounted = false;
        this.isCreateOrderSubmitting = false;
    }

    /**
     * GW-4348 / GW-5996 - Close Create Order confirmation and return to Receiving scan.
     */
    handleCreateOrderConfirmationClose() {
        this.resetCreateOrderWizardState();
        this.resetToScanPage();
    }

    /**
     * GW-4348 / GW-5996 - Open a created Work Order in a new browser tab.
     * @param {CustomEvent} event Confirmation row click
     */
    async handleCreateOrderOpenWorkOrder(event) {
        const workOrderId = event?.detail?.workOrderId;
        if (!workOrderId) {
            return;
        }
        try {
            const url = await this[NavigationMixin.GenerateUrl]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: workOrderId,
                    objectApiName: 'WorkOrder',
                    actionName: 'view'
                }
            });
            window.open(url, '_blank');
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to open Work Order',
                    message: this.normalizeError(error),
                    variant: 'error'
                })
            );
        }
    }

    handleBackToScan() {
        this.resetToScanPage();
    }

    /**
     * GW-5492 - Footer Cancel: discard and return to entry point.
     * Screen actions ignore NavigationMixin while the panel is open, so close
     * the action first, then open the Return Order record.
     */
    async handleCancelReceiving() {
        if (this.entryReturnOrderId) {
            const attached = await this.commitWorkOrderPhotos();
            if (!attached) {
                return;
            }
            this.dismissPhotoModal();
            this.returnToEntryReturnOrder();
            return;
        }
        await this.resetToScanPage();
    }

    /**
     * Close the Return Order screen action.
     * Finish Receiving passes reloadPage so the open record picks up Received.
     * @param {boolean} reloadPage When true, reload the record page after the action closes.
     * @return true when Receiving was opened from a Return Order
     */
    returnToEntryReturnOrder(reloadPage) {
        const returnOrderId = this.entryReturnOrderId;
        if (!returnOrderId) {
            return false;
        }
        this.dispatchEvent(new CloseActionScreenEvent());
        // Navigation is ignored until the screen action panel closes.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            if (reloadPage === true) {
                // NavigationMixin to the record already on screen does not refresh it.
                window.location.reload();
                return;
            }
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: returnOrderId,
                    objectApiName: 'ReturnOrder',
                    actionName: 'view'
                }
            });
        }, 0);
        return true;
    }

    /**
     * Record id when Receiving was opened from a Return Order (quick action or record page).
     * The Receiving tab has no record id, so Cancel returns to the scan screen.
     */
    get entryReturnOrderId() {
        if (this._recordId) {
            return this._recordId;
        }
        const pageRef = this._pageReference;
        if (
            pageRef?.type === 'standard__recordPage' &&
            pageRef?.attributes?.objectApiName === 'ReturnOrder' &&
            pageRef?.attributes?.recordId
        ) {
            return pageRef.attributes.recordId;
        }
        return null;
    }

    handleVendorVerifiedToggle(event) {
        const itemKey = event.target?.dataset?.itemKey || event.currentTarget?.dataset?.itemKey;
        if (!itemKey) {
            return;
        }
        const checked =
            event.detail && Object.prototype.hasOwnProperty.call(event.detail, 'checked')
                ? event.detail.checked === true
                : event.target.checked === true;
        this.updateItemState(itemKey, {
            vendorVerified: checked
        });
    }

    async handleVendorWorkOrderSubmit() {
        if (!this.activeWorkOrderId || !this.showVendorSubmitButton) {
            return;
        }
        this.isLoading = true;
        try {
            await submitVendorWorkOrderReceiving({ workOrderId: this.activeWorkOrderId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Vendor Work Order receiving submitted.',
                    variant: 'success'
                })
            );
            this.resetToScanPage();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: this.normalizeError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * GW-5492 / GW-5968 - Receive Next Order saves Scan Work Order verification,
     * then returns to the scan screen.
     */
    async handleReceiveNextOrder() {
        const saved = await this.commitWorkOrderQuantity();
        if (!saved) {
            return;
        }
        const leftScan = await this.resetToScanPage();
        if (leftScan) {
            this._initializedFromRecord = true;
        }
    }

    /**
     * GW-5968 - Persists Quantity Received edited on a scanned Work Order.
     * @return {Promise<boolean>} False when the quantity is missing or the save failed
     */
    async commitWorkOrderQuantity() {
        if (!this.isWorkOrderPath || !this.activeWorkOrderId) {
            return true;
        }
        const quantityItem = (this.shellContext?.items || []).find(
            (item) => item.showQuantityVerify === true
        );
        if (!quantityItem) {
            return true;
        }
        const rawValue = this.getItemState(quantityItem.itemKey).quantityReceived;
        if (rawValue === null || rawValue === '') {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Quantity Received is required',
                    message: 'Enter Quantity Received before receiving the next order.',
                    variant: 'error'
                })
            );
            return false;
        }
        const quantityReceived = Number(rawValue);
        if (!Number.isFinite(quantityReceived) || quantityReceived < 0) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Quantity Received is required',
                    message: 'Enter a valid Quantity Received before receiving the next order.',
                    variant: 'error'
                })
            );
            return false;
        }
        const loadedQuantity =
            quantityItem.quantityReturned == null ? null : Number(quantityItem.quantityReturned);
        if (loadedQuantity === quantityReceived) {
            return true;
        }
        try {
            await saveWorkOrderQuantityReceived({
                workOrderId: this.activeWorkOrderId,
                quantityReceived
            });
            return true;
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to save Quantity Received',
                    message: this.normalizeError(error),
                    variant: 'error'
                })
            );
            return false;
        }
    }

    async resetToScanPage() {
        const attached = await this.commitWorkOrderPhotos();
        if (!attached) {
            return false;
        }
        this.dismissPhotoModal();
        this.currentPage = PAGE_SCAN;
        this.activeReturnOrderId = undefined;
        this.activeWorkOrderId = undefined;
        this.committedWorkOrderPhotoIds = new Set();
        this.shellContext = undefined;
        this.itemUiState = {};
        this.scanInput = '';
        this.scanErrorMessage = undefined;
        this.modFormError = undefined;
        return true;
    }

    /**
     * GW-5492 - Footer Add Item to Receive: client-side draft Item (persisted later via Actions).
     */
    handleAddItemToReceive() {
        if (!this.shellContext) {
            return;
        }
        const items = [...(this.shellContext.items || [])];
        const itemNumber = items.length + 1;
        const itemKey = `adhoc-${Date.now()}`;
        const isSerializedAdd = this.isSerializedStyleAddItem;
        const draftItem = {
            itemKey,
            itemNumber,
            headerTitle: `Item ${itemNumber}:`,
            displayTitle: '',
            lineItemId: null,
            isAdHoc: true,
            isInstrumentItem: this.shellContext.returnOrderType === TYPE_INSTRUMENTS,
            showSerialVerify: false,
            showModelVerify: false,
            showQuantityVerify: false,
            showOutsideVendor: false,
            isVendorRequired: false,
            badges: []
        };
        this.shellContext = {
            ...this.shellContext,
            items: [...items, draftItem]
        };
        this.updateItemState(itemKey, {
            isExpanded: true,
            isAdHoc: true,
            isSerializedAddItem: isSerializedAdd,
            itemPanel: ITEM_PANEL_VERIFICATION,
            lastActionKey: null,
            assetId: null,
            serialNumber: '',
            product2Id: null,
            model: '',
            productLine: '',
            disinfected: null,
            customerCareReasonCodes: [REASON_CODE_QUANTITY_MISMATCH],
            customerCareNotes: '',
            isVerificationComplete: false
        });
    }

    handleRemoveAdHocItem(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey || !this.shellContext) {
            return;
        }
        const remaining = (this.shellContext.items || []).filter(
            (item) => item.itemKey !== itemKey
        );
        const renumbered = remaining.map((item, index) => {
            const itemNumber = index + 1;
            const displayTitle = item.displayTitle || '';
            return {
                ...item,
                itemNumber,
                headerTitle: displayTitle
                    ? `Item ${itemNumber}: ${displayTitle}`
                    : `Item ${itemNumber}:`
            };
        });
        this.shellContext = { ...this.shellContext, items: renumbered };
        const nextState = { ...this.itemUiState };
        delete nextState[itemKey];
        this.itemUiState = nextState;
    }

    handleAdHocFieldChange(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        const field = event.currentTarget.dataset.field;
        if (!itemKey || !field) {
            return;
        }
        let value = event.detail?.value;
        if (value === undefined) {
            value = event.target.value;
        }
        this.updateItemState(itemKey, { [field]: value });
        this.refreshAdHocHeaderTitle(itemKey);
    }

    handleAdHocRecordChange(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        const field = event.currentTarget.dataset.field;
        if (!itemKey || !field) {
            return;
        }
        const recordId = event.detail?.recordId || null;
        this.updateItemState(itemKey, { [field]: recordId });
        if (field === 'assetId') {
            this.applyAdHocAssetDefaults(itemKey, recordId);
            return;
        }
        if (field === 'product2Id') {
            this.applyAdHocProductDefaults(itemKey, recordId);
        }
    }

    async applyAdHocAssetDefaults(itemKey, assetId) {
        if (!assetId) {
            // Keep Product / Model / Product Line — only Asset + Serial are asset-owned.
            this.updateItemState(itemKey, {
                assetId: null,
                serialNumber: ''
            });
            this.refreshAdHocHeaderTitle(itemKey);
            return;
        }
        try {
            const assets = (await getAssetsByIds({ assetIds: [assetId] })) || [];
            const asset = assets[0];
            if (!asset) {
                return;
            }
            this.updateItemState(itemKey, {
                assetId: asset.id || assetId,
                serialNumber: asset.serialNumber || '',
                product2Id: asset.product2Id || null,
                model: asset.model || '',
                productLine: asset.productLine || ''
            });
            this.refreshAdHocHeaderTitle(itemKey);
            this.clearAdHocInputValidity(itemKey, 'serialNumber', asset.serialNumber || '');
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to load asset',
                    message: this.normalizeError(error),
                    variant: 'error'
                })
            );
        }
    }

    async applyAdHocProductDefaults(itemKey, productId) {
        if (!productId) {
            this.updateItemState(itemKey, {
                product2Id: null,
                model: '',
                productLine: ''
            });
            this.refreshAdHocHeaderTitle(itemKey);
            return;
        }
        try {
            const product = await getProductDetails({
                productId,
                requireServiceAssetType: false
            });
            if (!product) {
                return;
            }
            this.updateItemState(itemKey, {
                product2Id: product.Id || productId,
                model: product.Model__c || '',
                productLine: product.ProductLine__c || ''
            });
            this.refreshAdHocHeaderTitle(itemKey);
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to load product',
                    message: this.normalizeError(error),
                    variant: 'error'
                })
            );
        }
    }

    /**
     * lightning-input keeps a stale required error after programmatic value updates.
     */
    clearAdHocInputValidity(itemKey, field, value) {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            const input = this.template.querySelector(
                `lightning-input[data-item-key="${itemKey}"][data-field="${field}"]`
            );
            if (!input) {
                return;
            }
            input.value = value == null ? '' : value;
            input.setCustomValidity('');
            input.reportValidity();
        }, 0);
    }

    refreshAdHocHeaderTitle(itemKey) {
        const items = this.shellContext?.items || [];
        const index = items.findIndex((item) => item.itemKey === itemKey);
        if (index < 0) {
            return;
        }
        const state = this.getItemState(itemKey);
        const parts = [];
        if (state.productLine) {
            parts.push(String(state.productLine).toUpperCase());
        }
        if (state.serialNumber) {
            parts.push(`Serial # ${state.serialNumber}`);
        }
        if (state.model) {
            parts.push(`Model # ${state.model}`);
        }
        const displayTitle = parts.join(' | ');
        const nextItems = [...items];
        nextItems[index] = {
            ...nextItems[index],
            displayTitle,
            headerTitle: displayTitle
                ? `Item ${nextItems[index].itemNumber}: ${displayTitle}`
                : `Item ${nextItems[index].itemNumber}:`
        };
        this.shellContext = { ...this.shellContext, items: nextItems };
    }

    handleToggleItem(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        const state = this.getItemState(itemKey);
        this.updateItemState(itemKey, { isExpanded: !state.isExpanded });
    }

    handleDecisionClick(event) {
        const { itemKey, field, value } = event.currentTarget.dataset;
        if (!itemKey || !field) {
            return;
        }
        const state = this.getItemState(itemKey);
        const patch = { [field]: value };
        if (field === 'disinfected' && value !== 'Contaminated') {
            patch.resiTestFailed = false;
            patch.visualInspection = false;
            patch.bioBag = false;
        }
        if (field === 'serialMatch' || field === 'modelMatch') {
            const item = (this.shellContext?.items || []).find((row) => row.itemKey === itemKey);
            patch.customerCareReasonCodes = this.reasonCodesForVerificationAnswer(
                state.customerCareReasonCodes,
                field,
                value,
                item
            );
            this.copyReasonsIntoOpenCustomerCareDraft(state, patch);
        }
        this.updateItemState(itemKey, patch);
    }

    handleResiTestChange(event) {
        const itemKey = event.target.dataset.itemKey;
        this.updateItemState(itemKey, { resiTestPerformed: event.target.checked === true });
    }

    handleContaminationReasonChange(event) {
        const itemKey = event.target.dataset.itemKey;
        const reason = event.target.dataset.reason;
        if (!itemKey || !reason) {
            return;
        }
        this.updateItemState(itemKey, { [reason]: event.target.checked === true });
    }

    /**
     * GW-5492 - Reads the field on each keystroke. A number input's change
     * event waits until the user tabs or clicks away, which hid Next.
     * Instruments and Other (Non-Serialized) verify by quantity only and do
     * not flag Quantity Mismatch when the received quantity differs.
     * That reason is set when the user adds an item with Add Item to Receive.
     */
    handleQuantityReceivedChange(event) {
        const itemKey = event.target.dataset.itemKey;
        this.updateItemState(itemKey, { quantityReceived: event.target.value });
    }

    handleVendorChange(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey) {
            return;
        }
        this.updateItemState(itemKey, {
            vendorAccountId: event.detail?.value || null
        });
        this.propagateOutsideVendorDefaults(itemKey);
    }

    handleVendorInstructionsChange(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey) {
            return;
        }
        this.updateItemState(itemKey, {
            instructionsToVendor: event.detail?.value || event.target.value || ''
        });
        this.propagateOutsideVendorDefaults(itemKey);
    }

    /**
     * GW-5492 - Next opens the Actions menu in place of Verification (same item card).
     */
    handleItemNext(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey || this.isReceivingClosed(itemKey)) {
            return;
        }
        this.updateItemState(itemKey, {
            isExpanded: true,
            isVerificationComplete: true,
            itemPanel: ITEM_PANEL_ACTIONS
        });
    }

    /**
     * GW-5492 - Actions Back / Verification breadcrumb returns to the verification form.
     */
    handleActionsBack(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        this.navigateItemPanel(itemKey, ITEM_PANEL_VERIFICATION, {
            isVerificationComplete: false,
            customerCareDraftReasonCodes: [],
            customerCareDraftNotes: '',
            overrideDraftSerial: '',
            overrideDraftModel: '',
            overrideDraftReasonCodes: [],
            overrideDraftNotes: '',
            redirectDraftLocationId: null,
            redirectDraftNotes: '',
            accessoriesDraft: null,
            outsideVendorDraftAccountId: null,
            outsideVendorDraftInstructions: '',
            internalRepairDraftAccountId: null,
            internalRepairDraftNotes: ''
        });
    }

    /**
     * GW-5492 - Navigate to Actions (breadcrumb). Discards unsaved Customer Care draft.
     */
    handleNavigateToActions(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey || this.isReceivingClosed(itemKey)) {
            return;
        }
        this.navigateItemPanel(itemKey, this.workOrderHomePanel(), {
            customerCareDraftReasonCodes: [],
            customerCareDraftNotes: '',
            overrideDraftSerial: '',
            overrideDraftModel: '',
            overrideDraftReasonCodes: [],
            overrideDraftNotes: '',
            redirectDraftLocationId: null,
            redirectDraftNotes: '',
            accessoriesDraft: null,
            outsideVendorDraftAccountId: null,
            outsideVendorDraftInstructions: '',
            internalRepairDraftAccountId: null,
            internalRepairDraftNotes: ''
        });
    }

    /**
     * GW-5492 - Action tile selected.
     */
    handleActionSelect(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        const actionKey = event.currentTarget.dataset.actionKey;
        if (!itemKey || !actionKey) {
            return;
        }
        if (actionKey === ACTION_KEY_CUSTOMER_CARE) {
            this.openContactCustomerCare(itemKey);
            return;
        }
        if (actionKey === ACTION_KEY_OVERRIDE) {
            this.openOverridePanel(itemKey);
            return;
        }
        if (actionKey === ACTION_KEY_REDIRECT) {
            this.openRedirectPanel(itemKey);
            return;
        }
        if (actionKey === ACTION_KEY_ACCESSORIES) {
            this.openAccessoriesPanel(itemKey);
            return;
        }
        if (actionKey === ACTION_KEY_OUTSIDE_VENDOR) {
            this.openOutsideVendorPanel(itemKey);
            return;
        }
        if (actionKey === ACTION_KEY_INTERNAL_REPAIR) {
            this.openInternalRepairPanel(itemKey);
            return;
        }
        if (actionKey === ACTION_KEY_TAKE_PIC) {
            this.openTakePic(itemKey);
            return;
        }
        if (actionKey === ACTION_KEY_RERUN_RESI) {
            this.openRerunResiPanel(itemKey);
            return;
        }
        if (actionKey === ACTION_KEY_TRAVEL_TAG) {
            this.handleTravelTagPrint(itemKey);
            return;
        }
        const action = [...RECEIVING_ACTION_OPTIONS, ...WORK_ORDER_ACTION_OPTIONS].find(
            (option) => option.key === actionKey
        );
        this.dispatchEvent(
            new ShowToastEvent({
                title: action?.label || 'Action',
                message: 'This action screen will be available in a later story.',
                variant: 'info'
            })
        );
        this.updateItemState(itemKey, { lastActionKey: actionKey });
    }

    /**
     * GW-5968 - Open Rerun Resi-Test. Defaults Resi-Test Performed to true.
     */
    openRerunResiPanel(itemKey) {
        const state = this.getItemState(itemKey);
        this.updateItemState(itemKey, {
            isExpanded: true,
            itemPanel: ITEM_PANEL_RERUN_RESI,
            lastActionKey: ACTION_KEY_RERUN_RESI,
            resiTestPerformed: true,
            disinfected: state.disinfected || 'Clean'
        });
    }

    handleRerunResiBack(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        this.navigateItemPanel(itemKey, this.workOrderHomePanel(), {});
    }

    async handleRerunResiSubmit(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey || this.isRerunResiSubmitting || !this.activeWorkOrderId) {
            return;
        }
        const item = (this.shellContext?.items || []).find((row) => row.itemKey === itemKey);
        const state = this.getItemState(itemKey);
        if (!state.disinfected) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Disinfected required',
                    message: 'Select Clean or Contaminated before submitting.',
                    variant: 'error'
                })
            );
            return;
        }
        this.isRerunResiSubmitting = true;
        try {
            await submitWorkOrderRerunResiTest({
                workOrderId: this.activeWorkOrderId,
                workOrderLineItemId: item?.lineItemId || null,
                resiTestPerformed: state.resiTestPerformed === true,
                disinfectedUiValue: state.disinfected,
                customerCareReasonCodes: state.customerCareReasonCodes || [],
                quantityReceived:
                    state.quantityReceived != null && state.quantityReceived !== ''
                        ? Number(state.quantityReceived)
                        : item?.quantityReturned != null
                          ? Number(item.quantityReturned)
                          : 1
            });
            this.navigateItemPanel(itemKey, this.workOrderHomePanel(), {
                lastActionKey: ACTION_KEY_RERUN_RESI
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Rerun Resi-Test',
                    message: 'Resi-Test updates saved.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to save Resi-Test',
                    message: this.normalizeError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isRerunResiSubmitting = false;
        }
    }

    /**
     * GW-5968 - Re-print Travel Tag (Bin Tag) for the scanned Work Order.
     * Stays on Actions; brief selected highlight then success toast.
     */
    async handleTravelTagPrint(itemKey) {
        if (!this.activeWorkOrderId || this.isTravelTagPrinting) {
            return;
        }
        this.isTravelTagPrinting = true;
        this.updateItemState(itemKey, {
            travelTagSelected: true,
            lastActionKey: ACTION_KEY_TRAVEL_TAG
        });
        try {
            const message = await reprintWorkOrderTravelTag({
                workOrderId: this.activeWorkOrderId
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Travel Tag',
                    message: message || 'Bin tag sent to printer.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to print Travel Tag',
                    message: this.normalizeError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isTravelTagPrinting = false;
            this.updateItemState(itemKey, { travelTagSelected: false });
        }
    }

    /**
     * GW-5492 - Open Contact Customer Care; draft is discarded on Back.
     */
    openContactCustomerCare(itemKey) {
        const state = this.getItemState(itemKey);
        this.updateItemState(itemKey, {
            isExpanded: true,
            itemPanel: ITEM_PANEL_CUSTOMER_CARE,
            lastActionKey: ACTION_KEY_CUSTOMER_CARE,
            customerCareDraftReasonCodes: [...(state.customerCareReasonCodes || [])],
            customerCareDraftNotes: state.customerCareNotes || ''
        });
    }

    handleCustomerCareFieldChange(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        const field = event.currentTarget.dataset.field;
        if (!itemKey || !field) {
            return;
        }
        let value = event.detail?.value;
        if (value === undefined) {
            value = event.target.value;
        }
        this.updateItemState(itemKey, { [field]: value });
    }

    /**
     * GW-5492 - Contact Customer Care Back: return to Actions without saving.
     */
    handleCustomerCareBack(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        this.navigateItemPanel(itemKey, ITEM_PANEL_ACTIONS, {
            customerCareDraftReasonCodes: [],
            customerCareDraftNotes: ''
        });
    }

    /**
     * GW-5492 - Contact Customer Care Submit replaces the shared reason list and notes.
     */
    handleCustomerCareSubmit(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey) {
            return;
        }
        const state = this.getItemState(itemKey);
        const reasonCodes = [...(state.customerCareDraftReasonCodes || [])].filter(
            (reasonCode) => !!reasonCode
        );
        if (reasonCodes.length === 0) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Reason Code required',
                    message: 'Select at least one Reason Code before submitting.',
                    variant: 'error'
                })
            );
            return;
        }
        this.updateItemState(itemKey, {
            customerCareReasonCodes: reasonCodes,
            customerCareNotes: state.customerCareDraftNotes || '',
            customerCareDraftReasonCodes: [],
            customerCareDraftNotes: '',
            itemPanel: ITEM_PANEL_ACTIONS,
            lastActionKey: ACTION_KEY_CUSTOMER_CARE
        });
        const message =
            reasonCodes.length === 1
                ? `${reasonCodes[0]} saved for this item.`
                : `${reasonCodes.join(', ')} saved for this item.`;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Contact Customer Care',
                message,
                variant: 'success'
            })
        );
    }

    /**
     * GW-5492 - Open Override. Back discards unsaved corrections and Customer Care edits.
     */
    openOverridePanel(itemKey) {
        const state = this.getItemState(itemKey);
        const item = (this.shellContext?.items || []).find((row) => row.itemKey === itemKey);
        const draftState = {
            ...state,
            overrideDraftSerial: state.overrideCorrectedSerial || '',
            overrideDraftModel: state.overrideCorrectedModel || '',
            overrideDraftReasonCodes: [...(state.customerCareReasonCodes || [])],
            overrideDraftNotes: state.customerCareNotes || '',
            overrideAddedSerialReason: false,
            overrideAddedModelReason: false
        };
        this.updateItemState(itemKey, {
            isExpanded: true,
            itemPanel: ITEM_PANEL_OVERRIDE,
            lastActionKey: ACTION_KEY_OVERRIDE,
            ...this.buildOverrideCarePatch(item, draftState)
        });
    }

    handleOverrideFieldChange(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        const field = event.currentTarget.dataset.field;
        if (!itemKey || !field) {
            return;
        }
        let value = event.detail?.value;
        if (value === undefined) {
            value = event.target.value;
        }
        if (
            (field === 'overrideDraftSerial' || field === 'overrideDraftModel') &&
            typeof value === 'string'
        ) {
            value = value.toUpperCase();
        }
        const state = { ...this.getItemState(itemKey), [field]: value };
        const item = (this.shellContext?.items || []).find((row) => row.itemKey === itemKey);
        this.updateItemState(itemKey, {
            [field]: value,
            ...this.buildOverrideCarePatch(item, state)
        });
    }

    handleOverrideBack(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        this.navigateItemPanel(itemKey, ITEM_PANEL_ACTIONS, {
            overrideDraftSerial: '',
            overrideDraftModel: '',
            overrideDraftReasonCodes: [],
            overrideDraftNotes: '',
            overrideAddedSerialReason: false,
            overrideAddedModelReason: false
        });
    }

    async handleOverrideSubmit(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey || this.isOverrideSubmitting) {
            return;
        }
        const state = this.getItemState(itemKey);
        const item = (this.shellContext?.items || []).find((row) => row.itemKey === itemKey);
        const correctedSerial = (state.overrideDraftSerial || '').trim().toUpperCase();
        const correctedModel = (state.overrideDraftModel || '').trim().toUpperCase();
        const listedSerial = (item?.serialNumber || '').trim().toUpperCase();
        const serialTooLarge = this.isSerialOverrideTooLarge(listedSerial, correctedSerial);
        const showCustomerCare = serialTooLarge || !!correctedModel;
        const reasonCodes = [...(state.overrideDraftReasonCodes || [])].filter(
            (reasonCode) => !!reasonCode
        );
        if (showCustomerCare && reasonCodes.length === 0) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Reason Code required',
                    message: 'Select at least one Reason Code before submitting.',
                    variant: 'error'
                })
            );
            return;
        }

        this.isOverrideSubmitting = true;
        let savedSerial = item?.serialNumber || '';
        let assetUpdated = false;
        let lineUpdated = false;
        let modelUpdated = false;
        const serialChanged =
            !!correctedSerial && correctedSerial !== listedSerial && !serialTooLarge;
        const listedModel = (item?.model || '').trim().toUpperCase();
        const modelChanged = !!correctedModel && correctedModel !== listedModel;
        try {
            if (
                this.isWorkOrderPath &&
                item?.lineItemId &&
                (serialChanged || modelChanged || showCustomerCare)
            ) {
                const result = await applyWorkOrderSerialOverride({
                    workOrderLineItemId: item.lineItemId,
                    correctedSerial: serialChanged ? correctedSerial : '',
                    correctedModel: modelChanged ? correctedModel : '',
                    customerCareReasonCodes: showCustomerCare ? reasonCodes : [],
                    customerCareNotes: showCustomerCare ? state.overrideDraftNotes || '' : ''
                });
                assetUpdated = result?.assetUpdated === true;
                lineUpdated = result?.lineUpdated === true;
                savedSerial = result?.serialNumber || correctedSerial;
                modelUpdated = modelChanged && lineUpdated;
                if (serialChanged && lineUpdated) {
                    this.refreshItemCorrection(itemKey, savedSerial, null);
                }
                if (modelUpdated) {
                    this.refreshItemCorrection(itemKey, null, correctedModel);
                }
            } else if (serialChanged && item?.lineItemId) {
                const result = await applySerialOverride({
                    lineItemId: item.lineItemId,
                    correctedSerial
                });
                assetUpdated = result?.assetUpdated === true;
                lineUpdated = result?.lineUpdated === true;
                savedSerial = result?.serialNumber || correctedSerial;
                if (lineUpdated) {
                    this.refreshItemCorrection(itemKey, savedSerial, null);
                }
            }
        } catch (error) {
            this.isOverrideSubmitting = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to save override',
                    message: this.normalizeError(error),
                    variant: 'error'
                })
            );
            return;
        }

        this.isOverrideSubmitting = false;
        this.updateItemState(itemKey, {
            overrideCorrectedSerial: serialChanged && lineUpdated ? '' : correctedSerial,
            overrideCorrectedModel: modelUpdated ? '' : correctedModel,
            overrideDraftSerial: '',
            overrideDraftModel: '',
            overrideDraftReasonCodes: [],
            overrideDraftNotes: '',
            overrideAddedSerialReason: false,
            overrideAddedModelReason: false,
            customerCareReasonCodes: showCustomerCare
                ? reasonCodes
                : state.customerCareReasonCodes || [],
            customerCareNotes: showCustomerCare
                ? state.overrideDraftNotes || ''
                : state.customerCareNotes || '',
            itemPanel: this.workOrderHomePanel(),
            lastActionKey: ACTION_KEY_OVERRIDE
        });
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Override',
                message: this.overrideSubmitMessage(
                    assetUpdated,
                    lineUpdated,
                    serialTooLarge,
                    modelUpdated,
                    serialChanged && lineUpdated,
                    this.isWorkOrderPath && showCustomerCare
                ),
                variant: 'success'
            })
        );
    }

    overrideSubmitMessage(
        assetUpdated,
        lineUpdated,
        serialTooLarge,
        modelUpdated,
        serialSaved,
        customerCareSaved
    ) {
        if (customerCareSaved === true && serialTooLarge) {
            return (
                'Customer Care was saved on the Work Order. ' +
                'The serial number was not changed because more than 2 characters differ.'
            );
        }
        if (customerCareSaved === true) {
            return 'Customer Care was saved on the Work Order.';
        }
        if (serialTooLarge && modelUpdated !== true) {
            return 'Customer Care saved. The serial number was not changed because more than 2 characters differ.';
        }
        if (modelUpdated === true && serialSaved === true) {
            return 'Corrected serial and model were saved on the Work Order.';
        }
        if (modelUpdated === true) {
            return 'Corrected model was saved on the Work Order.';
        }
        if (assetUpdated) {
            return 'Serial number updated on the Asset.';
        }
        if (lineUpdated) {
            return 'Serial number saved for this item.';
        }
        return 'Override saved for Finish Receiving.';
    }

    /**
     * GW-5492 - Open Redirect Repair Center. Back discards unsaved edits.
     */
    openRedirectPanel(itemKey) {
        const state = this.getItemState(itemKey);
        this.updateItemState(itemKey, {
            isExpanded: true,
            itemPanel: ITEM_PANEL_REDIRECT,
            lastActionKey: ACTION_KEY_REDIRECT,
            redirectDraftLocationId:
                state.redirectLocationId || state.redirectDraftLocationId || null,
            redirectDraftNotes: state.redirectionNotes || state.redirectDraftNotes || ''
        });
    }

    handleRedirectFieldChange(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        const field = event.currentTarget.dataset.field;
        if (!itemKey || !field) {
            return;
        }
        let value = event.detail?.value;
        if (value === undefined) {
            value = event.target.value;
        }
        this.updateItemState(itemKey, { [field]: value });
    }

    handleRedirectBack(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        this.navigateItemPanel(itemKey, ITEM_PANEL_ACTIONS, {
            redirectDraftLocationId: null,
            redirectDraftNotes: ''
        });
    }

    handleRedirectSubmit(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey) {
            return;
        }
        const state = this.getItemState(itemKey);
        const redirectLocationId = state.redirectDraftLocationId || null;
        if (!redirectLocationId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Repair Center required',
                    message: 'Select a Redirect to Repair Center before submitting.',
                    variant: 'error'
                })
            );
            return;
        }
        const listedId = this.shellContext?.destinationLocationId || null;
        if (listedId && redirectLocationId === listedId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Different repair center required',
                    message: 'Select a repair center other than the listed repair center.',
                    variant: 'error'
                })
            );
            return;
        }
        const option = (this.repairCenterOptions || []).find(
            (row) => row.value === redirectLocationId
        );
        this.updateItemState(itemKey, {
            redirectLocationId,
            redirectLocationName: option?.label || '',
            redirectionNotes: state.redirectDraftNotes || '',
            redirectDraftLocationId: null,
            redirectDraftNotes: '',
            isRedirected: true,
            itemPanel: ITEM_PANEL_ACTIONS,
            lastActionKey: ACTION_KEY_REDIRECT
        });
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Redirect Repair Center',
                message: 'Redirect saved for Finish Receiving.',
                variant: 'success'
            })
        );
    }

    /**
     * GW-5492 - Open Outside Vendor. Prefill from Verification; Back discards the draft.
     * Vendor Work Order creation is GW-5264 and runs on Finish Receiving.
     */
    openOutsideVendorPanel(itemKey) {
        const state = this.getItemState(itemKey);
        this.updateItemState(itemKey, {
            isExpanded: true,
            itemPanel: ITEM_PANEL_OUTSIDE_VENDOR,
            lastActionKey: ACTION_KEY_OUTSIDE_VENDOR,
            outsideVendorDraftAccountId: state.vendorAccountId || null,
            outsideVendorDraftInstructions: state.instructionsToVendor || ''
        });
    }

    handleOutsideVendorChange(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey) {
            return;
        }
        this.updateItemState(itemKey, {
            outsideVendorDraftAccountId: event.detail?.value || null
        });
    }

    handleOutsideVendorInstructionsChange(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey) {
            return;
        }
        this.updateItemState(itemKey, {
            outsideVendorDraftInstructions: event.detail?.value || event.target.value || ''
        });
    }

    /**
     * GW-5492 - Outside Vendor Back: return to Actions without saving the draft.
     */
    handleOutsideVendorBack(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        this.navigateItemPanel(itemKey, ITEM_PANEL_ACTIONS, {
            outsideVendorDraftAccountId: null,
            outsideVendorDraftInstructions: ''
        });
    }

    /**
     * GW-5492 - Outside Vendor Submit: store vendor and instructions for Finish Receiving.
     */
    handleOutsideVendorSubmit(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey) {
            return;
        }
        const state = this.getItemState(itemKey);
        const vendorAccountId = state.outsideVendorDraftAccountId || null;
        const instructionsToVendor = (state.outsideVendorDraftInstructions || '').trim();
        if (!vendorAccountId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Vendor details required',
                    message: 'Select a Vendor before submitting.',
                    variant: 'error'
                })
            );
            return;
        }
        this.updateItemState(itemKey, {
            vendorAccountId,
            instructionsToVendor,
            outsideVendorDraftAccountId: null,
            outsideVendorDraftInstructions: '',
            itemPanel: ITEM_PANEL_ACTIONS,
            lastActionKey: ACTION_KEY_OUTSIDE_VENDOR
        });
        this.propagateOutsideVendorDefaults(itemKey);
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Outside Vendor',
                message: 'Vendor details saved for Finish Receiving.',
                variant: 'success'
            })
        );
    }

    /**
     * GW-5492 - Open Internal Repair. Prefill from session; Back discards the draft.
     */
    openInternalRepairPanel(itemKey) {
        const state = this.getItemState(itemKey);
        this.updateItemState(itemKey, {
            isExpanded: true,
            itemPanel: ITEM_PANEL_INTERNAL_REPAIR,
            lastActionKey: ACTION_KEY_INTERNAL_REPAIR,
            internalRepairDraftAccountId: state.internalAccountId || null,
            internalRepairDraftNotes: state.internalRepairNotes || ''
        });
    }

    handleInternalRepairFieldChange(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        const field = event.currentTarget.dataset.field;
        if (!itemKey || !field) {
            return;
        }
        let value = event.detail?.value;
        if (value === undefined) {
            value = event.target.value;
        }
        this.updateItemState(itemKey, { [field]: value });
    }

    /**
     * GW-5492 - Internal Repair Back: return to Actions without saving the draft.
     */
    handleInternalRepairBack(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        this.navigateItemPanel(itemKey, ITEM_PANEL_ACTIONS, {
            internalRepairDraftAccountId: null,
            internalRepairDraftNotes: ''
        });
    }

    /**
     * GW-5492 - Internal Repair Submit: store account and notes for Finish Receiving / WO.
     */
    handleInternalRepairSubmit(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey) {
            return;
        }
        const state = this.getItemState(itemKey);
        const internalAccountId = state.internalRepairDraftAccountId || null;
        if (!internalAccountId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Internal Account required',
                    message: 'Select an Internal Account before submitting.',
                    variant: 'error'
                })
            );
            return;
        }
        const option = (this.internalAccountOptions || []).find(
            (row) => row.value === internalAccountId
        );
        this.updateItemState(itemKey, {
            internalAccountId,
            internalAccountName: option?.label || '',
            internalRepairNotes: state.internalRepairDraftNotes || '',
            internalRepairDraftAccountId: null,
            internalRepairDraftNotes: '',
            itemPanel: ITEM_PANEL_ACTIONS,
            lastActionKey: ACTION_KEY_INTERNAL_REPAIR
        });
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Internal Repair',
                message: 'Internal Repair saved for Finish Receiving.',
                variant: 'success'
            })
        );
    }

    /**
     * GW-5968 - Scan Work Order keeps verification and actions on one screen.
     * Scan Return Order still uses a separate Actions step.
     * @return {string} Panel to show after leaving a Work Order action
     */
    workOrderHomePanel() {
        return this.isWorkOrderPath ? ITEM_PANEL_VERIFICATION : ITEM_PANEL_ACTIONS;
    }

    navigateItemPanel(itemKey, itemPanel, patch = {}) {
        if (!itemKey || !itemPanel) {
            return;
        }
        this.updateItemState(itemKey, {
            isExpanded: true,
            itemPanel,
            ...patch
        });
    }

    /**
     * GW-5492 - Open Add Case or Accessories; draft discarded on Back.
     * Existing accessories open expanded.
     */
    openAccessoriesPanel(itemKey) {
        const state = this.getItemState(itemKey);
        const saved = this.cloneAccessories(state.accessories || []).map((row) => ({
            ...row,
            isExpanded: true
        }));
        this.updateItemState(itemKey, {
            isExpanded: true,
            itemPanel: ITEM_PANEL_ACCESSORIES,
            lastActionKey: ACTION_KEY_ACCESSORIES,
            accessoriesDraft: saved
        });
    }

    handleAccessoriesBack(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        this.navigateItemPanel(itemKey, ITEM_PANEL_ACTIONS, {
            accessoriesDraft: null
        });
    }

    handleAddAccessoryRow(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey) {
            return;
        }
        const state = this.getItemState(itemKey);
        const draft = this.cloneAccessories(state.accessoriesDraft || []);
        const next = [
            {
                key: `acc-${Date.now()}`,
                accessoryType: '',
                storageLocation: '',
                quantity: '1',
                isExpanded: true
            },
            ...draft
        ];
        this.updateItemState(itemKey, { accessoriesDraft: next });
    }

    handleToggleAccessoryRow(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        const accessoryKey = event.currentTarget.dataset.accessoryKey;
        if (!itemKey || !accessoryKey) {
            return;
        }
        const state = this.getItemState(itemKey);
        const draft = this.cloneAccessories(state.accessoriesDraft || []);
        this.updateItemState(itemKey, {
            accessoriesDraft: draft.map((row) =>
                row.key === accessoryKey ? { ...row, isExpanded: !row.isExpanded } : row
            )
        });
    }

    handleEditAccessoryRow(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        const accessoryKey = event.currentTarget.dataset.accessoryKey;
        if (!itemKey || !accessoryKey) {
            return;
        }
        const state = this.getItemState(itemKey);
        const draft = this.cloneAccessories(state.accessoriesDraft || []);
        this.updateItemState(itemKey, {
            accessoriesDraft: draft.map((row) => ({
                ...row,
                isExpanded: row.key === accessoryKey
            }))
        });
    }

    handleDeleteAccessoryRow(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        const accessoryKey = event.currentTarget.dataset.accessoryKey;
        if (!itemKey || !accessoryKey) {
            return;
        }
        const state = this.getItemState(itemKey);
        const draft = (state.accessoriesDraft || []).filter((row) => row.key !== accessoryKey);
        this.updateItemState(itemKey, { accessoriesDraft: draft });
    }

    handleAccessoryFieldChange(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        const accessoryKey = event.currentTarget.dataset.accessoryKey;
        const field = event.currentTarget.dataset.field;
        if (!itemKey || !accessoryKey || !field) {
            return;
        }
        let value = event.detail?.value;
        if (value === undefined) {
            value = event.target.value;
        }
        const state = this.getItemState(itemKey);
        const draft = this.cloneAccessories(state.accessoriesDraft || []);
        this.updateItemState(itemKey, {
            accessoriesDraft: draft.map((row) =>
                row.key === accessoryKey ? { ...row, [field]: value } : row
            )
        });
    }

    /**
     * GW-5492 - Submit accessories for Finish Receiving; update Accessories(n) badge.
     */
    handleAccessoriesSubmit(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey) {
            return;
        }
        const state = this.getItemState(itemKey);
        const draft = this.cloneAccessories(state.accessoriesDraft || []);
        for (const row of draft) {
            if (!(row.accessoryType || '').trim()) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Accessory Type required',
                        message: 'Select an Accessory Type for every accessory before submitting.',
                        variant: 'error'
                    })
                );
                return;
            }
            const quantity = Number(row.quantity);
            if (!row.quantity || Number.isNaN(quantity) || quantity <= 0) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Quantity required',
                        message: 'Enter a Quantity greater than zero for every accessory.',
                        variant: 'error'
                    })
                );
                return;
            }
        }
        const accessoryQuantity = this.sumAccessoryQuantity(draft);
        this.updateItemState(itemKey, {
            accessories: draft.map((row) => ({ ...row, isExpanded: false })),
            accessoriesDraft: null,
            accessoryQuantity,
            itemPanel: ITEM_PANEL_ACTIONS,
            lastActionKey: ACTION_KEY_ACCESSORIES
        });
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Accessories saved',
                message:
                    draft.length === 0
                        ? 'Accessories cleared for this item.'
                        : `${draft.length} accessor${draft.length === 1 ? 'y' : 'ies'} saved for Finish Receiving.`,
                variant: 'success'
            })
        );
    }

    cloneAccessories(rows) {
        return (rows || []).map((row) => ({
            key: row.key,
            accessoryType: row.accessoryType || '',
            storageLocation: row.storageLocation || '',
            quantity: row.quantity == null ? '' : String(row.quantity),
            isExpanded: row.isExpanded === true
        }));
    }

    sumAccessoryQuantity(rows) {
        return (rows || []).reduce((total, row) => {
            const quantity = Number(row.quantity);
            if (Number.isNaN(quantity) || quantity <= 0) {
                return total;
            }
            return total + quantity;
        }, 0);
    }

    toDisplayAccessories(rows) {
        const list = rows || [];
        const count = list.length;
        return list.map((row, index) => {
            const typeLabel = ACCESSORY_TYPE_LABEL_BY_VALUE[row.accessoryType] || '';
            const displayNumber = count - index;
            return {
                ...row,
                displayNumber,
                headerLabel: typeLabel
                    ? `ACCESSORY ${displayNumber}: ${typeLabel}`
                    : `ACCESSORY ${displayNumber}`,
                chevronIcon: row.isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                quantityInputId: `acc-qty-${row.key}`
            };
        });
    }

    /**
     * GW-5492 - Finish Receiving from Actions: persist and create the Work Order.
     * Stay on verification until every item is received. Return Order entry
     * reloads the record only then. The Receiving tab returns to the scan page.
     */
    async handleFinishReceiving(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        if (!itemKey || this.isFinishReceivingBusy) {
            return;
        }
        const item = (this.shellContext?.items || []).find((row) => row.itemKey === itemKey);
        const state = this.getItemState(itemKey);
        if (!item && !state.isAdHoc) {
            return;
        }

        this.isFinishReceivingBusy = true;
        try {
            const accessories = (state.accessories || []).map((row) => ({
                accessoryType: row.accessoryType || '',
                condition: row.condition || '',
                storageLocation: row.storageLocation || '',
                quantity: row.quantity != null ? Number(row.quantity) : 1
            }));
            const contentDocumentIds = [];
            const seenDocumentIds = new Set();
            [...(state.takePicPhotos || []), ...(state.modFormPhotos || [])].forEach((photo) => {
                if (photo?.contentDocumentId && !seenDocumentIds.has(photo.contentDocumentId)) {
                    seenDocumentIds.add(photo.contentDocumentId);
                    contentDocumentIds.push(photo.contentDocumentId);
                }
            });

            // JSON string avoids Aura typed-DTO binding dropping Id fields (null returnOrderId).
            const result = await finishReceivingItem({
                requestJson: JSON.stringify({
                    returnOrderId: this.activeReturnOrderId,
                    lineItemId: item?.lineItemId || null,
                    receiverId: null,
                    receivedDateTime: new Date().toISOString(),
                    isAdHoc: state.isAdHoc === true,
                    assetId: state.assetId || null,
                    product2Id: state.product2Id || item?.product2Id || null,
                    serialNumber: state.serialNumber || '',
                    model: state.model || '',
                    quantityReceived:
                        state.quantityReceived != null
                            ? Number(state.quantityReceived)
                            : item?.quantityReturned != null
                              ? Number(item.quantityReturned)
                              : 1,
                    disinfected: state.disinfected || '',
                    resiTestPerformed: state.resiTestPerformed === true,
                    resiTestFailed: state.resiTestFailed === true,
                    visualInspection: state.visualInspection === true,
                    bioBag: state.bioBag === true,
                    customerCareReasonCodes: state.customerCareReasonCodes || [],
                    customerCareNotes: state.customerCareNotes || '',
                    overrideCorrectedSerial: state.overrideCorrectedSerial || '',
                    overrideCorrectedModel: state.overrideCorrectedModel || '',
                    isRedirected: state.isRedirected === true,
                    redirectLocationId: state.redirectLocationId || null,
                    redirectionNotes: state.redirectionNotes || '',
                    vendorAccountId: state.vendorAccountId || null,
                    instructionsToVendor: state.instructionsToVendor || '',
                    internalAccountId: state.internalAccountId || null,
                    internalRepairNotes: state.internalRepairNotes || '',
                    accessories,
                    contentDocumentIds
                })
            });

            this.updateItemState(itemKey, {
                hasWorkOrderCreated: result?.hasWorkOrderCreated === true,
                isRedirected: result?.isRedirected === true || state.isRedirected === true,
                isReceivingFinished: true,
                isExpanded: false,
                itemPanel: ITEM_PANEL_VERIFICATION,
                isVerificationComplete: false,
                lastActionKey: 'finishReceiving'
            });

            const openedFromReturnOrder = !!this.entryReturnOrderId;
            const allItemsFinished = (this.shellContext?.items || []).every((row) =>
                this.isItemFinishedReceiving(row)
            );
            const returnToReturnOrder =
                openedFromReturnOrder &&
                result?.returnOrderFullyReceived === true &&
                allItemsFinished;
            const workOrderCreated = result?.hasWorkOrderCreated === true || !!result?.workOrderId;
            let message = 'Item received successfully.';
            if (result?.isRedirected) {
                message = `Redirected to ${result.redirectReturnOrderNumber || 'new Return Order'}.`;
            } else if (returnToReturnOrder && workOrderCreated) {
                message = 'Work Order created.';
            }
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Finish Receiving',
                    message,
                    variant: 'success'
                })
            );
            const returnToScanPage = !openedFromReturnOrder && allItemsFinished;
            if (returnToReturnOrder) {
                // Let the success toast paint before the screen action closes and the record reloads.
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                window.setTimeout(() => {
                    this.returnToEntryReturnOrder(true);
                }, RETURN_TO_RECORD_DELAY_MS);
            } else if (returnToScanPage) {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                window.setTimeout(() => {
                    this.resetToScanPage();
                }, RETURN_TO_RECORD_DELAY_MS);
            } else {
                // Badges already come from the finish result. Reload in the background.
                this.refreshShellContext().catch(() => undefined);
            }
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Finish Receiving',
                    message: this.normalizeError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isFinishReceivingBusy = false;
        }
    }

    async refreshShellContext() {
        if (!this.activeReturnOrderId) {
            return;
        }
        const context = await getReceivingShellContext({
            returnOrderId: this.activeReturnOrderId
        });
        this.shellContext = context;
    }

    async initializeFromRecordId() {
        if (!this._recordId || this._initializedFromRecord) {
            return;
        }
        this._initializedFromRecord = true;
        this.isLoading = true;
        try {
            await this.openReturnOrder(this._recordId);
        } catch (error) {
            this.currentPage = PAGE_SCAN;
            this.scanErrorMessage = this.normalizeError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async openReturnOrder(returnOrderId) {
        const context = await getReceivingShellContext({ returnOrderId });
        this.shellContext = context;
        this.activeReturnOrderId = context.returnOrderId;
        this.activeWorkOrderId = undefined;
        this.itemUiState = this.buildInitialItemUiState(context.items || []);
        this.currentPage = PAGE_RECEIVE;
    }

    /**
     * GW-5968 - Open Work Order receiving shell.
     * @param {string} workOrderId Work Order Id
     */
    async openWorkOrder(workOrderId) {
        const context = await getWorkOrderReceivingShellContext({ workOrderId });
        this.shellContext = context;
        this.activeWorkOrderId = context.workOrderId;
        this.activeReturnOrderId = undefined;
        this.itemUiState = this.buildInitialItemUiState(context.items || []);
        this.currentPage = PAGE_RECEIVE;
    }

    buildInitialItemUiState(items) {
        const isWorkOrderPath = this.shellContext?.pathType === PATH_WORK_ORDER;
        const stateByKey = {};
        items.forEach((item) => {
            const defaultYes = isWorkOrderPath ? 'Yes' : null;
            stateByKey[item.itemKey] = {
                isExpanded: !this.itemAlreadyFinished(item),
                isAdHoc: item.isAdHoc === true,
                isSerializedAddItem: false,
                itemPanel: ITEM_PANEL_VERIFICATION,
                lastActionKey: null,
                serialMatch: item.showSerialVerify === true ? defaultYes : null,
                modelMatch: item.showModelVerify === true ? defaultYes : null,
                vendorVerified: item.vendorVerifiedDefault !== false,
                disinfected: item.disinfectedUiValue || null,
                resiTestPerformed: false,
                resiTestFailed: false,
                visualInspection: false,
                bioBag: false,
                vendorAccountId: null,
                instructionsToVendor: '',
                outsideVendorDraftAccountId: null,
                outsideVendorDraftInstructions: '',
                internalAccountId: null,
                internalAccountName: '',
                internalRepairNotes: '',
                internalRepairDraftAccountId: null,
                internalRepairDraftNotes: '',
                quantityReceived:
                    isWorkOrderPath &&
                    item.showQuantityVerify === true &&
                    item.quantityReturned != null
                        ? item.quantityReturned
                        : null,
                accessoryQuantity: null,
                customerCareReasonCodes: this.reasonCodesFromBadges(item.badges),
                customerCareNotes: '',
                customerCareDraftReasonCodes: [],
                customerCareDraftNotes: '',
                overrideCorrectedSerial: '',
                overrideCorrectedModel: '',
                overrideDraftSerial: '',
                overrideDraftModel: '',
                overrideDraftReasonCodes: [],
                overrideDraftNotes: '',
                overrideAddedSerialReason: false,
                overrideAddedModelReason: false,
                redirectLocationId: null,
                redirectLocationName: '',
                redirectionNotes: '',
                redirectDraftLocationId: null,
                redirectDraftNotes: '',
                accessories: [],
                accessoriesDraft: null,
                accessoryQuantity: 0,
                isRedirected: false,
                hasWorkOrderCreated: false,
                isReceivingFinished: false,
                assetId: null,
                serialNumber: '',
                product2Id: null,
                model: '',
                productLine: '',
                modFormPhotos: [],
                takePicPhotos: [],
                travelTagSelected: false,
                isVerificationComplete: false
            };
        });
        return stateByKey;
    }

    getItemState(itemKey) {
        return (
            this.itemUiState[itemKey] || {
                isExpanded: false,
                isAdHoc: false,
                isSerializedAddItem: false,
                itemPanel: ITEM_PANEL_VERIFICATION,
                lastActionKey: null,
                serialMatch: null,
                modelMatch: null,
                vendorVerified: true,
                disinfected: null,
                resiTestPerformed: false,
                resiTestFailed: false,
                visualInspection: false,
                bioBag: false,
                vendorAccountId: null,
                instructionsToVendor: '',
                outsideVendorDraftAccountId: null,
                outsideVendorDraftInstructions: '',
                internalAccountId: null,
                internalAccountName: '',
                internalRepairNotes: '',
                internalRepairDraftAccountId: null,
                internalRepairDraftNotes: '',
                quantityReceived: null,
                accessoryQuantity: null,
                customerCareReasonCodes: [],
                customerCareNotes: '',
                customerCareDraftReasonCodes: [],
                customerCareDraftNotes: '',
                overrideCorrectedSerial: '',
                overrideCorrectedModel: '',
                overrideDraftSerial: '',
                overrideDraftModel: '',
                overrideDraftReasonCodes: [],
                overrideDraftNotes: '',
                overrideAddedSerialReason: false,
                overrideAddedModelReason: false,
                redirectLocationId: null,
                redirectLocationName: '',
                redirectionNotes: '',
                redirectDraftLocationId: null,
                redirectDraftNotes: '',
                accessories: [],
                accessoriesDraft: null,
                accessoryQuantity: 0,
                isRedirected: false,
                hasWorkOrderCreated: false,
                isReceivingFinished: false,
                assetId: null,
                serialNumber: '',
                product2Id: null,
                model: '',
                productLine: '',
                modFormPhotos: [],
                takePicPhotos: [],
                travelTagSelected: false,
                isVerificationComplete: false
            }
        );
    }

    updateItemState(itemKey, patch) {
        this.itemUiState = {
            ...this.itemUiState,
            [itemKey]: {
                ...this.getItemState(itemKey),
                ...patch
            }
        };
    }

    /**
     * Reason codes already stored on the Work Order, shown as warning badges.
     */
    reasonCodesFromBadges(badges) {
        const codes = [];
        (badges || []).forEach((badge) => {
            if (
                badge?.label &&
                CUSTOMER_CARE_REASON_LABELS.has(badge.label) &&
                !codes.includes(badge.label)
            ) {
                codes.push(badge.label);
            }
        });
        return codes;
    }

    /**
     * Add or remove one reason from the shared Customer Care list.
     */
    withReasonCode(reasonCodes, reasonCode, include) {
        const next = (reasonCodes || []).filter((code) => code !== reasonCode);
        if (include && reasonCode) {
            next.push(reasonCode);
        }
        return next;
    }

    /**
     * Serial, model, and repair-exchange answers add or remove their reason.
     */
    reasonCodesForVerificationAnswer(reasonCodes, field, value, item) {
        if (field === 'serialMatch') {
            return this.withReasonCode(
                reasonCodes,
                REASON_CODE_SERIAL_MISMATCH,
                value === 'No'
            );
        }
        if (field === 'modelMatch') {
            const repairExchange = item?.isRepairExchange === true;
            const withoutModel = this.withReasonCode(
                reasonCodes,
                REASON_CODE_MODEL_MISMATCH,
                value === 'No' && !repairExchange
            );
            return this.withReasonCode(
                withoutModel,
                REASON_CODE_REPAIR_EXCHANGE_MODEL_MISMATCH,
                value === 'No' && repairExchange
            );
        }
        return [...(reasonCodes || [])];
    }

    /**
     * Keep the open Contact Customer Care draft aligned with a systematic change.
     */
    copyReasonsIntoOpenCustomerCareDraft(state, patch) {
        if (state.itemPanel === ITEM_PANEL_CUSTOMER_CARE && patch.customerCareReasonCodes) {
            patch.customerCareDraftReasonCodes = [...patch.customerCareReasonCodes];
        }
    }

    buildOverrideCarePatch(item, state) {
        const listedSerial = (item?.serialNumber || '').trim().toUpperCase();
        const correctedSerial = (state?.overrideDraftSerial || '').trim().toUpperCase();
        const correctedModel = (state?.overrideDraftModel || '').trim().toUpperCase();
        const serialTooLarge = this.isSerialOverrideTooLarge(listedSerial, correctedSerial);
        let reasonCodes = [...(state?.overrideDraftReasonCodes || [])];
        let addedSerial = state?.overrideAddedSerialReason === true;
        let addedModel = state?.overrideAddedModelReason === true;

        if (serialTooLarge && !reasonCodes.includes(REASON_CODE_SERIAL_MISMATCH)) {
            reasonCodes.push(REASON_CODE_SERIAL_MISMATCH);
            addedSerial = true;
        } else if (!serialTooLarge && addedSerial) {
            reasonCodes = reasonCodes.filter((code) => code !== REASON_CODE_SERIAL_MISMATCH);
            addedSerial = false;
        }

        const modelEntered = !!correctedModel;
        if (modelEntered && !reasonCodes.includes(REASON_CODE_MODEL_MISMATCH)) {
            reasonCodes.push(REASON_CODE_MODEL_MISMATCH);
            addedModel = true;
        } else if (!modelEntered && addedModel) {
            reasonCodes = reasonCodes.filter((code) => code !== REASON_CODE_MODEL_MISMATCH);
            addedModel = false;
        }

        const showOverrideCustomerCare = serialTooLarge || modelEntered;
        const serialChanged = !!correctedSerial && correctedSerial !== listedSerial;
        return {
            overrideDraftSerial: state?.overrideDraftSerial || '',
            overrideDraftModel: state?.overrideDraftModel || '',
            overrideDraftReasonCodes: reasonCodes,
            overrideDraftNotes: state?.overrideDraftNotes || '',
            overrideAddedSerialReason: addedSerial,
            overrideAddedModelReason: addedModel,
            showOverrideCustomerCare,
            overrideSerialError: serialTooLarge ? OVERRIDE_SERIAL_ERROR : '',
            isOverrideSubmitDisabled: showOverrideCustomerCare
                ? reasonCodes.length === 0
                : !serialChanged
        };
    }

    isSerialOverrideTooLarge(listedSerial, correctedSerial) {
        if (!correctedSerial) {
            return false;
        }
        return (
            this.serialCharacterDistance(listedSerial || '', correctedSerial) >
            OVERRIDE_SERIAL_CHARACTER_LIMIT
        );
    }

    serialCharacterDistance(leftValue, rightValue) {
        const leftText = leftValue || '';
        const rightText = rightValue || '';
        const previousRow = [];
        const currentRow = [];
        for (let column = 0; column <= rightText.length; column += 1) {
            previousRow[column] = column;
            currentRow[column] = 0;
        }
        for (let leftIndex = 1; leftIndex <= leftText.length; leftIndex += 1) {
            currentRow[0] = leftIndex;
            const leftCharacter = leftText.charAt(leftIndex - 1);
            for (let rightIndex = 1; rightIndex <= rightText.length; rightIndex += 1) {
                const substitutionCost = leftCharacter === rightText.charAt(rightIndex - 1) ? 0 : 1;
                currentRow[rightIndex] = Math.min(
                    previousRow[rightIndex] + 1,
                    currentRow[rightIndex - 1] + 1,
                    previousRow[rightIndex - 1] + substitutionCost
                );
            }
            for (let column = 0; column < currentRow.length; column += 1) {
                previousRow[column] = currentRow[column];
            }
        }
        return previousRow[rightText.length];
    }

    refreshItemCorrection(itemKey, correctedSerial, correctedModel) {
        const items = this.shellContext?.items || [];
        const index = items.findIndex((row) => row.itemKey === itemKey);
        if (index < 0) {
            return;
        }
        const item = items[index];
        const nextItem = { ...item };
        let displayTitle = item.displayTitle || '';
        let headerTitle = item.headerTitle || '';
        if (correctedSerial && item.serialNumber) {
            displayTitle = displayTitle.split(item.serialNumber).join(correctedSerial);
            headerTitle = headerTitle.split(item.serialNumber).join(correctedSerial);
            nextItem.serialNumber = correctedSerial;
        }
        if (correctedModel && item.model) {
            displayTitle = displayTitle.split(item.model).join(correctedModel);
            headerTitle = headerTitle.split(item.model).join(correctedModel);
            nextItem.model = correctedModel;
        }
        nextItem.displayTitle = displayTitle;
        nextItem.headerTitle = headerTitle;
        const nextItems = [...items];
        nextItems[index] = nextItem;
        this.shellContext = { ...this.shellContext, items: nextItems };
    }

    /**
     * Copies the selected vendor onto later items that do not have one yet.
     * Items that share that vendor show the instructions already entered for it.
     */
    propagateOutsideVendorDefaults(sourceItemKey) {
        const items = (this.shellContext?.items || []).filter(
            (item) => item.showOutsideVendor === true
        );
        if (items.length < 2) {
            return;
        }

        const sourceIndex = items.findIndex((item) => item.itemKey === sourceItemKey);
        if (sourceIndex < 0) {
            return;
        }
        const sourceState = this.getItemState(sourceItemKey);
        const sourceVendorId = sourceState.vendorAccountId || null;
        if (!sourceVendorId) {
            return;
        }

        const nextState = { ...this.itemUiState };
        let sharedInstructions = (sourceState.instructionsToVendor || '').trim();
        items.forEach((item) => {
            if (item.itemKey === sourceItemKey) {
                return;
            }
            const state = nextState[item.itemKey] || this.getItemState(item.itemKey);
            if (state.vendorAccountId !== sourceVendorId) {
                return;
            }
            sharedInstructions = this.mergeVendorInstructions(
                sharedInstructions,
                state.instructionsToVendor
            );
        });

        let changed = false;
        items.forEach((item, index) => {
            const state = nextState[item.itemKey] || this.getItemState(item.itemKey);
            const hasSameVendor = state.vendorAccountId === sourceVendorId;
            const copyVendorDown = index > sourceIndex && !state.vendorAccountId;
            if (!hasSameVendor && !copyVendorDown) {
                return;
            }
            const mergedInstructions = this.mergeVendorInstructions(
                hasSameVendor ? state.instructionsToVendor : '',
                sharedInstructions
            );
            const nextVendorId = copyVendorDown ? sourceVendorId : state.vendorAccountId;
            if (
                nextVendorId === state.vendorAccountId &&
                mergedInstructions === (state.instructionsToVendor || '')
            ) {
                return;
            }
            nextState[item.itemKey] = {
                ...state,
                vendorAccountId: nextVendorId,
                instructionsToVendor: mergedInstructions
            };
            changed = true;
        });

        if (sharedInstructions !== (sourceState.instructionsToVendor || '')) {
            nextState[sourceItemKey] = {
                ...sourceState,
                instructionsToVendor: sharedInstructions
            };
            changed = true;
        }
        if (changed) {
            this.itemUiState = nextState;
        }
    }

    /**
     * Appends vendor instructions. A longer version of the same text replaces the shorter one.
     * @param {string} existingText Instructions already on the item
     * @param {string} incomingText Instructions to add
     * @return {string} Combined instructions
     */
    mergeVendorInstructions(existingText, incomingText) {
        const existingValue = (existingText || '').trim();
        const incomingValue = (incomingText || '').trim();
        if (!incomingValue) {
            return existingText || '';
        }
        if (
            !existingValue ||
            existingValue === incomingValue ||
            incomingValue.includes(existingValue)
        ) {
            return incomingValue;
        }
        if (existingValue.includes(incomingValue)) {
            return existingValue;
        }
        return `${existingValue}\n${incomingValue}`;
    }

    toDisplayItem(item) {
        const state = this.getItemState(item.itemKey);
        const isAdHoc = item.isAdHoc === true || state.isAdHoc === true;
        const isSerializedAddItem = state.isSerializedAddItem === true;
        const isInstrumentItem = item.isInstrumentItem === true;
        const showSerialVerify = item.showSerialVerify === true;
        const showModelVerify = item.showModelVerify === true;
        const showQuantityVerify = item.showQuantityVerify === true;
        const showDisinfectedVerify = item.showDisinfectedVerify !== false && this.isReturnOrderPath;
        const showOutsideVendor =
            item.showOutsideVendor === true && this.isReturnOrderPath;
        const isVendorRequired = item.isVendorRequired === true;
        const badges = this.buildDisplayBadges(item, state);
        const vendorAccountId = state.vendorAccountId || null;
        const instructionsToVendor = state.instructionsToVendor || '';

        const showActionsPanel = state.itemPanel === ITEM_PANEL_ACTIONS;
        const showCustomerCarePanel = state.itemPanel === ITEM_PANEL_CUSTOMER_CARE;
        const showAccessoriesPanel = state.itemPanel === ITEM_PANEL_ACCESSORIES;
        const showOutsideVendorPanel = state.itemPanel === ITEM_PANEL_OUTSIDE_VENDOR;
        const showInternalRepairPanel = state.itemPanel === ITEM_PANEL_INTERNAL_REPAIR;
        const showOverridePanel = state.itemPanel === ITEM_PANEL_OVERRIDE;
        const showRedirectPanel = state.itemPanel === ITEM_PANEL_REDIRECT;
        const showRerunResiPanel = state.itemPanel === ITEM_PANEL_RERUN_RESI;
        const showVerificationPanel =
            !showActionsPanel &&
            !showCustomerCarePanel &&
            !showAccessoriesPanel &&
            !showOutsideVendorPanel &&
            !showInternalRepairPanel &&
            !showOverridePanel &&
            !showRedirectPanel &&
            !showRerunResiPanel &&
            (state.itemPanel === ITEM_PANEL_VERIFICATION || !state.itemPanel);
        const redirectDraftLocationId = state.redirectDraftLocationId || null;
        const redirectOptions = (this.repairCenterOptions || []).filter(
            (option) =>
                !this.shellContext?.destinationLocationId ||
                option.value !== this.shellContext.destinationLocationId
        );
        const overrideView = this.buildOverrideCarePatch(item, state);
        const outsideVendorDraftAccountId = state.outsideVendorDraftAccountId || null;
        const outsideVendorDraftInstructions = state.outsideVendorDraftInstructions || '';
        const internalRepairDraftAccountId = state.internalRepairDraftAccountId || null;
        const internalRepairDraftNotes = state.internalRepairDraftNotes || '';
        const leftActionOptions = [];
        const rightActionOptions = [];
        const actionCatalog = this.isWorkOrderPath
            ? WORK_ORDER_ACTION_OPTIONS
            : RECEIVING_ACTION_OPTIONS;
        actionCatalog.forEach((action, index) => {
            const column = index % 2 === 0 ? leftActionOptions : rightActionOptions;
            const isTravelSelected =
                action.key === ACTION_KEY_TRAVEL_TAG && state.travelTagSelected === true;
            column.push({
                ...action,
                cardClass: isTravelSelected ? 'action-card action-card_selected' : 'action-card'
            });
        });
        const accessoriesDraft = this.toDisplayAccessories(state.accessoriesDraft || []);
        const isRerunSubmitDisabled =
            this.isRerunResiSubmitting || !state.disinfected;

        return {
            ...item,
            isAdHoc,
            isSerializedAddItem,
            isExpanded: state.isExpanded === true,
            showActionsPanel,
            showCustomerCarePanel,
            showAccessoriesPanel,
            showOutsideVendorPanel,
            showInternalRepairPanel,
            showOverridePanel,
            showRedirectPanel,
            showRerunResiPanel,
            showVerificationPanel,
            isRerunSubmitDisabled,
            listedRepairCenterName: this.shellContext?.destinationLocationName || '',
            redirectDraftLocationId,
            redirectDraftNotes: state.redirectDraftNotes || '',
            redirectRepairCenterOptions: redirectOptions,
            isRedirectSubmitDisabled: !redirectDraftLocationId,
            listedSerialNumber: (item.serialNumber || '').toUpperCase(),
            listedModel: (item.model || '').toUpperCase(),
            overrideDraftSerial: state.overrideDraftSerial || '',
            overrideDraftModel: state.overrideDraftModel || '',
            overrideDraftReasonCodes: overrideView.overrideDraftReasonCodes || [],
            overrideDraftNotes: state.overrideDraftNotes || '',
            showOverrideCustomerCare: overrideView.showOverrideCustomerCare === true,
            overrideSerialError: overrideView.overrideSerialError || '',
            overrideSerialFieldClass: overrideView.overrideSerialError
                ? 'override-field override-field_error'
                : 'override-field',
            isOverrideSubmitDisabled:
                this.isOverrideSubmitting || overrideView.isOverrideSubmitDisabled === true,
            outsideVendorDraftAccountId,
            outsideVendorDraftInstructions,
            isOutsideVendorSubmitDisabled: !outsideVendorDraftAccountId,
            internalRepairDraftAccountId,
            internalRepairDraftNotes,
            internalAccountOptions: this.internalAccountOptions || [],
            isInternalRepairSubmitDisabled: !internalRepairDraftAccountId,
            leftActionOptions,
            rightActionOptions,
            customerCareReasonCodes: state.customerCareReasonCodes || [],
            customerCareNotes: state.customerCareNotes || '',
            customerCareDraftReasonCodes: state.customerCareDraftReasonCodes || [],
            customerCareDraftNotes: state.customerCareDraftNotes || '',
            isCustomerCareSubmitDisabled: (state.customerCareDraftReasonCodes || []).length === 0,
            accessoriesDraft,
            hasAccessoriesDraft: accessoriesDraft.length > 0,
            chevronIcon: state.isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
            isInstrumentItem,
            showSerialVerify,
            showModelVerify,
            showQuantityVerify,
            showDisinfectedVerify,
            showOutsideVendor,
            isVendorRequired,
            serialMatch: state.serialMatch,
            modelMatch: state.modelMatch,
            disinfected: isAdHoc ? state.disinfected || '' : state.disinfected,
            resiTestPerformed: state.resiTestPerformed === true,
            resiTestFailed: state.resiTestFailed === true,
            visualInspection: state.visualInspection === true,
            bioBag: state.bioBag === true,
            vendorAccountId,
            instructionsToVendor,
            quantityReceived: state.quantityReceived,
            qtyReceivedInputId: `qty-received-${item.itemKey}`,
            assetId: state.assetId || null,
            serialNumber: state.serialNumber || '',
            product2Id: state.product2Id || null,
            model: state.model || '',
            productLine: state.productLine || '',
            modFormPhotos: state.modFormPhotos || [],
            hasModFormPhotos: (state.modFormPhotos || []).length > 0,
            modFormPhotoCount: (state.modFormPhotos || []).length,
            modFormPhotoCountLabel: this.formatModFormPhotoCount(
                (state.modFormPhotos || []).length
            ),
            modFormDropzoneClass: this.isModFormDropActive
                ? 'mod-form__dropzone mod-form__dropzone_active'
                : 'mod-form__dropzone',
            badges,
            serialYesClass: this.pillClass(state.serialMatch, 'Yes', true),
            serialNoClass: this.pillClass(state.serialMatch, 'No', false),
            modelYesClass: this.pillClass(state.modelMatch, 'Yes', true),
            modelNoClass: this.pillClass(state.modelMatch, 'No', false),
            disinfectedCleanClass: this.pillClass(state.disinfected, 'Clean', true),
            disinfectedContaminatedClass: this.pillClass(state.disinfected, 'Contaminated', false),
            showContaminationReason: !isAdHoc && state.disinfected === 'Contaminated',
            showInlineActions:
                this.isWorkOrderPath && showVerificationPanel && isAdHoc !== true,
            showNextButton: this.isWorkOrderPath
                ? false
                : this.isItemReadyForNext(item, state),
            showRemoveItemButton: isAdHoc === true
        };
    }

    buildDisplayBadges(item, state) {
        const badges = [];
        const seenKeys = new Set();
        const pushBadge = (badge) => {
            if (!badge?.label || seenKeys.has(badge.key)) {
                return;
            }
            seenKeys.add(badge.key);
            const variant = badge.variant || 'info';
            // Informational badges: light blue pill + darker-blue circle with white mark.
            const useIconMark = variant === 'info';
            badges.push({
                ...badge,
                variant,
                iconName: badge.iconName || 'utility:info',
                useIconMark,
                iconMark: useIconMark ? 'i' : null,
                cssClass: `item-badge item-badge_${variant}`
            });
        };

        const sessionAccessoryQuantity = Number(state.accessoryQuantity || 0);

        (item.badges || []).forEach((badge) => {
            // Contaminated follows live Disinfected selection in the UI.
            if (badge.label === 'Contaminated') {
                return;
            }
            // Customer Care reasons come from the shared session list so adds and removals match every screen.
            if (CUSTOMER_CARE_REASON_LABELS.has(badge.label)) {
                return;
            }
            // Session accessories replace the server Accessories badge until Finish Receiving.
            if (
                sessionAccessoryQuantity > 0 &&
                badge.label?.startsWith('Accessories')
            ) {
                return;
            }
            pushBadge(badge);
        });

        if (state.disinfected === 'Contaminated') {
            pushBadge({
                key: `${item.itemKey}-Contaminated`,
                label: 'Contaminated',
                variant: 'alert',
                iconName: 'utility:warning'
            });
        }

        // Session overlays for Actions not yet persisted (accessories / customer care).
        if (sessionAccessoryQuantity > 0) {
            pushBadge({
                key: `${item.itemKey}-Accessories`,
                label: `Accessories (${sessionAccessoryQuantity})`,
                variant: 'info',
                iconName: 'utility:info'
            });
        }
        const takePicCount = (state.takePicPhotos || []).length;
        if (takePicCount > 0) {
            pushBadge({
                key: `${item.itemKey}-Photos`,
                label: `Photos (${takePicCount})`,
                variant: 'info',
                iconName: 'utility:photo'
            });
        }
        (state.customerCareReasonCodes || []).forEach((reasonCode) => {
            if (!reasonCode) {
                return;
            }
            pushBadge({
                key: `${item.itemKey}-Care-${reasonCode}`,
                label: reasonCode,
                variant: 'warning',
                iconName: 'utility:warning'
            });
        });
        if (state.isRedirected === true && !badges.some((b) => b.label === BADGE_LABEL_REDIRECT)) {
            pushBadge({
                key: `${item.itemKey}-Redirect`,
                label: BADGE_LABEL_REDIRECT,
                variant: 'redirect',
                iconName: 'utility:truck'
            });
        }
        if (
            state.hasWorkOrderCreated === true &&
            !badges.some((b) => b.label === BADGE_LABEL_WORK_ORDER_CREATED)
        ) {
            pushBadge({
                key: `${item.itemKey}-WorkOrderCreated`,
                label: BADGE_LABEL_WORK_ORDER_CREATED,
                variant: 'complete',
                iconName: 'utility:success'
            });
        }

        return this.sortDisplayBadges(badges);
    }

    /**
     * GW-5492 - Informational (blue), Customer Care (yellow), warning (red),
     * then Redirect (purple) and Work Order Created (green). Alphabetical within a color.
     * @param {object[]} badges Display badges
     * @return {object[]} Badges in color, then label, order
     */
    sortDisplayBadges(badges) {
        return (badges || []).slice().sort((left, right) => {
            const leftOrder = BADGE_COLOR_ORDER[left.variant] ?? 99;
            const rightOrder = BADGE_COLOR_ORDER[right.variant] ?? 99;
            if (leftOrder !== rightOrder) {
                return leftOrder - rightOrder;
            }
            return (left.label || '').localeCompare(right.label || '', undefined, {
                numeric: true,
                sensitivity: 'base'
            });
        });
    }

    /**
     * Finished Return Order items start collapsed on the verification screen.
     * @param {object} item Shell item
     * @return {boolean} True when the item already has a Work Order or Redirect badge
     */
    itemAlreadyFinished(item) {
        return (item?.badges || []).some(
            (badge) =>
                badge?.label === BADGE_LABEL_WORK_ORDER_CREATED ||
                badge?.label === BADGE_LABEL_REDIRECT
        );
    }

    /**
     * GW-5492 - Item finished when it has Work Order Created or Redirect badge.
     */
    isItemFinishedReceiving(item) {
        if (!item) {
            return false;
        }
        const state = this.getItemState(item.itemKey);
        const badges = this.buildDisplayBadges(item, state);
        return badges.some(
            (badge) =>
                badge.label === BADGE_LABEL_WORK_ORDER_CREATED ||
                badge.label === BADGE_LABEL_REDIRECT
        );
    }

    /**
     * GW-5968 - Next stays hidden after Finish Receiving (Work Order or redirect Return Order).
     */
    isReceivingClosed(itemKey) {
        const item = (this.shellContext?.items || []).find((row) => row.itemKey === itemKey);
        return this.isItemReceivingClosed(item, this.getItemState(itemKey));
    }

    isItemReceivingClosed(item, state) {
        if (state?.isReceivingFinished === true || state?.hasWorkOrderCreated === true) {
            return true;
        }
        return (item?.badges || []).some(
            (badge) =>
                badge.label === BADGE_LABEL_WORK_ORDER_CREATED ||
                badge.label === BADGE_LABEL_REDIRECT
        );
    }

    isItemReadyForNext(item, state) {
        if (this.isItemReceivingClosed(item, state) || state.isVerificationComplete) {
            return false;
        }
        if (item.isAdHoc === true || state.isAdHoc === true) {
            const productOk = !!state.product2Id;
            const disinfectedOk = !!state.disinfected;
            const reasonOk = (state.customerCareReasonCodes || []).length > 0;
            if (state.isSerializedAddItem === true) {
                const serialOk = !!(state.serialNumber || '').trim();
                return productOk && serialOk && disinfectedOk && reasonOk;
            }
            return productOk && disinfectedOk && reasonOk;
        }
        const quantityOk =
            item.showQuantityVerify !== true ||
            (state.quantityReceived !== null && state.quantityReceived !== '');
        const requiresDisinfected =
            item.showDisinfectedVerify !== false && this.isReturnOrderPath;
        if (item.isInstrumentItem === true) {
            return quantityOk && (!requiresDisinfected || state.disinfected != null);
        }
        const serialOk = item.showSerialVerify !== true || state.serialMatch != null;
        const modelOk = item.showModelVerify !== true || state.modelMatch != null;
        const disinfectedOk = !requiresDisinfected || state.disinfected != null;
        if (!(quantityOk && serialOk && modelOk && disinfectedOk)) {
            return false;
        }
        // GW-5492 - Vendor stays required. Instructions to Vendor are optional.
        if (
            item.showOutsideVendor === true &&
            this.isReturnOrderPath &&
            item.isVendorRequired === true &&
            !state.vendorAccountId
        ) {
            return false;
        }
        return true;
    }

    pillClass(currentValue, optionValue, isPositive) {
        const classes = ['decision-pill'];
        if (currentValue === optionValue) {
            classes.push(isPositive ? 'decision-pill_yes' : 'decision-pill_no');
        }
        return classes.join(' ');
    }

    handleModFormChooseFiles(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        const input = this.template.querySelector(
            `input[data-id="mod-form-file-input"][data-item-key="${itemKey}"]`
        );
        if (input) {
            input.click();
        }
    }

    handleModFormDragOver(event) {
        event.preventDefault();
        this.isModFormDropActive = true;
    }

    handleModFormDragLeave() {
        this.isModFormDropActive = false;
    }

    async handleModFormDrop(event) {
        event.preventDefault();
        this.isModFormDropActive = false;
        const itemKey = event.currentTarget.dataset.itemKey;
        const files = Array.from(event.dataTransfer?.files || []);
        await this.uploadModFormFiles(itemKey, files);
    }

    async handleModFormFileSelected(event) {
        const itemKey = event.target.dataset.itemKey;
        const files = Array.from(event.target.files || []);
        event.target.value = '';
        await this.uploadModFormFiles(itemKey, files);
    }

    async uploadModFormFiles(itemKey, files) {
        if (!itemKey || !files.length || !this.activeReturnOrderId || this.isModFormBusy) {
            return;
        }
        this.isModFormBusy = true;
        this.modFormError = undefined;
        this.cameraError = undefined;
        try {
            let uploaded = 0;
            for (const file of files) {
                const base64Data = await this.readFileAsDataUrl(file);
                const photo = await stageModFormPhoto({
                    returnOrderId: this.activeReturnOrderId,
                    base64Data,
                    fileName: file.name
                });
                this.addModFormPhoto(itemKey, photo);
                uploaded += 1;
            }
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Mod Form uploaded',
                    message:
                        uploaded === 1
                            ? '1 file attached to the Return Order.'
                            : `${uploaded} files attached to the Return Order.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            const message = this.normalizeError(error);
            this.modFormError = message;
            if (this.isModFormCameraOpen) {
                this.cameraError = message;
            }
        } finally {
            this.isModFormBusy = false;
        }
    }

    async uploadTakePicFiles(itemKey, files) {
        if (!itemKey || !files.length || this.isModFormBusy) {
            return;
        }
        this.isModFormBusy = true;
        this.modFormError = undefined;
        this.cameraError = undefined;
        try {
            let uploaded = 0;
            for (const file of files) {
                const base64Data = await this.readFileAsDataUrl(file);
                const photo = await stageReceivingPhoto({
                    base64Data,
                    fileName: file.name
                });
                this.addItemPhoto(itemKey, photo, 'takePicPhotos');
                uploaded += 1;
            }
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Photos staged',
                    message:
                        uploaded === 1
                            ? '1 photo staged for Finish Receiving.'
                            : `${uploaded} photos staged for Finish Receiving.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            const message = this.normalizeError(error);
            this.modFormError = message;
            if (this.isModFormCameraOpen) {
                this.cameraError = message;
            }
        } finally {
            this.isModFormBusy = false;
        }
    }

    addModFormPhoto(itemKey, photo) {
        this.addItemPhoto(itemKey, photo, 'modFormPhotos');
    }

    addItemPhoto(itemKey, photo, fieldName) {
        if (!photo?.contentDocumentId || !fieldName) {
            return;
        }
        const normalized = {
            ...photo,
            editTitle: photo.title || ''
        };
        const current = this.getItemState(itemKey)[fieldName] || [];
        const withoutDup = current.filter(
            (row) => row.contentDocumentId !== photo.contentDocumentId
        );
        this.updateItemState(itemKey, { [fieldName]: [...withoutDup, normalized] });
    }

    patchModFormPhoto(itemKey, contentDocumentId, mapper) {
        const fieldName = this.photoFieldForDocument(itemKey, contentDocumentId);
        this.patchItemPhoto(itemKey, contentDocumentId, mapper, fieldName);
    }

    /**
     * Take a Picture lists Mod Form photos and photos captured on this action.
     */
    photosForOpenModal(itemKey) {
        const state = this.getItemState(itemKey);
        if (!this.isTakePicMode) {
            return state.modFormPhotos || [];
        }
        const seen = new Set();
        const combined = [];
        [...(state.modFormPhotos || []), ...(state.takePicPhotos || [])].forEach((photo) => {
            if (!photo?.contentDocumentId || seen.has(photo.contentDocumentId)) {
                return;
            }
            seen.add(photo.contentDocumentId);
            combined.push(photo);
        });
        return combined;
    }

    /**
     * Mod Form files stay on the Return Order; Take a Picture files stay staged.
     */
    photoFieldForDocument(itemKey, contentDocumentId) {
        const state = this.getItemState(itemKey);
        const onModForm = (state.modFormPhotos || []).some(
            (photo) => photo.contentDocumentId === contentDocumentId
        );
        if (onModForm || !this.isTakePicMode) {
            return 'modFormPhotos';
        }
        return 'takePicPhotos';
    }

    patchItemPhoto(itemKey, contentDocumentId, mapper, fieldName) {
        if (!itemKey || !contentDocumentId || !fieldName) {
            return;
        }
        const current = this.getItemState(itemKey)[fieldName] || [];
        this.updateItemState(itemKey, {
            [fieldName]: current.map((photo) =>
                photo.contentDocumentId === contentDocumentId ? mapper(photo) : photo
            )
        });
    }

    async handleRemoveModFormPhoto(event) {
        const itemKey =
            event.currentTarget.dataset.itemKey || this.modFormCameraItemKey;
        const contentDocumentId = event.currentTarget.dataset.documentId;
        if (!itemKey || !contentDocumentId || !this.activeReturnOrderId) {
            return;
        }
        const deleting = new Set(this.deletingDocumentIds);
        deleting.add(contentDocumentId);
        this.deletingDocumentIds = deleting;
        this.isModFormBusy = true;
        this.modFormError = undefined;
        this.cameraError = undefined;
        try {
            const fieldName = this.photoFieldForDocument(itemKey, contentDocumentId);
            if (fieldName === 'takePicPhotos') {
                await deleteReceivingPhoto({ contentDocumentId });
            } else {
                await deleteModFormPhoto({
                    returnOrderId: this.activeReturnOrderId,
                    contentDocumentId
                });
            }
            const remaining = (this.getItemState(itemKey)[fieldName] || []).filter(
                (photo) => photo.contentDocumentId !== contentDocumentId
            );
            this.updateItemState(itemKey, { [fieldName]: remaining });
        } catch (error) {
            const message = this.normalizeError(error);
            this.modFormError = message;
            this.cameraError = message;
        } finally {
            const remainingIds = new Set(this.deletingDocumentIds);
            remainingIds.delete(contentDocumentId);
            this.deletingDocumentIds = remainingIds;
            this.isModFormBusy = false;
        }
    }

    handleModFormPhotoTitleChange(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        const value =
            event.detail && event.detail.value != null
                ? event.detail.value
                : event.target.value || '';
        if (!contentDocumentId || !this.modFormCameraItemKey) {
            return;
        }
        this.patchModFormPhoto(this.modFormCameraItemKey, contentDocumentId, (photo) => ({
            ...photo,
            editTitle: value
        }));
    }

    async handleSaveModFormPhotoTitle(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        if (!contentDocumentId || !this.modFormCameraItemKey || !this.activeReturnOrderId) {
            return;
        }
        const photos = this.photosForOpenModal(this.modFormCameraItemKey);
        const staged = photos.find((photo) => photo.contentDocumentId === contentDocumentId);
        const newTitle = (staged?.editTitle || staged?.title || '').trim();
        if (!newTitle) {
            this.cameraError = 'Photo title is required.';
            return;
        }

        const renaming = new Set(this.renamingDocumentIds);
        renaming.add(contentDocumentId);
        this.renamingDocumentIds = renaming;
        this.cameraError = undefined;
        try {
            const fieldName = this.photoFieldForDocument(
                this.modFormCameraItemKey,
                contentDocumentId
            );
            const updated =
                fieldName === 'takePicPhotos'
                    ? await renameReceivingPhoto({ contentDocumentId, newTitle })
                    : await renameModFormPhoto({
                          returnOrderId: this.activeReturnOrderId,
                          contentDocumentId,
                          newTitle
                      });
            this.patchModFormPhoto(this.modFormCameraItemKey, contentDocumentId, (photo) => ({
                ...photo,
                title: updated.title,
                editTitle: updated.title,
                fileExtension: updated.fileExtension || photo.fileExtension,
                thumbnailUrl: updated.thumbnailUrl || photo.thumbnailUrl,
                imageDownloadUrl: updated.imageDownloadUrl || photo.imageDownloadUrl
            }));
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Title updated',
                    message: `Photo renamed to "${updated.title}".`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.cameraError = this.normalizeError(error);
        } finally {
            const remaining = new Set(this.renamingDocumentIds);
            remaining.delete(contentDocumentId);
            this.renamingDocumentIds = remaining;
        }
    }

    handleModFormThumbnailError(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        if (!contentDocumentId) {
            return;
        }
        const next = new Set(this.thumbnailFallbackIds);
        next.add(contentDocumentId);
        this.thumbnailFallbackIds = next;
    }

    handleModFormModalChooseFiles() {
        const input = this.template.querySelector(
            'input[data-id="mod-form-modal-file-input"]'
        );
        if (input) {
            input.click();
        }
    }

    async handleModFormModalFileSelected(event) {
        const itemKey = this.modFormCameraItemKey;
        const files = Array.from(event.target.files || []);
        event.target.value = '';
        if (this.isTakePicMode) {
            await this.uploadTakePicFiles(itemKey, files);
            return;
        }
        await this.uploadModFormFiles(itemKey, files);
    }

    async openTakePic(itemKey) {
        if (!itemKey) {
            return;
        }
        this.photoModalMode = PHOTO_MODE_TAKE_PIC;
        this.modFormCameraItemKey = itemKey;
        this.isModFormCameraOpen = true;
        this.cameraError = undefined;
        this.updateItemState(itemKey, { lastActionKey: ACTION_KEY_TAKE_PIC });
        await this.refreshCameraOptions();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.bindCameraElements();
        }, 0);
    }

    async handleOpenModFormCamera(event) {
        this.photoModalMode = PHOTO_MODE_MOD_FORM;
        this.modFormCameraItemKey = event.currentTarget.dataset.itemKey;
        this.isModFormCameraOpen = true;
        this.cameraError = undefined;
        await this.refreshCameraOptions();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.bindCameraElements();
        }, 0);
    }

    async handleCloseModFormCamera() {
        if (this.isTakePicMode && this.isWorkOrderPath) {
            const attached = await this.commitWorkOrderPhotos();
            if (!attached) {
                return;
            }
        }
        this.dismissPhotoModal();
    }

    dismissPhotoModal() {
        this.handleStopCamera();
        this.isModFormCameraOpen = false;
        this.modFormCameraItemKey = undefined;
        this.photoModalMode = PHOTO_MODE_MOD_FORM;
        this.cameraError = undefined;
    }

    /**
     * GW-5968 - Device Work Order photos commit on Done and Receive Next Order.
     * Return Order photos stay staged until Finish Receiving creates the Work Order.
     * @return {Promise<boolean>} False when the link failed and the screen should stay put
     */
    async commitWorkOrderPhotos() {
        if (!this.isWorkOrderPath || !this.activeWorkOrderId) {
            return true;
        }
        const contentDocumentIds = [];
        const seenDocumentIds = new Set();
        Object.values(this.itemUiState || {}).forEach((state) => {
            (state.takePicPhotos || []).forEach((photo) => {
                const contentDocumentId = photo?.contentDocumentId;
                if (
                    !contentDocumentId ||
                    seenDocumentIds.has(contentDocumentId) ||
                    this.committedWorkOrderPhotoIds.has(contentDocumentId)
                ) {
                    return;
                }
                seenDocumentIds.add(contentDocumentId);
                contentDocumentIds.push(contentDocumentId);
            });
        });
        if (contentDocumentIds.length === 0) {
            return true;
        }
        try {
            await attachReceivingPhotos({
                workOrderId: this.activeWorkOrderId,
                contentDocumentIds
            });
            contentDocumentIds.forEach((contentDocumentId) => {
                this.committedWorkOrderPhotoIds.add(contentDocumentId);
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Photos attached',
                    message: 'Photos were attached to the Work Order.',
                    variant: 'success'
                })
            );
            return true;
        } catch (error) {
            const message = this.normalizeError(error);
            this.cameraError = message;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to attach photos',
                    message,
                    variant: 'error'
                })
            );
            return false;
        }
    }

    handleCameraChange(event) {
        this.selectedCameraId = event.detail.value;
    }

    async refreshCameraOptions() {
        this.cameraOptions = [];
        this.selectedCameraId = undefined;
        if (!navigator.mediaDevices?.enumerateDevices) {
            return;
        }
        try {
            const devices = await navigator.mediaDevices.enumerateDevices();
            const videoInputs = devices.filter((device) => device.kind === 'videoinput');
            this.cameraOptions = videoInputs.map((device, index) => ({
                label: device.label || `Camera ${index + 1}`,
                value: device.deviceId
            }));
            if (this.cameraOptions.length && !this.selectedCameraId) {
                this.selectedCameraId = this.cameraOptions[0].value;
            }
        } catch (error) {
            this.cameraError = this.normalizeError(error);
        }
    }

    bindCameraElements() {
        this.videoEl = this.template.querySelector('video.camera-preview');
        this.canvasEl = this.template.querySelector('canvas');
    }

    async handleStartCamera() {
        if (
            !navigator.mediaDevices ||
            typeof navigator.mediaDevices.getUserMedia !== 'function'
        ) {
            this.cameraError = 'Camera is not available in this browser.';
            return;
        }
        this.cameraError = undefined;
        this.isCameraStarting = true;
        this.handleStopCamera();
        try {
            this.bindCameraElements();
            const constraints = this.selectedCameraId
                ? { video: { deviceId: { exact: this.selectedCameraId } }, audio: false }
                : { video: true, audio: false };
            this.mediaStream = await navigator.mediaDevices.getUserMedia(constraints);
            if (this.videoEl) {
                this.videoEl.srcObject = this.mediaStream;
                await this.videoEl.play();
            }
            this.isCameraActive = true;
            await this.refreshCameraOptions();
        } catch (error) {
            this.cameraError = this.normalizeError(error);
            this.isCameraActive = false;
        } finally {
            this.isCameraStarting = false;
        }
    }

    handleStopCamera() {
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

    async handleCaptureModFormPhoto() {
        if (!this.isCameraActive || this.isCapturing || !this.modFormCameraItemKey) {
            return;
        }
        this.isCapturing = true;
        this.cameraError = undefined;
        try {
            this.bindCameraElements();
            if (!this.videoEl || !this.canvasEl) {
                throw new Error('Camera preview is not ready.');
            }
            const width = this.videoEl.videoWidth || 1280;
            const height = this.videoEl.videoHeight || 720;
            this.canvasEl.width = width;
            this.canvasEl.height = height;
            const context = this.canvasEl.getContext('2d');
            context.drawImage(this.videoEl, 0, 0, width, height);
            const dataUrl = this.canvasEl.toDataURL('image/jpeg', 0.92);
            const takePic = this.isTakePicMode;
            const photo = takePic
                ? await stageReceivingPhoto({
                      base64Data: dataUrl,
                      fileName: `Receive-${Date.now()}.jpg`
                  })
                : await stageModFormPhoto({
                      returnOrderId: this.activeReturnOrderId,
                      base64Data: dataUrl,
                      fileName: MOD_REQUEST_PHOTO_FILE_NAME
                  });
            this.addItemPhoto(
                this.modFormCameraItemKey,
                photo,
                takePic ? 'takePicPhotos' : 'modFormPhotos'
            );
            this.dispatchEvent(
                new ShowToastEvent({
                    title: takePic ? 'Photo staged' : 'Mod Form photo saved',
                    message: takePic
                        ? 'Photo staged for Finish Receiving.'
                        : 'Photo attached to the Return Order.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.cameraError = this.normalizeError(error);
        } finally {
            this.isCapturing = false;
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

    async updateWorkspaceTab() {
        document.title = BROWSER_TAB_LABEL;
        if (!this.isConsoleNavigation) {
            return;
        }
        try {
            const tabInfo = await getFocusedTabInfo();
            if (tabInfo?.tabId) {
                await setTabLabel(tabInfo.tabId, BROWSER_TAB_LABEL);
            }
        } catch (e) {
            // Non-console hosts ignore workspace APIs.
        }
    }

    formatModFormPhotoCount(count) {
        if (!count) {
            return '';
        }
        return count === 1 ? '1 photo' : `${count} photos`;
    }

    normalizeError(error) {
        return (
            error?.body?.message ||
            error?.message ||
            'Unable to continue. Check the Scan Order value and try again.'
        );
    }
}