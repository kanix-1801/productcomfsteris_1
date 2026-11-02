/**
 * @description Trigger for Order And OrderLine Hold object.
 * @author PSL
 * @date 2026-02-04
 * Change Date   Author              Description
 * ============================================================================
 * 2026-02-04    PSL                 Initial creation.
 * 2026-06-24    PSL                 CBM-422.
 * ============================================================================
 */
trigger OrderAndOrderLineHoldTrigger on OrderAndOrderLineHold__c (after insert,after Update) {
    
    Id userId = UserInfo.getUserId();
    List<Automation_Setting_Trigger__c> automationSetting = [SELECT Id, SetupOwnerId, SetupOwner.Name, disableAll__c, 
        CaseTriggerByPass__c, EmailMessageTriggerByPass__c, HoldTriggerByPass__c, OrderLineContactTriggerByPass__c, TaskTriggerByPass__c 
        from Automation_Setting_Trigger__c 
        WHERE SetupOwnerId = :userId AND IsDeleted = false];
    if(automationSetting!=null && !automationSetting.isEmpty() && automationSetting[0].HoldTriggerByPass__c)
        return;
    
    if(trigger.isAfter){
        if(trigger.isInsert){
            HoldTriggerHandler.afterTriggerHandler(trigger.new,null);
            
        }
        
        if(trigger.isUpdate){
            HoldTriggerHandler.afterTriggerHandler(trigger.new,trigger.oldmap);
        }
    }

}