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

    @IsTest
    static void testCreateForReceiving_mapsContaminatedStatus() {
        WorkOrder workOrder = new WorkOrder(Subject = 'GW5492 Resi Contaminated WO', Status = 'Received');
        insert workOrder;

        Test.startTest();
        Id historyId = ResiTestHistoriesService.createForReceiving(
            workOrder.Id,
            null,
            'Contaminated'
        );
        Test.stopTest();

        ResiTestHistory__c history = [
            SELECT DisinfectionStatus__c
            FROM ResiTestHistory__c
            WHERE Id = :historyId
        ];
        Assert.areEqual('Contaminated', history.DisinfectionStatus__c);
    }

    @IsTest
    static void testCreateForReceiving_passthroughNullDisinfectionStatus() {
        WorkOrder workOrder = new WorkOrder(Subject = 'GW5492 Resi Null Status WO', Status = 'Received');
        insert workOrder;

        Test.startTest();
        Id historyId = ResiTestHistoriesService.createForReceiving(workOrder.Id, null, null);
        Test.stopTest();

        ResiTestHistory__c history = [
            SELECT DisinfectionStatus__c
            FROM ResiTestHistory__c
            WHERE Id = :historyId
        ];
        Assert.isNull(history.DisinfectionStatus__c, 'Unmapped UI value should pass through');
    }

    @IsTest
    static void testCreateForReceiving_invalidStatusThrows() {
        WorkOrder workOrder = new WorkOrder(Subject = 'GW5492 Resi Invalid Status WO', Status = 'Received');
        insert workOrder;
        Boolean threw = false;

        try {
            Test.startTest();
            ResiTestHistoriesService.createForReceiving(workOrder.Id, null, 'NotAValidStatus');
            Test.stopTest();
        } catch (ResiTestHistoriesService.ResiTestHistoriesServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('Unable to create Resi-Test History'),
                'Should wrap the DML failure'
            );
        }

        Assert.isTrue(threw, 'Restricted picklist rejection should throw service exception');
    }

    @IsTest
    static void testGetById_returnsRowsAndGuardsBlank() {
        WorkOrder workOrder = new WorkOrder(Subject = 'GW5492 Resi GetById WO', Status = 'Received');
        insert workOrder;
        Id historyId = ResiTestHistoriesService.createForReceiving(workOrder.Id, null, 'Clean');

        Test.startTest();
        List<ResiTestHistory__c> rows = ResiTestHistoriesService.getById(new Set<Id>{ historyId });
        List<ResiTestHistory__c> blank = ResiTestHistoriesService.getById(null);
        List<ResiTestHistory__c> empty = ResiTestHistoriesService.getById(new Set<Id>());
        Test.stopTest();

        Assert.areEqual(1, rows.size());
        Assert.areEqual(historyId, rows[0].Id);
        Assert.areEqual(0, blank.size());
        Assert.areEqual(0, empty.size());
    }
}