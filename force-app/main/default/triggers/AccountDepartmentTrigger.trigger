/**
 * @description Single entry-point trigger for the AccountDepartment__c SObject.
 *              Delegates all logic to AccountDepartmentTriggerHandler via the TriggerHandler framework.
 */
trigger AccountDepartmentTrigger on AccountDepartment__c (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    new AccountDepartmentTriggerHandler().run();
}