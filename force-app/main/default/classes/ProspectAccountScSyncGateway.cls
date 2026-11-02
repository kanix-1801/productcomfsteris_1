/**
 * @description GC-3441 / GC-3500 - Gateway that posts Prospect Account updates
 *              to Boomi through ShoutOut SO_Callout using SF_PROSPECT_ACCOUNT_SC_SYNC.
 */
public with sharing class ProspectAccountScSyncGateway {
    private static final String CLASS_NAME = 'ProspectAccountScSyncGateway';
    public static final String SERVICE_SETTING_NAME = 'SF_PROSPECT_ACCOUNT_SC_SYNC';
    private static final String RESPONSE_SUCCESS_KEY = 'SO_SUCCESS';
    private static final String RESPONSE_RETURN_KEY = 'SO_RETURN';

    // GC-3441 - QA unit tests cannot rely on a Named Credential existing for HttpCalloutMock.
    @TestVisible
    static Boolean bypassHttpForTest = false;
    @TestVisible
    static Integer testSendCount = 0;
    @TestVisible
    static String testLastRequestJson;

    public class CalloutResult {
        public Boolean calloutSuccess { get; set; }
        public Boolean retryEnqueued { get; set; }
        public String errorDetail { get; set; }
        public Map<String, Object> serviceResponseMap { get; set; }

        public CalloutResult() {
            calloutSuccess = false;
            retryEnqueued = false;
        }
    }

    /**
     * @description Sends one Prospect Account payload to the configured Boomi/mock endpoint.
     */
    public static CalloutResult sendAccountUpdate(ProspectAccountScSyncRequest requestBody) {
        CalloutResult result = new CalloutResult();

        try {
            if (requestBody == null) {
                result.errorDetail = 'Request body is null';
                return result;
            }

            String requestJson = JSON.serialize(requestBody.toJsonMap());
            testLastRequestJson = requestJson;
            testSendCount++;
            System.debug('=== Prospect Account SC Sync Request ===');
            System.debug(requestJson);
            Logger.info(
                CLASS_NAME + '.sendAccountUpdate: payload=' + requestJson
            ).addTag('GC-3441');

            if (bypassHttpForTest) {
                result.calloutSuccess = true;
                result.serviceResponseMap = new Map<String, Object>{
                    RESPONSE_SUCCESS_KEY => true,
                    'SERVICE_STATUS' => 200,
                    'SERVICE_DATA' => '{"status":"success"}'
                };
                return result;
            }

            SO_Callout callout = new SO_Callout();
            callout
                .addToRequestMap(SO_Constants.CALLOUTOPERATION, SERVICE_SETTING_NAME)
                .addToRequestMap(SO_Constants.RESTBODY, requestJson);

            Map<String, Object> responseMap = callout.callWebService();
            result.serviceResponseMap = responseMap;

            System.debug('=== Prospect Account SC Sync Response Map ===');
            System.debug(JSON.serializePretty(responseMap));
            Logger.info(
                CLASS_NAME + '.sendAccountUpdate: responseMap=' + JSON.serialize(responseMap)
            ).addTag('GC-3441');

            Object retryValue = responseMap == null
                ? null
                : responseMap.get(SO_Constants.RETRY_ENQUEUED);
            result.retryEnqueued = retryValue instanceof Boolean && (Boolean) retryValue;
            result.calloutSuccess = isSuccessful(responseMap);

            if (!result.calloutSuccess) {
                result.errorDetail = extractErrorDetail(responseMap);
                Logger.warn(
                    CLASS_NAME + '.sendAccountUpdate: failed accountId=' +
                    requestBody.accountId + ', detail=' + result.errorDetail
                ).addTag('GC-3441');
            } else {
                Logger.info(
                    CLASS_NAME + '.sendAccountUpdate: completed accountId=' +
                    requestBody.accountId
                ).addTag('GC-3441');
            }
        } catch (Exception exceptionValue) {
            result.errorDetail = exceptionValue.getMessage();
            Logger.error(CLASS_NAME + '.sendAccountUpdate', exceptionValue).addTag('GC-3441');
        }

        return result;
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