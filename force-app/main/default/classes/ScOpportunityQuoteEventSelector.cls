/**
 * @author Himanshu Chaurasia
 * @date 2026/09/30
 *
 * @description GC-3457 - Data access for Opportunity / Quote SC event payloads.
 */
public with sharing class ScOpportunityQuoteEventSelector {
    /**
     * @description Loads Quote Ids and Sales Connection identifiers for outbound events.
     * @param quoteIds Salesforce Quote Ids included in the event.
     * @return Quote rows with Id and SalesConnectionQuoteID__c.
     */
    public static List<Quote> selectQuotesByIds(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return new List<Quote>();
        }

        return [
            SELECT Id,
                SalesConnectionQuoteID__c
            FROM Quote
            WHERE Id IN :quoteIds
            WITH SYSTEM_MODE
        ];
    }

    /**
     * @description Loads Quotes on an Opportunity that match Sales Connection Quote Ids from the SC response.
     * @param opportunityId Parent Opportunity for the sync action.
     * @param salesConnectionQuoteIds Sales Connection Quote Ids returned by the integration.
     * @return Matching Quote rows.
     */
    public static List<Quote> selectQuotesBySalesConnectionIds(
        Id opportunityId,
        Set<String> salesConnectionQuoteIds
    ) {
        if (opportunityId == null || salesConnectionQuoteIds == null || salesConnectionQuoteIds.isEmpty()) {
            return new List<Quote>();
        }

        return [
            SELECT Id,
                SalesConnectionQuoteID__c
            FROM Quote
            WHERE OpportunityId = :opportunityId
              AND SalesConnectionQuoteID__c IN :salesConnectionQuoteIds
            WITH SYSTEM_MODE
        ];
    }
}