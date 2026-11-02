/**
 * @author Divya Sree
 * @date 14-10-2026
 * @description #GC-3563 AC1 Delegates STERIS attendee changes to the handler.
 *              Org bypass: Automation_Setting_Trigger__c.disableAll__c.
 */
trigger CSCVisitAttendeeTrigger on CSCVisitAttendee__c (
    after insert,
    after update,
    after delete
) {
    Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();
    if (settings == null || !settings.disableAll__c) {
        new CSCVisitAttendeeTriggerHandler().run();
    }
}