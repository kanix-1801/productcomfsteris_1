/**
 * GC-2580 - Batch and schedulable for TemporaryAccessException__c team access processing.
 * @author Suraj Thapliyal
 * @date 2026/06/15
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-2580 - Batch and schedulable for TemporaryAccessException__c team access processing.
 * Runs daily at 1:00 AM via Schedulable (cron: 0 0 1 * * ?).
 * Grant: Approved + StartDate = today — adds Coverage Rep to Accounts/Opportunities where Requester is a team member.
 * Revoke: Active + EndDate = today — removes Temporary Coverage Rep team members in the same scope.
 * Schedule from Setup → Apex Classes → Schedule Apex (this class).
 */
public with sharing class TemporaryAccessExceptionBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    /**
     * @description Fallback batch scope size when BatchProcessConfig__mdt is missing or invalid.
     */
    public static final Integer DEFAULT_BATCH_SIZE = 100;
    /**
     * @description Platform flex queue capacity for batch jobs in Holding status (standard org limit).
     */
    public static final Integer FLEX_QUEUE_MAX_BATCH_JOBS = 100;
    /**
     * @description Cron expression for daily 1:00 AM execution.
     */
    public static final String SCHEDULE_CRON_DAILY_1AM = '0 0 1 * * ?';
    /**
     * @description Recommended schedulable job name for Setup → Schedule Apex.
     */
    public static final String SCHEDULE_JOB_NAME = 'Temporary Access Exception Team Access';
    private String originalTransactionId;
    @TestVisible
    private static Boolean skipFlexQueueCheckForTest = false;
    @TestVisible
    private static Integer testFlexQueueHoldingCountOverride;
    @TestVisible
    private static Integer testBatchSizeOverride;
    @TestVisible
    private static Boolean throwInStart = false;
    @TestVisible
    private static Boolean throwInExecute = false;
    @TestVisible
    private static Boolean throwInFinish = false;
    @TestVisible
    private static Integer startCatchCount = 0;
    @TestVisible
    private static Integer executeCatchCount = 0;
    @TestVisible
    private static Integer finishCatchCount = 0;

    /**
     * @description Default constructor for batch processing of eligible TemporaryAccessException__c rows.
     */
    public TemporaryAccessExceptionBatch() {
        // Intentionally empty — required for batch and schedulable instantiation.
    }

    /**
     * @description Schedulable entry point (Setup → Schedule Apex). Submits one batch for eligible rows.
     * @param sc Schedulable context from the platform.
     * @example
     * System.schedule(TemporaryAccessExceptionBatch.SCHEDULE_JOB_NAME,
     *     TemporaryAccessExceptionBatch.SCHEDULE_CRON_DAILY_1AM,
     *     new TemporaryAccessExceptionBatch());
     */
    public void execute(SchedulableContext sc) {
        Logger.info('TemporaryAccessExceptionBatch.execute (Schedulable): submitting batch');
        try {
            submitBatch();
        } catch (Exception e) {
            Logger.error('TemporaryAccessExceptionBatch.execute (Schedulable)', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }
    /**
     * @description GC-3179 - Modified: submits batch using scope size from BatchProcessConfig__mdt via resolveBatchSize().
     * @return AsyncApexJob Id for the submitted batch.
     * @example
     * TemporaryAccessExceptionBatch.submitBatch();
     */
    public static Id submitBatch() {
        assertFlexQueueHasCapacity();
        Integer batchSize = resolveBatchSize();
        Id jobId = Database.executeBatch(new TemporaryAccessExceptionBatch(), batchSize);
        Logger.info(
            'TemporaryAccessExceptionBatch.submitBatch: submitted jobId=' + jobId +
            ', batchSize=' + batchSize
        );
        return jobId;
    }
    /**
     * @description GC-3179 - Modified: reads active BatchProcessConfig__mdt BatchSize__c for this batch class.
     * @return Active configured batch size, or DEFAULT_BATCH_SIZE when config is absent or invalid.
     */
    public static Integer resolveBatchSize() {
        if (Test.isRunningTest() && testBatchSizeOverride != null) {
            return testBatchSizeOverride;
        }
        BatchProcessConfig__mdt config = BatchProcessConfigSelector.selectActiveByBatchClassName(
            BatchProcessConfigSelector.TAE_BATCH_CLASS_NAME
        );
        if (config != null && config.BatchSize__c != null) {
            Integer configuredSize = config.BatchSize__c.intValue();
            if (configuredSize > 0) {
                return configuredSize;
            }
            Logger.warn(
                'TemporaryAccessExceptionBatch.resolveBatchSize: invalid BatchSize__c=' +
                configuredSize + '; using fallback=' + DEFAULT_BATCH_SIZE
            );
        } else {
            Logger.warn(
                'TemporaryAccessExceptionBatch.resolveBatchSize: no active BatchProcessConfig__mdt; using fallback=' +
                DEFAULT_BATCH_SIZE
            );
        }
        return DEFAULT_BATCH_SIZE;
    }
    /**
     * @description Ensures the org flex queue can accept another batch job before executeBatch is called.
     */
    public static void assertFlexQueueHasCapacity() {
        if (Test.isRunningTest() && skipFlexQueueCheckForTest) {
            return;
        }
        Integer flexQueueHoldingCount = resolveFlexQueueHoldingCount();
        Logger.debug(
            'TemporaryAccessExceptionBatch.assertFlexQueueHasCapacity: holdingJobs=' +
            flexQueueHoldingCount + '/' + FLEX_QUEUE_MAX_BATCH_JOBS
        );
        if (flexQueueHoldingCount >= FLEX_QUEUE_MAX_BATCH_JOBS) {
            throw new TemporaryAccessExceptionException(
                'Cannot submit batch: flex queue is full (' +
                flexQueueHoldingCount + ' Holding jobs, max ' + FLEX_QUEUE_MAX_BATCH_JOBS + ')'
            );
        }
    }
    /**
     * @description Counts BatchApex jobs in Holding status, or test override when set.
     * @return Number of batch jobs currently in the flex queue.
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
     * @description Returns the TemporaryAccessException__c query locator for eligible rows.
     * @param bc Batchable context from the platform.
     * @return Query locator for grant and revoke eligible rows.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        this.originalTransactionId = Logger.getTransactionId();
        try {
            if (Test.isRunningTest() && throwInStart) {
                throw new QueryException('Test start failure');
            }
            return TemporaryAccessExceptionSelector.getProcessingQueryLocator();
        } catch (Exception e) {
            startCatchCount++;
            Logger.error('TemporaryAccessExceptionBatch.start', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }
    /**
     * @description Processes each batch chunk via TemporaryAccessExceptionService.
     * @param bc Batchable context from the platform.
     * @param scope List of TemporaryAccessException__c records in the current chunk.
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            if (Test.isRunningTest() && throwInExecute) {
                throw new TemporaryAccessExceptionException('Test execute failure');
            }
            List<TemporaryAccessException__c> taeScope = (List<TemporaryAccessException__c>) scope;
            TemporaryAccessExceptionService.process(taeScope);
        } catch (Exception e) {
            executeCatchCount++;
            Logger.error('TemporaryAccessExceptionBatch.execute', e);
        } finally {
            Logger.saveLog();
        }
    }
    /**
     * @description Completes the batch run and restores the parent log transaction Id.
     * @param bc Batchable context from the platform.
     */
    public void finish(Database.BatchableContext bc) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            if (Test.isRunningTest() && throwInFinish) {
                throw new DmlException('Test finish failure');
            }
        } catch (Exception e) {
            finishCatchCount++;
            Logger.error('TemporaryAccessExceptionBatch.finish', e);
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