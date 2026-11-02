/**
 * Resolves read-only installation project viewer access.
 * Supports direct permission set assignment and assignment via permission set group.
 */
public without sharing class InstallationProjectViewerAccessService {
    @TestVisible
    private static Boolean forceReadOnlyForTests = false;

    /**
     * When true, bypasses ReadInstallationProjects permission checks so integration tests can mutate data
     * even when the running user has the read-only viewer permission set (common in deployment validation).
     */
    @TestVisible
    private static Boolean ignoreReadOnlyPermissionForTests = false;

    @TestVisible
    static void setForceReadOnlyForTests(Boolean value) {
        forceReadOnlyForTests = value == true;
    }

    @TestVisible
    static void setIgnoreReadOnlyPermissionForTests(Boolean value) {
        ignoreReadOnlyPermissionForTests = value == true;
    }

    public static Boolean hasReadOnlyInstallationProjectViewerAccess() {
        if (ignoreReadOnlyPermissionForTests) {
            return false;
        }
        if (forceReadOnlyForTests) {
            return true;
        }
        return hasPermissionSetAssigned(
            UserInfo.getUserId(),
            InstallationProjectViewerController.READ_INSTALLATION_PROJECTS_PERMISSION_SET_NAME
        );
    }

    /**
     * True when the user has ReadInstallationProjects assigned directly or through a permission set group
     * (e.g. Field Management group that includes this permission set).
     */
    private static Boolean hasPermissionSetAssigned(Id userId, String permissionSetApiName) {
        if (userId == null || String.isBlank(permissionSetApiName)) {
            return false;
        }

        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :permissionSetApiName AND IsOwnedByProfile = FALSE
            LIMIT 1
        ];
        if (permissionSets.isEmpty()) {
            return false;
        }
        Id permissionSetId = permissionSets[0].Id;

        if (hasDirectPermissionSetAssignment(userId, permissionSetId)) {
            return true;
        }

        Set<Id> groupIds = new Set<Id>();
        for (PermissionSetGroupComponent component : [
            SELECT PermissionSetGroupId
            FROM PermissionSetGroupComponent
            WHERE PermissionSetId = :permissionSetId
        ]) {
            groupIds.add(component.PermissionSetGroupId);
        }
        if (groupIds.isEmpty()) {
            return false;
        }
        return hasPermissionSetGroupAssignment(userId, groupIds);
    }

    private static Boolean hasDirectPermissionSetAssignment(Id userId, Id permissionSetId) {
        return [
                SELECT Id
                FROM PermissionSetAssignment
                WHERE AssigneeId = :userId AND PermissionSetId = :permissionSetId
                LIMIT 1
            ]
            .size() > 0;
    }

    private static Boolean hasPermissionSetGroupAssignment(Id userId, Set<Id> permissionSetGroupIds) {
        return [
                SELECT Id
                FROM PermissionSetAssignment
                WHERE AssigneeId = :userId AND PermissionSetGroupId IN :permissionSetGroupIds
                LIMIT 1
            ]
            .size() > 0;
    }
}