/**
 * @description Trigger handler for the PFCL__c SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 */
public with sharing class PFCLTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('PFCLTrigger')) {
            return;
        }
        PFCLs domain = new PFCLs((List<PFCL__c>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('PFCLTrigger')) {
            return;
        }
        PFCLs domain = new PFCLs((List<PFCL__c>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes after insert logic.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('PFCLTrigger')) {
            return;
        }
        // Set<Id> pfclIds = new Map<Id, PFCL__c>((List<PFCL__c>) Trigger.new).keySet();
        // PFCLsService.handleNewPFCLs(pfclIds);
    }

    /**
     * @description Executes after update logic.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('PFCLTrigger')) {
            return;
        }
        // Set<Id> pfclIds = new Map<Id, PFCL__c>((List<PFCL__c>) Trigger.new).keySet();
        // PFCLsService.handleUpdatedPFCLs(pfclIds);
    }
}