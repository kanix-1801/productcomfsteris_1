/**
 * @author Divya Sree
 * @date 14-10-2026
 * @description #GC-3563 Handles CSC visit confirmation, cancellation,
 *              and VR/AR notification after save.
 *              #GC-3579 Keeps the Opportunity CSC visit count current.
 */
public with sharing class CSCVisitRequestTriggerHandler extends TriggerHandler {
    /**
     * @description #GC-3435 and #GC-3518 Delegates approval and submit checks
     *              to CscVisitRequestService.
     */
    @TestVisible
    protected override void beforeUpdate() {
        List<CSC_Visit_Request__c> visits = (List<CSC_Visit_Request__c>) Trigger.new;
        Map<Id, CSC_Visit_Request__c> oldVisits = (Map<Id, CSC_Visit_Request__c>) Trigger.oldMap;
        CscVisitRequestService.requireConfirmedDateForApproval(visits, oldVisits);
        CscVisitRequestService.requireFieldsOnSubmit(visits, oldVisits);
    }

    @TestVisible
    protected override void afterInsert() {
        CscVisitAttendeeService.handleAfterSave(
            (List<CSC_Visit_Request__c>) Trigger.new,
            null
        );
        CscVisitAttendeeService.addDefaultRequestors(
            (List<CSC_Visit_Request__c>) Trigger.new
        );
        CscVisitRequestService.refreshOpportunityVisitCounts(
            (List<CSC_Visit_Request__c>) Trigger.new,
            null
        );
    }

    /**
     * @description Runs the visit acceptance criteria after update.
     */
    @TestVisible
    protected override void afterUpdate() {
        CscVisitAttendeeService.handleAfterSave(
            (List<CSC_Visit_Request__c>) Trigger.new,
            (Map<Id, CSC_Visit_Request__c>) Trigger.oldMap
        );
        CscVisitRequestService.refreshOpportunityVisitCounts(
            (List<CSC_Visit_Request__c>) Trigger.new,
            (Map<Id, CSC_Visit_Request__c>) Trigger.oldMap
        );
    }

    /**
     * @description #GC-3579 Recounts the Opportunity after a CSC visit is deleted.
     */
    @TestVisible
    protected override void afterDelete() {
        CscVisitRequestService.refreshOpportunityVisitCounts(
            (List<CSC_Visit_Request__c>) Trigger.old,
            null
        );
    }

    /**
     * @description #GC-3579 Recounts the Opportunity after a CSC visit is restored.
     */
    @TestVisible
    protected override void afterUndelete() {
        CscVisitRequestService.refreshOpportunityVisitCounts(
            (List<CSC_Visit_Request__c>) Trigger.new,
            null
        );
    }
}