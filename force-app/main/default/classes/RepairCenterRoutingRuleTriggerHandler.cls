/**
 * @description Trigger handler for the RepairCenterRoutingRule__c SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 */
public with sharing class RepairCenterRoutingRuleTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('RepairCenterRoutingRuleTrigger')) {
            return;
        }
        RepairCenterRoutingRules domain = new RepairCenterRoutingRules((List<RepairCenterRoutingRule__c>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('RepairCenterRoutingRuleTrigger')) {
            return;
        }
        RepairCenterRoutingRules domain = new RepairCenterRoutingRules((List<RepairCenterRoutingRule__c>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes after insert logic.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('RepairCenterRoutingRuleTrigger')) {
            return;
        }
        // Set<Id> ruleIds = new Map<Id, RepairCenterRoutingRule__c>((List<RepairCenterRoutingRule__c>) Trigger.new).keySet();
        // RepairCenterRoutingRulesService.handleNewRepairCenterRoutingRules(ruleIds);
    }

    /**
     * @description Executes after update logic.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('RepairCenterRoutingRuleTrigger')) {
            return;
        }
        // Set<Id> ruleIds = new Map<Id, RepairCenterRoutingRule__c>((List<RepairCenterRoutingRule__c>) Trigger.new).keySet();
        // RepairCenterRoutingRulesService.handleUpdatedRepairCenterRoutingRules(ruleIds);
    }
}