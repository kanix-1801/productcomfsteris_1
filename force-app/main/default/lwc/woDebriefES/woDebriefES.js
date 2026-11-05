/**
 * @description Work Order debrief LWC (woDebriefES) for Field Service technicians.
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
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import LightningAlert from 'lightning/alert';
import LightningPrompt from 'lightning/prompt';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getBarcodeScanner } from 'lightning/mobileCapabilities';
import USER_ID from '@salesforce/user/Id';

import WOLI_OBJECT from '@salesforce/schema/WorkOrderLineItem';
import WOLI_WORKORDERID from '@salesforce/schema/WorkOrderLineItem.WorkOrderId';
import WOLI_LINETYPE from '@salesforce/schema/WorkOrderLineItem.LineType__c';
import WOLI_RECORDTYPE from '@salesforce/schema/WorkOrderLineItem.RecordTypeId';
import WOLI_RATE from '@salesforce/schema/WorkOrderLineItem.Rate__c';
import WOLI_TRAVEL_TYPE from '@salesforce/schema/WorkOrderLineItem.TravelType__c';
import WOLI_ASSIGNED_RES from '@salesforce/schema/WorkOrderLineItem.AssignedResource__c';
import WOLI_WORKTYPE from '@salesforce/schema/WorkOrderLineItem.WorkTypeId';
import WOLI_STARTDATE from '@salesforce/schema/WorkOrderLineItem.StartDate';
import WOLI_ENDDATE from '@salesforce/schema/WorkOrderLineItem.EndDate';
import WOLI_DURATION from '@salesforce/schema/WorkOrderLineItem.Duration';
import WOLI_ASSETID from '@salesforce/schema/WorkOrderLineItem.AssetId';
import WOLI_REPAIRCODE from '@salesforce/schema/WorkOrderLineItem.RepairCode__c';
import WOLI_PARTS_SOURCE from '@salesforce/schema/WorkOrderLineItem.PartsSource__c';
import WOLI_UNIT_QTY from '@salesforce/schema/WorkOrderLineItem.UnitQty__c';
import WOLI_DESCRIPTION from '@salesforce/schema/WorkOrderLineItem.Description';
import WOLI_PRODUCT_ITEM from '@salesforce/schema/WorkOrderLineItem.ProductItem__c';
import WOLI_PRODUCT from '@salesforce/schema/WorkOrderLineItem.Product__c';
import WOLI_PART_DESCRIPTION from '@salesforce/schema/WorkOrderLineItem.PartDescription__c';
import WOLI_ALLOWED_UNIT from '@salesforce/schema/WorkOrderLineItem.AllowedUnit__c';
import WOLI_RETURNABLE from '@salesforce/schema/WorkOrderLineItem.Returnable__c';
import WOLI_COMPONENT_TAG from '@salesforce/schema/WorkOrderLineItem.ComponentTag__c';
import WOLI_REMOVED_PART from '@salesforce/schema/WorkOrderLineItem.RemovedPart__c';
import WOLI_USAGES_EXCEPTION from '@salesforce/schema/WorkOrderLineItem.UsagesException__c';
import WOLI_APPROVAL_STATUS from '@salesforce/schema/WorkOrderLineItem.ApprovalStatus__c';
import WOLI_NON_APPROVED_PART_RESPONSE from '@salesforce/schema/WorkOrderLineItem.NonApprovedPartResponse__c';
import WOLI_PART_EXCEPTION_REASON from '@salesforce/schema/WorkOrderLineItem.PartExceptionReason__c';
import WOLI_BILLING_TYPE from '@salesforce/schema/WorkOrderLineItem.BillingType__c';
import WOLI_LIST_PRICE_CUSTOM from '@salesforce/schema/WorkOrderLineItem.ListPrice__c';
import WOLI_UNIT_PRICE_CUSTOM from '@salesforce/schema/WorkOrderLineItem.UnitPrice__c';
import WOLI_TOTAL_PRICE_CUSTOM from '@salesforce/schema/WorkOrderLineItem.TotalPrice__c';
import evaluateAllowedUnit from '@salesforce/apex/WoDebriefAllowedUnitController.evaluateAllowedUnit';
import evaluateAllowedUnitByProduct from '@salesforce/apex/WoDebriefAllowedUnitController.evaluateAllowedUnitByProduct';
import evaluateBillingType from '@salesforce/apex/WoDebriefAllowedUnitController.evaluateBillingType';
import evaluateBillingTypeForProductItem from '@salesforce/apex/WoDebriefAllowedUnitController.evaluateBillingTypeForProductItem';
import getComponentTagsForProduct from '@salesforce/apex/WoDebriefAllowedUnitController.getComponentTagsForProduct';
import getComponentTagsForProductItem from '@salesforce/apex/WoDebriefAllowedUnitController.getComponentTagsForProductItem';
import checkProductItemApproval from '@salesforce/apex/PartExceptionService.checkProductItemApproval';
import findProductItemByProductCode from '@salesforce/apex/WoDebriefProductItemController.findByProductCode';
import findProductByProductCode from '@salesforce/apex/WoDebriefProductItemController.findProductByProductCode';
import getLocationIdForServiceResource from '@salesforce/apex/WoDebriefProductItemController.getLocationIdForServiceResource';
import getUsageConsumptionRecordTypeId from '@salesforce/apex/WoDebriefProductItemController.getUsageConsumptionRecordTypeId';
import getRateListForWorkOrder from '@salesforce/apex/WoDebriefRateListController.getRateListForWorkOrder';
import resolveExpenseTypes from '@salesforce/apex/WoDebriefRegionalExpenseController.resolveExpenseTypes';
import saveExpense from '@salesforce/apex/WoDebriefRegionalExpenseController.saveExpense';
import listExpenseBillableFields from '@salesforce/apex/WoDebriefRegionalExpenseController.listExpenseBillableFields';
import checkServiceResourceSkills from '@salesforce/apex/WoDebriefSkillCheckController.checkServiceResourceSkills';
import getAssignedServiceResourceId from '@salesforce/apex/WoDebriefSkillCheckController.getAssignedServiceResourceId';
import getCurrentUserServiceResourceId from '@salesforce/apex/WoDebriefSkillCheckController.getCurrentUserServiceResourceId';
import PRODUCT2_PRODUCT_TYPE from '@salesforce/schema/Product2.ProductType__c';

import ASSET_TYPE from '@salesforce/schema/Asset.AssetType__c';
import ASSET_INTERNAL_CATEGORY from '@salesforce/schema/Asset.InternalAssetCategory__c';

import WO_CYCLE_COUNT from '@salesforce/schema/WorkOrder.CycleCount__c';
import WO_CYCLE_COUNT_DATE from '@salesforce/schema/WorkOrder.CycleCountDate__c';

import PC_OBJECT from '@salesforce/schema/ProductConsumed';
import PC_WORKORDER from '@salesforce/schema/ProductConsumed.WorkOrderId';
import PC_PRODUCTITEM from '@salesforce/schema/ProductConsumed.ProductItemId';
import PC_QUANTITY from '@salesforce/schema/ProductConsumed.QuantityConsumed';
import PC_DESCRIPTION from '@salesforce/schema/ProductConsumed.Description';
import PC_RETURNABLE from '@salesforce/schema/ProductConsumed.Returnable__c';
import PC_SERVICE_RESOURCE from '@salesforce/schema/ProductConsumed.ServiceResource__c';
import PC_WORKORDER_LINE_ITEM from '@salesforce/schema/ProductConsumed.WorkOrderLineItemId';

import PR_OBJECT from '@salesforce/schema/ProductRequired';
import PR_PARENT from '@salesforce/schema/ProductRequired.ParentRecordId';
import PR_PRODUCT from '@salesforce/schema/ProductRequired.Product2Id';
import PR_QUANTITY from '@salesforce/schema/ProductRequired.QuantityRequired';
import PR_RETURNABLE from '@salesforce/schema/ProductRequired.Returnable__c';

import EXPENSE_OBJECT from '@salesforce/schema/Expense';
import EXPENSE_EXPENSETYPE from '@salesforce/schema/Expense.ExpenseType';
import EXPENSE_DESCRIPTION from '@salesforce/schema/Expense.Description';
import EXPENSE_QUANTITY from '@salesforce/schema/Expense.Quantity';
import EXPENSE_UNITPRICE from '@salesforce/schema/Expense.UnitPrice';
import EXPENSE_TOTALPRICE from '@salesforce/schema/Expense.TotalPrice';
import EXPENSE_AMOUNT from '@salesforce/schema/Expense.Amount';
import EXPENSE_WORKORDER from '@salesforce/schema/Expense.WorkOrderId';
import EXPENSE_CURRENCY from '@salesforce/schema/Expense.CurrencyIsoCode';
import EXPENSE_OWNER from '@salesforce/schema/Expense.OwnerId';
import EXPENSE_TRANSACTIONDATE from '@salesforce/schema/Expense.TransactionDate';
import OVERRIDE_CODE from '@salesforce/schema/Expense.OverrideCode__c';
import EXPENSE_BILLABLE_AMOUNT from '@salesforce/schema/Expense.BillableAmount__c';
import EXPENSE_OVERRIDE_BILLABLE from '@salesforce/schema/Expense.OverrideBillableAmount__c';

const PART_EXCEPTION_PROMPT =
    'This part is not approved for this product and must be sent to service engineering for approval prior to replacement. Would you like to proceed?';
const PART_EXCEPTION_REASON_OPTIONS = [
    { label: 'Approved Part Unavailable', value: 'Approved Part Unavailable' },
    { label: 'Substitute Part', value: 'Substitute Part' },
    { label: 'Superseded Part', value: 'Superseded Part' },
    { label: 'Missing from SBOM', value: 'Missing from SBOM' },
    { label: 'SBOM Data Error', value: 'SBOM Data Error' },
    { label: 'Engineering Change', value: 'Engineering Change' },
    { label: 'Customer Requested Part', value: 'Customer Requested Part' },
    { label: 'Other', value: 'Other' }
];
const RETURNABLE_PART_ALERT_MESSAGE = 'Please note this is a returnable part.';
const PARTS_SOURCE_TRUNK = 'TrunkStock';
const PARTS_SOURCE_CUSTOMER = 'Customer Part';
const NO_COMPONENT_TAG_MESSAGE = 'No component tag available for this part.';
const PARTS_SOURCE_ON_ORDER = 'On Order';
const PARTS_SOURCE_INVENTORY_ISSUE = 'Inventory Issue';
const PARTS_SOURCE_ALLOWED = new Set([
    PARTS_SOURCE_TRUNK,
    PARTS_SOURCE_CUSTOMER,
    PARTS_SOURCE_ON_ORDER,
    PARTS_SOURCE_INVENTORY_ISSUE
]);
const BILLING_TYPE_LABELS = {
    Contract: 'Contract',
    Warranty: 'Warranty',
    'SVC Warranty': 'SVC Warranty',
    Billable: 'Billable',
    Courtesy: 'Courtesy'
};

/**
 * @description Maps renamed PartsSource__c API values so existing WOLIs still match debrief UI.
 * @param {String} value PartsSource__c API value
 * @return {String|null} Current API value, or the original when it is not a debrief source
 */
function normalizePartsSource(value) {
    if (value === 'Trunk Stock' || value === 'Trunk' || value === PARTS_SOURCE_TRUNK) {
        return PARTS_SOURCE_TRUNK;
    }
    if (value === 'Customer Stock' || value === PARTS_SOURCE_CUSTOMER) {
        return PARTS_SOURCE_CUSTOMER;
    }
    return value || null;
}

const PARTS_CONSUMED_RELATED_LIST_ID = 'ProductsConsumed';
const PARTS_CONSUMED_RELATED_LIST_FIELDS = [
    'ProductConsumed.Id',
    'ProductConsumed.QuantityConsumed',
    'ProductConsumed.Description',
    'ProductConsumed.ProductItemId',
    'ProductConsumed.Product2Id',
    `ProductConsumed.${PC_RETURNABLE.fieldApiName}`,
    `ProductConsumed.${PC_SERVICE_RESOURCE.fieldApiName}`,
    'ProductConsumed.WorkOrderLineItemId'
];

const PRODUCTS_REQUIRED_RELATED_LIST_ID = 'ProductsRequired';
const PRODUCTS_REQUIRED_RELATED_LIST_FIELDS = [
    'ProductRequired.Id',
    'ProductRequired.Product2Id',
    'ProductRequired.Product2.Name',
    'ProductRequired.QuantityRequired',
    `ProductRequired.${PR_RETURNABLE.fieldApiName}`
];

const EXPENSE_RELATED_LIST_ID = 'Expenses';
const EXPENSE_RELATED_LIST_FIELDS = [
    'Expense.Id',
    'Expense.ExpenseType',
    'Expense.Description',
    'Expense.Quantity',
    'Expense.UnitPrice',
    'Expense.TotalPrice',
    'Expense.Amount',
    'Expense.TransactionDate',
    'Expense.OverrideCode__c',
    'Expense.BillableAmount__c',
    'Expense.OverrideBillableAmount__c'
];

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
                            Description { value }
                            Quantity { value }
                            UnitPrice { value }
                            TotalPrice { value }
                            Amount { value }
                            TransactionDate { value }
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

const PRODUCTS_REQUIRED_QUERY = gql`
    query GetWorkOrderProductsRequired($workOrderId: ID) {
        uiapi {
            query {
                ProductRequired(
                    where: { ParentRecordId: { eq: $workOrderId } }
                    first: 200
                ) {
                    edges {
                        node {
                            Id
                            Product2Id { value }
                            QuantityRequired { value }
                            Returnable__c { value }
                            Product2 {
                                Id
                                Name { value }
                            }
                        }
                    }
                }
            }
        }
    }
`;

const WORK_ORDER_QUERY = gql`
    query GetWorkOrderDebriefES($workOrderId: ID) {
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
                            CoverageBadge__c { value }
                            Account {
                                Name { value }
                            }
                            AssetId { value }
                            Asset {
                                Name { value }
                                SerialNumber { value }
                            }
                            NoEquipmentWorkOrder__c { value }
                            Model__c { value }
                            CycleCount__c { value }
                            CycleCountDate__c { value }
                            CurrencyIsoCode { value }
                            WorkTypeId { value }
                            WorkType {
                                Id
                                Name { value }
                            }
                            WorkOrderLineItems(first: 200) {
                                edges {
                                    node {
                                        Id
                                        LineItemNumber { value }
                                        LineType__c { value }
                                        WorkTypeId { value }
                                        WorkType {
                                            Id
                                            Name { value }
                                        }
                                        Rate__c { value }
                                        TravelType__c { value }
                                        StartDate { value }
                                        EndDate { value }
                                        Duration { value }
                                        ListPrice__c { value }
                                        UnitPrice__c { value }
                                        TotalPrice__c { value }
                                        UnitQty__c { value }
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
                                        ProductCode__c { value }
                                        ProductDescription__c { value }
                                        Description { value }
                                        ProductItem__c { value }
                                        ProductItem__r {
                                            Id
                                            Product2Id { value }
                                            ProductName { value }
                                            Product2 {
                                                Id
                                                Name { value }
                                                RefurbishedProduct__c { value }
                                                RefurbishedProduct__r {
                                                    Id
                                                    Name { value }
                                                }
                                            }
                                        }
                                        Product__c { value }
                                        Product__r {
                                            Id
                                            Name { value }
                                            RefurbishedProduct__c { value }
                                            RefurbishedProduct__r {
                                                Id
                                                Name { value }
                                            }
                                        }
                                        PartDescription__c { value }
                                        AllowedUnit__c { value }
                                        Returnable__c { value }
                                        ComponentTag__c { value }
                                        ComponentTag__r {
                                            Id
                                            Name { value }
                                        }
                                        RemovedPart__c { value }
                                        UsagesException__c { value }
                                        BillingType__c { value }
                                        RepairCode__c { value }
                                        PartsSource__c { value }
                                        RepairCode__r {
                                            Id
                                            ProductCode { value }
                                            Description { value }
                                            Name { value }
                                        }
                                    }
                                }
                            }
                            ProductsConsumed(first: 200) {
                                edges {
                                    node {
                                        Id
                                        QuantityConsumed { value }
                                        Description { value }
                                        ProductItemId { value }
                                        Product2Id { value }
                                        Returnable__c { value }
                                        ServiceResource__c { value }
                                        WorkOrderLineItemId { value }
                                        WorkOrderLineItem {
                                            PartsSource__c { value }
                                        }
                                        ProductItem {
                                            Id
                                            ProductName { value }
                                        }
                                        Product2 {
                                            Id
                                            Name { value }
                                            IsReturnable__c { value }
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
                            LocationId { value }
                        }
                    }
                }
            }
        }
    }
`;

const SERVICE_RESOURCE_NAMES_QUERY = gql`
    query GetServiceResourceNames($resourceIds: [ID]) {
        uiapi {
            query {
                ServiceResource(
                    where: { Id: { in: $resourceIds } }
                    first: 50
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

const TAB_DEFS = [
    { key: 'Time', label: 'Time', addLabel: '+ Add Time Line', type: null, canAdd: true, schema: 'time' },
    { key: 'Parts', label: 'Parts', addLabel: '+ Add Parts Line', type: 'Parts', canAdd: true, schema: 'parts' },
    { key: 'Expense', label: 'Expenses', addLabel: '+ Add Expense Line', type: null, canAdd: true, schema: 'expense' },
    { key: 'RequiredProducts', label: 'Required Parts', addLabel: '+ Add Required Part', type: null, canAdd: false, schema: 'required_product' },
    { key: 'Calibration', label: 'Calibration', addLabel: '+ Add Calibration Line', type: 'Calibration', canAdd: true, schema: 'calibration' }
];

const TIME_LINE_TYPES = new Set(['Travel', 'Labor']);
const WOLI_USAGE_CONSUMPTION_RT = 'UsageConsumption';

const LINE_TYPE_TO_SCHEMA = {
    Travel: 'travel',
    Labor: 'labor',
    Calibration: 'calibration',
    Parts: 'parts'
};

const TIME_LINE_TYPE_OPTIONS = [
    { label: 'Travel', value: 'Travel' },
    { label: 'Labor', value: 'Labor' }
];

const RATE_OPTIONS = [
    { label: 'Standard', value: 'Standard' },
    { label: 'Overtime', value: 'Overtime' },
    { label: 'Premium', value: 'Premium' }
];
const RATE_STANDARD = 'Standard';

const TRAVEL_TYPE_ACTUAL = 'Actual Travel';
const TRAVEL_ZONE_FIELD_BY_TYPE = {
    'Travel Zone 1': 'travelZone1',
    'Travel Zone 2': 'travelZone2',
    'Travel Zone 3': 'travelZone3',
    'Travel Zone 4': 'travelZone4'
};

const SERVICE_CODE_PRODUCT_TYPE = 'Service Code';
const PART_PRODUCT_TYPE = 'Part';
const CALIBRATION_DEVICE_CATEGORY = 'Calibration Device';
const STERIS_ASSET_TYPE = 'STERIS Asset';

const PARTS_SOURCE_OPTIONS = [
    { label: 'Trunk', value: PARTS_SOURCE_TRUNK },
    { label: 'Customer Part', value: PARTS_SOURCE_CUSTOMER },
    { label: 'On Order', value: PARTS_SOURCE_ON_ORDER },
    { label: 'Inventory Issue', value: PARTS_SOURCE_INVENTORY_ISSUE }
];

/**
 * @description Keeps Part's Source options in debrief display order.
 * @param {Array<{label: String, value: String}>} options Picklist options
 * @return {Array<{label: String, value: String}>}
 */
function sortPartsSourceOptions(options) {
    const order = new Map(PARTS_SOURCE_OPTIONS.map((option, index) => [option.value, index]));
    return [...(options ?? [])].sort((a, b) => {
        const aIndex = order.has(a.value) ? order.get(a.value) : Number.MAX_SAFE_INTEGER;
        const bIndex = order.has(b.value) ? order.get(b.value) : Number.MAX_SAFE_INTEGER;
        if (aIndex !== bIndex) return aIndex - bIndex;
        return (a.label || '').localeCompare(b.label || '');
    });
}

const EXPENSE_TYPE_OPTIONS = [
    { label: 'Billable', value: 'Billable' },
    { label: 'Non-Billable', value: 'Non-Billable' },
    { label: 'Airfare', value: 'Airfare' },
    { label: 'Chamber Cleaning', value: 'Chamber Cleaning' },
    { label: 'Control Program Uploading', value: 'Control Program Uploading' },
    { label: 'Kilometers', value: 'Kilometers' },
    { label: 'Loaner', value: 'Loaner' },
    { label: 'Local Purchase', value: 'Local Purchase' },
    { label: 'Meals', value: 'Meals' },
    { label: 'Mileage', value: 'Mileage' },
    { label: 'Misc.', value: 'Misc.' },
    { label: 'Parking', value: 'Parking' },
    { label: 'Shipping and Handling', value: 'Shipping and Handling' },
    { label: 'Specialty Billing', value: 'Specialty Billing' },
    { label: 'Specialty Item', value: 'Specialty Item' },
    { label: 'Sub Cost', value: 'Sub Cost' },
    { label: 'Supplies', value: 'Supplies' },
    { label: 'Tolls', value: 'Tolls' }
];

const TYPE_TO_DEF = {
    Travel: { key: 'Time', type: 'Travel', schema: 'travel' },
    Labor: { key: 'Time', type: 'Labor', schema: 'labor' },
    Parts: { key: 'Parts', type: 'Parts', schema: 'parts' },
    Calibration: { key: 'Calibration', type: 'Calibration', schema: 'calibration' }
};

const TAB_KEY_TO_DEF = TAB_DEFS.reduce((acc, d) => {
    acc[d.key] = d;
    return acc;
}, {});

const EMPTY_ADD_FORM_VISIBILITY = () =>
    TAB_DEFS.filter(d => d.canAdd).reduce((acc, d) => { acc[d.key] = false; return acc; }, {});

const EMPTY_TAB_SEARCH_TERMS = () =>
    TAB_DEFS.reduce((acc, d) => { acc[d.key] = ''; return acc; }, {});

let _tempIdSeq = 0;

/**
 * @description WoDebriefES Lightning Web Component.
 * @author Uptima Development Team
 */
export default class WoDebriefES extends LightningElement {
    @api recordId;

    graphqlResult;
    expensesGraphqlResult;
    productsRequiredGraphqlResult;
    partsListResult;
    requiredListResult;
    expensesListResult;

    _workOrder = null;
    _serverLines = [];
    _serverPartsFromGraphql = [];
    _serverPartsFromRelatedList = [];
    _serverPartsConsumed = [];
    _serverRequiredFromGraphql = [];
    _serverRequiredFromRelatedList = [];
    _serverProductsRequired = [];
    _serverExpensesFromGraphql = [];
    _serverExpensesFromRelatedList = [];
    /** @description Apex-sourced billable custom fields keyed by 15-character Expense Id. */
    _expenseBillableById = {};
    _serverExpenses = [];

    _pendingEdits = {};
    _pendingDeletes = {};
    _pendingAdds = [];
    _pendingCycleCount;
    _pendingCycleCountDate;
    editStateMap = {};

    _repairCodeNameById = {};
    _repairCodeProductCodeById = {};
    _repairCodeDescriptionById = {};
    _repairCodeLookupId;
    /** @description Location Id by Service Resource Id (reactive so Product Item filters refresh). */
    locationIdByServiceResourceId = {};
    productItemFilterVersion = 0;
    _serviceResourceLocationLookupId;
    _productItemLookupId;
    _product2LookupId;
    _product2IdByProductItemId = {};
    _isReturnableByProductItemId = {};
    _productItemNameByProductItemId = {};
    _productNameByProduct2Id = {};
    _productCodeByProduct2Id = {};
    _partDescriptionByProduct2Id = {};
    _isReturnableByProduct2Id = {};
    /** @description Refurbished product `{ id, name }` keyed by the source Product2 Id. */
    _refurbishedByProduct2Id = {};
    /** @description Product2 whose removed-part options are being loaded. */
    _removedPartSourceProduct2Id;
    _partsSourceByWoliId = {};
    _serviceResourceNameById = {};
    _serviceResourceIdsForLookup;

    _currentUserServiceResourceId = null;
    _currentUserServiceResourceName = '';
    /** @description Service Resource assigned on the Work Order appointment, when present. */
    _workOrderAssignedResourceId = null;
    /** @description Rate List prices for travel and labor options/pricing (reactive; do not prefix with _). */
    rateList = null;
    /** @description Allowed Expense.ExpenseType values from Regional Control; null until loaded. */
    allowedExpenseTypes = null;
    /** @description Timestamp passed to Apex so Field Service does not reuse a stale response. */
    expenseTypeCacheBust = '0';
    /** @description True while an imperative expense-type request is in flight. */
    _expenseTypesLoading = false;
    /** @description True after the first expense-type request is started (prevents render loops). */
    _expenseTypesLoadStarted = false;
    /** @description Default WorkOrderLineItem record type for picklist wires. */
    woliDefaultRecordTypeId;
    /** @description WorkOrderLineItem UsageConsumption record type Id. */
    _usageConsumptionRecordTypeId = null;
    /** @description PartsSource__c picklist options from the WOLI field. */
    partsSourcePicklistOptions = [];
    partExceptionReasonOptions = PART_EXCEPTION_REASON_OPTIONS;
    partExceptionDecisionOptions = [
        { label: 'Yes', value: 'yes' },
        { label: 'No', value: 'no' }
    ];
    /** @description Record type Id used for Expense.OverrideCode__c picklist values. */
    expensePicklistRecordTypeId;
    /** @description Override Code picklist options from Expense.OverrideCode__c. */
    overrideCodePicklistOptions = [];

    tabSearchTerms = EMPTY_TAB_SEARCH_TERMS();
    showAddForm = EMPTY_ADD_FORM_VISIBILITY();
    addFormState = {};
    editErrors = {};
    addErrors = {};
    _saving = false;
    activeTab = 'Time';

    isOffline = !navigator.onLine;
    _onlineHandler = () => {
        this.isOffline = false;
        this._refreshAllowedExpenseTypes();
    };
    _offlineHandler = () => { this.isOffline = true; };
    /**
     * @description Lifecycle hook invoked when the component is inserted into the DOM.
     */
    connectedCallback() {
        window.addEventListener('online', this._onlineHandler);
        window.addEventListener('offline', this._offlineHandler);
        this.addFormState = this._emptyAddFormState();
        this._refreshAllowedExpenseTypes();
    }

    /**
     * @description Loads Regional Control expense types once recordId is available.
     *              Field Service Screen Actions often set recordId after connectedCallback.
     */
    renderedCallback() {
        if (this.recordId && this.allowedExpenseTypes == null && !this._expenseTypesLoadStarted) {
            this._refreshAllowedExpenseTypes();
        }
    }

    /**
     * @description Lifecycle hook invoked when the component is removed from the DOM.
     */
    disconnectedCallback() {
        window.removeEventListener('online', this._onlineHandler);
        window.removeEventListener('offline', this._offlineHandler);
    }

    /**
     * @description Wire adapter handler: Data.
     */
    @wire(graphql, { query: WORK_ORDER_QUERY, variables: '$queryVariables' })
    wiredData(result) {
        this.graphqlResult = result;
        if (!result.data) return;
        const woEdge = result.data.uiapi.query.WorkOrder.edges[0];
        if (!woEdge) return;
        this._workOrder = woEdge.node;
        this._serverLines = (woEdge.node.WorkOrderLineItems?.edges ?? []).map(e => e.node);
        this._serverPartsFromGraphql = (woEdge.node.ProductsConsumed?.edges ?? []).map(e => e.node);
        this._seedRepairCodeCache(this._serverLines);
        this._seedPartsSourceCacheFromLines(this._serverLines);
        this._seedProductItemNameCacheFromWoliLines(this._serverLines);
        this._seedRemovedPartSourcesFromWoliLines(this._serverLines);
        this._seedReturnableCacheFromParts(this._serverPartsFromGraphql);
        this._seedProductItemNameCacheFromParts(this._serverPartsFromGraphql);
        this._refreshServiceResourceNameLookups(this._serverPartsFromGraphql);
        this._rebuildServerPartsConsumed();
        this._defaultAddFormWorkTypeFromHeader();
    }

    /**
     * @description Wire: Schema UsageConsumption Record Type Id. Field Service mobile
     *              getObjectInfo often omits developerName or marks the type unavailable.
     */
    @wire(getUsageConsumptionRecordTypeId)
    wiredUsageConsumptionRecordType({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woDebriefES getUsageConsumptionRecordTypeId failed', error);
            return;
        }
        if (data) {
            this._usageConsumptionRecordTypeId = data;
        }
    }

    /**
     * @description Wire: WorkOrderLineItem object info for PartsSource__c picklist values.
     */
    @wire(getObjectInfo, { objectApiName: WOLI_OBJECT })
    wiredWoliObjectInfo({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woDebriefES getObjectInfo WorkOrderLineItem failed', error);
            return;
        }
        if (data?.defaultRecordTypeId) {
            this.woliDefaultRecordTypeId = data.defaultRecordTypeId;
        }
        const resolved = this._recordTypeIdByDeveloperName(
            data,
            WOLI_USAGE_CONSUMPTION_RT
        );
        if (resolved) {
            this._usageConsumptionRecordTypeId = resolved;
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$woliDefaultRecordTypeId',
        fieldApiName: WOLI_PARTS_SOURCE
    })
    wiredPartsSourcePicklist({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woDebriefES getPicklistValues PartsSource__c failed', error);
            return;
        }
        if (data?.values) {
            this.partsSourcePicklistOptions = this._debriefPartsSourceOptions(data.values);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$woliDefaultRecordTypeId',
        fieldApiName: WOLI_PART_EXCEPTION_REASON
    })
    wiredPartExceptionReasonPicklist({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woDebriefES getPicklistValues PartExceptionReason__c failed', error);
            return;
        }
        if (data?.values?.length) {
            this.partExceptionReasonOptions = data.values.map(({ label, value }) => ({ label, value }));
        }
    }

    /**
     * @description Wire: Expense object info for Override Code picklist record type.
     */
    @wire(getObjectInfo, { objectApiName: EXPENSE_OBJECT })
    wiredExpenseObjectInfo({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woDebriefES getObjectInfo Expense failed', error);
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
            console.error('woDebriefES getPicklistValues OverrideCode__c failed', error);
            return;
        }
        if (data?.values) {
            this.overrideCodePicklistOptions = data.values.map(({ label, value }) => ({ label, value }));
        }
    }

    /**
     * @description Imperatively loads Regional Control expense types.
     *              Field Service mobile often does not run @wire Apex on Screen Actions;
     *              this matches the Rate List fallback used on Travel.
     */
    async _refreshAllowedExpenseTypes() {
        if (!this.recordId || this._expenseTypesLoading) {
            return;
        }
        this._expenseTypesLoadStarted = true;
        this._expenseTypesLoading = true;
        this.expenseTypeCacheBust = String(Date.now());
        try {
            const data = await resolveExpenseTypes({
                workOrderId: this.recordId,
                cacheBust: this.expenseTypeCacheBust
            });
            this.allowedExpenseTypes = Array.isArray(data) ? data : [];
        } catch (e) {
            // No Regional Control match and Apex failures both show all types.
            this.allowedExpenseTypes = [];
            // eslint-disable-next-line no-console
            console.error('woDebriefES resolveExpenseTypes failed', e);
        } finally {
            this._expenseTypesLoading = false;
        }
    }

    /**
     * @description Wire: Rate List for WO Account (GW-2965 labor / GW-2967 travel pricing).
     */
    @wire(getRateListForWorkOrder, { workOrderId: '$recordId' })
    wiredRateList({ data, error }) {
        if (error) {
            this.rateList = null;
            // eslint-disable-next-line no-console
            console.error('woDebriefES getRateListForWorkOrder failed', error);
            return;
        }
        if (data !== undefined) {
            this.rateList = data;
            this._applyDefaultTravelTypeWhenReady();
        }
    }

    /**
     * @description Sets Travel Type to Actual Travel (default) once Rate List options are available.
     */
    _applyDefaultTravelTypeWhenReady() {
        const defaultTravel = this._defaultTravelType();
        if (!defaultTravel) {
            return;
        }
        if (this.addFormState?.lineType === 'Travel' && !this.addFormState.travelType) {
            this.addFormState = this._applyTravelPricingToState({
                ...this.addFormState,
                travelType: defaultTravel
            });
        }
        const nextEdits = { ...this._pendingEdits };
        let editsChanged = false;
        for (const [id, edit] of Object.entries(nextEdits)) {
            const isTravel = edit.lineType === 'Travel' || edit._lineType === 'Travel' || edit._schema === 'travel';
            if (isTravel && !edit.travelType) {
                nextEdits[id] = this._applyTravelPricingToState({ ...edit, travelType: defaultTravel });
                editsChanged = true;
            }
        }
        if (editsChanged) {
            this._pendingEdits = nextEdits;
        }
        this._pendingAdds = this._pendingAdds.map((add) => {
            const isTravel = add.lineType === 'Travel' || add._lineType === 'Travel' || add._schema === 'travel';
            if (isTravel && !add.travelType) {
                return this._applyTravelPricingToState({ ...add, travelType: defaultTravel });
            }
            return add;
        });
    }

    /**
     * @description Imperatively loads Rate List when Travel Types are missing (FLS / wire timing).
     */
    async _ensureRateListLoaded() {
        if (!this.recordId || this.travelTypeOptions.length) {
            return;
        }
        try {
            this.rateList = await getRateListForWorkOrder({ workOrderId: this.recordId });
            this._applyDefaultTravelTypeWhenReady();
        } catch (e) {
            this.rateList = null;
            // eslint-disable-next-line no-console
            console.error('woDebriefES _ensureRateListLoaded failed', e);
        }
    }

    /**
     * @description Wire adapter handler: Products Required Graphql.
     */
    @wire(graphql, { query: PRODUCTS_REQUIRED_QUERY, variables: '$queryVariables' })
    wiredProductsRequiredGraphql(result) {
        this.productsRequiredGraphqlResult = result;
        if (result.data) {
            this._serverRequiredFromGraphql = (result.data.uiapi.query.ProductRequired?.edges ?? []).map(e => e.node);
            this._rebuildServerProductsRequired();
        }
    }

    /**
     * @description Wire adapter handler: Expenses Graphql.
     */
    @wire(graphql, { query: EXPENSES_QUERY, variables: '$expenseQueryVariables' })
    wiredExpensesGraphql(result) {
        this.expensesGraphqlResult = result;
        if (result.data) {
            this._serverExpensesFromGraphql = (result.data.uiapi.query.Expense?.edges ?? [])
                .map(e => this._normalizeExpenseRecord(e.node));
            this._rebuildServerExpenses();
            this._refreshExpenseBillableFields();
        }
    }

    /**
     * @description Wire adapter handler: Parts Related.
     */
    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: PARTS_CONSUMED_RELATED_LIST_ID,
        fields: PARTS_CONSUMED_RELATED_LIST_FIELDS,
        pageSize: 200
    })
    wiredPartsRelated(result) {
        this.partsListResult = result;
        if (result.data) {
            this._serverPartsFromRelatedList = (result.data.records ?? []).map(r => this._normalizePartFromLds(r));
            this._seedProductItemNameCacheFromParts(this._serverPartsFromRelatedList);
            this._refreshServiceResourceNameLookups(this._serverPartsFromRelatedList);
            this._rebuildServerPartsConsumed();
        }
    }

    /**
     * @description Wire adapter handler: Required Related.
     */
    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: PRODUCTS_REQUIRED_RELATED_LIST_ID,
        fields: PRODUCTS_REQUIRED_RELATED_LIST_FIELDS,
        pageSize: 200
    })
    wiredRequiredRelated(result) {
        this.requiredListResult = result;
        if (result.data) {
            this._serverRequiredFromRelatedList = (result.data.records ?? []).map(r => this._normalizeRequiredFromLds(r));
            this._rebuildServerProductsRequired();
        }
    }

    /**
     * @description Wire adapter handler: Expenses Related.
     */
    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: EXPENSE_RELATED_LIST_ID,
        fields: EXPENSE_RELATED_LIST_FIELDS,
        pageSize: 200
    })
    wiredExpensesRelated(result) {
        this.expensesListResult = result;
        if (result.data) {
            this._serverExpensesFromRelatedList = (result.data.records ?? [])
                .map(r => this._normalizeExpenseRecord(this._normalizeExpenseFromLds(r)));
            this._rebuildServerExpenses();
            this._refreshExpenseBillableFields();
        }
    }

    /**
     * @description Wire adapter handler: Current User Service Resource.
     */
    @wire(graphql, { query: CURRENT_USER_SERVICE_RESOURCE_QUERY, variables: '$currentUserQueryVariables' })
    wiredCurrentUserServiceResource(result) {
        const edge = result.data?.uiapi?.query?.ServiceResource?.edges?.[0];
        if (!edge) return;
        this._currentUserServiceResourceId = edge.node.Id;
        this._currentUserServiceResourceName = edge.node.Name?.value ?? '';
        const locationId = edge.node.LocationId?.value ?? null;
        if (this._currentUserServiceResourceId) {
            this._cacheServiceResourceLocation(this._currentUserServiceResourceId, locationId);
            this._resolveLocationForResource(this._currentUserServiceResourceId);
        }
        if (this._currentUserServiceResourceId && this._currentUserServiceResourceName) {
            this._cacheServiceResourceName(
                this._currentUserServiceResourceId,
                this._currentUserServiceResourceName
            );
        }
        this._applyDefaultResourceToAddForm();
    }

    /**
     * @description Wire adapter handler: Work Order assigned Service Resource.
     */
    @wire(getAssignedServiceResourceId, { workOrderId: '$recordId' })
    wiredWorkOrderAssignedResource({ data, error }) {
        if (error || !data) {
            return;
        }
        this._workOrderAssignedResourceId = data;
        this._applyDefaultResourceToAddForm();
    }

    /**
     * @description Wire adapter handler: Service Resource Location.
     */
    @wire(getRecord, { recordId: '$_serviceResourceLocationLookupId', fields: ['ServiceResource.LocationId', 'ServiceResource.Name'] })
    wiredServiceResourceLocation({ data }) {
        if (!data) return;
        const srId = data.id;
        const locationId = data.fields?.LocationId?.value;
        const name = data.fields?.Name?.value;
        if (srId && locationId) {
            this._cacheServiceResourceLocation(srId, locationId);
        }
        if (srId && name) {
            this._cacheServiceResourceName(srId, name);
        }
    }

    /**
     * @description Wire adapter handler: Service Resource Names.
     */
    @wire(graphql, { query: SERVICE_RESOURCE_NAMES_QUERY, variables: '$serviceResourceQueryVariables' })
    wiredServiceResourceNames(result) {
        if (!result.data) return;
        for (const edge of result.data.uiapi.query.ServiceResource?.edges ?? []) {
            const id = edge.node.Id;
            const name = edge.node.Name?.value;
            if (id && name) this._cacheServiceResourceName(id, name);
        }
    }

    /**
     * @description Wire adapter handler: Product Item.
     */
    @wire(getRecord, {
        recordId: '$_productItemLookupId',
        fields: [
            'ProductItem.Product2Id',
            'ProductItem.ProductName',
            'ProductItem.Product2.IsReturnable__c',
            'ProductItem.Product2.ProductCode',
            'ProductItem.Product2.Description'
        ]
    })
    wiredProductItem({ data }) {
        if (!data) return;
        const piId = data.id;
        const product2Id = data.fields?.Product2Id?.value;
        const productName = data.fields?.ProductName?.value;
        const product2Fields = data.fields?.Product2?.value?.fields;
        const isReturnable = product2Fields?.IsReturnable__c?.value;
        const productCode = product2Fields?.ProductCode?.value;
        const partDescription = product2Fields?.Description?.value;
        if (piId && product2Id) {
            this._product2IdByProductItemId = { ...this._product2IdByProductItemId, [piId]: product2Id };
            this._removedPartSourceProduct2Id = product2Id;
        }
        if (piId && productName) {
            this._productItemNameByProductItemId = { ...this._productItemNameByProductItemId, [piId]: productName };
        }
        if (product2Id && productName) {
            this._productNameByProduct2Id = { ...this._productNameByProduct2Id, [product2Id]: productName };
        }
        if (product2Id && productCode != null) {
            this._productCodeByProduct2Id = { ...this._productCodeByProduct2Id, [product2Id]: productCode };
        }
        if (product2Id && partDescription != null) {
            this._partDescriptionByProduct2Id = { ...this._partDescriptionByProduct2Id, [product2Id]: partDescription };
        }
        if (product2Id && isReturnable !== undefined && isReturnable !== null) {
            this._isReturnableByProduct2Id = { ...this._isReturnableByProduct2Id, [product2Id]: isReturnable };
        }
        if (piId && isReturnable !== undefined && isReturnable !== null) {
            this._isReturnableByProductItemId = { ...this._isReturnableByProductItemId, [piId]: isReturnable };
            this._syncReturnableForProductItem(piId, isReturnable);
        }
        if (piId && (productCode != null || partDescription != null)) {
            this._syncProductDetailsForProductItem(piId, { productCode, partDescription });
        }
        this._seedProductItemNameCacheFromWoliLines(this._serverLines);
    }

    /**
     * @description Wire adapter handler: Product2 details (Customer Stock).
     */
    @wire(getRecord, {
        recordId: '$_product2LookupId',
        fields: [
            'Product2.Name',
            'Product2.ProductCode',
            'Product2.Description',
            'Product2.IsReturnable__c'
        ]
    })
    wiredProduct2Details({ data }) {
        if (!data) return;
        const product2Id = data.id;
        this._applyProductDetails(product2Id, {
            name: data.fields?.Name?.value,
            productCode: data.fields?.ProductCode?.value,
            partDescription: data.fields?.Description?.value,
            isReturnable: data.fields?.IsReturnable__c?.value
        });
    }

    /**
     * @description Loads the selected product name and RefurbishedProduct__c for Removed Part options.
     */
    @wire(getRecord, {
        recordId: '$_removedPartSourceProduct2Id',
        fields: [
            'Product2.Name',
            'Product2.RefurbishedProduct__c',
            'Product2.RefurbishedProduct__r.Name'
        ]
    })
    wiredRemovedPartSource({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woDebriefES refurbished product lookup failed', error);
            return;
        }
        if (!data) return;
        const product2Id = data.id;
        const name = data.fields?.Name?.value;
        if (product2Id && name) {
            this._productNameByProduct2Id = { ...this._productNameByProduct2Id, [product2Id]: name };
        }
        const refurbished = data.fields?.RefurbishedProduct__r;
        const refurbishedName = refurbished?.value?.fields?.Name?.value
            ?? refurbished?.displayValue
            ?? null;
        this._cacheRefurbishedProduct(
            product2Id,
            data.fields?.RefurbishedProduct__c?.value ?? null,
            refurbishedName
        );
    }

    /**
     * @description Wire adapter handler: Repair Code Details.
     */
    @wire(getRecord, {
        recordId: '$_repairCodeLookupId',
        fields: ['Product2.Name', 'Product2.ProductCode', 'Product2.Description']
    })
    wiredRepairCodeDetails({ data }) {
        if (!data) return;
        const id = data.id;
        const name = data.fields?.Name?.value;
        const productCode = data.fields?.ProductCode?.value;
        const description = data.fields?.Description?.value;
        this._cacheRepairCodeDetails(id, { name, productCode, description });
        this._syncRepairCodeDetailsForProduct(id, productCode, description);
    }

    /**
     * @description Query Variables.
     */
    get queryVariables() { return { workOrderId: this.recordId }; }
    /**
     * @description Expense Query Variables.
     */
    get expenseQueryVariables() { return this.recordId ? { workOrderId: this.recordId } : undefined; }
    /**
     * @description Current User Query Variables.
     */
    get currentUserQueryVariables() { return { userId: USER_ID }; }
    /**
     * @description Service Resource Query Variables.
     */
    get serviceResourceQueryVariables() {
        return this._serviceResourceIdsForLookup?.length
            ? { resourceIds: this._serviceResourceIdsForLookup }
            : undefined;
    }

    /**
     * @description Is Loading.
     */
    get isLoading() {
        const woLoading = !this.graphqlResult?.data && !this.graphqlResult?.errors;
        const gqlExpDone = !this.recordId || this.expensesGraphqlResult?.data || this.expensesGraphqlResult?.errors;
        const gqlReqDone = !this.recordId || this.productsRequiredGraphqlResult?.data || this.productsRequiredGraphqlResult?.errors;
        const rlPartsDone = !this.recordId || this.partsListResult?.data || this.partsListResult?.error;
        const rlReqDone = !this.recordId || this.requiredListResult?.data || this.requiredListResult?.error;
        const rlExpDone = !this.recordId || this.expensesListResult?.data || this.expensesListResult?.error;
        return woLoading || (!!this.recordId && !(gqlExpDone && gqlReqDone && rlPartsDone && rlReqDone && rlExpDone));
    }

    /**
     * @description Has Error.
     */
    get hasError() { return !!this.graphqlResult?.errors; }
    /**
     * @description Error Message.
     */
    get errorMessage() { return JSON.stringify(this.graphqlResult?.errors); }
    /**
     * @description Wo Status.
     */
    get woStatus() { return this._workOrder?.Status?.value ?? ''; }
    /**
     * @description Wo Account Name.
     */
    get woAccountName() { return this._workOrder?.Account?.Name?.value ?? ''; }
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
     * @description True when the Work Order has an Asset, or No Equipment Work Order is checked.
     */
    get hasValidEquipment() {
        const assetId = this._workOrder?.AssetId?.value ?? this._workOrder?.Asset?.Id ?? null;
        if (assetId) {
            return true;
        }
        return this._workOrder?.NoEquipmentWorkOrder__c?.value === true;
    }

    /**
     * @description Message shown when the Work Order has neither an Asset nor the No Equipment checkbox.
     */
    get missingEquipmentMessage() {
        return 'This Work Order needs an Asset, or the No Equipment Work Order checkbox checked.';
    }

    /**
     * @description Wo Cycle Count.
     */
    get woCycleCount() {
        if (this._pendingCycleCount !== undefined) return this._pendingCycleCount;
        return this._workOrder?.CycleCount__c?.value ?? '';
    }

    /**
     * @description Wo Cycle Count Date.
     */
    get woCycleCountDate() {
        if (this._pendingCycleCountDate !== undefined) return this._pendingCycleCountDate;
        return this._workOrder?.CycleCountDate__c?.value ?? '';
    }

    /**
     * @description Wo Number.
     */
    get woNumber() { return this._workOrder?.WorkOrderNumber?.value ?? ''; }

    /**
     * @description GW-2059 coverage flag: Warranty, Contract, or Billable.
     */
    get coverageBadge() {
        return this._workOrder?.CoverageBadge__c?.value ?? '';
    }

    /**
     * @description Header class so warranty, contract, and billable stay distinct on a phone.
     */
    get coverageBadgeClass() {
        const value = this.coverageBadge;
        if (value.includes('WARRANTY')) {
            return 'coverage-badge coverage-badge_warranty';
        }
        if (value.includes('CONTRACT')) {
            return 'coverage-badge coverage-badge_contract';
        }
        if (value.includes('BILLABLE')) {
            return 'coverage-badge coverage-badge_billable';
        }
        return 'coverage-badge';
    }
    /**
     * @description Has Pending Changes.
     */
    get hasPendingChanges() {
        return this._pendingCycleCount !== undefined ||
            this._pendingCycleCountDate !== undefined ||
            Object.keys(this._pendingEdits).length > 0 ||
            Object.keys(this._pendingDeletes).length > 0 ||
            this._pendingAdds.length > 0;
    }

    /**
     * @description Save All Disabled.
     */
    get saveAllDisabled() { return !this.hasPendingChanges || this._saving; }
    /**
     * @description Cancel Disabled.
     */
    get cancelDisabled() { return this._saving; }
    /**
     * @description Tabs.
     */
    get tabs() {
        void this.productItemFilterVersion;
        return TAB_DEFS.map(def => ({
            key: def.key,
            label: def.label,
            addLabel: def.addLabel,
            canAdd: def.canAdd,
            schema: def.schema,
            isActive: this.activeTab === def.key,
            showAddForm: !!this.showAddForm[def.key],
            addError: this.addErrors[def.key] ?? '',
            lines: this._buildLinesFor(def)
        }));
    }

    /**
     * @description Active Tab Model.
     */
    get activeTabModel() { return this.tabs.find(t => t.isActive) ?? this.tabs[0]; }
    /**
     * @description Active Tab Search Term.
     */
    get activeTabSearchTerm() { return this.tabSearchTerms[this.activeTab] ?? ''; }
    /**
     * @description Active Tab Search Placeholder.
     */
    get activeTabSearchPlaceholder() {
        const schema = this.activeTabModel?.schema;
        if (schema === 'parts') return 'Search product, unit qty, or description…';
        if (schema === 'time') return 'Search resource, dates, or rate…';
        if (schema === 'travel') return 'Search resource or dates…';
        if (schema === 'labor') return 'Search resource or dates…';
        if (schema === 'calibration') return 'Search resource, asset, or dates…';
        if (schema === 'required_product') return 'Search product or quantity…';
        if (schema === 'expense') return 'Search type, description, or amount…';
        return 'Search lines…';
    }

    /**
     * @description Active Tab Has No Search Results.
     */
    get activeTabHasNoSearchResults() {
        const term = (this.activeTabSearchTerm ?? '').trim();
        return !!term && (this.activeTabModel?.lines?.length ?? 0) === 0;
    }

    /**
     * @description Is Active Tab Parts.
     */
    get isActiveTabParts() { return this.activeTabModel?.schema === 'parts'; }
    /**
     * @description Is Active Tab Time.
     */
    get isActiveTabTime() { return this.activeTabModel?.schema === 'time'; }
    /**
     * @description Is Active Tab Travel.
     */
    get isActiveTabTravel() { return this.activeTabModel?.schema === 'travel'; }
    /**
     * @description Is Active Tab Labor.
     */
    get isActiveTabLabor() { return this.activeTabModel?.schema === 'labor'; }
    /**
     * @description Is Active Tab Calibration.
     */
    get isActiveTabCalibration() { return this.activeTabModel?.schema === 'calibration'; }
    /**
     * @description Is Active Tab Expense.
     */
    get isActiveTabExpense() { return this.activeTabModel?.schema === 'expense'; }
    /**
     * @description Expense Type Options. Restricted by Regional Control when a match is found.
     */
    get expenseTypeOptions() {
        const allowedList = Array.isArray(this.allowedExpenseTypes)
            ? this.allowedExpenseTypes
            : [];
        if (!allowedList.length) {
            return EXPENSE_TYPE_OPTIONS;
        }
        const allowed = new Set(allowedList);
        const filtered = EXPENSE_TYPE_OPTIONS.filter((option) => allowed.has(option.value));
        for (const value of allowedList) {
            if (!filtered.some((option) => option.value === value)) {
                filtered.push({ label: value, value });
            }
        }
        return filtered.length ? filtered : EXPENSE_TYPE_OPTIONS;
    }
    /**
     * @description Override Code picklist options.
     */
    get overrideCodeOptions() { return this.overrideCodePicklistOptions; }
    /**
     * @description True when the add-form Billable Amount is locked to Total Price.
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
        const amount = this._isTruthyFlag(this.addFormState.overrideBillableAmount)
            ? this.addFormState.billableAmount
            : this._computeExpenseAmount(this.addFormState);
        return this._fmtMoney(amount || 0);
    }
    /**
     * @description Parts Source Options.
     */
    get partsSourceOptions() {
        return this.partsSourcePicklistOptions.length
            ? this.partsSourcePicklistOptions
            : PARTS_SOURCE_OPTIONS;
    }
    /**
     * @description Add Form Is Trunk Stock.
     */
    get addFormIsTrunkStock() {
        return normalizePartsSource(this.addFormState.partsSource) === PARTS_SOURCE_TRUNK;
    }
    /**
     * @description Add Form Is Customer Stock.
     */
    get addFormIsCustomerStock() {
        return normalizePartsSource(this.addFormState.partsSource) === PARTS_SOURCE_CUSTOMER;
    }
    /**
     * @description Add Form Product Code.
     */
    get addFormProductCode() { return this.addFormState.productCode || ''; }
    /**
     * @description Add Form Part Description.
     */
    get addFormPartDescription() { return this.addFormState.partDescription || ''; }
    /**
     * @description Time Line Type Options.
     */
    get timeLineTypeOptions() { return TIME_LINE_TYPE_OPTIONS; }
    /**
     * @description Rate Options.
     */
    get addFormRateOptions() {
        return this._rateOptionsForLineType(this.addFormState.lineType);
    }
    /**
     * @description Travel Type options driven by populated Rate List values (GW-2967).
     */
    get travelTypeOptions() {
        return this._buildTravelTypeOptionsFromRateList();
    }
    /**
     * @description Add Form Is Travel Line.
     */
    get addFormIsTravelLine() { return this.addFormState.lineType === 'Travel'; }
    /**
     * @description True when Rate combobox should show on add form (Labor always; Travel only for Actual Travel).
     */
    get addFormShowRateField() {
        return this.addFormIsLaborLine
            || (this.addFormIsTravelLine && this.addFormState.travelType === TRAVEL_TYPE_ACTUAL);
    }
    /**
     * @description Rate required on add form for Actual Travel.
     */
    get addFormIsRateRequired() {
        return this.addFormIsTravelLine && this.addFormState.travelType === TRAVEL_TYPE_ACTUAL;
    }
    /**
     * @description Add Form Is Labor Line.
     */
    get addFormIsLaborLine() { return this.addFormState.lineType === 'Labor'; }
    /**
     * @description Add Form Is Labor or Travel Line.
     */
    get addFormHasRatePricing() {
        return this.addFormIsLaborLine || this.addFormIsTravelLine;
    }
    /**
     * @description Add Form Has Time Line Type.
     */
    get addFormHasTimeLineType() { return !!this.addFormState.lineType; }
    /**
     * @description Add Form Returnable Label.
     */
    get addFormReturnableLabel() {
        if (this.addFormIsCustomerStock) {
            return this._fmtReturnable(
                this._resolveReturnableForProduct2(this.addFormState.product2Id)
                ?? this.addFormState.returnable
            );
        }
        return this._fmtReturnable(this._resolveReturnableForProductItem(this.addFormState.productItemId));
    }

    /**
     * @description Removed Part is required on the add form when the selected part is returnable.
     */
    get addFormIsRemovedPartRequired() {
        if (this.addFormIsCustomerStock) {
            return this._isRemovedPartRequired(
                this._resolveReturnableForProduct2(this.addFormState.product2Id)
                ?? this.addFormState.returnable
            );
        }
        return this._isRemovedPartRequired(
            this._resolveReturnableForProductItem(this.addFormState.productItemId)
            ?? this.addFormState.returnable
        );
    }

    /**
     * @description Removed Part choices: the selected product, plus its refurbished product when set.
     */
    get addFormRemovedPartOptions() {
        const sourceProduct2Id = this._sourceProduct2IdForAddForm();
        const fallbackName = this.addFormState.productItemId
            ? this._productItemNameByProductItemId[this.addFormState.productItemId]
            : null;
        return this._removedPartOptions(sourceProduct2Id, fallbackName);
    }

    /**
     * @description Removed Part stays closed until a product is selected.
     */
    get addFormRemovedPartDisabled() {
        return this.addFormRemovedPartOptions.length === 0;
    }

    /**
     * @description Add Form Allowed Unit Label.
     */
    get addFormAllowedUnitLabel() {
        return this._fmtReturnable(this.addFormState.allowedUnit);
    }

    get partExceptionPrompt() {
        return PART_EXCEPTION_PROMPT;
    }

    get addFormShowPartExceptionQuestion() {
        return this.addFormState?.allowedUnit === false
            && this.addFormState?.partExceptionAlreadyApproved !== true
            && this.addFormState?.partExceptionBlocked !== true;
    }

    get addFormShowPartException() {
        return this.addFormShowPartExceptionQuestion
            && this.addFormState?.partExceptionDecision === 'yes';
    }

    /**
     * @description Add Form Billing Type Label (read-only; set by automation after save).
     */
    get addFormBillingTypeLabel() {
        return this._fmtBillingType(this.addFormState.billingType);
    }

    /**
     * @description GW-6095 — Component Tag view fields for the Parts add form.
     */
    get addFormComponentTag() {
        return this._componentTagView({
            allowedUnit: this.addFormState?.allowedUnit,
            componentTagId: this.addFormState?.componentTagId,
            componentTagOptions: this.addFormState?.componentTagOptions,
            componentTagsLoaded: this.addFormState?.componentTagsLoaded
        });
    }

    /**
     * @description Add Form Duration Label (legacy getter; duration is now editable).
     */
    get addFormDurationLabel() {
        return this._fmtDurationLabel(
            this.addFormState.durationHours
                ?? this._computeDurationHours(this.addFormState.startDate, this.addFormState.endDate)
        );
    }

    /**
     * @description Computed Add Total Price.
     */
    get computedAddTotalPrice() {
        const amount = this._computeExpenseAmount(this.addFormState);
        return (amount || 0).toFixed(2);
    }

    /**
     * @description Add Form Rate is required for Labor lines.
     */
    get addFormIsRateRequired() {
        return this.addFormIsLaborLine;
    }

    /**
     * @description Formatted List Price for add labor form.
     */
    get addFormListPriceLabel() {
        return this._fmtOptionalMoney(this.addFormState.listPrice);
    }

    /**
     * @description Formatted Unit Price for add labor form.
     */
    get addFormUnitPriceLabel() {
        return this._fmtOptionalMoney(this.addFormState.unitPrice);
    }

    /**
     * @description Formatted Total Price for add labor form.
     */
    get addFormTotalPriceLabel() {
        return this._fmtOptionalMoney(this.addFormState.totalPrice);
    }

    /**
     * @description Add Form Repair Code Name.
     */
    get addFormRepairCodeName() {
        return this._repairCodeNameById[this.addFormState.repairCodeId] ?? '';
    }

    /**
     * @description Add Form Product Item Filter.
     */
    get addFormProductItemFilter() {
        return this._productItemFilterForResource(this.addFormState.assignedResourceId);
    }

    /**
     * @description Add Form Product Item Scan Disabled.
     */
    get addFormProductItemScanDisabled() {
        return !this.addFormState.assignedResourceId;
    }

    /**
     * @description Resource Picker Filter.
     */
    get resourcePickerFilter() {
        return { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] };
    }

    /**
     * @description Resource Picker Display Info.
     */
    get resourcePickerDisplayInfo() { return { primaryField: 'Name' }; }
    /**
     * @description Resource Picker Matching Info.
     */
    get resourcePickerMatchingInfo() { return { primaryField: { fieldPath: 'Name' } }; }
    /**
     * @description Asset Picker Display Info.
     */
    get assetPickerDisplayInfo() { return { primaryField: 'SerialNumber', additionalFields: ['Name'] }; }
    /**
     * @description Asset Picker Matching Info.
     */
    get assetPickerMatchingInfo() {
        return {
            primaryField: { fieldPath: 'SerialNumber' },
            additionalFields: [{ fieldPath: 'Name' }]
        };
    }

    /**
     * @description Calibration Asset Picker Filter.
     */
    get calibrationAssetPickerFilter() {
        return {
            criteria: [
                {
                    fieldPath: ASSET_INTERNAL_CATEGORY.fieldApiName,
                    operator: 'eq',
                    value: CALIBRATION_DEVICE_CATEGORY
                },
                {
                    fieldPath: ASSET_TYPE.fieldApiName,
                    operator: 'eq',
                    value: STERIS_ASSET_TYPE
                }
            ],
            filterLogic: '1 AND 2'
        };
    }

    /**
     * @description Product Item Picker Display Info.
     */
    get productItemPickerDisplayInfo() {
        return {
            primaryField: 'ProductName',
            additionalFields: ['Product2.ProductCode']
        };
    }
    /**
     * @description Product Item Picker Matching Info.
     */
    get productItemPickerMatchingInfo() {
        return {
            primaryField: { fieldPath: 'ProductName' },
            additionalFields: [{ fieldPath: 'Product2.ProductCode' }]
        };
    }
    /**
     * @description Product Picker Display Info.
     */
    get productPickerDisplayInfo() { return { primaryField: 'ProductCode', additionalFields: ['Name'] }; }
    /**
     * @description Product Picker Matching Info.
     */
    get productPickerMatchingInfo() {
        return {
            primaryField: { fieldPath: 'ProductCode' },
            additionalFields: [{ fieldPath: 'Name' }]
        };
    }
    /**
     * @description Product Picker Filter — active Part products (customer stock).
     */
    get productPickerFilter() {
        return {
            criteria: [
                { fieldPath: 'IsActive', operator: 'eq', value: true },
                {
                    fieldPath: PRODUCT2_PRODUCT_TYPE.fieldApiName,
                    operator: 'eq',
                    value: PART_PRODUCT_TYPE
                }
            ],
            filterLogic: '1 AND 2'
        };
    }
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
    get repairCodePickerDisplayInfo() { return { primaryField: 'ProductCode', additionalFields: ['Name'] }; }
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
     * @description Handle Tab Select.
     */
    handleTabSelect(e) {
        this.activeTab = e.currentTarget.dataset.tab;
        if (this.activeTab === 'Expense') {
            this._refreshAllowedExpenseTypes();
        }
    }
    /**
     * @description Handle Cycle Count Change.
     */
    handleCycleCountChange(e) {
        this._pendingCycleCount = e.target.value ?? '';
    }

    /**
     * @description Handle Cycle Count Date Change.
     */
    handleCycleCountDateChange(e) {
        this._pendingCycleCountDate = e.target.value ?? '';
    }

    /**
     * @description Handle Tab Search Change.
     */
    handleTabSearchChange(e) {
        this.tabSearchTerms = { ...this.tabSearchTerms, [this.activeTab]: e.detail.value ?? '' };
    }

    /**
     * @description Handle Edit Toggle.
     */
    handleEditToggle(e) {
        const id = e.currentTarget.dataset.id;
        if (this._serverProductsRequired.some(p => p.Id === id)) return;
        const cur = this.editStateMap[id];
        const opening = !cur?.isEditing;
        this.editStateMap = { ...this.editStateMap, [id]: { isEditing: opening } };
        const errs = { ...this.editErrors };
        delete errs[id];
        this.editErrors = errs;
        if (opening) this._ensureRemovedPartSourceForLine(id);
    }

    /**
     * @description Handle Edit Close.
     */
    handleEditClose(e) {
        const id = e.currentTarget.dataset.id;
        if (this._serverProductsRequired.some(p => p.Id === id)) return;
        this.editStateMap = { ...this.editStateMap, [id]: { isEditing: false } };
        const errs = { ...this.editErrors };
        delete errs[id];
        this.editErrors = errs;
    }

    /**
     * @description Handle Edit Field Change.
     */
    handleEditFieldChange(e) {
        const id = e.currentTarget.dataset.id;
        const field = e.currentTarget.dataset.field;
        const rawValue = e.detail.checked !== undefined ? e.detail.checked : e.detail.value;
        const value = field === 'removedPartId' && !rawValue ? null : rawValue;
        this._stageEdit(id, field, value);
        if (field === 'partExceptionDecision') {
            this._stageEdit(id, 'partExceptionSubmit', value === 'yes');
        }
        if (field === 'lineType') {
            if (value === 'Travel') {
                this._stageEdit(id, 'repairCodeId', null);
                const defaultTravel = this._defaultTravelType();
                this._stageEdit(id, 'travelType', defaultTravel);
                this._stageEdit(
                    id,
                    'rate',
                    defaultTravel === TRAVEL_TYPE_ACTUAL ? this._defaultRate('Travel') : null
                );
                this._applyTravelPricingToEdit(id);
            } else if (value === 'Labor') {
                this._stageEdit(id, 'travelType', null);
                this._stageEdit(id, 'rate', this._defaultRate('Labor'));
                this._stageEdit(id, 'listPrice', null);
                this._stageEdit(id, 'unitPrice', null);
                this._stageEdit(id, 'totalPrice', null);
                this._stageEdit(id, 'quantity', null);
            }
            const schema = LINE_TYPE_TO_SCHEMA[value];
            if (schema) {
                this._stageEdit(id, '_schema', schema);
                this._stageEdit(id, '_lineType', value);
            }
        }
        if (field === 'partsSource') {
            this._stageEdit(id, 'removedPartId', null);
            this._applyPartsSourceChangeToEdit(id, value);
        }
        if (field === 'startDate' || field === 'endDate' || field === 'durationHours') {
            this._syncTimeFieldsOnEdit(id, field);
        }
        if (field === 'travelType' || field === 'rate' || field === 'durationHours') {
            if (field === 'travelType' && value !== TRAVEL_TYPE_ACTUAL) {
                this._stageEdit(id, 'rate', null);
            }
            if (field === 'travelType' && value === TRAVEL_TYPE_ACTUAL) {
                const pending = this._pendingEdits[id] || this._pendingAdds.find((a) => a._tempId === id);
                if (!pending?.rate) {
                    this._stageEdit(id, 'rate', this._defaultRate('Travel'));
                }
            }
            this._applyTravelPricingToEdit(id);
        }
        if (field === 'rate' || field === 'startDate' || field === 'endDate' || field === 'lineType') {
            this._applyLaborPricingToEdit(id);
        }
    }

    /**
     * @description Handle Delete.
     */
    handleDelete(e) {
        const id = e.currentTarget.dataset.id;
        if (this._serverProductsRequired.some(p => p.Id === id)) return;
        if (this._pendingAdds.some(a => a._tempId === id)) {
            this._pendingAdds = this._pendingAdds.filter(a => a._tempId !== id);
            return;
        }
        this._pendingDeletes = { ...this._pendingDeletes, [id]: true };
        const edits = { ...this._pendingEdits };
        delete edits[id];
        this._pendingEdits = edits;
    }

    /**
     * @description Handle Add Toggle.
     */
    handleAddToggle(e) {
        const tab = e.currentTarget.dataset.tab || this.activeTab;
        this.showAddForm = { ...EMPTY_ADD_FORM_VISIBILITY(), [tab]: true };
        this.addFormState = this._emptyAddFormState();
        this.addErrors = {};
        if (this.addFormState.assignedResourceId) {
            this._onResourceSelected(this.addFormState.assignedResourceId);
        }
    }

    /**
     * @description Handle Add Field Change.
     */
    async handleAddFieldChange(e) {
        const field = e.currentTarget.dataset.field;
        const rawValue = e.detail.checked !== undefined ? e.detail.checked : e.detail.value;
        const value = field === 'removedPartId' && !rawValue ? null : rawValue;
        let next = { ...this.addFormState, [field]: value };
        if (field === 'partExceptionDecision') {
            next.partExceptionSubmit = value === 'yes';
        }
        if (field === 'lineType') {
            next.repairCodeId = null;
            next.productCode = '';
            next.productDescription = '';
            next.travelType = '';
            next.rate = '';
            next.listPrice = null;
            next.unitPrice = null;
            next.totalPrice = null;
            next.quantity = null;
            if (value === 'Travel' || value === 'Labor') {
                next.workTypeId = next.workTypeId || this._headerWorkTypeId();
            }
            if (value === 'Travel') {
                await this._ensureRateListLoaded();
                next.travelType = this._defaultTravelType();
                if (next.travelType === TRAVEL_TYPE_ACTUAL) {
                    next.rate = this._defaultRate('Travel');
                }
                next = this._applyTravelPricingToState(next);
                if (!this.travelTypeOptions.length) {
                    this._toast(
                        'No Travel Types available',
                        'Assign a Rate List with Travel Hour or Travel Zone values on the Work Order Account.',
                        'warning'
                    );
                }
            } else if (value === 'Labor') {
                next.rate = this._defaultRate('Labor');
            }
        }
        if (field === 'partsSource') {
            next.allowedUnit = null;
            next.returnable = null;
            Object.assign(next, this._clearedComponentTagFields());
            next.removedPartId = null;
            next.productCode = '';
            next.partDescription = '';
            if (normalizePartsSource(value) === PARTS_SOURCE_TRUNK) {
                next.product2Id = null;
                if (next.productItemId) {
                    const linkedProduct2Id = this._product2IdByProductItemId[next.productItemId];
                    next.returnable = this._resolveReturnableForProductItem(next.productItemId);
                    next.productCode = linkedProduct2Id
                        ? (this._productCodeByProduct2Id[linkedProduct2Id] ?? '')
                        : '';
                    next.partDescription = linkedProduct2Id
                        ? (this._partDescriptionByProduct2Id[linkedProduct2Id] ?? '')
                        : '';
                    this.addFormState = next;
                    this._onProductItemSelected(next.productItemId, { isAddForm: true });
                    return;
                }
            } else if (normalizePartsSource(value) === PARTS_SOURCE_CUSTOMER) {
                next.productItemId = null;
            }
        }
        if (field === 'partsSource') {
            next.allowedUnit = null;
            next.returnable = null;
            Object.assign(next, this._clearedComponentTagFields());
            next.removedPartId = null;
            next.productCode = '';
            next.partDescription = '';
            if (normalizePartsSource(value) === PARTS_SOURCE_TRUNK) {
                next.product2Id = null;
                if (next.productItemId) {
                    const linkedProduct2Id = this._product2IdByProductItemId[next.productItemId];
                    next.returnable = this._resolveReturnableForProductItem(next.productItemId);
                    next.productCode = linkedProduct2Id
                        ? (this._productCodeByProduct2Id[linkedProduct2Id] ?? '')
                        : '';
                    next.partDescription = linkedProduct2Id
                        ? (this._partDescriptionByProduct2Id[linkedProduct2Id] ?? '')
                        : '';
                    this.addFormState = next;
                    this._onProductItemSelected(next.productItemId, { isAddForm: true });
                    return;
                }
            } else if (normalizePartsSource(value) === PARTS_SOURCE_CUSTOMER) {
                next.productItemId = null;
            }
        }
        if (field === 'startDate' || field === 'endDate' || field === 'durationHours') {
            next = this._syncTimeFieldsOnState(next, field);
        }
        if (field === 'travelType' || field === 'rate' || field === 'durationHours') {
            if (field === 'travelType' && value !== TRAVEL_TYPE_ACTUAL) {
                next.rate = '';
            }
            if (field === 'travelType' && value === TRAVEL_TYPE_ACTUAL && !next.rate) {
                next.rate = this._defaultRate(next.lineType || 'Travel');
            }
            next = this._applyTravelPricingToState(next);
        }
        if (field === 'rate' || field === 'startDate' || field === 'endDate' || field === 'lineType') {
            next = this._applyLaborPricingToState(next);
        }
        if (field === 'unitPrice' || field === 'quantity') {
            next = this._applyExpenseAmountToState(next);
        }
        if (field === 'overrideBillableAmount') {
            next = this._applyExpenseBillableSync(next, field);
        }
        this.addFormState = next;
    }

    /**
     * @description Handle Product Item Barcode Scan.
     */
    async handleProductItemBarcodeScan(e) {
        const editId = e.currentTarget.dataset.id || null;
        const isAddForm = e.currentTarget.dataset.mode === 'add';
        const resourceId = isAddForm
            ? this.addFormState.assignedResourceId
            : (this.editStateMap[editId]?.assignedResourceId
                ?? this._pendingEdits[editId]?.assignedResourceId
                ?? this._resourceIdForEditLine(editId));
        if (!resourceId) {
            this._toast('Select a Resource', 'Choose an Assigned Resource before scanning.', 'warning');
            return;
        }

        const productCode = await this._captureProductCode();
        if (!productCode) return;

        try {
            const match = await findProductItemByProductCode({
                productCode,
                serviceResourceId: resourceId
            });
            if (match?.locationId) {
                this._cacheServiceResourceLocation(resourceId, match.locationId);
            }
            if (!match?.productItemId) {
                this._toast(
                    'No match',
                    match?.locationId
                        ? `No in-stock Product Item found for Product Code "${productCode}" at this resource location.`
                        : 'The selected Resource has no Location for trunk stock.',
                    'warning'
                );
                return;
            }
            if (match.matchCount > 1) {
                this._toast(
                    'Multiple matches',
                    `Multiple Product Items matched "${productCode}". The highest-quantity item was selected.`,
                    'info'
                );
            }
            this._applyScannedProductItem(match, { editId, isAddForm });
        } catch (error) {
            this._toast(
                'Scan lookup failed',
                this._apexErrorMessage(error) || 'Unable to find Product Item for scanned code.',
                'error'
            );
        }
    }

    /**
     * @description Handle Product barcode scan (Customer Stock — Product2 by Product Code).
     */
    async handleProductBarcodeScan(e) {
        const editId = e.currentTarget.dataset.id || null;
        const isAddForm = e.currentTarget.dataset.mode === 'add';

        const productCode = await this._captureProductCode();
        if (!productCode) return;

        try {
            const match = await findProductByProductCode({ productCode });
            if (!match?.product2Id) {
                this._toast(
                    'No match',
                    `No active Product found for Product Code "${productCode}".`,
                    'warning'
                );
                return;
            }
            if (match.matchCount > 1) {
                this._toast(
                    'Multiple matches',
                    `Multiple Products matched "${productCode}". The most recently modified product was selected.`,
                    'info'
                );
            }
            this._applyScannedProduct(match, { editId, isAddForm });
        } catch (error) {
            this._toast(
                'Scan lookup failed',
                this._apexErrorMessage(error) || 'Unable to find Product for scanned code.',
                'error'
            );
        }
    }

    /**
     * @description Internal helper: Capture Product Code.
     */
    async _captureProductCode() {
        const scanner = getBarcodeScanner();
        if (scanner && scanner.isAvailable()) {
            try {
                let first;
                if (typeof scanner.scan === 'function') {
                    const results = await scanner.scan({
                        instructionText: 'Scan product barcode',
                        successText: 'Scan complete'
                    });
                    first = Array.isArray(results) ? results[0] : results;
                } else if (typeof scanner.beginCapture === 'function') {
                    first = await scanner.beginCapture({
                        instructionText: 'Scan product barcode',
                        successText: 'Scan complete'
                    });
                }
                const value = (typeof first === 'string' ? first : (first?.value ?? '')).trim();
                return value || null;
            } catch (error) {
                if (error?.code === 'userDismissedScanner') return null;
                this._toast(
                    'Barcode scanner',
                    error?.message || 'Unable to open the barcode scanner.',
                    'error'
                );
                return null;
            } finally {
                try {
                    if (typeof scanner.dismiss === 'function') scanner.dismiss();
                    else if (typeof scanner.endCapture === 'function') scanner.endCapture();
                } catch (e) {
                    // ignore dismiss errors
                }
            }
        }

        return new Promise((resolve) => {
            LightningPrompt.open({
                label: 'Product Code',
                message: 'Camera scan is unavailable. Enter the Product Code from the barcode.',
                defaultValue: ''
            }).then((value) => {
                const code = (value ?? '').trim();
                resolve(code || null);
            }).catch(() => resolve(null));
        });
    }

    /**
     * @description Handle Lookup Change.
     */
    handleLookupChange(e) {
        const id = e.currentTarget.dataset.id;
        const tab = e.currentTarget.dataset.tab;
        const field = e.currentTarget.dataset.field;
        const recordId = this._lookupRecordId(e);

        if (id) {
            this._stageEdit(id, field, recordId);
            if (field === 'workTypeId' || field === 'assignedResourceId') {
                this._checkTimeWorkTypeSkillsForLine(id);
            }
            if (field === 'assignedResourceId') this._onResourceSelected(recordId, id);
            if (field === 'productItemId') {
                this._stageEdit(id, 'removedPartId', null);
                if (recordId) this._stageEdit(id, 'partsSource', PARTS_SOURCE_TRUNK);
                this._onProductItemSelected(recordId, { editId: id });
            }
            if (field === 'product2Id') {
                this._stageEdit(id, 'removedPartId', null);
                if (recordId) {
                    this._stageEdit(id, 'partsSource', PARTS_SOURCE_CUSTOMER);
                    this._product2LookupId = recordId;
                    this._removedPartSourceProduct2Id = recordId;
                }
                this._evaluateAllowedUnitForProduct(recordId, { editId: id });
                this._evaluateBillingType({ product2Id: recordId, editId: id });
            }
        } else if (tab) {
            const next = { ...this.addFormState, [field]: recordId };
            if (field === 'assignedResourceId') {
                this._onResourceSelected(recordId);
                next.productItemId = null;
                next.product2Id = null;
                next.removedPartId = null;
                next.productCode = '';
                next.partDescription = '';
                next.returnable = null;
                next.allowedUnit = null;
                next.billingType = '';
                Object.assign(next, this._clearedComponentTagFields());
            }
            if (field === 'productItemId') {
                const linkedProduct2Id = recordId
                    ? (this._product2IdByProductItemId[recordId] ?? null)
                    : null;
                next.product2Id = null;
                next.removedPartId = null;
                if (linkedProduct2Id) this._removedPartSourceProduct2Id = linkedProduct2Id;
                if (recordId) next.partsSource = PARTS_SOURCE_TRUNK;
                next.returnable = recordId
                    ? (this._resolveReturnableForProductItem(recordId) ?? null)
                    : null;
                next.productCode = linkedProduct2Id
                    ? (this._productCodeByProduct2Id[linkedProduct2Id] ?? '')
                    : '';
                next.partDescription = linkedProduct2Id
                    ? (this._partDescriptionByProduct2Id[linkedProduct2Id] ?? '')
                    : '';
                next.allowedUnit = null;
                next.billingType = '';
                Object.assign(next, this._clearedComponentTagFields());
                Object.assign(next, this._clearedPartExceptionFields());
                this._onProductItemSelected(recordId, { isAddForm: true });
            }
            if (field === 'product2Id') {
                next.productItemId = null;
                next.removedPartId = null;
                if (recordId) {
                    next.partsSource = PARTS_SOURCE_CUSTOMER;
                    this._removedPartSourceProduct2Id = recordId;
                }
                next.returnable = recordId
                    ? (this._resolveReturnableForProduct2(recordId) ?? null)
                    : null;
                next.productCode = recordId
                    ? (this._productCodeByProduct2Id[recordId] ?? '')
                    : '';
                next.partDescription = recordId
                    ? (this._partDescriptionByProduct2Id[recordId] ?? '')
                    : '';
                next.allowedUnit = null;
                next.billingType = '';
                Object.assign(next, this._clearedComponentTagFields());
                Object.assign(next, this._clearedPartExceptionFields());
                if (recordId) this._product2LookupId = recordId;
                this._evaluateAllowedUnitForProduct(recordId, { isAddForm: true });
                this._evaluateBillingType({ product2Id: recordId, isAddForm: true });
            }
            if (field === 'repairCodeId') {
                next.productCode = recordId ? (this._resolveProductCodeForRepairCode(recordId) ?? '') : '';
                next.productDescription = recordId ? (this._resolveProductDescriptionForRepairCode(recordId) ?? '') : '';
                if (recordId) this._repairCodeLookupId = recordId;
            }
            this.addFormState = next;
            if ((field === 'workTypeId' || field === 'assignedResourceId') && tab === 'Time') {
                this._checkTimeWorkTypeSkills({
                    workTypeId: next.workTypeId,
                    assignedResourceId: next.assignedResourceId,
                    isAddForm: true
                });
            }
        }

        if (field === 'repairCodeId' && recordId) {
            this._repairCodeLookupId = recordId;
        }
    }

    /**
     * @description Handle Add Confirm.
     */
    async handleAddConfirm(e) {
        const tab = e.currentTarget.dataset.tab || this.activeTab;
        const def = TAB_KEY_TO_DEF[tab];
        const schema = def?.schema ?? 'generic';
        let payload = { ...this.addFormState };
        if (schema !== 'expense' && schema !== 'required_product' && schema !== 'parts_consumed') {
            payload.assignedResourceId = this._resolveAssignedResourceId(payload.assignedResourceId);
        }
        if (schema === 'time') {
            payload.assignedResourceId = this._resolveAssignedResourceId(payload.assignedResourceId);
        }
        if (schema === 'parts_consumed') {
            payload.assignedResourceId = this._resolveAssignedResourceId(payload.assignedResourceId);
            payload.product2Id = payload.product2Id || this._product2IdByProductItemId[payload.productItemId] || null;
            payload.returnable = this._resolveReturnableForProductItem(payload.productItemId);
        }
        if (schema === 'parts') {
            payload.assignedResourceId = this._resolveAssignedResourceId(payload.assignedResourceId);
            const isTrunk = normalizePartsSource(payload.partsSource) === PARTS_SOURCE_TRUNK;
            const isCustomer = normalizePartsSource(payload.partsSource) === PARTS_SOURCE_CUSTOMER;
            if (isTrunk) {
                payload.product2Id = null;
                payload.returnable = this._resolveReturnableForProductItem(payload.productItemId);
                if (payload.productItemId) {
                    await this._evaluateAllowedUnitForProductItem(payload.productItemId, { isAddForm: true });
                    await this._evaluateBillingType({
                        productItemId: payload.productItemId,
                        isAddForm: true
                    });
                    payload = {
                        ...payload,
                        allowedUnit: this.addFormState.allowedUnit,
                        billingType: this.addFormState.billingType,
                        componentTagId: this.addFormState.componentTagId ?? null,
                        componentTagOptions: this.addFormState.componentTagOptions ?? [],
                        componentTagsLoaded: !!this.addFormState.componentTagsLoaded,
                        returnable: this.addFormState.returnable
                            ?? this._resolveReturnableForProductItem(payload.productItemId)
                    };
                }
            } else if (isCustomer) {
                payload.productItemId = null;
                payload.returnable = this._resolveReturnableForProduct2(payload.product2Id)
                    ?? payload.returnable;
                if (payload.product2Id) {
                    await this._evaluateAllowedUnitForProduct(payload.product2Id, { isAddForm: true });
                    await this._evaluateBillingType({
                        product2Id: payload.product2Id,
                        isAddForm: true
                    });
                    payload = {
                        ...payload,
                        allowedUnit: this.addFormState.allowedUnit,
                        billingType: this.addFormState.billingType,
                        componentTagId: this.addFormState.componentTagId ?? null,
                        componentTagOptions: this.addFormState.componentTagOptions ?? [],
                        componentTagsLoaded: !!this.addFormState.componentTagsLoaded,
                        returnable: this.addFormState.returnable
                            ?? this._resolveReturnableForProduct2(payload.product2Id)
                    };
                }
            }
            payload = {
                ...payload,
                partExceptionDecision: this.addFormState.partExceptionDecision ?? null,
                partExceptionResponse: this.addFormState.partExceptionResponse ?? '',
                partExceptionReason: this.addFormState.partExceptionReason ?? '',
                partExceptionProductKey: this.addFormState.partExceptionProductKey ?? null,
                partExceptionAlreadyApproved: !!this.addFormState.partExceptionAlreadyApproved,
                partExceptionSubmit: !!this.addFormState.partExceptionSubmit
            };
        }
        const errMsg = this._validateForSchema(schema, payload);
        if (errMsg) {
            this.addErrors = { ...this.addErrors, [tab]: errMsg };
            return;
        }
        if (schema === 'parts' && this._isTruthyFlag(payload.returnable)) {
            await this._showReturnablePartAlert();
        }
        if (schema === 'time') {
            const skillOk = await this._checkTimeWorkTypeSkills({
                workTypeId: payload.workTypeId || this._headerWorkTypeId(),
                assignedResourceId: payload.assignedResourceId,
                isAddForm: true,
                showToast: true
            });
            if (!skillOk) return;
        }

        _tempIdSeq += 1;
        const resolvedSchema = schema === 'time'
            ? (LINE_TYPE_TO_SCHEMA[payload.lineType] ?? null)
            : schema;
        const resolvedLineType = schema === 'time' ? payload.lineType : tab;
        if (schema === 'time' && !resolvedSchema) {
            this.addErrors = { ...this.addErrors, [tab]: 'Line Type is required.' };
            return;
        }
        const baseAdd = {
            _tempId: `_new_${_tempIdSeq}`,
            _lineType: resolvedLineType,
            _schema: resolvedSchema
        };
        let newAdd;

        if (schema === 'parts_consumed') {
            newAdd = {
                ...baseAdd,
                _entity: 'ProductConsumed',
                assignedResourceId: payload.assignedResourceId,
                productItemId: payload.productItemId,
                product2Id: payload.product2Id,
                returnable: payload.returnable,
                quantityConsumed: Number(payload.quantityConsumed),
                description: payload.description ?? '',
                partsSource: payload.partsSource ?? '',
                workOrderLineItemId: null
            };
        } else if (schema === 'parts') {
            const isTrunk = normalizePartsSource(payload.partsSource) === PARTS_SOURCE_TRUNK;
            newAdd = {
                ...baseAdd,
                _entity: 'WorkOrderLineItem',
                _lineType: 'Parts',
                assignedResourceId: payload.assignedResourceId,
                assignedResourceName: this._assignedResourceNameForId(payload.assignedResourceId),
                partsSource: normalizePartsSource(payload.partsSource) ?? PARTS_SOURCE_TRUNK,
                productItemId: isTrunk ? (payload.productItemId ?? null) : null,
                product2Id: isTrunk ? null : (payload.product2Id ?? null),
                productCode: payload.productCode ?? '',
                partDescription: payload.partDescription ?? '',
                quantity: Number(payload.quantity),
                description: payload.description ?? '',
                usagesException: payload.partExceptionSubmit ? true : !!payload.usagesException,
                partExceptionDecision: payload.partExceptionDecision ?? null,
                partExceptionResponse: payload.partExceptionResponse ?? '',
                partExceptionReason: payload.partExceptionReason ?? '',
                partExceptionProductKey: payload.partExceptionProductKey ?? null,
                partExceptionAlreadyApproved: !!payload.partExceptionAlreadyApproved,
                partExceptionSubmit: !!payload.partExceptionSubmit,
                allowedUnit: payload.allowedUnit ?? null,
                billingType: payload.billingType || 'Billable',
                componentTagId: payload.componentTagId ?? null,
                componentTagOptions: payload.componentTagOptions ?? [],
                componentTagsLoaded: !!payload.componentTagsLoaded,
                returnable: payload.returnable ?? null,
                removedPartId: payload.removedPartId ?? null
            };
        } else if (schema === 'required_product') {
            newAdd = {
                ...baseAdd,
                _entity: 'ProductRequired',
                product2Id: payload.product2Id,
                quantityRequired: Number(payload.quantityRequired),
                returnable: payload.returnable ?? ''
            };
        } else if (schema === 'expense') {
            const next = this._applyExpenseAmountToState({
                ...payload,
                transactionDate: payload.transactionDate || this._todayDateString()
            });
            newAdd = {
                ...baseAdd,
                _entity: 'Expense',
                expenseType: next.expenseType,
                description: next.description ?? '',
                transactionDate: next.transactionDate || this._todayDateString(),
                quantity: Number(next.quantity),
                unitPrice: Number(next.unitPrice) || 0,
                totalPrice: this._computeExpenseAmount(next),
                overrideCode: next.overrideCode || '',
                overrideBillableAmount: this._isTruthyFlag(next.overrideBillableAmount),
                billableAmount: this._expenseBillableSaveValues(next).billableAmount
            };
        } else if (resolvedSchema === 'travel') {
            newAdd = {
                ...baseAdd,
                _entity: 'WorkOrderLineItem',
                assignedResourceId: payload.assignedResourceId,
                assignedResourceName: this._assignedResourceNameForId(payload.assignedResourceId),
                workTypeId: payload.workTypeId || this._headerWorkTypeId() || null,
                startDate: payload.startDate || null,
                endDate: payload.endDate || null,
                rate: payload.rate || null,
                travelType: payload.travelType || null
            };
        } else if (resolvedSchema === 'labor') {
            newAdd = {
                ...baseAdd,
                _entity: 'WorkOrderLineItem',
                assignedResourceId: payload.assignedResourceId,
                assignedResourceName: this._assignedResourceNameForId(payload.assignedResourceId),
                workTypeId: payload.workTypeId || this._headerWorkTypeId() || null,
                startDate: payload.startDate || null,
                endDate: payload.endDate || null,
                rate: payload.rate || null,
                travelType: null,
                listPrice: payload.listPrice ?? null,
                unitPrice: payload.unitPrice ?? null,
                quantity: payload.quantity ?? null,
                totalPrice: payload.totalPrice ?? null
            };
        } else if (schema === 'calibration') {
            newAdd = {
                ...baseAdd,
                _entity: 'WorkOrderLineItem',
                assignedResourceId: payload.assignedResourceId,
                assignedResourceName: this._assignedResourceNameForId(payload.assignedResourceId),
                assetId: payload.assetId
            };
        }

        this._pendingAdds = [...this._pendingAdds, newAdd];
        this._closeAddForm(tab);
    }

    /**
     * @description Handle Add Cancel.
     */
    handleAddCancel(e) {
        this._closeAddForm(e.currentTarget.dataset.tab);
    }

    /**
     * @description Internal helper: Close Add Form.
     */
    _closeAddForm(tab) {
        const key = tab || this.activeTab;
        this.showAddForm = EMPTY_ADD_FORM_VISIBILITY();
        this.addFormState = this._emptyAddFormState();
        if (key) {
            const errs = { ...this.addErrors };
            delete errs[key];
            this.addErrors = errs;
        } else {
            this.addErrors = {};
        }
    }

    /**
     * @description Handle Save All.
     */
    async handleSaveAll() {
        if (this._saving) return;
        const confirmed = await LightningConfirm.open({
            message: 'Save all changes to Salesforce?',
            variant: 'headerless',
            label: 'Confirm Save'
        });
        if (!confirmed) return;

        let hasValidationError = false;
        for (const [id, edit] of Object.entries(this._pendingEdits)) {
            const err = this._validateForSchema(edit._schema ?? 'generic', edit);
            if (err) {
                this.editErrors = { ...this.editErrors, [id]: err };
                hasValidationError = true;
            }
        }
        for (const a of this._pendingAdds) {
            const err = this._validateForSchema(a._schema ?? 'generic', a);
            if (err) {
                this.addErrors = { ...this.addErrors, [a._lineType]: err };
                hasValidationError = true;
            }
        }
        const skillCheckOk = await this._assertTimeSkillChecksForSave();
        if (!skillCheckOk) {
            hasValidationError = true;
        }
        if (hasValidationError) {
            this._toast('Validation Error', 'Fix highlighted errors before saving.', 'error');
            return;
        }
        if (this._hasReturnablePartChange()) {
            await this._showReturnablePartAlert();
        }

        this._saving = true;
        const pendingDeletes = { ...this._pendingDeletes };
        const pendingEdits = { ...this._pendingEdits };
        const pendingAdds = [...this._pendingAdds];
        const pendingCycleCount = this._pendingCycleCount;
        const pendingCycleCountDate = this._pendingCycleCountDate;
        this._pendingDeletes = {};
        this._pendingEdits = {};
        this._pendingAdds = [];
        this._pendingCycleCount = undefined;
        this._pendingCycleCountDate = undefined;

        const failedDeletes = {};
        const failedEdits = {};
        const failedAdds = [];
        let failedWorkOrderHeader = false;
        const okIds = [];

        if (pendingCycleCount !== undefined || pendingCycleCountDate !== undefined) {
            try {
                const fields = { Id: this.recordId };
                if (pendingCycleCount !== undefined) {
                    fields[WO_CYCLE_COUNT.fieldApiName] = pendingCycleCount ?? '';
                }
                if (pendingCycleCountDate !== undefined) {
                    fields[WO_CYCLE_COUNT_DATE.fieldApiName] = pendingCycleCountDate || null;
                }
                await updateRecord({ fields });
                okIds.push(this.recordId);
                this._workOrder = {
                    ...this._workOrder,
                    ...(pendingCycleCount !== undefined
                        ? { CycleCount__c: { value: pendingCycleCount ?? '' } }
                        : {}),
                    ...(pendingCycleCountDate !== undefined
                        ? { CycleCountDate__c: { value: pendingCycleCountDate || null } }
                        : {})
                };
            } catch (err) {
                failedWorkOrderHeader = true;
                if (pendingCycleCount !== undefined) this._pendingCycleCount = pendingCycleCount;
                if (pendingCycleCountDate !== undefined) this._pendingCycleCountDate = pendingCycleCountDate;
                this.editErrors = {
                    ...this.editErrors,
                    _workOrderHeader: this._errorMessage(err)
                };
            }
        }

        for (const id of Object.keys(pendingDeletes)) {
            try {
                await deleteRecord(id);
                okIds.push(id);
                if (this._serverExpenses.some(e => e.Id === id)) this._applyExpenseDelete(id);
                else if (this._serverPartsConsumed.some(p => p.Id === id)) this._applyPartsConsumedDelete(id);
                else if (this._serverProductsRequired.some(p => p.Id === id)) this._applyProductRequiredDelete(id);
            } catch (err) {
                failedDeletes[id] = true;
            }
        }

        for (const [id, edit] of Object.entries(pendingEdits)) {
            try {
                if (edit._schema === 'parts_consumed') {
                    await this._savePartsConsumedEdit(id, edit);
                } else if (edit._schema === 'expense') {
                    // Field Service mobile rejects new Expense custom fields on uiRecordApi drafts.
                    await saveExpense({ fields: this._buildUpdateFields(id, edit) });
                } else {
                    const fields = this._buildUpdateFields(id, edit);
                    await updateRecord({ fields });
                }
                okIds.push(id);
                if (edit._schema === 'parts_consumed' && edit.workOrderLineItemId) {
                    okIds.push(edit.workOrderLineItemId);
                }
                this._applyLocalUpdate(id, edit);
            } catch (err) {
                failedEdits[id] = edit;
                this.editErrors = { ...this.editErrors, [id]: this._errorMessage(err) };
            }
        }

        for (const a of pendingAdds) {
            try {
                if (a._schema === 'parts_consumed') {
                    const { pcId, woliId } = await this._savePartsConsumedAdd(a);
                    okIds.push(pcId, woliId);
                    this._applyLocalCreate(pcId, { ...a, workOrderLineItemId: woliId });
                } else if (a._schema === 'expense') {
                    const { fields } = this._buildCreateFields(a);
                    const expenseId = await saveExpense({ fields });
                    if (expenseId) {
                        okIds.push(expenseId);
                        this._applyLocalCreate(expenseId, a);
                    }
                } else {
                    const { apiName, fields } = this._buildCreateFields(a);
                    const result = await createRecord({ apiName, fields });
                    if (result?.id) {
                        okIds.push(result.id);
                        this._applyLocalCreate(result.id, a);
                    }
                }
            } catch (err) {
                failedAdds.push(a);
                this.editErrors = { ...this.editErrors, [a._tempId]: this._errorMessage(err) };
            }
        }

        try {
            notifyRecordUpdateAvailable([{ recordId: this.recordId }, ...okIds.map(id => ({ recordId: id }))]);
        } catch (e) { /* swallow */ }
        try { await refreshGraphQL(this.graphqlResult); } catch (e) { /* swallow */ }
        try { await refreshGraphQL(this.expensesGraphqlResult); } catch (e) { /* swallow */ }
        try { await this._refreshExpenseBillableFields(); } catch (e) { /* swallow */ }

        this._pendingDeletes = failedDeletes;
        this._pendingEdits = failedEdits;
        this._pendingAdds = failedAdds;
        this.editStateMap = {};
        this.showAddForm = EMPTY_ADD_FORM_VISIBILITY();
        this.addFormState = this._emptyAddFormState();
        this._saving = false;

        const anyFailed = (failedWorkOrderHeader ? 1 : 0) +
            Object.keys(failedDeletes).length +
            Object.keys(failedEdits).length +
            failedAdds.length;
        if (anyFailed === 0) {
            this._toast('Saved', `${okIds.length} change(s) saved.`, 'success');
        } else {
            const detail = this._firstSaveErrorMessage(failedEdits, failedAdds);
            this._toast('Partial Save', detail ? `${anyFailed} change(s) failed: ${detail}` : `${anyFailed} change(s) failed.`, 'warning');
        }
    }

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
            label: 'Confirm Discard'
        });
        if (!confirmed) return;
        this._resetDraft();
    }

    /**
     * @description Internal helper: Build Lines For.
     */
    _buildLinesFor(def) {
        if (def.schema === 'parts_consumed') return this._filterLinesBySearch(this._buildPartsLines(def), def.key);
        if (def.schema === 'required_product') return this._filterLinesBySearch(this._buildRequiredLines(def), def.key);
        if (def.schema === 'expense') return this._filterLinesBySearch(this._buildExpenseLines(def), def.key);
        if (def.schema === 'time') return this._filterLinesBySearch(this._buildTimeLines(def), def.key);

        const matches = l => l.LineType__c?.value === def.type;
        const buildExisting = this._modelBuilderForSchema(def.schema);
        const buildAdd = this._addModelBuilderForSchema(def.schema);

        const existing = this._serverLines
            .filter(l => !this._pendingDeletes[l.Id])
            .filter(matches)
            .map(l => buildExisting.call(this, l, this._pendingEdits[l.Id], this.editStateMap[l.Id] ?? {}));

        const adds = this._pendingAdds
            .filter(a => a._schema === def.schema)
            .map(a => buildAdd.call(this, a, this.editStateMap[a._tempId] ?? {}));

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
     * @description Internal helper: Build Time Lines.
     */
    _buildTimeLines(def) {
        const existing = this._serverLines
            .filter(l => !this._pendingDeletes[l.Id])
            .filter(l => TIME_LINE_TYPES.has(l.LineType__c?.value))
            .map(l => {
                const edit = this._pendingEdits[l.Id];
                const lineType = edit?.lineType ?? l.LineType__c?.value;
                const schema = LINE_TYPE_TO_SCHEMA[lineType] ?? 'travel';
                return this._modelBuilderForSchema(schema).call(
                    this,
                    l,
                    edit,
                    this.editStateMap[l.Id] ?? {}
                );
            });

        const adds = this._pendingAdds
            .filter(a => a._schema === 'travel' || a._schema === 'labor')
            .map(a => {
                const schema = a._schema === 'labor' || a.lineType === 'Labor' ? 'labor' : 'travel';
                return this._addModelBuilderForSchema(schema).call(
                    this,
                    a,
                    this.editStateMap[a._tempId] ?? {}
                );
            });

        const merged = [...existing, ...adds];
        merged.sort((a, b) => {
            const aMs = a.startDateMs ?? Number.POSITIVE_INFINITY;
            const bMs = b.startDateMs ?? Number.POSITIVE_INFINITY;
            if (aMs !== bMs) return aMs - bMs;
            return (a.lineNumber || '').localeCompare(b.lineNumber || '');
        });
        return merged;
    }

    /**
     * @description Internal helper: Build Parts Lines.
     */
    _buildPartsLines(def) {
        const buildExisting = (p, edit, state) => this._buildPartsLineModel(p, edit, state, false);
        const existing = this._serverPartsConsumed
            .filter(p => !this._pendingDeletes[p.Id])
            .map(p => buildExisting(p, this._pendingEdits[p.Id], this.editStateMap[p.Id] ?? {}));
        const adds = this._pendingAdds
            .filter(a => a._schema === def.schema)
            .map(a => this._buildPartsAddModel(a, this.editStateMap[a._tempId] ?? {}));
        return [...existing, ...adds];
    }

    /**
     * @description Internal helper: Build Required Lines.
     */
    _buildRequiredLines(def) {
        const existing = this._serverProductsRequired
            .map(p => this._buildRequiredLineModel(p));
        return this._filterLinesBySearch(existing, def.key);
    }

    /**
     * @description Internal helper: Build Expense Lines.
     */
    _buildExpenseLines(def) {
        const existing = this._serverExpenses
            .filter(e => !this._pendingDeletes[e.Id] && !this._pendingDeletes[this._idKey(e.Id)])
            .map(e => this._buildExpenseLineModel(e, this._pendingEdits[e.Id], this.editStateMap[e.Id] ?? {}));
        const adds = this._pendingAdds
            .filter(a => a._schema === def.schema)
            .map(a => this._buildExpenseAddModel(a, this.editStateMap[a._tempId] ?? {}));
        return [...existing, ...adds];
    }

    /**
     * @description Internal helper: Filter Lines By Search.
     */
    _filterLinesBySearch(lines, tabKey) {
        const term = (this.tabSearchTerms[tabKey] ?? '').trim().toLowerCase();
        if (!term) return lines;
        return lines.filter(line => this._lineMatchesSearch(line, term));
    }

    /**
     * @description Internal helper: Line Matches Search.
     */
    _lineMatchesSearch(line, term) {
        const haystack = [
            line.title, line.metaLine, line.lineNumber, line.description,
            line.expenseType, line.partsSource, line.returnable, line.usagesException,
            line.assignedResourceName, line.productName, line.repairCodeProductCode,
            line.returnableLabel, line.editReturnableLabel,
            line.assetSerialNumber, line.startDate, line.endDate, line.totalPrice,
            line.lineType, line.rate, line.travelType
        ].filter(v => v != null && v !== '').join(' ').toLowerCase();
        return haystack.includes(term);
    }

    /**
     * @description Internal helper: Model Builder For Schema.
     */
    _modelBuilderForSchema(schema) {
        if (schema === 'travel') return this._buildTravelLineModel;
        if (schema === 'labor') return this._buildLaborLineModel;
        if (schema === 'calibration') return this._buildCalibrationLineModel;
        if (schema === 'parts') return this._buildPartsWoliLineModel;
        return this._buildTravelLineModel;
    }

    /**
     * @description Internal helper: Add Model Builder For Schema.
     */
    _addModelBuilderForSchema(schema) {
        if (schema === 'travel') return this._buildTravelAddModel;
        if (schema === 'labor') return this._buildLaborAddModel;
        if (schema === 'calibration') return this._buildCalibrationAddModel;
        if (schema === 'parts') return this._buildPartsWoliAddModel;
        return this._buildTravelAddModel;
    }

    /**
     * @description Internal helper: Build Parts Woli Line Model.
     */
    _buildPartsWoliLineModel(l, edit, state) {
        const assignedResId = edit?.assignedResourceId
            ?? this._resolveAssignedResourceId(l.AssignedResource__c?.value);
        const assignedResName = this._assignedResourceNameForId(assignedResId)
            || l.AssignedResource__r?.Name?.value
            || '';
        const partsSource = normalizePartsSource(
            edit?.partsSource ?? l.PartsSource__c?.value
        ) ?? PARTS_SOURCE_TRUNK;
        const isTrunkStock = partsSource === PARTS_SOURCE_TRUNK;
        const isCustomerStock = partsSource === PARTS_SOURCE_CUSTOMER;
        const productItemId = edit?.productItemId ?? l.ProductItem__c?.value ?? null;
        const product2Id = edit?.product2Id ?? l.Product__c?.value ?? null;
        const linkedProduct2Id = product2Id
            || (productItemId ? this._product2IdByProductItemId[productItemId] : null);
        const productCode = (edit?.productCode
            ?? (linkedProduct2Id ? (this._productCodeByProduct2Id[linkedProduct2Id] ?? '') : ''))
            || '';
        const partDescription = (edit?.partDescription
            ?? l.PartDescription__c?.value
            ?? (linkedProduct2Id ? (this._partDescriptionByProduct2Id[linkedProduct2Id] ?? '') : ''))
            || '';
        const productItemName = this._productItemNameByProductItemId[productItemId] ?? '';
        const productName = this._productNameByProduct2Id[product2Id]
            ?? productItemName
            ?? productCode
            ?? '';
        const quantity = edit?.quantity ?? l.UnitQty__c?.value ?? 0;
        const description = edit?.description ?? l.Description?.value ?? '';
        const allowedUnit = edit?.allowedUnit ?? l.AllowedUnit__c?.value ?? false;
        const returnable = edit?.returnable
            ?? l.Returnable__c?.value
            ?? (isCustomerStock
                ? this._resolveReturnableForProduct2(product2Id)
                : this._resolveReturnableForProductItem(productItemId));
        const componentTagView = this._componentTagView({
            allowedUnit,
            componentTagId: edit && 'componentTagId' in edit
                ? edit.componentTagId
                : (l.ComponentTag__c?.value ?? null),
            componentTagOptions: edit?.componentTagOptions,
            componentTagsLoaded: edit?.componentTagsLoaded,
            savedComponentTagId: l.ComponentTag__c?.value ?? null,
            savedComponentTagName: l.ComponentTag__r?.Name?.value ?? ''
        });
        const returnableLabel = this._fmtReturnable(returnable);
        const usagesException = edit?.usagesException ?? l.UsagesException__c?.value ?? false;
        const removedPartId = edit?.removedPartId ?? l.RemovedPart__c?.value ?? null;
        const billingType = edit?.billingType ?? l.BillingType__c?.value ?? '';
        const billingTypeLabel = this._fmtBillingType(billingType);
        return {
            Id: l.Id,
            schema: 'parts',
            isPartsSchema: true,
            isPartsConsumedSchema: false,
            isTravelSchema: false,
            isLaborSchema: false,
            isCalibrationSchema: false,
            isRequiredProductSchema: false,
            isExpenseSchema: false,
            isTrunkStock,
            isCustomerStock,
            title: productName || 'Part',
            metaLine: this._fmtPartsWoliMeta(quantity, description, usagesException, returnableLabel, billingTypeLabel),
            productName,
            productItemId,
            product2Id,
            productCode,
            partDescription,
            partsSource,
            quantity,
            description,
            allowedUnit,
            returnable,
            returnableLabel,
            usagesException,
            billingType,
            billingTypeLabel,
            removedPartId,
            removedPartOptions: this._removedPartOptions(linkedProduct2Id, productItemName || productName),
            removedPartDisabled: !linkedProduct2Id,
            isRemovedPartRequired: this._isRemovedPartRequired(returnable),
            assignedResourceId: assignedResId,
            assignedResourceName: assignedResName,
            productItemFilter: this._productItemFilterForResource(
                state.assignedResourceId ?? edit?.assignedResourceId ?? assignedResId
            ),
            productItemScanDisabled: !(state.assignedResourceId ?? edit?.assignedResourceId ?? assignedResId),
            isEditing: state.isEditing ?? false,
            editAssignedResId: state.assignedResourceId ?? edit?.assignedResourceId ?? assignedResId,
            editPartsSource: state.partsSource ?? edit?.partsSource ?? partsSource,
            editProductItemId: state.productItemId ?? edit?.productItemId ?? productItemId,
            editProduct2Id: state.product2Id ?? edit?.product2Id ?? product2Id,
            editProductCode: state.productCode ?? edit?.productCode ?? productCode,
            editPartDescription: state.partDescription ?? edit?.partDescription ?? partDescription,
            editQuantity: state.quantity ?? edit?.quantity ?? quantity,
            editDescription: state.description ?? edit?.description ?? description,
            editReturnableLabel: returnableLabel,
            editAllowedUnitLabel: this._fmtReturnable(allowedUnit),
            editBillingTypeLabel: billingTypeLabel,
            ...componentTagView,
            editRemovedPartId: state.removedPartId ?? edit?.removedPartId ?? removedPartId,
            editUsagesException: state.usagesException ?? edit?.usagesException ?? usagesException,
            ...this._partExceptionView(state, edit, allowedUnit),
            editError: this.editErrors[l.Id] ?? '',
            isDirty: !!edit,
            isNew: false
        };
    }

    /**
     * @description Internal helper: Build Parts Woli Add Model.
     */
    _buildPartsWoliAddModel(a, state) {
        const assignedResId = state.assignedResourceId ?? a.assignedResourceId;
        const partsSource = normalizePartsSource(
            state.partsSource ?? a.partsSource
        ) ?? PARTS_SOURCE_TRUNK;
        const isTrunkStock = partsSource === PARTS_SOURCE_TRUNK;
        const isCustomerStock = partsSource === PARTS_SOURCE_CUSTOMER;
        const productItemId = state.productItemId ?? a.productItemId;
        const product2Id = state.product2Id ?? a.product2Id;
        const linkedProduct2Id = product2Id
            || (productItemId ? this._product2IdByProductItemId[productItemId] : null);
        const productCode = (state.productCode
            ?? a.productCode
            ?? (linkedProduct2Id ? (this._productCodeByProduct2Id[linkedProduct2Id] ?? '') : ''))
            || '';
        const partDescription = (state.partDescription
            ?? a.partDescription
            ?? (linkedProduct2Id ? (this._partDescriptionByProduct2Id[linkedProduct2Id] ?? '') : ''))
            || '';
        const quantity = state.quantity ?? a.quantity;
        const description = state.description ?? a.description ?? '';
        const usagesException = state.usagesException ?? a.usagesException ?? false;
        const allowedUnit = state.allowedUnit ?? a.allowedUnit ?? null;
        const returnable = state.returnable
            ?? a.returnable
            ?? (isCustomerStock
                ? this._resolveReturnableForProduct2(product2Id)
                : this._resolveReturnableForProductItem(productItemId));
        const componentTagView = this._componentTagView({
            allowedUnit,
            componentTagId: a.componentTagId ?? null,
            componentTagOptions: a.componentTagOptions,
            componentTagsLoaded: a.componentTagsLoaded
        });
        const returnableLabel = this._fmtReturnable(returnable);
        const removedPartId = state.removedPartId ?? a.removedPartId ?? null;
        const billingType = state.billingType ?? a.billingType ?? '';
        const billingTypeLabel = this._fmtBillingType(billingType);
        const productItemName = this._productItemNameByProductItemId[productItemId] ?? '';
        const productName = this._productNameByProduct2Id[product2Id]
            ?? productItemName
            ?? productCode
            ?? '';
        return {
            Id: a._tempId,
            schema: 'parts',
            isPartsSchema: true,
            isPartsConsumedSchema: false,
            isTravelSchema: false,
            isLaborSchema: false,
            isCalibrationSchema: false,
            isRequiredProductSchema: false,
            isExpenseSchema: false,
            isTrunkStock,
            isCustomerStock,
            title: productName || 'Part',
            metaLine: this._fmtPartsWoliMeta(quantity, description, usagesException, returnableLabel, billingTypeLabel),
            productName,
            productItemId,
            product2Id,
            productCode,
            partDescription,
            partsSource,
            quantity,
            description,
            allowedUnit,
            returnable,
            returnableLabel,
            usagesException,
            billingType,
            billingTypeLabel,
            removedPartId,
            removedPartOptions: this._removedPartOptions(linkedProduct2Id, productItemName || productName),
            removedPartDisabled: !linkedProduct2Id,
            isRemovedPartRequired: this._isRemovedPartRequired(returnable),
            assignedResourceId: assignedResId,
            assignedResourceName: this._assignedResourceNameForId(assignedResId),
            productItemFilter: this._productItemFilterForResource(assignedResId),
            productItemScanDisabled: !assignedResId,
            isEditing: state.isEditing ?? true,
            editAssignedResId: assignedResId,
            editPartsSource: partsSource,
            editProductItemId: productItemId,
            editProduct2Id: product2Id,
            editProductCode: productCode,
            editPartDescription: partDescription,
            editQuantity: quantity,
            editDescription: description,
            editReturnableLabel: returnableLabel,
            editAllowedUnitLabel: this._fmtReturnable(allowedUnit),
            editBillingTypeLabel: billingTypeLabel,
            ...componentTagView,
            editRemovedPartId: removedPartId,
            editUsagesException: usagesException,
            ...this._partExceptionView(state, a, allowedUnit),
            editError: this.addErrors.Parts ?? this.addErrors[a._lineType] ?? '',
            isDirty: true,
            isNew: true
        };
    }

    /**
     * @description Internal helper: Build Parts Line Model.
     */
    _buildPartsLineModel(p, edit, state) {
        const productItemId = edit?.productItemId ?? p.ProductItemId?.value ?? null;
        const product2Id = edit?.product2Id ?? p.Product2Id?.value ?? null;
        const qty = edit?.quantityConsumed ?? p.QuantityConsumed?.value ?? 0;
        const desc = edit?.description ?? p.Description?.value ?? '';
        const partsSource = edit?.partsSource ?? this._partsSourceForPart(p);
        const workOrderLineItemId = edit?.workOrderLineItemId ?? p.WorkOrderLineItemId?.value ?? null;
        const productName = p.ProductItem?.ProductName?.value
            ?? p.Product2?.Name?.value
            ?? this._productItemNameByProductItemId[productItemId]
            ?? '';
        const resourceId = edit?.assignedResourceId ?? p.ServiceResource__c?.value ?? null;
        const resourceName = this._assignedResourceNameForId(resourceId);
        const returnable = edit?.returnable ?? p.Returnable__c?.value ?? p.Product2?.IsReturnable__c?.value ?? null;
        const returnableLabel = this._fmtReturnable(returnable);
        return {
            Id: p.Id,
            schema: 'parts_consumed',
            isPartsConsumedSchema: true,
            isTravelSchema: false,
            isLaborSchema: false,
            isCalibrationSchema: false,
            isRequiredProductSchema: false,
            isExpenseSchema: false,
            title: productName || 'Part',
            metaLine: this._fmtPartsMeta(qty, desc, returnableLabel, partsSource),
            productName,
            quantityConsumed: qty,
            description: desc,
            partsSource,
            workOrderLineItemId,
            assignedResourceId: resourceId,
            assignedResourceName: resourceName,
            returnable,
            returnableLabel,
            productItemId,
            product2Id,
            productItemFilter: this._productItemFilterForResource(state.assignedResourceId ?? edit?.assignedResourceId ?? resourceId),
            isEditing: state.isEditing ?? false,
            editAssignedResId: state.assignedResourceId ?? edit?.assignedResourceId ?? resourceId,
            editProductItemId: state.productItemId ?? edit?.productItemId ?? productItemId,
            editQuantityConsumed: state.quantityConsumed ?? edit?.quantityConsumed ?? qty,
            editDescription: state.description ?? edit?.description ?? desc,
            editPartsSource: state.partsSource ?? edit?.partsSource ?? partsSource,
            editReturnableLabel: returnableLabel,
            editError: this.editErrors[p.Id] ?? '',
            isDirty: !!edit,
            isNew: false
        };
    }

    /**
     * @description Internal helper: Build Parts Add Model.
     */
    _buildPartsAddModel(a, state) {
        const productItemId = state.productItemId ?? a.productItemId;
        const product2Id = state.product2Id ?? a.product2Id;
        const qty = state.quantityConsumed ?? a.quantityConsumed;
        const desc = state.description ?? a.description;
        const partsSource = state.partsSource ?? a.partsSource;
        const resourceId = state.assignedResourceId ?? a.assignedResourceId;
        const returnable = a.returnable ?? this._resolveReturnableForProductItem(productItemId);
        const returnableLabel = this._fmtReturnable(returnable);
        const productName = this._productItemNameByProductItemId[productItemId] ?? '';
        return {
            Id: a._tempId,
            schema: 'parts_consumed',
            isPartsConsumedSchema: true,
            isTravelSchema: false,
            isLaborSchema: false,
            isCalibrationSchema: false,
            isRequiredProductSchema: false,
            isExpenseSchema: false,
            title: productName || 'Part',
            metaLine: this._fmtPartsMeta(qty, desc, returnableLabel, partsSource),
            productName,
            quantityConsumed: qty,
            description: desc,
            partsSource,
            returnable,
            returnableLabel,
            productItemId,
            product2Id,
            productItemFilter: this._productItemFilterForResource(resourceId),
            isEditing: state.isEditing ?? false,
            editAssignedResId: resourceId,
            editProductItemId: productItemId,
            editQuantityConsumed: qty,
            editDescription: desc,
            editPartsSource: partsSource,
            editReturnableLabel: returnableLabel,
            editError: this.editErrors[a._tempId] ?? '',
            isDirty: false,
            isNew: true
        };
    }

    /**
     * @description Internal helper: Build Required Line Model.
     */
    _buildRequiredLineModel(p) {
        const qty = p.QuantityRequired?.value ?? 0;
        const productName = p.Product2?.Name?.value ?? '';
        const returnable = p.Returnable__c?.value ?? '';
        return {
            Id: p.Id,
            schema: 'required_product',
            isPartsConsumedSchema: false,
            isTravelSchema: false,
            isLaborSchema: false,
            isCalibrationSchema: false,
            isRequiredProductSchema: true,
            isExpenseSchema: false,
            title: productName || 'Product',
            metaLine: this._fmtRequiredMeta(qty, returnable),
            productName,
            quantityRequired: qty,
            returnable,
            isEditing: false,
            isDirty: false,
            isNew: false
        };
    }

    /**
     * @description Internal helper: Build Required Add Model.
     */
    _buildRequiredAddModel(a, state) {
        const product2Id = state.product2Id ?? a.product2Id;
        const qty = state.quantityRequired ?? a.quantityRequired;
        return {
            Id: a._tempId,
            schema: 'required_product',
            isPartsConsumedSchema: false,
            isTravelSchema: false,
            isLaborSchema: false,
            isCalibrationSchema: false,
            isRequiredProductSchema: true,
            isExpenseSchema: false,
            title: 'New Required Product',
            metaLine: this._fmtRequiredMeta(qty, ''),
            product2Id,
            quantityRequired: qty,
            returnable: '',
            isEditing: state.isEditing ?? false,
            editProduct2Id: product2Id,
            editQuantityRequired: qty,
            editReturnable: '',
            editError: this.editErrors[a._tempId] ?? '',
            isDirty: false,
            isNew: true
        };
    }

    /**
     * @description Internal helper: Build Expense Line Model.
     */
    _buildExpenseLineModel(e, edit, state) {
        const expenseType = edit?.expenseType ?? e.ExpenseType?.value ?? '';
        const description = edit?.description ?? e.Description?.value ?? '';
        const transactionDate = edit?.transactionDate
            ?? e.TransactionDate?.value
            ?? this._todayDateString();
        const quantity = edit?.quantity ?? e.Quantity?.value ?? 0;
        const unitPrice = edit?.unitPrice ?? e.UnitPrice?.value ?? 0;
        const totalPrice = this._fmtMoney(this._computeTotalPrice(unitPrice, quantity));
        const overrideBillableAmount = this._isTruthyFlag(
            edit?.overrideBillableAmount ?? e.OverrideBillableAmount__c?.value
        );
        const computedAmount = this._computeTotalPrice(
            state.unitPrice ?? edit?.unitPrice ?? unitPrice,
            state.quantity ?? edit?.quantity ?? quantity
        );
        const billableAmount = overrideBillableAmount
            ? (edit?.billableAmount ?? e.BillableAmount__c?.value ?? computedAmount)
            : (edit?.billableAmount ?? computedAmount);
        const overrideCode = edit?.overrideCode ?? e.OverrideCode__c?.value ?? '';
        return {
            Id: e.Id,
            schema: 'expense',
            isPartsConsumedSchema: false,
            isTravelSchema: false,
            isLaborSchema: false,
            isCalibrationSchema: false,
            isRequiredProductSchema: false,
            isExpenseSchema: true,
            title: expenseType || 'Unspecified Expense',
            metaLine: this._fmtExpenseMeta(description, quantity, unitPrice, totalPrice),
            expenseType,
            description,
            transactionDate,
            quantity,
            unitPrice,
            totalPrice,
            overrideCode,
            billableAmount,
            isEditing: state.isEditing ?? false,
            editExpenseType: state.expenseType ?? edit?.expenseType ?? expenseType,
            editDescription: state.description ?? edit?.description ?? description,
            editTransactionDate: state.transactionDate ?? edit?.transactionDate ?? transactionDate,
            editQuantity: state.quantity ?? edit?.quantity ?? quantity,
            editUnitPrice: state.unitPrice ?? edit?.unitPrice ?? unitPrice,
            editTotalPrice: this._fmtMoney(computedAmount),
            editOverrideCode: state.overrideCode ?? overrideCode,
            editBillableAmount: state.billableAmount ?? billableAmount,
            editBillableAmountDisplay: this._fmtMoney(state.billableAmount ?? billableAmount),
            editOverrideBillableAmount: this._isTruthyFlag(
                state.overrideBillableAmount ?? overrideBillableAmount
            ),
            isBillableAmountReadOnly: !this._isTruthyFlag(
                state.overrideBillableAmount ?? overrideBillableAmount
            ),
            isOverrideCodeRequired: this._isTruthyFlag(
                state.overrideBillableAmount ?? overrideBillableAmount
            ),
            editError: this.editErrors[e.Id] ?? '',
            isDirty: !!edit,
            isNew: false
        };
    }

    /**
     * @description Internal helper: Build Expense Add Model.
     */
    _buildExpenseAddModel(a, state) {
        const expenseType = state.expenseType ?? a.expenseType;
        const description = state.description ?? a.description;
        const transactionDate = state.transactionDate ?? a.transactionDate ?? this._todayDateString();
        const quantity = state.quantity ?? a.quantity;
        const unitPrice = state.unitPrice ?? a.unitPrice;
        const totalPrice = this._fmtMoney(this._computeTotalPrice(unitPrice, quantity));
        const overrideBillableAmount = this._isTruthyFlag(
            state.overrideBillableAmount ?? a.overrideBillableAmount
        );
        const computedAmount = this._computeTotalPrice(unitPrice, quantity);
        const billableAmount = overrideBillableAmount
            ? (state.billableAmount ?? a.billableAmount ?? computedAmount)
            : (state.billableAmount ?? a.billableAmount ?? computedAmount);
        const overrideCode = state.overrideCode ?? a.overrideCode ?? '';
        return {
            Id: a._tempId,
            schema: 'expense',
            isPartsConsumedSchema: false,
            isTravelSchema: false,
            isLaborSchema: false,
            isCalibrationSchema: false,
            isRequiredProductSchema: false,
            isExpenseSchema: true,
            title: expenseType || 'Unspecified Expense',
            metaLine: this._fmtExpenseMeta(description, quantity, unitPrice, totalPrice),
            expenseType,
            description,
            transactionDate,
            quantity,
            unitPrice,
            totalPrice,
            overrideCode,
            billableAmount,
            isEditing: state.isEditing ?? false,
            editExpenseType: expenseType,
            editDescription: description,
            editTransactionDate: transactionDate,
            editQuantity: quantity,
            editUnitPrice: unitPrice,
            editTotalPrice: totalPrice,
            editOverrideCode: overrideCode,
            editBillableAmount: billableAmount,
            editBillableAmountDisplay: this._fmtMoney(billableAmount),
            editOverrideBillableAmount: overrideBillableAmount,
            isBillableAmountReadOnly: !overrideBillableAmount,
            isOverrideCodeRequired: overrideBillableAmount,
            editError: this.editErrors[a._tempId] ?? '',
            isDirty: false,
            isNew: true
        };
    }

    /**
     * @description Internal helper: Build Travel Line Model.
     */
    _buildTravelLineModel(l, edit, state) {
        const assignedResId = edit?.assignedResourceId
            ?? this._resolveAssignedResourceId(l.AssignedResource__c?.value);
        const assignedResName = this._assignedResourceNameForId(assignedResId)
            || l.AssignedResource__r?.Name?.value
            || '';
        const startDate = edit?.startDate ?? l.StartDate?.value ?? '';
        const endDate = edit?.endDate ?? l.EndDate?.value ?? '';
        const lineType = edit?.lineType ?? l.LineType__c?.value ?? 'Travel';
        const rate = edit?.rate ?? l.Rate__c?.value ?? '';
        const travelType = edit?.travelType ?? l.TravelType__c?.value ?? '';
        const workTypeId = edit?.workTypeId ?? l.WorkTypeId?.value ?? null;
        const listPrice = state.listPrice ?? edit?.listPrice ?? l.ListPrice__c?.value ?? null;
        const unitPrice = state.unitPrice ?? edit?.unitPrice ?? l.UnitPrice__c?.value ?? null;
        const quantity = state.quantity ?? edit?.quantity ?? l.UnitQty__c?.value ?? null;
        const totalPrice = state.totalPrice
            ?? edit?.totalPrice
            ?? l.TotalPrice__c?.value
            ?? (quantity != null && unitPrice != null ? Number(quantity) * Number(unitPrice) : null);
        const pricedState = {
            ...state,
            listPrice,
            unitPrice,
            totalPrice,
            quantity
        };
        const base = this._buildTimeLineBase({
            id: l.Id,
            schema: 'travel',
            lineType,
            assignedResId,
            assignedResName,
            workTypeId,
            startDate,
            endDate,
            lineNumber: l.LineItemNumber?.value ?? '',
            isDirty: !!edit,
            state: pricedState,
            isNew: false,
            durationFromServer: l.Duration?.value ?? null,
            rate,
            travelType
        });
        return {
            ...base,
            editListPriceLabel: this._fmtOptionalMoney(listPrice),
            editUnitPriceLabel: this._fmtOptionalMoney(unitPrice),
            editTotalPriceLabel: this._fmtOptionalMoney(totalPrice)
        };
    }

    /**
     * @description Internal helper: Build Travel Add Model.
     */
    _buildTravelAddModel(a, state) {
        const assignedResId = state.assignedResourceId ?? a.assignedResourceId;
        const startDate = state.startDate ?? a.startDate;
        const endDate = state.endDate ?? a.endDate;
        const titleName = a.assignedResourceName || this._assignedResourceNameForId(assignedResId) || 'Resource pending…';
        return this._buildTimeLineBase({
            id: a._tempId,
            schema: 'travel',
            lineType: a._lineType || 'Travel',
            assignedResId,
            assignedResName: titleName,
            workTypeId: state.workTypeId ?? a.workTypeId ?? null,
            startDate,
            endDate,
            lineNumber: '',
            isDirty: false,
            state,
            isNew: true,
            rate: state.rate ?? a.rate ?? '',
            travelType: state.travelType ?? a.travelType ?? ''
        });
    }

    /**
     * @description Internal helper: Build Labor Line Model.
     */
    _buildLaborLineModel(l, edit, state) {
        const assignedResId = edit?.assignedResourceId
            ?? this._resolveAssignedResourceId(l.AssignedResource__c?.value);
        const assignedResName = this._assignedResourceNameForId(assignedResId)
            || l.AssignedResource__r?.Name?.value
            || '';
        const startDate = edit?.startDate ?? l.StartDate?.value ?? '';
        const endDate = edit?.endDate ?? l.EndDate?.value ?? '';
        const lineType = edit?.lineType ?? l.LineType__c?.value ?? 'Labor';
        const rate = edit?.rate ?? l.Rate__c?.value ?? '';
        const workTypeId = edit?.workTypeId ?? l.WorkTypeId?.value ?? null;
        const listPrice = state.listPrice ?? edit?.listPrice ?? l.ListPrice__c?.value ?? null;
        const unitPrice = state.unitPrice ?? edit?.unitPrice ?? l.UnitPrice__c?.value ?? null;
        const quantity = state.quantity ?? edit?.quantity ?? l.UnitQty__c?.value ?? null;
        const totalPrice = state.totalPrice
            ?? edit?.totalPrice
            ?? l.TotalPrice__c?.value
            ?? (quantity != null && unitPrice != null ? Number(quantity) * Number(unitPrice) : null);
        const base = this._buildTimeLineBase({
            id: l.Id,
            schema: 'labor',
            lineType,
            assignedResId,
            assignedResName,
            workTypeId,
            startDate,
            endDate,
            lineNumber: l.LineItemNumber?.value ?? '',
            isDirty: !!edit,
            state,
            isNew: false,
            durationFromServer: l.Duration?.value ?? null,
            rate,
            travelType: ''
        });
        return {
            ...base,
            isLaborSchema: true,
            isLaborLine: true,
            isTravelLine: false,
            editRateOptions: this._rateOptionsForLineType('Labor'),
            editListPriceLabel: this._fmtOptionalMoney(listPrice),
            editUnitPriceLabel: this._fmtOptionalMoney(unitPrice),
            editTotalPriceLabel: this._fmtOptionalMoney(totalPrice),
            metaLine: this._fmtTimeMeta('Labor', startDate, endDate, rate, '')
        };
    }

    /**
     * @description Internal helper: Build Labor Add Model.
     */
    _buildLaborAddModel(a, state) {
        const assignedResId = state.assignedResourceId ?? a.assignedResourceId;
        const startDate = state.startDate ?? a.startDate;
        const endDate = state.endDate ?? a.endDate;
        const titleName = a.assignedResourceName || this._assignedResourceNameForId(assignedResId) || 'Resource pending…';
        const rate = state.rate ?? a.rate ?? '';
        const listPrice = state.listPrice ?? a.listPrice ?? null;
        const unitPrice = state.unitPrice ?? a.unitPrice ?? null;
        const quantity = state.quantity ?? a.quantity ?? null;
        const totalPrice = quantity != null && unitPrice != null
            ? Number(quantity) * Number(unitPrice)
            : null;
        const base = this._buildTimeLineBase({
            id: a._tempId,
            schema: 'labor',
            lineType: a._lineType || a.lineType || 'Labor',
            assignedResId,
            assignedResName: titleName,
            workTypeId: state.workTypeId ?? a.workTypeId ?? null,
            startDate,
            endDate,
            lineNumber: '',
            isDirty: false,
            state,
            isNew: true,
            rate,
            travelType: ''
        });
        return {
            ...base,
            isLaborSchema: true,
            isLaborLine: true,
            isTravelLine: false,
            editRateOptions: this._rateOptionsForLineType('Labor'),
            editListPriceLabel: this._fmtOptionalMoney(listPrice),
            editUnitPriceLabel: this._fmtOptionalMoney(unitPrice),
            editTotalPriceLabel: this._fmtOptionalMoney(totalPrice),
            metaLine: this._fmtTimeMeta('Labor', startDate, endDate, rate, '')
        };
    }

    /**
     * @description Internal helper: Build Calibration Line Model.
     */
    _buildCalibrationLineModel(l, edit, state) {
        const assignedResId = edit?.assignedResourceId ?? l.AssignedResource__c?.value ?? null;
        const assignedResName = l.AssignedResource__r?.Name?.value ?? '';
        const assetId = edit?.assetId ?? l.AssetId?.value ?? null;
        const assetSerial = l.Asset?.SerialNumber?.value ?? '';
        const base = this._buildTimeLineBase({
            id: l.Id,
            schema: 'calibration',
            assignedResId,
            assignedResName,
            startDate: '',
            endDate: '',
            lineNumber: l.LineItemNumber?.value ?? '',
            isDirty: !!edit,
            state,
            isNew: false
        });
        return {
            ...base,
            isCalibrationSchema: true,
            metaLine: this._fmtCalibrationMeta(assetSerial),
            assetId,
            assetSerialNumber: assetSerial,
            editAssetId: state.assetId ?? edit?.assetId ?? assetId
        };
    }

    /**
     * @description Internal helper: Build Calibration Add Model.
     */
    _buildCalibrationAddModel(a, state) {
        const assignedResId = state.assignedResourceId ?? a.assignedResourceId;
        const assetId = state.assetId ?? a.assetId;
        const titleName = a.assignedResourceName || this._assignedResourceNameForId(assignedResId) || 'Resource pending…';
        const base = this._buildTimeLineBase({
            id: a._tempId,
            schema: 'calibration',
            assignedResId,
            assignedResName: titleName,
            startDate: '',
            endDate: '',
            lineNumber: '',
            isDirty: false,
            state,
            isNew: true
        });
        return {
            ...base,
            isCalibrationSchema: true,
            metaLine: this._fmtCalibrationMeta(''),
            assetId,
            editAssetId: assetId
        };
    }

    _buildTimeLineBase({
        id,
        schema,
        lineType = '',
        assignedResId,
        assignedResName,
        workTypeId = null,
        startDate,
        endDate,
        lineNumber,
        isDirty,
        state,
        isNew,
        durationFromServer = null,
        rate = '',
        travelType = ''
    }) {
        const isTravel = schema === 'travel';
        const isLabor = schema === 'labor';
        const isTime = isTravel || isLabor;
        const flags = {
            isPartsConsumedSchema: false,
            isTravelSchema: isTravel,
            isLaborSchema: isLabor,
            isTimeSchema: isTime,
            isCalibrationSchema: schema === 'calibration',
            isRequiredProductSchema: false,
            isExpenseSchema: false
        };
        const editLineType = state.lineType ?? lineType;
        const editRate = state.rate ?? rate ?? '';
        const editTravelType = state.travelType ?? travelType ?? '';
        const effectiveStart = state.startDate ?? startDate ?? '';
        const effectiveEnd = state.endDate ?? endDate ?? '';
        const durationHours = state.durationHours != null && state.durationHours !== ''
            ? Number(state.durationHours)
            : (this._computeDurationHours(effectiveStart, effectiveEnd) ?? durationFromServer);
        const effectiveLineType = editLineType || (isTravel ? 'Travel' : isLabor ? 'Labor' : '');
        const isTravelLine = effectiveLineType === 'Travel';
        const isLaborLine = effectiveLineType === 'Labor';
        const isActualTravel = isTravelLine && editTravelType === TRAVEL_TYPE_ACTUAL;
        const listPrice = state.listPrice ?? null;
        const unitPrice = state.unitPrice ?? null;
        const totalPrice = state.totalPrice ?? null;
        return {
            Id: id,
            lineNumber,
            schema,
            ...flags,
            title: assignedResName || 'Unassigned',
            metaLine: this._fmtTimeMeta(effectiveLineType, startDate, endDate, rate, travelType),
            lineType: effectiveLineType,
            rate,
            travelType,
            workTypeId,
            assignedResourceId: assignedResId,
            assignedResourceName: assignedResName,
            startDate,
            endDate,
            durationHours,
            startDateMs: this._toMs(startDate),
            isEditing: state.isEditing ?? false,
            editLineType: effectiveLineType,
            editRate,
            editTravelType,
            isTravelLine,
            isLaborLine,
            showRateField: isLaborLine || isActualTravel,
            isRateRequired: isActualTravel,
            editWorkTypeId: state.workTypeId ?? workTypeId ?? null,
            editAssignedResId: state.assignedResourceId ?? assignedResId,
            editStartDate: state.startDate ?? startDate ?? '',
            editEndDate: state.endDate ?? endDate ?? '',
            editDurationHours: durationHours ?? '',
            editRateOptions: this._rateOptionsForLineType(effectiveLineType),
            editDurationLabel: this._fmtDurationLabel(durationHours),
            editListPriceLabel: this._fmtMoney(listPrice),
            editUnitPriceLabel: this._fmtMoney(unitPrice),
            editTotalPriceLabel: this._fmtMoney(totalPrice),
            editError: this.editErrors[id] ?? '',
            isDirty,
            isNew
        };
    }

    /**
     * @description Internal helper: Build Update Fields.
     */
    _buildUpdateFields(id, edit) {
        const schema = edit._schema;
        if (schema === 'parts_consumed') {
            return {
                Id: id,
                [PC_QUANTITY.fieldApiName]: Number(edit.quantityConsumed) || 0,
                [PC_DESCRIPTION.fieldApiName]: edit.description ?? '',
                [PC_SERVICE_RESOURCE.fieldApiName]: edit.assignedResourceId,
                ...(edit.returnable != null ? { [PC_RETURNABLE.fieldApiName]: edit.returnable } : {})
            };
        }
        if (schema === 'required_product') {
            return {
                Id: id,
                [PR_PRODUCT.fieldApiName]: edit.product2Id,
                [PR_QUANTITY.fieldApiName]: Number(edit.quantityRequired) || 0
            };
        }
        if (schema === 'expense') {
            const next = this._applyExpenseAmountToState(edit);
            const billable = this._expenseBillableSaveValues({ ...next, ...edit });
            return {
                Id: id,
                [EXPENSE_EXPENSETYPE.fieldApiName]: next.expenseType,
                [EXPENSE_DESCRIPTION.fieldApiName]: next.description ?? '',
                [EXPENSE_QUANTITY.fieldApiName]: Number(next.quantity) || 0,
                [EXPENSE_UNITPRICE.fieldApiName]: Number(next.unitPrice) || 0,
                [EXPENSE_AMOUNT.fieldApiName]: this._computeExpenseAmount(next),
                [EXPENSE_TRANSACTIONDATE.fieldApiName]: next.transactionDate || this._todayDateString(),
                [OVERRIDE_CODE.fieldApiName]: billable.overrideCode || null,
                [EXPENSE_BILLABLE_AMOUNT.fieldApiName]: billable.billableAmount,
                [EXPENSE_OVERRIDE_BILLABLE.fieldApiName]: billable.overrideBillableAmount
            };
        }
        const durationFields = this._buildDurationFields(edit.startDate, edit.endDate, edit.durationHours);
        if (schema === 'travel') {
            const travelPriceFields = this._buildTravelPriceSaveFields(edit);
            return {
                Id: id,
                [WOLI_LINETYPE.fieldApiName]: edit.lineType || 'Travel',
                [WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
                [WOLI_WORKTYPE.fieldApiName]: edit.workTypeId || null,
                [WOLI_STARTDATE.fieldApiName]: edit.startDate || null,
                [WOLI_ENDDATE.fieldApiName]: edit.endDate || null,
                [WOLI_RATE.fieldApiName]: edit.travelType === TRAVEL_TYPE_ACTUAL ? (edit.rate || null) : null,
                [WOLI_TRAVEL_TYPE.fieldApiName]: edit.travelType || null,
                ...durationFields,
                ...travelPriceFields
            };
        }
        if (schema === 'labor') {
            const pricingFields = this._laborPricingFieldsForSave(edit);
            return {
                Id: id,
                [WOLI_LINETYPE.fieldApiName]: edit.lineType || 'Labor',
                [WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
                [WOLI_WORKTYPE.fieldApiName]: edit.workTypeId || null,
                [WOLI_REPAIRCODE.fieldApiName]: null,
                [WOLI_STARTDATE.fieldApiName]: edit.startDate || null,
                [WOLI_ENDDATE.fieldApiName]: edit.endDate || null,
                [WOLI_RATE.fieldApiName]: edit.rate || null,
                [WOLI_TRAVEL_TYPE.fieldApiName]: null,
                ...pricingFields,
                ...durationFields
            };
        }
        if (schema === 'calibration') {
            return {
                Id: id,
                [WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
                [WOLI_ASSETID.fieldApiName]: edit.assetId
            };
        }
        if (schema === 'parts') {
            const partsSource = normalizePartsSource(edit.partsSource) ?? PARTS_SOURCE_TRUNK;
            const isTrunk = partsSource === PARTS_SOURCE_TRUNK;
            return {
                Id: id,
                [WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
                [WOLI_PARTS_SOURCE.fieldApiName]: partsSource,
                [WOLI_PRODUCT_ITEM.fieldApiName]: isTrunk ? (edit.productItemId ?? null) : null,
                [WOLI_PRODUCT.fieldApiName]: isTrunk ? null : (edit.product2Id ?? null),
                [WOLI_PART_DESCRIPTION.fieldApiName]: edit.partDescription ?? '',
                [WOLI_UNIT_QTY.fieldApiName]: Number(edit.quantity) || 0,
                [WOLI_DESCRIPTION.fieldApiName]: edit.description ?? '',
                ...this._partExceptionSaveFields(edit),
                [WOLI_BILLING_TYPE.fieldApiName]: edit.billingType || 'Billable',
                ...(edit.allowedUnit != null
                    ? { [WOLI_ALLOWED_UNIT.fieldApiName]: !!edit.allowedUnit }
                    : {}),
                ...(edit.returnable != null
                    ? { [WOLI_RETURNABLE.fieldApiName]: !!edit.returnable }
                    : {}),
                [WOLI_REMOVED_PART.fieldApiName]: edit.removedPartId ?? null,
                [WOLI_COMPONENT_TAG.fieldApiName]: edit.componentTagId ?? null
            };
        }
        return { Id: id };
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
     * @description RecordTypeId fields for Travel, Labor, Parts, and Calibration WOLI creates.
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
     * @description Internal helper: Build Create Fields.
     */
    _buildCreateFields(a) {
        const schema = a._schema;
        if (schema === 'parts_consumed') {
            return this._buildProductConsumedCreateFields(a);
        }
        if (schema === 'parts') {
            const partsSource = normalizePartsSource(a.partsSource) ?? PARTS_SOURCE_TRUNK;
            const isTrunk = partsSource === PARTS_SOURCE_TRUNK;
            return {
                apiName: WOLI_OBJECT.objectApiName,
                fields: {
                    [WOLI_WORKORDERID.fieldApiName]: this.recordId,
                    [WOLI_LINETYPE.fieldApiName]: 'Parts',
                    ...this._usageConsumptionRecordTypeFields(),
                    [WOLI_ASSIGNED_RES.fieldApiName]: a.assignedResourceId,
                    [WOLI_PARTS_SOURCE.fieldApiName]: partsSource,
                    [WOLI_PRODUCT_ITEM.fieldApiName]: isTrunk ? (a.productItemId ?? null) : null,
                    [WOLI_PRODUCT.fieldApiName]: isTrunk ? null : (a.product2Id ?? null),
                    [WOLI_PART_DESCRIPTION.fieldApiName]: a.partDescription ?? '',
                    [WOLI_UNIT_QTY.fieldApiName]: Number(a.quantity) || 0,
                    [WOLI_DESCRIPTION.fieldApiName]: a.description ?? '',
                    ...this._partExceptionSaveFields(a),
                    [WOLI_BILLING_TYPE.fieldApiName]: a.billingType || 'Billable',
                    ...(a.allowedUnit != null
                        ? { [WOLI_ALLOWED_UNIT.fieldApiName]: !!a.allowedUnit }
                        : {}),
                    ...(a.returnable != null
                        ? { [WOLI_RETURNABLE.fieldApiName]: !!a.returnable }
                        : {}),
                    [WOLI_REMOVED_PART.fieldApiName]: a.removedPartId ?? null,
                    [WOLI_COMPONENT_TAG.fieldApiName]: a.componentTagId ?? null
                }
            };
        }
        if (schema === 'required_product') {
            return {
                apiName: PR_OBJECT.objectApiName,
                fields: {
                    [PR_PARENT.fieldApiName]: this.recordId,
                    [PR_PRODUCT.fieldApiName]: a.product2Id,
                    [PR_QUANTITY.fieldApiName]: Number(a.quantityRequired) || 0
                }
            };
        }
        if (schema === 'expense') {
            const next = this._applyExpenseAmountToState(a);
            const billable = this._expenseBillableSaveValues({ ...next, ...a });
            return {
                apiName: EXPENSE_OBJECT.objectApiName,
                fields: {
                    [EXPENSE_EXPENSETYPE.fieldApiName]: next.expenseType,
                    [EXPENSE_DESCRIPTION.fieldApiName]: next.description ?? '',
                    [EXPENSE_QUANTITY.fieldApiName]: Number(next.quantity) || 0,
                    [EXPENSE_UNITPRICE.fieldApiName]: Number(next.unitPrice) || 0,
                    [EXPENSE_AMOUNT.fieldApiName]: this._computeExpenseAmount(next),
                    [OVERRIDE_CODE.fieldApiName]: billable.overrideCode || null,
                    [EXPENSE_BILLABLE_AMOUNT.fieldApiName]: billable.billableAmount,
                    [EXPENSE_OVERRIDE_BILLABLE.fieldApiName]: billable.overrideBillableAmount,
                    [EXPENSE_WORKORDER.fieldApiName]: this.recordId,
                    [EXPENSE_CURRENCY.fieldApiName]: this._workOrderCurrency(),
                    [EXPENSE_OWNER.fieldApiName]: USER_ID,
                    [EXPENSE_TRANSACTIONDATE.fieldApiName]: next.transactionDate || this._todayDateString()
                }
            };
        }
        const durationFields = this._buildDurationFields(a.startDate, a.endDate, a.durationHours);
        const base = {
            [WOLI_WORKORDERID.fieldApiName]: this.recordId,
            [WOLI_LINETYPE.fieldApiName]: a._lineType,
            [WOLI_ASSIGNED_RES.fieldApiName]: a.assignedResourceId,
            [WOLI_WORKTYPE.fieldApiName]: a.workTypeId || null,
            [WOLI_STARTDATE.fieldApiName]: a.startDate || null,
            [WOLI_ENDDATE.fieldApiName]: a.endDate || null,
            [WOLI_RATE.fieldApiName]: schema === 'travel' && a.travelType === TRAVEL_TYPE_ACTUAL
                ? (a.rate || null)
                : (schema === 'labor' ? (a.rate || null) : null),
            [WOLI_TRAVEL_TYPE.fieldApiName]: schema === 'travel' ? (a.travelType || null) : null,
            ...durationFields
        };
        if (schema === 'travel') {
            return {
                apiName: WOLI_OBJECT.objectApiName,
                fields: {
                    ...base,
                    ...this._usageConsumptionRecordTypeFields(),
                    ...this._buildTravelPriceSaveFields(a)
                }
            };
        }
        if (schema === 'labor') {
            const pricingFields = this._laborPricingFieldsForSave(a);
            return {
                apiName: WOLI_OBJECT.objectApiName,
                fields: {
                    ...base,
                    ...this._usageConsumptionRecordTypeFields(),
                    [WOLI_REPAIRCODE.fieldApiName]: null,
                    ...pricingFields
                }
            };
        }
        if (schema === 'calibration') {
            return {
                apiName: WOLI_OBJECT.objectApiName,
                fields: {
                    [WOLI_WORKORDERID.fieldApiName]: this.recordId,
                    [WOLI_LINETYPE.fieldApiName]: a._lineType,
                    ...this._usageConsumptionRecordTypeFields(),
                    [WOLI_ASSIGNED_RES.fieldApiName]: a.assignedResourceId,
                    [WOLI_ASSETID.fieldApiName]: a.assetId
                }
            };
        }
        return { apiName: WOLI_OBJECT.objectApiName, fields: base };
    }

    /**
     * @description Internal helper: Build Woli Parts Fields.
     */
    _buildWoliPartsFields(partsSource, assignedResourceId) {
        return {
            [WOLI_WORKORDERID.fieldApiName]: this.recordId,
            [WOLI_LINETYPE.fieldApiName]: 'Parts',
            ...this._usageConsumptionRecordTypeFields(),
            [WOLI_PARTS_SOURCE.fieldApiName]: normalizePartsSource(partsSource) ?? null,
            [WOLI_ASSIGNED_RES.fieldApiName]: assignedResourceId
        };
    }

    /**
     * @description Internal helper: Build Product Consumed Create Fields.
     */
    _buildProductConsumedCreateFields(a, workOrderLineItemId = null) {
        return {
            apiName: PC_OBJECT.objectApiName,
            fields: {
                [PC_WORKORDER.fieldApiName]: this.recordId,
                [PC_PRODUCTITEM.fieldApiName]: a.productItemId,
                [PC_QUANTITY.fieldApiName]: Number(a.quantityConsumed) || 0,
                [PC_DESCRIPTION.fieldApiName]: a.description ?? '',
                [PC_SERVICE_RESOURCE.fieldApiName]: a.assignedResourceId,
                ...(workOrderLineItemId ? { [PC_WORKORDER_LINE_ITEM.fieldApiName]: workOrderLineItemId } : {}),
                ...(a.returnable != null ? { [PC_RETURNABLE.fieldApiName]: a.returnable } : {})
            }
        };
    }

    /**
     * @description Internal helper: Save Parts Consumed Add.
     */
    async _savePartsConsumedAdd(a) {
        const woliResult = await createRecord({
            apiName: WOLI_OBJECT.objectApiName,
            fields: this._buildWoliPartsFields(a.partsSource, a.assignedResourceId)
        });
        const woliId = woliResult.id;
        const { apiName, fields } = this._buildProductConsumedCreateFields(a, woliId);
        const pcResult = await createRecord({ apiName, fields });
        this._cachePartsSource(woliId, a.partsSource ?? '');
        return { pcId: pcResult.id, woliId };
    }

    /**
     * @description Internal helper: Save Parts Consumed Edit.
     */
    async _savePartsConsumedEdit(pcId, edit) {
        await updateRecord({ fields: this._buildUpdateFields(pcId, edit) });

        let woliId = edit.workOrderLineItemId ?? null;
        const partsSource = edit.partsSource ?? null;

        if (woliId) {
            await updateRecord({
                fields: {
                    Id: woliId,
                    [WOLI_PARTS_SOURCE.fieldApiName]: partsSource,
                    [WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId
                }
            });
        } else {
            const woliResult = await createRecord({
                apiName: WOLI_OBJECT.objectApiName,
                fields: this._buildWoliPartsFields(partsSource, edit.assignedResourceId)
            });
            woliId = woliResult.id;
            await updateRecord({
                fields: {
                    Id: pcId,
                    [PC_WORKORDER_LINE_ITEM.fieldApiName]: woliId
                }
            });
            edit.workOrderLineItemId = woliId;
        }

        this._cachePartsSource(woliId, partsSource ?? '');
    }

    /**
     * @description Internal helper: Parts Source For Part.
     */
    _partsSourceForPart(p) {
        const woliId = p.WorkOrderLineItemId?.value ?? null;
        return normalizePartsSource(
            p.WorkOrderLineItem?.PartsSource__c?.value
            ?? (woliId ? this._partsSourceByWoliId[woliId] : null)
        ) ?? '';
    }

    /**
     * @description Internal helper: Seed Parts Source Cache From Lines.
     */
    _seedPartsSourceCacheFromLines(lines) {
        const next = { ...this._partsSourceByWoliId };
        for (const line of lines ?? []) {
            const id = line.Id;
            if (!id) continue;
            next[id] = normalizePartsSource(line.PartsSource__c?.value) ?? '';
        }
        this._partsSourceByWoliId = next;
    }

    /**
     * @description Internal helper: Cache Parts Source.
     */
    _cachePartsSource(woliId, partsSource) {
        if (!woliId) return;
        this._partsSourceByWoliId = { ...this._partsSourceByWoliId, [woliId]: normalizePartsSource(partsSource) ?? '' };
    }

    /**
     * @description Internal helper: Stage Edit.
     */
    _stageEdit(id, field, value) {
        if (this._pendingAdds.some(a => a._tempId === id)) {
            this._pendingAdds = this._pendingAdds.map(a => {
                if (a._tempId !== id) return a;
                const next = { ...a, [field]: value };
                if (field === 'productItemId') {
                    if (a._schema === 'parts') {
                        if (value) next.product2Id = null;
                        const linkedProduct2Id = value
                            ? (this._product2IdByProductItemId[value] ?? null)
                            : null;
                        next.returnable = value
                            ? (this._resolveReturnableForProductItem(value) ?? null)
                            : null;
                        next.productCode = linkedProduct2Id
                            ? (this._productCodeByProduct2Id[linkedProduct2Id] ?? '')
                            : (value ? '' : (next.productCode ?? ''));
                        next.partDescription = linkedProduct2Id
                            ? (this._partDescriptionByProduct2Id[linkedProduct2Id] ?? '')
                            : (value ? '' : (next.partDescription ?? ''));
                        if (value) {
                            next.allowedUnit = null;
                            Object.assign(next, this._clearedPartExceptionFields());
                            Object.assign(next, this._clearedComponentTagFields());
                        }
                    } else {
                        next.product2Id = value
                            ? (this._product2IdByProductItemId[value] ?? null)
                            : null;
                        next.returnable = value
                            ? (this._resolveReturnableForProductItem(value) ?? null)
                            : null;
                        next.allowedUnit = null;
                    }
                }
                if (field === 'product2Id' && a._schema === 'parts') {
                    if (value) next.productItemId = null;
                    next.returnable = value
                        ? (this._resolveReturnableForProduct2(value) ?? null)
                        : null;
                    next.productCode = value
                        ? (this._productCodeByProduct2Id[value] ?? '')
                        : (next.productCode ?? '');
                    next.partDescription = value
                        ? (this._partDescriptionByProduct2Id[value] ?? '')
                        : (next.partDescription ?? '');
                    if (value) {
                        next.allowedUnit = null;
                        this._product2LookupId = value;
                        Object.assign(next, this._clearedComponentTagFields());
                    }
                }
                if (field === 'repairCodeId') {
                    next.productCode = value ? (this._resolveProductCodeForRepairCode(value) ?? '') : '';
                    next.productDescription = value ? (this._resolveProductDescriptionForRepairCode(value) ?? '') : '';
                    if (value) this._repairCodeLookupId = value;
                }
                if (field === 'unitPrice' || field === 'quantity') {
                    next = this._applyExpenseAmountToState(next);
                }
                if (field === 'overrideBillableAmount') {
                    next = this._applyExpenseBillableSync(next, field);
                }
                if (field === 'lineType' || field === 'rate' || field === 'startDate' || field === 'endDate') {
                    return this._applyLaborPricingToState(next);
                }
                return next;
            });
            return;
        }

        const expense = this._serverExpenses.find(e => e.Id === id);
        if (expense) {
            let entry = this._mergeEdit(id, this._seedExpenseEditEntry(expense), field, value);
            if (field === 'unitPrice' || field === 'quantity') {
                entry = this._applyExpenseAmountToState(entry);
            }
            if (field === 'overrideBillableAmount') {
                entry = this._applyExpenseBillableSync(entry, field);
            }
            this._pendingEdits = { ...this._pendingEdits, [id]: entry };
            return;
        }
        const part = this._serverPartsConsumed.find(p => p.Id === id);
        if (part) {
            const entry = this._mergeEdit(id, this._seedPartsEditEntry(part), field, value);
            if (field === 'productItemId') {
                entry.product2Id = value ? (this._product2IdByProductItemId[value] ?? entry.product2Id) : null;
                entry.returnable = value ? (this._resolveReturnableForProductItem(value) ?? entry.returnable) : null;
            }
            this._pendingEdits = { ...this._pendingEdits, [id]: entry };
            return;
        }
        const required = this._serverProductsRequired.find(p => p.Id === id);
        if (required) {
            const entry = this._mergeEdit(id, this._seedRequiredEditEntry(required), field, value);
            this._pendingEdits = { ...this._pendingEdits, [id]: entry };
            return;
        }
        const line = this._serverLines.find(l => l.Id === id);
        if (!line) return;
        let entry = this._mergeEdit(id, this._seedEditEntry(line), field, value);
        if (field === 'productItemId') {
            if (value) entry.product2Id = null;
            entry.returnable = value ? (this._resolveReturnableForProductItem(value) ?? null) : null;
            const linkedProduct2Id = value ? (this._product2IdByProductItemId[value] ?? null) : null;
            entry.productCode = linkedProduct2Id
                ? (this._productCodeByProduct2Id[linkedProduct2Id] ?? '')
                : (value ? '' : (entry.productCode ?? ''));
            entry.partDescription = linkedProduct2Id
                ? (this._partDescriptionByProduct2Id[linkedProduct2Id] ?? '')
                : (value ? '' : (entry.partDescription ?? ''));
            if (value) {
                Object.assign(entry, this._clearedComponentTagFields());
                entry.allowedUnit = null;
            }
        }
        if (field === 'product2Id') {
            if (value) entry.productItemId = null;
            entry.returnable = value ? (this._resolveReturnableForProduct2(value) ?? null) : null;
            entry.productCode = value
                ? (this._productCodeByProduct2Id[value] ?? '')
                : (entry.productCode ?? '');
            entry.partDescription = value
                ? (this._partDescriptionByProduct2Id[value] ?? '')
                : (entry.partDescription ?? '');
            if (value) {
                entry.allowedUnit = null;
                this._product2LookupId = value;
                Object.assign(entry, this._clearedComponentTagFields());
            }
        }
        if (field === 'repairCodeId') {
            entry.productCode = value ? (this._resolveProductCodeForRepairCode(value) ?? entry.productCode ?? '') : '';
            entry.productDescription = value ? (this._resolveProductDescriptionForRepairCode(value) ?? entry.productDescription ?? '') : '';
            if (value) this._repairCodeLookupId = value;
        }
        if (field === 'lineType' || field === 'rate' || field === 'startDate' || field === 'endDate') {
            entry = this._applyLaborPricingToState(entry);
        }
        this._pendingEdits = { ...this._pendingEdits, [id]: entry };
    }

    /**
     * @description Internal helper: Merge Edit.
     */
    _mergeEdit(id, seed, field, value) {
        const existing = this._pendingEdits[id];
        return existing ? { ...existing, [field]: value } : { ...seed, [field]: value };
    }

    /**
     * @description Internal helper: Seed Parts Edit Entry.
     */
    _seedPartsEditEntry(p) {
        const productItemId = p.ProductItemId?.value ?? null;
        const product2Id = p.Product2Id?.value ?? null;
        return {
            _schema: 'parts_consumed',
            _entity: 'ProductConsumed',
            assignedResourceId: p.ServiceResource__c?.value ?? p.Service_Resource__c?.value ?? null,
            productItemId,
            product2Id,
            returnable: p.Returnable__c?.value ?? p.Product2?.IsReturnable__c?.value ?? null,
            quantityConsumed: p.QuantityConsumed?.value ?? 0,
            description: p.Description?.value ?? '',
            partsSource: this._partsSourceForPart(p),
            workOrderLineItemId: p.WorkOrderLineItemId?.value ?? null
        };
    }

    /**
     * @description Internal helper: Seed Required Edit Entry.
     */
    _seedRequiredEditEntry(p) {
        return {
            _schema: 'required_product',
            _entity: 'ProductRequired',
            product2Id: p.Product2Id?.value ?? null,
            quantityRequired: p.QuantityRequired?.value ?? 0,
            returnable: p.Returnable__c?.value ?? ''
        };
    }

    /**
     * @description Internal helper: Seed Expense Edit Entry.
     */
    _seedExpenseEditEntry(e) {
        const amount = e.TotalPrice?.value ?? e.Amount?.value ?? 0;
        const overrideBillableAmount = this._isTruthyFlag(e.OverrideBillableAmount__c?.value);
        return {
            _schema: 'expense',
            _entity: 'Expense',
            expenseType: e.ExpenseType?.value ?? '',
            description: e.Description?.value ?? '',
            transactionDate: e.TransactionDate?.value ?? this._todayDateString(),
            quantity: e.Quantity?.value ?? 0,
            unitPrice: e.UnitPrice?.value ?? 0,
            totalPrice: amount,
            overrideCode: e.OverrideCode__c?.value ?? '',
            overrideBillableAmount,
            billableAmount: overrideBillableAmount
                ? (e.BillableAmount__c?.value ?? amount)
                : amount
        };
    }

    /**
     * @description Internal helper: Seed Edit Entry.
     */
    _seedEditEntry(line) {
        const lineType = line.LineType__c?.value ?? null;
        const schema = this._schemaForLineType(lineType);
        const base = {
            lineType,
            assignedResourceId: this._resolveAssignedResourceId(line.AssignedResource__c?.value),
            workTypeId: line.WorkTypeId?.value ?? null,
            startDate: line.StartDate?.value ?? '',
            endDate: line.EndDate?.value ?? '',
            durationHours: line.Duration?.value
                ?? this._computeDurationHours(line.StartDate?.value, line.EndDate?.value)
                ?? '',
            rate: line.Rate__c?.value ?? '',
            travelType: line.TravelType__c?.value ?? '',
            listPrice: line.ListPrice__c?.value ?? null,
            unitPrice: line.UnitPrice__c?.value ?? null,
            quantity: line.UnitQty__c?.value ?? null,
            totalPrice: line.TotalPrice__c?.value
                ?? ((line.UnitPrice__c?.value != null && line.UnitQty__c?.value != null)
                    ? (Number(line.UnitPrice__c.value) * Number(line.UnitQty__c.value))
                    : null)
        };
        if (schema === 'labor') {
            return {
                _schema: 'labor',
                _entity: 'WorkOrderLineItem',
                ...base
            };
        }
        if (schema === 'calibration') {
            return {
                _schema: 'calibration',
                _entity: 'WorkOrderLineItem',
                assignedResourceId: this._resolveAssignedResourceId(line.AssignedResource__c?.value),
                assetId: line.AssetId?.value ?? null
            };
        }
        if (schema === 'parts') {
            const productItemId = line.ProductItem__c?.value ?? null;
            const product2Id = line.Product__c?.value ?? null;
            const linkedProduct2Id = product2Id
                || (productItemId ? this._product2IdByProductItemId[productItemId] : null);
            if (product2Id && !this._productCodeByProduct2Id[product2Id]) {
                this._product2LookupId = product2Id;
            }
            return {
                _schema: 'parts',
                _entity: 'WorkOrderLineItem',
                assignedResourceId: this._resolveAssignedResourceId(line.AssignedResource__c?.value),
                partsSource: normalizePartsSource(line.PartsSource__c?.value) ?? PARTS_SOURCE_TRUNK,
                productItemId,
                product2Id,
                productCode: linkedProduct2Id
                    ? (this._productCodeByProduct2Id[linkedProduct2Id] ?? '')
                    : '',
                partDescription: line.PartDescription__c?.value
                    ?? (linkedProduct2Id ? (this._partDescriptionByProduct2Id[linkedProduct2Id] ?? '') : '')
                    ?? '',
                quantity: line.UnitQty__c?.value ?? 0,
                description: line.Description?.value ?? '',
                componentTagId: line.ComponentTag__c?.value ?? null,
                allowedUnit: line.AllowedUnit__c?.value ?? false,
                returnable: line.Returnable__c?.value
                    ?? (product2Id
                        ? this._resolveReturnableForProduct2(product2Id)
                        : this._resolveReturnableForProductItem(productItemId))
                    ?? false,
                usagesException: line.UsagesException__c?.value ?? false,
                billingType: line.BillingType__c?.value ?? '',
                removedPartId: line.RemovedPart__c?.value ?? null
            };
        }
        return { _schema: 'travel', _entity: 'WorkOrderLineItem', ...base };
    }

    /**
     * @description Internal helper: Validate For Schema.
     */
    _validateForSchema(schema, payload) {
        if (schema === 'parts_consumed') return this._validatePartsConsumed(payload);
        if (schema === 'parts') return this._validatePartsWoli(payload);
        if (schema === 'required_product') return this._validateRequiredProduct(payload);
        if (schema === 'expense') return this._validateExpense(payload);
        if (schema === 'time') return this._validateTime(payload);
        if (schema === 'travel') return this._validateTravel(payload);
        if (schema === 'labor') return this._validateLabor(payload);
        if (schema === 'calibration') return this._validateCalibration(payload);
        return null;
    }

    /**
     * @description Internal helper: Validate Parts Woli.
     */
    _validatePartsWoli({
        assignedResourceId,
        partsSource,
        productItemId,
        product2Id,
        quantity,
        allowedUnit,
        returnable,
        removedPartId,
        partExceptionDecision,
        partExceptionResponse,
        partExceptionReason,
        partExceptionAlreadyApproved,
        componentTagId,
        componentTagOptions
    }) {
        const source = normalizePartsSource(partsSource);
        if (!assignedResourceId) return 'Resource is required.';
        if (!source) return 'Part\'s Source is required.';
        if (productItemId && product2Id) {
            return 'Select either Product Item or Product, but not both.';
        }
        if (source === PARTS_SOURCE_TRUNK) {
            if (!productItemId) return 'Product Item is required.';
            if (product2Id) return 'Select either Product Item or Product, but not both.';
        } else if (source === PARTS_SOURCE_CUSTOMER) {
            if (!product2Id) return 'Product is required.';
            if (productItemId) return 'Select either Product Item or Product, but not both.';
        }
        if (!quantity || Number(quantity) <= 0) return 'Unit Qty must be greater than 0.';
        if (allowedUnit === false && !partExceptionAlreadyApproved) {
            if (partExceptionDecision !== 'yes') {
                return partExceptionDecision === 'no'
                    ? 'This part is not approved for this product and cannot be saved.'
                    : 'This part is not approved for this product. Select Yes or No to continue.';
            }
            if (!String(partExceptionResponse || '').trim()) {
                return 'Response is required to request approval for this part.';
            }
            if (!partExceptionReason) {
                return 'Part Exception Reason is required.';
            }
        }
        // GW-6095: an allowed part with several Component Tags needs one selected.
        if (allowedUnit === true && (componentTagOptions?.length ?? 0) > 1 && !componentTagId) {
            return 'Component Tag is required.';
        }
        if (this._isRemovedPartRequired(returnable) && !removedPartId) {
            return 'Removed Part is required when the selected part is returnable.';
        }
        return null;
    }

    /**
     * @description Internal helper: Validate Parts Consumed.
     */
    _validatePartsConsumed({ assignedResourceId, productItemId, quantityConsumed }) {
        if (!assignedResourceId) return 'Resource is required.';
        if (!productItemId) return 'Product Item is required.';
        if (!quantityConsumed || Number(quantityConsumed) <= 0) return 'Quantity Consumed must be greater than 0.';
        return null;
    }

    /**
     * @description Internal helper: Validate Required Product.
     */
    _validateRequiredProduct({ product2Id, quantityRequired }) {
        if (!product2Id) return 'Product is required.';
        if (!quantityRequired || Number(quantityRequired) <= 0) return 'Quantity Required must be greater than 0.';
        return null;
    }

    /**
     * @description Internal helper: Validate Expense.
     */
    _validateExpense({
        expenseType,
        transactionDate,
        quantity,
        unitPrice,
        overrideCode,
        overrideBillableAmount,
        billableAmount
    }) {
        if (!expenseType) return 'Expense Type is required.';
        if (!transactionDate) return 'Transaction Date is required.';
        if (unitPrice === '' || unitPrice == null || Number(unitPrice) < 0) return 'Unit Price must be 0 or greater.';
        if (!quantity || Number(quantity) <= 0) return 'Quantity must be greater than 0.';
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
     * @description Internal helper: Validate Time.
     */
    _validateTime(payload) {
        if (!payload.lineType || !TIME_LINE_TYPES.has(payload.lineType)) {
            return 'Line Type is required.';
        }
        const schema = LINE_TYPE_TO_SCHEMA[payload.lineType];
        return this._validateForSchema(schema, payload);
    }

    /**
     * @description Internal helper: Validate Travel.
     */
    _validateTravel({ assignedResourceId, startDate, endDate, rate, travelType, durationHours }) {
        if (!assignedResourceId) return 'Resource is required.';
        if (!startDate) return 'Start Time is required.';
        if (!endDate) return 'End Time is required.';
        const hours = durationHours != null && durationHours !== ''
            ? Number(durationHours)
            : this._computeDurationHours(startDate, endDate);
        if (hours == null || Number.isNaN(hours) || hours <= 0) {
            return 'Duration is required and must be greater than 0.';
        }
        if (new Date(endDate).getTime() < new Date(startDate).getTime()) {
            return 'End Time must be the same as or after Start Time.';
        }
        if (!travelType) return 'Travel Type is required for Travel lines.';
        if (travelType === TRAVEL_TYPE_ACTUAL && !rate) {
            return 'Rate is required for Actual Travel.';
        }
        return null;
    }

    /**
     * @description Internal helper: Validate Labor.
     */
    _validateLabor({ assignedResourceId, startDate, endDate, durationHours, rate }) {
        if (!assignedResourceId) return 'Resource is required.';
        if (!startDate) return 'Start Time is required.';
        if (!endDate) return 'End Time is required.';
        const hours = durationHours != null && durationHours !== ''
            ? Number(durationHours)
            : this._computeDurationHours(startDate, endDate);
        if (hours == null || Number.isNaN(hours) || hours <= 0) {
            return 'Duration is required and must be greater than 0.';
        }
        if (new Date(endDate).getTime() < new Date(startDate).getTime()) {
            return 'End Time must be the same as or after Start Time.';
        }
        if (!rate) return 'Rate is required for Labor lines.';
        return null;
    }

    /**
     * @description Internal helper: Validate Calibration.
     */
    _validateCalibration({ assignedResourceId }) {
        if (!assignedResourceId) return 'Resource is required.';
        return null;
    }

    /**
     * @description Internal helper: Schema For Line Type.
     */
    _schemaForLineType(lineType) {
        return TYPE_TO_DEF[lineType]?.schema ?? 'travel';
    }

    /**
     * @description Internal helper: Reset Draft.
     */
    _resetDraft() {
        this._pendingEdits = {};
        this._pendingDeletes = {};
        this._pendingAdds = [];
        this._pendingCycleCount = undefined;
        this._pendingCycleCountDate = undefined;
        this.editStateMap = {};
        this.showAddForm = EMPTY_ADD_FORM_VISIBILITY();
        this.addFormState = this._emptyAddFormState();
        this.editErrors = {};
        this.addErrors = {};
    }

    /**
     * @description Internal helper: Empty Add Form State.
     */
    _emptyAddFormState() {
        return {
            lineType: '',
            rate: '',
            travelType: '',
            workTypeId: this._headerWorkTypeId(),
            assignedResourceId: this._defaultAssignedResourceId(),
            productItemId: null,
            product2Id: null,
            productCode: '',
            partDescription: '',
            returnable: null,
            quantityConsumed: '',
            partsSource: PARTS_SOURCE_TRUNK,
            quantityRequired: '',
            expenseType: '',
            description: '',
            transactionDate: this._todayDateString(),
            overrideCode: '',
            billableAmount: '',
            overrideBillableAmount: false,
            listPrice: null,
            unitPrice: '',
            listPrice: null,
            totalPrice: null,
            quantity: '',
            durationHours: '',
            totalPrice: null,
            usagesException: false,
            ...this._clearedPartExceptionFields(),
            ...this._clearedComponentTagFields(),
            allowedUnit: null,
            billingType: '',
            removedPartId: null,
            startDate: '',
            endDate: '',
            assetId: null,
            repairCodeId: null
        };
    }

    /**
     * @description Reads a record Id from a lookup / record-picker event (desktop and mobile).
     * @param {Event} event Change event
     * @return {string|null}
     */
    _lookupRecordId(event) {
        return event?.detail?.recordId
            ?? event?.detail?.value
            ?? event?.currentTarget?.value
            ?? event?.target?.value
            ?? null;
    }

    /**
     * @description Reads the current lightning-record-picker value for a Time-tab field.
     * @param {string} field Field dataset name
     * @param {Object} options Add form or edit line
     * @return {string|null}
     */
    _readTimePickerValue(field, { isAddForm = false, editId = null } = {}) {
        const pickers = this.template.querySelectorAll(`lightning-record-picker[data-field="${field}"]`);
        for (const picker of pickers) {
            const matchesAdd = isAddForm && picker.dataset.tab === 'Time';
            const matchesEdit = editId && picker.dataset.id === editId;
            if (matchesAdd || matchesEdit) {
                return picker.value || null;
            }
        }
        return null;
    }

    /**
     * @description Loads the Work Order assigned Service Resource when the wire has not populated it.
     * @return {Promise<string|null>}
     */
    async _ensureWorkOrderAssignedResourceId() {
        if (!this._currentUserServiceResourceId) {
            try {
                const currentId = await getCurrentUserServiceResourceId();
                if (currentId) {
                    this._currentUserServiceResourceId = currentId;
                }
            } catch (e) {
                /* briefcase / offline: keep GraphQL value */
            }
        }
        if (this._workOrderAssignedResourceId || !this.recordId) {
            return this._workOrderAssignedResourceId;
        }
        try {
            const assignedId = await getAssignedServiceResourceId({ workOrderId: this.recordId });
            if (assignedId) {
                this._workOrderAssignedResourceId = assignedId;
                this._applyDefaultResourceToAddForm();
            }
        } catch (e) {
            /* briefcase / offline: keep current default */
        }
        return this._workOrderAssignedResourceId;
    }

    /**
     * @description Resource used for the Time-tab skill check: picker, explicit selection,
     *              Work Order assignee, then current user.
     * @param {string|null} assignedResourceId Value from form state
     * @param {Object} options Add form or edit line
     * @return {Promise<string|null>}
     */
    async _resolveTimeSkillResourceId(assignedResourceId, { isAddForm = false, editId = null } = {}) {
        await this._ensureWorkOrderAssignedResourceId();
        const pickerId = this._readTimePickerValue('assignedResourceId', { isAddForm, editId });
        const selectedId = pickerId || assignedResourceId || this.addFormState?.assignedResourceId;
        const currentUserId = this._currentUserServiceResourceId;
        const workOrderAssignedId = this._workOrderAssignedResourceId;
        if (selectedId && !this._isSameSalesforceId(selectedId, currentUserId)) {
            return selectedId;
        }
        if (workOrderAssignedId) {
            return workOrderAssignedId;
        }
        return selectedId || currentUserId || null;
    }

    /**
     * @description Internal helper: Default Assigned Resource Id.
     *              Prefers the Work Order assigned resource over the current user's resource.
     */
    _defaultAssignedResourceId() {
        return this._workOrderAssignedResourceId ?? this._currentUserServiceResourceId ?? null;
    }

    /**
     * @description Sets the Time add-form Resource to the Work Order assignee when the field is
     *              empty or still on the current-user default.
     */
    _applyDefaultResourceToAddForm() {
        const preferredId = this._defaultAssignedResourceId();
        if (!preferredId || !this.addFormState) {
            return;
        }
        const currentId = this.addFormState.assignedResourceId;
        const isCurrentUserDefault = this._currentUserServiceResourceId
            && this._isSameSalesforceId(currentId, this._currentUserServiceResourceId);
        if (currentId && !isCurrentUserDefault) {
            return;
        }
        if (this._isSameSalesforceId(currentId, preferredId)) {
            return;
        }
        this.addFormState = { ...this.addFormState, assignedResourceId: preferredId };
        this._onResourceSelected(preferredId);
    }

    /**
     * @description True when two Salesforce Ids refer to the same record (15- or 18-char).
     * @param {string|null} left First Id
     * @param {string|null} right Second Id
     * @return {Boolean}
     */
    _isSameSalesforceId(left, right) {
        if (!left || !right) return false;
        const a = String(left);
        const b = String(right);
        return a === b || a.substring(0, 15) === b.substring(0, 15);
    }

    /**
     * @description True when the Time-line Work Type differs from the Work Order Work Type.
     * @param {string|null} workTypeId Selected Work Type Id
     * @return {Boolean}
     */
    _isDifferentWorkTypeFromHeader(workTypeId) {
        if (!workTypeId) return false;
        const headerWorkTypeId = this._headerWorkTypeId();
        if (!headerWorkTypeId) return false;
        return !this._isSameSalesforceId(workTypeId, headerWorkTypeId);
    }

    /**
     * @description Builds the user-facing message when a resource is missing Work Type skills.
     * @param {Object} result Apex SkillCheckResult
     * @return {string|null}
     */
    _timeSkillErrorMessage(result) {
        if (!result || result.hasRequiredSkills) return null;
        const names = (result.missingSkillNames || []).filter(Boolean);
        const resourceLabel = result.serviceResourceName
            ? `"${result.serviceResourceName}"`
            : 'The selected resource';
        if (!names.length) {
            return `${resourceLabel} does not have the required skill for this Work Type.`;
        }
        const plural = names.length > 1 ? 's' : '';
        return `${resourceLabel} does not have the required skill${plural} for this Work Type: ${names.join(', ')}.`;
    }

    /**
     * @description True when the message is a Time-tab skill-check error.
     * @param {string|null} message Error text
     * @return {Boolean}
     */
    _isTimeSkillError(message) {
        return typeof message === 'string' && message.includes('required skill');
    }

    /**
     * @description Applies or clears a Time-tab skill-check error on add or edit.
     * @param {string|null} message Error text, or null to clear
     * @param {Object} options Target line
     */
    _applyTimeSkillError(message, { editId = null, isAddForm = false } = {}) {
        if (isAddForm) {
            const errs = { ...this.addErrors };
            if (message) {
                errs.Time = message;
            } else if (this._isTimeSkillError(errs.Time)) {
                delete errs.Time;
            }
            this.addErrors = errs;
            return;
        }
        if (!editId) return;
        const errs = { ...this.editErrors };
        if (message) {
            errs[editId] = message;
        } else if (this._isTimeSkillError(errs[editId])) {
            delete errs[editId];
        }
        this.editErrors = errs;
    }

    /**
     * @description GW-2494: When Time-tab Work Type differs from the WO Work Type, verify the resource has the Work Type skills.
     * @param {Object} options Work Type, resource, and UI target
     * @return {Promise<Boolean>} True when the combination is allowed
     */
    async _checkTimeWorkTypeSkills({
        workTypeId,
        assignedResourceId,
        editId = null,
        isAddForm = false,
        showToast = true
    } = {}) {
        const resolvedResourceId = await this._resolveTimeSkillResourceId(assignedResourceId, {
            isAddForm,
            editId
        });
        if (!this._isDifferentWorkTypeFromHeader(workTypeId) || !resolvedResourceId) {
            this._applyTimeSkillError(null, { editId, isAddForm });
            return true;
        }
        try {
            const result = await checkServiceResourceSkills({
                workTypeId,
                serviceResourceId: resolvedResourceId,
                workOrderWorkTypeId: this._headerWorkTypeId(),
                cacheBust: Date.now()
            });
            const message = this._timeSkillErrorMessage(result);
            if (message) {
                this._applyTimeSkillError(message, { editId, isAddForm });
                if (showToast) {
                    this._toast('Missing required skill', message, 'error');
                }
                return false;
            }
            this._applyTimeSkillError(null, { editId, isAddForm });
            return true;
        } catch (error) {
            const message = this._apexErrorMessage(error)
                || 'Unable to verify resource skills for the selected Work Type.';
            this._applyTimeSkillError(message, { editId, isAddForm });
            if (showToast) {
                this._toast('Skill check failed', message, 'error');
            }
            return false;
        }
    }

    /**
     * @description Runs the Time-tab skill check for an existing or pending line.
     * @param {string} lineId Server Id or pending temp Id
     * @return {Promise<Boolean>}
     */
    async _checkTimeWorkTypeSkillsForLine(lineId) {
        const pendingAdd = this._pendingAdds.find((a) => a._tempId === lineId);
        const edit = this._pendingEdits[lineId];
        const schema = edit?._schema ?? pendingAdd?._schema;
        if (schema && schema !== 'travel' && schema !== 'labor' && schema !== 'time') {
            return true;
        }
        const serverLine = this._serverLines.find((l) => l.Id === lineId);
        const workTypeId = edit?.workTypeId
            ?? pendingAdd?.workTypeId
            ?? serverLine?.WorkTypeId?.value
            ?? null;
        const assignedResourceId = this._resolveAssignedResourceId(
            edit?.assignedResourceId,
            pendingAdd?.assignedResourceId,
            serverLine?.AssignedResource__c?.value
        );
        return this._checkTimeWorkTypeSkills({
            workTypeId,
            assignedResourceId,
            editId: lineId,
            showToast: true
        });
    }

    /**
     * @description Blocks Save All when any Time line fails the Work Type skill check.
     * @return {Promise<Boolean>}
     */
    async _assertTimeSkillChecksForSave() {
        const checks = [];
        for (const [id, edit] of Object.entries(this._pendingEdits)) {
            if (edit._schema !== 'travel' && edit._schema !== 'labor' && edit._schema !== 'time') {
                continue;
            }
            const serverLine = this._serverLines.find((l) => l.Id === id);
            checks.push(this._checkTimeWorkTypeSkills({
                workTypeId: edit.workTypeId ?? serverLine?.WorkTypeId?.value ?? null,
                assignedResourceId: this._resolveAssignedResourceId(
                    edit.assignedResourceId,
                    serverLine?.AssignedResource__c?.value
                ),
                editId: id,
                showToast: false
            }));
        }
        for (const add of this._pendingAdds) {
            if (add._schema !== 'travel' && add._schema !== 'labor' && add._schema !== 'time') {
                continue;
            }
            checks.push(this._checkTimeWorkTypeSkills({
                workTypeId: add.workTypeId || this._headerWorkTypeId(),
                assignedResourceId: add.assignedResourceId,
                editId: add._tempId,
                showToast: false
            }));
        }
        if (!checks.length) return true;
        const results = await Promise.all(checks);
        return results.every((ok) => ok);
    }

    /**
     * @description Work Order header Work Type Id used as the Time-tab default.
     * @return {string|null}
     */
    _headerWorkTypeId() {
        return this._workOrder?.WorkTypeId?.value ?? this._workOrder?.WorkType?.Id ?? null;
    }
    /**
     * @description Fills Work Type on an open Time add form once the Work Order header is available.
     */
    _defaultAddFormWorkTypeFromHeader() {
        if (!this.showAddForm?.Time || this.addFormState?.workTypeId) {
            return;
        }
        const workTypeId = this._headerWorkTypeId();
        if (!workTypeId) {
            return;
        }
        this.addFormState = { ...this.addFormState, workTypeId };
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
        if (!resourceId) return '';
        return this._serviceResourceNameById[resourceId] ?? '';
    }

    /**
     * @description Internal helper: Cache Service Resource Name.
     */
    _cacheServiceResourceName(resourceId, name) {
        if (!resourceId || !name || this._serviceResourceNameById[resourceId] === name) return;
        this._serviceResourceNameById = { ...this._serviceResourceNameById, [resourceId]: name };
    }

    /**
     * @description Internal helper: Collect Service Resource Ids From Parts.
     */
    _collectServiceResourceIdsFromParts(parts) {
        const ids = new Set();
        for (const p of parts ?? []) {
            const id = p.ServiceResource__c?.value ?? p.Service_Resource__c?.value;
            if (id) ids.add(id);
        }
        return [...ids];
    }

    /**
     * @description Internal helper: Refresh Service Resource Name Lookups.
     */
    _refreshServiceResourceNameLookups(parts) {
        const ids = this._collectServiceResourceIdsFromParts(parts).filter(
            id => !this._serviceResourceNameById[id]
        );
        this._serviceResourceIdsForLookup = ids.length ? ids : undefined;
    }

    /**
     * @description Internal helper: On Resource Selected.
     */
    _onResourceSelected(recordId, editId) {
        if (recordId) {
            this._resolveLocationForResource(recordId);
        }
        if (editId) {
            const source = normalizePartsSource(
                this._pendingEdits[editId]?.partsSource
                ?? this._serverLines.find(l => l.Id === editId)?.PartsSource__c?.value
            );
            this._stageEdit(editId, 'productItemId', null);
            if (source !== PARTS_SOURCE_CUSTOMER) {
                this._stageEdit(editId, 'removedPartId', null);
            }
            this._stageEdit(editId, 'allowedUnit', null);
            this._stageEdit(editId, 'billingType', '');
            this._clearComponentTagForEdit(editId);
        }
    }

    /**
     * @description Internal helper: On Product Item Selected.
     */
    _onProductItemSelected(recordId, options = {}) {
        if (recordId) this._productItemLookupId = recordId;
        this._evaluateAllowedUnitForProductItem(recordId, options);
        this._evaluateBillingType({ productItemId: recordId, ...options });
    }

    /**
     * @description Applies Parts Source change side-effects on a staged WOLI edit.
     */
    _applyPartsSourceChangeToEdit(editId, partsSource) {
        if (!editId) return;
        const source = normalizePartsSource(partsSource);
        this._stageEdit(editId, 'allowedUnit', null);
        this._stageEdit(editId, 'billingType', '');
        this._clearComponentTagForEdit(editId);
        this._stageEdit(editId, 'returnable', null);
        this._stageEdit(editId, 'productCode', '');
        this._stageEdit(editId, 'partDescription', '');
        if (source === PARTS_SOURCE_TRUNK) {
            this._stageEdit(editId, 'product2Id', null);
            const productItemId = this._pendingEdits[editId]?.productItemId
                ?? this._pendingAdds.find(a => a._tempId === editId)?.productItemId;
            if (productItemId) {
                const linkedProduct2Id = this._product2IdByProductItemId[productItemId];
                this._stageEdit(
                    editId,
                    'returnable',
                    this._resolveReturnableForProductItem(productItemId)
                );
                if (linkedProduct2Id) {
                    this._stageEdit(
                        editId,
                        'productCode',
                        this._productCodeByProduct2Id[linkedProduct2Id] ?? ''
                    );
                    this._stageEdit(
                        editId,
                        'partDescription',
                        this._partDescriptionByProduct2Id[linkedProduct2Id] ?? ''
                    );
                }
                this._onProductItemSelected(productItemId, { editId });
            }
        } else if (source === PARTS_SOURCE_CUSTOMER) {
            this._stageEdit(editId, 'productItemId', null);
        }
    }

    /**
     * @description GW-3329: Fields cleared when the selected part changes.
     */
    _clearedPartExceptionFields() {
        return {
            partExceptionDecision: null,
            partExceptionResponse: '',
            partExceptionReason: '',
            partExceptionProductKey: null,
            partExceptionAlreadyApproved: false,
            partExceptionBlocked: false,
            partExceptionSubmit: false
        };
    }

    /**
     * @description GW-3329: Approval fields written when the technician proceeds with a non-approved part.
     */
    _partExceptionSaveFields(record) {
        if (!record?.partExceptionSubmit) {
            return {
                [WOLI_USAGES_EXCEPTION.fieldApiName]: !!record?.usagesException
            };
        }
        return {
            [WOLI_USAGES_EXCEPTION.fieldApiName]: true,
            [WOLI_APPROVAL_STATUS.fieldApiName]: 'In Approvals',
            [WOLI_NON_APPROVED_PART_RESPONSE.fieldApiName]: record.partExceptionResponse ?? '',
            [WOLI_PART_EXCEPTION_REASON.fieldApiName]: record.partExceptionReason || null
        };
    }

    /**
     * @description GW-3329: View fields for the response and reason inputs.
     */
    _partExceptionView(primary, secondary, allowedUnit) {
        const decision = primary?.partExceptionDecision ?? secondary?.partExceptionDecision ?? null;
        const alreadyApproved = primary?.partExceptionAlreadyApproved
            ?? secondary?.partExceptionAlreadyApproved
            ?? false;
        const blocked = primary?.partExceptionBlocked ?? secondary?.partExceptionBlocked ?? false;
        return {
            showPartExceptionQuestion: allowedUnit === false && !alreadyApproved && !blocked,
            showPartException: decision === 'yes' && !alreadyApproved && !blocked && allowedUnit === false,
            editPartExceptionDecision: decision,
            editPartExceptionResponse: primary?.partExceptionResponse
                ?? secondary?.partExceptionResponse
                ?? '',
            editPartExceptionReason: primary?.partExceptionReason
                ?? secondary?.partExceptionReason
                ?? ''
        };
    }

    _partExceptionState({ editId = null, isAddForm = false } = {}) {
        if (isAddForm && !editId) {
            return this.addFormState || {};
        }
        if (!editId) {
            return {};
        }
        const pendingAdd = this._pendingAdds.find(a => a._tempId === editId);
        if (pendingAdd) {
            return pendingAdd;
        }
        if (this._pendingEdits[editId]) {
            return this._pendingEdits[editId];
        }
        const line = this._serverLines.find(l => l.Id === editId);
        return {
            productItemId: line?.ProductItem__c?.value ?? null,
            product2Id: line?.Product__c?.value ?? null
        };
    }

    _partExceptionKey(state) {
        return state?.productItemId || state?.product2Id || '';
    }

    _shouldPromptPartException({ editId = null, isAddForm = false } = {}) {
        if (isAddForm && !editId) {
            return this.activeTab === 'Parts';
        }
        const pendingAdd = this._pendingAdds.find(item => item._tempId === editId);
        if (pendingAdd) {
            return pendingAdd._schema === 'parts';
        }
        if (this._pendingEdits[editId]?._schema) {
            return this._pendingEdits[editId]._schema === 'parts';
        }
        const line = this._serverLines.find(item => item.Id === editId);
        return line?.LineType__c?.value === 'Parts';
    }

    _writePartException({ editId = null, isAddForm = false } = {}, values) {
        if (isAddForm && !editId) {
            this.addFormState = { ...this.addFormState, ...values };
            return;
        }
        if (editId && this._pendingAdds.some(a => a._tempId === editId)) {
            this._pendingAdds = this._pendingAdds.map(a => (
                a._tempId === editId ? { ...a, ...values } : a
            ));
            return;
        }
        if (!editId) {
            return;
        }
        Object.entries(values).forEach(([field, value]) => {
            this._stageEdit(editId, field, value);
        });
    }

    /**
     * @description GW-3329: Yes/No prompt when the selected part is not on the SBOM.
     */
    async _promptPartException({ editId = null, isAddForm = false } = {}) {
        const state = this._partExceptionState({ editId, isAddForm });
        const key = this._partExceptionKey(state);
        if (!key) {
            return;
        }
        if (state.partExceptionProductKey && state.partExceptionProductKey !== key) {
            this._writePartException({ editId, isAddForm }, this._clearedPartExceptionFields());
        }
        if (state.partExceptionProductKey === key && (
            state.partExceptionDecision === 'yes'
            || state.partExceptionDecision === 'no'
            || state.partExceptionAlreadyApproved
        )) {
            return;
        }
        if (this._partExceptionPromptKey === key && this._partExceptionPromptPromise) {
            await this._partExceptionPromptPromise;
            return;
        }
        this._partExceptionPromptKey = key;
        let resolvePrompt;
        this._partExceptionPromptPromise = new Promise((resolve) => {
            resolvePrompt = resolve;
        });
        const context = { editId, isAddForm };
        try {
            if (state.productItemId) {
                const check = await checkProductItemApproval({ productItemId: state.productItemId });
                if (this._partExceptionKey(this._partExceptionState(context)) !== key) {
                    return;
                }
                if (check?.alreadyApproved) {
                    this._writePartException(context, {
                        ...this._clearedPartExceptionFields(),
                        partExceptionDecision: 'yes',
                        partExceptionAlreadyApproved: true,
                        partExceptionProductKey: key,
                        partExceptionSubmit: false
                    });
                    return;
                }
                if (check && check.allowed === false) {
                    this._writePartException(context, {
                        ...this._clearedPartExceptionFields(),
                        partExceptionDecision: 'no',
                        partExceptionBlocked: true,
                        partExceptionProductKey: key
                    });
                    this._toast('Part not approved', check.message, 'error');
                }
            }
        } catch (error) {
            const message = this._apexErrorMessage(error) || 'Unable to check this part.';
            this._toast('Part not approved', message, 'error');
        } finally {
            if (this._partExceptionPromptKey === key) {
                this._partExceptionPromptKey = null;
                this._partExceptionPromptPromise = null;
            }
            if (resolvePrompt) {
                resolvePrompt();
            }
        }
    }

    /**
     * @description Evaluates Allowed Unit for a Product Item via Apex.
     *              Apex skips SBOM cross-reference when Root PFCL SBOM Required is not Yes
     *              (GW-4218) or when the Work Order has no Asset — both return evaluated=false.
     */
    async _evaluateAllowedUnitForProductItem(productItemId, options = {}) {
        const { editId = null, isAddForm = false } = options;
        // GW-6095: no part to evaluate, so clear any Component Tag selection.
        if (!this.recordId || !productItemId) {
            this._applyComponentTagFields(this._clearedComponentTagFields(), { editId, isAddForm });
        }
        if (!productItemId || !this.recordId) {
            await this._applyAllowedUnitResult(null, { editId, isAddForm });
            return;
        }

        try {
            const result = await evaluateAllowedUnit({
                workOrderId: this.recordId,
                productItemId
            });
            await this._refreshComponentTags(result, { productItemId }, { editId, isAddForm });
            // No WO asset, or Root PFCL SBOM Required != Yes → leave fields unset.
            if (!result?.evaluated) {
                await this._applyAllowedUnitResult(null, { editId, isAddForm });
                return;
            }
            await this._applyAllowedUnitResult(
                !!result.allowedUnit,
                { editId, isAddForm }
            );
        } catch (error) {
            const message = this._apexErrorMessage(error) || 'Unable to validate allowed parts.';
            this.dispatchEvent(new ShowToastEvent({
                title: 'Allowed Unit check failed',
                message,
                variant: 'error'
            }));
        }
    }

    /**
     * @description GW-4311 — Evaluates Allowed Unit for a Product2 via Apex.
     */
    async _evaluateAllowedUnitForProduct(product2Id, options = {}) {
        const { editId = null, isAddForm = false } = options;
        // GW-6095: no part to evaluate, so clear any Component Tag selection.
        if (!this.recordId || !product2Id) {
            this._applyComponentTagFields(this._clearedComponentTagFields(), { editId, isAddForm });
        }
        if (!product2Id || !this.recordId) {
            await this._applyAllowedUnitResult(null, { editId, isAddForm });
            return;
        }

        try {
            const result = await evaluateAllowedUnitByProduct({
                workOrderId: this.recordId,
                product2Id
            });
            await this._refreshComponentTags(result, { product2Id }, { editId, isAddForm });
            if (!result?.evaluated) {
                await this._applyAllowedUnitResult(null, { editId, isAddForm });
                return;
            }
            await this._applyAllowedUnitResult(
                !!result.allowedUnit,
                { editId, isAddForm }
            );
        } catch (error) {
            const message = this._apexErrorMessage(error) || 'Unable to validate allowed parts.';
            this.dispatchEvent(new ShowToastEvent({
                title: 'Allowed Unit check failed',
                message,
                variant: 'error'
            }));
        }
    }

    /**
     * @description GW-6095 — After the Allowed Unit check, loads the Component Tags of an allowed part
     *              or clears them when the part is not allowed or the check was skipped.
     *              One tag is selected automatically; with several, a still-valid selection is kept.
     * @param {Object} allowedUnitResult AllowedUnitEvaluationDTO returned by Apex
     * @param {Object} part { productItemId } for Trunk Stock or { product2Id } for Customer Stock
     * @param {Object} target { editId, isAddForm }
     */
    async _refreshComponentTags(
        allowedUnitResult,
        { productItemId = null, product2Id = null } = {},
        { editId = null, isAddForm = false } = {}
    ) {
        if (!allowedUnitResult?.evaluated || allowedUnitResult.allowedUnit !== true) {
            this._applyComponentTagFields(this._clearedComponentTagFields(), { editId, isAddForm });
            return;
        }

        let componentTagOptions;
        try {
            const tags = productItemId
                ? await getComponentTagsForProductItem({ workOrderId: this.recordId, productItemId })
                : await getComponentTagsForProduct({ workOrderId: this.recordId, product2Id });
            componentTagOptions = (tags ?? []).map(tag => ({ label: tag.label, value: tag.id }));
        } catch (error) {
            this._applyComponentTagFields(this._clearedComponentTagFields(), { editId, isAddForm });
            this._toast(
                'Component Tag lookup failed',
                this._apexErrorMessage(error) || 'Unable to load component tags.',
                'error'
            );
            return;
        }

        // The part may have changed while the tags were loading; ignore a stale response.
        const target = this._componentTagTarget({ editId, isAddForm });
        const stillSelected = productItemId
            ? target?.productItemId === productItemId
            : target?.product2Id === product2Id;
        if (target && !stillSelected) {
            return;
        }

        const currentId = target?.componentTagId ?? null;
        let componentTagId = null;
        if (componentTagOptions.length === 1) {
            componentTagId = componentTagOptions[0].value;
        } else if (componentTagOptions.some(option => option.value === currentId)) {
            componentTagId = currentId;
        }
        this._applyComponentTagFields(
            { componentTagId, componentTagOptions, componentTagsLoaded: true },
            { editId, isAddForm }
        );
    }

    /**
     * @description GW-6095 — Component Tag fields reset when the part changes or is not allowed.
     * @return {Object} Cleared Component Tag fields
     */
    _clearedComponentTagFields() {
        return { componentTagId: null, componentTagOptions: [], componentTagsLoaded: false };
    }

    /**
     * @description GW-6095 — Clears the Component Tag fields on an edit row or pending add.
     * @param {String} editId Line Id or pending add temp Id
     */
    _clearComponentTagForEdit(editId) {
        this._applyComponentTagFields(this._clearedComponentTagFields(), { editId });
    }

    /**
     * @description GW-6095 — Writes Component Tag fields to the add form, or stages them on an edit row.
     * @param {Object} fields componentTagId / componentTagOptions / componentTagsLoaded
     * @param {Object} target { editId, isAddForm }
     */
    _applyComponentTagFields(fields, { editId = null, isAddForm = false } = {}) {
        if (isAddForm) {
            this.addFormState = { ...this.addFormState, ...fields };
        } else if (editId) {
            Object.entries(fields).forEach(([field, value]) => this._stageEdit(editId, field, value));
        }
    }

    /**
     * @description GW-6095 — Current state holding the part and Component Tag for the add form,
     *              a pending add, or a staged edit.
     * @param {Object} target { editId, isAddForm }
     * @return {Object|null} State object, or null when nothing is staged yet
     */
    _componentTagTarget({ editId = null, isAddForm = false } = {}) {
        if (isAddForm) {
            return this.addFormState;
        }
        return this._pendingAdds.find(a => a._tempId === editId) ?? this._pendingEdits[editId] ?? null;
    }

    /**
     * @description GW-6095 — View fields for the Component Tag on a parts line or the add form.
     *              Several tags: required picklist. One tag or a saved tag: read-only name.
     *              Allowed part without tags: a message, and saving is still allowed.
     * @param {Object} input Allowed Unit flag, selected tag, options, loaded flag and saved tag
     * @return {Object} Component Tag view fields for the template
     */
    _componentTagView({
        allowedUnit,
        componentTagId,
        componentTagOptions,
        componentTagsLoaded,
        savedComponentTagId = null,
        savedComponentTagName = ''
    }) {
        const options = componentTagOptions ?? [];
        const selected = options.find(option => option.value === componentTagId);
        const label = selected?.label
            ?? (componentTagId && componentTagId === savedComponentTagId ? savedComponentTagName : '');
        const showPicker = allowedUnit === true && options.length > 1;
        const showNoTagMessage = !!componentTagsLoaded && allowedUnit === true && options.length === 0;
        return {
            editComponentTagId: componentTagId ?? null,
            componentTagOptions: options,
            componentTagLabel: label,
            showComponentTagPicker: showPicker,
            showComponentTagReadOnly: !showPicker && !showNoTagMessage && !!label,
            showNoComponentTagMessage: showNoTagMessage,
            noComponentTagMessage: NO_COMPONENT_TAG_MESSAGE
        };
    }

    /**
     * @description Internal helper: Apex Error Message.
     */
    _apexErrorMessage(error) {
        if (!error) return null;
        if (typeof error.body?.message === 'string' && error.body.message) return error.body.message;
        if (Array.isArray(error.body) && error.body[0]?.message) return error.body[0].message;
        if (typeof error.message === 'string' && error.message) return error.message;
        return null;
    }

    /**
     * @description Internal helper: Apply Allowed Unit Result.
     */
    async _applyAllowedUnitResult(allowedUnit, { editId = null, isAddForm = false } = {}) {
        if (isAddForm) {
            this.addFormState = { ...this.addFormState, allowedUnit };
        } else if (editId) {
            this._stageEdit(editId, 'allowedUnit', allowedUnit);
        }
        if (!this._shouldPromptPartException({ editId, isAddForm })) {
            return;
        }
        if (allowedUnit === false) {
            await this._promptPartException({ editId, isAddForm });
            return;
        }
        this._writePartException({ editId, isAddForm }, this._clearedPartExceptionFields());
    }

    /**
     * @description GW-1738 / GW-2001: Evaluates Billing Type via Apex for the selected part.
     */
    async _evaluateBillingType({
        product2Id = null,
        productItemId = null,
        editId = null,
        isAddForm = false
    } = {}) {
        if (!this.recordId || (!product2Id && !productItemId)) {
            this._applyBillingTypeResult('', { editId, isAddForm });
            return;
        }

        try {
            const billingType = productItemId
                ? await evaluateBillingTypeForProductItem({
                    workOrderId: this.recordId,
                    productItemId
                })
                : await evaluateBillingType({
                    workOrderId: this.recordId,
                    product2Id
                });
            this._applyBillingTypeResult(billingType || '', { editId, isAddForm });
        } catch (error) {
            const message = this._apexErrorMessage(error) || 'Unable to evaluate billing type.';
            this.dispatchEvent(new ShowToastEvent({
                title: 'Billing Type check failed',
                message,
                variant: 'error'
            }));
        }
    }

    /**
     * @description Applies Apex Billing Type onto the add form or staged edit.
     * @param {String} billingType Billable or SVC Warranty
     */
    _applyBillingTypeResult(billingType, { editId = null, isAddForm = false } = {}) {
        if (isAddForm) {
            this.addFormState = { ...this.addFormState, billingType };
            return;
        }
        if (editId) {
            this._stageEdit(editId, 'billingType', billingType);
        }
    }

    /**
     * @description Internal helper: Resolve Returnable For Product Item.
     */
    _resolveReturnableForProductItem(productItemId) {
        if (!productItemId) return null;
        return this._isReturnableByProductItemId[productItemId] ?? null;
    }

    /**
     * @description Internal helper: Resolve Returnable For Product2.
     */
    _resolveReturnableForProduct2(product2Id) {
        if (!product2Id) return null;
        return this._isReturnableByProduct2Id[product2Id] ?? null;
    }

    /**
     * @description Internal helper: Sync Returnable For Product Item.
     */
    _syncReturnableForProductItem(productItemId, isReturnable) {
        if (this.addFormState?.productItemId === productItemId) {
            this.addFormState = { ...this.addFormState, returnable: isReturnable };
        }
        this._pendingAdds = this._pendingAdds.map(a => (
            a.productItemId === productItemId
            && (a._entity === 'ProductConsumed' || a._schema === 'parts')
                ? { ...a, returnable: isReturnable }
                : a
        ));
        const edits = { ...this._pendingEdits };
        let changed = false;
        for (const [id, edit] of Object.entries(edits)) {
            if (
                edit.productItemId === productItemId
                && (edit._entity === 'ProductConsumed' || edit._schema === 'parts')
            ) {
                edits[id] = { ...edit, returnable: isReturnable };
                changed = true;
            }
        }
        if (changed) this._pendingEdits = edits;
    }

    /**
     * @description Caches Product2 details and syncs onto matching Parts form / pending rows.
     */
    _applyProductDetails(product2Id, details = {}) {
        if (!product2Id) return;
        const { name, productCode, partDescription, isReturnable } = details;
        if (name) {
            this._productNameByProduct2Id = { ...this._productNameByProduct2Id, [product2Id]: name };
        }
        if (productCode != null) {
            this._productCodeByProduct2Id = { ...this._productCodeByProduct2Id, [product2Id]: productCode };
        }
        if (partDescription != null) {
            this._partDescriptionByProduct2Id = {
                ...this._partDescriptionByProduct2Id,
                [product2Id]: partDescription
            };
        }
        if (isReturnable !== undefined && isReturnable !== null) {
            this._isReturnableByProduct2Id = {
                ...this._isReturnableByProduct2Id,
                [product2Id]: isReturnable
            };
        }
        this._syncProductDetailsForProduct2(product2Id, { productCode, partDescription, isReturnable });

        if (this.addFormState?.product2Id === product2Id) {
            this._evaluateAllowedUnitForProduct(product2Id, { isAddForm: true });
            this._evaluateBillingType({ product2Id, isAddForm: true });
        }
        for (const [id, edit] of Object.entries(this._pendingEdits)) {
            if (edit._schema === 'parts' && edit.product2Id === product2Id) {
                this._evaluateAllowedUnitForProduct(product2Id, { editId: id });
                this._evaluateBillingType({ product2Id, editId: id });
            }
        }
    }

    /**
     * @description Syncs Product2 code / description / returnable onto matching Parts rows.
     */
    _syncProductDetailsForProduct2(product2Id, { productCode, partDescription, isReturnable } = {}) {
        if (!product2Id) return;
        if (this.addFormState?.product2Id === product2Id) {
            this.addFormState = {
                ...this.addFormState,
                ...(productCode != null ? { productCode } : {}),
                ...(partDescription != null ? { partDescription } : {}),
                ...(isReturnable !== undefined && isReturnable !== null ? { returnable: isReturnable } : {})
            };
        }
        this._pendingAdds = this._pendingAdds.map(a => (
            a._schema === 'parts' && a.product2Id === product2Id
                ? {
                    ...a,
                    ...(productCode != null ? { productCode } : {}),
                    ...(partDescription != null ? { partDescription } : {}),
                    ...(isReturnable !== undefined && isReturnable !== null ? { returnable: isReturnable } : {})
                }
                : a
        ));
        const edits = { ...this._pendingEdits };
        let changed = false;
        for (const [id, edit] of Object.entries(edits)) {
            if (edit._schema === 'parts' && edit.product2Id === product2Id) {
                edits[id] = {
                    ...edit,
                    ...(productCode != null ? { productCode } : {}),
                    ...(partDescription != null ? { partDescription } : {}),
                    ...(isReturnable !== undefined && isReturnable !== null ? { returnable: isReturnable } : {})
                };
                changed = true;
            }
        }
        if (changed) this._pendingEdits = edits;
    }

    /**
     * @description Syncs Product2 code / description onto Parts rows keyed by Product Item.
     */
    _syncProductDetailsForProductItem(productItemId, { productCode, partDescription } = {}) {
        if (!productItemId) return;
        if (this.addFormState?.productItemId === productItemId) {
            this.addFormState = {
                ...this.addFormState,
                product2Id: null,
                ...(productCode != null ? { productCode } : {}),
                ...(partDescription != null ? { partDescription } : {})
            };
        }
        this._pendingAdds = this._pendingAdds.map(a => (
            a._schema === 'parts' && a.productItemId === productItemId
                ? {
                    ...a,
                    product2Id: null,
                    ...(productCode != null ? { productCode } : {}),
                    ...(partDescription != null ? { partDescription } : {})
                }
                : a
        ));
        const edits = { ...this._pendingEdits };
        let changed = false;
        for (const [id, edit] of Object.entries(edits)) {
            if (edit._schema === 'parts' && edit.productItemId === productItemId) {
                edits[id] = {
                    ...edit,
                    product2Id: null,
                    ...(productCode != null ? { productCode } : {}),
                    ...(partDescription != null ? { partDescription } : {})
                };
                changed = true;
            }
        }
        if (changed) this._pendingEdits = edits;
    }

    /**
     * @description Internal helper: Fmt Returnable.
     */
    _fmtReturnable(value) {
        if (value === true || value === 'true' || value === 'True') return 'Yes';
        if (value === false || value === 'false' || value === 'False') return 'No';
        return '';
    }

    /**
     * @description Removed Part is required when the selected part is returnable.
     */
    _isRemovedPartRequired(returnable) {
        return returnable === true || returnable === 'true' || returnable === 'True';
    }

    /**
     * @description Product2 Id that drives Removed Part options for the add form.
     */
    _sourceProduct2IdForAddForm() {
        if (this.addFormIsCustomerStock) return this.addFormState.product2Id || null;
        const productItemId = this.addFormState.productItemId;
        return productItemId ? (this._product2IdByProductItemId[productItemId] ?? null) : null;
    }

    /**
     * @description Removed Part options for a selected product.
     *              The refurbished choice is omitted when RefurbishedProduct__c is blank.
     * @param {string|null} sourceProduct2Id Product2 of the selected Product Item or Product
     * @param {string} fallbackName Product name used until Product2.Name is loaded
     * @return {Array<{label: string, value: string}>}
     */
    _removedPartOptions(sourceProduct2Id, fallbackName) {
        if (!sourceProduct2Id) return [];
        const productName = this._productNameByProduct2Id[sourceProduct2Id]
            || fallbackName
            || this._productCodeByProduct2Id[sourceProduct2Id]
            || 'Selected Part';
        const options = [{ label: productName, value: sourceProduct2Id }];
        const refurbished = this._refurbishedByProduct2Id[sourceProduct2Id];
        if (refurbished?.id && refurbished.id !== sourceProduct2Id) {
            const refurbishedName = refurbished.name || 'Product';
            options.push({
                label: `Refurbished Part: ${refurbishedName}`,
                value: refurbished.id
            });
        }
        return options;
    }

    /**
     * @description Caches RefurbishedProduct__c for a source product. A blank id hides that option.
     */
    _cacheRefurbishedProduct(sourceProduct2Id, refurbishedProductId, refurbishedProductName) {
        if (!sourceProduct2Id) return;
        const id = refurbishedProductId || null;
        const name = refurbishedProductName || null;
        const existing = this._refurbishedByProduct2Id[sourceProduct2Id];
        if (existing && existing.id === id && existing.name === name) return;
        this._refurbishedByProduct2Id = {
            ...this._refurbishedByProduct2Id,
            [sourceProduct2Id]: { id, name }
        };
    }

    /**
     * @description Stores product and refurbished-product details returned by a barcode match.
     */
    _cacheRefurbishedFromMatch(match) {
        const product2Id = match?.product2Id;
        if (!product2Id) return;
        this._cacheRefurbishedProduct(
            product2Id,
            match.refurbishedProductId,
            match.refurbishedProductName
        );
        this._removedPartSourceProduct2Id = product2Id;
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
     * @description Caches a Service Resource Location Id and refreshes Product Item filters.
     */
    _cacheServiceResourceLocation(resourceId, locationId) {
        if (!resourceId || !locationId) return;
        if (this.locationIdByServiceResourceId[resourceId] === locationId) return;
        this.locationIdByServiceResourceId = {
            ...this.locationIdByServiceResourceId,
            [resourceId]: locationId
        };
        this.productItemFilterVersion += 1;
    }

    /**
     * @description Loads Location Id for any selected Service Resource (current user or another technician).
     */
    _resolveLocationForResource(resourceId) {
        if (!resourceId) return;
        this._serviceResourceLocationLookupId = resourceId;
        if (this.locationIdByServiceResourceId[resourceId]) return;
        getLocationIdForServiceResource({ serviceResourceId: resourceId })
            .then((locationId) => {
                this._cacheServiceResourceLocation(resourceId, locationId);
            })
            .catch(() => {
                /* getRecord wire still attempts ServiceResource.LocationId */
            });
    }

    /**
     * @description Internal helper: Product Item Filter For Resource.
     */
    _productItemFilterForResource(resourceId) {
        void this.productItemFilterVersion;
        const locationId = resourceId ? this.locationIdByServiceResourceId[resourceId] : null;
        // Trunk stock: in-stock Product Items at the selected technician's Location.
        if (!locationId) {
            return {
                criteria: [{ fieldPath: 'LocationId', operator: 'eq', value: '000000000000000AAA' }]
            };
        }
        return {
            criteria: [
                { fieldPath: 'LocationId', operator: 'eq', value: locationId },
                { fieldPath: 'QuantityOnHand', operator: 'gt', value: 0 }
            ],
            filterLogic: '1 AND 2'
        };
    }

    /**
     * @description Internal helper: Resource Id For Edit Line.
     */
    _resourceIdForEditLine(editId) {
        if (!editId) return null;
        const line = this._serverLines.find(l => l.Id === editId);
        if (line?.AssignedResource__c?.value) return line.AssignedResource__c.value;
        const part = this._serverPartsConsumed.find(p => p.Id === editId);
        return part?.ServiceResource__c?.value
            ?? part?.Service_Resource__c?.value
            ?? part?.ServiceResourceId?.value
            ?? null;
    }

    /**
     * @description Internal helper: Apply Scanned Product Item.
     */
    _applyScannedProductItem(match, options = {}) {
        const { editId = null, isAddForm = false } = options;
        const productItemId = match.productItemId;
        if (match.productName) {
            this._productItemNameByProductItemId = {
                ...this._productItemNameByProductItemId,
                [productItemId]: match.productName
            };
        }
        if (match.product2Id) {
            this._product2IdByProductItemId = {
                ...this._product2IdByProductItemId,
                [productItemId]: match.product2Id
            };
            if (match.productName) {
                this._productNameByProduct2Id = {
                    ...this._productNameByProduct2Id,
                    [match.product2Id]: match.productName
                };
            }
            if (match.productCode != null) {
                this._productCodeByProduct2Id = {
                    ...this._productCodeByProduct2Id,
                    [match.product2Id]: match.productCode
                };
            }
            if (match.description != null) {
                this._partDescriptionByProduct2Id = {
                    ...this._partDescriptionByProduct2Id,
                    [match.product2Id]: match.description
                };
            }
            if (match.isReturnable != null) {
                this._isReturnableByProduct2Id = {
                    ...this._isReturnableByProduct2Id,
                    [match.product2Id]: match.isReturnable
                };
            }
        }
        if (match.isReturnable != null) {
            this._isReturnableByProductItemId = {
                ...this._isReturnableByProductItemId,
                [productItemId]: match.isReturnable
            };
        }
        this._cacheRefurbishedFromMatch(match);

        const productCode = match.productCode ?? '';
        const partDescription = match.description ?? '';

        if (isAddForm) {
            this.addFormState = {
                ...this.addFormState,
                partsSource: PARTS_SOURCE_TRUNK,
                productItemId,
                product2Id: null,
                productCode,
                partDescription,
                returnable: match.isReturnable ?? null,
                ...this._clearedComponentTagFields(),
                allowedUnit: null,
                removedPartId: null
            };
            this._onProductItemSelected(productItemId, { isAddForm: true });
            this._toast('Product Item selected', match.productName || productItemId, 'success');
            return;
        }

        if (editId) {
            this._stageEdit(editId, 'partsSource', PARTS_SOURCE_TRUNK);
            this._stageEdit(editId, 'productItemId', productItemId);
            this._stageEdit(editId, 'product2Id', null);
            this._stageEdit(editId, 'productCode', productCode);
            this._stageEdit(editId, 'partDescription', partDescription);
            this._stageEdit(editId, 'returnable', match.isReturnable ?? null);
            this._stageEdit(editId, 'removedPartId', null);
            this._clearComponentTagForEdit(editId);
            this._stageEdit(editId, 'allowedUnit', null);
            this._onProductItemSelected(productItemId, { editId });
            this._toast('Product Item selected', match.productName || productItemId, 'success');
        }
    }

    /**
     * @description GW-4311 — Apply scanned Product2 (Customer Stock).
     */
    _applyScannedProduct(match, options = {}) {
        const { editId = null, isAddForm = false } = options;
        const product2Id = match.product2Id;
        if (!product2Id) return;

        this._applyProductDetails(product2Id, {
            name: match.productName,
            productCode: match.productCode,
            partDescription: match.description,
            isReturnable: match.isReturnable
        });
        this._cacheRefurbishedFromMatch(match);
        this._product2LookupId = product2Id;

        const productCode = match.productCode ?? this._productCodeByProduct2Id[product2Id] ?? '';
        const partDescription = match.description ?? this._partDescriptionByProduct2Id[product2Id] ?? '';
        const returnable = match.isReturnable ?? this._resolveReturnableForProduct2(product2Id) ?? null;

        if (isAddForm) {
            this.addFormState = {
                ...this.addFormState,
                partsSource: PARTS_SOURCE_CUSTOMER,
                product2Id,
                productItemId: null,
                productCode,
                partDescription,
                returnable,
                ...this._clearedComponentTagFields(),
                allowedUnit: null,
                billingType: '',
                removedPartId: null
            };
            this._evaluateAllowedUnitForProduct(product2Id, { isAddForm: true });
            this._evaluateBillingType({ product2Id, isAddForm: true });
            this._toast('Product selected', match.productName || productCode || product2Id, 'success');
            return;
        }

        if (editId) {
            this._stageEdit(editId, 'partsSource', PARTS_SOURCE_CUSTOMER);
            this._stageEdit(editId, 'product2Id', product2Id);
            this._stageEdit(editId, 'productItemId', null);
            this._stageEdit(editId, 'productCode', productCode);
            this._stageEdit(editId, 'partDescription', partDescription);
            this._stageEdit(editId, 'returnable', returnable);
            this._stageEdit(editId, 'removedPartId', null);
            this._stageEdit(editId, 'allowedUnit', null);
            this._stageEdit(editId, 'billingType', '');
            this._clearComponentTagForEdit(editId);
            this._evaluateAllowedUnitForProduct(product2Id, { editId });
            this._evaluateBillingType({ product2Id, editId });
            this._toast('Product selected', match.productName || productCode || product2Id, 'success');
        }
    }

    /**
     * @description Internal helper: Compute Total Price.
     */
    _computeTotalPrice(unitPrice, quantity) {
        return (Number(unitPrice) || 0) * (Number(quantity) || 0);
    }

    /**
     * @description Expense Amount for display and save: Quantity × Unit Price.
     * @param {object} state Add or edit expense state
     * @return {number}
     */
    _computeExpenseAmount(state = {}) {
        return this._computeTotalPrice(state.unitPrice, state.quantity);
    }

    /**
     * @description Recalculates Total Price and synced Billable Amount from Quantity × Unit Price.
     * @param {object} state Add or edit expense state
     * @return {object}
     */
    _applyExpenseAmountToState(state = {}) {
        const qty = Number(state.quantity);
        if (!qty || qty <= 0) {
            const next = { ...state, totalPrice: null };
            if (!this._isTruthyFlag(next.overrideBillableAmount)) {
                next.billableAmount = next.totalPrice;
            }
            return next;
        }
        const amount = this._computeExpenseAmount(state);
        const next = {
            ...state,
            totalPrice: amount
        };
        if (!this._isTruthyFlag(next.overrideBillableAmount)) {
            next.billableAmount = amount;
        }
        return next;
    }

    /**
     * @description Copies Total Price into Billable Amount unless Override is selected.
     */
    _applyExpenseBillableSync(state, changedField) {
        const next = { ...state };
        if (changedField === 'overrideBillableAmount') {
            next.overrideBillableAmount = this._isTruthyFlag(next.overrideBillableAmount);
        }
        const override = this._isTruthyFlag(next.overrideBillableAmount);
        if (changedField === 'overrideBillableAmount' && !override) {
            next.billableAmount = this._computeExpenseAmount(next);
        }
        return next;
    }

    /**
     * @description Resolves Billable Amount, Override, and Override Code for save.
     */
    _expenseBillableSaveValues({
        billableAmount,
        overrideBillableAmount,
        overrideCode,
        quantity,
        unitPrice,
        expenseType,
        totalPrice
    }) {
        const override = this._isTruthyFlag(overrideBillableAmount);
        const amount = this._computeExpenseAmount({
            quantity,
            unitPrice,
            expenseType,
            totalPrice
        });
        const resolvedBillable = override ? Number(billableAmount) : amount;
        return {
            billableAmount: Number.isNaN(resolvedBillable) ? amount : resolvedBillable,
            overrideBillableAmount: override,
            overrideCode: overrideCode || ''
        };
    }

    /**
     * @description True for boolean true or the string "true".
     */
    _isTruthyFlag(value) {
        return value === true || value === 'true';
    }

    /**
     * @description Shows the returnable part notice; resolves when the user clicks OK.
     */
    async _showReturnablePartAlert() {
        await LightningAlert.open({
            message: RETURNABLE_PART_ALERT_MESSAGE,
            theme: 'info',
            label: 'Returnable Part'
        });
    }

    /**
     * @description True when a pending Parts edit changes the part to a returnable part.
     * @return {boolean}
     */
    _hasReturnablePartChange() {
        return Object.entries(this._pendingEdits).some(([id, edit]) => {
            if (edit._schema !== 'parts' || !this._isTruthyFlag(edit.returnable)) return false;
            const original = this._serverLines.find(l => l.Id === id);
            const productItemChanged = !!edit.productItemId
                && edit.productItemId !== (original?.ProductItem__c?.value ?? null);
            const productChanged = !!edit.product2Id
                && edit.product2Id !== (original?.Product__c?.value ?? null);
            return productItemChanged || productChanged;
        });
    }

    /**
     * @description Local calendar date (YYYY-MM-DD) for Expense.TransactionDate.
     * @return {string}
     */
    _todayDateString() {
        const now = new Date();
        const month = String(now.getMonth() + 1).padStart(2, '0');
        const day = String(now.getDate()).padStart(2, '0');
        return `${now.getFullYear()}-${month}-${day}`;
    }

    /**
     * @description Builds Travel Type combobox options from populated Rate List fields (GW-2967).
     * @return {{label: string, value: string}[]}
     */
    _buildTravelTypeOptionsFromRateList() {
        const options = [];
        const rl = this.rateList;
        if (!rl) {
            return options;
        }
        // Actual Travel first — default selection when Travel Hour is on the Rate List.
        if (this._isPopulatedRateAmount(rl.travelHour)) {
            options.push({ label: TRAVEL_TYPE_ACTUAL, value: TRAVEL_TYPE_ACTUAL });
        }
        const zones = [
            { label: 'Travel Zone 1', value: 'Travel Zone 1', amount: rl.travelZone1 },
            { label: 'Travel Zone 2', value: 'Travel Zone 2', amount: rl.travelZone2 },
            { label: 'Travel Zone 3', value: 'Travel Zone 3', amount: rl.travelZone3 },
            { label: 'Travel Zone 4', value: 'Travel Zone 4', amount: rl.travelZone4 }
        ];
        for (const zone of zones) {
            if (this._isPopulatedRateAmount(zone.amount)) {
                options.push({ label: zone.label, value: zone.value });
            }
        }
        return options;
    }

    /**
     * @description Builds labor Rate options from populated Rate List fields.
     * @return {{label: string, value: string}[]}
     */
    _buildLaborRateOptionsFromRateList() {
        const rl = this.rateList;
        if (!rl) {
            return [];
        }

        const options = [];
        if (this._isPopulatedRateAmount(rl.laborHour)) {
            options.push({ label: 'Standard', value: 'Standard' });
        }
        if (this._isPopulatedRateAmount(rl.premiumRateHour)) {
            options.push({ label: 'Premium', value: 'Premium' });
        }
        if (this._isPopulatedRateAmount(rl.extendedOvertimeRatePerHour)) {
            options.push({ label: 'Overtime', value: 'Overtime' });
        }
        return options;
    }

    /**
     * @description Default Travel Type is always Actual Travel when available on the Rate List.
     * @return {string}
     */
    _defaultTravelType() {
        if (this._isPopulatedRateAmount(this.rateList?.travelHour)) {
            return TRAVEL_TYPE_ACTUAL;
        }
        return this._buildTravelTypeOptionsFromRateList()[0]?.value ?? '';
    }

    /**
     * @description Returns valid Rate options for the given line type.
     * @param {string} lineType Time line type
     * @return {{label: string, value: string}[]}
     */
    _rateOptionsForLineType(lineType) {
        return lineType === 'Labor' ? this._buildLaborRateOptionsFromRateList() : RATE_OPTIONS;
    }

    /**
     * @description Default Rate value (Standard when available).
     * @param {string} lineType Time line type
     * @return {string}
     */
    _defaultRate(lineType) {
        const options = this._rateOptionsForLineType(lineType);
        if (options.some((option) => option.value === RATE_STANDARD)) {
            return RATE_STANDARD;
        }
        return options[0]?.value ?? RATE_STANDARD;
    }

    /**
     * @description True when Rate List currency/number field is populated (not blank).
     * @param {Decimal|number|null|undefined} amount
     * @return {boolean}
     */
    _isPopulatedRateAmount(amount) {
        return amount !== null && amount !== undefined && amount !== '';
    }

    /**
     * @description Syncs start/duration/end on an edit line after one of them changes.
     * @param {string} id Line Id
     * @param {string} changedField Field that changed
     */
    _syncTimeFieldsOnEdit(id, changedField) {
        const pending = this._pendingEdits[id] || this._pendingAdds.find((a) => a._tempId === id);
        if (!pending) {
            return;
        }
        const synced = this._syncTimeFieldsOnState({ ...pending }, changedField);
        if (this._pendingAdds.some((a) => a._tempId === id)) {
            this._pendingAdds = this._pendingAdds.map((a) => (a._tempId === id ? { ...a, ...synced } : a));
            return;
        }
        this._pendingEdits = { ...this._pendingEdits, [id]: { ...pending, ...synced } };
    }

    /**
     * @description Syncs start/duration/end on a state object.
     * @param {object} state Form/edit state
     * @param {string} changedField Field that changed
     * @return {object}
     */
    _syncTimeFieldsOnState(state, changedField) {
        const next = { ...state };
        if (changedField === 'durationHours' || changedField === 'startDate') {
            const hours = Number(next.durationHours);
            if (next.startDate && !Number.isNaN(hours) && hours > 0) {
                next.endDate = this._addHoursToDatetime(next.startDate, hours);
            }
        } else if (changedField === 'endDate') {
            const hours = this._computeDurationHours(next.startDate, next.endDate);
            if (hours != null) {
                next.durationHours = hours;
            }
        }
        return next;
    }

    /**
     * @description Adds hours to an ISO datetime string.
     * @param {string} startDate ISO datetime
     * @param {number} hours Duration hours
     * @return {string}
     */
    _addHoursToDatetime(startDate, hours) {
        const startMs = new Date(startDate).getTime();
        if (Number.isNaN(startMs)) {
            return startDate;
        }
        return new Date(startMs + (hours * 60 * 60 * 1000)).toISOString();
    }

    /**
     * @description Applies travel pricing onto a pending edit/add by Id.
     * @param {string} id Line Id
     */
    _applyTravelPricingToEdit(id) {
        const add = this._pendingAdds.find((a) => a._tempId === id);
        if (add) {
            const priced = this._applyTravelPricingToState({ ...add });
            this._pendingAdds = this._pendingAdds.map((a) => (a._tempId === id ? priced : a));
            return;
        }
        const pending = this._pendingEdits[id];
        if (!pending) {
            return;
        }
        this._pendingEdits = {
            ...this._pendingEdits,
            [id]: this._applyTravelPricingToState({ ...pending })
        };
    }

    /**
     * @description Applies labor pricing to a pending add or edit line.
     * @param {string} id Line Id
     */
    _applyLaborPricingToEdit(id) {
        const add = this._pendingAdds.find((a) => a._tempId === id);
        if (add) {
            const priced = this._applyLaborPricingToState({ ...add });
            this._pendingAdds = this._pendingAdds.map((a) => (a._tempId === id ? priced : a));
            return;
        }
        const pending = this._pendingEdits[id];
        if (!pending) {
            return;
        }
        this._pendingEdits = {
            ...this._pendingEdits,
            [id]: this._applyLaborPricingToState({ ...pending })
        };
    }

    /**
     * @description Applies Rate List travel pricing onto a state object (GW-2967).
     * @param {object} state Form/edit state
     * @return {object}
     */
    _applyTravelPricingToState(state) {
        if (state.lineType !== 'Travel' && state._lineType !== 'Travel' && state._schema !== 'travel') {
            return state;
        }
        const pricing = this._computeTravelPricing(state);
        return {
            ...state,
            listPrice: pricing.listPrice,
            unitPrice: pricing.unitPrice,
            quantity: pricing.quantity,
            totalPrice: pricing.totalPrice
        };
    }

    /**
     * @description Applies labor pricing fields to line state.
     * @param {object} state Line state
     * @return {object}
     */
    _applyLaborPricingToState(state) {
        if (state?.lineType !== 'Labor' && state?._lineType !== 'Labor' && state?._schema !== 'labor') {
            return state;
        }

        const pricing = this._computeLaborPricing(state);
        return {
            ...state,
            listPrice: pricing.listPrice,
            unitPrice: pricing.unitPrice,
            quantity: pricing.quantity,
            totalPrice: pricing.totalPrice
        };
    }

    /**
     * @description Computes list/unit/qty/total for a travel line from Rate List.
     * @param {object} state Travel line state
     * @return {{listPrice: number|null, unitPrice: number|null, quantity: number|null, totalPrice: number|null}}
     */
    _computeTravelPricing(state) {
        const empty = { listPrice: null, unitPrice: null, quantity: null, totalPrice: null };
        const rl = this.rateList;
        const travelType = state.travelType;
        if (!rl || !travelType) {
            return empty;
        }

        const zoneField = TRAVEL_ZONE_FIELD_BY_TYPE[travelType];
        if (zoneField) {
            const zonePrice = rl[zoneField];
            if (!this._isPopulatedRateAmount(zonePrice)) {
                return empty;
            }
            const amount = Number(zonePrice);
            return {
                listPrice: amount,
                unitPrice: amount,
                quantity: 1,
                totalPrice: amount
            };
        }

        if (travelType !== TRAVEL_TYPE_ACTUAL) {
            return empty;
        }

        let hourly = null;
        if (state.rate === 'Standard') {
            hourly = rl.travelHour;
        } else if (state.rate === 'Premium') {
            hourly = rl.premiumRateHour;
        } else if (state.rate === 'Overtime') {
            hourly = rl.extendedOvertimeRatePerHour;
        }
        if (!this._isPopulatedRateAmount(hourly)) {
            return empty;
        }

        const duration = state.durationHours != null && state.durationHours !== ''
            ? Number(state.durationHours)
            : this._computeDurationHours(state.startDate, state.endDate);
        const unit = Number(hourly);
        const qty = duration != null && !Number.isNaN(duration) ? duration : null;
        return {
            listPrice: unit,
            unitPrice: unit,
            quantity: qty,
            totalPrice: qty != null ? unit * qty : null
        };
    }

    /**
     * @description Computes labor list/unit/qty/total from selected Rate and duration.
     * @param {object} state Labor line state
     * @return {{listPrice: number|null, unitPrice: number|null, quantity: number|null, totalPrice: number|null}}
     */
    _computeLaborPricing(state) {
        const empty = { listPrice: null, unitPrice: null, quantity: null, totalPrice: null };
        const unit = this._resolveLaborRateAmount(state?.rate);
        if (unit == null) {
            return empty;
        }

        const quantity = state.durationHours != null && state.durationHours !== ''
            ? Number(state.durationHours)
            : this._computeDurationHours(state?.startDate, state?.endDate);
        const qty = quantity != null && !Number.isNaN(quantity) ? quantity : null;
        return {
            listPrice: unit,
            unitPrice: unit,
            quantity: qty,
            totalPrice: qty != null ? unit * qty : null
        };
    }

    /**
     * @description Builds WOLI price fields for travel create/update.
     * @param {object} state Travel line state
     * @return {object}
     */
    _buildTravelPriceSaveFields(state) {
        const pricing = this._computeTravelPricing(state);
        const fields = {};
        if (pricing.listPrice != null) {
            fields[WOLI_LIST_PRICE_CUSTOM.fieldApiName] = pricing.listPrice;
        }
        if (pricing.unitPrice != null) {
            fields[WOLI_UNIT_PRICE_CUSTOM.fieldApiName] = pricing.unitPrice;
        }
        if (pricing.totalPrice != null) {
            fields[WOLI_TOTAL_PRICE_CUSTOM.fieldApiName] = pricing.totalPrice;
        }
        if (pricing.quantity != null) {
            fields[WOLI_UNIT_QTY.fieldApiName] = pricing.quantity;
        }
        return fields;
    }

    /**
     * @description Resolves the selected labor Rate to the Rate List amount.
     * @param {string} rate Selected Rate
     * @return {number|null}
     */
    _resolveLaborRateAmount(rate) {
        const rl = this.rateList;
        if (!rl || !rate) {
            return null;
        }
        if (rate === 'Standard') {
            return this._isPopulatedRateAmount(rl.laborHour) ? Number(rl.laborHour) : null;
        }
        if (rate === 'Premium') {
            return this._isPopulatedRateAmount(rl.premiumRateHour) ? Number(rl.premiumRateHour) : null;
        }
        if (rate === 'Overtime') {
            return this._isPopulatedRateAmount(rl.extendedOvertimeRatePerHour)
                ? Number(rl.extendedOvertimeRatePerHour)
                : null;
        }
        return null;
    }

    /**
     * @description Builds pricing fields for saving Labor Work Order Line Items.
     * @param {object} state Labor line state
     * @return {object}
     */
    _laborPricingFieldsForSave(state) {
        const pricing = this._computeLaborPricing(state);
        const fields = {};
        if (pricing.listPrice != null) {
            fields[WOLI_LIST_PRICE_CUSTOM.fieldApiName] = pricing.listPrice;
        }
        if (pricing.unitPrice != null) {
            fields[WOLI_UNIT_PRICE_CUSTOM.fieldApiName] = pricing.unitPrice;
        }
        if (pricing.totalPrice != null) {
            fields[WOLI_TOTAL_PRICE_CUSTOM.fieldApiName] = pricing.totalPrice;
        }
        if (pricing.quantity != null) {
            fields[WOLI_UNIT_QTY.fieldApiName] = pricing.quantity;
        }
        return fields;
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
     * @description Internal helper: Build Duration Fields.
     */
    _buildDurationFields(startDate, endDate, durationHours) {
        const duration = durationHours != null && durationHours !== '' && !Number.isNaN(Number(durationHours))
            ? Number(durationHours)
            : this._computeDurationHours(startDate, endDate);
        if (duration == null) return {};
        return { [WOLI_DURATION.fieldApiName]: duration, DurationType: 'Hours' };
    }

    /**
     * @description Internal helper: Work Order Currency.
     */
    _workOrderCurrency() { return this._workOrder?.CurrencyIsoCode?.value ?? 'USD'; }
    /**
     * @description Internal helper: Record Id.
     */
    _recordId(record) {
        const raw = record?.Id ?? record?.id ?? null;
        if (raw == null) return null;
        if (typeof raw === 'object') return raw.value ?? raw.id ?? null;
        return raw;
    }

    /**
     * @description 15-character Id key so 15- and 18-character Salesforce Ids match.
     * @param {string|object|null} id Record Id
     * @return {string|null}
     */
    _idKey(id) {
        const value = this._recordId({ Id: id });
        return value ? String(value).substring(0, 15) : null;
    }

    /**
     * @description Ensures Expense.Id is a string Salesforce Id.
     * @param {object} record Expense record
     * @return {object}
     */
    _normalizeExpenseRecord(record) {
        if (!record) return record;
        const id = this._recordId(record);
        return id ? { ...record, Id: id } : record;
    }

    /**
     * @description Internal helper: Rebuild Server Parts Consumed.
     */
    _rebuildServerPartsConsumed() {
        const byId = new Map();
        const richness = (p) => {
            let score = 0;
            if (p.ProductItem?.ProductName?.value) score += 4;
            if (p.Product2?.Name?.value) score += 2;
            if (p.ProductItemId?.value) score += 1;
            return score;
        };
        for (const p of [...this._serverPartsFromRelatedList, ...this._serverPartsFromGraphql]) {
            if (!p?.Id) continue;
            const prev = byId.get(p.Id);
            if (!prev || richness(p) >= richness(prev)) byId.set(p.Id, p);
        }
        this._serverPartsConsumed = [...byId.values()];
    }

    /**
     * @description Internal helper: Rebuild Server Products Required.
     */
    _rebuildServerProductsRequired() {
        const byId = new Map();
        const richness = (p) => {
            let score = 0;
            if (p.Product2?.Name?.value) score += 2;
            if (p.QuantityRequired?.value != null) score += 1;
            if (p.Returnable__c?.value != null && p.Returnable__c?.value !== '') score += 1;
            return score;
        };
        for (const p of [...this._serverRequiredFromRelatedList, ...this._serverRequiredFromGraphql]) {
            const id = this._recordId(p);
            if (!id) continue;
            const normalized = { ...p, Id: id };
            const prev = byId.get(id);
            if (!prev || richness(normalized) >= richness(prev)) byId.set(id, normalized);
        }
        this._serverProductsRequired = [...byId.values()];
    }

    /**
     * @description Internal helper: Rebuild Server Expenses.
     */
    _rebuildServerExpenses() {
        const byId = new Map();
        for (const e of [...this._serverExpensesFromRelatedList, ...this._serverExpensesFromGraphql]) {
            const normalized = this._normalizeExpenseRecord(e);
            const key = this._idKey(normalized?.Id);
            if (!key) continue;
            byId.set(key, this._mergeExpenseBillableFields(byId.get(key), normalized));
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
                const key = this._idKey(row.id);
                if (key) {
                    next[key] = row;
                }
            }
            this._expenseBillableById = { ...this._expenseBillableById, ...next };
            this._rebuildServerExpenses();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('woDebriefES listExpenseBillableFields failed', e);
        }
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
        const key = this._idKey(id);
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
     * @description Internal helper: Normalize Part From Lds.
     */
    _normalizePartFromLds(record) {
        const f = record.fields ?? {};
        const val = (api) => f[api]?.value ?? null;
        return {
            Id: record.id,
            QuantityConsumed: { value: val('QuantityConsumed') },
            Description: { value: val('Description') ?? '' },
            ProductItemId: { value: val('ProductItemId') },
            Product2Id: { value: val('Product2Id') },
            Returnable__c: { value: val('Returnable__c') },
            ServiceResource__c: { value: val('ServiceResource__c') ?? val('Service_Resource__c') },
            WorkOrderLineItemId: { value: val('WorkOrderLineItemId') }
        };
    }

    /**
     * @description Internal helper: Normalize Required From Lds.
     */
    _normalizeRequiredFromLds(record) {
        const f = record.fields ?? {};
        const val = (api) => f[api]?.value ?? null;
        const product2Name = f.Product2?.value?.fields?.Name?.value ?? null;
        return {
            Id: record.id,
            Product2Id: { value: val('Product2Id') },
            QuantityRequired: { value: val('QuantityRequired') },
            Returnable__c: { value: val('Returnable__c') ?? '' },
            ...(product2Name != null ? { Product2: { Name: { value: product2Name } } } : {})
        };
    }

    /**
     * @description Internal helper: Normalize Expense From Lds.
     */
    _normalizeExpenseFromLds(record) {
        const f = record.fields ?? {};
        const val = (api) => f[api]?.value ?? null;
        return {
            Id: record.id,
            ExpenseType: { value: val('ExpenseType') ?? '' },
            Description: { value: val('Description') ?? '' },
            Quantity: { value: val('Quantity') },
            UnitPrice: { value: val('UnitPrice') },
            TotalPrice: { value: val('TotalPrice') },
            Amount: { value: val('Amount') },
            TransactionDate: { value: val('TransactionDate') ?? '' },
            OverrideCode__c: { value: val('OverrideCode__c') ?? '' },
            BillableAmount__c: { value: val('BillableAmount__c') },
            OverrideBillableAmount__c: { value: val('OverrideBillableAmount__c') === true }
        };
    }

    /**
     * @description Internal helper: Seed Repair Code Cache.
     */
    _seedRepairCodeCache(lines) {
        const nextName = { ...this._repairCodeNameById };
        const nextCode = { ...this._repairCodeProductCodeById };
        const nextDesc = { ...this._repairCodeDescriptionById };
        let changed = false;
        for (const l of lines) {
            const id = l.RepairCode__c?.value;
            if (!id) continue;
            const name = l.RepairCode__r?.Name?.value;
            const productCode = l.RepairCode__r?.ProductCode?.value;
            const description = l.RepairCode__r?.Description?.value;
            if (name && nextName[id] !== name) { nextName[id] = name; changed = true; }
            if (productCode != null && nextCode[id] !== productCode) { nextCode[id] = productCode; changed = true; }
            if (description != null && nextDesc[id] !== description) { nextDesc[id] = description; changed = true; }
        }
        if (changed) {
            this._repairCodeNameById = nextName;
            this._repairCodeProductCodeById = nextCode;
            this._repairCodeDescriptionById = nextDesc;
        }
    }

    /**
     * @description Internal helper: Cache Repair Code Details.
     */
    _cacheRepairCodeDetails(id, { name, productCode, description }) {
        if (!id) return;
        if (name) {
            this._repairCodeNameById = { ...this._repairCodeNameById, [id]: name };
        }
        if (productCode != null) {
            this._repairCodeProductCodeById = { ...this._repairCodeProductCodeById, [id]: productCode };
        }
        if (description != null) {
            this._repairCodeDescriptionById = { ...this._repairCodeDescriptionById, [id]: description };
        }
    }

    /**
     * @description Internal helper: Resolve Product Code For Repair Code.
     */
    _resolveProductCodeForRepairCode(repairCodeId) {
        if (!repairCodeId) return null;
        return this._repairCodeProductCodeById[repairCodeId] ?? null;
    }

    /**
     * @description Internal helper: Resolve Product Description For Repair Code.
     */
    _resolveProductDescriptionForRepairCode(repairCodeId) {
        if (!repairCodeId) return null;
        return this._repairCodeDescriptionById[repairCodeId] ?? null;
    }

    /**
     * @description Internal helper: Sync Repair Code Details For Product.
     */
    _syncRepairCodeDetailsForProduct(repairCodeId, productCode, description) {
        this._pendingAdds = this._pendingAdds.map(a => (
            a._schema === 'labor' && a.repairCodeId === repairCodeId
                ? { ...a, productCode: productCode ?? a.productCode ?? '', productDescription: description ?? a.productDescription ?? '' }
                : a
        ));
        const edits = { ...this._pendingEdits };
        let changed = false;
        for (const [id, edit] of Object.entries(edits)) {
            if (edit._schema === 'labor' && edit.repairCodeId === repairCodeId) {
                edits[id] = {
                    ...edit,
                    productCode: productCode ?? edit.productCode ?? '',
                    productDescription: description ?? edit.productDescription ?? ''
                };
                changed = true;
            }
        }
        if (changed) this._pendingEdits = edits;
        if (this.addFormState.repairCodeId === repairCodeId) {
            this.addFormState = {
                ...this.addFormState,
                productCode: productCode ?? this.addFormState.productCode ?? '',
                productDescription: description ?? this.addFormState.productDescription ?? ''
            };
        }
    }

    /**
     * @description Internal helper: Resolve Labor Product Code.
     */
    _resolveLaborProductCode(repairCodeId, productCode) {
        return productCode ?? this._resolveProductCodeForRepairCode(repairCodeId) ?? '';
    }

    /**
     * @description Internal helper: Resolve Labor Product Description.
     */
    _resolveLaborProductDescription(repairCodeId, productDescription) {
        return productDescription ?? this._resolveProductDescriptionForRepairCode(repairCodeId) ?? '';
    }

    /**
     * @description Internal helper: Seed Returnable Cache From Parts.
     */
    _seedReturnableCacheFromParts(parts) {
        const next = { ...this._isReturnableByProductItemId };
        let changed = false;
        for (const p of parts) {
            const productItemId = p.ProductItemId?.value;
            const isReturnable = p.Product2?.IsReturnable__c?.value;
            if (productItemId && isReturnable !== undefined && isReturnable !== null && next[productItemId] !== isReturnable) {
                next[productItemId] = isReturnable;
                changed = true;
            }
        }
        if (changed) this._isReturnableByProductItemId = next;
    }

    /**
     * @description Internal helper: Seed Product Item Name Cache From Parts.
     */
    _seedProductItemNameCacheFromParts(parts) {
        const next = { ...this._productItemNameByProductItemId };
        let changed = false;
        for (const p of parts) {
            const productItemId = p.ProductItemId?.value;
            const name = p.ProductItem?.ProductName?.value ?? p.Product2?.Name?.value;
            if (productItemId && name && next[productItemId] !== name) {
                next[productItemId] = name;
                changed = true;
            }
        }
        if (changed) this._productItemNameByProductItemId = next;
    }

    /**
     * @description Loads refurbished-product choices for a line when they are not cached yet.
     */
    _ensureRemovedPartSourceForLine(lineId) {
        const line = this._serverLines.find(l => l.Id === lineId);
        const edit = this._pendingEdits[lineId];
        const add = this._pendingAdds.find(a => a._tempId === lineId);
        const productItemId = edit?.productItemId
            ?? add?.productItemId
            ?? line?.ProductItem__c?.value
            ?? null;
        const product2Id = edit?.product2Id
            ?? add?.product2Id
            ?? line?.Product__c?.value
            ?? (productItemId ? this._product2IdByProductItemId[productItemId] : null)
            ?? line?.ProductItem__r?.Product2?.Id
            ?? null;
        if (product2Id && !this._refurbishedByProduct2Id[product2Id]) {
            this._removedPartSourceProduct2Id = product2Id;
            return;
        }
        if (productItemId && !product2Id) {
            this._productItemLookupId = productItemId;
        }
    }

    /**
     * @description Internal helper: Seed Product Item Name Cache From Woli Lines.
     */
    _seedProductItemNameCacheFromWoliLines(lines) {
        for (const l of lines ?? []) {
            const productItemId = l.ProductItem__c?.value;
            if (productItemId && !this._productItemNameByProductItemId[productItemId]) {
                this._productItemLookupId = productItemId;
                break;
            }
        }
        this._seedProduct2CacheFromWoliLines(lines);
    }

    /**
     * @description Seeds Product2 detail lookups for Customer Stock WOLI lines.
     */
    _seedProduct2CacheFromWoliLines(lines) {
        for (const l of lines ?? []) {
            const product2Id = l.Product__c?.value;
            if (
                product2Id
                && (
                    !this._productNameByProduct2Id[product2Id]
                    || this._productCodeByProduct2Id[product2Id] == null
                )
            ) {
                this._product2LookupId = product2Id;
                break;
            }
        }
    }

    /**
     * @description Caches selected-product and refurbished-product names from Work Order lines.
     */
    _seedRemovedPartSourcesFromWoliLines(lines) {
        const refurbishedNext = { ...this._refurbishedByProduct2Id };
        const namesNext = { ...this._productNameByProduct2Id };
        const product2ByItemNext = { ...this._product2IdByProductItemId };
        let refurbishedChanged = false;
        let namesChanged = false;
        let itemsChanged = false;

        const absorbProduct = (product2Node) => {
            const product2Id = product2Node?.Id;
            if (!product2Id) return;
            const name = product2Node.Name?.value;
            if (name && namesNext[product2Id] !== name) {
                namesNext[product2Id] = name;
                namesChanged = true;
            }
            if (!product2Node.RefurbishedProduct__c) return;
            const refurbishedId = product2Node.RefurbishedProduct__c.value || null;
            const refurbishedName = product2Node.RefurbishedProduct__r?.Name?.value || null;
            const existing = refurbishedNext[product2Id];
            if (!existing || existing.id !== refurbishedId || existing.name !== refurbishedName) {
                refurbishedNext[product2Id] = { id: refurbishedId, name: refurbishedName };
                refurbishedChanged = true;
            }
        };

        for (const line of lines ?? []) {
            absorbProduct(line.Product__r);
            const productItem = line.ProductItem__r;
            absorbProduct(productItem?.Product2);
            const productItemId = line.ProductItem__c?.value ?? productItem?.Id;
            const product2Id = productItem?.Product2?.Id ?? productItem?.Product2Id?.value;
            if (productItemId && product2Id && product2ByItemNext[productItemId] !== product2Id) {
                product2ByItemNext[productItemId] = product2Id;
                itemsChanged = true;
            }
            const itemName = productItem?.ProductName?.value;
            if (product2Id && itemName && !namesNext[product2Id]) {
                namesNext[product2Id] = itemName;
                namesChanged = true;
            }
        }

        if (namesChanged) this._productNameByProduct2Id = namesNext;
        if (itemsChanged) this._product2IdByProductItemId = product2ByItemNext;
        if (refurbishedChanged) this._refurbishedByProduct2Id = refurbishedNext;
    }

    /**
     * @description Internal helper: Apply Local Create.
     */
    _applyLocalCreate(id, add) {
        if (add._entity === 'Expense') this._applyExpenseCreate(id, add);
        else if (add._entity === 'ProductConsumed') this._applyPartsConsumedCreate(id, add);
        else if (add._entity === 'ProductRequired') this._applyProductRequiredCreate(id, add);
    }

    /**
     * @description Internal helper: Apply Local Update.
     */
    _applyLocalUpdate(id, edit) {
        if (edit._entity === 'Expense') this._applyExpenseUpdate(id, edit);
        else if (edit._entity === 'ProductConsumed') this._applyPartsConsumedUpdate(id, edit);
        else if (edit._entity === 'ProductRequired') this._applyProductRequiredUpdate(id, edit);
    }

    /**
     * @description Internal helper: Build Server Expense.
     */
    _buildServerExpense(id, data) {
        return {
            Id: id,
            ExpenseType: { value: data.expenseType ?? '' },
            Description: { value: data.description ?? '' },
            Quantity: { value: data.quantity },
            UnitPrice: { value: data.unitPrice },
            TotalPrice: { value: data.totalPrice },
            Amount: { value: data.totalPrice },
            TransactionDate: { value: data.transactionDate ?? '' },
            OverrideCode__c: { value: data.overrideCode ?? '' },
            BillableAmount__c: { value: data.billableAmount },
            OverrideBillableAmount__c: { value: this._isTruthyFlag(data.overrideBillableAmount) }
        };
    }

    /**
     * @description Internal helper: Apply Expense Create.
     */
    _applyExpenseCreate(id, add) {
        const billable = this._expenseBillableSaveValues(add);
        this._rememberExpenseBillableFields(id, billable);
        this._upsertLocalExpense(this._buildServerExpense(id, {
            expenseType: add.expenseType,
            description: add.description,
            quantity: Number(add.quantity) || 0,
            unitPrice: Number(add.unitPrice) || 0,
            totalPrice: this._computeTotalPrice(add.unitPrice, add.quantity),
            transactionDate: add.transactionDate || this._todayDateString(),
            overrideCode: billable.overrideCode,
            billableAmount: billable.billableAmount,
            overrideBillableAmount: billable.overrideBillableAmount
        }));
    }

    /**
     * @description Internal helper: Apply Expense Update.
     */
    _applyExpenseUpdate(id, edit) {
        const billable = this._expenseBillableSaveValues(edit);
        this._rememberExpenseBillableFields(id, billable);
        this._upsertLocalExpense(this._buildServerExpense(id, {
            expenseType: edit.expenseType,
            description: edit.description,
            quantity: Number(edit.quantity) || 0,
            unitPrice: Number(edit.unitPrice) || 0,
            totalPrice: this._computeTotalPrice(edit.unitPrice, edit.quantity),
            transactionDate: edit.transactionDate || this._todayDateString(),
            overrideCode: billable.overrideCode,
            billableAmount: billable.billableAmount,
            overrideBillableAmount: billable.overrideBillableAmount
        }));
    }

    /**
     * @description Internal helper: Apply Expense Delete.
     */
    _applyExpenseDelete(id) {
        const key = this._idKey(id);
        const nextBillable = { ...this._expenseBillableById };
        delete nextBillable[key];
        this._expenseBillableById = nextBillable;
        this._serverExpensesFromGraphql = this._serverExpensesFromGraphql.filter(e => this._idKey(e.Id) !== key);
        this._serverExpensesFromRelatedList = this._serverExpensesFromRelatedList.filter(e => this._idKey(e.Id) !== key);
        this._rebuildServerExpenses();
    }

    /**
     * @description Internal helper: Upsert Local Expense.
     */
    _upsertLocalExpense(expense) {
        const normalized = this._normalizeExpenseRecord(expense);
        const key = this._idKey(normalized?.Id);
        this._serverExpensesFromRelatedList = [
            ...this._serverExpensesFromRelatedList.filter(e => this._idKey(e.Id) !== key),
            normalized
        ];
        this._rebuildServerExpenses();
    }

    /**
     * @description Internal helper: Build Server Part.
     */
    _buildServerPart(id, data) {
        const productItemId = data.productItemId ?? null;
        const product2Id = data.product2Id ?? this._product2IdByProductItemId[productItemId] ?? null;
        const productName = this._productItemNameByProductItemId[productItemId] ?? null;
        return {
            Id: id,
            QuantityConsumed: { value: data.quantityConsumed },
            Description: { value: data.description ?? '' },
            ProductItemId: { value: productItemId },
            Product2Id: { value: product2Id },
            Returnable__c: { value: data.returnable ?? null },
            ServiceResource__c: { value: data.assignedResourceId ?? null },
            WorkOrderLineItemId: { value: data.workOrderLineItemId ?? null },
            ...(data.partsSource != null && data.workOrderLineItemId
                ? { WorkOrderLineItem: { PartsSource__c: { value: data.partsSource } } }
                : {}),
            ...(productName ? { ProductItem: { ProductName: { value: productName } } } : {})
        };
    }

    /**
     * @description Internal helper: Apply Parts Consumed Create.
     */
    _applyPartsConsumedCreate(id, add) {
        this._upsertLocalPart(this._buildServerPart(id, add));
    }

    /**
     * @description Internal helper: Apply Parts Consumed Update.
     */
    _applyPartsConsumedUpdate(id, edit) {
        this._upsertLocalPart(this._buildServerPart(id, edit));
    }

    /**
     * @description Internal helper: Apply Parts Consumed Delete.
     */
    _applyPartsConsumedDelete(id) {
        this._serverPartsFromGraphql = this._serverPartsFromGraphql.filter(p => p.Id !== id);
        this._serverPartsFromRelatedList = this._serverPartsFromRelatedList.filter(p => p.Id !== id);
        this._rebuildServerPartsConsumed();
    }

    /**
     * @description Internal helper: Upsert Local Part.
     */
    _upsertLocalPart(part) {
        this._serverPartsFromGraphql = [
            ...this._serverPartsFromGraphql.filter(p => p.Id !== part.Id),
            part
        ];
        this._rebuildServerPartsConsumed();
    }

    /**
     * @description Internal helper: Build Server Required.
     */
    _buildServerRequired(id, data) {
        return {
            Id: id,
            Product2Id: { value: data.product2Id },
            QuantityRequired: { value: data.quantityRequired },
            Returnable__c: { value: data.returnable ?? '' }
        };
    }

    /**
     * @description Internal helper: Apply Product Required Create.
     */
    _applyProductRequiredCreate(id, add) {
        this._upsertLocalRequired(this._buildServerRequired(id, add));
    }

    /**
     * @description Internal helper: Apply Product Required Update.
     */
    _applyProductRequiredUpdate(id, edit) {
        this._upsertLocalRequired(this._buildServerRequired(id, edit));
    }

    /**
     * @description Internal helper: Apply Product Required Delete.
     */
    _applyProductRequiredDelete(id) {
        this._serverRequiredFromGraphql = this._serverRequiredFromGraphql.filter(p => p.Id !== id);
        this._serverRequiredFromRelatedList = this._serverRequiredFromRelatedList.filter(p => p.Id !== id);
        this._rebuildServerProductsRequired();
    }

    /**
     * @description Internal helper: Upsert Local Required.
     */
    _upsertLocalRequired(required) {
        this._serverRequiredFromRelatedList = [
            ...this._serverRequiredFromRelatedList.filter(p => p.Id !== required.Id),
            required
        ];
        this._rebuildServerProductsRequired();
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
            try { body = JSON.parse(body); } catch (e) { return body; }
        }
        if (body?.message) return body.message;
        const pageErrors = body?.pageErrors;
        if (Array.isArray(pageErrors) && pageErrors.length) {
            return pageErrors.map(e => e.message).filter(Boolean).join(' ');
        }
        const fieldErrors = body?.fieldErrors;
        if (fieldErrors && typeof fieldErrors === 'object') {
            const msgs = Object.values(fieldErrors).flat().map(e => e?.message).filter(Boolean);
            if (msgs.length) return msgs.join(' ');
        }
        return err.message ?? null;
    }

    /**
     * @description Internal helper: Fmt Parts Meta.
     */
    _fmtPartsMeta(qty, desc, returnableLabel, partsSource) {
        const parts = [`Qty ${qty}`];
        const sourceLabel = this._partsSourceLabel(partsSource);
        if (sourceLabel) parts.push(sourceLabel);
        if (returnableLabel) parts.push(`Returnable: ${returnableLabel}`);
        if (desc) parts.push(desc);
        return parts.join(' · ');
    }

    /**
     * @description Label for a PartsSource__c API value.
     */
    _partsSourceLabel(value) {
        if (!value) return '';
        const apiValue = normalizePartsSource(value);
        return this.partsSourceOptions.find(option => option.value === apiValue)?.label ?? apiValue;
    }

    /**
     * @description Debrief Parts Source options: Trunk, Customer Part, On Order, Inventory Issue.
     * @param {Array} values getPicklistValues values
     * @return {Array<{label: String, value: String}>}
     */
    _debriefPartsSourceOptions(values) {
        const seen = new Set();
        const options = [];
        for (const entry of values ?? []) {
            const apiValue = normalizePartsSource(entry.value);
            if (!PARTS_SOURCE_ALLOWED.has(apiValue) || seen.has(apiValue)) {
                continue;
            }
            seen.add(apiValue);
            const fallback = PARTS_SOURCE_OPTIONS.find(option => option.value === apiValue);
            options.push({
                label: fallback?.label ?? entry.label,
                value: apiValue
            });
        }
        return sortPartsSourceOptions(options);
    }

    /**
     * @description Internal helper: Fmt Parts Woli Meta.
     */
    _fmtPartsWoliMeta(qty, desc, usagesException, returnableLabel, billingTypeLabel) {
        const parts = [`Unit Qty ${qty ?? ''}`];
        if (returnableLabel) parts.push(`Returnable: ${returnableLabel}`);
        if (usagesException) parts.push("Usage's Exception");
        if (billingTypeLabel) parts.push(`Billing Type: ${billingTypeLabel}`);
        if (desc) parts.push(desc);
        return parts.join(' · ');
    }

    /**
     * @description Display label for WorkOrderLineItem.BillingType__c.
     * @param {String} value Picklist API value
     * @return {String} Label or empty string
     */
    _fmtBillingType(value) {
        if (value == null || value === '') {
            return '';
        }
        return BILLING_TYPE_LABELS[value] || value;
    }

    /**
     * @description Internal helper: Fmt Required Meta.
     */
    _fmtRequiredMeta(qty, returnable) {
        const parts = [`Qty ${qty}`];
        const returnableLabel = this._fmtReturnable(returnable);
        if (returnableLabel) parts.push(`Returnable: ${returnableLabel}`);
        return parts.join(' · ');
    }

    /**
     * @description Internal helper: Fmt Expense Meta.
     */
    _fmtExpenseMeta(description, quantity, unitPrice, totalPrice) {
        const parts = [];
        if (description) parts.push(description);
        parts.push(`${quantity} × $${this._fmtMoney(unitPrice)} = $${totalPrice}`);
        return parts.join(' · ') || 'Expense';
    }

    /**
     * @description Internal helper: Fmt Travel Meta.
     */
    _fmtTravelMeta(startDate, endDate) { return this._fmtDateRange(startDate, endDate); }
    /**
     * @description Internal helper: Fmt Time Meta.
     */
    _fmtTimeMeta(lineType, startDate, endDate, rate, travelType, repairCode = '') {
        const parts = [];
        if (lineType) parts.push(lineType);
        if (repairCode) parts.push(repairCode);
        if (rate) parts.push(rate);
        if (travelType) parts.push(travelType);
        const range = this._fmtDateRange(startDate, endDate);
        if (range) parts.push(range);
        return parts.join(' · ');
    }

    /**
     * @description Internal helper: Fmt Labor Meta.
     */
    _fmtLaborMeta(repairCode, startDate, endDate) {
        const parts = [];
        if (repairCode) parts.push(repairCode);
        const range = this._fmtDateRange(startDate, endDate);
        if (range) parts.push(range);
        return parts.join(' · ');
    }

    /**
     * @description Internal helper: Fmt Calibration Meta.
     */
    _fmtCalibrationMeta(assetSerial) {
        return assetSerial ? `SN ${assetSerial}` : '';
    }

    /**
     * @description Internal helper: Fmt Date Range.
     */
    _fmtDateRange(startDate, endDate) {
        const s = this._fmtDateTime(startDate);
        const e = this._fmtDateTime(endDate);
        if (s && e) return `${s} → ${e}`;
        if (s) return s;
        if (e) return `→ ${e}`;
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
     * @description Internal helper: Fmt Money.
     */
    _fmtMoney(n) {
        const num = Number(n);
        if (!Number.isFinite(num)) return '0.00';
        return num.toFixed(2);
    }

    /**
     * @description Internal helper: Format money only when populated.
     */
    _fmtOptionalMoney(n) {
        return n === null || n === undefined || n === '' ? '' : this._fmtMoney(n);
    }

    /**
     * @description Internal helper: To Ms.
     */
    _toMs(iso) {
        if (!iso) return null;
        const t = new Date(iso).getTime();
        return Number.isNaN(t) ? null : t;
    }

    /**
     * @description Internal helper: Toast.
     */
    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}