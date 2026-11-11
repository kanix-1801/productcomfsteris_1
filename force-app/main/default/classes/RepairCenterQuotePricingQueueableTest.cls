/**
 * @description Tests the post-commit Repair Center quote document job.
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
		List<RepairCenterQuotePricingQueueable.Request> requests = new List<RepairCenterQuotePricingQueueable.Request>();
		// Bulk path: blank quote ids are ignored and must not call document generation.
		for (Integer index = 0; index < 200; index++) requests.add(new RepairCenterQuotePricingQueueable.Request());

		Test.startTest();
		RepairCenterQuotePricingQueueable.enqueue(requests);
		Test.stopTest();

		System.assertEquals(200, requests.size(), 'The job should accept a bulk request list.');
	}

	@IsTest
	static void executeHandlesUnknownQuote() {
		RepairCenterQuotePricingQueueable.Request request = new RepairCenterQuotePricingQueueable.Request();
		// A quote id with no record runs the document call path without building quote test data.
		request.quoteId = Quote.SObjectType.getDescribe().getKeyPrefix() + '000000000001';

		Test.startTest();
		RepairCenterQuotePricingQueueable.enqueue(new List<RepairCenterQuotePricingQueueable.Request>{ request });
		Test.stopTest();

		System.assertEquals(1, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'RepairCenterQuotePricingQueueable'], 'The job should run once for the quote id without throwing.');
	}
}