/**
 * @author PWC Developer
 * @date 2026/11/04
 *
 * @group Life Sciences Opportunity
 *
 * @description
 * GCL-73 - SOQL for the Life Sciences Opportunity owner check.
 * Declared without sharing so a private user record still exposes the
 * previous owner's role to the authorization decision.
 */
public without sharing class LSOpportunityOwnerSelector {

    private static final String BUSINESS_SYSTEM_ADMIN_PERMISSION_SET = 'LSBusinessSysAdminPS';

    /**
     * @description
     * GCL-73 - Profile and role of the running user.
     *
     * @return Running user, or null when the row cannot be read.
     *
     * @example
     * LSOpportunityOwnerSelector.selectRunningUser();
     */
    public static User selectRunningUser() {
        List<User> users = [
            SELECT Id, Profile.Name, UserRoleId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }

    /**
     * @description
     * GCL-73 - Whether the user is assigned LSBusinessSysAdminPS directly
     * or through a permission set group.
     *
     * @param userId User attempting the owner change.
     * @return TRUE when the Business System Admin permission set is assigned.
     *
     * @example
     * LSOpportunityOwnerSelector.hasBusinessSystemAdminPermission(userId);
     */
    public static Boolean hasBusinessSystemAdminPermission(Id userId) {
        if (userId == null) {
            return false;
        }
        return ![
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
            AND PermissionSet.Name = :BUSINESS_SYSTEM_ADMIN_PERMISSION_SET
            LIMIT 1
        ].isEmpty();
    }

    /**
     * @description
     * GCL-73 - Role Id for each previous Opportunity owner.
     *
     * @param userIds Previous owner Ids from the owner change.
     * @return Role Id by User Id.
     *
     * @example
     * LSOpportunityOwnerSelector.selectRoleIdByUserId(userIds);
     */
    public static Map<Id, Id> selectRoleIdByUserId(Set<Id> userIds) {
        Map<Id, Id> roleIdByUserId = new Map<Id, Id>();
        if (userIds == null || userIds.isEmpty()) {
            return roleIdByUserId;
        }
        for (User owner : [
            SELECT Id, UserRoleId
            FROM User
            WHERE Id IN :userIds
        ]) {
            roleIdByUserId.put(owner.Id, owner.UserRoleId);
        }
        return roleIdByUserId;
    }

    /**
     * @description
     * GCL-73 - Parent role for every internal role. One query keeps the
     * hierarchy walk out of a loop.
     *
     * @return Parent role Id by role Id.
     *
     * @example
     * LSOpportunityOwnerSelector.selectParentRoleIdByRoleId();
     */
    public static Map<Id, Id> selectParentRoleIdByRoleId() {
        Map<Id, Id> parentRoleIdByRoleId = new Map<Id, Id>();
        for (UserRole roleRecord : [
            SELECT Id, ParentRoleId
            FROM UserRole
            WHERE PortalType = 'None'
        ]) {
            parentRoleIdByRoleId.put(roleRecord.Id, roleRecord.ParentRoleId);
        }
        return parentRoleIdByRoleId;
    }
}