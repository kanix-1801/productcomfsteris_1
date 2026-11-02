/**
 * @description
 * Renders a collapsible SLDS section block for metadata Section rows. Displays the
 * section label from CMDT and passes child Field/Component elements to metadataColumnLayout.
 * Section.isEditable from Apex controls whether fields inside use view or edit form mode
 * for Full-access users.
 *
 * @group Account Management
 * @date 2026/07/22
 * @see metadataColumnLayout
 * GC-3183
 */
import { LightningElement, api } from 'lwc';

export default class MetadataSectionRenderer extends LightningElement {
    /** @description SectionNode from Apex (apiName, label, isEditable, elements). */
    @api section;

    /** @description Parent record Id passed to metadataColumnLayout. */
    @api recordId;

    /** @description User access level: Base or Full. Passed through to column layout. */
    @api accessLevel;

    /** @description Controls expanded/collapsed state of the SLDS section. Default: open. */
    isOpen = true;

    /**
     * @description
     * SLDS section CSS classes including open state for aria-expanded styling.
     *
     * @return CSS class string for the section wrapper.
     */
    get sectionClass() {
        return this.isOpen
            ? 'slds-section slds-is-open section-container'
            : 'slds-section section-container';
    }

    /**
     * @description
     * Chevron icon rotation class when the section is expanded.
     *
     * @return CSS class string for the chevron icon.
     */
    get chevronClass() {
        return this.isOpen ? 'chevron chevron-open' : 'chevron';
    }

    /**
     * @description
     * Toggles the collapsible section open/closed when the section title is clicked.
     */
    toggleSection() {
        this.isOpen = !this.isOpen;
    }
}