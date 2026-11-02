/**
 * @description Queueable entry point for Vendor FedEx label creation after Vendor Return
 *              Orders are inserted. Callouts are allowed because this is a new transaction.
 *              Transient Boomi misses are retried in-job, then with a delayed re-queue.
 * @author Uptima Development Team
 * @date 2026-08-13
 * @group Queueable
 */
public with sharing class VendorFedExShipmentQueueable implements Queueable, Database.AllowsCallouts {
    private static final Integer MAX_DELAYED_RETRIES = 2;
    private static final Integer DELAYED_RETRY_MINUTES = 1;

    private Map<Id, List<Id>> returnOrderIdToWorkOrderIdsMap;
    private Integer delayedRetryCount;

    /** Test hook: throw this many times from execute before calling the service. */
    @TestVisible
    private static Integer testForcedFailureTimes = 0;

    /** Test hook: exception message used with testForcedFailureTimes. */
    @TestVisible
    private static String testForcedFailureMessage =
        'FedEx shipment call did not return a tracking number. An unexpected error has occurred.';

    /**
     * @description Stores Vendor Return Order Id to grouped Work Order Ids for the async job.
     * @param returnOrderIdToWorkOrderIdsMap Vendor Return Order Id to Work Order Ids
     */
    public VendorFedExShipmentQueueable(Map<Id, List<Id>> returnOrderIdToWorkOrderIdsMap) {
        this(returnOrderIdToWorkOrderIdsMap, 0);
    }

    /**
     * @description Stores Vendor Return Order Id to grouped Work Order Ids and the current
     *              delayed-retry attempt.
     * @param returnOrderIdToWorkOrderIdsMap Vendor Return Order Id to Work Order Ids
     * @param delayedRetryCount Delayed re-queue attempts already used
     */
    public VendorFedExShipmentQueueable(
        Map<Id, List<Id>> returnOrderIdToWorkOrderIdsMap,
        Integer delayedRetryCount
    ) {
        this.returnOrderIdToWorkOrderIdsMap = returnOrderIdToWorkOrderIdsMap == null
            ? new Map<Id, List<Id>>()
            : returnOrderIdToWorkOrderIdsMap;
        this.delayedRetryCount = delayedRetryCount == null || delayedRetryCount < 0
            ? 0
            : delayedRetryCount;
    }

    /**
     * @description Runs FedEx shipment creation and logs failures with Nebula Logger.
     *              Retryable Boomi failures are re-queued after a delay instead of failing
     *              the Complete flow on the first empty tracking response.
     * @param context Queueable context
     */
    public void execute(QueueableContext context) {
        try {
            Logger.info(
                new LogMessage(
                    'VendorFedExShipmentQueueable started for {0} Return Order(s), delayed retry {1}',
                    returnOrderIdToWorkOrderIdsMap.size(),
                    delayedRetryCount
                )
            );
            if (testForcedFailureTimes > 0) {
                testForcedFailureTimes--;
                throw new VendorFedExShipmentException(testForcedFailureMessage);
            }
            VendorFedExShipmentService.createShipments(returnOrderIdToWorkOrderIdsMap);
        } catch (Exception e) {
            if (shouldRetryLater(e)) {
                Logger.warn(
                    new LogMessage(
                        'VendorFedExShipmentQueueable scheduling delayed retry {0} of {1}: {2}',
                        delayedRetryCount + 1,
                        MAX_DELAYED_RETRIES,
                        e.getMessage()
                    )
                );
                enqueueDelayedRetry();
                return;
            }
            Logger.error(
                new LogMessage(
                    'VendorFedExShipmentQueueable failed: {0}',
                    e.getMessage()
                ),
                e
            );
            if (e instanceof VendorFedExShipmentException) {
                throw e;
            }
            throw new VendorFedExShipmentException(
                'FedEx shipment queueable failed: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    @TestVisible
    static Boolean isRetryable(Exception e) {
        if (e == null || String.isBlank(e.getMessage())) {
            return false;
        }
        String message = e.getMessage();
        return message.contains('did not return a tracking number') ||
            message.contains('FedEx shipment call failed') ||
            message.contains('returned no SERVICE_DATA');
    }

    private Boolean shouldRetryLater(Exception e) {
        return isRetryable(e) && delayedRetryCount < MAX_DELAYED_RETRIES;
    }

    private void enqueueDelayedRetry() {
        VendorFedExShipmentQueueable retryJob = new VendorFedExShipmentQueueable(
            returnOrderIdToWorkOrderIdsMap,
            delayedRetryCount + 1
        );
        if (Test.isRunningTest()) {
            System.enqueueJob(retryJob);
        } else {
            System.enqueueJob(retryJob, DELAYED_RETRY_MINUTES);
        }
    }
}