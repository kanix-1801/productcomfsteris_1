/**
 * @author Himanshu Chaurasia
 * @date 2026/09/30
 *
 * @description GC-3457 - Gateway that posts Opportunity / Quote events to Boomi
 *              through ShoutOut SO_Callout using SF_SC_OPPORTUNITY_QUOTE_EVENTS.
 */
public with sharing class ScOpportunityQuoteEventGateway {
    private static final String CLASS_NAME = 'ScOpportunityQuoteEventGateway';
    public static final String SERVICE_SETTING_NAME = 'SF_SC_OPPORTUNITY_QUOTE_EVENTS';
    private static final String RESPONSE_SUCCESS_KEY = 'SO_SUCCESS';
    private static final String RESPONSE_RETURN_KEY = 'SO_RETURN';
    private static final String SERVICE_STATUS_KEY = 'SERVICE_STATUS';
    private static final String SERVICE_DATA_KEY = 'SERVICE_DATA';
    private static final Integer HARDCODED_HTTP_STATUS = 200;

    /** Tests only — production always uses ShoutOut / Named Credential callouts. */
    @TestVisible
    private static Boolean forceHardcodedResponse = false;

    public class CalloutResult {
        public Boolean calloutSuccess { get; set; }
        public Boolean retryEnqueued { get; set; }
        public String errorDetail { get; set; }
        public String responseBody { get; set; }
        public Map<String, Object> serviceResponseMap { get; set; }

        public CalloutResult() {
            calloutSuccess = false;
            retryEnqueued = false;
        }
    }

    /**
     * @description Sends one Opportunity / Quote event payload to the configured Boomi/mock endpoint.
     */
    public static CalloutResult sendEvent(ScOpportunityQuoteEventRequest requestBody) {
        CalloutResult result = new CalloutResult();

        try {
            if (requestBody == null) {
                result.errorDetail = 'Request body is null';
                Logger.warn(CLASS_NAME + '.sendEvent: request body is null').addTag('GC-3457');
                return result;
            }

            String requestJson = JSON.serialize(requestBody.toJsonMap());
            logRequestPayload(requestBody, requestJson);

            if (shouldUseHardcodedResponse()) {
                return buildHardcodedResult(requestBody);
            }

            SO_Callout callout = new SO_Callout();
            callout
                .addToRequestMap(SO_Constants.CALLOUTOPERATION, SERVICE_SETTING_NAME)
                .addToRequestMap(SO_Constants.RESTBODY, requestJson);

            Map<String, Object> responseMap = callout.callWebService();
            result.serviceResponseMap = responseMap;

            Object retryValue = responseMap == null
                ? null
                : responseMap.get(SO_Constants.RETRY_ENQUEUED);
            result.retryEnqueued = retryValue instanceof Boolean && (Boolean) retryValue;

            if (result.retryEnqueued) {
                Logger.warn(
                    CLASS_NAME + '.sendEvent: SO retry enqueued eventType=' + requestBody.eventType +
                    ', opportunityId=' + requestBody.sfOpportunityId
                ).addTag('GC-3457');
            }

            String responseBody = extractResponseBody(responseMap);
            result.responseBody = responseBody;
            logResponsePayload(requestBody, responseBody, responseMap);

            result.calloutSuccess = isSuccessful(responseMap, responseBody);

            if (!result.calloutSuccess) {
                result.errorDetail = extractErrorDetail(responseMap);
                Logger.warn(
                    CLASS_NAME + '.sendEvent: failed eventType=' + requestBody.eventType +
                    ', opportunityId=' + requestBody.sfOpportunityId +
                    ', detail=' + result.errorDetail
                ).addTag('GC-3457');
            } else {
                Logger.info(
                    CLASS_NAME + '.sendEvent: completed eventType=' + requestBody.eventType +
                    ', opportunityId=' + requestBody.sfOpportunityId
                ).addTag('GC-3457');
            }
        } catch (Exception exceptionValue) {
            result.errorDetail = exceptionValue.getMessage();
            Logger.error(CLASS_NAME + '.sendEvent', exceptionValue).addTag('GC-3457');
        }

        return result;
    }

    @TestVisible
    private static Boolean shouldUseHardcodedResponse() {
        return Test.isRunningTest() && forceHardcodedResponse == true;
    }

    @TestVisible
    private static CalloutResult buildHardcodedResult(ScOpportunityQuoteEventRequest requestBody) {
        CalloutResult result = new CalloutResult();
        String responseBody = buildHardcodedResponseBody(requestBody);
        result.responseBody = responseBody;
        result.calloutSuccess = true;
        result.serviceResponseMap = new Map<String, Object>{
            RESPONSE_SUCCESS_KEY => true,
            SERVICE_STATUS_KEY => HARDCODED_HTTP_STATUS,
            SERVICE_DATA_KEY => responseBody
        };

        Logger.info(
            CLASS_NAME + '.sendEvent: using hardcoded mock response eventType=' +
            requestBody.eventType + ', opportunityId=' + requestBody.sfOpportunityId
        ).addTag('GC-3457');
        logResponsePayload(requestBody, responseBody, result.serviceResponseMap);

        return result;
    }

    @TestVisible
    private static String buildHardcodedResponseBody(ScOpportunityQuoteEventRequest requestBody) {
        Map<String, Object> responseMap = new Map<String, Object>{
            'status' => ScOpportunityQuoteEventResponse.STATUS_SUCCESS,
            'quotes' => buildResponseQuoteMaps(requestBody)
        };

        if (ScOpportunityQuoteEventRequest.EVENT_TYPE_QUOTE_FORECAST_CONFIDENCE_UPDATE.equals(
            requestBody.eventType
        )) {
            responseMap.put('quoteStatus', ScOpportunityQuoteEventRequest.NOT_APPLICABLE_VALUE);
            responseMap.put('quoteForecastConfidence', requestBody.forecastConfidence);
        } else if (
            ScOpportunityQuoteEventRequest.EVENT_TYPE_OPPORTUNITY_CLOSED_LOST.equals(requestBody.eventType) ||
            ScOpportunityQuoteEventRequest.EVENT_TYPE_OPPORTUNITY_CONVERTED_TO_EPP_QUOTES_CLOSED.equals(
                requestBody.eventType
            )
        ) {
            responseMap.put('quoteStatus', ScOpportunityQuoteEventRequest.QUOTE_STATUS_CLOSED);
            responseMap.put(
                'quoteForecastConfidence',
                ScOpportunityQuoteEventRequest.NOT_APPLICABLE_VALUE
            );
        }

        return JSON.serialize(responseMap);
    }

    /**
     * @description Echoes request quote ids in the mock response (Boomi contract shape).
     */
    @TestVisible
    private static List<Map<String, Object>> buildResponseQuoteMaps(
        ScOpportunityQuoteEventRequest requestBody
    ) {
        List<Map<String, Object>> quoteMaps = new List<Map<String, Object>>();

        if (requestBody == null || requestBody.quotes == null) {
            return quoteMaps;
        }

        for (ScOpportunityQuoteEventRequest.QuoteEntry quoteEntry : requestBody.quotes) {
            if (quoteEntry == null) {
                continue;
            }

            quoteMaps.add(
                new Map<String, Object>{
                    'salesConnectionQuoteId' => quoteEntry.salesConnectionQuoteId,
                    'salesforceQuoteId' => quoteEntry.salesforceQuoteId
                }
            );
        }

        return quoteMaps;
    }

    @TestVisible
    private static void logRequestPayload(
        ScOpportunityQuoteEventRequest requestBody,
        String requestJson
    ) {
        Logger.info(
            CLASS_NAME + '.sendEvent: request eventType=' + requestBody.eventType +
            ', opportunityId=' + requestBody.sfOpportunityId +
            ', body=' + requestJson
        ).addTag('GC-3457');
    }

    @TestVisible
    private static void logResponsePayload(
        ScOpportunityQuoteEventRequest requestBody,
        String responseBody,
        Map<String, Object> responseMap
    ) {
        String loggedResponseBody = String.isBlank(responseBody)
            ? serializeResponseMapForLog(responseMap)
            : responseBody;

        Logger.info(
            CLASS_NAME + '.sendEvent: response eventType=' + requestBody.eventType +
            ', opportunityId=' + requestBody.sfOpportunityId +
            ', httpStatus=' + resolveHttpStatusForLog(responseMap) +
            ', body=' + loggedResponseBody
        ).addTag('GC-3457');
    }

    @TestVisible
    private static String serializeResponseMapForLog(Map<String, Object> responseMap) {
        if (responseMap == null || responseMap.isEmpty()) {
            return '';
        }

        return JSON.serialize(responseMap);
    }

    @TestVisible
    private static Boolean isSuccessful(Map<String, Object> responseMap, String responseBody) {
        if (responseMap == null || responseMap.isEmpty()) {
            return false;
        }

        Object successFlag = responseMap.get(RESPONSE_SUCCESS_KEY);
        if (!(successFlag instanceof Boolean) || !(Boolean) successFlag) {
            return false;
        }

        Object serviceStatus = responseMap.get(SERVICE_STATUS_KEY);
        if (serviceStatus != null) {
            Integer httpStatus;

            try {
                httpStatus = Integer.valueOf(String.valueOf(serviceStatus));
            } catch (Exception exceptionValue) {
                httpStatus = null;
            }

            if (httpStatus != null && (httpStatus < 200 || httpStatus >= 300)) {
                return false;
            }
        }

        ScOpportunityQuoteEventResponse businessResponse =
            ScOpportunityQuoteEventResponse.parse(responseBody);

        if (businessResponse == null || String.isBlank(businessResponse.status)) {
            return true;
        }

        return businessResponse.isSuccessStatus();
    }

    @TestVisible
    private static String extractResponseBody(Map<String, Object> responseMap) {
        if (responseMap == null || responseMap.isEmpty()) {
            return null;
        }

        Object payload = responseMap.get(SERVICE_DATA_KEY);

        if (payload == null) {
            payload = responseMap.get(SO_Constants.SERVICERESPONSE);
        }

        if (payload == null) {
            return null;
        }

        if (payload instanceof String) {
            String body = (String) payload;
            return String.isBlank(body) ? null : body;
        }

        return JSON.serialize(payload);
    }

    @TestVisible
    private static String extractErrorDetail(Map<String, Object> responseMap) {
        if (responseMap == null || responseMap.isEmpty()) {
            return 'SO_Callout returned an empty response map';
        }

        Object soReturn = responseMap.get(RESPONSE_RETURN_KEY);
        if (soReturn != null && String.isNotBlank(String.valueOf(soReturn))) {
            return String.valueOf(soReturn);
        }

        Object serviceResponse = responseMap.get(SO_Constants.SERVICERESPONSE);
        if (serviceResponse != null && String.isNotBlank(String.valueOf(serviceResponse))) {
            return String.valueOf(serviceResponse);
        }

        Object serviceStatus = responseMap.get(SERVICE_STATUS_KEY);
        Object serviceData = responseMap.get(SERVICE_DATA_KEY);
        if (serviceStatus != null) {
            String errorDetail =
                'Opportunity Quote SC event callout failed with HTTP status ' +
                String.valueOf(serviceStatus);
            if (serviceData != null && String.isNotBlank(String.valueOf(serviceData))) {
                errorDetail += ': ' + String.valueOf(serviceData);
            }
            return errorDetail;
        }

        return 'SO_Callout failed with SO_SUCCESS=false';
    }

    @TestVisible
    private static String resolveHttpStatusForLog(Map<String, Object> responseMap) {
        if (responseMap == null || responseMap.isEmpty()) {
            return 'n/a';
        }

        Object serviceStatus = responseMap.get(SERVICE_STATUS_KEY);
        return serviceStatus == null ? 'n/a' : String.valueOf(serviceStatus);
    }
}