/**
 * @description
 * Renders the body of a single metadata-configured tab. A tab may contain:
 * (1) zero or more Section rows rendered by metadataSectionRenderer,
 * (2) zero or more FieldList rows rendered by metadataFieldListLayout, and/or
 * (3) direct Field/Component rows rendered by metadataColumnLayout without a section wrapper.
 * Content blocks are merged and sorted by displayOrder from CMDT.
 *
 * @group Account Management
 * @date 2026/07/22
 * @see metadataSectionRenderer
 * @see metadataFieldListLayout
 * @see metadataColumnLayout
 * GC-3183
 */
import { LightningElement, api } from 'lwc';

export default class MetadataTabContent extends LightningElement {
    /** @description TabNode from Apex (apiName, label, sections, fieldLists, elements). */
    @api tab;

    /** @description Parent record Id passed to all child renderers. */
    @api recordId;

    /** @description User access level: Base or Full. Controls field edit mode downstream. */
    @api accessLevel;

    /**
     * @description
     * Section nodes nested under this tab (ElementType = Section in CMDT).
     *
     * @return List of SectionNode objects from Apex.
     */
    get sections() {
        return this.tab?.sections || [];
    }

    /**
     * @description
     * FieldList nodes placed directly under the tab.
     *
     * @return List of FieldListNode objects from Apex.
     */
    get fieldLists() {
        return this.tab?.fieldLists || [];
    }

    /**
     * @description
     * Field and Component rows placed directly under the tab (no Section parent).
     *
     * @return List of ElementNode objects from Apex.
     */
    get directElements() {
        return this.tab?.elements || [];
    }

    /**
     * @description
     * Direct Field/Component blocks merged for metadataColumnLayout when multiple
     * legacy field rows exist on the same tab. Uses the earliest displayOrder for sorting.
     *
     * @return Ordered tab content with direct elements grouped into one block.
     */
    get orderedContentWithGroupedElements() {
        const items = [];

        this.sections.forEach((section) => {
            items.push({
                key: `section-${section.apiName}`,
                isSection: true,
                isFieldList: false,
                isElement: false,
                order: section.displayOrder || 0,
                data: section
            });
        });

        this.fieldLists.forEach((fieldList) => {
            items.push({
                key: `fieldList-${fieldList.apiName}`,
                isSection: false,
                isFieldList: true,
                isElement: false,
                order: fieldList.displayOrder || 0,
                data: fieldList
            });
        });

        if (this.directElements.length > 0) {
            const minOrder = this.directElements.reduce(
                (lowest, element) => Math.min(lowest, element.displayOrder || 0),
                this.directElements[0].displayOrder || 0
            );

            items.push({
                key: 'direct-elements',
                isSection: false,
                isFieldList: false,
                isElement: true,
                order: minOrder,
                elementList: this.directElements
            });
        }

        return items.sort((first, second) => first.order - second.order);
    }

    /** @description TRUE when the tab has one or more configured content blocks. */
    get hasContent() {
        return this.orderedContentWithGroupedElements.length > 0;
    }

    /**
     * @description
     * Determines whether direct tab-level fields should use edit mode for Full users.
     * Block-level edit is driven by any Field row with isEditable = true under the tab.
     * Passed to metadataColumnLayout as isEditable.
     *
     * @return TRUE when at least one direct field element is marked editable in metadata.
     */
    get directFieldsEditable() {
        return this.directElements.some(
            (element) => element.elementType === 'Field' && element.isEditable === true
        );
    }
}