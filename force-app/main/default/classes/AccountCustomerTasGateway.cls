/**
 * @author Akash Dahinde
 * @date 07-01-2026
 * @description Integration gateway for Customer Account TAS callouts.
 *              Delegates HTTP to the SO_Callout framework (ShoutOut / SO_ProviderFactory).
 *
 * CMDT: ShoutOut_Service_Setting__mdt Developer Name = SF_CUSTOMER_TAS
 * GC-3021
 *
 * Nebula Logger: callout diagnostics are buffered here and persisted via
 * {@code Logger.saveLog()} in the {@code finally} block of this method.
 */
public with sharing class AccountCustomerTasGateway {

    private static final String CLASS_NAME = 'AccountCustomerTasGateway';
    private static final String TAS_SERVICE_SETTING_NAME = 'SF_CUSTOMER_TAS';
    private static final String RESPONSE_SUCCESS_KEY = 'SO_SUCCESS';
    private static final String RESPONSE_RETURN_KEY = 'SO_RETURN';

    /**
     * @description Result wrapper returned to the service layer after SO_Callout execution.
     */
    public class CalloutResult {
        public Boolean calloutSuccess { get; set; }
        public TasCustomerAccountResponse parsedResponse { get; set; }
        public String errorDetail { get; set; }
        public Map<String, Object> serviceResponseMap { get; set; }
        public Boolean retryEnqueued { get; set; }

        public CalloutResult() {
            this.calloutSuccess = false;
            this.retryEnqueued = false;
        }
    }

    /**
     * @description Invokes TAS via SO_Callout for one customer account request.
     * @param requestBody DTO serialized as SO_Constants.RESTBODY
     * @return CalloutResult with parsed response and SO framework response map
     */
    public static CalloutResult sendCustomerAccountRequest(TasCustomerAccountRequest requestBody) {
        CalloutResult result = new CalloutResult();

        try {
            Logger.info(CLASS_NAME + '.sendCustomerAccountRequest: started');

            if (requestBody == null) {
                result.errorDetail = 'Request body is null';
                Logger.warn(CLASS_NAME + '.sendCustomerAccountRequest: request body is null');
                return result;
            }

            String prospectId = resolveAccountIdForLog(requestBody);
            Logger.info(
                CLASS_NAME + '.sendCustomerAccountRequest: prospectId=' + prospectId
            );

            SO_Callout callout = new SO_Callout();
            callout
                .addToRequestMap(SO_Constants.CALLOUTOPERATION, TAS_SERVICE_SETTING_NAME)
                .addToRequestMap(SO_Constants.RESTBODY, JSON.serialize(requestBody.toJsonMap()));

            Map<String, Object> responseMap = callout.callWebService();
            result.serviceResponseMap = responseMap;

            Object retryEnqueued = responseMap != null
                ? responseMap.get(SO_Constants.RETRY_ENQUEUED)
                : null;
            result.retryEnqueued = retryEnqueued instanceof Boolean && (Boolean) retryEnqueued;

            if (result.retryEnqueued) {
                Logger.warn(
                    CLASS_NAME + '.sendCustomerAccountRequest: SO retry enqueued prospectId=' +
                    prospectId
                );
            }

            if (!isSuccessful(responseMap)) {
                result.errorDetail = extractErrorDetail(responseMap);
                Logger.debug(
                    CLASS_NAME + '.sendCustomerAccountRequest: callout failed prospectId=' +
                    prospectId +
                    ', detail=' +
                    result.errorDetail
                );
                return result;
            }

            String responseBody = extractResponseBody(responseMap);
            result.parsedResponse = TasCustomerAccountResponse.parse(responseBody);
            result.calloutSuccess = result.parsedResponse != null;

            if (!result.calloutSuccess) {
                result.errorDetail = 'TAS response body was empty or could not be parsed';
                Logger.debug(
                    CLASS_NAME + '.sendCustomerAccountRequest: response parse failed prospectId=' +
                    prospectId +
                    ', detail=' +
                    result.errorDetail
                );
                return result;
            }

            Integer territoryCount = result.parsedResponse.territoryData == null
                ? 0
                : result.parsedResponse.territoryData.size();
            Logger.info(
                CLASS_NAME + '.sendCustomerAccountRequest: completed prospectId=' +
                prospectId +
                ', territoryCount=' +
                territoryCount
            );

        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.sendCustomerAccountRequest', e);
            result.errorDetail = e.getMessage();
        } 
        return result;
    }

    @TestVisible
    private static String resolveAccountIdForLog(TasCustomerAccountRequest requestBody) {
        if (requestBody == null) {
            return 'unknown';
        }

        Map<String, Object> payload = requestBody.toJsonMap();
        Object accountIdValue = payload != null ? payload.get('prospectId') : null;

        if (accountIdValue != null && String.isNotBlank(String.valueOf(accountIdValue))) {
            return String.valueOf(accountIdValue);
        }

        Object oracleAddressIdValue = payload != null ? payload.get('oracleAddressId') : null;
        if (oracleAddressIdValue != null && String.isNotBlank(String.valueOf(oracleAddressIdValue))) {
            return 'oracleAddressId=' + String.valueOf(oracleAddressIdValue);
        }

        return 'unknown';
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

        return 'SO_Callout failed with SO_SUCCESS=false';
    }
}