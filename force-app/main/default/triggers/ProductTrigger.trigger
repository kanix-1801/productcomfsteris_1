/**
 * @description Single entry-point trigger for the Product2 SObject.
 *              Delegates all logic to ProductTriggerHandler via the TriggerHandler framework.
 */
trigger ProductTrigger on Product2 (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    new ProductTriggerHandler().run();
}