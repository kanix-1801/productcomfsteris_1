/**
 * @author Divya Sree
 * @date 14-10-2026
 * @description #GC-3563 Delegates CSC visit confirmation to the handler.
 *              #GC-3579 Keeps the Opportunity CSC visit count current.
 *              Org bypass: Automation_Setting_Trigger__c.disableAll__c.
 */
trigger CSCVisitRequestTrigger on CSC_Visit_Request__c (
    before update,
    after insert,
    after update,
    after delete,
    after undelete
) {
    Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();
    if (settings == null || !settings.disableAll__c) {
        new CSCVisitRequestTriggerHandler().run();
    }
}