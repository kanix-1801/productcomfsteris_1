/**
 * Lead platform trigger that delegates events to LeadTriggerHandler.
 *
 * Steris standards:
 * - Org bypass: Automation_Setting_Trigger__c.LeadTriggerByPass__c.
 * - Recursion: TriggerControl in handler.
 *
 * @description #GC-3279 Delegates to LeadTriggerHandler via kevinohara80
 */
trigger LeadTrigger on Lead (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();

    if (settings == null
        || (!settings.LeadTriggerByPass__c && !settings.disableAll__c)
    ) {
        new LeadTriggerHandler().run();
    }
}