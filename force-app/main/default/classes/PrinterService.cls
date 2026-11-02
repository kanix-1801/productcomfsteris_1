/**
 * @description Generates Zebra bin tags via ShoutOut POST to /Zebra/PrintLabels (GW-4637).
 *              Templates and ZPL encoding live on the STERIS print service; this class merges
 *              Work Order data into the JSON contract and validates the ZPL response size.
 * @group GW-4637
 */
public with sharing class PrinterService {
    private static final String CLASS_NAME = 'PrinterService';
    private static final String CALLOUT_OPERATION = 'STERIS_PRINT_LABEL_ZEBRA_DEV';
    private static final String RESPONSE_SUCCESS_KEY = 'SO_SUCCESS';
    private static final String RESPONSE_RETURN_KEY = 'SO_RETURN';
    // ShoutOut SO_Utils.getTimeout treats SERVICETIMEOUT as seconds (10-120), then converts to ms.
    private static final Integer CALLOUT_TIMEOUT_SECONDS = 60;
    @TestVisible
    private static final String CALLOUT_TIMEOUT_USER_MESSAGE =
        'The print service did not respond in time. Try Print Bin Tag again, or check that the mapped printer is online.';
    private static final String HARDCODED_SALES_REP = 'Call Jared Mauldin';
    @TestVisible
    private static final String PARENT_BIN_TAG_SALES_REP = 'Jared Mauldin';
    @TestVisible
    private static final String PARENT_BIN_TAG_PRINTER_NAME = 'OPSSHIP11L2';
    @TestVisible
    private static final String PARENT_BIN_TAG_PRINTER_IP = '172.21.48.166';
    @TestVisible
    private static final String PARENT_BIN_TAG_PRINTER_MODEL = 'GX420t';
    @TestVisible
    private static final String PARENT_BIN_TAG_PRINT_TEST_FLAG = 'NOTPRINTTESTGO';
    private static final Integer DESCRIPTION_MAX_LENGTH = 120;
    private static final Integer HEAP_SAFETY_BUFFER = 100000;
    private static final String ESTIMATE_REQUIRED = 'Estimate Required';
    private static final String VALUE_QUOTE_REQUIRED = 'Quote Required';
    private static final String VALUE_PRE_APPROVED = 'Pre-Approved';
    private static final String DEVICES_RECORD_TYPE_NAME = 'Repair Center - Devices';
    private static final String DEVICES_RECORD_TYPE_DEV_NAME = 'RepairCenterDevices';
    private static final String ENTITLEMENT_TYPE_CUSTOMER_REPAIR_PRIORITY = 'Customer Repair Priority';
    private static final String VALUE_CASE = 'Case';
    private static final String VALUE_ACCESSORY = 'Accessory';
    private static final String PRINTER_TYPE_TRAVEL_TAG = 'TRAVEL_TAG';
    private static final String PRINTER_TYPE_FEDEX_LABEL = 'FEDEX_LABEL';
    private static final String PRINTER_TYPE_DESKTOP = 'DESKTOP';
    private static final List<String> BIN_TAG_PRINT_FIELDS = new List<String>{
        'Id',
        'WorkOrderNumber',
        'WorkOrderType__c',
        'ProductLine_f__c',
        'ParentWorkOrderId',
        'ParentWorkOrder.WorkOrderNumber',
        'RepairCenter__c',
        'RecordTypeId',
        'ReturnOrderId',
        'ReturnOrder.ReturnOrderNumber',
        'ReturnOrder__c',
        'ReturnOrder__r.ReturnOrderNumber',
        'AssetId',
        'Asset.ProductLineCalculated__c',
        'Asset.Product2.ProductLine__c',
        'Asset.Product2.Description'
    };

    /**
     * @description Thrown when bin tag print cannot be completed.
     */
    public class PrinterServiceException extends Exception {
    }

    /**
     * @description JSON body for POST /Zebra/PrintLabels. Property names match the mock contract.
     */
    public class PrintLabelRequest {
        public Integer Copies;
        public String SalesOrder;
        public String Srn;
        public String SubWorkOrder;
        public String labelDate;
        public String Day;
        public String WorkOrderType;
        public Boolean Priority;
        public String SalesRep;
        public String Description;
        public String User;
        public String PrinterName;
        public String PrinterIpAddr;
        public String PrinterModel;
        public String PrintTestFlag;
        public Boolean isChildTravelTag;
        public String WorkOrderId;
        public String ReceivedDate;
        public String EstimateRequirement;
        public String RepairCategory;
        public Boolean Laps;
        public Boolean Specialty;
        public Boolean Stainless;
        public Boolean MachineShop;
        public Boolean Bipolar;
        public Boolean PowderCoating;
        public Integer InstrumentsInBin;
        public Integer InstrumentsTotal;
        public String QuantitySummary;
        public String PriorityRepair;
        public Boolean isDeviceTravelTag;
        public String SerialNumber;
        public String Model;
        public String CaseAccessoryIndication;
    }

    /**
     * @description Result of a print-label callout.
     */
    public class PrintLabelResult {
        public Boolean success;
        public String zplContent;
        public String errorDetail;
        public Integer httpStatus;
        public PrintLabelRequest request;

        public PrintLabelResult() {
            this.success = false;
        }
    }

    @TestVisible
    private static Map<String, Object> testCalloutResponseMap;

    @TestVisible
    private static PrintLabelRequest lastRequestForTest;

    /**
     * @description Builds the print payload from a Work Order and posts it through ShoutOut.
     * @param workOrderId Work Order to print (parent or child)
     * @return PrintLabelResult with ZPL text when the callout succeeds
     * @throws PrinterServiceException when the Work Order, quantity, printer, or callout fails
     */
    public static PrintLabelResult printBinTags(Id workOrderId) {
        return printBinTags(workOrderId, null);
    }

    /**
     * @description Builds the print payload from a Work Order and posts it through ShoutOut.
     * @param workOrderId Work Order to print (parent or child)
     * @param printerNameOverride Optional printer name; when blank, uses GW-4751 mapping
     * @return PrintLabelResult with ZPL text when the callout succeeds
     * @throws PrinterServiceException when the Work Order, quantity, printer, or callout fails
     */
    public static PrintLabelResult printBinTags(Id workOrderId, String printerNameOverride) {
        Logger.setScenario('Bin Tag Print');
        try {
            if (workOrderId == null) {
                throw new PrinterServiceException('Work Order Id is required to print bin tags.');
            }

            WorkOrder workOrder = queryWorkOrder(workOrderId);
            PrintLabelRequest request = buildRequest(workOrder, printerNameOverride);
            return sendPrintLabelRequest(request);
        } catch (PrinterServiceException e) {
            Logger.error(CLASS_NAME + '.printBinTags ' + e.getMessage());
            throw e;
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.printBinTags', e);
            throw new PrinterServiceException(toUserFacingError(e.getMessage()), e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Posts an already-built PrintLabels JSON body through ShoutOut.
     * @param request PrintLabels payload
     * @return PrintLabelResult with ZPL or error detail
     * @throws PrinterServiceException when the request is null or the response exceeds heap limits
     */
    public static PrintLabelResult sendPrintLabelRequest(PrintLabelRequest request) {
        if (request == null) {
            throw new PrinterServiceException('Print label request is required.');
        }
        if (String.isBlank(request.PrinterName)) {
            throw new PrinterServiceException('PrinterName is required.');
        }
        if (request.Copies == null) {
            request.Copies = BinTagPrintQuantitiesService.DEFAULT_PRINT_QUANTITY;
        }
        if (request.Copies <= 0) {
            throw new PrinterServiceException('Copies must be a positive number.');
        }

        lastRequestForTest = request;
        PrintLabelResult result = new PrintLabelResult();
        result.request = request;

        Map<String, Object> responseMap = invokeCallout(request);
        result.success = isSuccessful(responseMap);

        if (!result.success) {
            result.errorDetail = extractErrorDetail(responseMap);
            result.httpStatus = extractHttpStatus(responseMap);
            Logger.error(
                CLASS_NAME +
                '.sendPrintLabelRequest: callout failed printer=' +
                request.PrinterName +
                ', status=' +
                result.httpStatus +
                ', detail=' +
                result.errorDetail
            );
            throw new PrinterServiceException(
                toUserFacingError(formatCalloutFailure(request, result))
            );
        }

        String zplContent = extractResponseBody(responseMap);
        if (String.isNotBlank(zplContent)) {
            assertResponseWithinGovernorLimits(zplContent);
        }
        result.zplContent = zplContent;
        return result;
    }

    @TestVisible
    private static PrintLabelRequest buildRequest(WorkOrder workOrder, String printerNameOverride) {
        if (isDevicesRecordType(workOrder)) {
            return buildDeviceTravelTagRequest(workOrder, printerNameOverride);
        }
        if (workOrder.ParentWorkOrderId != null) {
            return buildChildTravelTagRequest(workOrder, printerNameOverride);
        }
        return applyParentBinTagPrinter(
            buildParentBinTagRequest(workOrder, printerNameOverride),
            printerNameOverride
        );
    }

    private static PrintLabelRequest buildParentBinTagRequest(WorkOrder workOrder, String printerNameOverride) {
        PrintLabelRequest request = new PrintLabelRequest();
        request.isChildTravelTag = false;
        applyCopiesAndPrinter(request, workOrder);
        request.SalesOrder = resolveSalesOrder(workOrder);
        request.Srn = resolveSrn(workOrder);
        request.SubWorkOrder = resolveSubWorkOrder(workOrder);
        request.labelDate = Datetime.now().format('M/d/yyyy');
        request.Day = Datetime.now().format('E');
        request.WorkOrderType = '';
        request.Priority = false;
        request.SalesRep = HARDCODED_SALES_REP;
        request.Description = truncateDescription(resolveDescription(workOrder));
        request.User = UserInfo.getName();
        return request;
    }

    private static PrintLabelRequest applyParentBinTagPrinter(
        PrintLabelRequest request,
        String printerNameOverride
    ) {
        request.SalesRep = PARENT_BIN_TAG_SALES_REP;
        request.PrintTestFlag = PARENT_BIN_TAG_PRINT_TEST_FLAG;
        request.Day = PlatformUtilities.toUpperCase(request.Day);
        applyTravelTagPrinter(request, printerNameOverride);
        return request;
    }

    private static PrintLabelRequest buildChildTravelTagRequest(WorkOrder workOrder, String printerNameOverride) {
        // Temporary: Child Instruments reuse the Parent Instruments payload until the
        // child travel-tag Zebra template is ready.
        return applyParentBinTagPrinter(
            buildParentBinTagRequest(workOrder, printerNameOverride),
            printerNameOverride
        );
    }

    private static PrintLabelRequest buildDeviceTravelTagRequest(WorkOrder workOrder, String printerNameOverride) {
        // Temporary: Devices reuse the Parent Instruments payload until the device
        // travel-tag Zebra template is ready.
        return applyParentBinTagPrinter(
            buildParentBinTagRequest(workOrder, printerNameOverride),
            printerNameOverride
        );
    }

    private static void applyCopiesAndPrinter(
        PrintLabelRequest request,
        WorkOrder workOrder
    ) {
        Integer copies = BinTagPrintQuantitiesService.getPrintQuantity(
            workOrder.RepairCenter__c,
            resolveProductLine(workOrder)
        );
        request.Copies = copies == null
            ? BinTagPrintQuantitiesService.DEFAULT_PRINT_QUANTITY
            : copies;
    }

    private static void applyTravelTagPrinter(PrintLabelRequest request, String printerNameOverride) {
        WorkstationPrinter__c printer = getActiveTravelTagPrinterForCurrentUser();
        if (printer != null) {
            request.PrinterIpAddr = printer.IPAddress__c;
            request.PrinterModel = printer.PrinterModel__c;
            if (String.isBlank(printerNameOverride)) {
                request.PrinterName = printer.Name;
            }
        }
        if (String.isNotBlank(printerNameOverride)) {
            request.PrinterName = printerNameOverride;
        }
        if (String.isBlank(request.PrinterName)) {
            throw new PrinterServiceException(
                'No active TRAVEL_TAG Workstation Printer is mapped to the current user.'
            );
        }
    }

    private static WorkOrder queryWorkOrder(Id workOrderId) {
        WorkOrder workOrder = (WorkOrder) new WorkOrdersSelector()
            .selectFields(BIN_TAG_PRINT_FIELDS)
            .whereEquals('Id', workOrderId)
            .first();
        if (workOrder == null) {
            throw new PrinterServiceException('Work Order was not found or is not accessible.');
        }
        return workOrder;
    }

    private static String resolveSalesOrder(WorkOrder workOrder) {
        if (workOrder.ParentWorkOrderId != null && workOrder.ParentWorkOrder != null) {
            return workOrder.ParentWorkOrder.WorkOrderNumber;
        }
        return workOrder.WorkOrderNumber;
    }

    private static String resolveSubWorkOrder(WorkOrder workOrder) {
        if (workOrder.ParentWorkOrderId != null) {
            return workOrder.WorkOrderNumber;
        }
        return '';
    }

    private static String resolveSrn(WorkOrder workOrder) {
        if (workOrder.ReturnOrder__r != null && String.isNotBlank(workOrder.ReturnOrder__r.ReturnOrderNumber)) {
            return workOrder.ReturnOrder__r.ReturnOrderNumber;
        }
        if (workOrder.ReturnOrder != null && String.isNotBlank(workOrder.ReturnOrder.ReturnOrderNumber)) {
            return workOrder.ReturnOrder.ReturnOrderNumber;
        }
        return '';
    }

    private static String resolveProductLine(WorkOrder workOrder) {
        if (workOrder.Asset != null && String.isNotBlank(workOrder.Asset.ProductLineCalculated__c)) {
            return workOrder.Asset.ProductLineCalculated__c;
        }
        if (
            workOrder.Asset != null &&
            workOrder.Asset.Product2 != null &&
            String.isNotBlank(workOrder.Asset.Product2.ProductLine__c)
        ) {
            return workOrder.Asset.Product2.ProductLine__c;
        }
        return workOrder.ProductLine_f__c;
    }

    private static String resolveDescription(WorkOrder workOrder) {
        if (
            workOrder.Asset != null &&
            workOrder.Asset.Product2 != null &&
            String.isNotBlank(workOrder.Asset.Product2.Description)
        ) {
            return workOrder.Asset.Product2.Description;
        }
        return '';
    }

    private static String truncateDescription(String description) {
        if (String.isBlank(description)) {
            return '';
        }
        return description.length() <= DESCRIPTION_MAX_LENGTH
            ? description
            : description.substring(0, DESCRIPTION_MAX_LENGTH);
    }

    private static Map<String, Object> invokeCallout(PrintLabelRequest request) {
        String requestJson = toJson(request);
        System.debug(
            LoggingLevel.INFO,
            CLASS_NAME +
            '.invokeCallout CALL operation=' +
            CALLOUT_OPERATION +
            ' path=/Zebra/PrintLabels verb=POST'
        );
        System.debug(LoggingLevel.INFO, CLASS_NAME + '.invokeCallout JSON=' + requestJson);

        if (testCalloutResponseMap != null) {
            return testCalloutResponseMap;
        }

        SO_Callout callout = new SO_Callout();
        callout
            .addToRequestMap(SO_Constants.CALLOUTOPERATION, CALLOUT_OPERATION)
            .addToRequestMap(SO_Constants.RESTBODY, requestJson)
            .addToRequestMap(SO_Constants.SERVICETIMEOUT, CALLOUT_TIMEOUT_SECONDS);
        Map<String, Object> responseMap = callout.callWebService();
        System.debug(
            LoggingLevel.INFO,
            CLASS_NAME +
            '.invokeCallout RESPONSE success=' +
            responseMap.get(RESPONSE_SUCCESS_KEY) +
            ' status=' +
            responseMap.get('SERVICE_STATUS') +
            ' soReturn=' +
            responseMap.get(RESPONSE_RETURN_KEY) +
            ' body=' +
            stringifyPayload(responseMap.get('SERVICE_DATA'))
        );
        return responseMap;
    }

    @TestVisible
    private static String toJson(PrintLabelRequest request) {
        return JSON.serialize(new Map<String, Object>{
            'Copies' => request.Copies,
            'Priority' => request.Priority,
            'Field1' => PlatformUtilities.blankToEmpty(PlatformUtilities.toUpperCase(request.Day)),
            'Field2' => PlatformUtilities.blankToEmpty(request.labelDate),
            'Field3' => PlatformUtilities.blankToEmpty(PARENT_BIN_TAG_SALES_REP),
            'Field4' => PlatformUtilities.blankToEmpty(request.SubWorkOrder),
            'Field5' => PlatformUtilities.blankToEmpty(request.WorkOrderType),
            'Field6' => PlatformUtilities.blankToEmpty(request.User),
            'Field7' => PlatformUtilities.blankToEmpty(request.SalesOrder),
            'Field8' => PlatformUtilities.blankToEmpty(PARENT_BIN_TAG_PRINT_TEST_FLAG),
            'Field9' => PlatformUtilities.blankToEmpty(request.Description),
            'PrinterName' => PlatformUtilities.blankToEmpty(request.PrinterName),
            'PrinterIpAddr' => PlatformUtilities.blankToEmpty(request.PrinterIpAddr),
            'PrinterModel' => PlatformUtilities.blankToEmpty(request.PrinterModel)
        });
    }

    @TestVisible
    private static String resolveEstimateRequirement(String estimateRequired) {
        return estimateRequired == ESTIMATE_REQUIRED ? VALUE_QUOTE_REQUIRED : VALUE_PRE_APPROVED;
    }

    private static Boolean isDevicesRecordType(WorkOrder workOrder) {
        if (workOrder == null || workOrder.RecordTypeId == null) {
            return false;
        }
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.WorkOrder.getRecordTypeInfosById()
            .get(workOrder.RecordTypeId);
        if (recordTypeInfo == null) {
            return false;
        }
        return recordTypeInfo.getName() == DEVICES_RECORD_TYPE_NAME ||
            recordTypeInfo.getDeveloperName() == DEVICES_RECORD_TYPE_DEV_NAME;
    }

    @TestVisible
    private static String resolvePriorityRepair(String entitlementType, String entitlementValue) {
        if (entitlementType != ENTITLEMENT_TYPE_CUSTOMER_REPAIR_PRIORITY) {
            return '';
        }
        return String.isBlank(entitlementValue) ? entitlementType : entitlementValue;
    }

    @TestVisible
    private static String resolveCaseAccessoryIndication(Boolean hasAccessoryLine, Boolean hasAsset) {
        return hasAccessoryLine == true && hasAsset != true ? VALUE_ACCESSORY : VALUE_CASE;
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
        if (responseMap == null) {
            return null;
        }
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

        Integer httpStatus = extractHttpStatus(responseMap);
        String body = firstNonBlank(
            stringifyPayload(responseMap.get('SERVICE_DATA'))
        );
        if (String.isNotBlank(body)) {
            return httpStatus == null ? body : 'HTTP ' + httpStatus + ': ' + body;
        }
        if (httpStatus != null) {
            return 'Zebra PrintLabels callout failed with HTTP ' + httpStatus + '.';
        }
        return 'Zebra PrintLabels callout failed with SO_SUCCESS=false';
    }

    private static String stringifyPayload(Object payload) {
        if (payload == null) {
            return null;
        }
        String value = payload instanceof String
            ? (String) payload
            : JSON.serialize(payload);
        if (String.isBlank(value)) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.length() > 500 ? trimmed.substring(0, 500) : trimmed;
    }

    private static String formatCalloutFailure(PrintLabelRequest request, PrintLabelResult result) {
        String detail = String.isBlank(result.errorDetail)
            ? 'Zebra PrintLabels callout failed.'
            : unwrapQuoted(result.errorDetail);
        if (
            result.httpStatus == 400 &&
            request != null &&
            String.isNotBlank(request.PrinterName) &&
            isGenericBadRequest(detail)
        ) {
            return 'The print service rejected printer ' +
                request.PrinterName +
                ' (HTTP 400: Bad request).';
        }
        return detail;
    }

    private static Boolean isGenericBadRequest(String detail) {
        if (String.isBlank(detail)) {
            return false;
        }
        String compact = unwrapQuoted(detail)
            .toLowerCase()
            .replace('http 400:', '')
            .replace('"', '')
            .replace('.', '')
            .trim();
        return compact == 'bad request';
    }

    private static String unwrapQuoted(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        String trimmed = value.trim();
        if (
            trimmed.length() >= 2 &&
            trimmed.startsWith('"') &&
            trimmed.endsWith('"')
        ) {
            return trimmed.substring(1, trimmed.length() - 1);
        }
        return trimmed;
    }

    @TestVisible
    private static String toUserFacingError(String detail) {
        return isCalloutTimeout(detail) ? CALLOUT_TIMEOUT_USER_MESSAGE : detail;
    }

    private static Boolean isCalloutTimeout(String detail) {
        if (String.isBlank(detail)) {
            return false;
        }
        String lower = detail.toLowerCase();
        return lower.contains('read timed out') ||
            lower.contains('exceeded maximum time allotted for callout') ||
            lower.contains('request timed out');
    }

    private static String firstNonBlank(String value) {
        return String.isBlank(value) ? null : value;
    }

    private static Integer extractHttpStatus(Map<String, Object> responseMap) {
        if (responseMap == null) {
            return null;
        }
        Object status = responseMap.get('SERVICE_STATUS');
        if (status instanceof Integer) {
            return (Integer) status;
        }
        if (status instanceof Decimal) {
            return ((Decimal) status).intValue();
        }
        return null;
    }

    @TestVisible
    private static void assertResponseWithinGovernorLimits(String zplContent) {
        if (String.isBlank(zplContent)) {
            return;
        }

        Integer remainingHeap = Limits.getLimitHeapSize() - Limits.getHeapSize();
        Integer allowedChars = remainingHeap > HEAP_SAFETY_BUFFER
            ? remainingHeap - HEAP_SAFETY_BUFFER
            : remainingHeap;
        if (zplContent.length() > allowedChars) {
            throw new PrinterServiceException(
                'Zebra PrintLabels response exceeds Salesforce heap governor limits.'
            );
        }
    }

    /**
     * @description GW-4751 - Active TRAVEL_TAG printer for the running user.
     *              When several match, returns the latest by CreatedDate. Returns null when none match.
     * @return The matching Workstation Printer, or null.
     * @throws PrinterServiceException when the query fails.
     */
    public static WorkstationPrinter__c getActiveTravelTagPrinterForCurrentUser() {
        return getActivePrinterForCurrentUser(PRINTER_TYPE_TRAVEL_TAG);
    }

    /**
     * @description GW-4751 - Active FEDEX_LABEL printer for the running user.
     *              When several match, returns the latest by CreatedDate. Returns null when none match.
     * @return The matching Workstation Printer, or null.
     * @throws PrinterServiceException when the query fails.
     */
    public static WorkstationPrinter__c getActiveFedExLabelPrinterForCurrentUser() {
        return getActivePrinterForCurrentUser(PRINTER_TYPE_FEDEX_LABEL);
    }

    /**
     * @description GW-4751 - Active DESKTOP printer for the running user.
     *              When several match, returns the latest by CreatedDate. Returns null when none match.
     * @return The matching Workstation Printer, or null.
     * @throws PrinterServiceException when the query fails.
     */
    public static WorkstationPrinter__c getActiveDesktopPrinterForCurrentUser() {
        return getActivePrinterForCurrentUser(PRINTER_TYPE_DESKTOP);
    }

    /**
     * @description GW-4751 - Active Workstation Printer of the given type for the running user.
     *              Returns null when none match. Query failures are logged and rethrown.
     * @param printerType PrinterType__c value to match.
     * @return The latest active record, or null when none match.
     * @throws PrinterServiceException when the query fails.
     */
    private static WorkstationPrinter__c getActivePrinterForCurrentUser(String printerType) {
        try {
            return UserPrinterMappingsService.getActivePrinterForCurrentUser(printerType);
        } catch (UserPrinterMappingsService.UserPrinterMappingsServiceException mappingError) {
            throw new PrinterServiceException(mappingError.getMessage(), mappingError);
        }
    }
}