/**
 * @author Suraj Thapliyal
 * @date 2026/08/17
 *
 * @group Sample
 *
 * @description
 * GC-3226 - Trigger handler for Sample__c.
 *           - Before insert: Owner or Opportunity Team Member required to create.
 *           - Before update: re-arm Follow-up Notified when Follow-up Date/Reminder changes.
 * GC-3225 - After insert: stamp Opportunity.HasSampleActivity__c on related Opportunity.
 */
public with sharing class SampleTriggerHandler extends TriggerHandler {

    /**
     * @description GC-3226 - Before insert: only Opportunity Owner or Team Member may create.
     */
    @TestVisible
    protected override void beforeInsert() {
        if (TriggerControl.enterBeforeInsert(Sample__c.SObjectType)) {
            SampleService.enforceCreateAccess((List<Sample__c>) Trigger.new);
        }
    }

    /**
     * @description GC-3226 - Before update: re-arm notifications when Follow-up Date changes.
     */
    @TestVisible
    protected override void beforeUpdate() {
        if (TriggerControl.enterBeforeUpdate(Sample__c.SObjectType)) {
            SampleService.resetFollowUpNotifiedOnChange(
                (List<Sample__c>) Trigger.new,
                (Map<Id, Sample__c>) Trigger.oldMap
            );
        }
    }

    /**
     * @description GC-3225 - After insert: mark related Opportunity as having Sample activity.
     */
    @TestVisible
    protected override void afterInsert() {
        if (TriggerControl.enterAfterInsert(Sample__c.SObjectType)) {
            SampleService.markRelatedOpportunitiesHasSampleActivity(
                (List<Sample__c>) Trigger.new
            );
        }
    }
}