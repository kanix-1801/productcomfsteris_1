/**
 * @author Oskay Taskin
 * @date 2026/09/02
 *
 * @group Repair Center Document Generation
 *
 * @description
 * GW-3600 / GW-5099 - Builds Repair Center Quote and Work Order document token data and submits
 * Document Generation requests.
 */
public with sharing class RepairCenterDocGenService {
    public static final String LOGGER_TAG = 'RepairCenterQuoteDocGen';
    public static final String SCENARIO = 'Repair Center Document Generation';
    public static final String DEFAULT_TEMPLATE_NAME = 'RepairCenterQuote';
    public static final String DEFAULT_WORK_ORDER_TEMPLATE_NAME = 'RepairCenterWorkOrder';
    public static final String DEFAULT_TEMPLATE_NAME_A4 = 'RepairCenterQuoteA4';
    public static final String DEFAULT_WORK_ORDER_TEMPLATE_NAME_A4 = 'RepairCenterWorkOrderA4';
    public static final String TOKEN_DATA_KEY = 'TokenData';
    public static final String TRANSFORM_METHOD_NAME = 'transformTokenData';

    public static final String LINE_TYPE_PRODUCT_SERVICED = 'Product Serviced';
    public static final String LINE_TYPE_CATEGORY_CODE = 'Category Code';
    public static final String LINE_TYPE_SERVICE_CODE = 'Service Code';
    public static final String LINE_TYPE_SPECIAL_PRICING = 'Special Pricing';
    public static final String LINE_TYPE_OBSERVATION_CODE = 'Observation Code';

    public static final String WORK_ORDER_TYPE_DEVICES = 'Devices';
    public static final String WORK_ORDER_TYPE_INSTRUMENTS = 'Instruments';
    public static final String RECORD_TYPE_DEVICES = 'RepairCenterDevices';
    public static final String RECORD_TYPE_INSTRUMENTS = 'RepairCenterInstruments';

    public static final String OPERATING_UNIT_US_TOKEN = 'STERIS US';
    public static final String OPERATING_UNIT_UK_TOKEN = 'STERIS UK';
    public static final String OPERATING_UNIT_US_ORG_ID = '82';
    public static final Set<String> OPERATING_UNIT_UK_ORG_IDS = new Set<String>{
        '84',
        '4871',
        '4870',
        '5689',
        '4872'
    };

    public static final String DOCUMENT_TITLE_US_ESTIMATE = 'Estimate';
    public static final String DOCUMENT_TITLE_US_RE_ESTIMATE = 'Re-Estimate';
    public static final String DOCUMENT_TITLE_UK_QUOTE = 'Quote';
    public static final String DOCUMENT_TITLE_UK_REQUOTE = 'Requote';
    public static final String DOCUMENT_TITLE_PURCHASE_ORDER_REQUIRED = 'Purchase Order Required';
    public static final String DOCUMENT_TITLE_ORDER_ACKNOWLEDGEMENT = 'Order Acknowledgement';
    public static final String ESTIMATE_TYPE_PO_REQUIRED = 'PO Required';

    public static final String DGP_TYPE = 'GenerateAndConvert';
    public static final String DGP_STATUS = 'InProgress';
    public static final String DGP_INPUT_TYPE = 'DocumentTemplate';
    public static final String DGP_ADDITIONAL_INPUT_TYPE = 'ContextService';

    /**
     * @description Invocable entry point for Flow to submit a Repair Center Quote or Work Order
     *              document generation request. Provide Quote Id or Work Order Id (not both required).
     * @param requests List of generation requests from Flow.
     * @return List of generation results containing the created process Id.
     */
    @InvocableMethod(
        label='Generate Repair Center Document'
        description='Submits a server-side Document Generation request for a Repair Center Quote or Work Order using Context Service.'
        category='Repair Center'
    )
    public static List<DocumentGenerationResult> generateDocuments(
        List<DocumentGenerationRequest> requests
    ) {
        List<DocumentGenerationResult> results = new List<DocumentGenerationResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Map<Id, String> operatingUnitByRecordId = selectOperatingUnitsForDefaultTemplates(requests);
        List<PreparedDocumentGeneration> preparedRequests = new List<PreparedDocumentGeneration>();
        Set<String> templateNames = new Set<String>();
        for (DocumentGenerationRequest request : requests) {
            PreparedDocumentGeneration prepared = prepareDocumentGeneration(
                request,
                operatingUnitByRecordId
            );
            preparedRequests.add(prepared);
            if (prepared.templateId == null && String.isNotBlank(prepared.templateName)) {
                templateNames.add(prepared.templateName);
            }
        }
        Map<String, Id> templateIdByName = DocumentTemplatesService.selectActiveIdsByNames(
            templateNames
        );

        List<DocumentGenerationProcess> processesToInsert = new List<DocumentGenerationProcess>();
        List<Integer> insertResultIndexes = new List<Integer>();
        Boolean generationFailed = false;
        for (PreparedDocumentGeneration prepared : preparedRequests) {
            DocumentGenerationResult result = new DocumentGenerationResult();
            try {
                if (prepared.errorMessage != null) {
                    throw new RepairCenterQuoteDocGenException(prepared.errorMessage);
                }
                Id templateId = prepared.templateId == null
                    ? templateIdByName.get(prepared.templateName)
                    : prepared.templateId;
                if (templateId == null) {
                    throw new RepairCenterQuoteDocGenException(
                        'No active document template was found for Repair Center document generation.'
                    );
                }
                processesToInsert.add(
                    buildDocumentGenerationProcess(
                        prepared.referenceObjectId,
                        templateId,
                        prepared.requestText
                    )
                );
                insertResultIndexes.add(results.size());
            } catch (Exception ex) {
                result.isSuccess = false;
                result.errorMessage = ex.getMessage();
                logDocumentGenerationFailure(prepared.request, ex);
                generationFailed = true;
            }
            results.add(result);
        }

        if (!processesToInsert.isEmpty()) {
            try {
                Database.SaveResult[] saveResults = Database.insert(
                    processesToInsert,
                    false,
                    AccessLevel.USER_MODE
                );
                for (Integer resultIndex = 0; resultIndex < saveResults.size(); resultIndex++) {
                    DocumentGenerationResult result = results[insertResultIndexes[resultIndex]];
                    Database.SaveResult saveResult = saveResults[resultIndex];
                    if (saveResult.isSuccess()) {
                        result.documentGenerationProcessId = saveResult.getId();
                        result.isSuccess = true;
                        continue;
                    }
                    result.isSuccess = false;
                    result.errorMessage = firstSaveError(saveResult);
                    logDocumentGenerationFailure(
                        preparedRequests[insertResultIndexes[resultIndex]].request,
                        new RepairCenterQuoteDocGenException(result.errorMessage)
                    );
                    generationFailed = true;
                }
            } catch (Exception ex) {
                for (Integer resultIndex : insertResultIndexes) {
                    results[resultIndex].isSuccess = false;
                    results[resultIndex].errorMessage = ex.getMessage();
                    logDocumentGenerationFailure(preparedRequests[resultIndex].request, ex);
                }
                generationFailed = true;
            }
        }

        if (generationFailed) {
            Logger.saveLog();
        }
        return results;
    }

    /**
     * @description Creates a DocumentGenerationProcess record for server-side Context Service generation.
     * @param referenceObjectId Quote or Work Order Id used as the root context record.
     * @param templateId Active document template Id.
     * @param requestText Optional unique request text. A default value is generated when blank.
     * @return Created DocumentGenerationProcess Id.
     */
    public static Id createDocumentGenerationProcess(
        Id referenceObjectId,
        Id templateId,
        String requestText
    ) {
        if (referenceObjectId == null) {
            throw new RepairCenterQuoteDocGenException(
                'Quote Id or Work Order Id is required.'
            );
        }
        if (templateId == null) {
            throw new RepairCenterQuoteDocGenException('Document Template Id is required.');
        }

        DocumentGenerationProcess processRecord = buildDocumentGenerationProcess(
            referenceObjectId,
            templateId,
            requestText
        );
        insert as user processRecord;
        return processRecord.Id;
    }

    private static DocumentGenerationProcess buildDocumentGenerationProcess(
        Id referenceObjectId,
        Id templateId,
        String requestText
    ) {
        if (referenceObjectId == null) {
            throw new RepairCenterQuoteDocGenException(
                'Quote Id or Work Order Id is required.'
            );
        }
        if (templateId == null) {
            throw new RepairCenterQuoteDocGenException('Document Template Id is required.');
        }

        DocumentGenerationProcess processRecord = new DocumentGenerationProcess();
        processRecord.Type = DGP_TYPE;
        processRecord.Status = DGP_STATUS;
        processRecord.DocumentInputType = DGP_INPUT_TYPE;
        processRecord.DocumentTemplateId = templateId;
        processRecord.ReferenceObject = referenceObjectId;
        processRecord.DocGenAdditionalInputType = DGP_ADDITIONAL_INPUT_TYPE;
        processRecord.DocGenAdditionalInput = String.valueOf(referenceObjectId);
        processRecord.RequestText = String.isBlank(requestText)
            ? buildDefaultRequestText(referenceObjectId)
            : requestText;
        return processRecord;
    }

    @TestVisible
    private static PreparedDocumentGeneration prepareDocumentGeneration(
        DocumentGenerationRequest request,
        Map<Id, String> operatingUnitByRecordId
    ) {
        PreparedDocumentGeneration prepared = new PreparedDocumentGeneration();
        prepared.request = request;
        if (request == null) {
            prepared.errorMessage = 'Quote Id or Work Order Id is required.';
            return prepared;
        }
        Boolean isWorkOrderRequest = request.workOrderId != null;
        prepared.referenceObjectId = isWorkOrderRequest ? request.workOrderId : request.quoteId;
        prepared.requestText = request.requestText;
        if (prepared.referenceObjectId == null) {
            prepared.errorMessage = 'Quote Id or Work Order Id is required.';
            return prepared;
        }
        prepared.templateId = request.documentTemplateId;
        if (prepared.templateId == null) {
            String defaultTemplateName = resolveDefaultTemplateName(
                isWorkOrderRequest,
                operatingUnitByRecordId.get(prepared.referenceObjectId)
            );
            prepared.templateName = String.isBlank(request.documentTemplateName)
                ? defaultTemplateName
                : request.documentTemplateName;
        }
        return prepared;
    }

    /**
     * @description GW-5833 - Returns the default template name for a request. STERIS US uses the
     *              Letter templates; every other Operating Unit, including blank, uses A4.
     * @param isWorkOrderRequest True for Order Acknowledgement (Work Order) requests.
     * @param operatingUnit Operating Unit of the Quote, or of the parent Work Order.
     * @return Default document template name.
     */
    @TestVisible
    private static String resolveDefaultTemplateName(
        Boolean isWorkOrderRequest,
        String operatingUnit
    ) {
        Boolean isLetterSize = resolveIsLetterSize(operatingUnit);
        if (isWorkOrderRequest) {
            return isLetterSize
                ? DEFAULT_WORK_ORDER_TEMPLATE_NAME
                : DEFAULT_WORK_ORDER_TEMPLATE_NAME_A4;
        }
        return isLetterSize ? DEFAULT_TEMPLATE_NAME : DEFAULT_TEMPLATE_NAME_A4;
    }

    /**
     * @description GW-5833 - Letter size is used only for STERIS US. Unlike resolveIsSterisUs,
     *              a blank or unknown Operating Unit is not treated as US here.
     * @param operatingUnit Operating Unit org Id or label.
     * @return True when the document should use the Letter template.
     */
    @TestVisible
    private static Boolean resolveIsLetterSize(String operatingUnit) {
        if (String.isBlank(operatingUnit)) {
            return false;
        }
        return OPERATING_UNIT_US_ORG_ID.equals(operatingUnit)
            || operatingUnit.contains(OPERATING_UNIT_US_TOKEN);
    }

    private static Boolean usesDefaultTemplate(DocumentGenerationRequest request) {
        return request != null
            && request.documentTemplateId == null
            && String.isBlank(request.documentTemplateName);
    }

    /**
     * @description GW-5833 - Loads the Operating Unit for each request that uses a default template.
     * @param requests Generation requests from Flow or Apex.
     * @return Quote or Work Order Id to Operating Unit.
     */
    private static Map<Id, String> selectOperatingUnitsForDefaultTemplates(
        List<DocumentGenerationRequest> requests
    ) {
        Set<Id> quoteIds = new Set<Id>();
        Set<Id> workOrderIds = new Set<Id>();
        for (DocumentGenerationRequest request : requests) {
            if (!usesDefaultTemplate(request)) {
                continue;
            }
            if (request.workOrderId != null) {
                workOrderIds.add(request.workOrderId);
            } else if (request.quoteId != null) {
                quoteIds.add(request.quoteId);
            }
        }

        Map<Id, String> operatingUnitByRecordId = new Map<Id, String>();
        operatingUnitByRecordId.putAll(selectQuoteOperatingUnits(quoteIds));
        operatingUnitByRecordId.putAll(selectWorkOrderOperatingUnits(workOrderIds));
        return operatingUnitByRecordId;
    }

    private static Map<Id, String> selectQuoteOperatingUnits(Set<Id> quoteIds) {
        Map<Id, String> operatingUnitByQuoteId = new Map<Id, String>();
        if (quoteIds.isEmpty()) {
            return operatingUnitByQuoteId;
        }
        // QuoteSelector does not extend SoqlQueryBuilder, so Quote is queried through the builder directly.
        SoqlQueryBuilder query = SoqlQueryBuilder.fromObject('Quote')
            .selectFields(new List<String>{ 'Id', 'OperatingUnit__c' });
        whereIdIn(query, quoteIds);
        for (Quote quoteRecord : (List<Quote>) query.execute()) {
            operatingUnitByQuoteId.put(quoteRecord.Id, quoteRecord.OperatingUnit__c);
        }
        return operatingUnitByQuoteId;
    }

    // The Order Acknowledgement header comes from the parent Work Order (see
    // buildWorkOrderDocumentTokenData), so the page size follows the same record.
    private static Map<Id, String> selectWorkOrderOperatingUnits(Set<Id> workOrderIds) {
        Map<Id, String> operatingUnitByWorkOrderId = new Map<Id, String>();
        if (workOrderIds.isEmpty()) {
            return operatingUnitByWorkOrderId;
        }
        SoqlQueryBuilder query = new WorkOrdersSelector()
            .selectFields(
                new List<String>{
                    'Id',
                    'OperatingUnit__c',
                    'ParentWorkOrderId',
                    'ParentWorkOrder.OperatingUnit__c'
                }
            );
        whereIdIn(query, workOrderIds);
        for (WorkOrder workOrderRecord : (List<WorkOrder>) query.execute()) {
            operatingUnitByWorkOrderId.put(
                workOrderRecord.Id,
                workOrderRecord.ParentWorkOrderId == null
                    ? workOrderRecord.OperatingUnit__c
                    : workOrderRecord.ParentWorkOrder?.OperatingUnit__c
            );
        }
        return operatingUnitByWorkOrderId;
    }

    // Binds each Id as its own filter, the same way the other Repair Center list queries do.
    private static void whereIdIn(SoqlQueryBuilder query, Set<Id> recordIds) {
        List<String> idFilterNumbers = new List<String>();
        Integer filterNumber = 1;
        for (Id recordId : recordIds) {
            query.whereEquals('Id', recordId);
            idFilterNumbers.add(String.valueOf(filterNumber));
            filterNumber++;
        }
        if (idFilterNumbers.size() > 1) {
            query.withFilterLogic(String.join(idFilterNumbers, ' OR '));
        }
    }

    private static void logDocumentGenerationFailure(
        DocumentGenerationRequest request,
        Exception ex
    ) {
        Logger.error(
            new LogMessage(
                'Document generation failed. Quote {0}, Work Order {1}: {2}',
                request == null ? null : request.quoteId,
                request == null ? null : request.workOrderId,
                ex == null ? null : ex.getMessage()
            ),
            ex
        ).addTag(LOGGER_TAG);
    }

    private static String firstSaveError(Database.SaveResult saveResult) {
        if (saveResult == null || saveResult.getErrors() == null || saveResult.getErrors().isEmpty()) {
            return 'Document generation process could not be created.';
        }
        return saveResult.getErrors()[0].getMessage();
    }

    /**
     * @description Transforms Context Service token data into the JSON structure expected by the Word template.
     * @param inputMap Input map from the document generation transform plug-in.
     * @param outputMap Output map for the transformed token data.
     */
    public static void transformTokenData(
        Map<String, Object> inputMap,
        Map<String, Object> outputMap
    ) {
        Map<String, Object> tokenData = extractTokenData(inputMap);
        Id referenceObjectId = extractReferenceObjectId(tokenData);

        if (referenceObjectId == null) {
            throw new RepairCenterQuoteDocGenException(
                'Unable to resolve Quote or Work Order Id from Context Service token data.'
            );
        }

        Map<String, Object> transformedTokenData =
            referenceObjectId.getSObjectType() == WorkOrder.SObjectType
                ? buildWorkOrderDocumentTokenData(referenceObjectId)
                : buildDocumentTokenData(referenceObjectId);
        outputMap.put(TOKEN_DATA_KEY, JSON.serialize(transformedTokenData));
    }

    /**
     * @description Builds the final token map for the Repair Center Quote document template.
     * @param quoteId Repair Center Quote Id.
     * @return Token map consumed by the Word template.
     */
    public static Map<String, Object> buildDocumentTokenData(Id quoteId) {
        Quote quoteRecord = QuoteService.selectForRepairCenterDocumentGeneration(quoteId);
        if (quoteRecord == null) {
            throw new RepairCenterQuoteDocGenException(
                'Quote record was not found for document generation.'
            );
        }

        return buildDocumentTokenDataFromQuote(
            quoteRecord,
            QuoteLineItemService.selectForRepairCenterDocumentGeneration(quoteId)
        );
    }

    /**
     * @description Builds token data from an in-memory Quote graph. Exposed for unit testing.
     * @param quoteRecord Quote record including child line items and related header values.
     * @return Token map consumed by the Word template.
     */
    @TestVisible
    private static Map<String, Object> buildDocumentTokenDataFromQuote(Quote quoteRecord) {
        return buildDocumentTokenDataFromQuote(quoteRecord, quoteRecord.QuoteLineItems);
    }

    @TestVisible
    private static Map<String, Object> buildDocumentTokenDataFromQuote(
        Quote quoteRecord,
        List<QuoteLineItem> lineItems
    ) {
        Map<String, Object> tokenData = new Map<String, Object>();
        String operatingUnit = quoteRecord.OperatingUnit__c;
        Boolean isSterisUs = resolveIsSterisUs(operatingUnit);
        Boolean isDevicesWorkOrder = isDevicesWorkOrderType(quoteRecord.WorkOrderType__c);
        Boolean isInstrumentsWorkOrder = isInstrumentsWorkOrderType(
            quoteRecord.WorkOrderType__c
        );
        Boolean isSupportedWorkOrderType = isDevicesWorkOrder || isInstrumentsWorkOrder;
        Boolean isPoRequired = quoteRecord.WorkOrder__r?.CustomerPORequired__c == true;
        Boolean isPoRequiredEstimate = isPoRequiredEstimate(quoteRecord);
        Boolean isReEstimate = isReEstimate(quoteRecord);
        String documentTitle = resolveDocumentTitle(
            isSterisUs,
            isReEstimate,
            isPoRequiredEstimate
        );

        tokenData.put('DocumentTitle', documentTitle);
        tokenData.put('IF_IsSterisUS', isSterisUs);
        tokenData.put('IF_IsSterisUK', !isSterisUs);
        tokenData.put('IF_IsDevicesWorkOrder', isDevicesWorkOrder);
        tokenData.put('IF_IsInstrumentsWorkOrder', isInstrumentsWorkOrder);
        tokenData.put('IF_IsSupportedWorkOrderType', isSupportedWorkOrderType);
        tokenData.put('IF_IsPoRequired', isPoRequired);
        tokenData.put('IF_IsReEstimate', isReEstimate);
        tokenData.put('IF_IsEstimate', !isReEstimate && !isPoRequiredEstimate);

        // GW-6001: Word uses these to show red "PO REQUIRED" when Purchase Order is blank.
        Boolean hasPurchaseOrder = String.isNotBlank(quoteRecord.PurchaseOrder__c);
        tokenData.put('IF_HasPurchaseOrder', hasPurchaseOrder);
        tokenData.put('IF_IsPurchaseOrderBlank', !hasPurchaseOrder);

        tokenData.put('ReturnOrderNumber', nullSafeString(quoteRecord.ReturnOrderNumber__c));
        tokenData.put('WorkOrderNumber', nullSafeString(quoteRecord.WorkOrderNumber__c));
        tokenData.put('PurchaseOrder', nullSafeString(quoteRecord.PurchaseOrder__c));
        tokenData.put('Version', quoteRecord.Version__c);
        // Screenshot 1: Print Date is today's date at generation time.
        tokenData.put('PrintDate', formatDate(Date.today()));
        tokenData.put('CurrencyCode', nullSafeString(quoteRecord.CurrencyIsoCode));

        putTwoLineAddress(
            tokenData,
            'BillToStreet',
            'BillToCityLine',
            'BillTo',
            quoteRecord.BillingStreet,
            quoteRecord.BillingCity,
            String.isNotBlank(quoteRecord.BillingState)
                ? quoteRecord.BillingState
                : quoteRecord.BillingStateCode,
            quoteRecord.BillingPostalCode
        );
        putTwoLineAddress(
            tokenData,
            'ShipToStreet',
            'ShipToCityLine',
            'ShipTo',
            quoteRecord.ShippingStreet,
            quoteRecord.ShippingCity,
            String.isNotBlank(quoteRecord.ShippingState)
                ? quoteRecord.ShippingState
                : quoteRecord.ShippingStateCode,
            quoteRecord.ShippingPostalCode
        );

        tokenData.put(
            'AccountName',
            formatCustomerNameWithNumber(
                quoteRecord.AccountName__c,
                quoteRecord.QuoteAccount?.AccountNumber
            )
        );
        String quoteContactName = quoteRecord.WorkOrder__r?.EstimateContact__r?.Name;
        // Estimate Contact is the quote recipient. Use the Work Order Contact when it is blank.
        if (String.isBlank(quoteContactName)) {
            quoteContactName = quoteRecord.WorkOrder__r?.Contact?.Name;
        }
        tokenData.put('ContactName', nullSafeString(quoteContactName));
        tokenData.put('AccountManager', nullSafeString(quoteRecord.AccountManager__c));
        tokenData.put('DepartmentName', nullSafeString(quoteRecord.DepartmentName__c));
        tokenData.put('CustomerReference', nullSafeString(quoteRecord.CustomerReference__c));

        List<QuoteLineItem> resolvedLineItems = lineItems == null
            ? new List<QuoteLineItem>()
            : lineItems;

        if (!isSupportedWorkOrderType) {
            tokenData.put('ProductServicedItems', new List<Map<String, Object>>());
            tokenData.put('GrandTotal', formatCurrency(0, quoteRecord.CurrencyIsoCode));
            tokenData.put('RepairEvaluationGroups', new List<Map<String, Object>>());
            tokenData.put('RepairEvaluationRows', new List<Map<String, Object>>());
            return tokenData;
        }

        Map<Id, List<QuoteLineItem>> childLinesByParentId = buildChildLinesByParentId(resolvedLineItems);
        List<Map<String, Object>> productServicedItems = buildProductServicedItems(
            resolvedLineItems,
            childLinesByParentId,
            quoteRecord.WorkOrderType__c,
            isDevicesWorkOrder,
            isInstrumentsWorkOrder,
            quoteRecord.CurrencyIsoCode
        );
        tokenData.put('ProductServicedItems', productServicedItems);
        tokenData.put(
            'GrandTotal',
            formatCurrency(sumItemTotals(productServicedItems), quoteRecord.CurrencyIsoCode)
        );

        if (isDevicesWorkOrder) {
            tokenData.put(
                'RepairEvaluationGroups',
                buildRepairEvaluationGroups(resolvedLineItems)
            );
            tokenData.put(
                'RepairEvaluationRows',
                buildRepairEvaluationRows(resolvedLineItems)
            );
        } else {
            tokenData.put('RepairEvaluationGroups', new List<Map<String, Object>>());
            tokenData.put('RepairEvaluationRows', new List<Map<String, Object>>());
        }

        return tokenData;
    }

    /**
     * @description Builds the final token map for the Repair Center Work Order document template.
     * @param workOrderId Repair Center Work Order Id.
     * @return Token map consumed by the Word template.
     */
    public static Map<String, Object> buildWorkOrderDocumentTokenData(Id workOrderId) {
        WorkOrder seedWorkOrder =
            WorkOrdersService.selectForRepairCenterDocumentGeneration(workOrderId);
        if (seedWorkOrder == null) {
            throw new RepairCenterQuoteDocGenException(
                'Work Order record was not found for document generation.'
            );
        }

        Id familyRootId = WorkOrdersService.resolveDocumentFamilyRootId(seedWorkOrder);
        WorkOrder headerWorkOrder = familyRootId == seedWorkOrder.Id
            ? seedWorkOrder
            : WorkOrdersService.selectForRepairCenterDocumentGeneration(familyRootId);
        if (headerWorkOrder == null) {
            throw new RepairCenterQuoteDocGenException(
                'Work Order record was not found for document generation.'
            );
        }

        List<WorkOrderLineItem> familyLineItems =
            WorkOrderLineItemsService.selectForRepairCenterDocumentGeneration(familyRootId);
        return buildDocumentTokenDataFromWorkOrder(headerWorkOrder, familyLineItems);
    }

    /**
     * @description Builds token data from an in-memory Work Order graph. Exposed for unit testing.
     * @param workOrderRecord Work Order header values for the Order Acknowledgement.
     * @return Token map consumed by the Word template.
     */
    @TestVisible
    private static Map<String, Object> buildDocumentTokenDataFromWorkOrder(
        WorkOrder workOrderRecord
    ) {
        return buildDocumentTokenDataFromWorkOrder(
            workOrderRecord,
            new List<WorkOrderLineItem>()
        );
    }

    @TestVisible
    private static Map<String, Object> buildDocumentTokenDataFromWorkOrder(
        WorkOrder workOrderRecord,
        List<WorkOrderLineItem> lineItems
    ) {
        Map<String, Object> tokenData = new Map<String, Object>();
        String operatingUnit = workOrderRecord.OperatingUnit__c;
        Boolean isSterisUs = resolveIsSterisUs(operatingUnit);
        String recordTypeDeveloperName = workOrderRecord.RecordType?.DeveloperName;
        Boolean isDevicesWorkOrder = isDevicesRecordType(recordTypeDeveloperName);
        Boolean isInstrumentsWorkOrder = isInstrumentsRecordType(recordTypeDeveloperName);
        Boolean isSupportedWorkOrderType = isDevicesWorkOrder || isInstrumentsWorkOrder;
        String workOrderType = isDevicesWorkOrder
            ? WORK_ORDER_TYPE_DEVICES
            : (isInstrumentsWorkOrder ? WORK_ORDER_TYPE_INSTRUMENTS : null);

        tokenData.put('DocumentTitle', DOCUMENT_TITLE_ORDER_ACKNOWLEDGEMENT);
        tokenData.put('IF_IsSterisUS', isSterisUs);
        tokenData.put('IF_IsSterisUK', !isSterisUs);
        tokenData.put('IF_IsDevicesWorkOrder', isDevicesWorkOrder);
        tokenData.put('IF_IsInstrumentsWorkOrder', isInstrumentsWorkOrder);
        tokenData.put('IF_IsSupportedWorkOrderType', isSupportedWorkOrderType);
        tokenData.put('IF_IsPoRequired', false);
        tokenData.put('IF_IsReEstimate', false);
        tokenData.put('IF_IsEstimate', false);

        tokenData.put('ReturnOrderNumber', nullSafeString(workOrderRecord.ReturnOrderNumber__c));
        tokenData.put('WorkOrderNumber', nullSafeString(workOrderRecord.WorkOrderNumber));
        tokenData.put('PurchaseOrder', nullSafeString(workOrderRecord.CustomerPO__c));
        tokenData.put('Version', '');
        tokenData.put('PrintDate', formatDate(Date.today()));
        tokenData.put('CurrencyCode', nullSafeString(workOrderRecord.CurrencyIsoCode));

        putTwoLineAddress(
            tokenData,
            'BillToStreet',
            'BillToCityLine',
            'BillTo',
            workOrderRecord.BillToAddress__Street__s,
            workOrderRecord.BillToAddress__City__s,
            workOrderRecord.BillToAddress__StateCode__s,
            workOrderRecord.BillToAddress__PostalCode__s
        );
        putTwoLineAddress(
            tokenData,
            'ShipToStreet',
            'ShipToCityLine',
            'ShipTo',
            workOrderRecord.Street,
            workOrderRecord.City,
            String.isNotBlank(workOrderRecord.State)
                ? workOrderRecord.State
                : workOrderRecord.StateCode,
            workOrderRecord.PostalCode
        );

        tokenData.put(
            'AccountName',
            formatCustomerNameWithNumber(
                workOrderRecord.Account?.Name,
                workOrderRecord.Account?.AccountNumber
            )
        );
        tokenData.put('ContactName', nullSafeString(workOrderRecord.Contact?.Name));
        tokenData.put('AccountManager', nullSafeString(workOrderRecord.AccountManager__c));
        tokenData.put('DepartmentName', nullSafeString(workOrderRecord.DepartmentName__c));
        tokenData.put('CustomerReference', nullSafeString(workOrderRecord.CustomerReference__c));

        List<WorkOrderLineItem> resolvedLineItems = lineItems == null
            ? new List<WorkOrderLineItem>()
            : lineItems;

        if (!isSupportedWorkOrderType) {
            tokenData.put('ProductServicedItems', new List<Map<String, Object>>());
            tokenData.put('GrandTotal', formatCurrency(0, workOrderRecord.CurrencyIsoCode));
            tokenData.put('RepairEvaluationGroups', new List<Map<String, Object>>());
            tokenData.put('RepairEvaluationRows', new List<Map<String, Object>>());
            return tokenData;
        }

        Map<Id, List<WorkOrderLineItem>> childLinesByParentId =
            buildWorkOrderChildLinesByParentId(resolvedLineItems);
        List<Map<String, Object>> productServicedItems = buildWorkOrderProductServicedItems(
            resolvedLineItems,
            childLinesByParentId,
            workOrderType,
            isDevicesWorkOrder,
            isInstrumentsWorkOrder,
            workOrderRecord.CurrencyIsoCode
        );
        tokenData.put('ProductServicedItems', productServicedItems);
        tokenData.put(
            'GrandTotal',
            formatCurrency(sumItemTotals(productServicedItems), workOrderRecord.CurrencyIsoCode)
        );

        if (isDevicesWorkOrder) {
            tokenData.put(
                'RepairEvaluationGroups',
                buildWorkOrderRepairEvaluationGroups(resolvedLineItems)
            );
            tokenData.put(
                'RepairEvaluationRows',
                buildWorkOrderRepairEvaluationRows(resolvedLineItems)
            );
        } else {
            tokenData.put('RepairEvaluationGroups', new List<Map<String, Object>>());
            tokenData.put('RepairEvaluationRows', new List<Map<String, Object>>());
        }

        return tokenData;
    }

    private static Map<String, Object> extractTokenData(Map<String, Object> inputMap) {
        if (inputMap == null || !inputMap.containsKey(TOKEN_DATA_KEY)) {
            return new Map<String, Object>();
        }

        Object tokenDataObject = inputMap.get(TOKEN_DATA_KEY);
        if (tokenDataObject instanceof Map<String, Object>) {
            return (Map<String, Object>) tokenDataObject;
        }

        if (tokenDataObject instanceof String) {
            String tokenDataJson = (String) tokenDataObject;
            if (String.isBlank(tokenDataJson)) {
                return new Map<String, Object>();
            }

            Object deserialized = JSON.deserializeUntyped(tokenDataJson);
            if (deserialized instanceof Map<String, Object>) {
                return (Map<String, Object>) deserialized;
            }
        }

        return new Map<String, Object>();
    }

    private static Id extractReferenceObjectId(Map<String, Object> tokenData) {
        if (tokenData == null || tokenData.isEmpty()) {
            return null;
        }

        Object workOrderNode = tokenData.get('WorkOrder');
        if (workOrderNode instanceof Map<String, Object>) {
            Map<String, Object> workOrderMap = (Map<String, Object>) workOrderNode;
            return toId(workOrderMap.get('Id'));
        }

        Object quoteNode = tokenData.get('Quote');
        if (quoteNode instanceof Map<String, Object>) {
            Map<String, Object> quoteMap = (Map<String, Object>) quoteNode;
            return toId(quoteMap.get('Id'));
        }

        return toId(tokenData.get('Id'));
    }

    private static Id toId(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return (Id) String.valueOf(value);
        } catch (Exception ex) {
            Logger.debug(
                new LogMessage(
                    'RepairCenterDocGenService.toId could not parse {0}: {1}',
                    String.valueOf(value),
                    ex.getMessage()
                )
            );
            return null;
        }
    }

    private static String buildDefaultRequestText(Id referenceObjectId) {
        if (referenceObjectId != null &&
            referenceObjectId.getSObjectType() == WorkOrder.SObjectType
        ) {
            WorkOrder workOrderRecord =
                WorkOrdersService.selectForRepairCenterDocumentGeneration(referenceObjectId);
            return JSON.serialize(
                new Map<String, Object>{
                    'keepIntermediate' => false,
                    'title' => buildWorkOrderDocumentFileTitle(workOrderRecord, referenceObjectId)
                }
            );
        }

        Quote quoteRecord = QuoteService.selectForRepairCenterDocumentGeneration(referenceObjectId);
        return JSON.serialize(
            new Map<String, Object>{
                'keepIntermediate' => false,
                'title' => buildDocumentFileTitle(quoteRecord, referenceObjectId)
            }
        );
    }

    /**
     * @description Builds the ContentVersion title: QuoteNumber-AccountNumber-VVersion.
     * @param quoteRecord Quote with naming fields populated.
     * @param quoteId Fallback Id when Quote Number is unavailable.
     * @return Document file title.
     */
    @TestVisible
    private static String buildDocumentFileTitle(Quote quoteRecord, Id quoteId) {
        String quoteNumber = nullSafeString(quoteRecord?.QuoteNumber);
        if (String.isBlank(quoteNumber)) {
            quoteNumber = quoteId == null ? 'RepairCenterQuote' : String.valueOf(quoteId);
        }

        String accountNumber = nullSafeString(quoteRecord?.QuoteAccount?.AccountNumber);
        Integer versionNumber = quoteRecord?.Version__c == null
            ? 1
            : Integer.valueOf(quoteRecord.Version__c);

        return quoteNumber + '-' + accountNumber + '-V' + String.valueOf(versionNumber);
    }

    /**
     * @description Builds the ContentVersion title: WorkOrderNumber-AccountNumber.
     * @param workOrderRecord Work Order with naming fields populated.
     * @param workOrderId Fallback Id when Work Order Number is unavailable.
     * @return Document file title.
     */
    @TestVisible
    private static String buildWorkOrderDocumentFileTitle(
        WorkOrder workOrderRecord,
        Id workOrderId
    ) {
        String workOrderNumber = nullSafeString(workOrderRecord?.WorkOrderNumber);
        if (String.isBlank(workOrderNumber)) {
            workOrderNumber = workOrderId == null
                ? 'RepairCenterWorkOrder'
                : String.valueOf(workOrderId);
        }

        String accountNumber = nullSafeString(workOrderRecord?.Account?.AccountNumber);
        return workOrderNumber + '-' + accountNumber;
    }

    @TestVisible
    private static Boolean resolveIsSterisUs(String operatingUnit) {
        if (String.isBlank(operatingUnit)) {
            return true;
        }
        if (OPERATING_UNIT_UK_ORG_IDS.contains(operatingUnit)) {
            return false;
        }
        if (OPERATING_UNIT_US_ORG_ID.equals(operatingUnit)) {
            return true;
        }
        if (operatingUnit.contains(OPERATING_UNIT_UK_TOKEN)) {
            return false;
        }
        if (operatingUnit.contains(OPERATING_UNIT_US_TOKEN)) {
            return true;
        }
        return true;
    }

    private static Boolean isDevicesWorkOrderType(String workOrderType) {
        return WORK_ORDER_TYPE_DEVICES.equalsIgnoreCase(workOrderType);
    }

    private static Boolean isInstrumentsWorkOrderType(String workOrderType) {
        return WORK_ORDER_TYPE_INSTRUMENTS.equalsIgnoreCase(workOrderType);
    }

    private static Boolean isDevicesRecordType(String recordTypeDeveloperName) {
        return RECORD_TYPE_DEVICES.equalsIgnoreCase(recordTypeDeveloperName);
    }

    private static Boolean isInstrumentsRecordType(String recordTypeDeveloperName) {
        return RECORD_TYPE_INSTRUMENTS.equalsIgnoreCase(recordTypeDeveloperName);
    }

    private static Boolean isReEstimate(Quote quoteRecord) {
        if (quoteRecord.Version__c != null && quoteRecord.Version__c > 1) {
            return true;
        }
        return 'Re-Estimate'.equalsIgnoreCase(quoteRecord.EstimateType__c);
    }

    private static Boolean isPoRequiredEstimate(Quote quoteRecord) {
        return ESTIMATE_TYPE_PO_REQUIRED.equalsIgnoreCase(quoteRecord.EstimateType__c);
    }

    /**
     * @description Resolves Quote document titles: Purchase Order Required, then US/UK Estimate vs Requote.
     * US: Estimate | Re-Estimate
     * UK: Quote | Requote
     */
    @TestVisible
    private static String resolveDocumentTitle(
        Boolean isSterisUs,
        Boolean isReEstimate,
        Boolean isPoRequiredEstimate
    ) {
        if (isPoRequiredEstimate) {
            return DOCUMENT_TITLE_PURCHASE_ORDER_REQUIRED;
        }
        if (isSterisUs) {
            return isReEstimate
                ? DOCUMENT_TITLE_US_RE_ESTIMATE
                : DOCUMENT_TITLE_US_ESTIMATE;
        }
        return isReEstimate
            ? DOCUMENT_TITLE_UK_REQUOTE
            : DOCUMENT_TITLE_UK_QUOTE;
    }

    private static Map<Id, List<QuoteLineItem>> buildChildLinesByParentId(
        List<QuoteLineItem> lineItems
    ) {
        Map<Id, List<QuoteLineItem>> childLinesByParentId = new Map<Id, List<QuoteLineItem>>();
        List<QuoteLineItem> orphanChildLines = new List<QuoteLineItem>();

        for (QuoteLineItem lineItem : lineItems) {
            if (!isChildServiceLine(lineItem.LineType__c)) {
                continue;
            }

            if (lineItem.ParentQuoteLineItemId == null) {
                orphanChildLines.add(lineItem);
                continue;
            }

            if (!childLinesByParentId.containsKey(lineItem.ParentQuoteLineItemId)) {
                childLinesByParentId.put(
                    lineItem.ParentQuoteLineItemId,
                    new List<QuoteLineItem>()
                );
            }
            childLinesByParentId.get(lineItem.ParentQuoteLineItemId).add(lineItem);
        }

        if (!orphanChildLines.isEmpty()) {
            Map<Id, Id> productServicedIdByWoliId = buildProductServicedIdByWorkOrderLineItemId(
                lineItems
            );
            Map<String, Id> productServicedIdBySerial = buildProductServicedIdBySerial(
                lineItems
            );
            Id soleParentId = resolveFallbackProductServicedParentId(lineItems);

            for (QuoteLineItem orphanChild : orphanChildLines) {
                Id parentId = null;
                if (
                    orphanChild.ParentWorkOrderLineItem__c != null &&
                    productServicedIdByWoliId.containsKey(
                        orphanChild.ParentWorkOrderLineItem__c
                    )
                ) {
                    parentId = productServicedIdByWoliId.get(
                        orphanChild.ParentWorkOrderLineItem__c
                    );
                }

                String serialNumber = nullSafeString(orphanChild.SerialNumber__c);
                if (
                    parentId == null &&
                    String.isNotBlank(serialNumber) &&
                    productServicedIdBySerial.containsKey(serialNumber)
                ) {
                    parentId = productServicedIdBySerial.get(serialNumber);
                } else if (parentId == null) {
                    parentId = soleParentId;
                }

                if (parentId == null) {
                    continue;
                }

                if (!childLinesByParentId.containsKey(parentId)) {
                    childLinesByParentId.put(parentId, new List<QuoteLineItem>());
                }
                childLinesByParentId.get(parentId).add(orphanChild);
            }
        }

        return childLinesByParentId;
    }

    private static Map<Id, Id> buildProductServicedIdByWorkOrderLineItemId(
        List<QuoteLineItem> lineItems
    ) {
        Map<Id, Id> productServicedIdByWoliId = new Map<Id, Id>();
        for (QuoteLineItem lineItem : lineItems) {
            if (!LINE_TYPE_PRODUCT_SERVICED.equalsIgnoreCase(lineItem.LineType__c)) {
                continue;
            }
            if (lineItem.WorkOrderLineItem__c == null) {
                continue;
            }
            productServicedIdByWoliId.put(lineItem.WorkOrderLineItem__c, lineItem.Id);
        }
        return productServicedIdByWoliId;
    }

    private static Map<String, Id> buildProductServicedIdBySerial(
        List<QuoteLineItem> lineItems
    ) {
        Map<String, Id> productServicedIdBySerial = new Map<String, Id>();
        for (QuoteLineItem lineItem : lineItems) {
            if (!LINE_TYPE_PRODUCT_SERVICED.equalsIgnoreCase(lineItem.LineType__c)) {
                continue;
            }
            String serialNumber = nullSafeString(lineItem.SerialNumber__c);
            if (String.isBlank(serialNumber)) {
                continue;
            }
            productServicedIdBySerial.put(serialNumber, lineItem.Id);
        }
        return productServicedIdBySerial;
    }

    private static Id resolveFallbackProductServicedParentId(
        List<QuoteLineItem> lineItems
    ) {
        Id soleParentId = null;

        for (QuoteLineItem lineItem : lineItems) {
            if (!LINE_TYPE_PRODUCT_SERVICED.equalsIgnoreCase(lineItem.LineType__c)) {
                continue;
            }

            if (soleParentId != null) {
                return null;
            }

            soleParentId = lineItem.Id;
        }

        return soleParentId;
    }

    private static Boolean isChildServiceLine(String lineType) {
        return LINE_TYPE_CATEGORY_CODE.equalsIgnoreCase(lineType)
            || LINE_TYPE_SERVICE_CODE.equalsIgnoreCase(lineType)
            || LINE_TYPE_SPECIAL_PRICING.equalsIgnoreCase(lineType);
    }

    private static List<Map<String, Object>> buildProductServicedItems(
        List<QuoteLineItem> lineItems,
        Map<Id, List<QuoteLineItem>> childLinesByParentId,
        String workOrderType,
        Boolean isDevicesWorkOrder,
        Boolean isInstrumentsWorkOrder,
        String currencyIsoCode
    ) {
        List<Map<String, Object>> productServicedItems = new List<Map<String, Object>>();

        for (QuoteLineItem lineItem : lineItems) {
            if (!LINE_TYPE_PRODUCT_SERVICED.equalsIgnoreCase(lineItem.LineType__c)) {
                continue;
            }

            List<QuoteLineItem> childLines = childLinesByParentId.containsKey(lineItem.Id)
                ? childLinesByParentId.get(lineItem.Id)
                : new List<QuoteLineItem>();

            Decimal itemTotal = sumChildLineTotals(childLines);
            Map<String, Object> itemMap = new Map<String, Object>();
            itemMap.put('ItemNumber', resolveItemNumber(lineItem, workOrderType));
            itemMap.put('Status', nullSafeString(lineItem.Status__c));
            itemMap.put('TurnTime', lineItem.TurnTime__c);
            itemMap.put('ProductDescription', nullSafeString(lineItem.ProductDescription__c));
            itemMap.put(
                'RecommendedServices',
                buildRecommendedServices(childLines, currencyIsoCode)
            );
            itemMap.put(
                'ReturnOrderLineItems',
                buildReturnOrderLineItems(lineItem, isInstrumentsWorkOrder)
            );
            itemMap.put('ItemTotalAmount', itemTotal);
            itemMap.put('ItemTotal', formatCurrency(itemTotal, currencyIsoCode));
            // Customer Facing Evaluator Comments = Evaluation Notes on the Product Serviced
            // line's Work Order (child device WO), not the parent Quote Work Order.
            itemMap.put(
                'EvaluationNotes',
                isDevicesWorkOrder
                    ? nullSafeString(
                          lineItem.WorkOrderLineItem__r?.WorkOrder?.EvaluationNotes__c
                      )
                    : ''
            );
            productServicedItems.add(itemMap);
        }

        return productServicedItems;
    }

    private static String resolveItemNumber(QuoteLineItem lineItem, String workOrderType) {
        if (WORK_ORDER_TYPE_INSTRUMENTS.equalsIgnoreCase(workOrderType)) {
            return nullSafeString(lineItem.ProductCode__c);
        }
        // Devices (and any future supported types defaulting to serial)
        return nullSafeString(lineItem.SerialNumber__c);
    }

    private static List<Map<String, Object>> buildRecommendedServices(
        List<QuoteLineItem> childLines,
        String currencyIsoCode
    ) {
        List<Map<String, Object>> recommendedServices = new List<Map<String, Object>>();

        for (QuoteLineItem childLine : childLines) {
            Map<String, Object> serviceMap = new Map<String, Object>();
            serviceMap.put('ProductCode', nullSafeString(childLine.ProductCode__c));
            serviceMap.put(
                'ServiceDescription',
                nullSafeString(childLine.ProductDescription__c)
            );
            serviceMap.put('Quantity', childLine.Quantity);
            serviceMap.put('UOM', resolveUom(childLine.UOM__c));
            serviceMap.put(
                'TotalPrice',
                formatCurrency(childLine.NetTotalPrice__c, currencyIsoCode)
            );
            recommendedServices.add(serviceMap);
        }

        return recommendedServices;
    }

    private static List<Map<String, Object>> buildReturnOrderLineItems(
        QuoteLineItem parentLineItem,
        Boolean isInstrumentsWorkOrder
    ) {
        List<Map<String, Object>> returnOrderLineItems = new List<Map<String, Object>>();
        if (!isInstrumentsWorkOrder) {
            return returnOrderLineItems;
        }

        String returnOrderLineItemsValue = parentLineItem.ReturnOrderLineItems__c;
        if (String.isBlank(returnOrderLineItemsValue)) {
            return returnOrderLineItems;
        }

        Map<String, Object> returnOrderLineItemMap = new Map<String, Object>();
        returnOrderLineItemMap.put('DisplayValue', returnOrderLineItemsValue);
        returnOrderLineItems.add(returnOrderLineItemMap);
        return returnOrderLineItems;
    }

    private static List<Map<String, Object>> buildRepairEvaluationGroups(
        List<QuoteLineItem> lineItems
    ) {
        Map<String, List<Map<String, Object>>> observationsBySerial = new Map<String, List<Map<String, Object>>>();

        for (QuoteLineItem lineItem : lineItems) {
            if (!LINE_TYPE_OBSERVATION_CODE.equalsIgnoreCase(lineItem.LineType__c)) {
                continue;
            }

            String serialNumber = nullSafeString(lineItem.SerialNumber__c);
            if (!observationsBySerial.containsKey(serialNumber)) {
                observationsBySerial.put(serialNumber, new List<Map<String, Object>>());
            }

            Map<String, Object> observationMap = new Map<String, Object>();
            observationMap.put(
                'ObservationDescription',
                nullSafeString(lineItem.ProductDescription__c)
            );
            observationMap.put('Condition', nullSafeString(lineItem.Condition__c));
            observationsBySerial.get(serialNumber).add(observationMap);
        }

        List<Map<String, Object>> repairEvaluationGroups = new List<Map<String, Object>>();
        for (String serialNumber : observationsBySerial.keySet()) {
            Map<String, Object> groupMap = new Map<String, Object>();
            groupMap.put('SerialNumber', serialNumber);
            groupMap.put('Observations', observationsBySerial.get(serialNumber));
            repairEvaluationGroups.add(groupMap);
        }

        return repairEvaluationGroups;
    }

    private static List<Map<String, Object>> buildRepairEvaluationRows(
        List<QuoteLineItem> lineItems
    ) {
        List<Map<String, Object>> repairEvaluationRows = new List<Map<String, Object>>();

        for (QuoteLineItem lineItem : lineItems) {
            if (!LINE_TYPE_OBSERVATION_CODE.equalsIgnoreCase(lineItem.LineType__c)) {
                continue;
            }

            Map<String, Object> rowMap = new Map<String, Object>();
            rowMap.put('SerialNumber', nullSafeString(lineItem.SerialNumber__c));
            rowMap.put(
                'ObservationDescription',
                nullSafeString(lineItem.ProductDescription__c)
            );
            rowMap.put('Condition', nullSafeString(lineItem.Condition__c));
            repairEvaluationRows.add(rowMap);
        }

        return repairEvaluationRows;
    }

    private static Map<Id, List<WorkOrderLineItem>> buildWorkOrderChildLinesByParentId(
        List<WorkOrderLineItem> lineItems
    ) {
        Map<Id, List<WorkOrderLineItem>> childLinesByParentId =
            new Map<Id, List<WorkOrderLineItem>>();
        List<WorkOrderLineItem> orphanChildLines = new List<WorkOrderLineItem>();

        for (WorkOrderLineItem lineItem : lineItems) {
            if (!isChildServiceLine(lineItem.LineType__c)) {
                continue;
            }

            if (lineItem.ParentWorkOrderLineItemId == null) {
                orphanChildLines.add(lineItem);
                continue;
            }

            if (!childLinesByParentId.containsKey(lineItem.ParentWorkOrderLineItemId)) {
                childLinesByParentId.put(
                    lineItem.ParentWorkOrderLineItemId,
                    new List<WorkOrderLineItem>()
                );
            }
            childLinesByParentId.get(lineItem.ParentWorkOrderLineItemId).add(lineItem);
        }

        if (!orphanChildLines.isEmpty()) {
            Map<String, Id> productServicedIdBySerial =
                buildWorkOrderProductServicedIdBySerial(lineItems);
            Id soleParentId = resolveWorkOrderFallbackProductServicedParentId(lineItems);

            for (WorkOrderLineItem orphanChild : orphanChildLines) {
                Id parentId = null;
                String serialNumber = nullSafeString(orphanChild.SerialNumber__c);
                if (
                    String.isNotBlank(serialNumber) &&
                    productServicedIdBySerial.containsKey(serialNumber)
                ) {
                    parentId = productServicedIdBySerial.get(serialNumber);
                } else {
                    parentId = soleParentId;
                }

                if (parentId == null) {
                    continue;
                }

                if (!childLinesByParentId.containsKey(parentId)) {
                    childLinesByParentId.put(parentId, new List<WorkOrderLineItem>());
                }
                childLinesByParentId.get(parentId).add(orphanChild);
            }
        }

        return childLinesByParentId;
    }

    private static Map<String, Id> buildWorkOrderProductServicedIdBySerial(
        List<WorkOrderLineItem> lineItems
    ) {
        Map<String, Id> productServicedIdBySerial = new Map<String, Id>();
        for (WorkOrderLineItem lineItem : lineItems) {
            if (!LINE_TYPE_PRODUCT_SERVICED.equalsIgnoreCase(lineItem.LineType__c)) {
                continue;
            }
            String serialNumber = nullSafeString(lineItem.SerialNumber__c);
            if (String.isBlank(serialNumber)) {
                continue;
            }
            productServicedIdBySerial.put(serialNumber, lineItem.Id);
        }
        return productServicedIdBySerial;
    }

    private static Id resolveWorkOrderFallbackProductServicedParentId(
        List<WorkOrderLineItem> lineItems
    ) {
        Id soleParentId = null;

        for (WorkOrderLineItem lineItem : lineItems) {
            if (!LINE_TYPE_PRODUCT_SERVICED.equalsIgnoreCase(lineItem.LineType__c)) {
                continue;
            }

            if (soleParentId != null) {
                return null;
            }

            soleParentId = lineItem.Id;
        }

        return soleParentId;
    }

    private static List<Map<String, Object>> buildWorkOrderProductServicedItems(
        List<WorkOrderLineItem> lineItems,
        Map<Id, List<WorkOrderLineItem>> childLinesByParentId,
        String workOrderType,
        Boolean isDevicesWorkOrder,
        Boolean isInstrumentsWorkOrder,
        String currencyIsoCode
    ) {
        List<Map<String, Object>> productServicedItems = new List<Map<String, Object>>();

        for (WorkOrderLineItem lineItem : lineItems) {
            if (!LINE_TYPE_PRODUCT_SERVICED.equalsIgnoreCase(lineItem.LineType__c)) {
                continue;
            }

            List<WorkOrderLineItem> childLines = childLinesByParentId.containsKey(lineItem.Id)
                ? childLinesByParentId.get(lineItem.Id)
                : new List<WorkOrderLineItem>();

            Decimal itemTotal = sumWorkOrderChildLineTotals(childLines);
            Map<String, Object> itemMap = new Map<String, Object>();
            itemMap.put('ItemNumber', resolveWorkOrderItemNumber(lineItem, workOrderType));
            itemMap.put('Status', nullSafeString(lineItem.Status));
            itemMap.put('TurnTime', lineItem.TurnTime__c);
            itemMap.put('ProductDescription', nullSafeString(lineItem.ProductDescription__c));
            itemMap.put(
                'RecommendedServices',
                buildWorkOrderRecommendedServices(childLines, currencyIsoCode)
            );
            itemMap.put(
                'ReturnOrderLineItems',
                buildWorkOrderReturnOrderLineItems(lineItem, isInstrumentsWorkOrder)
            );
            itemMap.put('ItemTotalAmount', itemTotal);
            itemMap.put('ItemTotal', formatCurrency(itemTotal, currencyIsoCode));
            // Customer Facing Evaluator Comments = Evaluation Notes on the Product Serviced
            // line's Work Order (child device WO), matching Quote doc-gen behavior.
            itemMap.put(
                'EvaluationNotes',
                isDevicesWorkOrder
                    ? nullSafeString(lineItem.WorkOrder?.EvaluationNotes__c)
                    : ''
            );
            productServicedItems.add(itemMap);
        }

        return productServicedItems;
    }

    private static String resolveWorkOrderItemNumber(
        WorkOrderLineItem lineItem,
        String workOrderType
    ) {
        if (WORK_ORDER_TYPE_INSTRUMENTS.equalsIgnoreCase(workOrderType)) {
            return nullSafeString(lineItem.ProductCode__c);
        }
        return nullSafeString(lineItem.SerialNumber__c);
    }

    private static List<Map<String, Object>> buildWorkOrderRecommendedServices(
        List<WorkOrderLineItem> childLines,
        String currencyIsoCode
    ) {
        List<Map<String, Object>> recommendedServices = new List<Map<String, Object>>();

        for (WorkOrderLineItem childLine : childLines) {
            Map<String, Object> serviceMap = new Map<String, Object>();
            serviceMap.put('ProductCode', nullSafeString(childLine.ProductCode__c));
            serviceMap.put(
                'ServiceDescription',
                nullSafeString(childLine.ProductDescription__c)
            );
            serviceMap.put('Quantity', childLine.Quantity);
            serviceMap.put(
                'UOM',
                resolveUom(childLine.Product2?.QuantityUnitOfMeasure)
            );
            serviceMap.put(
                'TotalPrice',
                formatCurrency(childLine.NetTotalPrice__c, currencyIsoCode)
            );
            recommendedServices.add(serviceMap);
        }

        return recommendedServices;
    }

    private static List<Map<String, Object>> buildWorkOrderReturnOrderLineItems(
        WorkOrderLineItem parentLineItem,
        Boolean isInstrumentsWorkOrder
    ) {
        List<Map<String, Object>> returnOrderLineItems = new List<Map<String, Object>>();
        if (!isInstrumentsWorkOrder) {
            return returnOrderLineItems;
        }

        String returnOrderLineItemsValue = parentLineItem.ReturnOrderLineItems__c;
        if (String.isBlank(returnOrderLineItemsValue)) {
            return returnOrderLineItems;
        }

        Map<String, Object> returnOrderLineItemMap = new Map<String, Object>();
        returnOrderLineItemMap.put('DisplayValue', returnOrderLineItemsValue);
        returnOrderLineItems.add(returnOrderLineItemMap);
        return returnOrderLineItems;
    }

    private static List<Map<String, Object>> buildWorkOrderRepairEvaluationGroups(
        List<WorkOrderLineItem> lineItems
    ) {
        Map<String, List<Map<String, Object>>> observationsBySerial =
            new Map<String, List<Map<String, Object>>>();

        for (WorkOrderLineItem lineItem : lineItems) {
            if (!LINE_TYPE_OBSERVATION_CODE.equalsIgnoreCase(lineItem.LineType__c)) {
                continue;
            }

            String serialNumber = nullSafeString(lineItem.SerialNumber__c);
            if (!observationsBySerial.containsKey(serialNumber)) {
                observationsBySerial.put(serialNumber, new List<Map<String, Object>>());
            }

            Map<String, Object> observationMap = new Map<String, Object>();
            observationMap.put(
                'ObservationDescription',
                nullSafeString(lineItem.ProductDescription__c)
            );
            observationMap.put(
                'Condition',
                nullSafeString(lineItem.ObservationCodeCondition__c)
            );
            observationsBySerial.get(serialNumber).add(observationMap);
        }

        List<Map<String, Object>> repairEvaluationGroups = new List<Map<String, Object>>();
        for (String serialNumber : observationsBySerial.keySet()) {
            Map<String, Object> groupMap = new Map<String, Object>();
            groupMap.put('SerialNumber', serialNumber);
            groupMap.put('Observations', observationsBySerial.get(serialNumber));
            repairEvaluationGroups.add(groupMap);
        }

        return repairEvaluationGroups;
    }

    private static List<Map<String, Object>> buildWorkOrderRepairEvaluationRows(
        List<WorkOrderLineItem> lineItems
    ) {
        List<Map<String, Object>> repairEvaluationRows = new List<Map<String, Object>>();

        for (WorkOrderLineItem lineItem : lineItems) {
            if (!LINE_TYPE_OBSERVATION_CODE.equalsIgnoreCase(lineItem.LineType__c)) {
                continue;
            }

            Map<String, Object> rowMap = new Map<String, Object>();
            rowMap.put('SerialNumber', nullSafeString(lineItem.SerialNumber__c));
            rowMap.put(
                'ObservationDescription',
                nullSafeString(lineItem.ProductDescription__c)
            );
            rowMap.put('Condition', nullSafeString(lineItem.ObservationCodeCondition__c));
            repairEvaluationRows.add(rowMap);
        }

        return repairEvaluationRows;
    }

    private static Decimal sumWorkOrderChildLineTotals(List<WorkOrderLineItem> childLines) {
        Decimal total = 0;
        for (WorkOrderLineItem childLine : childLines) {
            total += toDecimal(childLine.NetTotalPrice__c);
        }
        return total;
    }

    private static void putTwoLineAddress(
        Map<String, Object> tokenData,
        String streetToken,
        String cityLineToken,
        String combinedToken,
        String street,
        String city,
        String state,
        String postalCode
    ) {
        String streetValue = nullSafeString(street);
        String cityLine = formatAddressCityLine(city, state, postalCode);
        tokenData.put(streetToken, streetValue);
        tokenData.put(cityLineToken, cityLine);

        List<String> lines = new List<String>();
        if (String.isNotBlank(streetValue)) {
            lines.add(streetValue);
        }
        if (String.isNotBlank(cityLine)) {
            lines.add(cityLine);
        }
        tokenData.put(combinedToken, lines.isEmpty() ? '' : String.join(lines, '\n'));
    }

    private static String formatAddressCityLine(String city, String state, String postalCode) {
        String stateAndPostal = '';
        if (String.isNotBlank(state) && String.isNotBlank(postalCode)) {
            stateAndPostal = state + ' ' + postalCode;
        } else if (String.isNotBlank(state)) {
            stateAndPostal = state;
        } else if (String.isNotBlank(postalCode)) {
            stateAndPostal = postalCode;
        }

        if (String.isNotBlank(city) && String.isNotBlank(stateAndPostal)) {
            return city + ', ' + stateAndPostal;
        }
        if (String.isNotBlank(city)) {
            return city;
        }
        return stateAndPostal;
    }

    private static Decimal sumChildLineTotals(List<QuoteLineItem> childLines) {
        Decimal total = 0;
        for (QuoteLineItem childLine : childLines) {
            total += toDecimal(childLine.NetTotalPrice__c);
        }
        return total;
    }

    private static Decimal sumItemTotals(List<Map<String, Object>> productServicedItems) {
        Decimal grandTotal = 0;
        for (Map<String, Object> itemMap : productServicedItems) {
            Object itemTotalAmount = itemMap.get('ItemTotalAmount');
            if (itemTotalAmount instanceof Decimal) {
                grandTotal += (Decimal) itemTotalAmount;
            }
        }
        return grandTotal;
    }

    private static String resolveUom(String uomValue) {
        return String.isBlank(uomValue) ? 'EA' : uomValue;
    }

    private static String formatCustomerNameWithNumber(
        String accountName,
        String accountNumber
    ) {
        String safeAccountName = nullSafeString(accountName);
        if (String.isBlank(accountNumber)) {
            return safeAccountName;
        }
        return safeAccountName + ' (' + accountNumber + ')';
    }

    /**
     * @description Resolves an active document template Id by developer-facing name.
     * @param templateName Document template name configured in Document Template Designer.
     * @return Active template Id, or null when not found.
     */
    @TestVisible
    private static Id selectActiveTemplateIdByName(String templateName) {
        return DocumentTemplatesService.selectActiveIdByName(templateName);
    }

    private static String formatDate(Date value) {
        return value.format();
    }

    private static String formatCurrency(Decimal amount, String currencyIsoCode) {
        Decimal safeAmount = toDecimal(amount).setScale(2, RoundingMode.HALF_UP);
        String formattedAmount = formatTwoDecimalPlaces(safeAmount);

        if ('USD'.equalsIgnoreCase(currencyIsoCode) || String.isBlank(currencyIsoCode)) {
            return '$' + formattedAmount;
        }
        if ('GBP'.equalsIgnoreCase(currencyIsoCode)) {
            return '£' + formattedAmount;
        }

        return currencyIsoCode + ' ' + formattedAmount;
    }

    private static Decimal toDecimal(Object value) {
        if (value == null) {
            return 0;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        return Decimal.valueOf(String.valueOf(value));
    }

    private static String formatTwoDecimalPlaces(Decimal amount) {
        Decimal scaledAmount = amount.setScale(2, RoundingMode.HALF_UP);
        Boolean isNegative = scaledAmount < 0;
        scaledAmount = scaledAmount.abs();
        Long totalCents = (scaledAmount * 100).round();
        Long wholeUnits = totalCents / 100;
        Integer fractionalUnits = (Integer) Math.mod(totalCents, 100);
        String fraction = fractionalUnits < 10
            ? '0' + String.valueOf(fractionalUnits)
            : String.valueOf(fractionalUnits);
        return (isNegative ? '-' : '') + wholeUnits + '.' + fraction;
    }

    private static String nullSafeString(String value) {
        return value == null ? '' : value;
    }

    @TestVisible
    private class PreparedDocumentGeneration {
        public DocumentGenerationRequest request;
        public Id referenceObjectId;
        public Id templateId;
        public String templateName;
        public String requestText;
        public String errorMessage;
    }

    /**
     * @description Input wrapper for the invocable document generation action.
     */
    public class DocumentGenerationRequest {
        @InvocableVariable(
            label='Quote Id'
            description='Required for Quote document generation. Leave blank when Work Order Id is provided.'
        )
        public Id quoteId;

        @InvocableVariable(
            label='Work Order Id'
            description='Required for Work Order document generation. Leave blank when Quote Id is provided.'
        )
        public Id workOrderId;

        @InvocableVariable(
            label='Document Template Id'
            description='Optional active template Id. When blank, the Letter (STERIS US) or A4 (all other Operating Units) Quote or Work Order template is used.'
        )
        public Id documentTemplateId;

        @InvocableVariable(
            label='Document Template Name'
            description='Used when Document Template Id is blank. Defaults to RepairCenterQuote or RepairCenterWorkOrder for STERIS US, otherwise RepairCenterQuoteA4 or RepairCenterWorkOrderA4.'
        )
        public String documentTemplateName;

        @InvocableVariable(
            label='Request Text'
            description='Optional unique request text for the DocumentGenerationProcess record.'
        )
        public String requestText;
    }

    /**
     * @description Output wrapper for the invocable document generation action.
     */
    public class DocumentGenerationResult {
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;

        @InvocableVariable(label='Document Generation Process Id')
        public Id documentGenerationProcessId;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }
}