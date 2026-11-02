/**
 * @author PWC Developer
 * @date 2026/10/30
 *
 * @group Lost Business Products
 *
 * @description
 * GC-3574 - SOQL selector for the Lost Business product selection screen. Reads originating
 * Opportunity Products, the target opportunity price book, and active price book entries.
 */
public with sharing class LostBusinessProductSelector {

    /**
     * @description
     * GC-3574 - Returns the opportunity price book and currency used when adding products.
     *
     * @param opportunityId Opportunity to load.
     * @return The opportunity, or null when the Id is blank or not found.
     *
     * @example
     * LostBusinessProductSelector.selectOpportunityById(opportunityId);
     */
    public static Opportunity selectOpportunityById(Id opportunityId) {
        if (opportunityId == null) {
            return null;
        }

        List<Opportunity> opportunityList = [
            SELECT Id, Pricebook2Id, CurrencyIsoCode
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        return opportunityList.isEmpty() ? null : opportunityList[0];
    }

    /**
     * @description
     * GC-3574 - Returns Opportunity Products for one opportunity, with the product and price book
     * fields the selection screen displays.
     *
     * @param opportunityId Originating or Lost Business opportunity.
     * @return Matching Opportunity Products ordered by product name.
     *
     * @example
     * LostBusinessProductSelector.selectLinesByOpportunityId(opportunityId);
     */
    public static List<OpportunityLineItem> selectLinesByOpportunityId(Id opportunityId) {
        if (opportunityId == null) {
            return new List<OpportunityLineItem>();
        }

        return [
            SELECT Id,
                   Quantity,
                   UnitPrice,
                   ConsumptionFrequency__c,
                   Product_Number_SKU__c,
                   PricebookEntryId,
                   PricebookEntry.IsActive,
                   PricebookEntry.UnitPrice,
                   PricebookEntry.Pricebook2Id,
                   PricebookEntry.Product2Id,
                   PricebookEntry.Product2.Name,
                   PricebookEntry.Product2.ProductCode,
                   PricebookEntry.CurrencyIsoCode
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunityId
            WITH SYSTEM_MODE
            ORDER BY PricebookEntry.Product2.Name ASC
        ];
    }

    /**
     * @description
     * GC-3574 - Returns the requested Opportunity Products only when they belong to the originating
     * opportunity. A line from any other opportunity is excluded.
     *
     * @param lineItemIds Selected originating Opportunity Product Ids.
     * @param opportunityId Originating opportunity Id.
     * @return Matching Opportunity Products.
     *
     * @example
     * LostBusinessProductSelector.selectLinesByIdsAndOpportunity(lineItemIds, opportunityId);
     */
    public static List<OpportunityLineItem> selectLinesByIdsAndOpportunity(
        Set<Id> lineItemIds,
        Id opportunityId
    ) {
        if (lineItemIds == null || lineItemIds.isEmpty() || opportunityId == null) {
            return new List<OpportunityLineItem>();
        }

        return [
            SELECT Id,
                   Quantity,
                   UnitPrice,
                   ConsumptionFrequency__c,
                   Product_Number_SKU__c,
                   PricebookEntryId,
                   PricebookEntry.IsActive,
                   PricebookEntry.UnitPrice,
                   PricebookEntry.Pricebook2Id,
                   PricebookEntry.Product2Id,
                   PricebookEntry.Product2.Name,
                   PricebookEntry.Product2.ProductCode,
                   PricebookEntry.CurrencyIsoCode
            FROM OpportunityLineItem
            WHERE Id IN :lineItemIds
            AND OpportunityId = :opportunityId
            WITH SYSTEM_MODE
        ];
    }

    /**
     * @description
     * GC-3574 - Returns price book entry Ids already present on the Lost Business opportunity so a
     * repeated save does not create a second line for the same product.
     *
     * @param opportunityId Lost Business opportunity Id.
     * @return Price book entry Ids already used on that opportunity.
     *
     * @example
     * LostBusinessProductSelector.selectPricebookEntryIds(opportunityId);
     */
    public static Set<Id> selectPricebookEntryIds(Id opportunityId) {
        Set<Id> pricebookEntryIds = new Set<Id>();

        if (opportunityId == null) {
            return pricebookEntryIds;
        }

        for (OpportunityLineItem lineItem : [
            SELECT PricebookEntryId
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunityId
            WITH SYSTEM_MODE
        ]) {
            pricebookEntryIds.add(lineItem.PricebookEntryId);
        }

        return pricebookEntryIds;
    }

    /**
     * @description
     * GC-3574 - Returns active products, including the product code copied onto Product Number / SKU.
     *
     * @param productIds Products the rep selected from the catalogue.
     * @return Active products keyed by Id.
     *
     * @example
     * LostBusinessProductSelector.selectActiveProducts(productIds);
     */
    public static Map<Id, Product2> selectActiveProducts(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new Map<Id, Product2>();
        }

        return new Map<Id, Product2>([
            SELECT Id, Name, ProductCode
            FROM Product2
            WHERE Id IN :productIds
            AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]);
    }

    /**
     * @description
     * GC-3574 - Returns the org standard price book, used when neither opportunity has a price book yet.
     *
     * @return Standard price book Id, or null when none is available.
     *
     * @example
     * LostBusinessProductSelector.selectStandardPricebookId();
     */
    public static Id selectStandardPricebookId() {
        List<Pricebook2> pricebookList = [
            SELECT Id
            FROM Pricebook2
            WHERE IsStandard = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (!pricebookList.isEmpty()) {
            return pricebookList[0].Id;
        }

        // The standard price book is not returned by SOQL in a unit test unless the test
        // has already called Test.getStandardPricebookId in the same transaction.
        if (Test.isRunningTest()) {
            return Test.getStandardPricebookId();
        }

        return null;
    }

    /**
     * @description
     * GC-3574 - Returns active price book entries for the products on the Lost Business price book
     * and currency.
     *
     * @param pricebookId Price book on the Lost Business opportunity.
     * @param productIds Products the rep selected.
     * @param currencyCode Opportunity currency.
     * @return Active matching price book entries.
     *
     * @example
     * LostBusinessProductSelector.selectActiveEntries(pricebookId, productIds, currencyCode);
     */
    public static List<PricebookEntry> selectActiveEntries(
        Id pricebookId,
        Set<Id> productIds,
        String currencyCode
    ) {
        if (pricebookId == null || productIds == null || productIds.isEmpty() || String.isBlank(currencyCode)) {
            return new List<PricebookEntry>();
        }

        return [
            SELECT Id, Product2Id, UnitPrice, IsActive, CurrencyIsoCode
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
            AND Product2Id IN :productIds
            AND IsActive = TRUE
            AND CurrencyIsoCode = :currencyCode
            WITH SYSTEM_MODE
        ];
    }
}