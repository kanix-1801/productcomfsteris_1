/**
* @author PWC Developer
* @date 2026/06/10
*
* @group Overlay Assignment
*
* @description
* GC-3088 - SOQL - only selector for Opportunity Object
*/
public with sharing class OpportunitySelector {
    /**
* @description
* GC-3088 - Selects Opportunities by Account IDs.
* 
* @param accountIdSet Account ID set
* @return List of Opportunity by Accounts
* 
* @example
* OpportunitySelector.selectByAccountIds(accountIdSet);
*/
    public static List<Opportunity> selectByAccountIds(Set<Id> accountIdSet) {
        if (accountIdSet == null || accountIdSet.isEmpty()) {
            return new List<Opportunity>();
        }
        
        return [ Select Id,Name,AccountId, Account.Name, Account.Type, StageName, Amount,CloseDate,
                   OwnerId,Owner.Name,IsClosed, IsWon,Probability,ForecastCategoryName,
                   LastModifiedDate FROM Opportunity WHERE AccountId IN :accountIdSet
                   WITH SECURITY_ENFORCED
        ];
    }

    /**
     * @author Suraj Thapliyal.
     * @description GC-2580 - Selects Opportunities by Id, including Name for display.
     * @param opportunityIdSet Opportunity Id set.
     * @return List of Opportunities with Id and Name.
     */
    public static List<Opportunity> selectByIds(Set<Id> opportunityIdSet) {
        if (opportunityIdSet == null || opportunityIdSet.isEmpty()) {
            return new List<Opportunity>();
        }

        return [
            SELECT Id, Name
            FROM Opportunity
            WHERE Id IN :opportunityIdSet
            WITH USER_MODE
        ];
    }

    /**
     * @author Suraj Thapliyal.
     * @description GC-2580 - Selects Opportunities owned by the given user Ids.
     * @param ownerIds Owner user Ids.
     * @return Opportunity rows with Id and OwnerId.
     */
    public static List<Opportunity> selectByOwnerIds(Set<Id> ownerIds) {
        if (ownerIds == null || ownerIds.isEmpty()) {
            return new List<Opportunity>();
        }

        return [
            SELECT Id, OwnerId
            FROM Opportunity
            WHERE OwnerId IN :ownerIds
            WITH USER_MODE
        ];
    }

     /**
     * @author Himanshu Chaurasia
     * @description GC-2642 - Selects Opportunity by Id, including Name for display.
     * @param opportunityId Opportunity Id.
     * @return List of Opportunities with Id, Name and Pricebook2Id.
     */

    public static Opportunity selectById(Id opportunityId) {
        if (opportunityId == null) {
            return null;
        }

        List<Opportunity> opportunityList = [
            SELECT Id,
                Name,
                OwnerId,
                Pricebook2Id,
                AccountId,
                CurrencyIsoCode,
                ForecastConfidenceLevel__c,
                RecordType.DeveloperName
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];

        return opportunityList.isEmpty() ? null : opportunityList[0];
    }

    /**
     * @description Selects Forecast Confidence Level for Opportunities used during Quote insert.
     * @param opportunityIds Opportunity Id set.
     * @return Opportunity rows keyed by Id.
     */
    public static Map<Id, Opportunity> selectForecastConfidenceByIds(Set<Id> opportunityIds) {
        Map<Id, Opportunity> opportunitiesById = new Map<Id, Opportunity>();

        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return opportunitiesById;
        }

        for (Opportunity opportunityRecord : [
            SELECT Id,
                ForecastConfidenceLevel__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
            WITH USER_MODE
        ]) {
            opportunitiesById.put(opportunityRecord.Id, opportunityRecord);
        }

        return opportunitiesById;
    }
     /**
     * @author Sahithi PWC
     * @description Returns open Opportunities for the given Account Ids for enterprise pipeline roll-up.
     * @param accountIdSet Child Account Ids linked to an IDN/GPO parent Account.
     * @return Open Opportunities across the supplied Accounts.
     */
    public static List<Opportunity> selectOpenPipelineByAccountIds(Set<Id> accountIdSet) {
        if (accountIdSet == null || accountIdSet.isEmpty()) {
            return new List<Opportunity>();
        }

        return [
            SELECT Id,
                Name,
                AccountId,
                Account.Name,
                StageName,
                Amount,
                CloseDate,
                OwnerId,
                Owner.Name
            FROM Opportunity
            WHERE AccountId IN :accountIdSet
                AND IsClosed = false
            WITH USER_MODE
            ORDER BY CloseDate ASC NULLS LAST, Name ASC
        ];
    }

    /**
     * @author Akash Dahinde
     * @date 09-25-2026
     * @story GCL-11
     * @description Selects parent Opportunities with Primary Contact and record
     *              type fields required by PrimaryContactService.
     * @param opportunityIds Opportunity Ids to select.
     * @return Opportunity records keyed by Id.
     */
    public Map<Id, Opportunity> selectByIdsForPrimaryContact(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return new Map<Id, Opportunity>();
        }
        return new Map<Id, Opportunity>([
            SELECT Id, PrimaryContact__c, RecordTypeId
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ]);
    }

    private static final String BUSINESS_SYSTEM_ADMIN_PERMISSION_SET = 'LSBusinessSysAdminPS';

    /**
     * @description
     * GCL-73 - Id and role of the running user. UserInfo is used because a
     * Life Sciences Sales user cannot query User.Profile or User.UserRoleId.
     *
     * @return Running user.
     *
     * @example
     * OpportunitySelector.selectRunningUser();
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
     * OpportunitySelector.selectProfileName(profileId);
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
     * OpportunitySelector.hasBusinessSystemAdminPermission(userId);
     */
    public static Boolean hasBusinessSystemAdminPermission(Id userId) {
        if (userId == null) {
            return false;
        }
        List<PermissionSetAssignment> assignments = Database.queryWithBinds(
            'SELECT Id FROM PermissionSetAssignment'
            + ' WHERE AssigneeId = :userId'
            + ' AND PermissionSet.Name = :permissionSetName LIMIT 1',
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
     * OpportunitySelector.selectRoleIdByUserId(userIds);
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
     * OpportunitySelector.selectParentRoleIdByRoleId();
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