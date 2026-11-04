/**
 * @author PWC Developer
 * @date 2026/10/08
 *
 * @group Mock Room / ORI Calendar
 *
 * @description
 * GC-3483 - SOQL selector for Mock Room / ORI calendar queries.
 */
public without sharing class MockRoomORICalendarSelector {

    /**
     * @description Returns active requests with a requested date in the visible range.
     *
     * @param rangeStart First visible calendar day.
     * @param rangeEnd Last visible calendar day.
     * @param excludeRequestId Request being edited. It stays on the calendar.
     *        The screen component uses this id only to skip a conflict with itself.
     * @param requestorId Running user. Only this user's saved drafts are returned.
     * @return Submitted, approved, and the requestor's own saved draft requests.
     */
    @SuppressWarnings('PMD.UnusedFormalParameter')
    public static List<MockRoomOrORIRequest__c> selectActiveRequests(
        Date rangeStart,
        Date rangeEnd,
        Id excludeRequestId,
        Id requestorId
    ) {
        Set<String> sharedStatuses = new Set<String>{
            'Submitted',
            'Submitted for Approval',
            'Approved'
        };
        Date lookbackStart = rangeStart == null ? Date.today().addDays(-366) : rangeStart.addDays(-366);
        return [
            SELECT Id, Name, Status__c, RecordType.Name, Account__r.Name,
                PrimaryRequestedDate__c, BackupRequestedDate__c, ConfirmedDate__c,
                EventDurationDays__c
            FROM MockRoomOrORIRequest__c
            WHERE (
                Status__c IN :sharedStatuses
                OR (
                    Status__c = 'Draft'
                    AND Requestor__c = :requestorId
                    AND CustomerLocationType__c != null
                )
            )
            AND (
                (PrimaryRequestedDate__c >= :lookbackStart AND PrimaryRequestedDate__c <= :rangeEnd)
                OR (BackupRequestedDate__c >= :lookbackStart AND BackupRequestedDate__c <= :rangeEnd)
                OR (ConfirmedDate__c >= :lookbackStart AND ConfirmedDate__c <= :rangeEnd)
            )
        ];
    }

    /**
     * @description Returns blocked ranges that overlap the visible calendar range.
     *
     * @param rangeStart First visible calendar day.
     * @param rangeEnd Last visible calendar day.
     * @return Overlapping Strategic Events blocks.
     */
    public static List<MockRoomORICalendarBlock__c> selectBlocks(Date rangeStart, Date rangeEnd) {
        return [
            SELECT StartDate__c, EndDate__c, Reason__c, Notes__c
            FROM MockRoomORICalendarBlock__c
            WHERE StartDate__c <= :rangeEnd
            AND EndDate__c >= :rangeStart
        ];
    }
}