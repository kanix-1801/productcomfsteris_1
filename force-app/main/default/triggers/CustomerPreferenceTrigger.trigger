/**
 * @description Single entry-point trigger for the CustomerPreference__c SObject.
 *              Delegates all logic to CustomerPreferenceTriggerHandler via the TriggerHandler framework.
 */
trigger CustomerPreferenceTrigger on CustomerPreference__c (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    new CustomerPreferenceTriggerHandler().run();
}