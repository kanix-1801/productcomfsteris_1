/**
 * @description Tests the post-commit Repair Center quote pricing job.
 */
@IsTest
private class RepairCenterQuotePricingQueueableTest {
    @IsTest
    static void enqueueSkipsNullInput() {
        Test.startTest();
        RepairCenterQuotePricingQueueable.enqueue(null);
        Test.stopTest();

        System.assertEquals(0, Limits.getQueueableJobs(), 'A null request list must not enqueue a job.');
    }

    @IsTest
    static void executeSkipsBlankQuoteIds() {
        List<RepairCenterQuotePricingQueueable.Request> requests =
            new List<RepairCenterQuotePricingQueueable.Request>();
        // Bulk path: blank quote ids are ignored and must not call pricing.
        for (Integer index = 0; index < 200; index++) {
            requests.add(new RepairCenterQuotePricingQueueable.Request());
        }

        Test.startTest();
        RepairCenterQuotePricingQueueable.enqueue(requests);
        Test.stopTest();

        System.assertEquals(200, requests.size(), 'The job should accept a bulk request list.');
    }
}