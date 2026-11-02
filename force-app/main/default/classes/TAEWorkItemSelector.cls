/**
 * GC-3420 - Query-only selector for the serialized TAE work-item pipeline.
 * @author Suraj Thapliyal
 * @date 2026/09/29
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-3420 - SOQL for the work-item grant, revoke, and cleanup jobs.
 * This class does not call TemporaryAccessExceptionSelector.
 * Queries run WITH SYSTEM_MODE. DML stays in the service and batches.
 * GC-3482 - handbackLocator finds open records the Coverage Rep owns on the covered accounts.
 * Each call queries one object so a single transaction does not load opportunities, tasks, events, and contacts together.
 */
public with sharing class TAEWorkItemSelector {
    /**
     * @description Prevents construction. All methods are static.
     */
    private TAEWorkItemSelector() {
        throw new TAEWorkItemException('TAEWorkItemSelector is not constructable.');
    }

    /**
     * @description Exceptions due today: Approved and Start Date today, or Active and End Date today.
     * @return Query locator ordered by CreatedDate, then Id.
     */
    public static Database.QueryLocator eligibleTaeLocator() {
        Date today = Date.today();
        return Database.getQueryLocator([
            SELECT Id, Requester__c, CoverageRep__c, StartDate__c, EndDate__c, Status__c,
                ProcessingOperation__c, WorkItemsCreated__c
            FROM TemporaryAccessException__c
            WHERE Requester__c != null
              AND CoverageRep__c != null
              AND (
                  (Status__c = 'Approved' AND StartDate__c = :today)
                  OR (Status__c = 'Active' AND EndDate__c = :today)
              )
            WITH SYSTEM_MODE
            ORDER BY CreatedDate, Id
        ]);
    }

    /**
     * @description Loads one exception header used by plan building, workers, and email.
     * @param taeId TemporaryAccessException__c Id.
     * @return The exception, or null when it is not visible.
     */
    public static TemporaryAccessException__c selectTae(Id taeId) {
        List<TemporaryAccessException__c> rows = [
            SELECT Id, Name, Requester__c, CoverageRep__c, StartDate__c, EndDate__c,
                Status__c, ProcessingOperation__c, WorkItemsCreated__c
            FROM TemporaryAccessException__c
            WHERE Id = :taeId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        TemporaryAccessException__c header = null;
        if (!rows.isEmpty()) {
            header = rows[0];
        }
        return header;
    }

    /**
     * @description Processing Grant or Revoke exceptions, oldest LastModifiedDate first.
     * @return Up to 200 Processing exceptions.
     */
    public static List<TemporaryAccessException__c> selectProcessingTaes() {
        List<TemporaryAccessException__c> headers = [
            SELECT Id, Name, Requester__c, CoverageRep__c, StartDate__c, EndDate__c,
                Status__c, ProcessingOperation__c, WorkItemsCreated__c
            FROM TemporaryAccessException__c
            WHERE Status__c = 'Processing'
              AND ProcessingOperation__c IN ('Grant', 'Revoke')
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate, Id
            LIMIT 200
        ];
        return headers;
    }

    /**
     * @description Account Team Members for the Requester, including access and territory fields.
     * @param requesterId Requester user Id.
     * @return Team rows used to build the account book and to copy access onto the Coverage Rep.
     */
    public static List<AccountTeamMember> requesterAccountTeams(Id requesterId) {
        List<AccountTeamMember> teams = [
            SELECT Id, AccountId, UserId, TeamMemberRole, AccountAccessLevel,
                OpportunityAccessLevel, CaseAccessLevel, TerritoryCode__c,
                SalesCategoryCode__c, SalesCategoryDescription__c
            FROM AccountTeamMember
            WHERE UserId = :requesterId
            WITH SYSTEM_MODE
        ];
        return teams;
    }

    /**
     * @description Opportunity Team Members for the Requester.
     * @param requesterId Requester user Id.
     * @return Team rows used to build the opportunity book.
     */
    public static List<OpportunityTeamMember> requesterOpportunityTeams(Id requesterId) {
        List<OpportunityTeamMember> teams = [
            SELECT Id, OpportunityId, UserId, TeamMemberRole, OpportunityAccessLevel
            FROM OpportunityTeamMember
            WHERE UserId = :requesterId
            WITH SYSTEM_MODE
        ];
        return teams;
    }

    /**
     * @description Requester Account Team Members for the accounts in the current chunk.
     * @param accountIds Account Ids in the worker scope.
     * @param requesterId Requester user Id.
     * @return Account Id to the Requester's team row.
     */
    public static Map<Id, AccountTeamMember> requesterAccountTeamsByAccount(
        Set<Id> accountIds,
        Id requesterId
    ) {
        Map<Id, AccountTeamMember> result = new Map<Id, AccountTeamMember>();
        if (accountIds == null || accountIds.isEmpty() || requesterId == null) {
            return result;
        }
        for (AccountTeamMember row : [
            SELECT Id, AccountId, UserId, AccountAccessLevel, CaseAccessLevel,
                TerritoryCode__c, SalesCategoryCode__c, SalesCategoryDescription__c
            FROM AccountTeamMember
            WHERE AccountId IN :accountIds AND UserId = :requesterId
            WITH SYSTEM_MODE
        ]) {
            result.put(row.AccountId, row);
        }
        return result;
    }

    /**
     * @description Accounts in the chunk that the Requester owns.
     * @param accountIds Account Ids in the worker scope.
     * @param requesterId Requester user Id.
     * @return Owned Account Ids. Ownership drives Edit access on the new team row.
     */
    public static Set<Id> requesterOwnedAccountIds(Set<Id> accountIds, Id requesterId) {
        Set<Id> result = new Set<Id>();
        if (accountIds == null || accountIds.isEmpty() || requesterId == null) {
            return result;
        }
        for (Account row : [
            SELECT Id FROM Account WHERE Id IN :accountIds AND OwnerId = :requesterId WITH SYSTEM_MODE
        ]) {
            result.add(row.Id);
        }
        return result;
    }

    /**
     * @description All Accounts owned by the Requester.
     * @param requesterId Requester user Id.
     * @return Account Ids added to the grant or revoke plan.
     */
    public static List<Account> requesterOwnedAccounts(Id requesterId) {
        List<Account> accounts = [
            SELECT Id
            FROM Account
            WHERE OwnerId = :requesterId
            WITH SYSTEM_MODE
        ];
        return accounts;
    }

    /**
     * @description All Opportunities owned by the Requester.
     * @param requesterId Requester user Id.
     * @return Opportunity Ids added to the grant or revoke plan.
     */
    public static List<Opportunity> requesterOwnedOpportunities(Id requesterId) {
        List<Opportunity> opportunities = [
            SELECT Id
            FROM Opportunity
            WHERE OwnerId = :requesterId
            WITH SYSTEM_MODE
        ];
        return opportunities;
    }

    /**
     * @description Account Team Members for one user on the accounts in scope.
     * @param accountIds Account Ids in the worker scope.
     * @param userId Coverage Rep for grant skip checks, or the user being revoked.
     * @return Account Id to that user's team row.
     */
    public static Map<Id, AccountTeamMember> accountTeamsByAccount(
        Set<Id> accountIds,
        Id userId
    ) {
        Map<Id, AccountTeamMember> result = new Map<Id, AccountTeamMember>();
        if (accountIds == null || accountIds.isEmpty() || userId == null) {
            return result;
        }
        for (AccountTeamMember row : [
            SELECT Id, AccountId, UserId, TeamMemberRole, AssignmentType__c, ExpiryDate__c
            FROM AccountTeamMember
            WHERE AccountId IN :accountIds AND UserId = :userId
            WITH SYSTEM_MODE
        ]) {
            result.put(row.AccountId, row);
        }
        return result;
    }

    /**
     * @description Opportunity Team Members for one user on the opportunities in scope.
     * @param opportunityIds Opportunity Ids in the worker scope.
     * @param userId Coverage Rep for grant skip checks, or the user being revoked.
     * @return Opportunity Id to that user's team row.
     */
    public static Map<Id, OpportunityTeamMember> opportunityTeamsByOpportunity(
        Set<Id> opportunityIds,
        Id userId
    ) {
        Map<Id, OpportunityTeamMember> result = new Map<Id, OpportunityTeamMember>();
        if (opportunityIds == null || opportunityIds.isEmpty() || userId == null) {
            return result;
        }
        for (OpportunityTeamMember row : [
            SELECT Id, OpportunityId, UserId, TeamMemberRole, AssignmentType__c, ExpiryDate__c
            FROM OpportunityTeamMember
            WHERE OpportunityId IN :opportunityIds AND UserId = :userId
            WITH SYSTEM_MODE
        ]) {
            result.put(row.OpportunityId, row);
        }
        return result;
    }

    /**
     * @description Accounts that already have a TAE_AssignedRecord__c for this exception.
     * @param taeId TemporaryAccessException__c Id.
     * @param accountIds Account Ids in the junction chunk.
     * @return Account Ids that the junction phase should skip.
     */
    public static Set<Id> assignedAccountIds(Id taeId, Set<Id> accountIds) {
        Set<Id> result = new Set<Id>();
        if (taeId == null || accountIds == null || accountIds.isEmpty()) {
            return result;
        }
        for (TAE_AssignedRecord__c row : [
            SELECT Account__c
            FROM TAE_AssignedRecord__c
            WHERE TemporaryAccessException__c = :taeId AND Account__c IN :accountIds
            WITH SYSTEM_MODE
        ]) {
            result.add(row.Account__c);
        }
        return result;
    }

    /**
     * @description Opportunities that already have a TAE_AssignedRecord__c for this exception.
     * @param taeId TemporaryAccessException__c Id.
     * @param opportunityIds Opportunity Ids in the junction chunk.
     * @return Opportunity Ids that the junction phase should skip.
     */
    public static Set<Id> assignedOpportunityIds(Id taeId, Set<Id> opportunityIds) {
        Set<Id> result = new Set<Id>();
        if (taeId == null || opportunityIds == null || opportunityIds.isEmpty()) {
            return result;
        }
        for (TAE_AssignedRecord__c row : [
            SELECT Opportunity__c
            FROM TAE_AssignedRecord__c
            WHERE TemporaryAccessException__c = :taeId AND Opportunity__c IN :opportunityIds
            WITH SYSTEM_MODE
        ]) {
            result.add(row.Opportunity__c);
        }
        return result;
    }

    /**
     * @description GC-3482. Records the Coverage Rep owns now on the covered accounts, for one object.
     * Covered accounts are the Requester's team accounts and owned accounts, the same book the grant uses.
     * Ownership is what matters. Created By is not filtered, so a record transferred to the Coverage Rep
     * during coverage is included along with one the Coverage Rep created.
     * Excluded: closed opportunities, completed tasks, events that have already ended, records on any
     * other account, and individual occurrences of a recurring task or event.
     * A recurring series is included. Salesforce keeps the owner on the series, and an owner update
     * on an occurrence fails and would leave the request Processing.
     * An empty account book returns a locator with no rows. An IN bind on an empty set is invalid SOQL.
     * @param accountIds Covered account Ids from the Requester book.
     * @param coverageRepId Coverage Rep user Id.
     * @param workType REASSIGN_OPPORTUNITY, REASSIGN_TASK, REASSIGN_EVENT, or REASSIGN_CONTACT.
     * @return Query locator of Ids. The batch drafts 500 of these Ids per execute.
     */
    public static Database.QueryLocator handbackLocator(
        Set<Id> accountIds,
        Id coverageRepId,
        String workType
    ) {
        Set<Id> accounts = new Set<Id>();
        if (accountIds != null) {
            accounts.addAll(accountIds);
        }
        Date today = Date.today();
        Datetime nowStamp = System.now();
        Database.QueryLocator locator;
        if (accounts.isEmpty() || coverageRepId == null) {
            locator = emptyHandbackLocator(workType);
        } else if (workType == TAEWorkItemService.REASSIGN_OPPORTUNITY) {
            locator = Database.getQueryLocator([
                SELECT Id
                FROM Opportunity
                WHERE AccountId IN :accounts
                  AND OwnerId = :coverageRepId
                  AND IsClosed = false
                WITH SYSTEM_MODE
            ]);
        } else if (workType == TAEWorkItemService.REASSIGN_TASK) {
            locator = Database.getQueryLocator([
                SELECT Id
                FROM Task
                WHERE AccountId IN :accounts
                  AND OwnerId = :coverageRepId
                  AND IsClosed = false
                  AND RecurrenceActivityId = null
                WITH SYSTEM_MODE
            ]);
        } else if (workType == TAEWorkItemService.REASSIGN_EVENT) {
            locator = Database.getQueryLocator([
                SELECT Id
                FROM Event
                WHERE AccountId IN :accounts
                  AND OwnerId = :coverageRepId
                  AND RecurrenceActivityId = null
                  AND (
                      // Series still running. EndDateTime on the series is the first occurrence, so it is not used here.
                      (IsRecurrence = true AND (RecurrenceEndDateOnly = null OR RecurrenceEndDateOnly >= :today))
                      // One-time timed event that has not ended, including one already in progress today.
                      OR (IsRecurrence = false AND IsAllDayEvent = false AND EndDateTime >= :nowStamp)
                      // One-time all-day event today or later.
                      OR (IsRecurrence = false AND IsAllDayEvent = true AND ActivityDate >= :today)
                  )
                WITH SYSTEM_MODE
            ]);
        } else if (workType == TAEWorkItemService.REASSIGN_CONTACT) {
            locator = Database.getQueryLocator([
                SELECT Id
                FROM Contact
                WHERE AccountId IN :accounts
                  AND OwnerId = :coverageRepId
                WITH SYSTEM_MODE
            ]);
        } else {
            locator = emptyHandbackLocator(workType);
        }
        return locator;
    }

    /**
     * @description GC-3482. Locator with no rows, on the same object the draft phase expects.
     * Used when the covered-account list is empty or the work type is not a handback type.
     * @param workType Handback work type, used to keep the locator on the right object.
     * @return Query locator with no rows.
     */
    private static Database.QueryLocator emptyHandbackLocator(String workType) {
        Database.QueryLocator locator;
        if (workType == TAEWorkItemService.REASSIGN_TASK) {
            locator = Database.getQueryLocator([
                SELECT Id FROM Task WHERE Id = null WITH SYSTEM_MODE
            ]);
        } else if (workType == TAEWorkItemService.REASSIGN_EVENT) {
            locator = Database.getQueryLocator([
                SELECT Id FROM Event WHERE Id = null WITH SYSTEM_MODE
            ]);
        } else if (workType == TAEWorkItemService.REASSIGN_CONTACT) {
            locator = Database.getQueryLocator([
                SELECT Id FROM Contact WHERE Id = null WITH SYSTEM_MODE
            ]);
        } else {
            locator = Database.getQueryLocator([
                SELECT Id FROM Opportunity WHERE Id = null WITH SYSTEM_MODE
            ]);
        }
        return locator;
    }

    /**
     * @description Pending work items for one exception and a set of work types.
     * @param taeId TemporaryAccessException__c Id.
     * @param workTypes Work type API values for the current phase.
     * @return Query locator ordered by Id.
     */
    public static Database.QueryLocator pendingLocator(Id taeId, Set<String> workTypes) {
        return Database.getQueryLocator([
            SELECT Id, TemporaryAccessException__c, WorkType__c, RecordId__c, Status__c,
                CompositeKey__c, ErrorMessage__c, ProcessedDate__c
            FROM TAEProcessingWorkItem__c
            WHERE TemporaryAccessException__c = :taeId
              AND WorkType__c IN :workTypes
              AND Status__c = 'Pending'
            WITH SYSTEM_MODE
            ORDER BY Id
        ]);
    }

    /**
     * @description Count of every work item on an exception, any status.
     * @param taeId TemporaryAccessException__c Id.
     * @return Row count.
     */
    @TestVisible
    private static Integer countAllWorkItems(Id taeId) {
        Integer rowCount = [
            SELECT COUNT()
            FROM TAEProcessingWorkItem__c
            WHERE TemporaryAccessException__c = :taeId
            WITH SYSTEM_MODE
        ];
        return rowCount;
    }

    /**
     * @description Count of work items in the given statuses and work types.
     * @param taeId TemporaryAccessException__c Id.
     * @param statuses Status API values, such as Pending or Error.
     * @param workTypes Work type API values for the phase being checked.
     * @return Row count.
     */
    public static Integer countByStatusAndTypes(
        Id taeId,
        Set<String> statuses,
        Set<String> workTypes
    ) {
        Integer rowCount = [
            SELECT COUNT()
            FROM TAEProcessingWorkItem__c
            WHERE TemporaryAccessException__c = :taeId
              AND Status__c IN :statuses
              AND WorkType__c IN :workTypes
            WITH SYSTEM_MODE
        ];
        return rowCount;
    }

    /**
     * @description Done work items whose parent is Active or Expired. Pending, Skipped, and Error rows are excluded.
     * @param taeId TemporaryAccessException__c Id.
     * @return Query locator ordered by Id.
     */
    public static Database.QueryLocator doneItemsLocator(Id taeId) {
        return Database.getQueryLocator([
            SELECT Id
            FROM TAEProcessingWorkItem__c
            WHERE TemporaryAccessException__c = :taeId
              AND Status__c = 'Done'
              AND TemporaryAccessException__r.Status__c IN ('Active', 'Expired')
            WITH SYSTEM_MODE
            ORDER BY Id
        ]);
    }

    /**
     * @description Oldest Active or Expired exception that still has Done children.
     * @return Exception Id, or null when nothing is waiting for cleanup.
     */
    public static Id selectTaeIdWithDoneItemsToClean() {
        List<TAEProcessingWorkItem__c> rows = [
            SELECT TemporaryAccessException__c
            FROM TAEProcessingWorkItem__c
            WHERE Status__c = 'Done'
              AND TemporaryAccessException__r.Status__c IN ('Active', 'Expired')
            WITH SYSTEM_MODE
            ORDER BY TemporaryAccessException__r.LastModifiedDate, TemporaryAccessException__c
            LIMIT 1
        ];
        Id exceptionId = null;
        if (!rows.isEmpty()) {
            exceptionId = rows[0].TemporaryAccessException__c;
        }
        return exceptionId;
    }

    /**
     * @description Done rows still attached to one Active or Expired exception.
     * @param taeId TemporaryAccessException__c Id.
     * @return Row count. Cleanup finish uses this to decide whether to chain.
     */
    public static Integer countDoneItems(Id taeId) {
        Integer rowCount = [
            SELECT COUNT()
            FROM TAEProcessingWorkItem__c
            WHERE TemporaryAccessException__c = :taeId
              AND Status__c = 'Done'
              AND TemporaryAccessException__r.Status__c IN ('Active', 'Expired')
            WITH SYSTEM_MODE
        ];
        return rowCount;
    }

    /**
     * @description True when a creation, grant, revoke, handback, or cleanup batch is queued or running.
     * @return Whether the dispatcher should wait.
     */
    public static Boolean hasActivePipelineJob() {
        Set<String> classNames = new Set<String>{
            'TAEWorkItemCreationBatch',
            'TAEGrantWorkBatch',
            'TAERevokeWorkBatch',
            'TAEHandbackDraftBatch',
            'TAEWorkItemCleanupBatch'
        };
        Integer runningJobs = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE ApexClass.Name IN :classNames
              AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
            WITH SYSTEM_MODE
        ];
        Boolean pipelineIsActive = runningJobs > 0;
        return pipelineIsActive;
    }
}