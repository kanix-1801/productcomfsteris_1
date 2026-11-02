/**
 * @description Single entry-point trigger for the WorkOrder SObject.
 *              Delegates all logic to WorkOrderTriggerHandler via the TriggerHandler framework.
 */
trigger WorkOrderTrigger on WorkOrder (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    new WorkOrderTriggerHandler().run();
}