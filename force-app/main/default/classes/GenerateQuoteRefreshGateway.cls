/**
 * @author PWC Developer
 * @date 2026/07/08
 *
 * @group Generate Quote
 *
 * @description GC-3124 : Integration gateway for Refresh Quote callouts.
 *              POST to GlobalCRM UpsertRefreshSFQuotes; HTTP 2xx is success (SC updates SF via Composite separately).
 *
 * CMDT: ShoutOut_Service_Setting__mdt Developer Name = SF_REFRESH_QUOTE
 */
public with sharing class GenerateQuoteRefreshGateway {
    private static final String CLASS_NAME = 'GenerateQuoteRefreshGateway';
    private static final String REFRESH_SERVICE_SETTING_NAME = 'SF_REFRESH_QUOTE';
    private static final String LOGGER_TAG = 'GC-3124';
    private static final String RESPONSE_SUCCESS_KEY = 'SO_SUCCESS';
    private static final String RESPONSE_RETURN_KEY = 'SO_RETURN';
    private static final String SERVICE_STATUS_KEY = 'SERVICE_STATUS';

    @TestVisible
    private static Boolean forceHardcodedRefreshResponse = false;
    
    /**
     * @description Result wrapper returned to the service layer after SO_Callout execution.
     */
    public class CalloutResult {
        public Boolean calloutSuccess { get; set; }
        public List<GenerateQuoteController.QuoteWrapper> parsedResponse { get; set; }
        public String errorDetail { get; set; }
        public Map<String, Object> serviceResponseMap { get; set; }
        public Boolean retryEnqueued { get; set; }

        public CalloutResult() {
            this.calloutSuccess = false;
            this.retryEnqueued = false;
            this.parsedResponse = new List<GenerateQuoteController.QuoteWrapper>();
        }
    }

    /**
     * @description Invokes Refresh Quote via SO_Callout for one Opportunity.
     * @param requestBody DTO serialized as SO_Constants.RESTBODY.
     * @return CalloutResult with parsed quote rows and SO framework response map.
     */
    public static CalloutResult refreshQuotes(RefreshQuoteRequest requestBody) {
        CalloutResult result = new CalloutResult();

        try {
            if (requestBody == null) {
                result.errorDetail = 'Request body is null';
                Logger.warn(CLASS_NAME + '.refreshQuotes: request body is null').addTag(LOGGER_TAG);
                return result;
            }

            String requestJson = JSON.serialize(requestBody.toJsonMap());
            logRequestPayload(requestBody, requestJson);

            SO_Callout callout = new SO_Callout();
            callout
                .addToRequestMap(SO_Constants.CALLOUTOPERATION, REFRESH_SERVICE_SETTING_NAME)
                .addToRequestMap(SO_Constants.RESTBODY, requestJson);

            addRestConfigToCallout(callout);

            Map<String, Object> responseMap = callout.callWebService();
            result.serviceResponseMap = responseMap;

            Object retryEnqueued = responseMap != null
                ? responseMap.get(SO_Constants.RETRY_ENQUEUED)
                : null;
            result.retryEnqueued = retryEnqueued instanceof Boolean && (Boolean) retryEnqueued;

            String responseBody = extractResponseBody(responseMap);
            logResponsePayload(requestBody, responseBody, responseMap);

            if (result.retryEnqueued) {
                Logger.warn(
                    CLASS_NAME + '.refreshQuotes: SO retry enqueued opportunitySfId=' +
                    requestBody.opportunitySfId
                ).addTag(LOGGER_TAG);
            }

            if (!isSuccessful(responseMap)) {
                result.errorDetail = extractErrorDetail(responseMap);
                Logger.warn(
                    CLASS_NAME + '.refreshQuotes: failed opportunitySfId=' + requestBody.opportunitySfId +
                    ', detail=' + result.errorDetail
                ).addTag(LOGGER_TAG);
                return result;
            }

            result.calloutSuccess = true;
            if (String.isNotBlank(responseBody)) {
                List<GenerateQuoteController.QuoteWrapper> parsedQuotes =
                    RefreshQuoteResponseMapper.parse(responseBody);
                if (parsedQuotes != null) {
                    result.parsedResponse = parsedQuotes;
                }
            }

            Logger.info(
                CLASS_NAME + '.refreshQuotes: completed opportunitySfId=' + requestBody.opportunitySfId
            ).addTag(LOGGER_TAG);
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.refreshQuotes', e).addTag(LOGGER_TAG);
            result.errorDetail = e.getMessage();
        } finally {
            Logger.saveLog();
        }

        return result;
    }

    @TestVisible
    private static void logRequestPayload(RefreshQuoteRequest requestBody, String requestJson) {
        Logger.info(
            CLASS_NAME + '.refreshQuotes: request opportunitySfId=' + requestBody.opportunitySfId +
            ', body=' + requestJson
        ).addTag(LOGGER_TAG);
    }

    @TestVisible
    private static void logResponsePayload(
        RefreshQuoteRequest requestBody,
        String responseBody,
        Map<String, Object> responseMap
    ) {
        String loggedResponseBody = String.isBlank(responseBody)
            ? serializeResponseMapForLog(responseMap)
            : responseBody;

        Logger.info(
            CLASS_NAME + '.refreshQuotes: response opportunitySfId=' + requestBody.opportunitySfId +
            ', httpStatus=' + resolveHttpStatusForLog(responseMap) +
            ', body=' + loggedResponseBody
        ).addTag(LOGGER_TAG);
    }

    @TestVisible
    private static String serializeResponseMapForLog(Map<String, Object> responseMap) {
        if (responseMap == null || responseMap.isEmpty()) {
            return '';
        }

        return JSON.serialize(responseMap);
    }

    @TestVisible
    private static String resolveHttpStatusForLog(Map<String, Object> responseMap) {
        if (responseMap == null || responseMap.isEmpty()) {
            return 'n/a';
        }

        Object serviceStatus = responseMap.get(SERVICE_STATUS_KEY);
        return serviceStatus == null ? 'n/a' : String.valueOf(serviceStatus);
    }

    @TestVisible
    private static Boolean isSuccessful(Map<String, Object> responseMap) {
        if (responseMap == null || responseMap.isEmpty()) {
            return false;
        }

        Object successFlag = responseMap.get(RESPONSE_SUCCESS_KEY);
        return successFlag instanceof Boolean && (Boolean) successFlag;
    }

    @TestVisible
    private static String extractResponseBody(Map<String, Object> responseMap) {
        Object payload = responseMap.get('SERVICE_DATA');

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
        Object serviceData = responseMap.get('SERVICE_DATA');
        if (serviceStatus != null) {
            String errorDetail = 'Refresh Quote callout failed with HTTP status ' + String.valueOf(serviceStatus);
            if (serviceData != null && String.isNotBlank(String.valueOf(serviceData))) {
                errorDetail += ': ' + String.valueOf(serviceData);
            }
            return errorDetail;
        }

        return 'SO_Callout failed with SO_SUCCESS=false';
    }

    @TestVisible
    private static void addRestConfigToCallout(SO_Callout callout) {
        String restVerb = SO_Config.getRestVerb(REFRESH_SERVICE_SETTING_NAME);
        if (String.isNotBlank(restVerb)) {
            callout.addToRequestMap(SO_Constants.RESTHTTPVERB, restVerb);
        }

        String restPath = SO_Config.getRestPath(REFRESH_SERVICE_SETTING_NAME);
        if (String.isBlank(restPath)) {
            return;
        }

        if (restPath.endsWith('/')) {
            restPath = restPath.substring(0, restPath.length() - 1);
        }

        callout.addToRequestMap(SO_Constants.RESTPATH, restPath);
    }
}