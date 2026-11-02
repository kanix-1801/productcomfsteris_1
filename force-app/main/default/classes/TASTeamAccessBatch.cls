/**
 * @author Suraj Thapliyal
 * @date 2026/05/24
 *
 * @group Order Line Contact
 *
 * @description
 * Batch and schedulable for OrderLineContact__c team access processing.
 * GC-3278 - TAS class rename (formerly OrderLineContactTeamAccessBatch).
 * GC-3179 - Batch scope size resolved from BatchProcessConfig__mdt via BatchProcessConfigSelector.
 * Schedule from Setup → Apex Classes → Schedule Apex (this class).
 * Schedulable execute submits one batch for all pending Insert/Delete delta rows.
 * Runs in system mode (without sharing); CRUD/FLS is not applied to batch SOQL/DML.
 */
public without sharing class TASTeamAccessBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    /**
     * @description
     * Fallback batch scope size when BatchProcessConfig__mdt is missing or invalid.
     */
    public static final Integer DEFAULT_BATCH_SIZE = 200;

    /**
     * @description
     * Platform flex queue capacity for batch jobs in Holding status (standard org limit).
     */
    public static final Integer FLEX_QUEUE_MAX_BATCH_JOBS = 100;

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
     * @description
     * Default constructor for batch processing of pending OrderLineContact__c rows.
     *
     * @return void
     */
    public TASTeamAccessBatch() {
    }

    /**
     * @description
     * Schedulable entry point (Setup → Schedule Apex). Submits one batch for pending rows.
     *
     * @param sc Schedulable context from the platform
     * @return void
     * @example
     * Setup → Apex Classes → TASTeamAccessBatch → Schedule Apex.
     */
    public void execute(SchedulableContext sc) {
        Logger.info('TASTeamAccessBatch.execute (Schedulable): submitting batch');
        try {
            submitBatch();
        } catch (Exception e) {
            Logger.error('TASTeamAccessBatch.execute (Schedulable)', e);
            throw e;
        }
    }

    /**
     * @description
     * GC-3179 - Modified: submits batch using scope size from BatchProcessConfig__mdt via resolveBatchSize().
     *
     * @return AsyncApexJob Id for the submitted batch
     * @example
     * TASTeamAccessBatch.submitBatch();
     */
    public static Id submitBatch() {
        assertFlexQueueHasCapacity();
        Integer batchSize = resolveBatchSize();
        Id jobId = Database.executeBatch(new TASTeamAccessBatch(), batchSize);
        Logger.info(
            'TASTeamAccessBatch.submitBatch: submitted jobId=' + jobId +
            ', batchSize=' + batchSize
        );
        return jobId;
    }

    /**
     * @description
     * GC-3179 - Modified: reads active BatchProcessConfig__mdt BatchSize__c via BatchProcessConfigSelector.
     *
     * @return Active configured batch size, or DEFAULT_BATCH_SIZE when config is absent or invalid
     */
    public static Integer resolveBatchSize() {
        Integer batchSize = DEFAULT_BATCH_SIZE;
        if (Test.isRunningTest() && testBatchSizeOverride != null) {
            batchSize = testBatchSizeOverride;
        } else {
            BatchProcessConfig__mdt config = BatchProcessConfigSelector.selectActiveByBatchClassName(
                BatchProcessConfigSelector.OLC_TEAM_ACCESS_BATCH_CLASS_NAME
            );
            if (config != null && config.BatchSize__c != null) {
                Integer configuredSize = config.BatchSize__c.intValue();
                if (configuredSize > 0) {
                    batchSize = configuredSize;
                } else {
                    Logger.warn(
                        'TASTeamAccessBatch.resolveBatchSize: invalid BatchSize__c=' +
                        configuredSize + '; using fallback=' + DEFAULT_BATCH_SIZE
                    );
                }
            } else {
                Logger.warn(
                    'TASTeamAccessBatch.resolveBatchSize: no active BatchProcessConfig__mdt; using fallback=' +
                    DEFAULT_BATCH_SIZE
                );
            }
        }
        return batchSize;
    }

    /**
     * @description
     * Ensures the org flex queue can accept another batch job before executeBatch is called.
     *
     * @return void
     */
    public static void assertFlexQueueHasCapacity() {
        if (!(Test.isRunningTest() && isSkipFlexQueueCheckForTest)) {
            Integer flexQueueHoldingCount = resolveFlexQueueHoldingCount();
            Logger.debug(
                'TASTeamAccessBatch.assertFlexQueueHasCapacity: holdingJobs=' +
                flexQueueHoldingCount + '/' + FLEX_QUEUE_MAX_BATCH_JOBS
            );
            if (flexQueueHoldingCount >= FLEX_QUEUE_MAX_BATCH_JOBS) {
                throw new TASTeamAccessException(
                    'Cannot submit batch: flex queue is full (' +
                    flexQueueHoldingCount + ' Holding jobs, max ' + FLEX_QUEUE_MAX_BATCH_JOBS + ')'
                );
            }
        }
    }

    /**
     * @description
     * Counts BatchApex jobs in Holding status, or test override when set.
     *
     * @return Number of batch jobs currently in the flex queue
     */
    private static Integer resolveFlexQueueHoldingCount() {
        Integer flexQueueHoldingCount;
        if (Test.isRunningTest() && testFlexQueueHoldingCountOverride != null) {
            flexQueueHoldingCount = testFlexQueueHoldingCountOverride;
        } else {
            flexQueueHoldingCount = [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE JobType = 'BatchApex'
                  AND Status = 'Holding'
            ];
        }
        return flexQueueHoldingCount;
    }

    /**
     * @description
     * Returns the OrderLineContact__c query locator for pending delta rows.
     *
     * @param bc Batchable context from the platform
     * @return Query locator for rows with Insert or Delete delta scenario
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        this.originalTransactionId = Logger.getTransactionId();
        try {
            if (Test.isRunningTest() && isThrowInStart) {
                throw new QueryException('Test start failure');
            }
            // GC-2596 - Abort batch when TAS_FreezeWindow is malformed; error is logged below with saveLog().
            TASFreezeWindowUtil.validateFreezeWindowLabel();
            return TASTeamAccessSelector.getOrderLineContactsQueryLocator();
        } catch (Exception e) {
            startCatchCount++;
            Logger.error('TASTeamAccessBatch.start', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * Processes each batch chunk via TASTeamAccessService.
     *
     * @param bc Batchable context from the platform
     * @param scope List of OrderLineContact__c records in the current chunk
     * @return void
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            if (Test.isRunningTest() && isThrowInExecute) {
                throw new TASTeamAccessException('Test execute failure');
            }

            List<OrderLineContact__c> olcScope = (List<OrderLineContact__c>) scope;
            TASTeamAccessService.process(olcScope);
        } catch (Exception e) {
            executeCatchCount++;
            Logger.error('TASTeamAccessBatch.execute', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * Completes the batch run and restores the parent log transaction Id.
     *
     * @param bc Batchable context from the platform
     * @return void
     */
    public void finish(Database.BatchableContext bc) {
        Logger.setParentLogTransactionId(this.originalTransactionId);
        try {
            if (Test.isRunningTest() && isThrowInFinish) {
                throw new DmlException('Test finish failure');
            }
        } catch (Exception e) {
            finishCatchCount++;
            Logger.error('TASTeamAccessBatch.finish', e);
        } finally {
            Logger.saveLog();
        }
    }
}