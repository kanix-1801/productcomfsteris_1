/**
 * @description Single entry-point trigger for the ReturnOrderLineItem SObject.
 *              Delegates all logic to ReturnOrderLineItemTriggerHandler via the TriggerHandler framework.
 */
trigger ReturnOrderLineItemTrigger on ReturnOrderLineItem (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    new ReturnOrderLineItemTriggerHandler().run();
}