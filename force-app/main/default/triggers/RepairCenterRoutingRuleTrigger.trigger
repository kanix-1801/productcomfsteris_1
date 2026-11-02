/**
 * @description Single entry-point trigger for the RepairCenterRoutingRule__c SObject.
 *              Delegates all logic to RepairCenterRoutingRuleTriggerHandler via the TriggerHandler framework.
 */
trigger RepairCenterRoutingRuleTrigger on RepairCenterRoutingRule__c (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    new RepairCenterRoutingRuleTriggerHandler().run();
}