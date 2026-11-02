/**
 * @description
 * Dynamic component renderer for CMDT Component rows. Resolves the target LWC constructor
 * from standardComponentRegistry (Phase 2, standard:* names) or componentRegistry
 * (Phase 1, custom LWCs). Spreads PropsJson__c properties plus recordId onto the leaf
 * component via lwc:component and lwc:spread. Requires lightning__dynamicComponent capability.
 *
 * Note: Field rows are rendered by metadataColumnLayout via lightning-record-form;
 * this component handles Component elementType only.
 *
 * @group Account Management
 * @date 2026/07/22
 * @see componentRegistry
 * @see standardComponentRegistry
 * GC-3183
 */
import { LightningElement, api } from 'lwc';
import { parsePropsJson, resolveComponent } from './componentRegistry';
import { resolveStandardComponent } from './standardComponentRegistry';

export default class MetadataElementRenderer extends LightningElement {
    /** @description ElementNode from Apex (elementType, componentApiName, propsJson, etc.). */
    @api element;

    /** @description Parent record Id injected into every rendered child component. */
    @api recordId;

    /** @description TRUE when elementType is Field (reserved; fields use column layout). */
    get isField() {
        return this.element?.elementType === 'Field';
    }

    /** @description TRUE when elementType is Component. */
    get isComponent() {
        return this.element?.elementType === 'Component';
    }

    /** @description TRUE when the element metadata marks the block as editable. */
    get isEditable() {
        return this.element?.isEditable === true;
    }

    /** @description Field API name when elementType is Field. */
    get fieldApiName() {
        return this.element?.fieldApiName;
    }

    /**
     * @description
     * Resolves the LWC constructor for this component row. Standard types (standard:*)
     * are checked first, then custom registry entries.
     *
     * @return LWC constructor or null when not registered.
     */
    get componentConstructor() {
        return (
            resolveStandardComponent(this.element?.componentApiName) ||
            resolveComponent(this.element?.componentApiName)
        );
    }

    /** @description TRUE when a constructor was found in either registry. */
    get hasResolvedComponent() {
        return this.componentConstructor != null;
    }

    /**
     * @description
     * Props object passed to the leaf LWC via lwc:spread. Merges parsed PropsJson__c
     * from CMDT with the required recordId property.
     *
     * @return Key/value map of @api properties for the dynamic child component.
     */
    get componentProps() {
        const props = parsePropsJson(this.element?.propsJson);
        return {
            ...props,
            recordId: this.recordId
        };
    }

    /**
     * @description
     * ComponentAPIName__c value shown in the fallback message when resolution fails.
     *
     * @return Component name for error display.
     */
    get unknownComponentName() {
        return this.element?.componentApiName || 'Unknown component';
    }
}