import { LightningElement, api, wire } from 'lwc';
import { gql, graphql, refreshGraphQL } from 'lightning/uiGraphQLApi';
import {
    updateRecord,
    createRecord,
    deleteRecord,
    getRecord,
    notifyRecordUpdateAvailable
} from 'lightning/uiRecordApi';
import { ShowToastEvent }        from 'lightning/platformShowToastEvent';
import LightningConfirm          from 'lightning/confirm';
import { CloseActionScreenEvent } from 'lightning/actions';

import WOLI_OBJECT       from '@salesforce/schema/WorkOrderLineItem';
import WOLI_DESCRIPTION  from '@salesforce/schema/WorkOrderLineItem.Description';
import WOLI_DURATION     from '@salesforce/schema/WorkOrderLineItem.Duration';
import WOLI_UNITPRICE    from '@salesforce/schema/WorkOrderLineItem.UnitPrice';
import WOLI_QUANTITY     from '@salesforce/schema/WorkOrderLineItem.Quantity';
import WOLI_EXPENSETYPE  from '@salesforce/schema/WorkOrderLineItem.ExpenseType__c';
import WOLI_WORKORDERID  from '@salesforce/schema/WorkOrderLineItem.WorkOrderId';
import WOLI_LINETYPE     from '@salesforce/schema/WorkOrderLineItem.LineType__c';
import WOLI_ASSIGNED_RES from '@salesforce/schema/WorkOrderLineItem.AssignedResource__c';
import WOLI_STARTDATE    from '@salesforce/schema/WorkOrderLineItem.StartDate';
import WOLI_ENDDATE      from '@salesforce/schema/WorkOrderLineItem.EndDate';
import WOLI_ASSETID      from '@salesforce/schema/WorkOrderLineItem.AssetId';
import WOLI_REPAIRCODE   from '@salesforce/schema/WorkOrderLineItem.RepairCode__c';

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
                            Account {
                                Name { value }
                            }
                            WorkOrderType__c { value }
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
                                        ExpenseType__c { value }
                                        LineType__c { value }
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

// Tab definitions — order here drives the UI tab order.
// `type`   = picklist value to filter on (null = catch-all "Other").
// `canAdd` = whether this tab shows an Add Line button.
// `schema` = which form/card layout to render:
//             'travel'     → AssignedResource + StartDate/EndDate/Duration
//             'labor'      → travel + Asset + RepairCode
//             'expense'    → AssignedResource + ExpenseType + UnitPrice + Quantity (+ read-only TotalPrice)
//             'asset_time' → AssignedResource + Asset + StartDate/EndDate/Duration  (Calibration & Other share)
//             'generic'    → fallback: Description/Duration/UnitPrice
const TAB_DEFS = [
    { key: 'Travel',      label: 'Travel',      addLabel: '+ Add Travel Line',      type: 'Travel',      canAdd: true,  schema: 'travel'     },
    { key: 'Labor',       label: 'Labor',       addLabel: '+ Add Labor Line',       type: 'Labor',       canAdd: true,  schema: 'labor'      },
    { key: 'Expense',     label: 'Expense',     addLabel: '+ Add Expense Line',     type: 'Expense',     canAdd: true,  schema: 'expense'    },
    { key: 'Calibration', label: 'Calibration', addLabel: '+ Add Calibration Line', type: 'Calibration', canAdd: true,  schema: 'asset_time' },
    { key: 'Other',       label: 'Other',       addLabel: '',                       type: null,          canAdd: false, schema: 'asset_time' }
];
const HIDDEN_TAB_KEYS = new Set(['Expense']);

// ExpenseType__c picklist values — sourced from the `ExpenseTypes` global value set.
// Hard-coded here (rather than fetched via getPicklistValues) to avoid an extra
// wire on every render; keep in sync with the GVS if values change in the org.
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
const TYPE_TO_DEF = TAB_DEFS.reduce((acc, d) => {
    if (d.type) acc[d.type] = d;
    return acc;
}, {});

const KNOWN_TYPES = new Set(TAB_DEFS.filter(d => d.type).map(d => d.type));

const EMPTY_ADD_FORM_VISIBILITY = () =>
    TAB_DEFS.filter(d => d.canAdd)
            .reduce((acc, d) => { acc[d.key] = false; return acc; }, {});

let _tempIdSeq = 0;

export default class woDebriefBackup extends LightningElement {
    @api recordId;

    graphqlResult;
    _workOrder    = null;
    _serverLines  = [];

    // ── Draft / pending state ────────────────────────────────────────────────
    _pendingEdits   = {};  // { [woliId]: { desc, duration, unitPrice } }
    _pendingDeletes = {};  // { [woliId]: true }
    _pendingAdds    = [];  // [{ _tempId, _lineType, desc, duration, unitPrice }]

    // Live per-row edit form state
    editStateMap = {};

    // Cache of Product2 Id -> Name for Repair Code helper text below the picker.
    // Pre-seeded from server data (RepairCode__r.Name); supplemented by an
    // on-demand @wire(getRecord) lookup driven by `_repairCodeLookupId` whenever
    // the user picks a code we haven't seen yet.
    _repairCodeNameById = {};
    _repairCodeLookupId;

    // Per-tab add-form visibility and field values (keyed by tab key)
    showAddForm  = EMPTY_ADD_FORM_VISIBILITY();
    addFormState = {
        desc: '', unitPrice: '',
        assignedResourceId: null, startDate: '', endDate: '',
        assetId: null, repairCodeId: null,
        expenseType: '', quantity: '',
        duration: ''
    };

    editErrors = {};
    addErrors  = {};

    // Re-entrancy guard for Save All (prevents double-tap issues where the second
    // tap tries to enqueue draft actions for records already removed in the first)
    _saving = false;

    activeTab = 'Travel';

    isOffline = !navigator.onLine;
    _onlineHandler  = () => { this.isOffline = false; };
    _offlineHandler = () => { this.isOffline = true;  };

    // ── Wire ─────────────────────────────────────────────────────────────────

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
                this._seedRepairCodeNameCache(this._serverLines);
            }
        }
    }

    // Pre-populate the Repair Code name cache from server data so existing
    // labor lines can show their Name helper text without an extra round-trip.
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

    get queryVariables() {
        return { workOrderId: this.recordId };
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        window.addEventListener('online',  this._onlineHandler);
        window.addEventListener('offline', this._offlineHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('online',  this._onlineHandler);
        window.removeEventListener('offline', this._offlineHandler);
    }

    // ── Computed state ────────────────────────────────────────────────────────

    get isLoading()    { return !this.graphqlResult?.data && !this.graphqlResult?.errors; }
    get hasError()     { return !!this.graphqlResult?.errors; }
    get errorMessage() { return JSON.stringify(this.graphqlResult?.errors); }
    get woStatus()     { return this._workOrder?.Status?.value ?? ''; }
    get woAccountName(){ return this._workOrder?.Account?.Name?.value ?? ''; }
    get woType()       { return this._workOrder?.WorkOrderType__c?.value ?? ''; }
    get woNumber()     { return this._workOrder?.WorkOrderNumber?.value ?? ''; }

    get hasPendingChanges() {
        return Object.keys(this._pendingEdits).length   > 0 ||
               Object.keys(this._pendingDeletes).length > 0 ||
               this._pendingAdds.length > 0;
    }

    get saveAllDisabled() {
        return !this.hasPendingChanges || this._saving;
    }

    get cancelDisabled() {
        return this._saving;
    }

    // ── Tabs (data-driven from TAB_DEFS) ──────────────────────────────────────

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

    get activeTabModel() {
        return this.tabs.find(t => t.isActive) ?? this.tabs[0];
    }

    // Convenience flags — LWC templates can't compare strings directly.
    get isActiveTabTravel()    { return this.activeTabModel?.schema === 'travel'; }
    get isActiveTabLabor()     { return this.activeTabModel?.schema === 'labor'; }
    get isActiveTabExpense()   { return this.activeTabModel?.schema === 'expense'; }
    get isActiveTabAssetTime() { return this.activeTabModel?.schema === 'asset_time'; }

    get expenseTypeOptions() { return EXPENSE_TYPE_OPTIONS; }

    // Live total-price preview for the Expense add-form (UnitPrice × Quantity).
    // Mirrors the server-side TotalPrice formula (read-only on WOLI).
    get computedAddTotalPrice() {
        const u = Number(this.addFormState.unitPrice) || 0;
        const q = Number(this.addFormState.quantity)  || 0;
        return (u * q).toFixed(2);
    }

    // ── Picker configs (filter + displayInfo + matchingInfo) ─────────────────

    // AssignedResource → ServiceResource, only active records.
    get resourcePickerFilter() {
        return {
            criteria: [
                { fieldPath: 'IsActive', operator: 'eq', value: true }
            ]
        };
    }
    get resourcePickerDisplayInfo() {
        return { primaryField: 'Name' };
    }
    get resourcePickerMatchingInfo() {
        return { primaryField: { fieldPath: 'Name' } };
    }

    // Asset → no filter; show SerialNumber as the primary value (with Name as
    // secondary so users can find an Asset by either field).
    get assetPickerDisplayInfo() {
        return { primaryField: 'SerialNumber', additionalFields: ['Name'] };
    }
    get assetPickerMatchingInfo() {
        return {
            primaryField: { fieldPath: 'SerialNumber' },
            additionalFields: [{ fieldPath: 'Name' }]
        };
    }

    // Repair Code → Product2 with ProductType__c = 'Service Code'. Show
    // ProductCode as the primary value (with Name as secondary for context).
    get repairCodePickerFilter() {
        return {
            criteria: [
                { fieldPath: 'ProductType__c', operator: 'eq', value: 'Service Code' }
            ]
        };
    }
    get repairCodePickerDisplayInfo() {
        return { primaryField: 'ProductCode', additionalFields: ['Name'] };
    }
    get repairCodePickerMatchingInfo() {
        return {
            primaryField: { fieldPath: 'ProductCode' },
            additionalFields: [{ fieldPath: 'Name' }]
        };
    }

    _buildLinesFor(def) {
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
        // Expense: sort by ExpenseType ASC, then LineItemNumber.
        // Generic: leave in natural (LineItemNumber) order.
        const merged = [...existing, ...adds];
        if (def.schema === 'travel' || def.schema === 'labor' || def.schema === 'asset_time') {
            merged.sort((a, b) => {
                const aMs = a.startDateMs ?? Number.POSITIVE_INFINITY;
                const bMs = b.startDateMs ?? Number.POSITIVE_INFINITY;
                if (aMs !== bMs) return aMs - bMs;
                return (a.lineNumber || '').localeCompare(b.lineNumber || '');
            });
        } else if (def.schema === 'expense') {
            merged.sort((a, b) => {
                const aT = (a.expenseType || '\uffff'); // empty sorts last
                const bT = (b.expenseType || '\uffff');
                if (aT !== bT) return aT.localeCompare(bT);
                return (a.lineNumber || '').localeCompare(b.lineNumber || '');
            });
        }
        return merged;
    }

    _modelBuilderForSchema(schema) {
        if (schema === 'travel')     return this._buildTravelLineModel;
        if (schema === 'labor')      return this._buildLaborLineModel;
        if (schema === 'expense')    return this._buildExpenseLineModel;
        if (schema === 'asset_time') return this._buildAssetTimeLineModel;
        return this._buildGenericLineModel;
    }

    _addModelBuilderForSchema(schema) {
        if (schema === 'travel')     return this._buildTravelAddModel;
        if (schema === 'labor')      return this._buildLaborAddModel;
        if (schema === 'expense')    return this._buildExpenseAddModel;
        if (schema === 'asset_time') return this._buildAssetTimeAddModel;
        return this._buildGenericAddModel;
    }

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

    _buildTravelLineModel(l, edit, state, showLineType) {
        const lineType        = l.LineType__c?.value ?? '';
        const assignedResId   = edit?.assignedResourceId ?? l.AssignedResource__c?.value ?? null;
        const assignedResName = l.AssignedResource__r?.Name?.value ?? '';
        const startDate       = edit?.startDate ?? l.StartDate?.value ?? '';
        const endDate         = edit?.endDate   ?? l.EndDate?.value   ?? '';
        const duration        = edit?.duration  ?? l.Duration?.value  ?? 0;
        return {
            Id:                  l.Id,
            lineNumber:          l.LineItemNumber?.value ?? '',
            schema:              'travel',
            isTravelSchema:      true,
            isLaborSchema:       false,
            isExpenseSchema:     false,
            isAssetTimeSchema:   false,
            // Card display
            title:               assignedResName || 'Unassigned',
            metaLine:            this._fmtTravelMeta(startDate, endDate, duration),
            lineType,
            lineTypeLabel:       lineType || 'No Type',
            showLineType,
            // Travel fields
            assignedResourceId:  assignedResId,
            assignedResourceName:assignedResName,
            startDate,
            endDate,
            startDateMs:         this._toMs(startDate),
            duration,
            // Edit state
            isEditing:           state.isEditing ?? false,
            editAssignedResId:   state.assignedResourceId ?? edit?.assignedResourceId ?? l.AssignedResource__c?.value ?? null,
            editStartDate:       state.startDate ?? edit?.startDate ?? l.StartDate?.value ?? '',
            editEndDate:         state.endDate   ?? edit?.endDate   ?? l.EndDate?.value   ?? '',
            editDuration:        state.duration  ?? edit?.duration  ?? l.Duration?.value  ?? 0,
            editError:           this.editErrors[l.Id] ?? '',
            isDirty:             !!edit,
            isNew:               false
        };
    }

    _buildTravelAddModel(a, state) {
        const assignedResId = state.isEditing ? (state.assignedResourceId ?? a.assignedResourceId) : a.assignedResourceId;
        const startDate     = state.isEditing ? (state.startDate ?? a.startDate) : a.startDate;
        const endDate       = state.isEditing ? (state.endDate   ?? a.endDate)   : a.endDate;
        const duration      = state.isEditing ? (state.duration  ?? a.duration)  : a.duration;
        // For unsaved adds we don't have the resolved Name yet; show a placeholder.
        // (After save, the GraphQL refresh will populate AssignedResource__r.Name.)
        const titleName     = a.assignedResourceName || 'Assigned Resource pending…';
        return {
            Id:                  a._tempId,
            lineNumber:          '',
            schema:              'travel',
            isTravelSchema:      true,
            isLaborSchema:       false,
            isExpenseSchema:     false,
            isAssetTimeSchema:   false,
            title:               assignedResId ? titleName : 'Unassigned',
            metaLine:            this._fmtTravelMeta(startDate, endDate, duration),
            lineType:            a._lineType,
            lineTypeLabel:       a._lineType,
            showLineType:        false,
            assignedResourceId:  assignedResId,
            assignedResourceName:titleName,
            startDate,
            endDate,
            startDateMs:         this._toMs(startDate),
            duration,
            isEditing:           state.isEditing ?? false,
            editAssignedResId:   state.assignedResourceId ?? a.assignedResourceId ?? null,
            editStartDate:       state.startDate ?? a.startDate ?? '',
            editEndDate:         state.endDate   ?? a.endDate   ?? '',
            editDuration:        state.duration  ?? a.duration  ?? 0,
            editError:           this.editErrors[a._tempId] ?? '',
            isDirty:             false,
            isNew:               true
        };
    }

    _buildLaborLineModel(l, edit, state, showLineType) {
        const lineType         = l.LineType__c?.value ?? '';
        const assignedResId    = edit?.assignedResourceId ?? l.AssignedResource__c?.value ?? null;
        const assignedResName  = l.AssignedResource__r?.Name?.value ?? '';
        const assetId          = edit?.assetId ?? l.AssetId?.value ?? null;
        const assetSerial      = l.Asset?.SerialNumber?.value ?? '';
        const repairCodeId     = edit?.repairCodeId ?? l.RepairCode__c?.value ?? null;
        const repairCodeStr    = l.RepairCode__r?.ProductCode?.value ?? '';
        const editRepairCodeId = state.repairCodeId ?? edit?.repairCodeId ?? l.RepairCode__c?.value ?? null;
        const editRepairCodeName = this._repairCodeNameById[editRepairCodeId] ?? '';
        const startDate        = edit?.startDate ?? l.StartDate?.value ?? '';
        const endDate          = edit?.endDate   ?? l.EndDate?.value   ?? '';
        const duration         = edit?.duration  ?? l.Duration?.value  ?? 0;
        return {
            Id:                   l.Id,
            lineNumber:           l.LineItemNumber?.value ?? '',
            schema:               'labor',
            isTravelSchema:       false,
            isLaborSchema:        true,
            isExpenseSchema:      false,
            isAssetTimeSchema:    false,
            // Card display
            title:                assignedResName || 'Unassigned',
            metaLine:             this._fmtLaborMeta(assetSerial, repairCodeStr, startDate, endDate, duration),
            lineType,
            lineTypeLabel:        lineType || 'No Type',
            showLineType,
            // Labor fields
            assignedResourceId:   assignedResId,
            assignedResourceName: assignedResName,
            assetId,
            assetSerialNumber:    assetSerial,
            repairCodeId,
            repairCodeProductCode:repairCodeStr,
            startDate,
            endDate,
            startDateMs:          this._toMs(startDate),
            duration,
            // Edit state
            isEditing:            state.isEditing ?? false,
            editAssignedResId:    state.assignedResourceId ?? edit?.assignedResourceId ?? l.AssignedResource__c?.value ?? null,
            editAssetId:          state.assetId       ?? edit?.assetId       ?? l.AssetId?.value          ?? null,
            editRepairCodeId,
            editRepairCodeName,
            editStartDate:        state.startDate     ?? edit?.startDate     ?? l.StartDate?.value        ?? '',
            editEndDate:          state.endDate       ?? edit?.endDate       ?? l.EndDate?.value          ?? '',
            editDuration:         state.duration      ?? edit?.duration      ?? l.Duration?.value         ?? 0,
            editError:            this.editErrors[l.Id] ?? '',
            isDirty:              !!edit,
            isNew:                false
        };
    }

    _buildLaborAddModel(a, state) {
        const assignedResId = state.isEditing ? (state.assignedResourceId ?? a.assignedResourceId) : a.assignedResourceId;
        const assetId       = state.isEditing ? (state.assetId       ?? a.assetId)       : a.assetId;
        const repairCodeId  = state.isEditing ? (state.repairCodeId  ?? a.repairCodeId)  : a.repairCodeId;
        const editRepairCodeId   = state.repairCodeId ?? a.repairCodeId ?? null;
        const editRepairCodeName = this._repairCodeNameById[editRepairCodeId] ?? '';
        const startDate     = state.isEditing ? (state.startDate     ?? a.startDate)     : a.startDate;
        const endDate       = state.isEditing ? (state.endDate       ?? a.endDate)       : a.endDate;
        const duration      = state.isEditing ? (state.duration      ?? a.duration)      : a.duration;
        // Names aren't resolved until after save → placeholder for the title.
        const titleName     = a.assignedResourceName || 'Assigned Resource pending…';
        return {
            Id:                   a._tempId,
            lineNumber:           '',
            schema:               'labor',
            isTravelSchema:       false,
            isLaborSchema:        true,
            isExpenseSchema:      false,
            isAssetTimeSchema:    false,
            title:                assignedResId ? titleName : 'Unassigned',
            metaLine:             this._fmtLaborMeta('', '', startDate, endDate, duration),
            lineType:             a._lineType,
            lineTypeLabel:        a._lineType,
            showLineType:         false,
            assignedResourceId:   assignedResId,
            assignedResourceName: titleName,
            assetId,
            assetSerialNumber:    '',
            repairCodeId,
            repairCodeProductCode:'',
            startDate,
            endDate,
            startDateMs:          this._toMs(startDate),
            duration,
            isEditing:            state.isEditing ?? false,
            editAssignedResId:    state.assignedResourceId ?? a.assignedResourceId ?? null,
            editAssetId:          state.assetId            ?? a.assetId            ?? null,
            editRepairCodeId,
            editRepairCodeName,
            editStartDate:        state.startDate          ?? a.startDate          ?? '',
            editEndDate:          state.endDate            ?? a.endDate            ?? '',
            editDuration:         state.duration           ?? a.duration           ?? 0,
            editError:            this.editErrors[a._tempId] ?? '',
            isDirty:              false,
            isNew:                true
        };
    }

    _buildExpenseLineModel(l, edit, state, showLineType) {
        const lineType        = l.LineType__c?.value ?? '';
        const assignedResId   = edit?.assignedResourceId ?? l.AssignedResource__c?.value ?? null;
        const assignedResName = l.AssignedResource__r?.Name?.value ?? '';
        const expenseType     = edit?.expenseType ?? l.ExpenseType__c?.value ?? '';
        const unitPrice       = edit?.unitPrice   ?? l.UnitPrice?.value      ?? 0;
        const quantity        = edit?.quantity    ?? l.Quantity?.value       ?? 0;
        // TotalPrice on WOLI is read-only / auto-calculated. Show the persisted
        // value when present; otherwise compute the preview locally so unsaved
        // edits / new lines still display a sensible total.
        const persistedTotal  = l.TotalPrice?.value;
        const computedTotal   = (Number(unitPrice) || 0) * (Number(quantity) || 0);
        const totalPrice      = (persistedTotal != null && !edit) ? persistedTotal : computedTotal;
        const editUnit        = state.unitPrice ?? edit?.unitPrice ?? l.UnitPrice?.value ?? 0;
        const editQty         = state.quantity  ?? edit?.quantity  ?? l.Quantity?.value  ?? 0;
        return {
            Id:                  l.Id,
            lineNumber:          l.LineItemNumber?.value ?? '',
            schema:              'expense',
            isTravelSchema:      false,
            isLaborSchema:       false,
            isExpenseSchema:     true,
            isAssetTimeSchema:   false,
            // Card display
            title:               expenseType || 'Unspecified Expense',
            metaLine:            this._fmtExpenseMeta(quantity, unitPrice, totalPrice, assignedResName),
            lineType,
            lineTypeLabel:       lineType || 'No Type',
            showLineType,
            // Expense fields
            assignedResourceId:  assignedResId,
            assignedResourceName:assignedResName,
            expenseType,
            unitPrice,
            quantity,
            totalPrice:          this._fmtMoney(totalPrice),
            // Edit state
            isEditing:           state.isEditing ?? false,
            editAssignedResId:   state.assignedResourceId ?? edit?.assignedResourceId ?? l.AssignedResource__c?.value ?? null,
            editExpenseType:     state.expenseType ?? edit?.expenseType ?? l.ExpenseType__c?.value ?? '',
            editUnitPrice:       editUnit,
            editQuantity:        editQty,
            editTotalPrice:      this._fmtMoney((Number(editUnit) || 0) * (Number(editQty) || 0)),
            editError:           this.editErrors[l.Id] ?? '',
            isDirty:             !!edit,
            isNew:               false
        };
    }

    _buildExpenseAddModel(a, state) {
        const assignedResId = state.isEditing ? (state.assignedResourceId ?? a.assignedResourceId) : a.assignedResourceId;
        const expenseType   = state.isEditing ? (state.expenseType ?? a.expenseType) : a.expenseType;
        const unitPrice     = state.isEditing ? (state.unitPrice   ?? a.unitPrice)   : a.unitPrice;
        const quantity      = state.isEditing ? (state.quantity    ?? a.quantity)    : a.quantity;
        const totalPrice    = (Number(unitPrice) || 0) * (Number(quantity) || 0);
        const titleName     = a.assignedResourceName || 'Assigned Resource pending…';
        return {
            Id:                  a._tempId,
            lineNumber:          '',
            schema:              'expense',
            isTravelSchema:      false,
            isLaborSchema:       false,
            isExpenseSchema:     true,
            isAssetTimeSchema:   false,
            title:               expenseType || 'Unspecified Expense',
            metaLine:            this._fmtExpenseMeta(quantity, unitPrice, totalPrice, assignedResId ? titleName : ''),
            lineType:            a._lineType,
            lineTypeLabel:       a._lineType,
            showLineType:        false,
            assignedResourceId:  assignedResId,
            assignedResourceName:titleName,
            expenseType,
            unitPrice,
            quantity,
            totalPrice:          this._fmtMoney(totalPrice),
            isEditing:           state.isEditing ?? false,
            editAssignedResId:   state.assignedResourceId ?? a.assignedResourceId ?? null,
            editExpenseType:     state.expenseType ?? a.expenseType ?? '',
            editUnitPrice:       state.unitPrice   ?? a.unitPrice   ?? 0,
            editQuantity:        state.quantity    ?? a.quantity    ?? 0,
            editTotalPrice:      this._fmtMoney(totalPrice),
            editError:           this.editErrors[a._tempId] ?? '',
            isDirty:             false,
            isNew:               true
        };
    }

    // Calibration & Other share this schema (Resource + Asset + StartDate/EndDate/Duration).
    _buildAssetTimeLineModel(l, edit, state, showLineType) {
        const lineType        = l.LineType__c?.value ?? '';
        const assignedResId   = edit?.assignedResourceId ?? l.AssignedResource__c?.value ?? null;
        const assignedResName = l.AssignedResource__r?.Name?.value ?? '';
        const assetId         = edit?.assetId ?? l.AssetId?.value ?? null;
        const assetSerial     = l.Asset?.SerialNumber?.value ?? '';
        const startDate       = edit?.startDate ?? l.StartDate?.value ?? '';
        const endDate         = edit?.endDate   ?? l.EndDate?.value   ?? '';
        const duration        = edit?.duration  ?? l.Duration?.value  ?? 0;
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
            metaLine:            this._fmtAssetTimeMeta(assetSerial, startDate, endDate, duration),
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
            duration,
            // Edit state
            isEditing:           state.isEditing ?? false,
            editAssignedResId:   state.assignedResourceId ?? edit?.assignedResourceId ?? l.AssignedResource__c?.value ?? null,
            editAssetId:         state.assetId    ?? edit?.assetId    ?? l.AssetId?.value    ?? null,
            editStartDate:       state.startDate  ?? edit?.startDate  ?? l.StartDate?.value ?? '',
            editEndDate:         state.endDate    ?? edit?.endDate    ?? l.EndDate?.value   ?? '',
            editDuration:        state.duration   ?? edit?.duration   ?? l.Duration?.value  ?? 0,
            editError:           this.editErrors[l.Id] ?? '',
            isDirty:             !!edit,
            isNew:               false
        };
    }

    _buildAssetTimeAddModel(a, state) {
        const assignedResId = state.isEditing ? (state.assignedResourceId ?? a.assignedResourceId) : a.assignedResourceId;
        const assetId       = state.isEditing ? (state.assetId    ?? a.assetId)    : a.assetId;
        const startDate     = state.isEditing ? (state.startDate  ?? a.startDate)  : a.startDate;
        const endDate       = state.isEditing ? (state.endDate    ?? a.endDate)    : a.endDate;
        const duration      = state.isEditing ? (state.duration   ?? a.duration)   : a.duration;
        const titleName     = a.assignedResourceName || 'Assigned Resource pending…';
        return {
            Id:                  a._tempId,
            lineNumber:          '',
            schema:              'asset_time',
            isTravelSchema:      false,
            isLaborSchema:       false,
            isExpenseSchema:     false,
            isAssetTimeSchema:   true,
            title:               assignedResId ? titleName : 'Unassigned',
            metaLine:            this._fmtAssetTimeMeta('', startDate, endDate, duration),
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
            duration,
            isEditing:           state.isEditing ?? false,
            editAssignedResId:   state.assignedResourceId ?? a.assignedResourceId ?? null,
            editAssetId:         state.assetId    ?? a.assetId    ?? null,
            editStartDate:       state.startDate  ?? a.startDate  ?? '',
            editEndDate:         state.endDate    ?? a.endDate    ?? '',
            editDuration:        state.duration   ?? a.duration   ?? 0,
            editError:           this.editErrors[a._tempId] ?? '',
            isDirty:             false,
            isNew:               true
        };
    }

    _fmtExpenseMeta(quantity, unitPrice, totalPrice, resourceName) {
        const parts = [];
        const q = (quantity != null && quantity !== '') ? quantity : 0;
        const u = this._fmtMoney(unitPrice);
        const t = this._fmtMoney(totalPrice);
        parts.push(`${q} × $${u} = $${t}`);
        if (resourceName) parts.push(resourceName);
        return parts.join(' · ');
    }

    _fmtAssetTimeMeta(assetSerial, startDate, endDate, duration) {
        const parts = [];
        if (assetSerial) parts.push(`SN ${assetSerial}`);
        const range = this._fmtDateRange(startDate, endDate);
        if (range) parts.push(range);
        if (duration != null && duration !== '') parts.push(`${duration} hrs`);
        return parts.join(' · ');
    }

    _fmtMoney(n) {
        const num = Number(n);
        if (!Number.isFinite(num)) return '0.00';
        return num.toFixed(2);
    }

    _fmtLaborMeta(assetSerial, repairCode, startDate, endDate, duration) {
        const parts = [];
        if (assetSerial) parts.push(`SN ${assetSerial}`);
        if (repairCode)  parts.push(repairCode);
        const range = this._fmtDateRange(startDate, endDate);
        if (range) parts.push(range);
        if (duration != null && duration !== '') parts.push(`${duration} hrs`);
        return parts.join(' · ');
    }

    _fmtTravelMeta(startDate, endDate, duration) {
        const parts = [];
        const range = this._fmtDateRange(startDate, endDate);
        if (range) parts.push(range);
        if (duration != null && duration !== '') parts.push(`${duration} hrs`);
        return parts.join(' · ');
    }

    _fmtDateRange(startDate, endDate) {
        const s = this._fmtDateTime(startDate);
        const e = this._fmtDateTime(endDate);
        if (s && e) return `${s} → ${e}`;
        if (s)      return s;
        if (e)      return `→ ${e}`;
        return '';
    }

    _fmtDateTime(iso) {
        if (!iso) return '';
        const d = new Date(iso);
        if (Number.isNaN(d.getTime())) return '';
        return d.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
    }

    _toMs(iso) {
        if (!iso) return null;
        const t = new Date(iso).getTime();
        return Number.isNaN(t) ? null : t;
    }

    // ── Tab ───────────────────────────────────────────────────────────────────

    handleTabSelect(e) { this.activeTab = e.currentTarget.dataset.tab; }

    // ── Inline edit (autosave-to-draft) ───────────────────────────────────────
    //
    // UX model: there is NO per-row Done/Cancel. Tapping the pencil/card body
    // just opens or closes the inline form (visual only). Every field change
    // commits straight into _pendingEdits (existing rows) or _pendingAdds
    // (new rows), so the "Modified" badge appears immediately and Save All
    // commits whatever is staged. The footer "Cancel" still discards all
    // unsaved drafts in one go.

    // Bound to BOTH the pencil button and the .woli-info card body, so a tap
    // anywhere on the line text or the pencil toggles the inline edit form.
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

    handleEditFieldChange(e) {
        const id    = e.currentTarget.dataset.id;
        const field = e.currentTarget.dataset.field;
        this._stageEdit(id, field, e.detail.value);
    }

    // ── Delete (draft only) ───────────────────────────────────────────────────

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

    handleAddToggle(e) {
        const tab = e.currentTarget.dataset.tab;
        const cur = this.showAddForm[tab];
        this.showAddForm  = { ...this.showAddForm, [tab]: !cur };
        if (!cur) {
            this.addFormState = this._emptyAddFormState();
            this.addErrors    = {};
        }
    }

    handleAddFieldChange(e) {
        const field = e.currentTarget.dataset.field;
        this.addFormState = { ...this.addFormState, [field]: e.detail.value };
    }

    // lightning-record-picker emits `change` with `event.detail.recordId` rather
    // than `event.detail.value`. Field name carried via data-field as usual.
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
        // Repair Code helper-text support: trigger the on-demand wire to fetch
        // the Product Name for any code we haven't cached yet.
        if (field === 'repairCodeId' && recordId && !this._repairCodeNameById[recordId]) {
            this._repairCodeLookupId = recordId;
        }
    }

    // Helper text for the Add Labor Line form's Repair Code picker.
    get addFormRepairCodeName() {
        return this._repairCodeNameById[this.addFormState.repairCodeId] ?? '';
    }

    handleAddConfirm(e) {
        const tab    = e.currentTarget.dataset.tab;
        const def    = TYPE_TO_DEF[tab];
        const schema = def?.schema ?? 'generic';
        const errMsg = this._validateForSchema(schema, this.addFormState);
        if (errMsg) {
            this.addErrors = { ...this.addErrors, [tab]: errMsg };
            return;
        }
        _tempIdSeq += 1;
        const baseAdd = {
            _tempId:   `_new_${_tempIdSeq}`,
            _lineType: tab,
            _schema:   schema
        };
        let newAdd;
        if (schema === 'travel') {
            newAdd = {
                ...baseAdd,
                assignedResourceId: this.addFormState.assignedResourceId,
                startDate:          this.addFormState.startDate || null,
                endDate:            this.addFormState.endDate   || null,
                duration:           Number(this.addFormState.duration)
            };
        } else if (schema === 'labor') {
            newAdd = {
                ...baseAdd,
                assignedResourceId: this.addFormState.assignedResourceId,
                assetId:            this.addFormState.assetId,
                repairCodeId:       this.addFormState.repairCodeId,
                startDate:          this.addFormState.startDate || null,
                endDate:            this.addFormState.endDate   || null,
                duration:           Number(this.addFormState.duration)
            };
        } else if (schema === 'expense') {
            newAdd = {
                ...baseAdd,
                assignedResourceId: this.addFormState.assignedResourceId,
                expenseType:        this.addFormState.expenseType,
                unitPrice:          Number(this.addFormState.unitPrice) || 0,
                quantity:           Number(this.addFormState.quantity)  || 0
            };
        } else if (schema === 'asset_time') {
            newAdd = {
                ...baseAdd,
                assignedResourceId: this.addFormState.assignedResourceId,
                assetId:            this.addFormState.assetId,
                startDate:          this.addFormState.startDate || null,
                endDate:            this.addFormState.endDate   || null,
                duration:           Number(this.addFormState.duration)
            };
        } else {
            newAdd = {
                ...baseAdd,
                desc:      this.addFormState.desc,
                duration:  Number(this.addFormState.duration),
                unitPrice: Number(this.addFormState.unitPrice) || 0
            };
        }
        this._pendingAdds = [...this._pendingAdds, newAdd];
        this.showAddForm  = { ...this.showAddForm, [tab]: false };
        this.addFormState = this._emptyAddFormState();
        const errs = { ...this.addErrors };
        delete errs[tab];
        this.addErrors = errs;
    }

    handleAddCancel(e) {
        const tab = e.currentTarget.dataset.tab;
        this.showAddForm = { ...this.showAddForm, [tab]: false };
        const errs = { ...this.addErrors };
        delete errs[tab];
        this.addErrors = errs;
    }

    // ── Global Save All ───────────────────────────────────────────────────────

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
                        [WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
                        [WOLI_STARTDATE.fieldApiName]:    edit.startDate || null,
                        [WOLI_ENDDATE.fieldApiName]:      edit.endDate   || null,
                        [WOLI_DURATION.fieldApiName]:     Number(edit.duration) || 0
                    };
                } else if (schema === 'labor') {
                    fields = {
                        Id: id,
                        [WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
                        [WOLI_ASSETID.fieldApiName]:      edit.assetId,
                        [WOLI_REPAIRCODE.fieldApiName]:   edit.repairCodeId,
                        [WOLI_STARTDATE.fieldApiName]:    edit.startDate || null,
                        [WOLI_ENDDATE.fieldApiName]:      edit.endDate   || null,
                        [WOLI_DURATION.fieldApiName]:     Number(edit.duration) || 0
                    };
                } else if (schema === 'expense') {
                    fields = {
                        Id: id,
                        [WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
                        [WOLI_EXPENSETYPE.fieldApiName]:  edit.expenseType,
                        [WOLI_UNITPRICE.fieldApiName]:    Number(edit.unitPrice) || 0,
                        [WOLI_QUANTITY.fieldApiName]:     Number(edit.quantity)  || 0
                        // TotalPrice omitted: read-only, auto-calculated by Salesforce.
                    };
                } else if (schema === 'asset_time') {
                    fields = {
                        Id: id,
                        [WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
                        [WOLI_ASSETID.fieldApiName]:      edit.assetId,
                        [WOLI_STARTDATE.fieldApiName]:    edit.startDate || null,
                        [WOLI_ENDDATE.fieldApiName]:      edit.endDate   || null,
                        [WOLI_DURATION.fieldApiName]:     Number(edit.duration) || 0
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
                        [WOLI_STARTDATE.fieldApiName]:    a.startDate || null,
                        [WOLI_ENDDATE.fieldApiName]:      a.endDate   || null,
                        [WOLI_DURATION.fieldApiName]:     Number(a.duration) || 0,
                        DurationType:                     'Hours'
                    };
                } else if (schema === 'labor') {
                    fields = {
                        [WOLI_WORKORDERID.fieldApiName]:  this.recordId,
                        [WOLI_LINETYPE.fieldApiName]:     a._lineType,
                        [WOLI_ASSIGNED_RES.fieldApiName]: a.assignedResourceId,
                        [WOLI_ASSETID.fieldApiName]:      a.assetId,
                        [WOLI_REPAIRCODE.fieldApiName]:   a.repairCodeId,
                        [WOLI_STARTDATE.fieldApiName]:    a.startDate || null,
                        [WOLI_ENDDATE.fieldApiName]:      a.endDate   || null,
                        [WOLI_DURATION.fieldApiName]:     Number(a.duration) || 0,
                        DurationType:                     'Hours'
                    };
                } else if (schema === 'expense') {
                    fields = {
                        [WOLI_WORKORDERID.fieldApiName]:  this.recordId,
                        [WOLI_LINETYPE.fieldApiName]:     a._lineType,
                        [WOLI_ASSIGNED_RES.fieldApiName]: a.assignedResourceId,
                        [WOLI_EXPENSETYPE.fieldApiName]:  a.expenseType,
                        [WOLI_UNITPRICE.fieldApiName]:    Number(a.unitPrice) || 0,
                        [WOLI_QUANTITY.fieldApiName]:     Number(a.quantity)  || 0
                        // TotalPrice omitted: read-only, auto-calculated by Salesforce.
                    };
                } else if (schema === 'asset_time') {
                    fields = {
                        [WOLI_WORKORDERID.fieldApiName]:  this.recordId,
                        [WOLI_LINETYPE.fieldApiName]:     a._lineType,
                        [WOLI_ASSIGNED_RES.fieldApiName]: a.assignedResourceId,
                        [WOLI_ASSETID.fieldApiName]:      a.assetId,
                        [WOLI_STARTDATE.fieldApiName]:    a.startDate || null,
                        [WOLI_ENDDATE.fieldApiName]:      a.endDate   || null,
                        [WOLI_DURATION.fieldApiName]:     Number(a.duration) || 0,
                        DurationType:                     'Hours'
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
                // eslint-disable-next-line no-await-in-loop
                const result = await createRecord({ apiName: WOLI_OBJECT.objectApiName, fields });
                if (result?.id) okIds.push(result.id);
            } catch (err) {
                failedAdds.push(a);
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
            this._toast('Partial Save', `${anyFailed} change(s) failed to save. Review the highlighted lines and try again.`, 'warning');
        }
    }

    // ── Global Cancel / Discard ───────────────────────────────────────────────

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
    _emptyAddFormState() {
        return {
            // generic + expense schemas
            desc:               '',
            unitPrice:          '',
            // travel + labor + asset_time schemas
            assignedResourceId: null,
            startDate:          '',
            endDate:            '',
            // labor + asset_time schemas
            assetId:            null,
            // labor schema
            repairCodeId:       null,
            // expense schema
            expenseType:        '',
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
    _stageEdit(id, field, value) {
        if (this._pendingAdds.some(a => a._tempId === id)) {
            this._pendingAdds = this._pendingAdds.map(a =>
                a._tempId === id ? { ...a, [field]: value } : a
            );
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
    _seedEditEntry(line) {
        const schema = this._schemaForLineType(line.LineType__c?.value);
        if (schema === 'travel') {
            return {
                _schema:            'travel',
                assignedResourceId: line.AssignedResource__c?.value ?? null,
                startDate:          line.StartDate?.value ?? '',
                endDate:            line.EndDate?.value   ?? '',
                duration:           line.Duration?.value  ?? 0
            };
        }
        if (schema === 'labor') {
            return {
                _schema:            'labor',
                assignedResourceId: line.AssignedResource__c?.value ?? null,
                assetId:            line.AssetId?.value          ?? null,
                repairCodeId:       line.RepairCode__c?.value    ?? null,
                startDate:          line.StartDate?.value        ?? '',
                endDate:            line.EndDate?.value          ?? '',
                duration:           line.Duration?.value         ?? 0
            };
        }
        if (schema === 'expense') {
            return {
                _schema:            'expense',
                assignedResourceId: line.AssignedResource__c?.value ?? null,
                expenseType:        line.ExpenseType__c?.value      ?? '',
                unitPrice:          line.UnitPrice?.value           ?? 0,
                quantity:           line.Quantity?.value            ?? 0
            };
        }
        if (schema === 'asset_time') {
            return {
                _schema:            'asset_time',
                assignedResourceId: line.AssignedResource__c?.value ?? null,
                assetId:            line.AssetId?.value             ?? null,
                startDate:          line.StartDate?.value           ?? '',
                endDate:            line.EndDate?.value             ?? '',
                duration:           line.Duration?.value            ?? 0
            };
        }
        return {
            _schema:   'generic',
            desc:      line.Description?.value ?? '',
            duration:  line.Duration?.value    ?? 0,
            unitPrice: line.UnitPrice?.value   ?? 0
        };
    }

    _validateGeneric({ desc, duration }) {
        if (!desc || String(desc).trim() === '') return 'Description is required.';
        if (!duration || Number(duration) <= 0)   return 'Duration must be greater than 0.';
        return null;
    }

    _validateTravel({ assignedResourceId, duration, startDate, endDate }) {
        if (!assignedResourceId)                  return 'Assigned Resource is required.';
        if (!duration || Number(duration) <= 0)   return 'Duration must be greater than 0.';
        if (startDate && endDate && new Date(endDate).getTime() < new Date(startDate).getTime()) {
            return 'End Date must be the same as or after Start Date.';
        }
        return null;
    }

    // Labor uses the same required-field set as Travel (Resource + Duration);
    // Asset and RepairCode are optional. Date sanity check mirrors Travel.
    _validateLabor({ assignedResourceId, duration, startDate, endDate }) {
        if (!assignedResourceId)                  return 'Assigned Resource is required.';
        if (!duration || Number(duration) <= 0)   return 'Duration must be greater than 0.';
        if (startDate && endDate && new Date(endDate).getTime() < new Date(startDate).getTime()) {
            return 'End Date must be the same as or after Start Date.';
        }
        return null;
    }

    _validateExpense({ assignedResourceId, expenseType, unitPrice, quantity }) {
        if (!assignedResourceId)                                     return 'Assigned Resource is required.';
        if (!expenseType)                                            return 'Expense Type is required.';
        if (unitPrice === '' || unitPrice == null || Number(unitPrice) < 0) {
            return 'Unit Price must be 0 or greater.';
        }
        if (!quantity || Number(quantity) <= 0)                      return 'Quantity must be greater than 0.';
        return null;
    }

    // Calibration & Other share this validator. Same required set as Travel
    // (Resource + Duration); Asset is optional. Date sanity check mirrors Travel.
    _validateAssetTime({ assignedResourceId, duration, startDate, endDate }) {
        if (!assignedResourceId)                  return 'Assigned Resource is required.';
        if (!duration || Number(duration) <= 0)   return 'Duration must be greater than 0.';
        if (startDate && endDate && new Date(endDate).getTime() < new Date(startDate).getTime()) {
            return 'End Time must be the same as or after Start Time.';
        }
        return null;
    }

    // Resolve which validator to run for a given pending edit/add. We infer schema
    // from `_schema` on the entity (set when staged), falling back to the LineType
    // -> tab def lookup for older drafts that didn't carry the discriminator.
    _validateForSchema(schema, payload) {
        if (schema === 'travel')     return this._validateTravel(payload);
        if (schema === 'labor')      return this._validateLabor(payload);
        if (schema === 'expense')    return this._validateExpense(payload);
        if (schema === 'asset_time') return this._validateAssetTime(payload);
        return this._validateGeneric(payload);
    }

    _schemaForLineType(lineType) {
        return TYPE_TO_DEF[lineType]?.schema ?? 'generic';
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}