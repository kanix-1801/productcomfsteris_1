/**
 * @author Divya Sree
 * @date 15-10-2026
 * @description #GC-3563 Shared entry point for CSC visit saves and attendee changes.
 *              Other classes call handleAfterSave or syncAttendees. This service
 *              delegates to CscVisitConfirmationService.
 */
public inherited sharing class CscVisitAttendeeService {
    /**
     * @description Applies confirmation, cancellation, and VR/AR
     *              behavior after a CSC visit is saved.
     * @param visits Saved CSC visit records.
     * @param oldVisits Prior CSC visit records. Null on insert.
     */
    public static void handleAfterSave(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        CscVisitConfirmationService.handleAfterSave(visits, oldVisits);
    }

    /**
     * @description Refreshes calendar invitees after STERIS attendees change
     *              on a confirmed visit. Does not send the confirmation email.
     * @param visitIds CSC visit Ids from the attendee records.
     */
    public static void syncAttendees(Set<Id> visitIds) {
        CscVisitConfirmationService.syncAttendees(visitIds);
    }
    
    private static final String ATTENDEE_TYPE_STERIS = 'STERIS';
    
    public static void addDefaultRequestors(List<CSC_Visit_Request__c> visits) {
        Map<Id, Id> requestorByVisit = new Map<Id, Id>();
        for (CSC_Visit_Request__c visit : visits) {
            if (visit.Id != null && visit.VisitRequestor__c != null) {
                requestorByVisit.put(visit.Id, visit.VisitRequestor__c);
            }
        }
        if (requestorByVisit.isEmpty()) {
            return;
        }
        
        Set<Id> visitIds = requestorByVisit.keySet();
        Set<Id> requestorIds = new Set<Id>(requestorByVisit.values());
        Set<String> existingKeys = new Set<String>();
        for (CSCVisitAttendee__c attendee : [
            SELECT CSCVisit__c, STERISAttendee__c
            FROM CSCVisitAttendee__c
            WHERE CSCVisit__c IN :visitIds
            AND STERISAttendee__c IN :requestorIds
        ]) {
            existingKeys.add(key(attendee.CSCVisit__c, attendee.STERISAttendee__c));
        }
        
        List<CSCVisitAttendee__c> attendeesToInsert = new List<CSCVisitAttendee__c>();
        for (Id visitId : requestorByVisit.keySet()) {
            Id requestorId = requestorByVisit.get(visitId);
            if (!existingKeys.contains(key(visitId, requestorId))) {
                attendeesToInsert.add(new CSCVisitAttendee__c(
                    CSCVisit__c = visitId,
                    STERISAttendee__c = requestorId,
                    AttendeeType__c = ATTENDEE_TYPE_STERIS
                ));
            }
        }
        
        if (!attendeesToInsert.isEmpty()) {
            insert attendeesToInsert;
        }
    }
    
    private static String key(Id visitId, Id userId) {
        return String.valueOf(visitId) + '|' + String.valueOf(userId);
    }
}