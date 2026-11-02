/**
 * @description Selector class for the PricebookEntry SObject (plural).
 *              GW-3913 / GW-3096 - Device Evaluation Price Book Entry queries.
 *              Distinct from PricebookEntrySelector (Generate Quote).
 */
public with sharing class PricebookEntriesSelector {
    private static Id cachedStandardPricebookId;

    /**
     * @description GW-4585 - Org Standard Price Book Id for Headless Pricing fallback.
     * @return Standard Pricebook2 Id
     */
    public static Id selectStandardPricebookId() {
        if (cachedStandardPricebookId != null) {
            return cachedStandardPricebookId;
        }
        List<Pricebook2> pricebooks = [
            SELECT Id
            FROM Pricebook2
            WHERE IsStandard = true
            LIMIT 1
        ];
        if (!pricebooks.isEmpty()) {
            cachedStandardPricebookId = pricebooks[0].Id;
        } else if (Test.isRunningTest()) {
            cachedStandardPricebookId = Test.getStandardPricebookId();
        }
        return cachedStandardPricebookId;
    }

    /**
     * @description GW-3913 / GW-3096 - Selects active PricebookEntry Ids for a Price Book,
     *              Product set, and currency (Device Evaluation PBE lookup).
     * @param pricebookId Price Book Id
     * @param productIds Product2 Ids to resolve entries for
     * @param currencyIsoCode Work Order CurrencyIsoCode
     * @return Matching PricebookEntry records (Id, Product2Id)
     */
    public static List<PricebookEntry> selectActiveByPricebookProductAndCurrency(
        Id pricebookId,
        Set<Id> productIds,
        String currencyIsoCode
    ) {
        if (pricebookId == null || productIds == null || productIds.isEmpty()) {
            return new List<PricebookEntry>();
        }
        return [
            SELECT Id, Product2Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
                AND Product2Id IN :productIds
                AND CurrencyIsoCode = :currencyIsoCode
                AND IsActive = true
            WITH SECURITY_ENFORCED
        ];
    }

    /**
     * @description GW-5102 - Active Price Book Entries with Product labels for inspection-fee WOLI create.
     * @param pricebookId Price Book Id
     * @param productIds Product2 Ids
     * @param currencyIsoCode Work Order currency
     * @return Matching PricebookEntry records
     */
    public static List<PricebookEntry> selectActiveWithProductByPricebookProductAndCurrency(
        Id pricebookId,
        Set<Id> productIds,
        String currencyIsoCode
    ) {
        if (pricebookId == null || productIds == null || productIds.isEmpty()) {
            return new List<PricebookEntry>();
        }
        return [
            SELECT
                Id,
                Product2Id,
                Product2.Name,
                Product2.ProductCode,
                Product2.Description,
                Product2.ProductType__c
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
                AND Product2Id IN :productIds
                AND CurrencyIsoCode = :currencyIsoCode
                AND IsActive = true
            WITH SYSTEM_MODE
        ];
    }
}