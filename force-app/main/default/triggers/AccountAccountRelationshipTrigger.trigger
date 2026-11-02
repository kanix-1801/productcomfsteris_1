/**
 * AccountAccountRelationship trigger — orchestrates via kevinohara80 TriggerHandler.
 *
 * Steris standards:
 * - Org bypass: Automation_Setting_Trigger__c.AccountAccountRelationshipTriggerByPass__c.
 * - Recursion: TriggerControl in handler.
 *
 * User Story - GC-3213
 */
trigger AccountAccountRelationshipTrigger on AccountAccountRelationship__c (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();

    if (settings != null
        && (settings.AccountAccountRelationshipTriggerByPass__c || settings.disableAll__c)
    ) {
        return;
    }

    new AccountAccountRelationshipTriggerHandler().run();
}