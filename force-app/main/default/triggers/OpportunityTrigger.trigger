/**
 * @description After insert/update trigger on Opportunity for realtime TAS team access.
 *              Keeps trigger logic thin and delegates to OrderLineContactOppTriggerHandler
 *              using the Kevin Ohara TriggerHandler framework.
 *              Fires when Opportunity Address__c is populated or changed.
 *              Realtime scope is ADD-only (no delete team processing from Opportunity trigger).
 */
trigger OpportunityTrigger on Opportunity (before insert, before update, after insert, after update) {

    Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();

    if (settings != null && (settings.OpportunityTriggerByPass__c || settings.disableAll__c)) {
        return;
    }
    new OpportunityTriggerHandller().run();
}