/**
 * @description GC-3618 - SOQL-only selector for incomplete Healthcare Quote cleanup.
 *              Queries only. No business processing and no DML.
 */
public without sharing class IncompleteHcQuoteCleanupSelector {
    /**
     * @description Healthcare Quote record types used by Generate Quote and Prospect SC sync.
     *              Matches HCSales and HCSales* 
     */
    public static final String HC_QUOTE_RECORD_TYPE_LIKE = 'HCSales%';

    /**
     * @description Query locator for HC Quotes whose Sales Connection quote id was never received.
     *              Salesforce stores a blank text value as null, so this is the SC Quote Id = blank check.
     * @return Quote rows eligible for deletion.
     */
    public static Database.QueryLocator getIncompleteQuoteQueryLocator() {
        return Database.getQueryLocator([
            SELECT Id
            FROM Quote
            WHERE RecordType.DeveloperName LIKE :HC_QUOTE_RECORD_TYPE_LIKE
              AND SalesConnectionQuoteID__c = null
            WITH SYSTEM_MODE
        ]);
    }

    /**
     * @description Loads Quote Lines for the quotes in the current batch scope.
     * @param quoteIds Quote Ids from the batch scope.
     * @return QuoteLineItem rows for those quotes.
     */
    public static List<QuoteLineItem> selectLineItemsByQuoteIds(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return new List<QuoteLineItem>();
        }

        return [
            SELECT Id, QuoteId
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds
            WITH SYSTEM_MODE
        ];
    }
}