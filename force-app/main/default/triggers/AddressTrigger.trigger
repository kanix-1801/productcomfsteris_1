/**
 * @description After insert/update trigger on Address for realtime TAS team access.
 *              Keeps trigger logic thin and delegates to OrderLineContactAddressTriggerHandler
 *              using the Kevin Ohara TriggerHandler framework.
 *              Realtime scope is ADD-only (no delete team processing from Address trigger).
 */
trigger AddressTrigger on Address (after insert, after update) {

    Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();

    if (settings != null && (settings.AddressTriggerByPass__c || settings.disableAll__c)) {
        return;
    }
    new AddressTriggerHandller().run();
}