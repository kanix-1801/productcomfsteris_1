public with sharing class OppSupportingDocService  {

    /**
     * When a file is linked to an Opportunity,
     * mark HasSupportingDocumentation__c = true.
     */
    public static void handleAfterInsert(
        List<ContentDocumentLink> newLinks
    ) {
        Set<Id> opportunityIds = getOpportunityIds(newLinks);

        if (opportunityIds.isEmpty()) {
            return;
        }

        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();

        for (Id opportunityId : opportunityIds) {
            opportunitiesToUpdate.add(
                new Opportunity(
                    Id = opportunityId,
                    HasSupportingDocumentation__c = true
                )
            );
        }

        if (!opportunitiesToUpdate.isEmpty()) {
            update opportunitiesToUpdate;
        }
    }


    /**
     * When a file link is removed, check whether
     * the Opportunity still has any other files.
     */
    public static void handleAfterDelete(
        List<ContentDocumentLink> oldLinks
    ) {
        Set<Id> opportunityIds = getOpportunityIds(oldLinks);

        if (opportunityIds.isEmpty()) {
            return;
        }

        Set<Id> opportunitiesWithFiles = new Set<Id>();

        for (ContentDocumentLink remainingLink : [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :opportunityIds
        ]) {
            opportunitiesWithFiles.add(remainingLink.LinkedEntityId);
        }

        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();

        for (Id opportunityId : opportunityIds) {
            opportunitiesToUpdate.add(
                new Opportunity(
                    Id = opportunityId,
                    HasSupportingDocumentation__c =
                        opportunitiesWithFiles.contains(opportunityId)
                )
            );
        }

        if (!opportunitiesToUpdate.isEmpty()) {
            update opportunitiesToUpdate;
        }
    }


    /**
     * Return only Opportunity LinkedEntityIds.
     */
    private static Set<Id> getOpportunityIds(
        List<ContentDocumentLink> links
    ) {
        Set<Id> opportunityIds = new Set<Id>();

        if (links == null) {
            return opportunityIds;
        }

        for (ContentDocumentLink link : links) {

            if (
                link.LinkedEntityId != null &&
                link.LinkedEntityId.getSObjectType() == Opportunity.SObjectType
            ) {
                opportunityIds.add(link.LinkedEntityId);
            }
        }

        return opportunityIds;
    }
}