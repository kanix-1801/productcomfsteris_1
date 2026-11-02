/**
 *Selector class responsible for retrieving Account Team Member,
 *                Opportunity Team Member, Public Group, Group Member,
 *                and User records related to team member processing.
 * @author      : Vinay
 * @date        : 2026-06-12
 */
public inherited sharing class TeamMemberSelector {

    /**
     *Returns Account Team Member records matching the provided Users and roles.
     */
    public static List<AccountTeamMember> getAccountTeamMembersByUserIdsAndRoles(
        Set<Id> userIds,
        Set<String> teamMemberRoles
    ) {
        if (
            userIds != null && !userIds.isEmpty() &&
            teamMemberRoles != null && !teamMemberRoles.isEmpty() &&
            Schema.sObjectType.AccountTeamMember.isAccessible()
        ) {
        return [
            SELECT Id, AccountId, UserId, TeamMemberRole
            FROM AccountTeamMember
            WHERE UserId IN :userIds
            AND TeamMemberRole IN :teamMemberRoles
            WITH USER_MODE
        ];
        }
        return new List<AccountTeamMember>();
    }

    /**
     *Returns Opportunity Team Member records matching the provided Users and roles.
     */
    public static List<OpportunityTeamMember> getOpportunityTeamMembersByUserIdsAndRoles(
        Set<Id> userIds,
        Set<String> teamMemberRoles
    ) {
        if (
            userIds != null && !userIds.isEmpty() &&
            teamMemberRoles != null && !teamMemberRoles.isEmpty() &&
            Schema.sObjectType.OpportunityTeamMember.isAccessible()
        ) {
        return [
            SELECT Id, OpportunityId, UserId, TeamMemberRole
            FROM OpportunityTeamMember
            WHERE UserId IN :userIds
            AND TeamMemberRole IN :teamMemberRoles
            WITH USER_MODE
        ];
        }
         return new List<OpportunityTeamMember>();
    }

    /**
     *Returns existing Opportunity Team Member records for the given Opportunities and Users.
     *              Used to prevent duplicate Opportunity Team Member creation.
     */
    public static List<OpportunityTeamMember> getOpportunityTeamMembersByOpportunityIdsAndUserIds(
        Set<Id> opportunityIds,
        Set<Id> userIds
    ) {
        if (
            opportunityIds != null && !opportunityIds.isEmpty() &&
            userIds != null && !userIds.isEmpty() &&
            Schema.sObjectType.OpportunityTeamMember.isAccessible()
        ) {
        return [
            SELECT Id, OpportunityId, UserId, TeamMemberRole
            FROM OpportunityTeamMember
            WHERE OpportunityId IN :opportunityIds
            AND UserId IN :userIds
            WITH USER_MODE
        ];
        }
        return new List<OpportunityTeamMember>();
    }

    /**
     *Returns a Public Group by DeveloperName.
     */
    public static Group getPublicGroupByDeveloperName(String developerName) {
        if (
            String.isNotBlank(developerName) &&
            Schema.sObjectType.Group.isAccessible()
        ) {
        List<Group> groups = [
            SELECT Id, DeveloperName, Type
            FROM Group
            WHERE DeveloperName = :developerName
            AND Type = 'Regular'
            WITH USER_MODE
            LIMIT 1
        ];

        return groups.isEmpty() ? null : groups[0];
		}
        return null;
    }

    /**
     *Returns GroupMember records for the provided Group Ids.
     *              UserOrGroupId can point to either a User or another Group.
     */
    public static List<GroupMember> getGroupMembersByGroupIds(Set<Id> groupIds) {
        if (
            groupIds != null && !groupIds.isEmpty() &&
            Schema.sObjectType.GroupMember.isAccessible()
        ) {
        return [
            SELECT Id, GroupId, UserOrGroupId
            FROM GroupMember
            WHERE GroupId IN :groupIds
            WITH USER_MODE
        ];
		}
        return new List<GroupMember>();
    }
    
    /**
     *Returns Custom Notification Type by DeveloperName.
	 *	GC 3143
     */
    public static CustomNotificationType getCustomNotificationTypeByDeveloperName( String developerName) {
         if (
            String.isNotBlank(developerName) &&
            Schema.sObjectType.CustomNotificationType.isAccessible()
        ) {
       	List<CustomNotificationType> notificationTypes = [
            SELECT Id, DeveloperName
            FROM CustomNotificationType
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];
        return notificationTypes.isEmpty() ? null : notificationTypes[0];
    	}
        return null;
    }
    /**
     * Returns Queue Id by Developer Name.
     *
     * @param queueDevName Developer Name of the Queue.
     * @return Queue Id if found; otherwise null.
     */
    public static Id getQueueIdByDeveloperName(String queueDevName) {
        if (
            String.isNotBlank(queueDevName) &&
            Schema.sObjectType.Group.isAccessible()
        ) {
            List<Group> queues = [
                SELECT Id
                FROM Group
                WHERE Type = 'Queue'
                AND DeveloperName = :queueDevName
                WITH USER_MODE
                LIMIT 1
            ];
    
            return queues.isEmpty() ? null : queues[0].Id;
        }
    
        return null;
    }
    
}