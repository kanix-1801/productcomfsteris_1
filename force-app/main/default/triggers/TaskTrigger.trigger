/**
 * @author PSL
 * @date 12-31-2025
 * @description Task trigger routing to TaskTriggerHandler for before insert, update, and delete operations.
 */
trigger TaskTrigger on Task (before insert, before update, before delete, 
                                after insert, after update, after delete, after undelete) {
    new TaskTriggerHandler().run();
}