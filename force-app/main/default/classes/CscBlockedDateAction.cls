/**
 * @author Abhishek Mishra
 * @date 14-10-2026
 * @description #GC-3435 Saves CSC blocked dates from the admin calendar flow.
 *              One query, one insert, and one delete for the whole request.
 */
public with sharing class CscBlockedDateAction {
    private static final String PERMISSION_ADMIN = 'CSC_Visit_Administrator';

    public class Request {
        @InvocableVariable(required=true label='Visit Location')
        public String visitLocation;
        @InvocableVariable(required=true label='Blocked Reason')
        public String blockedReason;
        @InvocableVariable(label='Dates To Block')
        public String datesToBlock;
        @InvocableVariable(label='Dates To Unblock')
        public String datesToUnblock;
    }

    public class Result {
        @InvocableVariable(label='Blocked Count')
        public Integer blockedCount;
        @InvocableVariable(label='Removed Count')
        public Integer removedCount;
    }

    /**
     * @description Inserts new blocked days and deletes cleared days for each flow request.
     * @param requests List<Request> locations, reasons, and semicolon-separated dates
     * @return List<Result> counts saved for each request
     */
    @InvocableMethod(
        label='Save CSC Blocked Dates'
        description='Blocks or removes CSC calendar dates in one transaction.'
    )
    public static List<Result> save(List<Request> requests) {
        if (!FeatureManagement.checkPermission(PERMISSION_ADMIN)) {
            throw new BlockedDateException('Only a CSC Administrator can block a date.');
        }

        Id blockRecordTypeId = blockedDateRecordTypeId();
        Set<String> locations = new Set<String>();
        Set<Date> allDates = new Set<Date>();
        for (Request request : requests) {
            locations.add(request.visitLocation);
            allDates.addAll(parseDates(request.datesToBlock));
            allDates.addAll(parseDates(request.datesToUnblock));
        }

        Map<String, CSC_Visit_Request__c> existingByKey = new Map<String, CSC_Visit_Request__c>();
        if (!locations.isEmpty() && !allDates.isEmpty()) {
            for (CSC_Visit_Request__c row : [
                SELECT Id, VisitLocation__c, Blocked_Date__c
                FROM CSC_Visit_Request__c
                WHERE RecordTypeId = :blockRecordTypeId
                  AND VisitLocation__c IN :locations
                  AND Blocked_Date__c IN :allDates
            ]) {
                existingByKey.put(dateKey(row.VisitLocation__c, row.Blocked_Date__c), row);
            }
        }

        List<CSC_Visit_Request__c> toInsert = new List<CSC_Visit_Request__c>();
        List<CSC_Visit_Request__c> toDelete = new List<CSC_Visit_Request__c>();
        List<Result> results = new List<Result>();
        for (Request request : requests) {
            Result result = new Result();
            result.blockedCount = 0;
            result.removedCount = 0;
            for (Date blockDate : parseDates(request.datesToBlock)) {
                String rowKey = dateKey(request.visitLocation, blockDate);
                if (existingByKey.containsKey(rowKey)) {
                    continue;
                }
                CSC_Visit_Request__c row = new CSC_Visit_Request__c(
                    RecordTypeId = blockRecordTypeId,
                    VisitLocation__c = request.visitLocation,
                    Blocked_Date__c = blockDate,
                    Blocked_Reason__c = request.blockedReason
                );
                toInsert.add(row);
                existingByKey.put(rowKey, row);
                result.blockedCount++;
            }
            for (Date unblockDate : parseDates(request.datesToUnblock)) {
                CSC_Visit_Request__c row = existingByKey.get(dateKey(request.visitLocation, unblockDate));
                if (row != null && row.Id != null) {
                    toDelete.add(row);
                    result.removedCount++;
                }
            }
            results.add(result);
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        return results;
    }

    /**
     * @description Splits a semicolon-separated ISO date list.
     * @param value String dates from the calendar flow
     * @return Set<Date> unique dates
     */
    private static Set<Date> parseDates(String value) {
        Set<Date> dates = new Set<Date>();
        if (String.isBlank(value)) {
            return dates;
        }
        for (String part : value.split(';')) {
            if (String.isNotBlank(part)) {
                dates.add(Date.valueOf(part.trim()));
            }
        }
        return dates;
    }

    /**
     * @description Builds one map key for a location and day.
     * @param visitLocation String CSC location
     * @param value Date blocked day
     * @return String location and date key
     */
    private static String dateKey(String visitLocation, Date value) {
        return visitLocation + '|' + String.valueOf(value);
    }

    /**
     * @description Block Date record type used to separate an admin block from a visit.
     * @return Id Block Date record type id
     */
    private static Id blockedDateRecordTypeId() {
        String blockRecordTypeName = CscVisitRequestSelector.RECORD_TYPE_BLOCK;
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'CSC_Visit_Request__c'
              AND DeveloperName = :blockRecordTypeName
            LIMIT 1
        ];
        if (recordTypes.isEmpty()) {
            throw new BlockedDateException('Block Date record type is not available.');
        }
        return recordTypes[0].Id;
    }

    public class BlockedDateException extends Exception {
    }
}