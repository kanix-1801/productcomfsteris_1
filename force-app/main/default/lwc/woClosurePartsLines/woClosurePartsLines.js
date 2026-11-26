/**
 * @description GW-6407: Parts tab of the Work Order closure screen.
 *              Edit only: lines are not added or deleted here.
 * @author Sagar Anand
 */
import { LightningElement, api, wire } from 'lwc';
import { updateRecord, getRecord } from 'lightning/uiRecordApi';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningAlert from 'lightning/alert';
import LightningPrompt from 'lightning/prompt';
import { getBarcodeScanner } from 'lightning/mobileCapabilities';

import WOLI_OBJECT from '@salesforce/schema/WorkOrderLineItem';
import WOLI_ASSIGNED_RES from '@salesforce/schema/WorkOrderLineItem.AssignedResource__c';
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
import PRODUCT2_PRODUCT_TYPE from '@salesforce/schema/Product2.ProductType__c';
import {
    RESOURCE_PICKER_DISPLAY_INFO,
    RESOURCE_PICKER_FILTER,
    RESOURCE_PICKER_MATCHING_INFO,
    apexErrorMessage,
    filterLinesBySearch,
    isTruthyFlag,
    lookupRecordId,
    openCardsWithErrors,
    saveEditsInOrder,
    showToast,
    sortByStartDate,
    validateEdits,
    withoutKey
} from 'c/woClosureUtils';

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

const PART_PRODUCT_TYPE = 'Part';

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

export default class WoClosurePartsLines extends LightningElement {
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
    _currentUserServiceResourceId = null;
    _workOrderAssignedResourceId = null;
    /** @description Location Id by Service Resource Id (a new map re-renders the Product Item filters). */
    locationIdByServiceResourceId = {};
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
    /** @description Refurbished product (id and name) keyed by the source Product2 Id. */
    _refurbishedByProduct2Id = {};
    /** @description Product2 whose removed-part options are being loaded. */
    _removedPartSourceProduct2Id;
    _serviceResourceNameById = {};
    /** @description Default WorkOrderLineItem record type for picklist wires. */
    woliDefaultRecordTypeId;
    /** @description PartsSource__c picklist options from the WOLI field. */
    partsSourcePicklistOptions = [];
    partExceptionReasonOptions = PART_EXCEPTION_REASON_OPTIONS;
    partExceptionDecisionOptions = [
        { label: 'Yes', value: 'yes' },
        { label: 'No', value: 'no' }
    ];

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
        if (opening) this._ensureRemovedPartSourceForLine(id);
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
            this._cacheServiceResourceLocation(value.id, value.locationId);
            this._resolveLocationForResource(value.id);
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
     * @description Parts lines of the Work Order (WorkOrderLineItem GraphQL nodes).
     */
    @api
    get lines() {
        return this._serverLines;
    }
    set lines(value) {
        this._serverLines = value ?? [];
        this._seedProductItemNameCacheFromWoliLines(this._serverLines);
        this._seedRemovedPartSourcesFromWoliLines(this._serverLines);
    }

    /**
     * @description Line models shown on the tab.
     */
    get lineModels() {
        const lines = this._serverLines.map(
            l => this._buildPartsWoliLineModel(l, this._pendingEdits[l.Id], this.editStateMap[l.Id] ?? {})
        );
        return filterLinesBySearch(sortByStartDate(lines), this.searchTerm);
    }

    /**
     * @description Shows the returnable part notice when an edit changes a line to a returnable part.
     * @return {Promise<void>} Resolves when the user closes the notice
     */
    @api
    async confirmReturnableParts() {
        if (this._hasReturnablePartChange()) {
            await LightningAlert.open({
                message: RETURNABLE_PART_ALERT_MESSAGE,
                theme: 'info',
                label: 'Returnable Part'
            });
        }
    }

    /**
     * @description Caches a Service Resource Location Id; the new map re-renders the Product Item filters.
     */
    _cacheServiceResourceLocation(resourceId, locationId) {
        if (!resourceId || !locationId) return;
        if (this.locationIdByServiceResourceId[resourceId] === locationId) return;
        this.locationIdByServiceResourceId = {
            ...this.locationIdByServiceResourceId,
            [resourceId]: locationId
        };
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
        if (field === 'partsSource') {
            this._stageEdit(id, 'removedPartId', null);
            this._applyPartsSourceChangeToEdit(id, value);
        }
    }

    /**
     * @description Handle Lookup Change (Resource, Product Item, Product).
     */
    handleLookupChange(e) {
        const id = e.currentTarget.dataset.id;
        const field = e.currentTarget.dataset.field;
        const recordId = lookupRecordId(e);
        this._stageEdit(id, field, recordId);
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
    }

    /**
     * @description Internal helper: Stage Edit.
     */
    _stageEdit(id, field, value) {
        const line = this._serverLines.find(l => l.Id === id);
        if (!line) return;
        const entry = this._mergeEdit(id, this._seedEditEntry(line), field, value);
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
        this._pendingEdits = { ...this._pendingEdits, [id]: entry };
    }

    /**
     * @description Internal helper: Seed Edit Entry.
     */
    _seedEditEntry(line) {
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

    /**
     * @description Internal helper: Build Update Fields.
     */
    _buildUpdateFields(id, edit) {
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

    /**
     * @description Internal helper: Validate For Schema.
     */
    _validateForSchema(schema, payload) {
        return schema === 'parts' ? this._validatePartsWoli(payload) : null;
    }

    /**
     * @description Wire: WorkOrderLineItem object info for PartsSource__c picklist values.
     */
    @wire(getObjectInfo, { objectApiName: WOLI_OBJECT })
    wiredWoliObjectInfo({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woClosureES getObjectInfo WorkOrderLineItem failed', error);
            return;
        }
        if (data?.defaultRecordTypeId) {
            this.woliDefaultRecordTypeId = data.defaultRecordTypeId;
        }
    }
    @wire(getPicklistValues, {
        recordTypeId: '$woliDefaultRecordTypeId',
        fieldApiName: WOLI_PARTS_SOURCE
    })
    wiredPartsSourcePicklist({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woClosureES getPicklistValues PartsSource__c failed', error);
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
            console.error('woClosureES getPicklistValues PartExceptionReason__c failed', error);
            return;
        }
        if (data?.values?.length) {
            this.partExceptionReasonOptions = data.values.map(({ label, value }) => ({ label, value }));
        }
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
            console.error('woClosureES refurbished product lookup failed', error);
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
     * @description Parts Source Options.
     */
    get partsSourceOptions() {
        return this.partsSourcePicklistOptions.length
            ? this.partsSourcePicklistOptions
            : PARTS_SOURCE_OPTIONS;
    }
    get partExceptionPrompt() {
        return PART_EXCEPTION_PROMPT;
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
     * @description Handle Product Item Barcode Scan.
     */
    async handleProductItemBarcodeScan(e) {
        const editId = e.currentTarget.dataset.id || null;
        const resourceId = this.editStateMap[editId]?.assignedResourceId
            ?? this._pendingEdits[editId]?.assignedResourceId
            ?? this._resourceIdForEditLine(editId);
        if (!resourceId) {
            showToast(this, 'Select a Resource', 'Choose an Assigned Resource before scanning.', 'warning');
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
                showToast(this, 
                    'No match',
                    match?.locationId
                        ? `No in-stock Product Item found for Product Code "${productCode}" at this resource location.`
                        : 'The selected Resource has no Location for trunk stock.',
                    'warning'
                );
                return;
            }
            if (match.matchCount > 1) {
                showToast(this, 
                    'Multiple matches',
                    `Multiple Product Items matched "${productCode}". The highest-quantity item was selected.`,
                    'info'
                );
            }
            this._applyScannedProductItem(match, { editId });
        } catch (error) {
            showToast(this, 
                'Scan lookup failed',
                apexErrorMessage(error) || 'Unable to find Product Item for scanned code.',
                'error'
            );
        }
    }
    /**
     * @description Handle Product barcode scan (Customer Stock — Product2 by Product Code).
     */
    async handleProductBarcodeScan(e) {
        const editId = e.currentTarget.dataset.id || null;

        const productCode = await this._captureProductCode();
        if (!productCode) return;

        try {
            const match = await findProductByProductCode({ productCode });
            if (!match?.product2Id) {
                showToast(this, 
                    'No match',
                    `No active Product found for Product Code "${productCode}".`,
                    'warning'
                );
                return;
            }
            if (match.matchCount > 1) {
                showToast(this, 
                    'Multiple matches',
                    `Multiple Products matched "${productCode}". The most recently modified product was selected.`,
                    'info'
                );
            }
            this._applyScannedProduct(match, { editId });
        } catch (error) {
            showToast(this, 
                'Scan lookup failed',
                apexErrorMessage(error) || 'Unable to find Product for scanned code.',
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
                showToast(this, 
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
            isTravelSchema: false,
            isLaborSchema: false,
            isCalibrationSchema: false,
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
            isDirty: !!edit
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
     * @description Internal helper: Default Assigned Resource Id.
     *              Prefers the Work Order assigned resource over the current user's resource.
     */
    _defaultAssignedResourceId() {
        return this._workOrderAssignedResourceId ?? this._currentUserServiceResourceId ?? null;
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
            const productItemId = this._pendingEdits[editId]?.productItemId;
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
    _partExceptionState({ editId = null } = {}) {
        if (!editId) {
            return {};
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
    _shouldPromptPartException({ editId = null } = {}) {
        if (this._pendingEdits[editId]?._schema) {
            return this._pendingEdits[editId]._schema === 'parts';
        }
        const line = this._serverLines.find(item => item.Id === editId);
        return line?.LineType__c?.value === 'Parts';
    }
    _writePartException({ editId = null } = {}, values) {
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
    async _promptPartException({ editId = null } = {}) {
        const state = this._partExceptionState({ editId });
        const key = this._partExceptionKey(state);
        if (!key) {
            return;
        }
        if (state.partExceptionProductKey && state.partExceptionProductKey !== key) {
            this._writePartException({ editId }, this._clearedPartExceptionFields());
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
        const context = { editId };
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
                    showToast(this, 'Part not approved', check.message, 'error');
                }
            }
        } catch (error) {
            const message = apexErrorMessage(error) || 'Unable to check this part.';
            showToast(this, 'Part not approved', message, 'error');
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
        const { editId = null } = options;
        // GW-6095: no part to evaluate, so clear any Component Tag selection.
        if (!this.recordId || !productItemId) {
            this._applyComponentTagFields(this._clearedComponentTagFields(), { editId });
        }
        if (!productItemId || !this.recordId) {
            await this._applyAllowedUnitResult(null, { editId });
            return;
        }

        try {
            const result = await evaluateAllowedUnit({
                workOrderId: this.recordId,
                productItemId
            });
            await this._refreshComponentTags(result, { productItemId }, { editId });
            // No WO asset, or Root PFCL SBOM Required != Yes → leave fields unset.
            if (!result?.evaluated) {
                await this._applyAllowedUnitResult(null, { editId });
                return;
            }
            await this._applyAllowedUnitResult(
                !!result.allowedUnit,
                { editId }
            );
        } catch (error) {
            const message = apexErrorMessage(error) || 'Unable to validate allowed parts.';
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
        const { editId = null } = options;
        // GW-6095: no part to evaluate, so clear any Component Tag selection.
        if (!this.recordId || !product2Id) {
            this._applyComponentTagFields(this._clearedComponentTagFields(), { editId });
        }
        if (!product2Id || !this.recordId) {
            await this._applyAllowedUnitResult(null, { editId });
            return;
        }

        try {
            const result = await evaluateAllowedUnitByProduct({
                workOrderId: this.recordId,
                product2Id
            });
            await this._refreshComponentTags(result, { product2Id }, { editId });
            if (!result?.evaluated) {
                await this._applyAllowedUnitResult(null, { editId });
                return;
            }
            await this._applyAllowedUnitResult(
                !!result.allowedUnit,
                { editId }
            );
        } catch (error) {
            const message = apexErrorMessage(error) || 'Unable to validate allowed parts.';
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
     * @param {Object} target Edit line target (editId)
     */
    async _refreshComponentTags(
        allowedUnitResult,
        { productItemId = null, product2Id = null } = {},
        { editId = null } = {}
    ) {
        if (!allowedUnitResult?.evaluated || allowedUnitResult.allowedUnit !== true) {
            this._applyComponentTagFields(this._clearedComponentTagFields(), { editId });
            return;
        }

        let componentTagOptions;
        try {
            const tags = productItemId
                ? await getComponentTagsForProductItem({ workOrderId: this.recordId, productItemId })
                : await getComponentTagsForProduct({ workOrderId: this.recordId, product2Id });
            componentTagOptions = (tags ?? []).map(tag => ({ label: tag.label, value: tag.id }));
        } catch (error) {
            this._applyComponentTagFields(this._clearedComponentTagFields(), { editId });
            showToast(this, 
                'Component Tag lookup failed',
                apexErrorMessage(error) || 'Unable to load component tags.',
                'error'
            );
            return;
        }

        // The part may have changed while the tags were loading; ignore a stale response.
        const target = this._componentTagTarget({ editId });
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
            { editId }
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
     * @description GW-6095 — Clears the Component Tag fields on an edit row.
     * @param {String} editId Line Id
     */
    _clearComponentTagForEdit(editId) {
        this._applyComponentTagFields(this._clearedComponentTagFields(), { editId });
    }
    /**
     * @description GW-6095 — Stages Component Tag fields on an edit row.
     * @param {Object} fields componentTagId / componentTagOptions / componentTagsLoaded
     * @param {Object} target Edit line target (editId)
     */
    _applyComponentTagFields(fields, { editId = null } = {}) {
        if (editId) {
            Object.entries(fields).forEach(([field, value]) => this._stageEdit(editId, field, value));
        }
    }
    /**
     * @description GW-6095 — Staged edit holding the part and Component Tag of a line.
     * @param {Object} target Edit line target (editId)
     * @return {Object|null} State object, or null when nothing is staged yet
     */
    _componentTagTarget({ editId = null } = {}) {
        return this._pendingEdits[editId] ?? null;
    }
    /**
     * @description GW-6095 — View fields for the Component Tag on a parts line.
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
     * @description Internal helper: Apply Allowed Unit Result.
     */
    async _applyAllowedUnitResult(allowedUnit, { editId = null } = {}) {
        if (editId) {
            this._stageEdit(editId, 'allowedUnit', allowedUnit);
        }
        if (!this._shouldPromptPartException({ editId })) {
            return;
        }
        if (allowedUnit === false) {
            await this._promptPartException({ editId });
            return;
        }
        this._writePartException({ editId }, this._clearedPartExceptionFields());
    }
    /**
     * @description GW-1738 / GW-2001: Evaluates Billing Type via Apex for the selected part.
     */
    async _evaluateBillingType({
        product2Id = null,
        productItemId = null,
        editId = null
    } = {}) {
        if (!this.recordId || (!product2Id && !productItemId)) {
            this._applyBillingTypeResult('', { editId });
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
            this._applyBillingTypeResult(billingType || '', { editId });
        } catch (error) {
            const message = apexErrorMessage(error) || 'Unable to evaluate billing type.';
            this.dispatchEvent(new ShowToastEvent({
                title: 'Billing Type check failed',
                message,
                variant: 'error'
            }));
        }
    }
    /**
     * @description Applies Apex Billing Type onto the staged edit.
     * @param {String} billingType Billable or SVC Warranty
     */
    _applyBillingTypeResult(billingType, { editId = null } = {}) {
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
        const edits = { ...this._pendingEdits };
        let changed = false;
        for (const [id, edit] of Object.entries(edits)) {
            if (edit.productItemId === productItemId && edit._schema === 'parts') {
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
        return this._serverLines.find(l => l.Id === editId)?.AssignedResource__c?.value ?? null;
    }
    /**
     * @description Internal helper: Apply Scanned Product Item.
     */
    _applyScannedProductItem(match, options = {}) {
        const { editId = null } = options;
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
            showToast(this, 'Product Item selected', match.productName || productItemId, 'success');
        }
    }
    /**
     * @description GW-4311 — Apply scanned Product2 (Customer Stock).
     */
    _applyScannedProduct(match, options = {}) {
        const { editId = null } = options;
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
            showToast(this, 'Product selected', match.productName || productCode || product2Id, 'success');
        }
    }
    /**
     * @description True when a pending Parts edit changes the part to a returnable part.
     * @return {boolean}
     */
    _hasReturnablePartChange() {
        return Object.entries(this._pendingEdits).some(([id, edit]) => {
            if (edit._schema !== 'parts' || !isTruthyFlag(edit.returnable)) return false;
            const original = this._serverLines.find(l => l.Id === id);
            const productItemChanged = !!edit.productItemId
                && edit.productItemId !== (original?.ProductItem__c?.value ?? null);
            const productChanged = !!edit.product2Id
                && edit.product2Id !== (original?.Product__c?.value ?? null);
            return productItemChanged || productChanged;
        });
    }
    /**
     * @description Loads refurbished-product choices for a line when they are not cached yet.
     */
    _ensureRemovedPartSourceForLine(lineId) {
        const line = this._serverLines.find(l => l.Id === lineId);
        const edit = this._pendingEdits[lineId];
        const productItemId = edit?.productItemId
            ?? line?.ProductItem__c?.value
            ?? null;
        const product2Id = edit?.product2Id
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
}