/**
 * @author PWC Developer
 * @date 2026/10/08
 *
 * @group Mock Room / ORI Calendar
 *
 * @description
 * GC-3483 - LWC controller for the shared Mock Room / ORI calendar.
 * Contains only UI-facing operations and response wrappers.
 */
public with sharing class MockRoomORICalendarController {

    public static final String SCENARIO = 'Mock Room / ORI Calendar';
    public static final String LOGGER_TAG = 'MockRoomORICalendar';

    /**
     * @description Events and blocks that fall in the requested date range.
     * @param rangeStart First visible calendar day.
     * @param rangeEnd Last visible calendar day.
     * @param excludeRequestId Request being edited. It stays on the calendar. The screen uses this id so the request is not a conflict with itself.
     * @return Calendar rows for the screen.
     */
    @AuraEnabled
    public static CalendarData getCalendar(Date rangeStart, Date rangeEnd, Id excludeRequestId) {
        try {
            return MockRoomORICalendarService.getCalendar(rangeStart, rangeEnd, excludeRequestId);
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.error(
                'Unable to retrieve Mock Room / ORI calendar. ' + exceptionValue.getMessage()
            ).addTag(LOGGER_TAG);
            throw new AuraHandledException('Unable to retrieve the Mock Room / ORI calendar.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Calendar payload returned to the screen component.
     */
    public class CalendarData {
        @AuraEnabled public List<CalendarEvent> events;
        @AuraEnabled public List<CalendarBlock> blocks;
    }

    /**
     * @description One requested or scheduled date already on the shared calendar.
     */
    public class CalendarEvent {
        @AuraEnabled public String requestId;
        @AuraEnabled public String requestName;
        @AuraEnabled public String requestType;
        @AuraEnabled public String status;
        @AuraEnabled public Date eventDate;
        @AuraEnabled public String dateRole;
    }

    /**
     * @description A date range Strategic Events has marked unavailable.
     */
    public class CalendarBlock {
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String reason;
        @AuraEnabled public String notes;
    }
}