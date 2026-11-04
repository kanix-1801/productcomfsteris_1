/**
 * GCL-103. When a Life Science temporary coverage request expires, move records
 * owned by the Coverage Rep on the covered accounts back to the Rep Needing Coverage.
 * Healthcare expiry does not call this class.
 * Created By is never changed. AC6 is not implemented: completed activities are
 * reassigned, which is what AC5, the solution design, and the grooming table require.
 */
public without sharing class LSTemporaryAccessReassignmentService {

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

        Map<String, Id> newOwnerByCoverageAccount = new Map<String, Id>();
        Set<Id> coverageRepIds = new Set<Id>();
        Set<Id> accountIds = accountIdsForRequests(lifeScienceRows, newOwnerByCoverageAccount, coverageRepIds);
        if (accountIds.isEmpty()) {
            return;
        }
        reassignOpportunities(coverageRepIds, accountIds, newOwnerByCoverageAccount);
        reassignTasks(coverageRepIds, accountIds, newOwnerByCoverageAccount);
        reassignEvents(coverageRepIds, accountIds, newOwnerByCoverageAccount);
        reassignContacts(coverageRepIds, accountIds, newOwnerByCoverageAccount);
    }

    private static Set<Id> accountIdsForRequests(
        Map<Id, TemporaryAccessException__c> lifeScienceRows,
        Map<String, Id> newOwnerByCoverageAccount,
        Set<Id> coverageRepIds
    ) {
        Set<Id> accountIds = new Set<Id>();
        for (TAE_AssignedRecord__c assigned : [
            SELECT TemporaryAccessException__c, Account__c, Opportunity__r.AccountId
            FROM TAE_AssignedRecord__c
            WHERE TemporaryAccessException__c IN :lifeScienceRows.keySet()
        ]) {
            TemporaryAccessException__c row = lifeScienceRows.get(assigned.TemporaryAccessException__c);
            Id accountId = assigned.Account__c != null ? assigned.Account__c : assigned.Opportunity__r.AccountId;
            if (row == null || accountId == null) {
                continue;
            }
            String key = coverageAccountKey(row.CoverageRep__c, accountId);
            if (newOwnerByCoverageAccount.containsKey(key) && newOwnerByCoverageAccount.get(key) != row.Requester__c) {
                Logger.warn(
                    'LSTemporaryAccessReassignmentService: overlapping coverage for accountId=' + accountId
                );
                continue;
            }
            newOwnerByCoverageAccount.put(key, row.Requester__c);
            coverageRepIds.add(row.CoverageRep__c);
            accountIds.add(accountId);
        }
        return accountIds;
    }

    private static void reassignOpportunities(
        Set<Id> coverageRepIds,
        Set<Id> accountIds,
        Map<String, Id> newOwnerByCoverageAccount
    ) {
        List<Opportunity> updates = new List<Opportunity>();
        for (Opportunity opportunity : [
            SELECT Id, OwnerId, AccountId
            FROM Opportunity
            WHERE OwnerId IN :coverageRepIds
              AND AccountId IN :accountIds
        ]) {
            Id newOwnerId = newOwnerByCoverageAccount.get(coverageAccountKey(opportunity.OwnerId, opportunity.AccountId));
            if (newOwnerId != null && newOwnerId != opportunity.OwnerId) {
                updates.add(new Opportunity(Id = opportunity.Id, OwnerId = newOwnerId));
            }
        }
        saveUpdates(updates, 'Opportunity');
    }

    private static void reassignTasks(
        Set<Id> coverageRepIds,
        Set<Id> accountIds,
        Map<String, Id> newOwnerByCoverageAccount
    ) {
        List<Task> updates = new List<Task>();
        for (Task task : [
            SELECT Id, OwnerId, AccountId
            FROM Task
            WHERE OwnerId IN :coverageRepIds
              AND AccountId IN :accountIds
        ]) {
            Id newOwnerId = newOwnerByCoverageAccount.get(coverageAccountKey(task.OwnerId, task.AccountId));
            if (newOwnerId != null && newOwnerId != task.OwnerId) {
                updates.add(new Task(Id = task.Id, OwnerId = newOwnerId));
            }
        }
        saveUpdates(updates, 'Task');
    }

    private static void reassignEvents(
        Set<Id> coverageRepIds,
        Set<Id> accountIds,
        Map<String, Id> newOwnerByCoverageAccount
    ) {
        List<Event> updates = new List<Event>();
        for (Event event : [
            SELECT Id, OwnerId, AccountId
            FROM Event
            WHERE OwnerId IN :coverageRepIds
              AND AccountId IN :accountIds
        ]) {
            Id newOwnerId = newOwnerByCoverageAccount.get(coverageAccountKey(event.OwnerId, event.AccountId));
            if (newOwnerId != null && newOwnerId != event.OwnerId) {
                updates.add(new Event(Id = event.Id, OwnerId = newOwnerId));
            }
        }
        saveUpdates(updates, 'Event');
    }

    private static void reassignContacts(
        Set<Id> coverageRepIds,
        Set<Id> accountIds,
        Map<String, Id> newOwnerByCoverageAccount
    ) {
        List<Contact> updates = new List<Contact>();
        for (Contact contact : [
            SELECT Id, OwnerId, AccountId
            FROM Contact
            WHERE OwnerId IN :coverageRepIds
              AND AccountId IN :accountIds
        ]) {
            Id newOwnerId = newOwnerByCoverageAccount.get(coverageAccountKey(contact.OwnerId, contact.AccountId));
            if (newOwnerId != null && newOwnerId != contact.OwnerId) {
                updates.add(new Contact(Id = contact.Id, OwnerId = newOwnerId));
            }
        }
        saveUpdates(updates, 'Contact');
    }

    /**
     * Updates carry only Id and OwnerId. TaskTrigger rejects a Task that still holds the
     * read-only AccountId from the query.
     */
    private static void saveUpdates(List<SObject> updates, String objectName) {
        if (updates.isEmpty()) {
            return;
        }
        Database.SaveResult[] results = Database.update(updates, false);
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

    private static String coverageAccountKey(Id coverageRepId, Id accountId) {
        return String.valueOf(coverageRepId) + '|' + String.valueOf(accountId);
    }
}