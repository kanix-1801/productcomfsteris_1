/**
* @author PWC Developer
* @date 2026/10/08
*
* @group Mock Room / ORI Calendar
*
* @description
* GC-3483 - Business logic for building the shared Mock Room / ORI calendar.
*/
public without sharing class MockRoomORICalendarService {
    
    private static final String BACKUP_ROLE = 'Backup';
    
    /**
* @description Builds calendar events and blocked ranges for the requested date range.
* An approved request shows its confirmed date. Any other request holds its primary and backup dates.
*
* @param rangeStart First visible calendar day.
* @param rangeEnd Last visible calendar day.
* @return Calendar data for the LWC.
* @throws IllegalArgumentException When the end date is before the start date.
*/
    public static MockRoomORICalendarController.CalendarData getCalendar(Date rangeStart, Date rangeEnd) {
        Date startDate = rangeStart == null ? Date.today().toStartOfMonth() : rangeStart;
        Date endDate = rangeEnd == null ? startDate.addMonths(1).addDays(-1) : rangeEnd;
        if (endDate < startDate) {
            throw new IllegalArgumentException('The calendar end date must be on or after the start date.');
        }
        MockRoomORICalendarController.CalendarData data = new MockRoomORICalendarController.CalendarData();
        data.events = new List<MockRoomORICalendarController.CalendarEvent>();
        data.blocks = new List<MockRoomORICalendarController.CalendarBlock>();
        
        for (MockRoomOrORIRequest__c requestRecord :
             MockRoomORICalendarSelector.selectActiveRequests(startDate, endDate, UserInfo.getUserId())) {
                 Map<Date, String> dateRoleByDateMap = requestRecord.Status__c == 'Approved' && requestRecord.ConfirmedDate__c != null
                     ? new Map<Date, String>{ requestRecord.ConfirmedDate__c => 'Confirmed' }
                 : new Map<Date, String>{
                     requestRecord.PrimaryRequestedDate__c => 'Primary',
                         requestRecord.BackupRequestedDate__c => BACKUP_ROLE
                         };
                             dateRoleByDateMap.remove(null);
                 for (Date eventDate : dateRoleByDateMap.keySet()) {
                     addRequestSpan(data.events, requestRecord, eventDate, dateRoleByDateMap.get(eventDate), startDate, endDate);
                 }
             }
        
        for (MockRoomORICalendarBlock__c blockRecord : MockRoomORICalendarSelector.selectBlocks(startDate, endDate)) {
            MockRoomORICalendarController.CalendarBlock blockRow = new MockRoomORICalendarController.CalendarBlock();
            blockRow.startDate = blockRecord.StartDate__c;
            blockRow.endDate = blockRecord.EndDate__c;
            blockRow.reason = blockRecord.Reason__c;
            blockRow.notes = blockRecord.Notes__c;
            data.blocks.add(blockRow);
        }
        return data;
    }
    
    /**
* @description Adds each day of the request span that falls inside the visible range.
* GC-3483 Sprint 8. A blank or invalid duration is one day. The primary date and a confirmed date use the event duration.
* A backup requested date stays one day until Strategic Events confirms it.
*
* @param events Calendar events being built.
* @param requestRecord Request that owns the date.
* @param firstDay First day of the span.
* @param role Confirmed, Primary, or Backup.
* @param startDate First visible calendar day.
* @param endDate Last visible calendar day.
*/
    private static void addRequestSpan(
        List<MockRoomORICalendarController.CalendarEvent> events,
        MockRoomOrORIRequest__c requestRecord,
        Date firstDay,
        String role,
        Date startDate,
        Date endDate
    ) {
        Decimal duration = requestRecord.EventDurationDays__c;
        Integer durationDays = role == BACKUP_ROLE || duration == null || duration < 1 ? 1 : duration.intValue();
        for (Integer dayOffset = 0; dayOffset < durationDays; dayOffset++) {
            Date spanDate = firstDay.addDays(dayOffset);
            if (spanDate >= startDate && spanDate <= endDate) {
                MockRoomORICalendarController.CalendarEvent eventRow = new MockRoomORICalendarController.CalendarEvent();
                eventRow.requestId = requestRecord.Id;
                eventRow.requestName = requestRecord.Name;
                eventRow.requestType = requestRecord.RecordType.Name;
                eventRow.accountName = requestRecord.Account__r?.Name;
                eventRow.status = requestRecord.Status__c;
                eventRow.eventDate = spanDate;
                eventRow.dateRole = role;
                events.add(eventRow);
            }
        }
    }
}