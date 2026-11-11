/**
 * GC-3420 - Business service for the serialized TAE work-item pipeline.
 * @author Suraj Thapliyal
 * @date 2026/09/29
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-3420 - Builds the account and opportunity plan, drafts work items, runs
 * grant and revoke DML for one chunk, finalizes the exception, and starts the
 * next pipeline job. This class does not call TemporaryAccessExceptionService
 * or TemporaryAccessExceptionSelector.
 * GC-3482 - On revoke, after the temporary team rows are removed, open work the
 * Coverage Rep owns on the covered accounts is handed back to the Requester.
 * Only OwnerId changes. Created By, Created Date, and the rest of the record stay as they are.
 * GC-3482 - Each finished work item stores the outcome sentence on ErrorMessage__c.
 */
public with sharing class TAEWorkItemService {
    /**
     * @description Scope for creation, grant, and revoke batches.
     */
    public static final Integer WORKER_SCOPE = 500;
    /**
     * @description Scope for the Done-row cleanup batch.
     */
    public static final Integer CLEANUP_SCOPE = 2000;
    /**
     * @description Worker execute stops when DML rows pass this guard.
     */
    public static final Integer MAX_DML_ROWS = 4000;

    /**
     * @description ProcessingOperation__c value for a grant.
     */
    public static final String OP_GRANT = 'Grant';
    /**
     * @description ProcessingOperation__c value for a revoke.
     */
    public static final String OP_REVOKE = 'Revoke';
    /**
     * @description Work item waiting to be processed.
     */
    public static final String STATUS_PENDING = 'Pending';
    /**
     * @description Work item whose DML succeeded.
     */
    public static final String STATUS_DONE = 'Done';
    /**
     * @description Work item whose row-level DML failed.
     */
    public static final String STATUS_ERROR = 'Error';
    /**
     * @description Work item that needed no DML, such as a team row that already exists.
     */
    public static final String STATUS_SKIPPED = 'Skipped';
    /**
     * @description GC-3482. Error Message stored when the handback marker is marked Done.
     */
    public static final String REASON_HANDBACK_SEARCH_FINISHED =
        'Handback search finished. Open records are ready to reassign.';

    /**
     * @description Grant work type that inserts an Account Team Member.
     */
    public static final String ACCOUNT_TEAM = 'ACCOUNT_TEAM';
    /**
     * @description Grant work type that inserts an Opportunity Team Member.
     */
    public static final String OPP_TEAM = 'OPP_TEAM';
    /**
     * @description Grant work type that inserts a TAE_AssignedRecord__c for an Account.
     */
    public static final String JUNCTION_ACCOUNT = 'JUNCTION_ACCOUNT';
    /**
     * @description Grant work type that inserts a TAE_AssignedRecord__c for an Opportunity.
     */
    public static final String JUNCTION_OPP = 'JUNCTION_OPP';
    /**
     * @description Revoke work type that deletes a temporary Account Team Member.
     */
    public static final String DELETE_ACCOUNT_TEAM = 'DELETE_ACCOUNT_TEAM';
    /**
     * @description Revoke work type that deletes a temporary Opportunity Team Member.
     */
    public static final String DELETE_OPP_TEAM = 'DELETE_OPP_TEAM';
    /**
     * @description GC-3482 marker. One Pending row is created with the team-delete drafts.
     * It stays Pending until every handback draft job has finished. Finalize treats it as
     * open revoke work, so the request cannot become Expired and the revoke email cannot
     * send while owner reassignment has not been drafted yet.
     * RecordId__c on this row is the exception Id. It is not a business record to update.
     */
    public static final String DRAFT_HANDBACK = 'DRAFT_HANDBACK';
    /**
     * @description GC-3482. Open opportunity on a covered account, owned now by the Coverage Rep.
     * Closed Won and Closed Lost are not drafted. The worker sets OwnerId to the Requester.
     */
    public static final String REASSIGN_OPPORTUNITY = 'REASSIGN_OPPORTUNITY';
    /**
     * @description GC-3482. Incomplete task on a covered account, owned now by the Coverage Rep.
     * Completed tasks stay with the Coverage Rep. A recurring task is drafted as the series
     * only. Individual occurrences are skipped because Salesforce rejects an owner change on them.
     */
    public static final String REASSIGN_TASK = 'REASSIGN_TASK';
    /**
     * @description GC-3482. Event on a covered account that has not ended, owned now by the Coverage Rep.
     * A meeting that started earlier today and ends later today is included. A past event stays
     * with the Coverage Rep. A recurring meeting is drafted as the series only. Occurrences are skipped.
     */
    public static final String REASSIGN_EVENT = 'REASSIGN_EVENT';
    /**
     * @description GC-3482. Contact on a covered account, owned now by the Coverage Rep.
     * Contacts on any other account are left alone. The worker sets OwnerId to the Requester.
     */
    public static final String REASSIGN_CONTACT = 'REASSIGN_CONTACT';
    /**
     * @description Phase name used when both junction work types are processed in one job.
     */
    public static final String PHASE_JUNCTION = 'JUNCTION';
    /**
     * @description TemporaryAccessException__c status before a grant starts.
     */
    public static final String HEADER_APPROVED = 'Approved';
    /**
     * @description TemporaryAccessException__c status after a successful grant.
     */
    public static final String HEADER_ACTIVE = 'Active';
    /**
     * @description TemporaryAccessException__c status while work items are running.
     */
    public static final String HEADER_PROCESSING = 'Processing';
    /**
     * @description TemporaryAccessException__c status after a successful revoke.
     */
    public static final String HEADER_EXPIRED = 'Expired';
    /**
     * @description TeamMemberRole copied onto the Coverage Rep team row.
     */
    public static final String ROLE_SALES = 'Sales';
    /**
     * @description AssignmentType__c that marks a team row as temporary coverage.
     */
    public static final String ASSIGNMENT_TEMPORARY = 'Temporary Assignment';
    /**
     * @description Edit access written on team rows the Coverage Rep should update.
     */
    public static final String ACCESS_EDIT = 'Edit';
    /**
     * @description Read access used when the Requester does not own the account.
     */
    public static final String ACCESS_READ = 'Read';
    private static final String FIELD_ACCOUNT_ID = 'AccountId';
    private static final String FIELD_OPPORTUNITY_ID = 'OpportunityId';
    private static final String FIELD_USER_ID = 'UserId';
    private static final String FIELD_TEAM_ROLE = 'TeamMemberRole';
    private static final String FIELD_ASSIGNMENT_TYPE = 'AssignmentType__c';
    private static final String FIELD_EXPIRY = 'ExpiryDate__c';
    private static final String FIELD_OPPORTUNITY_ACCESS = 'OpportunityAccessLevel';
    private static final String FIELD_ACCOUNT_ACCESS = 'AccountAccessLevel';
    private static final String FIELD_CASE_ACCESS = 'CaseAccessLevel';
    private static final String FIELD_TERRITORY = 'TerritoryCode__c';
    private static final String FIELD_CATEGORY_CODE = 'SalesCategoryCode__c';
    private static final String FIELD_CATEGORY_DESCRIPTION = 'SalesCategoryDescription__c';

    /**
     * @description Every grant work type. Finalize uses this set.
     */
    public static final Set<String> GRANT_TYPES = new Set<String>{
        ACCOUNT_TEAM, OPP_TEAM, JUNCTION_ACCOUNT, JUNCTION_OPP
    };
    /**
     * @description Every revoke work type. Finalize uses this set.
     * GC-3482 includes the handback marker and the four owner-reassignment types.
     * Expired and the revoke email wait until none of these rows are Pending or Error.
     */
    public static final Set<String> REVOKE_TYPES = new Set<String>{
        DELETE_ACCOUNT_TEAM, DELETE_OPP_TEAM, DRAFT_HANDBACK,
        REASSIGN_OPPORTUNITY, REASSIGN_TASK, REASSIGN_EVENT, REASSIGN_CONTACT
    };

    /**
     * @description Frozen account and opportunity Ids for one exception.
     */
    public class PlanSnapshot {
        /**
         * @description TemporaryAccessException__c Id.
         */
        public Id coveredExceptionId;
        /**
         * @description Grant or Revoke.
         */
        public String pipelineOperation;
        /**
         * @description Sorted Account Ids from the Requester's team and ownership.
         */
        public List<Id> accountIdList = new List<Id>();
        /**
         * @description Sorted Opportunity Ids from the Requester's team and ownership.
         */
        public List<Id> opportunityIdList = new List<Id>();
    }

    /**
     * @description Pending and Error counts used by the dispatcher for one exception.
     */
    private class WorkState {
        Integer pendingCount = 0;
        Integer errorCount = 0;
        Set<String> pendingTypes = new Set<String>();
    }

    /**
     * @description Builds the account and opportunity book from the Requester's team rows and owned records.
     * @param exceptionId TemporaryAccessException__c Id.
     * @return Sorted plan used by the creation iterator.
     */
    public static PlanSnapshot buildPlan(Id exceptionId) {
        TemporaryAccessException__c header = TAEWorkItemSelector.selectTae(exceptionId);
        if (header == null) {
            throw TAEWorkItemException.create('TAE not found: ' + exceptionId);
        }
        PlanSnapshot snapshot = new PlanSnapshot();
        snapshot.coveredExceptionId = header.Id;
        snapshot.pipelineOperation = header.ProcessingOperation__c;
        Set<Id> accountIdSet = new Set<Id>();
        Set<Id> opportunityIdSet = new Set<Id>();
        for (AccountTeamMember row : TAEWorkItemSelector.requesterAccountTeams(header.Requester__c)) {
            accountIdSet.add(row.AccountId);
        }
        for (OpportunityTeamMember row : TAEWorkItemSelector.requesterOpportunityTeams(header.Requester__c)) {
            opportunityIdSet.add(row.OpportunityId);
        }
        for (Account row : TAEWorkItemSelector.requesterOwnedAccounts(header.Requester__c)) {
            accountIdSet.add(row.Id);
        }
        for (Opportunity row : TAEWorkItemSelector.requesterOwnedOpportunities(header.Requester__c)) {
            opportunityIdSet.add(row.Id);
        }
        snapshot.accountIdList.addAll(accountIdSet);
        snapshot.opportunityIdList.addAll(opportunityIdSet);
        snapshot.accountIdList.sort();
        snapshot.opportunityIdList.sort();
        return snapshot;
    }

    /**
     * @description Builds one in-memory work item. ErrorMessage__c and ProcessedDate__c stay blank.
     * @param exceptionId TemporaryAccessException__c Id.
     * @param workType Work type API value.
     * @param recordId Account or Opportunity Id stored on RecordId__c.
     * @return A Pending draft with CompositeKey__c set. Not inserted.
     */
    public static TAEProcessingWorkItem__c draft(
        Id exceptionId,
        String workType,
        Id recordId
    ) {
        TAEProcessingWorkItem__c draftItem = new TAEProcessingWorkItem__c(
            TemporaryAccessException__c = exceptionId,
            WorkType__c = workType,
            RecordId__c = String.valueOf(recordId),
            Status__c = STATUS_PENDING,
            CompositeKey__c = exceptionId + '|' + workType + '|' + recordId
        );
        return draftItem;
    }

    /**
     * @description Moves an eligible exception to Processing and records Grant or Revoke. Does not create work items.
     * @param header Approved exception starting today, or Active exception ending today.
     */
    public static void markForProcessing(TemporaryAccessException__c header) {
        String processingOperation;
        if (header.Status__c == HEADER_APPROVED && header.StartDate__c == Date.today()) {
            processingOperation = OP_GRANT;
        } else if (header.Status__c == HEADER_ACTIVE && header.EndDate__c == Date.today()) {
            processingOperation = OP_REVOKE;
        }
        if (processingOperation != null) {
            Id headerId = header.Id;
            Database.update(
                new TemporaryAccessException__c(
                    Id = headerId,
                    Status__c = HEADER_PROCESSING,
                    ProcessingOperation__c = processingOperation,
                    WorkItemsCreated__c = false
                ),
                AccessLevel.SYSTEM_MODE
            );
            Logger.info(
                'TAEWorkItemService.markForProcessing: exceptionId=' + header.Id +
                ' operation=' + processingOperation
            );
        }
    }

    /**
     * @description Starts at most one pipeline when no creation, grant, revoke, handback, or cleanup job is already queued.
     * Error-only exceptions are skipped so a later exception can still run.
     * Called from the orchestrator finish method. An operator can call it when a Processing exception has no running child job.
     */
    public static void startNextTaePipeline() {
        if (TAEWorkItemSelector.hasActivePipelineJob()) {
            Logger.info('TAEWorkItemService.startNextTaePipeline: a pipeline job is already active');
        } else {
            Logger.info('TAEWorkItemService.startNextTaePipeline: choosing the next job');
            continuePipeline();
        }
    }

    /**
     * @description Continues the pipeline after a worker or cleanup finish method.
     * The active-job guard is skipped because the job that just finished is still visible as Processing.
     */
    public static void resumeAfterPipelineFinish() {
        Logger.info('TAEWorkItemService.resumeAfterPipelineFinish: choosing the next job');
        continuePipeline();
    }

    /**
     * @description Prefers leftover Done-row cleanup, then walks Processing exceptions until one job is submitted.
     */
    private static void continuePipeline() {
        Boolean cleanupStarted = startCleanupIfPresent();
        if (cleanupStarted) {
            Logger.info('TAEWorkItemService.continuePipeline: cleanup submitted before the Processing walk');
        } else {
            walkProcessingExceptions();
        }
    }

    /**
     * @description Submits creation or the next phase for the oldest exception that still needs work.
     * An exception that only has Error rows is left in Processing so the walk can reach the next exception.
     */
    private static void walkProcessingExceptions() {
        List<TemporaryAccessException__c> headers = TAEWorkItemSelector.selectProcessingTaes();
        if (headers.isEmpty()) {
            Logger.info('TAEWorkItemService.walkProcessingExceptions: no Processing exceptions');
        } else {
            Set<Id> exceptionIds = new Map<Id, TemporaryAccessException__c>(headers).keySet();
            Map<Id, WorkState> states = loadWorkStates(exceptionIds);
            Boolean handedOff = false;
            for (TemporaryAccessException__c header : headers) {
                handedOff = handOffOneException(header, states);
                if (handedOff) {
                    break;
                }
            }
            if (!handedOff) {
                Logger.info('TAEWorkItemService.walkProcessingExceptions: no exception was ready to continue');
            }
        }
    }

    /**
     * @description Creates work items, resumes the next phase, or finalizes one exception.
     * @param header Processing exception from the dispatcher query.
     * @param states Pending and Error totals keyed by exception Id.
     * @return True when a batch was submitted and the walk must stop.
     */
    private static Boolean handOffOneException(
        TemporaryAccessException__c header,
        Map<Id, WorkState> states
    ) {
        WorkState state = states.containsKey(header.Id) ? states.get(header.Id) : new WorkState();
        Boolean handedOff = false;
        if (header.WorkItemsCreated__c != true) {
            submitCreation(header.Id);
            handedOff = true;
        } else {
            String phase = nextPendingPhase(header.ProcessingOperation__c, state.pendingTypes);
            if (phase != null) {
                submitWorker(header.Id, header.ProcessingOperation__c, phase);
                handedOff = true;
            } else if (state.errorCount == 0) {
                finalizeTae(header.Id, header.ProcessingOperation__c);
                handedOff = startCleanupIfPresent();
            }
        }
        return handedOff;
    }

    /**
     * @description Submits the creation batch for one exception. Called only from the dispatcher walk.
     * @param exceptionId TemporaryAccessException__c that does not yet have work items.
     */
    private static void submitCreation(Id exceptionId) {
        Id jobId = Database.executeBatch(new TAEWorkItemCreationBatch(exceptionId), WORKER_SCOPE);
        Logger.info(
            'TAEWorkItemService.submitCreation: exceptionId=' + exceptionId + ' jobId=' + jobId
        );
    }

    /**
     * @description Submits the grant or revoke worker for one phase. Called only from the dispatcher walk.
     * GC-3482: a Pending DRAFT_HANDBACK phase starts TAEHandbackDraftBatch at the opportunity
     * draft. Each draft job then chains the next object. Reassign phases start TAERevokeWorkBatch.
     * One child job is queued. The 10,000-row DML limit applies per execute, so objects are not combined.
     * @param exceptionId TemporaryAccessException__c being processed.
     * @param operation Grant or Revoke.
     * @param phase Next Pending phase name.
     */
    private static void submitWorker(Id exceptionId, String operation, String phase) {
        Id jobId;
        if (operation == OP_GRANT) {
            jobId = Database.executeBatch(
                new TAEGrantWorkBatch(exceptionId, phase),
                WORKER_SCOPE
            );
        } else if (phase == DRAFT_HANDBACK) {
            jobId = Database.executeBatch(
                new TAEHandbackDraftBatch(exceptionId, REASSIGN_OPPORTUNITY),
                WORKER_SCOPE
            );
        } else {
            jobId = Database.executeBatch(
                new TAERevokeWorkBatch(exceptionId, phase),
                WORKER_SCOPE
            );
        }
        Logger.info(
            'TAEWorkItemService.submitWorker: exceptionId=' + exceptionId +
            ' operation=' + operation + ' phase=' + phase + ' jobId=' + jobId
        );
    }

    /**
     * @description Starts cleanup for the oldest Active or Expired exception that still has Done work items.
     * @return True when a cleanup batch was submitted.
     */
    private static Boolean startCleanupIfPresent() {
        Id exceptionId = TAEWorkItemSelector.selectTaeIdWithDoneItemsToClean();
        Boolean started = false;
        if (exceptionId != null) {
            Id jobId = Database.executeBatch(
                new TAEWorkItemCleanupBatch(exceptionId),
                CLEANUP_SCOPE
            );
            Logger.info(
                'TAEWorkItemService.startCleanupIfPresent: exceptionId=' + exceptionId +
                ' jobId=' + jobId
            );
            started = true;
        }
        return started;
    }

    /**
     * @description Aggregates Pending and Error work items for the dispatcher.
     * @param exceptionIds Processing exception Ids.
     * @return Exception Id to pending types and error count.
     */
    private static Map<Id, WorkState> loadWorkStates(Set<Id> exceptionIds) {
        Map<Id, WorkState> result = new Map<Id, WorkState>();
        for (AggregateResult row : [
            SELECT TemporaryAccessException__c taeId, Status__c status,
                WorkType__c workType, COUNT(Id) rowCount
            FROM TAEProcessingWorkItem__c
            WHERE TemporaryAccessException__c IN :exceptionIds
              AND Status__c IN ('Pending', 'Error')
            WITH SYSTEM_MODE
            GROUP BY TemporaryAccessException__c, Status__c, WorkType__c
        ]) {
            Id exceptionId = (Id) row.get('taeId');
            if (!result.containsKey(exceptionId)) {
                result.put(exceptionId, new WorkState());
            }
            WorkState state = result.get(exceptionId);
            Integer countValue = Integer.valueOf(String.valueOf(row.get('rowCount')));
            if ((String) row.get('status') == STATUS_PENDING) {
                state.pendingCount += countValue;
                state.pendingTypes.add((String) row.get('workType'));
            } else {
                state.errorCount += countValue;
            }
        }
        return result;
    }

    /**
     * @description Next grant or revoke phase that still has Pending rows.
     * GC-3482 revoke order is fixed: delete account team, delete opportunity team,
     * draft handback, reassign open opportunities, incomplete tasks, upcoming events, then contacts.
     * The first type in that order that still has Pending rows is the next job.
     * @param operation Grant or Revoke.
     * @param pendingTypes Work types that still have Pending rows.
     * @return Phase name, or null when this exception has no Pending work left.
     */
    public static String nextPendingPhase(String operation, Set<String> pendingTypes) {
        String phaseName = null;
        if (operation == OP_GRANT) {
            if (pendingTypes.contains(ACCOUNT_TEAM)) {
                phaseName = ACCOUNT_TEAM;
            } else if (pendingTypes.contains(OPP_TEAM)) {
                phaseName = OPP_TEAM;
            } else if (
                pendingTypes.contains(JUNCTION_ACCOUNT) || pendingTypes.contains(JUNCTION_OPP)
            ) {
                phaseName = PHASE_JUNCTION;
            }
        } else if (pendingTypes.contains(DELETE_ACCOUNT_TEAM)) {
            phaseName = DELETE_ACCOUNT_TEAM;
        } else if (pendingTypes.contains(DELETE_OPP_TEAM)) {
            phaseName = DELETE_OPP_TEAM;
        } else if (pendingTypes.contains(DRAFT_HANDBACK)) {
            phaseName = DRAFT_HANDBACK;
        } else if (pendingTypes.contains(REASSIGN_OPPORTUNITY)) {
            phaseName = REASSIGN_OPPORTUNITY;
        } else if (pendingTypes.contains(REASSIGN_TASK)) {
            phaseName = REASSIGN_TASK;
        } else if (pendingTypes.contains(REASSIGN_EVENT)) {
            phaseName = REASSIGN_EVENT;
        } else if (pendingTypes.contains(REASSIGN_CONTACT)) {
            phaseName = REASSIGN_CONTACT;
        }
        return phaseName;
    }

    /**
     * @description Pending work types for one exception.
     * GC-3482 uses this after a reassign phase so finish() can queue only the next type that still has rows.
     * @param exceptionId TemporaryAccessException__c Id.
     * @return Work type API values that still have Pending rows.
     */
    public static Set<String> pendingWorkTypes(Id exceptionId) {
        Set<String> pendingTypes = new Set<String>();
        for (AggregateResult row : [
            SELECT WorkType__c workType
            FROM TAEProcessingWorkItem__c
            WHERE TemporaryAccessException__c = :exceptionId
              AND Status__c = :STATUS_PENDING
            WITH SYSTEM_MODE
            GROUP BY WorkType__c
        ]) {
            pendingTypes.add((String) row.get('workType'));
        }
        return pendingTypes;
    }

    /**
     * @description Inserts Coverage Rep Account Team Members for one chunk. Existing rows are Skipped.
     * @param items Pending ACCOUNT_TEAM work items.
     */
    public static void processAccountGrant(List<TAEProcessingWorkItem__c> items) {
        TemporaryAccessException__c header = requireTae(items);
        Set<Id> accountIdSet = recordIds(items);
        Map<Id, AccountTeamMember> existing =
            TAEWorkItemSelector.accountTeamsByAccount(accountIdSet, header.CoverageRep__c);
        Map<Id, AccountTeamMember> requester =
            TAEWorkItemSelector.requesterAccountTeamsByAccount(accountIdSet, header.Requester__c);
        Set<Id> owned = TAEWorkItemSelector.requesterOwnedAccountIds(accountIdSet, header.Requester__c);
        List<SObject> inserts = new List<SObject>();
        List<TAEProcessingWorkItem__c> insertItems = new List<TAEProcessingWorkItem__c>();
        List<TAEProcessingWorkItem__c> updates = new List<TAEProcessingWorkItem__c>();
        for (TAEProcessingWorkItem__c item : items) {
            Id accountId = (Id) item.RecordId__c;
            if (existing.containsKey(accountId)) {
                mark(item, STATUS_SKIPPED, 'Coverage Rep is already on this account team.');
                updates.add(item);
            } else {
                CoverageAccountRequest request = new CoverageAccountRequest();
                request.coverageHeader = header;
                request.coverageAccountId = accountId;
                request.requesterTeam = requester.get(accountId);
                request.ownedIds = owned;
                inserts.add(buildCoverageAccountTeam(request));
                insertItems.add(item);
            }
        }
        applyInsertResults(inserts, insertItems, updates);
    }

    /**
     * @description Values needed to build one Coverage Rep Account Team Member.
     */
    private class CoverageAccountRequest {
        TemporaryAccessException__c coverageHeader;
        Id coverageAccountId;
        AccountTeamMember requesterTeam;
        Set<Id> ownedIds;
    }

    /**
     * @description Builds the Coverage Rep Account Team Member, copying access from the Requester when needed.
     * @param request Header, account, requester team row, and owned-account ids.
     * @return Unsaved Account Team Member.
     */
    private static SObject buildCoverageAccountTeam(CoverageAccountRequest request) {
        TemporaryAccessException__c header = request.coverageHeader;
        Id accountId = request.coverageAccountId;
        AccountTeamMember source = request.requesterTeam;
        String accountAccess = ACCESS_READ;
        String caseAccess = ACCESS_READ;
        if (request.ownedIds.contains(accountId)) {
            accountAccess = ACCESS_EDIT;
        } else if (source != null) {
            accountAccess = source.AccountAccessLevel;
            caseAccess = source.CaseAccessLevel;
        }
        SObject teamMember = AccountTeamMember.SObjectType.newSObject();
        teamMember.put(FIELD_ACCOUNT_ID, accountId);
        teamMember.put(FIELD_USER_ID, header.CoverageRep__c);
        teamMember.put(FIELD_TEAM_ROLE, ROLE_SALES);
        teamMember.put(FIELD_ASSIGNMENT_TYPE, ASSIGNMENT_TEMPORARY);
        teamMember.put(FIELD_EXPIRY, header.EndDate__c);
        teamMember.put(FIELD_OPPORTUNITY_ACCESS, ACCESS_EDIT);
        teamMember.put(FIELD_ACCOUNT_ACCESS, accountAccess);
        teamMember.put(FIELD_CASE_ACCESS, caseAccess);
        if (source != null) {
            teamMember.put(FIELD_TERRITORY, source.TerritoryCode__c);
            teamMember.put(FIELD_CATEGORY_CODE, source.SalesCategoryCode__c);
            teamMember.put(FIELD_CATEGORY_DESCRIPTION, source.SalesCategoryDescription__c);
        }
        return teamMember;
    }

    /**
     * @description Inserts Coverage Rep Opportunity Team Members for one chunk. Existing rows are Skipped.
     * @param items Pending OPP_TEAM work items.
     */
    public static void processOpportunityGrant(List<TAEProcessingWorkItem__c> items) {
        TemporaryAccessException__c header = requireTae(items);
        Set<Id> opportunityIdSet = recordIds(items);
        Map<Id, OpportunityTeamMember> existing =
            TAEWorkItemSelector.opportunityTeamsByOpportunity(opportunityIdSet, header.CoverageRep__c);
        List<SObject> inserts = new List<SObject>();
        List<TAEProcessingWorkItem__c> insertItems = new List<TAEProcessingWorkItem__c>();
        List<TAEProcessingWorkItem__c> updates = new List<TAEProcessingWorkItem__c>();
        for (TAEProcessingWorkItem__c item : items) {
            Id opportunityId = (Id) item.RecordId__c;
            if (existing.containsKey(opportunityId)) {
                mark(item, STATUS_SKIPPED, 'Coverage Rep is already on this opportunity team.');
                updates.add(item);
                continue;
            }
            SObject otm = OpportunityTeamMember.SObjectType.newSObject();
            otm.put(FIELD_OPPORTUNITY_ID, opportunityId);
            otm.put(FIELD_USER_ID, header.CoverageRep__c);
            otm.put(FIELD_TEAM_ROLE, ROLE_SALES);
            otm.put(FIELD_ASSIGNMENT_TYPE, ASSIGNMENT_TEMPORARY);
            otm.put(FIELD_EXPIRY, header.EndDate__c);
            otm.put(FIELD_OPPORTUNITY_ACCESS, ACCESS_EDIT);
            inserts.add(otm);
            insertItems.add(item);
        }
        applyInsertResults(inserts, insertItems, updates);
    }

    /**
     * @description Inserts TAE_AssignedRecord__c rows for one mixed account and opportunity chunk.
     * @param items Pending JUNCTION_ACCOUNT and JUNCTION_OPP work items.
     */
    public static void processJunctionGrant(List<TAEProcessingWorkItem__c> items) {
        TemporaryAccessException__c header = requireTae(items);
        Set<Id> accountIdSet = new Set<Id>();
        Set<Id> opportunityIdSet = new Set<Id>();
        for (TAEProcessingWorkItem__c item : items) {
            if (item.WorkType__c == JUNCTION_ACCOUNT) {
                accountIdSet.add((Id) item.RecordId__c);
            } else {
                opportunityIdSet.add((Id) item.RecordId__c);
            }
        }
        Set<Id> existingAccounts = TAEWorkItemSelector.assignedAccountIds(header.Id, accountIdSet);
        Set<Id> existingOpps = TAEWorkItemSelector.assignedOpportunityIds(header.Id, opportunityIdSet);
        List<SObject> inserts = new List<SObject>();
        List<TAEProcessingWorkItem__c> insertItems = new List<TAEProcessingWorkItem__c>();
        List<TAEProcessingWorkItem__c> updates = new List<TAEProcessingWorkItem__c>();
        for (TAEProcessingWorkItem__c item : items) {
            Id recordId = (Id) item.RecordId__c;
            Boolean exists = item.WorkType__c == JUNCTION_ACCOUNT
                ? existingAccounts.contains(recordId) : existingOpps.contains(recordId);
            if (exists) {
                String skipReason = item.WorkType__c == JUNCTION_ACCOUNT
                    ? 'This account is already recorded on the request.'
                    : 'This opportunity is already recorded on the request.';
                mark(item, STATUS_SKIPPED, skipReason);
                updates.add(item);
                continue;
            }
            TAE_AssignedRecord__c row = new TAE_AssignedRecord__c(
                TemporaryAccessException__c = header.Id
            );
            if (item.WorkType__c == JUNCTION_ACCOUNT) {
                row.Account__c = recordId;
            } else {
                row.Opportunity__c = recordId;
            }
            inserts.add(row);
            insertItems.add(item);
        }
        applyInsertResults(inserts, insertItems, updates);
    }

    /**
     * @description Deletes temporary Sales Account Team Members. Missing or other rows are Skipped.
     * @param items Pending DELETE_ACCOUNT_TEAM work items.
     */
    public static void processAccountTeamDelete(List<TAEProcessingWorkItem__c> items) {
        TemporaryAccessException__c header = requireTae(items);
        Map<Id, AccountTeamMember> rows =
            TAEWorkItemSelector.accountTeamsByAccount(recordIds(items), header.CoverageRep__c);
        Map<Id, SObject> existing = new Map<Id, SObject>();
        for (Id key : rows.keySet()) {
            existing.put(key, rows.get(key));
        }
        deleteTemporaryMembers(items, existing);
    }

    /**
     * @description Deletes temporary Sales Opportunity Team Members. Missing or other rows are Skipped.
     * @param items Pending DELETE_OPP_TEAM work items.
     */
    public static void processOpportunityTeamDelete(List<TAEProcessingWorkItem__c> items) {
        TemporaryAccessException__c header = requireTae(items);
        Map<Id, OpportunityTeamMember> rows =
            TAEWorkItemSelector.opportunityTeamsByOpportunity(recordIds(items), header.CoverageRep__c);
        Map<Id, SObject> existing = new Map<Id, SObject>();
        for (Id key : rows.keySet()) {
            existing.put(key, rows.get(key));
        }
        deleteTemporaryMembers(items, existing);
    }

    /**
     * @description GC-3482. Sets OwnerId to the Requester for one chunk of one object type.
     * Scope is at most 500 work items. One Database.update writes the owners. A second update
     * writes Done or Error on the work items. allOrNone is false, so one locked record becomes
     * Error and the rest of the chunk can still succeed. Created By and every other field are left as they are.
     * A chunk whose DML rows pass the 4,000 guard is thrown back by persistItemUpdates so it rolls back
     * before the platform 10,000-row limit.
     * @param items Pending REASSIGN_OPPORTUNITY, REASSIGN_TASK, REASSIGN_EVENT, or REASSIGN_CONTACT rows.
     */
    public static void processOwnerReassign(List<TAEProcessingWorkItem__c> items) {
        TemporaryAccessException__c header = requireTae(items);
        Schema.SObjectType targetType = reassignTargetType(items[0].WorkType__c);
        List<SObject> ownerUpdates = new List<SObject>();
        List<TAEProcessingWorkItem__c> ownerItems = new List<TAEProcessingWorkItem__c>();
        List<TAEProcessingWorkItem__c> updates = new List<TAEProcessingWorkItem__c>();
        for (TAEProcessingWorkItem__c item : items) {
            Id recordId = (Id) item.RecordId__c;
            // The handback marker stores the exception Id. It is not an opportunity, task, event, or contact.
            if (recordId == header.Id) {
                mark(
                    item, STATUS_SKIPPED,
                    'This row is the handback marker, not a business record to reassign.'
                );
                updates.add(item);
            } else {
                SObject row = targetType.newSObject(recordId);
                row.put('OwnerId', header.Requester__c);
                ownerUpdates.add(row);
                ownerItems.add(item);
            }
        }
        if (!ownerUpdates.isEmpty()) {
            List<Database.SaveResult> results =
                Database.update(ownerUpdates, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < results.size(); i++) {
                String platformMessage = results[i].isSuccess() ? null : errors(results[i].getErrors());
                String status = results[i].isSuccess() ? STATUS_DONE : STATUS_ERROR;
                mark(ownerItems[i], status, ownerReason(status, platformMessage));
                updates.add(ownerItems[i]);
            }
        }
        persistItemUpdates(updates);
    }

    /**
     * @description GC-3482. Object whose OwnerId this work type updates.
     * Opportunity is the default because REASSIGN_OPPORTUNITY is the first reassign phase.
     * @param workType REASSIGN_OPPORTUNITY, REASSIGN_TASK, REASSIGN_EVENT, or REASSIGN_CONTACT.
     * @return Opportunity, Task, Event, or Contact.
     */
    private static Schema.SObjectType reassignTargetType(String workType) {
        Schema.SObjectType targetType = Opportunity.SObjectType;
        if (workType == REASSIGN_TASK) {
            targetType = Task.SObjectType;
        } else if (workType == REASSIGN_EVENT) {
            targetType = Event.SObjectType;
        } else if (workType == REASSIGN_CONTACT) {
            targetType = Contact.SObjectType;
        }
        return targetType;
    }

    /**
     * @description Deletes Sales Temporary Assignment rows and writes Done, Error, or Skipped on the work items.
     * @param items Pending delete work items.
     * @param existing Team rows keyed by Account or Opportunity Id.
     */
    private static void deleteTemporaryMembers(
        List<TAEProcessingWorkItem__c> items,
        Map<Id, SObject> existing
    ) {
        List<SObject> deletes = new List<SObject>();
        List<TAEProcessingWorkItem__c> deleteItems = new List<TAEProcessingWorkItem__c>();
        List<TAEProcessingWorkItem__c> updates = new List<TAEProcessingWorkItem__c>();
        for (TAEProcessingWorkItem__c item : items) {
            SObject member = existing.get((Id) item.RecordId__c);
            String skipReason = deleteSkipReason(member);
            if (skipReason != null) {
                mark(item, STATUS_SKIPPED, skipReason);
                updates.add(item);
            } else {
                deletes.add(member);
                deleteItems.add(item);
            }
        }
        if (!deletes.isEmpty()) {
            List<Database.DeleteResult> results =
                Database.delete(deletes, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < results.size(); i++) {
                String platformMessage = results[i].isSuccess() ? null : errors(results[i].getErrors());
                String status = results[i].isSuccess() ? STATUS_DONE : STATUS_ERROR;
                mark(
                    deleteItems[i], status,
                    teamChangeReason(deleteItems[i].WorkType__c, status, platformMessage)
                );
                updates.add(deleteItems[i]);
            }
        }
        persistItemUpdates(updates);
    }

    /**
     * @description Maps each SaveResult to Done or Error and writes the work-item updates.
     * @param inserts Rows passed to Database.insert.
     * @param insertItems Work items in the same order as inserts.
     * @param updates Skipped items plus the items updated from SaveResult.
     */
    private static void applyInsertResults(
        List<SObject> inserts,
        List<TAEProcessingWorkItem__c> insertItems,
        List<TAEProcessingWorkItem__c> updates
    ) {
        if (!inserts.isEmpty()) {
            List<Database.SaveResult> results =
                Database.insert(inserts, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < results.size(); i++) {
                String platformMessage = results[i].isSuccess() ? null : errors(results[i].getErrors());
                String status = results[i].isSuccess() ? STATUS_DONE : STATUS_ERROR;
                mark(
                    insertItems[i], status,
                    teamChangeReason(insertItems[i].WorkType__c, status, platformMessage)
                );
                updates.add(insertItems[i]);
            }
        }
        persistItemUpdates(updates);
    }

    /**
     * @description Updates work-item status and throws when the chunk passed the DML-row guard.
     * @param updates Work items whose Status__c, ErrorMessage__c, and ProcessedDate__c were set.
     */
    private static void persistItemUpdates(List<TAEProcessingWorkItem__c> updates) {
        if (!updates.isEmpty()) {
            Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        }
        if (Limits.getDmlRows() > MAX_DML_ROWS) {
            throw TAEWorkItemException.create(
                'TAE worker exceeded DML guard: ' + Limits.getDmlRows()
            );
        }
    }

    /**
     * @description Loads the Processing exception for a worker chunk.
     * @param items Work items in the current execute scope.
     * @return The exception header.
     */
    private static TemporaryAccessException__c requireTae(
        List<TAEProcessingWorkItem__c> items
    ) {
        if (items == null || items.isEmpty()) {
            throw new TAEWorkItemException('Work-item scope is empty.');
        }
        TemporaryAccessException__c tae =
            TAEWorkItemSelector.selectTae(items[0].TemporaryAccessException__c);
        if (tae == null || tae.Status__c != HEADER_PROCESSING) {
            throw new TAEWorkItemException('TAE is missing or not Processing.');
        }
        return tae;
    }

    /**
     * @description Account or Opportunity Ids stored on RecordId__c.
     * @param items Work items in the current execute scope.
     * @return Distinct record Ids.
     */
    private static Set<Id> recordIds(List<TAEProcessingWorkItem__c> items) {
        Set<Id> result = new Set<Id>();
        for (TAEProcessingWorkItem__c item : items) {
            result.add((Id) item.RecordId__c);
        }
        return result;
    }

    /**
     * @description Sets status, outcome sentence, and processed time on one work item. Does not DML.
     * GC-3482. ErrorMessage__c holds the Done, Skipped, or Error sentence. On Error the sentence
     * includes the platform message. The field is cleared when the row returns to Pending.
     * @param item Work item to update in memory.
     * @param status Pending, Done, Error, or Skipped.
     * @param message Outcome sentence stored on ErrorMessage__c.
     */
    private static void mark(
        TAEProcessingWorkItem__c item,
        String status,
        String message
    ) {
        item.Status__c = status;
        item.ErrorMessage__c = trimToLongText(message);
        item.ProcessedDate__c = System.now();
    }

    /**
     * @description GC-3482. Skip sentence for a team delete, or null when the row should be deleted.
     * @param member Coverage Rep team row, or null when none exists.
     * @return The skip reason, or null when the row is a temporary Sales assignment.
     */
    private static String deleteSkipReason(SObject member) {
        String skipReason = null;
        if (member == null) {
            skipReason = 'No Coverage Rep team row was found on this record.';
        } else if ((String) member.get(FIELD_TEAM_ROLE) != ROLE_SALES) {
            skipReason = 'Coverage Rep team role is not Sales, so the row was left in place.';
        } else if ((String) member.get(FIELD_ASSIGNMENT_TYPE) != ASSIGNMENT_TEMPORARY) {
            skipReason = 'Assignment type is not Temporary Assignment, so the row was left in place.';
        }
        return skipReason;
    }

    /**
     * @description GC-3482. Done or Error sentence for a grant insert or a team delete.
     * @param workType Work type on the work item.
     * @param status Done or Error.
     * @param platformMessage Platform error text, or null on success.
     * @return Sentence stored on ErrorMessage__c.
     */
    private static String teamChangeReason(String workType, String status, String platformMessage) {
        String reason;
        if (status == STATUS_ERROR) {
            String prefix = (workType == DELETE_ACCOUNT_TEAM || workType == DELETE_OPP_TEAM)
                ? 'Team row was not removed.'
                : 'Record was not created.';
            reason = withPlatformDetail(prefix, platformMessage);
        } else if (workType == ACCOUNT_TEAM) {
            reason = 'Coverage Rep was added to the account team.';
        } else if (workType == OPP_TEAM) {
            reason = 'Coverage Rep was added to the opportunity team.';
        } else if (workType == JUNCTION_ACCOUNT) {
            reason = 'This account was recorded on the request.';
        } else if (workType == JUNCTION_OPP) {
            reason = 'This opportunity was recorded on the request.';
        } else if (workType == DELETE_ACCOUNT_TEAM) {
            reason = 'Temporary Sales account team row was removed.';
        } else {
            reason = 'Temporary Sales opportunity team row was removed.';
        }
        return reason;
    }

    /**
     * @description GC-3482. Done or Error sentence for an owner handback.
     * @param status Done or Error.
     * @param platformMessage Platform error text, or null on success.
     * @return Sentence stored on ErrorMessage__c.
     */
    private static String ownerReason(String status, String platformMessage) {
        String reason = 'Owner was set back to the Requester.';
        if (status == STATUS_ERROR) {
            reason = withPlatformDetail('Owner was not changed.', platformMessage);
        }
        return reason;
    }

    /**
     * @description Appends the platform error after the short reason sentence.
     * @param sentence Short reason.
     * @param platformMessage Platform error text.
     * @return Combined reason.
     */
    private static String withPlatformDetail(String sentence, String platformMessage) {
        String reason = sentence;
        if (String.isNotBlank(platformMessage)) {
            reason = sentence + ' ' + platformMessage;
        }
        return reason;
    }

    /**
     * @description Keeps a reason inside the long-text field length.
     * @param value Reason text.
     * @return Value capped at 32,768 characters.
     */
    private static String trimToLongText(String value) {
        String trimmed = value;
        if (value != null && value.length() > 32768) {
            trimmed = value.substring(0, 32768);
        }
        return trimmed;
    }

    /**
     * @description Joins Database.Error status codes and messages, capped at the long-text limit.
     * @param values Errors from one SaveResult or DeleteResult.
     * @return A single message stored on ErrorMessage__c.
     */
    private static String errors(Database.Error[] values) {
        List<String> messages = new List<String>();
        for (Database.Error value : values) {
            messages.add(value.getStatusCode() + ': ' + value.getMessage());
        }
        String result = String.join(messages, ' | ');
        String trimmed = result;
        if (result.length() > 32768) {
            trimmed = result.substring(0, 32768);
        }
        return trimmed;
    }

    /**
     * @description True when Pending or Error rows remain for the given work types.
     * @param exceptionId TemporaryAccessException__c Id.
     * @param types Work types for the operation being finalized.
     * @return Whether finalize must wait.
     */
    public static Boolean hasOpenItems(Id exceptionId, Set<String> types) {
        Integer openCount = TAEWorkItemSelector.countByStatusAndTypes(
            exceptionId, new Set<String>{ STATUS_PENDING, STATUS_ERROR }, types
        );
        Boolean hasOpen = openCount > 0;
        return hasOpen;
    }

    /**
     * @description True when Error rows remain for the given work types.
     * @param exceptionId TemporaryAccessException__c Id.
     * @param types Work types for the phase that just finished.
     * @return Whether the worker must stop chaining.
     */
    public static Boolean hasErrors(Id exceptionId, Set<String> types) {
        Integer errorRowCount = TAEWorkItemSelector.countByStatusAndTypes(
            exceptionId, new Set<String>{ STATUS_ERROR }, types
        );
        Boolean foundErrors = errorRowCount > 0;
        return foundErrors;
    }

    /**
     * @description Sets Active or Expired and sends one email when no Pending or Error rows remain.
     * GC-3482: a revoke is Expired only after team deletes, the handback marker, and all four
     * owner-reassignment types are Done or Skipped. One Error row keeps the request Processing.
     * GCL-95 and GCL-103 run only when Created By is on the Life Sciences Sales profile.
     * Healthcare requests still use TAEWorkItemEmailService and the existing handback.
     * @param exceptionId TemporaryAccessException__c Id.
     * @param operation Grant or Revoke.
     */
    public static void finalizeTae(Id exceptionId, String operation) {
        Set<String> types = operation == OP_GRANT ? GRANT_TYPES : REVOKE_TYPES;
        if (!hasOpenItems(exceptionId, types)) {
            String nextStatus = HEADER_EXPIRED;
            if (operation == OP_GRANT) {
                nextStatus = HEADER_ACTIVE;
            }
            Set<Id> lifeScienceIds = LSTemporaryAccessExceptionEmailService.filterLifeScienceRequestIds(
                new Set<Id>{ exceptionId }
            );
            Boolean isLifeScience = lifeScienceIds.contains(exceptionId);
            if (isLifeScience && operation != OP_GRANT) {
                applyLifeScienceHandback(exceptionId, lifeScienceIds);
            }
            LSTemporaryAccessExceptionEmailService.suppressInvocableSend = isLifeScience;
            try {
                Database.update(
                    new TemporaryAccessException__c(
                        Id = exceptionId,
                        Status__c = nextStatus,
                        ProcessingOperation__c = null,
                        WorkItemsCreated__c = false
                    ),
                    AccessLevel.SYSTEM_MODE
                );
            } finally {
                LSTemporaryAccessExceptionEmailService.suppressInvocableSend = false;
            }
            Logger.info(
                'TAEWorkItemService.finalizeTae: exceptionId=' + exceptionId +
                ' status=' + nextStatus +
                ' lifeScience=' + isLifeScience
            );
            if (isLifeScience) {
                sendLifeScienceNotification(exceptionId, operation);
            } else if (operation == OP_GRANT) {
                TAEWorkItemEmailService.sendGrant(exceptionId);
            } else {
                TAEWorkItemEmailService.sendRevoke(exceptionId);
            }
        }
    }

    /**
     * GCL-103. Life Science revoke only. Moves records the Coverage Rep owns on covered
     * accounts back to the Requester, including completed tasks and past events.
     * A failure is logged and does not stop the Healthcare-style work items already finished.
     */
    private static void applyLifeScienceHandback(Id exceptionId, Set<Id> lifeScienceIds) {
        try {
            TemporaryAccessException__c header = TAEWorkItemSelector.selectTae(exceptionId);
            if (header != null) {
                LSTemporaryAccessReassignmentService.reassignOnExpiry(
                    new List<TemporaryAccessException__c>{ header },
                    lifeScienceIds
                );
            }
        } catch (Exception handbackError) {
            Logger.error('TAEWorkItemService.finalizeTae: Life Science reassignment failed', handbackError);
        }
    }

    /**
     * GCL-95. Life Science grant sends Temporary Coverage Access Granted. Life Science revoke
     * sends Temporary Salesforce Access has Expired. Healthcare requests do not use these emails.
     */
    private static void sendLifeScienceNotification(Id exceptionId, String operation) {
        try {
            if (operation == OP_GRANT) {
                LSTemporaryAccessExceptionEmailService.sendCoverageGranted(new List<Id>{ exceptionId });
                return;
            }
            LSTemporaryAccessExceptionEmailService.sendExpired(new List<Id>{ exceptionId });
        } catch (Exception emailError) {
            Logger.error('TAEWorkItemService.finalizeTae: Life Science email failed', emailError);
        }
    }

    /**
     * @description Resets Error work items to Pending so a later run can retry them. Does not start a batch.
     * @param exceptionId TemporaryAccessException__c Id.
     * @return Number of rows reset.
     */
    public static Integer requeueErrors(Id exceptionId) {
        List<TAEProcessingWorkItem__c> rows = [
            SELECT Id, Status__c, ErrorMessage__c, ProcessedDate__c
            FROM TAEProcessingWorkItem__c
            WHERE TemporaryAccessException__c = :exceptionId AND Status__c = :STATUS_ERROR
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
        for (TAEProcessingWorkItem__c row : rows) {
            row.Status__c = STATUS_PENDING;
            row.ErrorMessage__c = null;
            row.ProcessedDate__c = null;
        }
        if (!rows.isEmpty()) {
            Database.update(rows, false, AccessLevel.SYSTEM_MODE);
            Logger.info(
                'TAEWorkItemService.requeueErrors: exceptionId=' + exceptionId +
                ' reset=' + rows.size()
            );
        }
        return rows.size();
    }
}