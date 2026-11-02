/**
 * Shared SO_Callout gateway for Prospect Account and Lead TAS assignment.
 *
 * @author Akash Dahinde
 * @date 12-06-2026
 * @description Integration gateway for Account and Lead TAS assignment callouts.
 *              Delegates HTTP to the SO_Callout framework (ShoutOut / SO_ProviderFactory).
 *              No SOQL/DML — callouts only.
 *
 * SO framework flow:
 *   TasAssignmentGateway
 *     -> SO_Callout.addToRequestMap(SO_Constants.CALLOUTOPERATION, CMDT name)
 *     -> SO_Callout.addToRequestMap(SO_Constants.RESTBODY, JSON body)
 *     -> SO_Callout.callWebService()
 *     -> SO_ProviderFactory.getInstance(requestMap)
 *     -> Provider (from ShoutOut_Service_Setting__mdt) -> Named Credential -> Boomi TAS
 *     -> serviceResponseMap (SO_SUCCESS, SO_RETURN, SERVICERESPONSE)
 *
 * CMDT: ShoutOut_Service_Setting__mdt Developer Name = SF_PROSPECT_TAS
 */
public with sharing class TasAssignmentGateway {

    private static final String CLASS_NAME = 'TasAssignmentGateway';
    private static final String TAS_SERVICE_SETTING_NAME = 'SF_PROSPECT_TAS';
    private static final String RESPONSE_SUCCESS_KEY = 'SO_SUCCESS';
    private static final String RESPONSE_RETURN_KEY = 'SO_RETURN';
    private static final String EMPTY_STRING = '';
    private static final String UNKNOWN_RECORD_ID = 'unknown';

    /**
     * Result wrapper returned to the service layer after SO_Callout execution.
     */
    public class CalloutResult {
        /** @description True when the TAS callout succeeded and the response was parsed. */
        public Boolean calloutSuccess { get; set; }
        /** @description Parsed TAS response body, when available. */
        public TasAssignmentResponse parsedResponse { get; set; }
        /** @description Error detail when the callout or parse fails. */
        public String errorDetail { get; set; }
        /** @description Raw SO framework response map from SO_Callout. */
        public Map<String, Object> serviceResponseMap { get; set; }
        /** @description True when SO framework enqueued a retry for this callout. */
        public Boolean retryEnqueued { get; set; }

        /**
         * @description Initializes calloutSuccess and retryEnqueued to false.
         */
        public CalloutResult() {
            this.calloutSuccess = false;
            this.retryEnqueued = false;
        } 
    }

    /**
     * @description Invokes TAS via SO_Callout for one assignment request.
     * @param requestBody DTO serialized as SO_Constants.RESTBODY
     * @return CalloutResult with parsed response and SO framework response map
     */
    public static CalloutResult sendAssignmentRequest(TasAssignmentRequest requestBody) {
        CalloutResult result = new CalloutResult();

        try {
            if (requestBody == null) {
                result.errorDetail = 'Request body is null';
                Logger.warn(CLASS_NAME + '.sendAssignmentRequest: request body is null');
                return result;
            }

            String recordId = resolveRecordIdForLog(requestBody);
            Logger.info(
                CLASS_NAME + '.sendAssignmentRequest: started recordId=' + recordId
            );

            String requestJson = JSON.serialize(requestBody.toJsonMap());
            Logger.info(
                CLASS_NAME + '.sendAssignmentRequest: request recordId=' +
                recordId +
                ', body=' +
                requestJson
            );

            SO_Callout callout = new SO_Callout();
            callout
                .addToRequestMap(SO_Constants.CALLOUTOPERATION, TAS_SERVICE_SETTING_NAME)
                .addToRequestMap(SO_Constants.RESTBODY, requestJson);

            Map<String, Object> responseMap = callout.callWebService();
            result.serviceResponseMap = responseMap;

            Object retryEnqueued = responseMap != null
                ? responseMap.get(SO_Constants.RETRY_ENQUEUED)
                : null;
            result.retryEnqueued = retryEnqueued instanceof Boolean && (Boolean) retryEnqueued;

            if (result.retryEnqueued) {
                Logger.warn(
                    CLASS_NAME + '.sendAssignmentRequest: SO retry enqueued recordId=' +
                    recordId
                );
            }

            String responseBody = extractResponseBody(responseMap);
            Logger.info(
                CLASS_NAME + '.sendAssignmentRequest: response recordId=' +
                recordId +
                ', body=' +
                (String.isBlank(responseBody) ? EMPTY_STRING : responseBody)
            );

            if (!isSuccessful(responseMap)) {
                result.errorDetail = extractErrorDetail(responseMap);
                Logger.debug(
                    CLASS_NAME + '.sendAssignmentRequest: callout failed recordId=' +
                    recordId +
                    ', detail=' +
                    result.errorDetail
                );
                return result;
            }

            if (String.isBlank(responseBody)) {
                result.calloutSuccess = true;
                result.parsedResponse = new TasAssignmentResponse();
                result.parsedResponse.territoryData = new List<TasTerritoryItem>();
                return result;
            }

            result.parsedResponse = TasAssignmentResponse.parse(responseBody);
            result.calloutSuccess = result.parsedResponse != null;

            if (!result.calloutSuccess) {
                result.errorDetail = 'TAS response body was empty or could not be parsed';
                Logger.debug(
                    CLASS_NAME + '.sendAssignmentRequest: response parse failed recordId=' +
                    recordId +
                    ', detail=' +
                    result.errorDetail
                );
                return result;
            }

            Integer territoryCount = result.parsedResponse.territoryData == null
                ? 0
                : result.parsedResponse.territoryData.size();
            Logger.info(
                CLASS_NAME + '.sendAssignmentRequest: completed recordId=' +
                recordId +
                ', territoryCount=' +
                territoryCount
            );
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.sendAssignmentRequest', e);
            result.errorDetail = e.getMessage();
        }

        return result;
    }

    /**
     * @description Returns true when SO_SUCCESS is a Boolean true in the response map.
     * @param responseMap SO framework response map from SO_Callout.
     * @return True when the callout is marked successful; otherwise false.
     */
    @TestVisible
    private static Boolean isSuccessful(Map<String, Object> responseMap) {
        Boolean successful = false;

        if (responseMap != null && !responseMap.isEmpty()) {
            Object successFlag = responseMap.get(RESPONSE_SUCCESS_KEY);
            successful = successFlag instanceof Boolean && (Boolean) successFlag;
        }

        return successful;
    }

    /**
     * @description Reads the TAS response body from SERVICE_DATA or SERVICERESPONSE.
     * @param responseMap SO framework response map from SO_Callout.
     * @return Response body string, or blank when missing.
     */
    @TestVisible
    private static String extractResponseBody(Map<String, Object> responseMap) {
        String responseBody = EMPTY_STRING;

        if (responseMap == null || responseMap.isEmpty()) {
            return responseBody;
        }

        Object payload = responseMap.get('SERVICE_DATA');

        if (payload == null) {
            payload = responseMap.get(SO_Constants.SERVICERESPONSE);
        }

        if (payload != null) {
            if (payload instanceof String) {
                String body = (String) payload;
                if (String.isNotBlank(body)) {
                    responseBody = body;
                }
            } else {
                responseBody = JSON.serialize(payload);
            }
        }

        return responseBody;
    }

    /**
     * @description Builds a readable error message from the SO framework response map.
     * @param responseMap SO framework response map from SO_Callout.
     * @return Error detail string for logging and CalloutResult.
     */
    @TestVisible
    private static String extractErrorDetail(Map<String, Object> responseMap) {
        String errorDetail = 'SO_Callout failed with SO_SUCCESS=false';

        if (responseMap == null || responseMap.isEmpty()) {
            errorDetail = 'SO_Callout returned an empty response map';
        } else {
            Object soReturn = responseMap.get(RESPONSE_RETURN_KEY);
            if (soReturn != null && String.isNotBlank(String.valueOf(soReturn))) {
                errorDetail = String.valueOf(soReturn);
            } else {
                Object serviceResponse = responseMap.get(SO_Constants.SERVICERESPONSE);
                if (serviceResponse != null && String.isNotBlank(String.valueOf(serviceResponse))) {
                    errorDetail = String.valueOf(serviceResponse);
                }
            }
        }

        return errorDetail;
    }

    /**
     * @description Resolves prospectId or leadId for gateway log messages.
     * @param requestBody TAS assignment request DTO.
     * @return Record Id used in logs, or unknown when neither Id is present.
     */
    @TestVisible
    private static String resolveRecordIdForLog(TasAssignmentRequest requestBody) {
        String recordId = UNKNOWN_RECORD_ID;

        if (requestBody != null) {
            if (String.isNotBlank(requestBody.prospectId)) {
                recordId = requestBody.prospectId;
            } else if (String.isNotBlank(requestBody.leadId)) {
                //GC-3279 - START
                recordId = requestBody.leadId;
                //GC-3279-END
            }
        }

        return recordId;
    }
}