/**
 * Handles Lead before-insert duplicate checks, after-insert routing,
 * and after-update SLA clocks.
 *
 * @author Abhishek Mishra
 * @date 06-08-2026
 * @description #GC-3279 Receives Lead trigger context and guards against recursive
 *              after-insert execution via TriggerControl. After insert, a backend
 *              HubSpot Lead uses the same matrix, TAS, country queue, and ultimate queue
 *              flow as the New Lead page. A Lead created in Salesforce is not routed.
 *              The New Lead page sets
 *              LeadService.skipInsertTas so it is not routed twice. GC-3449
 *              starts the SLA clock after an owner or status change.
 */
public with sharing class LeadTriggerHandler extends TriggerHandler {
    /**
     * @description GC-3541 Part 1 for bulk upload only. A standard Lead Save is unchanged.
     */
    @TestVisible
    protected override void beforeInsert() {
        if (TriggerControl.enterBeforeInsert(Lead.SObjectType) && LeadDuplicateService.isBulkRequest()) {
            LeadDuplicateService.checkForDuplicateLeadsAndContacts((List<Lead>) Trigger.new);
        }
    }

    /**
     * @description Routes each inserted HubSpot Lead after the transaction commits.
     *              The New Lead page sets LeadService.skipInsertTas because it
     *              enqueues this same job after its products are saved.
     */
    @TestVisible
    protected override void afterInsert() {
        if (!TriggerControl.enterAfterInsert(Lead.SObjectType) || LeadService.skipInsertTas) {
            return;
        }
        List<Id> leadIds = new List<Id>();
        for (Lead leadRecord : (List<Lead>) Trigger.new) {
            if (leadRecord.HubSpot_Lead__c) {
                leadIds.add(leadRecord.Id);
            }
        }
        if (!leadIds.isEmpty()) {
            LeadRoutingQueueable.enqueue(leadIds);
        }
    }

    /**
     * @description Starts or stops the Lead SLA clock when the owner or status changes.
     */
    @TestVisible
    protected override void afterUpdate() {
        if (TriggerControl.enterAfterUpdate(Lead.SObjectType)) {
            Map<Id, Lead> oldLeads = (Map<Id, Lead>) Trigger.oldMap;
            LeadSlaService.apply((List<Lead>) Trigger.new, oldLeads);
            LeadNurtureFollowUpService.apply((List<Lead>) Trigger.new, oldLeads);
        }
    }
}