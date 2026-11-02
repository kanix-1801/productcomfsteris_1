/**
 * @author Suraj Thapliyal
 * @date 2026/08/17
 *
 * @group Sample
 *
 * @description
 * GC-3226 - SOQL-only selector for Sample create access and Follow-up notifications.
 * GC-3225 - Opportunity.HasSampleActivity__c stamp queries.
 */
public with sharing class SampleSelector {

    /**
     * @description Private constructor — static selector class (PMD UseSingleton).
     */
    private SampleSelector() {
    }

    /**
     * @description GC-3226 - Owner Ids for Related Opportunities, used to enforce Sample create access.
     *              System mode so Owner is known even when the running user cannot edit the Opportunity.
     * @param opportunityIds Related Opportunity Ids from Samples being inserted.
     * @return Opportunity Id to Owner Id.
     */
    public static Map<Id, Id> selectOwnerIdByOpportunityId(Set<Id> opportunityIds) {
        Map<Id, Id> ownerIdByOpportunityId = new Map<Id, Id>();
        if (opportunityIds != null && !opportunityIds.isEmpty()) {
            for (Opportunity opportunityRecord : [
                SELECT Id, OwnerId
                FROM Opportunity
                WHERE Id IN :opportunityIds
                WITH SYSTEM_MODE
            ]) {
                ownerIdByOpportunityId.put(opportunityRecord.Id, opportunityRecord.OwnerId);
            }
        }
        return ownerIdByOpportunityId;
    }

    /**
     * @description GC-3226 - Related Opportunity Ids on which the given user is an Opportunity Team Member.
     *              System mode so membership is evaluated from actual team rows, not sharing.
     * @param opportunityIds Related Opportunity Ids from Samples being inserted.
     * @param userId Running user Id.
     * @return Opportunity Ids where that user is a team member.
     */
    public static Set<Id> selectOpportunityIdsWhereUserIsTeamMember(Set<Id> opportunityIds, Id userId) {
        Set<Id> teamOpportunityIds = new Set<Id>();
        if (opportunityIds != null && !opportunityIds.isEmpty() && userId != null) {
            for (OpportunityTeamMember teamMember : [
                SELECT OpportunityId
                FROM OpportunityTeamMember
                WHERE OpportunityId IN :opportunityIds
                  AND UserId = :userId
                WITH SYSTEM_MODE
            ]) {
                teamOpportunityIds.add(teamMember.OpportunityId);
            }
        }
        return teamOpportunityIds;
    }

    /**
     * @description GC-3225 - Opportunities that still need HasSampleActivity__c stamped true.
     * @param opportunityIds Related Opportunity Ids from new Samples.
     * @return Opportunities where HasSampleActivity__c is not already true.
     */
    public static List<Opportunity> selectOpportunitiesMissingSampleActivity(Set<Id> opportunityIds) {
        List<Opportunity> opportunities = new List<Opportunity>();
        if (opportunityIds != null && !opportunityIds.isEmpty()) {
            opportunities = [
                SELECT Id, HasSampleActivity__c
                FROM Opportunity
                WHERE Id IN :opportunityIds
                  AND HasSampleActivity__c != true
                WITH SYSTEM_MODE
            ];
        }
        return opportunities;
    }

    /**
     * @description GC-3226 - Samples due for Follow-up bell + email on the given date.
     * @param followUpDate Follow-up Date to match (typically Date.today()).
     * @return QueryLocator for batch processing.
     */
    public static Database.QueryLocator selectDueForFollowUpNotification(Date followUpDate) {
        return Database.getQueryLocator([
            SELECT
                Id,
                Name,
                FollowUpDate__c,
                FollowUpReminder__c,
                FollowUpNotified__c,
                CreatedById
            FROM Sample__c
            WHERE FollowUpReminder__c = true
              AND FollowUpDate__c = :followUpDate
              AND FollowUpNotified__c = false
            WITH SYSTEM_MODE
        ]);
    }
}