/**
 * @description
 * Phase 2 standard component type registry for metadata-driven pages.
 * Maps ComponentAPIName__c values prefixed with "standard:" to framework LWCs that
 * wrap platform UI patterns (related lists, timelines, etc.). These types are fully
 * configured via PropsJson__c without a per-instance code deploy.
 *
 * Resolution order in metadataElementRenderer:
 * 1. standardComponentRegistry (this file)
 * 2. componentRegistry.js (custom LWCs)
 *
 * @group Account Management
 * @date 2026/07/23
 * @see metadataStandardRelatedList
 * @see metadataElementRenderer
 * GC-3183
 *
 * standard:relatedList PropsJson example:
 * {
 *   "relatedListId": "Opportunities",
 *   "title": "Opportunities",
 *   "iconName": "standard:opportunity",
 *   "objectApiName": "Opportunity",
 *   "showNewButton": true,
 *   "newDefaultFieldValues": "AccountId={recordId}",
 *   "rowActions": ["view", "edit"],
 *   "scrollThreshold": 10,
 *   "fields": [
 *     { "label": "Name", "wireField": "Opportunity.Name", "fieldName": "name", "linkTo": "record" },
 *     { "label": "Stage", "wireField": "Opportunity.StageName", "fieldName": "stageName" },
 *     { "label": "Close Date", "wireField": "Opportunity.CloseDate", "fieldName": "closeDate", "type": "date" }
 *   ]
 * }
 */
import metadataStandardRelatedList from 'c/metadataStandardRelatedList';

/** @description Lookup map: standard ComponentAPIName__c → framework LWC constructor. */
const STANDARD_COMPONENT_REGISTRY = {
    'standard:relatedList': metadataStandardRelatedList
};

/**
 * @description
 * Returns the framework LWC constructor for a standard ComponentAPIName__c value.
 * Only names starting with "standard:" are considered.
 *
 * @param componentApiName Value from DynamicPageElement__mdt.ComponentAPIName__c.
 * @return LWC constructor, or null when not a standard type or not registered.
 */
export function resolveStandardComponent(componentApiName) {
    if (!componentApiName?.startsWith('standard:')) {
        return null;
    }

    return STANDARD_COMPONENT_REGISTRY[componentApiName] || null;
}

/**
 * @description
 * Returns all registered standard component type names.
 *
 * @return Array of standard: prefixed ComponentAPIName__c keys.
 */
export function getRegisteredStandardComponentNames() {
    return Object.keys(STANDARD_COMPONENT_REGISTRY);
}