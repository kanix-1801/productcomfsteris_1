/**
 * Account trigger — orchestrates via kevinohara80 TriggerHandler (AccountTriggerHandler.run()).
 *
 * Steris standards:
 * - Org bypass: Automation_Setting_Trigger__c.AccountTriggerByPass__c.
 * - Recursion: AccountTriggerControl in handler.
 */
trigger AccountTrigger on Account (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();

    if (settings != null && (settings.AccountTriggerByPass__c || settings.disableAll__c)) {
        return;
    }

    new AccountTriggerHandler().run();
}