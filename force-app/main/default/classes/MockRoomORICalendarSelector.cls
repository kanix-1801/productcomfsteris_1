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
* @description Returns submitted and approved requests, plus the running user's saved drafts, with a date in range.
* Dates up to a year before the range are included so a multi-day event that started earlier still shows.
*
* @param rangeStart First visible calendar day.
* @param rangeEnd Last visible calendar day.
* @param requestorId Running user. Only this user's saved drafts are returned.
* @return Requests that can appear on the calendar.
*/
    public static List<MockRoomOrORIRequest__c> selectActiveRequests(Date rangeStart, Date rangeEnd, Id requestorId) {
        Date lookbackStart = rangeStart.addDays(-366);
        List<MockRoomOrORIRequest__c> requests = [
            SELECT Id, Name, Status__c, RecordType.Name, Account__r.Name,
            PrimaryRequestedDate__c, BackupRequestedDate__c, ConfirmedDate__c, EventDurationDays__c
            FROM MockRoomOrORIRequest__c
            WHERE (
                Status__c IN ('Submitted', 'Submitted for Approval', 'Approved')
                OR (Status__c = 'Draft' AND Requestor__c = :requestorId AND CustomerLocationType__c != null)
            )
            AND (
                (PrimaryRequestedDate__c >= :lookbackStart AND PrimaryRequestedDate__c <= :rangeEnd)
                OR (BackupRequestedDate__c >= :lookbackStart AND BackupRequestedDate__c <= :rangeEnd)
                OR (ConfirmedDate__c >= :lookbackStart AND ConfirmedDate__c <= :rangeEnd)
            )
        ];
        return requests;
    }
    
    /**
* @description Returns blocked ranges that overlap the visible calendar range.
*
* @param rangeStart First visible calendar day.
* @param rangeEnd Last visible calendar day.
* @return Overlapping Strategic Events blocks.
*/
    public static List<MockRoomORICalendarBlock__c> selectBlocks(Date rangeStart, Date rangeEnd) {
        List<MockRoomORICalendarBlock__c> blocks = [
            SELECT StartDate__c, EndDate__c, Reason__c, Notes__c
            FROM MockRoomORICalendarBlock__c
            WHERE StartDate__c <= :rangeEnd AND EndDate__c >= :rangeStart
        ];
        return blocks;
    }
}