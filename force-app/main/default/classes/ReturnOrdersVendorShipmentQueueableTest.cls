/**
 * @description Tests for ReturnOrdersVendorShipmentQueueable.
 * @author Uptima Development Team
 * @date 2026-09-03
 */
@IsTest
private class ReturnOrdersVendorShipmentQueueableTest {
    @IsTest
    static void testExecute_emptyMap_doesNotThrow() {
        ReturnOrdersVendorShipmentQueueable queueableJob = new ReturnOrdersVendorShipmentQueueable(
            new Map<Id, List<Id>>()
        );

        Test.startTest();
        Id jobId = System.enqueueJob(queueableJob);
        Test.stopTest();

        Assert.isNotNull(jobId, 'Queueable should enqueue with an empty Return Order map');
    }

    @IsTest
    static void testExecute_missingReturnOrder_throws() {
        ReturnOrdersVendorShipmentQueueable queueableJob = new ReturnOrdersVendorShipmentQueueable(
            new Map<Id, List<Id>>{ UserInfo.getUserId() => new List<Id>() }
        );

        Boolean threw = false;
        try {
            Test.startTest();
            queueableJob.execute(null);
            Test.stopTest();
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('was not found'),
                e.getMessage()
            );
        }

        Assert.isTrue(threw, 'Queueable should surface ReturnOrdersServiceException');
    }
}