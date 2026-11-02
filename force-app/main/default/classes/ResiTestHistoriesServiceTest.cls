/**
 * @description Tests for ResiTestHistoriesService (GW-5492).
 */
@IsTest
private class ResiTestHistoriesServiceTest {
    @IsTest
    static void testCreateForReceiving_createsHistory() {
        WorkOrder workOrder = new WorkOrder(Subject = 'GW5492 Resi History WO', Status = 'Received');
        insert workOrder;

        Test.startTest();
        Id historyId = ResiTestHistoriesService.createForReceiving(
            workOrder.Id,
            null,
            'Clean'
        );
        Test.stopTest();

        Assert.isNotNull(historyId);
        ResiTestHistory__c history = [
            SELECT WorkOrder__c, DisinfectionStatus__c, TestCompletionDate__c
            FROM ResiTestHistory__c
            WHERE Id = :historyId
        ];
        Assert.areEqual(workOrder.Id, history.WorkOrder__c);
        Assert.areEqual('Clean', history.DisinfectionStatus__c);
        Assert.isNotNull(history.TestCompletionDate__c);
    }

    @IsTest
    static void testCreateForReceiving_blankWorkOrderThrows() {
        Boolean threw = false;
        try {
            ResiTestHistoriesService.createForReceiving(null, null, 'Clean');
        } catch (Exception e) {
            threw = true;
        }
        Assert.isTrue(threw);
    }
}