/**
 * @description Tests for VendorFedExShipmentQueueable.
 * @author Uptima Development Team
 * @date 2026-08-13
 */
@IsTest
private class VendorFedExShipmentQueueableTest {
    @IsTest
    static void testExecute_emptyMap_doesNotThrow() {
        // Setup
        VendorFedExShipmentQueueable queueableJob = new VendorFedExShipmentQueueable(
            new Map<Id, List<Id>>()
        );

        // When
        Test.startTest();
        Id jobId = System.enqueueJob(queueableJob);
        Test.stopTest();

        // Then
        Assert.isNotNull(jobId, 'Queueable should enqueue with an empty Return Order map');
    }

    @IsTest
    static void testExecute_missingReturnOrder_throws() {
        // Setup
        VendorFedExShipmentQueueable queueableJob = new VendorFedExShipmentQueueable(
            new Map<Id, List<Id>>{ UserInfo.getUserId() => new List<Id>() }
        );

        Boolean threw = false;
        try {
            // When
            Test.startTest();
            queueableJob.execute(null);
            Test.stopTest();
        } catch (VendorFedExShipmentException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('was not found'),
                e.getMessage()
            );
        }

        // Then
        Assert.isTrue(threw, 'Queueable should surface VendorFedExShipmentException');
    }

    @IsTest
    static void testExecute_retryableFailure_enqueuesDelayedRetry() {
        // Setup
        VendorFedExShipmentQueueable.testForcedFailureTimes = 1;
        VendorFedExShipmentQueueable queueableJob = new VendorFedExShipmentQueueable(
            new Map<Id, List<Id>>()
        );

        // When
        Test.startTest();
        queueableJob.execute(null);
        Test.stopTest();

        // Then
        Assert.areEqual(
            0,
            VendorFedExShipmentQueueable.testForcedFailureTimes,
            'Forced failure should be consumed and retried without throwing'
        );
    }

    @IsTest
    static void testExecute_retryableFailureAfterMaxDelay_throws() {
        // Setup
        VendorFedExShipmentQueueable.testForcedFailureTimes = 1;
        VendorFedExShipmentQueueable queueableJob = new VendorFedExShipmentQueueable(
            new Map<Id, List<Id>>(),
            2
        );

        Boolean threw = false;
        try {
            // When
            Test.startTest();
            queueableJob.execute(null);
            Test.stopTest();
        } catch (VendorFedExShipmentException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('did not return a tracking number'),
                e.getMessage()
            );
        }

        // Then
        Assert.isTrue(threw, 'Final delayed retry should surface the FedEx exception');
    }

    @IsTest
    static void testIsRetryable_trackingAndCalloutFailures() {
        // Setup / When / Then
        Assert.isTrue(
            VendorFedExShipmentQueueable.isRetryable(
                new VendorFedExShipmentException(
                    'FedEx shipment call did not return a tracking number.'
                )
            )
        );
        Assert.isTrue(
            VendorFedExShipmentQueueable.isRetryable(
                new VendorFedExShipmentException('FedEx shipment call failed: HTTP 500')
            )
        );
        Assert.isFalse(
            VendorFedExShipmentQueueable.isRetryable(
                new VendorFedExShipmentException(
                    'Vendor Return Order was not found for FedEx shipment.'
                )
            )
        );
        Assert.isFalse(VendorFedExShipmentQueueable.isRetryable(null));
    }
}