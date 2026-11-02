/**
 * @description Tests for WorkOrderSelector Allowed Unit and ship-date queries.
 * @see WorkOrderSelector
 */
@IsTest
private class WorkOrderSelectorTest {
    /**
     * @description Creates an Account with required Source System Id for Work Order tests.
     * @param name Account Name
     * @return Inserted Account
     */
    private static Account createAccount(String name) {
        Account account = new Account(
            Name = name,
            SourceSystemID__c = 'ORACLE-WOSEL-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert account;
        return account;
    }

    /**
     * @description Verifies null/empty Id sets return an empty Work Order list.
     */
    @IsTest
    static void selectByIdsForAllowedUnit_emptyOrNull_returnsEmpty() {
        Test.startTest();
        List<WorkOrder> nullResult = WorkOrderSelector.selectByIdsForAllowedUnit(null);
        List<WorkOrder> emptyResult = WorkOrderSelector.selectByIdsForAllowedUnit(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, nullResult.size());
        System.assertEquals(0, emptyResult.size());
    }

    /**
     * @description Verifies Allowed Unit selector returns the requested Work Order.
     */
    @IsTest
    static void selectByIdsForAllowedUnit_withWorkOrder_returnsRecord() {
        Account account = createAccount('WO Selector Account');
        WorkOrder workOrder = new WorkOrder(AccountId = account.Id, Subject = 'WO Selector');
        insert workOrder;

        Test.startTest();
        List<WorkOrder> results =
            WorkOrderSelector.selectByIdsForAllowedUnit(new Set<Id>{ workOrder.Id });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(workOrder.Id, results[0].Id);
    }

    /**
     * @description Verifies Rate List selector returns Account.RateList__c for the requested Work Order.
     */
    @IsTest
    static void selectByIdsForRateList_withWorkOrder_returnsAccountRateList() {
        RateList__c rateList = new RateList__c(
            Name = 'WO Selector Rate List',
            TravelHour__c = 25,
            LaborHour__c = 25
        );
        insert rateList;

        Account account = createAccount('WO Selector Rate List Account');
        account.RateList__c = rateList.Id;
        update account;

        WorkOrder workOrder = new WorkOrder(AccountId = account.Id, Subject = 'WO Rate List');
        insert workOrder;

        Test.startTest();
        List<WorkOrder> emptyResult = WorkOrderSelector.selectByIdsForRateList(new Set<Id>());
        List<WorkOrder> results =
            WorkOrderSelector.selectByIdsForRateList(new Set<Id>{ workOrder.Id });
        Test.stopTest();

        System.assertEquals(0, emptyResult.size());
        System.assertEquals(1, results.size());
        System.assertEquals(rateList.Id, results[0].Account.RateList__c);
    }

    /**
     * @description Verifies ship-date selector returns matching Work Orders (including empty set).
     */
    @IsTest
    static void selectWorkOrdersWithOperatingHours_returnsMatchingRows() {
        Account account = createAccount('WO OH Account');
        WorkOrder workOrder = new WorkOrder(AccountId = account.Id, Subject = 'WO OH');
        insert workOrder;

        Test.startTest();
        List<WorkOrder> empty =
            WorkOrderSelector.selectWorkOrdersWithOperatingHours(new Set<Id>());
        List<WorkOrder> results =
            WorkOrderSelector.selectWorkOrdersWithOperatingHours(new Set<Id>{ workOrder.Id });
        Test.stopTest();

        System.assertEquals(0, empty.size());
        System.assertEquals(1, results.size());
        System.assertEquals(workOrder.Id, results[0].Id);
    }

    /**
     * @description Verifies holiday selector executes for empty and non-empty Operating Hours sets.
     */
    @IsTest
    static void selectOperatingHoursHolidays_queriesByOperatingHours() {
        OperatingHours oh = new OperatingHours(Name = 'WO Selector OH', TimeZone = 'America/New_York');
        insert oh;

        Test.startTest();
        List<OperatingHoursHoliday> empty =
            WorkOrderSelector.selectOperatingHoursHolidays(new Set<Id>());
        List<OperatingHoursHoliday> results =
            WorkOrderSelector.selectOperatingHoursHolidays(new Set<Id>{ oh.Id });
        Test.stopTest();

        System.assertEquals(0, empty.size());
        System.assertNotEquals(null, results);
    }
}