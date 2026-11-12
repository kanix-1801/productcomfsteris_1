/**
 * @description Service class for ProductRequest business operations.
 *              Entry point for all ProductRequest-related transactions.
 *              Performs DML directly — no Unit of Work.
 *              Includes GW-514 Oracle Create Sales Order submit (Flow / Invocable).
 */
public with sharing class ProductRequestsService {

    // ── GW-514 Oracle Create Sales Order constants ───────────────────────────
    private static final String CALLOUT_OPERATION = 'ORACLE_CREATESALESORDER_DEV';

    /** GW-514: Optional ShoutOut response override for unit tests (null = default success mock). */
    @TestVisible
    private static Map<String, Object> testOracleResponseOverride;
    private static final String SOURCE_APPLICATION = 'SFService';
    private static final String ORDER_TYPE = '1 USA FIELD REPLENISH ORDER';
    private static final String LINE_ORDER_TYPE = '1 USA FIELD REPLENISHMENT LINE';
    private static final String PRICE_LIST_ID = '6307';
    private static final String PRICE_LIST_NAME = 'FIELD SERVICE TECH PARTS LIST';
    private static final String PAYMENT_TERM = 'NET 60';
    private static final String FOB_POINT = 'ORIGIN';
    private static final String FREIGHT_TERMS = 'Paid';
    private static final String DEFAULT_SHIP_METHOD = '000001_FEDEX EXPR_A_FEDXS';
    private static final String DEFAULT_SHIP_PRIOR = 'High';
    private static final String TAX_HANDLING = 'S';
    private static final String SOURCE_TYPE = 'Internal';
    private static final String DEFAULT_UOM = 'EA';
    /** Address.BillTo__c API value for Primary. */
    private static final String BILL_TO_PRIMARY = 'P';
    /** ProductRequest.IntegrationStatus__c values for Create Sales Order. */
    private static final String INTEGRATION_SUCCESS = 'Success Create';
    private static final String INTEGRATION_FAIL = 'Fail Create';


    /**
     * @description Creates new ProductRequest records with validation.
     * @param productRequests List of ProductRequest records to create.
     * @throws ProductRequestsServiceException when the operation fails.
     * @example
     * ProductRequestsService.createProductRequests(productRequestList);
     */
    public static void createProductRequests(List<ProductRequest> productRequests) {
        if (productRequests == null || productRequests.isEmpty()) {
            return;
        }
        Logger.setScenario('Product Request Management');
        try {
            // Apply defaults and validate via Domain
            ProductRequests domain = new ProductRequests(productRequests);
            // domain.applyDefaults();
            // domain.validate();

            // Perform DML
            insert productRequests;
        } catch (ProductRequests.ProductRequestsException e) {
            Logger.error(new LogMessage('ProductRequestsService.createProductRequests: Validation failed. {0}', e.getMessage()), e);
            throw new ProductRequestsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ProductRequestsService.createProductRequests: Unexpected error.', e);
            throw new ProductRequestsServiceException('An unexpected error occurred while creating ProductRequest records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing ProductRequest records with validation.
     * @param productRequests List of ProductRequest records to update.
     * @throws ProductRequestsServiceException when the operation fails.
     * @example
     * ProductRequestsService.updateProductRequests(productRequestList);
     */
    public static void updateProductRequests(List<ProductRequest> productRequests) {
        if (productRequests == null || productRequests.isEmpty()) {
            return;
        }
        Logger.setScenario('Product Request Management');
        try {
            // Validate via Domain
            ProductRequests domain = new ProductRequests(productRequests);
            // domain.validate();

            // Perform DML
            update productRequests;
        } catch (ProductRequests.ProductRequestsException e) {
            Logger.error(new LogMessage('ProductRequestsService.updateProductRequests: Validation failed. {0}', e.getMessage()), e);
            throw new ProductRequestsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ProductRequestsService.updateProductRequests: Unexpected error.', e);
            throw new ProductRequestsServiceException('An unexpected error occurred while updating ProductRequest records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes ProductRequest records by their Ids.
     * @param productRequestIds Set of ProductRequest Ids to delete.
     * @throws ProductRequestsServiceException when the operation fails.
     * @example
     * ProductRequestsService.deleteProductRequests(productRequestIdSet);
     */
    public static void deleteProductRequests(Set<Id> productRequestIds) {
        if (productRequestIds == null || productRequestIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Product Request Management');
        try {
            // Retrieve records via Selector
            List<ProductRequest> productRequestList = ProductRequestsSelector.selectById(productRequestIds);
            if (productRequestList.isEmpty()) {
                return;
            }

            // Perform DML
            delete productRequestList;
        } catch (Exception e) {
            Logger.error('ProductRequestsService.deleteProductRequests: Unexpected error.', e);
            throw new ProductRequestsServiceException('An unexpected error occurred while deleting ProductRequest records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves ProductRequest records by their Ids.
     * @param productRequestIds Set of ProductRequest Ids to retrieve.
     * @return List of ProductRequest records.
     * @throws ProductRequestsServiceException when the operation fails.
     * @example
     * List<ProductRequest> results = ProductRequestsService.getProductRequestsById(productRequestIdSet);
     */
    public static List<ProductRequest> getProductRequestsById(Set<Id> productRequestIds) {
        if (productRequestIds == null || productRequestIds.isEmpty()) {
            return new List<ProductRequest>();
        }
        try {
            return ProductRequestsSelector.selectById(productRequestIds);
        } catch (Exception e) {
            Logger.error('ProductRequestsService.getProductRequestsById: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductRequestsServiceException('An unexpected error occurred while retrieving ProductRequest records.', e);
        }
    }

    /**
     * @description Retrieves ProductRequest records with their related ProductRequestLineItems.
     * @param productRequestIds Set of ProductRequest Ids to retrieve.
     * @return List of ProductRequest records with child ProductRequestLineItem records.
     * @throws ProductRequestsServiceException when the operation fails.
     * @example
     * List<ProductRequest> results = ProductRequestsService.getProductRequestsWithLineItems(productRequestIdSet);
     */
    public static List<ProductRequest> getProductRequestsWithLineItems(Set<Id> productRequestIds) {
        if (productRequestIds == null || productRequestIds.isEmpty()) {
            return new List<ProductRequest>();
        }
        try {
            return ProductRequestsSelector.selectByIdWithLineItems(productRequestIds);
        } catch (Exception e) {
            Logger.error('ProductRequestsService.getProductRequestsWithLineItems: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductRequestsServiceException('An unexpected error occurred while retrieving ProductRequests with Line Items.', e);
        }
    }


    // ── GW-514 Oracle Create Sales Order (Screen Flow) ─────────────────────

    /**
     * @description GW-514: Invocable input for Screen Flow ProductRequest_SCR_SubmitToERP.
     */
    public class OracleSubmitRequest {
        @InvocableVariable(required=true label='Product Request Id')
        public Id productRequestId;
        @InvocableVariable(label='Perform Callout' description='If false, only builds JSON (for testing).')
        public Boolean performCallout;
    }

    /**
     * @description GW-514: Invocable output returned to Screen Flow after submit attempt.
     */
    public class OracleSubmitResult {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Integration Status')
        public String integrationStatus;
        @InvocableVariable(label='Integration Message')
        public String integrationMessage;
        @InvocableVariable(label='ERP Order Number')
        public String erpOrderNumber;
        // Not exposed to Flow — used only in Apex/tests
        public String requestJson;
        public String responsePayload;
    }

    /**
     * @description GW-514: Invocable entry for Flow — builds Create Sales Order JSON and
     *              calls BOOMI/Oracle via SO_Callout (ORACLE_CREATESALESORDER_DEV), then stamps PR.
     * @param requests List of Product Request submit requests from Flow.
     * @return One result per request for Flow screens.
     */
    @InvocableMethod(
        label='Product Request - Submit Oracle Sales Order'
        description='GW-514: Builds Create Sales Order JSON and calls BOOMI/Oracle via SO_Callout.'
    )
    public static List<OracleSubmitResult> submitOracleSalesOrder(List<OracleSubmitRequest> requests) {
        List<OracleSubmitResult> results = new List<OracleSubmitResult>();
        if (requests == null) {
            return results;
        }
        for (OracleSubmitRequest req : requests) {
            results.add(processOracleSalesOrderSubmit(req));
        }
        return results;
    }

    /**
     * @description GW-514: Processes one Product Request — validate, build JSON, ShoutOut, stamp.
     * @param req Single Product Request submit request.
     * @return Submit result for Flow / caller.
     */
    @TestVisible
    private static OracleSubmitResult processOracleSalesOrderSubmit(OracleSubmitRequest req) {
        OracleSubmitResult result = new OracleSubmitResult();
        result.success = false;
        Boolean doCallout = req.performCallout == null ? true : req.performCallout;

        try {
            ProductRequest pr = queryProductRequestForOracle(req.productRequestId);
            List<ProductRequestLineItem> lines = queryProductRequestLinesForOracle(req.productRequestId);
            if (lines.isEmpty()) {
                return failAndStampOracleSubmit(pr, result, 'No Product Request Line Items to submit.');
            }

            String soldToOrgId = resolveOracleAccountIdFromServiceResource(pr);
            String shipToAddrId = resolveShipToAddressId(pr);
            String invAddrId = resolveInvoiceAddressId(pr);

            if (String.isBlank(soldToOrgId)) {
                return failAndStampOracleSubmit(
                    pr,
                    result,
                    'Missing ServiceResource.OracleAccountId__c (required for P_SOLD_TO_ORG_ID / P_SHIP_TO_CUST_ID). Set ProductRequest.ServiceResource__c.'
                );
            }
            if (String.isBlank(shipToAddrId)) {
                return failAndStampOracleSubmit(pr, result, shipToAddressFailureMessage(pr));
            }
            if (String.isBlank(invAddrId)) {
                return failAndStampOracleSubmit(
                    pr,
                    result,
                    'Missing primary Bill To address on the Service Resource location (Address.BillTo__c = Primary and Address.AddressID__c) for P_INV_ADDR_ID.'
                );
            }

            Map<String, Object> body = buildOracleSalesOrderHeader(
                pr,
                soldToOrgId,
                shipToAddrId,
                invAddrId
            );
            body.put(
                'P_ORDER_LINE_ITEMS',
                buildOracleSalesOrderLines(pr, lines, shipToAddrId, invAddrId)
            );
            String restBody = JSON.serialize(body);
            result.requestJson = restBody;

            // No DML before callout (governor restriction). Stamp once after response.
            if (!doCallout) {
                result.success = true;
                result.integrationStatus = null;
                result.integrationMessage = 'JSON built; callout skipped.';
                return result;
            }

            Map<String, Object> responseMap;
            if (Test.isRunningTest()) {
                // Avoid live ShoutOut HTTP in unit tests; exercise stamp/response path.
                responseMap = testOracleResponseOverride != null
                    ? testOracleResponseOverride
                    : new Map<String, Object>{
                          'SO_SUCCESS' => true,
                          'SERVICE_DATA' => new Map<String, Object>{
                              'p_Oracle_Order_Number' => 'TEST-SO-001',
                              'p_Order_Header_Status' => 'BOOKED',
                              'p_retcode' => 0
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

            return applyOracleCalloutResponse(pr.Id, result, restBody, responseMap);
        } catch (Exception e) {
            result.success = false;
            result.integrationStatus = INTEGRATION_FAIL;
            result.integrationMessage = e.getMessage();
            try {
                stampOracleSubmission(req.productRequestId, INTEGRATION_FAIL, e.getMessage(), null);
            } catch (Exception ignore) {
                // keep original error
            }
            return result;
        }
    }

    /**
     * @description GW-514: Interprets ShoutOut serviceResponseMap and stamps Integration fields.
     * @param productRequestId Product Request Id to stamp.
     * @param result Invocable result being populated.
     * @param restBody Serialized Create Sales Order request JSON.
     * @param responseMap ShoutOut response map (SO_SUCCESS / SERVICE_DATA).
     * @return Updated invocable result.
     */
    private static OracleSubmitResult applyOracleCalloutResponse(
        Id productRequestId,
        OracleSubmitResult result,
        String restBody,
        Map<String, Object> responseMap
    ) {
        result.requestJson = restBody;
        result.responsePayload = responseMap == null ? null : JSON.serialize(responseMap);

        Boolean soSuccess = responseMap != null && responseMap.get('SO_SUCCESS') == true;
        Object serviceData = responseMap == null ? null : responseMap.get('SERVICE_DATA');
        if (serviceData == null && responseMap != null) {
            serviceData = responseMap.get('SO_RETURN');
        }

        // Diagnostic only — never stamp JSON onto the Product Request / Flow message
        try {
            Logger.setScenario('Product Request Oracle Submit');
            Logger.info(
                new LogMessage(
                    'GW-514 ShoutOut response keys={0}; SERVICE_DATA type={1}',
                    responseMap == null ? 'null' : String.valueOf(responseMap.keySet()),
                    serviceData == null ? 'null' : String.valueOf(serviceData).left(200)
                )
            );
            Logger.saveLog();
        } catch (Exception ignore) {
            // logging must not break submit
        }

        String erpOrderNumber = extractOracleErpOrderNumber(serviceData, responseMap);
        String message = extractOracleResponseMessage(serviceData, soSuccess);
        String retcode = extractOracleRetcode(serviceData);
        Boolean oracleRetcodeOk = isOracleRetcodeSuccess(retcode);
        // SO_SUCCESS only means ShoutOut/BOOMI transport completed — not that Oracle created the order.
        // Business Success requires: transport OK + retcode OK (when present) + Oracle order number.
        Boolean businessSuccess =
            soSuccess &&
            oracleRetcodeOk &&
            String.isNotBlank(erpOrderNumber);

        if (businessSuccess) {
            result.success = true;
            result.integrationStatus = INTEGRATION_SUCCESS;
            // Prefer a clear SF message; Oracle often returns "Success" in p_errbuf on create.
            result.integrationMessage = 'Oracle sales order created.';
            result.erpOrderNumber = erpOrderNumber;
            stampOracleSubmission(productRequestId, INTEGRATION_SUCCESS, result.integrationMessage, erpOrderNumber);
        } else {
            result.success = false;
            result.integrationStatus = INTEGRATION_FAIL;
            if (String.isBlank(message)) {
                if (!soSuccess) {
                    message = 'Oracle/BOOMI call failed.';
                } else if (!oracleRetcodeOk) {
                    message = 'Oracle returned error retcode=' + retcode + '.';
                } else {
                    message =
                        'Oracle/BOOMI call completed but no order number was returned (treated as Fail). ' +
                        'Check p_errbuf / p_retcode / BOOMI OUT mapping for ORACLE_CREATESALESORDER_DEV.';
                }
            }
            result.integrationMessage = message;
            stampOracleSubmission(productRequestId, INTEGRATION_FAIL, result.integrationMessage, null);
        }
        return result;
    }

    /**
     * @description GW-514: Reads Oracle p_retcode from SERVICE_DATA when present.
     */
    private static String extractOracleRetcode(Object serviceData) {
        Map<String, Object> m = coerceOracleServiceDataMap(serviceData);
        if (m == null) {
            return null;
        }
        for (String key : new List<String>{ 'p_retcode', 'P_RETCODE', 'retcode', 'RETCODE' }) {
            if (m.containsKey(key) && m.get(key) != null && String.isNotBlank(String.valueOf(m.get(key)))) {
                return String.valueOf(m.get(key)).trim();
            }
        }
        return null;
    }

    /**
     * @description GW-514: Oracle success retcode is 0 / blank / S. Any other value is Fail.
     */
    private static Boolean isOracleRetcodeSuccess(String retcode) {
        if (String.isBlank(retcode)) {
            return true; // absent — rely on order number presence
        }
        String normalized = retcode.trim();
        return normalized == '0' || normalized.equalsIgnoreCase('S') || normalized.equalsIgnoreCase('SUCCESS');
    }

    /**
     * @description GW-514: Coerces SERVICE_DATA (Map or JSON string) to a Map when possible.
     */
    private static Map<String, Object> coerceOracleServiceDataMap(Object serviceData) {
        if (serviceData == null) {
            return null;
        }
        if (serviceData instanceof Map<String, Object>) {
            return (Map<String, Object>) serviceData;
        }
        if (serviceData instanceof String) {
            String s = ((String) serviceData).trim();
            if (s.startsWith('{')) {
                try {
                    Object parsed = JSON.deserializeUntyped(s);
                    if (parsed instanceof Map<String, Object>) {
                        return (Map<String, Object>) parsed;
                    }
                } catch (Exception e) {
                    return null;
                }
            }
        }
        return null;
    }

    /**
     * @description GW-514: Stamps Fail status/message on Product Request and returns fail result.
     * @param pr Product Request being submitted.
     * @param result Invocable result being populated.
     * @param message Failure message for IntegrationMessage__c.
     * @return Fail invocable result.
     */
    private static OracleSubmitResult failAndStampOracleSubmit(
        ProductRequest pr,
        OracleSubmitResult result,
        String message
    ) {
        result.success = false;
        result.integrationStatus = INTEGRATION_FAIL;
        result.integrationMessage = message;
        stampOracleSubmission(pr.Id, INTEGRATION_FAIL, message, null);
        return result;
    }

    /**
     * @description GW-514: Updates Integration Status / Message / ERP Order Number.
     *              Does not change SubmissionToERP__c. Boomi sets that to Submitted.
     * @param productRequestId Product Request Id.
     * @param integrationStatus Success or Fail.
     * @param integrationMessage User-facing message.
     * @param erpOrderNumber Oracle order number when successful; null otherwise.
     */
    private static void stampOracleSubmission(
        Id productRequestId,
        String integrationStatus,
        String integrationMessage,
        String erpOrderNumber
    ) {
        ProductRequest updatePr = new ProductRequest(Id = productRequestId);
        updatePr.IntegrationStatus__c = integrationStatus;
        updatePr.IntegrationMessage__c = integrationMessage;
        if (erpOrderNumber != null) {
            updatePr.ERPOrderNumber__c = erpOrderNumber;
        }
        update updatePr;
    }

    /**
     * @description GW-514: Queries Product Request header fields needed for Create Sales Order JSON.
     * @param productRequestId Product Request Id.
     * @return Product Request with Service Resource / Case / Work Order relationships.
     */
    private static ProductRequest queryProductRequestForOracle(Id productRequestId) {
        return [
            SELECT
                Id,
                ProductRequestNumber,
                Status,
                NeedByDate,
                ShipmentType,
                Description,
                CurrencyIsoCode,
                DestinationLocationId,
                DestinationLocation.Name,
                SourceLocationId,
                CaseId,
                Case.CaseNumber,
                Case.Contact.FirstName,
                Case.Contact.LastName,
                WorkOrderId,
                WorkOrder.WorkOrderNumber,
                WorkOrder.Contact.FirstName,
                WorkOrder.Contact.LastName,
                WorkOrder.ContactId,
                AccountId,
                ServiceResource__c,
                ServiceResource__r.OracleAccountId__c,
                ServiceResource__r.Description,
                ServiceResource__r.LocationId,
                ShipToAddressAccount__c,
                ShipToAddressAccount__r.AddressID__c,
                ShipToTechnicianAddress__c,
                ShipToTechnicianAddress__r.AddressID__c
            FROM ProductRequest
            WHERE Id = :productRequestId
            LIMIT 1
        ];
    }

    /**
     * @description GW-514: Queries Product Request Line Items for Create Sales Order line payload.
     * @param productRequestId Parent Product Request Id.
     * @return Ordered list of line items with Product2 codes.
     */
    private static List<ProductRequestLineItem> queryProductRequestLinesForOracle(Id productRequestId) {
        return [
            SELECT
                Id,
                ProductRequestLineItemNumber,
                Product2Id,
                Product2.ProductCode,
                Product2.StockKeepingUnit,
                QuantityRequested,
                QuantityUnitOfMeasure,
                NeedByDate,
                Description,
                WorkOrderLineItemId,
                SourceLocationId,
                DestinationLocationId
            FROM ProductRequestLineItem
            WHERE ParentId = :productRequestId
            ORDER BY CreatedDate ASC
        ];
    }

    /**
     * @description GW-514: Resolves P_SOLD_TO_ORG_ID / P_SHIP_TO_CUST_ID from ServiceResource.OracleAccountId__c
     *              via ProductRequest.ServiceResource__c (fallbacks: Destination Location SR, running-user SR).
     *              Does not use Account.
     * @param pr Product Request header.
     * @return OracleAccountId__c or null.
     */
    private static String resolveOracleAccountIdFromServiceResource(ProductRequest pr) {
        ServiceResource sr = resolveServiceResourceForOracle(pr);
        return sr == null || String.isBlank(sr.OracleAccountId__c) ? null : sr.OracleAccountId__c;
    }

    /**
     * @description GW-514: P_SHIP_TO_ADDR_ID from Ship-to Address Account.AddressID__c when that
     *              lookup is set; otherwise Ship-To Technician Address.AddressID__c.
     * @param pr Product Request header.
     * @return Address ID or null.
     */
    private static String resolveShipToAddressId(ProductRequest pr) {
        if (pr.ShipToAddressAccount__c != null) {
            String accountAddressId = pr.ShipToAddressAccount__r == null
                ? null
                : pr.ShipToAddressAccount__r.AddressID__c;
            return String.isBlank(accountAddressId) ? null : accountAddressId.trim();
        }
        if (pr.ShipToTechnicianAddress__c != null) {
            String technicianAddressId = pr.ShipToTechnicianAddress__r == null
                ? null
                : pr.ShipToTechnicianAddress__r.AddressID__c;
            return String.isBlank(technicianAddressId) ? null : technicianAddressId.trim();
        }
        return null;
    }

    /**
     * @description GW-514: Explains why P_SHIP_TO_ADDR_ID could not be resolved.
     * @param pr Product Request header.
     * @return Failure message stamped on the Product Request.
     */
    private static String shipToAddressFailureMessage(ProductRequest pr) {
        if (pr.ShipToAddressAccount__c != null) {
            return 'Ship-to Address Account is set but Account.AddressID__c is blank (required for P_SHIP_TO_ADDR_ID).';
        }
        if (pr.ShipToTechnicianAddress__c != null) {
            return 'Ship-To Technician Address is set but Address.AddressID__c is blank (required for P_SHIP_TO_ADDR_ID).';
        }
        return 'Set Ship-to Address Account or Ship-To Technician Address (required for P_SHIP_TO_ADDR_ID).';
    }

    /**
     * @description GW-514: P_INV_ADDR_ID from the first Address on the Service Resource Location
     *              whose Bill To is Primary.
     * @param pr Product Request header.
     * @return Address.AddressID__c or null.
     */
    private static String resolveInvoiceAddressId(ProductRequest pr) {
        ServiceResource sr = resolveServiceResourceForOracle(pr);
        if (sr == null || sr.LocationId == null) {
            return null;
        }
        List<Schema.Address> primaryBillTo = [
            SELECT AddressID__c
            FROM Address
            WHERE ParentId = :sr.LocationId
                AND BillTo__c = :BILL_TO_PRIMARY
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT 1
        ];
        if (primaryBillTo.isEmpty() || String.isBlank(primaryBillTo[0].AddressID__c)) {
            return null;
        }
        return primaryBillTo[0].AddressID__c.trim();
    }

    /**
     * @description GW-514: Resolves Service Resource for Oracle keys (lookup, then Location, then user).
     */
    private static ServiceResource resolveServiceResourceForOracle(ProductRequest pr) {
        if (pr.ServiceResource__c != null) {
            if (
                pr.ServiceResource__r != null &&
                (String.isNotBlank(pr.ServiceResource__r.OracleAccountId__c) ||
                    String.isNotBlank(pr.ServiceResource__r.Description))
            ) {
                return pr.ServiceResource__r;
            }
            List<ServiceResource> srs = [
                SELECT Id, OracleAccountId__c, Description, LocationId
                FROM ServiceResource
                WHERE Id = :pr.ServiceResource__c
                LIMIT 1
            ];
            if (!srs.isEmpty()) {
                return srs[0];
            }
        }

        if (pr.DestinationLocationId != null) {
            List<ServiceResource> byLocation = [
                SELECT Id, OracleAccountId__c, Description, LocationId
                FROM ServiceResource
                WHERE LocationId = :pr.DestinationLocationId
                    AND IsActive = TRUE
                LIMIT 1
            ];
            if (!byLocation.isEmpty()) {
                return byLocation[0];
            }
        }

        List<ServiceResource> byUser = [
            SELECT Id, OracleAccountId__c, Description, LocationId
            FROM ServiceResource
            WHERE RelatedRecordId = :UserInfo.getUserId()
                AND IsActive = TRUE
            LIMIT 1
        ];
        return byUser.isEmpty() ? null : byUser[0];
    }

    /**
     * @description GW-514: Builds Create Sales Order header map (P_* fields) from Product Request.
     * @param pr Product Request header.
     * @param soldToOrgId ServiceResource.OracleAccountId__c for P_SOLD_TO_ORG_ID / P_SHIP_TO_CUST_ID.
     * @param shipToAddrId Account.AddressID__c or Address.AddressID__c for P_SHIP_TO_ADDR_ID.
     * @param invAddrId Primary Bill To Address.AddressID__c for P_INV_ADDR_ID.
     * @return Header field map for RESTBODY.
     */
    private static Map<String, Object> buildOracleSalesOrderHeader(
        ProductRequest pr,
        String soldToOrgId,
        String shipToAddrId,
        String invAddrId
    ) {
        Map<String, Object> header = new Map<String, Object>();
        header.put('P_SOURCE_APPLICATION', SOURCE_APPLICATION);
        header.put('P_ORIG_SYS_DOCUMENT_REF', blankToEmpty(pr.ProductRequestNumber));
        header.put('P_CUST_PO_NUMBER', '');
        header.put('P_CUST_ACCOUNT_ROLE_ID', '');
        // Blank in sample JSON — do not fill from SF
        header.put('P_CONTACT_FIRST_NAME', '');
        header.put('P_CONTACT_LAST_NAME', '');
        header.put('P_ORDER_TYPE', ORDER_TYPE);
        header.put('P_SOLD_TO_ORG_ID', soldToOrgId);
        header.put('P_SHIP_TO_CUST_ID', soldToOrgId);
        header.put('P_SHIP_TO_ADDR_ID', shipToAddrId);
        header.put('P_INV_ADDR_ID', invAddrId);
        header.put('P_PRICE_LIST_ID', PRICE_LIST_ID);
        header.put('P_CURRENCY_CODE', String.isBlank(pr.CurrencyIsoCode) ? 'USD' : pr.CurrencyIsoCode);
        header.put('P_PAYMENT_TERM', PAYMENT_TERM);
        header.put('P_SOURCE_HEADER_ATTRIBUTE1', 'No');
        // ATTR2-15 blank in sample — do not fill from SF
        for (Integer i = 2; i <= 15; i++) {
            header.put('P_SOURCE_HEADER_ATTRIBUTE' + i, '');
        }
        header.put('P_FOB_POINT', FOB_POINT);
        header.put('P_FREIGHT_TERMS', FREIGHT_TERMS);
        header.put('P_SHIP_METHOD', DEFAULT_SHIP_METHOD);
        header.put('P_SHIP_PRIOR', DEFAULT_SHIP_PRIOR);
        header.put('P_PACKING_INSTRUCTIONS', '');
        header.put('P_SHIPPING_INSTRUCTIONS', '');
        header.put('P_PAYMENT_TYPE', '');
        header.put('P_CREDIT_CARD_TYPE', '');
        header.put('P_CREDIT_CARD_NUMBER', '');
        header.put('P_CREDIT_CARD_EXPIRATION_DATE', '');
        header.put('P_CREDIT_CARD_HOLDER', '');
        header.put('P_TAX_HANDLING', TAX_HANDLING);
        header.put('P_SHIP_TO_CONTACT_ID', '');
        header.put('P_SHIP_TO_CONTACT_FIRST_NAME', '');
        header.put('P_SHIP_TO_CONTACT_LAST_NAME', '');
        header.put('P_TAX_EXAMPTION_REASON', '');
        header.put('P_TAX_EXAMPTION_NUMBER', '');
        return header;
    }

    /**
     * @description GW-514: Builds Create Sales Order line item maps (P_* fields) from PR lines.
     * @param pr Product Request header.
     * @param lines Product Request Line Items.
     * @param shipToAddrId Ship-to address id for line P_SHIP_TO_ADDR.
     * @param invAddrId Primary Bill To address id for line P_BILL_TO_ADDR.
     * @return List of line maps for P_ORDER_LINE_ITEMS.
     */
    private static List<Object> buildOracleSalesOrderLines(
        ProductRequest pr,
        List<ProductRequestLineItem> lines,
        String shipToAddrId,
        String invAddrId
    ) {
        List<Object> linePayloads = new List<Object>();
        Integer lineNum = 1;
        String shipMethod = DEFAULT_SHIP_METHOD;
        String shipPrior = DEFAULT_SHIP_PRIOR;
        String headerNeedBy = formatOracleDate(pr.NeedByDate);

        for (ProductRequestLineItem line : lines) {
            String productName = line.Product2 != null
                ? (String.isNotBlank(line.Product2.ProductCode)
                      ? line.Product2.ProductCode
                      : line.Product2.StockKeepingUnit)
                : null;
            if (String.isBlank(productName) || line.QuantityRequested == null || line.QuantityRequested <= 0) {
                throw new ProductRequestsServiceException(
                    'Line ' + lineNum + ' requires Product Code and Quantity Requested > 0.'
                );
            }

            String needBy = line.NeedByDate != null ? formatOracleDate(line.NeedByDate) : headerNeedBy;
            if (String.isBlank(needBy)) {
                needBy = formatOracleDate(Date.today());
            }

            Map<String, Object> lineMap = new Map<String, Object>();
            lineMap.put('P_LINE_ORIG_SYS_DOCUMENT_REF', blankToEmpty(pr.ProductRequestNumber));
            lineMap.put('P_PRODUCT_NAME', productName);
            lineMap.put('P_UOM_CODE', mapOracleUom(line.QuantityUnitOfMeasure));
            lineMap.put('P_QUANTITY', String.valueOf(line.QuantityRequested.intValue()));
            lineMap.put('P_ITEM_PRICE', '0');
            lineMap.put('P_LINE_CUST_PO_NUMBER', '');
            lineMap.put('P_PRICE_LIST_NAME', PRICE_LIST_NAME);
            lineMap.put('P_LINE_PAYMENT_TERM', PAYMENT_TERM);
            lineMap.put('P_LINE_NUMBER', String.valueOf(lineNum));
            lineMap.put('P_LINE_NUMBER1', String.valueOf(lineNum));
            lineMap.put('P_REQUEST_SHIP_DATE', needBy);
            lineMap.put('P_SCHEDULED_SHIP_DATE', needBy);
            // ATTR1-15 blank in sample — do not fill from SF
            for (Integer i = 1; i <= 15; i++) {
                lineMap.put('P_SOURCE_LINE_ATTRIBUTE' + i, '');
            }
            lineMap.put('P_BILL_TO_ADDR', invAddrId);
            lineMap.put('P_SHIP_TO_ADDR', shipToAddrId);
            lineMap.put('P_LINE_FOB_POINT', FOB_POINT);
            lineMap.put('P_FREIGHT_TERMS2', FREIGHT_TERMS);
            lineMap.put('P_LINE_SHIP_METHOD', shipMethod);
            lineMap.put('P_LINE_SHIP_PRIOR', shipPrior);
            lineMap.put('P_SHIP_SET', '');
            lineMap.put('P_FULL_SET', '');
            lineMap.put('P_LINE_PACKING_INSTRUCTIONS', '');
            lineMap.put('P_LINE_SHIPPING_INSTRUCTIONS', '');
            lineMap.put('P_RETURN_REASON', '');
            lineMap.put('P_LINE_ORDER_TYPE', LINE_ORDER_TYPE);
            lineMap.put('P_SALES_REP_ID', '');
            lineMap.put('P_OVER_REASON_CODE', '');
            lineMap.put('P_OVER_REASON_NOTE', '');
            lineMap.put('P_INVENTORY_ORG', '');
            lineMap.put('P_SOURCE_TYPE', SOURCE_TYPE);
            linePayloads.add(lineMap);
            lineNum++;
        }
        return linePayloads;
    }

    /**
     * @description GW-514: Maps Salesforce ShipmentType to Oracle ship method (currently sample default).
     * @param shipmentType ProductRequest.ShipmentType value.
     * @return Oracle P_SHIP_METHOD value.
     */
    private static String mapOracleShipMethod(String shipmentType) {
        // Sample hardcode; ShipmentType crosswalk not used (blank/unmapped -> sample value).
        return DEFAULT_SHIP_METHOD;
    }

    /**
     * @description GW-514: Maps Salesforce UOM to Oracle P_UOM_CODE (default EA).
     * @param sfUom QuantityUnitOfMeasure from line.
     * @return Oracle UOM code.
     */
    private static String mapOracleUom(String sfUom) {
        if (String.isBlank(sfUom)) {
            return DEFAULT_UOM;
        }
        String u = sfUom.trim().toUpperCase();
        if (u == 'EACH' || u == 'EA') {
            return 'EA';
        }
        return u.length() <= 3 ? u : DEFAULT_UOM;
    }

    /**
     * @description GW-514: Formats a Date as MM/dd/yyyy for Oracle request/ship dates.
     * @param d Date to format.
     * @return Formatted date string, or blank when null.
     */
    private static String formatOracleDate(Date d) {
        if (d == null) {
            return '';
        }
        String mm = d.month() < 10 ? '0' + String.valueOf(d.month()) : String.valueOf(d.month());
        String dd = d.day() < 10 ? '0' + String.valueOf(d.day()) : String.valueOf(d.day());
        return mm + '/' + dd + '/' + String.valueOf(d.year());
    }

    /**
     * @description GW-514: Formats a Datetime as MM/dd/yyyy for Oracle request/ship dates.
     * @param dt Datetime to format.
     * @return Formatted date string, or blank when null.
     */
    private static String formatOracleDate(Datetime dt) {
        if (dt == null) {
            return '';
        }
        return formatOracleDate(dt.date());
    }

    /**
     * @description GW-514: Converts null strings to empty string for Oracle JSON fields.
     * @param value Input string.
     * @return Non-null string.
     */
    private static String blankToEmpty(String value) {
        return value == null ? '' : value;
    }

    /**
     * @description GW-514: Best-effort parse of ERP order number from ShoutOut SERVICE_DATA / response map.
     *              Handles SERVICE_DATA as Map or JSON/XML-ish String; also scans top-level response keys.
     * @param serviceData SERVICE_DATA (or SO_RETURN) payload.
     * @param responseMap Full ShoutOut response map.
     * @return Order number when found; otherwise null.
     */
    private static String extractOracleErpOrderNumber(Object serviceData, Map<String, Object> responseMap) {
        String fromPayload = findOracleOrderNumberInObject(serviceData, 0);
        if (String.isNotBlank(fromPayload)) {
            return fromPayload;
        }
        if (responseMap != null) {
            String fromMap = findOracleOrderNumberInObject(responseMap, 0);
            if (String.isNotBlank(fromMap)) {
                return fromMap;
            }
        }
        // Last resort: regex on serialized payload text
        String blobText = summarizeOracleResponse(serviceData, responseMap);
        if (String.isBlank(blobText)) {
            return null;
        }
        Matcher m = Pattern.compile(
                '(?i)(?:"|\\b)(?:p_)?(?:Oracle_)?Order[_\\s]?Number(?:"|\\b)\\s*[:=]\\s*"?([A-Za-z0-9\\-_/]+)"?'
            )
            .matcher(blobText);
        if (m.find()) {
            return m.group(1);
        }
        return null;
    }

    /**
     * @description GW-514: Recursively searches Maps/Lists/JSON strings for known order-number keys.
     */
    private static String findOracleOrderNumberInObject(Object node, Integer depth) {
        if (node == null || depth > 6) {
            return null;
        }
        if (node instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) node;
            for (String key : new List<String>{
                'p_Oracle_Order_Number',
                'P_ORACLE_ORDER_NUMBER',
                'P_Oracle_Order_Number',
                'ORACLE_ORDER_NUMBER',
                'ORDER_NUMBER',
                'orderNumber',
                'OrderNumber',
                'P_ORDER_NUMBER',
                'X_ORDER_NUMBER',
                'x_order_number',
                'erpOrderNumber',
                'SalesOrderNumber',
                'SALES_ORDER_NUMBER'
            }) {
                if (m.containsKey(key) && m.get(key) != null && String.isNotBlank(String.valueOf(m.get(key)))) {
                    String val = String.valueOf(m.get(key)).trim();
                    // Skip boolean / status-like values
                    if (val.equalsIgnoreCase('true') || val.equalsIgnoreCase('false') || val.equalsIgnoreCase('S') || val.equalsIgnoreCase('E')) {
                        continue;
                    }
                    return val;
                }
            }
            // Case-insensitive key scan
            for (String key : m.keySet()) {
                if (key != null && key.toUpperCase().contains('ORDER') && key.toUpperCase().contains('NUMBER')) {
                    Object v = m.get(key);
                    if (v != null && !(v instanceof Map<String, Object>) && !(v instanceof List<Object>)) {
                        String val = String.valueOf(v).trim();
                        if (String.isNotBlank(val) && !val.equalsIgnoreCase('true') && !val.equalsIgnoreCase('false')) {
                            return val;
                        }
                    }
                }
            }
            for (Object child : m.values()) {
                String nested = findOracleOrderNumberInObject(child, depth + 1);
                if (String.isNotBlank(nested)) {
                    return nested;
                }
            }
        } else if (node instanceof List<Object>) {
            for (Object child : (List<Object>) node) {
                String nested = findOracleOrderNumberInObject(child, depth + 1);
                if (String.isNotBlank(nested)) {
                    return nested;
                }
            }
        } else if (node instanceof String) {
            String s = ((String) node).trim();
            if (String.isBlank(s)) {
                return null;
            }
            if (s.startsWith('{') || s.startsWith('[')) {
                try {
                    return findOracleOrderNumberInObject(JSON.deserializeUntyped(s), depth + 1);
                } catch (Exception e) {
                    // fall through to regex below
                }
            }
            Matcher m = Pattern.compile(
                    '(?i)(?:"|\\b)(?:p_)?(?:Oracle_)?Order[_\\s]?Number(?:"|\\b)\\s*[:=]\\s*"?([A-Za-z0-9\\-_/]+)"?'
                )
                .matcher(s);
            if (m.find()) {
                return m.group(1);
            }
        }
        return null;
    }

    /**
     * @description GW-514: Short text summary of response payload for Integration Message diagnostics.
     */
    private static String summarizeOracleResponse(Object serviceData, Map<String, Object> responseMap) {
        try {
            if (serviceData != null) {
                if (serviceData instanceof String) {
                    return ((String) serviceData).left(1000);
                }
                return JSON.serialize(serviceData).left(1000);
            }
            if (responseMap != null) {
                Map<String, Object> copy = new Map<String, Object>(responseMap);
                // Avoid dumping huge RESTBODY echoes if present
                copy.remove('RESTBODY');
                return JSON.serialize(copy).left(1000);
            }
        } catch (Exception e) {
            return String.valueOf(serviceData).left(500);
        }
        return '';
    }

    /**
     * @description GW-514: Best-effort parse of user-facing message from SERVICE_DATA payload.
     * @param serviceData SERVICE_DATA (Map or String) from ShoutOut response.
     * @param success Whether SO_SUCCESS was true.
     * @return Message string when found; truncated raw body on fail when non-JSON.
     */
    private static String extractOracleResponseMessage(Object serviceData, Boolean success) {
        if (serviceData == null) {
            return null;
        }
        Object parsed = serviceData;
        if (serviceData instanceof String) {
            String s = ((String) serviceData).trim();
            if (String.isBlank(s)) {
                return null;
            }
            if (s.startsWith('{') || s.startsWith('[')) {
                try {
                    parsed = JSON.deserializeUntyped(s);
                } catch (Exception e) {
                    return success == true ? null : s.left(1000);
                }
            } else {
                return success == true ? null : s.left(1000);
            }
        }
        if (parsed instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) parsed;
            for (String key : new List<String>{
                'p_errbuf',
                'P_ERRBUF',
                'p_Order_Header_Status',
                'P_ORDER_HEADER_STATUS',
                'message',
                'Message',
                'ERROR_MESSAGE',
                'errorMessage',
                'statusMessage',
                'X_MSG_DATA',
                'SO_RETURN'
            }) {
                if (m.containsKey(key) && m.get(key) != null && String.isNotBlank(String.valueOf(m.get(key)))) {
                    return String.valueOf(m.get(key)).left(1000);
                }
            }
        }
        return success == true ? null : String.valueOf(serviceData).left(1000);
    }

    /**
     * @description Thrown when a ProductRequest service operation fails.
     */
    public class ProductRequestsServiceException extends Exception {}
}