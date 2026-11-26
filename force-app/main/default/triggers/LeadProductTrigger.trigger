/**
 * GC-3606 Lead Product trigger. Delegates to LeadProductTriggerHandler.
 */
trigger LeadProductTrigger on LeadProduct__c (before insert, before update) {
    new LeadProductTriggerHandler().run();
}