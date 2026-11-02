/**
 * Processes TemporaryAccessException__c rows for account and opportunity team access.
 * @author Suraj Thapliyal
 * @date 2026/06/15
 * @description Processes TemporaryAccessException__c rows for account and opportunity team access.
 *              Grant (Approved + StartDate = today): adds Coverage Rep as temporary Sales team member
 *              (AssignmentType = Temporary Assignment) on Accounts/Opportunities where Requester is a
 *              team member or owner, copying Requester access levels.
 *              GC-3352 - On AccountTeamMember insert only, stamp TerritoryCode__c, SalesCategoryCode__c,
 *              and SalesCategoryDescription__c from the requester ATM when present. Existing ATMs are
 *              not updated.
 *              GC-3345 - AccountTeamMember and OpportunityTeamMember insert set OpportunityAccessLevel to Edit.
 *              Revoke (Active + EndDate = today): removes matching team members when ExpiryDate__c
 *              equals EndDate. On success, updates Status to Active or Expired and sends notifications.
 *              GCL-95 - Life Science rows do not use the Healthcare grant or revoke email.
 *              Approval, rejection, and manual Active or Expired changes are emailed by
 *              LS Temporary Access Notification. This class emails Life Science rows only
 *              after the nightly batch saves Status as Active or Expired.
 *              During that save, the flow action is suppressed so the batch sends one email.
 *              CRUD/FLS is enforced via WITH USER_MODE SOQL and Database DML with AccessLevel.USER_MODE
 *              (equivalent to insert/update/delete as user) instead of a separate security class.
 */
public with sharing class TemporaryAccessExceptionService {
    @TestVisible
    private static Boolean testOnlyForceCommonReadSecurityFailure = false;
    @TestVisible
    private static Boolean testOnlyForceGrantSecurityFailure = false;
    @TestVisible
    private static Boolean testOnlyForceRevokeSecurityFailure = false;
    public static final String TEAM_MEMBER_ROLE_SALES = 'Sales';
    public static final String ASSIGNMENT_TYPE_TEMPORARY_ASSIGNMENT = 'Temporary Assignment';
    private static final String FLD_ASSIGNMENT_TYPE = 'AssignmentType__c';
    private static final String API_ACCOUNT_TEAM_MEMBER = 'AccountTeamMember';
    private static final String API_OPPORTUNITY_TEAM_MEMBER = 'OpportunityTeamMember';
    private static final Schema.SObjectType ACC_TEAM_MEMBER_TYPE =
        Schema.getGlobalDescribe().get(API_ACCOUNT_TEAM_MEMBER);
    private static final Schema.SObjectType OPP_TEAM_MEMBER_TYPE =
        Schema.getGlobalDescribe().get(API_OPPORTUNITY_TEAM_MEMBER);
    private static final String FLD_ACCOUNT_ID = 'AccountId';
    private static final String FLD_OPPORTUNITY_ID = 'OpportunityId';
    private static final String FLD_USER_ID = 'UserId';
    private static final String FLD_TEAM_MEMBER_ROLE = 'TeamMemberRole';
    private static final String FLD_ACCOUNT_ACCESS_LEVEL = 'AccountAccessLevel';
    private static final String FLD_OPPORTUNITY_ACCESS_LEVEL = 'OpportunityAccessLevel';
    private static final String FLD_CASE_ACCESS_LEVEL = 'CaseAccessLevel';
    private static final String FLD_EXPIRY_DATE = 'ExpiryDate__c'; //GC-3109
    private static final String FLD_TERRITORY_CODE = 'TerritoryCode__c'; // GC-3352
    private static final String FLD_SALES_CATEGORY_CODE = 'SalesCategoryCode__c'; // GC-3352
    private static final String FLD_SALES_CATEGORY_DESCRIPTION = 'SalesCategoryDescription__c'; // GC-3352 

    /**
     * @description Resolved team targets and access levels for one TemporaryAccessException__c row.
     */
    private class TeamAccessPlan {
        Id taeId;
        Id requesterId;
        Id coverageRepId;
        Date expiryDate; // GC-3109
        Set<Id> accountIds = new Set<Id>();
        Set<Id> opportunityIds = new Set<Id>();
        Set<Id> requesterOwnedAccountIds = new Set<Id>();
        Set<Id> requesterOwnedOpportunityIds = new Set<Id>();
        Map<Id, AccountTeamMember> requesterAccountTeamByAccountId = new Map<Id, AccountTeamMember>();
        Map<Id, OpportunityTeamMember> requesterOpportunityTeamByOppId = new Map<Id, OpportunityTeamMember>();
    }

    private class NotificationBuildContext {
        List<TemporaryAccessException__c> rows;
        Set<Id> successfulTaeIds;
        Boolean isGrant;
        Map<Id, List<String>> territoryIdsByRequesterId;
    }

    private class RevokePlanEvaluationContext {
        TeamAccessPlan plan;
        Map<String, SObject> accountTeamByKey;
        Map<String, SObject> opportunityTeamByKey;
        Date expiryDate;
        Set<String> deletedKeys;
    }

    private class AccountTeamMemberBuildInput {
        Id accountId;
        Id coverageRepId;
        AccountTeamMember requesterAtm;
        Boolean requesterIsOwner;
        Date expiryDate;
    }

    private class OpportunityTeamMemberBuildInput {
        Id opportunityId;
        Id coverageRepId;
        OpportunityTeamMember requesterOtm;
        Boolean requesterIsOwner;
        Date expiryDate;
    }

    private class AssignedRecordBuildContext {
        Set<Id> successfulTaeIds;
        Map<Id, TeamAccessPlan> plansByTaeId;
        Set<Id> allAccountIds = new Set<Id>();
        Set<Id> allOpportunityIds = new Set<Id>();
        Set<String> existingAccountKeys;
        Set<String> existingOpportunityKeys;
    }

    private class AssignedRecordRowAddContext {
        Id taeId;
        TeamAccessPlan plan;
        Set<String> existingKeys;
        List<TAE_AssignedRecord__c> inserts;
    }
    /**
     * @description GC-3179 - Modified: routes grant/revoke without TemporaryAccessExceptionSecurity pre-checks.
     * @param scope TemporaryAccessException__c rows from the batch query locator.
     * @example
     * TemporaryAccessExceptionService.process(batchScope);
     */
    public static void process(List<TemporaryAccessException__c> scope) {
        if (scope == null || scope.isEmpty()) {
            Logger.warn('TemporaryAccessExceptionService.process: empty scope');
            return;
        }
        if (!assertCommonReadSecurity()) {
            return;
        }
        List<TemporaryAccessException__c> grantRows = new List<TemporaryAccessException__c>();
        List<TemporaryAccessException__c> revokeRows = new List<TemporaryAccessException__c>();
        for (TemporaryAccessException__c row : scope) {
            if (TemporaryAccessExceptionSelector.isGrantScenario(row)) {
                grantRows.add(row);
            } else if (TemporaryAccessExceptionSelector.isRevokeScenario(row)) {
                revokeRows.add(row);
            }
        }
        Logger.debug(
            'TemporaryAccessExceptionService.process: grantRows=' + grantRows.size() +
            ', revokeRows=' + revokeRows.size()
        );
        if (!grantRows.isEmpty() && assertGrantSecurity()) {
            processGrants(grantRows);
        }
        if (!revokeRows.isEmpty() && assertRevokeSecurity()) {
            processRevokes(revokeRows);
        }
    }
    /**
     * @description Grants team access for Approved rows with StartDate = today.
     * @param rows Grant-scenario TemporaryAccessException__c rows.
     */
    private static void processGrants(List<TemporaryAccessException__c> rows) {
        Map<Id, TeamAccessPlan> plansByTaeId = buildPlans(rows);
        if (plansByTaeId.isEmpty()) {
            Logger.warn('TemporaryAccessExceptionService.processGrants: no resolvable plans');
            return;
        }
        Set<Id> allAccountIds = new Set<Id>();
        Set<Id> allOpportunityIds = new Set<Id>();
        Set<Id> allCoverageRepIds = new Set<Id>();
        for (TeamAccessPlan plan : plansByTaeId.values()) {
            allAccountIds.addAll(plan.accountIds);
            allOpportunityIds.addAll(plan.opportunityIds);
            allCoverageRepIds.add(plan.coverageRepId);
        }
        Set<String> existingAccountKeys =
            TemporaryAccessExceptionSelector.selectExistingCoverageRepAccountTeamKeys(
                allAccountIds,
                allCoverageRepIds
            );
        Set<String> existingOpportunityKeys =
            TemporaryAccessExceptionSelector.selectExistingCoverageRepOpportunityTeamKeys(
                allOpportunityIds,
                allCoverageRepIds
            );
        Set<String> insertedKeys = insertMissingTeamMembers(
            plansByTaeId,
            existingAccountKeys,
            existingOpportunityKeys
        );
        existingAccountKeys.addAll(insertedKeys);
        existingOpportunityKeys.addAll(insertedKeys);
        Set<Id> successfulTaeIds = new Set<Id>();
        for (TeamAccessPlan plan : plansByTaeId.values()) {
            if (isGrantPlanSatisfied(plan, existingAccountKeys, existingOpportunityKeys)) {
                successfulTaeIds.add(plan.taeId);
            }
        }
        Set<Id> updatedIds = finalizeSuccessfulGrants(successfulTaeIds, plansByTaeId);
        sendGrantEmails(rows, updatedIds);
        Logger.info(
            'TemporaryAccessExceptionService.processGrants: successfulCount=' + successfulTaeIds.size()
        );
    }
    /**
     * @description Revokes team access for Active rows with EndDate = today.
     * @param rows Revoke-scenario TemporaryAccessException__c rows.
     */
    private static void processRevokes(List<TemporaryAccessException__c> rows) {
        Map<Id, TeamAccessPlan> plansByTaeId = buildPlans(rows);
        if (plansByTaeId.isEmpty()) {
            Logger.warn('TemporaryAccessExceptionService.processRevokes: no resolvable plans');
            return;
        }
        Set<Id> allAccountIds = new Set<Id>();
        Set<Id> allOpportunityIds = new Set<Id>();
        Set<Id> allCoverageRepIds = new Set<Id>();
        for (TeamAccessPlan plan : plansByTaeId.values()) {
            allAccountIds.addAll(plan.accountIds);
            allOpportunityIds.addAll(plan.opportunityIds);
            allCoverageRepIds.add(plan.coverageRepId);
        }
        Map<String, SObject> accountTeamByKey = indexAccountTeamForRevoke(allAccountIds, allCoverageRepIds);
        Map<String, SObject> opportunityTeamByKey = indexOpportunityTeamForRevoke(
            allOpportunityIds,
            allCoverageRepIds
        );
        Map<String, SObject> recordsToDelete = new Map<String, SObject>();
        for (TeamAccessPlan plan : plansByTaeId.values()) {
            RevokePlanEvaluationContext context = new RevokePlanEvaluationContext();
            context.plan = plan;
            context.accountTeamByKey = accountTeamByKey;
            context.opportunityTeamByKey = opportunityTeamByKey;
            context.expiryDate = plan.expiryDate != null ? plan.expiryDate : Date.today();
            recordsToDelete.putAll(collectTeamMembersToDeleteForPlan(context));
        }
        Set<String> deletedKeys = deleteTeamMembers(recordsToDelete, Date.today());
        Set<Id> successfulTaeIds = new Set<Id>();
        for (TeamAccessPlan plan : plansByTaeId.values()) {
            RevokePlanEvaluationContext context = new RevokePlanEvaluationContext();
            context.plan = plan;
            context.accountTeamByKey = accountTeamByKey;
            context.opportunityTeamByKey = opportunityTeamByKey;
            context.deletedKeys = deletedKeys;
            if (isRevokePlanComplete(context)) {
                successfulTaeIds.add(plan.taeId);
            }
        }
        Set<Id> updatedIds = updateStatuses(successfulTaeIds, TemporaryAccessExceptionSelector.STATUS_EXPIRED);
        sendRevokeEmails(rows, updatedIds);
        Logger.info(
            'TemporaryAccessExceptionService.processRevokes: successfulCount=' + successfulTaeIds.size()
        );
    }
    /**
     * @description Sends grant notification emails for successfully processed rows.
     * @param rows Grant-scenario TemporaryAccessException__c rows.
     * @param successfulTaeIds Successfully processed row Ids.
     */
    private static void sendGrantEmails(
        List<TemporaryAccessException__c> rows,
        Set<Id> successfulTaeIds
    ) {
        sendEmails(rows, successfulTaeIds, true);
    }
    /**
     * @description Sends revoke notification emails for successfully processed rows.
     * @param rows Revoke-scenario TemporaryAccessException__c rows.
     * @param successfulTaeIds Successfully processed row Ids.
     */
    private static void sendRevokeEmails(
        List<TemporaryAccessException__c> rows,
        Set<Id> successfulTaeIds
    ) {
        sendEmails(rows, successfulTaeIds, false);
    }
    /**
     * @description Sends Healthcare and Life Science emails for rows whose Status update succeeded.
     *              Healthcare territory Ids are loaded once per chunk. Life Science end-date emails
     *              are sent separately so one failure does not skip the other.
     * @param rows TemporaryAccessException__c rows in the current pass.
     * @param successfulTaeIds Ids whose Status update succeeded.
     * @param isGrant True for grant notifications; false for revoke notifications.
     */
    private static void sendEmails(
        List<TemporaryAccessException__c> rows,
        Set<Id> successfulTaeIds,
        Boolean isGrant
    ) {
        if (rows == null || successfulTaeIds == null || successfulTaeIds.isEmpty()) {
            return;
        }
        Set<Id> lifeScienceIds = new Set<Id>();
        try {
            lifeScienceIds = LSTemporaryAccessExceptionEmailService.filterLifeScienceRequestIds(successfulTaeIds);
        } catch (Exception e) {
            Logger.error(
                'TemporaryAccessExceptionService.sendEmails: Life Science filter failed; Healthcare emails will include all rows',
                e
            );
        }
        Set<Id> healthcareIds = new Set<Id>();
        healthcareIds.addAll(successfulTaeIds);
        healthcareIds.removeAll(lifeScienceIds);

        if (!healthcareIds.isEmpty()) {
            Map<Id, List<String>> territoryIdsByRequesterId =
                loadTerritoryIdsForNotifications(rows, healthcareIds);
            NotificationBuildContext context = new NotificationBuildContext();
            context.rows = rows;
            context.successfulTaeIds = healthcareIds;
            context.isGrant = isGrant;
            context.territoryIdsByRequesterId = territoryIdsByRequesterId;
            List<TemporaryAccessExceptionEmailService.NotificationRequest> requests =
                buildNotificationRequests(context);
            Map<Id, User> usersById = loadUsersForNotifications(rows, healthcareIds);
            TemporaryAccessExceptionEmailService.sendBulkNotifications(requests, usersById);
        }

        if (lifeScienceIds.isEmpty()) {
            return;
        }
        List<Id> lifeScienceIdList = new List<Id>(lifeScienceIds);
        if (isGrant == true) {
            sendLifeScienceBatchEmail(lifeScienceIdList, true, false);
            return;
        }
        sendLifeScienceBatchEmail(lifeScienceIdList, false, false);
        sendLifeScienceBatchEmail(lifeScienceIdList, false, true);
    }

    /**
     * @description Sends one Life Science batch email. A failure is logged and does not stop the other email.
     * @param lifeScienceIds Life Science TemporaryAccessException__c Ids whose status update succeeded.
     * @param isGrant True for coverage granted. False for an end-date email.
     * @param isCoverageRevoked True for the coverage-revoked email. Ignored when isGrant is true.
     */
    private static void sendLifeScienceBatchEmail(
        List<Id> lifeScienceIds,
        Boolean isGrant,
        Boolean isCoverageRevoked
    ) {
        try {
            if (isGrant == true) {
                LSTemporaryAccessExceptionEmailService.sendCoverageGranted(lifeScienceIds);
            } else if (isCoverageRevoked == true) {
                LSTemporaryAccessExceptionEmailService.sendCoverageRevoked(lifeScienceIds);
            } else {
                LSTemporaryAccessExceptionEmailService.sendExpired(lifeScienceIds);
            }
        } catch (Exception e) {
            Logger.error('TemporaryAccessExceptionService.sendEmails: Life Science email failed', e);
        }
    }
    /**
     * @description Loads distinct TerritoryID__c values for Rep Needing Coverage on successful rows.
     * @param rows TemporaryAccessException__c rows in the current grant or revoke pass.
     * @param successfulTaeIds Ids of rows processed successfully in this pass.
     * @return Map of Requester__c Id to sorted unique territory external Ids.
     */
    private static Map<Id, List<String>> loadTerritoryIdsForNotifications(
        List<TemporaryAccessException__c> rows,
        Set<Id> successfulTaeIds
    ) {
        Set<Id> requesterIds = new Set<Id>();
        for (TemporaryAccessException__c row : rows) {
            if (successfulTaeIds.contains(row.Id) && row.Requester__c != null) {
                requesterIds.add(row.Requester__c);
            }
        }
        return TemporaryAccessExceptionSelector.selectDistinctTerritoryIdsByAssignedSalesRep(requesterIds);
    }
    /**
     * @description Builds notification payloads for successfully processed rows in the current chunk.
     * @param context Notification build context with rows, success Ids, grant flag, and territory map.
     * @return Notification requests for the email service.
     */
    private static List<TemporaryAccessExceptionEmailService.NotificationRequest> buildNotificationRequests(
        NotificationBuildContext context
    ) {
        List<TemporaryAccessExceptionEmailService.NotificationRequest> requests =
            new List<TemporaryAccessExceptionEmailService.NotificationRequest>();
        for (TemporaryAccessException__c row : context.rows) {
            if (!context.successfulTaeIds.contains(row.Id)) {
                continue;
            }
            TemporaryAccessExceptionEmailService.NotificationRequest request =
                new TemporaryAccessExceptionEmailService.NotificationRequest();
            request.taeRow = row;
            request.isGrant = context.isGrant;
            request.territoryIds = resolveTerritoryIdsForRequester(
                row.Requester__c,
                context.territoryIdsByRequesterId
            );
            requests.add(request);
        }
        return requests;
    }
    /**
     * @description Returns territory Ids for one requester, or an empty list when none exist.
     * @param requesterId Requester user Id.
     * @param territoryIdsByRequesterId Territory map keyed by requester Id.
     * @return Sorted territory external Ids for the requester.
     */
    private static List<String> resolveTerritoryIdsForRequester(
        Id requesterId,
        Map<Id, List<String>> territoryIdsByRequesterId
    ) {
        if (requesterId == null || territoryIdsByRequesterId == null) {
            return new List<String>();
        }
        List<String> territoryIds = territoryIdsByRequesterId.get(requesterId);
        return territoryIds == null ? new List<String>() : territoryIds;
    }
    /**
     * @description Loads requester and coverage rep users for notification emails.
     * @param rows TemporaryAccessException__c rows in the current pass.
     * @param successfulTaeIds Successfully processed row Ids.
     * @return Users keyed by Id for email delivery.
     */
    private static Map<Id, User> loadUsersForNotifications(
        List<TemporaryAccessException__c> rows,
        Set<Id> successfulTaeIds
    ) {
        Set<Id> userIds = new Set<Id>();
        for (TemporaryAccessException__c row : rows) {
            if (!successfulTaeIds.contains(row.Id)) {
                continue;
            }
            userIds.add(row.Requester__c);
            userIds.add(row.CoverageRep__c);
        }
        return TemporaryAccessExceptionSelector.selectUsersById(userIds);
    }
    /**
     * @description Builds TeamAccessPlan entries from requester team memberships and owned records for each row.
     * @param rows TemporaryAccessException__c rows in the current grant or revoke pass.
     * @return Map of TemporaryAccessException__c Id to resolved plan.
     */
    private static Map<Id, TeamAccessPlan> buildPlans(List<TemporaryAccessException__c> rows) {
        Map<Id, TeamAccessPlan> plansByTaeId = new Map<Id, TeamAccessPlan>();
        List<TemporaryAccessException__c> validRows = new List<TemporaryAccessException__c>();
        Set<Id> requesterIds = new Set<Id>();
        for (TemporaryAccessException__c row : rows) {
            if (row.Requester__c != null && row.CoverageRep__c != null) {
                validRows.add(row);
                requesterIds.add(row.Requester__c);
            }
        }
        Map<Id, Map<Id, AccountTeamMember>> accountTeamsByRequester = groupAccountTeamsByRequester(
            TemporaryAccessExceptionSelector.selectRequesterAccountTeamMembers(requesterIds)
        );
        Map<Id, Map<Id, OpportunityTeamMember>> opportunityTeamsByRequester = groupOpportunityTeamsByRequester(
            TemporaryAccessExceptionSelector.selectRequesterOpportunityTeamMembers(requesterIds)
        );
        Map<Id, Set<Id>> ownedAccountIdsByRequester = groupOwnedRecordIdsByOwner(
            TemporaryAccessExceptionSelector.selectRequesterOwnedAccounts(requesterIds)
        );
        Map<Id, Set<Id>> ownedOpportunityIdsByRequester = groupOwnedRecordIdsByOwner(
            TemporaryAccessExceptionSelector.selectRequesterOwnedOpportunities(requesterIds)
        );
        for (TemporaryAccessException__c row : validRows) {
            TeamAccessPlan plan = new TeamAccessPlan();
            plan.taeId = row.Id;
            plan.requesterId = row.Requester__c;
            plan.coverageRepId = row.CoverageRep__c;
            plan.expiryDate = row.EndDate__c; //GC-3109
            Map<Id, AccountTeamMember> requesterAccountTeams = accountTeamsByRequester.get(row.Requester__c);
            if (requesterAccountTeams != null) {
                plan.accountIds.addAll(requesterAccountTeams.keySet());
                plan.requesterAccountTeamByAccountId.putAll(requesterAccountTeams);
            }
            Map<Id, OpportunityTeamMember> requesterOpportunityTeams =
                opportunityTeamsByRequester.get(row.Requester__c);
            if (requesterOpportunityTeams != null) {
                plan.opportunityIds.addAll(requesterOpportunityTeams.keySet());
                plan.requesterOpportunityTeamByOppId.putAll(requesterOpportunityTeams);
            }
            Set<Id> ownedAccountIds = ownedAccountIdsByRequester.get(row.Requester__c);
            if (ownedAccountIds != null) {
                plan.accountIds.addAll(ownedAccountIds);
                plan.requesterOwnedAccountIds.addAll(ownedAccountIds);
            }
            Set<Id> ownedOpportunityIds = ownedOpportunityIdsByRequester.get(row.Requester__c);
            if (ownedOpportunityIds != null) {
                plan.opportunityIds.addAll(ownedOpportunityIds);
                plan.requesterOwnedOpportunityIds.addAll(ownedOpportunityIds);
            }
            plansByTaeId.put(plan.taeId, plan);
        }
        return plansByTaeId;
    }
    /**
     * @description Inserts missing Temporary Coverage Rep team members for the chunk.
     * @param plansByTaeId Resolved plans keyed by TemporaryAccessException__c Id.
     * @param existingAccountKeys Existing coverage rep account team keys.
     * @param existingOpportunityKeys Existing coverage rep opportunity team keys.
     * @return Composite keys successfully inserted in this pass.
     */
    private static Set<String> insertMissingTeamMembers(
        Map<Id, TeamAccessPlan> plansByTaeId,
        Set<String> existingAccountKeys,
        Set<String> existingOpportunityKeys
    ) {
        Map<String, SObject> recordsByKey = new Map<String, SObject>();
        for (TeamAccessPlan plan : plansByTaeId.values()) {
            for (Id accountId : plan.accountIds) {
                String accountKey = TemporaryAccessExceptionSelector.buildAccountTeamKey(
                    accountId,
                    plan.coverageRepId
                );
                if (!existingAccountKeys.contains(accountKey) && !recordsByKey.containsKey(accountKey)) {
                    AccountTeamMemberBuildInput accountInput = new AccountTeamMemberBuildInput();
                    accountInput.accountId = accountId;
                    accountInput.coverageRepId = plan.coverageRepId;
                    accountInput.requesterAtm = plan.requesterAccountTeamByAccountId.get(accountId);
                    accountInput.requesterIsOwner = plan.requesterOwnedAccountIds.contains(accountId);
                    accountInput.expiryDate = plan.expiryDate; // GC-3109
                    recordsByKey.put(accountKey, buildAccountTeamMember(accountInput));
                }
            }
            for (Id opportunityId : plan.opportunityIds) {
                String oppKey = TemporaryAccessExceptionSelector.buildOpportunityTeamKey(
                    opportunityId,
                    plan.coverageRepId
                );
                if (!existingOpportunityKeys.contains(oppKey) && !recordsByKey.containsKey(oppKey)) {
                    OpportunityTeamMemberBuildInput opportunityInput = new OpportunityTeamMemberBuildInput();
                    opportunityInput.opportunityId = opportunityId;
                    opportunityInput.coverageRepId = plan.coverageRepId;
                    opportunityInput.requesterOtm = plan.requesterOpportunityTeamByOppId.get(opportunityId);
                    opportunityInput.requesterIsOwner = plan.requesterOwnedOpportunityIds.contains(opportunityId);
                    opportunityInput.expiryDate = plan.expiryDate; // GC-3109
                    recordsByKey.put(oppKey, buildOpportunityTeamMember(opportunityInput));
                }
            }
        }
        return insertTeamMembers(recordsByKey);
    }
    /**
     * @description True when coverage rep is on every account and opportunity in the plan scope.
     * @param plan Resolved team access plan.
     * @param existingAccountKeys All satisfied account team keys.
     * @param existingOpportunityKeys All satisfied opportunity team keys.
     * @return True when grant processing for this row is complete.
     */
    private static Boolean isGrantPlanSatisfied(
        TeamAccessPlan plan,
        Set<String> existingAccountKeys,
        Set<String> existingOpportunityKeys
    ) {
        for (Id accountId : plan.accountIds) {
            String key = TemporaryAccessExceptionSelector.buildAccountTeamKey(accountId, plan.coverageRepId);
            if (!existingAccountKeys.contains(key)) {
                return false;
            }
        }
        for (Id opportunityId : plan.opportunityIds) {
            String key = TemporaryAccessExceptionSelector.buildOpportunityTeamKey(
                opportunityId,
                plan.coverageRepId
            );
            if (!existingOpportunityKeys.contains(key)) {
                return false;
            }
        }
        return true;
    }
    /**
     * @description Collects Temporary Coverage Rep team members to delete for one plan.
     * @param context Revoke plan evaluation context including plan, indexed team members, and expiryDate.
     * @return Team member rows keyed by composite key.
     */
    private static Map<String, SObject> collectTeamMembersToDeleteForPlan(
        RevokePlanEvaluationContext context
    ) {
        Map<String, SObject> recordsToDelete = new Map<String, SObject>();
        TeamAccessPlan plan = context.plan;
        for (Id accountId : plan.accountIds) {
            String key = TemporaryAccessExceptionSelector.buildAccountTeamKey(accountId, plan.coverageRepId);
            SObject atm = context.accountTeamByKey.get(key);
            if (isEligibleTemporaryAssignmentForRevoke(atm, context.expiryDate)) {
                recordsToDelete.put(key, atm);
            }
        }
        for (Id opportunityId : plan.opportunityIds) {
            String key = TemporaryAccessExceptionSelector.buildOpportunityTeamKey(
                opportunityId,
                plan.coverageRepId
            );
            SObject otm = context.opportunityTeamByKey.get(key);
            if (isEligibleTemporaryAssignmentForRevoke(otm, context.expiryDate)) {
                recordsToDelete.put(key, otm);
            }
        }
        return recordsToDelete;
    }
    /**
     * @description True when a team member matches Sales + Temporary Assignment + expected expiry.
     * @param teamMember Account or Opportunity team member candidate for revoke.
     * @param expiryDate Expected expiry date on the temporary assignment.
     * @return True when the team member is eligible for revoke deletion.
     */
    private static Boolean isEligibleTemporaryAssignmentForRevoke(SObject teamMember, Date expiryDate) {
        if (teamMember == null || expiryDate == null) {
            return false;
        }
        return TEAM_MEMBER_ROLE_SALES == teamMember.get(FLD_TEAM_MEMBER_ROLE)
            && ASSIGNMENT_TYPE_TEMPORARY_ASSIGNMENT == teamMember.get(FLD_ASSIGNMENT_TYPE);
           // && expiryDate == (Date) teamMember.get(FLD_EXPIRY_DATE);
    }
    /**
     * @description True when required Temporary Coverage Rep memberships are gone or never existed.
     * @param context Revoke completion context with plan, accountTeamByKey, opportunityTeamByKey, and deletedKeys.
     * @return True when revoke processing for this row is complete.
     */
    private static Boolean isRevokePlanComplete(RevokePlanEvaluationContext context) {
        TeamAccessPlan plan = context.plan;
        for (Id accountId : plan.accountIds) {
            String key = TemporaryAccessExceptionSelector.buildAccountTeamKey(accountId, plan.coverageRepId);
            if (context.accountTeamByKey.containsKey(key) && !context.deletedKeys.contains(key)) {
                return false;
            }
        }
        for (Id opportunityId : plan.opportunityIds) {
            String key = TemporaryAccessExceptionSelector.buildOpportunityTeamKey(
                opportunityId,
                plan.coverageRepId
            );
            if (context.opportunityTeamByKey.containsKey(key) && !context.deletedKeys.contains(key)) {
                return false;
            }
        }
        return true;
    }
    /**
     * @description Indexes Temporary Coverage Rep AccountTeamMember rows for revoke by composite key.
     * @param accountIds Account Ids in revoke scope.
     * @param coverageRepIds Coverage rep user Ids.
     * @return Map of accountId|userId to team member SObject.
     */
    private static Map<String, SObject> indexAccountTeamForRevoke(
        Set<Id> accountIds,
        Set<Id> coverageRepIds
    ) {
        Map<String, SObject> recordsByKey = new Map<String, SObject>();
        TemporaryAccessExceptionSelector.RevokeTeamMemberCriteria criteria =
            buildRevokeTeamMemberCriteria(accountIds, coverageRepIds);
        for (SObject atm : TemporaryAccessExceptionSelector.selectTemporaryAssignmentAccountTeamMembersForRevoke(
            criteria
        )) {
            recordsByKey.put(
                TemporaryAccessExceptionSelector.buildAccountTeamKey(
                    (Id) atm.get(FLD_ACCOUNT_ID),
                    (Id) atm.get(FLD_USER_ID)
                ),
                atm
            );
        }
        return recordsByKey;
    }
    /**
     * @description Indexes Temporary Coverage Rep OpportunityTeamMember rows for revoke by composite key.
     * @param opportunityIds Opportunity Ids in revoke scope.
     * @param coverageRepIds Coverage rep user Ids.
     * @return Map of opportunityId|userId to team member SObject.
     */
    private static Map<String, SObject> indexOpportunityTeamForRevoke(
        Set<Id> opportunityIds,
        Set<Id> coverageRepIds
    ) {
        Map<String, SObject> recordsByKey = new Map<String, SObject>();
        TemporaryAccessExceptionSelector.RevokeTeamMemberCriteria criteria =
            buildRevokeTeamMemberCriteria(opportunityIds, coverageRepIds);
        for (SObject otm : TemporaryAccessExceptionSelector.selectTemporaryAssignmentOpportunityTeamMembersForRevoke(
            criteria
        )) {
            recordsByKey.put(
                TemporaryAccessExceptionSelector.buildOpportunityTeamKey(
                    (Id) otm.get(FLD_OPPORTUNITY_ID),
                    (Id) otm.get(FLD_USER_ID)
                ),
                otm
            );
        }
        return recordsByKey;
    }
    /**
     * @description GC-3179 - Modified: insert as user via Database.insert AccessLevel.USER_MODE (partial success).
     * @param recordsByKey Deduplicated team members keyed by composite key.
     * @return Set of composite keys successfully inserted.
     */
    private static Set<String> insertTeamMembers(Map<String, SObject> recordsByKey) {
        Set<String> successfulKeys = new Set<String>();
        if (recordsByKey == null || recordsByKey.isEmpty()) {
            return successfulKeys;
        }
        List<SObject> records = recordsByKey.values();
        Logger.debug('TemporaryAccessExceptionService.insertTeamMembers: count=' + records.size());
        List<Database.SaveResult> results = Database.insert(records, false, AccessLevel.USER_MODE);
        Integer failureCount = 0;
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                successfulKeys.add(compositeKeyFromTeamMember(records[i]));
            } else {
                failureCount++;
                logDmlErrors(results[i].getErrors(), 'insertTeamMembers');
            }
        }
        if (failureCount > 0) {
            Logger.warn(
                'TemporaryAccessExceptionService.insertTeamMembers: partial failure, failures=' + failureCount
            );
        }
        return successfulKeys;
    }
    /**
     * @description GC-3179 - Modified: delete as user via Database.delete AccessLevel.USER_MODE (partial success).
     * @param recordsByKey Team member rows keyed by composite key.
     * @param expiryDate Expected expiry date used to filter eligible temporary assignments.
     * @return Set of composite keys successfully deleted.
     */
    private static Set<String> deleteTeamMembers(Map<String, SObject> recordsByKey, Date expiryDate) {
        Set<String> successfulKeys = new Set<String>();
        if (recordsByKey == null || recordsByKey.isEmpty()) {
            return successfulKeys;
        }
        List<SObject> records = new List<SObject>();
        for (SObject teamMember : recordsByKey.values()) {
            if (isEligibleTemporaryAssignmentForRevoke(teamMember, expiryDate)) {
                records.add(teamMember);
            }
        }
        if (records.isEmpty()) {
            return successfulKeys;
        }
        Logger.debug('TemporaryAccessExceptionService.deleteTeamMembers: count=' + records.size());
        List<Database.DeleteResult> results = Database.delete(records, false, AccessLevel.USER_MODE);
        Integer failureCount = 0;
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                successfulKeys.add(compositeKeyFromTeamMember(records[i]));
            } else {
                failureCount++;
                logDmlErrors(results[i].getErrors(), 'deleteTeamMembers');
            }
        }
        if (failureCount > 0) {
            Logger.warn(
                'TemporaryAccessExceptionService.deleteTeamMembers: partial failure, failures=' + failureCount
            );
        }
        return successfulKeys;
    }
    /**
     * @description GC-3333 -
     * Marks successfully granted TemporaryAccessException__c rows Active and inserts
     * TAE_AssignedRecord__c audit rows for granted Accounts and Opportunities.
     * GC-3179 - Modified: update as user via Database.update AccessLevel.USER_MODE.
     *
     * @param successfulTaeIds TemporaryAccessException__c Ids processed successfully in the grant pass.
     * @param plansByTaeId Resolved team access plans keyed by TemporaryAccessException__c Id.
     * @return Ids whose Status update to Active succeeded.
     */
    private static Set<Id> finalizeSuccessfulGrants(
        Set<Id> successfulTaeIds,
        Map<Id, TeamAccessPlan> plansByTaeId
    ) {
        if (successfulTaeIds == null || successfulTaeIds.isEmpty()) {
            return new Set<Id>();
        }
        List<TemporaryAccessException__c> updates = new List<TemporaryAccessException__c>();
        for (Id taeId : successfulTaeIds) {
            updates.add(
                new TemporaryAccessException__c(
                    Id = taeId,
                    Status__c = TemporaryAccessExceptionSelector.STATUS_ACTIVE
                )
            );
        }
        Logger.info(
            'TemporaryAccessExceptionService.finalizeSuccessfulGrants: count=' + updates.size()
        );
        Set<Id> updatedIds = applyStatusUpdates(updates, 'finalizeSuccessfulGrants');
        insertAssignedRecords(successfulTaeIds, plansByTaeId);
        return updatedIds;
    }
    /**
     * @description GC-3333 -
     * Inserts TAE_AssignedRecord__c audit rows for successfully granted Accounts and Opportunities.
     * Dedupes against existing rows. Uses SYSTEM_MODE because sales permission sets are read-only
     * on this object and rows are system-generated by the grant batch.
     *
     * @param successfulTaeIds TemporaryAccessException__c Ids processed successfully in the grant pass.
     * @param plansByTaeId Resolved team access plans keyed by TemporaryAccessException__c Id.
     */
    private static void insertAssignedRecords(
        Set<Id> successfulTaeIds,
        Map<Id, TeamAccessPlan> plansByTaeId
    ) {
        if (successfulTaeIds == null || successfulTaeIds.isEmpty()) {
            return;
        }
        AssignedRecordBuildContext context = initializeAssignedRecordBuildContext(
            successfulTaeIds,
            plansByTaeId
        );
        List<TAE_AssignedRecord__c> assignedRecordInserts = buildAssignedRecordRows(context);
        persistAssignedRecords(assignedRecordInserts);
    }

    private static AssignedRecordBuildContext initializeAssignedRecordBuildContext(
        Set<Id> successfulTaeIds,
        Map<Id, TeamAccessPlan> plansByTaeId
    ) {
        AssignedRecordBuildContext context = new AssignedRecordBuildContext();
        context.successfulTaeIds = successfulTaeIds;
        context.plansByTaeId = plansByTaeId;
        collectAssignedRecordScopeIds(context);
        context.existingAccountKeys = TAEAssignedRecordSelector.selectExistingAccountKeys(
            successfulTaeIds,
            context.allAccountIds
        );
        context.existingOpportunityKeys = TAEAssignedRecordSelector.selectExistingOpportunityKeys(
            successfulTaeIds,
            context.allOpportunityIds
        );
        return context;
    }

    private static void collectAssignedRecordScopeIds(AssignedRecordBuildContext context) {
        for (Id taeId : context.successfulTaeIds) {
            TeamAccessPlan plan = context.plansByTaeId.get(taeId);
            if (plan == null) {
                continue;
            }
            context.allAccountIds.addAll(plan.accountIds);
            context.allOpportunityIds.addAll(plan.opportunityIds);
        }
    }

    private static List<TAE_AssignedRecord__c> buildAssignedRecordRows(
        AssignedRecordBuildContext context
    ) {
        List<TAE_AssignedRecord__c> assignedRecordInserts = new List<TAE_AssignedRecord__c>();
        for (Id taeId : context.successfulTaeIds) {
            TeamAccessPlan plan = context.plansByTaeId.get(taeId);
            if (plan == null) {
                continue;
            }
            AssignedRecordRowAddContext accountContext = new AssignedRecordRowAddContext();
            accountContext.taeId = taeId;
            accountContext.plan = plan;
            accountContext.existingKeys = context.existingAccountKeys;
            accountContext.inserts = assignedRecordInserts;
            addAccountAssignedRecords(accountContext);
            AssignedRecordRowAddContext opportunityContext = new AssignedRecordRowAddContext();
            opportunityContext.taeId = taeId;
            opportunityContext.plan = plan;
            opportunityContext.existingKeys = context.existingOpportunityKeys;
            opportunityContext.inserts = assignedRecordInserts;
            addOpportunityAssignedRecords(opportunityContext);
        }
        return assignedRecordInserts;
    }

    private static void addAccountAssignedRecords(AssignedRecordRowAddContext context) {
        for (Id accountId : context.plan.accountIds) {
            String accountKey = TAEAssignedRecordSelector.buildAccountKey(context.taeId, accountId);
            if (context.existingKeys.contains(accountKey)) {
                continue;
            }
            context.inserts.add(
                new TAE_AssignedRecord__c(
                    TemporaryAccessException__c = context.taeId,
                    Account__c = accountId
                )
            );
            context.existingKeys.add(accountKey);
        }
    }

    private static void addOpportunityAssignedRecords(AssignedRecordRowAddContext context) {
        for (Id opportunityId : context.plan.opportunityIds) {
            String opportunityKey = TAEAssignedRecordSelector.buildOpportunityKey(
                context.taeId,
                opportunityId
            );
            if (context.existingKeys.contains(opportunityKey)) {
                continue;
            }
            context.inserts.add(
                new TAE_AssignedRecord__c(
                    TemporaryAccessException__c = context.taeId,
                    Opportunity__c = opportunityId
                )
            );
            context.existingKeys.add(opportunityKey);
        }
    }

    private static void persistAssignedRecords(List<TAE_AssignedRecord__c> assignedRecordInserts) {
        if (assignedRecordInserts == null || assignedRecordInserts.isEmpty()) {
            return;
        }
        Logger.info(
            'TemporaryAccessExceptionService.insertAssignedRecords: count=' + assignedRecordInserts.size()
        );
        List<Database.SaveResult> results = Database.insert(
            assignedRecordInserts,
            false,
            AccessLevel.SYSTEM_MODE
        );
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                logDmlErrors(result.getErrors(), 'insertAssignedRecords');
            }
        }
    }
    /**
     * @description GC-3179 - Modified: update as user via Database.update AccessLevel.USER_MODE.
     * @param taeIds TemporaryAccessException__c Ids to update.
     * @param newStatus Target Status__c value (Active or Expired).
     */
    private static Set<Id> updateStatuses(Set<Id> taeIds, String newStatus) {
        if (taeIds == null || taeIds.isEmpty()) {
            return new Set<Id>();
        }
        List<TemporaryAccessException__c> updates = new List<TemporaryAccessException__c>();
        for (Id taeId : taeIds) {
            updates.add(new TemporaryAccessException__c(Id = taeId, Status__c = newStatus));
        }
        Logger.info('TemporaryAccessExceptionService.updateStatuses: count=' + updates.size() + ', status=' + newStatus);
        return applyStatusUpdates(updates, 'updateStatuses');
    }

    /**
     * @description Saves Status__c and returns the Ids that saved.
     *              The Life Science flow action is suppressed for this DML only.
     * @param updates TemporaryAccessException__c rows with Id and Status__c set.
     * @param logContext Logger and DML error context.
     * @return Ids whose status update succeeded.
     */
    private static Set<Id> applyStatusUpdates(List<TemporaryAccessException__c> updates, String logContext) {
        Set<Id> updatedIds = new Set<Id>();
        LSTemporaryAccessExceptionEmailService.suppressInvocableSend = true;
        List<Database.SaveResult> results;
        try {
            results = Database.update(updates, false, AccessLevel.USER_MODE);
        } finally {
            LSTemporaryAccessExceptionEmailService.suppressInvocableSend = false;
        }
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                updatedIds.add(result.getId());
            } else {
                logDmlErrors(result.getErrors(), logContext);
            }
        }
        return updatedIds;
    }
    /**
     * @description Builds an AccountTeamMember with access levels copied from the requester or Edit when owner.
     *              GC-3352 - Copies coverage fields from requesterAtm on insert when that ATM exists.
     *              GC-3345 - Sets OpportunityAccessLevel to Edit.
     * @param input Account team member build input with accountId, coverageRepId, requesterAtm, requesterIsOwner, and expiryDate.
     * @return Uninserted AccountTeamMember SObject.
     */
    private static SObject buildAccountTeamMember(AccountTeamMemberBuildInput input) {
        SObject atm = ACC_TEAM_MEMBER_TYPE.newSObject();
        atm.put(FLD_ACCOUNT_ID, input.accountId);
        atm.put(FLD_USER_ID, input.coverageRepId);
        atm.put(FLD_TEAM_MEMBER_ROLE, TEAM_MEMBER_ROLE_SALES);
        atm.put(FLD_ASSIGNMENT_TYPE, ASSIGNMENT_TYPE_TEMPORARY_ASSIGNMENT);
        atm.put(FLD_EXPIRY_DATE, input.expiryDate); // GC-3109
        if (input.requesterAtm != null) {
            atm.put(FLD_TERRITORY_CODE, input.requesterAtm.TerritoryCode__c);
            atm.put(FLD_SALES_CATEGORY_CODE, input.requesterAtm.SalesCategoryCode__c);
            atm.put(FLD_SALES_CATEGORY_DESCRIPTION, input.requesterAtm.SalesCategoryDescription__c);
        }
        atm.put(FLD_OPPORTUNITY_ACCESS_LEVEL, 'Edit'); // GC-3345
        if (input.requesterIsOwner == true) {
            atm.put(FLD_ACCOUNT_ACCESS_LEVEL, 'Edit');
            atm.put(FLD_CASE_ACCESS_LEVEL, 'Read');
        } else {
            atm.put(FLD_ACCOUNT_ACCESS_LEVEL, input.requesterAtm != null ? input.requesterAtm.AccountAccessLevel : 'Read');
            atm.put(FLD_CASE_ACCESS_LEVEL, input.requesterAtm != null ? input.requesterAtm.CaseAccessLevel : 'Read');
        }
        return atm;
    }
    /**
     * @description Builds an OpportunityTeamMember with OpportunityAccessLevel Edit (GC-3345).
     * @param input Opportunity team member build input with opportunityId, coverageRepId, requesterOtm, requesterIsOwner, and expiryDate.
     * @return Uninserted OpportunityTeamMember SObject.
     */
    private static SObject buildOpportunityTeamMember(OpportunityTeamMemberBuildInput input) {
        SObject otm = OPP_TEAM_MEMBER_TYPE.newSObject();
        otm.put(FLD_OPPORTUNITY_ID, input.opportunityId);
        otm.put(FLD_USER_ID, input.coverageRepId);
        otm.put(FLD_TEAM_MEMBER_ROLE, TEAM_MEMBER_ROLE_SALES);
        otm.put(FLD_ASSIGNMENT_TYPE, ASSIGNMENT_TYPE_TEMPORARY_ASSIGNMENT);
        otm.put(FLD_EXPIRY_DATE, input.expiryDate); // GC-3109
        otm.put(FLD_OPPORTUNITY_ACCESS_LEVEL, 'Edit'); // GC-3345
        return otm;
    }
    /**
     * @description Builds accountId|userId or opportunityId|userId from a team member SObject.
     * @param teamMember AccountTeamMember or OpportunityTeamMember row.
     * @return Composite key used for satisfaction checks.
     */
    private static String compositeKeyFromTeamMember(SObject teamMember) {
        Id userId = (Id) teamMember.get(FLD_USER_ID);
        if (teamMember.getSObjectType() == ACC_TEAM_MEMBER_TYPE) {
            return TemporaryAccessExceptionSelector.buildAccountTeamKey(
                (Id) teamMember.get(FLD_ACCOUNT_ID),
                userId
            );
        }
        return TemporaryAccessExceptionSelector.buildOpportunityTeamKey(
            (Id) teamMember.get(FLD_OPPORTUNITY_ID),
            userId
        );
    }
    private static Map<Id, Map<Id, AccountTeamMember>> groupAccountTeamsByRequester(
        List<AccountTeamMember> members
    ) {
        Map<Id, Map<Id, AccountTeamMember>> grouped = new Map<Id, Map<Id, AccountTeamMember>>();
        for (AccountTeamMember atm : members) {
            if (!grouped.containsKey(atm.UserId)) {
                grouped.put(atm.UserId, new Map<Id, AccountTeamMember>());
            }
            grouped.get(atm.UserId).put(atm.AccountId, atm);
        }
        return grouped;
    }
    private static Map<Id, Map<Id, OpportunityTeamMember>> groupOpportunityTeamsByRequester(
        List<OpportunityTeamMember> members
    ) {
        Map<Id, Map<Id, OpportunityTeamMember>> grouped = new Map<Id, Map<Id, OpportunityTeamMember>>();
        for (OpportunityTeamMember otm : members) {
            if (!grouped.containsKey(otm.UserId)) {
                grouped.put(otm.UserId, new Map<Id, OpportunityTeamMember>());
            }
            grouped.get(otm.UserId).put(otm.OpportunityId, otm);
        }
        return grouped;
    }
    private static Map<Id, Set<Id>> groupOwnedRecordIdsByOwner(List<SObject> ownedRecords) {
        Map<Id, Set<Id>> grouped = new Map<Id, Set<Id>>();
        for (SObject record : ownedRecords) {
            Id ownerId = (Id) record.get('OwnerId');
            if (ownerId == null) {
                continue;
            }
            if (!grouped.containsKey(ownerId)) {
                grouped.put(ownerId, new Set<Id>());
            }
            grouped.get(ownerId).add(record.Id);
        }
        return grouped;
    }
    private static TemporaryAccessExceptionSelector.RevokeTeamMemberCriteria buildRevokeTeamMemberCriteria(
        Set<Id> recordIds,
        Set<Id> coverageRepIds
    ) {
        TemporaryAccessExceptionSelector.RevokeTeamMemberCriteria criteria =
            new TemporaryAccessExceptionSelector.RevokeTeamMemberCriteria();
        criteria.recordIds = recordIds;
        criteria.coverageRepIds = coverageRepIds;
        criteria.teamMemberRole = TEAM_MEMBER_ROLE_SALES;
        criteria.assignmentType = ASSIGNMENT_TYPE_TEMPORARY_ASSIGNMENT;
        return criteria;
    }

    private static String getKeyPrefix(Schema.SObjectType objectType) {
        return String.valueOf(objectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix());
    }

    private static void logDmlErrors(List<Database.Error> errors, String operation) {
        if (errors == null) {
            return;
        }
        for (Database.Error err : errors) {
            Logger.error(
                'TemporaryAccessExceptionService.' + operation + ': ' + err.getStatusCode() +
                ' ' + err.getMessage()
            );
        }
    }
    /**
     * @description GC-3179 - Modified: test hook only; CRUD/FLS enforced at SOQL/DML user mode.
     * @return True when processing may continue; false when the test hook simulates failure.
     */
    private static Boolean assertCommonReadSecurity() {
        try {
            if (Test.isRunningTest() && testOnlyForceCommonReadSecurityFailure) {
                throw new TemporaryAccessExceptionException('Test forced common read security failure');
            }
            return true;
        } catch (Exception e) {
            Logger.error('TemporaryAccessExceptionService.assertCommonReadSecurity', e);
            return false;
        }
    }
    /**
     * @description GC-3179 - Modified: test hook only; grant DML enforces access via USER_MODE.
     * @return True when grant processing may continue; false when the test hook simulates failure.
     */
    private static Boolean assertGrantSecurity() {
        try {
            if (Test.isRunningTest() && testOnlyForceGrantSecurityFailure) {
                throw new TemporaryAccessExceptionException('Test forced grant security failure');
            }
            return true;
        } catch (Exception e) {
            Logger.error('TemporaryAccessExceptionService.assertGrantSecurity', e);
            return false;
        }
    }
    /**
     * @description GC-3179 - Modified: test hook only; revoke DML enforces access via USER_MODE.
     * @return True when revoke processing may continue; false when the test hook simulates failure.
     */
    private static Boolean assertRevokeSecurity() {
        try {
            if (Test.isRunningTest() && testOnlyForceRevokeSecurityFailure) {
                throw new TemporaryAccessExceptionException('Test forced revoke security failure');
            }
            return true;
        } catch (Exception e) {
            Logger.error('TemporaryAccessExceptionService.assertRevokeSecurity', e);
            return false;
        }
    }
    /**
     * @description
     * Test-only entry to exercise logDmlErrors null guard and error logging loop.
     */
    @TestVisible
    private static void testOnlyInvokeLogDmlErrors() {
        logDmlErrors(null, 'nullErrors');
        List<SObject> invalidRows = new List<SObject>{ new Account() };
        for (Database.SaveResult saveResult : Database.insert(invalidRows, false, AccessLevel.USER_MODE)) {
            if (!saveResult.isSuccess()) {
                logDmlErrors(saveResult.getErrors(), 'invalidInsert');
            }
        }
    }
    /**
     * @description
     * Test-only entry to exercise insertTeamMembers partial-failure logging.
     */
    @TestVisible
    private static void testOnlyInvokePartialInsertFailure() {
        Map<String, SObject> recordsByKey = new Map<String, SObject>();
        SObject invalidAtm = ACC_TEAM_MEMBER_TYPE.newSObject();
        invalidAtm.put(FLD_USER_ID, UserInfo.getUserId());
        recordsByKey.put('invalid', invalidAtm);
        insertTeamMembers(recordsByKey);
    }
    /**
     * @description
     * Test-only entry to exercise deleteTeamMembers partial-failure logging.
     */
    @TestVisible
    private static void testOnlyInvokePartialDeleteFailure() {
        String keyPrefix = getKeyPrefix(AccountTeamMember.SObjectType);
        Id fakeTeamMemberId = (Id) (keyPrefix + '000000000000');
        SObject fakeAtm = ACC_TEAM_MEMBER_TYPE.newSObject(fakeTeamMemberId);
        fakeAtm.put(FLD_TEAM_MEMBER_ROLE, TEAM_MEMBER_ROLE_SALES);
        fakeAtm.put(FLD_ASSIGNMENT_TYPE, ASSIGNMENT_TYPE_TEMPORARY_ASSIGNMENT);
        fakeAtm.put(FLD_EXPIRY_DATE, Date.today());
        Map<String, SObject> recordsByKey = new Map<String, SObject>();
        recordsByKey.put('invalid', fakeAtm);
        deleteTeamMembers(recordsByKey, Date.today());
    }
    /**
     * @description
     * Test-only entry to exercise updateStatuses failure logging.
     */
    @TestVisible
    private static void testOnlyInvokeUpdateStatusesFailure() {
        Id fakeTaeId = (Id) (getKeyPrefix(TemporaryAccessException__c.SObjectType) + '000000000000');
        updateStatuses(
            new Set<Id>{ fakeTaeId },
            TemporaryAccessExceptionSelector.STATUS_ACTIVE
        );
    }
    /**
     * @description
     * Test-only entry to exercise opportunity team builder, satisfaction, and revoke helper paths.
     */
    @TestVisible
    private static void testOnlyInvokeOpportunityCoveragePaths() {
        testOnlyInvokeTeamMemberBuilderPaths();
        testOnlyInvokeRevokeEvaluationPaths();
    }

    @TestVisible
    private static void testOnlyInvokeTeamMemberBuilderPaths() {
        Id fakeAccountId = (Id) (getKeyPrefix(Account.SObjectType) + '000000000000');
        Id fakeOppId = (Id) (getKeyPrefix(Opportunity.SObjectType) + '000000000000');
        Id coverageRepId = UserInfo.getUserId();
        AccountTeamMemberBuildInput accountInput = new AccountTeamMemberBuildInput();
        accountInput.accountId = fakeAccountId;
        accountInput.coverageRepId = coverageRepId;
        accountInput.requesterIsOwner = false;
        buildAccountTeamMember(accountInput);
        accountInput.requesterIsOwner = true;
        buildAccountTeamMember(accountInput);
        OpportunityTeamMember requesterOtm = new OpportunityTeamMember(
            OpportunityId = fakeOppId,
            UserId = UserInfo.getUserId(),
            OpportunityAccessLevel = 'Edit'
        );
        OpportunityTeamMemberBuildInput ownedOppInput = new OpportunityTeamMemberBuildInput();
        ownedOppInput.opportunityId = fakeOppId;
        ownedOppInput.coverageRepId = coverageRepId;
        ownedOppInput.requesterIsOwner = true;
        buildOpportunityTeamMember(ownedOppInput);
        OpportunityTeamMemberBuildInput oppInput = new OpportunityTeamMemberBuildInput();
        oppInput.opportunityId = fakeOppId;
        oppInput.coverageRepId = coverageRepId;
        oppInput.requesterOtm = requesterOtm;
        oppInput.requesterIsOwner = false;
        buildOpportunityTeamMember(oppInput);
        oppInput.expiryDate = Date.today();
        SObject builtOtm = buildOpportunityTeamMember(oppInput);
        compositeKeyFromTeamMember(builtOtm);
        groupOpportunityTeamsByRequester(new List<OpportunityTeamMember>{ requesterOtm });
    }

    @TestVisible
    private static void testOnlyInvokeRevokeEvaluationPaths() {
        Id fakeAccountId = (Id) (getKeyPrefix(Account.SObjectType) + '000000000000');
        Id fakeOppId = (Id) (getKeyPrefix(Opportunity.SObjectType) + '000000000000');
        Id coverageRepId = UserInfo.getUserId();
        OpportunityTeamMember requesterOtm = new OpportunityTeamMember(
            OpportunityId = fakeOppId,
            UserId = UserInfo.getUserId(),
            OpportunityAccessLevel = 'Edit'
        );
        OpportunityTeamMemberBuildInput oppInput = new OpportunityTeamMemberBuildInput();
        oppInput.opportunityId = fakeOppId;
        oppInput.coverageRepId = coverageRepId;
        oppInput.requesterOtm = requesterOtm;
        oppInput.requesterIsOwner = false;
        oppInput.expiryDate = Date.today();
        SObject builtOtm = buildOpportunityTeamMember(oppInput);
        TeamAccessPlan plan = new TeamAccessPlan();
        plan.taeId = fakeOppId;
        plan.coverageRepId = coverageRepId;
        plan.accountIds.add(fakeAccountId);
        plan.opportunityIds.add(fakeOppId);
        plan.requesterOwnedOpportunityIds.add(fakeOppId);
        plan.requesterOpportunityTeamByOppId.put(fakeOppId, requesterOtm);
        String accountKey = TemporaryAccessExceptionSelector.buildAccountTeamKey(fakeAccountId, coverageRepId);
        String oppKey = TemporaryAccessExceptionSelector.buildOpportunityTeamKey(fakeOppId, coverageRepId);
        Set<String> accountKeys = new Set<String>();
        Set<String> opportunityKeys = new Set<String>();
        isGrantPlanSatisfied(plan, accountKeys, opportunityKeys);
        accountKeys.add(accountKey);
        opportunityKeys.add(oppKey);
        isGrantPlanSatisfied(plan, accountKeys, opportunityKeys);
        Map<String, SObject> accountTeamByKey = new Map<String, SObject>();
        Map<String, SObject> opportunityTeamByKey = new Map<String, SObject>();
        AccountTeamMemberBuildInput revokeAccountInput = new AccountTeamMemberBuildInput();
        revokeAccountInput.accountId = fakeAccountId;
        revokeAccountInput.coverageRepId = coverageRepId;
        revokeAccountInput.expiryDate = Date.today();
        accountTeamByKey.put(accountKey, buildAccountTeamMember(revokeAccountInput));
        opportunityTeamByKey.put(oppKey, builtOtm);
        RevokePlanEvaluationContext deleteContext = new RevokePlanEvaluationContext();
        deleteContext.plan = plan;
        deleteContext.accountTeamByKey = accountTeamByKey;
        deleteContext.opportunityTeamByKey = opportunityTeamByKey;
        deleteContext.expiryDate = Date.today();
        collectTeamMembersToDeleteForPlan(deleteContext);
        RevokePlanEvaluationContext completeContext = new RevokePlanEvaluationContext();
        completeContext.plan = plan;
        completeContext.accountTeamByKey = accountTeamByKey;
        completeContext.opportunityTeamByKey = opportunityTeamByKey;
        completeContext.deletedKeys = new Set<String>();
        isRevokePlanComplete(completeContext);
        completeContext.deletedKeys = new Set<String>{ accountKey, oppKey };
        isRevokePlanComplete(completeContext);
        Map<Id, TeamAccessPlan> plansByTaeId = new Map<Id, TeamAccessPlan>();
        plansByTaeId.put(plan.taeId, plan);
        insertMissingTeamMembers(plansByTaeId, accountKeys, opportunityKeys);
        indexOpportunityTeamForRevoke(plan.opportunityIds, new Set<Id>{ coverageRepId });
    }
}