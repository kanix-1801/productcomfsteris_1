import { LightningElement, api, wire } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getRecord } from 'lightning/uiRecordApi';
import { getLayout } from 'lightning/uiLayoutApi';

const OBJECT_API_NAME = 'Opportunity';
const RECORD_TYPE_FIELD = 'Opportunity.RecordTypeId';

/**
 * Compact header for the dealer opportunity page.
 * Fields come from the compact layout for the opportunity record type, the same source as the internal highlights panel.
 */
export default class DealerOpportunityHighlights extends LightningElement {
    _recordId;
    objectLabel = 'Opportunity';
    objectInfo;
    recordTypeId;
    layoutFields = [];
    recordFields = [RECORD_TYPE_FIELD];
    recordData;
    errorMessage;
    isLoading = false;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        this.recordData = undefined;
        this.recordTypeId = undefined;
        this.layoutFields = [];
        this.recordFields = [RECORD_TYPE_FIELD];
        this.errorMessage = undefined;
        this.isLoading = Boolean(value);
    }

    @wire(getObjectInfo, { objectApiName: OBJECT_API_NAME })
    wiredObjectInfo({ data }) {
        if (data) {
            this.objectInfo = data;
            if (data.label) {
                this.objectLabel = data.label;
            }
            this.refreshRecordFields();
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: '$recordFields' })
    wiredRecord({ data, error }) {
        if (data) {
            this.recordData = data;
            this.recordTypeId = data.recordTypeId || data.fields?.RecordTypeId?.value;
            this.errorMessage = undefined;
            this.isLoading = this.layoutFields.length === 0;
        } else if (error) {
            this.isLoading = false;
            this.errorMessage = reduceError(error);
        }
    }

    @wire(getLayout, {
        objectApiName: OBJECT_API_NAME,
        layoutType: 'Compact',
        mode: 'View',
        recordTypeId: '$recordTypeId'
    })
    wiredLayout({ data, error }) {
        if (data) {
            this.layoutFields = extractCompactFields(data);
            this.refreshRecordFields();
            this.errorMessage = undefined;
            this.isLoading = false;
        } else if (error) {
            this.isLoading = false;
            this.errorMessage = reduceError(error);
        }
    }

    get showPlaceholder() {
        return !this.recordId;
    }

    get showHighlights() {
        return Boolean(this.recordId) && !this.errorMessage && !this.isLoading && this.layoutFields.length > 0;
    }

    get primaryValue() {
        const primary = this.layoutFields[0];
        if (!primary || !this.recordData) {
            return '';
        }
        return readFieldValue(this.recordData, primary.apiName, this.fieldInfo(primary.apiName));
    }

    get detailFields() {
        if (!this.recordData) {
            return [];
        }
        return this.layoutFields.slice(1).map((field) => {
            const displayValue = readFieldValue(this.recordData, field.apiName, this.fieldInfo(field.apiName));
            return {
                apiName: field.apiName,
                label: field.label,
                displayValue
            };
        });
    }

    get hasDetails() {
        return this.detailFields.length > 0;
    }

    fieldInfo(apiName) {
        return this.objectInfo?.fields?.[apiName];
    }

    refreshRecordFields() {
        const nextFields = buildRecordFields(this.layoutFields, this.objectInfo);
        if (nextFields.length && !sameFieldList(this.recordFields, nextFields)) {
            this.recordFields = nextFields;
        }
    }
}

function extractCompactFields(layout) {
    const fields = [];
    const seen = new Set();
    const sections = Array.isArray(layout?.sections) ? layout.sections : [];
    sections.forEach((section) => {
        const rows = Array.isArray(section?.layoutRows) ? section.layoutRows : [];
        rows.forEach((row) => {
            const items = Array.isArray(row?.layoutItems) ? row.layoutItems : [];
            items.forEach((item) => {
                const components = Array.isArray(item?.layoutComponents) ? item.layoutComponents : [];
                components.forEach((component) => {
                    if (component?.componentType !== 'Field' || !component.apiName || seen.has(component.apiName)) {
                        return;
                    }
                    seen.add(component.apiName);
                    fields.push({
                        apiName: component.apiName,
                        label: item.label || component.label || component.apiName
                    });
                });
            });
        });
    });
    return fields;
}

function buildRecordFields(layoutFields, objectInfo) {
    if (!layoutFields.length) {
        return [RECORD_TYPE_FIELD];
    }
    const names = [];
    layoutFields.forEach((field) => {
        names.push(`${OBJECT_API_NAME}.${field.apiName}`);
        const info = objectInfo?.fields?.[field.apiName];
        if (info?.dataType === 'Reference' && info.relationshipName) {
            const nameField = info.referenceToInfos?.[0]?.nameFields?.[0] || 'Name';
            names.push(`${OBJECT_API_NAME}.${info.relationshipName}.${nameField}`);
        }
    });
    return names;
}

function readFieldValue(record, apiName, fieldInfo) {
    if (fieldInfo?.dataType === 'Reference') {
        return readReferenceValue(record, apiName, fieldInfo);
    }
    const field = record?.fields?.[apiName];
    if (!field) {
        return '';
    }
    if (field.displayValue !== null && field.displayValue !== undefined && field.displayValue !== '') {
        return field.displayValue;
    }
    if (field.value === null || field.value === undefined || field.value === '') {
        return '';
    }
    if (typeof field.value === 'boolean') {
        return field.value ? 'True' : 'False';
    }
    return String(field.value);
}

function readReferenceValue(record, apiName, fieldInfo) {
    const direct = record?.fields?.[apiName]?.displayValue;
    if (direct) {
        return direct;
    }
    const related = record?.fields?.[fieldInfo.relationshipName];
    const nameField = fieldInfo.referenceToInfos?.[0]?.nameFields?.[0] || 'Name';
    return related?.displayValue || related?.value?.fields?.[nameField]?.value || '';
}

function sameFieldList(current, next) {
    return current.length === next.length && current.every((field, index) => field === next[index]);
}

function reduceError(error) {
    if (Array.isArray(error?.body)) {
        return error.body.map((item) => item.message).filter(Boolean).join(', ');
    }
    if (typeof error?.body?.message === 'string') {
        return error.body.message;
    }
    if (typeof error?.message === 'string') {
        return error.message;
    }
    return 'Opportunity details could not be loaded.';
}