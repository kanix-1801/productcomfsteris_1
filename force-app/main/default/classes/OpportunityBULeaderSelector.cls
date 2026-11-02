/**
 * @description
 * Selector class for OpportunityBULeaderTeamSync.
 * Contains all query logic used to synchronize
 * Business Unit Leaders with Opportunity Team Members.
 */
public with sharing class OpportunityBULeaderSelector {

    /**
     * @description
     * Retrieves Opportunities along with the given
     * Business Unit multi-select picklist field.
     * Dynamic SOQL is used because the field API name
     * is configurable by the caller.
     */
    public static List<Opportunity> selectOpportunitiesWithBUField(
        Set<Id> opportunityIds,
        String buFieldApiName
    ) {
        String query =
            'SELECT Id, ' + buFieldApiName + ' FROM Opportunity WHERE Id IN :opportunityIds';

        return Database.query(query);
    }

    /**
     * @description
     * Retrieves all Business Unit -> Business Unit Leader
     * Custom Metadata mappings that have both fields populated.
     */
    public static List<Business_Unit_Leader_Mappings__mdt> selectBULeaderMappings() {
        return [
            SELECT Business_Unit__c, Business_Unit_Leader__c
            FROM Business_Unit_Leader_Mappings__mdt
            WHERE Business_Unit__c != null
            AND Business_Unit_Leader__c != null
        ];
    }

    /**
     * @description
     * Retrieves active Users whose Username matches
     * one of the given leader names.
     */
    public static List<User> selectActiveUsersByUsernames(
        Set<String> usernames
    ) {
        return [
            SELECT Id, Name, IsActive, Username
            FROM User
            WHERE Username IN :usernames
            AND IsActive = true
        ];
    }

    /**
     * @description
     * Retrieves existing Opportunity Team Members that hold
     * the given BU Leader team member role for the given Opportunities.
     */
    public static List<OpportunityTeamMember> selectBULeaderTeamMembers(
        Set<Id> opportunityIds,
        String teamMemberRole
    ) {
        return [
            SELECT Id, OpportunityId, UserId, TeamMemberRole, OpportunityAccessLevel
            FROM OpportunityTeamMember
            WHERE OpportunityId IN :opportunityIds
            AND TeamMemberRole = :teamMemberRole
        ];
    }
}