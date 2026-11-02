/**
 * @author PWC Developer
 * @date 2026/07/27
 *
 * @group Product Sub-Group Detail
 *
 * @description
 * GC-3129 - SOQL selector for QuoteLineItem records used when deriving Product Sub-Group Detail on Opportunity.
 */
public with sharing class QuoteLineItemSelector extends SoqlQueryBuilder {
    /**
     * @description GW-3600 - Binds this selector to QuoteLineItem for SoqlQueryBuilder queries.
     */
    public QuoteLineItemSelector() {
        this.objectName = 'QuoteLineItem';
    }

    /**
     * @description Returns Quote Line Item rows for Quotes related to the given Opportunity Ids.
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
     * @description GW-4777/5676 - Selects a Quote Line Item for given id.
     * @param quoteLineItemId Quote Line Item Id
     * @return Matching Quote Line Item, or null
     */
    public static List<QuoteLineItem> selectQuoteLineItemById(Id quoteLineItemId, List<String> fields) {
        if (quoteLineItemId == null || fields == null || fields.isEmpty()) {
            return new List<QuoteLineItem>();
        }

        return (List<QuoteLineItem>) SoqlQueryBuilder.fromObject('QuoteLineItem')
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
}