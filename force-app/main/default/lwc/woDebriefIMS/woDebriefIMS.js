/**
 * @description Work Order debrief LWC (woDebriefIMS) for Field Service technicians.
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
import LightningAlert            from 'lightning/alert';
import { CloseActionScreenEvent } from 'lightning/actions';
import USER_ID from '@salesforce/user/Id';
import getUsageConsumptionRecordTypeId from '@salesforce/apex/WoDebriefProductItemController.getUsageConsumptionRecordTypeId';
import assignSelectedTruck from '@salesforce/apex/WoDebriefIMSController.assignSelectedTruck';
import checkSiteVisitReview from '@salesforce/apex/WoDebriefIMSController.checkSiteVisitReview';
import saveExpense from '@salesforce/apex/WoDebriefRegionalExpenseController.saveExpense';
import listExpenseBillableFields from '@salesforce/apex/WoDebriefRegionalExpenseController.listExpenseBillableFields';

import WORK_ORDER_OBJECT from '@salesforce/schema/WorkOrder';
import SERVICE_LOCATION_FIELD from '@salesforce/schema/WorkOrder.ServiceLocation__c';
import SERVICE_LOCATION_TYPE_FIELD from '@salesforce/schema/WorkOrder.ServiceLocationType__c';
import WO_LOCATION_FIELD from '@salesforce/schema/WorkOrder.LocationId';
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
import WOLI_RECORDTYPE from '@salesforce/schema/WorkOrderLineItem.RecordTypeId';
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
                            ParentWorkOrderId {
                                value
                                displayValue
                            }
                            ParentWorkOrder {
                                WorkOrderNumber { value }
                            }
                            Status { value }
                            Account {
                                Name { value }
                            }
                            Asset {
                                Name { value }
                                SerialNumber { value }
                            }
                            WorkOrderType__c { value }
                            TotalTrays__c { value }
                            TotalServicedTrays__c { value }
                            CurrencyIsoCode { value }
                            ServiceLocation__c {
                                value
                                displayValue
                            }
                            ServiceTerritoryId { value }
                            ServiceTerritory {
                                Name { value }
                            }
                            ServiceLocationType__c { value }
                            LocationId { value }
                            Location {
                                Id
                                Name { value }
                                LocationType { value }
                                District__c { value }
                            }
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

const RETURN_ORDERS_QUERY = gql`
    query GetSiteVisitReturnOrders($workOrderId: ID) {
        uiapi {
            query {
                ReturnOrder(
                    where: { WorkOrder__c: { eq: $workOrderId } }
                    first: 200
                ) {
                    edges {
                        node {
                            Id
                            ReturnOrderNumber { value }
                            Status { value }
                            DestinationLocation {
                                Name { value }
                            }
                            ReturnOrderLineItems(first: 50) {
                                edges {
                                    node {
                                        Id
                                        SerialNumber__c { value }
                                        ItemDescription__c { value }
                                        Model__c { value }
                                        ProductLine__c { value }
                                        Department__r {
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

const CHILD_WORK_ORDERS_QUERY = gql`
    query GetChildWorkOrders($workOrderId: ID) {
        uiapi {
            query {
                WorkOrder(
                    where: { ParentWorkOrderId: { eq: $workOrderId } }
                    first: 200
                    orderBy: { WorkOrderNumber: { order: ASC } }
                ) {
                    edges {
                        node {
                            Id
                            WorkOrderNumber { value }
                            Status { value }
                            TotalInstruments__c { value }
                            TotalServicedInstruments__c { value }
                            Asset {
                                Name { value }
                                SerialNumber { value }
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

const TRUNK_LOCATION_TYPE = 'Trunk location';
const IN_HOUSE_LOCATION_TYPE = 'In-House';
const REGIONAL_LAB_LOCATION_TYPE = 'Regional Lab';
const LOCATION_LIST_TYPES = new Set([IN_HOUSE_LOCATION_TYPE, REGIONAL_LAB_LOCATION_TYPE]);
const TRUCK_TECHNICIAN_TYPE = 'Truck';
const SERVICE_LOCATION_TYPE_OPTIONS = [
    { label: 'Trunk location', value: 'Trunk location' },
    { label: 'In-House', value: 'In-House' },
    { label: 'Regional Lab', value: 'Regional Lab' },
    { label: 'Other', value: 'Other' }
];
const SKIPPED_APPOINTMENT_STATUSES = new Set(['Canceled', 'Cannot Complete']);
const SERVICED_TRAY_STATUSES = new Set(['Completed', 'Closed']);
const SERVICE_LOCATION_RESOURCES_QUERY = gql`
    query GetServiceLocationResources {
        uiapi {
            query {
                ServiceResource(
                    where: {
                        TechnicianType__c: { eq: "Truck" }
                    }
                    first: 2000
                    orderBy: { Name: { order: ASC } }
                ) {
                    edges {
                        node {
                            Id
                            Name { value }
                            TechnicianType__c { value }
                            ServiceTerritories(first: 20) {
                                edges {
                                    node {
                                        TerritoryType { value }
                                        EffectiveStartDate { value }
                                        EffectiveEndDate { value }
                                        ServiceTerritory {
                                            Id
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

const SERVICE_APPOINTMENTS_QUERY = gql`
    query GetWorkOrderServiceAppointments($workOrderId: ID) {
        uiapi {
            query {
                ServiceAppointment(
                    where: { ParentRecordId: { eq: $workOrderId } }
                    first: 50
                    orderBy: { SchedStartTime: { order: ASC } }
                ) {
                    edges {
                        node {
                            Id
                            TruckAppointment__c { value }
                            Truck__c { value }
                            Status { value }
                            Subject { value }
                            SchedStartTime { value }
                            SchedEndTime { value }
                            EarliestStartTime { value }
                            DueDate { value }
                            Duration { value }
                            DurationType { value }
                            ServiceTerritoryId { value }
                            ServiceResources(first: 10) {
                                edges {
                                    node {
                                        Id
                                        ServiceResourceId { value displayValue }
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

const LOCATIONS_QUERY = gql`
    query GetFilteredLocations {
        uiapi {
            query {
                Location(
                    where: {
                        or: [
                            { LocationType: { eq: "In-House" } }
                            { LocationType: { eq: "Regional Lab" } }
                        ]
                    }
                    first: 2000
                    orderBy: { Name: { order: ASC } }
                ) {
                    edges {
                        node {
                            Id
                            Name { value }
                            LocationType { value }
                            District__c { value }
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
//             'labor'   → travel + Asset
//             'expense' → Expense object: ExpenseType + TransactionDate + Amount + billable fields (+ hidden WorkOrderId on save)
//             'generic' → fallback: Description/Duration/UnitPrice
const TAB_DEFS = [
    { key: 'Time',            label: 'Time',            addLabel: '+ Add Time Line', type: null, canAdd: true, schema: 'time' },
    { key: 'ChildWorkOrders', label: 'Child Work Orders', addLabel: '', type: null, canAdd: false, schema: 'child_work_orders' },
    { key: 'Expense',         label: 'Expense',         addLabel: '+ Add Expense Line', type: null, canAdd: true, schema: 'expense' },
    { key: 'ReturnOrders',    label: 'Return Orders',   addLabel: '', type: null, canAdd: false, schema: 'return_orders' }
];
const HIDDEN_TAB_KEYS = new Set(/*['Expense']*/);

const TIME_LINE_TYPES = new Set(['Travel', 'Labor']);
const WOLI_USAGE_CONSUMPTION_RT = 'UsageConsumption';

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

// Map LineType picklist value -> tab def (used during save to look up the schema
// for an existing record being edited).
const TYPE_TO_DEF = {
    Travel:  { key: 'Time', type: 'Travel',  schema: 'travel'  },
    Labor:   { key: 'Time', type: 'Labor',   schema: 'labor'   },
    Expense: { key: 'Expense', type: 'Expense', schema: 'expense' }
};

const TAB_KEY_TO_DEF = TAB_DEFS.reduce((acc, d) => {
    acc[d.key] = d;
    return acc;
}, {});

const KNOWN_TYPES = new Set(['Travel', 'Labor', 'Expense']);

const EMPTY_ADD_FORM_VISIBILITY = () =>
    TAB_DEFS.filter(d => d.canAdd)
            .reduce((acc, d) => { acc[d.key] = false; return acc; }, {});

const EMPTY_TAB_SEARCH_TERMS = () =>
    TAB_DEFS.filter(d => !HIDDEN_TAB_KEYS.has(d.key))
            .reduce((acc, d) => { acc[d.key] = ''; return acc; }, {});

let _tempIdSeq = 0;

/**
 * @description WoDebriefIMS Lightning Web Component.
 * @author Uptima Development Team
 */
export default class WoDebriefIMS extends LightningElement {
    @api recordId;

    graphqlResult;
    expensesGraphqlResult;
    childWorkOrdersGraphqlResult;
    returnOrdersGraphqlResult;
    expensesListResult;
    _workOrder      = null;
    _serverLines    = [];
    _serverExpenses = [];
    _serverChildWorkOrders = [];
    _serverReturnOrders = [];
    showCreateReturnOrder = false;
    selectedReturnOrderId = null;
    _finishingReview = false;
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

    _currentUserServiceResourceId   = null;
    _currentUserServiceResourceName = '';
    _serviceResourceByUserId        = {};
    _userIdByServiceResourceId      = {};
    _ownerUserIdsForLookup          = [];
    _assignedResourceOwnerLookupId;

    _serviceLocationResources = [];
    _locations = [];
    _serviceAppointments = [];
    _serviceAppointmentsReady = false;
    serviceAppointmentsGraphqlResult;
    _serviceLocationUpdateable;
    _serviceLocationTypeUpdateable;
    _serviceLocationSelection;
    _serviceLocationTypeSelection;
    _locationSelection;
    _serviceLocationDefaultApplied = false;
    _savingServiceLocation = false;

    // Per-tab search terms (keyed by tab key; each tab filters independently)
    tabSearchTerms = EMPTY_TAB_SEARCH_TERMS();

    // Per-tab add-form visibility and field values (keyed by tab key)
    showAddForm  = EMPTY_ADD_FORM_VISIBILITY();
    addFormState = {
        lineType: '',
        desc: '', unitPrice: '',
        assignedResourceId: null, workTypeId: null, startDate: '', endDate: '',
        assetId: null,
        expenseType: '', transactionDate: '', amount: '',
        overrideCode: '', billableAmount: '', overrideBillableAmount: false,
        quantity: '', duration: ''
    };

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

    activeTab = 'Time';

    isOffline = !navigator.onLine;
    _onlineHandler  = () => {
        this.isOffline = false;
        this._applyServiceLocationDefault();
    };
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
            console.error('woDebriefIMS getUsageConsumptionRecordTypeId failed', error);
            return;
        }
        if (data) {
            this._usageConsumptionRecordTypeId = data;
        }
    }

    /**
     * @description Wire: WorkOrderLineItem object info to resolve UsageConsumption record type.
     */
    @wire(getObjectInfo, { objectApiName: WOLI_OBJECT })
    wiredWoliObjectInfo({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woDebriefIMS getObjectInfo WorkOrderLineItem failed', error);
            return;
        }
        const resolved = this._recordTypeIdByDeveloperName(
            data,
            WOLI_USAGE_CONSUMPTION_RT
        );
        if (resolved) {
            this._usageConsumptionRecordTypeId = resolved;
        }
    }

    /**
     * @description Wire: Expense object info for Override Code picklist record type.
     */
    @wire(getObjectInfo, { objectApiName: EXPENSE_OBJECT })
    wiredExpenseObjectInfo({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woDebriefIMS getObjectInfo Expense failed', error);
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
            console.error('woDebriefIMS getPicklistValues OverrideCode__c failed', error);
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
                this._workOrder   = woEdge.node;
                this._serverLines = (woEdge.node.WorkOrderLineItems?.edges ?? [])
                    .map(e => e.node);
                this._applyServiceLocationDefault();
            }
        }
    }

    /**
     * @description Wire: Work Order field access for Service Location.
     */
    @wire(getObjectInfo, { objectApiName: WORK_ORDER_OBJECT })
    wiredWorkOrderObjectInfo({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woDebriefIMS getObjectInfo WorkOrder failed', error);
            this._serviceLocationUpdateable = false;
            this._serviceLocationTypeUpdateable = false;
            return;
        }
        if (!data) return;
        const fields = data.fields ?? {};
        this._serviceLocationTypeUpdateable = fields.ServiceLocationType__c?.updateable === true;
        this._serviceLocationUpdateable = fields.ServiceLocation__c?.updateable === true
            && fields.LocationId?.updateable === true;
        this._applyServiceLocationDefault();
    }

    /**
     * @description Wire: Service Resources that can be selected as Service Location.
     */
    @wire(graphql, { query: SERVICE_LOCATION_RESOURCES_QUERY })
    wiredServiceLocationResources(result) {
        if (result.errors) {
            // eslint-disable-next-line no-console
            console.error('woDebriefIMS service location resources query failed', result.errors);
        }
        if (result.data) {
            this._serviceLocationResources = result.data.uiapi?.query?.ServiceResource?.edges
                ?.map(edge => edge.node) ?? [];
        }
    }

    /**
     * @description Wire: Service Appointments on this Work Order, used to default Service Location.
     */
    @wire(graphql, {
        query: SERVICE_APPOINTMENTS_QUERY,
        variables: '$serviceAppointmentQueryVariables'
    })
    wiredServiceAppointments(result) {
        this.serviceAppointmentsGraphqlResult = result;
        if (result.errors) {
            // eslint-disable-next-line no-console
            console.error('woDebriefIMS service appointments query failed', result.errors);
        }
        if (result.data) {
            this._serviceAppointments = result.data.uiapi?.query?.ServiceAppointment?.edges
                ?.map(edge => edge.node) ?? [];
        }
        if (result.data || result.errors) {
            this._serviceAppointmentsReady = true;
            this._applyServiceLocationDefault();
        }
    }

    /**
     * @description Wire: Locations for a non-trunk Service Location Type.
     */
    @wire(graphql, { query: LOCATIONS_QUERY })
    wiredLocations(result) {
        if (result.errors) {
            // eslint-disable-next-line no-console
            console.error('woDebriefIMS locations query failed', result.errors);
        }
        if (result.data) {
            this._locations = result.data.uiapi?.query?.Location?.edges?.map(edge => edge.node) ?? [];
        }
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
     * @description Wire adapter handler: Child Work Orders.
     */
    @wire(graphql, {
        query: CHILD_WORK_ORDERS_QUERY,
        variables: '$childWorkOrderQueryVariables'
    })
    wiredChildWorkOrders(result) {
        this.childWorkOrdersGraphqlResult = result;
        if (result.data) {
            this._serverChildWorkOrders = (result.data.uiapi.query.WorkOrder?.edges ?? [])
                .map(e => e.node);
        }
    }

    /**
     * @description Wire adapter handler: Return Orders created from this site visit (GW-1353).
     */
    @wire(graphql, {
        query: RETURN_ORDERS_QUERY,
        variables: '$returnOrderQueryVariables'
    })
    wiredReturnOrders(result) {
        this.returnOrdersGraphqlResult = result;
        if (result.errors) {
            // eslint-disable-next-line no-console
            console.error('woDebriefIMS return orders query failed', result.errors);
        }
        if (result.data) {
            this._serverReturnOrders = (result.data.uiapi.query.ReturnOrder?.edges ?? [])
                .map(e => e.node);
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

    /**
     * @description Query Variables.
     */
    get queryVariables() {
        return { workOrderId: this.recordId };
    }

    /**
     * @description Service Appointment query variables. Paused until the Work Order Id is set.
     */
    get serviceAppointmentQueryVariables() {
        if (!this.recordId) return undefined;
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

    /**
     * @description Child Work Order Query Variables.
     */
    get childWorkOrderQueryVariables() {
        return this.recordId ? { workOrderId: this.recordId } : undefined;
    }

    /**
     * @description Return Order Query Variables.
     */
    get returnOrderQueryVariables() {
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
        const childWoDone = !this.recordId
            || this.childWorkOrdersGraphqlResult?.data
            || this.childWorkOrdersGraphqlResult?.errors;
        const returnOrdersDone = !this.recordId
            || this.returnOrdersGraphqlResult?.data
            || this.returnOrdersGraphqlResult?.errors;
        const expLoading = !!this.recordId && !(gqlExpDone && rlExpDone);
        const childWoLoading = !!this.recordId && !childWoDone;
        const returnOrdersLoading = !!this.recordId && !returnOrdersDone;
        return woLoading || expLoading || childWoLoading || returnOrdersLoading;
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
    get woAccountName(){ return this._workOrder?.Account?.Name?.value ?? ''; }

    /**
     * @description Child work orders cannot open the site visit review.
     */
    get isChildWorkOrder() {
        return !!this._workOrder?.ParentWorkOrderId?.value;
    }

    /**
     * @description Site visit review is available only for a work order with no parent.
     */
    get showReview() {
        return !!this._workOrder && !this.isChildWorkOrder;
    }

    /**
     * @description Site visit review. Hidden while Create Return Order is open.
     */
    get showDebrief() {
        return this.showReview && !this.showCreateReturnOrder;
    }

    /**
     * @description Passed to the embedded Create Return Order wizard.
     */
    get useSiteVisitRepairCenterLines() {
        return true;
    }

    /**
     * @description Passed to the embedded Create Return Order wizard.
     */
    get embedCreateReturnOrder() {
        return true;
    }

    /**
     * @description Return Orders has no search box.
     */
    get showActiveTabSearch() {
        return this.activeTabModel?.schema !== 'return_orders';
    }

    /**
     * @description Return order opened from the list, with its lines for the read-only table.
     */
    get selectedReturnOrder() {
        if (!this.selectedReturnOrderId || !this.isActiveTabReturnOrders) {
            return null;
        }
        const lines = this.activeTabModel?.lines ?? [];
        return lines.find(line => line.Id === this.selectedReturnOrderId) ?? null;
    }

    /**
     * @description True while a return order's lines are shown instead of the list.
     */
    get showReturnOrderDetail() {
        return !!this.selectedReturnOrder;
    }

    /**
     * @description Message shown when the opened work order is not the site visit.
     */
    get childWorkOrderMessage() {
        const parentNumber = this._workOrder?.ParentWorkOrder?.WorkOrderNumber?.value
            || this._workOrder?.ParentWorkOrderId?.displayValue;
        return parentNumber
            ? `Only the site visit work order can access this screen. The site visit work order is ${parentNumber}.`
            : 'Only the site visit work order can access this screen. Open the parent work order.';
    }

    /**
     * @description GW-1353 - Total Serviced Trays is the number of Completed or Closed child work orders.
     */
    get woTotalServicedTrays() {
        return String(
            this._serverChildWorkOrders
                .filter(wo => SERVICED_TRAY_STATUSES.has(wo.Status?.value))
                .length
        );
    }

    /**
     * @description Wo Number.
     */
    get woNumber()     { return this._workOrder?.WorkOrderNumber?.value ?? ''; }

    /**
     * @description Selected Service Location Id.
     */
    get serviceLocationValue() {
        if (this._serviceLocationSelection !== undefined) {
            return this._serviceLocationSelection;
        }
        return this._workOrder?.ServiceLocation__c?.value || null;
    }

    /**
     * @description Service Location combobox options, Work Order territory first.
     */
    get serviceLocationOptions() {
        const woTerritoryId = this._workOrder?.ServiceTerritoryId?.value ?? null;
        const resourcesById = new Map();
        for (const resource of this._serviceLocationResources) {
            if (resource?.Id) resourcesById.set(resource.Id, resource);
        }

        const options = [...resourcesById.values()].map(resource => {
            const territory = this._serviceLocationTerritory(resource, woTerritoryId);
            const resourceName = resource.Name?.value ?? '';
            return {
                label: this._serviceLocationLabel(resourceName, territory.name),
                value: resource.Id,
                territoryName: territory.name,
                resourceName,
                matchesWorkOrder: territory.matchesWorkOrder
            };
        });
        options.sort((a, b) => {
            if (a.matchesWorkOrder !== b.matchesWorkOrder) {
                return a.matchesWorkOrder ? -1 : 1;
            }
            const byTerritory = this._territorySortKey(a.territoryName)
                .localeCompare(this._territorySortKey(b.territoryName));
            if (byTerritory !== 0) return byTerritory;
            return (a.resourceName || '').localeCompare(b.resourceName || '');
        });

        const mapped = options.map(({ label, value }) => ({ label, value }));
        const selected = this.serviceLocationValue;
        if (selected && !mapped.some(option => option.value === selected)) {
            mapped.unshift({
                label: this._workOrder?.ServiceLocation__c?.displayValue || 'Service Location',
                value: selected
            });
        }
        return mapped;
    }

    /**
     * @description Service Location Type options.
     */
    get serviceLocationTypeOptions() {
        const selected = this.serviceLocationTypeValue;
        return SERVICE_LOCATION_TYPE_OPTIONS.map(option => ({
            label: option.label,
            value: option.value,
            pressed: option.value === selected ? 'true' : 'false',
            className: option.value === selected ? 'type-pill type-pill_selected' : 'type-pill'
        }));
    }

    /**
     * @description Selected Service Location Type.
     */
    get serviceLocationTypeValue() {
        if (this._serviceLocationTypeSelection !== undefined) {
            return this._serviceLocationTypeSelection;
        }
        return this._workOrder?.ServiceLocationType__c?.value || '';
    }

    /**
     * @description Trunk location uses the Service Resource list.
     */
    get showTruckServiceLocation() {
        return this.serviceLocationTypeValue === TRUNK_LOCATION_TYPE;
    }

    /**
     * @description In-House and Regional Lab use the Location list. Other hides it.
     */
    get showInventoryLocation() {
        return LOCATION_LIST_TYPES.has(this.serviceLocationTypeValue);
    }

    /**
     * @description Selected Location Id.
     */
    get locationValue() {
        if (this._locationSelection !== undefined) {
            return this._locationSelection;
        }
        return this._workOrder?.LocationId?.value || null;
    }

    /**
     * @description In-House or Regional Lab locations. Label is Location Name - District.
     */
    get locationOptions() {
        const selectedType = this.serviceLocationTypeValue;
        const woTerritoryName = this._workOrder?.ServiceTerritory?.Name?.value ?? '';
        const options = this._locations
            .filter(location => location.LocationType?.value === selectedType)
            .map(location => {
                const locationName = location.Name?.value ?? '';
                const districtName = location.District__c?.value ?? '';
                return {
                    label: this._serviceLocationLabel(locationName, districtName),
                    value: location.Id,
                    districtName,
                    locationName,
                    matchesWorkOrder: !!woTerritoryName && districtName === woTerritoryName
                };
            });
        options.sort((a, b) => {
            if (a.matchesWorkOrder !== b.matchesWorkOrder) {
                return a.matchesWorkOrder ? -1 : 1;
            }
            const byDistrict = this._territorySortKey(a.districtName)
                .localeCompare(this._territorySortKey(b.districtName));
            if (byDistrict !== 0) return byDistrict;
            return (a.locationName || '').localeCompare(b.locationName || '');
        });
        const mapped = options.map(({ label, value }) => ({ label, value }));
        const selected = this.locationValue;
        if (selected && !mapped.some(option => option.value === selected)) {
            const current = this._workOrder?.Location;
            mapped.unshift({
                label: this._serviceLocationLabel(
                    current?.Name?.value,
                    current?.District__c?.value
                ) || 'Location',
                value: selected
            });
        }
        return mapped;
    }

    /**
     * @description Placeholder when the selected type has no matching locations.
     */
    get locationPlaceholder() {
        return this._locations.some(location => location.LocationType?.value === this.serviceLocationTypeValue)
            ? 'Select a location'
            : 'No locations for this type';
    }

    /**
     * @description Service Location Type can be changed when the user has edit access.
     */
    get serviceLocationTypeDisabled() {
        return this._savingServiceLocation || this._serviceLocationTypeUpdateable === false;
    }

    /**
     * @description Header location fields are read-only when the user cannot edit them.
     */
    get serviceLocationDisabled() {
        return this._savingServiceLocation || this._serviceLocationUpdateable === false;
    }
    /**
     * @description Has Pending Changes.
     */
    get hasPendingChanges() {
        return Object.keys(this._pendingEdits).length   > 0 ||
               Object.keys(this._pendingDeletes).length > 0 ||
               this._pendingAdds.length > 0;
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

    /**
     * @description GW-1353 - Finish Review Child Work Order is off while the check runs, while saving, or offline.
     */
    get finishChildReviewDisabled() {
        return this._finishingReview || this._saving || this.isOffline;
    }

    // ── Tabs (data-driven from TAB_DEFS) ──────────────────────────────────────
    /**
     * @description Tabs.
     */
    get tabs() {
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
        if (schema === 'labor')   return 'Search resource or asset…';
        if (schema === 'child_work_orders') return 'Search work order number, status, or asset…';
        if (schema === 'return_orders') return 'Search return order number, status, or repair center…';
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
     * @description Is Active Tab Expense.
     */
    get isActiveTabExpense()   { return this.activeTabModel?.schema === 'expense'; }
    /**
     * @description Is Active Tab Child Work Orders.
     */
    get isActiveTabChildWorkOrders() { return this.activeTabModel?.schema === 'child_work_orders'; }
    /**
     * @description Is Active Tab Return Orders.
     */
    get isActiveTabReturnOrders() { return this.activeTabModel?.schema === 'return_orders'; }
    /**
     * @description Time Line Type Options.
     */
    get timeLineTypeOptions() { return TIME_LINE_TYPE_OPTIONS; }
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
     * @description Active Tab Has No Lines.
     */
    get activeTabHasNoLines() {
        return !(this.activeTabSearchTerm ?? '').trim()
            && (this.activeTabModel?.lines?.length ?? 0) === 0;
    }

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

    // Asset → no filter; show SerialNumber as the primary value (with Name as
    // secondary so users can find an Asset by either field).
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

    /**
     * @description Internal helper: Build Lines For.
     */
    _buildLinesFor(def) {
        if (def.schema === 'expense') {
            return this._buildExpenseLinesFor(def);
        }
        if (def.schema === 'child_work_orders') {
            return this._buildChildWorkOrderLinesFor(def);
        }
        if (def.schema === 'return_orders') {
            return this._buildReturnOrderLinesFor(def);
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
     * @description Internal helper: Build Child Work Order Lines For.
     */
    _buildChildWorkOrderLinesFor(def) {
        const lines = this._serverChildWorkOrders.map(wo => this._buildChildWorkOrderLineModel(wo));
        return this._filterLinesBySearch(lines, def.key);
    }

    /**
     * @description GW-1353 - Return orders linked to this site visit.
     */
    _buildReturnOrderLinesFor(def) {
        const lines = this._serverReturnOrders.map(order => this._buildReturnOrderLineModel(order));
        lines.sort((a, b) => (b.returnOrderNumber || '').localeCompare(a.returnOrderNumber || ''));
        return this._filterLinesBySearch(lines, def.key);
    }

    /**
     * @description Read-only return order row. Repair Center is the destination location.
     */
    _buildReturnOrderLineModel(order) {
        const returnOrderNumber = order.ReturnOrderNumber?.value ?? '';
        const status = order.Status?.value ?? '';
        const repairCenterName = order.DestinationLocation?.Name?.value ?? '';
        const lineItems = (order.ReturnOrderLineItems?.edges ?? [])
            .map(edge => this._returnOrderLineRow(edge?.node))
            .filter(item => item?.id);
        return {
            Id: order.Id,
            schema: 'return_orders',
            isReturnOrderSchema: true,
            isChildWorkOrderSchema: false,
            cardClass: 'woli-card woli-card_readonly return-order-card_clickable',
            title: returnOrderNumber || 'Return Order',
            metaLine: [status, repairCenterName].filter(Boolean).join(' · '),
            returnOrderNumber: returnOrderNumber || '—',
            status: status || '—',
            repairCenterName: repairCenterName || '—',
            lineItems,
            hasLineItems: lineItems.length > 0,
            hasNoLineItems: lineItems.length === 0,
            showLineType: false,
            isEditing: false,
            isDirty: false,
            isNew: false
        };
    }

    /**
     * @description Read-only table row for one return order line.
     */
    _returnOrderLineRow(node) {
        if (!node?.Id) {
            return null;
        }
        const text = (field) => (field?.value || '').trim() || '—';
        return {
            id: node.Id,
            serialNumber: text(node.SerialNumber__c),
            itemDescription: text(node.ItemDescription__c),
            model: text(node.Model__c),
            productLine: text(node.ProductLine__c),
            departmentName: (node.Department__r?.Name?.value || '').trim() || '—'
        };
    }

    /**
     * @description Opens the read-only line table for the tapped return order.
     */
    handleReturnOrderSelect(event) {
        if (event.type === 'keydown' && event.key !== 'Enter' && event.key !== ' ') {
            return;
        }
        if (event.type === 'keydown') {
            event.preventDefault();
        }
        const returnOrderId = event.currentTarget?.dataset?.id;
        if (returnOrderId) {
            this.selectedReturnOrderId = returnOrderId;
        }
    }

    /**
     * @description Returns from the line table to the return order list.
     */
    handleReturnOrderDetailClose() {
        this.selectedReturnOrderId = null;
    }

    /**
     * @description GW-1353 - Finish Review Child Work Order. Blocks while a child work order is open
     *              or a return line is still marked. Otherwise points to the summary. No status changes.
     */
    async handleFinishChildReview() {
        if (this.isOffline) {
            this._toast(
                'Offline',
                'An internet connection is required to finish the review.',
                'error'
            );
            return;
        }
        if (this.hasPendingChanges) {
            this._toast('Save first', 'Save All before finishing the review.', 'warning');
            return;
        }
        if (!this.recordId || this._finishingReview) {
            return;
        }

        this._finishingReview = true;
        try {
            const result = await checkSiteVisitReview({ workOrderId: this.recordId });
            if (!result?.canFinish) {
                const parts = [
                    'The review cannot be finished. Complete the child work orders or create the return orders.'
                ];
                if (result?.openWorkOrders?.length) {
                    parts.push('Work orders to complete:\n' + result.openWorkOrders.join('\n'));
                }
                if (result?.returnOrderLines?.length) {
                    parts.push('Lines that still need a return order:\n' + result.returnOrderLines.join('\n'));
                }
                await LightningAlert.open({
                    label: 'Review cannot be finished',
                    message: parts.join('\n\n'),
                    theme: 'error'
                });
                return;
            }
            await LightningAlert.open({
                label: 'Child work order review finished',
                message: 'Move to the work order summary to generate the service report.',
                theme: 'success'
            });
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (error) {
            this._toast('Review was not finished', this._errorMessage(error), 'error');
        } finally {
            this._finishingReview = false;
        }
    }

    /**
     * @description Opens Create Return Order. Marked child lines are prefilled.
     *              With none, the wizard asks the technician to enter the items.
     */
    handleCreateReturnOrder() {
        if (this.isOffline) {
            this._toast(
                'Offline',
                'An internet connection is required to create a return order.',
                'error'
            );
            return;
        }
        if (!this.recordId) {
            return;
        }
        this.selectedReturnOrderId = null;
        this.showCreateReturnOrder = true;
    }

    /**
     * @description Closes Create Return Order and reloads the Return Orders tab.
     */
    async handleCreateReturnOrderExit() {
        this.showCreateReturnOrder = false;
        try {
            await refreshGraphQL(this.returnOrdersGraphqlResult);
        } catch (e) { /* swallow — the tab query refreshes on the next load */ }
    }

    _buildChildWorkOrderLineModel(wo) {
        const workOrderNumber = wo.WorkOrderNumber?.value ?? '';
        const status = wo.Status?.value ?? '';
        const assetName = this._fmtWoAssetLabel(wo.Asset);
        const totalServicedInstruments = this._fmtCount(wo.TotalServicedInstruments__c?.value);
        const statusClass = this._childWorkOrderStatusClass(status);
        return {
            Id: wo.Id,
            schema: 'child_work_orders',
            isChildWorkOrderSchema: true,
            cardClass: statusClass ? `woli-card woli-card_readonly ${statusClass}` : 'woli-card woli-card_readonly',
            isTravelSchema: false,
            isLaborSchema: false,
            isExpenseSchema: false,
            isAssetTimeSchema: false,
            title: workOrderNumber || 'Work Order',
            metaLine: [status, assetName].filter(Boolean).join(' · '),
            workOrderNumber,
            status,
            assetName,
            totalServicedInstruments,
            showLineType: false,
            isEditing: false,
            isDirty: false,
            isNew: false
        };
    }

    /**
     * @description Light status color for a child work order row. Text stays dark.
     *              Green Completed, yellow In Progress, red Canceled, blue New and Received, gray Closed.
     */
    _childWorkOrderStatusClass(status) {
        const value = (status || '').trim().toLowerCase();
        if (value === 'canceled' || value === 'cancelled') return 'child-wo-card_canceled';
        if (value === 'in progress') return 'child-wo-card_inprogress';
        if (value === 'completed') return 'child-wo-card_completed';
        if (value === 'closed') return 'child-wo-card_closed';
        if (value === 'new' || value === 'received') return 'child-wo-card_new';
        return '';
    }

    /**
     * @description True when a date-time falls on the device's current calendar day.
     */
    _isToday(dateTimeValue) {
        if (!dateTimeValue) return false;
        const value = new Date(dateTimeValue);
        if (Number.isNaN(value.getTime())) return false;
        const today = new Date();
        return value.getFullYear() === today.getFullYear()
            && value.getMonth() === today.getMonth()
            && value.getDate() === today.getDate();
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
        if (!term) return lines;
        return lines.filter(line => this._lineMatchesSearch(line, term));
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
            line.startDate,
            line.endDate,
            line.lineType,
            line.workOrderNumber,
            line.status,
            line.assetName,
            line.totalServicedInstruments,
            line.returnOrderNumber,
            line.repairCenterName
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
            metaLine:            this._fmtTravelMeta(startDate, endDate),
            lineType:            effectiveLineType,
            lineTypeLabel:       effectiveLineType || 'No Type',
            showLineType,
            isTravelLine:        effectiveLineType === 'Travel',
            isLaborLine:         effectiveLineType === 'Labor',
            // Travel fields
            assignedResourceId:  assignedResId,
            assignedResourceName:assignedResName,
            workTypeId,
            startDate,
            endDate,
            startDateMs:         this._toMs(startDate),
            durationHours,
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
            metaLine:            this._fmtTravelMeta(startDate, endDate),
            lineType,
            lineTypeLabel:       lineType,
            showLineType:        false,
            isTravelLine:        lineType === 'Travel',
            isLaborLine:         lineType === 'Labor',
            assignedResourceId:  assignedResId,
            assignedResourceName:titleName,
            workTypeId,
            startDate,
            endDate,
            startDateMs:         this._toMs(startDate),
            durationHours,
            isEditing:           state.isEditing ?? false,
            editLineType:        lineType,
            editWorkTypeId:      state.workTypeId ?? a.workTypeId ?? null,
            editAssignedResId:   this._resolveAssignedResourceId(
                state.assignedResourceId, a.assignedResourceId
            ),
            editStartDate:       state.startDate ?? a.startDate ?? '',
            editEndDate:         state.endDate   ?? a.endDate   ?? '',
            editDurationLabel:   this._editDurationLabel(state, null, startDate, endDate, durationHours),
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
        const startDate        = edit?.startDate ?? l.StartDate?.value ?? '';
        const endDate          = edit?.endDate   ?? l.EndDate?.value   ?? '';
        const durationHours    = this._computeDurationHours(startDate, endDate) ?? l.Duration?.value ?? null;
        const effectiveLineType = edit?.lineType ?? lineType;
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
            metaLine:             this._fmtLaborMeta(assetSerial, startDate, endDate, durationHours),
            lineType:             effectiveLineType,
            lineTypeLabel:        effectiveLineType || 'No Type',
            showLineType,
            isTravelLine:         effectiveLineType === 'Travel',
            isLaborLine:          effectiveLineType === 'Labor',
            // Labor fields
            assignedResourceId:   assignedResId,
            assignedResourceName: assignedResName,
            workTypeId,
            assetId,
            assetSerialNumber:    assetSerial,
            startDate,
            endDate,
            startDateMs:          this._toMs(startDate),
            durationHours,
            // Edit state
            isEditing:            state.isEditing ?? false,
            editLineType:         edit?.lineType ?? lineType,
            editWorkTypeId:       state.workTypeId ?? edit?.workTypeId ?? l.WorkTypeId?.value ?? null,
            editAssignedResId:    this._resolveAssignedResourceId(
                state.assignedResourceId, edit?.assignedResourceId, l.AssignedResource__c?.value
            ),
            editAssetId:          state.assetId       ?? edit?.assetId       ?? l.AssetId?.value          ?? null,
            editStartDate:        state.startDate     ?? edit?.startDate     ?? l.StartDate?.value        ?? '',
            editEndDate:          state.endDate       ?? edit?.endDate       ?? l.EndDate?.value          ?? '',
            editDurationLabel:    this._editDurationLabel(state, edit, startDate, endDate, l.Duration?.value),
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
        const startDate     = state.isEditing ? (state.startDate     ?? a.startDate)     : a.startDate;
        const endDate       = state.isEditing ? (state.endDate       ?? a.endDate)       : a.endDate;
        const durationHours = this._computeDurationHours(startDate, endDate);
        const lineType      = a._lineType || a.lineType || 'Labor';
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
            metaLine:             this._fmtLaborMeta('', startDate, endDate, durationHours),
            lineType,
            lineTypeLabel:        lineType,
            showLineType:         false,
            isTravelLine:         lineType === 'Travel',
            isLaborLine:          lineType === 'Labor',
            assignedResourceId:   assignedResId,
            assignedResourceName: titleName,
            workTypeId,
            assetId,
            assetSerialNumber:    '',
            startDate,
            endDate,
            startDateMs:          this._toMs(startDate),
            durationHours,
            isEditing:            state.isEditing ?? false,
            editLineType:         lineType,
            editWorkTypeId:       state.workTypeId ?? a.workTypeId ?? null,
            editAssignedResId:    this._resolveAssignedResourceId(
                state.assignedResourceId, a.assignedResourceId
            ),
            editAssetId:          state.assetId            ?? a.assetId            ?? null,
            editStartDate:        state.startDate          ?? a.startDate          ?? '',
            editEndDate:          state.endDate            ?? a.endDate            ?? '',
            editDurationLabel:    this._editDurationLabel(state, null, startDate, endDate, durationHours),
            editError:            this.editErrors[a._tempId] ?? '',
            isDirty:              false,
            isNew:                true
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
    _fmtLaborMeta(assetSerial, startDate, endDate, duration) {
        const parts = [];
        if (assetSerial) parts.push(`SN ${assetSerial}`);
        const range = this._fmtDateRange(startDate, endDate);
        if (range) parts.push(range);
        const durationLabel = this._fmtDurationLabel(duration);
        if (durationLabel) parts.push(durationLabel);
        return parts.join(' · ');
    }

    /**
     * @description Internal helper: Fmt Travel Meta.
     */
    _fmtTravelMeta(startDate, endDate) {
        return this._fmtDateRange(startDate, endDate);
    }

    /**
     * @description Internal helper: Fmt Wo Asset Label.
     */
    _fmtWoAssetLabel(asset) {
        const serial = asset?.SerialNumber?.value ?? '';
        const name = asset?.Name?.value ?? '';
        if (serial && name) return `${serial} — ${name}`;
        return serial || name || '';
    }

    /**
     * @description Internal helper: Fmt Count.
     */
    _fmtCount(value) {
        if (value == null || value === '') return '';
        const n = Number(value);
        return Number.isFinite(n) ? String(n) : String(value);
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
        this.selectedReturnOrderId = null;
        this.activeTab = e.currentTarget.dataset.tab;
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
        this.editStateMap = {
            ...this.editStateMap,
            [id]: { isEditing: !(cur?.isEditing) }
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
    handleEditFieldChange(e) {
        const id    = e.currentTarget.dataset.id;
        const field = e.currentTarget.dataset.field;
        const value = field === 'overrideBillableAmount'
            ? e.detail.checked === true
            : e.detail.value;
        this._stageEdit(id, field, value);
        if (field === 'lineType') {
            if (value === 'Travel') {
                this._stageEdit(id, 'assetId', null);
            }
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
        this.showAddForm = { ...EMPTY_ADD_FORM_VISIBILITY(), [tab]: true };
        this.addFormState = this._emptyAddFormState();
        this.addErrors    = {};
    }

    /**
     * @description Handle Add Field Change.
     */
    handleAddFieldChange(e) {
        const field = e.currentTarget.dataset.field;
        const value = field === 'overrideBillableAmount'
            ? e.detail.checked === true
            : e.detail.value;
        let next = { ...this.addFormState, [field]: value };
        if (field === 'lineType') {
            next.assetId = null;
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
    handleLookupChange(e) {
        const id    = e.currentTarget.dataset.id;     // present for inline-edit
        const tab   = e.currentTarget.dataset.tab;    // present for add-form
        const field = e.currentTarget.dataset.field;
        const recordId = e.detail.recordId ?? null;
        if (id) {
            this._stageEdit(id, field, recordId);
        } else if (tab) {
            this.addFormState = { ...this.addFormState, [field]: recordId };
        }
        if (field === 'assignedResourceId' && recordId && !this._userIdByServiceResourceId[recordId]) {
            this._assignedResourceOwnerLookupId = recordId;
        }
    }

    /**
     * @description Handle Add Confirm.
     */
    handleAddConfirm(e) {
        const tab    = e.currentTarget.dataset.tab || this.activeTab;
        const def    = TAB_KEY_TO_DEF[tab];
        const schema = def?.schema ?? 'generic';
        const addPayload = schema === 'expense'
            ? { ...this.addFormState }
            : {
                ...this.addFormState,
                assignedResourceId: this._resolveAssignedResourceId(this.addFormState.assignedResourceId)
            };
        const errMsg = this._validateForSchema(schema, addPayload);
        if (errMsg) {
            this.addErrors = { ...this.addErrors, [tab]: errMsg };
            return;
        }
        const assignedResourceId   = addPayload.assignedResourceId;
        const assignedResourceName = this._assignedResourceNameForId(assignedResourceId);
        _tempIdSeq += 1;
        const resolvedSchema = schema === 'time'
            ? (LINE_TYPE_TO_SCHEMA[addPayload.lineType] ?? null)
            : schema;
        const resolvedLineType = schema === 'time' ? addPayload.lineType : (def?.type ?? tab);
        if (schema === 'time' && !resolvedSchema) {
            this.addErrors = { ...this.addErrors, [tab]: 'Line Type is required.' };
            return;
        }
        const baseAdd = {
            _tempId:   `_new_${_tempIdSeq}`,
            _lineType: resolvedLineType,
            _schema:   resolvedSchema
        };
        let newAdd;
        if (resolvedSchema === 'travel') {
            newAdd = {
                ...baseAdd,
                assignedResourceId,
                assignedResourceName,
                workTypeId:         addPayload.workTypeId || null,
                startDate:          addPayload.startDate || null,
                endDate:            addPayload.endDate   || null
            };
        } else if (resolvedSchema === 'labor') {
            newAdd = {
                ...baseAdd,
                assignedResourceId,
                assignedResourceName,
                workTypeId:         addPayload.workTypeId || null,
                assetId:            addPayload.assetId,
                startDate:          addPayload.startDate || null,
                endDate:            addPayload.endDate   || null
            };
        } else if (schema === 'expense') {
            const overrideBillableAmount = this._isTruthyFlag(addPayload.overrideBillableAmount);
            const amount = Number(addPayload.amount) || 0;
            newAdd = {
                ...baseAdd,
                _entity:            'Expense',
                expenseType:        addPayload.expenseType,
                transactionDate:    addPayload.transactionDate || null,
                amount,
                overrideCode:      addPayload.overrideCode || '',
                overrideBillableAmount,
                billableAmount:     overrideBillableAmount
                    ? Number(addPayload.billableAmount)
                    : amount
            };
        } else if (schema === 'asset_time') {
            newAdd = {
                ...baseAdd,
                assignedResourceId,
                assignedResourceName,
                assetId:            addPayload.assetId,
                startDate:          addPayload.startDate || null,
                endDate:            addPayload.endDate   || null
            };
        } else {
            newAdd = {
                ...baseAdd,
                desc:      addPayload.desc,
                duration:  Number(addPayload.duration),
                unitPrice: Number(addPayload.unitPrice) || 0
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

        // Validate staged edits — route validator by schema
        let hasValidationError = false;
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
                this.addErrors = { ...this.addErrors, [a._lineType]: err };
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

        const failedDeletes = {};
        const failedEdits   = {};
        const failedAdds    = [];
        const okIds         = [];

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
                        ...this._buildDurationFields(edit.startDate, edit.endDate)
                    };
                } else if (schema === 'labor') {
                    fields = {
                        Id: id,
                        [WOLI_LINETYPE.fieldApiName]:     edit.lineType || edit._lineType || 'Labor',
                        [WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
                        [WOLI_WORKTYPE.fieldApiName]:     edit.workTypeId || null,
                        [WOLI_ASSETID.fieldApiName]:      edit.assetId,
                        [WOLI_STARTDATE.fieldApiName]:    edit.startDate || null,
                        [WOLI_ENDDATE.fieldApiName]:      edit.endDate   || null,
                        ...this._buildDurationFields(edit.startDate, edit.endDate)
                    };
                } else if (schema === 'expense') {
                    // Field Service mobile rejects new Expense custom fields on uiRecordApi drafts.
                    // eslint-disable-next-line no-await-in-loop
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
            } catch (err) {
                failedEdits[id] = edit;
                this.editErrors = {
                    ...this.editErrors,
                    [id]: this._errorMessage(err)
                };
            }
        }
        for (const a of pendingAdds) {
            try {
                const schema = a._schema ?? 'generic';
                let fields;
                if (schema === 'travel') {
                    fields = {
                        [WOLI_WORKORDERID.fieldApiName]:  this.recordId,
                        [WOLI_LINETYPE.fieldApiName]:     a._lineType,
                        [WOLI_ASSIGNED_RES.fieldApiName]: a.assignedResourceId,
                        [WOLI_WORKTYPE.fieldApiName]:     a.workTypeId || null,
                        [WOLI_STARTDATE.fieldApiName]:    a.startDate || null,
                        [WOLI_ENDDATE.fieldApiName]:      a.endDate   || null,
                        ...this._buildDurationFields(a.startDate, a.endDate),
                        ...this._usageConsumptionRecordTypeFields()
                    };
                } else if (schema === 'labor') {
                    fields = {
                        [WOLI_WORKORDERID.fieldApiName]:  this.recordId,
                        [WOLI_LINETYPE.fieldApiName]:     a._lineType,
                        [WOLI_ASSIGNED_RES.fieldApiName]: a.assignedResourceId,
                        [WOLI_WORKTYPE.fieldApiName]:     a.workTypeId || null,
                        [WOLI_ASSETID.fieldApiName]:      a.assetId,
                        [WOLI_STARTDATE.fieldApiName]:    a.startDate || null,
                        [WOLI_ENDDATE.fieldApiName]:      a.endDate   || null,
                        ...this._buildDurationFields(a.startDate, a.endDate),
                        ...this._usageConsumptionRecordTypeFields()
                    };
                } else if (schema === 'expense') {
                    // eslint-disable-next-line no-await-in-loop
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
                const apiName = WOLI_OBJECT.objectApiName;
                // eslint-disable-next-line no-await-in-loop
                const result = await createRecord({ apiName, fields });
                if (result?.id) {
                    okIds.push(result.id);
                }
            } catch (err) {
                failedAdds.push(a);
                this.editErrors = {
                    ...this.editErrors,
                    [a._tempId]: this._errorMessage(err)
                };
            }
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

        // Re-populate pending state with ONLY the failed operations
        this._pendingDeletes = failedDeletes;
        this._pendingEdits   = failedEdits;
        this._pendingAdds    = failedAdds;

        // Clear in-flight form state (edit toggles + add forms) either way
        this.editStateMap = {};
        this.showAddForm  = EMPTY_ADD_FORM_VISIBILITY();
        this.addFormState = this._emptyAddFormState();

        this._saving = false;

        const anyFailed = Object.keys(failedDeletes).length
                        + Object.keys(failedEdits).length
                        + failedAdds.length;

        if (anyFailed === 0) {
            this._toast('Saved', `${okIds.length} change(s) saved.`, 'success');
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
            console.error('woDebriefIMS listExpenseBillableFields failed', e);
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
        this.editStateMap    = {};
        this.showAddForm     = EMPTY_ADD_FORM_VISIBILITY();
        this.addFormState    = this._emptyAddFormState();
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
                endDate:            line.EndDate?.value   ?? ''
            };
        }
        if (schema === 'labor') {
            return {
                _schema:            'labor',
                ...base,
                assignedResourceId: this._resolveAssignedResourceId(line.AssignedResource__c?.value),
                workTypeId:         line.WorkTypeId?.value ?? null,
                assetId:            line.AssetId?.value          ?? null,
                startDate:          line.StartDate?.value        ?? '',
                endDate:            line.EndDate?.value          ?? ''
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
        if (schema === 'time')       return this._validateTime(payload);
        if (schema === 'travel')     return this._validateTravel(payload);
        if (schema === 'labor')      return this._validateLabor(payload);
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
     * @description Internal helper: Toast.
     */
    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    /**
     * @description Defaults Service Location Type and Service Location from a truck appointment.
     */
    _applyServiceLocationDefault() {
        if (this._serviceLocationDefaultApplied || !this.recordId || !this._workOrder) {
            return;
        }
        const savedType = this._workOrder.ServiceLocationType__c?.value;
        const savedLocation = this._workOrder.ServiceLocation__c?.value;
        if (savedLocation || (savedType && savedType !== TRUNK_LOCATION_TYPE)) {
            this._serviceLocationDefaultApplied = true;
            return;
        }
        if (!this._serviceAppointmentsReady || this._serviceLocationUpdateable === undefined) {
            return;
        }
        const truckAppointment = this._truckAppointment();
        const defaultId = this._assignedTruckId(truckAppointment);
        if (!defaultId || this._serviceLocationUpdateable !== true || this.isOffline) {
            if (!defaultId || this._serviceLocationUpdateable !== true) {
                this._serviceLocationDefaultApplied = true;
            }
            return;
        }
        this._serviceLocationDefaultApplied = true;
        this._serviceLocationTypeSelection = TRUNK_LOCATION_TYPE;
        this._serviceLocationSelection = defaultId;
        this._locationSelection = null;
        this._persistWorkOrderFields({
            [SERVICE_LOCATION_TYPE_FIELD.fieldApiName]: TRUNK_LOCATION_TYPE,
            [SERVICE_LOCATION_FIELD.fieldApiName]: defaultId,
            [WO_LOCATION_FIELD.fieldApiName]: null
        });
    }

    /**
     * @description Open service appointments, earliest schedule first.
     */
    _openAppointments() {
        return [...this._serviceAppointments]
            .filter(appointment => !SKIPPED_APPOINTMENT_STATUSES.has(appointment.Status?.value))
            .sort((a, b) => String(a.SchedStartTime?.value || '').localeCompare(String(b.SchedStartTime?.value || '')));
    }

    /**
     * @description Related service appointment marked as a truck appointment.
     */
    _truckAppointment() {
        return this._openAppointments().find(appointment => appointment.TruckAppointment__c?.value === true) || null;
    }

    /**
     * @description Truck appointment scheduled for today.
     */
    _truckAppointmentForToday() {
        return this._openAppointments().find(appointment =>
            appointment.TruckAppointment__c?.value === true && this._isToday(appointment.SchedStartTime?.value)
        ) || null;
    }

    /**
     * @description Service appointment the new truck appointment is scheduled with.
     */
    _sourceAppointment() {
        return this._openAppointments().find(appointment => appointment.TruckAppointment__c?.value !== true) || null;
    }

    /**
     * @description Non-truck service appointment scheduled for today.
     */
    _sourceAppointmentForToday() {
        return this._openAppointments().find(appointment =>
            appointment.TruckAppointment__c?.value !== true && this._isToday(appointment.SchedStartTime?.value)
        ) || null;
    }

    /**
     * @description Assigned truck Service Resource Id on an appointment.
     */
    _assignedTruckId(appointment) {
        const assigned = this._assignedResourceRecord(appointment);
        const resourceId = assigned?.ServiceResourceId?.value;
        if (resourceId && this._truckResourceIds().has(resourceId)) {
            return resourceId;
        }
        return null;
    }

    /**
     * @description Service Resource Ids whose Technician Type is Truck.
     */
    _truckResourceIds() {
        return new Set(this._serviceLocationResources.map(resource => resource?.Id).filter(Boolean));
    }

    /**
     * @description Assigned Resource row for the truck, or the first assigned resource.
     */
    _assignedResourceRecord(appointment) {
        const edges = appointment?.ServiceResources?.edges ?? [];
        const truckIds = this._truckResourceIds();
        const truckEdge = edges.find(edge => truckIds.has(edge.node?.ServiceResourceId?.value));
        return (truckEdge || edges[0])?.node || null;
    }

    /**
     * @description Scheduled start and end on an appointment.
     */
    _scheduleTimes(appointment) {
        const start = appointment?.SchedStartTime?.value;
        const end = appointment?.SchedEndTime?.value;
        if (!start || !end) return null;
        return { SchedStartTime: start, SchedEndTime: end };
    }

    /**
     * @description Label for a Service Location option.
     */
    _serviceLocationOptionLabel(resourceId) {
        return this.serviceLocationOptions.find(option => option.value === resourceId)?.label || 'the selected truck';
    }

    /**
     * @description Territory shown for a Service Location option. The Work Order territory wins.
     */
    _serviceLocationTerritory(resource, woTerritoryId) {
        const today = new Date().toISOString().slice(0, 10);
        const members = (resource?.ServiceTerritories?.edges ?? [])
            .map(edge => edge.node)
            .filter(member => {
                const start = member?.EffectiveStartDate?.value;
                const end = member?.EffectiveEndDate?.value;
                if (start && start > today) return false;
                if (end && end < today) return false;
                return !!member?.ServiceTerritory?.Id;
            });
        const workOrderMatch = woTerritoryId
            ? members.find(member => member.ServiceTerritory.Id === woTerritoryId)
            : null;
        if (workOrderMatch) {
            return {
                name: workOrderMatch.ServiceTerritory.Name?.value ?? '',
                matchesWorkOrder: true
            };
        }
        const primary = members.find(member => {
            const territoryType = member.TerritoryType?.value;
            return territoryType === 'P' || territoryType === 'Primary';
        }) ?? members[0];
        return {
            name: primary?.ServiceTerritory?.Name?.value ?? '',
            matchesWorkOrder: false
        };
    }

    /**
     * @description Joins the non-empty parts of a list label with " - ".
     */
    _serviceLocationLabel(...parts) {
        return parts.filter(part => part).join(' - ');
    }

    /**
     * @description Empty territory names sort after named territories.
     */
    _territorySortKey(territoryName) {
        return territoryName ? territoryName : '\uffff';
    }

    /**
     * @description Persists Work Order location fields.
     */
    async _persistWorkOrderFields(fields) {
        if (!this.recordId || this.isOffline) return false;
        if (this._serviceLocationTypeUpdateable !== true && this._serviceLocationUpdateable !== true) {
            return false;
        }
        this._savingServiceLocation = true;
        try {
            await updateRecord({
                fields: {
                    Id: this.recordId,
                    ...fields
                }
            });
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            return true;
        } catch (error) {
            this._serviceLocationSelection = undefined;
            this._serviceLocationTypeSelection = undefined;
            this._locationSelection = undefined;
            this._toast('Error', this._errorMessage(error), 'error');
            return false;
        } finally {
            this._savingServiceLocation = false;
        }
    }

    /**
     * @description Refreshes the service appointment query after a Gantt change.
     */
    async _refreshServiceAppointments() {
        if (this.serviceAppointmentsGraphqlResult) {
            await refreshGraphQL(this.serviceAppointmentsGraphqlResult);
        }
    }

    /**
     * @description Creates or reassigns the truck appointment on the server.
     *              Field Service mobile rejects these writes through Lightning Data Service
     *              with LightningDataService.SQLiteResult error 5.
     */
    async _assignSelectedTruck(truckAppointment, truckId) {
        const source = this._sourceAppointmentForToday() || this._sourceAppointment();
        if (!truckAppointment) {
            if (!source?.Id || !this._scheduleTimes(source)) {
                this._toast(
                    'Truck appointment',
                    'Service Location was saved. The current service appointment needs a scheduled start and end before a truck can be assigned.',
                    'warning'
                );
                return;
            }
        } else if (!this._scheduleTimes(truckAppointment) && !this._scheduleTimes(source)) {
            this._toast(
                'Truck appointment',
                'Service Location was saved. The service appointment needs a scheduled start and end before the assigned resource can be updated.',
                'warning'
            );
            return;
        }
        await assignSelectedTruck({
            technicianAppointmentId: source?.Id || null,
            truckAppointmentId: truckAppointment?.Id || null,
            serviceResourceId: truckId
        });
        await this._refreshServiceAppointments();
    }

    /**
     * @description Service Location Type combobox change.
     */
    async handleServiceLocationTypeChange(event) {
        if (this._serviceLocationTypeUpdateable !== true || !this.recordId) return;
        const value = event.currentTarget?.dataset?.value || event.detail?.value || null;
        if (!value || value === this.serviceLocationTypeValue) return;
        this._serviceLocationDefaultApplied = true;
        this._serviceLocationTypeSelection = value;
        const fields = {
            [SERVICE_LOCATION_TYPE_FIELD.fieldApiName]: value
        };
        if (value !== TRUNK_LOCATION_TYPE) {
            this._serviceLocationSelection = null;
            fields[SERVICE_LOCATION_FIELD.fieldApiName] = null;
        }
        this._locationSelection = null;
        fields[WO_LOCATION_FIELD.fieldApiName] = null;
        await this._persistWorkOrderFields(fields);
    }

    /**
     * @description Service Location combobox change. A different truck updates the Gantt appointment.
     */
    async handleServiceLocationChange(event) {
        if (this._serviceLocationUpdateable !== true || !this.recordId) return;
        const value = event.detail.value || null;
        const previous = this.serviceLocationValue;
        if (value === previous) return;
        this._serviceLocationDefaultApplied = true;
        this._serviceLocationSelection = value;

        const truckAppointment = this._truckAppointmentForToday();
        const assignedTruckId = this._assignedTruckId(truckAppointment);
        const changesGantt = !!value && !!truckAppointment && value !== assignedTruckId;
        if (changesGantt) {
            const truckLabel = this._serviceLocationOptionLabel(value);
            const confirmed = await LightningConfirm.open({
                message: `${truckLabel} will replace the assigned resource on today's truck appointment. The Gantt will show this truck.`,
                label: 'Service Location',
                theme: 'warning'
            });
            if (!confirmed) {
                this._serviceLocationSelection = previous || null;
                return;
            }
        }
        const saved = await this._persistWorkOrderFields({
            [SERVICE_LOCATION_FIELD.fieldApiName]: value
        });
        if (!saved || !value) return;
        if (truckAppointment && !changesGantt) return;
        try {
            await this._assignSelectedTruck(truckAppointment, value);
        } catch (error) {
            this._toast('Truck appointment', this._errorMessage(error), 'error');
        }
    }

    /**
     * @description Location combobox change for a non-trunk Service Location Type.
     */
    handleLocationChange(event) {
        if (this._serviceLocationUpdateable !== true || !this.recordId) return;
        const value = event.detail.value || null;
        this._serviceLocationDefaultApplied = true;
        this._locationSelection = value;
        this._persistWorkOrderFields({
            [WO_LOCATION_FIELD.fieldApiName]: value
        });
    }
}