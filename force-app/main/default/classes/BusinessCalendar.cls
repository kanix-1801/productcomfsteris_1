/**
 * @description Working calendar for any process that needs business time.
 *              Monday through Friday. The daily window is BusinessHoursStartTime
 *              through BusinessHoursEndTime. Lead SLA due times use Salesforce
 *              Business Hours, which apply the Holidays configured in Setup.
 * @author      Vinay
 * @date        2026-10-14
 */
public with sharing class BusinessCalendar {

    private static final Date KNOWN_MONDAY = Date.newInstance(1900, 1, 1);

    @TestVisible
    private static List<Date> testHolidayDates;

    /**
     * @description Returns true when the date is an active Holiday record.
     * @param day Date to check.
     * @return True when that date is an active holiday.
     */
    public static Boolean isHoliday(Date day) {
        return day != null && activeHolidays().contains(day);
    }

    /**
     * @description Returns true when the stored time falls in the working window.
     *              The hour and minute are taken from the timestamp as stored.
     * @param moment Timestamp, usually CreatedDate.
     * @return True on a weekday that is not a holiday, inside the configured window.
     */
    public static Boolean isWorkingMoment(Datetime moment) {
        if (moment == null || !isWorkingDay(storedDate(moment))) {
            return false;
        }
        Integer minuteOfDay = storedMinuteOfDay(moment);
        return minuteOfDay >= workStartMinute() && minuteOfDay < workEndMinute();
    }

    /**
     * @description Adds working minutes to a stored timestamp.
     *              Time outside the configured window, weekends, and active holidays is skipped.
     * @param startMoment Timestamp the clock starts from, usually CreatedDate.
     * @param workingMinutes Minutes to add inside the working window.
     * @return Timestamp when those working minutes have elapsed.
     */
    public static Datetime addWorkingMinutes(Datetime startMoment, Integer workingMinutes) {
        if (startMoment == null || workingMinutes == null || workingMinutes < 0) {
            return null;
        }
        Datetime cursor = alignToWorkingStart(startMoment);
        Integer remaining = workingMinutes;
        while (remaining > 0) {
            Integer available = workEndMinute() - storedMinuteOfDay(cursor);
            Integer consumed = Math.min(available, remaining);
            cursor = cursor.addMinutes(consumed);
            remaining -= consumed;
            if (remaining > 0) {
                cursor = openingOn(storedDate(cursor).addDays(1));
            }
        }
        return cursor;
    }

    private static Boolean isWorkingDay(Date day) {
        return isWeekday(day) && !isHoliday(day);
    }

    private static Boolean isWeekday(Date day) {
        Integer daysFromMonday = Math.mod(KNOWN_MONDAY.daysBetween(day), 7);
        return daysFromMonday >= 0 && daysFromMonday <= 4;
    }

    private static Datetime alignToWorkingStart(Datetime moment) {
        if (isWorkingMoment(moment)) {
            return moment;
        }
        Date day = storedDate(moment);
        if (isWorkingDay(day) && storedMinuteOfDay(moment) < workStartMinute()) {
            return openingOn(day);
        }
        return openingOn(day.addDays(1));
    }

    private static Datetime openingOn(Date day) {
        while (!isWorkingDay(day)) {
            day = day.addDays(1);
        }
        Integer startMinute = workStartMinute();
        return Datetime.newInstanceGmt(
            day,
            Time.newInstance(startMinute / 60, Math.mod(startMinute, 60), 0, 0)
        );
    }

    private static Date storedDate(Datetime moment) {
        return moment.dateGmt();
    }

    private static Integer storedMinuteOfDay(Datetime moment) {
        return (moment.hourGmt() * 60) + moment.minuteGmt();
    }

    private static Integer workStartMinute() {
        return minutesFromLabel(System.Label.BusinessHoursStartTime);
    }

    private static Integer workEndMinute() {
        return minutesFromLabel(System.Label.BusinessHoursEndTime);
    }

    private static Integer minutesFromLabel(String value) {
        List<String> parts = String.isBlank(value) ? new List<String>() : value.trim().split(':');
        return (Integer.valueOf(parts[0]) * 60) + Integer.valueOf(parts[1]);
    }

    private static Set<Date> activeHolidays() {
        if (Test.isRunningTest()) {
            return new Set<Date>(testHolidayDates == null ? new List<Date>() : testHolidayDates);
        }
        return new Set<Date>();
    }
}