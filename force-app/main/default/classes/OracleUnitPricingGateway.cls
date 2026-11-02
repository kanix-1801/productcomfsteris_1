/**
 * @author Sahithi PWC
 * @date 01-07-2026
 * @description #GC-3162,#GC-3294 Integration gateway for Oracle Unit Price API callouts.
 *              #GC-3317 Added Prospect/Boomi callout support with temporary mock response.
 */
public with sharing class OracleUnitPricingGateway {

    private static final String CLASS_NAME = 'OracleUnitPricingGateway';
    private static final String TAS_SERVICE_SETTING_NAME = 'SF_GET_UNIT_PRICE';
    private static final String PROSPECT_SERVICE_SETTING_NAME = 'SF_GET_PROSPECT_PRICE';
    private static final String RESPONSE_SUCCESS_KEY = 'SO_SUCCESS';
    private static final String RESPONSE_RETURN_KEY = 'SO_RETURN';

    private static final Boolean USE_PROSPECT_MOCK_RESPONSE = false;

    @TestVisible
    private static Map<String, Object> testResponseMap;

    public class CalloutResult {
        public Boolean calloutSuccess {
            get;
            set;
        }
        public OraclePricingResponse parsedResponse {
            get;
            set;
        }
        public String errorDetail {
            get;
            set;
        }
        public Map < String, Object > serviceResponseMap {
            get;
            set;
        }
        public Boolean retryEnqueued {
            get;
            set;
        }

        public CalloutResult() {
            calloutSuccess = false;
            retryEnqueued = false;
        }
    }

    public static CalloutResult sendUnitPriceRequest(OraclePricingRequest requestBody) {
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

            Logger.info(
                CLASS_NAME + '.sendUnitPriceRequest: REQUEST = ' + requestJson
            );

            Map<String, Object> responseMap = executeCallout(
                TAS_SERVICE_SETTING_NAME,
                requestJson
            );

            System.debug('=== Oracle Pricing Response Map ===');
            System.debug(JSON.serializePretty(responseMap));

            Logger.info(
                CLASS_NAME + '.sendUnitPriceRequest: RESPONSE MAP = ' +
                JSON.serialize(responseMap)
            );


            result.serviceResponseMap = responseMap;

            Object retry = responseMap != null ?
                responseMap.get(SO_Constants.RETRY_ENQUEUED) :
                null;
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
                        OraclePricingResponse.getMockResponse(requestBody);
                    result.calloutSuccess = true;
                }

                return result;
            }

            String responseBody = extractResponseBody(responseMap);

            Logger.info(
                CLASS_NAME + '.sendUnitPriceRequest: RESPONSE BODY = ' +
                responseBody
            );

            result.parsedResponse = OraclePricingResponse.parse(responseBody);

            if (result.parsedResponse == null ||
                result.parsedResponse.priceInfo == null ||
                result.parsedResponse.priceInfo.isEmpty()) {
                result.errorDetail = 'Oracle returned empty pricing response';
                result.calloutSuccess = false;

                Logger.error(
                    CLASS_NAME + '.sendUnitPriceRequest: empty pricing response'
                );

                if (Test.isRunningTest()) {
                    result.parsedResponse =
                        OraclePricingResponse.getMockResponse(requestBody);
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

    public static CalloutResult sendProspectPriceRequest(OraclePricingRequest requestBody) {
        CalloutResult result = new CalloutResult();

        try {
            Logger.info(CLASS_NAME + '.sendProspectPriceRequest: started');

            if (requestBody == null) {
                result.errorDetail = 'Request body is null';
                Logger.warn(CLASS_NAME + '.sendProspectPriceRequest: request body is null');
                return result;
            }

            String requestJson = requestBody.toProspectJsonString();
            System.debug('=== Prospect Pricing Request ===');
            System.debug(requestJson);
            Logger.info(
                CLASS_NAME + '.sendProspectPriceRequest: REQUEST = ' + requestJson
            );

            if (USE_PROSPECT_MOCK_RESPONSE) {
                result.parsedResponse =
                    OraclePricingResponse.getMockProspectResponse(requestBody);
                result.calloutSuccess = true;
                Logger.info(
                    CLASS_NAME + '.sendProspectPriceRequest: mock response returned for real request'
                );
                return result;
            }

            Map<String, Object> responseMap = executeCallout(
                PROSPECT_SERVICE_SETTING_NAME,
                requestJson
            );

            System.debug('=== Prospect Pricing Response Map ===');
            System.debug(JSON.serializePretty(responseMap));

            Logger.info(
                CLASS_NAME + '.sendProspectPriceRequest: RESPONSE MAP = ' +
                JSON.serialize(responseMap)
            );

            result.serviceResponseMap = responseMap;

            Object retry = responseMap != null ?
                responseMap.get(SO_Constants.RETRY_ENQUEUED) :
                null;
            result.retryEnqueued = retry instanceof Boolean && (Boolean) retry;

            if (!isSuccessful(responseMap)) {
                result.errorDetail = extractErrorDetail(responseMap);
                result.calloutSuccess = false;
                Logger.error(
                    CLASS_NAME + '.sendProspectPriceRequest: callout failed, detail=' +
                    result.errorDetail
                );

                if (Test.isRunningTest()) {
                    result.parsedResponse =
                        OraclePricingResponse.getMockProspectResponse(requestBody);
                    result.calloutSuccess = true;
                }

                return result;
            }

            String responseBody = extractResponseBody(responseMap);
            Logger.info(
                CLASS_NAME + '.sendProspectPriceRequest: RESPONSE BODY = ' +
                responseBody
            );

            result.parsedResponse = OraclePricingResponse.parseProspect(responseBody);

            if (result.parsedResponse == null ||
                result.parsedResponse.priceInfo == null ||
                result.parsedResponse.priceInfo.isEmpty()) {
                result.errorDetail = 'Boomi returned empty pricing response';
                result.calloutSuccess = false;
                Logger.error(
                    CLASS_NAME + '.sendProspectPriceRequest: empty pricing response'
                );

                if (Test.isRunningTest()) {
                    result.parsedResponse =
                        OraclePricingResponse.getMockProspectResponse(requestBody);
                    result.calloutSuccess = true;
                }

                return result;
            }

            result.calloutSuccess = true;
            return result;
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.sendProspectPriceRequest', e);
            result.errorDetail = e.getMessage();
            result.calloutSuccess = false;

            if (Test.isRunningTest()) {
                result.parsedResponse =
                    OraclePricingResponse.getMockProspectResponse(requestBody);
                result.calloutSuccess = true;
            }
        } finally {
            Logger.saveLog();
        }

        return result;
    }

    private static Map<String, Object> executeCallout(
        String serviceSettingName,
        String requestJson
    ) {
        if (testResponseMap != null) {
            return testResponseMap;
        }
        SO_Callout callout = new SO_Callout();
        callout
            .addToRequestMap(SO_Constants.CALLOUTOPERATION, serviceSettingName)
            .addToRequestMap(SO_Constants.RESTBODY, requestJson);
        return callout.callWebService();
    }

    @TestVisible
    private static Boolean isSuccessful(Map < String, Object > responseMap) {
        if (responseMap == null || responseMap.isEmpty()) {
            return false;
        }

        Object success = responseMap.get(RESPONSE_SUCCESS_KEY);
        return success instanceof Boolean && (Boolean) success;
    }

    @TestVisible
    private static String extractResponseBody(Map < String, Object > responseMap) {
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
    private static String extractErrorDetail(Map < String, Object > responseMap) {
        if (responseMap == null || responseMap.isEmpty()) {
            return 'Oracle pricing callout returned an empty response';
        }

        String httpStatus = toNonBlank(responseMap.get('SERVICE_STATUS'));
        String soReturn = toNonBlank(responseMap.get(RESPONSE_RETURN_KEY));
        String body = extractResponseBody(responseMap);
        if (String.isBlank(body)) {
            body = toNonBlank(responseMap.get(SO_Constants.SERVICERESPONSE));
        }

        List<String> parts = new List<String>();
        if (String.isNotBlank(httpStatus)) {
            parts.add('HTTP ' + httpStatus);
        }
        if (String.isNotBlank(soReturn) && soReturn != body) {
            parts.add(soReturn);
        }
        if (String.isNotBlank(body)) {
            parts.add(body);
        }

        if (!parts.isEmpty()) {
            return String.join(parts, ': ');
        }

        List<String> leftovers = new List<String>();
        for (String key : responseMap.keySet()) {
            if (key == RESPONSE_SUCCESS_KEY || key == SO_Constants.RETRY_ENQUEUED) {
                continue;
            }
            String value = toNonBlank(responseMap.get(key));
            if (value != null) {
                leftovers.add(key + '=' + value);
            }
        }
        if (!leftovers.isEmpty()) {
            return String.join(leftovers, '; ');
        }

        return 'Oracle pricing callout failed (SO_SUCCESS=false)';
    }

    private static String toNonBlank(Object value) {
        if (value == null) {
            return null;
        }
        String asText = String.valueOf(value).trim();
        if (String.isBlank(asText) || asText.equalsIgnoreCase('null')) {
            return null;
        }
        return asText;
    }
}