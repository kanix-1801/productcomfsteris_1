/**
 * @description GC-3618 - Weekly cleanup of Healthcare Quotes that never received a Sales Connection quote id.
 *              Runs Sunday at 1:00 AM. Deletes the Quote and its Quote Lines.
 *              
 */
public without sharing class IncompleteHcQuoteCleanupBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {
    /**
     * @description Scope size for each execute chunk.
     */
    public static final Integer DEFAULT_BATCH_SIZE = 100;
    /**
     * @description Platform flex queue capacity for batch jobs in Holding status.
     */
    public static final Integer FLEX_QUEUE_MAX_BATCH_JOBS = 100;
    /**
     * @description Cron for Sunday at 1:00 AM in the org time zone.
     */
    public static final String SCHEDULE_CRON_SUNDAY_1AM = '0 0 1 ? * SUN';
    /**
     * @description Job name for Setup → Schedule Apex.
     */
    public static final String SCHEDULE_JOB_NAME = 'Incomplete HC Quote Cleanup';
    private static final String LOGGER_TAG = 'GC-3618';

    private String originalTransactionId;
    private Integer quotesDeleted = 0;
    private Integer linesDeleted = 0;
    private Integer failureCount = 0;

    @TestVisible
    private static Boolean skipFlexQueueCheckForTest = false;
    @TestVisible
    private static Integer testFlexQueueHoldingCountOverride;
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
     * @description Schedulable entry point. Submits one batch after the flex queue check.
     * @param context Schedulable context from the platform.
     */
    public void execute(SchedulableContext context) {
        Logger.info('IncompleteHcQuoteCleanupBatch.execute (Schedulable): submitting batch').addTag(LOGGER_TAG);
        try {
            submitBatch();
        } catch (Exception exceptionValue) {
            Logger.error('IncompleteHcQuoteCleanupBatch.execute (Schedulable)', exceptionValue).addTag(LOGGER_TAG);
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Submits the batch when the flex queue has room.
     * @return AsyncApexJob Id for the submitted batch.
     */
    public static Id submitBatch() {
        assertFlexQueueHasCapacity();
        Id jobId = Database.executeBatch(new IncompleteHcQuoteCleanupBatch(), DEFAULT_BATCH_SIZE);
        Logger.info(
            'IncompleteHcQuoteCleanupBatch.submitBatch: jobId=' + jobId + ', batchSize=' + DEFAULT_BATCH_SIZE
        ).addTag(LOGGER_TAG);
        return jobId;
    }

    /**
     * @description Stops submission when the org already has 100 Holding batch jobs.
     */
    public static void assertFlexQueueHasCapacity() {
        if (Test.isRunningTest() && skipFlexQueueCheckForTest) {
            return;
        }

        Integer holdingCount = resolveFlexQueueHoldingCount();
        if (holdingCount >= FLEX_QUEUE_MAX_BATCH_JOBS) {
            throw new IncompleteHcQuoteCleanupException(
                'Cannot submit batch: flex queue is full (' +
                holdingCount + ' Holding jobs, max ' + FLEX_QUEUE_MAX_BATCH_JOBS + ')'
            );
        }
    }

    /**
     * @description Returns HC Quotes with a blank Sales Connection quote id.
     * @param context Batchable context from the platform.
     * @return Query locator for incomplete HC Quotes.
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        this.originalTransactionId = Logger.getTransactionId();
        try {
            if (Test.isRunningTest() && throwInStart) {
                throw new QueryException('Test start failure');
            }
            return IncompleteHcQuoteCleanupSelector.getIncompleteQuoteQueryLocator();
        } catch (Exception exceptionValue) {
            startCatchCount++;
            Logger.error('IncompleteHcQuoteCleanupBatch.start', exceptionValue).addTag(LOGGER_TAG);
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes the Quote Lines and Quotes in this chunk.
     * @param context Batchable context from the platform.
     * @param scope Quote rows for this chunk.
     */
    public void execute(Database.BatchableContext context, List<SObject> scope) {
        linkLogsToStartTransaction();
        try {
            if (Test.isRunningTest() && throwInExecute) {
                throw new IncompleteHcQuoteCleanupException('Test execute failure');
            }
            IncompleteHcQuoteCleanupService.CleanupTotals totals =
                IncompleteHcQuoteCleanupService.deleteIncompleteQuotes((List<Quote>) scope);
            quotesDeleted += totals.quotesDeleted;
            linesDeleted += totals.linesDeleted;
            failureCount += totals.failureCount;
        } catch (Exception exceptionValue) {
            executeCatchCount++;
            Logger.error('IncompleteHcQuoteCleanupBatch.execute', exceptionValue).addTag(LOGGER_TAG);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Logs the run totals. Rows that failed stay in Salesforce for the next Sunday run.
     * @param context Batchable context from the platform.
     */
    public void finish(Database.BatchableContext context) {
        linkLogsToStartTransaction();
        try {
            if (Test.isRunningTest() && throwInFinish) {
                throw new IncompleteHcQuoteCleanupException('Test finish failure');
            }
            Logger.info(
                'IncompleteHcQuoteCleanupBatch.finish: quotesDeleted=' + quotesDeleted +
                ', linesDeleted=' + linesDeleted +
                ', failureCount=' + failureCount
            ).addTag(LOGGER_TAG);
        } catch (Exception exceptionValue) {
            finishCatchCount++;
            Logger.error('IncompleteHcQuoteCleanupBatch.finish', exceptionValue).addTag(LOGGER_TAG);
        } finally {
            Logger.saveLog();
        }
    }

    private void linkLogsToStartTransaction() {
        Logger.setParentLogTransactionId(this.originalTransactionId);
    }

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
}