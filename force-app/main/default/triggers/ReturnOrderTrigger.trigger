/**
 * @description Single entry-point trigger for the ReturnOrder SObject.
 *              Delegates all logic to ReturnOrderTriggerHandler via the TriggerHandler framework.
 */
trigger ReturnOrderTrigger on ReturnOrder (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    new ReturnOrderTriggerHandler().run();
}