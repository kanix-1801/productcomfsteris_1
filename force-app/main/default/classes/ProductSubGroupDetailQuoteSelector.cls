/**
 * @author PWC Developer
 * @date 2026/07/27
 *
 * @group Product Sub-Group Detail
 *
 * @description
 * GC-3129 - Quote selector used by Product Sub-Group Detail automation.
 */
public with sharing class ProductSubGroupDetailQuoteSelector {
    /**
     * @description Returns Opportunity Ids keyed by Quote Id.
     * @param quoteIds Quote Id set.
     * @return Map of Quote Id to related Opportunity Id.
     */
    public static Map<Id, Id> selectOpportunityIdByQuoteId(Set<Id> quoteIds) {
        Map<Id, Id> opportunityIdByQuoteId = new Map<Id, Id>();
        if (quoteIds == null || quoteIds.isEmpty()) {
            return opportunityIdByQuoteId;
        }

        for (Quote quoteRecord : [
            SELECT Id, OpportunityId
            FROM Quote
            WHERE Id IN :quoteIds
            AND OpportunityId != NULL
            WITH USER_MODE
        ]) {
            opportunityIdByQuoteId.put(quoteRecord.Id, quoteRecord.OpportunityId);
        }

        return opportunityIdByQuoteId;
    }
}