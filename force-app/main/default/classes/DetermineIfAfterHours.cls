/**
 * @description Flow Apex Action: Determine If After Hours.
 *              Converts InputTime into the Operating Hours timezone and evaluates
 *              TimeSlots. Extended slots count as operating only when
 *              ReferToExtendedAsNormalHours is true.
 * @group Operating Hours
 */
public with sharing class DetermineIfAfterHours {
    private static final String SLOT_TYPE_NORMAL = 'Normal';
    private static final String SLOT_TYPE_EXTENDED = 'Extended';

    /**
     * @description Flow request inputs for after-hours evaluation.
     */
    public class Request {
        /** @description Absolute date/time value to evaluate (e.g. $Flow.CurrentDateTime). */
        @InvocableVariable(required=true label='Input Time')
        public Datetime inputTime;

        /**
         * @description Time zone SID associated with Input Time (e.g. America/Los_Angeles).
         *              Salesforce Datetime values are absolute instants; this is used with
         *              Input Time only for validation/context. Evaluation uses Operating Hours TimeZone.
         */
        @InvocableVariable(required=true label='Input Time Zone')
        public String inputTimeZone;

        /** @description Operating Hours record used for TimeSlots and evaluation timezone. */
        @InvocableVariable(required=true label='Operating Hours')
        public OperatingHours operationalHours;

        /**
         * @description When true, Extended TimeSlots are treated as normal operating hours.
         *              When false, Extended TimeSlots count as non-operating (after hours).
         */
        @InvocableVariable(required=true label='Refer To Extended As Normal Hours')
        public Boolean referToExtendedAsNormalHours;
    }

    /**
     * @description Flow response for after-hours evaluation.
     */
    public class Response {
        /**
         * @description True when Input Time is during non-operating (after) hours;
         *              false when during operating hours.
         */
        @InvocableVariable(label='Is After Hours')
        public Boolean isAfterHours;
    }

    /**
     * @description Determines whether each request's Input Time is after hours.
     * @param requests Flow requests
     * @return One response per request
     */
    @InvocableMethod(
        label='Determine If After Hours'
        description='Returns true when Input Time is outside Operating Hours (after hours), accounting for Extended slots via Refer To Extended As Normal Hours.'
    )
    public static List<Response> determine(List<Request> requests) {
        List<Response> responses = new List<Response>();
        try {
            if (requests == null || requests.isEmpty()) {
                return responses;
            }

            Set<Id> operatingHoursIdSet = new Set<Id>();
            for (Request request : requests) {
                if (request?.operationalHours?.Id != null) {
                    operatingHoursIdSet.add(request.operationalHours.Id);
                }
            }

            Map<Id, OperatingHours> operatingHoursById = queryOperatingHoursById(operatingHoursIdSet);
            Map<Id, List<TimeSlot>> timeSlotsByOperatingHoursId =
                groupTimeSlotsByOperatingHoursId(queryTimeSlotsByOperatingHoursIds(operatingHoursIdSet));

            for (Request request : requests) {
                responses.add(evaluateRequest(request, operatingHoursById, timeSlotsByOperatingHoursId));
            }
            return responses;
        } catch (Exception e) {
            Logger.error('DetermineIfAfterHours.determine failed', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Evaluates a single Flow request.
     * @param request Flow request
     * @param operatingHoursById Queried Operating Hours by Id
     * @param timeSlotsByOperatingHoursId TimeSlots grouped by Operating Hours Id
     * @return Response with isAfterHours
     */
    private static Response evaluateRequest(
        Request request,
        Map<Id, OperatingHours> operatingHoursById,
        Map<Id, List<TimeSlot>> timeSlotsByOperatingHoursId
    ) {
        Response response = new Response();
        if (request == null
            || request.inputTime == null
            || String.isBlank(request.inputTimeZone)
            || request.operationalHours == null
            || request.operationalHours.Id == null
        ) {
            Logger.warn('DetermineIfAfterHours: missing required inputs; defaulting isAfterHours=true');
            response.isAfterHours = true;
            return response;
        }

        OperatingHours operatingHours = operatingHoursById.get(request.operationalHours.Id);
        if (operatingHours == null || String.isBlank(operatingHours.TimeZone)) {
            Logger.warn(
                new LogMessage(
                    'DetermineIfAfterHours: Operating Hours {0} missing or has no TimeZone; defaulting isAfterHours=true',
                    request.operationalHours.Id
                )
            );
            response.isAfterHours = true;
            return response;
        }

        // Salesforce Datetime (e.g. $Flow.CurrentDateTime) is an absolute instant.
        // Convert that instant into the Operating Hours timezone for slot evaluation.
        // Do not re-apply InputTimeZone as a wall-clock offset — that double-shifts Flow datetimes.
        String dayOfWeek = request.inputTime.format('EEEE', operatingHours.TimeZone);
        Time localTime = toLocalTime(request.inputTime, operatingHours.TimeZone);
        List<TimeSlot> slots =
            timeSlotsByOperatingHoursId.containsKey(operatingHours.Id)
                ? timeSlotsByOperatingHoursId.get(operatingHours.Id)
                : new List<TimeSlot>();

        Boolean matchedNormal = false;
        Boolean matchedExtended = false;
        for (TimeSlot slot : slots) {
            if (slot.DayOfWeek != dayOfWeek) {
                continue;
            }
            if (!isTimeWithinSlot(localTime, slot.StartTime, slot.EndTime)) {
                continue;
            }
            if (SLOT_TYPE_NORMAL.equals(slot.Type)) {
                matchedNormal = true;
            } else if (SLOT_TYPE_EXTENDED.equals(slot.Type)) {
                matchedExtended = true;
            }
        }

        if (matchedNormal) {
            response.isAfterHours = false;
        } else if (matchedExtended) {
            // Extended counts as operating only when ReferToExtendedAsNormalHours is true
            response.isAfterHours = request.referToExtendedAsNormalHours != true;
        } else {
            response.isAfterHours = true;
        }
        return response;
    }

    /**
     * @description Queries Operating Hours by Id including TimeZone.
     * @param operatingHoursIdSet Operating Hours Ids
     * @return Map of Operating Hours by Id
     */
    private static Map<Id, OperatingHours> queryOperatingHoursById(Set<Id> operatingHoursIdSet) {
        if (operatingHoursIdSet == null || operatingHoursIdSet.isEmpty()) {
            return new Map<Id, OperatingHours>();
        }
        return new Map<Id, OperatingHours>([
            SELECT Id, Name, TimeZone
            FROM OperatingHours
            WHERE Id IN :operatingHoursIdSet
        ]);
    }

    /**
     * @description Queries TimeSlots for the given Operating Hours Ids.
     * @param operatingHoursIdSet Operating Hours Ids
     * @return Matching TimeSlot records
     */
    private static List<TimeSlot> queryTimeSlotsByOperatingHoursIds(Set<Id> operatingHoursIdSet) {
        if (operatingHoursIdSet == null || operatingHoursIdSet.isEmpty()) {
            return new List<TimeSlot>();
        }
        return [
            SELECT Id, OperatingHoursId, DayOfWeek, StartTime, EndTime, Type
            FROM TimeSlot
            WHERE OperatingHoursId IN :operatingHoursIdSet
        ];
    }

    /**
     * @description Builds a Time value for the Datetime as seen in the given timezone.
     * @param inputTime Absolute Datetime
     * @param timeZoneId Timezone SID
     * @return Local Time in that timezone
     */
    @TestVisible
    private static Time toLocalTime(Datetime inputTime, String timeZoneId) {
        Integer hourValue = Integer.valueOf(inputTime.format('H', timeZoneId));
        Integer minuteValue = Integer.valueOf(inputTime.format('m', timeZoneId));
        Integer secondValue = Integer.valueOf(inputTime.format('s', timeZoneId));
        return Time.newInstance(hourValue, minuteValue, secondValue, 0);
    }

    /**
     * @description Returns true when localTime falls within [startTime, endTime),
     *              including overnight slots where startTime > endTime.
     * @param localTime Local time of day
     * @param startTime Slot start
     * @param endTime Slot end
     * @return True when inside the slot
     */
    @TestVisible
    private static Boolean isTimeWithinSlot(Time localTime, Time startTime, Time endTime) {
        if (localTime == null || startTime == null || endTime == null) {
            return false;
        }
        if (startTime < endTime) {
            return localTime >= startTime && localTime < endTime;
        }
        if (startTime > endTime) {
            // Overnight window (e.g. 22:00 – 06:00)
            return localTime >= startTime || localTime < endTime;
        }
        // start == end: treat as full-day coverage
        return true;
    }

    /**
     * @description Groups TimeSlots by Operating Hours Id.
     * @param timeSlotList TimeSlots
     * @return Map of Operating Hours Id to TimeSlots
     */
    private static Map<Id, List<TimeSlot>> groupTimeSlotsByOperatingHoursId(List<TimeSlot> timeSlotList) {
        Map<Id, List<TimeSlot>> timeSlotsByOperatingHoursId = new Map<Id, List<TimeSlot>>();
        if (timeSlotList == null) {
            return timeSlotsByOperatingHoursId;
        }
        for (TimeSlot slot : timeSlotList) {
            if (!timeSlotsByOperatingHoursId.containsKey(slot.OperatingHoursId)) {
                timeSlotsByOperatingHoursId.put(slot.OperatingHoursId, new List<TimeSlot>());
            }
            timeSlotsByOperatingHoursId.get(slot.OperatingHoursId).add(slot);
        }
        return timeSlotsByOperatingHoursId;
    }
}