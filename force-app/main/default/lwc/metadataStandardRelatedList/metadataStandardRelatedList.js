/**
 * @description
 * Phase 2 framework LWC that renders a generic related list from PropsJson__c configuration.
 * Used when ComponentAPIName__c = standard:relatedList. Loads data via getRelatedListRecords,
 * displays rows in lightning-datatable, and supports optional New button and View/Edit row
 * actions via NavigationMixin. All behavior is metadata-driven; no CMDT-specific code paths.
 *
 * @group Account Management
 * @date 2026/07/23
 * @see standardComponentRegistry
 * GC-3183
 */
import { LightningElement, api, wire } from 'lwc';
import { getRelatedListRecords, getRelatedListCount } from 'lightning/uiRelatedListApi';
import { NavigationMixin } from 'lightning/navigation';

/** @description Default row count before the datatable becomes scrollable. */
const DEFAULT_SCROLL_THRESHOLD = 10;

/** @description Maximum related list rows fetched from the UI API. */
const DEFAULT_FETCH_PAGE_SIZE = 1999;

/** @description Default labels for rowActions shorthand values (view, edit). */
const DEFAULT_ROW_ACTION_LABELS = {
    view: 'View',
    edit: 'Edit'
};

export default class MetadataStandardRelatedList extends NavigationMixin(LightningElement) {
    /** @description Parent record Id (Account Id on Customer 360). */
    @api recordId;

    /** @description Related list API name, e.g. Contacts, Opportunities, Histories. */
    @api relatedListId;

    /** @description Card title; falls back to relatedListId. */
    @api title;

    /** @description lightning-card icon-name; defaults to standard:related_list. */
    @api iconName;

    /** @description Column config array from PropsJson (label, wireField, fieldName, type). */
    @api fields;

    /** @description Max visible rows before scroll; default 10. Legacy pageSize alias. */
    @api pageSize;

    /** @description Record count above which the datatable becomes vertically scrollable. */
    @api scrollThreshold;

    /** @description Max rows to fetch from getRelatedListRecords; default 1999. */
    @api maxRecords;

    /** @description Legacy flag; use rowActions instead. Adds View-only action when true. */
    @api showViewAction = false;

    /** @description Row dropdown actions, e.g. ["view", "edit"]. */
    @api rowActions;

    /** @description Child object API name for View/Edit navigation. */
    @api objectApiName;

    /** @description When true, renders a New button in the card actions slot. */
    @api showNewButton = false;

    /** @description Label for the New button; default "New". */
    @api newButtonLabel;

    /** @description Object for New navigation; defaults to objectApiName. */
    @api newObjectApiName;

    /** @description Default field values on create; use {recordId} for parent Id token. */
    @api newDefaultFieldValues;

    /** @description Optional sort, e.g. ["AccountHistory.CreatedDate DESC"]. */
    @api sortBy;

    /** @description Related list rows mapped for lightning-datatable. */
    records = [];

    /** @description Total related list count from getRelatedListCount. */
    totalRecordCount;

    /** @description TRUE after getRelatedListRecords wire completes (success or error). */
    recordsLoaded = false;

    /** @description Wire or config error object. */
    error;

    /**
     * @description
     * Normalizes the fields prop from PropsJson (array or JSON string).
     *
     * @return Array of field column definitions.
     */
    get parsedFields() {
        if (Array.isArray(this.fields)) {
            return this.fields;
        }

        if (typeof this.fields === 'string') {
            try {
                const parsed = JSON.parse(this.fields);
                return Array.isArray(parsed) ? parsed : [];
            } catch (parseError) {
                return [];
            }
        }

        return [];
    }

    /**
     * @description
     * Builds lightning-datatable row action menu from rowActions or showViewAction.
     *
     * @return Array of { label, name } action definitions.
     */
    get parsedRowActions() {
        let actions = this.rowActions;

        if (typeof actions === 'string') {
            try {
                actions = JSON.parse(actions);
            } catch (parseError) {
                actions = [];
            }
        }

        if (Array.isArray(actions) && actions.length) {
            return actions.map((action) => this.normalizeRowAction(action)).filter(Boolean);
        }

        if (this.isTruthy(this.showViewAction)) {
            return [{ label: 'View', name: 'view' }];
        }

        return [];
    }

    /**
     * @description
     * Converts a string or object row action entry to datatable format.
     *
     * @param action Action string (view/edit) or { label, name } object.
     * @return Normalized action object or null when invalid.
     */
    normalizeRowAction(action) {
        if (typeof action === 'string') {
            const name = action.toLowerCase();
            return {
                label: DEFAULT_ROW_ACTION_LABELS[name] || action,
                name
            };
        }

        if (action?.name) {
            return {
                label: action.label || DEFAULT_ROW_ACTION_LABELS[action.name] || action.name,
                name: action.name
            };
        }

        return null;
    }

    /**
     * @description
     * Coerces PropsJson boolean values that may arrive as strings from metadata.
     *
     * @param value Boolean or string "true".
     * @return TRUE when value is boolean true or string "true".
     */
    isTruthy(value) {
        return value === true || value === 'true';
    }

    /** @description TRUE when at least one row action is configured. */
    get hasRowActions() {
        return this.parsedRowActions.length > 0;
    }

    /** @description TRUE when the New button should render. */
    get showNew() {
        return this.isTruthy(this.showNewButton);
    }

    /** @description Display label for the New button. */
    get newButtonText() {
        return this.newButtonLabel || 'New';
    }

    /** @description Object API name used for New record navigation. */
    get effectiveNewObjectApiName() {
        return this.newObjectApiName || this.objectApiName;
    }

    /**
     * @description
     * Replaces {recordId} token in newDefaultFieldValues with the parent record Id.
     *
     * @return Default field values string for navigation state, or undefined.
     */
    get resolvedNewDefaultFieldValues() {
        if (!this.newDefaultFieldValues) {
            return undefined;
        }

        return this.newDefaultFieldValues.replaceAll('{recordId}', this.recordId || '');
    }

    /**
     * @description
     * Validates required PropsJson properties before calling the wire adapter.
     *
     * @return Error message string, or null when configuration is valid.
     */
    get configError() {
        if (!this.relatedListId) {
            return 'PropsJson must include relatedListId.';
        }

        if (!this.parsedFields.length) {
            return 'PropsJson must include a fields array.';
        }

        if (this.parsedFields.some((field) => !field.wireField || !field.fieldName)) {
            return 'Each field entry requires wireField and fieldName.';
        }

        return null;
    }

    /** @description TRUE when PropsJson and recordId are sufficient to load data. */
    get hasValidConfig() {
        return !this.configError && Boolean(this.recordId);
    }

    /** @description Related list Id passed to wire; undefined when config is invalid. */
    get wireRelatedListId() {
        return this.hasValidConfig ? this.relatedListId : undefined;
    }

    /** @description Field paths for getRelatedListRecords wire adapter. */
    get wireFields() {
        if (!this.hasValidConfig) {
            return undefined;
        }

        const fieldPaths = new Set();

        for (const field of this.parsedFields) {
            fieldPaths.add(field.wireField);
            if (field.linkTo === 'related' && field.linkIdWireField) {
                fieldPaths.add(field.linkIdWireField);
            }
        }

        return [...fieldPaths];
    }

    /** @description Row count threshold before enabling vertical scroll on the datatable. */
    get effectiveScrollThreshold() {
        const configuredThreshold = Number(this.scrollThreshold);
        return Number.isFinite(configuredThreshold) && configuredThreshold > 0
            ? configuredThreshold
            : DEFAULT_SCROLL_THRESHOLD;
    }

    /** @description pageSize parameter for getRelatedListRecords wire adapter. */
    get wirePageSize() {
        if (!this.hasValidConfig) {
            return undefined;
        }

        const configuredMax = Number(this.maxRecords);
        return Number.isFinite(configuredMax) && configuredMax > 0
            ? configuredMax
            : DEFAULT_FETCH_PAGE_SIZE;
    }

    /** @description Optional sortBy array for getRelatedListRecords wire adapter. */
    get wireSortBy() {
        if (!this.hasValidConfig) {
            return undefined;
        }

        let sortValues = this.sortBy;

        if (typeof sortValues === 'string') {
            try {
                sortValues = JSON.parse(sortValues);
            } catch (parseError) {
                sortValues = [sortValues];
            }
        }

        if (Array.isArray(sortValues) && sortValues.length) {
            return sortValues;
        }

        return undefined;
    }

    /**
     * @description
     * lightning-datatable column definitions built from PropsJson fields plus optional action column.
     *
     * @return Column configuration array for lightning-datatable.
     */
    get datatableColumns() {
        const columns = this.parsedFields.map((field) => this.buildDatatableColumn(field));

        if (this.hasRowActions) {
            columns.push({
                type: 'action',
                typeAttributes: {
                    rowActions: this.parsedRowActions
                }
            });
        }

        return columns;
    }

    /**
     * @description
     * Builds a single datatable column from PropsJson, including optional hyperlink columns.
     *
     * @param field Field definition from PropsJson fields array.
     * @return Column configuration for lightning-datatable.
     */
    buildDatatableColumn(field) {
        if (this.fieldHasLink(field)) {
            return {
                label: field.label,
                fieldName: this.getLinkUrlFieldName(field.fieldName),
                type: 'url',
                typeAttributes: {
                    label: { fieldName: field.fieldName },
                    target: '_self',
                    tooltip: { fieldName: field.fieldName }
                }
            };
        }

        return {
            label: field.label,
            fieldName: field.fieldName,
            type: field.type || 'text',
            typeAttributes: field.typeAttributes || this.getDefaultTypeAttributes(field)
        };
    }

    /**
     * @description
     * Default lightning-datatable typeAttributes when PropsJson omits them.
     *
     * @param field Field definition from PropsJson fields array.
     * @return typeAttributes object or undefined.
     */
    getDefaultTypeAttributes(field) {
        if (field.type === 'currency') {
            return { currencyDisplayAs: 'symbol' };
        }

        return undefined;
    }

    /**
     * @description
     * TRUE when PropsJson marks a column as a record or related-record hyperlink.
     *
     * @param field Field definition from PropsJson fields array.
     * @return TRUE when linkTo is record or related.
     */
    fieldHasLink(field) {
        return field.linkTo === 'record' || field.linkTo === 'related';
    }

    /**
     * @description
     * Datatable row property name that stores the hyperlink URL for a linked column.
     *
     * @param fieldName Base fieldName from PropsJson.
     * @return URL property name, e.g. nameUrl.
     */
    getLinkUrlFieldName(fieldName) {
        return `${fieldName}Url`;
    }

    /**
     * @description
     * Builds a Lightning record view URL for hyperlink columns.
     *
     * @param objectApiName Salesforce object API name.
     * @param recordId Target record Id.
     * @return Record view URL or undefined when inputs are missing.
     */
    buildRecordViewUrl(objectApiName, recordId) {
        if (!objectApiName || !recordId) {
            return undefined;
        }

        return `/lightning/r/${objectApiName}/${recordId}/view`;
    }

    /** @description Card header title with record count, e.g. Contacts (12). */
    get cardTitle() {
        const baseTitle = this.title || this.relatedListId || 'Related List';
        const count = this.displayRecordCount;

        if (count === undefined || count === null) {
            return baseTitle;
        }

        return `${baseTitle} (${count})`;
    }

    /**
     * @description
     * Count shown in the card title. Prefers getRelatedListCount; falls back to loaded
     * row count when the count wire is unavailable (e.g. Histories related list).
     *
     * @return Total or loaded record count, or undefined while loading.
     */
    get displayRecordCount() {
        if (this.totalRecordCount !== undefined && this.totalRecordCount !== null) {
            return this.totalRecordCount;
        }

        if (this.recordsLoaded) {
            return this.records.length;
        }

        return undefined;
    }

    /** @description Card icon with default related list icon. */
    get cardIcon() {
        return this.iconName || 'standard:related_list';
    }

    /** @description TRUE when the datatable should scroll vertically instead of growing. */
    get isScrollableTable() {
        const recordCount = this.displayRecordCount ?? 0;
        return recordCount > this.effectiveScrollThreshold;
    }

    /** @description Wrapper class for optional scrollable datatable container. */
    get datatableContainerClass() {
        return this.isScrollableTable
            ? 'datatable-container_scrollable'
            : '';
    }

    /** @description TRUE when the related list returned at least one row. */
    get hasRecords() {
        return this.records.length > 0;
    }

    /**
     * @description
     * User-facing error from invalid PropsJson or wire failure.
     *
     * @return Error message for template display, or null.
     */
    get errorMessage() {
        if (this.configError) {
            return this.configError;
        }

        if (this.error) {
            return this.error.body?.message || this.error.message || 'Unable to load related list.';
        }

        return null;
    }

    /**
     * @description
     * Loads related list records when configuration and recordId are valid.
     *
     * @param data Successful getRelatedListRecords response.
     * @param error Wire error when the related list query fails.
     */
    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: '$wireRelatedListId',
        fields: '$wireFields',
        sortBy: '$wireSortBy',
        pageSize: '$wirePageSize'
    })
    wiredRecords({ data, error }) {
        if (!this.hasValidConfig) {
            return;
        }

        if (data) {
            this.records = data.records.map((row) => this.mapRecord(row));
            this.error = undefined;
            this.recordsLoaded = true;
        } else if (error) {
            this.records = [];
            this.error = error;
            this.recordsLoaded = true;
        }
    }

    /**
     * @description
     * Loads the total related list count for the card title.
     *
     * @param data Successful getRelatedListCount response.
     * @param error Wire error when the count query fails.
     */
    @wire(getRelatedListCount, {
        parentRecordId: '$recordId',
        relatedListId: '$wireRelatedListId',
        maxCount: DEFAULT_FETCH_PAGE_SIZE
    })
    wiredRecordCount({ data, error }) {
        if (!this.hasValidConfig) {
            return;
        }

        if (data) {
            this.totalRecordCount = data.count;
        } else if (error) {
            this.totalRecordCount = undefined;
        }
    }

    /**
     * @description
     * Maps a UI API related list record to a flat datatable row object.
     *
     * @param row Single record from getRelatedListRecords.
     * @return Row object keyed by fieldName values from PropsJson.
     */
    mapRecord(row) {
        const mapped = { id: row.id };

        for (const field of this.parsedFields) {
            mapped[field.fieldName] = this.getFieldValue(row.fields, field.wireField, field.type);
            this.applyFieldLink(mapped, field, row);
        }

        return mapped;
    }

    /**
     * @description
     * Adds a hyperlink URL property when PropsJson configures linkTo for a column.
     *
     * @param mapped Row object being built for lightning-datatable.
     * @param field Field definition from PropsJson fields array.
     * @param row Single record from getRelatedListRecords.
     */
    applyFieldLink(mapped, field, row) {
        const urlFieldName = this.getLinkUrlFieldName(field.fieldName);

        if (field.linkTo === 'record') {
            mapped[urlFieldName] = this.buildRecordViewUrl(this.objectApiName, row.id);
            return;
        }

        if (field.linkTo === 'related') {
            const relatedId = this.getFieldRawValue(row.fields, field.linkIdWireField);
            mapped[urlFieldName] = this.buildRecordViewUrl(field.linkObjectApiName, relatedId);
        }
    }

    /**
     * @description
     * Extracts display or raw value from a wire field path (supports relationship fields).
     *
     * @param fields fields map from a UI API record row.
     * @param wireField Full field path, e.g. Contact.Name or Case.Contact.Name.
     * @param fieldType Optional PropsJson type (currency, date, etc.).
     * @return Display value, raw value, or undefined.
     */
    getFieldValue(fields, wireField, fieldType) {
        const parts = wireField.split('.');

        if (parts.length >= 3) {
            const relationshipField = fields[parts[parts.length - 2]];
            return relationshipField?.displayValue ?? relationshipField?.value;
        }

        const fieldKey = parts[parts.length - 1];
        const field = fields[fieldKey];

        if (!field) {
            return undefined;
        }

        if (fieldType === 'currency' || fieldType === 'number' || fieldType === 'percent') {
            return this.getNumericFieldValue(field.value);
        }

        if (fieldType === 'date' || fieldType === 'date-local') {
            return field.value ?? field.displayValue;
        }

        return field.displayValue ?? field.value;
    }

    /**
     * @description
     * Coerces UI API numeric field values for lightning-datatable currency/number columns.
     *
     * @param rawValue Raw value from a UI API field payload.
     * @return Finite number or undefined when empty/invalid.
     */
    getNumericFieldValue(rawValue) {
        if (rawValue === null || rawValue === undefined || rawValue === '') {
            return undefined;
        }

        const numeric = Number(rawValue);
        return Number.isFinite(numeric) ? numeric : undefined;
    }

    /**
     * @description
     * Extracts the raw Id value from a wire field path for related-record hyperlinks.
     *
     * @param fields fields map from a UI API record row.
     * @param wireField Full field path, e.g. Opportunity.OwnerId or Contact.AccountId.
     * @return Raw field value, typically a Salesforce Id.
     */
    getFieldRawValue(fields, wireField) {
        if (!wireField) {
            return undefined;
        }

        const parts = wireField.split('.');
        const fieldKey = parts[parts.length - 1];
        const field = fields[fieldKey];
        return field?.value;
    }

    /**
     * @description
     * Navigates to the child record view or edit page for View/Edit row actions.
     *
     * @param event lightning-datatable rowaction event.
     */
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (!row?.id || !this.objectApiName) {
            return;
        }

        if (actionName !== 'view' && actionName !== 'edit') {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: row.id,
                objectApiName: this.objectApiName,
                actionName
            }
        });
    }

    /**
     * @description
     * Navigates to the new record page with optional default field values pre-filled.
     */
    handleNewRecord() {
        if (!this.effectiveNewObjectApiName) {
            return;
        }

        const navigationState = this.resolvedNewDefaultFieldValues
            ? { defaultFieldValues: this.resolvedNewDefaultFieldValues }
            : undefined;

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: this.effectiveNewObjectApiName,
                actionName: 'new'
            },
            state: navigationState
        });
    }
}