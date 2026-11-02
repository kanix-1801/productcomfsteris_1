/**
 * @author Abhishek Mishra
 * @date 27-08-2026
 * @description #GC-3302 Queries CSC availability by visit location.
 *              Without sharing so every Sales Rep sees the same calendar.
 */
public without sharing class CscVisitRequestSelector {
    public static final String STATUS_CONFIRMED = 'Confirmed';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_REQUESTED = 'Requested';
    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_POSTPONED = 'Postponed';
    public static final String STATUS_CANCELLED = 'Cancelled';
    public static final String UNAVAILABLE_CONFIRMED = 'Confirmed';
    public static final String UNAVAILABLE_PENDING = 'Pending';
    public static final String UNAVAILABLE_BLOCKED = 'Blocked';
    public static final String RECORD_TYPE_VISIT = 'CSCVisitRequest';
    public static final String RECORD_TYPE_VISIT_LEGACY = 'CSC_Visit_Request';
    public static final String RECORD_TYPE_BLOCK = 'Block_Date';
    public static final String REQUEST_CSC = 'CSC';
    public static final String REQUEST_ORC = 'ORC';
    public static final String REQUEST_IMS = 'IMS';
    public static final String REQUEST_OSV = 'OSV';

    /**
     * @description Requested and confirmed dates in one visit location and date window.
     * @param visitLocation String visit location used to scope availability
     * @param startDate Date first date in the requested range
     * @param endDate Date last date in the requested range
     * @return List<CSC_Visit_Request__c> records occupying the requested range
     */
    public static List<CSC_Visit_Request__c> selectAvailabilityInRange(
        String visitLocation,
        Date startDate,
        Date endDate
    ) {
        Datetime currentTime = System.now();
        Set<String> visitRecordTypes = visitRecordTypes();
        return [
            SELECT Id, Status__c, VisitLocation__c, VisitType__c, RecordType.DeveloperName,
                Primary_Requested_Date__c, Backup_Requested_Date__c,
                Confirmed_Date__c, Blocked_Date__c, Hold_Expiry_Date__c
            FROM CSC_Visit_Request__c
            WHERE VisitLocation__c = :visitLocation
              AND (
                  (
                      RecordType.DeveloperName = :RECORD_TYPE_BLOCK
                      AND Blocked_Date__c >= :startDate
                      AND Blocked_Date__c <= :endDate
                  )
                  OR (
                      (
                          RecordTypeId = NULL
                          OR RecordType.DeveloperName IN :visitRecordTypes
                      )
                      AND (VisitType__c = :REQUEST_CSC OR VisitType__c = NULL)
                      AND Status__c = :STATUS_CONFIRMED
                      AND Confirmed_Date__c >= :startDate
                      AND Confirmed_Date__c <= :endDate
                  )
                  OR (
                      (
                          RecordTypeId = NULL
                          OR RecordType.DeveloperName IN :visitRecordTypes
                      )
                      AND (VisitType__c = :REQUEST_CSC OR VisitType__c = NULL)
                      AND (
                          Status__c = :STATUS_REQUESTED
                          OR (
                              Status__c = :STATUS_APPROVED
                              AND (
                                  Hold_Expiry_Date__c = NULL
                                  OR Hold_Expiry_Date__c > :currentTime
                              )
                          )
                      )
                      AND (
                          (Primary_Requested_Date__c >= :startDate
                              AND Primary_Requested_Date__c <= :endDate)
                          OR (Backup_Requested_Date__c >= :startDate
                              AND Backup_Requested_Date__c <= :endDate)
                          OR (Confirmed_Date__c >= :startDate
                              AND Confirmed_Date__c <= :endDate)
                      )
                  )
              )
        ];
    }

    /**
     * @description #GC-3518 Occupancy for one non-CSC request type.
     *              ORC, IMS, and OSV do not share dates with each other or with a CSC location.
     * @param requestType String ORC, IMS, or OSV
     * @param startDate Date first date in the requested range
     * @param endDate Date last date in the requested range
     * @return List<CSC_Visit_Request__c> records occupying that request-type calendar
     */
    public static List<CSC_Visit_Request__c> selectAvailabilityForRequestType(
        String requestType,
        Date startDate,
        Date endDate
    ) {
        Datetime currentTime = System.now();
        Set<String> visitRecordTypes = visitRecordTypes();
        return [
            SELECT Id, Status__c, VisitLocation__c, VisitType__c, RecordType.DeveloperName,
                Primary_Requested_Date__c, Backup_Requested_Date__c,
                Confirmed_Date__c, Blocked_Date__c, Hold_Expiry_Date__c
            FROM CSC_Visit_Request__c
            WHERE VisitType__c = :requestType
              AND (
                  RecordTypeId = NULL
                  OR RecordType.DeveloperName IN :visitRecordTypes
              )
              AND (
                  (
                      Status__c = :STATUS_CONFIRMED
                      AND Confirmed_Date__c >= :startDate
                      AND Confirmed_Date__c <= :endDate
                  )
                  OR (
                      (
                          Status__c = :STATUS_REQUESTED
                          OR (
                              Status__c = :STATUS_APPROVED
                              AND (
                                  Hold_Expiry_Date__c = NULL
                                  OR Hold_Expiry_Date__c > :currentTime
                              )
                          )
                      )
                      AND (
                          (Primary_Requested_Date__c >= :startDate
                              AND Primary_Requested_Date__c <= :endDate)
                          OR (Backup_Requested_Date__c >= :startDate
                              AND Backup_Requested_Date__c <= :endDate)
                          OR (Confirmed_Date__c >= :startDate
                              AND Confirmed_Date__c <= :endDate)
                      )
                  )
              )
        ];
    }

    /**
     * @description True when the request type has its own calendar.
     * @param requestType String stored Visit Type value
     * @return Boolean true for ORC, IMS, and OSV
     */
    public static Boolean isNonCscRequest(String requestType) {
        return requestType == REQUEST_ORC
            || requestType == REQUEST_IMS
            || requestType == REQUEST_OSV;
    }

    private static Set<String> visitRecordTypes() {
        return new Set<String>{ RECORD_TYPE_VISIT, RECORD_TYPE_VISIT_LEGACY };
    }
}