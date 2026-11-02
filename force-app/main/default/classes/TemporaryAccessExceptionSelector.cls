/**
 * GC-2580 - SOQL-only selector for Temporary Access Exception batch processing.
 * @author Suraj Thapliyal
 * @date 2026/06/15
 * @description GC-2580 - SOQL-only selector for Temporary Access Exception batch processing.
 *              This class owns query logic only and does not perform business processing or DML.
 *              All queries use WITH USER_MODE (or delegate to selectors that do) for CRUD/FLS enforcement.
 */
public with sharing class TemporaryAccessExceptionSelector {

    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_ACTIVE = 'Active';
    public static final String STATUS_EXPIRED = 'Expired';

    /**
     * @description Input for temporary-assignment team member revoke queries.
     *              recordIds — Account or Opportunity Ids in revoke scope.
     *              coverageRepIds — Coverage rep user Ids from the current chunk.
     *              teamMemberRole — Team member role to match (Sales).
     *              assignmentType — AssignmentType__c value to match (Temporary Assignment).
     */
    public class RevokeTeamMemberCriteria {
        public Set<Id> recordIds;
        public Set<Id> coverageRepIds;
        public String teamMemberRole;
        public String assignmentType;
    }

    /**
     * @description GC-3179 - Modified: removed TemporaryAccessExceptionSecurity pre-check; WITH USER_MODE enforces access.
     *              Query locator for TemporaryAccessException__c rows eligible for nightly processing.
     *              Grant path: Approved + StartDate = today.
     *              Revoke path: Active + EndDate = today.
     * @return Query locator for eligible rows with Requester and Coverage Rep populated.
     */
    public static Database.QueryLocator getProcessingQueryLocator() {
        Date today = Date.today();
        return Database.getQueryLocator([
            SELECT Id, Name, StartDate__c, EndDate__c, Status__c, Requester__c, CoverageRep__c
            FROM TemporaryAccessException__c
            WHERE Requester__c != null
              AND CoverageRep__c != null
              AND (
                  (Status__c = :STATUS_APPROVED AND StartDate__c = :today)
                  OR (Status__c = :STATUS_ACTIVE AND EndDate__c = :today)
              )
            WITH USER_MODE
        ]);
    }
    /**
     * @description GC-3179 - Modified: removed TemporaryAccessExceptionSecurity pre-check; delegated query uses WITH USER_MODE.
     *              Loads AccountTeamMember rows for requesters to determine grant/revoke scope and access levels.
     * @param requesterIds User Ids from TemporaryAccessException__c.Requester__c.
     * @return AccountTeamMember rows for the given requesters.
     */
    public static List<AccountTeamMember> selectRequesterAccountTeamMembers(Set<Id> requesterIds) {
        if (requesterIds == null || requesterIds.isEmpty()) {
            return new List<AccountTeamMember>();
        }
        return AccountTeamMemberSelector.selectByUserIds(requesterIds);
    }
    /**
     * @description GC-3179 - Modified: removed TemporaryAccessExceptionSecurity pre-check; delegated query uses WITH USER_MODE.
     *              Loads OpportunityTeamMember rows for requesters to determine grant/revoke scope and access levels.
     * @param requesterIds User Ids from TemporaryAccessException__c.Requester__c.
     * @return OpportunityTeamMember rows for the given requesters.
     */
    public static List<OpportunityTeamMember> selectRequesterOpportunityTeamMembers(Set<Id> requesterIds) {
        if (requesterIds == null || requesterIds.isEmpty()) {
            return new List<OpportunityTeamMember>();
        }
        return OpportunityTeamMemberSelector.selectByUserIds(requesterIds);
    }
    /**
     * @description GC-3179 - Modified: removed TemporaryAccessExceptionSecurity pre-check; delegated query uses WITH USER_MODE.
     *              Loads Accounts owned by requesters to extend grant/revoke scope beyond team membership.
     * @param requesterIds User Ids from TemporaryAccessException__c.Requester__c.
     * @return Account rows owned by the given requesters.
     */
    public static List<Account> selectRequesterOwnedAccounts(Set<Id> requesterIds) {
        if (requesterIds == null || requesterIds.isEmpty()) {
            return new List<Account>();
        }
        return AccountSelector.selectByOwnerIds(requesterIds);
    }
    /**
     * @description GC-3179 - Modified: removed TemporaryAccessExceptionSecurity pre-check; delegated query uses WITH USER_MODE.
     *              Loads Opportunities owned by requesters to extend grant/revoke scope beyond team membership.
     * @param requesterIds User Ids from TemporaryAccessException__c.Requester__c.
     * @return Opportunity rows owned by the given requesters.
     */
    public static List<Opportunity> selectRequesterOwnedOpportunities(Set<Id> requesterIds) {
        if (requesterIds == null || requesterIds.isEmpty()) {
            return new List<Opportunity>();
        }
        return OpportunitySelector.selectByOwnerIds(requesterIds);
    }
    /**
     * @description GC-3179 - Modified: removed TemporaryAccessExceptionSecurity pre-check; delegated query uses WITH USER_MODE.
     *              Returns composite keys for coverage reps already on account teams (any role).
     * @param accountIds Account Ids in the current processing scope.
     * @param coverageRepIds User Ids from TemporaryAccessException__c.CoverageRep__c.
     * @return Set of accountId|userId composite keys.
     */
    public static Set<String> selectExistingCoverageRepAccountTeamKeys(
        Set<Id> accountIds,
        Set<Id> coverageRepIds
    ) {
        Set<String> keys = new Set<String>();
        if (accountIds == null || accountIds.isEmpty()
            || coverageRepIds == null || coverageRepIds.isEmpty()) {
            return keys;
        }
        for (AccountTeamMember atm : AccountTeamMemberSelector.selectByAccountsAndUsers(
            accountIds,
            coverageRepIds
        )) {
            keys.add(buildAccountTeamKey(atm.AccountId, atm.UserId));
        }
        return keys;
    }
    /**
     * @description GC-3179 - Modified: removed TemporaryAccessExceptionSecurity pre-check; delegated query uses WITH USER_MODE.
     *              Returns composite keys for coverage reps already on opportunity teams (any role).
     * @param opportunityIds Opportunity Ids in the current processing scope.
     * @param coverageRepIds User Ids from TemporaryAccessException__c.CoverageRep__c.
     * @return Set of opportunityId|userId composite keys.
     */
    public static Set<String> selectExistingCoverageRepOpportunityTeamKeys(
        Set<Id> opportunityIds,
        Set<Id> coverageRepIds
    ) {
        Set<String> keys = new Set<String>();
        if (opportunityIds == null || opportunityIds.isEmpty()
            || coverageRepIds == null || coverageRepIds.isEmpty()) {
            return keys;
        }
        for (OpportunityTeamMember otm : OpportunityTeamMemberSelector.selectByOpportunitiesAndUsers(
            opportunityIds,
            coverageRepIds
        )) {
            keys.add(buildOpportunityTeamKey(otm.OpportunityId, otm.UserId));
        }
        return keys;
    }
    /**
     * @description GC-3179 - Modified: removed TemporaryAccessExceptionSecurity pre-check; delegated query uses WITH USER_MODE.
     *              Queries AccountTeamMember rows eligible for revoke (temporary assignment only).
     * @param criteria Revoke query criteria including account Ids, coverage reps, role, and assignment type.
     * @return AccountTeamMember SObjects matching account, user, role, assignment type, and expiry.
     */
    public static List<SObject> selectTemporaryAssignmentAccountTeamMembersForRevoke(
        RevokeTeamMemberCriteria criteria
    ) {
        if (criteria == null
            || criteria.recordIds == null || criteria.recordIds.isEmpty()
            || criteria.coverageRepIds == null || criteria.coverageRepIds.isEmpty()) {
            return new List<SObject>();
        }
        List<SObject> results = new List<SObject>();
        results.addAll(
            AccountTeamMemberSelector.selectByAccountsUsersRoleAssignmentType(
                criteria.recordIds,
                criteria.coverageRepIds,
                criteria.teamMemberRole,
                criteria.assignmentType
            )
        );
        return results;
    }
    /**
     * @description GC-3179 - Modified: removed TemporaryAccessExceptionSecurity pre-check; delegated query uses WITH USER_MODE.
     *              Queries OpportunityTeamMember rows eligible for revoke (temporary assignment only).
     * @param criteria Revoke query criteria including opportunity Ids, coverage reps, role, and assignment type.
     * @return OpportunityTeamMember SObjects matching opportunity, user, role, assignment type, and expiry.
     */
    public static List<SObject> selectTemporaryAssignmentOpportunityTeamMembersForRevoke(
        RevokeTeamMemberCriteria criteria
    ) {
        if (criteria == null
            || criteria.recordIds == null || criteria.recordIds.isEmpty()
            || criteria.coverageRepIds == null || criteria.coverageRepIds.isEmpty()) {
            return new List<SObject>();
        }
        List<SObject> results = new List<SObject>();
        results.addAll(
            OpportunityTeamMemberSelector.selectByOpportunitiesUsersRoleAssignmentType(
                criteria.recordIds,
                criteria.coverageRepIds,
                criteria.teamMemberRole,
                criteria.assignmentType
            )
        );
        return results;
    }
    /**
     * @description GC-3179 - Modified: removed TemporaryAccessExceptionSecurity pre-check; inline SOQL uses WITH USER_MODE.
     *              Loads distinct TerritoryID__c values from OrderLineContact__c for each Rep Needing Coverage.
     *              Queries all OrderLineContact__c rows where AssignedSalesRep__c matches the given user Ids.
     *              Blank/null TerritoryID__c values are excluded. DeltaScenario__c is not filtered.
     * @param assignedSalesRepIds User Ids from TemporaryAccessException__c.Requester__c (Rep Needing Coverage).
     * @return Map of AssignedSalesRep__c Id to sorted, unique TerritoryID__c external Id list.
     */
    public static Map<Id, List<String>> selectDistinctTerritoryIdsByAssignedSalesRep(
        Set<Id> assignedSalesRepIds
    ) {
        Map<Id, Set<String>> territorySetByRepId = new Map<Id, Set<String>>();
        if (assignedSalesRepIds == null || assignedSalesRepIds.isEmpty()) {
            return new Map<Id, List<String>>();
        }

        for (OrderLineContact__c row : [
            SELECT AssignedSalesRep__c, TerritoryNumber__c
            FROM OrderLineContact__c
            WHERE AssignedSalesRep__c IN :assignedSalesRepIds
              AND TerritoryNumber__c != null
            WITH USER_MODE
        ]) {
            String territoryId = row.TerritoryNumber__c.trim();
            if (String.isBlank(territoryId)) {
                continue;
            }
            if (!territorySetByRepId.containsKey(row.AssignedSalesRep__c)) {
                territorySetByRepId.put(row.AssignedSalesRep__c, new Set<String>());
            }
            territorySetByRepId.get(row.AssignedSalesRep__c).add(territoryId);
        }

        Map<Id, List<String>> territoryIdsByRepId = new Map<Id, List<String>>();
        for (Id repId : territorySetByRepId.keySet()) {
            List<String> sortedTerritoryIds = new List<String>(territorySetByRepId.get(repId));
            sortedTerritoryIds.sort();
            territoryIdsByRepId.put(repId, sortedTerritoryIds);
        }
        return territoryIdsByRepId;
    }

    /**
     * @description GC-3179 - Modified: removed TemporaryAccessExceptionSecurity pre-check; delegated query uses WITH USER_MODE.
     *              Loads User records for email delivery.
     * @param userIds Requester and Coverage Rep user Ids.
     * @return Map of User Id to User (Email, Name).
     */
    public static Map<Id, User> selectUsersById(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return new Map<Id, User>();
        }
        return new Map<Id, User>(UserSelector.selectByIdsForEmail(userIds));
    }
    /**
     * @description GC-3179 - Modified: removed TemporaryAccessExceptionSecurity pre-check; delegated query uses WITH USER_MODE.
     *              GC-3189 - Loads Account names for grant notification email record links.
     * @param accountIds Account Ids in the processing scope.
     * @return Map of Account Id to Account Name.
     */
    public static Map<Id, Account> selectAccountsById(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new Map<Id, Account>();
        }
        return new Map<Id, Account>(AccountSelector.selectByIds(accountIds));
    }
    /**
     * @description GC-3179 - Modified: removed TemporaryAccessExceptionSecurity pre-check; delegated query uses WITH USER_MODE.
     *              GC-3189 - Loads Opportunity names for grant notification email record links.
     * @param opportunityIds Opportunity Ids in the processing scope.
     * @return Map of Opportunity Id to Opportunity Name.
     */
    public static Map<Id, Opportunity> selectOpportunitiesById(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return new Map<Id, Opportunity>();
        }
        return new Map<Id, Opportunity>(OpportunitySelector.selectByIds(opportunityIds));
    }
    /**
     * @description Indicates whether a row should grant temporary coverage rep access.
     * @param row TemporaryAccessException__c from the batch scope.
     * @return True when Status is Approved and StartDate is today.
     */
    public static Boolean isGrantScenario(TemporaryAccessException__c row) {
        return row != null
            && STATUS_APPROVED == row.Status__c
            && row.StartDate__c == Date.today();
    }
    /**
     * @description Indicates whether a row should revoke temporary coverage rep access.
     * @param row TemporaryAccessException__c from the batch scope.
     * @return True when Status is Active and EndDate is today.
     */
    public static Boolean isRevokeScenario(TemporaryAccessException__c row) {
        return row != null
            && STATUS_ACTIVE == row.Status__c
            && row.EndDate__c == Date.today();
    }
    /**
     * @description Builds the Account Team composite key used for duplicate prevention.
     * @param accountId Account Id.
     * @param userId User Id.
     * @return Composite key in accountId|userId format.
     */
    public static String buildAccountTeamKey(Id accountId, Id userId) {
        return String.valueOf(accountId) + '|' + String.valueOf(userId);
    }
    /**
     * @description Builds the Opportunity Team composite key used for duplicate prevention.
     * @param opportunityId Opportunity Id.
     * @param userId User Id.
     * @return Composite key in opportunityId|userId format.
     */
    public static String buildOpportunityTeamKey(Id opportunityId, Id userId) {
        return String.valueOf(opportunityId) + '|' + String.valueOf(userId);
    }
}