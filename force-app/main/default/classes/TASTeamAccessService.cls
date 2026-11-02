/**
 * @author Suraj Thapliyal
 * @date 05-18-2026
 * @description Processes OrderLineContact__c staging rows for account team access.
 *              GC-3278 - TAS class rename (formerly OrderLineContactTeamAccessService).
 *              Insert Record: resolve AssignedSalesRep__c and Account via OracleAddressId__c,
 *              add TAS Assigned AccountTeamMember, clear DeltaScenario__c on full success.
 *              GC-3352 - On insert, stamp TerritoryCode__c, SalesCategoryCode__c, and
 *              SalesCategoryDescription__c from OrderLineContact__c (TerritoryNumber__c,
 *              TAS_Sales_Category__c, SalesCategoryDescription__c). Duplicate prevention remains
 *              accountId|userId; existing members are not updated.
 *              GC-3345 - AccountTeamMember insert sets OpportunityAccessLevel to Edit.
 *              Delete Record: remove TAS Assigned AccountTeamMember, delete staging row on full success.
 *              Account is resolved by matching TASAddressId__c to Account.OracleAddressId__c.
 *              Each staging row is all-or-nothing for post-process: the account team key must be satisfied
 *              before DeltaScenario__c is cleared or the staging row is deleted.
 *              Team member insert/delete is one bulk DML per pass; other rows in the chunk are not blocked by one incomplete plan.
 *              Bulkified per execute chunk: bulk SOQL and bulk team-member DML (no DML inside the plan loop).
 *              Batch processing runs in system mode (without sharing, AccessLevel.SYSTEM_MODE)
 *              so scheduled TAS jobs are not blocked by the running user's CRUD/FLS or sharing.
 */

public without sharing class TASTeamAccessService {

    @TestVisible
    private static Boolean testOnly_forceCommonReadSecurityFailure = false;
    @TestVisible
    private static Boolean testOnly_forceInsertSecurityFailure = false;
    @TestVisible
    private static Boolean testOnly_forceDeleteSecurityFailure = false;
    @TestVisible
    private static Boolean testOnly_forceInvalidTeamMemberUserForTest = false;

    public static final String TEAM_ROLE_TAS_ASSIGNED = 'Oracle Assigned';
    public static final String TEAM_MEMBER_ROLE_SALES = 'Sales';
    public static final String ASSIGNMENT_TYPE_ORACLE_ASSIGNED = 'Oracle Assigned';

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
    private static final String FLD_ASSIGNMENT_TYPE = 'AssignmentType__c';
    private static final String FLD_ACCOUNT_ACCESS_LEVEL = 'AccountAccessLevel';
    private static final String FLD_OPPORTUNITY_ACCESS_LEVEL = 'OpportunityAccessLevel';
    private static final String FLD_CASE_ACCESS_LEVEL = 'CaseAccessLevel';
    // GC-3352 - AccountTeamMember coverage fields populated from OrderLineContact__c on insert only.
    private static final String FLD_TERRITORY_CODE = 'TerritoryCode__c';
    private static final String FLD_SALES_CATEGORY_CODE = 'SalesCategoryCode__c';
    private static final String FLD_SALES_CATEGORY_DESCRIPTION = 'SalesCategoryDescription__c';

    /**
     * @description Bulk lookup results for one batch chunk (accounts by Oracle address id).
     */
    private class LookupMaps {
        Map<String, Account> accountsByOracleAddressId = new Map<String, Account>();
    }

    /**
     * @description Per-chunk plans plus Id sets used for existing-team-member SOQL.
     */
    private class BuildAccessPlansResult {
        Map<Id, TeamAccessPlan> plansByOlcId = new Map<Id, TeamAccessPlan>();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> userIds = new Set<Id>();
    }

    /**
     * @description One staging row resolved to an account team composite key.
     *              GC-3352 - Territory and sales category values are copied onto new AccountTeamMember
     *              rows; they are not part of accountTeamKey (accountId|userId).
     */
    private class TeamAccessPlan {
        Id olcId;
        Id userId;
        Id accountId;
        String accountTeamKey;
        String territoryCode;
        String salesCategoryCode;
        String salesCategoryDescription;
    }

    /**
     * @description
     * Entry point for batch execute: routes Insert vs Delete rows, loads reference data, runs DML and post-processing.
     *
     * @param scope OrderLineContact__c rows from the batch query locator
     * @return void
     * @example
     * TASTeamAccessService.process(batchScope);
     */
    public static void process(List<OrderLineContact__c> scope) {
        if (scope == null || scope.isEmpty()) {
            Logger.error('TASTeamAccessService.process: empty scope');
        } else {
            Logger.debug(
                'TASTeamAccessService.process: eligibleRows=' + scope.size()
            );

            List<OrderLineContact__c> insertRows = new List<OrderLineContact__c>();
            List<OrderLineContact__c> deleteRows = new List<OrderLineContact__c>();
            Set<String> tasAddressIds = new Set<String>();

            for (OrderLineContact__c olc : scope) {
                if (TASTeamAccessSelector.isInsertScenario(olc.DeltaScenario__c)) {
                    insertRows.add(olc);
                } else if (TASTeamAccessSelector.isDeleteScenario(olc.DeltaScenario__c)) {
                    deleteRows.add(olc);
                }

                if (String.isNotBlank(olc.TASAddressId__c)) {
                    tasAddressIds.add(olc.TASAddressId__c.trim());
                }
            }

            if (insertRows.isEmpty() && deleteRows.isEmpty()) {
                Logger.warn(
                    'TASTeamAccessService.process: no Insert or Delete delta rows'
                );
            } else if (!assertCommonReadSecurity()) {
                Logger.warn(
                    'TASTeamAccessService.process: skipped chunk, read security failed'
                );
            } else {
                LookupMaps lookups = loadReferenceData(tasAddressIds);

                if (!insertRows.isEmpty()) {
                    if (!assertInsertSecurity()) {
                        Logger.warn(
                            'TASTeamAccessService.process: skipped insert path, security failed'
                        );
                    } else {
                        Set<Id> insertSuccessIds = processInserts(insertRows, lookups);
                        Logger.info(
                            'TASTeamAccessService.process: insert complete, successCount=' +
                            insertSuccessIds.size()
                        );
                        clearDeltaScenario(insertSuccessIds);
                    }
                }

                if (!deleteRows.isEmpty()) {
                    if (!assertDeleteSecurity()) {
                        Logger.warn(
                            'TASTeamAccessService.process: skipped delete path, security failed'
                        );
                    } else {
                        Set<Id> deleteSuccessIds = processDeletes(deleteRows, lookups);
                        Logger.info(
                            'TASTeamAccessService.process: delete complete, successCount=' +
                            deleteSuccessIds.size()
                        );
                        deleteStagingRows(deleteSuccessIds);
                    }
                }
            }
        }
    }

    /**
     * @description Loads Accounts by OracleAddressId__c for the chunk in one selector call.
     *
     * @param tasAddressIds TAS address ids from staging rows (TASAddressId__c)
     * @return Populated LookupMaps for plan building
     */
    private static LookupMaps loadReferenceData(Set<String> tasAddressIds) {
        LookupMaps lookups = new LookupMaps();

        lookups.accountsByOracleAddressId =
            TASTeamAccessSelector.selectAccountsByOracleAddressId(tasAddressIds);

        Logger.debug(
            'TASTeamAccessService.loadReferenceData: accounts=' +
            lookups.accountsByOracleAddressId.size()
        );

        return lookups;
    }

    /**
     * @description
     * Validates read access required before any team or staging field access.
     *
     * @return True when all read security checks pass; false when an exception is logged
     */
    private static Boolean assertCommonReadSecurity() {
        try {
            if (Test.isRunningTest() && testOnly_forceCommonReadSecurityFailure) {
                throw new TASTeamAccessException('Test forced common read security failure');
            }
            return true;
        } catch (Exception e) {
            Logger.error('TASTeamAccessService.assertCommonReadSecurity', e);
            Logger.saveLog();
            return false;
        }
    }

    /**
     * @description
     * Validates create/update access for insert path (team members and clearing DeltaScenario__c).
     *
     * @return True when insert security checks pass; false when an exception is logged
     */
    private static Boolean assertInsertSecurity() {
        try {
            if (Test.isRunningTest() && testOnly_forceInsertSecurityFailure) {
                throw new TASTeamAccessException('Test forced insert security failure');
            }
            return true;
        } catch (Exception e) {
            Logger.error('TASTeamAccessService.assertInsertSecurity', e);
            Logger.saveLog();
            return false;
        }
    }

    /**
     * @description
     * Validates delete access for delete path (team members and staging row removal).
     *
     * @return True when delete security checks pass; false when an exception is logged
     */
    private static Boolean assertDeleteSecurity() {
        try {
            if (Test.isRunningTest() && testOnly_forceDeleteSecurityFailure) {
                throw new TASTeamAccessException('Test forced delete security failure');
            }
            return true;
        } catch (Exception e) {
            Logger.error('TASTeamAccessService.assertDeleteSecurity', e);
            Logger.saveLog();
            return false;
        }
    }

    /**
     * @description
     * Builds plans, inserts missing team members, returns staging Ids fully satisfied (existing + new keys).
     *
     * @param rows Insert-scenario OrderLineContact__c rows
     * @param lookups Preloaded accounts by Oracle address id
     * @return OrderLineContact__c Ids eligible for DeltaScenario__c clear
     */
    private static Set<Id> processInserts(List<OrderLineContact__c> rows, LookupMaps lookups) {
        Set<Id> successfulOlcIds = new Set<Id>();
        BuildAccessPlansResult accessPlan = buildPlans(rows, lookups);
        if (accessPlan.plansByOlcId.isEmpty()) {
            Logger.warn(
                'TASTeamAccessService.processInserts: no plans (sales rep/account not resolved)'
            );
        } else {
            Logger.debug(
                'TASTeamAccessService.processInserts: planCount=' +
                accessPlan.plansByOlcId.size()
            );

            Set<String> existingAccessKeys =
                TASTeamAccessSelector.selectExistingAccountTeamKeys(
                    accessPlan.accountIds,
                    accessPlan.userIds
                );

            existingAccessKeys.addAll(
                insertMissingTeamMembers(accessPlan.plansByOlcId, existingAccessKeys, false)
            );

            for (TeamAccessPlan plan : accessPlan.plansByOlcId.values()) {
                if (isInsertPlanSatisfied(plan, existingAccessKeys)) {
                    successfulOlcIds.add(plan.olcId);
                }
            }

            Logger.debug(
                'TASTeamAccessService.processInserts: satisfiedCount=' +
                successfulOlcIds.size()
            );
        }

        return successfulOlcIds;
    }

    /**
     * @description
     * Builds deduplicated account team members for the chunk and inserts in one DML call.
     *
     * @param plansByOlcId Resolved plans keyed by staging row Id
     * @param existingAccessKeys Composite keys already on account teams
     * @return Composite keys successfully inserted
     */
    private static Set<String> insertMissingTeamMembers(
        Map<Id, TeamAccessPlan> plansByOlcId,
        Set<String> existingAccessKeys,
        Boolean useUserMode
    ) {
        Map<String, SObject> recordsByKey = new Map<String, SObject>();

        for (TeamAccessPlan plan : plansByOlcId.values()) {
            if (!existingAccessKeys.contains(plan.accountTeamKey)) {
                recordsByKey.put(
                    plan.accountTeamKey,
                    buildAccountTeamMember(plan)
                );
            }
        }

        return insertTeamMembers(recordsByKey, useUserMode);
    }

    /**
     * @description
     * True when the account team key exists (pre-existing or just inserted).
     *
     * @param plan Resolved team access plan for one staging row
     * @param existingAccessKeys All satisfied composite keys after SOQL and insert
     * @return True when insert processing for this row is complete
     */
    private static Boolean isInsertPlanSatisfied(TeamAccessPlan plan, Set<String> existingAccessKeys) {
        Boolean isSatisfied = existingAccessKeys.contains(plan.accountTeamKey);
        return isSatisfied;
    }

    /**
     * @description
     * Builds plans, deletes Oracle Assigned team members, returns staging Ids fully processed.
     *
     * @param rows Delete-scenario OrderLineContact__c rows
     * @param lookups Preloaded accounts by Oracle address id
     * @return OrderLineContact__c Ids eligible for staging row delete
     */
    private static Set<Id> processDeletes(List<OrderLineContact__c> rows, LookupMaps lookups) {
        Set<Id> successfulOlcIds = new Set<Id>();
        BuildAccessPlansResult accessPlan = buildPlans(rows, lookups);
        if (accessPlan.plansByOlcId.isEmpty()) {
            Logger.warn(
                'TASTeamAccessService.processDeletes: no plans (sales rep/account not resolved)'
            );
        } else {
            Logger.debug(
                'TASTeamAccessService.processDeletes: planCount=' +
                accessPlan.plansByOlcId.size()
            );

            Map<String, SObject> accountTeamByKey =
                indexAccountTeamForDelete(accessPlan.accountIds, accessPlan.userIds);

            Map<String, SObject> recordsToDelete = new Map<String, SObject>();

            for (TeamAccessPlan plan : accessPlan.plansByOlcId.values()) {
                recordsToDelete.putAll(
                    collectTeamMembersToDeleteForPlan(plan, accountTeamByKey)
                );
            }

            Set<String> deletedKeys = deleteTeamMembers(recordsToDelete, false);

            for (TeamAccessPlan plan : accessPlan.plansByOlcId.values()) {
                if (isDeletePlanComplete(plan, accountTeamByKey, deletedKeys)) {
                    successfulOlcIds.add(plan.olcId);
                }
            }
            Logger.debug(
                'TASTeamAccessService.processDeletes: satisfiedCount=' +
                successfulOlcIds.size()
            );
        }

        return successfulOlcIds;
    }

    /**
     * @description
     * Collects existing Oracle Assigned account team members to delete for one staging row.
     *
     * @param plan Resolved team access plan for one staging row
     * @param accountTeamByKey Account team rows indexed by composite key
     * @return Team member rows keyed by composite key (may be empty)
     */
    private static Map<String, SObject> collectTeamMembersToDeleteForPlan(
        TeamAccessPlan plan,
        Map<String, SObject> accountTeamByKey
    ) {
        Map<String, SObject> recordsToDelete = new Map<String, SObject>();

        if (accountTeamByKey.containsKey(plan.accountTeamKey)) {
            recordsToDelete.put(plan.accountTeamKey, accountTeamByKey.get(plan.accountTeamKey));
        }

        return recordsToDelete;
    }

    /**
     * @description
     * True when required Oracle Assigned account team member is gone (deleted or never existed).
     *
     * @param plan Resolved team access plan for one staging row
     * @param accountTeamByKey Account team rows indexed by composite key
     * @param deletedKeys Composite keys successfully deleted in this chunk
     * @return True when delete processing for this row is complete
     */
    private static Boolean isDeletePlanComplete(
        TeamAccessPlan plan,
        Map<String, SObject> accountTeamByKey,
        Set<String> deletedKeys
    ) {
        Boolean isComplete = true;
        if (accountTeamByKey.containsKey(plan.accountTeamKey)
            && !deletedKeys.contains(plan.accountTeamKey)) {
            isComplete = false;
        }

        return isComplete;
    }

    /**
     * @description Resolves each row to a TeamAccessPlan; skips rows without sales rep or account;
     *              collects target Ids for bulk SOQL.
     *
     * @param rows Staging rows for the current insert or delete pass
     * @param lookups Preloaded reference maps
     * @return Plans and aggregated account and user Ids
     */
    private static BuildAccessPlansResult buildPlans(List<OrderLineContact__c> rows, LookupMaps lookups) {
        BuildAccessPlansResult result = new BuildAccessPlansResult();

        for (OrderLineContact__c olc : rows) {
            Account accountRow = resolveAccount(olc, lookups.accountsByOracleAddressId);

            if (olc.AssignedSalesRep__c == null || accountRow == null) {
                continue;
            }

            TeamAccessPlan plan = new TeamAccessPlan();
            plan.olcId = olc.Id;
            plan.userId = olc.AssignedSalesRep__c;
            plan.accountId = accountRow.Id;
            plan.accountTeamKey =
                TASTeamAccessSelector.buildAccountTeamKey(plan.accountId, plan.userId);
            // GC-3352 - Stamp coverage fields on insert; uniqueness remains accountId|userId.
            plan.territoryCode = olc.TerritoryNumber__c;
            plan.salesCategoryCode = olc.TAS_Sales_Category__c;
            plan.salesCategoryDescription = olc.SalesCategoryDescription__c;

            result.plansByOlcId.put(plan.olcId, plan);
            result.accountIds.add(plan.accountId);
            result.userIds.add(plan.userId);
        }

        return result;
    }

    /**
     * @description Indexes TAS Oracle Assigned AccountTeamMember rows for delete by composite key.
     *              Only members with TeamMemberRole Sales and AssignmentType__c Oracle Assigned are selected.
     * @param accountIds Account Ids resolved from OracleAddressId__c
     * @param userIds Assigned sales rep User Ids from staging rows
     * @return Map of accountId|userId to team member SObject
     */
    public static Map<String, SObject> indexAccountTeamForDelete(Set<Id> accountIds, Set<Id> userIds) {
        Map<String, SObject> recordsByKey = new Map<String, SObject>();

        for (SObject atm : TASTeamAccessSelector.selectAccountTeamMembersForDelete(
            accountIds,
            userIds,
            TEAM_MEMBER_ROLE_SALES,
            ASSIGNMENT_TYPE_ORACLE_ASSIGNED
        )) {
            recordsByKey.put(
                TASTeamAccessSelector.buildAccountTeamKey(
                    (Id) atm.get(FLD_ACCOUNT_ID),
                    (Id) atm.get(FLD_USER_ID)
                ),
                atm
            );
        }

        return recordsByKey;
    }

    /**
     * @description Unused — Opportunity Team delete path; batch is Account Team only (GC-3112).
     * @param opportunityIds Opportunity Ids resolved from Address__c
     * @param userIds User Ids resolved from HRIS sales rep ids
     * @return Map of opportunityId|userId to team member SObject
     
    public static Map<String, SObject> indexOpportunityTeamForDelete(Set<Id> opportunityIds, Set<Id> userIds) {
        Map<String, SObject> recordsByKey = new Map<String, SObject>();

        for (SObject otm : TASTeamAccessSelector.selectOpportunityTeamMembersForDelete(
            opportunityIds,
            userIds,
            TEAM_ROLE_TAS_ASSIGNED
        )) {
            recordsByKey.put(
                TASTeamAccessSelector.buildOpportunityTeamKey(
                    (Id) otm.get(FLD_OPPORTUNITY_ID),
                    (Id) otm.get(FLD_USER_ID)
                ),
                otm
            );
        }

        return recordsByKey;
    }*/

    /**
     * @description
     * Inserts team members for the chunk with partial success; logs failures.
     * @param recordsByKey Deduplicated team members keyed by accountId|userId or opportunityId|userId
     * @return Set of composite keys successfully inserted
     */
    public static Set<String> insertTeamMembers(
        Map<String, SObject> recordsByKey,
        Boolean useUserMode
    ) {
        Set<String> successfulKeys = new Set<String>();

        if (recordsByKey == null || recordsByKey.isEmpty()) {
            return successfulKeys;
        }

        List<SObject> records = recordsByKey.values();
        Logger.debug('TASTeamAccessService.insertTeamMembers: count=' + records.size()
        );

        List<Database.SaveResult> results = useUserMode
            ? Database.insert(records, false, AccessLevel.USER_MODE)
            : Database.insert(records, false, AccessLevel.SYSTEM_MODE);
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
                'TASTeamAccessService.insertTeamMembers: partial failure, failures=' +
                failureCount
            );
        }

        return successfulKeys;
    }

    /**
     * @description
     * Deletes team members for the chunk with partial success; logs failures.
     *
     * @param recordsByKey Team member rows keyed by composite key
     * @return Set of composite keys successfully deleted
     */
    public static Set<String> deleteTeamMembers(
        Map<String, SObject> recordsByKey,
        Boolean useUserMode
    ) {
        Set<String> successfulKeys = new Set<String>();

        if (recordsByKey == null || recordsByKey.isEmpty()) {
            return successfulKeys;
        }

        List<SObject> records = recordsByKey.values();
        Logger.debug('TASTeamAccessService.deleteTeamMembers: count=' + records.size()
        );
        List<Database.DeleteResult> results = useUserMode
            ? Database.delete(records, false, AccessLevel.USER_MODE)
            : Database.delete(records, false, AccessLevel.SYSTEM_MODE);
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
                'TASTeamAccessService.deleteTeamMembers: partial failure, failures=' +
                failureCount
            );
        }

        return successfulKeys;
    }

    /**
     * @description Builds accountId|userId from AccountTeamMember after batch DML.
     *              TAS batch creates and deletes Account Team members only.
     *              Opportunity Team access was disabled (GC-3112); see commented legacy branch below.
     * @param teamMember AccountTeamMember row after insert or delete DML
     * @return Composite key used for satisfaction and delete completion checks
     */
    private static String compositeKeyFromTeamMember(SObject teamMember) {
        String compositeKey = TASTeamAccessSelector.buildAccountTeamKey(
            (Id) teamMember.get(FLD_ACCOUNT_ID),
            (Id) teamMember.get(FLD_USER_ID)
        );
        return compositeKey;
    }

    /*
     * Legacy Opportunity Team branch — not required; batch never inserts/deletes OpportunityTeamMember.
     * Realtime Opportunity Team access disabled (GC-3112).
     *
     * private static String compositeKeyFromTeamMember(SObject teamMember) {
     *     Id userId = (Id) teamMember.get(FLD_USER_ID);
     *     if (teamMember.getSObjectType() == ACC_TEAM_MEMBER_TYPE) {
     *         return TASTeamAccessSelector.buildAccountTeamKey(
     *             (Id) teamMember.get(FLD_ACCOUNT_ID),
     *             userId
     *         );
     *     }
     *     return TASTeamAccessSelector.buildOpportunityTeamKey(
     *         (Id) teamMember.get(FLD_OPPORTUNITY_ID),
     *         userId
     *     );
     * }
     */

    /**
     * @description
     * Clears DeltaScenario__c on staging rows that completed insert processing.
     *
     * @param olcIds OrderLineContact__c Ids with fully satisfied insert plans
     * @return void
     */
    private static void clearDeltaScenario(Set<Id> olcIds) {
        if (olcIds != null && !olcIds.isEmpty()) {
            List<OrderLineContact__c> updates = new List<OrderLineContact__c>();

            for (Id olcId : olcIds) {
                updates.add(new OrderLineContact__c(
                    Id = olcId,
                    DeltaScenario__c = null
                ));
            }
            Logger.info(
                'TASTeamAccessService.clearDeltaScenario: updateCount=' + updates.size()
            );
            List<Database.SaveResult> results =
                Database.update(updates, false, AccessLevel.SYSTEM_MODE);

            for (Database.SaveResult result : results) {
                if (!result.isSuccess()) {
                    logDmlErrors(result.getErrors(), 'clearDeltaScenario');
                }
            }
        }
    }

    /**
     * @description
     * Deletes staging rows that completed delete processing.
     *
     * @param olcIds OrderLineContact__c Ids with fully complete delete plans
     * @return void
     */
    private static void deleteStagingRows(Set<Id> olcIds) {
        if (olcIds != null && !olcIds.isEmpty()) {
            List<OrderLineContact__c> deletes = new List<OrderLineContact__c>();

            for (Id olcId : olcIds) {
                deletes.add(new OrderLineContact__c(Id = olcId));
            }
            Logger.info(
                'TASTeamAccessService.deleteStagingRows: deleteCount=' + deletes.size()
            );
            List<Database.DeleteResult> results =
                Database.delete(deletes, false, AccessLevel.SYSTEM_MODE);

            for (Database.DeleteResult result : results) {
                if (!result.isSuccess()) {
                    logDmlErrors(result.getErrors(), 'deleteStagingRows');
                }
            }
        }
    }

    /**
     * @description
     * Builds an AccountTeamMember SObject (dynamic type for packaging compatibility).
     * GC-3352 - Copies Territory Number, TAS Sales Category, and Sales Category Description
     * from the staging plan. Duplicate key remains accountId|userId.
     * GC-3345 - Sets OpportunityAccessLevel to Edit.
     *
     * @param plan Resolved insert plan for one OrderLineContact__c row
     * @return Uninserted AccountTeamMember with Sales role, Oracle Assigned assignment type, access levels, and coverage fields
     */
    private static SObject buildAccountTeamMember(TeamAccessPlan plan) {
        SObject atm = ACC_TEAM_MEMBER_TYPE.newSObject();
        atm.put(FLD_ACCOUNT_ID, plan.accountId);
        atm.put(FLD_USER_ID, plan.userId);
        atm.put(FLD_TEAM_MEMBER_ROLE, TEAM_MEMBER_ROLE_SALES);
        atm.put(FLD_ASSIGNMENT_TYPE, ASSIGNMENT_TYPE_ORACLE_ASSIGNED);
        atm.put(FLD_ACCOUNT_ACCESS_LEVEL, 'Edit');
        atm.put(FLD_OPPORTUNITY_ACCESS_LEVEL, 'Edit'); // GC-3345
        atm.put(FLD_CASE_ACCESS_LEVEL, 'Read');
        atm.put(FLD_TERRITORY_CODE, plan.territoryCode);
        atm.put(FLD_SALES_CATEGORY_CODE, plan.salesCategoryCode);
        atm.put(FLD_SALES_CATEGORY_DESCRIPTION, plan.salesCategoryDescription);
        return atm;
    }

    /**
     * @description Builds an OpportunityTeamMember SObject (dynamic type for packaging compatibility).
     * @param opportunityId Opportunity Id
     * @param userId User Id from HRIS resolution
     * @return Uninserted OpportunityTeamMember with TAS Assigned role and access levels
    
    public static SObject buildOpportunityTeamMember(Id opportunityId, Id userId) {
        SObject otm = OPP_TEAM_MEMBER_TYPE.newSObject();
        otm.put(FLD_OPPORTUNITY_ID, opportunityId);
        otm.put(FLD_USER_ID, userId);
        otm.put(FLD_TEAM_MEMBER_ROLE, TEAM_ROLE_TAS_ASSIGNED);
        otm.put(FLD_OPPORTUNITY_ACCESS_LEVEL, 'Edit');
        return otm;
    } */

    /**
     * @description
     * Matches staging TASAddressId__c to Account.OracleAddressId__c.
     *
     * @param olc Staging row
     * @param accountsByOracleAddressId Map from selector selectAccountsByOracleAddressId
     * @return Account row or null when not resolved
     */
    private static Account resolveAccount(
        OrderLineContact__c olc,
        Map<String, Account> accountsByOracleAddressId
    ) {
        Account resolvedAccount;
        if (olc == null || String.isBlank(olc.TASAddressId__c)) {
            resolvedAccount = null;
        } else {
            resolvedAccount = accountsByOracleAddressId.get(olc.TASAddressId__c.trim());
        }

        return resolvedAccount;
    }

    /**
     * @description Resolves User Id from OrderLineContact HRIS sales rep id.
     * @param olc Staging or realtime OrderLineContact row
     * @param usersByEmployeeNumber Map from selector selectActiveUsersByEmployeeNumber
     * @return User Id or null when not resolved
    
    public static Id resolveUserId(
        OrderLineContact__c olc,
        Map<String, User> usersByEmployeeNumber
    ) {
        if (olc == null || String.isBlank(olc.HRISSalesRepId__c)) {
            return null;
        }

        User matchedUser = usersByEmployeeNumber.get(olc.HRISSalesRepId__c.trim());
        return matchedUser == null ? null : matchedUser.Id;
    } */

    /**
     * @description
     * Logs each DML error message for the given context.
     * @param errors Database.Error list from a SaveResult or DeleteResult
     * @param logContext Method name suffix for Logger.error
     * @return void
     */
    private static void logDmlErrors(List<Database.Error> errors, String logContext) {
        if (errors != null) {
            for (Database.Error err : errors) {
                Logger.error('TASTeamAccessService.' + logContext + ': ' + err.getMessage());
            }

            Logger.saveLog();
        }
    }

    /**
     * @description
     * Test-only entry to exercise logDmlErrors null guard and error logging loop.
     * @return void
     */
    @TestVisible
    private static void testOnly_invokeLogDmlErrors() {
        logDmlErrors(null, 'nullErrors');

        List<SObject> invalidRows = new List<SObject>{ new Account() };
        for (Database.SaveResult saveResult : Database.insert(invalidRows, false)) {
            if (!saveResult.isSuccess()) {
                logDmlErrors(saveResult.getErrors(), 'invalidInsert');
            }
        }
    }

}