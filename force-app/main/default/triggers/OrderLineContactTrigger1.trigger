/*Shiv kumar To be deleted*/
trigger OrderLineContactTrigger1 on OrderLineContact__c ( before insert,
 
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete) {

    Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();

    if (settings != null && (settings.OrderLineContactTriggerByPass__c   || settings.disableAll__c)) {
        return;
    }

    new OrderLineContactTriggerHandler().run();
}