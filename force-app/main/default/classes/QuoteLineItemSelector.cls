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
     * @description GW-5102 - Quote Line Items used when processing Repair Center quote email replies.
     * @param quoteId Quote Id
     * @return Matching Quote Line Item rows
     */
    public static List<QuoteLineItem> selectForQuoteEmailReplyByQuoteId(Id quoteId) {
        if (quoteId == null) {
            return new List<QuoteLineItem>();
        }

        return [
            SELECT
                Id,
                QuoteId,
                Quantity,
                Description,
                LineType__c,
                Status__c,
                Product2Id,
                Product2.Name,
                Product2.ProductCode,
                Product2.Description,
                Product2.Model__c,
                Product2.ProductType__c,
                WorkOrderLineItem__c,
                ParentWorkOrderLineItem__c,
                Asset__c,
                SerialNumber__c,
                Item__c,
                ItemCode__c,
                ItemDescription__c,
                ProductDescription__c,
                WorkOrder__c,
                TopLevelWorkOrder__c
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            WITH SYSTEM_MODE
            ORDER BY LineNumber ASC
        ];
    }

    /**
     * @description GW-5333 - Selects Quote Line Items for Approve/Reject Quote.
     * @param quoteId Quote Id
     * @return Matching Quote Line Item rows
     */
    public static List<QuoteLineItem> selectForApproveRejectByQuoteId(Id quoteId) {
        if (quoteId == null) {
            return new List<QuoteLineItem>();
        }

        return [
            SELECT
                Id,
                QuoteId,
                LineNumber,
                Quantity,
                Description,
                TotalPrice,
                LineType__c,
                Status__c,
                QuoteComments__c,
                ParentQuoteLineItemId,
                Product2Id,
                WorkOrderLineItem__c,
                ParentWorkOrderLineItem__c,
                Asset__c,
                SerialNumber__c,
                Item__c,
                ItemCode__c,
                ItemDescription__c,
                ProductDescription__c,
                WorkOrder__c,
                TopLevelWorkOrder__c
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            WITH SYSTEM_MODE
            ORDER BY LineNumber ASC
        ];
    }

    /**
     * @description GW-5333 - Selects a Quote Line Item for comment updates.
     * @param quoteLineItemId Quote Line Item Id
     * @return Matching Quote Line Item, or null
     */
    public static QuoteLineItem selectForApproveRejectById(Id quoteLineItemId) {
        if (quoteLineItemId == null) {
            return null;
        }

        List<QuoteLineItem> lineItems = [
            SELECT
                Id,
                QuoteId,
                QuoteComments__c
            FROM QuoteLineItem
            WHERE Id = :quoteLineItemId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return lineItems.isEmpty() ? null : lineItems[0];
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

    /**
     * @description GW-4585 - Quote lines used when pricing JSON does not include line rows.
     * @param quoteIds Quote header Ids
     * @return Quote line items with product pricing fields
     */
    public static List<QuoteLineItem> selectForPricingFrameworkByQuoteIds(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return new List<QuoteLineItem>();
        }

        return [
            SELECT Id, Product2.ProductCode, Product2.PricingSource__c, Quantity
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds
        ];
    }

    /**
     * @description GW-4585 - Quote lines used to build Salesforce Headless Pricing JSON.
     * @param lineIds Quote line item Ids
     * @return Quote line items with header and price book context
     */
    public static Map<Id, QuoteLineItem> selectForPricingFrameworkHeadlessByIds(Set<Id> lineIds) {
        if (lineIds == null || lineIds.isEmpty()) {
            return new Map<Id, QuoteLineItem>();
        }

        return new Map<Id, QuoteLineItem>([
            SELECT
                Id,
                QuoteId,
                Product2Id,
                Product2.ProductCode,
                Product2.PricingSource__c,
                PricebookEntryId,
                Quantity,
                PricebookEntry.Pricebook2Id,
                Quote.Pricebook2Id,
                Quote.CurrencyIsoCode,
                Quote.AccountId
            FROM QuoteLineItem
            WHERE Id IN :lineIds
        ]);
    }

    /**
     * @description GW-5892 - Lines of a Field Service quote for the Edit Quote editor, in display order.
     * @param quoteId Quote Id
     * @return Quote lines
     */
    public static List<QuoteLineItem> selectForFieldServiceEditorByQuoteId(Id quoteId) {
        if (quoteId == null) {
            return new List<QuoteLineItem>();
        }
        return [
            SELECT Id, LineType__c, Product2Id, Product2.Name, Product2.ProductCode, Quantity, Rate__c, TravelType__c,
                ExpenseType__c, ListPrice, UnitPrice, Discount, TotalPrice, Description, IsManualPrice__c,
                PricingMessage__c
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            ORDER BY SortOrder ASC NULLS LAST, CreatedDate ASC
        ];
    }
}