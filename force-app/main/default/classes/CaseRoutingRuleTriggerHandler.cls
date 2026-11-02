/**
 * @description Trigger handler for CaseRoutingRule__c - orchestrates Domain and Service layer calls
 * @author Agentforce
 * @date 2026-04-27
 * @group Trigger Handlers
 */
public class CaseRoutingRuleTriggerHandler extends TriggerHandler {
    /**
     * @description Handles before insert logic
     */
    public override void beforeInsert() {
        // Automation control check - exit if trigger is disabled
        if (!AutomationControl.isTriggerEnabled('CaseRoutingRuleTrigger')) return;
        // Create domain instance with new records
        CaseRoutingRules domain = new CaseRoutingRules((List<CaseRoutingRule__c>) Trigger.new);
        
    }

    /**
     * @description Handles before update logic
     */
    public override void beforeUpdate() {
        // Automation control check - exit if trigger is disabled
        if (!AutomationControl.isTriggerEnabled('CaseRoutingRuleTrigger')) return;        
        // Create domain instance with updated records
        CaseRoutingRules domain = new CaseRoutingRules((List<CaseRoutingRule__c>) Trigger.new);
        
        
        
    }

    /**
     * @description Handles after insert logic
     */
    public override void afterInsert() {
        // Automation control check - exit if trigger is disabled
        if (!AutomationControl.isTriggerEnabled('CaseRoutingRuleTrigger')) return;        
        // Log successful creation
        Logger.info(new LogMessage('CaseRoutingRule__c records created: {0}', Trigger.new.size()));
    }

    /**
     * @description Handles after update logic
     */
    public override void afterUpdate() {
        // Automation control check - exit if trigger is disabled
        if (!AutomationControl.isTriggerEnabled('CaseRoutingRuleTrigger')) return;
        // Log successful update
        Logger.info(new LogMessage('CaseRoutingRule__c records updated: {0}', Trigger.new.size()));
    }

    /**
     * @description Handles after delete logic
     */
    public override void afterDelete() {
        // Automation control check - exit if trigger is disabled
        if (!AutomationControl.isTriggerEnabled('CaseRoutingRuleTrigger')) return;
        // Log successful deletion
        Logger.info(new LogMessage('CaseRoutingRule__c records deleted: {0}', Trigger.old.size()));
    }
}