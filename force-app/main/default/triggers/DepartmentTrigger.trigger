/**
 * @description Single entry-point trigger for the Department__c SObject.
 *              Delegates all logic to DepartmentTriggerHandler via the TriggerHandler framework.
 */
trigger DepartmentTrigger on Department__c (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    new DepartmentTriggerHandler().run();
}