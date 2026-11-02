/**
 * @description GC-3431 Selector for EPP Opportunities, eligible Price Book Entries, and Opportunity Products.
 *
 *              Responsibilities:
 *              1. Read the Opportunity price book, stage, currency, and record type.
 *              2. Search active Standard Price Book entries by product flags, not the Opportunity Price Book.
 *              3. Re-check selected entries before Opportunity Products are created.
 *              4. Return existing capital or consumable Opportunity Products for the EPP tables.
 * @author      Vinay
 * @date        2026-09-29
 */
public with sharing class EPPPricebookEntrySelector {

    private static Id standardPricebookId;

    /**
     * @description Returns the org Standard Price Book. Tests fall back to Test.getStandardPricebookId when the standard flag is not visible.
     * @return Standard Price Book Id.
     */
    private static Id getStandardPricebookId() {
        if (standardPricebookId != null) {
            return standardPricebookId;
        }

        List<Pricebook2> standardPricebooks = [
            SELECT Id
            FROM Pricebook2
            WHERE IsStandard = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!standardPricebooks.isEmpty()) {
            standardPricebookId = standardPricebooks[0].Id;
        } else if (Test.isRunningTest()) {
            standardPricebookId = Test.getStandardPricebookId();
        }
        return standardPricebookId;
    }

    /**
     * @description Returns the Opportunity used to validate EPP product search and creation.
     * @param opportunityId Equipment Placement Program Opportunity Id.
     * @return The Opportunity, or null when the Id does not match a record.
     */
    public static Opportunity selectOpportunity(Id opportunityId) {
        List<Opportunity> opportunities = [
            SELECT Id, Pricebook2Id, StageName, CurrencyIsoCode, RecordType.DeveloperName
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        return opportunities.isEmpty() ? null : opportunities[0];
    }

    /**
     * @description Returns active Standard Price Book entries for the Opportunity currency that match the EPP section and search text.
     * @param isConsumable True for the Consumables section; false for Capital Equipment.
     * @param searchKey Product name or product code text. A blank value matches all eligible products.
     * @param currencyIsoCode Currency of the Opportunity. Keeps multi-currency products from appearing twice.
     * @return Up to 200 matching Standard Price Book entries, ordered by product name.
     */
    public static List<PricebookEntry> searchEligibleEntries(
        Boolean isConsumable,
        String searchKey,
        String currencyIsoCode
    ) {
        Id standardPricebookId = getStandardPricebookId();
        String searchTerm = '%' + (String.isBlank(searchKey) ? '' : searchKey.trim()) + '%';

        return [
            SELECT Id, UnitPrice, Pricebook2Id,
                   Product2Id, Product2.Name, Product2.ProductCode,
                   Product2.Family, Product2.ItemFamily__c, Product2.BusinessUnit__c,
                   Product2.Description,
                   Product2.EPPEligible__c, Product2.IsConsumable__c
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPricebookId
              AND CurrencyIsoCode = :currencyIsoCode
              AND IsActive = true
              AND Product2.IsActive = true
              AND Product2.EPPEligible__c = true
              AND Product2.IsConsumable__c = :isConsumable
              AND (Product2.Name LIKE :searchTerm OR Product2.ProductCode LIKE :searchTerm)
            WITH SYSTEM_MODE
            ORDER BY Product2.Name
            LIMIT 200
        ];
    }

    /**
     * @description Returns the requested Price Book Entries only when they remain eligible for this Opportunity and section.
     * @param pricebookEntryIds Standard Price Book Entry Ids selected in the EPP product modal.
     * @param isConsumable True for the Consumables section; false for Capital Equipment.
     * @param currencyIsoCode Currency of the Opportunity.
     * @return Eligible Standard Price Book entries. An empty list is returned when no Ids are supplied.
     */
    public static List<PricebookEntry> selectEligibleEntriesByIds(
        Set<Id> pricebookEntryIds,
        Boolean isConsumable,
        String currencyIsoCode
    ) {
        if (pricebookEntryIds == null || pricebookEntryIds.isEmpty()) {
            return new List<PricebookEntry>();
        }

        Id standardPricebookId = getStandardPricebookId();
        return [
            SELECT Id, UnitPrice, Pricebook2Id, Product2Id, Product2.Name,
                   Product2.EPPEligible__c, Product2.IsConsumable__c
            FROM PricebookEntry
            WHERE Id IN :pricebookEntryIds
              AND Pricebook2Id = :standardPricebookId
              AND CurrencyIsoCode = :currencyIsoCode
              AND IsActive = true
              AND Product2.IsActive = true
              AND Product2.EPPEligible__c = true
              AND Product2.IsConsumable__c = :isConsumable
            WITH SYSTEM_MODE
        ];
    }

    /**
     * @description Returns Price Book Entries already on the Opportunity Price Book for the selected products.
     * @param pricebookId Price Book assigned to the Opportunity.
     * @param productIds Products selected from the Standard Price Book.
     * @param currencyIsoCode Currency of the Opportunity.
     * @return Existing entries, including inactive entries that can be reactivated.
     */
    public static List<PricebookEntry> selectOpportunityEntries(
        Id pricebookId,
        Set<Id> productIds,
        String currencyIsoCode
    ) {
        if (productIds == null || productIds.isEmpty()) {
            return new List<PricebookEntry>();
        }

        return [
            SELECT Id, UnitPrice, Product2Id, IsActive
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
              AND Product2Id IN :productIds
              AND CurrencyIsoCode = :currencyIsoCode
            WITH SYSTEM_MODE
        ];
    }

    /**
     * @description Returns existing Opportunity Products for one EPP product section.
     * @param opportunityId Equipment Placement Program Opportunity Id.
     * @param isConsumable True for consumable lines; false for capital equipment lines.
     * @return Opportunity Products ordered by created date.
     */
    public static List<OpportunityLineItem> selectLines(Id opportunityId, Boolean isConsumable) {
        return [
            SELECT Id, PricebookEntryId, Product2Id, Product2.Name, Product2.ProductCode,
                   ProductFamily__c, BusinessUnit__c,
                   Quantity, UnitPrice, TotalPrice,
                   PlacementStartDate__c, PlacementEndDate__c,
                   ConsumptionFrequency__c, ElevatedEPPPricingApplicable__c, EPPPrice__c,
                   CommitmentStartDate__c, CommitmentEndDate__c,
                   AnnualCommittedRevenue__c, ContractTermRevenue__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunityId
              AND Product2.EPPEligible__c = true
              AND Product2.IsConsumable__c = :isConsumable
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
        ];
    }
}