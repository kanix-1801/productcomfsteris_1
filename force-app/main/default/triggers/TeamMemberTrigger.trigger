/**
 * @author Abhishek Mishra
 * @date 15-10-2026
 * @description #GC-3435 Shares the related record when a Team Member is added, changed, or removed.
 *              Org bypass: Automation_Setting_Trigger__c.disableAll__c.
 */
trigger TeamMemberTrigger on TeamMember__c (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();
    if (settings == null || !settings.disableAll__c) {
        new TeamMemberTriggerHandler().run();
    }
}