/**
 * GCL-103. When a Life Science temporary coverage request expires, move records
 * owned by the Coverage Rep back to the Rep Needing Coverage.
 * Scope is the covered accounts on the request, plus any Opportunity listed on
 * the request. Opportunity stage does not matter. Open and completed Tasks and
 * Events are included. Created By is never changed.
 * AC6 conflicts with AC5 and the solution design, so completed activities are
 * reassigned and AC6 is not implemented. Account owner is not changed.
 * Healthcare expiry does not call this class.
 */
public without sharing class LSTemporaryAccessReassignmentService {

    /** Moves Coverage Rep ownership on covered accounts back to the Rep Needing Coverage. */
    public static void reassignOnExpiry(List<TemporaryAccessException__c> rows, Set<Id> lifeScienceIds) {
        if (rows == null || lifeScienceIds == null || lifeScienceIds.isEmpty()) {
            return;
        }
        Map<Id, TemporaryAccessException__c> lifeScienceRows = new Map<Id, TemporaryAccessException__c>();
        for (TemporaryAccessException__c row : rows) {
            if (lifeScienceIds.contains(row.Id) && row.CoverageRep__c != null && row.Requester__c != null) {
                lifeScienceRows.put(row.Id, row);
            }
        }
        if (lifeScienceRows.isEmpty()) {
            return;
        }

        Scope scope = scopeForRequests(lifeScienceRows);
        if (scope.accountIds.isEmpty() && scope.opportunityIds.isEmpty()) {
            return;
        }
        ValidationSwitch validationSwitch = suspendValidationRules();
        try {
            reassignOpportunities(scope);
            reassignTasks(scope);
            reassignEvents(scope);
            reassignContacts(scope);
        } finally {
            restoreValidationRules(validationSwitch);
        }
    }

    /** The running user's validation setting row and whether this class created it. */
    private class ValidationSwitch {
        Automation_Setting_Validation_Rule__c setting;
        Boolean created = false;
    }

    /**
     * Owner-only handback must not fail on unrelated field rules such as Position in Funnel.
     * Turns on the running user's validation switch. Returns null when it was already on.
     */
    private static ValidationSwitch suspendValidationRules() {
        Id userId = UserInfo.getUserId();
        List<Automation_Setting_Validation_Rule__c> existing = [
            SELECT Id, disableAll__c
            FROM Automation_Setting_Validation_Rule__c
            WHERE SetupOwnerId = :userId
            LIMIT 1
        ];
        if (!existing.isEmpty() && existing[0].disableAll__c == true) {
            return null;
        }
        ValidationSwitch validationSwitch = new ValidationSwitch();
        validationSwitch.created = existing.isEmpty();
        validationSwitch.setting = validationSwitch.created
            ? new Automation_Setting_Validation_Rule__c(SetupOwnerId = userId)
            : existing[0];
        validationSwitch.setting.disableAll__c = true;
        upsert validationSwitch.setting;
        return validationSwitch;
    }

    /** Puts the running user's validation switch back to how it was before the handback. */
    private static void restoreValidationRules(ValidationSwitch validationSwitch) {
        if (validationSwitch == null) {
            return;
        }
        if (validationSwitch.created) {
            delete validationSwitch.setting;
        } else {
            validationSwitch.setting.disableAll__c = false;
            update validationSwitch.setting;
        }
    }

    /** Covered accounts and the Opportunities explicitly listed on the request. */
    private class Scope {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> opportunityIds = new Set<Id>();
        Set<Id> coverageRepIds = new Set<Id>();
        Map<String, Id> newOwnerByCoverageAccount = new Map<String, Id>();
        Map<Id, Id> newOwnerByOpportunity = new Map<Id, Id>();
    }

    /** Collects covered accounts and Opportunities listed on each Life Science request. */
    private static Scope scopeForRequests(Map<Id, TemporaryAccessException__c> lifeScienceRows) {
        Scope scope = new Scope();
        for (TAE_AssignedRecord__c assigned : [
            SELECT TemporaryAccessException__c, Account__c, Opportunity__c
            FROM TAE_AssignedRecord__c
            WHERE TemporaryAccessException__c IN :lifeScienceRows.keySet()
        ]) {
            TemporaryAccessException__c row = lifeScienceRows.get(assigned.TemporaryAccessException__c);
            if (row == null) {
                continue;
            }
            if (assigned.Account__c != null) {
                addCoveredAccount(scope, row, assigned.Account__c);
            }
            if (assigned.Opportunity__c != null) {
                scope.opportunityIds.add(assigned.Opportunity__c);
                scope.coverageRepIds.add(row.CoverageRep__c);
                scope.newOwnerByOpportunity.put(assigned.Opportunity__c, row.Requester__c);
            }
        }
        return scope;
    }

    /** Records one covered account and the Rep Needing Coverage who should own it. */
    private static void addCoveredAccount(Scope scope, TemporaryAccessException__c row, Id accountId) {
        String key = coverageAccountKey(row.CoverageRep__c, accountId);
        if (scope.newOwnerByCoverageAccount.containsKey(key) && scope.newOwnerByCoverageAccount.get(key) != row.Requester__c) {
            Logger.warn('LSTemporaryAccessReassignmentService: overlapping coverage for accountId=' + accountId);
            return;
        }
        scope.newOwnerByCoverageAccount.put(key, row.Requester__c);
        scope.coverageRepIds.add(row.CoverageRep__c);
        scope.accountIds.add(accountId);
    }

    /**
     * Any stage. Includes Opportunities the Coverage Rep owns on a covered account
     * and Opportunities listed on the temporary request, even when that Opportunity
     * belongs to a different account.
     */
    private static void reassignOpportunities(Scope scope) {
        List<Opportunity> updates = new List<Opportunity>();
        for (Opportunity opportunity : [
            SELECT Id, OwnerId, AccountId
            FROM Opportunity
            WHERE OwnerId IN :scope.coverageRepIds
              AND (AccountId IN :scope.accountIds OR Id IN :scope.opportunityIds)
        ]) {
            Id newOwnerId = ownerForOpportunity(scope, opportunity);
            if (newOwnerId != null && newOwnerId != opportunity.OwnerId) {
                updates.add(new Opportunity(Id = opportunity.Id, OwnerId = newOwnerId));
            }
        }
        saveUpdates(updates, 'Opportunity');
    }

    /** Rep Needing Coverage for one Opportunity, from the request list or its covered account. */
    private static Id ownerForOpportunity(Scope scope, Opportunity opportunity) {
        if (scope.newOwnerByOpportunity.containsKey(opportunity.Id)) {
            return scope.newOwnerByOpportunity.get(opportunity.Id);
        }
        return scope.newOwnerByCoverageAccount.get(coverageAccountKey(opportunity.OwnerId, opportunity.AccountId));
    }

    /** Open and completed Tasks on a covered account or on an Opportunity listed on the request. */
    private static void reassignTasks(Scope scope) {
        List<Task> updates = new List<Task>();
        for (Task task : [
            SELECT Id, OwnerId, AccountId, WhatId
            FROM Task
            WHERE OwnerId IN :scope.coverageRepIds
              AND (
                    AccountId IN :scope.accountIds
                    OR WhatId IN :scope.accountIds
                    OR WhatId IN :scope.opportunityIds
              )
        ]) {
            Id newOwnerId = ownerForActivity(scope, task.OwnerId, task.AccountId, task.WhatId);
            if (newOwnerId != null && newOwnerId != task.OwnerId) {
                updates.add(new Task(Id = task.Id, OwnerId = newOwnerId));
            }
        }
        saveUpdates(updates, 'Task');
    }

    /** Open and completed Events on a covered account or on an Opportunity listed on the request. */
    private static void reassignEvents(Scope scope) {
        List<Event> updates = new List<Event>();
        for (Event event : [
            SELECT Id, OwnerId, AccountId, WhatId
            FROM Event
            WHERE OwnerId IN :scope.coverageRepIds
              AND (
                    AccountId IN :scope.accountIds
                    OR WhatId IN :scope.accountIds
                    OR WhatId IN :scope.opportunityIds
              )
        ]) {
            Id newOwnerId = ownerForActivity(scope, event.OwnerId, event.AccountId, event.WhatId);
            if (newOwnerId != null && newOwnerId != event.OwnerId) {
                updates.add(new Event(Id = event.Id, OwnerId = newOwnerId));
            }
        }
        saveUpdates(updates, 'Event');
    }

    /** Contacts the Coverage Rep owns on a covered account. */
    private static void reassignContacts(Scope scope) {
        List<Contact> updates = new List<Contact>();
        for (Contact contact : [
            SELECT Id, OwnerId, AccountId
            FROM Contact
            WHERE OwnerId IN :scope.coverageRepIds
              AND AccountId IN :scope.accountIds
        ]) {
            Id newOwnerId = scope.newOwnerByCoverageAccount.get(coverageAccountKey(contact.OwnerId, contact.AccountId));
            if (newOwnerId != null && newOwnerId != contact.OwnerId) {
                updates.add(new Contact(Id = contact.Id, OwnerId = newOwnerId));
            }
        }
        saveUpdates(updates, 'Contact');
    }

    /** Rep Needing Coverage for a Task or Event related to a covered account or listed Opportunity. */
    private static Id ownerForActivity(Scope scope, Id ownerId, Id accountId, Id whatId) {
        if (whatId != null && scope.newOwnerByOpportunity.containsKey(whatId)) {
            return scope.newOwnerByOpportunity.get(whatId);
        }
        if (accountId != null) {
            return scope.newOwnerByCoverageAccount.get(coverageAccountKey(ownerId, accountId));
        }
        if (whatId != null) {
            return scope.newOwnerByCoverageAccount.get(coverageAccountKey(ownerId, whatId));
        }
        return null;
    }

    /** Saves owner-only updates and logs any row that fails. */
    private static void saveUpdates(List<SObject> updates, String objectName) {
        if (updates.isEmpty()) {
            return;
        }
        Database.SaveResult[] results = Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                for (Database.Error error : result.getErrors()) {
                    Logger.error(
                        'LSTemporaryAccessReassignmentService.' + objectName + ': ' +
                        error.getStatusCode() + ' ' + error.getMessage()
                    );
                }
            }
        }
    }

    /** Builds the map key for one Coverage Rep and one covered account. */
    private static String coverageAccountKey(Id coverageRepId, Id accountId) {
        return String.valueOf(coverageRepId) + '|' + String.valueOf(accountId);
    }
}