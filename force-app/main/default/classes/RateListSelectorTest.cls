/**
 * @description Tests for RateListSelector.
 * @see RateListSelector
 */
@IsTest
private class RateListSelectorTest {
    @IsTest
    static void selectByIdsForDebriefPricing_emptyOrNull_returnsEmpty() {
        Test.startTest();
        List<RateList__c> nullResult = RateListSelector.selectByIdsForDebriefPricing(null);
        List<RateList__c> emptyResult = RateListSelector.selectByIdsForDebriefPricing(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, nullResult.size());
        System.assertEquals(0, emptyResult.size());
    }

    @IsTest
    static void selectByIdsForDebriefPricing_withRateList_returnsPrices() {
        RateList__c rateList = new RateList__c(
            Name = 'GW2967 Selector Rate List',
            TravelHour__c = 50,
            TravelZone1__c = 100,
            LaborHour__c = 40,
            PremiumRateHour__c = 75,
            ExtendedOvertimeRatePerHour__c = 90
        );
        insert rateList;

        Test.startTest();
        List<RateList__c> results =
            RateListSelector.selectByIdsForDebriefPricing(new Set<Id>{ rateList.Id });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(rateList.Id, results[0].Id);
        System.assertEquals(40, results[0].LaborHour__c);
        System.assertEquals(50, results[0].TravelHour__c);
        System.assertEquals(100, results[0].TravelZone1__c);
        System.assertEquals(75, results[0].PremiumRateHour__c);
        System.assertEquals(90, results[0].ExtendedOvertimeRatePerHour__c);
    }
}