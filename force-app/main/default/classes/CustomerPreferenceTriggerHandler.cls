/**
 * @description Trigger handler for the CustomerPreference__c SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 */
public with sharing class CustomerPreferenceTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('CustomerPreferenceTrigger')) {
            return;
        }
        CustomerPreferences domain = new CustomerPreferences((List<CustomerPreference__c>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('CustomerPreferenceTrigger')) {
            return;
        }
        CustomerPreferences domain = new CustomerPreferences((List<CustomerPreference__c>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes after insert logic.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('CustomerPreferenceTrigger')) {
            return;
        }
        // Set<Id> preferenceIds = new Map<Id, CustomerPreference__c>((List<CustomerPreference__c>) Trigger.new).keySet();
        // CustomerPreferencesService.handleNewCustomerPreferences(preferenceIds);
    }

    /**
     * @description Executes after update logic.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('CustomerPreferenceTrigger')) {
            return;
        }
        // Set<Id> preferenceIds = new Map<Id, CustomerPreference__c>((List<CustomerPreference__c>) Trigger.new).keySet();
        // CustomerPreferencesService.handleUpdatedCustomerPreferences(preferenceIds);
    }
}