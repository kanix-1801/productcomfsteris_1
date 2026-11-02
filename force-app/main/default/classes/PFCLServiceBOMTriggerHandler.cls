/**
 * @description Trigger handler for the PFCLServiceBOM__c SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 */
public with sharing class PFCLServiceBOMTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('PFCLServiceBOMTrigger')) {
            return;
        }
        PFCLServiceBOMs domain = new PFCLServiceBOMs((List<PFCLServiceBOM__c>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('PFCLServiceBOMTrigger')) {
            return;
        }
        PFCLServiceBOMs domain = new PFCLServiceBOMs((List<PFCLServiceBOM__c>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes after insert logic.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('PFCLServiceBOMTrigger')) {
            return;
        }
        // Set<Id> junctionIds = new Map<Id, PFCLServiceBOM__c>((List<PFCLServiceBOM__c>) Trigger.new).keySet();
        // PFCLServiceBOMsService.handleNewPFCLServiceBOMs(junctionIds);
    }

    /**
     * @description Executes after update logic.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('PFCLServiceBOMTrigger')) {
            return;
        }
        // Set<Id> junctionIds = new Map<Id, PFCLServiceBOM__c>((List<PFCLServiceBOM__c>) Trigger.new).keySet();
        // PFCLServiceBOMsService.handleUpdatedPFCLServiceBOMs(junctionIds);
    }
}