/**
 * @description Tests for DetermineIfAfterHours Flow action.
 * @see DetermineIfAfterHours
 */
@IsTest
private class DetermineIfAfterHoursTest {
    private static final String TIME_ZONE_NY = 'America/New_York';
    private static final String TIME_ZONE_LA = 'America/Los_Angeles';

    /**
     * @description Creates Operating Hours with Normal and optional Extended Monday slots.
     * @param includeExtended When true, adds Monday 17:00-21:00 Extended slot
     * @return Inserted Operating Hours
     */
    private static OperatingHours createOperatingHoursWithMondaySlots(Boolean includeExtended) {
        OperatingHours operatingHours = new OperatingHours(
            Name = 'AU After Hours ' + String.valueOf(Crypto.getRandomInteger()),
            TimeZone = TIME_ZONE_NY
        );
        insert operatingHours;

        List<TimeSlot> slots = new List<TimeSlot>{
            new TimeSlot(
                OperatingHoursId = operatingHours.Id,
                DayOfWeek = 'Monday',
                Type = 'Normal',
                StartTime = Time.newInstance(9, 0, 0, 0),
                EndTime = Time.newInstance(17, 0, 0, 0)
            )
        };
        if (includeExtended) {
            slots.add(
                new TimeSlot(
                    OperatingHoursId = operatingHours.Id,
                    DayOfWeek = 'Monday',
                    Type = 'Extended',
                    StartTime = Time.newInstance(17, 0, 0, 0),
                    EndTime = Time.newInstance(21, 0, 0, 0)
                )
            );
        }
        insert slots;
        return operatingHours;
    }

    /**
     * @description Builds an absolute Datetime for a wall-clock local time in timeZoneId.
     * @param year Year
     * @param month Month
     * @param day Day
     * @param hour Local hour
     * @param minute Local minute
     * @param timeZoneId Timezone SID for the wall-clock values
     * @return Absolute Datetime
     */
    private static Datetime absoluteFromLocal(
        Integer year,
        Integer month,
        Integer day,
        Integer hour,
        Integer minute,
        String timeZoneId
    ) {
        Datetime asGmt = Datetime.newInstanceGmt(year, month, day, hour, minute, 0);
        Integer offsetMs = TimeZone.getTimeZone(timeZoneId).getOffset(asGmt);
        return asGmt.addSeconds(-offsetMs / 1000);
    }

    /**
     * @description Builds a request for Monday local time in America/New_York.
     *              2026-08-10 is a Monday.
     * @param hour Local hour in NY
     * @param minute Local minute in NY
     * @param operatingHours Operating Hours record
     * @param referToExtendedAsNormalHours Extended-hours flag
     * @return Flow request
     */
    private static DetermineIfAfterHours.Request buildMondayNyRequest(
        Integer hour,
        Integer minute,
        OperatingHours operatingHours,
        Boolean referToExtendedAsNormalHours
    ) {
        DetermineIfAfterHours.Request request = new DetermineIfAfterHours.Request();
        request.inputTime = absoluteFromLocal(2026, 8, 10, hour, minute, TIME_ZONE_NY);
        request.inputTimeZone = TIME_ZONE_NY;
        request.operationalHours = operatingHours;
        request.referToExtendedAsNormalHours = referToExtendedAsNormalHours;
        return request;
    }

    @IsTest
    static void determine_nullOrEmptyRequests_returnsEmpty() {
        Test.startTest();
        List<DetermineIfAfterHours.Response> nullResult = DetermineIfAfterHours.determine(null);
        List<DetermineIfAfterHours.Response> emptyResult =
            DetermineIfAfterHours.determine(new List<DetermineIfAfterHours.Request>());
        Test.stopTest();

        System.assertEquals(0, nullResult.size());
        System.assertEquals(0, emptyResult.size());
    }

    @IsTest
    static void determine_missingInputs_defaultsToAfterHours() {
        DetermineIfAfterHours.Request request = new DetermineIfAfterHours.Request();

        Test.startTest();
        List<DetermineIfAfterHours.Response> responses =
            DetermineIfAfterHours.determine(new List<DetermineIfAfterHours.Request>{ request });
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(true, responses[0].isAfterHours);
    }

    @IsTest
    static void determine_duringNormalHours_returnsFalse() {
        OperatingHours operatingHours = createOperatingHoursWithMondaySlots(false);
        DetermineIfAfterHours.Request request =
            buildMondayNyRequest(10, 30, operatingHours, false);

        Test.startTest();
        List<DetermineIfAfterHours.Response> responses =
            DetermineIfAfterHours.determine(new List<DetermineIfAfterHours.Request>{ request });
        Test.stopTest();

        System.assertEquals(false, responses[0].isAfterHours, '10:30 Monday NY is during Normal hours');
    }

    @IsTest
    static void determine_outsideAnySlot_returnsTrue() {
        OperatingHours operatingHours = createOperatingHoursWithMondaySlots(false);
        DetermineIfAfterHours.Request request =
            buildMondayNyRequest(22, 0, operatingHours, false);

        Test.startTest();
        List<DetermineIfAfterHours.Response> responses =
            DetermineIfAfterHours.determine(new List<DetermineIfAfterHours.Request>{ request });
        Test.stopTest();

        System.assertEquals(true, responses[0].isAfterHours, '22:00 Monday NY is after hours');
    }

    @IsTest
    static void determine_extendedHours_referAsNormal_returnsFalse() {
        OperatingHours operatingHours = createOperatingHoursWithMondaySlots(true);
        DetermineIfAfterHours.Request request =
            buildMondayNyRequest(18, 0, operatingHours, true);

        Test.startTest();
        List<DetermineIfAfterHours.Response> responses =
            DetermineIfAfterHours.determine(new List<DetermineIfAfterHours.Request>{ request });
        Test.stopTest();

        System.assertEquals(
            false,
            responses[0].isAfterHours,
            'Extended hours with referAsNormal=true should be operating'
        );
    }

    @IsTest
    static void determine_extendedHours_notReferAsNormal_returnsTrue() {
        OperatingHours operatingHours = createOperatingHoursWithMondaySlots(true);
        DetermineIfAfterHours.Request request =
            buildMondayNyRequest(18, 0, operatingHours, false);

        Test.startTest();
        List<DetermineIfAfterHours.Response> responses =
            DetermineIfAfterHours.determine(new List<DetermineIfAfterHours.Request>{ request });
        Test.stopTest();

        System.assertEquals(
            true,
            responses[0].isAfterHours,
            'Extended hours with referAsNormal=false should be after hours'
        );
    }

    @IsTest
    static void determine_flowCurrentDateTime_earlyMorningLa_isAfterHoursInNy() {
        // Mirrors Flow: $Flow.CurrentDateTime at 01:45 America/Los_Angeles,
        // Operating Hours in America/New_York (≈ 04:45) → after hours.
        OperatingHours operatingHours = createOperatingHoursWithMondaySlots(false);
        DetermineIfAfterHours.Request request = new DetermineIfAfterHours.Request();
        request.inputTime = absoluteFromLocal(2026, 8, 10, 1, 45, TIME_ZONE_LA);
        request.inputTimeZone = TIME_ZONE_LA;
        request.operationalHours = operatingHours;
        request.referToExtendedAsNormalHours = false;

        Test.startTest();
        List<DetermineIfAfterHours.Response> responses =
            DetermineIfAfterHours.determine(new List<DetermineIfAfterHours.Request>{ request });
        Test.stopTest();

        System.assertEquals(
            true,
            responses[0].isAfterHours,
            '01:45 LA (=04:45 NY) should be after hours'
        );
    }

    @IsTest
    static void isTimeWithinSlot_supportsOvernightAndEdgeCases() {
        Time localEvening = Time.newInstance(23, 0, 0, 0);
        Time localMorning = Time.newInstance(2, 0, 0, 0);
        Time localMidday = Time.newInstance(12, 0, 0, 0);
        Time startNight = Time.newInstance(22, 0, 0, 0);
        Time endMorning = Time.newInstance(6, 0, 0, 0);
        Time startDay = Time.newInstance(9, 0, 0, 0);
        Time endDay = Time.newInstance(17, 0, 0, 0);

        System.assertEquals(
            true,
            DetermineIfAfterHours.isTimeWithinSlot(localEvening, startNight, endMorning)
        );
        System.assertEquals(
            true,
            DetermineIfAfterHours.isTimeWithinSlot(localMorning, startNight, endMorning)
        );
        System.assertEquals(
            false,
            DetermineIfAfterHours.isTimeWithinSlot(localMidday, startNight, endMorning)
        );
        System.assertEquals(
            true,
            DetermineIfAfterHours.isTimeWithinSlot(Time.newInstance(9, 0, 0, 0), startDay, endDay)
        );
        System.assertEquals(
            false,
            DetermineIfAfterHours.isTimeWithinSlot(Time.newInstance(17, 0, 0, 0), startDay, endDay)
        );
        System.assertEquals(
            true,
            DetermineIfAfterHours.isTimeWithinSlot(localMidday, startDay, startDay),
            'Equal start/end treated as full day'
        );
        System.assertEquals(false, DetermineIfAfterHours.isTimeWithinSlot(null, startDay, endDay));
    }
}