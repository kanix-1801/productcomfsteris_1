/**
 * @description Selector for RateList__c SOQL used by Work Order ES debrief travel and labor pricing.
 * @group Work Order Debrief
 */
public with sharing class RateListSelector {
    /**
     * @description Selects Rate Lists with price fields required for ES debrief Travel Type, travel, and labor pricing.
     * @param rateListIdSet Rate List Ids
     * @return Matching Rate List records
     */
    public static List<RateList__c> selectByIdsForDebriefPricing(Set<Id> rateListIdSet) {
        if (rateListIdSet == null || rateListIdSet.isEmpty()) {
            return new List<RateList__c>();
        }

        return [
            SELECT
                Id,
                Name,
                LaborHour__c,
                TravelHour__c,
                PremiumRateHour__c,
                ExtendedOvertimeRatePerHour__c,
                TravelZone1__c,
                TravelZone2__c,
                TravelZone3__c,
                TravelZone4__c
            FROM RateList__c
            WHERE Id IN :rateListIdSet
        ];
    }
}