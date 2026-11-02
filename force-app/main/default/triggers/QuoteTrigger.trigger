/**
 * @author Himanshu Chaurasia
 * @date 2026/07/28
 *
 * @description GC-2659 After insert/update/delete trigger on Quote
 *                      
 */
trigger QuoteTrigger on Quote (
    before insert,
    before update,
    after insert,
    after update,
    after delete
) {
    Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();

    if (settings != null && (settings.QuoteTriggerByPass__c || settings.disableAll__c)) {
        return;
    }

    new QuoteTriggerHandler().run();
}