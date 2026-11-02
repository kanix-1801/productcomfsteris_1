/**
 * @description
 * Lays out Field and Component elements for a tab or section. Field rows are rendered
 * with lightning-record-form using Left/Right column interleaving for two-column layout,
 * or Full width for single-column fields. Component rows stack below fields and each
 * delegates to metadataElementRenderer for dynamic LWC resolution.
 *
 * @group Account Management
 * @date 2026/07/22
 * @see metadataElementRenderer
 * GC-3183
 */
import { LightningElement, api } from 'lwc';

/** @description Column__c value for left column fields in metadata. */
const COLUMN_LEFT = 'Left';

/** @description Column__c value for right column fields in metadata. */
const COLUMN_RIGHT = 'Right';

/** @description Column__c value for full-width fields in metadata. */
const COLUMN_FULL = 'Full';

export default class MetadataColumnLayout extends LightningElement {
    /** @description List of ElementNode objects (Field or Component) to render. */
    @api elements = [];

    /** @description Record Id used by lightning-record-form and child components. */
    @api recordId;

    /** @description User access level: Base or Full. Used to derive formMode. */
    @api accessLevel;

    /**
     * @description
     * Block-level edit flag from tab or section metadata (IsEditable__c).
     * Only applies when accessLevel is Full.
     */
    @api isEditable = false;

    /**
     * @description
     * Returns a copy of items sorted by displayOrder ascending.
     *
     * @param items Element nodes to sort.
     * @return New array sorted by displayOrder.
     */
    sortByDisplayOrder(items) {
        return [...items].sort(
            (first, second) => (first.displayOrder || 0) - (second.displayOrder || 0)
        );
    }

    /**
     * @description
     * Filters elements to a single Column__c value and sorts by displayOrder.
     *
     * @param column Column__c value: Left, Right, or Full.
     * @return Filtered and sorted element list.
     */
    filterByColumn(column) {
        return this.sortByDisplayOrder(
            (this.elements || []).filter(
                (element) => (element.column || COLUMN_LEFT) === column
            )
        );
    }

    /** @description TRUE when at least one element exists in the input list. */
    get hasElements() {
        return (this.elements || []).length > 0;
    }

    /** @description TRUE when recordId is available for lightning-record-form. */
    get hasRecordId() {
        return Boolean(this.recordId);
    }

    /** @description All Field-type elements in the input list. */
    get fieldElements() {
        return (this.elements || []).filter((element) => element.elementType === 'Field');
    }

    /** @description All Component-type elements, sorted by displayOrder. */
    get componentElements() {
        return this.sortByDisplayOrder(
            (this.elements || []).filter((element) => element.elementType === 'Component')
        );
    }

    /** @description TRUE when at least one Field element exists. */
    get hasFieldElements() {
        return this.fieldElements.length > 0;
    }

    /** @description TRUE when at least one Component element exists. */
    get hasComponentElements() {
        return this.componentElements.length > 0;
    }

    /**
     * @description
     * Object API name taken from the first field element (all fields on a tab/section
     * share the same object, e.g. Account).
     *
     * @return SObject API name for lightning-record-form.
     */
    get objectApiName() {
        return this.fieldElements[0]?.objectApiName;
    }

    /** @description Field elements with Column__c = Left. */
    get leftFieldElements() {
        return this.filterByColumn(COLUMN_LEFT).filter(
            (element) => element.elementType === 'Field'
        );
    }

    /** @description Field elements with Column__c = Right. */
    get rightFieldElements() {
        return this.filterByColumn(COLUMN_RIGHT).filter(
            (element) => element.elementType === 'Field'
        );
    }

    /** @description Field elements with Column__c = Full. */
    get fullFieldElements() {
        return this.filterByColumn(COLUMN_FULL).filter(
            (element) => element.elementType === 'Field'
        );
    }

    /** @description TRUE when at least one Left column field exists. */
    get hasLeftFields() {
        return this.leftFieldElements.length > 0;
    }

    /** @description TRUE when at least one Right column field exists. */
    get hasRightFields() {
        return this.rightFieldElements.length > 0;
    }

    /** @description TRUE when at least one Full-width field exists. */
    get hasFullFields() {
        return this.fullFieldElements.length > 0;
    }

    /** @description TRUE when a two-column Left/Right field layout is configured. */
    get hasLeftRightFieldLayout() {
        return this.hasLeftFields || this.hasRightFields;
    }

    /**
     * @description
     * Builds the field API name list for lightning-record-form with columns=2.
     * Left and Right metadata columns are interleaved so each form row shows
     * Left then Right (matching the configured visual layout).
     *
     * @return Ordered list of field API names for the two-column record form.
     */
    get columnFormFieldApiNames() {
        const leftFields = this.leftFieldElements.map((element) => element.fieldApiName);
        const rightFields = this.rightFieldElements.map((element) => element.fieldApiName);
        const interleaved = [];
        const rowCount = Math.max(leftFields.length, rightFields.length);

        for (let index = 0; index < rowCount; index += 1) {
            if (index < leftFields.length) {
                interleaved.push(leftFields[index]);
            }
            if (index < rightFields.length) {
                interleaved.push(rightFields[index]);
            }
        }

        return interleaved;
    }

    /**
     * @description
     * Field API names for full-width (Column = Full) fields.
     *
     * @return List of field API names for the single-column record form.
     */
    get fullFormFieldApiNames() {
        return this.fullFieldElements.map((element) => element.fieldApiName);
    }

    /** @description TRUE when the two-column record form should render. */
    get hasColumnFormFields() {
        return this.columnFormFieldApiNames.length > 0;
    }

    /** @description TRUE when the full-width record form should render. */
    get hasFullFormFields() {
        return this.fullFormFieldApiNames.length > 0;
    }

    /**
     * @description
     * CSS class applied to the full-width form when a two-column form also exists,
     * adding vertical spacing between the forms.
     *
     * @return CSS class string or empty string.
     */
    get fullFormClass() {
        return this.hasColumnFormFields ? 'full-width-form' : '';
    }

    /**
     * @description
     * CSS class for the component stack. Adds top offset when fields render above components.
     *
     * @return CSS class string for the component container.
     */
    get componentStackClass() {
        return this.hasFieldElements
            ? 'component-stack component-stack--offset'
            : 'component-stack';
    }

    /**
     * @description
     * Derives lightning-record-form mode from access level and block isEditable flag:
     * - Base users: readonly (no inline edit)
     * - Full users + isEditable false: view (pencil icons, inline edit)
     * - Full users + isEditable true: edit (Save/Cancel footer)
     *
     * @return Form mode: readonly, view, or edit.
     */
    get formMode() {
        if (this.accessLevel !== 'Full') {
            return 'readonly';
        }

        if (this.isEditable === true) {
            return 'edit';
        }

        return 'view';
    }
}