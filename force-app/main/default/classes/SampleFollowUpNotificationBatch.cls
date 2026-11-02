/**
 * @author Suraj Thapliyal
 * @date 2026/08/17
 *
 * @group Sample
 *
 * @description
 * GC-3226 - Daily batch/schedulable that sends Sample Follow-up Custom Notification (bell)
 *           and email on Follow-up Date. Batch size from BatchProcessConfig__mdt.
 *           Schedule from Setup → Apex Classes → Schedule Apex
 *           (cron example: 0 0 9 * * ? for 9:00 AM daily).
 */
public with sharing class SampleFollowUpNotificationBatch
    implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    /**
     * @description Fallback batch scope size when BatchProcessConfig__mdt is missing or invalid.
     */
    public static final Integer DEFAULT_BATCH_SIZE = 200;

    /**
     * @description Platform flex queue capacity for batch jobs in Holding status.
     */
    public static final Integer FLEX_QUEUE_MAX_BATCH_JOBS = 100;

    /**
     * @description Cron expression for daily 9:00 AM execution.
     */
    public static final String SCHEDULE_CRON_DAILY_9AM = '0 0 9 * * ?';

    /**
     * @description Recommended schedulable job name for Setup → Schedule Apex.
     */
    public static final String SCHEDULE_JOB_NAME = 'Sample Follow-up Notifications';

    private String originalTransactionId;

    @TestVisible
    private static Boolean isSkipFlexQueueCheckForTest = false;
    @TestVisible
    private static Integer testFlexQueueHoldingCountOverride;
    @TestVisible
    private static Integer testBatchSizeOverride;
    @TestVisible
    private static Boolean isThrowInStart = false;
    @TestVisible
    private static Boolean isThrowInExecute = false;
    @TestVisible
    private static Boolean isThrowInFinish = false;
    @TestVisible
    private static Integer startCatchCount = 0;
    @TestVisible
    private static Integer executeCatchCount = 0;
    @TestVisible
    private static Integer finishCatchCount = 0;

    /**
     * @description Default constructor for Sample Follow-up notification batch.
     */
    public SampleFollowUpNotificationBatch() {
    }

    /**
     * @description Schedulable entry — submits the Follow-up notification batch.
     * @param sc Schedulable context
     * @example
     * System.schedule(SampleFollowUpNotificationBatch.SCHEDULE_JOB_NAME,
     *     SampleFollowUpNotificationBatch.SCHEDULE_CRON_DAILY_9AM,
     *     new SampleFollowUpNotificationBatch());
     */
    public void execute(SchedulableContext sc) {
        Logger.info('SampleFollowUpNotificationBatch.execute (Schedulable): submitting batch');
        try {
            submitBatch();
        } catch (Exception e) {
            Logger.error('SampleFollowUpNotificationBatch.execute (Schedulable)', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Submits batch using scope size from BatchProcessConfig__mdt via resolveBatchSize().
     * @return AsyncApexJob Id for the submitted batch
     */
    public static Id submitBatch() {
        assertFlexQueueHasCapacity();
        Integer batchSize = resolveBatchSize();
        Id jobId = Database.executeBatch(new SampleFollowUpNotificationBatch(), batchSize);
        Logger.info(
            'SampleFollowUpNotificationBatch.submitBatch: submitted jobId=' + jobId +
            ', batchSize=' + batchSize
        );
        return jobId;
    }

    /**
     * @description Reads active BatchProcessConfig__mdt BatchSize__c for this batch class.
     * @return Active configured batch size, or DEFAULT_BATCH_SIZE when config is absent or invalid
     */
    public static Integer resolveBatchSize() {
        if (Test.isRunningTest() && testBatchSizeOverride != null) {
            return testBatchSizeOverride;
        }

        BatchProcessConfig__mdt config = BatchProcessConfigSelector.selectActiveByBatchClassName(
            BatchProcessConfigSelector.SAMPLE_FOLLOW_UP_BATCH_CLASS_NAME
        );
        if (config != null && config.BatchSize__c != null) {
            Integer configuredSize = config.BatchSize__c.intValue();
            if (configuredSize > 0) {
                return configuredSize;
            }
            Logger.warn(
                'SampleFollowUpNotificationBatch.resolveBatchSize: invalid BatchSize__c=' +
                configuredSize + '; using fallback=' + DEFAULT_BATCH_SIZE
            );
        } else {
            Logger.warn(
                'SampleFollowUpNotificationBatch.resolveBatchSize: no active BatchProcessConfig__mdt; using fallback=' +
                DEFAULT_BATCH_SIZE
            );
        }
        return DEFAULT_BATCH_SIZE;
    }

    /**
     * @description Ensures the org flex queue can accept another batch job before executeBatch.
     */
    public static void assertFlexQueueHasCapacity() {
        if (!(Test.isRunningTest() && isSkipFlexQueueCheckForTest)) {
            Integer flexQueueHoldingCount = resolveFlexQueueHoldingCount();
            Logger.debug(
                'SampleFollowUpNotificationBatch.assertFlexQueueHasCapacity: holdingJobs=' +
                flexQueueHoldingCount + '/' + FLEX_QUEUE_MAX_BATCH_JOBS
            );
            if (flexQueueHoldingCount >= FLEX_QUEUE_MAX_BATCH_JOBS) {
                throw new SampleException(
                    'Cannot submit batch: flex queue is full (' +
                    flexQueueHoldingCount + ' Holding jobs, max ' + FLEX_QUEUE_MAX_BATCH_JOBS + ')'
                );
            }
        }
    }

    /**
     * @description Counts BatchApex jobs in Holding status, or test override when set.
     * @return Number of batch jobs currently in the flex queue
     */
    private static Integer resolveFlexQueueHoldingCount() {
        if (Test.isRunningTest() && testFlexQueueHoldingCountOverride != null) {
            return testFlexQueueHoldingCountOverride;
        }
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
              AND Status = 'Holding'
        ];
    }

    /**
     * @description Query Samples due for Follow-up notification today.
     * @param bc Batchable context
     * @return QueryLocator of due Samples
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        this.originalTransactionId = Logger.getTransactionId();
        try {
            if (Test.isRunningTest() && isThrowInStart) {
                throw new QueryException('Test start failure');
            }
            return SampleSelector.selectDueForFollowUpNotification(Date.today());
        } catch (Exception e) {
            startCatchCount++;
            Logger.error('SampleFollowUpNotificationBatch.start', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Sends bell + email for the current scope.
     * @param bc Batchable context
     * @param scope Sample rows
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            if (Test.isRunningTest() && isThrowInExecute) {
                throw new SampleException('Test execute failure');
            }
            SampleService.sendFollowUpNotifications((List<Sample__c>) scope);
        } catch (Exception e) {
            executeCatchCount++;
            Logger.error('SampleFollowUpNotificationBatch.execute', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Completes the batch run and restores the parent log transaction Id.
     * @param bc Batchable context
     */
    public void finish(Database.BatchableContext bc) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            if (Test.isRunningTest() && isThrowInFinish) {
                throw new DmlException('Test finish failure');
            }
            Logger.info('SampleFollowUpNotificationBatch.finish: completed');
        } catch (Exception e) {
            finishCatchCount++;
            Logger.error('SampleFollowUpNotificationBatch.finish', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Relates execute/finish log entries to the start transaction (Nebula Logger batch pattern).
     */
    private void linkExecuteAndFinishLogsToStartTransaction() {
        Logger.setParentLogTransactionId(this.originalTransactionId);
    }
}