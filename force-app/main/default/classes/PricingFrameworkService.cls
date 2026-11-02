/**
 * @description GW-4585 common Oracle pricing API for Repair Center, Field Service, and Service Sales.
 *              Uses the generic Oracle pricing call (operating unit name, ship-to, bill-to,
 *              ST_ACCOUNT / BT_ACCOUNT) through the existing ShoutOut unit-price gateway.
 *              Workstream callers keep post-Oracle Salesforce Pricing logic in their own flows.
 *              Salesforce Pricing (RCA) Headless Pricing licenses are required for the subflow step.
 * @group Pricing Framework
 */
public with sharing class PricingFrameworkService {
    private static final String CLASS_NAME = 'PricingFrameworkService';
    private static Schema.DescribeFieldResult cachedOrgIdFieldDescribe;
    private static final String SOURCE_ORACLE = 'Oracle';
    private static final String SOURCE_SALESFORCE = 'Salesforce';
    private static final String SOURCE_SYSTEM = System.Label.Source_System;
    private static final String RECORD_TYPE_PROSPECT = 'Prospect';
    private static final String PRICE_LIST_LEVEL_ACCOUNT = 'ST_ACCOUNT';
    private static final String DISCOUNT_ACCOUNT_BILL_TO = 'BT_ACCOUNT';
    private static final String ACCOUNT_TYPE_ADDRESS = 'Address';
    private static final Integer FLOW_ERROR_MESSAGE_MAX_LENGTH = 1000;

    @TestVisible
    private static OraclePricingResponse testOracleResponse;

    /**
     * @description GW-4585 - Executes Oracle and Salesforce Headless Pricing for a single request.
     * @param request Pricing request from Flow or other callers
     * @return Pricing result with merged JSON
     */
    public static PricingFrameworkOracleInvocable.Result executePricing(
        PricingFrameworkOracleInvocable.Request request
    ) {
        PricingFrameworkOracleInvocable.Result result =
            new PricingFrameworkOracleInvocable.Result();
        result.isSuccess = false;
        result.workstream = request == null ? null : request.workstream;

        try {
            if (request == null || request.accountId == null) {
                result.errorMessage = 'Account Id is required.';
                return result;
            }

            Boolean isQuote = businessObjectType(request.workstream) == 'Quote';
            Set<Id> headerIds = new Set<Id>();
            List<PricingFrameworkOracleInvocable.PricingLine> lines = parseLines(request.pricingLineJson, headerIds);
            hydrateLineAttributes(lines, isQuote);
            lines = linesWithProductCode(lines);
            if (isHeaderRecordId(request.recordId)) {
                headerIds.add(request.recordId);
            }
            if (lines.isEmpty()) {
                lines = linesFromHeaderIds(headerIds, isQuote);
            }
            if (lines.isEmpty()) {
                result.errorMessage = 'Pricing lines are required.';
                return result;
            }
            populatePricingSource(lines, isQuote);

            List<PricingFrameworkOracleInvocable.PricingLine> oracleLines = new List<PricingFrameworkOracleInvocable.PricingLine>();
            for (PricingFrameworkOracleInvocable.PricingLine line : lines) {
                if (SOURCE_ORACLE.equalsIgnoreCase(line.pricingSource)) {
                    oracleLines.add(line);
                }
            }

            if (!oracleLines.isEmpty()) {
                applyWorkOrderAccountOverrides(request);
                Set<Id> accountIds = new Set<Id>{ request.accountId };
                if (request.billToAccountId != null) {
                    accountIds.add(request.billToAccountId);
                }
                Map<Id, Account> accountsById = selectAccounts(accountIds);
                Account shipToAccount = preferOracleAddressAccount(
                    accountsById.get(request.accountId)
                );
                if (shipToAccount == null) {
                    result.errorMessage = 'Account was not found.';
                    return result;
                }

                Account billToAccount = request.billToAccountId == null
                    ? shipToAccount
                    : preferOracleAddressAccount(accountsById.get(request.billToAccountId));
                if (request.billToAccountId != null && billToAccount == null) {
                    result.errorMessage = 'Bill To Account was not found.';
                    return result;
                }

                OraclePricingRequest oracleRequest = buildOracleRequest(
                    shipToAccount,
                    billToAccount,
                    oracleLines
                );
                if (!isProspect(shipToAccount)) {
                    if (String.isBlank(oracleRequest.operatingUnitName)) {
                        result.errorMessage =
                            'Account Org ID is required for Oracle pricing.';
                        return result;
                    }
                    if (String.isBlank(oracleRequest.shipToCustomerNumber)) {
                        result.errorMessage = 'Ship To Account Number is required.';
                        return result;
                    }
                    if (String.isBlank(oracleRequest.billToCustomerNumber)) {
                        result.errorMessage = 'Bill To Account Number is required.';
                        return result;
                    }
                }

                OracleUnitPricingGateway.CalloutResult calloutResult = invokeOraclePricing(
                    shipToAccount,
                    oracleRequest
                );

                if (calloutResult == null || !calloutResult.calloutSuccess) {
                    result.errorMessage = calloutResult == null
                        ? 'Oracle pricing callout failed.'
                        : calloutResult.errorDetail;
                } else if (!isOracleHeaderSuccess(calloutResult.parsedResponse)) {
                    result.errorMessage = oracleHeaderError(
                        calloutResult.parsedResponse,
                        oracleRequest
                    );
                } else {
                    applyOraclePrices(oracleLines, calloutResult.parsedResponse);
                    persistOraclePrices(oracleLines, isQuote);
                }
            }

            result.pricingDataJson = toPricingDataJson(
                request.workstream,
                request.accountId,
                firstHeaderId(headerIds, request.recordId),
                lines
            );
            result.isSuccess = String.isBlank(result.errorMessage);
            return result;
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.executePricing', e);
            result.errorMessage = e.getMessage();
            return result;
        } finally {
            result.errorMessage = toFlowErrorMessage(result.errorMessage);
            try {
                Logger.saveLog();
            } catch (Exception saveException) {
                // Do not let log persistence turn a handled Oracle error into a Flow fault.
            }
        }
    }

    @TestVisible
    private static List<PricingFrameworkOracleInvocable.PricingLine> parseLines(String pricingLineJson) {
        return parseLines(pricingLineJson, new Set<Id>());
    }

    @TestVisible
    private static List<PricingFrameworkOracleInvocable.PricingLine> parseLines(String pricingLineJson, Set<Id> headerIds) {
        List<PricingFrameworkOracleInvocable.PricingLine> lines = new List<PricingFrameworkOracleInvocable.PricingLine>();
        if (headerIds == null) {
            headerIds = new Set<Id>();
        }
        if (String.isBlank(pricingLineJson)) {
            return lines;
        }

        Object parsed = JSON.deserializeUntyped(pricingLineJson);
        for (Object row : extractLineRows(parsed, headerIds)) {
            if (!(row instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> values = (Map<String, Object>) row;
            PricingFrameworkOracleInvocable.PricingLine line = new PricingFrameworkOracleInvocable.PricingLine();
            line.lineId = PlatformUtilities.firstNonBlank(
                toStringValue(values.get('lineId')),
                toStringValue(values.get('id'))
            );
            line.productCode = toStringValue(values.get('productCode'));
            line.quantity = toDecimalValue(values.get('quantity'));
            line.pricingSource = toStringValue(values.get('pricingSource'));
            line.listPrice = toDecimalValue(values.get('listPrice'));
            line.oracleDiscountedPrice = toDecimalValue(values.get('oracleDiscountedPrice'));
            if (String.isBlank(line.productCode) && String.isBlank(line.lineId)) {
                continue;
            }
            if (line.quantity == null && String.isNotBlank(line.productCode)) {
                line.quantity = 1;
            }
            lines.add(line);
        }
        return lines;
    }

    private static List<Object> extractLineRows(Object parsed, Set<Id> headerIds) {
        List<Object> rows = new List<Object>();
        if (parsed instanceof List<Object>) {
            List<Object> parsedList = (List<Object>) parsed;
            if (parsedList.isEmpty()) {
                return rows;
            }
            Object first = parsedList[0];
            if (first instanceof Map<String, Object> && isLeafPricingLineMap((Map<String, Object>) first)) {
                return parsedList;
            }
            for (Object node : parsedList) {
                rows.addAll(extractLineRows(node, headerIds));
            }
            return rows;
        }
        if (!(parsed instanceof Map<String, Object>)) {
            return rows;
        }

        Map<String, Object> root = (Map<String, Object>) parsed;
        Object nestedLines = root.get('lines');
        if (nestedLines instanceof List<Object>) {
            return (List<Object>) nestedLines;
        }

        addHeaderId(headerIds, root);
        rows.addAll(asObjectList(root.get('WorkOrderLineItem')));
        rows.addAll(asObjectList(root.get('QuoteLineItem')));
        if (!rows.isEmpty()) {
            return rows;
        }

        Object workOrderNode = root.get('WorkOrder');
        Object quoteNode = root.get('Quote');
        if (workOrderNode != null) {
            return extractLineRows(workOrderNode, headerIds);
        }
        if (quoteNode != null) {
            return extractLineRows(quoteNode, headerIds);
        }
        return rows;
    }

    private static Boolean isLeafPricingLineMap(Map<String, Object> values) {
        if (values.containsKey('WorkOrder')
            || values.containsKey('Quote')
            || values.containsKey('WorkOrderLineItem')
            || values.containsKey('QuoteLineItem')
            || values.containsKey('lines')
        ) {
            return false;
        }
        String objectType = toStringValue(values.get('businessObjectType'));
        return values.containsKey('productCode')
            || values.containsKey('lineId')
            || objectType == 'WorkOrderLineItem'
            || objectType == 'QuoteLineItem';
    }

    private static List<Object> asObjectList(Object value) {
        List<Object> rows = new List<Object>();
        if (value instanceof List<Object>) {
            return (List<Object>) value;
        }
        if (value instanceof Map<String, Object>) {
            rows.add(value);
        }
        return rows;
    }

    private static void addHeaderId(Set<Id> headerIds, Map<String, Object> root) {
        if (headerIds == null || root == null) {
            return;
        }
        String objectType = toStringValue(root.get('businessObjectType'));
        if (objectType != 'WorkOrder'
            && objectType != 'Quote'
            && !root.containsKey('WorkOrderLineItem')
            && !root.containsKey('QuoteLineItem')
        ) {
            return;
        }
        Id headerId = asId(toStringValue(root.get('id')));
        if (isHeaderRecordId(headerId)) {
            headerIds.add(headerId);
        }
    }

    private static Boolean isHeaderRecordId(Id recordId) {
        if (recordId == null) {
            return false;
        }
        String objectName = recordId.getSObjectType().getDescribe().getName();
        return objectName == 'WorkOrder' || objectName == 'Quote';
    }

    private static List<PricingFrameworkOracleInvocable.PricingLine> linesWithProductCode(List<PricingFrameworkOracleInvocable.PricingLine> lines) {
        List<PricingFrameworkOracleInvocable.PricingLine> resolved = new List<PricingFrameworkOracleInvocable.PricingLine>();
        if (lines == null) {
            return resolved;
        }
        for (PricingFrameworkOracleInvocable.PricingLine line : lines) {
            if (line != null && String.isNotBlank(line.productCode)) {
                resolved.add(line);
            }
        }
        return resolved;
    }

    private static void hydrateLineAttributes(List<PricingFrameworkOracleInvocable.PricingLine> lines, Boolean isQuote) {
        Map<Id, SObject> recordsByLineId = selectLineRecords(isQuote, lines);
        for (PricingFrameworkOracleInvocable.PricingLine line : lines) {
            Id lineId = asId(line.lineId);
            SObject record = lineId == null ? null : recordsByLineId.get(lineId);
            if (record == null) {
                continue;
            }
            if (String.isBlank(line.productCode)) {
                line.productCode = productCodeFrom(record);
            }
            if (String.isBlank(line.pricingSource)) {
                line.pricingSource = pricingSourceFrom(record);
            }
            if (line.quantity == null) {
                line.quantity = (Decimal) record.get('Quantity');
            }
        }
    }

    private static List<PricingFrameworkOracleInvocable.PricingLine> linesFromHeaderIds(Set<Id> headerIds, Boolean isQuote) {
        List<PricingFrameworkOracleInvocable.PricingLine> lines = new List<PricingFrameworkOracleInvocable.PricingLine>();
        if (headerIds == null || headerIds.isEmpty()) {
            return lines;
        }
        if (isQuote) {
            for (QuoteLineItem lineItem : QuoteLineItemSelector.selectForPricingFrameworkByQuoteIds(
                headerIds
            )) {
                String productCode = productCodeFrom(lineItem);
                if (String.isBlank(productCode)) {
                    continue;
                }
                lines.add(
                    pricingLineFrom(
                        lineItem.Id,
                        productCode,
                        lineItem.Quantity,
                        pricingSourceFrom(lineItem)
                    )
                );
            }
            return lines;
        }
        for (WorkOrderLineItem lineItem :
            WorkOrderLineItemsSelector.selectForPricingFrameworkByWorkOrderIds(headerIds)
        ) {
            String productCode = productCodeFrom(lineItem);
            if (String.isBlank(productCode)) {
                continue;
            }
            lines.add(
                pricingLineFrom(
                    lineItem.Id,
                    productCode,
                    lineItem.Quantity,
                    pricingSourceFrom(lineItem)
                )
            );
        }
        return lines;
    }

    private static PricingFrameworkOracleInvocable.PricingLine pricingLineFrom(Id lineId, String productCode, Decimal quantity) {
        return pricingLineFrom(lineId, productCode, quantity, null);
    }

    private static PricingFrameworkOracleInvocable.PricingLine pricingLineFrom(
        Id lineId,
        String productCode,
        Decimal quantity,
        String pricingSource
    ) {
        PricingFrameworkOracleInvocable.PricingLine line = new PricingFrameworkOracleInvocable.PricingLine();
        line.lineId = String.valueOf(lineId);
        line.productCode = productCode;
        line.quantity = quantity == null ? 1 : quantity;
        line.pricingSource = pricingSource;
        return line;
    }

    private static String productCodeFrom(SObject record) {
        if (record == null) {
            return null;
        }
        String productCode = productCodeFromRelated(record.getSObject('Product2'));
        if (String.isNotBlank(productCode)) {
            return productCode;
        }
        SObject pricebookEntry = record.getSObject('PricebookEntry');
        return pricebookEntry == null
            ? null
            : productCodeFromRelated(pricebookEntry.getSObject('Product2'));
    }

    private static String productCodeFromRelated(SObject product) {
        return product == null ? null : (String) product.get('ProductCode');
    }

    private static String pricingSourceFrom(SObject record) {
        if (record == null) {
            return null;
        }
        String pricingSource = pricingSourceFromRelated(record.getSObject('Product2'));
        if (String.isNotBlank(pricingSource)) {
            return pricingSource;
        }
        SObject pricebookEntry = record.getSObject('PricebookEntry');
        return pricebookEntry == null
            ? null
            : pricingSourceFromRelated(pricebookEntry.getSObject('Product2'));
    }

    private static String pricingSourceFromRelated(SObject product) {
        return product == null ? null : (String) product.get('PricingSource__c');
    }

    private static Id firstHeaderId(Set<Id> headerIds, Id recordId) {
        if (headerIds != null) {
            for (Id headerId : headerIds) {
                if (isHeaderRecordId(headerId)) {
                    return headerId;
                }
            }
        }
        return isHeaderRecordId(recordId) ? recordId : null;
    }

    private static void populatePricingSource(List<PricingFrameworkOracleInvocable.PricingLine> lines, Boolean isQuote) {
        Map<Id, SObject> recordsByLineId = selectLineRecords(isQuote, lines);
        for (PricingFrameworkOracleInvocable.PricingLine line : lines) {
            if (String.isNotBlank(line.pricingSource)) {
                continue;
            }
            Id lineId = asId(line.lineId);
            SObject record = lineId == null ? null : recordsByLineId.get(lineId);
            line.pricingSource = pricingSourceFrom(record);
        }

        Set<String> productCodes = new Set<String>();
        for (PricingFrameworkOracleInvocable.PricingLine line : lines) {
            if (String.isBlank(line.pricingSource) && String.isNotBlank(line.productCode)) {
                productCodes.add(line.productCode);
            }
        }
        Map<String, String> sourceByCode = new Map<String, String>();
        if (!productCodes.isEmpty()) {
            for (Product2 product :
                Product2Selector.selectPricingSourceByProductCodes(productCodes)
            ) {
                if (String.isNotBlank(product.ProductCode)
                    && !sourceByCode.containsKey(product.ProductCode)
                ) {
                    sourceByCode.put(product.ProductCode, product.PricingSource__c);
                }
            }
        }

        for (PricingFrameworkOracleInvocable.PricingLine line : lines) {
            if (String.isBlank(line.pricingSource) && sourceByCode.containsKey(line.productCode)) {
                line.pricingSource = sourceByCode.get(line.productCode);
            }
            if (String.isBlank(line.pricingSource)) {
                line.pricingSource = SOURCE_ORACLE;
            }
        }
    }

    private static Map<Id, Account> selectAccounts(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new Map<Id, Account>();
        }

        return AccountSelector.selectForOraclePricingByIds(accountIds);
    }

    @TestVisible
    private static void applyWorkOrderAccountOverrides(
        PricingFrameworkOracleInvocable.Request request
    ) {
        if (request == null || !isWorkOrderRecordId(request.recordId)) {
            return;
        }

        WorkOrder workOrder = WorkOrdersSelector.selectPricingFrameworkAccountOverrides(
            request.recordId
        );
        if (workOrder == null) {
            return;
        }
        if (workOrder.ShipToAddressAccount__c != null) {
            request.accountId = workOrder.ShipToAddressAccount__c;
        } else if (request.accountId == null) {
            request.accountId = workOrder.AccountId;
        }
        if (workOrder.BillToAddressAccount__c != null) {
            request.billToAccountId = workOrder.BillToAddressAccount__c;
        }
    }

    @TestVisible
    private static Account preferOracleAddressAccount(Account account) {
        if (account == null || isAddressAccount(account) || String.isNotBlank(account.OracleAddressId__c)) {
            return account;
        }

        List<Account> addresses = AccountSelector.selectOracleAddressAccountsForPricing(
            account.Id
        );
        return addresses.isEmpty() ? account : addresses[0];
    }

    private static Boolean isWorkOrderRecordId(Id recordId) {
        return recordId != null
            && recordId.getSObjectType() == WorkOrder.SObjectType;
    }

    private static Boolean isAddressAccount(Account account) {
        return account != null && ACCOUNT_TYPE_ADDRESS.equalsIgnoreCase(account.Type);
    }

    @TestVisible
    private static OracleUnitPricingGateway.CalloutResult invokeOraclePricing(
        Account shipToAccount,
        OraclePricingRequest oracleRequest
    ) {
        if (testOracleResponse != null) {
            return buildTestCalloutResult(testOracleResponse);
        }

        return isProspect(shipToAccount)
            ? OracleUnitPricingGateway.sendProspectPriceRequest(oracleRequest)
            : OracleUnitPricingGateway.sendUnitPriceRequest(oracleRequest);
    }

    @TestVisible
    private static OracleUnitPricingGateway.CalloutResult buildTestCalloutResult(
        OraclePricingResponse parsedResponse
    ) {
        OracleUnitPricingGateway.CalloutResult injected = new OracleUnitPricingGateway.CalloutResult();
        injected.calloutSuccess = true;
        injected.parsedResponse = parsedResponse;
        return injected;
    }

    private static Boolean isProspect(Account account) {
        return account != null
            && account.RecordType != null
            && account.RecordType.DeveloperName == RECORD_TYPE_PROSPECT;
    }

    @TestVisible
    private static OraclePricingRequest buildOracleRequest(
        Account shipToAccount,
        Account billToAccount,
        List<PricingFrameworkOracleInvocable.PricingLine> lines
    ) {
        OraclePricingRequest request = new OraclePricingRequest();
        request.sourceSystem = SOURCE_SYSTEM;
        request.productPartNumbers = new List<OraclePricingRequest.ProductPartNumber>();
        for (PricingFrameworkOracleInvocable.PricingLine line : lines) {
            request.productPartNumbers.add(
                new OraclePricingRequest.ProductPartNumber(line.productCode, line.quantity)
            );
        }

        if (isProspect(shipToAccount)) {
            request.prospectId = shipToAccount.Id;
            request.accountType = RECORD_TYPE_PROSPECT;
            request.priceList = shipToAccount.Price_List__r != null
                ? String.valueOf(shipToAccount.Price_List__r.Price_List_ID__c)
                : null;
            request.priceListName = request.priceList;
            return request;
        }

        Account operatingUnitAccount = billToAccount != null ? billToAccount : shipToAccount;
        request.accountType = 'Account';
        request.operatingUnit = PlatformUtilities.firstNonBlank(
            orgIdValue(operatingUnitAccount),
            orgIdValue(shipToAccount)
        );
        request.operatingUnitName = operatingUnitName(request.operatingUnit);
        request.shipToCustomerNumber = shipToAccount.AccountNumber;
        request.shipToAddressSiteId = shipToAccount.OracleAddressId__c;
        request.billToCustomerNumber = billToAccount != null
            ? billToAccount.AccountNumber
            : shipToAccount.AccountNumber;
        request.genericPriceListLevel = PRICE_LIST_LEVEL_ACCOUNT;
        request.genericDiscountAccount = DISCOUNT_ACCOUNT_BILL_TO;
        return request;
    }

    private static String orgIdValue(Account pricingAccount) {
        if (pricingAccount == null) {
            return null;
        }
        if (String.isNotBlank(pricingAccount.OrgIDs__c)) {
            return pricingAccount.OrgIDs__c;
        }
        return pricingAccount.Parent == null ? null : pricingAccount.Parent.OrgIDs__c;
    }

    private static String operatingUnitName(String orgId) {
        if (String.isBlank(orgId)) {
            return null;
        }

        Schema.DescribeFieldResult orgIdDescribe = orgIdFieldDescribe();
        if (orgIdDescribe == null) {
            return orgId;
        }

        for (Schema.PicklistEntry entry : orgIdDescribe.getPicklistValues()) {
            if (entry.getValue() == orgId) {
                return entry.getLabel();
            }
        }
        return orgId;
    }

    private static Schema.DescribeFieldResult orgIdFieldDescribe() {
        if (cachedOrgIdFieldDescribe != null) {
            return cachedOrgIdFieldDescribe;
        }
        Schema.DescribeSObjectResult accountDescribe =
            Schema.describeSObjects(new List<String>{ 'Account' })[0];
        Map<String, Schema.SObjectField> fieldMap = accountDescribe.fields.getMap();
        Schema.SObjectField orgIdField = fieldMap.get('OrgIDs__c');
        cachedOrgIdFieldDescribe = orgIdField == null ? null : orgIdField.getDescribe();
        return cachedOrgIdFieldDescribe;
    }

    private static Boolean isOracleHeaderSuccess(OraclePricingResponse response) {
        if (response == null) {
            return false;
        }
        if (String.isBlank(response.messageKey) && String.isBlank(response.errorCode)) {
            return true;
        }
        return OraclePricingResponse.isPricingSuccess(response.messageKey, response.errorCode);
    }

    private static String oracleHeaderError(OraclePricingResponse response) {
        return oracleHeaderError(response, null);
    }

    private static String oracleHeaderError(
        OraclePricingResponse response,
        OraclePricingRequest request
    ) {
        if (response == null) {
            return 'Oracle pricing callout failed.';
        }
        List<String> parts = new List<String>();
        if (String.isNotBlank(response.errorCode)) {
            parts.add(response.errorCode);
        }
        if (String.isNotBlank(response.messageKey)) {
            parts.add(response.messageKey);
        }
        String headerError = parts.isEmpty()
            ? 'Oracle pricing callout failed.'
            : String.join(parts, ' ');
        if (request == null || String.isBlank(request.shipToCustomerNumber)) {
            return headerError;
        }
        if (headerError.contains('SHIPTO_ACCT_NUM_INVALID')) {
            return 'Oracle rejected ship-to account number '
                + request.shipToCustomerNumber
                + ' ('
                + headerError
                + '). Set the Work Order Ship-to Address Account to an Oracle customer.';
        }
        return headerError + ' (ship-to ' + request.shipToCustomerNumber + ')';
    }

    private static void applyOraclePrices(List<PricingFrameworkOracleInvocable.PricingLine> lines, OraclePricingResponse response) {
        if (response == null || response.priceInfo == null) {
            return;
        }

        Map<String, OraclePricingResponse.PriceInfo> priceByCode =
            new Map<String, OraclePricingResponse.PriceInfo>();
        for (OraclePricingResponse.PriceInfo info : response.priceInfo) {
            if (info != null && String.isNotBlank(info.productPartNumber)) {
                priceByCode.put(info.productPartNumber, info);
            }
        }

        for (PricingFrameworkOracleInvocable.PricingLine line : lines) {
            OraclePricingResponse.PriceInfo info = priceByCode.get(line.productCode);
            if (info == null) {
                continue;
            }
            if (!OraclePricingResponse.isPricingSuccess(info.messageKey, info.errorCode)) {
                continue;
            }
            line.listPrice = info.listPrice != null ? info.listPrice : info.price;
            line.oracleDiscountedPrice = OraclePricingResponse.resolveUnitPrice(info);
        }
    }

    private static void persistOraclePrices(List<PricingFrameworkOracleInvocable.PricingLine> lines, Boolean isQuote) {
        if (lines == null || lines.isEmpty()) {
            return;
        }

        List<SObject> updates = new List<SObject>();
        for (PricingFrameworkOracleInvocable.PricingLine line : lines) {
            if (line.listPrice == null && line.oracleDiscountedPrice == null) {
                continue;
            }
            Id lineId = asId(line.lineId);
            if (lineId == null) {
                continue;
            }
            Schema.SObjectType lineType = lineId.getSObjectType();
            if (isQuote && lineType != QuoteLineItem.SObjectType) {
                continue;
            }
            if (!isQuote && lineType != WorkOrderLineItem.SObjectType) {
                continue;
            }

            SObject record = isQuote
                ? (SObject) new QuoteLineItem(Id = lineId)
                : (SObject) new WorkOrderLineItem(Id = lineId);
            if (line.listPrice != null) {
                record.put('OracleListPrice__c', line.listPrice);
            }
            if (line.oracleDiscountedPrice != null) {
                record.put('OracleDiscountedPrice__c', line.oracleDiscountedPrice);
                record.put('UnitPrice', line.oracleDiscountedPrice);
            }
            updates.add(record);
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    @TestVisible
    private static String toPricingDataJson(String workstream, List<PricingFrameworkOracleInvocable.PricingLine> lines) {
        return toPricingDataJson(workstream, null, null, lines);
    }

    @TestVisible
    private static String toPricingDataJson(String workstream, Id accountId, List<PricingFrameworkOracleInvocable.PricingLine> lines) {
        return toPricingDataJson(workstream, accountId, null, lines);
    }

    @TestVisible
    private static String toPricingDataJson(
        String workstream,
        Id accountId,
        Id recordId,
        List<PricingFrameworkOracleInvocable.PricingLine> lines
    ) {
        String objectType = businessObjectType(workstream);
        Map<String, Object> header = buildHeadlessHeader(objectType, accountId, recordId, lines);
        return JSON.serialize(new Map<String, Object>{
            objectType => new List<Object>{ header }
        });
    }

    private static Map<String, Object> buildHeadlessHeader(
        String objectType,
        Id accountId,
        Id recordId,
        List<PricingFrameworkOracleInvocable.PricingLine> lines
    ) {
        Boolean isQuote = objectType == 'Quote';

        Map<Id, SObject> recordsByLineId = selectLineRecords(isQuote, lines);
        Map<String, Id> productIdByCode = selectProductIds(lines);
        Map<Id, Id> sellingModelByProductId = selectSellingModels(recordsByLineId, productIdByCode);
        Id fallbackSellingModelId = selectOneTimeSellingModelId();
        Id fallbackPricebookId = standardPricebookId();

        Id headerId = isHeaderRecordId(recordId) ? recordId : null;
        Id pricebookId;
        String currencyIsoCode;
        Id headerAccountId = accountId;
        List<Map<String, Object>> lineMaps = new List<Map<String, Object>>();

        for (PricingFrameworkOracleInvocable.PricingLine line : lines) {
            Id lineId = asId(line.lineId);
            SObject record = lineId == null ? null : recordsByLineId.get(lineId);
            Id productId = productIdFrom(record, line.productCode, productIdByCode);
            Id sellingModelId = productId == null
                ? fallbackSellingModelId
                : sellingModelByProductId.get(productId);
            if (sellingModelId == null) {
                sellingModelId = fallbackSellingModelId;
            }

            if (!isQuote && record instanceof WorkOrderLineItem) {
                WorkOrderLineItem woli = (WorkOrderLineItem) record;
                if (headerId == null) {
                    headerId = woli.WorkOrderId;
                }
                if (woli.WorkOrder != null) {
                    if (pricebookId == null) {
                        pricebookId = woli.WorkOrder.Pricebook2Id;
                    }
                    if (String.isBlank(currencyIsoCode)) {
                        currencyIsoCode = woli.WorkOrder.CurrencyIsoCode;
                    }
                    if (headerAccountId == null) {
                        headerAccountId = woli.WorkOrder.AccountId;
                    }
                }
                if (pricebookId == null && woli.PricebookEntry != null) {
                    pricebookId = woli.PricebookEntry.Pricebook2Id;
                }
            } else if (isQuote && record instanceof QuoteLineItem) {
                QuoteLineItem qli = (QuoteLineItem) record;
                if (headerId == null) {
                    headerId = qli.QuoteId;
                }
                if (qli.Quote != null) {
                    if (pricebookId == null) {
                        pricebookId = qli.Quote.Pricebook2Id;
                    }
                    if (String.isBlank(currencyIsoCode)) {
                        currencyIsoCode = qli.Quote.CurrencyIsoCode;
                    }
                    if (headerAccountId == null) {
                        headerAccountId = qli.Quote.AccountId;
                    }
                }
            }

            Id pricebookEntryId = record == null ? null : (Id) record.get('PricebookEntryId');
            String sourceKey = lineId == null ? line.lineId : String.valueOf(lineId);
            Map<String, Object> lineMap = new Map<String, Object>{
                'businessObjectType' => itemNodeName(objectType),
                'Quantity' => line.quantity
            };
            if (String.isNotBlank(sourceKey)) {
                lineMap.put('SalesTransactionItemSource', sourceKey);
            }
            if (lineId != null) {
                lineMap.put('id', lineId);
            }
            if (productId != null) {
                lineMap.put('Product', productId);
            }
            if (sellingModelId != null) {
                lineMap.put('ProductSellingModel', sellingModelId);
            }
            if (pricebookEntryId != null) {
                lineMap.put('PricebookEntry', pricebookEntryId);
            }
            if (String.isNotBlank(line.productCode)) {
                lineMap.put('ProductCode', line.productCode);
            }
            if (line.listPrice != null) {
                lineMap.put('ListPrice', line.listPrice);
                lineMap.put('OracleListPrice__c', line.listPrice);
            }
            if (line.oracleDiscountedPrice != null) {
                lineMap.put('OracleDiscountedPrice__c', line.oracleDiscountedPrice);
            }
            lineMaps.add(lineMap);
        }

        if (pricebookId == null) {
            pricebookId = fallbackPricebookId;
        }
        if (String.isBlank(currencyIsoCode)) {
            currencyIsoCode = UserInfo.getDefaultCurrency();
        }

        Map<String, Object> header = new Map<String, Object>{
            'businessObjectType' => objectType,
            itemNodeName(objectType) => lineMaps
        };
        if (headerId != null) {
            header.put('id', headerId);
            header.put('SalesTransactionSource', headerId);
        }
        if (pricebookId != null) {
            header.put('Pricebook', pricebookId);
        }
        if (String.isNotBlank(currencyIsoCode)) {
            header.put('CurrencyIsoCode', currencyIsoCode);
        }
        if (headerAccountId != null) {
            header.put('QuoteAccount', headerAccountId);
            header.put('Account', headerAccountId);
        }
        return header;
    }

    private static Map<Id, SObject> selectLineRecords(Boolean isQuote, List<PricingFrameworkOracleInvocable.PricingLine> lines) {
        Set<Id> lineIds = new Set<Id>();
        for (PricingFrameworkOracleInvocable.PricingLine line : lines) {
            Id lineId = asId(line.lineId);
            if (lineId != null) {
                lineIds.add(lineId);
            }
        }
        if (lineIds.isEmpty()) {
            return new Map<Id, SObject>();
        }

        Map<Id, SObject> recordsByLineId = new Map<Id, SObject>();
        if (isQuote) {
            for (QuoteLineItem lineItem :
                QuoteLineItemSelector.selectForPricingFrameworkHeadlessByIds(lineIds).values()
            ) {
                recordsByLineId.put(lineItem.Id, lineItem);
            }
        } else {
            for (WorkOrderLineItem lineItem :
                WorkOrderLineItemsSelector.selectForPricingFrameworkHeadlessByIds(lineIds).values()
            ) {
                recordsByLineId.put(lineItem.Id, lineItem);
            }
        }
        return recordsByLineId;
    }

    private static Map<String, Id> selectProductIds(List<PricingFrameworkOracleInvocable.PricingLine> lines) {
        Set<String> productCodes = new Set<String>();
        for (PricingFrameworkOracleInvocable.PricingLine line : lines) {
            if (String.isNotBlank(line.productCode)) {
                productCodes.add(line.productCode);
            }
        }
        Map<String, Id> productIdByCode = new Map<String, Id>();
        if (productCodes.isEmpty()) {
            return productIdByCode;
        }
        for (Product2 product : Product2Selector.selectIdsByProductCodes(productCodes)) {
            if (String.isNotBlank(product.ProductCode) && !productIdByCode.containsKey(product.ProductCode)) {
                productIdByCode.put(product.ProductCode, product.Id);
            }
        }
        return productIdByCode;
    }

    private static Map<Id, Id> selectSellingModels(
        Map<Id, SObject> recordsByLineId,
        Map<String, Id> productIdByCode
    ) {
        Set<Id> productIds = new Set<Id>(productIdByCode.values());
        for (SObject record : recordsByLineId.values()) {
            Id productId = (Id) record.get('Product2Id');
            if (productId != null) {
                productIds.add(productId);
            }
        }
        Map<Id, Id> sellingModelByProductId = new Map<Id, Id>();
        if (productIds.isEmpty()) {
            return sellingModelByProductId;
        }
        for (ProductSellingModelOption option :
            Product2Selector.selectSellingModelOptionsByProductIds(productIds)
        ) {
            if (option.Product2Id != null
                && option.ProductSellingModelId != null
                && !sellingModelByProductId.containsKey(option.Product2Id)
            ) {
                sellingModelByProductId.put(option.Product2Id, option.ProductSellingModelId);
            }
        }
        return sellingModelByProductId;
    }

    private static Id selectOneTimeSellingModelId() {
        return Product2Selector.selectOneTimeSellingModelId();
    }

    private static Id standardPricebookId() {
        return PricebookEntriesSelector.selectStandardPricebookId();
    }

    private static Id productIdFrom(
        SObject record,
        String productCode,
        Map<String, Id> productIdByCode
    ) {
        if (record != null) {
            Id productId = (Id) record.get('Product2Id');
            if (productId != null) {
                return productId;
            }
        }
        return String.isBlank(productCode) ? null : productIdByCode.get(productCode);
    }

    private static Id asId(String value) {
        if (String.isBlank(value) || (value.length() != 15 && value.length() != 18)) {
            return null;
        }
        try {
            return Id.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }

    private static String businessObjectType(String workstream) {
        if ('ServiceSales'.equalsIgnoreCase(workstream)) {
            return 'Quote';
        }
        return 'WorkOrder';
    }

    private static String itemNodeName(String objectType) {
        return objectType == 'Quote' ? 'QuoteLineItem' : 'WorkOrderItem';
    }

    private static String toStringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Decimal toDecimalValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }
        if (value instanceof Long) {
            return Decimal.valueOf((Long) value);
        }
        if (value instanceof Double) {
            return Decimal.valueOf((Double) value);
        }
        String asText = String.valueOf(value);
        if (String.isBlank(asText)) {
            return null;
        }
        return Decimal.valueOf(asText);
    }

    @TestVisible
    private static String toFlowErrorMessage(String errorMessage) {
        if (String.isBlank(errorMessage)) {
            return errorMessage;
        }
        String compact = errorMessage.stripHtmlTags().normalizeSpace();
        if (compact.length() > FLOW_ERROR_MESSAGE_MAX_LENGTH) {
            return compact.substring(0, FLOW_ERROR_MESSAGE_MAX_LENGTH) + '...';
        }
        return compact;
    }
}