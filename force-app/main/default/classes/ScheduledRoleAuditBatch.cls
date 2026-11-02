/**
 * @description
 * author: Sarthak Pani (part of GCL-53 POC; this is NOT a final version)
 * Scheduled batch that sets User.HasReportees__c from the role hierarchy.
 * Users with a UserRoleId whose role has child UserRole records are marked true;
 * users whose role has no subordinates are marked false.
 */
public without sharing class ScheduledRoleAuditBatch implements Database.Batchable<SObject>, Schedulable {

    private static final Integer BATCH_SIZE = 200;

    /**
     * @description Queries users assigned to a role.
     *
     * @param bc Batchable context from the platform
     * @return Query locator of users with UserRoleId populated
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, UserRoleId, HasReportees__c
            FROM User
            WHERE UserRoleId != null
        ]);
    }

    /**
     * @description Marks HasReportees__c true when the user's role has reporting roles beneath it.
     *
     * @param bc Batchable context from the platform
     * @param usersToProcess Users in the current chunk
     * @return void
     */
    public void execute(Database.BatchableContext bc, List<SObject> usersToProcess) {
        List<User> scopedUsers = (List<User>) usersToProcess;
        if (scopedUsers.isEmpty()) {
            return;
        }

        Set<Id> roleIds = new Set<Id>();
        for (User currentUser : scopedUsers) {
            roleIds.add(currentUser.UserRoleId);
        }

        Set<Id> parentRoleIdsWithChildren = new Set<Id>();
        for (UserRole childRole : [
            SELECT ParentRoleId
            FROM UserRole
            WHERE ParentRoleId IN :roleIds
        ]) {
            parentRoleIdsWithChildren.add(childRole.ParentRoleId);
        }

        List<User> usersToUpdate = new List<User>();
        for (User currentUser : scopedUsers) {
            Boolean hasReportees = parentRoleIdsWithChildren.contains(currentUser.UserRoleId);
            if (currentUser.HasReportees__c != hasReportees) {
                usersToUpdate.add(new User(
                    Id = currentUser.Id,
                    HasReportees__c = hasReportees
                ));
            }
        }

        if (!usersToUpdate.isEmpty()) {
            Database.update(usersToUpdate, false);
        }
    }

    /**
     * @description Completes the batch run.
     *
     * @param bc Batchable context from the platform
     * @return void
     */
    public void finish(Database.BatchableContext bc) {
    }

    /**
     * @description Schedulable entry point. Submits this batch.
     *
     * @param sc Schedulable context from the platform
     * @return void
     */
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new ScheduledRoleAuditBatch(), BATCH_SIZE);
    }
}