/**
 * @author Abhishek Mishra
 * @date 27-08-2026
 * @description #GC-3302 Builds location-aware CSC availability for the calendar.
 *              #GC-3435 and #GC-3518 Visit approval, submit checks, and Team Member notice.
 *              #GC-3579 Keeps the Opportunity CSC visit count for the Capital page tab.
 */
public without sharing class CscVisitRequestService {
    private static final String CLASS_NAME = 'CscVisitRequestService';
    private static Boolean serviceLogPending = false;
    private static Set<String> loggedMissingRecordTypes = new Set<String>();

    public class UnavailableDate {
        @AuraEnabled public String dateValue;
        @AuraEnabled public String reason;
    }

    /**
     * @description Sunday = 0 through Saturday = 6. 1900-01-07 is a Sunday.
     * @param value Date date to evaluate
     * @return Boolean true when the date is Saturday or Sunday
     */
    public static Boolean isWeekend(Date value) {
        if (value == null) {
            return false;
        }
        Date sunday = Date.newInstance(1900, 1, 7);
        Integer dayNumber = Math.mod(sunday.daysBetween(value), 7);
        return dayNumber == 0 || dayNumber == 6;
    }

    /**
     * @description Pending and confirmed dates in one visit location calendar window.
     * @param visitLocation String visit location used to scope availability
     * @param startDate Date first date in the requested range
     * @param endDate Date last date in the requested range
     * @return List<UnavailableDate> unique occupied dates and their reason codes
     */
    public static List<UnavailableDate> getUnavailableDates(
        String visitLocation,
        Date startDate,
        Date endDate
    ) {
        return getUnavailableDates(null, visitLocation, startDate, endDate);
    }

    /**
     * @description #GC-3518 Pending and unavailable dates for one calendar.
     *              A blank or CSC request type uses the location calendar.
     *              ORC, IMS, and OSV each use a separate calendar.
     * @param requestType String Visit Type API value
     * @param visitLocation String visit location used for a CSC calendar
     * @param startDate Date first date in the requested range
     * @param endDate Date last date in the requested range
     * @return List<UnavailableDate> unique occupied dates and their reason codes
     */
    public static List<UnavailableDate> getUnavailableDates(
        String requestType,
        String visitLocation,
        Date startDate,
        Date endDate
    ) {
        return getUnavailableDates(requestType, visitLocation, startDate, endDate, null);
    }

    /**
     * @description #GC-3579 Occupancy for one calendar. The visit being changed is excluded
     *              so the administrator can keep or replace its current date.
     *              An Approved visit holds Confirmed Date until the 10-day hold expires.
     * @param requestType String Visit Type API value
     * @param visitLocation String visit location used for a CSC calendar
     * @param startDate Date first date in the requested range
     * @param endDate Date last date in the requested range
     * @param excludeVisitId Id visit to leave off this calendar
     * @return List<UnavailableDate> unique occupied dates and their reason codes
     */
    public static List<UnavailableDate> getUnavailableDates(
        String requestType,
        String visitLocation,
        Date startDate,
        Date endDate,
        Id excludeVisitId
    ) {
        if (startDate == null || endDate == null || endDate < startDate) {
            return new List<UnavailableDate>();
        }
        Boolean nonCsc = CscVisitRequestSelector.isNonCscRequest(requestType);
        if (!nonCsc && String.isBlank(visitLocation)) {
            return new List<UnavailableDate>();
        }

        Map<Date, String> reasonByDate = new Map<Date, String>();
        List<CSC_Visit_Request__c> rows = nonCsc
            ? CscVisitRequestSelector.selectAvailabilityForRequestType(requestType, startDate, endDate)
            : CscVisitRequestSelector.selectAvailabilityInRange(visitLocation, startDate, endDate);
        for (CSC_Visit_Request__c row : rows) {
            if (excludeVisitId != null && row.Id == excludeVisitId) {
                continue;
            }
            if (row.RecordType != null
                && row.RecordType.DeveloperName == CscVisitRequestSelector.RECORD_TYPE_BLOCK
            ) {
                putUnavailable(
                    reasonByDate,
                    row.Blocked_Date__c,
                    CscVisitRequestSelector.UNAVAILABLE_BLOCKED
                );
            } else if (row.Status__c == CscVisitRequestSelector.STATUS_CONFIRMED) {
                putUnavailable(reasonByDate, row.Confirmed_Date__c, CscVisitRequestSelector.UNAVAILABLE_CONFIRMED);
            } else if (
                row.Status__c == CscVisitRequestSelector.STATUS_REQUESTED
                || (
                    row.Status__c == CscVisitRequestSelector.STATUS_APPROVED
                    && (
                        row.Hold_Expiry_Date__c == null
                        || row.Hold_Expiry_Date__c > System.now()
                    )
                )
            ) {
                putPending(reasonByDate, row.Primary_Requested_Date__c);
                putPending(reasonByDate, row.Backup_Requested_Date__c);
                if (row.Status__c == CscVisitRequestSelector.STATUS_APPROVED) {
                    putPending(reasonByDate, row.Confirmed_Date__c);
                }
            }
        }

        List<UnavailableDate> results = new List<UnavailableDate>();
        for (Date dateValue : reasonByDate.keySet()) {
            UnavailableDate item = new UnavailableDate();
            item.dateValue = String.valueOf(dateValue);
            item.reason = reasonByDate.get(dateValue);
            results.add(item);
        }
        return results;
    }

    /**
     * @description Adds a pending date without replacing a stronger unavailable reason.
     * @param reasonByDate Map<Date, String> accumulated reason by date
     * @param dateValue Date pending date to add
     * @return void
     */
    private static void putPending(Map<Date, String> reasonByDate, Date dateValue) {
        if (dateValue != null && !reasonByDate.containsKey(dateValue)) {
            reasonByDate.put(dateValue, CscVisitRequestSelector.UNAVAILABLE_PENDING);
        }
    }

    /**
     * @description Adds an unavailable date and replaces any pending reason.
     * @param reasonByDate Map<Date, String> accumulated reason by date
     * @param dateValue Date unavailable date to add
     * @param reason String unavailability reason code
     * @return void
     */
    private static void putUnavailable(
        Map<Date, String> reasonByDate,
        Date dateValue,
        String reason
    ) {
        if (dateValue != null) {
            reasonByDate.put(dateValue, reason);
        }
    }

    /**
     * @description #GC-3435 The standard Approve action sets Status to Approved.
     *              That field update runs this trigger, so approval stops when
     *              Confirmed Date is still blank.
     * @param visits Visit records being saved.
     * @param oldVisits Prior visit records.
     */
    public static void requireConfirmedDateForApproval(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        if (visits == null || visits.isEmpty()) {
            return;
        }
        try {
            Id blockTypeId = recordTypeId(CscVisitRequestSelector.RECORD_TYPE_BLOCK, true);
            for (CSC_Visit_Request__c visit : visits) {
                if (visit == null || isBlockDate(visit, blockTypeId)) {
                    continue;
                }
                CSC_Visit_Request__c priorVisit = oldVisits == null ? null : oldVisits.get(visit.Id);
                if (priorVisit == null
                    || visit.Status__c != CscVisitRequestSelector.STATUS_APPROVED
                    || priorVisit.Status__c == CscVisitRequestSelector.STATUS_APPROVED
                    || visit.Confirmed_Date__c != null
                ) {
                    continue;
                }
                visit.Confirmed_Date__c.addError(Label.CSC_Confirmed_Date_Required);
            }
        } catch (Exception approvalError) {
            logError(CLASS_NAME + '.requireConfirmedDateForApproval', approvalError);
            throw approvalError;
        } finally {
            saveServiceLog();
        }
    }

    /**
     * @description #GC-3518 Shows the CSC_002 and CSC_012 messages when Submit
     *              changes Status to Requested. Approval field updates skip
     *              those validation rules.
     * @param visits Visit records being saved.
     * @param oldVisits Prior visit records.
     */
    public static void requireFieldsOnSubmit(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        if (visits == null || visits.isEmpty() || isValidationBypassed()) {
            return;
        }
        try {
            Automation_Setting_Validation_Rule__c validationSetting =
                Automation_Setting_Validation_Rule__c.getInstance();
            Boolean datesRuleEnabled = validationSetting == null
                || validationSetting.CSC_002_DatesRequiredOnSubmit__c != true;
            Id blockTypeId = recordTypeId(CscVisitRequestSelector.RECORD_TYPE_BLOCK, true);
            Set<Id> visitTypeIds = visitRecordTypeIds();

            for (CSC_Visit_Request__c visit : visits) {
                if (visit == null || isBlockDate(visit, blockTypeId)) {
                    continue;
                }
                CSC_Visit_Request__c oldVisit = oldVisits == null ? null : oldVisits.get(visit.Id);
                if (oldVisit == null
                    || visit.Status__c != CscVisitRequestSelector.STATUS_REQUESTED
                    || oldVisit.Status__c == CscVisitRequestSelector.STATUS_REQUESTED
                ) {
                    continue;
                }
                if (datesRuleEnabled && missingSubmitFields(visit)) {
                    visit.addError(Label.CSC_Submit_Fields_Required);
                }
                if (visitTypeIds.contains(visit.RecordTypeId)
                    && includesOther(visit.Visit_Purpose__c)
                    && String.isBlank(visit.VisitPurposeOther__c)
                ) {
                    visit.addError(Label.CSC_Visit_Purpose_Other_Required);
                }
            }
        } catch (Exception submitError) {
            logError(CLASS_NAME + '.requireFieldsOnSubmit', submitError);
            throw submitError;
        } finally {
            saveServiceLog();
        }
    }

    private static Set<Id> visitRecordTypeIds() {
        Set<Id> recordTypeIds = new Set<Id>();
        Id visitTypeId = recordTypeId(CscVisitRequestSelector.RECORD_TYPE_VISIT, true);
        Id legacyTypeId = recordTypeId(CscVisitRequestSelector.RECORD_TYPE_VISIT_LEGACY, false);
        if (visitTypeId != null) {
            recordTypeIds.add(visitTypeId);
        }
        if (legacyTypeId != null) {
            recordTypeIds.add(legacyTypeId);
        }
        return recordTypeIds;
    }

    private static Id recordTypeId(String developerName, Boolean logWhenMissing) {
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.CSC_Visit_Request__c
            .getRecordTypeInfosByDeveloperName()
            .get(developerName);
        if (recordTypeInfo != null) {
            return recordTypeInfo.getRecordTypeId();
        }
        if (logWhenMissing && loggedMissingRecordTypes.add(developerName)) {
            logError(CLASS_NAME + '.recordTypeId: record type not found ' + developerName);
        }
        return null;
    }

    private static Boolean isBlockDate(CSC_Visit_Request__c visit, Id blockTypeId) {
        return blockTypeId != null && visit.RecordTypeId == blockTypeId;
    }

    private static void logError(String message) {
        Logger.error(message);
        serviceLogPending = true;
    }

    private static void logError(String message, Exception error) {
        Logger.error(message, error);
        serviceLogPending = true;
    }

    private static void saveServiceLog() {
        if (!serviceLogPending) {
            return;
        }
        Logger.saveLog();
        serviceLogPending = false;
    }

    private static Boolean isValidationBypassed() {
        Automation_Setting_Global__c globalSetting = Automation_Setting_Global__c.getInstance();
        if (globalSetting != null && globalSetting.disableAll__c) {
            return true;
        }
        Automation_Setting_Validation_Rule__c validationSetting =
            Automation_Setting_Validation_Rule__c.getInstance();
        return validationSetting != null && validationSetting.disableAll__c;
    }

    private static Boolean missingSubmitFields(CSC_Visit_Request__c visit) {
        return visit.Primary_Requested_Date__c == null
            || visit.Backup_Requested_Date__c == null
            || String.isBlank(visit.Visit_Purpose__c)
            || String.isBlank(visit.PrimaryObjective__c);
    }

    private static Boolean includesOther(String visitPurpose) {
        if (String.isBlank(visitPurpose)) {
            return false;
        }
        for (String value : visitPurpose.split(';')) {
            if (value == 'Other') {
                return true;
            }
        }
        return false;
    }

    /**
     * @description #GC-3579 Keeps the Opportunity CSC visit count current for the Capital page tab.
     * @param visits Visit records from this trigger context.
     * @param oldVisits Prior visit records.
     */
    public static void refreshOpportunityVisitCounts(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        if (visits == null || visits.isEmpty()) {
            return;
        }
        try {
            Set<Id> opportunityIds = new Set<Id>();
            for (CSC_Visit_Request__c visit : visits) {
                if (visit == null) {
                    continue;
                }
                CSC_Visit_Request__c oldVisit = oldVisits == null ? null : oldVisits.get(visit.Id);
                if (oldVisit != null && oldVisit.Opportunity__c == visit.Opportunity__c) {
                    continue;
                }
                if (visit.Opportunity__c != null) {
                    opportunityIds.add(visit.Opportunity__c);
                }
                if (oldVisit != null && oldVisit.Opportunity__c != null) {
                    opportunityIds.add(oldVisit.Opportunity__c);
                }
            }
            if (opportunityIds.isEmpty()) {
                return;
            }

            Map<Id, Decimal> countByOpportunityId = new Map<Id, Decimal>();
            for (Id opportunityId : opportunityIds) {
                countByOpportunityId.put(opportunityId, 0);
            }
            for (AggregateResult result : [
                SELECT Opportunity__c opportunityId, COUNT(Id) visitCount
                FROM CSC_Visit_Request__c
                WHERE Opportunity__c IN :opportunityIds
                GROUP BY Opportunity__c
            ]) {
                countByOpportunityId.put(
                    (Id) result.get('opportunityId'),
                    Decimal.valueOf(Integer.valueOf(result.get('visitCount')))
                );
            }

            List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
            for (Opportunity opportunityRecord : [
                SELECT Id, CSCVisitRequestCount__c
                FROM Opportunity
                WHERE Id IN :opportunityIds
            ]) {
                Decimal visitCount = countByOpportunityId.get(opportunityRecord.Id);
                if (opportunityRecord.CSCVisitRequestCount__c != visitCount) {
                    opportunitiesToUpdate.add(new Opportunity(
                        Id = opportunityRecord.Id,
                        CSCVisitRequestCount__c = visitCount
                    ));
                }
            }
            if (!opportunitiesToUpdate.isEmpty()) {
                update opportunitiesToUpdate;
            }
        } catch (Exception countError) {
            logError(CLASS_NAME + '.refreshOpportunityVisitCounts', countError);
            throw countError;
        } finally {
            saveServiceLog();
        }
    }
}