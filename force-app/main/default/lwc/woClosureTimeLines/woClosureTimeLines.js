/**
 * @description GW-6407: Time tab (Travel and Labor lines) of the Work Order closure screen.
 *              Edit only: lines are not added or deleted here.
 * @author Sagar Anand
 */
import { LightningElement, api, wire } from 'lwc';
import { updateRecord, getRecord } from 'lightning/uiRecordApi';

import WOLI_LINETYPE from '@salesforce/schema/WorkOrderLineItem.LineType__c';
import WOLI_RATE from '@salesforce/schema/WorkOrderLineItem.Rate__c';
import WOLI_TRAVEL_TYPE from '@salesforce/schema/WorkOrderLineItem.TravelType__c';
import WOLI_ASSIGNED_RES from '@salesforce/schema/WorkOrderLineItem.AssignedResource__c';
import WOLI_WORKTYPE from '@salesforce/schema/WorkOrderLineItem.WorkTypeId';
import WOLI_STARTDATE from '@salesforce/schema/WorkOrderLineItem.StartDate';
import WOLI_ENDDATE from '@salesforce/schema/WorkOrderLineItem.EndDate';
import WOLI_DURATION from '@salesforce/schema/WorkOrderLineItem.Duration';
import WOLI_REPAIRCODE from '@salesforce/schema/WorkOrderLineItem.RepairCode__c';
import WOLI_UNIT_QTY from '@salesforce/schema/WorkOrderLineItem.UnitQty__c';
import WOLI_LIST_PRICE_CUSTOM from '@salesforce/schema/WorkOrderLineItem.ListPrice__c';
import WOLI_UNIT_PRICE_CUSTOM from '@salesforce/schema/WorkOrderLineItem.UnitPrice__c';
import WOLI_TOTAL_PRICE_CUSTOM from '@salesforce/schema/WorkOrderLineItem.TotalPrice__c';
import getRateListForWorkOrder from '@salesforce/apex/WoDebriefRateListController.getRateListForWorkOrder';
import checkServiceResourceSkills from '@salesforce/apex/WoDebriefSkillCheckController.checkServiceResourceSkills';
import getAssignedServiceResourceId from '@salesforce/apex/WoDebriefSkillCheckController.getAssignedServiceResourceId';
import getCurrentUserServiceResourceId from '@salesforce/apex/WoDebriefSkillCheckController.getCurrentUserServiceResourceId';
import {
    RESOURCE_PICKER_DISPLAY_INFO,
    RESOURCE_PICKER_FILTER,
    RESOURCE_PICKER_MATCHING_INFO,
    addHoursToDatetime,
    apexErrorMessage,
    computeDurationHours,
    filterLinesBySearch,
    fmtDateRange,
    fmtDurationLabel,
    fmtMoney,
    fmtOptionalMoney,
    isSameSalesforceId,
    lookupRecordId,
    openCardsWithErrors,
    saveEditsInOrder,
    sortByStartDate,
    toMs,
    validateEdits,
    withoutKey
} from 'c/woClosureUtils';

const TIME_LINE_TYPES = new Set(['Travel', 'Labor']);

const LINE_TYPE_TO_SCHEMA = {
    Travel: 'travel',
    Labor: 'labor'
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

export default class WoClosureTimeLines extends LightningElement {
    @api recordId;
    /** @description Work Order (GraphQL node) the lines belong to. */
    @api workOrder;
    /** @description Search text entered for this tab. */
    @api searchTerm = '';

    _serverLines = [];
    _edits = {};
    editStateMap = {};
    editErrors = {};
    _serviceResourceNameById = {};
    /** @description Service Resource whose name is loaded after it is selected. */
    _resourceNameLookupId;
    /** @description Current user's Service Resource passed by the parent. */
    _currentUserResource;
    _currentUserServiceResourceId = null;
    _workOrderAssignedResourceId = null;
    /** @description Rate List prices for travel and labor options/pricing (reactive; do not prefix with _). */
    rateList = null;

    /**
     * @description Staged line edits keyed by line Id. Every change tells the parent how many lines are edited.
     */
    get _pendingEdits() {
        return this._edits;
    }
    set _pendingEdits(value) {
        this._edits = value;
        this.dispatchEvent(new CustomEvent('pendingchange', { detail: { count: Object.keys(value).length } }));
    }

    /**
     * @description True when a search is entered and no line matches it.
     */
    get hasNoSearchResults() {
        return !!(this.searchTerm ?? '').trim() && this.lineModels.length === 0;
    }

    /**
     * @description Validates the staged edits and shows the errors on their lines.
     * @return {Promise<Boolean>} True when every edit can be saved
     */
    @api
    async validate() {
        const errors = validateEdits(this._pendingEdits, edit => this._validateForSchema(edit._schema ?? 'generic', edit));
        this.editErrors = { ...this.editErrors, ...errors };
        const skillCheckOk = await this._assertTimeSkillChecksForSave();
        this.editStateMap = openCardsWithErrors(this.editStateMap, this._pendingEdits, this.editErrors);
        return Object.keys(errors).length === 0 && skillCheckOk;
    }

    /**
     * @description Saves the staged edits; failed edits stay staged with their error.
     * @return {Promise<Object>} okIds, failedCount and firstError
     */
    @api
    async save() {
        const pendingEdits = { ...this._pendingEdits };
        this._pendingEdits = {};
        const result = await saveEditsInOrder(pendingEdits, (id, edit) => updateRecord({ fields: this._buildUpdateFields(id, edit) }));
        this._pendingEdits = result.failedEdits;
        this.editStateMap = {};
        this.editErrors = { ...this.editErrors, ...result.errors };
        const errorList = Object.values(result.errors);
        return { okIds: result.okIds, failedCount: errorList.length, firstError: errorList[0] ?? null };
    }

    /**
     * @description Discards the staged edits.
     */
    @api
    reset() {
        this._pendingEdits = {};
        this.editStateMap = {};
        this.editErrors = {};
    }

    /**
     * @description Handle Edit Toggle.
     */
    handleEditToggle(e) {
        const id = e.currentTarget.dataset.id;
        const cur = this.editStateMap[id];
        const opening = !cur?.isEditing;
        this.editStateMap = { ...this.editStateMap, [id]: { isEditing: opening } };
        const errs = { ...this.editErrors };
        delete errs[id];
        this.editErrors = errs;
    }

    /**
     * @description Current user's active Service Resource (id, name and location) loaded by the parent.
     */
    @api
    get currentUserResource() {
        return this._currentUserResource;
    }
    set currentUserResource(value) {
        this._currentUserResource = value;
        if (value?.id) {
            this._currentUserServiceResourceId = value.id;
            this._cacheServiceResourceName(value.id, value.name);
        }
    }

    /**
     * @description Service Resource assigned on the Work Order appointment, loaded by the parent.
     */
    @api
    get workOrderAssignedResourceId() {
        return this._workOrderAssignedResourceId;
    }
    set workOrderAssignedResourceId(value) {
        if (value) {
            this._workOrderAssignedResourceId = value;
        }
    }

    /**
     * @description Resource Picker Filter.
     */
    get resourcePickerFilter() { return RESOURCE_PICKER_FILTER; }
    /**
     * @description Resource Picker Display Info.
     */
    get resourcePickerDisplayInfo() { return RESOURCE_PICKER_DISPLAY_INFO; }
    /**
     * @description Resource Picker Matching Info.
     */
    get resourcePickerMatchingInfo() { return RESOURCE_PICKER_MATCHING_INFO; }

    /**
     * @description Travel and Labor lines of the Work Order (WorkOrderLineItem GraphQL nodes).
     */
    @api
    get lines() {
        return this._serverLines;
    }
    set lines(value) {
        this._serverLines = value ?? [];
    }

    /**
     * @description Line models shown on the tab, by start date.
     */
    get lineModels() {
        const lines = this._serverLines.map(l => {
            const edit = this._pendingEdits[l.Id];
            const lineType = edit?.lineType ?? l.LineType__c?.value;
            const schema = LINE_TYPE_TO_SCHEMA[lineType] ?? 'travel';
            return this._modelBuilderForSchema(schema).call(this, l, edit, this.editStateMap[l.Id] ?? {});
        });
        return filterLinesBySearch(sortByStartDate(lines), this.searchTerm);
    }

    /**
     * @description Internal helper: Model Builder For Schema.
     */
    _modelBuilderForSchema(schema) {
        return schema === 'labor' ? this._buildLaborLineModel : this._buildTravelLineModel;
    }

    /**
     * @description Handle Edit Field Change.
     */
    handleEditFieldChange(e) {
        const id = e.currentTarget.dataset.id;
        const field = e.currentTarget.dataset.field;
        const value = e.detail.checked !== undefined ? e.detail.checked : e.detail.value;
        this._stageEdit(id, field, value);
        if (field === 'lineType') {
            if (value === 'Travel') {
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
        if (field === 'startDate' || field === 'endDate' || field === 'durationHours') {
            this._syncTimeFieldsOnEdit(id, field);
        }
        if (field === 'travelType' || field === 'rate' || field === 'durationHours') {
            if (field === 'travelType' && value !== TRAVEL_TYPE_ACTUAL) {
                this._stageEdit(id, 'rate', null);
            }
            if (field === 'travelType' && value === TRAVEL_TYPE_ACTUAL && !this._pendingEdits[id]?.rate) {
                this._stageEdit(id, 'rate', this._defaultRate('Travel'));
            }
            this._applyTravelPricingToEdit(id);
        }
        if (field === 'rate' || field === 'startDate' || field === 'endDate' || field === 'lineType') {
            this._applyLaborPricingToEdit(id);
        }
    }

    /**
     * @description Handle Lookup Change (Work Type and Resource).
     */
    handleLookupChange(e) {
        const id = e.currentTarget.dataset.id;
        const field = e.currentTarget.dataset.field;
        const recordId = lookupRecordId(e);
        this._stageEdit(id, field, recordId);
        this._checkTimeWorkTypeSkillsForLine(id);
        if (field === 'assignedResourceId' && recordId && !this._serviceResourceNameById[recordId]) {
            this._resourceNameLookupId = recordId;
        }
    }

    /**
     * @description Wire adapter handler: name of a newly selected Service Resource.
     */
    @wire(getRecord, { recordId: '$_resourceNameLookupId', fields: ['ServiceResource.Name'] })
    wiredResourceName({ data }) {
        if (data?.id && data.fields?.Name?.value) {
            this._cacheServiceResourceName(data.id, data.fields.Name.value);
        }
    }

    /**
     * @description Internal helper: Stage Edit.
     */
    _stageEdit(id, field, value) {
        const line = this._serverLines.find(l => l.Id === id);
        if (!line) return;
        let entry = this._mergeEdit(id, this._seedEditEntry(line), field, value);
        if (field === 'lineType' || field === 'rate' || field === 'startDate' || field === 'endDate') {
            entry = this._applyLaborPricingToState(entry);
        }
        this._pendingEdits = { ...this._pendingEdits, [id]: entry };
    }

    /**
     * @description Internal helper: Seed Edit Entry.
     */
    _seedEditEntry(line) {
        const lineType = line.LineType__c?.value ?? null;
        return {
            _schema: lineType === 'Labor' ? 'labor' : 'travel',
            _entity: 'WorkOrderLineItem',
            lineType,
            assignedResourceId: this._resolveAssignedResourceId(line.AssignedResource__c?.value),
            workTypeId: line.WorkTypeId?.value ?? null,
            startDate: line.StartDate?.value ?? '',
            endDate: line.EndDate?.value ?? '',
            durationHours: line.Duration?.value
                ?? computeDurationHours(line.StartDate?.value, line.EndDate?.value)
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
    }

    /**
     * @description Internal helper: Build Update Fields.
     */
    _buildUpdateFields(id, edit) {
        const durationFields = this._buildDurationFields(edit.startDate, edit.endDate, edit.durationHours);
        if (edit._schema === 'labor') {
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
                ...this._laborPricingFieldsForSave(edit),
                ...durationFields
            };
        }
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
            ...this._buildTravelPriceSaveFields(edit)
        };
    }

    /**
     * @description Internal helper: Validate For Schema.
     */
    _validateForSchema(schema, payload) {
        if (schema === 'time') return this._validateTime(payload);
        if (schema === 'travel') return this._validateTravel(payload);
        if (schema === 'labor') return this._validateLabor(payload);
        return null;
    }

    /**
     * @description Wire: Rate List for WO Account (GW-2965 labor / GW-2967 travel pricing).
     */
    @wire(getRateListForWorkOrder, { workOrderId: '$recordId' })
    wiredRateList({ data, error }) {
        if (error) {
            this.rateList = null;
            // eslint-disable-next-line no-console
            console.error('woClosureES getRateListForWorkOrder failed', error);
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
    }
    /**
     * @description Time Line Type Options.
     */
    get timeLineTypeOptions() { return TIME_LINE_TYPE_OPTIONS; }
    /**
     * @description Travel Type options driven by populated Rate List values (GW-2967).
     */
    get travelTypeOptions() {
        return this._buildTravelTypeOptionsFromRateList();
    }
    /**
     * @description Handle Edit Close.
     */
    handleEditClose(e) {
        const id = e.currentTarget.dataset.id;
        this.editStateMap = { ...this.editStateMap, [id]: { isEditing: false } };
        const errs = { ...this.editErrors };
        delete errs[id];
        this.editErrors = errs;
    }

    /**
     * @description Cancel Changes: discards the staged edit and error of one line; the card shows the saved values.
     */
    handleRevertLine(e) {
        const id = e.currentTarget.dataset.id;
        this._pendingEdits = withoutKey(this._pendingEdits, id);
        this.editErrors = withoutKey(this.editErrors, id);
        this.editStateMap = { ...this.editStateMap, [id]: { isEditing: true } };
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
            durationFromServer: l.Duration?.value ?? null,
            rate,
            travelType
        });
        return {
            ...base,
            editListPriceLabel: fmtOptionalMoney(listPrice),
            editUnitPriceLabel: fmtOptionalMoney(unitPrice),
            editTotalPriceLabel: fmtOptionalMoney(totalPrice)
        };
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
            editListPriceLabel: fmtOptionalMoney(listPrice),
            editUnitPriceLabel: fmtOptionalMoney(unitPrice),
            editTotalPriceLabel: fmtOptionalMoney(totalPrice),
            metaLine: this._fmtTimeMeta('Labor', startDate, endDate, rate, '')
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
        durationFromServer = null,
        rate = '',
        travelType = ''
    }) {
        const isTravel = schema === 'travel';
        const isLabor = schema === 'labor';
        const isTime = isTravel || isLabor;
        const flags = {
            isTravelSchema: isTravel,
            isLaborSchema: isLabor,
            isTimeSchema: isTime,
            isCalibrationSchema: schema === 'calibration',
            isExpenseSchema: false
        };
        const editLineType = state.lineType ?? lineType;
        const editRate = state.rate ?? rate ?? '';
        const editTravelType = state.travelType ?? travelType ?? '';
        const effectiveStart = state.startDate ?? startDate ?? '';
        const effectiveEnd = state.endDate ?? endDate ?? '';
        const durationHours = state.durationHours != null && state.durationHours !== ''
            ? Number(state.durationHours)
            : (computeDurationHours(effectiveStart, effectiveEnd) ?? durationFromServer);
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
            startDateMs: toMs(startDate),
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
            editDurationLabel: fmtDurationLabel(durationHours),
            editListPriceLabel: fmtMoney(listPrice),
            editUnitPriceLabel: fmtMoney(unitPrice),
            editTotalPriceLabel: fmtMoney(totalPrice),
            editError: this.editErrors[id] ?? '',
            isDirty
        };
    }
    /**
     * @description Internal helper: Merge Edit.
     */
    _mergeEdit(id, seed, field, value) {
        const existing = this._pendingEdits[id];
        return existing ? { ...existing, [field]: value } : { ...seed, [field]: value };
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
            : computeDurationHours(startDate, endDate);
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
            : computeDurationHours(startDate, endDate);
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
     * @description Reads the current lightning-record-picker value for a Time-tab field.
     * @param {string} field Field dataset name
     * @param {string} editId Line Id
     * @return {string|null}
     */
    _readTimePickerValue(field, editId) {
        const pickers = this.template.querySelectorAll(`lightning-record-picker[data-field="${field}"]`);
        for (const picker of pickers) {
            if (editId && picker.dataset.id === editId) {
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
     * @param {string} editId Line Id
     * @return {Promise<string|null>}
     */
    async _resolveTimeSkillResourceId(assignedResourceId, editId) {
        await this._ensureWorkOrderAssignedResourceId();
        const pickerId = this._readTimePickerValue('assignedResourceId', editId);
        const selectedId = pickerId || assignedResourceId;
        const currentUserId = this._currentUserServiceResourceId;
        const workOrderAssignedId = this._workOrderAssignedResourceId;
        if (selectedId && !isSameSalesforceId(selectedId, currentUserId)) {
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
     * @description True when the Time-line Work Type differs from the Work Order Work Type.
     * @param {string|null} workTypeId Selected Work Type Id
     * @return {Boolean}
     */
    _isDifferentWorkTypeFromHeader(workTypeId) {
        if (!workTypeId) return false;
        const headerWorkTypeId = this._headerWorkTypeId();
        if (!headerWorkTypeId) return false;
        return !isSameSalesforceId(workTypeId, headerWorkTypeId);
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
     * @description Applies or clears a Time-tab skill-check error on a line.
     * @param {string|null} message Error text, or null to clear
     * @param {string} editId Line Id
     */
    _applyTimeSkillError(message, editId) {
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
        showToast = true
    } = {}) {
        const resolvedResourceId = await this._resolveTimeSkillResourceId(assignedResourceId, editId);
        if (!this._isDifferentWorkTypeFromHeader(workTypeId) || !resolvedResourceId) {
            this._applyTimeSkillError(null, editId);
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
                this._applyTimeSkillError(message, editId);
                if (showToast) {
                    showToast(this, 'Missing required skill', message, 'error');
                }
                return false;
            }
            this._applyTimeSkillError(null, editId);
            return true;
        } catch (error) {
            const message = apexErrorMessage(error)
                || 'Unable to verify resource skills for the selected Work Type.';
            this._applyTimeSkillError(message, editId);
            if (showToast) {
                showToast(this, 'Skill check failed', message, 'error');
            }
            return false;
        }
    }
    /**
     * @description Runs the Time-tab skill check for a line.
     * @param {string} lineId Line Id
     * @return {Promise<Boolean>}
     */
    async _checkTimeWorkTypeSkillsForLine(lineId) {
        const edit = this._pendingEdits[lineId];
        const schema = edit?._schema;
        if (schema && schema !== 'travel' && schema !== 'labor' && schema !== 'time') {
            return true;
        }
        const serverLine = this._serverLines.find((l) => l.Id === lineId);
        const workTypeId = edit?.workTypeId
            ?? serverLine?.WorkTypeId?.value
            ?? null;
        const assignedResourceId = this._resolveAssignedResourceId(
            edit?.assignedResourceId,
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
        if (!checks.length) return true;
        const results = await Promise.all(checks);
        return results.every((ok) => ok);
    }
    /**
     * @description Work Order header Work Type Id used as the Time-tab default.
     * @return {string|null}
     */
    _headerWorkTypeId() {
        return this.workOrder?.WorkTypeId?.value ?? this.workOrder?.WorkType?.Id ?? null;
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
        const pending = this._pendingEdits[id];
        if (!pending) {
            return;
        }
        const synced = this._syncTimeFieldsOnState({ ...pending }, changedField);
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
                next.endDate = addHoursToDatetime(next.startDate, hours);
            }
        } else if (changedField === 'endDate') {
            const hours = computeDurationHours(next.startDate, next.endDate);
            if (hours != null) {
                next.durationHours = hours;
            }
        }
        return next;
    }
    /**
     * @description Applies travel pricing onto a pending edit by Id.
     * @param {string} id Line Id
     */
    _applyTravelPricingToEdit(id) {
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
     * @description Applies labor pricing to a pending edit line.
     * @param {string} id Line Id
     */
    _applyLaborPricingToEdit(id) {
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
            : computeDurationHours(state.startDate, state.endDate);
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
            : computeDurationHours(state?.startDate, state?.endDate);
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
     * @description Internal helper: Build Duration Fields.
     */
    _buildDurationFields(startDate, endDate, durationHours) {
        const duration = durationHours != null && durationHours !== '' && !Number.isNaN(Number(durationHours))
            ? Number(durationHours)
            : computeDurationHours(startDate, endDate);
        if (duration == null) return {};
        return { [WOLI_DURATION.fieldApiName]: duration, DurationType: 'Hours' };
    }
    /**
     * @description Internal helper: Fmt Time Meta.
     */
    _fmtTimeMeta(lineType, startDate, endDate, rate, travelType, repairCode = '') {
        const parts = [];
        if (lineType) parts.push(lineType);
        if (repairCode) parts.push(repairCode);
        if (rate) parts.push(rate);
        if (travelType) parts.push(travelType);
        const range = fmtDateRange(startDate, endDate);
        if (range) parts.push(range);
        return parts.join(' · ');
    }
}