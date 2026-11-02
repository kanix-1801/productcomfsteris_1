/**
 * @description Selector for Regional Control and Regional Control Setting used by ES debrief expense types.
 * @group Work Order Debrief
 * @see WoDebriefRegionalExpenseController
 */
public without sharing class RegionalControlSelector {
    /**
     * @description Selects active Regional Controls for a business unit and country.
     * @param businessUnit Account Customer Class Code
     * @param country Work Order Country
     * @return Matching active Regional Control records, oldest first
     */
    public static List<Regional_Control__c> selectByBusinessUnitAndCountry(
        String businessUnit,
        String country
    ) {
        if (String.isBlank(businessUnit) || String.isBlank(country)) {
            return new List<Regional_Control__c>();
        }

        return [
            SELECT Id, BusinessUnit__c, Country__c, PricingMethod__c, MaximumPrice__c
            FROM Regional_Control__c
            WHERE BusinessUnit__c = :businessUnit
            AND Country__c = :country
            AND Active__c = true
            ORDER BY CreatedDate ASC
        ];
    }

    /**
     * @description Selects Expense Type settings for Regional Control Ids.
     * @param regionalControlIdSet Regional Control Ids
     * @return Matching Regional Control Setting records
     */
    public static List<Regional_Control_Setting__c> selectExpenseTypeSettingsByControlIds(
        Set<Id> regionalControlIdSet
    ) {
        if (regionalControlIdSet == null || regionalControlIdSet.isEmpty()) {
            return new List<Regional_Control_Setting__c>();
        }

        return [
            SELECT Id, Regional_Control__c, SettingName__c, AllowedValues__c
            FROM Regional_Control_Setting__c
            WHERE Regional_Control__c IN :regionalControlIdSet
            AND SettingName__c = 'Expense Type'
            ORDER BY CreatedDate ASC
        ];
    }

    /**
     * @description Selects Pricing Rules for Regional Control Ids, lowest Starting Qty first.
     * @param regionalControlIdSet Regional Control Ids
     * @return Matching Pricing Rule records
     */
    public static List<Pricing_Rule__c> selectPricingRulesByControlIds(Set<Id> regionalControlIdSet) {
        if (regionalControlIdSet == null || regionalControlIdSet.isEmpty()) {
            return new List<Pricing_Rule__c>();
        }

        return [
            SELECT Id, RegionalControl__c, StartingQuantity__c, EndingQuantity__c, Rate__c
            FROM Pricing_Rule__c
            WHERE RegionalControl__c IN :regionalControlIdSet
            ORDER BY StartingQuantity__c ASC, CreatedDate ASC
        ];
    }
}