/**
 * @author Chandini Singarapu
 * @date 2026/06/04
 *
 * @description
 * Batch and schedulable class for evaluating stale Opportunity records.
 * Delegates query logic to OpportunityStaleSelector and business processing
 * to OpportunityStaleService.
 * #USER STORY GC-2647
 */
public with sharing class OpportunityStaleBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    public static final Integer DEFAULT_BATCH_SIZE = 200;
    public static final Integer FLEX_QUEUE_MAX_BATCH_JOBS = 100;

    private String originalTransactionId;

    @TestVisible private static Boolean skipFlexQueueCheckForTest = false;
    @TestVisible private static Integer testFlexQueueHoldingCountOverride;

    @TestVisible private static Boolean throwInStart = false;
    @TestVisible private static Boolean throwInExecute = false;
    @TestVisible private static Boolean throwInFinish = false;

    @TestVisible private static Integer startCatchCount = 0;
    @TestVisible private static Integer executeCatchCount = 0;
    @TestVisible private static Integer finishCatchCount = 0;

    /**
     * @description Default constructor for stale Opportunity batch processing.
     */
    public OpportunityStaleBatch() {
    }

    /**
     * @description Schedulable entry point. Submits the stale Opportunity batch.
     *
     * @param sc Schedulable context from the platform
     */
    public void execute(SchedulableContext sc) {
        Logger.setScenario('Opportunity Stale Management');
        Logger.info('OpportunityStaleBatch.execute Schedulable: submitting batch');

        try {
            submitBatch();
        } catch (Exception e) {
            Logger.error('OpportunityStaleBatch.execute Schedulable', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Submits the batch after validating flex queue capacity.
     *
     * @return AsyncApexJob Id for the submitted batch
     */
    public static Id submitBatch() {
        assertFlexQueueHasCapacity();

        Id jobId = Database.executeBatch(new OpportunityStaleBatch(), DEFAULT_BATCH_SIZE);

        Logger.info(
            'OpportunityStaleBatch.submitBatch: submitted jobId=' + jobId +
            ', batchSize=' + DEFAULT_BATCH_SIZE
        );

        return jobId;
    }

    /**
     * @description Ensures the org flex queue can accept another batch job.
     */
    public static void assertFlexQueueHasCapacity() {
        if (Test.isRunningTest() && skipFlexQueueCheckForTest) {
            return;
        }

        Integer flexQueueHoldingCount = resolveFlexQueueHoldingCount();

        Logger.debug(
            'OpportunityStaleBatch.assertFlexQueueHasCapacity: holdingJobs=' +
            flexQueueHoldingCount + '/' + FLEX_QUEUE_MAX_BATCH_JOBS
        );

        if (flexQueueHoldingCount >= FLEX_QUEUE_MAX_BATCH_JOBS) {
            throw new OpportunityStaleBatchException(
                'Cannot submit batch: flex queue is full (' +
                flexQueueHoldingCount + ' Holding jobs, max ' + FLEX_QUEUE_MAX_BATCH_JOBS + ')'
            );
        }
    }

    /**
     * @description Counts BatchApex jobs in Holding status, or test override when set.
     *
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
     * @description Returns open Opportunity records to be evaluated for stale status.
     *
     * @param bc Batchable context from the platform
     * @return Query locator for open Opportunity records
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        this.originalTransactionId = Logger.getTransactionId();
        Logger.setScenario('Opportunity Stale Management');

        try {
            if (Test.isRunningTest() && throwInStart) {
                throw new QueryException('Test start failure');
            }

            return OpportunityStaleSelector.getOpenOpportunitiesQueryLocator();
        } catch (Exception e) {
            startCatchCount++;
            Logger.error('OpportunityStaleBatch.start', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Processes each batch chunk via OpportunityStaleService.
     *
     * @param bc Batchable context from the platform
     * @param scope Opportunity records in the current chunk
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Logger.setScenario('Opportunity Stale Management');

        try {
            if (Test.isRunningTest() && throwInExecute) {
                throw new OpportunityStaleBatchException('Test execute failure');
            }

            List<Opportunity> opportunityScope = (List<Opportunity>) scope;
            OpportunityStaleService.process(opportunityScope);
        } catch (Exception e) {
            executeCatchCount++;
            Logger.error('OpportunityStaleBatch.execute', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Completes the batch run and restores the parent log transaction Id.
     *
     * @param bc Batchable context from the platform
     */
    public void finish(Database.BatchableContext bc) {
        Logger.setParentLogTransactionId(this.originalTransactionId);
        Logger.setScenario('Opportunity Stale Management');

        try {
            if (Test.isRunningTest() && throwInFinish) {
                throw new DmlException('Test finish failure');
            }

            Logger.info('OpportunityStaleBatch.finish: batch completed');
        } catch (Exception e) {
            finishCatchCount++;
            Logger.error('OpportunityStaleBatch.finish', e);
        } finally {
            Logger.saveLog();
        }
    }
}