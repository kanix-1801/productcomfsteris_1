/**
 * @author Abhishek Mishra
 * @date 14-10-2026
 * @description #GC-3435 Sales Rep cancel and CSC Admin postpone actions.
 *              #GC-3518 Sales Rep confirmation after admin approval.
 *              #GC-3579 CSC Administrator changes the visit to one available date.
 *              Closes a pending approval before the status change so the
 *              approval lock does not block the update.
 */
public with sharing class CscVisitStatusAction {
    private static final String PERMISSION_ADMIN = 'CSC_Visit_Administrator';

    /**
     * @description Cancels a visit the running user owns, or any visit when the user is a CSC Administrator.
     * @param recordId Id CSC Visit Request to cancel
     * @return void
     */
    @AuraEnabled
    public static void cancelVisit(Id recordId) {
        CSC_Visit_Request__c visit = loadVisit(recordId);
        Boolean isAdmin = FeatureManagement.checkPermission(PERMISSION_ADMIN);
        if (visit.OwnerId != UserInfo.getUserId() && !isAdmin) {
            throw handledException(System.Label.CSC_Cancel_Owner_Only);
        }
        assertStatus(
            visit,
            new Set<String>{
                CscVisitRequestSelector.STATUS_DRAFT,
                CscVisitRequestSelector.STATUS_REQUESTED,
                CscVisitRequestSelector.STATUS_APPROVED,
                CscVisitRequestSelector.STATUS_CONFIRMED
            },
            System.Label.CSC_Cancel_Status_Invalid
        );
        if (visit.OwnerId == UserInfo.getUserId()) {
            closePendingApproval(recordId, 'Removed', 'Cancelled by the requester.');
        } else {
            closePendingApproval(recordId, 'Reject', 'Cancelled by CSC Administrator.');
        }
        visit.Status__c = CscVisitRequestSelector.STATUS_CANCELLED;
        saveVisit(visit);
    }

    /**
     * @description #GC-3518 Confirms an approved visit after the administrator
     *              has selected the Confirmed Date.
     * @param recordId Id CSC Visit Request to confirm
     * @return void
     */
    @AuraEnabled
    public static void confirmVisit(Id recordId) {
        CSC_Visit_Request__c visit = loadVisit(recordId);
        Boolean isAdmin = FeatureManagement.checkPermission(PERMISSION_ADMIN);
        if (visit.OwnerId != UserInfo.getUserId() && !isAdmin) {
            throw handledException(System.Label.CSC_Confirm_Owner_Only);
        }
        assertStatus(
            visit,
            new Set<String>{ CscVisitRequestSelector.STATUS_APPROVED },
            System.Label.CSC_Confirm_Status_Approved_Only
        );
        if (visit.Confirmed_Date__c == null) {
            throw handledException(System.Label.CSC_Confirm_Date_Required_Before_Confirm);
        }
        visit.Status__c = CscVisitRequestSelector.STATUS_CONFIRMED;
        saveVisit(visit);
    }

    /**
     * @description Postpones a requested, approved, or confirmed visit. A pending approval
     *              is rejected first. Only Confirmed Date is cleared, so that reservation is released.
     *              Primary and Backup stay on the record. The after-save path emails the
     *              requester, account team, visit team, and attendees, and removes the calendar invite.
     * @param recordId Id CSC Visit Request to postpone
     * @return void
     */
    @AuraEnabled
    public static void postponeVisit(Id recordId) {
        if (!FeatureManagement.checkPermission(PERMISSION_ADMIN)) {
            throw handledException(System.Label.CSC_Postpone_Admin_Only);
        }
        CSC_Visit_Request__c visit = loadVisit(recordId);
        assertStatus(
            visit,
            new Set<String>{
                CscVisitRequestSelector.STATUS_REQUESTED,
                CscVisitRequestSelector.STATUS_APPROVED,
                CscVisitRequestSelector.STATUS_CONFIRMED
            },
            System.Label.CSC_Postpone_Status_Invalid
        );
        closePendingApproval(recordId, 'Reject', 'Postponed by CSC Administrator.');
        visit.Status__c = CscVisitRequestSelector.STATUS_POSTPONED;
        visit.Confirmed_Date__c = null;
        saveVisit(visit);
    }

    /**
     * @description #GC-3579 Confirms the first date while the visit is Requested.
     *              Approves the pending approval, writes Confirmed Date, and sets Status to Approved.
     * @param recordId Id CSC Visit Request to confirm
     * @param confirmedDate Date the administrator selected on the calendar
     * @return void
     */
    @AuraEnabled
    public static void confirmVisitDate(Id recordId, Date confirmedDate) {
        if (!FeatureManagement.checkPermission(PERMISSION_ADMIN)) {
            throw handledException(System.Label.CSC_Confirm_Date_Admin_Only);
        }
        if (confirmedDate == null) {
            throw handledException(System.Label.CSC_Select_Available_Date);
        }
        CSC_Visit_Request__c visit = loadVisit(recordId);
        assertStatus(
            visit,
            new Set<String>{ CscVisitRequestSelector.STATUS_REQUESTED },
            System.Label.CSC_Confirm_Date_Wrong_Status
        );
        if (CscVisitRequestService.isWeekend(confirmedDate) || confirmedDate < Date.today()) {
            throw handledException(System.Label.CSC_Select_Available_Weekday);
        }
        assertDateAvailable(visit, confirmedDate);
        visit.Confirmed_Date__c = confirmedDate;
        saveVisit(visit);
        closePendingApproval(recordId, 'Approve', 'Date confirmed by CSC Administrator.');
        visit.Status__c = CscVisitRequestSelector.STATUS_APPROVED;
        saveVisit(visit);
    }

    /**
     * @description #GC-3579 Replaces an existing Confirmed Date and sets Status to Approved.
     *              The approval is already complete, so this save does not approve, reject, or submit one.
     * @param recordId Id CSC Visit Request to reschedule
     * @param confirmedDate Date the administrator selected on the calendar
     * @return void
     */
    @AuraEnabled
    public static void changeVisitDate(Id recordId, Date confirmedDate) {
        if (!FeatureManagement.checkPermission(PERMISSION_ADMIN)) {
            throw handledException(System.Label.CSC_Change_Date_Admin_Only);
        }
        if (confirmedDate == null) {
            throw handledException(System.Label.CSC_Select_Available_Date);
        }
        CSC_Visit_Request__c visit = loadVisit(recordId);
        if (visit.Confirmed_Date__c == null) {
            throw handledException(System.Label.CSC_Change_Date_Use_Confirm);
        }
        assertStatus(
            visit,
            new Set<String>{
                CscVisitRequestSelector.STATUS_APPROVED,
                CscVisitRequestSelector.STATUS_CONFIRMED
            },
            System.Label.CSC_Change_Date_Needs_Date
        );
        if (CscVisitRequestService.isWeekend(confirmedDate) || confirmedDate < Date.today()) {
            throw handledException(System.Label.CSC_Select_Available_Weekday);
        }
        assertDateAvailable(visit, confirmedDate);
        visit.Confirmed_Date__c = confirmedDate;
        visit.Status__c = CscVisitRequestSelector.STATUS_APPROVED;
        saveVisit(visit);
    }

    /**
     * @description Loads the visit status and owner.
     * @param recordId Id CSC Visit Request
     * @return CSC_Visit_Request__c visit row
     */
    private static CSC_Visit_Request__c loadVisit(Id recordId) {
        if (recordId == null) {
            throw handledException(System.Label.CSC_Visit_Record_Required);
        }
        List<CSC_Visit_Request__c> rows = [
            SELECT Id, Status__c, OwnerId, VisitType__c, VisitLocation__c,
                Confirmed_Date__c, Primary_Requested_Date__c, Backup_Requested_Date__c
            FROM CSC_Visit_Request__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw handledException(System.Label.CSC_Visit_Not_Found);
        }
        return rows[0];
    }

    /**
     * @description Stops the action when the visit is not in an allowed status.
     * @param visit CSC_Visit_Request__c visit being changed
     * @param allowedStatuses Set<String> statuses that accept this action
     * @param message String error shown to the user
     * @return void
     */
    private static void assertStatus(
        CSC_Visit_Request__c visit,
        Set<String> allowedStatuses,
        String message
    ) {
        if (!allowedStatuses.contains(visit.Status__c)) {
            throw handledException(message);
        }
    }

    /**
     * @description Approves, rejects, or recalls the pending work item when one exists.
     * @param recordId Id visit in the approval process
     * @param actionName String Removed or Reject
     * @param comments String comment stored on the approval history
     * @return void
     */
    private static void closePendingApproval(
        Id recordId,
        String actionName,
        String comments
    ) {
        List<ProcessInstanceWorkitem> items = [
            SELECT Id
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :recordId
              AND ProcessInstance.Status = 'Pending'
        ];
        if (items.isEmpty()) {
            return;
        }

        List<Approval.ProcessWorkitemRequest> requests = new List<Approval.ProcessWorkitemRequest>();
        for (ProcessInstanceWorkitem item : items) {
            Approval.ProcessWorkitemRequest request = new Approval.ProcessWorkitemRequest();
            request.setWorkitemId(item.Id);
            request.setAction(actionName);
            request.setComments(comments);
            requests.add(request);
        }

        List<Approval.ProcessResult> results = Approval.process(requests, false);
        for (Approval.ProcessResult result : results) {
            if (!result.isSuccess()) {
                String detail = result.getErrors().isEmpty()
                    ? System.Label.CSC_Approval_Not_Closed
                    : result.getErrors()[0].getMessage();
                throw handledException(detail);
            }
        }
    }

    /**
     * @description Stops the save when another visit already holds the selected date.
     * @param visit CSC_Visit_Request__c visit being rescheduled
     * @param confirmedDate Date selected by the administrator
     * @return void
     */
    private static void assertDateAvailable(CSC_Visit_Request__c visit, Date confirmedDate) {
        List<CscVisitRequestService.UnavailableDate> occupied = CscVisitRequestService.getUnavailableDates(
            visit.VisitType__c,
            visit.VisitLocation__c,
            confirmedDate,
            confirmedDate,
            visit.Id
        );
        if (!occupied.isEmpty()) {
            throw handledException(System.Label.CSC_Date_No_Longer_Available);
        }
    }

    /**
     * @description Saves the status change and returns the first validation message.
     * @param visit CSC_Visit_Request__c visit with the new status
     * @return void
     */
    private static void saveVisit(CSC_Visit_Request__c visit) {
        try {
            update visit;
        } catch (DmlException ex) {
            throw handledException(ex.getDmlMessage(0));
        }
    }

    /**
     * @description Builds an Aura exception whose message survives the Lightning boundary.
     * @param message String text shown in the toast
     * @return AuraHandledException exception to throw
     */
    private static AuraHandledException handledException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}