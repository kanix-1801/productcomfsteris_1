/**
 * @description Single entry-point trigger for the Contact SObject.
 *              Delegates all logic to ContactTriggerHandler via the TriggerHandler framework.
 */
trigger ContactTrigger on Contact (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    new ContactTriggerHandler().run();
}