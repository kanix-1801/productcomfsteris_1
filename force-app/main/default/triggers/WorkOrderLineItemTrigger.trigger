/**
 * @description Trigger for the WorkOrderLineItem SObject.
 *              Delegates all logic to WorkOrderLineItemTriggerHandler.
 */
trigger WorkOrderLineItemTrigger on WorkOrderLineItem (
    before insert,
    before update,
    after insert,
    after update
) {
    new WorkOrderLineItemTriggerHandler().run();
}