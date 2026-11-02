/**
 * @description Work Order debrief LWC (woDebrief) for Field Service technicians.
 * @author Uptima Development Team
 */
import { LightningElement, api, wire } from 'lwc';
import { gql, graphql, refreshGraphQL } from 'lightning/uiGraphQLApi';
import {
    updateRecord,
    createRecord,
    deleteRecord,
    getRecord,
    notifyRecordUpdateAvailable
} from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent }        from 'lightning/platformShowToastEvent';
import LightningConfirm          from 'lightning/confirm';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getBarcodeScanner } from 'lightning/mobileCapabilities';
import USER_ID from '@salesforce/user/Id';
import getUsageConsumptionRecordTypeId from '@salesforce/apex/WoDebriefProductItemController.getUsageConsumptionRecordTypeId';
import getProductServicedRecordTypeId from '@salesforce/apex/WoDebriefProductItemController.getProductServicedRecordTypeId';
import stampAssetInspections from '@salesforce/apex/WoDebriefAssetInspection.stampAssetInspections';
import saveExpense from '@salesforce/apex/WoDebriefRegionalExpenseController.saveExpense';
import listExpenseBillableFields from '@salesforce/apex/WoDebriefRegionalExpenseController.listExpenseBillableFields';
import getDepartmentsForAccount from '@salesforce/apex/WoDebriefIMSchildWOController.getDepartmentsForAccount';
import linkFilesToRecord from '@salesforce/apex/WoDebriefIMSchildWOController.linkFilesToRecord';
import listMobileDevicePictures from '@salesforce/apex/WoDebriefIMSchildWOController.listMobileDevicePictures';
import getMobileDevicePictureData from '@salesforce/apex/WoDebriefIMSchildWOController.getMobileDevicePictureData';
import saveWorkOrderHeaderMobileDevicePicture from '@salesforce/apex/WoDebriefIMSchildWOController.saveWorkOrderHeaderMobileDevicePicture';
import saveProductServicedLineMobileDevicePicture from '@salesforce/apex/WoDebriefIMSchildWOController.saveProductServicedLineMobileDevicePicture';
import saveMobileDevicePicture from '@salesforce/apex/WoDebriefIMSchildWOController.saveMobileDevicePicture';
import saveMobileDevicePictureOnWorkOrderLineItem from '@salesforce/apex/WoDebriefIMSchildWOController.saveMobileDevicePictureOnWorkOrderLineItem';
import deleteMobileDevicePicture from '@salesforce/apex/WoDebriefIMSchildWOController.deleteMobileDevicePicture';
import updateMobileDevicePictureComment from '@salesforce/apex/WoDebriefIMSchildWOController.updateMobileDevicePictureComment';
import resolveMobilePictureRecordId from '@salesforce/apex/WoDebriefIMSchildWOController.resolveMobilePictureRecordId';
import findLatestProductServicedLineId from '@salesforce/apex/WoDebriefIMSchildWOController.findLatestProductServicedLineId';

import WOLI_OBJECT       from '@salesforce/schema/WorkOrderLineItem';
import WOLI_DESCRIPTION  from '@salesforce/schema/WorkOrderLineItem.Description';
import WOLI_DURATION     from '@salesforce/schema/WorkOrderLineItem.Duration';
import WOLI_UNITPRICE    from '@salesforce/schema/WorkOrderLineItem.UnitPrice';
import WOLI_QUANTITY     from '@salesforce/schema/WorkOrderLineItem.Quantity';
import WOLI_WORKORDERID  from '@salesforce/schema/WorkOrderLineItem.WorkOrderId';
import WOLI_LINETYPE     from '@salesforce/schema/WorkOrderLineItem.LineType__c';
import WOLI_ASSIGNED_RES from '@salesforce/schema/WorkOrderLineItem.AssignedResource__c';
import WOLI_WORKTYPE     from '@salesforce/schema/WorkOrderLineItem.WorkTypeId';
import WOLI_STARTDATE    from '@salesforce/schema/WorkOrderLineItem.StartDate';
import WOLI_ENDDATE      from '@salesforce/schema/WorkOrderLineItem.EndDate';
import WOLI_ASSETID      from '@salesforce/schema/WorkOrderLineItem.AssetId';
import WOLI_REPAIRCODE   from '@salesforce/schema/WorkOrderLineItem.RepairCode__c';
import WOLI_STATUS from '@salesforce/schema/WorkOrderLineItem.Status';
import WOLI_INSPECTION_OUTCOME from '@salesforce/schema/WorkOrderLineItem.InspectionOutcome__c';
import WOLI_SEND_TO_REPAIR_CENTER from '@salesforce/schema/WorkOrderLineItem.SendToRepairCenter__c';
import WOLI_SERIAL_NUMBER from '@salesforce/schema/WorkOrderLineItem.SerialNumber__c';
import WOLI_MODEL from '@salesforce/schema/WorkOrderLineItem.Model__c';
import WOLI_DEPARTMENT from '@salesforce/schema/WorkOrderLineItem.Department__c';
import WOLI_REPORTED_PROBLEM from '@salesforce/schema/WorkOrderLineItem.ReportedProblem__c';
import WOLI_NOT_INSPECTED_REASON from '@salesforce/schema/WorkOrderLineItem.NotInspectedReason__c';
import WOLI_ADDITIONAL_SERVICES from '@salesforce/schema/WorkOrderLineItem.AdditionalServices__c';
import WOLI_INSULATION from '@salesforce/schema/WorkOrderLineItem.InsulationPowderCoating__c';
import WOLI_BILLING_TYPE from '@salesforce/schema/WorkOrderLineItem.BillingType__c';
import WOLI_DISCOUNT from '@salesforce/schema/WorkOrderLineItem.Discount';
import WOLI_RECORDTYPE from '@salesforce/schema/WorkOrderLineItem.RecordTypeId';
import PRODUCT2_PRODUCT_TYPE from '@salesforce/schema/Product2.ProductType__c';
import EXPENSE_OBJECT            from '@salesforce/schema/Expense';
import EXPENSE_EXPENSETYPE       from '@salesforce/schema/Expense.ExpenseType';
import EXPENSE_TRANSACTIONDATE   from '@salesforce/schema/Expense.TransactionDate';
import EXPENSE_AMOUNT            from '@salesforce/schema/Expense.Amount';
import EXPENSE_WORKORDER         from '@salesforce/schema/Expense.WorkOrderId';
import EXPENSE_CURRENCY          from '@salesforce/schema/Expense.CurrencyIsoCode';
import EXPENSE_OWNER             from '@salesforce/schema/Expense.OwnerId';
import OVERRIDE_CODE            from '@salesforce/schema/Expense.OverrideCode__c';
import EXPENSE_BILLABLE_AMOUNT   from '@salesforce/schema/Expense.BillableAmount__c';
import EXPENSE_OVERRIDE_BILLABLE from '@salesforce/schema/Expense.OverrideBillableAmount__c';

const EXPENSE_RELATED_LIST_ID = 'Expenses';
const EXPENSE_RELATED_LIST_FIELDS = [
    'Expense.Id',
    'Expense.ExpenseType',
    'Expense.TransactionDate',
    'Expense.Amount',
    'Expense.OverrideCode__c',
    'Expense.BillableAmount__c',
    'Expense.OverrideBillableAmount__c'
];

// Separate from WORK_ORDER_QUERY — combining WorkOrder + Expense in one document
// breaks ObjectInfo resolution for Expense in some orgs.
const EXPENSES_QUERY = gql`
    query GetWorkOrderExpenses($workOrderId: ID) {
        uiapi {
            query {
                Expense(
                    where: { WorkOrderId: { eq: $workOrderId } }
                    first: 200
                ) {
                    edges {
                        node {
                            Id
                            ExpenseType { value }
                            TransactionDate { value }
                            Amount { value }
                            OverrideCode__c { value }
                            BillableAmount__c { value }
                            OverrideBillableAmount__c { value }
                        }
                    }
                }
            }
        }
    }
`;

const WORK_ORDER_QUERY = gql`
    query GetWorkOrderDebrief($workOrderId: ID) {
        uiapi {
            query {
                WorkOrder(
                    where: { Id: { eq: $workOrderId } }
                    first: 1
                ) {
                    edges {
                        node {
                            Id
                            WorkOrderNumber { value }
                            Status { value }
                            AccountId { value }
                            Account {
                                Name { value }
                            }
                            Asset {
                                Name { value }
                                SerialNumber { value }
                            }
                            WorkOrderType__c { value }
                            WorkTypeId { value }
                            CurrencyIsoCode { value }
                            WorkOrderLineItems(first: 200) {
                                edges {
                                    node {
                                        Id
                                        LineItemNumber { value }
                                        Description { value }
                                        Status { value }
                                        Duration { value }
                                        UnitPrice { value }
                                        Quantity { value }
                                        TotalPrice { value }
                                        LineType__c { value }
                                        WorkTypeId { value }
                                        WorkType {
                                            Id
                                            Name { value }
                                        }
                                        StartDate { value }
                                        EndDate { value }
                                        InspectionOutcome__c { value }
                                        BillingType__c { value }
                                        AssignedResource__c { value }
                                        AssignedResource__r {
                                            Id
                                            Name { value }
                                        }
                                        AssetId { value }
                                        Asset {
                                            Id
                                            SerialNumber { value }
                                            Name { value }
                                        }
                                        RepairCode__c { value }
                                        RepairCode__r {
                                            Id
                                            ProductCode { value }
                                            Name { value }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
`;

const SERVICE_RESOURCES_BY_USERS_QUERY = gql`
    query GetServiceResourcesByUsers($userIds: [ID]) {
        uiapi {
            query {
                ServiceResource(
                    where: {
                        and: [
                            { IsActive: { eq: true } }
                            { RelatedRecordId: { in: $userIds } }
                        ]
                    }
                    first: 50
                ) {
                    edges {
                        node {
                            Id
                            Name { value }
                            RelatedRecordId { value }
                        }
                    }
                }
            }
        }
    }
`;

const ASSET_BY_SERIAL_QUERY = gql`
    query FindAccountImsAssetBySerial($accountId: ID, $serialNumber: String) {
        uiapi {
            query {
                Asset(
                    where: {
                        and: [
                            { AccountId: { eq: $accountId } }
                            { RecordType: { DeveloperName: { eq: "IMS_Asset" } } }
                            { SerialNumber: { eq: $serialNumber } }
                        ]
                    }
                    first: 5
                ) {
                    edges {
                        node {
                            Id
                            Name { value }
                            SerialNumber { value }
                        }
                    }
                }
            }
        }
    }
`;

const ACCOUNT_IMS_ASSETS_QUERY = gql`
    query GetAccountImsAssets($accountId: ID) {
        uiapi {
            query {
                Asset(
                    where: {
                        and: [
                            { AccountId: { eq: $accountId } }
                            { RecordType: { DeveloperName: { eq: "IMS_Asset" } } }
                        ]
                    }
                    first: 2000
                    orderBy: { Name: { order: ASC } }
                ) {
                    edges {
                        node {
                            Id
                            Name { value }
                            SerialNumber { value }
                            LastInspectionDate__c { value }
                            LastServicedDate__c { value }
                            Product2 {
                                ProductLine__c { value }
                                SubProductLine__c { value }
                                DeviceType__c { value }
                                Manufacturer__c { value }
                                Model__c { value }
                            }
                        }
                    }
                }
            }
        }
    }
`;

const REPAIR_CENTER_LINES_QUERY = gql`
    query GetWoDebriefRepairCenterLines($workOrderId: ID) {
        uiapi {
            query {
                WorkOrderLineItem(
                    where: { WorkOrderId: { eq: $workOrderId } }
                    first: 200
                ) {
                    edges {
                        node {
                            Id
                            SerialNumber__c { value }
                            Model__c { value }
                            Department__c { value }
                            ReportedProblem__c { value }
                            NotInspectedReason__c { value }
                            AdditionalServices__c { value }
                            InsulationPowderCoating__c { value }
                            SendToRepairCenter__c { value }
                        }
                    }
                }
            }
        }
    }
`;

const CURRENT_USER_SERVICE_RESOURCE_QUERY = gql`
    query GetCurrentUserServiceResource($userId: ID) {
        uiapi {
            query {
                ServiceResource(
                    where: {
                        and: [
                            { RelatedRecordId: { eq: $userId } }
                            { IsActive: { eq: true } }
                        ]
                    }
                    first: 1
                ) {
                    edges {
                        node {
                            Id
                            Name { value }
                        }
                    }
                }
            }
        }
    }
`;

// Tab definitions — order here drives the UI tab order.
// `type`   = picklist value to filter on.
// `canAdd` = whether this tab shows an Add Line button.
// `schema` = which form/card layout to render:
//             'travel'  → AssignedResource + StartDate/EndDate
//             'labor'   → travel + Asset + RepairCode
//             'expense' → Expense object: ExpenseType + TransactionDate + Amount (+ hidden WorkOrderId on save)
//             'generic' → fallback: Description/Duration/UnitPrice
const TAB_DEFS = [
    { key: 'Time',             label: 'Time',                   addLabel: '+ Add Time Line',              type: null,                canAdd: true, schema: 'time'            },
    { key: 'ProductServiced',  label: 'Product Serviced',      addLabel: '+ Add Product Serviced Line',  type: 'Product Serviced',  canAdd: true, schema: 'productServiced' },
    { key: 'Expense',          label: 'Expense',               addLabel: '+ Add Expense Line',           type: null,                canAdd: true, schema: 'expense'         }
];
const HIDDEN_TAB_KEYS = new Set(/*['Expense']*/);
const SERVICE_CODE_PRODUCT_TYPE = 'Service Code';

const TIME_LINE_TYPES = new Set(['Travel', 'Labor']);
const LINE_TYPE_PRODUCT_SERVICED = 'Product Serviced';
/** @description GW-6437 - CRSS Mobile Device Picture comment delimiter for mobile-safe Apex payloads. */
const MOBILE_PICTURE_COMMENT_DELIMITER = '|||';
/** @description GW-6437 - Maximum CRSS Mobile Device Picture comment length. */
const MOBILE_PICTURE_COMMENT_MAX_LENGTH = 1000;
const WOLI_USAGE_CONSUMPTION_RT = 'UsageConsumption';
const WOLI_PRODUCT_SERVICED_RT = 'ProductServiced';
const BILLING_TYPE_BILLABLE = 'Billable';
const BILLING_TYPE_COURTESY = 'Courtesy';
const BILLING_TYPE_NON_BILLABLE = 'Non-Billable';
const HIGHLIGHT_BILLING_TYPES = new Set(['Courtesy', 'Warranty', 'SVC Warranty']);
const LINE_STATUS_IN_PROGRESS = 'In Progress';
const BILLING_TYPE_OPTIONS = [
    { label: 'Contract', value: 'Contract' },
    { label: 'Warranty', value: 'Warranty' },
    { label: 'SVC Warranty', value: 'SVC Warranty' },
    { label: 'Billable', value: BILLING_TYPE_BILLABLE },
    { label: 'Courtesy', value: BILLING_TYPE_COURTESY },
    { label: 'Non-Billable', value: BILLING_TYPE_NON_BILLABLE }
];

const LINE_TYPE_TO_SCHEMA = {
    Travel: 'travel',
    Labor:  'labor'
};

const TIME_LINE_TYPE_OPTIONS = [
    { label: 'Travel', value: 'Travel' },
    { label: 'Labor',  value: 'Labor' }
];

// Expense.ExpenseType picklist values — keep in sync with the org picklist if values change.
const EXPENSE_TYPE_OPTIONS = [
    { label: 'Billable',                  value: 'Billable' },
    { label: 'Non-Billable',              value: 'Non-Billable' },
    { label: 'Airfare',                   value: 'Airfare' },
    { label: 'Chamber Cleaning',          value: 'Chamber Cleaning' },
    { label: 'Control Program Uploading', value: 'Control Program Uploading' },
    { label: 'Kilometers',                value: 'Kilometers' },
    { label: 'Loaner',                    value: 'Loaner' },
    { label: 'Local Purchase',            value: 'Local Purchase' },
    { label: 'Meals',                     value: 'Meals' },
    { label: 'Mileage',                   value: 'Mileage' },
    { label: 'Misc.',                     value: 'Misc.' },
    { label: 'Parking',                   value: 'Parking' },
    { label: 'Shipping and Handling',     value: 'Shipping and Handling' },
    { label: 'Specialty Billing',         value: 'Specialty Billing' },
    { label: 'Specialty Item',            value: 'Specialty Item' },
    { label: 'Sub Cost',                  value: 'Sub Cost' },
    { label: 'Supplies',                  value: 'Supplies' },
    { label: 'Tolls',                     value: 'Tolls' }
];

// WorkOrderLineItem.InspectionOutcome__c picklist — keep in sync with the org picklist if values change.
const INSPECTION_OUTCOME_OPTIONS = [
    { label: 'Passed',                              value: 'Passed' },
    { label: 'Recommended for Repair',              value: 'Recommended for Repair' },
    { label: 'Not Available',                       value: 'Not Available' },
    { label: 'Do Not Use(P0)',                      value: 'Do Not Use(P0)' },
    { label: 'Performance Standard Not Met (P1)',   value: 'Performance Standard Not Met (P1)' },
    { label: 'Cost Avoidance Opportunity (P2)',     value: 'Cost Avoidance Opportunity (P2)' },
    { label: 'No Repair Needed (OK)',               value: 'No Repair Needed (OK)' },
    { label: 'Not Inspected (Inventory Only)',      value: 'Not Inspected (Inventory Only)' }
];

const DO_NOT_USE_P0 = 'Do Not Use(P0)';
const LINE_STATUS_CANCELED = 'Canceled';
const LINE_STATUS_COMPLETED = 'Completed';
const LINE_STATUS_NEW = 'New';
const INSULATION_POWDER_COATING_OPTIONS = [
    'Black', 'Blue', 'Light Blue', 'Navy Blue', 'Green', 'Yellow', 'Orange',
    'Light Gray', 'Purple', 'Salmon Orange', 'Lavender', 'Brown', 'Red'
].map(value => ({ label: value, value }));

const EMPTY_ASSET_FILTERS = () => ({
    productLine: '',
    subProductLine: '',
    deviceType: '',
    manufacturer: '',
    model: ''
});

// Map LineType picklist value -> tab def (used during save to look up the schema
// for an existing record being edited).
const TYPE_TO_DEF = {
    Travel:  { key: 'Time', type: 'Travel',  schema: 'travel'  },
    Labor:   { key: 'Time', type: 'Labor',   schema: 'labor'   },
    'Product Serviced': { key: 'ProductServiced', type: LINE_TYPE_PRODUCT_SERVICED, schema: 'productServiced' },
    Expense: { key: 'Expense', type: 'Expense', schema: 'expense' }
};

const TAB_KEY_TO_DEF = TAB_DEFS.reduce((acc, d) => {
    acc[d.key] = d;
    return acc;
}, {});

const KNOWN_TYPES = new Set(['Travel', 'Labor', LINE_TYPE_PRODUCT_SERVICED, 'Expense']);

const EMPTY_ADD_FORM_VISIBILITY = () =>
    TAB_DEFS.filter(d => d.canAdd)
            .reduce((acc, d) => { acc[d.key] = false; return acc; }, {});

const EMPTY_TAB_SEARCH_TERMS = () =>
    TAB_DEFS.filter(d => !HIDDEN_TAB_KEYS.has(d.key))
            .reduce((acc, d) => { acc[d.key] = ''; return acc; }, {});

let _tempIdSeq = 0;

/**
 * @description WoDebrief Lightning Web Component.
 * @author Uptima Development Team
 */
export default class WoDebrief extends LightningElement {
    @api recordId;

    graphqlResult;
    accountAssetsGraphqlResult;
    expensesGraphqlResult;
    expensesListResult;
    _workOrder      = null;
    _serverLines    = [];
    _serverExpenses = [];
    _serverExpensesFromGraphql = [];
    _serverExpensesFromRelatedList = [];
    /** @description Apex-sourced billable custom fields keyed by 15-character Expense Id. */
    _expenseBillableById = {};

    // ── Draft / pending state ────────────────────────────────────────────────
    _pendingEdits   = {};  // { [woliId]: { desc, duration, unitPrice } }
    _pendingDeletes = {};  // { [woliId]: true }
    _pendingAdds    = [];  // [{ _tempId, _lineType, desc, duration, unitPrice }]

    // Live per-row edit form state
    editStateMap = {};
    _mobilePicturesByRecordId = {};
    _pictureLineIds = {};
    /** @description GW-375 - GraphQL line ids keyed by 15-character prefix (mobile-safe). */
    _pictureLineIdBySaveKey = {};
    /** @description GW-375 - Last Product Serviced line opened for edit (mobile file buttons lose line id). */
    _activeProductServicedLineIdForPicture = null;
    /** @description GW-375 - Header/line pictures waiting for Save All. */
    _stagedMobilePictureSaves = [];
    /** @description GW-375 - Line pictures held until a Product Serviced line exists. */
    _picturesWaitingForNextLine = [];
    _mobilePictureRequest = 0;
    _savingPicture = false;
    mobilePictureVersion = 0;
    showPictureReview = false;
    reviewPictureUrl = '';
    reviewPictureLoading = false;
    reviewPicture = null;
    /** @description GW-6437 - Optional comment before a CRSS picture upload completes. */
    showPictureCommentCapture = false;
    pictureCommentDraftText = '';
    reviewPictureComment = '';
    _pendingMobilePictureCapture = null;
    _pictureDataPromises = {};

    // Cache of Product2 Id -> Name for Repair Code helper text below the picker.
    // Pre-seeded from server data (RepairCode__r.Name); supplemented by an
    // on-demand @wire(getRecord) lookup driven by `_repairCodeLookupId` whenever
    // the user picks a code we haven't seen yet.
    _repairCodeNameById = {};
    _repairCodeLookupId;

    _currentUserServiceResourceId   = null;
    _currentUserServiceResourceName = '';
    _serviceResourceByUserId        = {};
    _userIdByServiceResourceId      = {};
    _ownerUserIdsForLookup          = [];
    _assignedResourceOwnerLookupId;

    // Per-tab search terms (keyed by tab key; each tab filters independently)
    tabSearchTerms = EMPTY_TAB_SEARCH_TERMS();

    // Per-tab add-form visibility and field values (keyed by tab key)
    showAddForm  = EMPTY_ADD_FORM_VISIBILITY();
    /** @description Product Serviced multi-asset picker, matching CRSS Assign Assets. */
    showMultiAssetPicker = false;
    selectedMultiAssetIds = {};
    multiAssetError = '';
    assetFilters = EMPTY_ASSET_FILTERS();
    assetScanSerial = '';
    assetScanMessage = '';
    departmentOptions = [];
    _extraDepartmentOptions = [];
    _insulationPicklistOptions = [];
    _repairCenterByLineId = {};
    _repairCenterLoaded = false;
    _assetDepartmentById = {};
    /** @description Asset whose Make, Model, and Department should be copied onto a Do Not Use (P0) line. */
    _repairDefaultAssetId;
    /** @description Line receiving asset defaults. Null is the add form. */
    _repairDefaultLineId = null;
    /** @description Serial number lookup for the add-form scanner. */
    _assetSerialLookup;
    /** @description Bumped when Make or Model is defaulted so those inputs pick up the new value. */
    repairFieldEpoch = 0;
    _productServicedRecordTypeWireDone = false;
    _woliObjectInfoDone = false;
    addFormState = {
        desc: '', unitPrice: '',
        assignedResourceId: null, workTypeId: null, startDate: '', endDate: '',
        assetId: null, repairCodeId: null, inspectionOutcome: '',
        expenseType: '', transactionDate: '', amount: '',
        overrideCode: '', billableAmount: '', overrideBillableAmount: false,
        quantity: '', duration: '',
        billingType: BILLING_TYPE_BILLABLE, discount: 0
    };

    /** @description Record type Id used for BillingType__c picklist values. */
    woliPicklistRecordTypeId;
    /** @description BillingType__c picklist options from the WOLI field. */
    billingTypePicklistOptions = [];
    /** @description Record type Id used for Expense.OverrideCode__c picklist values. */
    expensePicklistRecordTypeId;
    /** @description Override Code picklist options from Expense.OverrideCode__c. */
    overrideCodePicklistOptions = [];

    editErrors = {};
    addErrors  = {};

    // Re-entrancy guard for Save All (prevents double-tap issues where the second
    // tap tries to enqueue draft actions for records already removed in the first)
    _saving = false;

    /** @description WorkOrderLineItem UsageConsumption record type Id. */
    _usageConsumptionRecordTypeId = null;
    /** @description WorkOrderLineItem ProductServiced record type Id. */
    _productServicedRecordTypeId = null;

    activeTab = 'Time';

    isOffline = !navigator.onLine;
    _onlineHandler  = () => { this.isOffline = false; };
    _offlineHandler = () => { this.isOffline = true;  };

    // ── Wire ─────────────────────────────────────────────────────────────────
    /**
     * @description Wire: Schema UsageConsumption Record Type Id. Field Service mobile
     *              getObjectInfo often omits developerName or marks the type unavailable.
     */
    @wire(getUsageConsumptionRecordTypeId)
    wiredUsageConsumptionRecordType({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woDebrief getUsageConsumptionRecordTypeId failed', error);
            return;
        }
        if (data) {
            this._usageConsumptionRecordTypeId = data;
            this.woliPicklistRecordTypeId = data;
        }
    }

    /**
     * @description Wire: ProductServiced record type Id. Field Service mobile
     *              getObjectInfo often omits developerName or marks the type unavailable.
     */
    @wire(getProductServicedRecordTypeId)
    wiredProductServicedRecordType({ data, error }) {
        if (error) {
            this._productServicedRecordTypeWireDone = true;
            // eslint-disable-next-line no-console
            console.error('woDebrief getProductServicedRecordTypeId failed', error);
            return;
        }
        if (data) {
            this._productServicedRecordTypeWireDone = true;
            this._productServicedRecordTypeId = data;
        }
    }

    /**
     * @description Wire: WorkOrderLineItem object info to resolve UsageConsumption record type.
     */
    @wire(getObjectInfo, { objectApiName: WOLI_OBJECT })
    wiredWoliObjectInfo({ data, error }) {
        if (error) {
            this._woliObjectInfoDone = true;
            // eslint-disable-next-line no-console
            console.error('woDebrief getObjectInfo WorkOrderLineItem failed', error);
            return;
        }
        if (data?.defaultRecordTypeId && !this.woliPicklistRecordTypeId) {
            this.woliPicklistRecordTypeId = data.defaultRecordTypeId;
        }
        const resolved = this._recordTypeIdByDeveloperName(
            data,
            WOLI_USAGE_CONSUMPTION_RT
        );
        if (resolved) {
            this._usageConsumptionRecordTypeId = resolved;
            this.woliPicklistRecordTypeId = resolved;
        }
        const productServicedId = this._recordTypeIdByDeveloperName(
            data,
            WOLI_PRODUCT_SERVICED_RT
        );
        if (productServicedId) {
            this._productServicedRecordTypeId = productServicedId;
        }
        if (data) {
            this._woliObjectInfoDone = true;
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$woliPicklistRecordTypeId',
        fieldApiName: WOLI_BILLING_TYPE
    })
    wiredBillingTypePicklist({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woDebrief getPicklistValues BillingType__c failed', error);
            return;
        }
        if (data?.values) {
            this.billingTypePicklistOptions = data.values.map(({ label, value }) => ({ label, value }));
        }
    }

    /**
     * @description Wire: Expense object info for Override Code picklist record type.
     */
    @wire(getObjectInfo, { objectApiName: EXPENSE_OBJECT })
    wiredExpenseObjectInfo({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woDebrief getObjectInfo Expense failed', error);
            return;
        }
        if (data?.defaultRecordTypeId) {
            this.expensePicklistRecordTypeId = data.defaultRecordTypeId;
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$expensePicklistRecordTypeId',
        fieldApiName: OVERRIDE_CODE
    })
    wiredOverrideCodePicklist({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woDebrief getPicklistValues OverrideCode__c failed', error);
            return;
        }
        if (data?.values) {
            this.overrideCodePicklistOptions = data.values.map(({ label, value }) => ({ label, value }));
        }
    }

    /**
     * @description Wire adapter handler: Data.
     */
    @wire(graphql, {
        query: WORK_ORDER_QUERY,
        variables: '$queryVariables'
    })
    wiredData(result) {
        this.graphqlResult = result;
        if (result.data) {
            const woEdge = result.data.uiapi.query.WorkOrder.edges[0];
            if (woEdge) {
                this._workOrder = {
                    ...woEdge.node,
                    Id: this._recordIdFromGraphql(woEdge.node.Id)
                };
                this._serverLines = (woEdge.node.WorkOrderLineItems?.edges ?? [])
                    .map(e => ({
                        ...e.node,
                        Id: this._recordIdFromGraphql(e.node.Id)
                    }));
                this._seedRepairCodeNameCache(this._serverLines);
                this._syncPictureLineRegistry();
                this._loadMobileDevicePictures();
            }
        }
    }

    /**
     * @description IMS Assets on the work order account for the multi-asset picker.
     */
    @wire(graphql, {
        query: ACCOUNT_IMS_ASSETS_QUERY,
        variables: '$accountAssetQueryVariables'
    })
    wiredAccountAssets(result) {
        this.accountAssetsGraphqlResult = result;
    }

    /**
     * @description Departments on the Work Order account for Do Not Use (P0) lines.
     */
    @wire(getDepartmentsForAccount, { accountId: '$repairCenterAccountId' })
    wiredDepartments({ data }) {
        const fromAccount = (data || [])
            .filter(row => row?.id)
            .map(row => ({ label: row.name || row.id, value: row.id }));
        const seen = new Set(fromAccount.map(option => option.value));
        const extras = (this._extraDepartmentOptions || []).filter(option => !seen.has(option.value));
        this.departmentOptions = [...fromAccount, ...extras];
    }

    /**
     * @description Insulation / Powder Coating values from the work order line field.
     */
    @wire(getPicklistValues, {
        recordTypeId: '$woliPicklistRecordTypeId',
        fieldApiName: WOLI_INSULATION
    })
    wiredInsulationPicklist({ data }) {
        if (data?.values?.length) {
            this._insulationPicklistOptions = data.values.map(({ label, value }) => ({ label, value }));
        }
    }

    /**
     * @description Saved repair-center values. Kept off the main query so a field-access
     *              error does not blank the rest of the debrief.
     */
    @wire(graphql, { query: REPAIR_CENTER_LINES_QUERY, variables: '$queryVariables' })
    wiredRepairCenterLines({ data }) {
        const edges = data?.uiapi?.query?.WorkOrderLineItem?.edges ?? [];
        if (!data) return;
        this._repairCenterLoaded = true;
        const byId = {};
        for (const edge of edges) {
            const node = edge?.node;
            if (!node?.Id) continue;
            byId[node.Id] = {
                serialNumber: node.SerialNumber__c?.value ?? '',
                model: node.Model__c?.value ?? '',
                departmentId: node.Department__c?.value ?? null,
                reportedProblem: node.ReportedProblem__c?.value ?? '',
                notInspectedReason: node.NotInspectedReason__c?.value ?? '',
                additionalServices: !!node.AdditionalServices__c?.value,
                insulationPowderCoating: node.InsulationPowderCoating__c?.value ?? '',
                sendToRepairCenter: !!node.SendToRepairCenter__c?.value
            };
        }
        this._repairCenterByLineId = byId;
        if (this.addFormState?.inspectionOutcome === DO_NOT_USE_P0) {
            this._defaultDepartmentForLine(null);
        }
        Object.entries(this.editStateMap || {}).forEach(([id, state]) => {
            if (state?.isEditing) {
                this._defaultDepartmentForLine(id);
            }
        });
    }

    /**
     * @description Wire adapter handler: Expenses Graphql.
     */
    @wire(graphql, {
        query: EXPENSES_QUERY,
        variables: '$expenseQueryVariables'
    })
    wiredExpensesGraphql(result) {
        this.expensesGraphqlResult = result;
        if (result.data) {
            this._serverExpensesFromGraphql = (result.data.uiapi.query.Expense?.edges ?? [])
                .map(e => e.node);
            this._rebuildServerExpenses();
            this._refreshExpenseBillableFields();
        }
    }

    /**
     * @description Wire adapter handler: Expenses Related.
     */
    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId:  EXPENSE_RELATED_LIST_ID,
        fields:         EXPENSE_RELATED_LIST_FIELDS,
        pageSize:       200,
        sortBy:         ['Expense.TransactionDate']
    })
    wiredExpensesRelated(result) {
        this.expensesListResult = result;
        if (result.data) {
            this._serverExpensesFromRelatedList = (result.data.records ?? [])
                .map(r => this._normalizeExpenseFromLds(r));
            this._rebuildServerExpenses();
            this._refreshExpenseBillableFields();
        }
    }

    /**
     * @description Wire adapter handler: Owner Service Resources.
     */
    @wire(graphql, {
        query: SERVICE_RESOURCES_BY_USERS_QUERY,
        variables: '$srByUsersVariables'
    })
    wiredOwnerServiceResources(result) {
        const edges = result.data?.uiapi?.query?.ServiceResource?.edges ?? [];
        if (!edges.length) return;
        const srByUser = { ...this._serviceResourceByUserId };
        const userBySr = { ...this._userIdByServiceResourceId };
        for (const edge of edges) {
            const srId   = edge.node.Id;
            const userId = edge.node.RelatedRecordId?.value;
            if (srId && userId) {
                srByUser[userId] = srId;
                userBySr[srId]   = userId;
            }
        }
        this._serviceResourceByUserId   = srByUser;
        this._userIdByServiceResourceId = userBySr;
    }

    /**
     * @description Wire adapter handler: Current User Service Resource.
     */
    @wire(graphql, {
        query: CURRENT_USER_SERVICE_RESOURCE_QUERY,
        variables: '$currentUserQueryVariables'
    })
    wiredCurrentUserServiceResource(result) {
        const edge = result.data?.uiapi?.query?.ServiceResource?.edges?.[0];
        if (!edge) return;
        this._currentUserServiceResourceId   = edge.node.Id;
        this._currentUserServiceResourceName = edge.node.Name?.value ?? '';
        this._serviceResourceByUserId = {
            ...this._serviceResourceByUserId,
            [USER_ID]: edge.node.Id
        };
        this._userIdByServiceResourceId = {
            ...this._userIdByServiceResourceId,
            [edge.node.Id]: USER_ID
        };
        if (!this.addFormState.assignedResourceId && this._currentUserServiceResourceId) {
            this.addFormState = {
                ...this.addFormState,
                assignedResourceId: this._currentUserServiceResourceId
            };
        }
    }

    /**
     * @description Wire adapter handler: Assigned Resource Owner.
     */
    @wire(getRecord, {
        recordId: '$_assignedResourceOwnerLookupId',
        fields: ['ServiceResource.RelatedRecordId']
    })
    wiredAssignedResourceOwner({ data }) {
        if (!data) return;
        const srId   = data.id;
        const userId = data.fields?.RelatedRecordId?.value;
        if (srId && userId) {
            this._userIdByServiceResourceId = {
                ...this._userIdByServiceResourceId,
                [srId]: userId
            };
            this._serviceResourceByUserId = {
                ...this._serviceResourceByUserId,
                [userId]: srId
            };
        }
    }

    // Pre-populate the Repair Code name cache from server data so existing
    // labor lines can show their Name helper text without an extra round-trip.
    /**
     * @description Internal helper: Seed Repair Code Name Cache.
     */
    _seedRepairCodeNameCache(lines) {
        const next = { ...this._repairCodeNameById };
        let changed = false;
        for (const l of lines) {
            const id   = l.RepairCode__c?.value;
            const name = l.RepairCode__r?.Name?.value;
            if (id && name && next[id] !== name) {
                next[id] = name;
                changed = true;
            }
        }
        if (changed) this._repairCodeNameById = next;
    }

    // On-demand Product2.Name lookup for the Repair Code helper text.
    // `_repairCodeLookupId` is set in handleLookupChange when the user picks a
    // code we don't have cached yet; the wire fires, we cache the Name, and
    // the helper text under the picker is rendered on the next reactive pass.
    /**
     * @description Wire adapter handler: Repair Code Name.
     */
    @wire(getRecord, { recordId: '$_repairCodeLookupId', fields: ['Product2.Name'] })
    wiredRepairCodeName({ data }) {
        if (!data) return;
        const id   = data.id;
        const name = data.fields?.Name?.value;
        if (id && name && this._repairCodeNameById[id] !== name) {
            this._repairCodeNameById = {
                ...this._repairCodeNameById,
                [id]: name
            };
        }
    }

    /**
     * @description Manufacturer, Model, and Department for the selected Asset.
     */
    @wire(getRecord, {
        recordId: '$_repairDefaultAssetId',
        optionalFields: [
            'Asset.Department__c',
            'Asset.ManufacturerCalculated__c',
            'Asset.ModelCalculated__c',
            'Asset.Product2.Manufacturer__c',
            'Asset.Product2.Model__c'
        ]
    })
    wiredAssetRepairDefaults({ data, error }) {
        if (error || !data || !this._sameSalesforceId(data.id, this._repairDefaultAssetId)) return;
        const product = data.fields?.Product2?.value?.fields || {};
        const departmentId = data.fields?.Department__c?.value;
        const asset = {
            department: departmentId ? { id: departmentId, name: departmentId } : null,
            manufacturer: String(
                data.fields?.ManufacturerCalculated__c?.value
                || product.Manufacturer__c?.value
                || ''
            ).trim(),
            model: String(
                data.fields?.ModelCalculated__c?.value
                || product.Model__c?.value
                || ''
            ).trim()
        };
        if (!asset.manufacturer && !asset.model && !asset.department) return;
        this._assetDepartmentById = {
            ...this._assetDepartmentById,
            [data.id]: asset,
            [this._repairDefaultAssetId]: asset
        };
        this._applyAssetRepairDefaults(this._repairDefaultLineId, data.id, asset);
    }

    /**
     * @description Variables for the add-form serial scan. Undefined skips the query.
     */
    get assetSerialQueryVariables() {
        if (!this._assetSerialLookup || !this.woAccountId) return undefined;
        return {
            accountId: this.woAccountId,
            serialNumber: this._assetSerialLookup
        };
    }

    /**
     * @description IMS Asset matched by the serial number typed or scanned on the add form.
     */
    @wire(graphql, { query: ASSET_BY_SERIAL_QUERY, variables: '$assetSerialQueryVariables' })
    wiredScannedAsset(result) {
        const serial = this._assetSerialLookup;
        if (!serial || !result) return;
        if (result.errors?.length) {
            this.assetScanMessage = this._graphqlErrorText(result.errors);
            this._assetSerialLookup = null;
            return;
        }
        if (!result.data) return;
        const matches = (result.data.uiapi?.query?.Asset?.edges ?? [])
            .map(edge => edge.node)
            .filter(node => node?.Id);
        this._assetSerialLookup = null;
        if (!matches.length) {
            this.assetScanMessage = `No asset found for serial number ${serial}.`;
            return;
        }
        if (matches.length > 1) {
            this.assetScanMessage = `More than one asset has serial number ${serial}. Select the asset from the list.`;
            return;
        }
        this.addFormState = { ...this.addFormState, assetId: matches[0].Id };
        this.assetScanMessage = '';
        this._requestAssetRepairDefaults(null);
    }

    /**
     * @description Account asset query runs only while the multi-asset picker is open.
     */
    get accountAssetQueryVariables() {
        if (!this.showMultiAssetPicker) return undefined;
        const accountId = this.woAccountId;
        return accountId ? { accountId } : undefined;
    }

    get queryVariables() {
        return { workOrderId: this.recordId };
    }

    /**
     * @description Current User Query Variables.
     */
    get currentUserQueryVariables() {
        return { userId: USER_ID };
    }

    /**
     * @description Sr By Users Variables.
     */
    get srByUsersVariables() {
        if (!this._ownerUserIdsForLookup.length) return undefined;
        return { userIds: this._ownerUserIdsForLookup };
    }

    /**
     * @description Expense Query Variables.
     */
    get expenseQueryVariables() {
        return this.recordId ? { workOrderId: this.recordId } : undefined;
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    /**
     * @description Lifecycle hook invoked when the component is inserted into the DOM.
     */
    connectedCallback() {
        window.addEventListener('online',  this._onlineHandler);
        window.addEventListener('offline', this._offlineHandler);
    }

    /**
     * @description Lifecycle hook invoked when the component is removed from the DOM.
     */
    disconnectedCallback() {
        window.removeEventListener('online',  this._onlineHandler);
        window.removeEventListener('offline', this._offlineHandler);
    }

    // ── Computed state ────────────────────────────────────────────────────────
    /**
     * @description Is Loading.
     */
    get isLoading() {
        const woLoading = !this.graphqlResult?.data && !this.graphqlResult?.errors;
        const gqlExpDone = !this.recordId
            || this.expensesGraphqlResult?.data
            || this.expensesGraphqlResult?.errors;
        const rlExpDone  = !this.recordId
            || this.expensesListResult?.data
            || this.expensesListResult?.error;
        const expLoading = !!this.recordId && !(gqlExpDone && rlExpDone);
        return woLoading || expLoading;
    }

    /**
     * @description Has Error.
     */
    get hasError()     { return !!this.graphqlResult?.errors; }
    /**
     * @description Error Message.
     */
    get errorMessage() { return JSON.stringify(this.graphqlResult?.errors); }
    /**
     * @description Wo Status.
     */
    get woStatus()     { return this._workOrder?.Status?.value ?? ''; }
    /**
     * @description Wo Account Name.
     */
    get woAccountId()  { return this._workOrder?.AccountId?.value ?? null; }
    /**
     * @description Account Id used to load departments for Do Not Use (P0) lines.
     */
    get repairCenterAccountId() {
        return this.woAccountId || undefined;
    }
    /**
     * @description Insulation / Powder Coating options for Do Not Use (P0) lines.
     */
    get insulationPowderCoatingOptions() {
        return this._insulationPicklistOptions.length
            ? this._insulationPicklistOptions
            : INSULATION_POWDER_COATING_OPTIONS;
    }
    /**
     * @description True when the single-line add form should collect repair-center details.
     */
    get addFormShowRepairCenterFields() {
        return this.addFormState?.inspectionOutcome === DO_NOT_USE_P0;
    }
    /**
     * @description True when Additional Services is checked on the add form.
     */
    get addFormShowInsulation() {
        return this.addFormShowRepairCenterFields && !!this.addFormState?.additionalServices;
    }
    /**
     * @description Pictures chosen on a new line before it is saved.
     */
    get addFormPictureItems() {
        return (this.addFormState?.pictures || []).map(picture => ({
            id: picture.contentDocumentId,
            name: picture.name
        }));
    }
    /**
     * @description Camera barcode scan is available on this device.
     */
    get showBarcodeScanButton() {
        try {
            const scanner = getBarcodeScanner();
            return !!(scanner && typeof scanner.isAvailable === 'function' && scanner.isAvailable());
        } catch (e) {
            return false;
        }
    }
    /** @description Work Type on the parent Work Order, used as the Product Serviced default. */
    get woWorkTypeId() { return this._workOrder?.WorkTypeId?.value ?? null; }
    get woAccountName(){ return this._workOrder?.Account?.Name?.value ?? ''; }
    /**
     * @description Wo Asset Name.
     */
    get woAssetName() {
        const asset  = this._workOrder?.Asset;
        const serial = asset?.SerialNumber?.value ?? '';
        const name   = asset?.Name?.value ?? '';
        return serial || name;
    }

    /**
     * @description Wo Type.
     */
    get woType()       { return this._workOrder?.WorkOrderType__c?.value ?? ''; }
    /**
     * @description Wo Number.
     */
    get woNumber()     { return this._workOrder?.WorkOrderNumber?.value ?? ''; }
    /**
     * @description Has Pending Changes.
     */
    get hasPendingChanges() {
        return Object.keys(this._pendingEdits).length   > 0 ||
               Object.keys(this._pendingDeletes).length > 0 ||
               this._pendingAdds.length > 0 ||
               this._hasStagedMobilePictures();
    }

    /**
     * @description Save All Disabled.
     */
    get saveAllDisabled() {
        return !this.hasPendingChanges || this._saving;
    }

    /**
     * @description Cancel Disabled.
     */
    get cancelDisabled() {
        return this._saving;
    }

    // ── Tabs (data-driven from TAB_DEFS) ──────────────────────────────────────
    /**
     * @description Tabs.
     */
    get tabs() {
        void this.mobilePictureVersion;
        return TAB_DEFS
            .filter(def => !HIDDEN_TAB_KEYS.has(def.key))
            .map(def => ({
            key:         def.key,
            label:       def.label,
            addLabel:    def.addLabel,
            canAdd:      def.canAdd,
            schema:      def.schema,
            isActive:    this.activeTab === def.key,
            showAddForm: !!this.showAddForm[def.key],
            addError:    this.addErrors[def.key] ?? '',
            lines:       this._buildLinesFor(def)
        }));
    }

    /**
     * @description Active Tab Model.
     */
    get activeTabModel() {
        return this.tabs.find(t => t.isActive) ?? this.tabs[0];
    }

    /**
     * @description GW-375 - Mobile Device Pictures saved on this work order.
     */
    get headerPictures() {
        void this.mobilePictureVersion;
        const key = this._pictureRecordKey(this._headerPictureRecordId());
        return (this._mobilePicturesByRecordId[key] || []).map(picture => this._pictureView(picture));
    }

    /**
     * @description GW-375 - True when the work order header has a Mobile Device Picture.
     */
    get hasHeaderPictures() {
        return this.headerPictures.length > 0;
    }

    /**
     * @description GW-375 - Live count of header Mobile Device Pictures.
     */
    get headerPictureCountLabel() {
        return this._pictureCountLabel(this.headerPictures.length);
    }

    /**
     * @description GW-6437 - Preview for the optional comment capture dialog.
     */
    get pictureCommentCapturePreviewUrl() {
        return this._pendingMobilePictureCapture?.localPicture?.previewUrl || '';
    }

    /**
     * @description GW-6437 - True when the review dialog can persist comment edits to Salesforce.
     */
    get reviewPictureCanSaveComment() {
        return !!(this.reviewPicture?.key);
    }

    /**
     * @description GW-375 - Pictures chosen on the add form before the line exists.
     */
    get addFormMobilePictures() {
        void this.mobilePictureVersion;
        return (this.addFormState?.mobilePictures || []).map(picture => this._pictureView(picture));
    }

    /**
     * @description GW-375 - True when the add form has a staged Mobile Device Picture.
     */
    get hasAddFormMobilePictures() {
        return this.addFormMobilePictures.length > 0;
    }

    /**
     * @description GW-375 - Live count of add-form Mobile Device Pictures.
     */
    get addFormMobilePictureCountLabel() {
        return this._pictureCountLabel(this.addFormMobilePictures.length);
    }

    /**
     * @description Active Tab Search Term.
     */
    get activeTabSearchTerm() {
        return this.tabSearchTerms[this.activeTab] ?? '';
    }

    /**
     * @description Active Tab Search Placeholder.
     */
    get activeTabSearchPlaceholder() {
        const schema = this.activeTabModel?.schema;
        if (schema === 'time')    return 'Search line type, resource, or dates…';
        if (schema === 'travel')  return 'Search resource or dates…';
        if (schema === 'labor')   return 'Search resource, asset, or repair code…';
        if (schema === 'productServiced') return 'Search asset, work type, or outcome…';
        if (schema === 'expense') return 'Search type, date, or amount…';
        return 'Search lines…';
    }

    /**
     * @description Active Tab Has No Search Results.
     */
    get activeTabHasNoSearchResults() {
        const term = (this.activeTabSearchTerm ?? '').trim();
        return !!term && (this.activeTabModel?.lines?.length ?? 0) === 0;
    }

    // Convenience flags — LWC templates can't compare strings directly.
    /**
     * @description Is Active Tab Time.
     */
    get isActiveTabTime()      { return this.activeTabModel?.schema === 'time'; }
    /**
     * @description Is Active Tab Travel.
     */
    get isActiveTabTravel()    { return this.activeTabModel?.schema === 'travel'; }
    /**
     * @description Is Active Tab Labor.
     */
    get isActiveTabLabor()     { return this.activeTabModel?.schema === 'labor'; }
    /**
     * @description Is Active Tab Product Serviced.
     */
    get isActiveTabProductServiced() { return this.activeTabModel?.schema === 'productServiced'; }
    /**
     * @description Is Active Tab Expense.
     */
    get isActiveTabExpense()   { return this.activeTabModel?.schema === 'expense'; }
    /**
     * @description Expense Type Options.
     */
    get expenseTypeOptions() { return EXPENSE_TYPE_OPTIONS; }
    /**
     * @description Override Code picklist options.
     */
    get overrideCodeOptions() { return this.overrideCodePicklistOptions; }
    /**
     * @description True when the add-form Billable Amount is locked to Amount.
     */
    get isAddBillableAmountReadOnly() {
        return !this._isTruthyFlag(this.addFormState.overrideBillableAmount);
    }
    /**
     * @description True when Override Code is required on the add form.
     */
    get isAddOverrideCodeRequired() {
        return this._isTruthyFlag(this.addFormState.overrideBillableAmount);
    }
    /**
     * @description Formatted Billable Amount for the locked add-form display.
     */
    get formattedAddBillableAmount() {
        return this._fmtBillableAmount(this.addFormState.billableAmount);
    }
    /**
     * @description Inspection Outcome Options.
     */
    get inspectionOutcomeOptions() { return INSPECTION_OUTCOME_OPTIONS; }
    /**
     * @description Remounts the add-form Make field after an asset default is applied.
     */
    get addFormMakeKey() {
        return `add-make-${this.repairFieldEpoch}`;
    }
    /**
     * @description Remounts the add-form Model field after an asset default is applied.
     */
    get addFormModelKey() {
        return `add-model-${this.repairFieldEpoch}`;
    }
    /**
     * @description Time Line Type Options.
     */
    get timeLineTypeOptions() { return TIME_LINE_TYPE_OPTIONS; }
    /**
     * @description Billing Type picklist options.
     */
    get billingTypeOptions() {
        return this.billingTypePicklistOptions.length
            ? this.billingTypePicklistOptions
            : BILLING_TYPE_OPTIONS;
    }
    /**
     * @description Add Form Is Travel Line.
     */
    get addFormIsTravelLine() { return this.addFormState.lineType === 'Travel'; }
    /**
     * @description Add Form Is Labor Line.
     */
    get addFormIsLaborLine() { return this.addFormState.lineType === 'Labor'; }
    /**
     * @description Add Form Has Time Line Type.
     */
    get addFormHasTimeLineType() { return !!this.addFormState.lineType; }
    /**
     * @description Add Form Duration Label.
     */
    get addFormDurationLabel() {
        return this._fmtDurationLabel(
            this._computeDurationHours(this.addFormState.startDate, this.addFormState.endDate)
        );
    }

    // ── Picker configs (filter + displayInfo + matchingInfo) ─────────────────

    // AssignedResource → ServiceResource, only active records.
    /**
     * @description Resource Picker Filter.
     */
    get resourcePickerFilter() {
        return {
            criteria: [
                { fieldPath: 'IsActive', operator: 'eq', value: true }
            ]
        };
    }

    /**
     * @description Resource Picker Display Info.
     */
    get resourcePickerDisplayInfo() {
        return { primaryField: 'Name' };
    }

    /**
     * @description Resource Picker Matching Info.
     */
    get resourcePickerMatchingInfo() {
        return { primaryField: { fieldPath: 'Name' } };
    }

    /**
     * @description Product Serviced assets limited to IMS Asset records on the work order account.
     */
    get productServicedAssetFilter() {
        return {
            criteria: [
                { fieldPath: 'AccountId', operator: 'eq', value: this.woAccountId },
                { fieldPath: 'RecordType.DeveloperName', operator: 'eq', value: 'IMS_Asset' }
            ]
        };
    }

    /**
     * @description Multi-asset picker is open on the Product Serviced tab.
     */
    get showProductServicedMultiAsset() {
        return this.showMultiAssetPicker && this.isActiveTabProductServiced;
    }

    /**
     * @description The single-line Add button stays hidden while the asset table is open.
     */
    get showTabAddButton() {
        return !this.showProductServicedMultiAsset;
    }

    /**
     * @description Account IMS assets that do not already have a line on this work order.
     */
    get accountInspectAssets() {
        const edges = this.accountAssetsGraphqlResult?.data?.uiapi?.query?.Asset?.edges ?? [];
        const linked = this._linkedAssetIds();
        return edges
            .map(edge => edge.node)
            .filter(node => node?.Id && !linked.has(node.Id))
            .map(node => {
                const product = node.Product2 || {};
                const serialNumber = node.SerialNumber?.value ?? '';
                const lastInspectionDate = node.LastInspectionDate__c?.value || '';
                const lastServicedDate = node.LastServicedDate__c?.value || '';
                const selected = !!this.selectedMultiAssetIds[node.Id];
                const productLine = product.ProductLine__c?.value ?? '';
                const subProductLine = product.SubProductLine__c?.value ?? '';
                const deviceType = product.DeviceType__c?.value ?? '';
                const manufacturer = product.Manufacturer__c?.value ?? '';
                const model = product.Model__c?.value ?? '';
                return {
                    id: node.Id,
                    rowKey: `${node.Id}-${selected ? '1' : '0'}`,
                    name: node.Name?.value || 'Asset',
                    serialNumber,
                    lastInspectionDate,
                    lastServicedDate,
                    productLine,
                    subProductLine,
                    deviceType,
                    manufacturer,
                    model,
                    nameLine: this._fmtInspectAssetName(node.Name?.value || 'Asset', serialNumber),
                    dateLine: this._fmtInspectAssetDates(lastInspectionDate, lastServicedDate),
                    selected
                };
            });
    }

    /**
     * @description Account assets narrowed by the product information filters.
     */
    get availableInspectAssets() {
        return this.accountInspectAssets
            .filter(asset => this._assetMatchesFilters(asset))
            .sort((left, right) => {
                const leftDate = left.lastServicedDate || '';
                const rightDate = right.lastServicedDate || '';
                if (leftDate !== rightDate) {
                    return leftDate < rightDate ? -1 : 1;
                }
                return (left.name || '').localeCompare(right.name || '');
            });
    }

    /**
     * @description True when product filters hide every available asset.
     */
    get multiAssetFilterEmpty() {
        return !this.multiAssetStatusMessage
            && !this.multiAssetLoading
            && this.accountInspectAssets.length > 0
            && this.availableInspectAssets.length === 0;
    }

    /**
     * @description Product Line choices from the loaded assets.
     */
    get productLineFilterOptions() {
        return this._assetFilterOptions('productLine');
    }

    /**
     * @description Sub Product Line choices from the loaded assets.
     */
    get subProductLineFilterOptions() {
        return this._assetFilterOptions('subProductLine');
    }

    /**
     * @description Device Type choices from the loaded assets.
     */
    get deviceTypeFilterOptions() {
        return this._assetFilterOptions('deviceType');
    }

    /**
     * @description Manufacturer choices from the loaded assets.
     */
    get manufacturerFilterOptions() {
        return this._assetFilterOptions('manufacturer');
    }

    /**
     * @description Model choices from the loaded assets.
     */
    get modelFilterOptions() {
        return this._assetFilterOptions('model');
    }

    /**
     * @description Status text for the multi-asset picker when the list cannot be shown.
     */
    get multiAssetStatusMessage() {
        if (this.productServicedRecordTypeMissing) {
            return 'The Product Serviced record type was not found. Ask an administrator to check the Work Order Line Item record types, then try again.';
        }
        if (!this.woAccountId) {
            return 'This Work Order has no Account, so Assets cannot be listed.';
        }
        if (this.accountAssetsGraphqlResult?.errors) {
            return this._graphqlErrorText(this.accountAssetsGraphqlResult.errors);
        }
        if (this.multiAssetLoading) {
            return '';
        }
        if (!this.accountInspectAssets.length) {
            return 'No IMS Assets are available to link. IMS Assets that already have a Work Order Line Item on this Work Order are not shown.';
        }
        return '';
    }

    /**
     * @description True while the account asset query is in flight.
     */
    get multiAssetLoading() {
        if (!this.woAccountId || this.productServicedRecordTypeMissing) {
            return false;
        }
        const result = this.accountAssetsGraphqlResult;
        return !result?.data && !result?.errors;
    }

    /**
     * @description Product Serviced record type lookup finished without an Id.
     */
    get productServicedRecordTypeMissing() {
        return this._productServicedRecordTypeWireDone
            && this._woliObjectInfoDone
            && !this._productServicedRecordTypeId;
    }

    /**
     * @description Link Assets stays available only when assets can be selected.
     */
    get multiAssetCanLink() {
        return !this.multiAssetStatusMessage && !this.multiAssetLoading && this.accountInspectAssets.length > 0;
    }

    // Asset picker shows SerialNumber first, with Name as a secondary match.
    /**
     * @description Asset Picker Display Info.
     */
    get assetPickerDisplayInfo() {
        return { primaryField: 'SerialNumber', additionalFields: ['Name'] };
    }

    /**
     * @description Asset Picker Matching Info.
     */
    get assetPickerMatchingInfo() {
        return {
            primaryField: { fieldPath: 'SerialNumber' },
            additionalFields: [{ fieldPath: 'Name' }]
        };
    }

    // Repair Code → Product2 with Service Product Category = Service Code.
    /**
     * @description Repair Code Picker Filter.
     */
    get repairCodePickerFilter() {
        return {
            criteria: [
                { fieldPath: 'IsActive', operator: 'eq', value: true },
                {
                    fieldPath: PRODUCT2_PRODUCT_TYPE.fieldApiName,
                    operator: 'eq',
                    value: SERVICE_CODE_PRODUCT_TYPE
                }
            ],
            filterLogic: '1 AND 2'
        };
    }

    /**
     * @description Repair Code Picker Display Info.
     */
    get repairCodePickerDisplayInfo() {
        return { primaryField: 'ProductCode', additionalFields: ['Name'] };
    }

    /**
     * @description Repair Code Picker Matching Info.
     */
    get repairCodePickerMatchingInfo() {
        return {
            primaryField: { fieldPath: 'ProductCode' },
            additionalFields: [{ fieldPath: 'Name' }]
        };
    }

    /**
     * @description Internal helper: Build Lines For.
     */
    _buildLinesFor(def) {
        if (def.schema === 'expense') {
            return this._buildExpenseLinesFor(def);
        }
        if (def.schema === 'time') {
            return this._buildTimeLinesFor(def);
        }

        // Categorized tab → exact match. Other tab → anything not in the known set
        // (covers null/blank as well as any future picklist values not yet in TAB_DEFS).
        const matches = def.type
            ? l => l.LineType__c?.value === def.type
            : l => !KNOWN_TYPES.has(l.LineType__c?.value);

        const showLineType   = !def.type;
        const buildExisting  = this._modelBuilderForSchema(def.schema, false);
        const buildAdd       = this._addModelBuilderForSchema(def.schema);

        const existing = this._serverLines
            .filter(l => !this._pendingDeletes[l.Id])
            .filter(matches)
            .map(l => {
                const edit  = this._pendingEdits[l.Id];
                const state = this.editStateMap[l.Id] ?? {};
                return buildExisting.call(this, l, edit, state, showLineType);
            });

        // Pending adds only attach to a categorized tab (Other can't add).
        const adds = def.type
            ? this._pendingAdds
                .filter(a => a._lineType === def.type)
                .map(a => {
                    const state = this.editStateMap[a._tempId] ?? {};
                    return buildAdd.call(this, a, state);
                })
            : [];

        // Time-based schemas (travel/labor/asset_time): sort chronologically by
        // StartDate (nulls last), then LineItemNumber.
        // Expense: sort by TransactionDate (nulls last), then ExpenseType.
        // Generic: leave in natural (LineItemNumber) order.
        const merged = [...existing, ...adds];
        if (def.schema === 'travel' || def.schema === 'labor' || def.schema === 'asset_time') {
            merged.sort((a, b) => {
                const aMs = a.startDateMs ?? Number.POSITIVE_INFINITY;
                const bMs = b.startDateMs ?? Number.POSITIVE_INFINITY;
                if (aMs !== bMs) return aMs - bMs;
                return (a.lineNumber || '').localeCompare(b.lineNumber || '');
            });
        }
        return this._filterLinesBySearch(merged, def.key);
    }

    /**
     * @description Internal helper: Build Time Lines For.
     */
    _buildTimeLinesFor(def) {
        const existing = this._serverLines
            .filter(l => !this._pendingDeletes[l.Id])
            .filter(l => TIME_LINE_TYPES.has(l.LineType__c?.value))
            .map(l => {
                const edit     = this._pendingEdits[l.Id];
                const state    = this.editStateMap[l.Id] ?? {};
                const lineType = edit?.lineType ?? l.LineType__c?.value;
                const schema   = LINE_TYPE_TO_SCHEMA[lineType] ?? 'travel';
                const buildExisting = this._modelBuilderForSchema(schema);
                return buildExisting.call(this, l, edit, state, false);
            });

        const adds = this._pendingAdds
            .filter(a => a._schema === 'travel' || a._schema === 'labor')
            .map(a => {
                const state  = this.editStateMap[a._tempId] ?? {};
                const schema = a._schema === 'labor' || a._lineType === 'Labor' ? 'labor' : 'travel';
                const buildAdd = this._addModelBuilderForSchema(schema);
                return buildAdd.call(this, a, state);
            });

        const merged = [...existing, ...adds];
        merged.sort((a, b) => {
            const aMs = a.startDateMs ?? Number.POSITIVE_INFINITY;
            const bMs = b.startDateMs ?? Number.POSITIVE_INFINITY;
            if (aMs !== bMs) return aMs - bMs;
            return (a.lineNumber || '').localeCompare(b.lineNumber || '');
        });
        return this._filterLinesBySearch(merged, def.key);
    }

    /**
     * @description Internal helper: Build Expense Lines For.
     */
    _buildExpenseLinesFor(def) {
        const existing = this._serverExpenses
            .filter(e => !this._pendingDeletes[e.Id])
            .map(e => {
                const edit  = this._pendingEdits[e.Id];
                const state = this.editStateMap[e.Id] ?? {};
                return this._buildExpenseLineModel(e, edit, state, false);
            });

        const adds = this._pendingAdds
            .filter(a => a._schema === 'expense')
            .map(a => {
                const state = this.editStateMap[a._tempId] ?? {};
                return this._buildExpenseAddModel(a, state);
            });

        const merged = [...existing, ...adds];
        merged.sort((a, b) => {
            const aMs = a.transactionDateMs ?? Number.POSITIVE_INFINITY;
            const bMs = b.transactionDateMs ?? Number.POSITIVE_INFINITY;
            if (aMs !== bMs) return aMs - bMs;
            const aT = (a.expenseType || '\uffff');
            const bT = (b.expenseType || '\uffff');
            if (aT !== bT) return aT.localeCompare(bT);
            return (a.Id || '').localeCompare(b.Id || '');
        });
        return this._filterLinesBySearch(merged, def.key);
    }

    /**
     * @description Internal helper: Filter Lines By Search.
     */
    _filterLinesBySearch(lines, tabKey) {
        const term = (this.tabSearchTerms[tabKey] ?? '').trim().toLowerCase();
        const visible = !term ? lines : lines.filter(line => this._lineMatchesSearch(line, term));
        return visible.map(line => ({
            ...line,
            cardClass: line.schema === 'productServiced'
                ? this._productServicedCardClass(line)
                : 'woli-card'
        }));
    }

    /**
     * @description Internal helper: Line Matches Search.
     */
    _lineMatchesSearch(line, term) {
        const haystack = [
            line.title,
            line.metaLine,
            line.lineNumber,
            line.lineTypeLabel,
            line.assignedResourceName,
            line.expenseType,
            line.overrideCode,
            line.transactionDate,
            line.amount,
            line.billableAmount,
            line.assetSerialNumber,
            line.repairCodeProductCode,
            line.startDate,
            line.endDate,
            line.lineType,
            line.billingType
        ].filter(v => v != null && v !== '')
         .join(' ')
         .toLowerCase();
        return haystack.includes(term);
    }

    /**
     * @description Internal helper: Model Builder For Schema.
     */
    _modelBuilderForSchema(schema) {
        if (schema === 'travel')     return this._buildTravelLineModel;
        if (schema === 'labor')      return this._buildLaborLineModel;
        if (schema === 'productServiced') return this._buildProductServicedLineModel;
        if (schema === 'expense')    return this._buildExpenseLineModel;
        if (schema === 'asset_time') return this._buildAssetTimeLineModel;
        return this._buildGenericLineModel;
    }

    /**
     * @description Internal helper: Add Model Builder For Schema.
     */
    _addModelBuilderForSchema(schema) {
        if (schema === 'travel')     return this._buildTravelAddModel;
        if (schema === 'labor')      return this._buildLaborAddModel;
        if (schema === 'productServiced') return this._buildProductServicedAddModel;
        if (schema === 'expense')    return this._buildExpenseAddModel;
        if (schema === 'asset_time') return this._buildAssetTimeAddModel;
        return this._buildGenericAddModel;
    }

    /**
     * @description Internal helper: Build Generic Line Model.
     */
    _buildGenericLineModel(l, edit, state, showLineType) {
        const lineType    = l.LineType__c?.value ?? '';
        const description = edit?.desc      ?? l.Description?.value ?? '';
        const duration    = edit?.duration  ?? l.Duration?.value    ?? 0;
        const unitPrice   = edit?.unitPrice ?? l.UnitPrice?.value   ?? 0;
        return {
            Id:               l.Id,
            lineNumber:       l.LineItemNumber?.value ?? '',
            schema:           'generic',
            isTravelSchema:   false,
            isLaborSchema:    false,
            isExpenseSchema:  false,
            isAssetTimeSchema:false,
            // Card display
            title:            description || '(no description)',
            metaLine:         `${duration} hrs · $${unitPrice}`,
            lineType,
            lineTypeLabel:    lineType || 'No Type',
            showLineType,
            // Generic fields
            description,
            duration,
            unitPrice,
            // Edit state
            isEditing:        state.isEditing ?? false,
            editDesc:         state.desc      ?? edit?.desc      ?? l.Description?.value ?? '',
            editDuration:     state.duration  ?? edit?.duration  ?? l.Duration?.value    ?? 0,
            editUnitPrice:    state.unitPrice ?? edit?.unitPrice ?? l.UnitPrice?.value   ?? 0,
            editError:        this.editErrors[l.Id] ?? '',
            isDirty:          !!edit,
            isNew:            false
        };
    }

    /**
     * @description Internal helper: Build Generic Add Model.
     */
    _buildGenericAddModel(a, state) {
        const description = state.isEditing ? (state.desc ?? a.desc) : a.desc;
        const duration    = state.isEditing ? (state.duration  ?? a.duration)  : a.duration;
        const unitPrice   = state.isEditing ? (state.unitPrice ?? a.unitPrice) : a.unitPrice;
        return {
            Id:               a._tempId,
            lineNumber:       '',
            schema:           'generic',
            isTravelSchema:   false,
            isLaborSchema:    false,
            isExpenseSchema:  false,
            isAssetTimeSchema:false,
            title:            description || '(no description)',
            metaLine:         `${duration} hrs · $${unitPrice}`,
            lineType:         a._lineType,
            lineTypeLabel:    a._lineType,
            showLineType:     false,
            description,
            duration,
            unitPrice,
            isEditing:        state.isEditing ?? false,
            editDesc:         state.desc      ?? a.desc,
            editDuration:     state.duration  ?? a.duration,
            editUnitPrice:    state.unitPrice ?? a.unitPrice,
            editError:        this.editErrors[a._tempId] ?? '',
            isDirty:          false,
            isNew:            true
        };
    }

    /**
     * @description Internal helper: Build Travel Line Model.
     */
    _buildTravelLineModel(l, edit, state, showLineType) {
        const lineType        = edit?.lineType ?? l.LineType__c?.value ?? 'Travel';
        const assignedResId   = edit?.assignedResourceId ?? l.AssignedResource__c?.value ?? null;
        const assignedResName = l.AssignedResource__r?.Name?.value ?? '';
        const workTypeId      = edit?.workTypeId ?? l.WorkTypeId?.value ?? null;
        const startDate       = edit?.startDate ?? l.StartDate?.value ?? '';
        const endDate         = edit?.endDate   ?? l.EndDate?.value   ?? '';
        const durationHours   = this._computeDurationHours(startDate, endDate) ?? l.Duration?.value ?? null;
        const effectiveLineType = edit?.lineType ?? lineType;
        const billingType     = this._resolveBillingType(edit, state, l.BillingType__c?.value);
        return {
            Id:                  l.Id,
            lineNumber:          l.LineItemNumber?.value ?? '',
            schema:              'travel',
            isTravelSchema:      true,
            isLaborSchema:       false,
            isTimeSchema:        true,
            isExpenseSchema:     false,
            isAssetTimeSchema:   false,
            // Card display
            title:               assignedResName || 'Unassigned',
            metaLine:            this._fmtTravelMeta(startDate, endDate, billingType),
            lineType:            effectiveLineType,
            lineTypeLabel:       effectiveLineType || 'No Type',
            showLineType,
            isTravelLine:        effectiveLineType === 'Travel',
            isLaborLine:         effectiveLineType === 'Labor',
            hasTimeLineType:     effectiveLineType === 'Travel' || effectiveLineType === 'Labor',
            // Travel fields
            assignedResourceId:  assignedResId,
            assignedResourceName:assignedResName,
            workTypeId,
            startDate,
            endDate,
            startDateMs:         this._toMs(startDate),
            durationHours,
            billingType,
            // Edit state
            isEditing:           state.isEditing ?? false,
            editLineType:        edit?.lineType ?? lineType,
            editWorkTypeId:      state.workTypeId ?? edit?.workTypeId ?? l.WorkTypeId?.value ?? null,
            editAssignedResId:   this._resolveAssignedResourceId(
                state.assignedResourceId, edit?.assignedResourceId, l.AssignedResource__c?.value
            ),
            editStartDate:       state.startDate ?? edit?.startDate ?? l.StartDate?.value ?? '',
            editEndDate:         state.endDate   ?? edit?.endDate   ?? l.EndDate?.value   ?? '',
            editDurationLabel:   this._editDurationLabel(state, edit, startDate, endDate, l.Duration?.value),
            editBillingType:     billingType,
            editError:           this.editErrors[l.Id] ?? '',
            isDirty:             !!edit,
            isNew:               false
        };
    }

    /**
     * @description Internal helper: Build Travel Add Model.
     */
    _buildTravelAddModel(a, state) {
        const assignedResId = this._resolveAssignedResourceId(
            state.isEditing ? state.assignedResourceId : null,
            a.assignedResourceId
        );
        const workTypeId    = state.isEditing ? (state.workTypeId ?? a.workTypeId) : a.workTypeId;
        const startDate     = state.isEditing ? (state.startDate ?? a.startDate) : a.startDate;
        const endDate       = state.isEditing ? (state.endDate   ?? a.endDate)   : a.endDate;
        const durationHours = this._computeDurationHours(startDate, endDate);
        const lineType      = a._lineType || a.lineType || 'Travel';
        const billingType   = this._resolveBillingType(a, state);
        // For unsaved adds we don't have the resolved Name yet; show a placeholder.
        // (After save, the GraphQL refresh will populate AssignedResource__r.Name.)
        const titleName     = a.assignedResourceName
            || this._assignedResourceNameForId(assignedResId)
            || 'Assigned Resource pending…';
        return {
            Id:                  a._tempId,
            lineNumber:          '',
            schema:              'travel',
            isTravelSchema:      true,
            isLaborSchema:       false,
            isTimeSchema:        true,
            isExpenseSchema:     false,
            isAssetTimeSchema:   false,
            title:               assignedResId ? titleName : 'Unassigned',
            metaLine:            this._fmtTravelMeta(startDate, endDate, billingType),
            lineType,
            lineTypeLabel:       lineType,
            showLineType:        false,
            isTravelLine:        lineType === 'Travel',
            isLaborLine:         lineType === 'Labor',
            hasTimeLineType:     lineType === 'Travel' || lineType === 'Labor',
            assignedResourceId:  assignedResId,
            assignedResourceName:titleName,
            workTypeId,
            startDate,
            endDate,
            startDateMs:         this._toMs(startDate),
            durationHours,
            billingType,
            isEditing:           state.isEditing ?? false,
            editLineType:        lineType,
            editWorkTypeId:      state.workTypeId ?? a.workTypeId ?? null,
            editAssignedResId:   this._resolveAssignedResourceId(
                state.assignedResourceId, a.assignedResourceId
            ),
            editStartDate:       state.startDate ?? a.startDate ?? '',
            editEndDate:         state.endDate   ?? a.endDate   ?? '',
            editDurationLabel:   this._editDurationLabel(state, null, startDate, endDate, durationHours),
            editBillingType:     billingType,
            editError:           this.editErrors[a._tempId] ?? '',
            isDirty:             false,
            isNew:               true
        };
    }

    /**
     * @description Internal helper: Build Labor Line Model.
     */
    _buildLaborLineModel(l, edit, state, showLineType) {
        const lineType         = edit?.lineType ?? l.LineType__c?.value ?? 'Labor';
        const assignedResId    = edit?.assignedResourceId ?? l.AssignedResource__c?.value ?? null;
        const assignedResName  = l.AssignedResource__r?.Name?.value ?? '';
        const workTypeId       = edit?.workTypeId ?? l.WorkTypeId?.value ?? null;
        const assetId          = edit?.assetId ?? l.AssetId?.value ?? null;
        const assetSerial      = l.Asset?.SerialNumber?.value ?? '';
        const repairCodeId     = edit?.repairCodeId ?? l.RepairCode__c?.value ?? null;
        const repairCodeStr    = l.RepairCode__r?.ProductCode?.value ?? '';
        const editRepairCodeId = state.repairCodeId ?? edit?.repairCodeId ?? l.RepairCode__c?.value ?? null;
        const editRepairCodeName = this._repairCodeNameById[editRepairCodeId] ?? '';
        const startDate        = edit?.startDate ?? l.StartDate?.value ?? '';
        const endDate          = edit?.endDate   ?? l.EndDate?.value   ?? '';
        const inspectionOutcome = edit?.inspectionOutcome ?? l.InspectionOutcome__c?.value ?? '';
        const durationHours    = this._computeDurationHours(startDate, endDate) ?? l.Duration?.value ?? null;
        const effectiveLineType = edit?.lineType ?? lineType;
        const billingType      = this._resolveBillingType(edit, state, l.BillingType__c?.value);
        return {
            Id:                   l.Id,
            lineNumber:           l.LineItemNumber?.value ?? '',
            schema:               'labor',
            isTravelSchema:       false,
            isLaborSchema:        true,
            isTimeSchema:         true,
            isExpenseSchema:      false,
            isAssetTimeSchema:    false,
            // Card display
            title:                assignedResName || 'Unassigned',
            metaLine:             this._fmtLaborMeta(assetSerial, repairCodeStr, startDate, endDate, durationHours, billingType),
            lineType:             effectiveLineType,
            lineTypeLabel:        effectiveLineType || 'No Type',
            showLineType,
            isTravelLine:         effectiveLineType === 'Travel',
            isLaborLine:          effectiveLineType === 'Labor',
            hasTimeLineType:      effectiveLineType === 'Travel' || effectiveLineType === 'Labor',
            // Labor fields
            assignedResourceId:   assignedResId,
            assignedResourceName: assignedResName,
            workTypeId,
            assetId,
            assetSerialNumber:    assetSerial,
            repairCodeId,
            repairCodeProductCode:repairCodeStr,
            startDate,
            endDate,
            inspectionOutcome,
            startDateMs:          this._toMs(startDate),
            durationHours,
            billingType,
            // Edit state
            isEditing:            state.isEditing ?? false,
            editLineType:         edit?.lineType ?? lineType,
            editWorkTypeId:       state.workTypeId ?? edit?.workTypeId ?? l.WorkTypeId?.value ?? null,
            editAssignedResId:    this._resolveAssignedResourceId(
                state.assignedResourceId, edit?.assignedResourceId, l.AssignedResource__c?.value
            ),
            editAssetId:          state.assetId       ?? edit?.assetId       ?? l.AssetId?.value          ?? null,
            editRepairCodeId,
            editRepairCodeName,
            editStartDate:        state.startDate     ?? edit?.startDate     ?? l.StartDate?.value        ?? '',
            editEndDate:          state.endDate       ?? edit?.endDate       ?? l.EndDate?.value          ?? '',
            editInspectionOutcome: state.inspectionOutcome ?? edit?.inspectionOutcome ?? l.InspectionOutcome__c?.value ?? '',
            editDurationLabel:    this._editDurationLabel(state, edit, startDate, endDate, l.Duration?.value),
            editBillingType:      billingType,
            editError:            this.editErrors[l.Id] ?? '',
            isDirty:              !!edit,
            isNew:                false
        };
    }

    /**
     * @description Internal helper: Build Labor Add Model.
     */
    _buildLaborAddModel(a, state) {
        const assignedResId = this._resolveAssignedResourceId(
            state.isEditing ? state.assignedResourceId : null,
            a.assignedResourceId
        );
        const workTypeId    = state.isEditing ? (state.workTypeId ?? a.workTypeId) : a.workTypeId;
        const assetId       = state.isEditing ? (state.assetId       ?? a.assetId)       : a.assetId;
        const repairCodeId  = state.isEditing ? (state.repairCodeId  ?? a.repairCodeId)  : a.repairCodeId;
        const editRepairCodeId   = state.repairCodeId ?? a.repairCodeId ?? null;
        const editRepairCodeName = this._repairCodeNameById[editRepairCodeId] ?? '';
        const startDate     = state.isEditing ? (state.startDate     ?? a.startDate)     : a.startDate;
        const endDate       = state.isEditing ? (state.endDate       ?? a.endDate)       : a.endDate;
        const inspectionOutcome = state.isEditing ? (state.inspectionOutcome ?? a.inspectionOutcome) : a.inspectionOutcome;
        const durationHours = this._computeDurationHours(startDate, endDate);
        const lineType      = a._lineType || a.lineType || 'Labor';
        const billingType   = this._resolveBillingType(a, state);
        // Names aren't resolved until after save → placeholder for the title.
        const titleName     = a.assignedResourceName
            || this._assignedResourceNameForId(assignedResId)
            || 'Assigned Resource pending…';
        return {
            Id:                   a._tempId,
            lineNumber:           '',
            schema:               'labor',
            isTravelSchema:       false,
            isLaborSchema:        true,
            isTimeSchema:         true,
            isExpenseSchema:      false,
            isAssetTimeSchema:    false,
            title:                assignedResId ? titleName : 'Unassigned',
            metaLine:             this._fmtLaborMeta('', '', startDate, endDate, durationHours, billingType),
            lineType,
            lineTypeLabel:        lineType,
            showLineType:         false,
            isTravelLine:         lineType === 'Travel',
            isLaborLine:          lineType === 'Labor',
            hasTimeLineType:      lineType === 'Travel' || lineType === 'Labor',
            assignedResourceId:   assignedResId,
            assignedResourceName: titleName,
            workTypeId,
            assetId,
            assetSerialNumber:    '',
            repairCodeId,
            repairCodeProductCode:'',
            startDate,
            endDate,
            inspectionOutcome,
            startDateMs:          this._toMs(startDate),
            durationHours,
            billingType,
            isEditing:            state.isEditing ?? false,
            editLineType:         lineType,
            editWorkTypeId:       state.workTypeId ?? a.workTypeId ?? null,
            editAssignedResId:    this._resolveAssignedResourceId(
                state.assignedResourceId, a.assignedResourceId
            ),
            editAssetId:          state.assetId            ?? a.assetId            ?? null,
            editRepairCodeId,
            editRepairCodeName,
            editStartDate:        state.startDate          ?? a.startDate          ?? '',
            editEndDate:          state.endDate            ?? a.endDate            ?? '',
            editInspectionOutcome: state.inspectionOutcome ?? a.inspectionOutcome ?? '',
            editDurationLabel:    this._editDurationLabel(state, null, startDate, endDate, durationHours),
            editBillingType:      billingType,
            editError:            this.editErrors[a._tempId] ?? '',
            isDirty:              false,
            isNew:                true
        };
    }

    /**
     * @description Internal helper: Build Product Serviced Line Model.
     */
    _buildProductServicedLineModel(l, edit, state, showLineType) {
        const assignedResId = edit?.assignedResourceId ?? l.AssignedResource__c?.value ?? null;
        const assignedResName = l.AssignedResource__r?.Name?.value ?? '';
        const workTypeId = edit?.workTypeId ?? l.WorkTypeId?.value ?? null;
        const workTypeName = l.WorkType?.Name?.value ?? '';
        const assetId = edit?.assetId ?? l.AssetId?.value ?? null;
        const assetSerial = l.Asset?.SerialNumber?.value ?? '';
        const assetName = l.Asset?.Name?.value ?? '';
        const inspectionOutcome = state.inspectionOutcome ?? edit?.inspectionOutcome ?? l.InspectionOutcome__c?.value ?? '';
        const outcomeText = inspectionOutcome == null ? '' : String(inspectionOutcome).trim();
        const billingType = edit?.billingType
            ?? l.BillingType__c?.value
            ?? BILLING_TYPE_NON_BILLABLE;
        const title = assetSerial || assetName || 'Product Serviced';
        const savedRepair = this._repairCenterByLineId[l.Id] || {};
        const lineStatus = state.lineStatus ?? edit?.lineStatus ?? l.Status?.value ?? LINE_STATUS_NEW;
        const repairSource = {
            serialNumber: state.serialNumber ?? edit?.serialNumber ?? savedRepair.serialNumber,
            model: state.model ?? edit?.model ?? savedRepair.model,
            departmentId: state.departmentId ?? edit?.departmentId ?? savedRepair.departmentId,
            reportedProblem: state.reportedProblem ?? edit?.reportedProblem ?? savedRepair.reportedProblem,
            notInspectedReason: state.notInspectedReason ?? edit?.notInspectedReason ?? savedRepair.notInspectedReason
        };
        const isComplete = this._isProductServicedComplete({
            assetId,
            workTypeId,
            assignedResourceId: assignedResId,
            inspectionOutcome: outcomeText,
            ...repairSource
        });
        return {
            Id: l.Id,
            lineNumber: l.LineItemNumber?.value ?? '',
            schema: 'productServiced',
            isTravelSchema: false,
            isLaborSchema: false,
            isTimeSchema: false,
            isExpenseSchema: false,
            isProductServicedSchema: true,
            isAssetTimeSchema: false,
            title,
            metaLine: this._fmtProductServicedMeta(workTypeName, inspectionOutcome, assignedResName),
            lineType: LINE_TYPE_PRODUCT_SERVICED,
            lineTypeLabel: LINE_TYPE_PRODUCT_SERVICED,
            showLineType,
            assignedResourceId: assignedResId,
            assignedResourceName: assignedResName,
            workTypeId,
            workTypeName,
            assetId,
            assetSerialNumber: assetSerial,
            inspectionOutcome,
            billingType,
            requiresInspectionDetails: true,
            isEditing: state.isEditing ?? false,
            editWorkTypeId: state.workTypeId ?? edit?.workTypeId ?? l.WorkTypeId?.value ?? null,
            editAssignedResId: this._resolveAssignedResourceId(
                state.assignedResourceId, edit?.assignedResourceId, l.AssignedResource__c?.value
            ),
            editAssetId: state.assetId ?? edit?.assetId ?? l.AssetId?.value ?? null,
            editInspectionOutcome: state.inspectionOutcome ?? edit?.inspectionOutcome ?? l.InspectionOutcome__c?.value ?? '',
            editBillingType: billingType,
            editError: this.editErrors[l.Id] ?? '',
            ...this._mobilePictureModel(l.Id),
            pictureLineNumber: l.LineItemNumber?.value ?? '',
            lineStatus,
            editCanceled: lineStatus === LINE_STATUS_CANCELED,
            lineTone: this._productServicedTone(lineStatus, isComplete),
            repairMakeKey: `${l.Id}-make-${this.repairFieldEpoch}`,
            repairModelKey: `${l.Id}-model-${this.repairFieldEpoch}`,
            ...this._repairCenterView(l.Id, outcomeText, {
                serialNumber: state.serialNumber ?? edit?.serialNumber,
                model: state.model ?? edit?.model,
                departmentId: state.departmentId ?? edit?.departmentId,
                reportedProblem: state.reportedProblem ?? edit?.reportedProblem,
                notInspectedReason: state.notInspectedReason ?? edit?.notInspectedReason,
                additionalServices: state.additionalServices ?? edit?.additionalServices,
                insulationPowderCoating: state.insulationPowderCoating ?? edit?.insulationPowderCoating,
                pictures: edit?.pictures || []
            }, savedRepair),
            isDirty: !!edit,
            isNew: false
        };
    }

    /**
     * @description Internal helper: Build Product Serviced Add Model.
     */
    _buildProductServicedAddModel(a, state) {
        const assignedResId = a._bulkAssetLink
            ? (state.assignedResourceId ?? a.assignedResourceId ?? this._defaultAssignedResourceId())
            : this._resolveAssignedResourceId(
                state.isEditing ? state.assignedResourceId : null,
                a.assignedResourceId
            );
        const assignedResName = a.assignedResourceName
            || this._assignedResourceNameForId(assignedResId)
            || '';
        const workTypeId = state.isEditing
            ? (state.workTypeId ?? a.workTypeId ?? (a._bulkAssetLink ? this.woWorkTypeId : null))
            : (a.workTypeId ?? (a._bulkAssetLink ? this.woWorkTypeId : null));
        const assetId = state.isEditing ? (state.assetId ?? a.assetId) : a.assetId;
        const inspectionOutcome = state.inspectionOutcome ?? a.inspectionOutcome ?? '';
        const outcomeText = inspectionOutcome == null ? '' : String(inspectionOutcome).trim();
        const assetSerial = a.assetSerial || '';
        const assetName = a.assetName || '';
        const lineStatus = state.lineStatus ?? a.lineStatus ?? LINE_STATUS_NEW;
        const repairSource = {
            serialNumber: state.serialNumber ?? a.serialNumber,
            model: state.model ?? a.model,
            departmentId: state.departmentId ?? a.departmentId,
            reportedProblem: state.reportedProblem ?? a.reportedProblem,
            notInspectedReason: state.notInspectedReason ?? a.notInspectedReason
        };
        const isComplete = this._isProductServicedComplete({
            _bulkAssetLink: a._bulkAssetLink,
            assetId,
            workTypeId,
            assignedResourceId: assignedResId,
            inspectionOutcome: outcomeText,
            ...repairSource
        });
        return {
            Id: a._tempId,
            lineNumber: '',
            schema: 'productServiced',
            isTravelSchema: false,
            isLaborSchema: false,
            isTimeSchema: false,
            isExpenseSchema: false,
            isProductServicedSchema: true,
            isAssetTimeSchema: false,
            title: assetSerial || assetName || 'Product Serviced',
            metaLine: (a._bulkAssetLink && assetSerial && assetName)
                ? [assetName, inspectionOutcome, assignedResName].filter(Boolean).join(' · ')
                : this._fmtProductServicedMeta('', inspectionOutcome, assignedResName),
            lineType: LINE_TYPE_PRODUCT_SERVICED,
            lineTypeLabel: LINE_TYPE_PRODUCT_SERVICED,
            showLineType: false,
            assignedResourceId: assignedResId,
            assignedResourceName: assignedResName,
            workTypeId,
            assetId,
            assetSerialNumber: assetSerial,
            inspectionOutcome,
            billingType: BILLING_TYPE_NON_BILLABLE,
            requiresInspectionDetails: !a._bulkAssetLink,
            isEditing: state.isEditing ?? false,
            editWorkTypeId: state.workTypeId ?? a.workTypeId ?? (a._bulkAssetLink ? this.woWorkTypeId : null),
            editAssignedResId: a._bulkAssetLink
                ? (state.assignedResourceId ?? a.assignedResourceId ?? this._defaultAssignedResourceId())
                : assignedResId,
            editAssetId: state.assetId ?? a.assetId ?? null,
            editInspectionOutcome: state.inspectionOutcome ?? a.inspectionOutcome ?? '',
            editBillingType: BILLING_TYPE_NON_BILLABLE,
            editError: this.editErrors[a._tempId] ?? '',
            ...this._mobilePictureModel(a._tempId, a.mobilePictures),
            lineStatus,
            editCanceled: lineStatus === LINE_STATUS_CANCELED,
            lineTone: this._productServicedTone(lineStatus, isComplete),
            repairMakeKey: `${a._tempId}-make-${this.repairFieldEpoch}`,
            repairModelKey: `${a._tempId}-model-${this.repairFieldEpoch}`,
            ...this._repairCenterView(a._tempId, outcomeText, {
                serialNumber: state.serialNumber ?? a.serialNumber,
                model: state.model ?? a.model,
                departmentId: state.departmentId ?? a.departmentId,
                reportedProblem: state.reportedProblem ?? a.reportedProblem,
                notInspectedReason: state.notInspectedReason ?? a.notInspectedReason,
                additionalServices: state.additionalServices ?? a.additionalServices,
                insulationPowderCoating: state.insulationPowderCoating ?? a.insulationPowderCoating,
                pictures: a.pictures || []
            }, {}),
            isDirty: false,
            isNew: true
        };
    }

    /**
     * @description Internal helper: Build Expense Line Model.
     */
    _buildExpenseLineModel(e, edit, state, showLineType) {
        const expenseType     = edit?.expenseType     ?? e.ExpenseType?.value       ?? '';
        const transactionDate = edit?.transactionDate ?? e.TransactionDate?.value    ?? '';
        const amount          = edit?.amount          ?? e.Amount?.value            ?? 0;
        const overrideBillableAmount = this._isTruthyFlag(
            edit?.overrideBillableAmount ?? e.OverrideBillableAmount__c?.value
        );
        const billableAmount = overrideBillableAmount
            ? (edit?.billableAmount ?? e.BillableAmount__c?.value ?? amount)
            : (edit?.billableAmount ?? amount);
        const overrideCode = edit?.overrideCode ?? e.OverrideCode__c?.value ?? '';
        return {
            Id:                  e.Id,
            lineNumber:          '',
            schema:              'expense',
            isTravelSchema:      false,
            isLaborSchema:       false,
            isExpenseSchema:     true,
            isAssetTimeSchema:   false,
            title:               expenseType || 'Unspecified Expense',
            metaLine:            this._fmtExpenseMeta(transactionDate, amount),
            lineType:            'Expense',
            lineTypeLabel:       'Expense',
            showLineType,
            expenseType,
            overrideCode,
            transactionDate,
            transactionDateMs:   this._toMs(transactionDate),
            amount,
            billableAmount,
            isEditing:           state.isEditing ?? false,
            editExpenseType:     state.expenseType     ?? edit?.expenseType     ?? e.ExpenseType?.value    ?? '',
            editTransactionDate: state.transactionDate ?? edit?.transactionDate ?? e.TransactionDate?.value ?? '',
            editAmount:          state.amount          ?? edit?.amount          ?? e.Amount?.value         ?? 0,
            editOverrideCode:   state.overrideCode   ?? overrideCode,
            editBillableAmount:  state.billableAmount  ?? billableAmount,
            editBillableAmountDisplay: this._fmtBillableAmount(
                state.billableAmount ?? billableAmount
            ),
            editOverrideBillableAmount: this._isTruthyFlag(
                state.overrideBillableAmount ?? overrideBillableAmount
            ),
            isBillableAmountReadOnly: !this._isTruthyFlag(
                state.overrideBillableAmount ?? overrideBillableAmount
            ),
            isOverrideCodeRequired: this._isTruthyFlag(
                state.overrideBillableAmount ?? overrideBillableAmount
            ),
            editError:           this.editErrors[e.Id] ?? '',
            isDirty:             !!edit,
            isNew:               false
        };
    }

    /**
     * @description Internal helper: Build Expense Add Model.
     */
    _buildExpenseAddModel(a, state) {
        const expenseType     = state.isEditing ? (state.expenseType     ?? a.expenseType)     : a.expenseType;
        const transactionDate = state.isEditing ? (state.transactionDate ?? a.transactionDate) : a.transactionDate;
        const amount          = state.isEditing ? (state.amount          ?? a.amount)          : a.amount;
        const overrideBillableAmount = this._isTruthyFlag(
            state.overrideBillableAmount ?? a.overrideBillableAmount
        );
        const billableAmount = overrideBillableAmount
            ? (state.billableAmount ?? a.billableAmount ?? amount)
            : (state.billableAmount ?? a.billableAmount ?? amount);
        const overrideCode = state.overrideCode ?? a.overrideCode ?? '';
        return {
            Id:                  a._tempId,
            lineNumber:          '',
            schema:              'expense',
            isTravelSchema:      false,
            isLaborSchema:       false,
            isExpenseSchema:     true,
            isAssetTimeSchema:   false,
            title:               expenseType || 'Unspecified Expense',
            metaLine:            this._fmtExpenseMeta(transactionDate, amount),
            lineType:            a._lineType,
            lineTypeLabel:       a._lineType,
            showLineType:        false,
            expenseType,
            overrideCode,
            transactionDate,
            transactionDateMs:   this._toMs(transactionDate),
            amount,
            billableAmount,
            isEditing:           state.isEditing ?? false,
            editExpenseType:     state.expenseType     ?? a.expenseType     ?? '',
            editTransactionDate: state.transactionDate ?? a.transactionDate ?? '',
            editAmount:          state.amount          ?? a.amount          ?? 0,
            editOverrideCode:   overrideCode,
            editBillableAmount:  billableAmount,
            editBillableAmountDisplay: this._fmtBillableAmount(billableAmount),
            editOverrideBillableAmount: overrideBillableAmount,
            isBillableAmountReadOnly: !overrideBillableAmount,
            isOverrideCodeRequired: overrideBillableAmount,
            editError:           this.editErrors[a._tempId] ?? '',
            isDirty:             false,
            isNew:               true
        };
    }

    // Calibration & Other share this schema (Resource + Asset + StartDate/EndDate/Duration).
    /**
     * @description Internal helper: Build Asset Time Line Model.
     */
    _buildAssetTimeLineModel(l, edit, state, showLineType) {
        const lineType        = l.LineType__c?.value ?? '';
        const assignedResId   = edit?.assignedResourceId ?? l.AssignedResource__c?.value ?? null;
        const assignedResName = l.AssignedResource__r?.Name?.value ?? '';
        const assetId         = edit?.assetId ?? l.AssetId?.value ?? null;
        const assetSerial     = l.Asset?.SerialNumber?.value ?? '';
        const startDate       = edit?.startDate ?? l.StartDate?.value ?? '';
        const endDate         = edit?.endDate   ?? l.EndDate?.value   ?? '';
        const durationHours   = this._computeDurationHours(startDate, endDate) ?? l.Duration?.value ?? null;
        return {
            Id:                  l.Id,
            lineNumber:          l.LineItemNumber?.value ?? '',
            schema:              'asset_time',
            isTravelSchema:      false,
            isLaborSchema:       false,
            isExpenseSchema:     false,
            isAssetTimeSchema:   true,
            // Card display
            title:               assignedResName || 'Unassigned',
            metaLine:            this._fmtAssetTimeMeta(assetSerial, startDate, endDate, durationHours),
            lineType,
            lineTypeLabel:       lineType || 'No Type',
            showLineType,
            // Asset-time fields
            assignedResourceId:  assignedResId,
            assignedResourceName:assignedResName,
            assetId,
            assetSerialNumber:   assetSerial,
            startDate,
            endDate,
            startDateMs:         this._toMs(startDate),
            durationHours,
            // Edit state
            isEditing:           state.isEditing ?? false,
            editAssignedResId:   this._resolveAssignedResourceId(
                state.assignedResourceId, edit?.assignedResourceId, l.AssignedResource__c?.value
            ),
            editAssetId:         state.assetId    ?? edit?.assetId    ?? l.AssetId?.value    ?? null,
            editStartDate:       state.startDate  ?? edit?.startDate  ?? l.StartDate?.value ?? '',
            editEndDate:         state.endDate    ?? edit?.endDate    ?? l.EndDate?.value   ?? '',
            editDurationLabel:   this._editDurationLabel(state, edit, startDate, endDate, l.Duration?.value),
            editError:           this.editErrors[l.Id] ?? '',
            isDirty:             !!edit,
            isNew:               false
        };
    }

    /**
     * @description Internal helper: Build Asset Time Add Model.
     */
    _buildAssetTimeAddModel(a, state) {
        const assignedResId = this._resolveAssignedResourceId(
            state.isEditing ? state.assignedResourceId : null,
            a.assignedResourceId
        );
        const assetId       = state.isEditing ? (state.assetId    ?? a.assetId)    : a.assetId;
        const startDate     = state.isEditing ? (state.startDate  ?? a.startDate)  : a.startDate;
        const endDate       = state.isEditing ? (state.endDate    ?? a.endDate)    : a.endDate;
        const durationHours = this._computeDurationHours(startDate, endDate);
        const titleName     = a.assignedResourceName
            || this._assignedResourceNameForId(assignedResId)
            || 'Assigned Resource pending…';
        return {
            Id:                  a._tempId,
            lineNumber:          '',
            schema:              'asset_time',
            isTravelSchema:      false,
            isLaborSchema:       false,
            isExpenseSchema:     false,
            isAssetTimeSchema:   true,
            title:               assignedResId ? titleName : 'Unassigned',
            metaLine:            this._fmtAssetTimeMeta('', startDate, endDate, durationHours),
            lineType:            a._lineType,
            lineTypeLabel:       a._lineType,
            showLineType:        false,
            assignedResourceId:  assignedResId,
            assignedResourceName:titleName,
            assetId,
            assetSerialNumber:   '',
            startDate,
            endDate,
            startDateMs:         this._toMs(startDate),
            durationHours,
            isEditing:           state.isEditing ?? false,
            editAssignedResId:   this._resolveAssignedResourceId(
                state.assignedResourceId, a.assignedResourceId
            ),
            editAssetId:         state.assetId    ?? a.assetId    ?? null,
            editStartDate:       state.startDate  ?? a.startDate  ?? '',
            editEndDate:         state.endDate    ?? a.endDate    ?? '',
            editDurationLabel:   this._editDurationLabel(state, null, startDate, endDate, durationHours),
            editError:           this.editErrors[a._tempId] ?? '',
            isDirty:             false,
            isNew:               true
        };
    }

    /**
     * @description Internal helper: Fmt Expense Meta.
     */
    _fmtExpenseMeta(transactionDate, amount) {
        const parts = [];
        const d = this._fmtDate(transactionDate);
        if (d) parts.push(d);
        const a = this._fmtMoney(amount);
        if (a) parts.push(`$${a}`);
        return parts.join(' · ') || 'Expense';
    }

    /**
     * @description Internal helper: Fmt Asset Time Meta.
     */
    _fmtAssetTimeMeta(assetSerial, startDate, endDate, duration) {
        const parts = [];
        if (assetSerial) parts.push(`SN ${assetSerial}`);
        const range = this._fmtDateRange(startDate, endDate);
        if (range) parts.push(range);
        const durationLabel = this._fmtDurationLabel(duration);
        if (durationLabel) parts.push(durationLabel);
        return parts.join(' · ');
    }

    /**
     * @description Internal helper: Fmt Money.
     */
    _fmtMoney(n) {
        const num = Number(n);
        if (!Number.isFinite(num)) return '0.00';
        return num.toFixed(2);
    }

    /**
     * @description Internal helper: Fmt Labor Meta.
     */
    _fmtProductServicedMeta(workTypeName, inspectionOutcome, assignedResName) {
        const parts = [];
        if (workTypeName) parts.push(workTypeName);
        if (inspectionOutcome) parts.push(inspectionOutcome);
        if (assignedResName) parts.push(assignedResName);
        return parts.join(' · ') || 'Product Serviced';
    }

    /**
     * @description Asset name and serial for the link list. The account is already in the header, so it is left off the row.
     * @param {string} name Asset name
     * @param {string} serialNumber Asset serial number
     * @return {string}
     */
    _fmtInspectAssetName(name, serialNumber) {
        const parts = [];
        const label = this._assetNameWithoutAccount(name);
        if (label) parts.push(label);
        if (serialNumber) parts.push(`SN ${serialNumber}`);
        return parts.join(' · ');
    }

    /**
     * @description Drop a leading account name from an Asset name.
     * @param {string} name Asset name
     * @return {string}
     */
    _assetNameWithoutAccount(name) {
        const label = String(name || '').trim();
        const account = String(this.woAccountName || '').trim();
        if (!label) return 'Asset';
        if (!account || !label.toLowerCase().startsWith(account.toLowerCase())) return label;
        const rest = label.slice(account.length).replace(/^[\s\-–—:]+/, '').trim();
        return rest || label;
    }

    /**
     * @description Last inspection and last serviced dates for one asset in the link list.
     * @param {string} lastInspectionDate ISO date
     * @param {string} lastServicedDate ISO date
     * @return {string}
     */
    _fmtInspectAssetDates(lastInspectionDate, lastServicedDate) {
        const inspection = lastInspectionDate ? this._fmtDate(lastInspectionDate) : '—';
        const serviced = lastServicedDate ? this._fmtDate(lastServicedDate) : '—';
        return `Last inspection ${inspection} · Last serviced ${serviced}`;
    }

    /**
     * @description True when the asset matches the current product information filters.
     * @param {Object} asset Mapped account asset
     * @return {boolean}
     */
    _assetMatchesFilters(asset) {
        const filters = this.assetFilters || {};
        const checks = [
            ['productLine', asset.productLine],
            ['subProductLine', asset.subProductLine],
            ['deviceType', asset.deviceType],
            ['manufacturer', asset.manufacturer],
            ['model', asset.model]
        ];
        return checks.every(([key, value]) => {
            const selected = filters[key];
            if (!selected) return true;
            return (value || '') === selected;
        });
    }

    /**
     * @description Combobox options for one product information filter.
     * @param {string} field Asset row property
     * @return {Array}
     */
    _assetFilterOptions(field) {
        const values = new Set();
        for (const asset of this.accountInspectAssets) {
            const value = asset[field];
            if (value) values.add(value);
        }
        return [
            { label: 'All', value: '' },
            ...[...values].sort((a, b) => a.localeCompare(b)).map(value => ({ label: value, value }))
        ];
    }

    /**
     * @description Find one IMS Asset on the work order account by serial number and set it on the add form.
     * @param {string} serial Scanned or typed serial number
     */
    _applyScannedSerialToAddForm(serial) {
        const key = String(serial || '').trim();
        if (!key) return;
        if (!this.woAccountId) {
            this.assetScanMessage = 'This Work Order has no Account, so the asset cannot be found.';
            return;
        }
        this.assetScanMessage = '';
        this._assetSerialLookup = null;
        Promise.resolve().then(() => {
            this._assetSerialLookup = key;
        });
    }

    /**
     * @description Read one serial number from the device barcode scanner.
     * @return {Promise<string|null>}
     */
    async _captureAssetSerial() {
        const scanner = getBarcodeScanner();
        if (!scanner || typeof scanner.isAvailable !== 'function' || !scanner.isAvailable()) {
            this.assetScanMessage = 'Camera scan is unavailable. Type or scan the serial number into the field.';
            return null;
        }
        try {
            let first;
            if (typeof scanner.scan === 'function') {
                const results = await scanner.scan({
                    instructionText: 'Scan the asset serial number',
                    successText: 'Serial number scanned'
                });
                first = Array.isArray(results) ? results[0] : results;
            } else if (typeof scanner.beginCapture === 'function') {
                first = await scanner.beginCapture({
                    instructionText: 'Scan the asset serial number',
                    successText: 'Serial number scanned'
                });
            }
            const value = (typeof first === 'string' ? first : (first?.value ?? '')).trim();
            return value || null;
        } catch (error) {
            if (error?.code === 'userDismissedScanner') return null;
            this.assetScanMessage = error?.message || 'Unable to open the barcode scanner.';
            return null;
        } finally {
            try {
                if (typeof scanner.dismiss === 'function') scanner.dismiss();
                else if (typeof scanner.endCapture === 'function') scanner.endCapture();
            } catch (e) {
                // Ignore dismiss errors.
            }
        }
    }

    /**
     * @description Repair-center values saved with a Do Not Use (P0) line.
     * @param {Object} source Staged Product Serviced line
     * @return {Object}
     */
    _repairCenterPersistFields(source) {
        const sendToRepairCenter = source?.inspectionOutcome === DO_NOT_USE_P0;
        const fields = {
            [WOLI_SEND_TO_REPAIR_CENTER.fieldApiName]: sendToRepairCenter
        };
        if (!sendToRepairCenter) return fields;
        const additionalServices = !!source.additionalServices;
        fields[WOLI_SERIAL_NUMBER.fieldApiName] = String(source.serialNumber || '').trim();
        fields[WOLI_MODEL.fieldApiName] = String(source.model || '').trim();
        fields[WOLI_DEPARTMENT.fieldApiName] = source.departmentId || null;
        fields[WOLI_REPORTED_PROBLEM.fieldApiName] = String(source.reportedProblem || '').trim();
        fields[WOLI_NOT_INSPECTED_REASON.fieldApiName] = String(source.notInspectedReason || '').trim();
        fields[WOLI_ADDITIONAL_SERVICES.fieldApiName] = additionalServices;
        fields[WOLI_INSULATION.fieldApiName] = additionalServices
            ? this._insulationPersistValue(source.insulationPowderCoating)
            : null;
        return fields;
    }

    /**
     * @description Saved repair-center values used to seed the first edit.
     * @param {string} lineId Work Order Line Item Id
     * @return {Object}
     */
    _savedRepairSeed(lineId) {
        const saved = this._repairCenterByLineId[lineId] || {};
        return {
            serialNumber: saved.serialNumber || '',
            model: saved.model || '',
            departmentId: saved.departmentId || null,
            reportedProblem: saved.reportedProblem || '',
            notInspectedReason: saved.notInspectedReason || '',
            additionalServices: !!saved.additionalServices,
            insulationPowderCoating: this._insulationList(saved.insulationPowderCoating),
            pictures: []
        };
    }

    /**
     * @description Template values for the Do Not Use (P0) return-order fields.
     * @param {string} lineId Line or temp Id
     * @param {string} inspectionOutcome Current inspection outcome
     * @param {Object} source Staged values
     * @param {Object} stored Values already saved on the line
     * @return {Object}
     */
    _repairCenterView(lineId, inspectionOutcome, source, stored) {
        const saved = stored || {};
        const showRepairCenterFields = inspectionOutcome === DO_NOT_USE_P0;
        const additionalServices = source?.additionalServices ?? saved.additionalServices ?? false;
        const pictures = source?.pictures || [];
        return {
            showRepairCenterFields,
            editSerialNumber: source?.serialNumber ?? saved.serialNumber ?? '',
            editModel: source?.model ?? saved.model ?? '',
            editDepartmentId: source?.departmentId ?? saved.departmentId ?? null,
            editNotInspectedReason: source?.notInspectedReason ?? saved.notInspectedReason ?? '',
            editReportedProblem: source?.reportedProblem ?? saved.reportedProblem ?? '',
            editAdditionalServices: !!additionalServices,
            showInsulationField: showRepairCenterFields && !!additionalServices,
            editInsulationPowderCoating: this._insulationList(
                source?.insulationPowderCoating ?? saved.insulationPowderCoating
            ),
            showRecordPictureUpload: showRepairCenterFields && this._isSalesforceWoliId(lineId),
            showStagedPictureUpload: showRepairCenterFields && !this._isSalesforceWoliId(lineId),
            persistedLineIdForUpload: this._isSalesforceWoliId(lineId) ? lineId : null,
            pictureItems: pictures
                .filter(picture => picture?.contentDocumentId)
                .map(picture => ({
                    id: picture.contentDocumentId,
                    name: picture.name || 'Picture'
                }))
        };
    }

    /**
     * @description True when the value is a Salesforce Work Order Line Item Id.
     * @param {string} value Candidate Id
     * @return {boolean}
     */
    _isSalesforceWoliId(value) {
        return this._isPersistedWoliId(value);
    }

    /**
     * @description Multi-select values as a list.
     * @param {string|Array} value Stored or staged insulation values
     * @return {Array}
     */
    _insulationList(value) {
        if (Array.isArray(value)) return value.filter(Boolean);
        if (!value) return [];
        return String(value).split(';').map(item => item.trim()).filter(Boolean);
    }

    /**
     * @description Multi-select values stored as a semicolon-separated string.
     * @param {string|Array} value Staged insulation values
     * @return {string|null}
     */
    _insulationPersistValue(value) {
        const items = this._insulationList(value);
        return items.length ? items.join(';') : null;
    }

    /**
     * @description Internal helper: Fmt Labor Meta.
     */
    _fmtLaborMeta(assetSerial, repairCode, startDate, endDate, duration, billingType = '') {
        const parts = [];
        if (assetSerial) parts.push(`SN ${assetSerial}`);
        if (repairCode)  parts.push(repairCode);
        const range = this._fmtDateRange(startDate, endDate);
        if (range) parts.push(range);
        const durationLabel = this._fmtDurationLabel(duration);
        if (durationLabel) parts.push(durationLabel);
        const billingTypeLabel = this._fmtBillingType(billingType);
        if (billingTypeLabel) parts.push(billingTypeLabel);
        return parts.join(' · ');
    }

    /**
     * @description Internal helper: Fmt Travel Meta.
     */
    _fmtTravelMeta(startDate, endDate, billingType = '') {
        const parts = [];
        const range = this._fmtDateRange(startDate, endDate);
        if (range) parts.push(range);
        const billingTypeLabel = this._fmtBillingType(billingType);
        if (billingTypeLabel) parts.push(billingTypeLabel);
        return parts.join(' · ');
    }

    /**
     * @description Internal helper: Edit Duration Label.
     */
    _editDurationLabel(state, edit, startDate, endDate, durationFromServer) {
        const effectiveStart = state.startDate ?? edit?.startDate ?? startDate ?? '';
        const effectiveEnd = state.endDate ?? edit?.endDate ?? endDate ?? '';
        const hours = this._computeDurationHours(effectiveStart, effectiveEnd) ?? durationFromServer;
        return this._fmtDurationLabel(hours);
    }

    /**
     * @description Internal helper: Fmt Duration Label.
     */
    _fmtDurationLabel(hours) {
        if (hours == null || hours === '') return '';
        const n = Number(hours);
        if (Number.isNaN(n)) return '';
        return `${n.toFixed(2)} hrs`;
    }

    /**
     * @description Internal helper: Compute Duration Hours.
     */
    _computeDurationHours(startDate, endDate) {
        if (!startDate || !endDate) return null;
        const start = new Date(startDate).getTime();
        const end = new Date(endDate).getTime();
        if (Number.isNaN(start) || Number.isNaN(end) || end <= start) return null;
        return (end - start) / (1000 * 60 * 60);
    }

    /**
     * @description Resolves a WorkOrderLineItem record type Id by developer name.
     * @param {Object} objectInfo getObjectInfo result
     * @param {String} developerName Record type developer name
     * @return {String|null} Record type Id
     */
    _recordTypeIdByDeveloperName(objectInfo, developerName) {
        if (!objectInfo?.recordTypeInfos || !developerName) {
            return null;
        }
        const match = Object.entries(objectInfo.recordTypeInfos).find(([, info]) => {
            if (!info) {
                return false;
            }
            return info.developerName === developerName || info.name === developerName;
        });
        if (!match) {
            return null;
        }
        const [recordTypeIdKey, info] = match;
        return info.recordTypeId || recordTypeIdKey || null;
    }

    /**
     * @description RecordTypeId fields for Travel and Labor WOLI creates.
     * @return {Object} Fields map including RecordTypeId
     */
    _usageConsumptionRecordTypeFields() {
        if (!this._usageConsumptionRecordTypeId) {
            throw new Error(
                'Work Order Line Item record type UsageConsumption is not available.'
            );
        }
        return { [WOLI_RECORDTYPE.fieldApiName]: this._usageConsumptionRecordTypeId };
    }

    /**
     * @description RecordTypeId fields for Product Serviced WOLI creates.
     * @return {Object} Fields map including RecordTypeId
     */
    _productServicedRecordTypeFields() {
        if (!this._productServicedRecordTypeId) {
            throw new Error(
                'Work Order Line Item record type ProductServiced is not available.'
            );
        }
        return { [WOLI_RECORDTYPE.fieldApiName]: this._productServicedRecordTypeId };
    }

    /**
     * @description Billing Type Non-Billable. Discount is omitted; a discount
     *              requires a product on the line and Non-Billable does not set one.
     * @return {Object}
     */
    _nonBillableBillingFields() {
        return {
            [WOLI_BILLING_TYPE.fieldApiName]: BILLING_TYPE_NON_BILLABLE
        };
    }

    /**
     * @description Writes a field only when the pending edit staged it.
     *              Used so a Travel date edit does not blank Asset or Inspection Outcome.
     * @param {Object} edit Pending edit
     * @param {Object} fieldMap Local property name to API name
     * @return {Object}
     */
    _optionalClearedFields(edit, fieldMap) {
        const fields = {};
        Object.entries(fieldMap).forEach(([prop, apiName]) => {
            if (Object.prototype.hasOwnProperty.call(edit, prop)) {
                fields[apiName] = edit[prop] || null;
            }
        });
        return fields;
    }

    /**
     * @description Internal helper: Build Duration Fields.
     */
    _buildDurationFields(startDate, endDate) {
        const duration = this._computeDurationHours(startDate, endDate);
        if (duration == null) return {};
        return { [WOLI_DURATION.fieldApiName]: duration, DurationType: 'Hours' };
    }

    /**
     * @description Internal helper: Fmt Date Range.
     */
    _fmtDateRange(startDate, endDate) {
        const s = this._fmtDateTime(startDate);
        const e = this._fmtDateTime(endDate);
        if (s && e) return `${s} → ${e}`;
        if (s)      return s;
        if (e)      return `→ ${e}`;
        return '';
    }

    /**
     * @description Internal helper: Fmt Date Time.
     */
    _fmtDateTime(iso) {
        if (!iso) return '';
        const d = new Date(iso);
        if (Number.isNaN(d.getTime())) return '';
        return d.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
    }

    /**
     * @description Internal helper: Fmt Date.
     */
    _fmtDate(iso) {
        if (!iso) return '';
        if (/^\d{4}-\d{2}-\d{2}$/.test(iso)) {
            const [y, m, d] = iso.split('-').map(Number);
            const dt = new Date(y, m - 1, d);
            return dt.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
        }
        const dt = new Date(iso);
        if (Number.isNaN(dt.getTime())) return '';
        return dt.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
    }

    /**
     * @description Internal helper: Today Date String.
     */
    _todayDateString() {
        const d = new Date();
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        return `${y}-${m}-${day}`;
    }

    /**
     * @description Internal helper: To Ms.
     */
    _toMs(iso) {
        if (!iso) return null;
        const t = new Date(iso).getTime();
        return Number.isNaN(t) ? null : t;
    }

    // ── Tab ───────────────────────────────────────────────────────────────────
    /**
     * @description Handle Tab Select.
     */
    handleTabSelect(e) {
        this.activeTab = e.currentTarget.dataset.tab;
        if (this.activeTab !== 'ProductServiced') {
            this._closeMultiAssetPicker();
        }
    }
    /**
     * @description Handle Tab Search Change.
     */
    handleTabSearchChange(e) {
        this.tabSearchTerms = {
            ...this.tabSearchTerms,
            [this.activeTab]: e.detail.value ?? ''
        };
    }

    // ── Inline edit (autosave-to-draft) ───────────────────────────────────────
    //
    // UX model: field changes autosave into draft (_pendingEdits / _pendingAdds).
    // Open via pencil/card; Close (or pencil again) collapses the form without
    // discarding staged changes. Footer Cancel still discards all drafts.

    // Bound to BOTH the pencil button and the .woli-info card body, so a tap
    // anywhere on the line text or the pencil toggles the inline edit form.
    /**
     * @description Handle Edit Toggle.
     */
    handleEditToggle(e) {
        const id  = e.currentTarget.dataset.id;
        const cur = this.editStateMap[id];
        const opening = !(cur?.isEditing);
        if (!opening) {
            this._applyProductServicedClose(id);
            if (this._activeProductServicedLineIdForPicture
                && this._pictureRecordKey(this._activeProductServicedLineIdForPicture)
                    === this._pictureRecordKey(id)) {
                this._activeProductServicedLineIdForPicture = null;
            }
        } else {
            this._defaultDepartmentForLine(id);
            this._activeProductServicedLineIdForPicture = this._recordIdFromGraphql(id) || id;
        }
        this.editStateMap = {
            ...this.editStateMap,
            [id]: { isEditing: opening }
        };
        const errs = { ...this.editErrors };
        delete errs[id];
        this.editErrors = errs;
    }

    /**
     * @description Handle Edit Close.
     */
    handleEditClose(e) {
        const id = e.currentTarget.dataset.id;
        this._applyProductServicedClose(id);
        this.editStateMap = {
            ...this.editStateMap,
            [id]: { isEditing: false }
        };
        const errs = { ...this.editErrors };
        delete errs[id];
        this.editErrors = errs;
    }

    /**
     * @description Handle Edit Field Change.
     */
    async handleEditFieldChange(e) {
        const id    = e.currentTarget.dataset.id;
        const field = e.currentTarget.dataset.field;
        const value = (field === 'overrideBillableAmount' || field === 'additionalServices' || field === 'canceled')
            ? e.detail.checked === true
            : e.detail.value;
        if (this._ignoreBlankRepairClear(field, value)) return;
        this._stageEdit(id, field, value);
        if (field === 'canceled') {
            this._stageEdit(id, 'lineStatus', value ? LINE_STATUS_CANCELED : LINE_STATUS_NEW);
        }
        if (field === 'inspectionOutcome' && value === DO_NOT_USE_P0) {
            this._requestAssetRepairDefaults(id);
        }
        if (field === 'additionalServices' && value !== true) {
            this._stageEdit(id, 'insulationPowderCoating', []);
        }
        if (field === 'lineType' && (value === 'Travel' || value === 'Labor')) {
            this._stageEdit(id, 'workTypeId', null);
            this._stageEdit(id, 'repairCodeId', null);
            this._stageEdit(id, 'assetId', null);
            this._stageEdit(id, 'inspectionOutcome', null);
            this._stageEdit(id, 'billingType', BILLING_TYPE_NON_BILLABLE);
            const schema = LINE_TYPE_TO_SCHEMA[value];
            if (schema) {
                this._stageEdit(id, '_schema', schema);
                this._stageEdit(id, '_lineType', value);
            }
        }
    }

    // ── Delete (draft only) ───────────────────────────────────────────────────
    /**
     * @description Handle Delete.
     */
    handleDelete(e) {
        const id = e.currentTarget.dataset.id;

        // Pending-add line (temp ID) — just remove from the add list
        if (this._pendingAdds.some(a => a._tempId === id)) {
            this._pendingAdds = this._pendingAdds.filter(a => a._tempId !== id);
            return;
        }

        // Existing server record — stage for deletion and clear any staged edit
        this._pendingDeletes = { ...this._pendingDeletes, [id]: true };
        const edits = { ...this._pendingEdits };
        delete edits[id];
        this._pendingEdits = edits;
    }

    // ── Add form (draft only) ─────────────────────────────────────────────────
    /**
     * @description Handle Add Toggle.
     */
    handleAddToggle(e) {
        const tab = e.currentTarget.dataset.tab || this.activeTab;
        this._closeMultiAssetPicker();
        this.showAddForm = { ...EMPTY_ADD_FORM_VISIBILITY(), [tab]: true };
        const form = this._emptyAddFormState();
        if (tab === 'ProductServiced') {
            form.workTypeId = this.woWorkTypeId;
        }
        this.addFormState = form;
        this.assetScanSerial = '';
        this.assetScanMessage = '';
        this.addErrors = {};
    }

    /**
     * @description Handle Add Field Change.
     */
    async handleAddFieldChange(e) {
        const field = e.currentTarget.dataset.field;
        const value = (field === 'overrideBillableAmount' || field === 'additionalServices' || field === 'canceled')
            ? e.detail.checked === true
            : e.detail.value;
        if (this._ignoreBlankRepairClear(field, value)) return;
        let next = { ...this.addFormState, [field]: value };
        if (field === 'canceled') {
            next.lineStatus = value ? LINE_STATUS_CANCELED : LINE_STATUS_NEW;
        }
        if (field === 'additionalServices' && value !== true) {
            next.insulationPowderCoating = [];
        }
        if (field === 'inspectionOutcome' && value === DO_NOT_USE_P0) {
            this.addFormState = next;
            this._requestAssetRepairDefaults(null);
            return;
        }
        if (field === 'billingType') {
            next.discount = this._discountForBillingType(value);
        }
        if (field === 'lineType' && (value === 'Travel' || value === 'Labor')) {
            next.workTypeId = null;
            next.repairCodeId = null;
            next.assetId = null;
            next.inspectionOutcome = '';
            next.billingType = BILLING_TYPE_NON_BILLABLE;
            next.discount = 0;
        }
        if (field === 'amount' || field === 'overrideBillableAmount') {
            next = this._applyExpenseBillableSync(next, field);
        }
        this.addFormState = next;
    }

    // lightning-record-picker emits `change` with `event.detail.recordId` rather
    // than `event.detail.value`. Field name carried via data-field as usual.
    /**
     * @description Handle Lookup Change.
     */
    async handleLookupChange(e) {
        const id    = e.currentTarget.dataset.id;     // present for inline-edit
        const tab   = e.currentTarget.dataset.tab;    // present for add-form
        const field = e.currentTarget.dataset.field;
        const recordId = e.detail.recordId ?? null;
        if (field === 'assetId') {
            if (id) {
                this._stageEdit(id, field, recordId);
            } else if (tab) {
                this.addFormState = { ...this.addFormState, assetId: recordId };
            }
            this._requestAssetRepairDefaults(id || null);
        } else if (id) {
            this._stageEdit(id, field, recordId);
        } else if (tab) {
            this.addFormState = { ...this.addFormState, [field]: recordId };
        }
        // Repair Code helper-text support: trigger the on-demand wire to fetch
        // the Product Name for any code we haven't cached yet.
        if (field === 'repairCodeId' && recordId && !this._repairCodeNameById[recordId]) {
            this._repairCodeLookupId = recordId;
        }
        if (field === 'assignedResourceId' && recordId && !this._userIdByServiceResourceId[recordId]) {
            this._assignedResourceOwnerLookupId = recordId;
        }
    }

    // Helper text for the Add Labor Line form's Repair Code picker.
    /**
     * @description Add Form Repair Code Name.
     */
    get addFormRepairCodeName() {
        return this._repairCodeNameById[this.addFormState.repairCodeId] ?? '';
    }

    /**
     * @description Handle Add Confirm.
     */
    handleAddConfirm(e) {
        const tab = e.currentTarget.dataset.tab || this.activeTab;
        const built = this._buildPendingAddFromOpenForm(tab);
        if (built.errMsg) {
            this.addErrors = { ...this.addErrors, [built.tab]: built.errMsg };
            return;
        }
        this._pendingAdds = [...this._pendingAdds, built.newAdd];
        this._closeAddForm(built.tab);
    }

    /**
     * @description GW-375 - Builds a pending add row from the open add form.
     * @param {string} tab Tab key
     * @return {{ tab: string, newAdd: Object|null, errMsg: string|null }}
     */
    _buildPendingAddFromOpenForm(tab) {
        const tabKey = tab || this.activeTab;
        const def = TAB_KEY_TO_DEF[tabKey];
        const schema = def?.schema ?? 'generic';
        const addPayload = schema === 'expense'
            ? { ...this.addFormState }
            : {
                ...this.addFormState,
                assignedResourceId: this._resolveAssignedResourceId(this.addFormState.assignedResourceId)
            };
        const errMsg = this._validateForSchema(schema, addPayload);
        if (errMsg) {
            return { tab: tabKey, newAdd: null, errMsg };
        }
        const assignedResourceId = addPayload.assignedResourceId;
        const assignedResourceName = this._assignedResourceNameForId(assignedResourceId);
        _tempIdSeq += 1;
        const resolvedSchema = schema === 'time'
            ? (LINE_TYPE_TO_SCHEMA[addPayload.lineType] ?? null)
            : schema;
        const resolvedLineType = schema === 'time' ? addPayload.lineType : (def?.type ?? tabKey);
        if (schema === 'time' && !resolvedSchema) {
            return { tab: tabKey, newAdd: null, errMsg: 'Line Type is required.' };
        }
        const baseAdd = {
            _tempId: `_new_${_tempIdSeq}`,
            _lineType: resolvedLineType,
            _schema: resolvedSchema
        };
        let newAdd;
        if (resolvedSchema === 'travel' || resolvedSchema === 'labor') {
            newAdd = {
                ...baseAdd,
                assignedResourceId,
                assignedResourceName,
                startDate: addPayload.startDate || null,
                endDate: addPayload.endDate || null,
                billingType: BILLING_TYPE_NON_BILLABLE,
                discount: 0
            };
        } else if (resolvedSchema === 'productServiced') {
            newAdd = {
                ...baseAdd,
                assignedResourceId,
                assignedResourceName,
                workTypeId: addPayload.workTypeId || null,
                assetId: addPayload.assetId,
                inspectionOutcome: addPayload.inspectionOutcome || null,
                canceled: addPayload.canceled === true,
                lineStatus: addPayload.canceled === true
                    ? LINE_STATUS_CANCELED
                    : this._isProductServicedComplete({
                        assetId: addPayload.assetId,
                        workTypeId: addPayload.workTypeId,
                        assignedResourceId,
                        inspectionOutcome: addPayload.inspectionOutcome,
                        serialNumber: addPayload.serialNumber,
                        model: addPayload.model,
                        departmentId: addPayload.departmentId,
                        reportedProblem: addPayload.reportedProblem,
                        notInspectedReason: addPayload.notInspectedReason
                    }) ? LINE_STATUS_COMPLETED : LINE_STATUS_NEW,
                serialNumber: addPayload.serialNumber || '',
                model: addPayload.model || '',
                departmentId: addPayload.departmentId || null,
                reportedProblem: addPayload.reportedProblem || '',
                notInspectedReason: addPayload.notInspectedReason || '',
                additionalServices: !!addPayload.additionalServices,
                insulationPowderCoating: addPayload.insulationPowderCoating || [],
                pictures: addPayload.pictures || [],
                mobilePictures: addPayload.mobilePictures || [],
                billingType: BILLING_TYPE_NON_BILLABLE,
                discount: 0
            };
        } else if (schema === 'expense') {
            const overrideBillableAmount = this._isTruthyFlag(addPayload.overrideBillableAmount);
            const amount = Number(addPayload.amount) || 0;
            newAdd = {
                ...baseAdd,
                _entity: 'Expense',
                expenseType: addPayload.expenseType,
                transactionDate: addPayload.transactionDate || null,
                amount,
                overrideCode: addPayload.overrideCode || '',
                overrideBillableAmount,
                billableAmount: overrideBillableAmount
                    ? Number(addPayload.billableAmount)
                    : amount
            };
        } else if (schema === 'asset_time') {
            newAdd = {
                ...baseAdd,
                assignedResourceId,
                assignedResourceName,
                assetId: addPayload.assetId,
                startDate: addPayload.startDate || null,
                endDate: addPayload.endDate || null
            };
        } else {
            newAdd = {
                ...baseAdd,
                desc: addPayload.desc,
                duration: Number(addPayload.duration),
                unitPrice: Number(addPayload.unitPrice) || 0
            };
        }
        return { tab: tabKey, newAdd, errMsg: null };
    }

    /**
     * @description GW-375 - True when an open add form has fields or pictures to commit.
     * @param {string} tab Tab key
     * @return {boolean}
     */
    _openAddFormHasDraft(tab) {
        if (!tab || !this.showAddForm?.[tab]) {
            return false;
        }
        const form = this.addFormState || {};
        if ((form.mobilePictures || []).some(picture => picture?.base64Data)) {
            return true;
        }
        if ((form.pictures || []).length) {
            return true;
        }
        const def = TAB_KEY_TO_DEF[tab];
        const schema = def?.schema ?? 'generic';
        if (schema === 'productServiced') {
            return !!form.assetId
                || !!form.inspectionOutcome
                || !!form.workTypeId
                || !!form.assignedResourceId;
        }
        if (schema === 'expense') {
            return !!form.expenseType || !!form.amount;
        }
        if (schema === 'time') {
            return !!form.lineType || !!form.startDate || !!form.endDate;
        }
        return !!form.desc || !!form.duration || !!form.unitPrice;
    }

    /**
     * @description GW-375 - Moves open add forms into pending adds before Save All.
     * @return {boolean} True when a validation error was found
     */
    _commitOpenAddFormsBeforeSave() {
        let hasValidationError = false;
        Object.entries(this.showAddForm || {}).forEach(([tab, open]) => {
            if (!open || !this._openAddFormHasDraft(tab)) {
                return;
            }
            const built = this._buildPendingAddFromOpenForm(tab);
            if (built.errMsg) {
                this.addErrors = { ...this.addErrors, [built.tab]: built.errMsg };
                hasValidationError = true;
                return;
            }
            this._pendingAdds = [...this._pendingAdds, built.newAdd];
            this._closeAddForm(built.tab);
        });
        return hasValidationError;
    }

    /**
     * @description Handle Add Cancel.
     */
    handleAddCancel(e) {
        this._closeAddForm(e.currentTarget.dataset.tab);
    }

    /**
     * @description Open the Product Serviced multi-asset picker.
     */
    handleOpenMultiAssetPicker() {
        this.activeTab = 'ProductServiced';
        this.showAddForm = EMPTY_ADD_FORM_VISIBILITY();
        this.addFormState = this._emptyAddFormState();
        this.showMultiAssetPicker = true;
        this.selectedMultiAssetIds = {};
        this.multiAssetError = '';
        this.assetFilters = EMPTY_ASSET_FILTERS();
    }

    /**
     * @description Narrow the asset table by one product information field.
     */
    handleAssetFilterChange(e) {
        const field = e.currentTarget.dataset.field;
        if (!field) return;
        this.assetFilters = {
            ...this.assetFilters,
            [field]: e.detail.value || ''
        };
    }

    /**
     * @description Put the scanned serial number on the single Product Serviced line.
     */
    async handleAssetScanInput(e) {
        const serial = (e.detail.value || '').trim();
        this.assetScanSerial = serial;
        if (serial) {
            await this._applyScannedSerialToAddForm(serial);
        }
        this.assetScanSerial = '';
    }

    /**
     * @description Open the device camera and fill the Asset on the add form.
     */
    async handleAssetCameraScan() {
        const serial = await this._captureAssetSerial();
        if (serial) {
            await this._applyScannedSerialToAddForm(serial);
        }
    }

    /**
     * @description GW-375 - Compresses a mobile-device photo and saves it on this record only.
     */
    async handleMobilePictureSelected(event) {
        const { input, scope, lineId, slot, saveKey, lineNumber } = this._mobilePictureContextFromEvent(event);
        const effectiveScope = this._normalizePictureScope(scope, lineId, { saveKey, slot });
        const registryLineId = saveKey ? this._pictureLineIdBySaveKey[saveKey] : null;
        const pictureLineId = effectiveScope === 'line'
            ? (registryLineId
                || this._resolveLinePictureTargetId(lineId, slot, saveKey)
                || this._lineIdFromOpenEditForm()
                || this._activeProductServicedLineIdForPicture
                || lineId)
            : lineId;
        const file = input?.files && input.files[0];
        if (input) {
            input.value = '';
        }
        if (!file || this._savingPicture) {
            return;
        }
        this._savingPicture = true;
        try {
            const localPicture = await this._fileToMobilePicture(file);
            localPicture.comment = '';
            if (effectiveScope === 'add') {
                this._pendingMobilePictureCapture = {
                    localPicture,
                    effectiveScope,
                    pictureLineId,
                    slot,
                    saveKey,
                    lineNumber,
                    registryLineId,
                    workOrderId: this._workOrderPictureContextId()
                };
                this.pictureCommentDraftText = '';
                this.showPictureCommentCapture = true;
                return;
            }
            this._pendingMobilePictureCapture = {
                localPicture,
                effectiveScope,
                pictureLineId,
                slot,
                saveKey,
                lineNumber,
                registryLineId,
                workOrderId: this._workOrderPictureContextId()
            };
            this.pictureCommentDraftText = '';
            this.showPictureCommentCapture = true;
        } catch (error) {
            this._toast('Picture was not saved', this._errorMessage(error), 'error');
        } finally {
            this._savingPicture = false;
        }
    }

    /**
     * @description GW-6437 - Keeps the capture comment textarea in sync.
     */
    handlePictureCommentDraftChange(event) {
        this.pictureCommentDraftText = event.detail.value || '';
    }

    /**
     * @description GW-6437 - Cancels optional comment entry for a new CRSS picture.
     */
    handlePictureCommentCaptureCancel() {
        this.showPictureCommentCapture = false;
        this.pictureCommentDraftText = '';
        this._pendingMobilePictureCapture = null;
    }

    /**
     * @description GW-6437 - Saves a CRSS picture after optional comment entry.
     */
    async handlePictureCommentCaptureConfirm() {
        const pending = this._pendingMobilePictureCapture;
        if (!pending?.localPicture) {
            this.handlePictureCommentCaptureCancel();
            return;
        }
        const comment = this._normalizeMobilePictureComment(this.pictureCommentDraftText);
        pending.localPicture.comment = comment;
        this.showPictureCommentCapture = false;
        this.pictureCommentDraftText = '';
        this._pendingMobilePictureCapture = null;
        this._savingPicture = true;
        try {
            await this._completeMobilePictureUpload(pending);
        } catch (error) {
            this._queueFailedMobilePicture(
                pending.localPicture,
                pending.effectiveScope,
                pending.pictureLineId,
                pending.slot,
                null,
                null,
                pending.saveKey
            );
            this._toast(
                'Upload will retry on Save All',
                this._errorMessage(error),
                'warning'
            );
        } finally {
            this._savingPicture = false;
        }
    }

    /**
     * @description GW-6437 - Uploads or stages a CRSS picture after comment entry.
     * @param {Object} pending Capture context
     */
    async _completeMobilePictureUpload(pending) {
        const {
            localPicture,
            effectiveScope,
            pictureLineId,
            slot,
            saveKey,
            registryLineId,
            workOrderId
        } = pending;
        const comment = localPicture.comment || '';
        if (effectiveScope !== 'header') {
            const existingLineId = effectiveScope === 'line'
                ? this._savedProductServicedLineId(pictureLineId, saveKey, registryLineId)
                : null;
            if (!existingLineId) {
                this._holdPictureUntilLineExists(localPicture, pictureLineId, slot);
                return;
            }
            const saved = await saveProductServicedLineMobileDevicePicture(
                this._linePictureApexArgs(existingLineId, localPicture.base64Data, comment)
            );
            this._rememberMobilePicture(
                saved.linkedEntityId || existingLineId,
                saved,
                localPicture.previewUrl
            );
            this._toast('Picture saved', 'Mobile Device Picture saved to Salesforce.', 'success');
            return;
        }
        if (!workOrderId) {
            this._queueFailedMobilePicture(localPicture, effectiveScope, pictureLineId, slot, null, null, saveKey);
            this._toast('Picture kept on device', 'Open the work order again, then tap Save All.', 'warning');
            return;
        }
        const saved = await saveWorkOrderHeaderMobileDevicePicture({
            pictureUploadContext: this._appendPictureCommentToUploadContext(workOrderId, comment),
            base64Data: localPicture.base64Data
        });
        this._rememberMobilePicture(workOrderId, saved, localPicture.previewUrl);
        this._toast('Picture saved', 'Mobile Device Picture saved to Salesforce.', 'success');
    }

    /**
     * @description GW-375 - Opens a Mobile Device Picture for review.
     */
    async handleReviewPicture(event) {
        const scope = event.currentTarget.dataset.scope;
        const lineId = event.currentTarget.dataset.lineId;
        const key = event.currentTarget.dataset.key;
        const picture = this._findMobilePicture(scope, lineId, key);
        if (!picture) {
            return;
        }
        const view = this._pictureView(picture);
        this.reviewPicture = {
            ...view,
            scope,
            lineId: lineId || null,
            contentVersionId: picture.contentVersionId || null
        };
        this.reviewPictureComment = view.comment || '';
        this.showPictureReview = true;
        if (view.previewUrl && view.previewUrl.startsWith('data:')) {
            this.reviewPictureUrl = view.previewUrl;
            this.reviewPictureLoading = false;
            return;
        }
        this.reviewPictureUrl = '';
        this.reviewPictureLoading = true;
        try {
            const dataUrl = await this._loadSavedPicturePreview(picture.contentVersionId);
            if (this.reviewPicture?.contentVersionId === picture.contentVersionId && dataUrl) {
                this.reviewPictureUrl = dataUrl;
            }
        } catch (error) {
            this._toast('Picture', this._errorMessage(error), 'error');
        } finally {
            if (this.reviewPicture?.contentVersionId === picture.contentVersionId) {
                this.reviewPictureLoading = false;
            }
        }
    }

    /**
     * @description GW-375 - Closes the picture review.
     */
    handleClosePictureReview() {
        this.showPictureReview = false;
        this.reviewPicture = null;
        this.reviewPictureUrl = '';
        this.reviewPictureLoading = false;
        this.reviewPictureComment = '';
    }

    /**
     * @description GW-6437 - Keeps the review comment textarea in sync.
     */
    handleReviewPictureCommentChange(event) {
        this.reviewPictureComment = event.detail.value || '';
    }

    /**
     * @description GW-6437 - Saves an edited CRSS Mobile Device Picture comment.
     */
    async handleSaveReviewPictureComment() {
        if (!this.reviewPicture?.key) {
            return;
        }
        const comment = this._normalizeMobilePictureComment(this.reviewPictureComment);
        if (this.reviewPicture.contentDocumentId) {
            try {
                const saved = await updateMobileDevicePictureComment({
                    contentDocumentIdValue: this.reviewPicture.contentDocumentId,
                    pictureComment: comment
                });
                this._updateMobilePictureComment(
                    this.reviewPicture.lineId || saved.linkedEntityId,
                    this.reviewPicture.contentDocumentId,
                    saved.comment || comment
                );
                this.reviewPicture = {
                    ...this.reviewPicture,
                    comment: saved.comment || comment,
                    hasComment: !!(saved.comment || comment)
                };
                this.reviewPictureComment = saved.comment || comment;
                this._toast('Comment saved', 'Picture comment updated.', 'success');
            } catch (error) {
                this._toast('Comment was not saved', this._errorMessage(error), 'error');
            }
            return;
        }
        this._updateMobilePictureCommentLocal(
            this.reviewPicture.scope,
            this.reviewPicture.lineId,
            this.reviewPicture.key,
            comment
        );
        this.reviewPicture = {
            ...this.reviewPicture,
            comment,
            hasComment: !!comment
        };
        this.reviewPictureComment = comment;
        this._toast('Comment saved', comment ? 'Comment will upload with the picture.' : 'Comment cleared.', 'success');
    }

    /**
     * @description GW-375 - Deletes the picture shown in the review dialog.
     */
    async handleDeleteReviewedPicture() {
        if (!this.reviewPicture) {
            return;
        }
        const deleted = await this._deleteMobilePicture(
            this.reviewPicture.scope,
            this.reviewPicture.lineId,
            this.reviewPicture.key
        );
        if (deleted) {
            this.handleClosePictureReview();
        }
    }

    /**
     * @description GW-375 - Deletes a Mobile Device Picture from a thumbnail.
     */
    async handleDeletePicture(event) {
        event.stopPropagation();
        await this._deleteMobilePicture(
            event.currentTarget.dataset.scope,
            event.currentTarget.dataset.lineId,
            event.currentTarget.dataset.key
        );
    }

    /**
     * @description GW-375 - Loads image bytes when the thumbnail link does not paint.
     */
    handlePicturePreviewError(event) {
        const versionId = event.currentTarget?.dataset?.versionId;
        if (!versionId || this._pictureDataPromises[versionId]) {
            return;
        }
        this._loadSavedPicturePreview(versionId).catch(error => {
            this._toast('Picture', this._errorMessage(error), 'error');
        });
    }

    /**
     * @description Store a picture uploaded before the Product Serviced line exists.
     */
    handleRepairCenterFileUpload(event) {
        const files = (event.detail.files || []).map(file => ({
            contentDocumentId: file.documentId,
            name: file.name
        })).filter(file => file.contentDocumentId);
        if (!files.length) return;
        const lineId = event.currentTarget.dataset.id;
        if (!lineId) {
            this.addFormState = {
                ...this.addFormState,
                pictures: [...(this.addFormState.pictures || []), ...files]
            };
            return;
        }
        if (this._pendingAdds.some(add => add._tempId === lineId)) {
            this._pendingAdds = this._pendingAdds.map(add => (
                add._tempId === lineId
                    ? { ...add, pictures: [...(add.pictures || []), ...files] }
                    : add
            ));
        }
    }

    /**
     * @description Toggle one asset in the multi-asset picker.
     */
    handleMultiAssetToggle(e) {
        const id = e.currentTarget.dataset.id;
        if (!id) return;
        const checked = typeof e.detail?.checked === 'boolean'
            ? e.detail.checked
            : e.target.checked === true;
        const next = { ...this.selectedMultiAssetIds };
        if (checked) {
            next[id] = true;
        } else {
            delete next[id];
        }
        this.selectedMultiAssetIds = next;
        this.multiAssetError = '';
    }

    /**
     * @description Stage one Product Serviced line per selected asset.
     */
    handleMultiAssetConfirm() {
        const selected = this.accountInspectAssets.filter(asset => asset.selected);
        if (!selected.length) {
            this.multiAssetError = 'Select at least one Asset.';
            return;
        }
        if (!this._productServicedRecordTypeId) {
            this.multiAssetError = 'The Product Serviced record type was not found. Ask an administrator to check the Work Order Line Item record types, then try again.';
            return;
        }
        const adds = selected.map(asset => {
            _tempIdSeq += 1;
            return {
                _tempId: `_new_${_tempIdSeq}`,
                _lineType: LINE_TYPE_PRODUCT_SERVICED,
                _schema: 'productServiced',
                _bulkAssetLink: true,
                assetId: asset.id,
                assetName: asset.name,
                assetSerial: asset.serialNumber,
                workTypeId: this.woWorkTypeId,
                assignedResourceId: this._defaultAssignedResourceId(),
                assignedResourceName: this._currentUserServiceResourceName || '',
                inspectionOutcome: null,
                lineStatus: LINE_STATUS_NEW,
                billingType: BILLING_TYPE_NON_BILLABLE,
                discount: 0
            };
        });
        this._pendingAdds = [...this._pendingAdds, ...adds];
        this._closeMultiAssetPicker();
    }

    /**
     * @description Close the multi-asset picker without adding lines.
     */
    handleMultiAssetCancel() {
        this._closeMultiAssetPicker();
    }

    /**
     * @description Internal helper: Close Multi Asset Picker.
     */
    _closeMultiAssetPicker() {
        this.showMultiAssetPicker = false;
        this.selectedMultiAssetIds = {};
        this.multiAssetError = '';
        this.assetFilters = EMPTY_ASSET_FILTERS();
    }

    /**
     * @description Asset Ids already used by a work order line or a staged add.
     * @return {Set<string>}
     */
    _linkedAssetIds() {
        const ids = new Set();
        for (const line of this._serverLines) {
            if (this._pendingDeletes[line.Id]) continue;
            const assetId = line.AssetId?.value;
            if (assetId) ids.add(assetId);
        }
        for (const add of this._pendingAdds) {
            if (add.assetId) ids.add(add.assetId);
        }
        return ids;
    }

    /**
     * @description Internal helper: GraphQL error text.
     */
    _graphqlErrorText(errors) {
        const list = Array.isArray(errors) ? errors : [errors];
        const message = list
            .map(err => err?.message || err?.error?.message)
            .filter(Boolean)
            .join(' ');
        return message || 'Assets could not be loaded. Please try again or contact your administrator.';
    }

    /**
     * @description Internal helper: Close Add Form.
     */
    _closeAddForm(tab) {
        const key = tab || this.activeTab;
        this.showAddForm = EMPTY_ADD_FORM_VISIBILITY();
        this.addFormState = this._emptyAddFormState();
        this.assetScanSerial = '';
        this.assetScanMessage = '';
        if (key) {
            const errs = { ...this.addErrors };
            delete errs[key];
            this.addErrors = errs;
        } else {
            this.addErrors = {};
        }
    }

    // ── Global Save All ───────────────────────────────────────────────────────
    /**
     * @description Handle Save All.
     */
    async handleSaveAll() {
        // Re-entrancy guard — prevents double-tap from enqueuing duplicate draft actions
        if (this._saving) return;

        const confirmed = await LightningConfirm.open({
            message: 'Save all changes to Salesforce?',
            variant: 'headerless',
            label:   'Confirm Save'
        });
        if (!confirmed) return;

        let hasValidationError = this._commitOpenAddFormsBeforeSave();

        // Validate staged edits — route validator by schema
        for (const [id, edit] of Object.entries(this._pendingEdits)) {
            const err = this._validateForSchema(edit._schema ?? 'generic', edit);
            if (err) {
                this.editErrors = { ...this.editErrors, [id]: err };
                hasValidationError = true;
            }
        }
        // Validate staged adds — route validator by schema
        for (const a of this._pendingAdds) {
            const err = this._validateForSchema(a._schema ?? 'generic', a);
            if (err) {
                const errTab = a._schema === 'travel' || a._schema === 'labor'
                    ? 'Time'
                    : (TYPE_TO_DEF[a._lineType]?.key ?? 'Expense');
                this.addErrors = { ...this.addErrors, [errTab]: err };
                hasValidationError = true;
            }
        }
        if (hasValidationError) {
            this._toast('Validation Error', 'Fix highlighted errors before saving.', 'error');
            return;
        }

        this._saving = true;

        // Snapshot pending state and clear LIVE state — this way, if an individual
        // op fails, we re-add ONLY the failed one back to pending (avoids the
        // "cannot enqueue a draft action for a deleted record" error on retry,
        // which comes from re-submitting an already-enqueued action).
        const pendingDeletes = { ...this._pendingDeletes };
        const pendingEdits   = { ...this._pendingEdits };
        const pendingAdds    = [...this._pendingAdds];
        this._pendingDeletes = {};
        this._pendingEdits   = {};
        this._pendingAdds    = [];

        /** @description GW-375 - New Product Serviced line ids keyed by pending _tempId. */
        const createdProductServicedLineByTempId = {};

        const failedDeletes = {};
        const failedEdits   = {};
        const failedAdds    = [];
        const okIds         = [];
        const inspectionStamps = [];

        // Deletes first, then updates, then creates (sequential to avoid draft-queue races).
        for (const id of Object.keys(pendingDeletes)) {
            try {
                // eslint-disable-next-line no-await-in-loop
                await deleteRecord(id);
                okIds.push(id);
                if (this._serverExpenses.some(e => e.Id === id)) {
                    this._applyExpenseDelete(id);
                }
            } catch (err) {
                failedDeletes[id] = true;
            }
        }
        for (const [id, edit] of Object.entries(pendingEdits)) {
            try {
                const schema = edit._schema ?? 'generic';
                let fields;
                if (schema === 'travel') {
                    fields = {
                        Id: id,
                        [WOLI_LINETYPE.fieldApiName]:     edit.lineType || edit._lineType || 'Travel',
                        [WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
                        [WOLI_WORKTYPE.fieldApiName]:     edit.workTypeId || null,
                        [WOLI_STARTDATE.fieldApiName]:    edit.startDate || null,
                        [WOLI_ENDDATE.fieldApiName]:      edit.endDate   || null,
                        ...this._optionalClearedFields(edit, {
                            assetId: WOLI_ASSETID.fieldApiName,
                            inspectionOutcome: WOLI_INSPECTION_OUTCOME.fieldApiName
                        }),
                        ...this._buildDurationFields(edit.startDate, edit.endDate),
                        ...this._buildBillingPersistFields(edit)
                    };
                } else if (schema === 'labor') {
                    fields = {
                        Id: id,
                        [WOLI_LINETYPE.fieldApiName]:     edit.lineType || edit._lineType || 'Labor',
                        [WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
                        [WOLI_WORKTYPE.fieldApiName]:     edit.workTypeId || null,
                        [WOLI_ASSETID.fieldApiName]:      edit.assetId || null,
                        [WOLI_REPAIRCODE.fieldApiName]:   edit.repairCodeId || null,
                        [WOLI_STARTDATE.fieldApiName]:    edit.startDate || null,
                        [WOLI_ENDDATE.fieldApiName]:      edit.endDate   || null,
                        [WOLI_INSPECTION_OUTCOME.fieldApiName]: edit.inspectionOutcome || null,
                        ...this._buildDurationFields(edit.startDate, edit.endDate),
                        ...this._buildBillingPersistFields(edit)
                    };
                } else if (schema === 'productServiced') {
                    fields = {
                        Id: id,
                        [WOLI_LINETYPE.fieldApiName]:     LINE_TYPE_PRODUCT_SERVICED,
                        [WOLI_WORKTYPE.fieldApiName]:     edit.workTypeId || null,
                        [WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
                        [WOLI_ASSETID.fieldApiName]:      edit.assetId,
                        [WOLI_INSPECTION_OUTCOME.fieldApiName]: edit.inspectionOutcome || null,
                        [WOLI_STATUS.fieldApiName]: edit.lineStatus || LINE_STATUS_NEW,
                        ...this._repairCenterPersistFields(edit),
                        ...this._buildBillingPersistFields({
                            billingType: edit.billingType || BILLING_TYPE_NON_BILLABLE
                        })
                    };
                } else if (schema === 'expense') {
                    // Field Service mobile rejects new Expense custom fields on uiRecordApi drafts.
                    await saveExpense({ fields: this._expenseUpdateFields(id, edit) });
                    okIds.push(id);
                    this._applyExpenseUpdate(id, edit);
                    continue;
                } else if (schema === 'asset_time') {
                    fields = {
                        Id: id,
                        [WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
                        [WOLI_ASSETID.fieldApiName]:      edit.assetId,
                        [WOLI_STARTDATE.fieldApiName]:    edit.startDate || null,
                        [WOLI_ENDDATE.fieldApiName]:      edit.endDate   || null,
                        ...this._buildDurationFields(edit.startDate, edit.endDate)
                    };
                } else {
                    fields = {
                        Id: id,
                        [WOLI_DESCRIPTION.fieldApiName]: edit.desc,
                        [WOLI_DURATION.fieldApiName]:    Number(edit.duration) || 0
                        // UnitPrice omitted: requires Product (PricebookEntryId) on the WOLI
                    };
                }
                // eslint-disable-next-line no-await-in-loop
                await updateRecord({ fields });
                okIds.push(id);
                if (schema === 'productServiced') {
                    inspectionStamps.push({
                        assetId: edit.assetId,
                        inspectionOutcome: edit.inspectionOutcome,
                        markServiced: edit.lineStatus === LINE_STATUS_COMPLETED
                    });
                }
                if (schema === 'expense') {
                    this._applyExpenseUpdate(id, edit);
                }
            } catch (err) {
                failedEdits[id] = edit;
                this.editErrors = {
                    ...this.editErrors,
                    [id]: this._errorMessage(err)
                };
            }
        }
        let inlineMobilePictureError = null;
        let waitingPicturesClaimed = false;
        for (const a of pendingAdds) {
            try {
                const schema = a._schema ?? 'generic';
                let fields;
                if (schema === 'travel' || schema === 'labor') {
                    fields = {
                        [WOLI_WORKORDERID.fieldApiName]:  this.recordId,
                        [WOLI_LINETYPE.fieldApiName]:     a._lineType,
                        [WOLI_ASSIGNED_RES.fieldApiName]: a.assignedResourceId,
                        [WOLI_STARTDATE.fieldApiName]:    a.startDate || null,
                        [WOLI_ENDDATE.fieldApiName]:      a.endDate   || null,
                        ...this._buildDurationFields(a.startDate, a.endDate),
                        ...this._usageConsumptionRecordTypeFields(),
                        ...this._nonBillableBillingFields()
                    };
                } else if (schema === 'productServiced') {
                    fields = {
                        [WOLI_WORKORDERID.fieldApiName]: this.recordId,
                        [WOLI_LINETYPE.fieldApiName]: LINE_TYPE_PRODUCT_SERVICED,
                        [WOLI_ASSETID.fieldApiName]: a.assetId,
                        ...this._productServicedRecordTypeFields(),
                        ...this._repairCenterPersistFields(a),
                        [WOLI_STATUS.fieldApiName]: a.lineStatus || LINE_STATUS_NEW
                    };
                    if (a._bulkAssetLink) {
                        const workTypeId = a.workTypeId || this.woWorkTypeId;
                        const assignedResourceId = a.assignedResourceId || this._defaultAssignedResourceId();
                        if (workTypeId) {
                            fields[WOLI_WORKTYPE.fieldApiName] = workTypeId;
                        }
                        if (assignedResourceId) {
                            fields[WOLI_ASSIGNED_RES.fieldApiName] = assignedResourceId;
                        }
                        if (a.inspectionOutcome) {
                            fields[WOLI_INSPECTION_OUTCOME.fieldApiName] = a.inspectionOutcome;
                        }
                    } else {
                        fields = {
                            ...fields,
                            [WOLI_WORKTYPE.fieldApiName]: a.workTypeId || null,
                            [WOLI_ASSIGNED_RES.fieldApiName]: a.assignedResourceId,
                            [WOLI_INSPECTION_OUTCOME.fieldApiName]: a.inspectionOutcome || null,
                            ...this._nonBillableBillingFields()
                        };
                    }
                } else if (schema === 'expense') {
                    const expenseId = await saveExpense({ fields: this._expenseCreateFields(a) });
                    if (expenseId) {
                        okIds.push(expenseId);
                        this._applyExpenseCreate(expenseId, a);
                    }
                    continue;
                } else if (schema === 'asset_time') {
                    fields = {
                        [WOLI_WORKORDERID.fieldApiName]:  this.recordId,
                        [WOLI_LINETYPE.fieldApiName]:     a._lineType,
                        [WOLI_ASSIGNED_RES.fieldApiName]: a.assignedResourceId,
                        [WOLI_ASSETID.fieldApiName]:      a.assetId,
                        [WOLI_STARTDATE.fieldApiName]:    a.startDate || null,
                        [WOLI_ENDDATE.fieldApiName]:      a.endDate   || null,
                        ...this._buildDurationFields(a.startDate, a.endDate)
                    };
                } else {
                    fields = {
                        [WOLI_WORKORDERID.fieldApiName]: this.recordId,
                        [WOLI_LINETYPE.fieldApiName]:    a._lineType,
                        [WOLI_DESCRIPTION.fieldApiName]: a.desc,
                        [WOLI_DURATION.fieldApiName]:    Number(a.duration) || 0,
                        DurationType:                    'Hours'
                        // UnitPrice omitted: requires Product (PricebookEntryId) on the WOLI
                    };
                }
                const apiName = schema === 'expense'
                    ? EXPENSE_OBJECT.objectApiName
                    : WOLI_OBJECT.objectApiName;
                // eslint-disable-next-line no-await-in-loop
                const result = await createRecord({ apiName, fields });
                if (result?.id) {
                    okIds.push(result.id);
                    if (schema === 'productServiced') {
                        inspectionStamps.push({
                            assetId: a.assetId,
                            inspectionOutcome: a.inspectionOutcome,
                            markServiced: a.lineStatus === LINE_STATUS_COMPLETED
                        });
                        if (a.pictures?.length) {
                            try {
                                await linkFilesToRecord({
                                    recordId: result.id,
                                    contentDocumentIds: a.pictures.map(picture => picture.contentDocumentId)
                                });
                            } catch (linkErr) {
                                this._toast('Picture was not saved', this._errorMessage(linkErr), 'error');
                            }
                        }
                        if (a._tempId) {
                            createdProductServicedLineByTempId[a._tempId] = result.id;
                        }
                        const waitingPictures = !waitingPicturesClaimed
                            ? (this._picturesWaitingForNextLine || [])
                            : [];
                        const picturesToUpload = [
                            ...(a.mobilePictures || []),
                            ...waitingPictures
                        ];
                        if (picturesToUpload.length) {
                            waitingPicturesClaimed = true;
                            try {
                                await this._uploadStagedMobilePictures(result.id, picturesToUpload);
                            } catch (pictureErr) {
                                const message = this._errorMessage(pictureErr);
                                inlineMobilePictureError = inlineMobilePictureError || message;
                                this._toast(
                                    'Picture kept on the line',
                                    `${message} The picture is still on the line. Tap Save All to try the upload again.`,
                                    'warning'
                                );
                            }
                            this._picturesWaitingForNextLine = [];
                        }
                    }
                    if (schema === 'expense') {
                        this._applyExpenseCreate(result.id, a);
                    }
                }
            } catch (err) {
                failedAdds.push(a);
                this.editErrors = {
                    ...this.editErrors,
                    [a._tempId]: this._errorMessage(err)
                };
            }
        }

        if (Object.keys(createdProductServicedLineByTempId).length) {
            this._stagedMobilePictureSaves = (this._stagedMobilePictureSaves || []).filter(
                item => !(
                    item.scope === 'line'
                    && item.displayRecordId
                    && createdProductServicedLineByTempId[item.displayRecordId]
                )
            );
        }

        let assetInspectionError = null;
        try {
            await this._stampSavedAssetInspections(inspectionStamps);
        } catch (err) {
            assetInspectionError = this._errorMessage(err);
        }

        let mobilePictureError = inlineMobilePictureError || null;
        let mobilePictureUploadCount = 0;
        try {
            mobilePictureUploadCount = await this._flushStagedMobilePictureSaves(
                createdProductServicedLineByTempId
            );
        } catch (err) {
            mobilePictureError = mobilePictureError || this._errorMessage(err);
        }

        // ONE cache invalidation + GraphQL refresh at the end of the batch.
        // Per-op invalidation mid-batch triggers overlapping LDS reconciliation
        // which can destabilise the draft queue.
        try {
            const refs = [{ recordId: this.recordId }, ...okIds.map(id => ({ recordId: id }))];
            notifyRecordUpdateAvailable(refs);
        } catch (e) { /* swallow — surfaced via toast below */ }
        try {
            await refreshGraphQL(this.graphqlResult);
        } catch (e) { /* swallow — surfaced via toast below */ }
        try {
            await refreshGraphQL(this.expensesGraphqlResult);
        } catch (e) { /* swallow — surfaced via toast below */ }
        try {
            await this._refreshExpenseBillableFields();
        } catch (e) { /* swallow — surfaced via toast below */ }
        try {
            await this._loadMobileDevicePictures({ extraRecordIds: okIds });
        } catch (e) { /* swallow — surfaced via toast below */ }

        // Re-populate pending state with ONLY the failed operations
        this._pendingDeletes = failedDeletes;
        this._pendingEdits   = failedEdits;
        this._pendingAdds    = failedAdds;

        // Clear in-flight form state (edit toggles + add forms) either way
        this.editStateMap = {};
        this._activeProductServicedLineIdForPicture = null;
        this.showAddForm  = EMPTY_ADD_FORM_VISIBILITY();
        this.addFormState = this._emptyAddFormState();
        this._closeMultiAssetPicker();

        this._saving = false;

        const anyFailed = Object.keys(failedDeletes).length
                        + Object.keys(failedEdits).length
                        + failedAdds.length;
        const savedCount = okIds.length + mobilePictureUploadCount;

        if (anyFailed === 0 && !assetInspectionError && !mobilePictureError) {
            this._toast('Saved', `${savedCount} change(s) saved.`, 'success');
        } else if (anyFailed === 0 && !mobilePictureError) {
            this._toast(
                'Partial Save',
                `Lines were saved, but the Asset inspection was not updated. ${assetInspectionError}`,
                'warning'
            );
        } else if (anyFailed === 0 && mobilePictureError) {
            this._toast(
                'Partial Save',
                `Lines were saved, but a picture was not uploaded. ${mobilePictureError}`,
                'warning'
            );
        } else {
            const detail = this._firstSaveErrorMessage(failedEdits, failedAdds);
            this._toast(
                'Partial Save',
                detail
                    ? `${anyFailed} change(s) failed: ${detail}`
                    : `${anyFailed} change(s) failed to save. Review the highlighted lines and try again.`,
                'warning'
            );
        }
    }

    /**
     * @description Copy a saved Product Serviced inspection onto the Asset.
     * @param stamps Saved lines with an Asset and an Inspection Outcome
     */
    async _stampSavedAssetInspections(stamps) {
        const payload = (stamps || []).filter(stamp => stamp?.assetId && stamp?.inspectionOutcome);
        if (!payload.length) {
            return;
        }
        await stampAssetInspections({ stamps: payload });
    }

    // ── Global Cancel / Discard ───────────────────────────────────────────────
    /**
     * @description Handle Discard All.
     */
    async handleDiscardAll() {
        if (!this.hasPendingChanges) {
            this.dispatchEvent(new CloseActionScreenEvent());
            return;
        }
        const confirmed = await LightningConfirm.open({
            message: 'Discard all unsaved changes?',
            variant: 'headerless',
            label:   'Confirm Discard'
        });
        if (!confirmed) return;
        this._resetDraft();
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    /**
     * @description Internal helper: Work Order Currency.
     */
    _workOrderCurrency() {
        return this._workOrder?.CurrencyIsoCode?.value ?? 'USD';
    }

    /**
     * @description Internal helper: Build Server Expense.
     */
    _buildServerExpense(id, {
        expenseType,
        transactionDate,
        amount,
        overrideCode,
        billableAmount,
        overrideBillableAmount
    }) {
        return {
            Id: id,
            ExpenseType:     { value: expenseType ?? '' },
            TransactionDate: { value: transactionDate },
            Amount:          { value: amount },
            OverrideCode__c: { value: overrideCode ?? '' },
            BillableAmount__c: { value: billableAmount },
            OverrideBillableAmount__c: { value: this._isTruthyFlag(overrideBillableAmount) }
        };
    }

    /**
     * @description Internal helper: Apply Expense Create.
     */
    _applyExpenseCreate(id, add) {
        const fields = this._expenseBillableSaveValues(add);
        this._rememberExpenseBillableFields(id, fields);
        this._upsertLocalExpense(this._buildServerExpense(id, {
            expenseType:     add.expenseType,
            transactionDate: add.transactionDate,
            amount:          fields.amount,
            overrideCode:   fields.overrideCode,
            billableAmount:  fields.billableAmount,
            overrideBillableAmount: fields.overrideBillableAmount
        }));
    }

    /**
     * @description Internal helper: Apply Expense Update.
     */
    _applyExpenseUpdate(id, edit) {
        const fields = this._expenseBillableSaveValues(edit);
        this._rememberExpenseBillableFields(id, fields);
        this._upsertLocalExpense(this._buildServerExpense(id, {
            expenseType:     edit.expenseType,
            transactionDate: edit.transactionDate,
            amount:          fields.amount,
            overrideCode:   fields.overrideCode,
            billableAmount:  fields.billableAmount,
            overrideBillableAmount: fields.overrideBillableAmount
        }));
    }

    /**
     * @description Internal helper: Apply Expense Delete.
     */
    _applyExpenseDelete(id) {
        const key = this._expenseIdKey(id);
        const nextBillable = { ...this._expenseBillableById };
        delete nextBillable[key];
        this._expenseBillableById = nextBillable;
        this._serverExpensesFromGraphql = this._serverExpensesFromGraphql
            .filter(e => this._expenseIdKey(e.Id) !== key);
        this._serverExpensesFromRelatedList = this._serverExpensesFromRelatedList
            .filter(e => this._expenseIdKey(e.Id) !== key);
        this._rebuildServerExpenses();
    }

    /**
     * @description Internal helper: Upsert Local Expense.
     */
    _upsertLocalExpense(expense) {
        this._serverExpensesFromRelatedList = [
            ...this._serverExpensesFromRelatedList.filter(e => e.Id !== expense.Id),
            expense
        ];
        this._rebuildServerExpenses();
    }

    /**
     * @description Internal helper: Expense Create Fields.
     */
    _expenseCreateFields(add) {
        const fields = this._expenseBillableSaveValues(add);
        return {
            [EXPENSE_EXPENSETYPE.fieldApiName]:       add.expenseType,
            [EXPENSE_TRANSACTIONDATE.fieldApiName]:   add.transactionDate || null,
            [EXPENSE_AMOUNT.fieldApiName]:            fields.amount,
            [OVERRIDE_CODE.fieldApiName]:            fields.overrideCode || null,
            [EXPENSE_BILLABLE_AMOUNT.fieldApiName]:   fields.billableAmount,
            [EXPENSE_OVERRIDE_BILLABLE.fieldApiName]: fields.overrideBillableAmount,
            [EXPENSE_WORKORDER.fieldApiName]:         this.recordId,
            [EXPENSE_CURRENCY.fieldApiName]:          this._workOrderCurrency(),
            [EXPENSE_OWNER.fieldApiName]:             USER_ID
        };
    }

    /**
     * @description Internal helper: Expense Update Fields.
     */
    _expenseUpdateFields(id, edit) {
        const fields = this._expenseBillableSaveValues(edit);
        return {
            Id: id,
            [EXPENSE_EXPENSETYPE.fieldApiName]:       edit.expenseType,
            [EXPENSE_TRANSACTIONDATE.fieldApiName]:   edit.transactionDate || null,
            [EXPENSE_AMOUNT.fieldApiName]:            fields.amount,
            [OVERRIDE_CODE.fieldApiName]:            fields.overrideCode || null,
            [EXPENSE_BILLABLE_AMOUNT.fieldApiName]:   fields.billableAmount,
            [EXPENSE_OVERRIDE_BILLABLE.fieldApiName]: fields.overrideBillableAmount
        };
    }

    /**
     * @description Resolves Amount, Billable Amount, Override, and Override Code for save.
     */
    _expenseBillableSaveValues({
        amount,
        billableAmount,
        overrideBillableAmount,
        overrideCode
    }) {
        const override = this._isTruthyFlag(overrideBillableAmount);
        const resolvedAmount = Number(amount) || 0;
        const resolvedBillable = override ? Number(billableAmount) : resolvedAmount;
        return {
            amount: resolvedAmount,
            billableAmount: Number.isNaN(resolvedBillable) ? resolvedAmount : resolvedBillable,
            overrideBillableAmount: override,
            overrideCode: overrideCode || ''
        };
    }

    /**
     * @description Copies Amount into Billable Amount unless Override is selected.
     * Unchecking Override resets Billable Amount to Amount.
     */
    _applyExpenseBillableSync(state, changedField) {
        const next = { ...state };
        if (changedField === 'overrideBillableAmount') {
            next.overrideBillableAmount = this._isTruthyFlag(next.overrideBillableAmount);
        }
        const override = this._isTruthyFlag(next.overrideBillableAmount);
        if (
            (changedField === 'amount' && !override)
            || (changedField === 'overrideBillableAmount' && !override)
        ) {
            next.billableAmount = next.amount;
        }
        return next;
    }

    /**
     * @description True for boolean true or the string "true".
     */
    _isTruthyFlag(value) {
        return value === true || value === 'true';
    }

    /**
     * @description Formats a currency amount for the locked Billable Amount display.
     */
    _fmtBillableAmount(value) {
        const n = Number(value);
        if (value === '' || value == null || Number.isNaN(n)) {
            return '0.00';
        }
        return n.toFixed(2);
    }

    /**
     * @description Internal helper: First Save Error Message.
     */
    _firstSaveErrorMessage(failedEdits, failedAdds) {
        for (const id of Object.keys(failedEdits)) {
            const msg = this.editErrors[id];
            if (msg) return msg;
        }
        for (const a of failedAdds) {
            const msg = this.editErrors[a._tempId];
            if (msg) return msg;
        }
        return null;
    }

    /**
     * @description Internal helper: Error Message.
     */
    _errorMessage(err) {
        return this._ldsErrorMessage(err) || this._serializeError(err) || 'Save failed.';
    }

    /**
     * @description Internal helper: Serialize Error.
     */
    _serializeError(err) {
        if (!err) return null;
        try {
            const payload = err.body ?? err;
            const text = typeof payload === 'string' ? payload : JSON.stringify(payload);
            return text && text !== '{}' ? text : null;
        } catch (e) {
            return err.message ?? null;
        }
    }

    /**
     * @description Internal helper: Lds Error Message.
     */
    _ldsErrorMessage(err) {
        if (!err) return null;
        let body = err.body;
        if (typeof body === 'string') {
            try {
                body = JSON.parse(body);
            } catch (e) {
                return body;
            }
        }
        if (body?.errorMessage) return body.errorMessage;
        if (body?.message) return body.message;
        const pageErrors = body?.pageErrors;
        if (Array.isArray(pageErrors) && pageErrors.length) {
            return pageErrors.map(e => e.message).filter(Boolean).join(' ');
        }
        const fieldErrors = body?.fieldErrors;
        if (fieldErrors && typeof fieldErrors === 'object') {
            const msgs = Object.values(fieldErrors)
                .flat()
                .map(e => e?.message)
                .filter(Boolean);
            if (msgs.length) return msgs.join(' ');
        }
        const outputs = body?.output?.errors;
        if (Array.isArray(outputs) && outputs.length) {
            return outputs.map(e => e.message).filter(Boolean).join(' ');
        }
        return err.message ?? null;
    }

    /**
     * @description Internal helper: Default Assigned Resource Id.
     */
    _defaultAssignedResourceId() {
        return this._currentUserServiceResourceId ?? null;
    }

    /**
     * @description Internal helper: Resolve Assigned Resource Id.
     */
    _resolveAssignedResourceId(...values) {
        for (const value of values) {
            if (value) return value;
        }
        return this._defaultAssignedResourceId();
    }

    /**
     * @description Internal helper: Assigned Resource Name For Id.
     */
    _assignedResourceNameForId(resourceId) {
        if (resourceId && resourceId === this._currentUserServiceResourceId) {
            return this._currentUserServiceResourceName;
        }
        return '';
    }

    /**
     * @description Internal helper: Normalize Expense From Lds.
     */
    _normalizeExpenseFromLds(record) {
        const f = record.fields ?? {};
        const val = (api) => f[api]?.value ?? null;
        return {
            Id: record.id,
            ExpenseType:     { value: val('ExpenseType') ?? '' },
            TransactionDate: { value: val('TransactionDate') },
            Amount:          { value: val('Amount') },
            OverrideCode__c: { value: val('OverrideCode__c') ?? '' },
            BillableAmount__c: { value: val('BillableAmount__c') },
            OverrideBillableAmount__c: { value: val('OverrideBillableAmount__c') === true }
        };
    }

    /**
     * @description Internal helper: Rebuild Server Expenses.
     */
    _rebuildServerExpenses() {
        const byId = new Map();
        for (const e of this._serverExpensesFromRelatedList) {
            const key = this._expenseIdKey(e.Id);
            if (key) byId.set(key, e);
        }
        for (const e of this._serverExpensesFromGraphql) {
            const key = this._expenseIdKey(e.Id);
            if (key) byId.set(key, this._mergeExpenseBillableFields(byId.get(key), e));
        }
        for (const [key, overlay] of Object.entries(this._expenseBillableById)) {
            const existing = byId.get(key);
            if (existing) {
                byId.set(key, this._applyExpenseBillableOverlay(existing, overlay));
            }
        }
        this._serverExpenses = [...byId.values()];
    }

    /**
     * @description Loads Billable Amount, Override, and Override Code from Apex.
     *              Field Service GraphQL often returns those custom fields blank.
     */
    async _refreshExpenseBillableFields() {
        if (!this.recordId) {
            return;
        }
        try {
            const rows = await listExpenseBillableFields({ workOrderId: this.recordId });
            const next = {};
            for (const row of rows ?? []) {
                const key = this._expenseIdKey(row.id);
                if (key) {
                    next[key] = row;
                }
            }
            this._expenseBillableById = { ...this._expenseBillableById, ...next };
            this._rebuildServerExpenses();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('woDebrief listExpenseBillableFields failed', e);
        }
    }

    /**
     * @description 15-character Id key so 15- and 18-character Salesforce Ids match.
     */
    _expenseIdKey(id) {
        return id ? String(id).substring(0, 15) : null;
    }

    /**
     * @description Keeps custom billable fields when GraphQL/related-list omits them.
     */
    _mergeExpenseBillableFields(previous, incoming) {
        if (!previous) {
            return incoming;
        }
        if (!incoming) {
            return previous;
        }
        return this._applyExpenseBillableOverlay(incoming, {
            overrideCode: this._expenseFieldValue(incoming.OverrideCode__c, previous.OverrideCode__c),
            billableAmount: this._expenseFieldValue(incoming.BillableAmount__c, previous.BillableAmount__c),
            overrideBillableAmount: this._expenseFieldValue(
                incoming.OverrideBillableAmount__c,
                previous.OverrideBillableAmount__c
            )
        });
    }

    /**
     * @description Prefers a present field value over a blank GraphQL/related-list value.
     */
    _expenseFieldValue(preferred, fallback) {
        if (preferred && preferred.value !== undefined && preferred.value !== null && preferred.value !== '') {
            return preferred.value;
        }
        if (preferred && (preferred.value === false || preferred.value === 0)) {
            return preferred.value;
        }
        return fallback?.value;
    }

    /**
     * @description Applies Apex or locally saved billable fields onto an Expense record.
     */
    _applyExpenseBillableOverlay(record, overlay) {
        if (!record || !overlay) {
            return record;
        }
        return {
            ...record,
            OverrideCode__c: { value: overlay.overrideCode ?? '' },
            BillableAmount__c: { value: overlay.billableAmount },
            OverrideBillableAmount__c: { value: overlay.overrideBillableAmount === true }
        };
    }

    /**
     * @description Stores locally saved billable fields so GraphQL refresh cannot blank them.
     */
    _rememberExpenseBillableFields(id, billable) {
        const key = this._expenseIdKey(id);
        if (!key || !billable) {
            return;
        }
        this._expenseBillableById = {
            ...this._expenseBillableById,
            [key]: {
                id,
                overrideCode: billable.overrideCode || '',
                billableAmount: billable.billableAmount,
                overrideBillableAmount: this._isTruthyFlag(billable.overrideBillableAmount)
            }
        };
    }

    /**
     * @description Internal helper: Seed Expense Edit Entry.
     */
    _seedExpenseEditEntry(expense) {
        const amount = expense.Amount?.value ?? 0;
        const overrideBillableAmount = this._isTruthyFlag(expense.OverrideBillableAmount__c?.value);
        return {
            _schema:            'expense',
            _entity:            'Expense',
            expenseType:        expense.ExpenseType?.value     ?? '',
            transactionDate:    expense.TransactionDate?.value ?? '',
            amount,
            overrideCode:      expense.OverrideCode__c?.value ?? '',
            overrideBillableAmount,
            billableAmount:     overrideBillableAmount
                ? (expense.BillableAmount__c?.value ?? amount)
                : amount
        };
    }

    /**
     * @description Internal helper: Reset Draft.
     */
    _resetDraft() {
        this._pendingEdits   = {};
        this._pendingDeletes = {};
        this._pendingAdds    = [];
        this._stagedMobilePictureSaves = [];
        this._picturesWaitingForNextLine = [];
        this._dropUnsavedMobilePicturePreviews();
        this.editStateMap    = {};
        this.showAddForm     = EMPTY_ADD_FORM_VISIBILITY();
        this.addFormState    = this._emptyAddFormState();
        this._closeMultiAssetPicker();
        this.editErrors      = {};
        this.addErrors       = {};
    }

    // Single shape that covers all schemas. Each tab's form reads only the
    // fields it needs; unused fields are ignored. Reset between toggles so
    // values from a previous tab don't leak into the next one.
    /**
     * @description Internal helper: Empty Add Form State.
     */
    _emptyAddFormState() {
        return {
            lineType:           '',
            // generic + expense schemas
            desc:               '',
            unitPrice:          '',
            // travel + labor + asset_time schemas
            assignedResourceId: this._defaultAssignedResourceId(),
            workTypeId:         null,
            startDate:          '',
            endDate:            '',
            // labor + asset_time schemas
            assetId:            null,
            // labor schema
            repairCodeId:       null,
            inspectionOutcome:  '',
            serialNumber:       '',
            model:              '',
            departmentId:       null,
            reportedProblem:    '',
            notInspectedReason: '',
            additionalServices: false,
            insulationPowderCoating: [],
            pictures:           [],
            mobilePictures:     [],
            canceled:           false,
            lineStatus:         LINE_STATUS_NEW,
            billingType:        BILLING_TYPE_BILLABLE,
            discount:           0,
            // expense schema
            expenseType:        '',
            transactionDate:    this._todayDateString(),
            amount:             '',
            overrideCode:      '',
            billableAmount:     '',
            overrideBillableAmount: false,
            quantity:           '',
            // shared
            duration:           ''
        };
    }

    // Autosave hook — every inline-edit field/lookup change funnels through
    // here. For pending-add lines the entry in `_pendingAdds` is mutated
    // directly. For existing server lines, on the FIRST change we seed
    // `_pendingEdits[id]` with a full schema-shaped snapshot of server values
    // (so the `handleSaveAll` payload builder always has every required field
    // even if the user only touched one), then merge in subsequent changes.
    /**
     * @description Internal helper: Stage Edit.
     */
    _stageEdit(id, field, value) {
        if (this._pendingAdds.some(a => a._tempId === id)) {
            this._pendingAdds = this._pendingAdds.map(a => {
                if (a._tempId !== id) return a;
                let next = { ...a, [field]: value };
                if (field === 'billingType') {
                    next.discount = this._discountForBillingType(value);
                }
                if (
                    (a._schema === 'expense' || a._entity === 'Expense')
                    && (field === 'amount' || field === 'overrideBillableAmount')
                ) {
                    next = this._applyExpenseBillableSync(next, field);
                }
                return next;
            });
            return;
        }
        const expense = this._serverExpenses.find(e => e.Id === id);
        if (expense) {
            const existing = this._pendingEdits[id];
            let entry = existing
                ? { ...existing, [field]: value }
                : { ...this._seedExpenseEditEntry(expense), [field]: value };
            if (field === 'amount' || field === 'overrideBillableAmount') {
                entry = this._applyExpenseBillableSync(entry, field);
            }
            this._pendingEdits = { ...this._pendingEdits, [id]: entry };
            return;
        }
        const line = this._serverLines.find(l => l.Id === id);
        if (!line) return;
        const existing = this._pendingEdits[id];
        const entry = existing
            ? { ...existing, [field]: value }
            : { ...this._seedEditEntry(line), [field]: value };
        if (field === 'billingType') {
            entry.discount = this._discountForBillingType(value);
        }
        this._pendingEdits = { ...this._pendingEdits, [id]: entry };
    }

    // Build a full schema-shaped pending-edit entry from server values.
    // Used as the seed on the first inline-edit change to a server row so
    // the entry always carries every field the save payload builder needs.
    /**
     * @description Internal helper: Seed Edit Entry.
     */
    _seedEditEntry(line) {
        const schema = this._schemaForLineType(line.LineType__c?.value);
        const lineType = line.LineType__c?.value ?? '';
        const base = {
            lineType
        };
        if (schema === 'travel') {
            return {
                _schema:            'travel',
                ...base,
                assignedResourceId: this._resolveAssignedResourceId(line.AssignedResource__c?.value),
                workTypeId:         line.WorkTypeId?.value ?? null,
                startDate:          line.StartDate?.value ?? '',
                endDate:            line.EndDate?.value   ?? '',
                billingType:        this._normalizeBillingType(line.BillingType__c?.value),
                discount:           this._discountForBillingType(line.BillingType__c?.value)
            };
        }
        if (schema === 'labor') {
            return {
                _schema:            'labor',
                ...base,
                assignedResourceId: this._resolveAssignedResourceId(line.AssignedResource__c?.value),
                workTypeId:         line.WorkTypeId?.value ?? null,
                assetId:            line.AssetId?.value          ?? null,
                repairCodeId:       line.RepairCode__c?.value    ?? null,
                startDate:          line.StartDate?.value        ?? '',
                endDate:            line.EndDate?.value          ?? '',
                inspectionOutcome:  line.InspectionOutcome__c?.value ?? '',
                billingType:        this._normalizeBillingType(line.BillingType__c?.value),
                discount:           this._discountForBillingType(line.BillingType__c?.value)
            };
        }
        if (schema === 'productServiced') {
            return {
                _schema:            'productServiced',
                ...base,
                assignedResourceId: this._resolveAssignedResourceId(line.AssignedResource__c?.value),
                workTypeId:         line.WorkTypeId?.value ?? null,
                assetId:            line.AssetId?.value ?? null,
                inspectionOutcome:  line.InspectionOutcome__c?.value ?? '',
                lineStatus:         line.Status?.value || LINE_STATUS_NEW,
                ...this._savedRepairSeed(line.Id),
                billingType:        line.BillingType__c?.value || BILLING_TYPE_NON_BILLABLE,
                discount:           0
            };
        }
        if (schema === 'asset_time') {
            return {
                _schema:            'asset_time',
                assignedResourceId: this._resolveAssignedResourceId(line.AssignedResource__c?.value),
                assetId:            line.AssetId?.value             ?? null,
                startDate:          line.StartDate?.value           ?? '',
                endDate:            line.EndDate?.value             ?? ''
            };
        }
        return {
            _schema:   'generic',
            desc:      line.Description?.value ?? '',
            duration:  line.Duration?.value    ?? 0,
            unitPrice: line.UnitPrice?.value   ?? 0
        };
    }

    /**
     * @description Internal helper: Validate Generic.
     */
    _validateGeneric({ desc, duration }) {
        if (!desc || String(desc).trim() === '') return 'Description is required.';
        if (!duration || Number(duration) <= 0)   return 'Duration must be greater than 0.';
        return null;
    }

    /**
     * @description Internal helper: Validate Travel.
     */
    _validateTravel({ assignedResourceId, startDate, endDate }) {
        return this._validateTimeRange({ assignedResourceId, startDate, endDate });
    }

    /**
     * @description Internal helper: Validate Labor.
     */
    _validateLabor({ assignedResourceId, startDate, endDate }) {
        return this._validateTimeRange({ assignedResourceId, startDate, endDate });
    }

    /**
     * @description Card color for a Product Serviced line. Text stays dark.
     *              Red Canceled, green Completed, orange when the line has no picture
     *              or Billing Type is Warranty, SVC Warranty, or Courtesy, yellow In Progress,
     *              blue New.
     * @param {Object} line Line view model
     * @return {string}
     */
    _productServicedCardClass(line) {
        const status = line?.lineStatus;
        if (status === LINE_STATUS_CANCELED) return 'woli-card woli-card_canceled';
        if (status === LINE_STATUS_COMPLETED) return 'woli-card woli-card_completed';
        if (this._productServicedNeedsOrange(line)) return 'woli-card woli-card_billing';
        if (status === LINE_STATUS_IN_PROGRESS) return 'woli-card woli-card_pending-outcome';
        if (status === LINE_STATUS_NEW) return 'woli-card woli-card_new';
        return 'woli-card';
    }

    /**
     * @description Orange highlight for a missing picture or Warranty, SVC Warranty, or Courtesy.
     * @param {Object} line Line view model
     * @return {boolean}
     */
    _productServicedNeedsOrange(line) {
        const billingType = line?.billingType || line?.editBillingType;
        if (HIGHLIGHT_BILLING_TYPES.has(billingType)) return true;
        return line?.hasMobilePictures !== true;
    }

    /**
     * @description Red when canceled, green when completed, yellow while required fields are missing.
     * @param {string} lineStatus Work order line status
     * @param {boolean} isComplete Required Product Serviced fields are filled
     * @return {string}
     */
    _productServicedTone(lineStatus, isComplete) {
        if (lineStatus === LINE_STATUS_CANCELED) return 'canceled';
        if (lineStatus === LINE_STATUS_COMPLETED) return 'completed';
        if (lineStatus === LINE_STATUS_IN_PROGRESS || !isComplete) return 'incomplete';
        return '';
    }

    /**
     * @description True when the Product Serviced line has the fields required to complete it.
     * @param {Object} source Staged line
     * @return {boolean}
     */
    _isProductServicedComplete(source) {
        if (!source?.assetId) return false;
        if (!source._bulkAssetLink) {
            if (!source.workTypeId || !source.assignedResourceId) return false;
        }
        const outcome = source.inspectionOutcome == null ? '' : String(source.inspectionOutcome).trim();
        if (!outcome) return false;
        if (outcome !== DO_NOT_USE_P0) return true;
        return !!String(source.serialNumber || '').trim()
            && !!String(source.model || '').trim()
            && !!source.departmentId
            && !!String(source.reportedProblem || '').trim()
            && !!String(source.notInspectedReason || '').trim();
    }

    /**
     * @description Current Product Serviced values for a line, or the add form when lineId is empty.
     * @param {string|null} lineId Line or temp Id
     * @return {Object|null}
     */
    _productServicedSource(lineId) {
        if (!lineId) {
            return { ...this.addFormState, _schema: 'productServiced' };
        }
        const add = this._pendingAdds.find(item => item._tempId === lineId);
        if (add) {
            return add._schema === 'productServiced' ? add : null;
        }
        if (this._pendingEdits[lineId]?._schema === 'productServiced') {
            return this._pendingEdits[lineId];
        }
        const line = this._serverLines.find(item => item.Id === lineId);
        if (!line || line.LineType__c?.value !== LINE_TYPE_PRODUCT_SERVICED) return null;
        return this._seedEditEntry(line);
    }

    /**
     * @description Mark a Product Serviced line Completed when Close is used and every required field is filled.
     * @param {string} lineId Line or temp Id
     */
    _applyProductServicedClose(lineId) {
        const source = this._productServicedSource(lineId);
        if (!source || source.lineStatus === LINE_STATUS_CANCELED) return;
        const isPendingAdd = this._pendingAdds.some(item => item._tempId === lineId);
        if (
            !isPendingAdd
            && source.inspectionOutcome === DO_NOT_USE_P0
            && !this._repairCenterLoaded
        ) {
            return;
        }
        if (this._isProductServicedComplete(source)) {
            if (source.lineStatus !== LINE_STATUS_COMPLETED) {
                this._stageEdit(lineId, 'lineStatus', LINE_STATUS_COMPLETED);
            }
            return;
        }
        if (source.lineStatus === LINE_STATUS_COMPLETED) {
            this._stageEdit(lineId, 'lineStatus', LINE_STATUS_NEW);
        }
    }

    /**
     * @description Ask for the Asset manufacturer, model, and department when Do Not Use (P0) is selected.
     * @param {string|null} lineId Line or temp Id, or null for the add form
     */
    _requestAssetRepairDefaults(lineId) {
        const source = this._productServicedSource(lineId);
        if (!source?.assetId || source.inspectionOutcome !== DO_NOT_USE_P0) return;
        this._repairDefaultLineId = lineId;
        const cached = this._assetDepartmentById[source.assetId];
        if (cached) {
            this._applyAssetRepairDefaults(lineId, source.assetId, cached);
            return;
        }
        this._repairDefaultAssetId = source.assetId;
    }

    /**
     * @description Write blank Make, Model, and Department from a loaded Asset.
     * @param {string|null} lineId Line or temp Id, or null for the add form
     * @param {{department: {id: string, name: string}|null, manufacturer: string, model: string}} asset Asset values
     */
    _applyAssetRepairDefaults(lineId, assetId, asset) {
        if (!asset) return;
        const source = this._productServicedSource(lineId);
        if (!source || source.inspectionOutcome !== DO_NOT_USE_P0) return;
        if (!this._sameSalesforceId(source.assetId, assetId)) return;
        const isPendingAdd = !lineId || this._pendingAdds.some(item => item._tempId === lineId);
        if (!isPendingAdd && !this._repairCenterLoaded) return;
        const saved = isPendingAdd ? {} : (this._repairCenterByLineId[lineId] || {});
        const patch = {};
        if (this._repairTextBlank(source.serialNumber) && this._repairTextBlank(saved.serialNumber) && asset.manufacturer) {
            patch.serialNumber = asset.manufacturer;
        }
        if (this._repairTextBlank(source.model) && this._repairTextBlank(saved.model) && asset.model) {
            patch.model = asset.model;
        }
        if (!source.departmentId && !saved.departmentId && asset.department?.id) {
            this._ensureDepartmentOption(asset.department);
            patch.departmentId = asset.department.id;
        }
        if (!Object.keys(patch).length) return;
        if (lineId) {
            Object.entries(patch).forEach(([field, value]) => this._stageEdit(lineId, field, value));
        } else {
            this.addFormState = { ...this.addFormState, ...patch };
        }
        if (patch.serialNumber || patch.model) {
            this._suppressBlankRepairClear = true;
            clearTimeout(this._blankRepairClearTimer);
            this._blankRepairClearTimer = setTimeout(() => {
                this._suppressBlankRepairClear = false;
            }, 400);
            this.repairFieldEpoch += 1;
        }
    }

    /**
     * @description Default blank return-order fields from the Asset when Do Not Use (P0) is selected.
     * @param {string|null} lineId Line or temp Id, or null for the add form
     */
    _defaultDepartmentForLine(lineId) {
        this._requestAssetRepairDefaults(lineId);
    }

    /**
     * @description True when Make, Model, or Department can still be defaulted.
     * @param {Object} source Current line values
     * @param {Object} saved Values already saved on the line
     * @return {boolean}
     */
    _repairDefaultsNeeded(source, saved) {
        return (this._repairTextBlank(source?.serialNumber) && this._repairTextBlank(saved?.serialNumber))
            || (this._repairTextBlank(source?.model) && this._repairTextBlank(saved?.model))
            || (!source?.departmentId && !saved?.departmentId);
    }

    /**
     * @description True when a return-order text field has no value.
     * @param {string} value Field value
     * @return {boolean}
     */
    _repairTextBlank(value) {
        return !String(value || '').trim();
    }

    /**
     * @description Ignore the empty change event fired when Make or Model is filled from the asset.
     * @param {string} field Changed field
     * @param {string|boolean} value New value
     * @return {boolean}
     */
    _ignoreBlankRepairClear(field, value) {
        return this._suppressBlankRepairClear
            && (field === 'serialNumber' || field === 'model')
            && this._repairTextBlank(value);
    }

    /**
     * @description Compare Salesforce Ids that may be 15 or 18 characters.
     * @param {string} left First Id
     * @param {string} right Second Id
     * @return {boolean}
     */
    _sameSalesforceId(left, right) {
        if (!left || !right) return false;
        return String(left).substring(0, 15) === String(right).substring(0, 15);
    }

    /**
     * @description Keep a defaulted Asset department visible in the Department list.
     * @param {{id: string, name: string}} department Department to show
     */
    _ensureDepartmentOption(department) {
        if (!department?.id) return;
        if (this.departmentOptions.some(option => option.value === department.id)) return;
        const option = { label: department.name || department.id, value: department.id };
        this._extraDepartmentOptions = [...(this._extraDepartmentOptions || []), option];
        this.departmentOptions = [...this.departmentOptions, option];
    }

    /**
     * @description Internal helper: Validate Product Serviced.
     */
    _validateProductServiced(payload) {
        const { workTypeId, assignedResourceId, assetId, inspectionOutcome } = payload;
        if (!assetId) return 'Asset is required.';
        if (payload.lineStatus === LINE_STATUS_CANCELED) return null;
        const repairError = this._validateRepairCenter(payload);
        if (repairError) return repairError;
        if (payload._bulkAssetLink) return null;
        if (!workTypeId) return 'Work Type is required.';
        if (!assignedResourceId) return 'Assigned Resource is required.';
        if (!inspectionOutcome) return 'Inspection Outcome is required.';
        return null;
    }

    /**
     * @description Required return-order fields when the outcome is Do Not Use (P0).
     * @param {Object} payload Staged Product Serviced line
     * @return {string|null}
     */
    _validateRepairCenter(payload) {
        if (payload?.inspectionOutcome !== DO_NOT_USE_P0) return null;
        if (!String(payload.serialNumber || '').trim()) return 'Make is required.';
        if (!String(payload.model || '').trim()) return 'Model is required.';
        if (!payload.departmentId) return 'Department is required.';
        if (!String(payload.notInspectedReason || '').trim()) return 'Not Inspected Reason is required.';
        if (!String(payload.reportedProblem || '').trim()) return 'Reported Problem is required.';
        return null;
    }

    /**
     * @description Internal helper: Validate Expense.
     */
    _validateExpense({
        expenseType,
        transactionDate,
        amount,
        overrideCode,
        overrideBillableAmount,
        billableAmount
    }) {
        if (!expenseType)                                            return 'Expense Type is required.';
        if (!transactionDate)                                        return 'Transaction Date is required.';
        if (amount === '' || amount == null || Number(amount) <= 0)  return 'Amount must be greater than 0.';
        if (this._isTruthyFlag(overrideBillableAmount)) {
            if (!overrideCode) {
                return 'Override Code is required when Override Billable Amount is selected.';
            }
            if (billableAmount === '' || billableAmount == null || Number.isNaN(Number(billableAmount))) {
                return 'Billable Amount is required when Override Billable Amount is selected.';
            }
        }
        return null;
    }

    /**
     * @description Internal helper: Validate Asset Time.
     */
    _validateAssetTime({ assignedResourceId, startDate, endDate }) {
        return this._validateTimeRange({ assignedResourceId, startDate, endDate });
    }

    /**
     * @description Internal helper: Validate Time Range.
     */
    _validateTimeRange({ assignedResourceId, startDate, endDate }) {
        if (!assignedResourceId)                  return 'Assigned Resource is required.';
        if (startDate && endDate && new Date(endDate).getTime() < new Date(startDate).getTime()) {
            return 'End Date must be the same as or after Start Date.';
        }
        return null;
    }

    // Resolve which validator to run for a given pending edit/add. We infer schema
    // from `_schema` on the entity (set when staged), falling back to the LineType
    // -> tab def lookup for older drafts that didn't carry the discriminator.
    /**
     * @description Internal helper: Validate For Schema.
     */
    _validateForSchema(schema, payload) {
        if (schema === 'time')     return this._validateTime(payload);
        if (schema === 'travel')     return this._validateTravel(payload);
        if (schema === 'labor')      return this._validateLabor(payload);
        if (schema === 'productServiced') return this._validateProductServiced(payload);
        if (schema === 'expense')    return this._validateExpense(payload);
        if (schema === 'asset_time') return this._validateAssetTime(payload);
        return this._validateGeneric(payload);
    }

    /**
     * @description Internal helper: Validate Time.
     */
    _validateTime(payload) {
        if (!payload.lineType || !TIME_LINE_TYPES.has(payload.lineType)) {
            return 'Line Type is required.';
        }
        const innerSchema = LINE_TYPE_TO_SCHEMA[payload.lineType];
        return this._validateForSchema(innerSchema, payload);
    }

    /**
     * @description Internal helper: Schema For Line Type.
     */
    _schemaForLineType(lineType) {
        return TYPE_TO_DEF[lineType]?.schema ?? 'generic';
    }

    /**
     * @description Billing Type API value, defaulting to Billable.
     * @param {string} value Picklist value
     * @return {string}
     */
    _normalizeBillingType(value) {
        return value || BILLING_TYPE_BILLABLE;
    }

    /**
     * @description Resolves Billing Type from edit/state/record, defaulting to Billable.
     * @param {Object} [edit]
     * @param {Object} [state]
     * @param {string} [recordValue]
     * @return {string}
     */
    _resolveBillingType(edit, state, recordValue) {
        return this._normalizeBillingType(state?.billingType ?? edit?.billingType ?? recordValue);
    }

    /**
     * @description 100% Discount when Billing Type is Courtesy; otherwise none.
     * @param {string} billingType
     * @return {number}
     */
    _discountForBillingType(billingType) {
        return this._normalizeBillingType(billingType) === BILLING_TYPE_COURTESY ? 100 : 0;
    }

    /**
     * @description Billing Type and Discount fields for LDS create/update.
     * @param {Object} payload Pending add or edit
     * @return {Object}
     */
    _buildBillingPersistFields(payload) {
        const billingType = this._normalizeBillingType(payload?.billingType);
        const fields = {
            [WOLI_BILLING_TYPE.fieldApiName]: billingType
        };
        if (billingType !== BILLING_TYPE_NON_BILLABLE) {
            fields[WOLI_DISCOUNT.fieldApiName] = this._discountForBillingType(billingType);
        }
        return fields;
    }

    /**
     * @description Display label for Billing Type.
     * @param {string} value Picklist API value
     * @return {string}
     */
    _fmtBillingType(value) {
        if (value == null || value === '') {
            return '';
        }
        return this.billingTypeOptions.find(option => option.value === value)?.label ?? value;
    }

    /**
     * @description Internal helper: Toast.
     */
    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    /**
     * @description GW-375 - Loads Mobile Device Pictures for this work order and its product serviced lines.
     */
    async _loadMobileDevicePictures(options = {}) {
        if (!this.recordId) {
            return;
        }
        const recordIdSet = new Set();
        const addRecordId = (value) => {
            const text = this._recordIdFromGraphql(value) ?? (value == null ? '' : String(value).trim());
            if (text) {
                recordIdSet.add(text);
            }
        };
        addRecordId(this._workOrder?.Id);
        addRecordId(this.recordId);
        for (const line of this._serverLines) {
            if (line?.LineType__c?.value !== LINE_TYPE_PRODUCT_SERVICED) {
                continue;
            }
            addRecordId(line.Id);
        }
        (options.extraRecordIds || []).forEach(addRecordId);
        const recordIds = [...recordIdSet];
        if (!recordIds.length) {
            return;
        }
        const requestId = this._mobilePictureRequest + 1;
        this._mobilePictureRequest = requestId;
        try {
            const rows = await listMobileDevicePictures({ recordIdsCsv: recordIds.join(',') });
            if (this._mobilePictureRequest !== requestId) {
                return;
            }
            const keptPreviews = {};
            Object.values(this._mobilePicturesByRecordId || {}).forEach(pictures => {
                (pictures || []).forEach(picture => {
                    if (picture?.contentDocumentId && String(picture.previewUrl || '').startsWith('data:')) {
                        keptPreviews[picture.contentDocumentId] = picture.previewUrl;
                    }
                });
            });
            const byRecord = {};
            for (const row of rows || []) {
                const recordKey = this._pictureRecordKey(row?.linkedEntityId);
                if (!recordKey || !row.contentDocumentId) {
                    continue;
                }
                const picture = {
                    key: `${recordKey}:${row.contentDocumentId}`,
                    contentDocumentId: row.contentDocumentId,
                    contentVersionId: row.contentVersionId,
                    title: row.title || 'Mobile Device Picture',
                    comment: row.comment || '',
                    previewUrl: keptPreviews[row.contentDocumentId] || ''
                };
                if (!byRecord[recordKey]) {
                    byRecord[recordKey] = [];
                }
                byRecord[recordKey].push(picture);
            }
            this._mobilePicturesByRecordId = this._mergeMobilePictureMaps(
                this._mobilePicturesByRecordId,
                byRecord
            );
            this.mobilePictureVersion += 1;
            Object.values(byRecord).forEach(pictures => {
                pictures.forEach(picture => {
                    if (picture.contentVersionId && !String(picture.previewUrl || '').startsWith('data:')) {
                        this._loadSavedPicturePreview(picture.contentVersionId).catch(() => {});
                    }
                });
            });
        } catch (error) {
            if (this._mobilePictureRequest !== requestId) {
                return;
            }
            // eslint-disable-next-line no-console
            console.warn('woDebrief listMobileDevicePictures failed', error);
        }
    }

    /**
     * @description GW-375 - Work order id used to repair a damaged line id on save.
     * @return {string|null}
     */
    _workOrderPictureContextId() {
        const fromWire = this._recordIdFromGraphql(this._workOrder?.Id);
        if (fromWire) {
            return fromWire;
        }
        return this._recordIdFromGraphql(this.recordId);
    }

    /**
     * @description GW-375 - Maps stable 15-character keys to canonical WOLI ids from GraphQL.
     */
    _syncPictureLineRegistry() {
        const next = {};
        (this._serverLines || []).forEach((row) => {
            if (row.LineType__c?.value !== LINE_TYPE_PRODUCT_SERVICED) {
                return;
            }
            const lineId = this._recordIdFromGraphql(row.Id);
            const saveKey = this._pictureRecordKey(lineId);
            if (saveKey && lineId) {
                next[saveKey] = lineId;
            }
        });
        this._pictureLineIdBySaveKey = next;
    }

    /**
     * @description GW-375 - Reads the hidden file input from a label or input change event.
     * @param {Event} event Change event from the picture button
     * @return {HTMLInputElement|null}
     */
    _pictureFileInputFromEvent(event) {
        const target = event?.target;
        if (target?.files) {
            return target;
        }
        const current = event?.currentTarget;
        if (current?.files) {
            return current;
        }
        if (current?.querySelector) {
            const nested = current.querySelector('input.mobile-picture-input[type="file"]');
            if (nested?.files) {
                return nested;
            }
        }
        return current || target || null;
    }

    /**
     * @description GW-375 - Scope, line id, and slot from a picture change event (mobile-safe).
     * @param {Event} event Change event from the picture button
     * @return {{ input: HTMLInputElement|null, scope: string, lineId: string|null, slot: string }}
     */
    _mobilePictureContextFromEvent(event) {
        const input = this._pictureFileInputFromEvent(event);
        const carrier = input?.closest?.('.mobile-picture-button') || input;
        if (input?.closest?.('.header-picture-action') || carrier?.closest?.('.header-picture-action')) {
            return {
                input,
                scope: 'header',
                lineId: this._workOrderPictureContextId() || this.recordId,
                slot: '',
                saveKey: '',
                lineNumber: ''
            };
        }
        if (input?.closest?.('.add-form-picture-action') || carrier?.closest?.('.add-form-picture-action')) {
            return {
                input,
                scope: 'add',
                lineId: null,
                slot: '',
                saveKey: '',
                lineNumber: ''
            };
        }
        const read = (element, key) => {
            if (!element?.dataset) {
                return '';
            }
            return element.dataset[key] || '';
        };
        const slotRaw = read(input, 'pictureSlot') || read(carrier, 'pictureSlot');
        const slot = slotRaw.toLowerCase();
        const declaredScope = read(input, 'scope') || read(carrier, 'scope');
        const saveKeyRaw = read(input, 'saveKey') || read(carrier, 'saveKey');
        const lineNumberRaw = read(input, 'lineNumber') || read(carrier, 'lineNumber');
        const saveKey = saveKeyRaw ? saveKeyRaw.toUpperCase() : '';
        const lineNumber = lineNumberRaw ? String(lineNumberRaw).trim() : '';
        let lineId = saveKey && this._pictureLineIdBySaveKey[saveKey]
            ? this._pictureLineIdBySaveKey[saveKey]
            : this._canonicalLinePictureId(
                slot,
                read(input, 'id') || read(carrier, 'id') || (slot && this._pictureLineIds[slot])
            );
        if (
            String(declaredScope || '').trim().toLowerCase() === 'line'
            && this._isWorkOrderRecordId(lineId)
            && slot
        ) {
            lineId = this._canonicalLinePictureId(slot, this._pictureLineIds[slot])
                || this._knownPictureRecordId(this._pictureLineIds[slot])
                || lineId;
        }
        const scope = this._resolveMobilePictureScope(declaredScope, lineId);
        return { input, scope, lineId, slot, saveKey, lineNumber };
    }

    /**
     * @description GW-375 - Field Service mobile often drops data-scope on the file input.
     * @param {string} scope Declared scope from markup
     * @param {string|null} lineId Line or temp id
     * @return {string} add, line, or header
     */
    _resolveMobilePictureScope(scope, lineId, pictureHints = {}) {
        const token = (scope || '').trim().toLowerCase();
        if (token === 'add' || token === 'header' || token === 'line') {
            return token;
        }
        const saveKey = pictureHints.saveKey ? String(pictureHints.saveKey).trim() : '';
        const slot = pictureHints.slot ? String(pictureHints.slot).trim() : '';
        if (saveKey || slot) {
            return 'line';
        }
        if (this._lineIdFromOpenEditForm()) {
            return 'line';
        }
        const resolvedLineId = this._knownPictureRecordId(lineId) || lineId;
        if (resolvedLineId && this._isPersistedWoliId(resolvedLineId)) {
            return 'line';
        }
        if (this._isWorkOrderRecordId(lineId)) {
            return 'header';
        }
        if (lineId && String(lineId).startsWith('_new_')) {
            return 'line';
        }
        if (lineId && !this._isPersistedWoliId(lineId)) {
            return 'line';
        }
        if (this.showAddForm?.ProductServiced) {
            return 'add';
        }
        if (lineId && this._isPersistedWoliId(lineId)) {
            return 'line';
        }
        return 'add';
    }

    /**
     * @description GW-375 - Work order header scope when mobile drops data-scope but keeps the WO id on data-id.
     * @param {string} scope Declared scope
     * @param {string|null} lineId Id from the file button
     * @return {string}
     */
    _normalizePictureScope(scope, lineId, pictureHints = {}) {
        const token = (scope || '').trim().toLowerCase();
        if (token === 'line') {
            return 'line';
        }
        if (token === 'header') {
            return 'header';
        }
        return this._resolveMobilePictureScope(scope, lineId, pictureHints);
    }

    /**
     * @description GW-375 - Product Serviced line id for upload when the mobile file button sends the work order id.
     * @param {string|null} lineId Id from the button
     * @param {string} slot Picture slot
     * @return {string|null}
     */
    _resolveLinePictureTargetId(lineId, slot, saveKey) {
        const key = saveKey ? saveKey.toUpperCase() : '';
        if (key && this._pictureLineIdBySaveKey[key]) {
            return this._pictureLineIdBySaveKey[key];
        }
        if (lineId && this._isPersistedWoliId(lineId)) {
            return this._knownPictureRecordId(lineId) || lineId;
        }
        if (lineId && this._isWorkOrderRecordId(lineId)) {
            lineId = null;
        }
        if (slot && this._pictureLineIds[slot]) {
            const remembered = this._knownPictureRecordId(this._pictureLineIds[slot])
                || this._pictureLineIds[slot];
            if (remembered && this._isPersistedWoliId(remembered)) {
                return remembered;
            }
        }
        const recordKey = lineId ? this._pictureRecordKey(lineId) : '';
        if (recordKey) {
            const line = (this._serverLines || []).find(
                row => row.LineType__c?.value === LINE_TYPE_PRODUCT_SERVICED
                    && this._pictureRecordKey(row.Id) === recordKey
            );
            const resolved = this._recordIdFromGraphql(line?.Id);
            if (resolved && this._isPersistedWoliId(resolved)) {
                return resolved;
            }
        }
        return this._lineIdFromOpenEditForm();
    }

    /**
     * @description GW-375 - Line currently open in inline edit (Product Serviced picture button).
     * @return {string|null}
     */
    _lineIdFromOpenEditForm() {
        for (const [id, state] of Object.entries(this.editStateMap || {})) {
            if (!state?.isEditing) {
                continue;
            }
            const resolved = this._knownPictureRecordId(id) || id;
            if (resolved && this._isPersistedWoliId(resolved)) {
                return resolved;
            }
        }
        return null;
    }

    /**
     * @description GW-375 - True when the value is a Salesforce Work Order Id.
     * @param {string} value Candidate id
     * @return {boolean}
     */
    _isWorkOrderRecordId(value) {
        return typeof value === 'string' && /^0WO[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?$/i.test(value.trim());
    }

    /**
     * @description GW-375 - Canonical work order id for header picture storage.
     * @return {string|null}
     */
    _headerPictureRecordId() {
        return this._workOrderPictureContextId() || this._recordIdFromGraphql(this.recordId);
    }

    /**
     * @description GW-375 - Keeps the thumbnail and queues Save All when an immediate upload fails.
     * @param {Object} localPicture Compressed picture
     * @param {string} scope add, line, or header
     * @param {string|null} lineId Line or temp id
     * @param {string} slot Picture slot
     * @param {string|null} rawPrimaryRecordId Resolved primary id when known
     * @param {string|null} workOrderIdForResolve Work order context id
     */
    _queueFailedMobilePicture(
        localPicture,
        scope,
        lineId,
        slot,
        rawPrimaryRecordId,
        workOrderIdForResolve,
        saveKey
    ) {
        if (!localPicture?.base64Data) {
            return;
        }
        if (scope === 'add' || (scope === 'line' && !this._isPersistedLineForPictureUpload(lineId))) {
            if (this._stageMobilePictureForNewLine(localPicture, lineId, slot)) {
                return;
            }
        }
        if (scope === 'line' && !this._isPersistedLineForPictureUpload(lineId)) {
            return;
        }
        const workOrderId = workOrderIdForResolve || this._workOrderPictureContextId();
        if (!workOrderId) {
            return;
        }
        const canonicalLineId = scope === 'line'
            ? (rawPrimaryRecordId
                || this._knownPictureRecordId(lineId)
                || (this._isPersistedWoliId(lineId) ? lineId : null))
            : null;
        this._stageMobilePictureSave({
            scope: scope === 'header' ? 'header' : 'line',
            displayRecordId: scope === 'header' ? workOrderId : (canonicalLineId || lineId),
            workOrderIdValue: String(workOrderId),
            localPicture
        });
    }

    /**
     * @description GW-375 - Saved Product Serviced line id for an immediate picture upload.
     *              Returns nothing for a new line so the picture waits until Save All.
     * @param {string|null} pictureLineId Id from the picture button
     * @param {string} saveKey Stable line key
     * @param {string|null} registryLineId Line id already mapped for this key
     * @return {string|null}
     */
    _savedProductServicedLineId(pictureLineId, saveKey, registryLineId) {
        const key = saveKey ? String(saveKey).toUpperCase() : '';
        const fromRegistry = registryLineId || (key && this._pictureLineIdBySaveKey[key]);
        if (fromRegistry && this._isPersistedWoliId(fromRegistry) && !this._isWorkOrderRecordId(fromRegistry)) {
            return this._knownPictureRecordId(fromRegistry) || fromRegistry;
        }
        const known = this._knownPictureRecordId(pictureLineId);
        if (known && this._isPersistedWoliId(known) && !this._isWorkOrderRecordId(known)) {
            return known;
        }
        if (
            pictureLineId
            && this._isPersistedWoliId(pictureLineId)
            && !this._isWorkOrderRecordId(pictureLineId)
        ) {
            const recordKey = this._pictureRecordKey(pictureLineId);
            const onServer = (this._serverLines || []).some(
                row => row.LineType__c?.value === LINE_TYPE_PRODUCT_SERVICED
                    && this._pictureRecordKey(row.Id) === recordKey
            );
            if (onServer) {
                return pictureLineId;
            }
        }
        return null;
    }

    /**
     * @description GW-375 - Keeps a line picture on the device until Save All creates the line.
     * @param {Object} localPicture Compressed picture
     * @param {string|null} lineId Line or temp id
     * @param {string} slot Picture slot
     */
    _holdPictureUntilLineExists(localPicture, lineId, slot) {
        if (this._stageMobilePictureForNewLine(localPicture, lineId, slot)) {
            return;
        }
        this._picturesWaitingForNextLine = [
            ...(this._picturesWaitingForNextLine || []),
            localPicture
        ];
        this.mobilePictureVersion += 1;
        this._toast(
            'Picture added',
            'It will upload when you save the Product Serviced line.',
            'success'
        );
    }

    /**
     * @description GW-375 - True when Apex can link a mobile picture to this line id now.
     * @param {string|null} lineId Line or temp id
     * @return {boolean}
     */
    _isPersistedLineForPictureUpload(lineId) {
        if (!lineId) {
            return false;
        }
        const resolved = this._knownPictureRecordId(lineId) || lineId;
        if (!this._isPersistedWoliId(resolved)) {
            return false;
        }
        const key = this._pictureRecordKey(resolved);
        if ((this._serverLines || []).some(row => this._pictureRecordKey(row.Id) === key)) {
            return true;
        }
        const editingId = this._lineIdFromOpenEditForm();
        if (editingId && this._pictureRecordKey(editingId) === key) {
            return true;
        }
        if (this._knownPictureRecordId(resolved)) {
            return true;
        }
        return Object.values(this._pictureLineIdBySaveKey || {}).some(
            (id) => this._pictureRecordKey(id) === key
        );
    }

    /**
     * @description GW-375 - Stages a picture on the add form or a not-yet-saved Product Serviced line.
     * @param {Object} localPicture Compressed picture from the device
     * @param {string|null} lineId Line or temp id
     * @param {string} slot Picture slot from the file button
     * @return {boolean} True when the picture was staged locally
     */
    _stageMobilePictureForNewLine(localPicture, lineId, slot) {
        const pendingAdd = this._findPendingAddForMobilePicture(lineId, slot)
            || this._latestProductServicedPendingAdd();
        if (pendingAdd) {
            const tempId = pendingAdd._tempId;
            this._pendingAdds = this._pendingAdds.map(add => (
                add._tempId === tempId
                    ? { ...add, mobilePictures: [...(add.mobilePictures || []), localPicture] }
                    : add
            ));
            this.mobilePictureVersion += 1;
            this._toast(
                'Picture added',
                'Tap Save All to save the line and upload the picture.',
                'success'
            );
            return true;
        }
        if (this.showAddForm?.ProductServiced && !this._lineIdFromOpenEditForm()) {
            this._appendMobilePictureToAddForm(localPicture);
            return true;
        }
        return false;
    }

    /**
     * @description GW-375 - Most recent staged Product Serviced line waiting for Save All.
     * @return {Object|null}
     */
    _latestProductServicedPendingAdd() {
        const adds = this._pendingAdds.filter(add => add._schema === 'productServiced');
        return adds.length ? adds[adds.length - 1] : null;
    }

    /**
     * @description GW-375 - Keeps a mobile picture on the Product Serviced add form.
     * @param {Object} localPicture Compressed picture from the device
     */
    _appendMobilePictureToAddForm(localPicture) {
        this.addFormState = {
            ...this.addFormState,
            mobilePictures: [...(this.addFormState.mobilePictures || []), localPicture]
        };
        this.mobilePictureVersion += 1;
        this._toast(
            'Picture added',
            'Tap Save All to save the line and upload the picture.',
            'success'
        );
    }

    /**
     * @description GW-375 - Id string from GraphQL or the debrief record id.
     * @param {*} value Id field from uiapi
     * @return {string|null}
     */
    _recordIdFromGraphql(value) {
        if (value == null) {
            return null;
        }
        if (typeof value === 'string') {
            const text = value.trim();
            return text || null;
        }
        if (typeof value === 'object') {
            if (typeof value.value === 'string') {
                const text = value.value.trim();
                return text || null;
            }
            if (typeof value.id === 'string') {
                const text = value.id.trim();
                return text || null;
            }
        }
        return null;
    }

    /**
     * @description GW-375 - Product serviced line id from server data, not the lowercased file button.
     * @param {string} slot Picture slot on the file button
     * @param {*} fallback Id from the button when the slot is missing
     * @return {string|null}
     */
    _canonicalLinePictureId(slot, fallback) {
        const remembered = slot ? this._pictureLineIds[slot] : null;
        const known = this._knownPictureRecordId(remembered || fallback);
        return this._recordIdFromGraphql(known || remembered || fallback);
    }

    /**
     * @description GW-375 - Remembers the line id away from the button, which the mobile app lowercases.
     * @param {string} lineId Salesforce or temporary line Id
     * @return {string} Slot written on the file button
     */
    _trackPictureLine(lineId) {
        const raw = lineId == null ? '' : String(lineId);
        if (!raw) {
            return '';
        }
        const key = this._pictureRecordKey(raw);
        if (!key) {
            this._pictureLineIds[raw] = raw;
            return raw;
        }
        const slot = key.toLowerCase();
        this._pictureLineIds[slot] = this._preferPictureId(this._pictureLineIds[slot], raw);
        return slot;
    }

    /**
     * @description GW-375 - Keeps the id Apex can read when both a short and a full id are known.
     * @param {string} current Id already remembered
     * @param {string} next Id just seen
     * @return {string}
     */
    _preferPictureId(current, next) {
        if (!current) {
            return next;
        }
        const score = (value) => (String(value).length >= 18 ? 2 : 0) + (/[A-Z]/.test(value) ? 1 : 0);
        return score(next) > score(current) ? next : current;
    }

    /**
     * @description GW-375 - Picture fields for a product serviced line.
     * @param {string} lineId Salesforce or temporary line Id
     * @param {Object[]} stagedPictures Pictures not yet saved
     * @return {Object}
     */
    _mobilePictureModel(lineId, stagedPictures) {
        void this.mobilePictureVersion;
        const canonicalId = this._recordIdFromGraphql(lineId)
            ?? (typeof lineId === 'string' ? lineId : null);
        const recordKey = this._pictureRecordKey(canonicalId);
        const saved = recordKey ? (this._mobilePicturesByRecordId[recordKey] || []) : [];
        const pictures = [...saved, ...(stagedPictures || [])].map(picture => this._pictureView(picture));
        const count = pictures.length;
        const pictureSlot = this._trackPictureLine(canonicalId || lineId);
        const pictureSaveKey = recordKey || pictureSlot;
        return {
            pictureSlot,
            pictureSaveKey,
            mobilePictures: pictures,
            hasMobilePictures: count > 0,
            mobilePictureCountLabel: this._pictureCountLabel(count),
            showMobilePictureCount: true
        };
    }

    /**
     * @description GW-375 - Display label for a picture count.
     * @param {number} count Picture count
     * @return {string}
     */
    _pictureCountLabel(count) {
        return count === 1 ? '1 picture' : `${count} pictures`;
    }

    /**
     * @description GW-375 - Template row for a picture. Omits the image body.
     * @param {Object} picture Stored picture
     * @return {Object}
     */
    _pictureView(picture) {
        const contentVersionId = picture?.contentVersionId;
        const comment = picture?.comment == null ? '' : String(picture.comment).trim();
        return {
            key: picture?.key || picture?.contentDocumentId || picture?.localId,
            contentDocumentId: picture?.contentDocumentId || null,
            contentVersionId: contentVersionId || null,
            localId: picture?.localId || null,
            title: picture?.title || 'Mobile Device Picture',
            comment,
            hasComment: comment.length > 0,
            commentPreview: this._mobilePictureCommentPreview(comment),
            previewUrl: String(picture?.previewUrl || '').startsWith('data:') ? picture.previewUrl : ''
        };
    }

    /**
     * @description GW-375 - Thumbnail address for a saved picture.
     * @param {string} contentVersionId ContentVersion Id
     * @param {string} contentDocumentId ContentDocument Id
     * @return {string}
     */
    _mobilePicturePreviewUrl(contentVersionId, contentDocumentId) {
        if (!contentVersionId) {
            return '';
        }
        const content = contentDocumentId ? `&contentId=${contentDocumentId}` : '';
        return `/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=${contentVersionId}&operationContext=CHATTER${content}`;
    }

    /**
     * @description GW-375 - True when the value is a saved Work Order Line Item Id.
     * @param {string} value Candidate Id
     * @return {boolean}
     */
    _isPersistedWoliId(value) {
        return typeof value === 'string' && /^1WL[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?$/i.test(value);
    }

    /**
     * @description GW-375 - Work order or line id already loaded with its original letter case.
     * @param {*} value Id from the screen, possibly lowercased
     * @return {string|null}
     */
    _knownPictureRecordId(value) {
        const key = this._pictureRecordKey(value);
        if (!key) {
            return null;
        }
        const workOrderId = this._recordIdFromGraphql(this._workOrder?.Id);
        if (workOrderId && this._pictureRecordKey(workOrderId) === key) {
            return workOrderId;
        }
        const line = (this._serverLines || []).find(row => this._pictureRecordKey(row.Id) === key);
        return this._recordIdFromGraphql(line?.Id) || null;
    }

    /**
     * @description GW-375 - Id to store a picture on. Uses the loaded record, or matches a damaged mobile id to this work order.
     * @param {*} recordId Work order or line id from the screen
     * @return {Promise<string|null>}
     */
    async _pictureSaveId(recordId) {
        const candidates = [];
        const addCandidate = (value) => {
            const text = value == null ? '' : String(value).trim();
            if (text && !candidates.includes(text)) {
                candidates.push(text);
            }
        };
        addCandidate(this._knownPictureRecordId(recordId));
        addCandidate(recordId);
        const workOrderIds = [];
        const addWorkOrder = (value) => {
            const text = value == null ? '' : String(value).trim();
            if (text && !workOrderIds.includes(text)) {
                workOrderIds.push(text);
            }
        };
        addWorkOrder(this.recordId);
        addWorkOrder(this._workOrder?.Id);
        if (!candidates.length || !workOrderIds.length) {
            return null;
        }
        for (const candidate of candidates) {
            for (const workOrderId of workOrderIds) {
                try {
                    // eslint-disable-next-line no-await-in-loop
                    const resolved = await resolveMobilePictureRecordId({
                        recordIdValue: candidate,
                        workOrderIdValue: workOrderId
                    });
                    if (resolved) {
                        return resolved;
                    }
                } catch (error) {
                    // A damaged mobile id is skipped. The next candidate is tried.
                }
            }
        }
        return null;
    }

    /**
     * @description GW-375 - Record id sent to Apex, including the case checksum.
     * @param {*} value Record id from the screen
     * @return {string|null}
     */
    _apexId(value) {
        if (value == null) {
            return null;
        }
        const text = String(value).trim();
        if (!/^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(text)) {
            return null;
        }
        return text;
    }

    /**
     * @description GW-375 - Map key for a record's pictures. Ignores id length and case.
     * @param {*} value Record id
     * @return {string}
     */
    _pictureRecordKey(value) {
        const id = this._apexId(value);
        return id ? id.substring(0, 15).toUpperCase() : '';
    }

    /**
     * @description GW-375 - Keeps pictures already on screen when a reload runs before GraphQL lists a new line.
     * @param {Object} previous Pictures keyed by record prefix
     * @param {Object} loaded Pictures returned from Apex
     * @return {Object}
     */
    _mergeMobilePictureMaps(previous, loaded) {
        const next = { ...(loaded || {}) };
        Object.entries(previous || {}).forEach(([recordKey, pictures]) => {
            const localRows = (pictures || []).filter(
                picture => picture?.localId && !picture.contentDocumentId
            );
            const savedRows = (pictures || []).filter(picture => picture?.contentDocumentId);
            if (!localRows.length && !savedRows.length) {
                return;
            }
            const current = next[recordKey] ? [...next[recordKey]] : [];
            const seenDocuments = new Set(current.map(picture => picture.contentDocumentId).filter(Boolean));
            const seenLocals = new Set(current.map(picture => picture.localId).filter(Boolean));
            localRows.forEach((picture) => {
                if (picture.localId && !seenLocals.has(picture.localId)) {
                    current.push(picture);
                    seenLocals.add(picture.localId);
                }
            });
            savedRows.forEach((picture) => {
                if (picture.contentDocumentId && !seenDocuments.has(picture.contentDocumentId)) {
                    current.push(picture);
                    seenDocuments.add(picture.contentDocumentId);
                }
            });
            if (current.length) {
                next[recordKey] = current;
            }
        });
        return next;
    }

    /**
     * @description GW-375 - Line item number for Apex when mobile drops the WOLI id.
     * @param {string} saveKey Picture save key
     * @param {string|null} lineId Line id when known
     * @return {string}
     */
    _lineItemNumberForPicture(saveKey, lineId) {
        const key = (saveKey || this._pictureRecordKey(lineId) || '').toUpperCase();
        if (!key) {
            return '';
        }
        const line = (this._serverLines || []).find(
            row => row.LineType__c?.value === LINE_TYPE_PRODUCT_SERVICED
                && this._pictureRecordKey(row.Id) === key
        );
        if (!line) {
            return '';
        }
        const numberValue = line.LineItemNumber?.value;
        return numberValue == null ? '' : String(numberValue).trim();
    }

    /**
     * @description GW-375 - Composite line reference for Product Serviced picture Apex.
     * @param {string} saveKey Stable 15-character key
     * @param {string|null} lineId Canonical WOLI id
     * @param {string} lineNumber Line item number
     * @return {string}
     */
    _buildLinePictureReference(saveKey, lineId, lineNumber) {
        const key = (saveKey || this._pictureRecordKey(lineId) || '').toUpperCase();
        const number = lineNumber == null ? '' : String(lineNumber).trim();
        const id = this._apexId(lineId) || '';
        if (!key && !number && !id) {
            return '';
        }
        return `${key}|${number}|${id}`;
    }

    /**
     * @description GW-375 - Single Apex target string (work order + line) for Field Service Mobile.
     * @param {string} workOrderId Work Order Id
     * @param {string} saveKey Stable 15-character key
     * @param {string|null} lineId Canonical WOLI id
     * @param {string} lineNumber Line item number
     * @return {string}
     */
    _buildLinePictureTarget(workOrderId, saveKey, lineId, lineNumber) {
        const workOrder = workOrderId == null ? '' : String(workOrderId).trim();
        const lineReference = this._buildLinePictureReference(saveKey, lineId, lineNumber);
        if (!workOrder) {
            return lineReference;
        }
        if (!lineReference) {
            const idOnly = this._apexId(lineId);
            return idOnly ? `${workOrder}::${idOnly}` : '';
        }
        return `${workOrder}::${lineReference}`;
    }

    /**
     * @description GW-375 - Short upload context for an existing Product Serviced line on mobile.
     * @param {string} workOrderId Work Order Id
     * @param {string|null} canonicalLineId Resolved WOLI Id
     * @param {string} saveKey Picture save key
     * @param {string} lineNumber Line item number
     * @param {string|null} fallbackLineId Line id from the file button
     * @return {string}
     */
    _buildPersistedLinePictureUploadContext(
        workOrderId,
        canonicalLineId,
        saveKey,
        lineNumber,
        fallbackLineId
    ) {
        const lineId = this._pictureUploadLineToken(
            canonicalLineId || this._knownPictureRecordId(fallbackLineId) || fallbackLineId
        );
        if (lineId) {
            return lineId;
        }
        return this._buildLinePictureTarget(
            workOrderId,
            saveKey || this._pictureRecordKey(canonicalLineId || fallbackLineId),
            canonicalLineId || fallbackLineId,
            this._lineItemNumberForPicture(saveKey, canonicalLineId || fallbackLineId) || lineNumber
        );
    }

    /**
     * @description GW-375 - Salesforce WOLI id token for a picture upload after the line exists.
     * @param {*} lineId Saved or canonical Work Order Line Item Id
     * @return {string}
     */
    _pictureUploadLineToken(lineId) {
        const known = this._knownPictureRecordId(lineId);
        const candidate = known || lineId;
        const apex = this._apexId(candidate);
        if (apex && this._isPersistedWoliId(apex)) {
            return apex;
        }
        if (candidate == null) {
            return '';
        }
        const token = String(candidate).trim();
        return this._isPersistedWoliId(token) ? token : '';
    }

    /**
     * @description GW-375 - Canonical WOLI id for upload immediately after createRecord.
     * @param {string} salesforceLineId Id returned from createRecord
     * @return {Promise<string>}
     */
    /**
     * @description GW-375 - Id token used when uploading to a line that already exists in Salesforce.
     * @param {*} lineId WOLI id from createRecord, GraphQL, or the debrief screen
     * @return {string}
     */
    _salesforceLineIdForPictureUpload(lineId) {
        return this._pictureUploadLineToken(
            this._knownPictureRecordId(lineId) || lineId
        );
    }

    /**
     * @description GW-375 - Saves a CRSS line picture using the child-debrief pattern when the WOLI id is known.
     * @param {string|null} lineId Work Order Line Item Id
     * @param {string} base64Data Image data
     * @param {string} pictureComment Optional comment
     * @param {string|null} mobileRepairContext Composite token when mobile damaged the line id
     * @return {Promise<Object>}
     */
    async _saveMobilePictureOnLine(lineId, base64Data, pictureComment, mobileRepairContext) {
        const lineToken = this._salesforceLineIdForPictureUpload(lineId);
        if (lineToken) {
            return saveProductServicedLineMobileDevicePicture(
                this._linePictureApexArgs(lineToken, base64Data, pictureComment)
            );
        }
        const repairContext = mobileRepairContext
            ? this._appendPictureCommentToUploadContext(mobileRepairContext, pictureComment)
            : '';
        if (repairContext) {
            return saveProductServicedLineMobileDevicePicture({
                pictureUploadContext: repairContext,
                base64Data
            });
        }
        const workOrderId = this._workOrderPictureContextId() || this.recordId;
        const primaryRecordId = this._apexId(lineId);
        if (primaryRecordId && this._isPersistedWoliId(primaryRecordId) && workOrderId) {
            return saveMobileDevicePicture({
                primaryRecordId,
                parentWorkOrderId: null,
                base64Data,
                fileName: 'MobileDevicePicture.jpg',
                workOrderIdForResolve: workOrderId
            });
        }
        throw new Error('A Product Serviced line is required to save the picture.');
    }

    /**
     * @description GW-375 - Embeds line context in the file name when mobile drops Apex id params.
     * @param {string} lineId Work Order Line Item Id
     * @param {string} workOrderId Work Order Id
     * @param {string} assetId Asset Id on the new line
     * @return {string}
     */
    _mobileLinePictureUploadFileName(lineId, workOrderId, assetId) {
        const line = lineId == null ? '' : String(lineId).trim();
        const workOrder = workOrderId == null ? '' : String(workOrderId).trim();
        const asset = assetId == null ? '' : String(assetId).trim();
        return `GW375;${line};${workOrder};${asset};MobileDevicePicture.jpg`;
    }

    /**
     * @description GW-375 - Single Apex context string for staged new-line uploads on mobile.
     * @param {string} lineId Work Order Line Item Id
     * @param {string} workOrderId Work Order Id
     * @param {string} assetId Asset Id
     * @return {string}
     */
    _buildMobilePictureUploadContext(lineId, workOrderId, assetId, pictureComment) {
        const fileName = this._mobileLinePictureUploadFileName(lineId, workOrderId, assetId);
        const linePayload = `${lineId == null ? '' : String(lineId).trim()}|${workOrderId == null ? '' : String(workOrderId).trim()}|${assetId == null ? '' : String(assetId).trim()}`;
        const baseContext = `${fileName}||${linePayload}`;
        return this._appendPictureCommentToUploadContext(baseContext, pictureComment);
    }

    /**
     * @description GW-6437 - Appends an optional comment to a mobile-safe Apex upload context.
     * @param {string} uploadContext Existing upload context
     * @param {string} pictureComment Comment text
     * @return {string}
     */
    /**
     * @description GW-375 - Line picture arguments that survive Field Service Mobile.
     *              A bare line id is replaced with the work order id, so the id is split and embedded in the image.
     * @param {string} lineId Saved Work Order Line Item Id
     * @param {string} base64Data Image data
     * @param {string} pictureComment Optional comment
     * @return {{ pictureUploadContext: string, base64Data: string }}
     */
    _linePictureApexArgs(lineId, base64Data, pictureComment) {
        const id = lineId == null ? '' : String(lineId).trim();
        const dotted = id.length > 5 ? `${id.slice(0, 5)}.${id.slice(5)}` : id;
        const comment = this._normalizeMobilePictureComment(pictureComment).replace(/:::/g, '');
        const token = comment ? `ps.${dotted}|||${comment}` : `ps.${dotted}`;
        const image = base64Data == null ? '' : String(base64Data);
        return {
            pictureUploadContext: token,
            base64Data: `${token}:::${image}`
        };
    }

    _appendPictureCommentToUploadContext(uploadContext, pictureComment) {
        const comment = this._normalizeMobilePictureComment(pictureComment);
        if (!comment) {
            return uploadContext || '';
        }
        return `${uploadContext || ''}${MOBILE_PICTURE_COMMENT_DELIMITER}${comment}`;
    }

    /**
     * @description GW-6437 - Trims and caps a CRSS picture comment.
     * @param {string} value Raw comment
     * @return {string}
     */
    _normalizeMobilePictureComment(value) {
        const text = value == null ? '' : String(value).trim();
        if (!text) {
            return '';
        }
        return text.length > MOBILE_PICTURE_COMMENT_MAX_LENGTH
            ? text.substring(0, MOBILE_PICTURE_COMMENT_MAX_LENGTH)
            : text;
    }

    /**
     * @description GW-6437 - Short label shown under a picture thumbnail.
     * @param {string} comment Full comment
     * @return {string}
     */
    _mobilePictureCommentPreview(comment) {
        const text = comment == null ? '' : String(comment).trim();
        if (!text) {
            return '';
        }
        return text.length > 48 ? `${text.substring(0, 45)}...` : text;
    }

    /**
     * @description GW-6437 - Updates a saved picture comment in local state.
     * @param {string} recordId Linked record id
     * @param {string} contentDocumentId ContentDocument Id
     * @param {string} comment Comment text
     */
    _updateMobilePictureComment(recordId, contentDocumentId, comment) {
        const recordKey = this._pictureRecordKey(recordId);
        if (!recordKey || !contentDocumentId) {
            return;
        }
        const current = this._mobilePicturesByRecordId[recordKey] || [];
        this._mobilePicturesByRecordId = {
            ...this._mobilePicturesByRecordId,
            [recordKey]: current.map(picture => (
                picture.contentDocumentId === contentDocumentId
                    ? { ...picture, comment: comment || '' }
                    : picture
            ))
        };
        this.mobilePictureVersion += 1;
    }

    /**
     * @description GW-6437 - Updates a staged or not-yet-uploaded picture comment in local state.
     * @param {string} scope header, add, or line
     * @param {string|null} lineId Line id for line scope
     * @param {string} pictureKey Thumbnail key
     * @param {string} comment Comment text
     */
    _updateMobilePictureCommentLocal(scope, lineId, pictureKey, comment) {
        const normalized = comment || '';
        const matchesKey = (picture) => {
            const keys = [
                picture.key,
                picture.localId,
                picture.contentDocumentId
            ].filter(Boolean);
            return keys.includes(pictureKey);
        };
        const patch = (picture) => (
            matchesKey(picture) ? { ...picture, comment: normalized } : picture
        );
        if (scope === 'add') {
            this.addFormState = {
                ...this.addFormState,
                mobilePictures: (this.addFormState?.mobilePictures || []).map(patch)
            };
            this.mobilePictureVersion += 1;
            return;
        }
        const recordId = scope === 'header'
            ? this._headerPictureRecordId()
            : (this._knownPictureRecordId(lineId) || lineId);
        const recordKey = this._pictureRecordKey(recordId);
        if (recordKey) {
            const current = this._mobilePicturesByRecordId[recordKey] || [];
            this._mobilePicturesByRecordId = {
                ...this._mobilePicturesByRecordId,
                [recordKey]: current.map(patch)
            };
        }
        this._pendingAdds = (this._pendingAdds || []).map(add => (
            add._tempId === lineId
                ? { ...add, mobilePictures: (add.mobilePictures || []).map(patch) }
                : add
        ));
        this._stagedMobilePictureSaves = (this._stagedMobilePictureSaves || []).map(item => (
            matchesKey(item.localPicture)
                ? {
                    ...item,
                    localPicture: { ...item.localPicture, comment: normalized }
                }
                : item
        ));
        this.mobilePictureVersion += 1;
    }

    /**
     * @description GW-375 - Saved and staged pictures for one product serviced line.
     * @param {string} lineId Line Id
     * @return {Object[]}
     */
    _picturesForLine(lineId) {
        const saved = this._mobilePicturesByRecordId[this._pictureRecordKey(lineId)] || [];
        const pending = this._pendingAdds.find(add => add._tempId === lineId);
        return [...saved, ...(pending?.mobilePictures || [])];
    }

    /**
     * @description GW-375 - Finds a picture by the key rendered on its thumbnail.
     * @param {string} scope header, add, or line
     * @param {string} lineId Line Id for a line-scope picture
     * @param {string} key Thumbnail key
     * @return {Object|undefined}
     */
    _findMobilePicture(scope, lineId, key) {
        let pictures = [];
        if (scope === 'header') {
            pictures = this._mobilePicturesByRecordId[this._pictureRecordKey(this._headerPictureRecordId())] || [];
        } else if (scope === 'add') {
            pictures = this.addFormState?.mobilePictures || [];
        } else {
            pictures = this._picturesForLine(lineId);
        }
        return pictures.find(picture => this._mobilePictureKeysMatch(picture, key));
    }

    /**
     * @description GW-6437 - True when a stored picture matches the thumbnail key.
     * @param {Object} picture Stored picture row
     * @param {string} key Key from the thumbnail button
     * @return {boolean}
     */
    _mobilePictureKeysMatch(picture, key) {
        if (!picture || !key) {
            return false;
        }
        const candidates = new Set([
            picture.key,
            picture.localId,
            picture.contentDocumentId
        ].filter(Boolean));
        if (candidates.has(key)) {
            return true;
        }
        const viewKey = this._pictureView(picture).key;
        return viewKey === key;
    }

    /**
     * @description GW-375 - Reads the camera or library file and shrinks it before upload.
     * @param {File} file Selected image
     * @return {Promise<Object>}
     */
    _fileToMobilePicture(file) {
        return this._compressImageFile(file).then(dataUrl => {
            _tempIdSeq += 1;
            const localId = `local_${_tempIdSeq}`;
            return {
                key: localId,
                localId,
                contentDocumentId: null,
                contentVersionId: null,
                title: 'Mobile Device Picture',
                previewUrl: dataUrl,
                base64Data: dataUrl,
                fileName: 'MobileDevicePicture.jpg'
            };
        });
    }

    /**
     * @description GW-375 - Draws the photo to a smaller jpeg so the upload stays within Apex limits.
     * @param {File} file Selected image
     * @return {Promise<string>}
     */
    _compressImageFile(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onerror = () => reject(new Error('The picture could not be read. Take it again.'));
            reader.onload = () => {
                const source = reader.result;
                const image = new Image();
                image.onerror = () => reject(new Error('The picture could not be read. Take it again.'));
                image.onload = () => {
                    const maxEdge = 1600;
                    const scale = Math.min(1, maxEdge / Math.max(image.width || 1, image.height || 1));
                    const width = Math.max(1, Math.round((image.width || 1) * scale));
                    const height = Math.max(1, Math.round((image.height || 1) * scale));
                    const canvas = document.createElement('canvas');
                    canvas.width = width;
                    canvas.height = height;
                    const context = canvas.getContext('2d');
                    if (!context) {
                        resolve(source);
                        return;
                    }
                    context.drawImage(image, 0, 0, width, height);
                    resolve(canvas.toDataURL('image/jpeg', 0.72));
                };
                image.src = source;
            };
            reader.readAsDataURL(file);
        });
    }

    /**
     * @description GW-375 - True when staged mobile pictures still need Save All.
     * @return {boolean}
     */
    _hasStagedMobilePictures() {
        if (this._stagedMobilePictureSaves.length > 0) {
            return true;
        }
        const addFormPictures = this.addFormState?.mobilePictures || [];
        if (addFormPictures.some(picture => picture?.base64Data && !picture.contentDocumentId)) {
            return true;
        }
        if ((this._picturesWaitingForNextLine || []).some(
            picture => picture?.base64Data && !picture.contentDocumentId
        )) {
            return true;
        }
        return this._pendingAdds.some(add => (add.mobilePictures || []).some(
            picture => picture?.base64Data && !picture.contentDocumentId
        ));
    }

    /**
     * @description GW-375 - Resolves a not-yet-saved Product Serviced line for a mobile picture.
     * @param {string|null} lineId Line or temp Id from the file button
     * @param {string} slot Picture slot on the file button
     * @return {Object|null}
     */
    _findPendingAddForMobilePicture(lineId, slot) {
        const candidates = this._pendingAdds.filter(add => add._schema === 'productServiced');
        if (!candidates.length) {
            return null;
        }
        if (lineId) {
            const direct = candidates.find(add => add._tempId === lineId);
            if (direct) {
                return direct;
            }
            const lineKey = this._pictureRecordKey(lineId);
            if (lineKey) {
                const byKey = candidates.find(
                    add => this._pictureRecordKey(add._tempId) === lineKey
                );
                if (byKey) {
                    return byKey;
                }
            }
        }
        const remembered = slot ? this._pictureLineIds[slot] : null;
        if (remembered) {
            const bySlot = candidates.find(
                add => add._tempId === remembered
                    || this._pictureRecordKey(add._tempId) === this._pictureRecordKey(remembered)
            );
            if (bySlot) {
                return bySlot;
            }
        }
        return candidates.length === 1 ? candidates[0] : null;
    }

    /**
     * @description GW-375 - Queues a header or line picture for Save All.
     * @param {Object} item Staged picture payload
     */
    _stageMobilePictureSave(item) {
        if (!item?.localPicture?.base64Data) {
            return;
        }
        this._stagedMobilePictureSaves = [...this._stagedMobilePictureSaves, item];
        this._rememberStagedMobilePicturePreview(item.displayRecordId, item.localPicture);
        this.mobilePictureVersion += 1;
    }

    /**
     * @description GW-375 - Shows a staged picture before Save All uploads it.
     * @param {string} recordId Work order or line Id for the thumbnail strip
     * @param {Object} localPicture Compressed local picture
     */
    _rememberStagedMobilePicturePreview(recordId, localPicture) {
        const recordKey = this._pictureRecordKey(recordId);
        if (!recordKey || !localPicture?.localId) {
            return;
        }
        const picture = {
            key: `${recordKey}:local:${localPicture.localId}`,
            localId: localPicture.localId,
            contentDocumentId: null,
            contentVersionId: null,
            title: 'Mobile Device Picture',
            comment: localPicture.comment || '',
            previewUrl: localPicture.previewUrl || ''
        };
        const current = this._mobilePicturesByRecordId[recordKey] || [];
        if (current.some(existing => existing.localId === localPicture.localId)) {
            return;
        }
        this._mobilePicturesByRecordId = {
            ...this._mobilePicturesByRecordId,
            [recordKey]: [...current, picture]
        };
    }

    /**
     * @description GW-375 - Removes unstaged previews after Cancel / Discard.
     */
    _dropUnsavedMobilePicturePreviews() {
        const next = {};
        Object.entries(this._mobilePicturesByRecordId).forEach(([recordId, pictures]) => {
            const kept = (pictures || []).filter(picture => picture.contentDocumentId);
            if (kept.length) {
                next[recordId] = kept;
            }
        });
        this._mobilePicturesByRecordId = next;
        this.mobilePictureVersion += 1;
    }

    /**
     * @description GW-375 - Uploads header and line pictures queued for Save All.
     * @return {Promise<number>} Count of pictures uploaded
     */
    async _flushStagedMobilePictureSaves(createdProductServicedLineByTempId = {}) {
        const queue = [...this._stagedMobilePictureSaves];
        if (!queue.length) {
            return 0;
        }
        const failed = [];
        const retained = [];
        let uploaded = 0;
        let firstError = null;
        const workOrderId = this._workOrderPictureContextId() || this.recordId;
        for (const item of queue) {
            try {
                const base64Data = item.localPicture.base64Data;
                const workOrderIdValue = item.workOrderIdValue || item.workOrderIdForResolve || workOrderId;
                let saved;
                if (item.scope === 'header') {
                    // eslint-disable-next-line no-await-in-loop
                    saved = await saveWorkOrderHeaderMobileDevicePicture({
                        pictureUploadContext: this._appendPictureCommentToUploadContext(
                            workOrderIdValue,
                            item.localPicture.comment
                        ),
                        base64Data
                    });
                } else {
                    const tempId = item.displayRecordId;
                    const createdLineId = tempId && createdProductServicedLineByTempId[tempId]
                        ? createdProductServicedLineByTempId[tempId]
                        : null;
                    const rawLineId = createdLineId || item.displayRecordId;
                    const lineId = rawLineId == null ? '' : String(rawLineId).trim();
                    if (!this._isPersistedWoliId(lineId) || this._isWorkOrderRecordId(lineId)) {
                        retained.push(item);
                        continue;
                    }
                    // eslint-disable-next-line no-await-in-loop
                    saved = await saveProductServicedLineMobileDevicePicture(
                        this._linePictureApexArgs(lineId, base64Data, item.localPicture.comment)
                    );
                }
                this._replaceStagedMobilePicturePreview(
                    item.displayRecordId,
                    item.localPicture.localId,
                    saved,
                    item.localPicture.previewUrl
                );
                uploaded += 1;
            } catch (error) {
                failed.push(item);
                if (!firstError) {
                    firstError = error;
                }
            }
        }
        this._stagedMobilePictureSaves = [...failed, ...retained];
        if (firstError) {
            throw firstError;
        }
        return uploaded;
    }

    /**
     * @description GW-375 - Swaps a staged thumbnail for the saved ContentDocument.
     * @param {string} recordId Display record Id
     * @param {string} localId Staged local id
     * @param {Object} saved Apex result
     * @param {string} localPreviewUrl Device preview
     */
    _replaceStagedMobilePicturePreview(recordId, localId, saved, localPreviewUrl) {
        const recordKey = this._pictureRecordKey(recordId);
        if (!recordKey || !saved?.contentDocumentId) {
            return;
        }
        const savedPicture = {
            key: `${recordKey}:${saved.contentDocumentId}`,
            contentDocumentId: saved.contentDocumentId,
            contentVersionId: saved.contentVersionId,
            title: saved.title || 'Mobile Device Picture',
            comment: saved.comment || '',
            previewUrl: localPreviewUrl || this._mobilePicturePreviewUrl(
                saved.contentVersionId,
                saved.contentDocumentId
            )
        };
        const current = this._mobilePicturesByRecordId[recordKey] || [];
        const prior = current.find(picture => picture.localId === localId);
        if (prior?.comment && !savedPicture.comment) {
            savedPicture.comment = prior.comment;
        }
        const withoutLocal = current.filter(picture => picture.localId !== localId);
        this._mobilePicturesByRecordId = {
            ...this._mobilePicturesByRecordId,
            [recordKey]: [...withoutLocal, savedPicture]
        };
        this.mobilePictureVersion += 1;
        this._mobilePictureRequest += 1;
    }

    /**
     * @description GW-375 - Adds a saved picture to the record it was taken for.
     * @param {string} recordId Work order or product serviced line Id
     * @param {Object} saved Apex picture result
     * @param {string} localPreviewUrl Image already on the device
     */
    _rememberMobilePicture(recordId, saved, localPreviewUrl) {
        if (!recordId || !saved?.contentDocumentId) {
            return;
        }
        const recordKey = this._pictureRecordKey(recordId);
        if (!recordKey) {
            return;
        }
        const picture = {
            key: `${recordKey}:${saved.contentDocumentId}`,
            contentDocumentId: saved.contentDocumentId,
            contentVersionId: saved.contentVersionId,
            title: saved.title || 'Mobile Device Picture',
            comment: saved.comment || '',
            previewUrl: localPreviewUrl || this._mobilePicturePreviewUrl(saved.contentVersionId, saved.contentDocumentId)
        };
        const current = this._mobilePicturesByRecordId[recordKey] || [];
        this._mobilePicturesByRecordId = {
            ...this._mobilePicturesByRecordId,
            [recordKey]: [...current, picture]
        };
        this.mobilePictureVersion += 1;
        this._mobilePictureRequest += 1;
    }

    /**
     * @description GW-375 - Uploads pictures taken before the product serviced line existed.
     * @param {string} workOrderLineItemId Saved line Id
     * @param {Object[]} pictures Staged pictures
     */
    async _uploadStagedMobilePictures(workOrderLineItemId, pictures) {
        const lineId = workOrderLineItemId == null ? '' : String(workOrderLineItemId).trim();
        if (!lineId || this._isWorkOrderRecordId(lineId)) {
            throw new Error('A Product Serviced line is required to save the picture.');
        }
        const staged = (pictures || []).filter(picture => picture?.base64Data && !picture.contentDocumentId);
        staged.forEach(picture => this._rememberStagedMobilePicturePreview(lineId, picture));
        if (staged.length) {
            this.mobilePictureVersion += 1;
        }
        let firstError = null;
        for (const picture of staged) {
            try {
                // eslint-disable-next-line no-await-in-loop
                const saved = await saveProductServicedLineMobileDevicePicture(
                    this._linePictureApexArgs(lineId, picture.base64Data, picture.comment)
                );
                this._replaceStagedMobilePicturePreview(lineId, picture.localId, saved, picture.previewUrl);
                this._stagedMobilePictureSaves = (this._stagedMobilePictureSaves || []).filter(
                    item => item.localPicture?.localId !== picture.localId
                );
            } catch (error) {
                firstError = firstError || error;
                this._keepFailedLinePicture(lineId, picture);
            }
        }
        if (firstError) {
            throw firstError;
        }
    }

    /**
     * @description GW-375 - Leaves a failed line picture on the saved line so Save All can retry it.
     * @param {string} lineId Saved Work Order Line Item Id
     * @param {Object} localPicture Compressed picture still on the device
     */
    _keepFailedLinePicture(lineId, localPicture) {
        if (!lineId || !localPicture?.base64Data) {
            return;
        }
        this._rememberStagedMobilePicturePreview(lineId, localPicture);
        const queue = this._stagedMobilePictureSaves || [];
        const alreadyQueued = queue.some(item => item.localPicture?.localId === localPicture.localId);
        this._stagedMobilePictureSaves = alreadyQueued
            ? queue.map(item => (
                item.localPicture?.localId === localPicture.localId
                    ? { ...item, scope: 'line', displayRecordId: lineId, localPicture }
                    : item
            ))
            : [...queue, { scope: 'line', displayRecordId: lineId, localPicture }];
        this.mobilePictureVersion += 1;
    }

    /**
     * @description GW-375 - Loads a saved picture as image bytes so the mobile preview can paint it.
     * @param {string} contentVersionId ContentVersion Id
     * @return {Promise<string>}
     */
    _loadSavedPicturePreview(contentVersionId) {
        if (!contentVersionId) {
            return Promise.resolve('');
        }
        if (!this._pictureDataPromises[contentVersionId]) {
            this._pictureDataPromises[contentVersionId] = getMobileDevicePictureData({ contentVersionId })
                .then(base64 => {
                    const dataUrl = `data:image/jpeg;base64,${base64}`;
                    this._applyPictureDataUrl(contentVersionId, dataUrl);
                    return dataUrl;
                })
                .catch(error => {
                    delete this._pictureDataPromises[contentVersionId];
                    throw error;
                });
        }
        return this._pictureDataPromises[contentVersionId];
    }

    /**
     * @description GW-375 - Stores image bytes on the saved picture.
     * @param {string} contentVersionId ContentVersion Id
     * @param {string} dataUrl Image data url
     */
    _applyPictureDataUrl(contentVersionId, dataUrl) {
        if (!contentVersionId || !dataUrl) {
            return;
        }
        const next = {};
        let changed = false;
        Object.entries(this._mobilePicturesByRecordId).forEach(([recordId, pictures]) => {
            next[recordId] = (pictures || []).map(picture => {
                if (picture.contentVersionId === contentVersionId && picture.previewUrl !== dataUrl) {
                    changed = true;
                    return { ...picture, previewUrl: dataUrl };
                }
                return picture;
            });
        });
        if (changed) {
            this._mobilePicturesByRecordId = next;
            this.mobilePictureVersion += 1;
        }
    }

    /**
     * @description GW-375 - Deletes a saved picture, or drops one that has not been saved yet.
     * @param {string} scope header, add, or line
     * @param {string} lineId Line Id
     * @param {string} key Thumbnail key
     * @return {Promise<boolean>}
     */
    async _deleteMobilePicture(scope, lineId, key) {
        const picture = this._findMobilePicture(scope, lineId, key);
        if (!picture) {
            return false;
        }
        const confirmed = await LightningConfirm.open({
            message: picture.contentDocumentId
                ? 'Delete this Mobile Device Picture?'
                : 'Remove this Mobile Device Picture?',
            variant: 'headerless',
            label: 'Delete picture'
        });
        if (!confirmed) {
            return false;
        }
        try {
            if (picture.contentDocumentId) {
                await deleteMobileDevicePicture({ contentDocumentId: picture.contentDocumentId });
                const next = {};
                Object.entries(this._mobilePicturesByRecordId).forEach(([recordId, pictures]) => {
                    next[recordId] = pictures.filter(item => item.contentDocumentId !== picture.contentDocumentId);
                });
                this._mobilePicturesByRecordId = next;
                this.mobilePictureVersion += 1;
                this._mobilePictureRequest += 1;
            } else if (scope === 'add') {
                this.addFormState = {
                    ...this.addFormState,
                    mobilePictures: (this.addFormState.mobilePictures || []).filter(
                        item => item.localId !== picture.localId
                    )
                };
                this.mobilePictureVersion += 1;
            } else if (picture.localId && this._stagedMobilePictureSaves.some(
                item => item.localPicture?.localId === picture.localId
            )) {
                this._stagedMobilePictureSaves = this._stagedMobilePictureSaves.filter(
                    item => item.localPicture?.localId !== picture.localId
                );
                const recordKey = this._pictureRecordKey(lineId || this.recordId);
                if (recordKey) {
                    const current = this._mobilePicturesByRecordId[recordKey] || [];
                    this._mobilePicturesByRecordId = {
                        ...this._mobilePicturesByRecordId,
                        [recordKey]: current.filter(item => item.localId !== picture.localId)
                    };
                }
                this.mobilePictureVersion += 1;
            } else {
                this._pendingAdds = this._pendingAdds.map(add => (
                    add._tempId === lineId
                        ? {
                            ...add,
                            mobilePictures: (add.mobilePictures || []).filter(
                                item => item.localId !== picture.localId
                            )
                        }
                        : add
                ));
                this.mobilePictureVersion += 1;
            }
            return true;
        } catch (error) {
            this._toast('Picture was not deleted', this._errorMessage(error), 'error');
            return false;
        }
    }
}