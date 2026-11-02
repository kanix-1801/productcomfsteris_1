/**
 * @author PSL
 * @date 02-05-2026
 * @description Task trigger routing to OrderLineContactTriggerHandler for before insert/update/delete and after insert/update/delete/undelete operations.
 */
trigger OrderLineContactTrigger on OrderLineContact__c (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete) {

    new OrderLineContactTriggerHandler().run();
}