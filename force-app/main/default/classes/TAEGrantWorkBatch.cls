/**
 * GC-3420 - Grant worker for one DML domain of one exception.
 * @author Suraj Thapliyal
 * @date 2026/09/29
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-3420 - QueryLocator batch over Pending work items of one phase.
 * ACCOUNT_TEAM inserts Account Team Members, OPP_TEAM inserts Opportunity Team
 * Members, and JUNCTION inserts TAE_AssignedRecord__c rows. finish() starts the
 * next phase, or finalizes the exception when the junction phase has no errors.
 * Scope is TAEWorkItemService.WORKER_SCOPE.
 */
public with sharing class TAEGrantWorkBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    private Id taeId;
    private String phase;
    private String originalTransactionId;
    /**
     * @description When true, finish() does not chain the next phase. Tests set this. Production leaves it false.
     */
    @TestVisible
    private static Boolean isChainingSuppressedForTest = false;

    /**
     * @description Scope used when a later phase of this batch is submitted.
     * @return TAEWorkItemService.WORKER_SCOPE, currently 500.
     */
    public static Integer submissionScope() {
        return TAEWorkItemService.WORKER_SCOPE;
    }

    /**
     * @description Binds this job to one exception and one grant phase.
     * @param exceptionId TemporaryAccessException__c being granted.
     * @param grantPhase ACCOUNT_TEAM, OPP_TEAM, or JUNCTION.
     */
    public TAEGrantWorkBatch(Id exceptionId, String grantPhase) {
        this.taeId = exceptionId;
        this.phase = grantPhase;
    }

    /**
     * @description Returns Pending work items for this exception and phase.
     * @param context Batchable context from the platform.
     * @return Query locator ordered by Id.
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        this.originalTransactionId = Logger.getTransactionId();
        try {
            return TAEWorkItemSelector.pendingLocator(taeId, phaseTypes());
        } catch (Exception e) {
            Logger.error('TAEGrantWorkBatch.start', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Inserts team members or assigned records for the current chunk.
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
                throw new TAEWorkItemException('Grant work-item scope exceeds configured maximum.');
            }
            if (phase == TAEWorkItemService.ACCOUNT_TEAM) {
                TAEWorkItemService.processAccountGrant(scope);
            } else if (phase == TAEWorkItemService.OPP_TEAM) {
                TAEWorkItemService.processOpportunityGrant(scope);
            } else {
                TAEWorkItemService.processJunctionGrant(scope);
            }
        } catch (Exception e) {
            Logger.error('TAEGrantWorkBatch.execute', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Chains the next grant phase, or finalizes when this phase has no Error rows.
     * @param context Batchable context from the platform.
     */
    public void finish(Database.BatchableContext context) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            Set<String> types = phaseTypes();
            if (TAEWorkItemService.hasErrors(taeId, types)) {
                Logger.warn(
                    'TAEGrantWorkBatch.finish: taeId=' + taeId +
                    ' phase=' + phase + ' has Error rows'
                );
                if (!isChainingSuppressedForTest) {
                    TAEWorkItemService.resumeAfterPipelineFinish();
                }
            } else if (isChainingSuppressedForTest) {
                if (phase == TAEWorkItemService.PHASE_JUNCTION) {
                    TAEWorkItemService.finalizeTae(taeId, TAEWorkItemService.OP_GRANT);
                }
            } else if (phase == TAEWorkItemService.ACCOUNT_TEAM) {
                Id jobId = Database.executeBatch(
                    new TAEGrantWorkBatch(taeId, TAEWorkItemService.OPP_TEAM),
                    TAEWorkItemService.WORKER_SCOPE
                );
                Logger.info('TAEGrantWorkBatch.finish: submitted OPP_TEAM jobId=' + jobId);
            } else if (phase == TAEWorkItemService.OPP_TEAM) {
                Id jobId = Database.executeBatch(
                    new TAEGrantWorkBatch(taeId, TAEWorkItemService.PHASE_JUNCTION),
                    TAEWorkItemService.WORKER_SCOPE
                );
                Logger.info('TAEGrantWorkBatch.finish: submitted JUNCTION jobId=' + jobId);
            } else {
                TAEWorkItemService.finalizeTae(taeId, TAEWorkItemService.OP_GRANT);
                TAEWorkItemService.resumeAfterPipelineFinish();
            }
        } catch (Exception e) {
            Logger.error('TAEGrantWorkBatch.finish', e);
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

    /**
     * @description Work types queried and checked for this phase. JUNCTION covers both junction types.
     * @return Work type API values for the current phase.
     */
    private Set<String> phaseTypes() {
        Set<String> types = new Set<String>();
        if (phase == TAEWorkItemService.ACCOUNT_TEAM) {
            types.add(TAEWorkItemService.ACCOUNT_TEAM);
        } else if (phase == TAEWorkItemService.OPP_TEAM) {
            types.add(TAEWorkItemService.OPP_TEAM);
        } else {
            types.add(TAEWorkItemService.JUNCTION_ACCOUNT);
            types.add(TAEWorkItemService.JUNCTION_OPP);
        }
        return types;
    }
}