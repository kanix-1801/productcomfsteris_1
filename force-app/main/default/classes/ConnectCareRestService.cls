/**
 * @description GW-4726 ConnectCare REST wrapper for BOOMI inbound integration.
 *              POST /services/apexrest/connectcare/v1/return-orders
 *              GET  /services/apexrest/connectcare/v1/assets
 */
@RestResource(urlMapping='/connectcare/v1/*')
global with sharing class ConnectCareRestService {
    private static final List<String> ASSET_SEARCH_FIELDS = new List<String>{
        'Id',
        'SerialNumber',
        'ModelCalculated__c',
        'Specialty__c',
        'Department__c',
        'Department__r.Name',
        'Product2Id',
        'Product2.ProductLine__c',
        'Product2.Name',
        'Product2.ItemID__c',
        'AccountId',
        'Account.AccountNumber',
        'Account.Name'
    };

    private static final List<String> ENRICH_LINES_ASSET_FIELDS = new List<String>{
        'Id',
        'Product2Id',
        'SerialNumber',
        'ModelCalculated__c',
        'Product2.ProductLine__c'
    };

    private static final Integer MAX_ASSET_RESULTS = 200;
    private static final Integer MIN_SERIAL_SEARCH_LENGTH = 3;
    private static final String CREATION_SOURCE_CONNECT_CARE = 'ConnectCare';
    private static final String LINE_TYPE_SERIALIZED = 'serialized';
    private static final String ROLI_LINE_TYPE_SERIALIZED = 'Serialized';
    private static final String ERROR_CODE_VALIDATION = 'VALIDATION_ERROR';
    private static final String ERROR_CODE_ROUTING = 'ROUTING_ERROR';
    private static final String ERROR_CODE_NOT_FOUND = 'NOT_FOUND';

    @HttpGet
    global static void searchAssets() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            if (!isAssetsRequest()) {
                writeError(response, 404, null, ERROR_CODE_NOT_FOUND, 'Unsupported GET resource.', null);
                return;
            }

            Map<String, String> params = RestContext.request.params;
            String accountNumber = PlatformUtilities.trimToNull(params.get('accountNumber'));
            String accountIdParam = PlatformUtilities.trimToNull(params.get('accountId'));
            String serialSearchTerm = PlatformUtilities.trimToNull(params.get('serialSearchTerm'));

            if (String.isBlank(serialSearchTerm) || serialSearchTerm.length() < MIN_SERIAL_SEARCH_LENGTH) {
                writeError(
                    response,
                    400,
                    null,
                    ERROR_CODE_VALIDATION,
                    'serialSearchTerm is required and must be at least ' +
                        MIN_SERIAL_SEARCH_LENGTH +
                        ' characters.',
                    null
                );
                return;
            }

            Id accountId = resolveAccountId(accountNumber, accountIdParam);
            if (accountId == null) {
                writeError(
                    response,
                    400,
                    null,
                    ERROR_CODE_VALIDATION,
                    'accountNumber or accountId is required and must match an account.',
                    null
                );
                return;
            }

            List<Object> assets = queryAssetsForAccount(accountId, serialSearchTerm);
            PlatformUtilities.writeJson(response, 200, new Map<String, Object>{ 'assets' => assets });
        } catch (Exception e) {
            writeError(
                response,
                400,
                null,
                ERROR_CODE_VALIDATION,
                'Error searching assets: ' + e.getMessage(),
                null
            );
        }
    }

    @HttpPost
    global static void createReturnOrders() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        String connectCareRequestId = null;

        try {
            if (!isReturnOrdersRequest()) {
                writeError(
                    response,
                    404,
                    connectCareRequestId,
                    ERROR_CODE_NOT_FOUND,
                    'Unsupported POST resource.',
                    null
                );
                return;
            }

            Map<String, Object> requestBody = parseRequestBody();
            Map<String, Object> headerInput = PlatformUtilities.getMapValue(requestBody, 'header');
            List<Object> lineInputs = PlatformUtilities.getListValue(requestBody, 'lines');

            if (headerInput == null) {
                writeError(
                    response,
                    400,
                    connectCareRequestId,
                    ERROR_CODE_VALIDATION,
                    'header is required.',
                    null
                );
                return;
            }

            connectCareRequestId = PlatformUtilities.trimToNull((String) headerInput.get('connectCareRequestId'));
            List<String> validationErrors = validateConnectCareRequest(headerInput, lineInputs);
            if (!validationErrors.isEmpty()) {
                writeError(
                    response,
                    400,
                    connectCareRequestId,
                    ERROR_CODE_VALIDATION,
                    validationErrors[0],
                    validationErrors
                );
                return;
            }

            Id accountId = resolveAccountId(
                PlatformUtilities.trimToNull((String) headerInput.get('accountNumber')),
                PlatformUtilities.trimToNull((String) headerInput.get('accountId'))
            );
            if (accountId == null) {
                writeError(
                    response,
                    400,
                    connectCareRequestId,
                    ERROR_CODE_VALIDATION,
                    'Account could not be resolved from accountNumber or accountId.',
                    null
                );
                return;
            }

            Map<String, Object> header = buildHeaderPayload(headerInput, accountId);
            List<Object> lineItems = buildLineItemsPayload(lineInputs);
            enrichLinesFromAssets(lineItems);

            String headerJson = JSON.serialize(header);
            String lineItemsJson = JSON.serialize(lineItems);

            CreateReturnOrderController.LineRoutingValidation routingValidation =
                CreateReturnOrderController.validateLineRoutingMatches(headerJson, lineItemsJson);
            if (routingValidation != null && routingValidation.isValid == false) {
                writeError(
                    response,
                    422,
                    connectCareRequestId,
                    ERROR_CODE_ROUTING,
                    'No matching repair center routing rule for one or more lines.',
                    routingValidation.messages
                );
                return;
            }

            List<CreateReturnOrderController.ProposedReturnOrderGroup> proposedGroups =
                CreateReturnOrderController.buildReturnOrderPlan(headerJson, lineItemsJson);

            List<String> routingErrors = collectRoutingSelectionErrors(proposedGroups);
            if (!routingErrors.isEmpty()) {
                writeError(
                    response,
                    422,
                    connectCareRequestId,
                    ERROR_CODE_ROUTING,
                    'No matching repair center routing rule for one or more lines.',
                    routingErrors
                );
                return;
            }

            String groupsJson = buildGroupsJson(proposedGroups);
            CreateReturnOrderController.CreateOrdersResult createResult =
                CreateReturnOrderController.createReturnOrders(headerJson, groupsJson);

            PlatformUtilities.writeJson(
                response,
                200,
                buildCreateSuccessResponse(connectCareRequestId, createResult)
            );
        } catch (AuraHandledException e) {
            writeError(
                response,
                400,
                connectCareRequestId,
                ERROR_CODE_VALIDATION,
                e.getMessage(),
                null
            );
        } catch (Exception e) {
            writeError(
                response,
                400,
                connectCareRequestId,
                ERROR_CODE_VALIDATION,
                'Error creating return orders: ' + e.getMessage(),
                null
            );
        }
    }

    private static Boolean isAssetsRequest() {
        return getResourcePath().endsWith('/assets');
    }

    private static Boolean isReturnOrdersRequest() {
        return getResourcePath().endsWith('/return-orders');
    }

    private static String getResourcePath() {
        String requestUri = RestContext.request == null ? '' : RestContext.request.requestURI;
        if (String.isBlank(requestUri)) {
            return '';
        }

        Integer apexRestIndex = requestUri.indexOf('/connectcare/v1/');
        if (apexRestIndex >= 0) {
            return requestUri.substring(apexRestIndex);
        }

        return requestUri.toLowerCase();
    }

    private static Map<String, Object> parseRequestBody() {
        if (RestContext.request == null || RestContext.request.requestBody == null) {
            return new Map<String, Object>();
        }

        String rawBody = RestContext.request.requestBody.toString();
        if (String.isBlank(rawBody)) {
            return new Map<String, Object>();
        }

        Object parsed = JSON.deserializeUntyped(rawBody);
        if (!(parsed instanceof Map<String, Object>)) {
            throw new AuraHandledException('Request body must be a JSON object.');
        }

        return (Map<String, Object>) parsed;
    }

    private static List<String> validateConnectCareRequest(
        Map<String, Object> headerInput,
        List<Object> lineInputs
    ) {
        List<String> errors = new List<String>();

        String accountNumber = PlatformUtilities.trimToNull((String) headerInput.get('accountNumber'));
        String accountId = PlatformUtilities.trimToNull((String) headerInput.get('accountId'));
        if (String.isBlank(accountNumber) && String.isBlank(accountId)) {
            errors.add('header.accountNumber or header.accountId is required.');
        }

        String creationSource = PlatformUtilities.trimToNull((String) headerInput.get('creationSource'));
        if (String.isBlank(creationSource)) {
            errors.add('header.creationSource is required.');
        } else if (!CREATION_SOURCE_CONNECT_CARE.equalsIgnoreCase(creationSource)) {
            errors.add('header.creationSource must be ConnectCare.');
        }

        if (lineInputs == null || lineInputs.isEmpty()) {
            errors.add('lines must contain at least one serialized line item.');
            return errors;
        }

        for (Integer index = 0; index < lineInputs.size(); index++) {
            if (!(lineInputs[index] instanceof Map<String, Object>)) {
                errors.add('Line ' + (index + 1) + ' must be a JSON object.');
                continue;
            }

            Map<String, Object> line = (Map<String, Object>) lineInputs[index];
            String lineType = PlatformUtilities.trimToNull((String) line.get('lineType'));
            if (!LINE_TYPE_SERIALIZED.equalsIgnoreCase(lineType)) {
                errors.add('Line ' + (index + 1) + ': only serialized lines are supported in POC.');
                continue;
            }

            validateSerializedLine(errors, line, index + 1);
        }

        return errors;
    }

    private static void validateSerializedLine(
        List<String> errors,
        Map<String, Object> line,
        Integer lineNumber
    ) {
        String prefix = 'Line ' + lineNumber + ': ';

        if (PlatformUtilities.parseId(PlatformUtilities.trimToNull((String) line.get('assetId'))) == null) {
            errors.add(prefix + 'assetId is required.');
        }

        if (
            PlatformUtilities.parseId(PlatformUtilities.trimToNull((String) line.get('product2Id'))) == null &&
            PlatformUtilities.parseId(PlatformUtilities.trimToNull((String) line.get('assetId'))) == null
        ) {
            errors.add(prefix + 'product2Id is required when assetId is not resolvable.');
        }

        if (String.isBlank(PlatformUtilities.trimToNull((String) line.get('serialNumber')))) {
            errors.add(prefix + 'serialNumber is required.');
        }
        if (String.isBlank(PlatformUtilities.trimToNull((String) line.get('model')))) {
            errors.add(prefix + 'model is required.');
        }
        if (String.isBlank(PlatformUtilities.trimToNull((String) line.get('productLine')))) {
            errors.add(prefix + 'productLine is required.');
        }
        if (PlatformUtilities.parseId(PlatformUtilities.trimToNull((String) line.get('departmentId'))) == null) {
            errors.add(prefix + 'departmentId is required.');
        }
        if (PlatformUtilities.parseId(PlatformUtilities.trimToNull((String) line.get('contactId'))) == null) {
            errors.add(prefix + 'contactId is required.');
        }
        if (String.isBlank(PlatformUtilities.trimToNull((String) line.get('disinfected')))) {
            errors.add(prefix + 'disinfected is required.');
        }
        if (String.isBlank(PlatformUtilities.trimToNull((String) line.get('reportedProblem')))) {
            errors.add(prefix + 'reportedProblem is required.');
        }
        if (String.isBlank(PlatformUtilities.trimToNull((String) line.get('estimateRequired')))) {
            errors.add(prefix + 'estimateRequired is required.');
        }
        if (String.isBlank(PlatformUtilities.trimToNull((String) line.get('repairWarranty')))) {
            errors.add(prefix + 'repairWarranty is required.');
        }

        String estimateRequired = PlatformUtilities.trimToNull((String) line.get('estimateRequired'));
        if (
            estimateRequired != null &&
            estimateRequired.equalsIgnoreCase('Estimate Required') &&
            PlatformUtilities.parseId(PlatformUtilities.trimToNull((String) line.get('estimateContactId'))) == null
        ) {
            errors.add(prefix + 'estimateContactId is required when estimateRequired is Estimate Required.');
        }

        String repairWarranty = PlatformUtilities.trimToNull((String) line.get('repairWarranty'));
        if (repairWarranty != null && repairWarranty.equalsIgnoreCase('Yes')) {
            Boolean hasWarrantyNotes = String.isNotBlank(PlatformUtilities.trimToNull((String) line.get('warrantyNotes')));
            Boolean hasPreviousReturnOrder = String.isNotBlank(
                PlatformUtilities.trimToNull((String) line.get('previousReturnOrder'))
            );
            if (!hasWarrantyNotes && !hasPreviousReturnOrder) {
                errors.add(
                    prefix +
                        'warrantyNotes or previousReturnOrder is required when repairWarranty is Yes.'
                );
            }
        }
    }

    private static Map<String, Object> buildHeaderPayload(
        Map<String, Object> headerInput,
        Id accountId
    ) {
        Map<String, Object> header = new Map<String, Object>{
            'accountId' => String.valueOf(accountId),
            'operatingUnit' => PlatformUtilities.trimToNull((String) headerInput.get('operatingUnit')),
            'creationSource' => CREATION_SOURCE_CONNECT_CARE,
            'salesRepId' => PlatformUtilities.trimToNull((String) headerInput.get('salesRepId')),
            'caseId' => PlatformUtilities.trimToNull((String) headerInput.get('caseId')),
            'workOrderId' => PlatformUtilities.trimToNull((String) headerInput.get('workOrderId'))
        };
        return header;
    }

    private static List<Object> buildLineItemsPayload(List<Object> lineInputs) {
        List<Object> lineItems = new List<Object>();

        for (Integer index = 0; index < lineInputs.size(); index++) {
            Map<String, Object> line = (Map<String, Object>) lineInputs[index];
            String lineKey = 'cc-line-' + String.valueOf(index + 1);

            lineItems.add(
                new Map<String, Object>{
                    'lineKey' => lineKey,
                    'lineNumber' => index + 1,
                    'lineType' => LINE_TYPE_SERIALIZED,
                    'roliLineType' => ROLI_LINE_TYPE_SERIALIZED,
                    'serialized' => true,
                    'serialNumber' => PlatformUtilities.trimToNull((String) line.get('serialNumber')),
                    'assetId' => PlatformUtilities.trimToNull((String) line.get('assetId')),
                    'product2Id' => PlatformUtilities.trimToNull((String) line.get('product2Id')),
                    'model' => PlatformUtilities.trimToNull((String) line.get('model')),
                    'productLine' => PlatformUtilities.trimToNull((String) line.get('productLine')),
                    'departmentId' => PlatformUtilities.trimToNull((String) line.get('departmentId')),
                    'disinfected' => PlatformUtilities.trimToNull((String) line.get('disinfected')),
                    'contactId' => PlatformUtilities.trimToNull((String) line.get('contactId')),
                    'estimateContactId' => PlatformUtilities.trimToNull((String) line.get('estimateContactId')),
                    'estimateRequired' => PlatformUtilities.trimToNull((String) line.get('estimateRequired')),
                    'customerPo' => PlatformUtilities.trimToNull((String) line.get('customerPo')),
                    'isLoanerAsset' => line.get('isLoanerAsset'),
                    'loanerRequested' => line.get('loanerRequested'),
                    'reportedProblem' => PlatformUtilities.trimToNull((String) line.get('reportedProblem')),
                    'customerReference' => PlatformUtilities.trimToNull((String) line.get('customerReference')),
                    'repairWarranty' => PlatformUtilities.trimToNull((String) line.get('repairWarranty')),
                    'previousReturnOrder' => PlatformUtilities.trimToNull((String) line.get('previousReturnOrder')),
                    'warrantyNotes' => PlatformUtilities.trimToNull((String) line.get('warrantyNotes')),
                    'quantityReturned' => 1
                }
            );
        }

        return lineItems;
    }

    private static void enrichLinesFromAssets(List<Object> lineItems) {
        Set<Id> assetIds = new Set<Id>();
        for (Object lineObj : lineItems) {
            Map<String, Object> line = (Map<String, Object>) lineObj;
            Id assetId = PlatformUtilities.parseId(PlatformUtilities.trimToNull((String) line.get('assetId')));
            if (assetId != null) {
                assetIds.add(assetId);
            }
        }

        if (assetIds.isEmpty()) {
            return;
        }

        List<Asset> assets = (List<Asset>) new AssetsSelector().selectFields(ENRICH_LINES_ASSET_FIELDS)
            .whereIn('Id', new List<Id>(assetIds))
            .execute();

        Map<Id, Asset> assetsById = new Map<Id, Asset>(assets);

        for (Object lineObj : lineItems) {
            Map<String, Object> line = (Map<String, Object>) lineObj;
            Id assetId = PlatformUtilities.parseId(PlatformUtilities.trimToNull((String) line.get('assetId')));
            if (assetId == null || !assetsById.containsKey(assetId)) {
                continue;
            }

            Asset asset = assetsById.get(assetId);
            if (PlatformUtilities.parseId(PlatformUtilities.trimToNull((String) line.get('product2Id'))) == null && asset.Product2Id != null) {
                line.put('product2Id', String.valueOf(asset.Product2Id));
            }
            if (String.isBlank(PlatformUtilities.trimToNull((String) line.get('serialNumber')))) {
                line.put('serialNumber', asset.SerialNumber);
            }
            if (String.isBlank(PlatformUtilities.trimToNull((String) line.get('model')))) {
                line.put('model', asset.ModelCalculated__c);
            }
            if (
                String.isBlank(PlatformUtilities.trimToNull((String) line.get('productLine'))) &&
                asset.Product2 != null
            ) {
                line.put('productLine', asset.Product2.ProductLine__c);
            }
        }
    }

    private static String buildGroupsJson(
        List<CreateReturnOrderController.ProposedReturnOrderGroup> proposedGroups
    ) {
        List<Object> groupsPayload = new List<Object>();
        for (CreateReturnOrderController.ProposedReturnOrderGroup proposedGroup : proposedGroups) {
            groupsPayload.add(
                new Map<String, Object>{
                    'groupKey' => proposedGroup.groupKey,
                    'repairCenterId' => proposedGroup.repairCenterId,
                    'requiresRepairCenterSelection' => proposedGroup.requiresRepairCenterSelection,
                    'lineItemsJson' => proposedGroup.lineItemsJson,
                    'orderHeader' => null
                }
            );
        }
        return JSON.serialize(groupsPayload);
    }

    private static List<String> collectRoutingSelectionErrors(
        List<CreateReturnOrderController.ProposedReturnOrderGroup> proposedGroups
    ) {
        List<String> errors = new List<String>();
        for (CreateReturnOrderController.ProposedReturnOrderGroup proposedGroup : proposedGroups) {
            if (proposedGroup.requiresRepairCenterSelection == true) {
                errors.add(
                    'Group ' +
                        proposedGroup.groupKey +
                        ' requires repair center selection. ConnectCare POC does not support manual repair center selection.'
                );
            }
        }
        return errors;
    }

    private static Map<String, Object> buildCreateSuccessResponse(
        String connectCareRequestId,
        CreateReturnOrderController.CreateOrdersResult createResult
    ) {
        List<Object> returnOrders = new List<Object>();
        if (createResult != null && createResult.returnOrders != null) {
            for (CreateReturnOrderController.CreateResult createdOrder : createResult.returnOrders) {
                returnOrders.add(
                    new Map<String, Object>{
                        'returnOrderId' => createdOrder.returnOrderId,
                        'returnOrderNumber' => createdOrder.returnOrderNumber,
                        'returnOrderType' => createdOrder.returnOrderType,
                        'repairCenterName' => createdOrder.repairCenterName,
                        'lineCount' => createdOrder.lineCount
                    }
                );
            }
        }

        return new Map<String, Object>{
            'success' => true,
            'connectCareRequestId' => connectCareRequestId,
            'returnOrders' => returnOrders
        };
    }

    private static Id resolveAccountId(String accountNumber, String accountIdParam) {
        Id accountId = PlatformUtilities.parseId(accountIdParam);
        if (accountId != null) {
            return accountId;
        }

        if (String.isBlank(accountNumber)) {
            return null;
        }

        List<Account> accounts = (List<Account>) new AccountSelector().selectField('Id')
            .whereEquals('AccountNumber', accountNumber)
            .limitTo(2)
            .execute();

        if (accounts.isEmpty()) {
            return null;
        }
        if (accounts.size() > 1) {
            throw new AuraHandledException(
                'Multiple accounts found for accountNumber ' + accountNumber + '.'
            );
        }

        return accounts[0].Id;
    }

    private static List<Object> queryAssetsForAccount(Id accountId, String serialSearchTerm) {
        String likePattern = '%' + serialSearchTerm + '%';

        List<Asset> assets = (List<Asset>) new AssetsSelector().selectFields(ASSET_SEARCH_FIELDS)
            .whereEquals('AccountId', accountId)
            .whereField('SerialNumber', 'LIKE', likePattern)
            .orderBy('SerialNumber')
            .limitTo(MAX_ASSET_RESULTS)
            .execute();

        List<Object> rows = new List<Object>();
        for (Asset asset : assets) {
            rows.add(mapAssetSearchResult(asset));
        }
        return rows;
    }

    private static Map<String, Object> mapAssetSearchResult(Asset asset) {
        Map<String, Object> row = new Map<String, Object>{
            'assetId' => asset.Id,
            'serialNumber' => asset.SerialNumber,
            'model' => asset.ModelCalculated__c,
            'departmentId' => asset.Department__c,
            'departmentName' => asset.Department__r == null ? null : asset.Department__r.Name,
            'product2Id' => asset.Product2Id,
            'productLine' => asset.Product2 == null ? null : asset.Product2.ProductLine__c,
            'productName' => asset.Product2 == null ? null : asset.Product2.Name,
            'accountId' => asset.AccountId,
            'accountNumber' => asset.Account == null ? null : asset.Account.AccountNumber,
            'accountName' => asset.Account == null ? null : asset.Account.Name
        };

        row.put('specialty', asset.Specialty__c);
        row.put(
            'productExternalId',
            asset.Product2 == null ? null : asset.Product2.ItemID__c
        );

        return row;
    }

    private static void writeError(
        RestResponse response,
        Integer statusCode,
        String connectCareRequestId,
        String errorCode,
        String message,
        List<String> details
    ) {
        Map<String, Object> body = new Map<String, Object>{
            'success' => false,
            'connectCareRequestId' => connectCareRequestId,
            'errorCode' => errorCode,
            'message' => message,
            'details' => details == null ? new List<String>() : details
        };
        PlatformUtilities.writeJson(response, statusCode, body);
    }
}