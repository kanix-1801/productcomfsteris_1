/**
 * @description Service-layer orchestration for FedEx inbound shipping-label generation (GW-2793).
 *              Builds Shout Out request payloads, invokes the Boomi FedEx operation, and
 *              returns tracking number / label data for Return Order persistence.
 * @author Uptima Development Team
 * @date 2026-08-23
 * @group Services
 * @see VendorFedExShipmentService for vendor/outbound FedEx orchestration
 */
public with sharing class FedExService {
    /** Default FedEx service type when no active Carrier Service level preference exists. */
    @TestVisible
    private static final String DEFAULT_SHIPPING_METHOD = 'FEDEX PRIORITY OVERNIGHT';

    /** Shout Out callout operation developer name for inbound FedEx label generation. */
    @TestVisible
    private static final String CALLOUT_OPERATION_FEDEX_LABEL = 'FEDEX_LABEL';

    /**
     * Test seam: inject a Shout Out-shaped response map so unit tests cover parse/error paths
     * without calling SO_Callout / HTTP. Null means production callout (or live SO_Callout in tests).
     */
    @TestVisible
    private static Map<String, Object> testCalloutResponseMap;

    /**
     * @description Shout Out payload: tracking number plus shipping-label PDF bytes.
     */
    public class TrackingResponseDTO {
        public String trackingNumber;
        public Blob shippingLabel;
    }

    /**
     * @description Resolves the FedEx shipping method for an Account from the active IMS
     *              Customer Preference (Preference Type = Carrier Service level). Falls back to
     *              FEDEX PRIORITY OVERNIGHT when none is found.
     * @param accountId Account Id used to look up the preference
     * @return PreferenceValue__c when present; otherwise FEDEX PRIORITY OVERNIGHT
     */
    public static String getShippingMethod(Id accountId) {
        String carrierServiceLevel = CustomerPreferencesService.getCarrierServiceLevel(accountId);
        return String.isBlank(carrierServiceLevel)
            ? DEFAULT_SHIPPING_METHOD
            : carrierServiceLevel;
    }

    /**
     * @description GW-2793 - Invokes Shout Out FEDEX_LABEL with the given REST body and returns
     *              the tracking number and shipping-label PDF bytes.
     * @param restBody JSON request body for SO_Constants.RESTBODY
     * @return Tracking number and shipping-label blob
     * @throws FedExServiceException when restBody is blank, the call fails, or tracking is missing
     */
    public static TrackingResponseDTO requestShippingLabel(String restBody) {
        if (String.isBlank(restBody)) {
            throw new FedExServiceException('FedEx shipping-label request body is required.');
        }

        Logger.setScenario('FedEx Inbound Label');
        Map<String, Object> serviceResponseMap;
        String jsonPayload;
        try {
            if (Test.isRunningTest() && testCalloutResponseMap != null) {
                serviceResponseMap = testCalloutResponseMap;
            } else {
                SO_Callout callout = new SO_Callout();
                callout
                    .addToRequestMap(SO_Constants.CALLOUTOPERATION, CALLOUT_OPERATION_FEDEX_LABEL)
                    .addToRequestMap(SO_Constants.RESTBODY, restBody);
                callout.callWebService();
                serviceResponseMap = callout.serviceResponseMap;
            }

            Boolean success = (Boolean) serviceResponseMap.get('SO_SUCCESS');
            Object serviceData = serviceResponseMap.get('SERVICE_DATA');
            jsonPayload = serviceDataToJson(serviceData);

            if (success == false) {
                throw new FedExServiceException(
                    'FedEx shipping-label call failed: ' +
                    formatCalloutFailure(serviceResponseMap, jsonPayload)
                );
            }

            if (serviceData == null) {
                throw new FedExServiceException(
                    'FedEx shipping-label call returned no SERVICE_DATA.'
                );
            }

            TrackingResponseDTO response = (TrackingResponseDTO) JSON.deserialize(
                jsonPayload,
                TrackingResponseDTO.class
            );
            if (response == null || String.isBlank(response.trackingNumber)) {
                String serviceErrors = extractErrorMessages(jsonPayload);
                throw new FedExServiceException(
                    'FedEx shipping-label call did not return a tracking number.' +
                    (String.isBlank(serviceErrors) ? '' : ' ' + serviceErrors)
                );
            }
            return response;
        } catch (Exception e) {
            logFailedShippingLabelCall(restBody, serviceResponseMap, jsonPayload, e);
            Logger.error(
                new LogMessage(
                    'FedExService.requestShippingLabel failed: {0}',
                    e.getMessage()
                ),
                e
            );
            if (e instanceof FedExServiceException) {
                throw e;
            }
            throw new FedExServiceException(
                'An unexpected error occurred while requesting a FedEx shipping label.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Test helper: builds a successful SO-shaped response map for injection.
     * @param trackingNumber Tracking number returned to callers
     * @param shippingLabel Optional label bytes (base64-encoded into SERVICE_DATA)
     */
    @TestVisible
    private static Map<String, Object> buildTestSuccessResponse(
        String trackingNumber,
        Blob shippingLabel
    ) {
        Map<String, Object> serviceData = new Map<String, Object>{
            'trackingNumber' => trackingNumber
        };
        if (shippingLabel != null) {
            serviceData.put('shippingLabel', EncodingUtil.base64Encode(shippingLabel));
        }
        return new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => serviceData
        };
    }

    /**
     * @description Temporary diagnostic for failed FEDEX_LABEL calls. Logs the outbound JSON
     *              and Boomi response without the shipping-label PDF.
     * @param restBody Outbound FEDEX_LABEL JSON
     * @param serviceResponseMap Shout Out response map, when the callout returned one
     * @param jsonPayload SERVICE_DATA as JSON, when present
     * @param failure Exception about to be returned to the caller
     */
    private static void logFailedShippingLabelCall(
        String restBody,
        Map<String, Object> serviceResponseMap,
        String jsonPayload,
        Exception failure
    ) {
        try {
            Object success = serviceResponseMap == null
                ? null
                : serviceResponseMap.get('SO_SUCCESS');
            Object status = serviceResponseMap == null
                ? null
                : serviceResponseMap.get('SERVICE_STATUS');
            Object soReturn = serviceResponseMap == null
                ? null
                : serviceResponseMap.get('SO_RETURN');
            Logger.error(
                'FedExService.requestShippingLabel diagnostic. transactionId=' +
                Logger.getTransactionId() +
                ' requestId=' + currentRequestId() +
                ' success=' + success +
                ' status=' + status +
                ' soReturn=' + soReturn +
                ' request=' + sanitizeFedExPayload(restBody) +
                ' serviceData=' + sanitizeFedExPayload(jsonPayload) +
                ' error=' + (failure == null ? '' : failure.getMessage()),
                failure
            );
        } catch (Exception logFailure) {
            Logger.error(
                'FedExService.requestShippingLabel diagnostic log failed: ' +
                logFailure.getMessage(),
                logFailure
            );
        }
    }

    /**
     * @description Removes shippingLabel and caps length so a failed call can be logged.
     * @param payload JSON request or SERVICE_DATA
     * @return Payload safe to store on a log entry
     */
    @TestVisible
    private static String sanitizeFedExPayload(String payload) {
        if (String.isBlank(payload)) {
            return payload;
        }
        String sanitized = payload;
        try {
            Object parsed = JSON.deserializeUntyped(payload);
            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> values = (Map<String, Object>) parsed;
                List<String> labelKeys = new List<String>();
                for (String key : values.keySet()) {
                    if (key != null && key.equalsIgnoreCase('shippingLabel')) {
                        labelKeys.add(key);
                    }
                }
                for (String key : labelKeys) {
                    values.remove(key);
                }
                sanitized = JSON.serialize(values);
            }
        } catch (Exception ignored) {
            sanitized = payload;
        }
        return truncateForLog(sanitized);
    }

    private static String currentRequestId() {
        try {
            Request currentRequest = Request.getCurrent();
            return currentRequest == null ? null : currentRequest.getRequestId();
        } catch (Exception ignored) {
            return null;
        }
    }

    private static String truncateForLog(String value) {
        Integer maxLength = 12000;
        if (value == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength) + '...[truncated]';
    }

    @TestVisible
    private static String serviceDataToJson(Object serviceData) {
        if (serviceData == null) {
            return null;
        }
        return serviceData instanceof String
            ? (String) serviceData
            : JSON.serialize(serviceData);
    }

    @TestVisible
    private static String formatCalloutFailure(
        Map<String, Object> responseMap,
        String jsonPayload
    ) {
        List<String> parts = new List<String>();
        if (responseMap != null) {
            Object status = responseMap.get('SERVICE_STATUS');
            if (status != null && String.isNotBlank(String.valueOf(status))) {
                parts.add('HTTP ' + String.valueOf(status));
            }
            Object soReturn = responseMap.get('SO_RETURN');
            if (soReturn != null) {
                String returnText = String.valueOf(soReturn);
                if (String.isNotBlank(returnText) && returnText != 'null') {
                    parts.add(returnText);
                }
            }
        }
        String serviceErrors = extractErrorMessages(jsonPayload);
        if (String.isNotBlank(serviceErrors)) {
            parts.add(serviceErrors);
        }
        return parts.isEmpty() ? 'unknown error' : String.join(parts, ' - ');
    }

    @TestVisible
    private static String extractErrorMessages(String jsonPayload) {
        if (String.isBlank(jsonPayload)) {
            return null;
        }
        try {
            Object parsed = JSON.deserializeUntyped(jsonPayload);
            if (!(parsed instanceof Map<String, Object>)) {
                return null;
            }
            Object errorsObj = ((Map<String, Object>) parsed).get('errors');
            if (!(errorsObj instanceof List<Object>)) {
                return null;
            }
            List<String> messages = new List<String>();
            for (Object errorObj : (List<Object>) errorsObj) {
                if (!(errorObj instanceof Map<String, Object>)) {
                    continue;
                }
                Object message = ((Map<String, Object>) errorObj).get('errorMessage');
                if (message != null && String.isNotBlank(String.valueOf(message))) {
                    messages.add(String.valueOf(message).trim().removeEnd(',').trim());
                }
            }
            return messages.isEmpty() ? null : String.join(messages, '; ');
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Business exception for FedEx inbound label / tracking operations.
     */
    public class FedExServiceException extends Exception {
    }
}