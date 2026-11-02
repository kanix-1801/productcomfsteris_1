/**
 * @author Suraj Thapliyal
 * @date 2026/08/20
 *
 * @group Sample
 *
 * @description
 * GC-3226 - Sample__c trigger. Thin entry point; delegates to SampleTriggerHandler.
 *           Before insert: only Opportunity Owner or Opportunity Team Member may create.
 *           Before update: re-arm Follow-up Notified when Follow-up Date or Reminder changes.
 *           Bypass: Automation_Setting_Trigger__c.SampleTriggerByPass__c or disableAll__c.
 *           Recursion: TriggerControl in SampleTriggerHandler.
 * GC-3225 - After insert: stamp Opportunity.HasSampleActivity__c on the related Opportunity.
 */
trigger SampleTrigger on Sample__c (before insert, before update, after insert) {
    Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();

    if (settings != null && (settings.SampleTriggerByPass__c || settings.disableAll__c)) {
        return;
    }

    new SampleTriggerHandler().run();
}