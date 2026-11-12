/**
 * @description Tests that the Oracle submit queueable calls ProductRequestsService after commit.
 */
@IsTest
private class ProductRequestOracleSubmitQueueableTest {
    @IsTest
    static void shouldStampFail_WhenQueuedRequestHasNoLines() {
        ProductRequest pr = new ProductRequest(Status = 'Draft');
        insert pr;

        ProductRequestOracleSubmitQueueable.Request req = new ProductRequestOracleSubmitQueueable.Request();
        req.productRequestId = pr.Id;

        ProductRequestsService.OracleSubmitRequest submitReq = new ProductRequestsService.OracleSubmitRequest();
        submitReq.productRequestId = pr.Id;
        submitReq.performCallout = true;

        Test.startTest();
        List<ProductRequestsService.OracleSubmitResult> results = ProductRequestsService.submitOracleSalesOrder(
            new List<ProductRequestsService.OracleSubmitRequest>{ submitReq }
        );
        Assert.areEqual('Fail Create', results[0].integrationStatus, results[0].integrationMessage);
        ProductRequestOracleSubmitQueueable.enqueue(
            new List<ProductRequestOracleSubmitQueueable.Request>{ req }
        );
        Assert.areEqual(1, Limits.getQueueableJobs());
        Test.stopTest();
    }

    @IsTest
    static void shouldDoNothing_WhenRequestListIsEmpty() {
        Test.startTest();
        ProductRequestOracleSubmitQueueable.enqueue(null);
        ProductRequestOracleSubmitQueueable.enqueue(
            new List<ProductRequestOracleSubmitQueueable.Request>()
        );
        Test.stopTest();

        Assert.areEqual(0, Limits.getQueueableJobs());
    }
}