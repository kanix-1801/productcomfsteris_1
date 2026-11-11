/**
 * @author Uptima
 * @date 2026/07/27
 * @group Selectors
 * @description QuoteLineItem selector: binds SoqlQueryBuilder for invoker-built queries.
 *              Legacy selectByOpportunityIds remains for QACBM (GC-3129) parity.
 */
public with sharing class QuoteLineItemSelector extends SoqlQueryBuilder {
    /**
     * @description Binds this selector to QuoteLineItem for SoqlQueryBuilder queries.
     */
    public QuoteLineItemSelector() {
        super('QuoteLineItem');
    }

    /**
     * @description Returns Quote Line Item rows for Quotes related to the given Opportunity Ids.
     *              Already on QACBM (GC-3129); keep for org parity.
     * @param opportunityIds Opportunity Id set.
     * @return QuoteLineItem rows with Product2Id and parent Quote OpportunityId.
     */
    public static List<QuoteLineItem> selectByOpportunityIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return new List<QuoteLineItem>();
        }

        return [
            SELECT Id, Product2Id, QuoteId, Quote.OpportunityId
            FROM QuoteLineItem
            WHERE Quote.OpportunityId IN :opportunityIds
            WITH USER_MODE
        ];
    }

    /**
     * @description GW-4777/5676 - Selects a Quote Line Item for given id with caller-supplied fields.
     * @param quoteLineItemId Quote Line Item Id
     * @param fields Field API names to select
     * @return Matching Quote Line Item rows (0 or 1)
     */
    public static List<QuoteLineItem> selectQuoteLineItemById(Id quoteLineItemId, List<String> fields) {
        if (quoteLineItemId == null || fields == null || fields.isEmpty()) {
            return new List<QuoteLineItem>();
        }

        return (List<QuoteLineItem>) new QuoteLineItemSelector()
            .selectFields(fields)
            .whereEquals('Id', quoteLineItemId)
            .limitTo(1)
            .execute();
    }
}