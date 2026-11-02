/**
 * @description Tests for WoDebriefRateListController.
 * @see WoDebriefRateListController
 */
@IsTest
private class WoDebriefRateListControllerTest {
    @IsTest
    static void getRateListForWorkOrder_nullId_returnsNull() {
        Test.startTest();
        WoDebriefRateListController.RateListPrices result =
            WoDebriefRateListController.getRateListForWorkOrder(null);
        Test.stopTest();
        System.assertEquals(null, result);
    }

    @IsTest
    static void getRateListForWorkOrder_withAccountRateList_returnsPrices() {
        RateList__c rateList = new RateList__c(
            Name = 'GW2967 Rate List',
            TravelHour__c = 50,
            TravelZone1__c = 100,
            TravelZone2__c = 200,
            PremiumRateHour__c = 75,
            ExtendedOvertimeRatePerHour__c = 90,
            LaborHour__c = 40
        );
        insert rateList;

        Account account = new Account(
            Name = 'GW2967 Account',
            SourceSystemID__c = 'ORACLE-GW2967-' + String.valueOf(Crypto.getRandomInteger()),
            RateList__c = rateList.Id
        );
        insert account;

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'GW2967 Rate List WO'
        );
        insert workOrder;

        Test.startTest();
        WoDebriefRateListController.RateListPrices result =
            WoDebriefRateListController.getRateListForWorkOrder(workOrder.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(rateList.Id, result.rateListId);
        System.assertEquals(40, result.laborHour);
        System.assertEquals(50, result.travelHour);
        System.assertEquals(100, result.travelZone1);
        System.assertEquals(200, result.travelZone2);
        System.assertEquals(75, result.premiumRateHour);
        System.assertEquals(90, result.extendedOvertimeRatePerHour);
    }

    @IsTest
    static void getRateListForWorkOrder_noRateList_returnsNull() {
        Account account = new Account(
            Name = 'GW2967 No RL Account',
            SourceSystemID__c = 'ORACLE-GW2967-NRL-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert account;

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'GW2967 No Rate List WO'
        );
        insert workOrder;

        Test.startTest();
        WoDebriefRateListController.RateListPrices result =
            WoDebriefRateListController.getRateListForWorkOrder(workOrder.Id);
        Test.stopTest();

        System.assertEquals(null, result);
    }
}