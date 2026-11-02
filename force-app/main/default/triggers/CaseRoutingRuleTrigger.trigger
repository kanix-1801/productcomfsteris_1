/**
 * @description Trigger for CaseRoutingRule__c object
 * @author Agentforce
 * @date 2026-04-27
 */
trigger CaseRoutingRuleTrigger on CaseRoutingRule__c (before insert, before update, after insert, after update, after delete) {
    new CaseRoutingRuleTriggerHandler().run();
}