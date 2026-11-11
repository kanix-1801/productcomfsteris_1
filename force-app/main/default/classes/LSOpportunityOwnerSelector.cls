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
     * GCL-73 - Id and role of the running user. UserInfo is used because a
     * Life Sciences Sales user cannot query User.Profile or User.UserRoleId.
     *
     * @return Running user.
     *
     * @example
     * LSOpportunityOwnerSelector.selectRunningUser();
     */
    public static User selectRunningUser() {
        return new User(
            Id = UserInfo.getUserId(),
            UserRoleId = UserInfo.getUserRoleId()
        );
    }

    /**
     * @description
     * GCL-73 - Profile name for a Profile Id. System mode is required because
     * a Life Sciences Sales user cannot query Profile.
     *
     * @param profileId Profile Id from UserInfo.getProfileId.
     * @return Profile name, or null when the profile cannot be read.
     *
     * @example
     * LSOpportunityOwnerSelector.selectProfileName(profileId);
     */
    public static String selectProfileName(Id profileId) {
        if (profileId == null) {
            return null;
        }
        List<Profile> profiles = Database.queryWithBinds(
            'SELECT Name FROM Profile WHERE Id = :profileId LIMIT 1',
            new Map<String, Object>{ 'profileId' => profileId },
            AccessLevel.SYSTEM_MODE
        );
        return profiles.isEmpty() ? null : profiles[0].Name;
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
        List<PermissionSetAssignment> assignments = Database.queryWithBinds(
            'SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSet.Name = :permissionSetName LIMIT 1',
            new Map<String, Object>{
                'userId' => userId,
                'permissionSetName' => BUSINESS_SYSTEM_ADMIN_PERMISSION_SET
            },
            AccessLevel.SYSTEM_MODE
        );
        return !assignments.isEmpty();
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
        List<User> owners = Database.queryWithBinds(
            'SELECT Id, UserRoleId FROM User WHERE Id IN :userIds',
            new Map<String, Object>{ 'userIds' => userIds },
            AccessLevel.SYSTEM_MODE
        );
        for (User owner : owners) {
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
        List<UserRole> roles = Database.queryWithBinds(
            'SELECT Id, ParentRoleId FROM UserRole WHERE PortalType = :portalType',
            new Map<String, Object>{ 'portalType' => 'None' },
            AccessLevel.SYSTEM_MODE
        );
        for (UserRole roleRecord : roles) {
            parentRoleIdByRoleId.put(roleRecord.Id, roleRecord.ParentRoleId);
        }
        return parentRoleIdByRoleId;
    }
}