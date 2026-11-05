/**
 * GCL-95 / GCL-103 - Batch and schedulable for Life Science TemporaryAccessException__c processing.
 * @description
 * Replaces TemporaryAccessExceptionBatch for Life Science rows only. TemporaryAccessExceptionBatch
 * is being retired in favor of TAEWorkItemOrchestratorBatch (GC-3420/GC-3482), a generic pipeline
 * that is not Life Science aware: it has no CreatedBy.Profile.Name check, its own grant/revoke
 * notice (TAEWorkItemEmailService) always uses the Healthcare "Temporary Coverage Access
 * Granted/Revoked" subject and body for every request, and its generic owner handback
 * (TAEWorkItemService.processOwnerReassign / REASSIGN_OPPORTUNITY/TASK/EVENT/CONTACT) only
 * targets open Opportunities, incomplete Tasks, and future Events - it does not reassign completed
 * Tasks or past Events the way GCL-103 (LSTemporaryAccessReassignmentService) requires.
 *
 * This class keeps Life Science on its existing, already-approved GCL-95/GCL-103 behavior,
 * independent of whatever batch Healthcare schedules next:
 *   - Query locator is scoped to CreatedBy.Profile.Name = Life Sciences Sales only, so this batch
 *     never touches a Healthcare row and can run safely alongside TAEWorkItemOrchestratorBatch.
 *   - execute() calls the existing, unmodified TemporaryAccessExceptionService.process(scope).
 *     Every row passed in is already Life Science, so inside that service:
 *       - sendEmails() always finds healthcareIds empty, so TemporaryAccessExceptionEmailService
 *         (the Healthcare email class) is never invoked from this batch.
 *       - reassignLifeScienceOwnership() / LSTemporaryAccessReassignmentService.reassignOnExpiry()
 *         always runs for this batch's rows (GCL-103).
 *       - applyStatusUpdates() still suppresses LSTemporaryAccessExceptionEmailService's invocable
 *         send during the Status__c DML, and sendLifeScienceBatchEmail() still sends the one
 *         GCL-95 batch email (Granted / Expired) afterward.
 *   - Grant (Approved + StartDate = today): adds Coverage Rep as a temporary Sales team member on
 *     Accounts/Opportunities where the Requester is a team member or owner.
 *   - Revoke (Active + EndDate = today): removes those temporary team members, reassigns
 *     Opportunity/Task/Event/Contact ownership back to the Requester (GCL-103), then sets Status.
 *
 * IMPORTANT - required coordination, not done by this class:
 * TAEWorkItemSelector.eligibleTaeLocator() (owned by the Healthcare/TAEWorkItem team) has no Life
 * Science exclusion. Until that query adds "AND CreatedBy.Profile.Name != 'Life Sciences Sales'"
 * (or equivalent), TAEWorkItemOrchestratorBatch can still pick up the same Life Science row this
 * batch processes, which would double-run team grant/revoke and send the Healthcare-branded notice
 * in addition to the Life Science one. Request that exclusion from the TAEWorkItem pipeline owner
 * before both batches run in the same org on the same schedule.
 *
 * Schedule from Setup -> Apex Classes -> Schedule Apex (this class), or call scheduleDaily().
 */
public with sharing class LSTemporaryAccessExceptionBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    /**
     * @description BatchProcessConfig__mdt.BatchClassName__c lookup key for this batch.
     * Deliberately a local literal (not a shared constant) so this class never breaks if another
     * team renames or removes a constant it does not own.
     */
    public static final String BATCH_CLASS_NAME = 'LSTemporaryAccessExceptionBatch';
    /**
     * @description Fallback batch scope size when BatchProcessConfig__mdt is missing or invalid.
     * Life Science volume is low, so a conservative default is sufficient without a config row.
     */
    public static final Integer DEFAULT_BATCH_SIZE = 50;
    /**
     * @description Platform flex queue capacity for batch jobs in Holding status (standard org limit).
     */
    public static final Integer FLEX_QUEUE_MAX_BATCH_JOBS = 100;
    /**
     * @description Cron expression for daily 1:00 AM execution, same window as the legacy batch.
     */
    public static final String SCHEDULE_CRON_DAILY_1AM = '0 0 1 * * ?';
    /**
     * @description Recommended schedulable job name for Setup -> Schedule Apex.
     */
    public static final String SCHEDULE_JOB_NAME = 'Life Science Temporary Access Exception Batch';

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
     * @description Default constructor for batch and schedulable instantiation.
     */
    public LSTemporaryAccessExceptionBatch() {
        // Intentionally empty - required for batch and schedulable instantiation.
    }

    /**
     * @description Schedulable entry point (Setup -> Schedule Apex). Submits one batch for eligible Life Science rows.
     * @param sc Schedulable context from the platform.
     * @example
     * System.schedule(LSTemporaryAccessExceptionBatch.SCHEDULE_JOB_NAME,
     *     LSTemporaryAccessExceptionBatch.SCHEDULE_CRON_DAILY_1AM,
     *     new LSTemporaryAccessExceptionBatch());
     */
    public void execute(SchedulableContext sc) {
        Logger.info('LSTemporaryAccessExceptionBatch.execute (Schedulable): submitting batch');
        try {
            submitBatch();
        } catch (Exception e) {
            Logger.error('LSTemporaryAccessExceptionBatch.execute (Schedulable)', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Convenience helper to register the daily 1:00 AM schedule.
     * @return CronTrigger Id for the scheduled job.
     */
    public static Id scheduleDaily() {
        return System.schedule(SCHEDULE_JOB_NAME, SCHEDULE_CRON_DAILY_1AM, new LSTemporaryAccessExceptionBatch());
    }

    /**
     * @description Submits the batch using scope size from BatchProcessConfig__mdt via resolveBatchSize().
     * @return AsyncApexJob Id for the submitted batch.
     * @example
     * LSTemporaryAccessExceptionBatch.submitBatch();
     */
    public static Id submitBatch() {
        assertFlexQueueHasCapacity();
        Integer batchSize = resolveBatchSize();
        Id jobId = Database.executeBatch(new LSTemporaryAccessExceptionBatch(), batchSize);
        Logger.info(
            'LSTemporaryAccessExceptionBatch.submitBatch: submitted jobId=' + jobId +
            ', batchSize=' + batchSize
        );
        return jobId;
    }

    /**
     * @description Reads active BatchProcessConfig__mdt BatchSize__c for this batch class.
     * @return Active configured batch size, or DEFAULT_BATCH_SIZE when config is absent or invalid.
     */
    public static Integer resolveBatchSize() {
        if (Test.isRunningTest() && testBatchSizeOverride != null) {
            return testBatchSizeOverride;
        }
        BatchProcessConfig__mdt config = BatchProcessConfigSelector.selectActiveByBatchClassName(
            BATCH_CLASS_NAME
        );
        if (config != null && config.BatchSize__c != null) {
            Integer configuredSize = config.BatchSize__c.intValue();
            if (configuredSize > 0) {
                return configuredSize;
            }
            Logger.warn(
                'LSTemporaryAccessExceptionBatch.resolveBatchSize: invalid BatchSize__c=' +
                configuredSize + '; using fallback=' + DEFAULT_BATCH_SIZE
            );
        } else {
            Logger.warn(
                'LSTemporaryAccessExceptionBatch.resolveBatchSize: no active BatchProcessConfig__mdt; using fallback=' +
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
            'LSTemporaryAccessExceptionBatch.assertFlexQueueHasCapacity: holdingJobs=' +
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
     * @description Returns the TemporaryAccessException__c query locator for eligible Life Science rows only.
     * Grant path: Approved + StartDate = today. Revoke path: Active + EndDate = today.
     * CreatedBy.Profile.Name scoping keeps this batch from ever touching a Healthcare row.
     * @param bc Batchable context from the platform.
     * @return Query locator for grant and revoke eligible Life Science rows.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        this.originalTransactionId = Logger.getTransactionId();
        try {
            if (Test.isRunningTest() && throwInStart) {
                throw new QueryException('Test start failure');
            }
            Date today = Date.today();
            return Database.getQueryLocator([
                SELECT Id, Name, StartDate__c, EndDate__c, Status__c, Requester__c, CoverageRep__c
                FROM TemporaryAccessException__c
                WHERE Requester__c != null
                  AND CoverageRep__c != null
                  AND CreatedBy.Profile.Name = :LSTemporaryAccessExceptionEmailService.LIFE_SCIENCE_SALES_PROFILE
                  AND (
                      (Status__c = :TemporaryAccessExceptionSelector.STATUS_APPROVED AND StartDate__c = :today)
                      OR (Status__c = :TemporaryAccessExceptionSelector.STATUS_ACTIVE AND EndDate__c = :today)
                  )
                WITH USER_MODE
            ]);
        } catch (Exception e) {
            startCatchCount++;
            Logger.error('LSTemporaryAccessExceptionBatch.start', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Processes each batch chunk via the existing, unmodified TemporaryAccessExceptionService.
     * Every row in scope is already Life Science only (see start()), so the Healthcare email branch
     * inside TemporaryAccessExceptionService.sendEmails() is always skipped for this batch.
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
            Logger.error('LSTemporaryAccessExceptionBatch.execute', e);
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
            Logger.error('LSTemporaryAccessExceptionBatch.finish', e);
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