/**
 * @author PWC Developer
 * @date 2026/07/15
 *
 * @group Record Type Permission Set Assignment
 *
 * @description
 * GC-3148 - SOQL selector for PermissionSet and PermissionSetAssignment queries.
 */
public without sharing class PermissionSetSelector {

    /**
     * @description
     * Returns permission sets matching the provided API names.
     *
     * @param permissionSetNames Permission set API names.
     * @return Matching permission sets.
     */
    public static List<PermissionSet> selectByNames(Set<String> permissionSetNames) {
        if (permissionSetNames == null || permissionSetNames.isEmpty()) {
            return new List<PermissionSet>();
        }

        return [
            SELECT Id, Name, Label
            FROM PermissionSet
            WHERE Name IN :permissionSetNames
            AND IsOwnedByProfile = FALSE
        ];
    }

    /**
     * @description
     * Returns permission set assignments for a user and permission set id set.
     *
     * @param userId Assignee user id.
     * @param permissionSetIds Permission set ids.
     * @return Matching permission set assignments.
     */
    public static List<PermissionSetAssignment> selectAssignmentsByUserAndPermissionSetIds(
        Id userId,
        Set<Id> permissionSetIds
    ) {
        if (userId == null || permissionSetIds == null || permissionSetIds.isEmpty()) {
            return new List<PermissionSetAssignment>();
        }

        return [
            SELECT Id, PermissionSetId, AssigneeId
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
            AND PermissionSetId IN :permissionSetIds
        ];
    }
}