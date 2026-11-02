/**
 * @author PWC Developer
 * @date 2026/07/07
 *
 * @group GC-2649 Generate Quote
 *
 * @description
 * Selector for PricebookEntry records used during Generate Quote.
 */
public with sharing class PricebookEntrySelector {
    @TestVisible
    private static Boolean returnNullInTest = false;

    /**
     * @description Returns the first active Pricebook Entry for a Price Book.
     * @param pricebookId Price Book Id.
     * @return Active Pricebook Entry, or null when none exist.
     */
    public static PricebookEntry selectFirstActiveByPricebookId(Id pricebookId) {
        return selectFirstActiveByPricebookId(pricebookId, null);
    }

    /**
     * @description Returns the first active Pricebook Entry for a Price Book and currency.
     * @param pricebookId Price Book Id.
     * @param currencyIsoCode Quote or Opportunity currency code.
     * @return Active Pricebook Entry, or null when none exist.
     */
    public static PricebookEntry selectFirstActiveByPricebookId(Id pricebookId, String currencyIsoCode) {
        List<PricebookEntry> pricebookEntries = selectActiveByPricebookId(pricebookId, 1, currencyIsoCode);
        return pricebookEntries.isEmpty() ? null : pricebookEntries[0];
    }

    /**
     * @description Returns active Pricebook Entries for a Price Book.
     * @param pricebookId Price Book Id.
     * @param rowLimit Maximum number of entries to return.
     * @return Active Pricebook Entries ordered by product name.
     */
    public static List<PricebookEntry> selectActiveByPricebookId(Id pricebookId, Integer rowLimit) {
        return selectActiveByPricebookId(pricebookId, rowLimit, null);
    }

    /**
     * @description Returns active Pricebook Entries for a Price Book.
     * @param pricebookId Price Book Id.
     * @param rowLimit Maximum number of entries to return.
     * @param currencyIsoCode Quote or Opportunity currency code used to filter entries in multi-currency orgs.
     * @return Active Pricebook Entries ordered by product name.
     */
    public static List<PricebookEntry> selectActiveByPricebookId(
        Id pricebookId,
        Integer rowLimit,
        String currencyIsoCode
    ) {
        if (Test.isRunningTest() && returnNullInTest) {
            return new List<PricebookEntry>();
        }

        if (pricebookId == null) {
            return new List<PricebookEntry>();
        }

        Integer limitSize = rowLimit == null || rowLimit <= 0 ? 50 : rowLimit;

        if (shouldFilterByCurrency(currencyIsoCode)) {
            return [
                SELECT Id,
                    UnitPrice,
                    Product2Id,
                    Product2.Name,
                    Product2.ProductCode,
                    CurrencyIsoCode
                FROM PricebookEntry
                WHERE Pricebook2Id = :pricebookId
                    AND IsActive = true
                    AND CurrencyIsoCode = :currencyIsoCode
                WITH USER_MODE
                ORDER BY Product2.Name ASC
                LIMIT :limitSize
            ];
        }

        return [
            SELECT Id,
                UnitPrice,
                Product2Id,
                Product2.Name,
                Product2.ProductCode
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
                AND IsActive = true
            WITH USER_MODE
            ORDER BY Product2.Name ASC
            LIMIT :limitSize
        ];
    }

    private static Boolean shouldFilterByCurrency(String currencyIsoCode) {
        return UserInfo.isMultiCurrencyOrganization() && String.isNotBlank(currencyIsoCode);
    }
}