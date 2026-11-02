/**
 * @description Flow Apex Action: Convert Time By Time Zone (GW-4800).
 *              Treats Input Time GMT components as wall-clock values in Input Time Zone
 *              (Flow formula / DATETIMEVALUE pattern), then returns the equivalent
 *              local date/time in Target Time Zone as a Datetime whose GMT components
 *              match that target-local wall clock.
 * @group Flow Actions
 */
public with sharing class ConvertTimeByTimeZone {
    /**
     * @description Flow request inputs for timezone conversion.
     */
    public class Request {
        /**
         * @description Date/time whose GMT year/month/day/hour/minute/second are the
         *              wall-clock values in Input Time Zone (e.g. Flow DATETIMEVALUE at 07:00).
         */
        @InvocableVariable(required=true label='Input Time')
        public Datetime inputTime;

        /**
         * @description Time zone SID for Input Time wall-clock values (e.g. America/New_York).
         *              Typically the running user time zone.
         */
        @InvocableVariable(required=true label='Input Time Zone')
        public String inputTimeZone;

        /** @description Time zone SID to convert Input Time into. */
        @InvocableVariable(required=true label='Target Time Zone')
        public String targetTimeZone;
    }

    /**
     * @description Flow response for timezone conversion.
     */
    public class Response {
        /**
         * @description Target-local wall clock stored as GMT components
         *              (so Flow consumers read the converted local date/time).
         */
        @InvocableVariable(label='Converted Time')
        public Datetime convertedTime;
    }

    /**
     * @description Converts each request's Input Time from Input Time Zone to Target Time Zone.
     * @param requests Flow requests
     * @return One response per request
     */
    @InvocableMethod(
        label='Convert Time By Time Zone'
        description='Converts Input Time wall-clock values from Input Time Zone to the equivalent local date/time in Target Time Zone.'
    )
    public static List<Response> convert(List<Request> requests) {
        List<Response> responses = new List<Response>();
        try {
            if (requests == null || requests.isEmpty()) {
                return responses;
            }

            for (Request request : requests) {
                responses.add(convertRequest(request));
            }
            return responses;
        } catch (Exception e) {
            Logger.error('ConvertTimeByTimeZone.convert failed', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Converts a single Flow request.
     * @param request Flow request
     * @return Response with converted time, or null converted time when inputs are invalid
     */
    private static Response convertRequest(Request request) {
        Response response = new Response();
        if (request == null
            || request.inputTime == null
            || String.isBlank(request.inputTimeZone)
            || String.isBlank(request.targetTimeZone)
        ) {
            Logger.warn('ConvertTimeByTimeZone: missing required inputs; returning null converted time');
            return response;
        }

        if (!isValidTimeZone(request.inputTimeZone) || !isValidTimeZone(request.targetTimeZone)) {
            Logger.warn(
                new LogMessage(
                    'ConvertTimeByTimeZone: invalid time zone inputTimeZone={0} targetTimeZone={1}',
                    request.inputTimeZone,
                    request.targetTimeZone
                )
            );
            return response;
        }

        Datetime absoluteInstant = resolveAbsoluteInstant(request.inputTime, request.inputTimeZone);
        response.convertedTime = toLocalDatetime(absoluteInstant, request.targetTimeZone);
        return response;
    }

    /**
     * @description Resolves the absolute instant by treating Input Time GMT components as
     *              wall-clock values in Input Time Zone (Flow DATETIMEVALUE / formula pattern).
     * @param inputTime Input date/time (GMT components = source wall clock)
     * @param inputTimeZone Source time zone SID
     * @return Absolute Datetime
     */
    @TestVisible
    private static Datetime resolveAbsoluteInstant(Datetime inputTime, String inputTimeZone) {
        return absoluteFromLocal(
            inputTime.yearGmt(),
            inputTime.monthGmt(),
            inputTime.dayGmt(),
            inputTime.hourGmt(),
            inputTime.minuteGmt(),
            inputTime.secondGmt(),
            inputTimeZone
        );
    }

    /**
     * @description Builds a Datetime whose components match the local date/time in timeZoneId.
     * @param absoluteInstant Absolute Datetime
     * @param timeZoneId Target time zone SID
     * @return Datetime with target-local components stored as GMT components
     */
    @TestVisible
    private static Datetime toLocalDatetime(Datetime absoluteInstant, String timeZoneId) {
        return Datetime.newInstanceGmt(
            Integer.valueOf(absoluteInstant.format('yyyy', timeZoneId)),
            Integer.valueOf(absoluteInstant.format('MM', timeZoneId)),
            Integer.valueOf(absoluteInstant.format('d', timeZoneId)),
            Integer.valueOf(absoluteInstant.format('H', timeZoneId)),
            Integer.valueOf(absoluteInstant.format('m', timeZoneId)),
            Integer.valueOf(absoluteInstant.format('s', timeZoneId))
        );
    }

    /**
     * @description Converts wall-clock local components in timeZoneId to an absolute Datetime.
     * @param year Local year
     * @param month Local month
     * @param day Local day
     * @param hour Local hour
     * @param minute Local minute
     * @param second Local second
     * @param timeZoneId Time zone SID for the wall-clock values
     * @return Absolute Datetime
     */
    @TestVisible
    private static Datetime absoluteFromLocal(
        Integer year,
        Integer month,
        Integer day,
        Integer hour,
        Integer minute,
        Integer second,
        String timeZoneId
    ) {
        Datetime asGmt = Datetime.newInstanceGmt(year, month, day, hour, minute, second);
        Integer offsetMs = TimeZone.getTimeZone(timeZoneId).getOffset(asGmt);
        return asGmt.addSeconds(-offsetMs / 1000);
    }

    /**
     * @description Returns true when the time zone SID resolves in Apex.
     * @param timeZoneId Time zone SID
     * @return True when valid
     */
    @TestVisible
    private static Boolean isValidTimeZone(String timeZoneId) {
        if (String.isBlank(timeZoneId)) {
            return false;
        }
        TimeZone resolved = TimeZone.getTimeZone(timeZoneId);
        if (resolved == null) {
            return false;
        }
        // Unknown SIDs fall back to GMT in Apex.
        String resolvedId = resolved.getID();
        return !('GMT'.equals(resolvedId)
            && !'GMT'.equals(timeZoneId)
            && !'UTC'.equals(timeZoneId));
    }
}