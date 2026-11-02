/**
 * @description
 * GC-2868 
 * Returns Tasks and Events associated with Customer/Address Accounts
 * related to the current IDN/GPO through AccountAccountRelationship__c.
 *
 * Relationship path:
 *
 * IDN/GPO Account
 *      -> AccountAccountRelationship__c.ParentAccount__c
 *      -> AccountAccountRelationship__c.ChildAccount__c
 *      -> Task.WhatId / Event.WhatId
 */
public with sharing class EnterpriseActivityController {

    private static final Set<String> VALID_ENTERPRISE_TYPES =
        new Set<String>{ 'IDN', 'GPO' };

    private static final Integer MAX_TASK_ROWS = 1000;
    private static final Integer MAX_EVENT_ROWS = 1000;

    /**
     * @description Returns consolidated enterprise Activities.
     *
     * IDN/GPO:
     * Retrieves Activities from AAR Child Accounts.
     *
     * Customer/Address Account:
     * Retrieves Activities for the current Account only.
     *
     * @param accountId Current Account record Id.
     * @return EnterpriseActivityResponse.
     */
    @AuraEnabled(cacheable=true)
    public static EnterpriseActivityResponse getEnterpriseActivities(
        Id accountId
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        EnterpriseActivityResponse response =
            initializeResponse();

        List<Account> currentAccounts = [
            SELECT Id,
                   Name,
                   Type
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];

        if (currentAccounts.isEmpty()) {
            throw new AuraHandledException(
                'The Account does not exist or you do not have access to it.'
            );
        }

        Account currentAccount = currentAccounts[0];

        response.currentAccountId = currentAccount.Id;
        response.currentAccountName = currentAccount.Name;
        response.currentAccountType = currentAccount.Type;
        response.displayComponent = true;

        Set<Id> activityAccountIds = new Set<Id>();

        /*
         * IDN/GPO:
         * Retrieve Customer/Address Accounts through AAR.
         */
        if (
            !String.isBlank(currentAccount.Type) &&
            VALID_ENTERPRISE_TYPES.contains(currentAccount.Type)
        ) {
            List<AccountAccountRelationship__c> relationships = [
                SELECT Id,
                       ParentAccount__c,
                       ParentAccountType__c,
                       ChildAccount__c,
                       ChildAccount__r.Name,
                       ChildAccountType__c
                FROM AccountAccountRelationship__c
                WHERE ParentAccount__c = :accountId
                  AND ParentAccountType__c IN :VALID_ENTERPRISE_TYPES
                  AND ChildAccount__c != null
                WITH USER_MODE
            ];

            for (
                AccountAccountRelationship__c relationship
                : relationships
            ) {
                activityAccountIds.add(
                    relationship.ChildAccount__c
                );
            }

            response.isEnterpriseView = true;
        } else {
            /*
             * Address/Customer Account:
             * Show Activities only for the current Account.
             */
            activityAccountIds.add(accountId);
            response.isEnterpriseView = false;
        }

        response.relatedAccountCount =
            activityAccountIds.size();

        if (activityAccountIds.isEmpty()) {
            return response;
        }

        Map<Id, Account> accountById = new Map<Id, Account>([
            SELECT Id,
                   Name,
                   Type
            FROM Account
            WHERE Id IN :activityAccountIds
            WITH USER_MODE
        ]);

        List<ActivityRow> activityRows =
            new List<ActivityRow>();

        /*
         * Tasks directly related to Customer/Address Accounts.
         *
         * Task.WhatId identifies the related Account.
         */
        List<Task> tasks = [
            SELECT Id,
                   Subject,
                   Status,
                   Priority,
                   ActivityDate,
                   WhatId,
                   WhoId,
                   Who.Name,
                   OwnerId,
                   Owner.Name,
                   Description,
                   IsClosed,
                   CreatedDate,
                   LastModifiedDate
            FROM Task
            WHERE WhatId IN :activityAccountIds
            WITH USER_MODE
            ORDER BY ActivityDate DESC NULLS LAST,
                     LastModifiedDate DESC
            LIMIT :MAX_TASK_ROWS
        ];

        for (Task taskRecord : tasks) {
            ActivityRow row = new ActivityRow();

            row.activityId = taskRecord.Id;
            row.activityType = 'Task';
            row.subject = taskRecord.Subject;
            row.status = taskRecord.Status;
            row.priority = taskRecord.Priority;
            row.activityDate = taskRecord.ActivityDate;

            if (taskRecord.ActivityDate != null) {
                row.activityDateTime = Datetime.newInstance(
                    taskRecord.ActivityDate,
                    Time.newInstance(0, 0, 0, 0)
                );
            }

            row.relatedAccountId = taskRecord.WhatId;

            Account relatedAccount =
                accountById.get(taskRecord.WhatId);

            row.relatedAccountName =
                relatedAccount != null
                    ? relatedAccount.Name
                    : null;

            row.relatedAccountType =
                relatedAccount != null
                    ? relatedAccount.Type
                    : null;

            row.whoId = taskRecord.WhoId;
            row.whoName =
                taskRecord.Who != null
                    ? taskRecord.Who.Name
                    : null;

            row.ownerId = taskRecord.OwnerId;
            row.ownerName =
                taskRecord.Owner != null
                    ? taskRecord.Owner.Name
                    : null;

            row.description = taskRecord.Description;
            row.isClosed = taskRecord.IsClosed;
            row.createdDate = taskRecord.CreatedDate;
            row.lastModifiedDate =
                taskRecord.LastModifiedDate;

            activityRows.add(row);
        }

        /*
         * Events directly related to Customer/Address Accounts.
         *
         * Event.WhatId identifies the related Account.
         */
        List<Event> events = [
            SELECT Id,
                   Subject,
                   StartDateTime,
                   EndDateTime,
                   ActivityDate,
                   WhatId,
                   WhoId,
                   Who.Name,
                   OwnerId,
                   Owner.Name,
                   Description,
                   IsAllDayEvent,
                   Location,
                   CreatedDate,
                   LastModifiedDate
            FROM Event
            WHERE WhatId IN :activityAccountIds
            WITH USER_MODE
            ORDER BY StartDateTime DESC NULLS LAST,
                     LastModifiedDate DESC
            LIMIT :MAX_EVENT_ROWS
        ];

        for (Event eventRecord : events) {
            ActivityRow row = new ActivityRow();

            row.activityId = eventRecord.Id;
            row.activityType = 'Event';
            row.subject = eventRecord.Subject;
            row.status = null;
            row.priority = null;
            row.activityDate = eventRecord.ActivityDate;
            row.activityDateTime =
                eventRecord.StartDateTime;
            row.endDateTime =
                eventRecord.EndDateTime;

            row.relatedAccountId = eventRecord.WhatId;

            Account relatedAccount =
                accountById.get(eventRecord.WhatId);

            row.relatedAccountName =
                relatedAccount != null
                    ? relatedAccount.Name
                    : null;

            row.relatedAccountType =
                relatedAccount != null
                    ? relatedAccount.Type
                    : null;

            row.whoId = eventRecord.WhoId;
            row.whoName =
                eventRecord.Who != null
                    ? eventRecord.Who.Name
                    : null;

            row.ownerId = eventRecord.OwnerId;
            row.ownerName =
                eventRecord.Owner != null
                    ? eventRecord.Owner.Name
                    : null;

            row.description = eventRecord.Description;
            row.location = eventRecord.Location;
            row.isAllDayEvent =
                eventRecord.IsAllDayEvent;
            row.isClosed = false;
            row.createdDate = eventRecord.CreatedDate;
            row.lastModifiedDate =
                eventRecord.LastModifiedDate;

            activityRows.add(row);
        }

        activityRows.sort(
            new ActivityDateComparator()
        );

        response.activities = activityRows;
        response.totalActivityCount =
            activityRows.size();
        response.taskCount = tasks.size();
        response.eventCount = events.size();

        response.resultLimitReached =
            tasks.size() == MAX_TASK_ROWS ||
            events.size() == MAX_EVENT_ROWS;

        return response;
    }

    private static EnterpriseActivityResponse initializeResponse() {
        EnterpriseActivityResponse response =
            new EnterpriseActivityResponse();

        response.displayComponent = false;
        response.isEnterpriseView = false;
        response.resultLimitReached = false;
        response.relatedAccountCount = 0;
        response.totalActivityCount = 0;
        response.taskCount = 0;
        response.eventCount = 0;
        response.activities =
            new List<ActivityRow>();

        return response;
    }

    /**
     * Sort newest Activities first.
     *
     * Activities without a date appear last.
     */
    private class ActivityDateComparator
        implements Comparator<ActivityRow> {

        public Integer compare(
            ActivityRow firstRow,
            ActivityRow secondRow
        ) {
            if (
                firstRow.activityDateTime == null &&
                secondRow.activityDateTime == null
            ) {
                return 0;
            }

            if (firstRow.activityDateTime == null) {
                return 1;
            }

            if (secondRow.activityDateTime == null) {
                return -1;
            }

            if (
                firstRow.activityDateTime >
                secondRow.activityDateTime
            ) {
                return -1;
            }

            if (
                firstRow.activityDateTime <
                secondRow.activityDateTime
            ) {
                return 1;
            }

            return 0;
        }
    }

    public class EnterpriseActivityResponse {
        @AuraEnabled
        public Boolean displayComponent;

        @AuraEnabled
        public Boolean isEnterpriseView;

        @AuraEnabled
        public Boolean resultLimitReached;

        @AuraEnabled
        public Id currentAccountId;

        @AuraEnabled
        public String currentAccountName;

        @AuraEnabled
        public String currentAccountType;

        @AuraEnabled
        public Integer relatedAccountCount;

        @AuraEnabled
        public Integer totalActivityCount;

        @AuraEnabled
        public Integer taskCount;

        @AuraEnabled
        public Integer eventCount;

        @AuraEnabled
        public List<ActivityRow> activities;
    }

    public class ActivityRow {
        @AuraEnabled
        public Id activityId;

        @AuraEnabled
        public String activityType;

        @AuraEnabled
        public String subject;

        @AuraEnabled
        public String status;

        @AuraEnabled
        public String priority;

        @AuraEnabled
        public Date activityDate;

        @AuraEnabled
        public Datetime activityDateTime;

        @AuraEnabled
        public Datetime endDateTime;

        @AuraEnabled
        public Id relatedAccountId;

        @AuraEnabled
        public String relatedAccountName;

        @AuraEnabled
        public String relatedAccountType;

        @AuraEnabled
        public Id whoId;

        @AuraEnabled
        public String whoName;

        @AuraEnabled
        public Id ownerId;

        @AuraEnabled
        public String ownerName;

        @AuraEnabled
        public String description;

        @AuraEnabled
        public String location;

        @AuraEnabled
        public Boolean isAllDayEvent;

        @AuraEnabled
        public Boolean isClosed;

        @AuraEnabled
        public Datetime createdDate;

        @AuraEnabled
        public Datetime lastModifiedDate;
    }
}