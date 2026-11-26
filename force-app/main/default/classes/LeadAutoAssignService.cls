/**
 * GC-3662 Auto Assign Lead.
 * Checks the Auto Assign Lead checkbox on a Lead and starts routing the first time it is selected.
 * The checkbox can be selected once, only when the Lead has a Product, and cannot be cleared afterwards.
 * A Lead whose Lead Source is HubSpot follows the HubSpot routing instead.
 */
public with sharing class LeadAutoAssignService {

    private static final String HUBSPOT_SOURCE = 'HubSpot';

    /**
     * Returns true when the Lead has Auto Assign Lead selected and did not come from HubSpot.
     * @param leadRecord Lead to check.
     * @return True when the Lead is routed by Auto Assign Lead.
     */
    public static Boolean isEligible(Lead leadRecord) {
        return leadRecord.Auto_Assign_Lead__c && leadRecord.LeadSource != HUBSPOT_SOURCE;
    }

    /**
     * Rejects a new Lead saved outside the New Lead page with the checkbox selected,
     * because it cannot have a Product yet. The New Lead page checks its own Products.
     * @param newLeads Leads being inserted.
     */
    public static void validateInsert(List<Lead> newLeads) {
        if (LeadService.skipInsertTas) {
            return;
        }
        for (Lead leadRecord : newLeads) {
            if (leadRecord.Auto_Assign_Lead__c) {
                leadRecord.Auto_Assign_Lead__c.addError(System.Label.LeadAutoAssignOnInsertMessage);
            }
        }
    }

    /**
     * Rejects clearing the checkbox, and selecting it on a Lead that has no Product.
     * @param newLeads Leads being updated.
     * @param oldLeads Leads before the update.
     */
    public static void validateUpdate(List<Lead> newLeads, Map<Id, Lead> oldLeads) {
        Map<Id, Lead> selectedLeads = new Map<Id, Lead>();
        for (Lead leadRecord : newLeads) {
            Boolean wasSelected = oldLeads.get(leadRecord.Id).Auto_Assign_Lead__c;
            if (wasSelected && !leadRecord.Auto_Assign_Lead__c) {
                leadRecord.Auto_Assign_Lead__c.addError(System.Label.LeadAutoAssignLockedMessage);
            } else if (!wasSelected && leadRecord.Auto_Assign_Lead__c) {
                selectedLeads.put(leadRecord.Id, leadRecord);
            }
        }
        if (selectedLeads.isEmpty()) {
            return;
        }

        Set<Id> leadsWithProducts = new Set<Id>();
        for (AggregateResult row : [
            SELECT Lead__c leadId
            FROM LeadProduct__c
            WHERE Lead__c IN :selectedLeads.keySet()
            WITH USER_MODE
            GROUP BY Lead__c
        ]) {
            leadsWithProducts.add((Id) row.get('leadId'));
        }
        for (Lead leadRecord : selectedLeads.values()) {
            if (!leadsWithProducts.contains(leadRecord.Id)) {
                leadRecord.Auto_Assign_Lead__c.addError(System.Label.LeadAutoAssignNoProductMessage);
            }
        }
    }

    /**
     * Starts routing for each Lead where the checkbox was just selected.
     * Routing runs once because the checkbox cannot be cleared and selected again.
     * @param newLeads Leads after the update.
     * @param oldLeads Leads before the update.
     */
    public static void routeNewlySelected(List<Lead> newLeads, Map<Id, Lead> oldLeads) {
        List<Id> leadIds = new List<Id>();
        for (Lead leadRecord : newLeads) {
            if (isEligible(leadRecord) && !oldLeads.get(leadRecord.Id).Auto_Assign_Lead__c) {
                leadIds.add(leadRecord.Id);
            }
        }
        LeadRoutingQueueable.enqueue(leadIds);
    }
}