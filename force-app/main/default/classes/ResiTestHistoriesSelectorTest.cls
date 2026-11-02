/**
 * @description Tests for ResiTestHistoriesSelector (GW-5492).
 */
@IsTest
private class ResiTestHistoriesSelectorTest {
    @IsTest
    static void testSelectById_returnsRows() {
        WorkOrder workOrder = new WorkOrder(Subject = 'GW5492 Resi Selector WO', Status = 'Received');
        insert workOrder;
        ResiTestHistory__c history = new ResiTestHistory__c(
            WorkOrder__c = workOrder.Id,
            TestCompletionDate__c = System.now(),
            DisinfectionStatus__c = 'Clean'
        );
        insert history;

        Test.startTest();
        List<ResiTestHistory__c> rows = ResiTestHistoriesSelector.selectById(
            new Set<Id>{ history.Id }
        );
        Test.stopTest();

        Assert.areEqual(1, rows.size());
        Assert.areEqual(history.Id, rows[0].Id);
    }

    @IsTest
    static void testSelectById_emptyIds() {
        Assert.areEqual(0, ResiTestHistoriesSelector.selectById(null).size());
        Assert.areEqual(0, ResiTestHistoriesSelector.selectById(new Set<Id>()).size());
    }
}