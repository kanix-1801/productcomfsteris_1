/**
 * @description GW-580: Sends a Product Request to Digital Parts Catalog through Boomi (ShoutOut).
 *              Body keys: CustomerPO, ProductRequestNum, AddressID, SerialNum, PMCLVersionNum.
 *              CustomerPO is ProductRequest.PONumber__c, or WorkOrder.CustomerPO__c when the PR PO is blank.
 *              AddressID is sent as null; Product Request has no Address source.
 *              GW-5262: After DPC accepts the call, sets DPCOrderNumber__c to the Product Request number.
 *              Does not create lines and does not stamp the Oracle submit fields.
 */
public with sharing class ProductRequestsDpcService {

    private static final String CALLOUT_OPERATION = 'DPC_GETPRODUCTINSTANCE_DEV';

    /** Optional ShoutOut response override for unit tests. Null uses the default success mock. */
    @TestVisible
    private static Map<String, Object> testResponseOverride;

    /**
     * @description Invocable input for Screen Flow ProductRequest_SCR_OpenDPC.
     */
    public class DpcLaunchRequest {
        @InvocableVariable(required=true label='Product Request Id')
        public Id productRequestId;
    }

    /**
     * @description Invocable output returned to the calling flow.
     */
    public class DpcLaunchResult {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Catalog URL')
        public String catalogUrl;
        public String requestJson;
    }

    /**
     * @description DPC request body. Field order is the order Boomi expects.
     */
    @TestVisible
    private class DpcRequestBody {
        public String CustomerPO;
        public String ProductRequestNum;
        public String AddressID;
        public String SerialNum;
        public String PMCLVersionNum;
    }

    /**
     * @description Builds the DPC payload and calls ShoutOut. Returns the catalog URL on success.
     * @param requests Product Request launch requests from Flow.
     * @return One result per request.
     */
    @InvocableMethod(
        label='Product Request - Open DPC'
        description='GW-580: Sends CustomerPO, ProductRequestNum, AddressID, SerialNum, and PMCLVersionNum to DPC through ShoutOut.'
    )
    public static List<DpcLaunchResult> openDpc(List<DpcLaunchRequest> requests) {
        List<DpcLaunchResult> results = new List<DpcLaunchResult>();
        if (requests == null) {
            return results;
        }
        List<ProductRequest> toStamp = new List<ProductRequest>();
        for (DpcLaunchRequest req : requests) {
            results.add(launch(req, toStamp));
        }
        stampDpcOrderNumbers(toStamp);
        return results;
    }

    /**
     * @description GW-5262: Sets DPCOrderNumber__c to the Product Request number so Boomi can add DPC lines
     *              by external ID. Runs after all callouts. A failed save does not block the DPC launch.
     * @param toStamp Product Requests that DPC accepted and that have no DPC Order Number yet.
     */
    private static void stampDpcOrderNumbers(List<ProductRequest> toStamp) {
        if (toStamp.isEmpty()) {
            return;
        }
        List<Database.SaveResult> saves = Database.update(toStamp, false, AccessLevel.SYSTEM_MODE);
        for (Database.SaveResult save : saves) {
            if (!save.isSuccess()) {
                System.debug(LoggingLevel.WARN, 'GW-5262 DPC Order Number not saved: ' + save.getErrors());
            }
        }
    }

    /**
     * @description Validates one Product Request, builds the five-key body, and calls ShoutOut.
     * @param req Product Request launch request.
     * @param toStamp Collects Product Requests that need a DPC Order Number after a successful call.
     * @return Launch result for Flow.
     */
    @TestVisible
    private static DpcLaunchResult launch(DpcLaunchRequest req, List<ProductRequest> toStamp) {
        DpcLaunchResult result = new DpcLaunchResult();
        result.success = false;
        if (req == null || req.productRequestId == null) {
            result.message = 'Product Request is required to open DPC.';
            return result;
        }

        List<ProductRequest> rows = ProductRequestsSelector.selectForDpcLaunch(
            new Set<Id>{ req.productRequestId }
        );
        if (rows.isEmpty()) {
            result.message = 'Product Request was not found.';
            return result;
        }

        ProductRequest pr = rows[0];
        String blockMessage = validateLaunch(pr);
        if (blockMessage != null) {
            result.message = blockMessage;
            return result;
        }

        DpcRequestBody body = new DpcRequestBody();
        body.CustomerPO = resolveCustomerPo(pr);
        body.ProductRequestNum = pr.ProductRequestNumber;
        body.SerialNum = pr.WorkOrder.Asset.SerialNumber;
        body.PMCLVersionNum = toPmclVersion(pr.WorkOrder.Asset.PFCL__c);
        String restBody = JSON.serialize(body);
        result.requestJson = restBody;

        Map<String, Object> responseMap;
        if (Test.isRunningTest()) {
            responseMap = testResponseOverride != null
                ? testResponseOverride
                : new Map<String, Object>{
                      'SO_SUCCESS' => true,
                      'SERVICE_DATA' => new Map<String, Object>{
                          'clientURL' => new Map<String, Object>{
                              'key' => 'clientURL',
                              'value' => 'https://dpc.example/topics/IS?filterId=1'
                          }
                      }
                  };
        } else {
            SO_Callout callout = new SO_Callout();
            callout
                .addToRequestMap(SO_Constants.CALLOUTOPERATION, CALLOUT_OPERATION)
                .addToRequestMap(SO_Constants.SERVICETIMEOUT, '60000')
                .addToRequestMap(SO_Constants.RESTBODY, restBody);
            callout.callWebService();
            responseMap = callout.serviceResponseMap;
        }

        applyResponse(result, responseMap);
        if (result.success && String.isBlank(pr.DPCOrderNumber__c)) {
            toStamp.add(new ProductRequest(Id = pr.Id, DPCOrderNumber__c = pr.ProductRequestNumber));
        }
        return result;
    }

    /**
     * @description Stops the launch when a required DPC key source is missing.
     * @param pr Product Request loaded for the launch.
     * @return Block message, or null when the payload can be built.
     */
    private static String validateLaunch(ProductRequest pr) {
        if (pr.WorkOrderId == null) {
            return 'Work Order is required to open DPC.';
        }
        if (pr.WorkOrder.AssetId == null) {
            return 'Asset is required to open DPC.';
        }
        if (String.isBlank(pr.WorkOrder.Asset.PFCL__c)) {
            return 'Asset PFCL is required to open DPC.';
        }
        if (String.isBlank(pr.WorkOrder.Asset.SerialNumber)) {
            return 'Asset serial number is required to open DPC.';
        }
        return null;
    }

    /**
     * @description Uses the Product Request PO when it is populated; otherwise the Work Order Customer PO.
     * @param pr Product Request loaded for the launch.
     * @return CustomerPO for DPC, or null when both sources are blank.
     */
    private static String resolveCustomerPo(ProductRequest pr) {
        if (String.isNotBlank(pr.PONumber__c)) {
            return pr.PONumber__c.trim();
        }
        if (pr.WorkOrder != null && String.isNotBlank(pr.WorkOrder.CustomerPO__c)) {
            return pr.WorkOrder.CustomerPO__c.trim();
        }
        return null;
    }

    /**
     * @description Converts PFCL slash format to the DPC dash format.
     * @param pfcl Asset PFCL value.
     * @return PMCL version number.
     */
    private static String toPmclVersion(String pfcl) {
        return pfcl == null ? null : pfcl.trim().replace('/', '-');
    }

    /**
     * @description Reads the catalog URL from the ShoutOut response. Does not open a blank catalog.
     * @param result Result being populated.
     * @param responseMap ShoutOut response map.
     * @return Updated result.
     */
    private static DpcLaunchResult applyResponse(DpcLaunchResult result, Map<String, Object> responseMap) {
        Boolean soSuccess = responseMap != null && responseMap.get('SO_SUCCESS') == true;
        Object serviceData = responseMap == null ? null : responseMap.get('SERVICE_DATA');
        if (serviceData == null && responseMap != null) {
            serviceData = responseMap.get('SO_RETURN');
        }
        Map<String, Object> data = coerceMap(serviceData);
        String url = extractUrl(data);
        if (url == null && data == null && serviceData instanceof String) {
            url = ((String) serviceData).trim().removeStart('"').removeEnd('"').trim();
        }
        Boolean dpcRejected = data != null && isFalse(data.get('success'));

        if (!dpcRejected && isHttpUrl(url)) {
            result.success = true;
            result.catalogUrl = url;
            result.message = 'DPC catalog is ready.';
            return result;
        }
        if (soSuccess && !dpcRejected && String.isNotBlank(url)) {
            result.success = false;
            result.catalogUrl = null;
            result.message =
                'Boomi returned a catalog path, not a full URL. Ask DPC for the site host to put in front of: ' +
                url;
            return result;
        }

        result.success = false;
        result.catalogUrl = null;
        result.message = extractMessage(data, serviceData, soSuccess);
        return result;
    }

    private static Boolean isHttpUrl(String url) {
        if (String.isBlank(url)) {
            return false;
        }
        String value = url.trim().toLowerCase();
        return value.startsWith('https://') || value.startsWith('http://');
    }

    private static Boolean isFalse(Object value) {
        return value == false || (value instanceof String && ((String) value).equalsIgnoreCase('false'));
    }

    private static Object firstValue(Map<String, Object> data, List<String> keys) {
        if (data == null) {
            return null;
        }
        for (String key : keys) {
            if (data.containsKey(key) && data.get(key) != null) {
                return data.get(key);
            }
        }
        return null;
    }

    private static String extractUrl(Map<String, Object> data) {
        if (data == null) {
            return null;
        }
        Object clientUrl = firstValue(data, new List<String>{ 'clientURL', 'clientUrl', 'ClientURL' });
        Map<String, Object> clientUrlMap = coerceMap(clientUrl);
        if (clientUrlMap != null) {
            Object nested = firstValue(clientUrlMap, new List<String>{ 'value', 'Value' });
            if (nested != null && String.isNotBlank(String.valueOf(nested))) {
                return String.valueOf(nested).trim();
            }
        }
        if (clientUrl instanceof String && String.isNotBlank((String) clientUrl)) {
            return ((String) clientUrl).trim();
        }
        for (String key : new List<String>{ 'url', 'Url', 'URL', 'catalogUrl', 'CatalogUrl' }) {
            if (data.containsKey(key) && data.get(key) != null && String.isNotBlank(String.valueOf(data.get(key)))) {
                return String.valueOf(data.get(key)).trim();
            }
        }
        return null;
    }

    private static String extractMessage(Map<String, Object> data, Object serviceData, Boolean soSuccess) {
        if (data != null) {
            for (String key : new List<String>{ 'message', 'Message', 'error', 'Error', 'errorMessage' }) {
                if (data.containsKey(key) && data.get(key) != null && String.isNotBlank(String.valueOf(data.get(key)))) {
                    return String.valueOf(data.get(key)).trim();
                }
            }
        }
        if (serviceData instanceof String && String.isNotBlank((String) serviceData)) {
            return ((String) serviceData).trim();
        }
        if (!soSuccess) {
            return 'DPC call failed.';
        }
        return 'DPC did not return a catalog URL.';
    }

    private static Map<String, Object> coerceMap(Object serviceData) {
        if (serviceData instanceof Map<String, Object>) {
            return (Map<String, Object>) serviceData;
        }
        if (serviceData instanceof String && String.isNotBlank((String) serviceData)) {
            try {
                Object parsed = JSON.deserializeUntyped((String) serviceData);
                if (parsed instanceof Map<String, Object>) {
                    return (Map<String, Object>) parsed;
                }
            } catch (Exception ignore) {
                return null;
            }
        }
        return null;
    }
}