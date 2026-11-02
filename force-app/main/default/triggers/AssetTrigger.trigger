/**
 * @description Single entry-point trigger for the Asset SObject.
 *              Delegates all logic to AssetTriggerHandler via the TriggerHandler framework.
 */
trigger AssetTrigger on Asset (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
){
    new AssetTriggerHandler().run();
}