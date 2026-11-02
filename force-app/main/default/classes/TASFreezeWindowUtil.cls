/**
 * @author Suraj Thapliyal
 * @date 2026/08/11
 * @description TAS delete freeze window from Custom Label TAS_FreezeWindow (MM/DD/YYYY|MM/DD/YYYY,
 *              America/Los_Angeles calendar dates, inclusive). Blank, whitespace, or NO_FREEZE = no freeze.
 *              Malformed label values throw TASTeamAccessException so TASTeamAccessBatch aborts at start.
 *              GC-2596 - TAS delete freeze window; pauses Delete Record batch processing during configured dates.
 */
public without sharing class TASFreezeWindowUtil {

    private static final String FREEZE_TIMEZONE = 'America/Los_Angeles';
    private static final String RANGE_SEPARATOR = '\\|';
    private static final String DATE_SEPARATOR = '/';

    @TestVisible
    private static String testLabelOverride;
    @TestVisible
    private static Date testTodayOverride;

    /**
     * @description Clears freeze-window test hooks between test methods.
     * @return void
     */
    @TestVisible
    static void testOnlyResetHooks() {
        testLabelOverride = null;
        testTodayOverride = null;
    }

    /**
     * @description GC-2596 - Validates Custom Label TAS_FreezeWindow before batch start.
     *              Blank and NO_FREEZE are allowed; malformed values throw TASTeamAccessException.
     * @return void
     */
    public static void validateFreezeWindowLabel() {
        parseLabel(getLabelValue());
    }

    /**
     * @description GC-2596 - True when the label is valid and today (Pacific) is within the range inclusive.
     *              Used by TASTeamAccessSelector to omit Delete Record rows from the batch query locator.
     * @return Whether TAS delete processing should be paused for the current calendar day.
     * @example
     * TASFreezeWindowUtil.isDeleteFreezeActive();
     */
    public static Boolean isDeleteFreezeActive() {
        String labelValue = getLabelValue();
        WindowDates window = parseLabel(labelValue);
        Boolean isDeleteFreezeActive = false;
        if (window != null) {
            Date todayPacific = getTodayPacific();
            isDeleteFreezeActive =
                todayPacific >= window.startDate && todayPacific <= window.endDate;
        }
        return isDeleteFreezeActive;
    }

    /**
     * @description Reads Custom Label TAS_FreezeWindow, or the test override when set.
     * @return Raw label value used for freeze-window parsing.
     */
    private static String getLabelValue() {
        if (Test.isRunningTest() && testLabelOverride != null) {
            return testLabelOverride;
        }
        return System.Label.TAS_FreezeWindow;
    }

    /**
     * @description Returns the current calendar date in America/Los_Angeles, or the test override when set.
     * @return Today's date in the Pacific timezone.
     */
    private static Date getTodayPacific() {
        if (Test.isRunningTest() && testTodayOverride != null) {
            return testTodayOverride;
        }
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', FREEZE_TIMEZONE));
    }

    /**
     * @description True when the org label is the documented default that intentionally disables freeze.
     * @param labelValue Raw Custom Label TAS_FreezeWindow value.
     * @return Whether the label value is NO_FREEZE.
     */
    private static Boolean isNoFreezeDefaultLabel(String labelValue) {
        return 'NO_FREEZE'.equalsIgnoreCase(labelValue.trim());
    }

    /**
     * @description Parsed start and end dates from a valid freeze-window label value.
     */
    private class WindowDates {
        Date startDate;
        Date endDate;
    }

    /**
     * @description Parses MM/DD/YYYY|MM/DD/YYYY label text into inclusive start and end dates.
     * @param labelValue Custom Label TAS_FreezeWindow value.
     * @return Parsed window dates, or null when the label is blank or NO_FREEZE.
     */
    private static WindowDates parseLabel(String labelValue) {
        if (String.isBlank(labelValue) || isNoFreezeDefaultLabel(labelValue)) {
            return null;
        }

        List<String> dateParts = labelValue.trim().split(RANGE_SEPARATOR);
        if (dateParts.size() != 2) {
            throwParseException(
                labelValue,
                'expected MM/DD/YYYY|MM/DD/YYYY (Pacific, inclusive)'
            );
        }

        Date parsedStartDate = parseUsDate(dateParts[0].trim());
        if (parsedStartDate == null) {
            throwParseException(labelValue, 'invalid start date; expected MM/DD/YYYY');
        }

        Date parsedEndDate = parseUsDate(dateParts[1].trim());
        if (parsedEndDate == null) {
            throwParseException(labelValue, 'invalid end date; expected MM/DD/YYYY');
        }

        if (parsedStartDate > parsedEndDate) {
            throwParseException(labelValue, 'start date must be on or before end date');
        }

        WindowDates window = new WindowDates();
        window.startDate = parsedStartDate;
        window.endDate = parsedEndDate;
        return window;
    }

    /**
     * @description Raises TASTeamAccessException for malformed TAS_FreezeWindow label values.
     * @param labelValue Raw Custom Label TAS_FreezeWindow value.
     * @param reason Specific format or parsing failure reason.
     * @return void
     */
    private static void throwParseException(String labelValue, String reason) {
        throw new TASTeamAccessException(
            'TAS_FreezeWindow label parse failed; ' + reason +
            '. labelValue=' + labelValue
        );
    }

    /**
     * @description Parses a US calendar date in MM/DD/YYYY format.
     * @param dateText Date text from Custom Label TAS_FreezeWindow.
     * @return Parsed Date or null when format or calendar value is invalid.
     */
    private static Date parseUsDate(String dateText) {
        if (String.isBlank(dateText)) {
            return null;
        }

        List<String> components = dateText.split(DATE_SEPARATOR);
        if (components.size() != 3) {
            return null;
        }

        try {
            Integer month = Integer.valueOf(components[0].trim());
            Integer day = Integer.valueOf(components[1].trim());
            Integer year = Integer.valueOf(components[2].trim());

            if (month < 1 || month > 12 || day < 1 || day > 31 || year < 1) {
                return null;
            }

            Date parsedDate = Date.newInstance(year, month, day);
            if (parsedDate.year() != year || parsedDate.month() != month || parsedDate.day() != day) {
                return null;
            }

            return parsedDate;
        } catch (Exception e) {
            return null;
        }
    }
}