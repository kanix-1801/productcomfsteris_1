/**
 * @description Tests the reusable working calendar.
 * @author      Vinay
 * @date        2026-10-13
 */
@IsTest(SeeAllData=false)
private class BusinessCalendarTest {

    private static final Datetime MONDAY_MORNING = Datetime.newInstanceGmt(2026, 10, 12, 10, 0, 0);
    private static final Datetime MONDAY_LATE = Datetime.newInstanceGmt(2026, 10, 12, 18, 30, 0);
    private static final Datetime FRIDAY_LATE = Datetime.newInstanceGmt(2026, 10, 16, 18, 30, 0);

    /**
     * @description Confirms 10:00 is inside the window and 19:00 is outside it.
     */
    @IsTest
    static void workingWindowUsesTheStoredClock() {
        Assert.isTrue(BusinessCalendar.isWorkingMoment(MONDAY_MORNING));
        Assert.isFalse(BusinessCalendar.isWorkingMoment(Datetime.newInstanceGmt(2026, 10, 12, 9, 59, 0)));
        Assert.isFalse(BusinessCalendar.isWorkingMoment(Datetime.newInstanceGmt(2026, 10, 12, 19, 0, 0)));
        Assert.isFalse(BusinessCalendar.isWorkingMoment(Datetime.newInstanceGmt(2026, 10, 17, 12, 0, 0)));
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 10, 12, 11, 0, 0),
            BusinessCalendar.addWorkingMinutes(MONDAY_MORNING, 60)
        );
    }

    /**
     * @description Confirms an active holiday is skipped and the stored time is kept inside the window.
     */
    @IsTest
    static void holidayAndWorkingMinutesFollowTheStoredClock() {
        BusinessCalendar.testHolidayDates = new List<Date>{ Date.newInstance(2026, 10, 12) };

        Assert.isTrue(BusinessCalendar.isHoliday(Date.newInstance(2026, 10, 12)));
        Assert.isFalse(BusinessCalendar.isWorkingMoment(MONDAY_MORNING));
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 10, 13, 11, 0, 0),
            BusinessCalendar.addWorkingMinutes(MONDAY_MORNING, 60)
        );
    }

    /**
     * @description Confirms minutes past 19:00 continue at 10:00 on the next working day.
     */
    @IsTest
    static void minutesCrossTheWorkingDayAndWeekend() {
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 10, 13, 10, 30, 0),
            BusinessCalendar.addWorkingMinutes(MONDAY_LATE, 60)
        );
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 10, 19, 10, 30, 0),
            BusinessCalendar.addWorkingMinutes(FRIDAY_LATE, 60)
        );

        BusinessCalendar.testHolidayDates = new List<Date>{ Date.newInstance(2026, 10, 19) };
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 10, 20, 10, 30, 0),
            BusinessCalendar.addWorkingMinutes(FRIDAY_LATE, 60)
        );
    }
}