/**
 * @description Trigger for Email Message object.
 * @author PSL
 * @date 2026-01-08
 * Change Date   Author              Description
 * ============================================================================
 * 2026-01-08    PSL                 Initial creation.
 * 2026-06-24    PSL                 CBM-422.
 * ============================================================================
 */
//*** Hadar Hargil 2.11.2026
// excluding the project obejct 
//trigger EmailMessageTrigger on EmailMessage (after insert) {
    
//    if(trigger.isAfter){
//        if(trigger.isInsert){
//            EmailMessageHandler.EmAfterInsertHandler(trigger.new);
//        }
//    }

//}

trigger EmailMessageTrigger on EmailMessage (after insert) {
    
    Id userId = UserInfo.getUserId();
    List<Automation_Setting_Trigger__c> automationSetting = [SELECT Id, SetupOwnerId, SetupOwner.Name, disableAll__c, 
        CaseTriggerByPass__c, EmailMessageTriggerByPass__c, HoldTriggerByPass__c, OrderLineContactTriggerByPass__c, TaskTriggerByPass__c 
        from Automation_Setting_Trigger__c 
        WHERE SetupOwnerId = :userId AND IsDeleted = false];
    if(automationSetting!=null && !automationSetting.isEmpty() && automationSetting[0].EmailMessageTriggerByPass__c)
        return;
    
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            // Bulk-safe filter: exclude EmailMessages related to Project__c
            List<EmailMessage> toProcess = new List<EmailMessage>();
            for (EmailMessage em : Trigger.new) {
                if (em.RelatedToId == null) {
                    toProcess.add(em);
                    continue;
                }
                // Use Id.getSObjectType() to check the target sObject type without queries
                if (em.RelatedToId.getSObjectType() != Project__c.SObjectType) {
                    toProcess.add(em);
                }
            }
            if (!toProcess.isEmpty()) {
                EmailMessageHandler.EmAfterInsertHandler(toProcess);
            }
        }
    }
}