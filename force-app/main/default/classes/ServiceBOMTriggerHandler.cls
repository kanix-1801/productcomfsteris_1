/**
 * @description Trigger handler for the ServiceBOM__c SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 */
public with sharing class ServiceBOMTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('ServiceBOMTrigger')) {
            return;
        }
        ServiceBOMs domain = new ServiceBOMs((List<ServiceBOM__c>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('ServiceBOMTrigger')) {
            return;
        }
        ServiceBOMs domain = new ServiceBOMs((List<ServiceBOM__c>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes after insert logic.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('ServiceBOMTrigger')) {
            return;
        }
        // Set<Id> serviceBomIds = new Map<Id, ServiceBOM__c>((List<ServiceBOM__c>) Trigger.new).keySet();
        // ServiceBOMsService.handleNewServiceBOMs(serviceBomIds);
    }

    /**
     * @description Executes after update logic.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('ServiceBOMTrigger')) {
            return;
        }
        // Set<Id> serviceBomIds = new Map<Id, ServiceBOM__c>((List<ServiceBOM__c>) Trigger.new).keySet();
        // ServiceBOMsService.handleUpdatedServiceBOMs(serviceBomIds);
    }
}