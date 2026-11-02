/**
 * @description Single entry-point trigger for the ProductRequest SObject.
 *              Delegates all logic to ProductRequestTriggerHandler via the TriggerHandler framework.
 */
trigger ProductRequestTrigger on ProductRequest (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    new ProductRequestTriggerHandler().run();
}