/**
 * @description
 * Renders a metadata-configured FieldList row with left/right columns and per-field
 * modes (* = required, # = readonly, $ = editable). Base users always see read-only fields.
 *
 * @group Account Management
 * @date 2026/07/28
 * @see metadataTabContent
 * GC-3183
 */
import { LightningElement, api, wire } from 'lwc';
import { getFieldValue, getRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const MODE_READONLY = 'readonly';
const MODE_EDITABLE = 'editable';
const MODE_REQUIRED = 'required';

const DISPLAY_LABELS = {
    BillingStreet: 'Address Line 1'
};

export default class MetadataFieldListLayout extends LightningElement {
    /** @description FieldListNode from Apex (leftFields, rightFields, objectApiName). */
    @api fieldList;

    /** @description Record Id for lightning-record-view-form / edit-form. */
    @api recordId;

    /** @description User access level: Base or Full. */
    @api accessLevel;

    isEditing = false;
    labeledRecord;
    labeledFieldRefCache;

    /**
     * @description Field refs whose Salesforce label is replaced in the template.
     * @return Object.Field tokens, or undefined until the object name is known.
     */
    get labeledFieldRefs() {
        if (!this.objectApiName) {
            return undefined;
        }

        const refs = Object.keys(DISPLAY_LABELS).map(
            (fieldApiName) => `${this.objectApiName}.${fieldApiName}`
        );
        const signature = refs.join(',');

        if (!this.labeledFieldRefCache || this.labeledFieldRefCache.signature !== signature) {
            this.labeledFieldRefCache = { signature, refs };
        }

        return this.labeledFieldRefCache.refs;
    }

    @wire(getRecord, { recordId: '$recordId', optionalFields: '$labeledFieldRefs' })
    wiredLabeledRecord({ data }) {
        this.labeledRecord = data;
    }

    /**
     * @description
     * Resolves the effective field mode for the current user.
     * Base users always receive readonly regardless of metadata suffix.
     *
     * @param field Parsed field item from Apex.
     * @return Effective mode string.
     */
    resolveMode(field) {
        if (!field) {
            return MODE_READONLY;
        }

        if (this.accessLevel !== 'Full') {
            return MODE_READONLY;
        }

        return field.mode || MODE_READONLY;
    }

    /**
     * @description
     * Builds a cell descriptor for template rendering.
     *
     * @param field Parsed field item from Apex.
     * @param columnKey Unique key prefix for the column slot.
     * @return Cell descriptor or null when field is absent.
     */
    buildCell(field, columnKey) {
        if (!field) {
            return null;
        }

        const mode = this.resolveMode(field);
        const displayLabel = DISPLAY_LABELS[field.fieldApiName];

        return {
            key: `${columnKey}-${field.fieldApiName}`,
            fieldApiName: field.fieldApiName,
            mode,
            isReadonly: mode === MODE_READONLY,
            isEditable: mode === MODE_EDITABLE,
            isRequired: mode === MODE_REQUIRED,
            displayLabel,
            hasDisplayLabel: Boolean(displayLabel),
            displayValue: this.displayValueFor(field.fieldApiName)
        };
    }

    /**
     * @description Value shown beside a replaced label, on the same line as other fields.
     * @param fieldApiName Field API name.
     * @return Display text, or an empty string when the value is blank.
     */
    displayValueFor(fieldApiName) {
        if (!DISPLAY_LABELS[fieldApiName] || !this.labeledRecord || !this.objectApiName) {
            return '';
        }

        const value = getFieldValue(
            this.labeledRecord,
            `${this.objectApiName}.${fieldApiName}`
        );
        return value == null ? '' : value;
    }

    /** @description SObject API name for the field list. */
    get objectApiName() {
        return this.fieldList?.objectApiName;
    }

    /** @description TRUE when recordId is available. */
    get hasRecordId() {
        return Boolean(this.recordId);
    }

    /** @description TRUE when object API name is configured. */
    get hasObjectApiName() {
        return Boolean(this.objectApiName);
    }

    /** @description TRUE when the field list can render forms. */
    get canRenderForm() {
        return this.hasRecordId && this.hasObjectApiName;
    }

    /**
     * @description
     * Interleaves left and right column fields into display rows.
     *
     * @return Row objects with optional left and right cell descriptors.
     */
    get rows() {
        const leftFields = this.fieldList?.leftFields || [];
        const rightFields = this.fieldList?.rightFields || [];
        const rowCount = Math.max(leftFields.length, rightFields.length);
        const rows = [];

        for (let index = 0; index < rowCount; index += 1) {
            rows.push({
                key: `row-${index}`,
                left: this.buildCell(leftFields[index], 'left'),
                right: this.buildCell(rightFields[index], 'right')
            });
        }

        return rows;
    }

    /** @description TRUE when at least one row exists. */
    get hasRows() {
        return this.rows.length > 0;
    }

    /** @description TRUE when any field is editable or required for Full users. */
    get hasEditableFields() {
        const allFields = [
            ...(this.fieldList?.leftFields || []),
            ...(this.fieldList?.rightFields || [])
        ];

        return allFields.some((field) => {
            const mode = this.resolveMode(field);
            return mode === MODE_EDITABLE || mode === MODE_REQUIRED;
        });
    }

    /** @description TRUE when the list should render in read-only view mode. */
    get showViewMode() {
        return !this.isEditing || !this.hasEditableFields;
    }

    /** @description TRUE when the Edit action should appear for Full users. */
    get showEditButton() {
        return this.accessLevel === 'Full' && this.hasEditableFields && !this.isEditing;
    }

    /** @description TRUE when Save/Cancel actions should appear in edit mode. */
    get showEditActions() {
        return this.isEditing && this.hasEditableFields;
    }

    /**
     * @description
     * Switches the component into edit mode for editable Full-access fields.
     */
    handleEditClick() {
        this.isEditing = true;
    }

    /**
     * @description
     * Returns to view mode without saving changes.
     */
    handleCancelEdit() {
        this.isEditing = false;
    }

    /**
     * @description
     * Handles successful save from lightning-record-edit-form.
     */
    handleSuccess() {
        this.isEditing = false;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Record updated.',
                variant: 'success'
            })
        );
    }
}