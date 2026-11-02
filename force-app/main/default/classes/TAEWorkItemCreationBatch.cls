/**
 * GC-3420 - Creates TAEProcessingWorkItem__c rows for one exception.
 * @author Suraj Thapliyal
 * @date 2026/09/29
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-3420 - Iterable batch that writes Pending work items from the Requester's
 * account and opportunity book. start() cannot use a QueryLocator because the
 * rows do not exist yet. DraftIterator builds one unsaved row per next() call.
 * finish() sets WorkItemsCreated__c and starts the first grant or revoke worker
 * only when every upsert succeeded. Scope is TAEWorkItemService.WORKER_SCOPE.
 * GC-3482 - A revoke draft ends with one DRAFT_HANDBACK row. That row is the marker
 * that owner reassignment still has to be queried. The open opportunities, tasks,
 * events, and contacts are not known here, so they are drafted later by TAEHandbackDraftBatch.
 */
public with sharing class TAEWorkItemCreationBatch
    implements Database.Batchable<TAEProcessingWorkItem__c>, Database.Stateful {

    private Id taeId;
    private String operation;
    private Integer failedUpserts = 0;
    private String originalTransactionId;
    /**
     * @description When true, finish() does not start the first worker. Tests only.
     */
    @TestVisible
    private static Boolean isChainingSuppressedForTest = false;

    /**
     * @description Scope used when this batch is submitted by the dispatcher.
     * @return TAEWorkItemService.WORKER_SCOPE, currently 500.
     */
    public static Integer submissionScope() {
        return TAEWorkItemService.WORKER_SCOPE;
    }

    /**
     * @description Binds this job to one TemporaryAccessException__c.
     * @param exceptionId Exception whose work items will be created.
     */
    public TAEWorkItemCreationBatch(Id exceptionId) {
        this.taeId = exceptionId;
    }

    /**
     * @description Loads the Requester book once and returns a cursor over draft work items.
     * @param context Batchable context from the platform.
     * @return Iterable that yields one Pending draft per team, audit, or delete line.
     */
    public Iterable<TAEProcessingWorkItem__c> start(Database.BatchableContext context) {
        this.originalTransactionId = Logger.getTransactionId();
        try {
            TAEWorkItemService.PlanSnapshot snapshot = TAEWorkItemService.buildPlan(taeId);
            operation = snapshot.pipelineOperation;
            DraftIterable drafts = new DraftIterable(snapshot);
            return drafts;
        } catch (Exception e) {
            Logger.error('TAEWorkItemCreationBatch.start', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Upserts the current chunk on CompositeKey__c. A failed row increments failedUpserts.
     * @param context Batchable context from the platform.
     * @param scope Draft work items built by DraftIterator for this chunk.
     */
    public void execute(
        Database.BatchableContext context,
        List<TAEProcessingWorkItem__c> scope
    ) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            List<Database.UpsertResult> results = Database.upsert(
                scope,
                TAEProcessingWorkItem__c.Fields.CompositeKey__c,
                false,
                AccessLevel.SYSTEM_MODE
            );
            for (Database.UpsertResult result : results) {
                if (!result.isSuccess()) {
                    failedUpserts++;
                }
            }
        } catch (Exception e) {
            Logger.error('TAEWorkItemCreationBatch.execute', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Marks the exception ready and starts ACCOUNT_TEAM or DELETE_ACCOUNT_TEAM when no upsert failed.
     * @param context Batchable context from the platform.
     */
    public void finish(Database.BatchableContext context) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            if (failedUpserts > 0) {
                Logger.warn(
                    'TAEWorkItemCreationBatch.finish: taeId=' + taeId +
                    ' failedUpserts=' + failedUpserts + '; work items not marked created'
                );
            } else {
                Database.update(
                    new TemporaryAccessException__c(
                        Id = taeId,
                        WorkItemsCreated__c = true
                    ),
                    AccessLevel.SYSTEM_MODE
                );
                if (!isChainingSuppressedForTest) {
                    submitFirstWorker();
                }
            }
        } catch (Exception e) {
            Logger.error('TAEWorkItemCreationBatch.finish', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Relates execute and finish log entries to the start transaction.
     */
    /**
     * @description Starts ACCOUNT_TEAM for a grant or DELETE_ACCOUNT_TEAM for a revoke.
     */
    private void submitFirstWorker() {
        if (operation == TAEWorkItemService.OP_GRANT) {
            Id jobId = Database.executeBatch(
                new TAEGrantWorkBatch(taeId, TAEWorkItemService.ACCOUNT_TEAM),
                TAEWorkItemService.WORKER_SCOPE
            );
            Logger.info(
                'TAEWorkItemCreationBatch.finish: submitted grant jobId=' + jobId +
                ', taeId=' + taeId
            );
        } else {
            Id jobId = Database.executeBatch(
                new TAERevokeWorkBatch(taeId, TAEWorkItemService.DELETE_ACCOUNT_TEAM),
                TAEWorkItemService.WORKER_SCOPE
            );
            Logger.info(
                'TAEWorkItemCreationBatch.finish: submitted revoke jobId=' + jobId +
                ', taeId=' + taeId
            );
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

    /**
     * @description Iterable wrapper required by Database.Batchable. Holds the plan and creates the cursor.
     */
    public class DraftIterable implements Iterable<TAEProcessingWorkItem__c> {
        private TAEWorkItemService.PlanSnapshot plan;

        /**
         * @description Stores the plan produced by TAEWorkItemService.buildPlan.
         * @param snapshot Frozen account ids, opportunity ids, and Grant or Revoke operation.
         */
        public DraftIterable(TAEWorkItemService.PlanSnapshot snapshot) {
            this.plan = snapshot;
        }

        /**
         * @description Creates a new cursor at position 0 for this plan.
         * @return DraftIterator over the plan.
         */
        public Iterator<TAEProcessingWorkItem__c> iterator() {
            DraftIterator cursor = new DraftIterator(plan);
            return cursor;
        }
    }

    /**
     * @description Cursor that builds one unsaved work item per next() call.
     * Grant order is account team, account audit, opportunity team, opportunity audit.
     * GC-3482 revoke order is delete account team, delete opportunity team, then one handback marker.
     * The marker's record Id is the exception Id. Adding one to the revoke total keeps finalize from
     * running when the only known rows are the team deletes.
     */
    public class DraftIterator implements Iterator<TAEProcessingWorkItem__c> {
        private TAEWorkItemService.PlanSnapshot plan;
        /**
         * @description Zero-based index of the next draft to build.
         */
        private Integer position = 0;
        /**
         * @description Grant count is 2 per record. Revoke count is 1 per record plus the handback marker.
         */
        private Integer total;

        /**
         * @description Sets the plan and the number of drafts to produce.
         * @param snapshot Frozen account ids, opportunity ids, and Grant or Revoke operation.
         */
        public DraftIterator(TAEWorkItemService.PlanSnapshot snapshot) {
            this.plan = snapshot;
            Integer recordCount = snapshot.accountIdList.size() + snapshot.opportunityIdList.size();
            if (snapshot.pipelineOperation == TAEWorkItemService.OP_GRANT) {
                total = 2 * recordCount;
            } else {
                total = recordCount + 1;
            }
        }

        /**
         * @description True while position is still inside the calculated total.
         * @return Whether another draft remains.
         */
        public Boolean hasNext() {
            Boolean moreRemain = position < total;
            return moreRemain;
        }

        /**
         * @description Builds the draft for the current position, then advances the cursor.
         * @return Pending work item, or null when the cursor is exhausted.
         */
        public TAEProcessingWorkItem__c next() {
            if (!hasNext()) {
                return null;
            }
            Integer accountCount = plan.accountIdList.size();
            Integer opportunityCount = plan.opportunityIdList.size();
            String workType;
            Id recordId;
            if (plan.pipelineOperation == TAEWorkItemService.OP_GRANT) {
                if (position < accountCount) {
                    workType = TAEWorkItemService.ACCOUNT_TEAM;
                    recordId = plan.accountIdList[position];
                } else if (position < 2 * accountCount) {
                    workType = TAEWorkItemService.JUNCTION_ACCOUNT;
                    recordId = plan.accountIdList[position - accountCount];
                } else if (position < 2 * accountCount + opportunityCount) {
                    workType = TAEWorkItemService.OPP_TEAM;
                    recordId = plan.opportunityIdList[position - (2 * accountCount)];
                } else {
                    workType = TAEWorkItemService.JUNCTION_OPP;
                    recordId = plan.opportunityIdList[
                        position - (2 * accountCount) - opportunityCount
                    ];
                }
            } else if (position < accountCount) {
                workType = TAEWorkItemService.DELETE_ACCOUNT_TEAM;
                recordId = plan.accountIdList[position];
            } else if (position < accountCount + opportunityCount) {
                workType = TAEWorkItemService.DELETE_OPP_TEAM;
                recordId = plan.opportunityIdList[position - accountCount];
            } else {
                // GC-3482. One marker per revoke. Its record Id is the exception, not an account or opportunity.
                workType = TAEWorkItemService.DRAFT_HANDBACK;
                recordId = plan.coveredExceptionId;
            }
            position++;
            TAEProcessingWorkItem__c draftItem =
                TAEWorkItemService.draft(plan.coveredExceptionId, workType, recordId);
            return draftItem;
        }
    }
}