/**
 * @description Tests for ConvertTimeByTimeZone Flow action (GW-4800).
 * @see ConvertTimeByTimeZone
 */
@IsTest
private class ConvertTimeByTimeZoneTest {
    private static final String TIME_ZONE_NY = 'America/New_York';
    private static final String TIME_ZONE_LA = 'America/Los_Angeles';
    private static final String TIME_ZONE_UTC = 'UTC';

    /**
     * @description Builds a Flow-style naive Datetime (GMT components = wall clock).
     * @param year Year
     * @param month Month
     * @param day Day
     * @param hour Wall-clock hour
     * @param minute Wall-clock minute
     * @return Datetime with GMT components equal to the wall clock
     */
    private static Datetime wallClockAsGmt(
        Integer year,
        Integer month,
        Integer day,
        Integer hour,
        Integer minute
    ) {
        return Datetime.newInstanceGmt(year, month, day, hour, minute, 0);
    }

    /**
     * @description Builds a conversion request.
     * @param inputTime Input date/time
     * @param inputTimeZone Source time zone SID
     * @param targetTimeZone Target time zone SID
     * @return Flow request
     */
    private static ConvertTimeByTimeZone.Request buildRequest(
        Datetime inputTime,
        String inputTimeZone,
        String targetTimeZone
    ) {
        ConvertTimeByTimeZone.Request request = new ConvertTimeByTimeZone.Request();
        request.inputTime = inputTime;
        request.inputTimeZone = inputTimeZone;
        request.targetTimeZone = targetTimeZone;
        return request;
    }

    /**
     * @description Verifies null and empty request lists return empty results.
     */
    @IsTest
    static void testConvert_nullOrEmptyRequests() {
        Test.startTest();
        List<ConvertTimeByTimeZone.Response> nullResult = ConvertTimeByTimeZone.convert(null);
        List<ConvertTimeByTimeZone.Response> emptyResult =
            ConvertTimeByTimeZone.convert(new List<ConvertTimeByTimeZone.Request>());
        Test.stopTest();

        System.assertEquals(0, nullResult.size());
        System.assertEquals(0, emptyResult.size());
    }

    /**
     * @description Verifies missing required inputs return null converted time.
     */
    @IsTest
    static void testConvert_missingInputs_returnsNullConvertedTime() {
        ConvertTimeByTimeZone.Request request = new ConvertTimeByTimeZone.Request();

        Test.startTest();
        List<ConvertTimeByTimeZone.Response> responses =
            ConvertTimeByTimeZone.convert(new List<ConvertTimeByTimeZone.Request>{ request });
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(null, responses[0].convertedTime);
    }

    /**
     * @description Verifies invalid time zone values return null converted time.
     */
    @IsTest
    static void testConvert_invalidTimeZone_returnsNullConvertedTime() {
        Datetime inputTime = wallClockAsGmt(2026, 8, 19, 10, 0);
        ConvertTimeByTimeZone.Request request = buildRequest(
            inputTime,
            'Not/A_TimeZone',
            TIME_ZONE_LA
        );

        Test.startTest();
        List<ConvertTimeByTimeZone.Response> responses =
            ConvertTimeByTimeZone.convert(new List<ConvertTimeByTimeZone.Request>{ request });
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(null, responses[0].convertedTime);
    }

    /**
     * @description Verifies America/New_York wall clock converts to America/Los_Angeles wall clock.
     *              2026-08-19 15:00 in New York is 12:00 in Los Angeles (EDT, UTC-4 / PDT, UTC-7).
     */
    @IsTest
    static void testConvert_newYorkToLosAngeles() {
        Datetime inputTime = wallClockAsGmt(2026, 8, 19, 15, 0);
        ConvertTimeByTimeZone.Request request = buildRequest(
            inputTime,
            TIME_ZONE_NY,
            TIME_ZONE_LA
        );

        Test.startTest();
        List<ConvertTimeByTimeZone.Response> responses =
            ConvertTimeByTimeZone.convert(new List<ConvertTimeByTimeZone.Request>{ request });
        Test.stopTest();

        System.assertEquals(1, responses.size());
        Datetime convertedTime = responses[0].convertedTime;
        System.assertNotEquals(null, convertedTime);
        System.assertEquals(2026, convertedTime.yearGmt());
        System.assertEquals(8, convertedTime.monthGmt());
        System.assertEquals(19, convertedTime.dayGmt());
        System.assertEquals(12, convertedTime.hourGmt());
        System.assertEquals(0, convertedTime.minuteGmt());
    }

    /**
     * @description Verifies Flow formula pattern: GMT 07:00 as America/New_York wall clock
     *              converts to 11:00 UTC (EDT, UTC-4). Matches FRM_DateTime_7AMStartTime usage.
     */
    @IsTest
    static void testConvert_newYorkSevenAmToUtc() {
        Datetime inputTime = wallClockAsGmt(2026, 8, 20, 7, 0);
        ConvertTimeByTimeZone.Request request = buildRequest(
            inputTime,
            TIME_ZONE_NY,
            TIME_ZONE_UTC
        );

        Test.startTest();
        List<ConvertTimeByTimeZone.Response> responses =
            ConvertTimeByTimeZone.convert(new List<ConvertTimeByTimeZone.Request>{ request });
        Test.stopTest();

        Datetime convertedTime = responses[0].convertedTime;
        System.assertNotEquals(null, convertedTime);
        System.assertEquals(2026, convertedTime.yearGmt());
        System.assertEquals(8, convertedTime.monthGmt());
        System.assertEquals(20, convertedTime.dayGmt());
        System.assertEquals(11, convertedTime.hourGmt());
        System.assertEquals(0, convertedTime.minuteGmt());
    }

    /**
     * @description Verifies converting within the same time zone preserves local components.
     */
    @IsTest
    static void testConvert_sameTimeZone_preservesLocalComponents() {
        Datetime inputTime = wallClockAsGmt(2026, 3, 10, 9, 30);
        ConvertTimeByTimeZone.Request request = buildRequest(
            inputTime,
            TIME_ZONE_NY,
            TIME_ZONE_NY
        );

        Test.startTest();
        List<ConvertTimeByTimeZone.Response> responses =
            ConvertTimeByTimeZone.convert(new List<ConvertTimeByTimeZone.Request>{ request });
        Test.stopTest();

        Datetime convertedTime = responses[0].convertedTime;
        System.assertEquals(2026, convertedTime.yearGmt());
        System.assertEquals(3, convertedTime.monthGmt());
        System.assertEquals(10, convertedTime.dayGmt());
        System.assertEquals(9, convertedTime.hourGmt());
        System.assertEquals(30, convertedTime.minuteGmt());
    }

    /**
     * @description Verifies bulk conversion returns one response per request.
     */
    @IsTest
    static void testConvert_bulkRequests() {
        List<ConvertTimeByTimeZone.Request> requests = new List<ConvertTimeByTimeZone.Request>{
            buildRequest(
                wallClockAsGmt(2026, 8, 19, 15, 0),
                TIME_ZONE_NY,
                TIME_ZONE_LA
            ),
            buildRequest(
                wallClockAsGmt(2026, 1, 15, 8, 0),
                TIME_ZONE_LA,
                TIME_ZONE_NY
            )
        };

        Test.startTest();
        List<ConvertTimeByTimeZone.Response> responses = ConvertTimeByTimeZone.convert(requests);
        Test.stopTest();

        System.assertEquals(2, responses.size());
        System.assertNotEquals(null, responses[0].convertedTime);
        System.assertNotEquals(null, responses[1].convertedTime);
        System.assertEquals(12, responses[0].convertedTime.hourGmt());
        // 08:00 America/Los_Angeles (PST, UTC-8) => 11:00 America/New_York (EST, UTC-5)
        System.assertEquals(11, responses[1].convertedTime.hourGmt());
    }
}