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
* @description Builds calendar events and blocked ranges for the requested date range.
* An approved request shows its confirmed date. Any other request holds its primary and backup dates.
* GC-3666. Each date is one day. Event duration is informational and never blocks extra days.
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
						 requestRecord.BackupRequestedDate__c => 'Backup'
						 };
							 dateRoleByDateMap.remove(null);
				 for (Date eventDate : dateRoleByDateMap.keySet()) {
					 if (eventDate >= startDate && eventDate <= endDate) {
						 MockRoomORICalendarController.CalendarEvent eventRow = new MockRoomORICalendarController.CalendarEvent();
						 eventRow.requestId = requestRecord.Id;
						 eventRow.requestName = requestRecord.Name;
						 eventRow.requestType = requestRecord.RecordType.Name;
						 eventRow.accountName = requestRecord.Account__r?.Name;
						 eventRow.status = requestRecord.Status__c;
						 eventRow.eventDate = eventDate;
						 eventRow.dateRole = dateRoleByDateMap.get(eventDate);
						 data.events.add(eventRow);
					 }
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
}