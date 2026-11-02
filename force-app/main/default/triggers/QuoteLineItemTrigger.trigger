/**
 * @author PWC Developer
 * @date 2026/07/27
 *
 * @group Product Sub-Group Detail
 *
 * @description GC-3129 After insert/update/delete/undelete trigger on Quote Line Item.
 *              Keeps trigger logic thin and delegates to QuoteLineItemTriggerHandler
 *              using the Kevin Ohara TriggerHandler framework.
 */
trigger QuoteLineItemTrigger on QuoteLineItem (
    after insert,
    after update,
    after delete,
    after undelete,
    before insert,
    before update
) {
    Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();

    if (settings != null && settings.disableAll__c) {
        return;
    }

    new QuoteLineItemTriggerHandler().run();
}