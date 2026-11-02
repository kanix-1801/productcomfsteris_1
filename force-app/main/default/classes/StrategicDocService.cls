/**
 * @description GC-3366
 *              Maintains HasSupportingDocumentation__c
 *              for Strategic Contract Opportunities.
 */
public with sharing class StrategicDocService {

    private static final String STRATEGIC_CONTRACT_RT =
        'HCSalesStrategicContract';

    /**
     * @description Sets HasSupportingDocumentation__c to TRUE
     *              when a file is linked to a Strategic Contract
     *              Opportunity.
     */
    public static void handleAfterInsert(
        List<ContentDocumentLink> newLinks
    ) {
        Set<Id> opportunityIds =
            getOpportunityIds(newLinks);

        if (opportunityIds.isEmpty()) {
            return;
        }

        List<Opportunity> opportunitiesToUpdate =
            new List<Opportunity>();

        for (Opportunity opp : [
            SELECT Id,
                   HasSupportingDocumentation__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
            AND RecordType.DeveloperName = :STRATEGIC_CONTRACT_RT
        ]) {

            if (opp.HasSupportingDocumentation__c != true) {

                opportunitiesToUpdate.add(
                    new Opportunity(
                        Id = opp.Id,
                        HasSupportingDocumentation__c = true
                    )
                );
            }
        }

        if (!opportunitiesToUpdate.isEmpty()) {
            update opportunitiesToUpdate;
        }
    }

    /**
     * @description Checks remaining files after a link is deleted.
     *              Sets HasSupportingDocumentation__c to FALSE
     *              only when no files remain.
     */
    public static void handleAfterDelete(
        List<ContentDocumentLink> oldLinks
    ) {
        Set<Id> opportunityIds =
            getOpportunityIds(oldLinks);

        if (opportunityIds.isEmpty()) {
            return;
        }

        Map<Id, Opportunity> strategicOppMap =
            new Map<Id, Opportunity>([
                SELECT Id,
                       HasSupportingDocumentation__c
                FROM Opportunity
                WHERE Id IN :opportunityIds
                AND RecordType.DeveloperName = :STRATEGIC_CONTRACT_RT
            ]);

        if (strategicOppMap.isEmpty()) {
            return;
        }

        Set<Id> opportunitiesWithFiles = new Set<Id>();

        /*
         * Because this runs in afterDelete, the deleted
         * ContentDocumentLink is no longer returned.
         */
        for (ContentDocumentLink link : [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :strategicOppMap.keySet()
        ]) {
            opportunitiesWithFiles.add(
                link.LinkedEntityId
            );
        }

        List<Opportunity> opportunitiesToUpdate =
            new List<Opportunity>();

        for (Opportunity opp : strategicOppMap.values()) {

            Boolean hasFiles =
                opportunitiesWithFiles.contains(opp.Id);

            if (opp.HasSupportingDocumentation__c != hasFiles) {

                opportunitiesToUpdate.add(
                    new Opportunity(
                        Id = opp.Id,
                        HasSupportingDocumentation__c = hasFiles
                    )
                );
            }
        }

        if (!opportunitiesToUpdate.isEmpty()) {
            update opportunitiesToUpdate;
        }
    }

    /**
     * @description Extracts only Opportunity IDs from
     *              ContentDocumentLink records.
     */
    private static Set<Id> getOpportunityIds(
        List<ContentDocumentLink> links
    ) {
        Set<Id> opportunityIds = new Set<Id>();

        if (links == null || links.isEmpty()) {
            return opportunityIds;
        }

        for (ContentDocumentLink link : links) {

            if (
                link.LinkedEntityId != null &&
                link.LinkedEntityId.getSObjectType() ==
                    Opportunity.SObjectType
            ) {
                opportunityIds.add(
                    link.LinkedEntityId
                );
            }
        }

        return opportunityIds;
    }
}