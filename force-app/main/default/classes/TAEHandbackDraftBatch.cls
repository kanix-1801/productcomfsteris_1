/**
 * GC-3482 - Drafts owner-reassignment work items for one object type.
 * @author Suraj Thapliyal
 * @date 2026/10/15
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-3482 - QueryLocator batch over open records the Coverage Rep owns on the
 * covered accounts. The count of those records is not known when the team-delete
 * drafts are written, and loading every Id in start() can pass the 50,000 query-row
 * limit or the heap limit. A QueryLocator hands this job 500 Ids per execute.
 * Order of jobs: open opportunities, incomplete tasks, upcoming events, contacts.
 * Each job upserts Pending TAEProcessingWorkItem__c rows on CompositeKey__c, so a
 * resumed draft does not create a second row for the same record.
 * Occurrences of a recurring event or task are not drafted. The series row is drafted.
 * After contacts, the DRAFT_HANDBACK marker is set to Done and the first reassign
 * worker starts. A failed upsert leaves the marker Pending so the request cannot expire.
 * Scope is TAEWorkItemService.WORKER_SCOPE.
 */
public with sharing class TAEHandbackDraftBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    private Id taeId;
    private String workType;
    private Integer failedUpserts = 0;
    private String originalTransactionId;
    /**
     * @description When true, finish() does not chain the next draft or worker. Tests only.
     */
    @TestVisible
    private static Boolean isChainingSuppressedForTest = false;

    /**
     * @description Scope used when this draft is submitted.
     * @return TAEWorkItemService.WORKER_SCOPE, currently 500.
     */
    public static Integer submissionScope() {
        return TAEWorkItemService.WORKER_SCOPE;
    }

    /**
     * @description Binds this job to one exception and one handback object.
     * @param exceptionId TemporaryAccessException__c being revoked.
     * @param handbackType REASSIGN_OPPORTUNITY, REASSIGN_TASK, REASSIGN_EVENT, or REASSIGN_CONTACT.
     */
    public TAEHandbackDraftBatch(Id exceptionId, String handbackType) {
        this.taeId = exceptionId;
        this.workType = handbackType;
    }

    /**
     * @description GC-3482. Covered accounts come from the Requester book already used by the grant.
     * The Coverage Rep on the exception is the owner filter. This start() does not update any record.
     * @param context Batchable context from the platform.
     * @return Query locator of record Ids for the current object only.
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        this.originalTransactionId = Logger.getTransactionId();
        try {
            TAEWorkItemService.PlanSnapshot snapshot = TAEWorkItemService.buildPlan(taeId);
            Set<Id> accountIds = new Set<Id>();
            accountIds.addAll(snapshot.accountIdList);
            TemporaryAccessException__c header = TAEWorkItemSelector.selectTae(taeId);
            Id coverageRepId = null;
            if (header != null) {
                coverageRepId = header.CoverageRep__c;
            }
            return TAEWorkItemSelector.handbackLocator(accountIds, coverageRepId, workType);
        } catch (Exception e) {
            Logger.error('TAEHandbackDraftBatch.start', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GC-3482. Upserts one Pending work item per record. OwnerId is not changed here.
     * The composite key is exception Id, work type, and record Id. A later worker performs the owner update.
     * A failed row increments failedUpserts so finish() will not mark the handback marker Done.
     * @param context Batchable context from the platform.
     * @param scope Opportunity, Task, Event, or Contact rows for this chunk. At most 500.
     */
    public void execute(Database.BatchableContext context, List<SObject> scope) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            if (scope.size() > TAEWorkItemService.WORKER_SCOPE) {
                throw new TAEWorkItemException('Handback draft scope exceeds configured maximum.');
            }
            List<TAEProcessingWorkItem__c> drafts = new List<TAEProcessingWorkItem__c>();
            for (SObject row : scope) {
                drafts.add(TAEWorkItemService.draft(taeId, workType, row.Id));
            }
            if (!drafts.isEmpty()) {
                List<Database.UpsertResult> results = Database.upsert(
                    drafts,
                    TAEProcessingWorkItem__c.Fields.CompositeKey__c,
                    false,
                    AccessLevel.SYSTEM_MODE
                );
                for (Database.UpsertResult result : results) {
                    if (!result.isSuccess()) {
                        failedUpserts++;
                    }
                }
            }
        } catch (Exception e) {
            failedUpserts++;
            Logger.error('TAEHandbackDraftBatch.execute', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GC-3482. Chains the next object draft. After contacts, marks DRAFT_HANDBACK Done
     * and starts owner reassignment. One child job is queued. A failed chunk leaves the marker Pending.
     * @param context Batchable context from the platform.
     */
    public void finish(Database.BatchableContext context) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            if (failedUpserts > 0) {
                Logger.warn(
                    'TAEHandbackDraftBatch.finish: taeId=' + taeId +
                    ' workType=' + workType + ' failedUpserts=' + failedUpserts
                );
                if (!isChainingSuppressedForTest) {
                    TAEWorkItemService.resumeAfterPipelineFinish();
                }
            } else {
                String nextType = nextDraftType(workType);
                if (nextType != null) {
                    submitNextDraft(nextType);
                } else {
                    completeHandbackMarker();
                    submitFirstReassignOrFinalize();
                }
            }
        } catch (Exception e) {
            Logger.error('TAEHandbackDraftBatch.finish', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Starts the draft for the next object when chaining is allowed.
     * @param nextType Next REASSIGN work type.
     */
    private void submitNextDraft(String nextType) {
        if (!isChainingSuppressedForTest) {
            Id jobId = Database.executeBatch(
                new TAEHandbackDraftBatch(taeId, nextType),
                TAEWorkItemService.WORKER_SCOPE
            );
            Logger.info(
                'TAEHandbackDraftBatch.finish: submitted draft=' + nextType + ' jobId=' + jobId
            );
        }
    }

    /**
     * @description Marks the handback marker Done, then starts the first Pending reassign phase.
     */
    private void submitFirstReassignOrFinalize() {
        if (!isChainingSuppressedForTest) {
            String nextPhase = TAEWorkItemService.nextPendingPhase(
                TAEWorkItemService.OP_REVOKE,
                TAEWorkItemService.pendingWorkTypes(taeId)
            );
            if (nextPhase == null) {
                TAEWorkItemService.finalizeTae(taeId, TAEWorkItemService.OP_REVOKE);
                TAEWorkItemService.resumeAfterPipelineFinish();
            } else if (nextPhase == TAEWorkItemService.DRAFT_HANDBACK) {
                Id draftJobId = Database.executeBatch(
                    new TAEHandbackDraftBatch(taeId, TAEWorkItemService.REASSIGN_OPPORTUNITY),
                    TAEWorkItemService.WORKER_SCOPE
                );
                Logger.info(
                    'TAEHandbackDraftBatch.finish: resubmitted handback draft jobId=' + draftJobId
                );
            } else {
                Id jobId = Database.executeBatch(
                    new TAERevokeWorkBatch(taeId, nextPhase),
                    TAEWorkItemService.WORKER_SCOPE
                );
                Logger.info(
                    'TAEHandbackDraftBatch.finish: submitted phase=' + nextPhase + ' jobId=' + jobId
                );
            }
        }
    }

    /**
     * @description GC-3482. Sets DRAFT_HANDBACK to Done. Reassign rows can still be Pending.
     * Finalize waits for those rows because they are in REVOKE_TYPES. The marker only means drafting finished.
     */
    private void completeHandbackMarker() {
        List<TAEProcessingWorkItem__c> markers = [
            SELECT Id, Status__c, ErrorMessage__c, ProcessedDate__c
            FROM TAEProcessingWorkItem__c
            WHERE TemporaryAccessException__c = :taeId
              AND WorkType__c = :TAEWorkItemService.DRAFT_HANDBACK
              AND Status__c = :TAEWorkItemService.STATUS_PENDING
            WITH SYSTEM_MODE
        ];
        for (TAEProcessingWorkItem__c marker : markers) {
            marker.Status__c = TAEWorkItemService.STATUS_DONE;
            marker.ErrorMessage__c = TAEWorkItemService.REASON_HANDBACK_SEARCH_FINISHED;
            marker.ProcessedDate__c = System.now();
        }
        if (!markers.isEmpty()) {
            Database.update(markers, false, AccessLevel.SYSTEM_MODE);
        }
    }

    /**
     * @description GC-3482 draft order: opportunity, task, event, contact. Null means contacts are done.
     * @param currentType Work type this job drafted.
     * @return The following REASSIGN work type, or null after REASSIGN_CONTACT.
     */
    private static String nextDraftType(String currentType) {
        String nextType = null;
        if (currentType == TAEWorkItemService.REASSIGN_OPPORTUNITY) {
            nextType = TAEWorkItemService.REASSIGN_TASK;
        } else if (currentType == TAEWorkItemService.REASSIGN_TASK) {
            nextType = TAEWorkItemService.REASSIGN_EVENT;
        } else if (currentType == TAEWorkItemService.REASSIGN_EVENT) {
            nextType = TAEWorkItemService.REASSIGN_CONTACT;
        }
        return nextType;
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