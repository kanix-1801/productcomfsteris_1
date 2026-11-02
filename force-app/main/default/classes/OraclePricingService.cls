/**
 * Orchestrates Oracle getPricingDetail for a Work Order: CMDT + Account + line items, gateway callout,
 * maps results onto Work Order Line Items. Invoked from LWC via {@link #fetchAndApplyOraclePricing}.
 * <p>Nebula Logger: follows the
 * <a href="https://github.com/jongpie/NebulaLogger/wiki/Logging-in-Apex" target="_top">Apex quick start</a>
 * pattern (add entries, then a single {@code saveLog} in a {@code finally} block). Save method is chosen
 * in {@link #saveNebulaLogToStorage()}; see that method and Nebula’s {@code Logger.SaveMethod} docs.</p>
 *
 * @author Michal David (Uptima)
 */
public with sharing class OraclePricingService {
    private static final String POC_BUSINESS_ORG = 'STERIS US';
    private static final String POC_BUSINESS_GROUP = 'Other';
    private static final String P_SOURCE_SYSTEM_VALUE = 'SALESFORCE';

    /**
     * Payload returned to LWC after pricing is applied.
     */
    public class WorkOrderPricingResult {
        @AuraEnabled
        public Boolean success { get; set; }
        @AuraEnabled
        public String message { get; set; }
        @AuraEnabled
        public List<LinePricingRow> lines { get; set; }
    }

    /**
     * One Work Order line item row shown in the UI.
     */
    public class LinePricingRow {
        @AuraEnabled
        public Id workOrderLineItemId { get; set; }
        @AuraEnabled
        public String partNumber { get; set; }
        @AuraEnabled
        public Decimal oracleListPrice { get; set; }
        @AuraEnabled
        public Decimal oracleDiscountedPrice { get; set; }
    }

    /**
     * Loads Work Order context, calls Oracle pricing, updates line item prices, returns rows for the UI.
     *
     * @param workOrderId Work Order Id (record page).
     */
    @AuraEnabled
    public static WorkOrderPricingResult fetchAndApplyOraclePricing(Id workOrderId) {
        try {
            WorkOrderPricingResult output = new WorkOrderPricingResult();
            output.success = false;
            output.lines = new List<LinePricingRow>();

            if (workOrderId == null) {
                return failureResult('Work Order Id is required.');
            }

            if (!WorkOrder.SObjectType.getDescribe().isAccessible()) {
                return failureResult('You do not have access to Work Orders.');
            }
            if (!WorkOrderLineItem.SObjectType.getDescribe().isAccessible()) {
                return failureResult('You do not have access to Work Order Line Items.');
            }

            List<WorkOrder> workOrders;
            try {
                workOrders = [
                    SELECT Id, AccountId, Account.AccountNumber
                    FROM WorkOrder
                    WHERE Id = :workOrderId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
            } catch (QueryException qe) {
                Logger.error('OraclePricingService.fetchAndApplyOraclePricing WorkOrder query', qe);
                return failureResult('Unable to read this Work Order.');
            }

            if (workOrders.isEmpty()) {
                return failureResult('Work Order was not found.');
            }
            WorkOrder wo = workOrders[0];
            if (wo.AccountId == null) {
                return failureResult('Work Order must have an Account for Oracle pricing.');
            }
            String accountNumber = wo.Account.AccountNumber;
            if (String.isBlank(accountNumber)) {
                return failureResult('Account must have an Account Number for Oracle pricing.');
            }

            List<OraclePricingOrgPriceMapping__mdt> orgMappings = [
                SELECT BusinessOrg__c, PriceListCode__c, DiscountCode__c
                FROM OraclePricingOrgPriceMapping__mdt
                WHERE BusinessOrg__c = :POC_BUSINESS_ORG AND BusinessGroup__c = :POC_BUSINESS_GROUP
                LIMIT 1
            ];
            if (orgMappings.isEmpty()) {
                return failureResult(
                    'Oracle pricing is not configured for this org/group (Custom Metadata mapping missing).'
                );
            }
            OraclePricingOrgPriceMapping__mdt mapping = orgMappings[0];

            List<WorkOrderLineItem> lineItems;
            try {
                lineItems = [
                    SELECT Id, ProductCode__c
                    FROM WorkOrderLineItem
                    WHERE WorkOrderId = :workOrderId
                    WITH SECURITY_ENFORCED
                ];
            } catch (QueryException qe) {
                Logger.error('OraclePricingService.fetchAndApplyOraclePricing WOLI query', qe);
                return failureResult('Unable to read Work Order Line Items.');
            }

            List<String> distinctPartNumbers = new List<String>();
            Set<String> seenPartKeys = new Set<String>();
            for (WorkOrderLineItem woli : lineItems) {
                if (String.isBlank(woli.ProductCode__c)) {
                    continue;
                }
                String trimmed = woli.ProductCode__c.trim();
                String key = normalizePartKey(trimmed);
                if (seenPartKeys.add(key)) {
                    distinctPartNumbers.add(trimmed);
                }
            }
            if (distinctPartNumbers.isEmpty()) {
                return failureResult(
                    'No line items have an item number (Product Code). Add products to the lines first.'
                );
            }

            OraclePricingGateway.GetPricingDetailRequestDto request = buildGatewayRequest(
                mapping,
                accountNumber,
                accountNumber,
                distinctPartNumbers
            );
            OraclePricingGateway gateway = new OraclePricingGateway();
            OraclePricingGateway.GetPricingDetailResponseDto response = gateway.sendGetPricingDetail(request);

            Integer oracleLineCount =
                (response.OutputParameters != null && response.OutputParameters.X_ITEMS_TBL != null)
                ? response.OutputParameters.X_ITEMS_TBL.size()
                : 0;
            Logger.warn(
                'OraclePricingService.fetchAndApplyOraclePricing: parsed '
                    + String.valueOf(oracleLineCount)
                    + ' Oracle price line(s).'
            );

            Map<String, OraclePricingGateway.LineItemResponseDto> priceByPart = new Map<String, OraclePricingGateway.LineItemResponseDto>();
            if (response.OutputParameters != null && response.OutputParameters.X_ITEMS_TBL != null) {
                for (OraclePricingGateway.LineItemResponseDto row : response.OutputParameters.X_ITEMS_TBL) {
                    if (row != null && String.isNotBlank(row.PARTNUMBER)) {
                        priceByPart.put(normalizePartKey(row.PARTNUMBER), row);
                    }
                }
            }

            List<WorkOrderLineItem> toUpdate = new List<WorkOrderLineItem>();
            for (WorkOrderLineItem woli : lineItems) {
                if (String.isBlank(woli.ProductCode__c)) {
                    continue;
                }
                OraclePricingGateway.LineItemResponseDto priced = priceByPart.get(normalizePartKey(woli.ProductCode__c));
                if (priced == null) {
                    continue;
                }
                Boolean hasList = priced.LIST_PRICE != null;
                Boolean hasDiscounted = priced.PRICE != null;
                if (!hasList && !hasDiscounted) {
                    continue;
                }
                WorkOrderLineItem updateRow = new WorkOrderLineItem(Id = woli.Id);
                if (hasList) {
                    updateRow.OracleListPrice__c = priced.LIST_PRICE;
                }
                if (hasDiscounted) {
                    updateRow.OracleDiscountedPrice__c = priced.PRICE;
                    updateRow.UnitPrice = priced.PRICE;
                }
                toUpdate.add(updateRow);
            }

            if (toUpdate.isEmpty()) {
                // Diagnose: no WOLI got prices — compare requested Product Codes to Oracle X_ITEMS_TBL / keys
                List<String> respPartSamples = new List<String>();
                Integer rawTblSize = 0;
                if (response.OutputParameters != null && response.OutputParameters.X_ITEMS_TBL != null) {
                    rawTblSize = response.OutputParameters.X_ITEMS_TBL.size();
                    for (OraclePricingGateway.LineItemResponseDto r : response.OutputParameters.X_ITEMS_TBL) {
                        if (r == null) {
                            continue;
                        }
                        if (respPartSamples.size() < 10) {
                            respPartSamples.add(
                                'PN=' + r.PARTNUMBER + ',LIST=' + r.LIST_PRICE + ',PRICE=' + r.PRICE
                            );
                        }
                    }
                }
                String noMatchDiag =
                    'workOrderId='
                    + workOrderId
                    + ' requestedPartNumbers='
                    + String.valueOf(distinctPartNumbers)
                    + ' responseX_ITEMS_TBLSize='
                    + String.valueOf(rawTblSize)
                    + ' responseRowSamples='
                    + String.valueOf(respPartSamples);
                Logger.warn('OraclePricingService.fetchAndApplyOraclePricing: no line updates. ' + noMatchDiag);
                // TODO(Oracle pricing): remove temporary System.debug — troubleshooting only
                System.debug(LoggingLevel.DEBUG, 'OraclePricingService: ' + noMatchDiag);
                output.message = 'Oracle returned no prices matching your line item numbers.';
                output.success = true;
                return output;
            }

            if (!WorkOrderLineItem.SObjectType.getDescribe().isUpdateable()) {
                return failureResult('You cannot update Work Order Line Items.');
            }

            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, toUpdate);
            List<SObject> safeUpdates = decision.getRecords();
            if (safeUpdates.isEmpty()) {
                return failureResult('You do not have permission to update pricing fields on line items.');
            }
            update safeUpdates;
            Logger.warn(
                'OraclePricingService: DML updated '
                    + String.valueOf(safeUpdates.size())
                    + ' Work Order Line Item(s) with Oracle prices.'
            );

            Set<Id> updatedIds = new Set<Id>();
            for (SObject sobj : safeUpdates) {
                updatedIds.add(sobj.Id);
            }
            for (WorkOrderLineItem woli : lineItems) {
                if (!updatedIds.contains(woli.Id)) {
                    continue;
                }
                OraclePricingGateway.LineItemResponseDto pricedRow = priceByPart.get(
                    normalizePartKey(woli.ProductCode__c)
                );
                LinePricingRow row = new LinePricingRow();
                row.workOrderLineItemId = woli.Id;
                row.partNumber = woli.ProductCode__c;
                row.oracleListPrice = pricedRow != null ? pricedRow.LIST_PRICE : null;
                row.oracleDiscountedPrice = pricedRow != null ? pricedRow.PRICE : null;
                output.lines.add(row);
            }

            output.success = true;
            output.message = 'Updated ' + output.lines.size() + ' line item(s) with Oracle pricing.';
            return output;
        } catch (OraclePricingGateway.OraclePricingGatewayException e) {
            Logger.error('OraclePricingService.fetchAndApplyOraclePricing gateway', e);
            throw new AuraHandledException(e.getMessage());
        } catch (DmlException e) {
            Logger.error('OraclePricingService.fetchAndApplyOraclePricing DML', e);
            throw new AuraHandledException('Could not save prices: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            Logger.error('OraclePricingService.fetchAndApplyOraclePricing', e);
            throw new AuraHandledException('Oracle pricing failed. Please try again or contact support.');
        } finally {
            saveNebulaLogToStorage();
        }
    }

    /**
     * Persists the buffered {@code LogEntry} records in Nebula, per
     * <a href="https://github.com/jongpie/NebulaLogger/wiki/Logging-in-Apex" target="_top">Logging in Apex</a>
     * (end with one {@code saveLog} call; {@code Logger} buffers entries until then).
     * <p>Save method:</p>
     * <ul>
     *   <li><b>{@code SYNCHRONOUS_DML}</b> (first): Inserts {@code Log__c} / {@code LogEntry__c} immediately. The
     *     default <b>EVENT_BUS</b> method is async, so log rows may not exist until after the LWC call returns.
     *     Synchronous DML is appropriate for this one synchronous entry point, after Work Order line DML.</li>
     *   <li><b>We do not use {@code REST}</b> for this class: the wiki uses REST when a <i>second callout</i> is
     *     required to avoid mixed DML. Our transaction order is Oracle <i>callout</i> → <i>Work Order line DML</i>
     *     → <i>save log DML</i>. A callout-based save (REST) <i>after</i> line-item DML is not valid in the same
     *     request; finishing with synchronous DML to Nebula is correct here.</li>
     *   <li><b>Fallback</b> to parameterless {@code saveLog()}: uses org default (typically EVENT_BUS) if sync save
     *     fails; see the wiki for {@code SaveMethod} options.</li>
     * </ul>
     * <p>Also note: Nebula’s wiki warns that with {@code SYNCHRONOUS_DML}, an exception later in the transaction
     * can roll back the log DML; we use {@code try/finally} and catch save failures to avoid changing the UI.</p>
     */
    private static void saveNebulaLogToStorage() {
        try {
            Logger.saveLog(Logger.SaveMethod.SYNCHRONOUS_DML);
        } catch (Exception syncEx) {
            try {
                Logger.saveLog();
            } catch (Exception busEx) {
                System.debug(
                    LoggingLevel.WARN,
                    'OraclePricingService: Nebula Logger.saveLog failed. SYNCHRONOUS_DML: '
                        + syncEx.getMessage()
                        + ' Default: '
                        + busEx.getMessage()
                );
            }
        }
    }

    /**
     * Expected validation / access failures: return to LWC as {@code success = false} so the client
     * receives a resolved imperative response (avoids duplicate Lightning error surfaces for the same text).
     */
    private static WorkOrderPricingResult failureResult(String message) {
        WorkOrderPricingResult result = new WorkOrderPricingResult();
        result.success = false;
        result.message = message;
        result.lines = new List<LinePricingRow>();
        return result;
    }

    /**
     * @param billToAccountNumber When Oracle needs a different bill-to (see API: {@code P_BT_ACCT_NUM}),
     *     supply it here. Until a dedicated field exists on Account, the service passes the same value
     *     as ship-to ({@code P_ST_ACCT_NUM}).
     */
    private static OraclePricingGateway.GetPricingDetailRequestDto buildGatewayRequest(
        OraclePricingOrgPriceMapping__mdt mapping,
        String shipToAccountNumber,
        String billToAccountNumber,
        List<String> distinctPartNumbers
    ) {
        OraclePricingGateway.GetPricingDetailRequestDto dto = new OraclePricingGateway.GetPricingDetailRequestDto();
        dto.InputParameters = new OraclePricingGateway.InputParametersDto();
        dto.InputParameters.P_OU_NAME = mapping.BusinessOrg__c;
        dto.InputParameters.P_ST_ACCT_NUM = shipToAccountNumber;
        dto.InputParameters.P_BT_ACCT_NUM = billToAccountNumber;
        dto.InputParameters.P_PRICE_LIST_LEVEL = mapping.PriceListCode__c;
        dto.InputParameters.P_DISCOUNT_ACCOUNT = mapping.DiscountCode__c;
        List<OraclePricingGateway.LineItemRequestDto> partLines = new List<OraclePricingGateway.LineItemRequestDto>();
        for (String partNumber : distinctPartNumbers) {
            OraclePricingGateway.LineItemRequestDto lineReq = new OraclePricingGateway.LineItemRequestDto();
            lineReq.PARTNUMBER = partNumber;
            partLines.add(lineReq);
        }
        OraclePricingGateway.ItemsTableBlockDto itemsBlock = new OraclePricingGateway.ItemsTableBlockDto();
        itemsBlock.P_ITEMS_TBL_ITEM = partLines;
        dto.InputParameters.P_ITEMS_TBL = new List<OraclePricingGateway.ItemsTableBlockDto>{ itemsBlock };
        dto.InputParameters.P_SOURCE_SYSTEM = P_SOURCE_SYSTEM_VALUE;
        return dto;
    }

    private static String normalizePartKey(String partNumber) {
        return partNumber != null ? partNumber.trim().toUpperCase() : '';
    }
}