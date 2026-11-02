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

    /**
     * @description
     * Builds calendar events and blocked ranges for the requested date range.
     *
     * @param rangeStart First visible calendar day.
     * @param rangeEnd Last visible calendar day.
     * @param excludeRequestId Request being edited. It remains visible on the calendar.
     * @return Calendar data for the LWC.
     */
    public static MockRoomORICalendarController.CalendarData getCalendar(
        Date rangeStart,
        Date rangeEnd,
        Id excludeRequestId
    ) {
        Date startDate = rangeStart == null ? Date.today().toStartOfMonth() : rangeStart;
        Date endDate = rangeEnd == null ? startDate.addMonths(1).addDays(-1) : rangeEnd;
        MockRoomORICalendarController.CalendarData data =
            new MockRoomORICalendarController.CalendarData();
        data.events = new List<MockRoomORICalendarController.CalendarEvent>();
        data.blocks = new List<MockRoomORICalendarController.CalendarBlock>();

        for (MockRoomOrORIRequest__c requestRecord :
            MockRoomORICalendarSelector.selectActiveRequests(
                startDate,
                endDate,
                excludeRequestId,
                UserInfo.getUserId()
            )) {
            if (
                requestRecord.Status__c == 'Approved' &&
                requestRecord.ConfirmedDate__c != null
            ) {
                addRequestDate(
                    data,
                    requestRecord,
                    requestRecord.ConfirmedDate__c,
                    'Confirmed',
                    startDate,
                    endDate
                );
                continue;
            }

            Map<Date, String> dateRoleByDateMap = new Map<Date, String>{
                requestRecord.PrimaryRequestedDate__c => 'Primary',
                requestRecord.BackupRequestedDate__c => 'Backup'
            };
            dateRoleByDateMap.remove(null);

            for (Date eventDate : dateRoleByDateMap.keySet()) {
                addRequestDate(
                    data,
                    requestRecord,
                    eventDate,
                    dateRoleByDateMap.get(eventDate),
                    startDate,
                    endDate
                );
            }
        }

        for (MockRoomORICalendarBlock__c blockRecord :
            MockRoomORICalendarSelector.selectBlocks(startDate, endDate)) {
            MockRoomORICalendarController.CalendarBlock blockRow =
                new MockRoomORICalendarController.CalendarBlock();
            blockRow.startDate = blockRecord.StartDate__c;
            blockRow.endDate = blockRecord.EndDate__c;
            blockRow.reason = blockRecord.Reason__c;
            blockRow.notes = blockRecord.Notes__c;
            data.blocks.add(blockRow);
        }
        return data;
    }

    /**
     * @description Adds one calendar date when it falls inside the visible range.
     * GC-3483. Approved requests add only the confirmed date. Earlier statuses add each requested date as pending.
     *
     * @param data Calendar payload being built.
     * @param requestRecord Request that owns the date.
     * @param eventDate Date to show.
     * @param dateRole Confirmed, Primary, or Backup.
     * @param startDate First visible calendar day.
     * @param endDate Last visible calendar day.
     */
    private static void addRequestDate(
        MockRoomORICalendarController.CalendarData data,
        MockRoomOrORIRequest__c requestRecord,
        Date eventDate,
        String dateRole,
        Date startDate,
        Date endDate
    ) {
        if (eventDate == null || eventDate < startDate || eventDate > endDate) {
            return;
        }
        MockRoomORICalendarController.CalendarEvent eventRow =
            new MockRoomORICalendarController.CalendarEvent();
        eventRow.requestId = requestRecord.Id;
        eventRow.requestName = requestRecord.Name;
        eventRow.requestType = requestRecord.RecordType.Name;
        eventRow.status = requestRecord.Status__c;
        eventRow.eventDate = eventDate;
        eventRow.dateRole = dateRole;
        data.events.add(eventRow);
    }
}