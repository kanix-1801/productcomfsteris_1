/**
* @author PWC Developer
* @date 2026/06/10
*
* @group Overlay Assignment
*
* @description
* GC-3088 - SOQL - only selector for OpportunityTeamMember Object
*/
public with sharing class OpportunityTeamMemberSelector {
    /**
* @description
* GC-3088 - Selects Selects existing Opportunity Team Members for duplicate prevention.
* GC-3179 - Modified: WITH USER_MODE replaces WITH SECURITY_ENFORCED for user-mode access.
* 
* @param opportunityIdSet Opportunity ID set
* @param userIdSet user ID set
* @return Existing Opportunity Team Members.
* 
* @example
* OpportunityTeamMemberSelector.selectByOpportunitiesAndUsers(opportunityIdSet, userIdSet);
*/
    public static List<OpportunityTeamMember> selectByOpportunitiesAndUsers(Set<Id> opportunityIdSet, Set<Id> userIdSet) {
        if (opportunityIdSet == null || opportunityIdSet.isEmpty() || userIdSet == null || userIdSet.isEmpty()) {
            return new List<OpportunityTeamMember>();
        }
        
        return [
            SELECT OpportunityId,
            UserId,
            OpportunityAccessLevel
            FROM OpportunityTeamMember
            WHERE OpportunityId IN :opportunityIdSet
            AND UserId IN :userIdSet
            WITH USER_MODE
        ];
    }

    /**
     * @author Suraj Thapliyal
     * @description GC-2580 Selects Opportunity Team Members by User Id, including access level fields.
     * @param userIds User Ids to query.
     * @return OpportunityTeamMember rows for the given users.
     */
    public static List<OpportunityTeamMember> selectByUserIds(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return new List<OpportunityTeamMember>();
        }

        return [
            SELECT Id, OpportunityId, UserId, TeamMemberRole, OpportunityAccessLevel
            FROM OpportunityTeamMember
            WHERE UserId IN :userIds
            WITH USER_MODE
        ];
    }

    /**
     * @author Suraj Thapliyal
     * @description GC-2580 Selects Opportunity Team Members by opportunity, user, and role.
     * @param opportunityIdSet Opportunity Ids.
     * @param userIdSet User Ids.
     * @param teamMemberRole Team member role to match.
     * @return Matching OpportunityTeamMember rows.
     */
    public static List<OpportunityTeamMember> selectByOpportunitiesUsersAndRole(
        Set<Id> opportunityIdSet,
        Set<Id> userIdSet,
        String teamMemberRole
    ) {
        if (opportunityIdSet == null || opportunityIdSet.isEmpty()
            || userIdSet == null || userIdSet.isEmpty()
            || String.isBlank(teamMemberRole)) {
            return new List<OpportunityTeamMember>();
        }

        return [
            SELECT Id, OpportunityId, UserId
            FROM OpportunityTeamMember
            WHERE OpportunityId IN :opportunityIdSet
              AND UserId IN :userIdSet
              AND TeamMemberRole = :teamMemberRole
            WITH USER_MODE
        ];
    }

    /**
     * @author Suraj Thapliyal
     * @description GC-2580 Selects Opportunity Team Members by opportunity, user, role, assignment type, and expiry date.
     * @param opportunityIdSet Opportunity Ids.
     * @param userIdSet User Ids.
     * @param teamMemberRole Team member role to match.
     * @param assignmentType AssignmentType__c value to match.
     * @param expiryDate ExpiryDate__c value to match.
     * @return Matching OpportunityTeamMember rows.
     */
    public static List<OpportunityTeamMember> selectByOpportunitiesUsersRoleAssignmentType(
        Set<Id> opportunityIdSet,
        Set<Id> userIdSet,
        String teamMemberRole,
        String assignmentType
        
    ) {
        if (opportunityIdSet == null || opportunityIdSet.isEmpty()
            || userIdSet == null || userIdSet.isEmpty()
            || String.isBlank(teamMemberRole)
            || String.isBlank(assignmentType)
          ) {
            return new List<OpportunityTeamMember>();
        }

        return [
            SELECT Id, OpportunityId, UserId, TeamMemberRole, AssignmentType__c
            FROM OpportunityTeamMember
            WHERE OpportunityId IN :opportunityIdSet
              AND UserId IN :userIdSet
              AND TeamMemberRole = :teamMemberRole
              AND AssignmentType__c = :assignmentType
            WITH USER_MODE
        ];
    }
}