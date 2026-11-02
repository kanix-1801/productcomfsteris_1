/**
 * @author Abhishek Mishra
 * @date 27-08-2026
 * @description #GC-3302 UI-facing Apex for the CSC availability calendar LWC.
 */
public with sharing class CscAvailabilityController {
    /**
     * @description #GC-3518 Returns pending and unavailable dates for one calendar.
     *              Pass ORC, IMS, or OSV to load that request-type calendar.
     *              A blank or CSC request type loads the location calendar.
     * @param requestType String Visit Type API value from the create flow
     * @param visitLocation String visit location selected for a CSC Visit
     * @param startDate Date first date shown on the calendar
     * @param endDate Date last date shown on the calendar
     * @return List<CscVisitRequestService.UnavailableDate> dates to disable in the LWC
     */
    @AuraEnabled
    public static List<CscVisitRequestService.UnavailableDate> getUnavailableDates(
        String requestType,
        String visitLocation,
        Date startDate,
        Date endDate
    ) {
        return CscVisitRequestService.getUnavailableDates(
            requestType,
            visitLocation,
            startDate,
            endDate
        );
    }

    /**
     * @description #GC-3579 Same calendar occupancy, ignoring the visit being rescheduled
     *              so its own date stays selectable.
     * @param requestType String Visit Type API value
     * @param visitLocation String visit location used for a CSC calendar
     * @param startDate Date first date shown on the calendar
     * @param endDate Date last date shown on the calendar
     * @param excludeVisitId Id visit whose dates should not block the calendar
     * @return List<CscVisitRequestService.UnavailableDate> dates to disable in the LWC
     */
    @AuraEnabled
    public static List<CscVisitRequestService.UnavailableDate> getUnavailableDatesForVisit(
        String requestType,
        String visitLocation,
        Date startDate,
        Date endDate,
        Id excludeVisitId
    ) {
        return CscVisitRequestService.getUnavailableDates(
            requestType,
            visitLocation,
            startDate,
            endDate,
            excludeVisitId
        );
    }
}