/**
 * @description
 * Phase 1 custom LWC component registry for metadata-driven pages.
 * Maps ComponentAPIName__c values from DynamicPageElement__mdt to statically imported
 * LWC constructors. Salesforce requires static imports for dynamic lwc:component rendering;
 * metadata alone cannot reference an unregistered bundle.
 *
 * To add a new custom widget:
 * 1. Create the LWC bundle under force-app/main/default/lwc/.
 * 2. Import it below and add an entry to COMPONENT_REGISTRY.
 * 3. Create a CMDT Component row with matching ComponentAPIName__c.
 *
 * @group Account Management
 * @date 2026/07/22
 * @see metadataElementRenderer
 * @see standardComponentRegistry
 * GC-3183
 */
import accountDashbord from 'c/accountDashbord';
import accountTeamMemberDetails from 'c/accountTeamMemberDetails';
import accountAccountRelationshipTab from 'c/accountAccountRelationshipTab';
import childAccountContacts from 'c/childAccountContacts';
import childAccountOpportunities from 'c/childAccountOpportunities';
import competitiveInstalledBase from 'c/competitiveInstalledBase';
import enterpriseActivities from 'c/enterpriseActivities';
import keyAccountProcessReviewHistory from 'c/keyAccountProcessReviewHistory';

/** @description Lookup map: ComponentAPIName__c → LWC constructor. */
const COMPONENT_REGISTRY = {
    accountDashbord,
    accountTeamMemberDetails,
    accountAccountRelationshipTab,
    childAccountContacts,
    childAccountOpportunities,
    competitiveInstalledBase,
    enterpriseActivities,
    keyAccountProcessReviewHistory
};

/**
 * @description
 * Returns the LWC constructor for a custom ComponentAPIName__c value.
 *
 * @param componentApiName Value from DynamicPageElement__mdt.ComponentAPIName__c.
 * @return LWC constructor, or null when the name is not registered.
 */
export function resolveComponent(componentApiName) {
    return COMPONENT_REGISTRY[componentApiName] || null;
}

/**
 * @description
 * Parses PropsJson__c from CMDT into a JavaScript object for lwc:spread.
 * Returns an empty object when the value is blank or invalid JSON.
 *
 * @param propsJson Raw JSON string from DynamicPageElement__mdt.PropsJson__c.
 * @return Parsed props object; never throws.
 */
export function parsePropsJson(propsJson) {
    if (!propsJson) {
        return {};
    }

    try {
        return JSON.parse(propsJson);
    } catch (error) {
        // eslint-disable-next-line no-console
        console.warn('Invalid PropsJson__c value', propsJson, error);
        return {};
    }
}

/**
 * @description
 * Returns all registered custom component API names (for diagnostics or admin tooling).
 *
 * @return Array of ComponentAPIName__c keys in the registry.
 */
export function getRegisteredComponentNames() {
    return Object.keys(COMPONENT_REGISTRY);
}