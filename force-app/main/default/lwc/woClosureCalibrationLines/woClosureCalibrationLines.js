/**
 * @description GW-6407: Calibration tab of the Work Order closure screen.
 *              Edit only: lines are not added or deleted here.
 * @author Sagar Anand
 */
import { LightningElement, api } from 'lwc';
import { updateRecord } from 'lightning/uiRecordApi';

import WOLI_ASSIGNED_RES from '@salesforce/schema/WorkOrderLineItem.AssignedResource__c';
import WOLI_ASSETID from '@salesforce/schema/WorkOrderLineItem.AssetId';
import ASSET_TYPE from '@salesforce/schema/Asset.AssetType__c';
import ASSET_INTERNAL_CATEGORY from '@salesforce/schema/Asset.InternalAssetCategory__c';
import {
    RESOURCE_PICKER_DISPLAY_INFO,
    RESOURCE_PICKER_FILTER,
    RESOURCE_PICKER_MATCHING_INFO,
    filterLinesBySearch,
    lookupRecordId,
    openCardsWithErrors,
    saveEditsInOrder,
    sortByStartDate,
    validateEdits,
    withoutKey
} from 'c/woClosureUtils';

const CALIBRATION_DEVICE_CATEGORY = 'Calibration Device';
const STERIS_ASSET_TYPE = 'STERIS Asset';

export default class WoClosureCalibrationLines extends LightningElement {
    @api recordId;
    /** @description Work Order (GraphQL node) the lines belong to. */
    @api workOrder;
    /** @description Search text entered for this tab. */
    @api searchTerm = '';

    _serverLines = [];
    _edits = {};
    editStateMap = {};
    editErrors = {};
    /** @description Current user's Service Resource passed by the parent. */
    _currentUserResource;
    /** @description Service Resource assigned on the Work Order appointment, passed by the parent. */
    _workOrderAssignedResourceId = null;

    /**
     * @description Calibration lines of the Work Order (WorkOrderLineItem GraphQL nodes).
     */
    @api
    get lines() {
        return this._serverLines;
    }
    set lines(value) {
        this._serverLines = value ?? [];
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
     * @description Line models shown on the tab.
     */
    get lineModels() {
        const lines = this._serverLines.map(l => this._buildLineModel(l, this._pendingEdits[l.Id], this.editStateMap[l.Id] ?? {}));
        return filterLinesBySearch(sortByStartDate(lines), this.searchTerm);
    }

    /**
     * @description True when a search is entered and no line matches it.
     */
    get hasNoSearchResults() {
        return !!(this.searchTerm ?? '').trim() && this.lineModels.length === 0;
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
     * @description Calibration Asset Picker Filter: STERIS calibration devices.
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
     * @description Validates the staged edits and shows the errors on their lines.
     * @return {Promise<Boolean>} True when every edit can be saved
     */
    @api
    async validate() {
        const errors = validateEdits(this._pendingEdits, edit => (edit.assignedResourceId ? null : 'Resource is required.'));
        this.editErrors = { ...this.editErrors, ...errors };
        this.editStateMap = openCardsWithErrors(this.editStateMap, this._pendingEdits, this.editErrors);
        return Object.keys(errors).length === 0;
    }

    /**
     * @description Saves the staged edits; failed edits stay staged with their error.
     * @return {Promise<Object>} okIds, failedCount and firstError
     */
    @api
    async save() {
        const pendingEdits = { ...this._pendingEdits };
        this._pendingEdits = {};
        const result = await saveEditsInOrder(pendingEdits, (id, edit) => updateRecord({
            fields: {
                Id: id,
                [WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
                [WOLI_ASSETID.fieldApiName]: edit.assetId
            }
        }));
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
        const opening = !this.editStateMap[id]?.isEditing;
        this.editStateMap = { ...this.editStateMap, [id]: { isEditing: opening } };
        this._clearError(id);
    }

    /**
     * @description Handle Edit Close.
     */
    handleEditClose(e) {
        const id = e.currentTarget.dataset.id;
        this.editStateMap = { ...this.editStateMap, [id]: { isEditing: false } };
        this._clearError(id);
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
     * @description Handle Lookup Change (Resource and Asset).
     */
    handleLookupChange(e) {
        const id = e.currentTarget.dataset.id;
        const line = this._serverLines.find(l => l.Id === id);
        if (!line) return;
        const existing = this._pendingEdits[id] ?? {
            _schema: 'calibration',
            _entity: 'WorkOrderLineItem',
            assignedResourceId: line.AssignedResource__c?.value
                ?? this._workOrderAssignedResourceId
                ?? this._currentUserResource?.id
                ?? null,
            assetId: line.AssetId?.value ?? null
        };
        this._pendingEdits = {
            ...this._pendingEdits,
            [id]: { ...existing, [e.currentTarget.dataset.field]: lookupRecordId(e) }
        };
    }

    /**
     * @description Removes the error shown on a line.
     * @param {string} id Line Id
     */
    _clearError(id) {
        const errs = { ...this.editErrors };
        delete errs[id];
        this.editErrors = errs;
    }

    /**
     * @description Builds the card and edit view of a Calibration line.
     * @param {Object} l WorkOrderLineItem GraphQL node
     * @param {Object} edit Staged edit, when present
     * @param {Object} state Edit state of the card
     * @return {Object}
     */
    _buildLineModel(l, edit, state) {
        const assignedResId = edit?.assignedResourceId ?? l.AssignedResource__c?.value ?? null;
        const assignedResName = l.AssignedResource__r?.Name?.value ?? '';
        const assetId = edit?.assetId ?? l.AssetId?.value ?? null;
        const assetSerial = l.Asset?.SerialNumber?.value ?? '';
        return {
            Id: l.Id,
            lineNumber: l.LineItemNumber?.value ?? '',
            title: assignedResName || 'Unassigned',
            metaLine: assetSerial ? `SN ${assetSerial}` : '',
            assignedResourceId: assignedResId,
            assignedResourceName: assignedResName,
            assetId,
            assetSerialNumber: assetSerial,
            isEditing: state.isEditing ?? false,
            editAssignedResId: state.assignedResourceId ?? assignedResId,
            editAssetId: state.assetId ?? edit?.assetId ?? assetId,
            editError: this.editErrors[l.Id] ?? '',
            isDirty: !!edit
        };
    }
}