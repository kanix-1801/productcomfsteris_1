/**
 * GC-3420 - Revoke worker for one DML domain of one exception.
 * @author Suraj Thapliyal
 * @date 2026/09/29
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-3420 - QueryLocator batch over Pending delete work items.
 * DELETE_ACCOUNT_TEAM removes temporary Account Team Members.
 * DELETE_OPP_TEAM removes temporary Opportunity Team Members.
 * Assigned records are not deleted.
 * GC-3482 - After both deletes, finish() starts the handback draft instead of Expired.
 * Later executions of this same class set OwnerId back to the Requester, one object per job:
 * open opportunities, incomplete tasks, upcoming events, then contacts.
 * Each job is its own transaction at scope 500, so the 10,000-row DML limit starts over.
 * Expired and the revoke email run only when no revoke work item is Pending or Error.
 * Scope is TAEWorkItemService.WORKER_SCOPE.
 */
public with sharing class TAERevokeWorkBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    private Id taeId;
    private String phase;
    private String originalTransactionId;
    /**
     * @description When true, finish() does not chain the next phase. Tests only.
     */
    @TestVisible
    private static Boolean isChainingSuppressedForTest = false;

    /**
     * @description Scope used when the opportunity delete phase is submitted.
     * @return TAEWorkItemService.WORKER_SCOPE, currently 500.
     */
    public static Integer submissionScope() {
        return TAEWorkItemService.WORKER_SCOPE;
    }

    /**
     * @description Binds this job to one exception and one revoke phase.
     * @param exceptionId TemporaryAccessException__c being revoked.
     * @param revokePhase Delete or reassign phase name.
     */
    public TAERevokeWorkBatch(Id exceptionId, String revokePhase) {
        this.taeId = exceptionId;
        this.phase = revokePhase;
    }

    /**
     * @description Returns Pending delete work items for this exception and phase.
     * @param context Batchable context from the platform.
     * @return Query locator ordered by Id.
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        this.originalTransactionId = Logger.getTransactionId();
        try {
            return TAEWorkItemSelector.pendingLocator(taeId, phaseTypes());
        } catch (Exception e) {
            Logger.error('TAERevokeWorkBatch.start', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GC-3420 deletes temporary team members. GC-3482 reassign phases call processOwnerReassign.
     * The phase is chosen in the constructor, so one execute never mixes deletes and owner updates.
     * @param context Batchable context from the platform.
     * @param rawScope Pending TAEProcessingWorkItem__c rows.
     */
    public void execute(
        Database.BatchableContext context,
        List<SObject> rawScope
    ) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            List<TAEProcessingWorkItem__c> scope =
                (List<TAEProcessingWorkItem__c>) rawScope;
            if (scope.size() > TAEWorkItemService.WORKER_SCOPE) {
                throw new TAEWorkItemException('Revoke work-item scope exceeds configured maximum.');
            }
            if (phase == TAEWorkItemService.DELETE_ACCOUNT_TEAM) {
                TAEWorkItemService.processAccountTeamDelete(scope);
            } else if (phase == TAEWorkItemService.DELETE_OPP_TEAM) {
                TAEWorkItemService.processOpportunityTeamDelete(scope);
            } else {
                // GC-3482. REASSIGN_OPPORTUNITY, REASSIGN_TASK, REASSIGN_EVENT, or REASSIGN_CONTACT.
                TAEWorkItemService.processOwnerReassign(scope);
            }
        } catch (Exception e) {
            Logger.error('TAERevokeWorkBatch.execute', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GC-3482 chain: account delete, opportunity delete, handback draft, then each reassign phase.
     * An Error row does not finalize. resumeAfterPipelineFinish decides the next job.
     * Expired is reached only when nextPendingPhase finds nothing left.
     * @param context Batchable context from the platform.
     */
    public void finish(Database.BatchableContext context) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            Set<String> types = phaseTypes();
            if (TAEWorkItemService.hasErrors(taeId, types)) {
                Logger.warn(
                    'TAERevokeWorkBatch.finish: taeId=' + taeId +
                    ' phase=' + phase + ' has Error rows'
                );
                if (!isChainingSuppressedForTest) {
                    TAEWorkItemService.resumeAfterPipelineFinish();
                }
            } else if (isChainingSuppressedForTest) {
                if (phase == TAEWorkItemService.REASSIGN_CONTACT) {
                    TAEWorkItemService.finalizeTae(taeId, TAEWorkItemService.OP_REVOKE);
                }
            } else if (phase == TAEWorkItemService.DELETE_ACCOUNT_TEAM) {
                Id jobId = Database.executeBatch(
                    new TAERevokeWorkBatch(taeId, TAEWorkItemService.DELETE_OPP_TEAM),
                    TAEWorkItemService.WORKER_SCOPE
                );
                Logger.info(
                    'TAERevokeWorkBatch.finish: submitted DELETE_OPP_TEAM jobId=' + jobId
                );
            } else if (phase == TAEWorkItemService.DELETE_OPP_TEAM) {
                // GC-3482. Team removal is done. Draft open work before anyone can mark the request Expired.
                Id jobId = Database.executeBatch(
                    new TAEHandbackDraftBatch(taeId, TAEWorkItemService.REASSIGN_OPPORTUNITY),
                    TAEWorkItemService.WORKER_SCOPE
                );
                Logger.info(
                    'TAERevokeWorkBatch.finish: submitted handback draft jobId=' + jobId
                );
            } else {
                submitNextReassignOrFinalize();
            }
        } catch (Exception e) {
            Logger.error('TAERevokeWorkBatch.finish', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GC-3482. Queues the next Pending reassign phase, or finalizes when none remain.
     * One executeBatch only. Opportunities, tasks, events, and contacts stay in separate transactions.
     * If the handback marker is still Pending, the draft is started again instead of an owner update.
     */
    private void submitNextReassignOrFinalize() {
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
                'TAERevokeWorkBatch.finish: submitted handback draft jobId=' + draftJobId
            );
        } else {
            Id jobId = Database.executeBatch(
                new TAERevokeWorkBatch(taeId, nextPhase),
                TAEWorkItemService.WORKER_SCOPE
            );
            Logger.info(
                'TAERevokeWorkBatch.finish: submitted phase=' + nextPhase + ' jobId=' + jobId
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
     * @description Work type queried and checked for this phase.
     * @return The single delete work type for the current phase.
     */
    private Set<String> phaseTypes() {
        Set<String> types = new Set<String>{ phase };
        return types;
    }
}