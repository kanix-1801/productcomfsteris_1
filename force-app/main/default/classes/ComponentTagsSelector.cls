/**
 * @author Sagar Anand
 * @date 2026-10-28
 * @description GW-6095 - Selector for ComponentTag__c (Component Tags of a BOM Component).
 *              Queries run in USER_MODE through SoqlQueryBuilder / DynamicSoqlQuery.
 * @group Work Order Debrief
 * @see WorkOrderLineItemsService
 */
public with sharing class ComponentTagsSelector extends SoqlQueryBuilder {
    /** @description Fields needed to build Component Tag options for the debrief LWC. */
    private static final List<String> OPTION_FIELDS = new List<String>{ 'Id', 'Name', 'BomComponent__c' };

    /**
     * @description Binds this selector to ComponentTag__c for SoqlQueryBuilder queries.
     */
    public ComponentTagsSelector() {
        this.objectName = 'ComponentTag__c';
    }

    /**
     * @description GW-6095 - Selects the Component Tags of the given BOM Components, ordered by Name.
     * @param bomComponentIdSet ProductRelatedMaterial (BOM Component) Ids
     * @return Matching Component Tags (empty when the input is null or empty)
     * @example
     * List<ComponentTag__c> tags = ComponentTagsSelector.selectByBomComponentIds(new Set<Id>{ bomComponentId });
     */
    public static List<ComponentTag__c> selectByBomComponentIds(Set<Id> bomComponentIdSet) {
        List<String> bomComponentIdList = new List<String>();
        if (bomComponentIdSet != null) {
            for (Id bomComponentId : bomComponentIdSet) {
                if (bomComponentId != null) {
                    bomComponentIdList.add(bomComponentId);
                }
            }
        }
        if (bomComponentIdList.isEmpty()) {
            return new List<ComponentTag__c>();
        }

        return (List<ComponentTag__c>) new ComponentTagsSelector()
            .selectFields(OPTION_FIELDS)
            .whereIn('BomComponent__c', bomComponentIdList)
            .orderBy('Name')
            .execute();
    }
}