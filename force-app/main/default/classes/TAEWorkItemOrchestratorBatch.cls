/**
 * GC-3420 - Nightly entry point for the serialized TAE work-item pipeline.
 * @author Suraj Thapliyal
 * @date 2026/09/29
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-3420 - Batch and schedulable that marks each due TemporaryAccessException__c
 * as Processing. Scope is fixed at 1. execute() does not start a child job.
 * finish() starts the oldest Processing exception through TAEWorkItemService.
 * This class is not scheduled by metadata. Schedule it only during cutover
 * after disabling the legacy TemporaryAccessExceptionBatch schedule.
 * Cron for daily 1:00 AM: 0 0 1 * * ?.
 */
public with sharing class TAEWorkItemOrchestratorBatch
    implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    /**
     * @description Parent batch scope. Always one exception per execute.
     */
    public static final Integer FIXED_PARENT_SCOPE = 1;
    /**
     * @description Cron expression for daily 1:00 AM execution.
     */
    public static final String DAILY_1_AM = '0 0 1 * * ?';
    private String originalTransactionId;
    /**
     * @description When true, finish() does not call the dispatcher. Tests only.
     */
    @TestVisible
    private static Boolean isDispatchSuppressedForTest = false;
    /**
     * @description When true, the schedulable entry throws before submit. Tests only.
     */
    @TestVisible
    private static Boolean isSubmitFailureForcedForTest = false;

    /**
     * @description Scope used when the nightly parent batch is submitted.
     * @return FIXED_PARENT_SCOPE, which is always 1.
     */
    public static Integer submissionScope() {
        return FIXED_PARENT_SCOPE;
    }

    /**
     * @description Schedulable entry point. Submits the parent batch at scope 1.
     * @param context Schedulable context from the platform.
     * @example
     * System.schedule('TAE Work Item Orchestrator',
     *     TAEWorkItemOrchestratorBatch.DAILY_1_AM,
     *     new TAEWorkItemOrchestratorBatch());
     */
    public void execute(SchedulableContext context) {
        Logger.info('TAEWorkItemOrchestratorBatch.execute (Schedulable): submitting batch');
        try {
            if (isSubmitFailureForcedForTest) {
                throw new TAEWorkItemException('Orchestrator submit failed for test.');
            }
            submit();
        } catch (Exception e) {
            Logger.error('TAEWorkItemOrchestratorBatch.execute (Schedulable)', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Submits this batch with FIXED_PARENT_SCOPE.
     * @return AsyncApexJob Id for the submitted batch.
     * @example
     * TAEWorkItemOrchestratorBatch.submit();
     */
    public static Id submit() {
        Id jobId = Database.executeBatch(
            new TAEWorkItemOrchestratorBatch(),
            FIXED_PARENT_SCOPE
        );
        Logger.info(
            'TAEWorkItemOrchestratorBatch.submit: submitted jobId=' + jobId +
            ', batchSize=' + FIXED_PARENT_SCOPE
        );
        return jobId;
    }

    /**
     * @description Returns exceptions due today: Approved with Start Date today, or Active with End Date today.
     * @param context Batchable context from the platform.
     * @return Query locator ordered by CreatedDate, then Id.
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        this.originalTransactionId = Logger.getTransactionId();
        try {
            return TAEWorkItemSelector.eligibleTaeLocator();
        } catch (Exception e) {
            Logger.error('TAEWorkItemOrchestratorBatch.start', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Marks the single exception in scope as Processing. Does not create work items.
     * @param context Batchable context from the platform.
     * @param rawScope One TemporaryAccessException__c.
     */
    public void execute(
        Database.BatchableContext context,
        List<SObject> rawScope
    ) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            List<TemporaryAccessException__c> scope =
                (List<TemporaryAccessException__c>) rawScope;
            if (scope.size() != 1) {
                throw new TAEWorkItemException('Parent TAE scope must be exactly one.');
            }
            TAEWorkItemService.markForProcessing(scope[0]);
        } catch (Exception e) {
            Logger.error('TAEWorkItemOrchestratorBatch.execute', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Starts the next work-item pipeline after every parent execute has finished.
     * @param context Batchable context from the platform.
     */
    public void finish(Database.BatchableContext context) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            if (isDispatchSuppressedForTest) {
                Logger.info('TAEWorkItemOrchestratorBatch.finish: dispatch suppressed for test');
            } else {
                TAEWorkItemService.startNextTaePipeline();
            }
        } catch (Exception e) {
            Logger.error('TAEWorkItemOrchestratorBatch.finish', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Relates execute and finish log entries to the start transaction.
     */
    private void linkExecuteAndFinishLogsToStartTransaction() {
        if (String.isNotBlank(this.originalTransactionId)) {
            Logger.setParentLogTransactionId(this.originalTransactionId);
        }
    }
}