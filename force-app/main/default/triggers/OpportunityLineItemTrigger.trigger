/**
 * @author PWC Developer
 * @date 2026/07/23
 *
 * @group Product Sub-Group Detail
 *
 * @description GC-3129 After insert/update/delete/undelete trigger on Opportunity Line Item.
 *              Keeps trigger logic thin and delegates to OpportunityLineItemTriggerHandler
 *              using the Kevin Ohara TriggerHandler framework.
 */
trigger OpportunityLineItemTrigger on OpportunityLineItem (
    after insert,
    after update,
    after delete,
    after undelete
) {
    Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();

    if (settings != null && settings.disableAll__c) {
        return;
    }

    new OpportunityLineItemTriggerHandler().run();
}