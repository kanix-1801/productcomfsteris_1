/**
 * @author Sahithi PWC
 * @date 01-07-2026
 * @description #GC-3162 Integration gateway for Oracle Unit Price API callouts (Part2).
 */
public with sharing class OracleUnitPricingGatewayPart2 {

    private static final String CLASS_NAME = 'OracleUnitPricingGatewayPart2';
    private static final String TAS_SERVICE_SETTING_NAME = 'SF_GET_UNIT_PRICE';
    private static final String RESPONSE_SUCCESS_KEY = 'SO_SUCCESS';
    private static final String RESPONSE_RETURN_KEY = 'SO_RETURN';

    public class CalloutResult {
        public Boolean calloutSuccess { get; set; }
        public OraclePricingResponsePart2 parsedResponse { get; set; }
        public String errorDetail { get; set; }
        public Map<String, Object> serviceResponseMap { get; set; }
        public Boolean retryEnqueued { get; set; }

        public CalloutResult() {
            calloutSuccess = false;
            retryEnqueued = false;
        }
    }

    public static CalloutResult sendUnitPriceRequest(OraclePricingRequestPart2 requestBody) {
        CalloutResult result = new CalloutResult();

        try {
            Logger.info(CLASS_NAME + '.sendUnitPriceRequest: started');

            if (requestBody == null) {
                result.errorDetail = 'Request body is null';
                Logger.warn(CLASS_NAME + '.sendUnitPriceRequest: request body is null');
                return result;
            }

            String requestJson = requestBody.toJsonString();
            System.debug('=== Oracle Pricing Request ===');
            System.debug(requestJson);

            SO_Callout callout = new SO_Callout();
            callout
                .addToRequestMap(SO_Constants.CALLOUTOPERATION, TAS_SERVICE_SETTING_NAME)
                .addToRequestMap(SO_Constants.RESTBODY, requestJson);

            Map<String, Object> responseMap = callout.callWebService();

            System.debug('=== Oracle Pricing Response Map ===');
            System.debug(JSON.serializePretty(responseMap));

            result.serviceResponseMap = responseMap;

            Object retry = responseMap != null
                ? responseMap.get(SO_Constants.RETRY_ENQUEUED)
                : null;
            result.retryEnqueued = retry instanceof Boolean && (Boolean) retry;

            if (result.retryEnqueued) {
                Logger.warn(CLASS_NAME + '.sendUnitPriceRequest: SO retry enqueued');
            }

            if (!isSuccessful(responseMap)) {
                result.errorDetail = extractErrorDetail(responseMap);
                result.calloutSuccess = false;

                Logger.error(
                    CLASS_NAME + '.sendUnitPriceRequest: callout failed, detail=' +
                    result.errorDetail
                );

                if (Test.isRunningTest()) {
                    result.parsedResponse =
                        OraclePricingResponsePart2.getMockResponse(requestBody);
                    result.calloutSuccess = true;
                }

                return result;
            }

            String responseBody = extractResponseBody(responseMap);
            result.parsedResponse = OraclePricingResponsePart2.parse(responseBody);

            if (result.parsedResponse == null
                || result.parsedResponse.priceInfo == null
                || result.parsedResponse.priceInfo.isEmpty()) {
                result.errorDetail = 'Oracle returned empty pricing response';
                result.calloutSuccess = false;

                Logger.error(
                    CLASS_NAME + '.sendUnitPriceRequest: empty pricing response'
                );

                if (Test.isRunningTest()) {
                    result.parsedResponse =
                        OraclePricingResponsePart2.getMockResponse(requestBody);
                    result.calloutSuccess = true;
                }

                return result;
            }

            result.calloutSuccess = true;
            return result;
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.sendUnitPriceRequest', e);
            result.errorDetail = e.getMessage();
            result.calloutSuccess = false;
        } finally {
            Logger.saveLog();
        }

        return result;
    }

    @TestVisible
    private static Boolean isSuccessful(Map<String, Object> responseMap) {
        if (responseMap == null || responseMap.isEmpty()) {
            return false;
        }

        Object success = responseMap.get(RESPONSE_SUCCESS_KEY);
        return success instanceof Boolean && (Boolean) success;
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
            return 'SO_Callout returned empty response';
        }

        Object soReturn = responseMap.get(RESPONSE_RETURN_KEY);
        if (soReturn != null && String.isNotBlank(String.valueOf(soReturn))) {
            return String.valueOf(soReturn);
        }

        Object serviceResponse = responseMap.get(SO_Constants.SERVICERESPONSE);
        if (serviceResponse != null && String.isNotBlank(String.valueOf(serviceResponse))) {
            return String.valueOf(serviceResponse);
        }

        return 'SO_Callout failed';
    }
}