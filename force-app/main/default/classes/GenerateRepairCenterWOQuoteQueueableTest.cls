/**
 * @description Tests for async Repair Center WO Quote SubFlow enqueue/execute.
 */
@IsTest
private class GenerateRepairCenterWOQuoteQueueableTest {
    @IsTest
    static void testEnqueue_withWorkOrderId_enqueuesJob() {
        Id fakeWorkOrderId = WorkOrder.SObjectType.getDescribe().getKeyPrefix() + '000000000001';

        GenerateRepairCenterWOQuoteQueueable.Request request =
            new GenerateRepairCenterWOQuoteQueueable.Request();
        request.workOrderId = fakeWorkOrderId;

        Test.startTest();
        GenerateRepairCenterWOQuoteQueueable.enqueue(
            new List<GenerateRepairCenterWOQuoteQueueable.Request>{ request }
        );
        Integer enqueuedJobs = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.areEqual(1, enqueuedJobs, 'Valid Work Order Id should enqueue one job');
    }

    @IsTest
    static void testEnqueue_nullOrEmpty_doesNotEnqueue() {
        Test.startTest();
        GenerateRepairCenterWOQuoteQueueable.enqueue(null);
        GenerateRepairCenterWOQuoteQueueable.enqueue(
            new List<GenerateRepairCenterWOQuoteQueueable.Request>()
        );
        GenerateRepairCenterWOQuoteQueueable.Request blank =
            new GenerateRepairCenterWOQuoteQueueable.Request();
        GenerateRepairCenterWOQuoteQueueable.enqueue(
            new List<GenerateRepairCenterWOQuoteQueueable.Request>{ blank }
        );
        Integer enqueuedJobs = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.areEqual(0, enqueuedJobs, 'Blank requests should not enqueue');
    }

    @IsTest
    static void testExecute_emptySet_doesNotThrow() {
        Test.startTest();
        new GenerateRepairCenterWOQuoteQueueable(new Set<Id>()).execute(null);
        Assert.areEqual(0, Limits.getQueueableJobs(), 'Empty execute should not enqueue another job');
        Test.stopTest();

        Assert.areEqual(
            0,
            GenerateRepairCenterWOQuoteQueueable.subFlowStartCount,
            'Empty execute should not start the subflow'
        );
    }

    @IsTest
    static void testExecute_unknownId_doesNotStartSubFlow() {
        Id fakeWorkOrderId = WorkOrder.SObjectType.getDescribe().getKeyPrefix() + '000000000001';

        Test.startTest();
        new GenerateRepairCenterWOQuoteQueueable(new Set<Id>{ fakeWorkOrderId }).execute(null);
        Assert.areEqual(0, Limits.getQueueableJobs(), 'Missing Work Order should not enqueue another job');
        Test.stopTest();

        Assert.areEqual(
            0,
            GenerateRepairCenterWOQuoteQueueable.subFlowStartCount,
            'Missing Work Order should not start the subflow'
        );
    }

    @IsTest
    static void testStartSubFlow_nullAndBypass_doNotThrow() {
        GenerateRepairCenterWOQuoteQueueable.bypassSubFlow = true;

        Test.startTest();
        GenerateRepairCenterWOQuoteQueueable.startSubFlow(null);
        GenerateRepairCenterWOQuoteQueueable.startSubFlow(new WorkOrder());
        GenerateRepairCenterWOQuoteQueueable.startSubFlow(
            new WorkOrder(Id = WorkOrder.SObjectType.getDescribe().getKeyPrefix() + '000000000001')
        );
        Assert.areEqual(0, Limits.getQueueableJobs(), 'Bypass should not enqueue another job');
        Test.stopTest();

        Assert.areEqual(
            0,
            GenerateRepairCenterWOQuoteQueueable.subFlowStartCount,
            'Bypass should not start the subflow'
        );
    }
}