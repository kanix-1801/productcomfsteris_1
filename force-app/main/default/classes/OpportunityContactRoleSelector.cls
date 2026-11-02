/**
 * @author Akash Dahinde
 * @date 09-25-2026
 * @story GCL-11
 * @description Selector for OpportunityContactRole queries.
 *              Centralizes all OCR SOQL required by PrimaryContactService.
 */
public with sharing class OpportunityContactRoleSelector {

    /**
     * @description Selects all contact roles related to the supplied Opportunities.
     * @param opportunityIds Parent Opportunity Ids.
     * @return Related OCR records with fields required for synchronization.
     */
    public List<OpportunityContactRole> selectByOpportunityIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return new List<OpportunityContactRole>();
        }
        return [
            SELECT Id, OpportunityId, ContactId, IsPrimary
            FROM OpportunityContactRole
            WHERE OpportunityId IN :opportunityIds
        ];
    }

    /**
     * @description Selects Primary contact roles for the supplied Opportunities.
     * @param opportunityIds Parent Opportunity Ids.
     * @return Related OCR records where IsPrimary is true.
     */
    public List<OpportunityContactRole> selectPrimaryByOpportunityIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return new List<OpportunityContactRole>();
        }
        return [
            SELECT Id, OpportunityId, ContactId, IsPrimary
            FROM OpportunityContactRole
            WHERE OpportunityId IN :opportunityIds
            AND IsPrimary = TRUE
        ];
    }
}