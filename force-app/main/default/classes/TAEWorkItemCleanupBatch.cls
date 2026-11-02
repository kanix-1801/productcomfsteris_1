/**
 * GC-3420 - Deletes Done work items after the exception is Active or Expired.
 * @author Suraj Thapliyal
 * @date 2026/09/29
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-3420 - QueryLocator batch at scope TAEWorkItemService.CLEANUP_SCOPE.
 * Each execute deletes only Status = Done rows whose parent is Active or Expired.
 * Skipped, Error, and Pending rows are not selected. A failed delete stays Done
 * so recovery can retry it. The row is not rewritten to Error.
 * finish() starts the next exception only when no Done rows remain.
 */
public with sharing class TAEWorkItemCleanupBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    private Id taeId;
    private String originalTransactionId;
    /**
     * @description When true, finish() does not start the next pipeline. Tests only.
     */
    @TestVisible
    private static Boolean isChainingSuppressedForTest = false;

    /**
     * @description Scope used when cleanup is submitted.
     * @return TAEWorkItemService.CLEANUP_SCOPE, currently 2000.
     */
    public static Integer submissionScope() {
        return TAEWorkItemService.CLEANUP_SCOPE;
    }

    /**
     * @description Binds cleanup to one TemporaryAccessException__c.
     * @param exceptionId Exception whose Done work items will be deleted.
     */
    public TAEWorkItemCleanupBatch(Id exceptionId) {
        this.taeId = exceptionId;
    }

    /**
     * @description Returns Done work items for this exception when the parent is Active or Expired.
     * @param context Batchable context from the platform.
     * @return Query locator ordered by Id.
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        this.originalTransactionId = Logger.getTransactionId();
        try {
            return TAEWorkItemSelector.doneItemsLocator(taeId);
        } catch (Exception e) {
            Logger.error('TAEWorkItemCleanupBatch.start', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes the current chunk. No other DML runs in this execute.
     * @param context Batchable context from the platform.
     * @param scope Done TAEProcessingWorkItem__c rows.
     */
    public void execute(
        Database.BatchableContext context,
        List<SObject> scope
    ) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            if (scope.size() > TAEWorkItemService.CLEANUP_SCOPE) {
                throw new TAEWorkItemException('Cleanup scope exceeds configured maximum.');
            }
            if (!scope.isEmpty()) {
                Database.delete(scope, false, AccessLevel.SYSTEM_MODE);
            }
        } catch (Exception e) {
            Logger.error('TAEWorkItemCleanupBatch.execute', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Starts the next exception when this exception has no remaining Done rows.
     * @param context Batchable context from the platform.
     */
    public void finish(Database.BatchableContext context) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            if (isChainingSuppressedForTest) {
                Logger.info('TAEWorkItemCleanupBatch.finish: chaining suppressed for test');
            } else if (TAEWorkItemSelector.countDoneItems(taeId) > 0) {
                Logger.warn(
                    'TAEWorkItemCleanupBatch.finish: taeId=' + taeId +
                    ' still has Done rows; leaving them for recovery'
                );
            } else {
                TAEWorkItemService.resumeAfterPipelineFinish();
            }
        } catch (Exception e) {
            Logger.error('TAEWorkItemCleanupBatch.finish', e);
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