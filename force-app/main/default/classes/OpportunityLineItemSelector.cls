/**
 * @author PWC Developer
 * @date 2026/07/23
 *
 * @group Product Sub-Group Detail
 *
 * @description
 * GC-3129 - SOQL selector for OpportunityLineItem records used when deriving Product Sub-Group Detail on Opportunity.
 */
public with sharing class OpportunityLineItemSelector {
    /**
     * @description Returns Opportunity Product rows for the given Opportunity Ids.
     * @param opportunityIds Opportunity Id set.
     * @return OpportunityLineItem rows with OpportunityId and Product2Id.
     */
    public static List<OpportunityLineItem> selectByOpportunityIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return new List<OpportunityLineItem>();
        }

        return [
            SELECT Id, OpportunityId, Product2Id
            FROM OpportunityLineItem
            WHERE OpportunityId IN :opportunityIds
            WITH USER_MODE
        ];
    }
}