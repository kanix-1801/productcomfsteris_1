/**
 * @author Divya Sree
 * @date 14-10-2026
 * @description #GC-3563 AC1 Keeps the confirmed visit calendar invite aligned
 *              with the STERIS attendee list.
 */
public with sharing class CSCVisitAttendeeTriggerHandler extends TriggerHandler {
    /**
     * @description Adds new STERIS attendees to the calendar event.
     */
    @TestVisible
    protected override void afterInsert() {
        CscVisitAttendeeService.syncAttendees(visitIds((List<CSCVisitAttendee__c>) Trigger.new));
    }

    /**
     * @description Updates the calendar event when a STERIS attendee changes.
     */
    @TestVisible
    protected override void afterUpdate() {
        CscVisitAttendeeService.syncAttendees(visitIds((List<CSCVisitAttendee__c>) Trigger.new));
    }

    /**
     * @description Removes a STERIS attendee from the calendar event.
     */
    @TestVisible
    protected override void afterDelete() {
        CscVisitAttendeeService.syncAttendees(visitIds((List<CSCVisitAttendee__c>) Trigger.old));
    }

    /**
     * @description Collects parent visit Ids from attendee rows.
     * @param attendees Attendee records from the trigger.
     * @return Set<Id> CSC visit Ids.
     */
    private static Set<Id> visitIds(List<CSCVisitAttendee__c> attendees) {
        Set<Id> visitIds = new Set<Id>();
        if (attendees == null) {
            return visitIds;
        }
        for (CSCVisitAttendee__c attendee : attendees) {
            if (attendee.CSCVisit__c != null) {
                visitIds.add(attendee.CSCVisit__c);
            }
        }
        return visitIds;
    }
}