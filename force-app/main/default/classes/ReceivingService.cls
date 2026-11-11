/**
 * @description GW-5492 / GW-5968 - Orchestration for Repair Center Receiving
 *              (Return Order and Work Order paths). Controllers stay thin.
 *              Queries use SoqlQueryBuilder via object selectors.
 */
public with sharing class ReceivingService {
    private static final String RECORD_TYPE_CUSTOMER_RETURN = 'CustomerReturn';
    private static final String STATUS_RECEIVED = 'Received';
    private static final String STATUS_CANCELED = 'Canceled';
    private static final String STATUS_LINE_CREATED = 'Created';
    private static final String STATUS_LINE_REDIRECTED = 'Redirected';
    private static final String STATUS_LINE_RECEIVED = 'Received';
    private static final String CREDIT_HOLD = 'CREDIT HOLD';
    private static final String CIO_CATEGORY = 'Continuous Improvement Opportunity (CIO)';
    private static final String WARRANTY_YES = 'Yes';
    /** GW-5492 - Marks a file uploaded from the Receiving Mod Form. */
    public static final String MOD_FORM_FILE_DESCRIPTION = 'Mod Form';

    private static final String PATH_RETURN_ORDER = 'ReturnOrder';
    private static final String PATH_WORK_ORDER = 'WorkOrder';
    private static final String WO_RT_VENDOR = 'RepairCenterVendor';
    private static final String WO_RT_DEVICES = 'RepairCenterDevices';
    private static final String WO_RT_INSTRUMENTS = 'RepairCenterInstruments';
    private static final String HEADER_VENDOR_WORK_ORDER = 'Vendor Work Order';
    private static final String HEADER_WORK_ORDER = 'Work Order';
    /** GW-4348 / GW-5996 - Repair Centers allowed to use Create New Order. */
    private static final Set<String> CREATE_NEW_ORDER_REPAIR_CENTER_NAMES = new Set<String>{
        'DUN-NORTHAMPTON (UK)',
        'CAPITAL EQUIPMENT REPAIR CENTER'
    };
    private static final Set<String> RECEIVING_WORK_ORDER_RECORD_TYPES = new Set<String>{
        WO_RT_VENDOR,
        WO_RT_DEVICES,
        WO_RT_INSTRUMENTS
    };

    private static final String LINE_TYPE_PRODUCT_SERVICED = 'Product Serviced';
    private static final String LINE_TYPE_INBOUND = 'Inbound';
    private static final String WO_STATUS_RECEIVE_FROM_VENDOR = 'Receive from Vendor';
    private static final String WO_SUB_STATUS_CONTAMINATED = 'Contaminated';
    private static final String WO_SUB_STATUS_CUSTOMER_CARE = 'Customer Care';
    private static final String WO_SUB_STATUS_READY_FOR_EVAL = 'Ready for Eval';

    private static final List<String> WORK_ORDER_RECEIVING_SHELL_FIELDS = new List<String>{
        'Id',
        'WorkOrderNumber',
        'ShipComplete__c',
        'Product__c',
        'QuantityReceived__c',
        'IsPriorityRepair__c',
        'RepairWarranty__c',
        'ParentWorkOrderId',
        'ParentWorkOrder.Status',
        'ParentWorkOrder.SubStatus__c',
        'ParentWorkOrder.RecordType.DeveloperName',
        'AccountId',
        'Account.Name',
        'Account.SystemID__c',
        'Account.CreditStatusCode__c',
        'AssignedSalesPerson__c',
        'AssignedSalesPerson__r.Name',
        'OperatingUnit__c',
        'CaseId',
        'Case.Category__c',
        'RecordType.DeveloperName',
        'ProductLine_f__c',
        'CurrencyIsoCode',
        'Pricebook2Id',
        'ParentWorkOrder.Pricebook2Id',
        'VendorReturnOrder__c',
        'AssetId',
        'Asset.SerialNumber',
        'Asset.Product2Id',
        'Asset.Product2.ProductCode',
        'Asset.Product2.Model__c',
        'Asset.Product2.Description'
    };

    private static final List<String> WORK_ORDER_LINE_RECEIVING_FIELDS = new List<String>{
        'Id',
        'WorkOrderId',
        'LineItemNumber',
        'Quantity',
        'SerialNumber__c',
        'Model__c',
        'LineType__c',
        'IsAccessory__c',
        'IsPriorityRepair__c',
        'RepairWarranty__c',
        'VendorReturnOrder__c',
        'Product2Id',
        'Product2.ProductCode',
        'Product2.ProductLine__c',
        'Product2.SubProductLine__c',
        'Product2.DeviceType__c',
        'Product2.Model__c',
        'RecordType.DeveloperName',
        'AssetId',
        'Asset.SerialNumber',
        'Asset.Product2Id',
        'Asset.Product2.ProductCode',
        'Asset.Product2.Model__c',
        'Asset.Product2.Description'
    };

    private static final String TYPE_SERIALIZED = 'Serialized';
    private static final String TYPE_OTHER_SERIALIZED = 'Other (Serialized)';
    private static final String TYPE_OTHER_NON_SERIALIZED = 'Other (Non-Serialized)';
    private static final String TYPE_INSTRUMENTS = 'Instruments';
    private static final String MODEL_ANY = 'ANY';
    private static final String MODEL_GENERIC = 'GENERIC';

    private static final String BADGE_VARIANT_INFO = 'info';
    private static final String BADGE_VARIANT_ALERT = 'alert';
    private static final String BADGE_VARIANT_REDIRECT = 'redirect';
    private static final String BADGE_VARIANT_WARNING = 'warning';
    private static final String BADGE_VARIANT_COMPLETE = 'complete';
    private static final String BADGE_ICON_INFO = 'utility:info';
    private static final String BADGE_ICON_ALERT = 'utility:path_experiment';
    private static final String BADGE_ICON_REDIRECT = 'utility:truck';
    private static final String BADGE_ICON_COMPLETE = 'utility:success';
    private static final String BADGE_ICON_WARNING = 'utility:warning';

    /** Test seam for VendorRequiredProductRule__mdt matching. */
    @TestVisible
    private static List<VendorRequiredProductRule__mdt> vendorRequiredRulesOverride;

    private static final List<String> RETURN_ORDER_RECEIVING_FIELDS = new List<String>{
        'Id',
        'ReturnOrderNumber',
        'Status',
        'ReturnOrderType__c',
        'OperatingUnit__c',
        'RepairWarranty__c',
        'AccountId',
        'Account.Name',
        'Account.SystemID__c',
        'Account.OrgIDs__c',
        'Account.CreditStatusCode__c',
        'SalesRep__c',
        'SalesRep__r.Name',
        'CaseId',
        'Case.Category__c',
        'DestinationLocationId',
        'DestinationLocation.Name',
        'RecordType.DeveloperName'
    };

    private static final String DISINFECTED_YES = 'Yes, Item is Disinfected';
    private static final String DISINFECTED_NO = 'No, Item is not Disinfected';
    private static final String UI_CLEAN = 'Clean';
    private static final String UI_CONTAMINATED = 'Contaminated';
    private static final String SERVICE_CODE_TYPE_DISINFECTION = 'Disinfection';

    private static final List<String> LINE_ITEM_RECEIVING_FIELDS = new List<String>{
        'Id',
        'ReturnOrderId',
        'Status__c',
        'QuantityReturned',
        'SerialNumber__c',
        'Model__c',
        'ProductLine__c',
        'Disinfected__c',
        'IsPriorityRepair__c',
        'IsRepairExchange__c',
        'RepairWarranty__c',
        'Product2Id',
        'Product2.Name',
        'Product2.ProductCode',
        'Product2.Model__c',
        'Product2.ProductLine__c',
        'Product2.SubProductLine__c',
        'Product2.DeviceType__c'
    };

    /**
     * @description Scan resolve result for the Receiving LWC.
     */
    public class ScanResolveResult {
        @AuraEnabled public String returnOrderId;
        @AuraEnabled public String returnOrderNumber;
        @AuraEnabled public String workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public String pathType;
    }

    /**
     * @description GW-5492 Item header badge (Priority, Contaminated, Redirect, etc.).
     */
    public class ReceivingBadge {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String variant;
        @AuraEnabled public String iconName;
    }

    /**
     * @description Receiving Item row (GW-5492 Screen 2). One Item may map to one or more ROLIs.
     */
    public class ReceivingShellItem {
        @AuraEnabled public String itemKey;
        @AuraEnabled public Integer itemNumber;
        @AuraEnabled public String headerTitle;
        @AuraEnabled public String displayTitle;
        @AuraEnabled public String lineItemId;
        @AuraEnabled public String assetId;
        @AuraEnabled public String product2Id;
        @AuraEnabled public Decimal quantityReturned;
        @AuraEnabled public String productCode;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String model;
        @AuraEnabled public String serialVerifyLabel;
        @AuraEnabled public String modelVerifyLabel;
        @AuraEnabled public Boolean showSerialVerify;
        @AuraEnabled public Boolean showModelVerify;
        @AuraEnabled public Boolean showQuantityVerify;
        @AuraEnabled public Boolean showDisinfectedVerify;
        @AuraEnabled public Boolean isInstrumentItem;
        @AuraEnabled public Boolean showOutsideVendor;
        @AuraEnabled public Boolean isVendorRequired;
        @AuraEnabled public Boolean isPriorityRepair;
        @AuraEnabled public Boolean isRepairExchange;
        @AuraEnabled public Boolean vendorVerifiedDefault;
        @AuraEnabled public String disinfectedUiValue;
        @AuraEnabled public List<ReceivingBadge> badges;
    }

    /**
     * @description Aggregated badge inputs for one or more ROLIs under an Item.
     */
    private class BadgeAggregate {
        Boolean isPriorityRepair;
        Boolean isRepairExchange;
        Boolean isContaminated;
        Boolean isRedirected;
        Boolean hasWorkOrder;
        Boolean isRepairWarranty;
        Decimal accessoryQuantity;
        List<String> customerCareReasonCodes = new List<String>();
    }

    /**
     * @description Related WO / accessory data keyed by ROLI Id for badge assembly.
     */
    private class BadgeRelatedData {
        Map<Id, Boolean> hasWorkOrderByLineItemId = new Map<Id, Boolean>();
        Map<Id, Decimal> accessoryQuantityByLineItemId = new Map<Id, Decimal>();
        Map<Id, List<String>> reasonCodesByLineItemId = new Map<Id, List<String>>();
    }

    /**
     * @description Header/shell context for the Receiving RO or WO screen.
     */
    public class ReceivingShellContext {
        @AuraEnabled public String pathType;
        @AuraEnabled public Boolean isVendorWorkOrder;
        @AuraEnabled public String returnOrderId;
        @AuraEnabled public String returnOrderNumber;
        @AuraEnabled public String returnOrderType;
        @AuraEnabled public String workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public String workOrderRecordTypeDeveloperName;
        /** GW-6070 - True when the scanned Work Order must ship complete. */
        @AuraEnabled public Boolean shipComplete;
        @AuraEnabled public String headerTitle;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String salesRepName;
        @AuraEnabled public String operatingUnit;
        @AuraEnabled public String legacyCustomerId;
        @AuraEnabled public String receiverName;
        @AuraEnabled public Boolean isCio;
        @AuraEnabled public Boolean isCreditHold;
        @AuraEnabled public String destinationLocationId;
        @AuraEnabled public String destinationLocationName;
        @AuraEnabled public List<ReceivingShellItem> items;
    }

    /**
     * @description Label/value pair for Receiving picklists.
     */
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    /**
     * @description GW-5492 / GW-5968 - Resolves Scan Order input to a receivable
     *              Customer Return Order or Repair Center Work Order.
     * @param scanInput Salesforce Id or Return/Work Order number
     * @return Scan resolve result for the RO or WO path
     */
    public static ScanResolveResult resolveScanInput(String scanInput) {
        String trimmed = scanInput == null ? null : scanInput.trim();
        if (String.isBlank(trimmed)) {
            throw new ReceivingServiceException('Scan Order is required.');
        }

        try {
            Id typedId = tryParseId(trimmed);
            if (typedId != null) {
                if (typedId.getSObjectType() == ReturnOrder.SObjectType) {
                    ReturnOrder returnOrder = requireReturnOrderForReceiving(typedId);
                    return toScanResult(returnOrder);
                }
                if (typedId.getSObjectType() == WorkOrder.SObjectType) {
                    WorkOrder workOrder = requireWorkOrderForReceiving(typedId);
                    return toScanResult(workOrder);
                }
            }

            ReturnOrder byNumber = findReturnOrderByNumber(trimmed);
            if (byNumber != null) {
                validateReturnOrderForReceiving(byNumber);
                return toScanResult(byNumber);
            }

            List<WorkOrder> workOrdersByNumber = queryWorkOrdersByNumber(trimmed);
            if (!workOrdersByNumber.isEmpty()) {
                if (workOrdersByNumber.size() > 1) {
                    throw new ReceivingServiceException(
                        'Multiple Work Orders were found for the entered value. Scan the Work Order Id.'
                    );
                }
                validateWorkOrderForReceiving(workOrdersByNumber[0]);
                return toScanResult(workOrdersByNumber[0]);
            }

            throw new ReceivingServiceException(
                'No valid Return Order or Work Order was found for the entered value.'
            );
        } catch (ReceivingServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('ReceivingService.resolveScanInput: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to resolve Scan Order: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5492 - Repair Center Location Names for Redirect.
     * @return Picklist options with Location Id values and Name labels
     */
    public static List<PicklistOption> getRepairCenterOptions() {
        try {
            List<PicklistOption> options = new List<PicklistOption>();
            for (Schema.Location locationRecord : LocationsService.getRepairCenters()) {
                PicklistOption option = new PicklistOption();
                option.label = locationRecord.Name;
                option.value = String.valueOf(locationRecord.Id);
                options.add(option);
            }
            return options;
        } catch (Exception e) {
            Logger.error('ReceivingService.getRepairCenterOptions: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to load repair centers: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-4348 / GW-5996 - Whether Create New Order is available for the
     *              running user based on their Repair Center Service Resource.
     * @return true when the user's Repair Center is DUN-NORTHAMPTON (UK) or
     *         CAPITAL EQUIPMENT REPAIR CENTER
     */
    public static Boolean canCreateNewOrder() {
        try {
            String repairCenterName = ServiceResourcesService.getRepairCenterNameForCurrentUser();
            return String.isNotBlank(repairCenterName)
                && CREATE_NEW_ORDER_REPAIR_CENTER_NAMES.contains(repairCenterName);
        } catch (Exception e) {
            Logger.error('ReceivingService.canCreateNewOrder: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to determine Create New Order eligibility: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-4348 / GW-5996 - Groups Create Order items by Product Line, PO, and Ship-To.
     *              Repair Center comes from the current user's Service Resource (no RO routing).
     * @param headerJson Account / OU / Sales Rep header
     * @param itemsJson Serialized item payloads from createOrderItems
     * @return Proposed order groups for the Review screen
     */
    public static List<CreateOrderGroup> buildCreateOrderPlan(
        String headerJson,
        String itemsJson
    ) {
        try {
            return buildCreateOrderPlanInternal(headerJson, itemsJson);
        } catch (ReceivingServiceException e) {
            Logger.error('ReceivingService.buildCreateOrderPlan: Business error.', e);
            Logger.saveLog();
            throw e;
        } catch (Exception e) {
            Logger.error('ReceivingService.buildCreateOrderPlan: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to build Create Order plan: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-4348 / GW-5996 - Creates Customer Return Orders via Create RO mappings.
     *              Work Orders are created in a separate Apex transaction per RO (LWC loops
     *              createWorkOrdersForCreateOrder) to avoid Work Order before-save Flow limits.
     * @param headerJson Account / OU / Sales Rep header
     * @param itemsJson Serialized item payloads from createOrderItems
     * @return Created Return Order Ids for navigation / WO create follow-up
     */
    public static CreateOrderSubmitResult submitCreateOrder(
        String headerJson,
        String itemsJson
    ) {
        Logger.setScenario('Create Order Submit');
        try {
            List<CreateOrderGroup> groups = buildCreateOrderPlanInternal(headerJson, itemsJson);
            if (groups.isEmpty()) {
                throw new ReceivingServiceException('Add at least one item before creating orders.');
            }

            Map<String, Object> header = (Map<String, Object>) JSON.deserializeUntyped(headerJson);
            if (header.get('creationSource') == null ||
                String.isBlank(String.valueOf(header.get('creationSource')))) {
                header.put('creationSource', 'Salesforce');
            }
            String normalizedHeaderJson = JSON.serialize(header);

            List<Map<String, Object>> createGroups = new List<Map<String, Object>>();
            for (CreateOrderGroup groupRecord : groups) {
                Map<String, Object> payload = new Map<String, Object>{
                    'groupKey' => groupRecord.groupKey,
                    'repairCenterId' => groupRecord.repairCenterId,
                    'requiresRepairCenterSelection' => false,
                    'lineItemsJson' => groupRecord.lineItemsJson
                };
                createGroups.add(payload);
            }

            List<ReturnOrdersService.GroupedReturnOrderResult> createdOrders =
                ReturnOrdersService.createGroupedReturnOrders(
                    normalizedHeaderJson,
                    JSON.serialize(createGroups)
                );

            CreateOrderSubmitResult result = new CreateOrderSubmitResult();
            result.returnOrderIds = new List<Id>();
            result.returnOrderNumbers = new List<String>();
            result.workOrderIds = new List<Id>();

            if (createdOrders.isEmpty()) {
                throw new ReceivingServiceException('No return orders were created.');
            }

            for (ReturnOrdersService.GroupedReturnOrderResult created : createdOrders) {
                Id returnOrderId = created.returnOrderId;
                result.returnOrderIds.add(returnOrderId);
                result.returnOrderNumbers.add(created.returnOrderNumber);
                if (result.navigationReturnOrderId == null) {
                    result.navigationReturnOrderId = returnOrderId;
                }
            }
            return result;
        } catch (ReceivingServiceException e) {
            Logger.error('ReceivingService.submitCreateOrder: Business error.', e);
            Logger.saveLog();
            throw e;
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            Logger.error('ReceivingService.submitCreateOrder: Create RO error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ReceivingService.submitCreateOrder: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to create orders: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-4348 / GW-5996 - Create parent/child RepairCenterDevices WOs for one
     *              Create Order Return Order (one transaction per RO).
     * @param returnOrderId Newly created Customer Return Order Id
     * @return Created parent Work Order Id and number for confirmation
     */
    public static CreateOrderCreatedWorkOrder createWorkOrdersForCreateOrder(Id returnOrderId) {
        Logger.setScenario('Create Order Work Orders');
        try {
            return ReceivingFinishService.createWorkOrdersForCreateOrder(returnOrderId);
        } catch (ReceivingServiceException e) {
            Logger.error('ReceivingService.createWorkOrdersForCreateOrder: Business error.', e);
            Logger.saveLog();
            throw e;
        } catch (Exception e) {
            Logger.error('ReceivingService.createWorkOrdersForCreateOrder: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to create Work Orders: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    private static List<CreateOrderGroup> buildCreateOrderPlanInternal(
        String headerJson,
        String itemsJson
    ) {
        Map<String, Object> header = String.isBlank(headerJson)
            ? new Map<String, Object>()
            : (Map<String, Object>) JSON.deserializeUntyped(headerJson);
        List<Object> itemObjects = String.isBlank(itemsJson)
            ? new List<Object>()
            : (List<Object>) JSON.deserializeUntyped(itemsJson);

        if (header.get('accountId') == null || String.isBlank(String.valueOf(header.get('accountId')))) {
            throw new ReceivingServiceException('Account is required.');
        }
        if (
            header.get('operatingUnit') == null ||
            String.isBlank(String.valueOf(header.get('operatingUnit')))
        ) {
            throw new ReceivingServiceException('Operating Unit is required.');
        }
        if (itemObjects.isEmpty()) {
            throw new ReceivingServiceException('Add at least one item.');
        }

        Id repairCenterId = ServiceResourcesService.getRepairCenterIdForCurrentUser();
        String repairCenterName = ServiceResourcesService.getRepairCenterNameForCurrentUser();
        if (repairCenterId == null || String.isBlank(repairCenterName)) {
            throw new ReceivingServiceException(
                'A Repair Center Service Resource is required for Create New Order.'
            );
        }

        Map<String, List<Object>> linesByGroupKey = new Map<String, List<Object>>();
        Map<String, String> productLineByGroupKey = new Map<String, String>();
        Integer lineIndex = 0;
        for (Object itemObj : itemObjects) {
            Map<String, Object> item = (Map<String, Object>) itemObj;
            Map<String, Object> line = normalizeCreateOrderLine(item, lineIndex);
            lineIndex++;
            String groupKey = buildCreateOrderGroupKey(line);
            if (!linesByGroupKey.containsKey(groupKey)) {
                linesByGroupKey.put(groupKey, new List<Object>());
                productLineByGroupKey.put(
                    groupKey,
                    String.valueOf(line.get('productLine') == null ? '' : line.get('productLine'))
                );
            }
            linesByGroupKey.get(groupKey).add(line);
        }

        List<String> sortedKeys = new List<String>(linesByGroupKey.keySet());
        sortedKeys.sort();

        List<CreateOrderGroup> groups = new List<CreateOrderGroup>();
        Integer displayIndex = 1;
        for (String groupKey : sortedKeys) {
            List<Object> groupedLines = linesByGroupKey.get(groupKey);
            CreateOrderGroup groupRecord = new CreateOrderGroup();
            groupRecord.groupKey = groupKey;
            groupRecord.displayIndex = displayIndex;
            groupRecord.displayTitle = 'Order #' + displayIndex;
            groupRecord.productLine = productLineByGroupKey.get(groupKey);
            groupRecord.repairCenterId = repairCenterId;
            groupRecord.repairCenterName = repairCenterName;
            groupRecord.lineCount = groupedLines.size();
            groupRecord.lineItemsJson = JSON.serialize(groupedLines);
            groupRecord.lines = new List<CreateOrderLineSummary>();
            for (Object lineObj : groupedLines) {
                Map<String, Object> line = (Map<String, Object>) lineObj;
                CreateOrderLineSummary summary = new CreateOrderLineSummary();
                summary.lineKey = String.valueOf(line.get('key'));
                summary.serialNumber = String.valueOf(
                    line.get('serialNumber') == null ? '' : line.get('serialNumber')
                );
                summary.model = String.valueOf(line.get('model') == null ? '' : line.get('model'));
                summary.quantityLabel = '1';
                groupRecord.lines.add(summary);
            }
            groups.add(groupRecord);
            displayIndex++;
        }
        return groups;
    }

    private static Map<String, Object> normalizeCreateOrderLine(
        Map<String, Object> item,
        Integer lineIndex
    ) {
        Map<String, Object> line = new Map<String, Object>(item);
        line.put('lineType', 'serialized');
        if (line.get('itemType') == null || String.isBlank(String.valueOf(line.get('itemType')))) {
            line.put('itemType', 'serialized');
        }
        if (line.get('key') == null || String.isBlank(String.valueOf(line.get('key')))) {
            line.put('key', 'item-' + String.valueOf(lineIndex + 1));
        }
        if (line.get('quantityReturned') == null) {
            line.put('quantityReturned', 1);
        }

        List<Object> attachmentObjects = line.get('attachments') instanceof List<Object>
            ? (List<Object>) line.get('attachments')
            : new List<Object>();
        List<String> contentDocumentIds = new List<String>();
        for (Object attachmentObj : attachmentObjects) {
            if (!(attachmentObj instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> attachment = (Map<String, Object>) attachmentObj;
            Object documentId = attachment.get('contentDocumentId');
            if (documentId != null && String.isNotBlank(String.valueOf(documentId))) {
                contentDocumentIds.add(String.valueOf(documentId));
            }
        }
        line.put('contentDocumentIds', contentDocumentIds);
        return line;
    }

    private static String buildCreateOrderGroupKey(Map<String, Object> line) {
        String productLine = normalizeCreateOrderSegment(
            line == null ? null : (String) line.get('productLine'),
            true
        );
        String customerPo = normalizeCreateOrderSegment(
            line == null ? null : (String) line.get('customerPo'),
            true
        );
        String shipToAccountId = normalizeCreateOrderSegment(
            line == null ? null : (String) line.get('shipToAccountId'),
            false
        );
        return 'PL|' + productLine + '|PO|' + customerPo + '|ST|' + shipToAccountId;
    }

    private static String normalizeCreateOrderSegment(String value, Boolean ignoreCase) {
        if (String.isBlank(value)) {
            return 'UNSPECIFIED';
        }
        return ignoreCase ? value.trim().toUpperCase() : value.trim();
    }

    /**
     * @description GW-5492 - Internal Account options for Internal Repair (Account.Type = I).
     * @return Picklist options with Account Id values and Number - Name labels
     */
    public static List<PicklistOption> getInternalAccountOptions() {
        try {
            List<PicklistOption> options = new List<PicklistOption>();
            for (Account accountRecord : AccountSelector.selectInternalAccountsForReceiving()) {
                PicklistOption option = new PicklistOption();
                option.label = formatAccountNumberAndName(accountRecord);
                option.value = String.valueOf(accountRecord.Id);
                options.add(option);
            }
            return options;
        } catch (Exception e) {
            Logger.error('ReceivingService.getInternalAccountOptions: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to load internal accounts: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5492 - Dropdown label: Account Number - Account Name.
     * @param accountRecord Account with Name and AccountNumber
     * @return Formatted label
     */
    private static String formatAccountNumberAndName(Account accountRecord) {
        String accountName = accountRecord == null ? null : accountRecord.Name;
        String accountNumber = accountRecord == null ? null : accountRecord.AccountNumber;
        if (String.isBlank(accountNumber)) {
            return accountName;
        }
        if (String.isBlank(accountName)) {
            return accountNumber;
        }
        return accountNumber + ' - ' + accountName;
    }

    /**
     * @description GW-5492 - Vendor Account options for Outside Vendor (Account.Type = Vendor).
     * @return Picklist options with Account Id values and Name labels
     */
    public static List<PicklistOption> getVendorAccountOptions() {
        try {
            List<PicklistOption> options = new List<PicklistOption>();
            for (Account accountRecord : AccountSelector.selectVendorAccountsForReceiving()) {
                PicklistOption option = new PicklistOption();
                option.label = accountRecord.Name;
                option.value = String.valueOf(accountRecord.Id);
                options.add(option);
            }
            return options;
        } catch (Exception e) {
            Logger.error('ReceivingService.getVendorAccountOptions: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to load vendor accounts: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5492 - Validates a Return Order Id for Receiving and returns shell context.
     * @param returnOrderId Return Order Id
     * @return Receiving shell context
     */
    public static ReceivingShellContext getReceivingShellContext(Id returnOrderId) {
        if (returnOrderId == null) {
            throw new ReceivingServiceException('Return Order is required.');
        }
        try {
            ReturnOrder returnOrder = requireReturnOrderForReceiving(returnOrderId);
            List<ReturnOrderLineItem> lineItems = queryShellLineItems(returnOrder.Id);
            return toShellContext(returnOrder, lineItems);
        } catch (ReceivingServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                'ReceivingService.getReceivingShellContext: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to load Receiving context: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5968 - Validates a Work Order Id for Receiving and returns shell context
     *              (header / account shell; item list filled in later phases).
     * @param workOrderId Work Order Id
     * @return Receiving shell context for the Work Order path
     */
    public static ReceivingShellContext getWorkOrderReceivingShellContext(Id workOrderId) {
        if (workOrderId == null) {
            throw new ReceivingServiceException('Work Order is required.');
        }
        try {
            WorkOrder workOrder = requireWorkOrderForReceiving(workOrderId);
            return toWorkOrderShellContext(workOrder);
        } catch (ReceivingServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                'ReceivingService.getWorkOrderReceivingShellContext: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to load Work Order Receiving context: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    private static ReturnOrder requireReturnOrderForReceiving(Id returnOrderId) {
        List<ReturnOrder> rows = queryReturnOrdersById(new Set<Id>{ returnOrderId });
        if (rows.isEmpty()) {
            throw new ReceivingServiceException('Return Order was not found.');
        }
        validateReturnOrderForReceiving(rows[0]);
        return rows[0];
    }

    private static void validateReturnOrderForReceiving(ReturnOrder returnOrder) {
        if (returnOrder == null) {
            throw new ReceivingServiceException('Return Order was not found.');
        }
        if (
            returnOrder.RecordType == null ||
            returnOrder.RecordType.DeveloperName != RECORD_TYPE_CUSTOMER_RETURN
        ) {
            throw new ReceivingServiceException(
                'Only Customer Return Orders can be received here.'
            );
        }
        if (returnOrder.Status == STATUS_CANCELED) {
            throw new ReceivingServiceException(
                'This return order is canceled. Enter another return order number.'
            );
        }
        if (returnOrder.Status == STATUS_RECEIVED) {
            throw new ReceivingServiceException(
                'This return order is already received. Enter another return order number.'
            );
        }
        if (!hasCreatedLinesForReceiving(returnOrder.Id)) {
            throw new ReceivingServiceException(
                'This return order has no open line items. Enter another return order number.'
            );
        }
    }

    private static ReturnOrder findReturnOrderByNumber(String returnOrderNumber) {
        Set<String> candidateNumbers = buildReturnOrderNumberCandidates(returnOrderNumber);
        List<ReturnOrder> rows = queryReturnOrdersByNumbers(candidateNumbers);
        if (rows.isEmpty()) {
            return null;
        }
        if (rows.size() == 1) {
            return rows[0];
        }
        for (ReturnOrder row : rows) {
            if (row.ReturnOrderNumber == returnOrderNumber) {
                return row;
            }
        }
        return rows[0];
    }

    private static List<ReturnOrder> queryReturnOrdersById(Set<Id> returnOrderIds) {
        if (returnOrderIds == null || returnOrderIds.isEmpty()) {
            return new List<ReturnOrder>();
        }
        return (List<ReturnOrder>) new ReturnOrdersSelector()
            .selectFields(RETURN_ORDER_RECEIVING_FIELDS)
            .whereIn('Id', new List<Id>(returnOrderIds))
            .execute();
    }

    private static List<ReturnOrder> queryReturnOrdersByNumbers(Set<String> candidateNumbers) {
        if (candidateNumbers == null || candidateNumbers.isEmpty()) {
            return new List<ReturnOrder>();
        }
        return (List<ReturnOrder>) new ReturnOrdersSelector()
            .selectFields(RETURN_ORDER_RECEIVING_FIELDS)
            .whereIn('ReturnOrderNumber', new List<String>(candidateNumbers))
            .orderByDesc('CreatedDate')
            .execute();
    }

    private static Boolean hasCreatedLinesForReceiving(Id returnOrderId) {
        if (returnOrderId == null) {
            return false;
        }
        ReturnOrderLineItem lineItem = (ReturnOrderLineItem) new ReturnOrderLineItemsSelector()
            .selectField('Id')
            .whereEquals('ReturnOrderId', returnOrderId)
            .whereEquals('Status__c', STATUS_LINE_CREATED)
            .first();
        return lineItem != null;
    }

    /**
     * @description Line items shown on the Receiving shell (open + post-action statuses for badges).
     */
    private static List<ReturnOrderLineItem> queryShellLineItems(Id returnOrderId) {
        if (returnOrderId == null) {
            return new List<ReturnOrderLineItem>();
        }
        return (List<ReturnOrderLineItem>) new ReturnOrderLineItemsSelector()
            .selectFields(LINE_ITEM_RECEIVING_FIELDS)
            .whereEquals('ReturnOrderId', returnOrderId)
            .whereIn(
                'Status__c',
                new List<String>{
                    STATUS_LINE_CREATED,
                    STATUS_LINE_REDIRECTED,
                    STATUS_LINE_RECEIVED
                }
            )
            .orderBy('CreatedDate')
            .execute();
    }

    private static WorkOrder requireWorkOrderForReceiving(Id workOrderId) {
        WorkOrder workOrder = queryWorkOrderForShell(workOrderId);
        if (workOrder == null) {
            throw new ReceivingServiceException('Work Order was not found.');
        }
        validateWorkOrderForReceiving(workOrder);
        return workOrder;
    }

    private static void validateWorkOrderForReceiving(WorkOrder workOrder) {
        if (workOrder == null) {
            throw new ReceivingServiceException('Work Order was not found.');
        }
        String recordTypeDeveloperName = workOrder.RecordType == null
            ? null
            : workOrder.RecordType.DeveloperName;
        if (
            String.isBlank(recordTypeDeveloperName) ||
            !RECEIVING_WORK_ORDER_RECORD_TYPES.contains(recordTypeDeveloperName)
        ) {
            throw new ReceivingServiceException(
                'Only Repair Center Work Orders can be received here.'
            );
        }
    }

    private static WorkOrder queryWorkOrderForShell(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }
        return (WorkOrder) new WorkOrdersSelector()
            .selectFields(WORK_ORDER_RECEIVING_SHELL_FIELDS)
            .whereEquals('Id', workOrderId)
            .first();
    }

    private static List<WorkOrder> queryWorkOrdersByNumber(String workOrderNumber) {
        if (String.isBlank(workOrderNumber)) {
            return new List<WorkOrder>();
        }
        return (List<WorkOrder>) new WorkOrdersSelector()
            .selectFields(WORK_ORDER_RECEIVING_SHELL_FIELDS)
            .whereEquals('WorkOrderNumber', workOrderNumber)
            .limitTo(5)
            .execute();
    }

    private static Set<String> buildReturnOrderNumberCandidates(String returnOrderNumber) {
        Set<String> candidateNumbers = new Set<String>{ returnOrderNumber };
        String upperNumber = returnOrderNumber.toUpperCase();
        if (upperNumber.startsWith('RO')) {
            String suffix = returnOrderNumber.substring(2).replaceFirst('^[-\\s]+', '');
            if (String.isNotBlank(suffix)) {
                candidateNumbers.add(suffix);
            }
        } else {
            candidateNumbers.add('RO' + returnOrderNumber);
            candidateNumbers.add('RO-' + returnOrderNumber);
        }
        return candidateNumbers;
    }

    private static ScanResolveResult toScanResult(ReturnOrder returnOrder) {
        ScanResolveResult result = new ScanResolveResult();
        result.returnOrderId = returnOrder.Id;
        result.returnOrderNumber = returnOrder.ReturnOrderNumber;
        result.pathType = PATH_RETURN_ORDER;
        return result;
    }

    private static ScanResolveResult toScanResult(WorkOrder workOrder) {
        ScanResolveResult result = new ScanResolveResult();
        result.workOrderId = workOrder.Id;
        result.workOrderNumber = workOrder.WorkOrderNumber;
        result.pathType = PATH_WORK_ORDER;
        return result;
    }

    private static ReceivingShellContext toShellContext(
        ReturnOrder returnOrder,
        List<ReturnOrderLineItem> lineItems
    ) {
        ReceivingShellContext context = new ReceivingShellContext();
        context.pathType = PATH_RETURN_ORDER;
        context.returnOrderId = returnOrder.Id;
        context.returnOrderNumber = returnOrder.ReturnOrderNumber;
        context.returnOrderType = returnOrder.ReturnOrderType__c;
        context.headerTitle = String.isBlank(returnOrder.ReturnOrderNumber)
            ? 'Receive Order'
            : 'Receive Order ' + returnOrder.ReturnOrderNumber;
        context.accountId = returnOrder.AccountId;
        context.accountName = returnOrder.Account == null ? null : returnOrder.Account.Name;
        context.salesRepName = returnOrder.SalesRep__r == null
            ? null
            : returnOrder.SalesRep__r.Name;
        context.operatingUnit = resolveOperatingUnitDisplay(returnOrder);
        context.legacyCustomerId = returnOrder.Account == null
            ? null
            : returnOrder.Account.SystemID__c;
        context.receiverName = UserInfo.getName();
        context.isCio =
            returnOrder.CaseId != null &&
            returnOrder.Case != null &&
            returnOrder.Case.Category__c == CIO_CATEGORY;
        context.isCreditHold =
            returnOrder.Account != null &&
            returnOrder.Account.CreditStatusCode__c == CREDIT_HOLD;
        context.destinationLocationId = returnOrder.DestinationLocationId;
        context.destinationLocationName = returnOrder.DestinationLocation == null
            ? null
            : returnOrder.DestinationLocation.Name;
        BadgeRelatedData relatedData = loadBadgeRelatedData(lineItems);
        Boolean returnOrderRepairWarranty = returnOrder.RepairWarranty__c == WARRANTY_YES;
        context.items = toShellItems(
            returnOrder.ReturnOrderType__c,
            lineItems,
            returnOrderRepairWarranty,
            relatedData
        );
        return context;
    }

    private static ReceivingShellContext toWorkOrderShellContext(WorkOrder workOrder) {
        ReceivingShellContext context = new ReceivingShellContext();
        context.pathType = PATH_WORK_ORDER;
        context.workOrderId = workOrder.Id;
        context.workOrderNumber = workOrder.WorkOrderNumber;
        context.workOrderRecordTypeDeveloperName = workOrder.RecordType == null
            ? null
            : workOrder.RecordType.DeveloperName;
        context.isVendorWorkOrder = context.workOrderRecordTypeDeveloperName == WO_RT_VENDOR;
        context.headerTitle = buildWorkOrderHeaderTitle(workOrder);
        context.shipComplete = workOrder.ShipComplete__c == true;
        context.accountId = workOrder.AccountId;
        context.accountName = workOrder.Account == null ? null : workOrder.Account.Name;
        context.salesRepName = workOrder.AssignedSalesPerson__r == null
            ? null
            : workOrder.AssignedSalesPerson__r.Name;
        context.operatingUnit = workOrder.OperatingUnit__c;
        context.legacyCustomerId = workOrder.Account == null
            ? null
            : workOrder.Account.SystemID__c;
        context.receiverName = UserInfo.getName();
        context.isCio =
            workOrder.CaseId != null &&
            workOrder.Case != null &&
            workOrder.Case.Category__c == CIO_CATEGORY;
        context.isCreditHold =
            workOrder.Account != null &&
            workOrder.Account.CreditStatusCode__c == CREDIT_HOLD;
        List<WorkOrderLineItem> lineItems = queryProductServicedLinesForReceiving(workOrder.Id);
        Decimal accessoryQuantity = sumAccessoryQuantityForWorkOrder(workOrder.Id);
        context.items = toWorkOrderShellItems(workOrder, lineItems, accessoryQuantity);
        return context;
    }

    private static String buildWorkOrderHeaderTitle(WorkOrder workOrder) {
        String recordTypeDeveloperName = workOrder.RecordType == null
            ? null
            : workOrder.RecordType.DeveloperName;
        String label = recordTypeDeveloperName == WO_RT_VENDOR
            ? HEADER_VENDOR_WORK_ORDER
            : HEADER_WORK_ORDER;
        if (String.isBlank(workOrder.WorkOrderNumber)) {
            return label;
        }
        return label + ' ' + workOrder.WorkOrderNumber;
    }

    private static List<WorkOrderLineItem> queryProductServicedLinesForReceiving(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WorkOrderLineItem>();
        }
        return (List<WorkOrderLineItem>) new WorkOrderLineItemsSelector()
            .selectFields(WORK_ORDER_LINE_RECEIVING_FIELDS)
            .whereEquals('WorkOrderId', workOrderId)
            .whereEquals('LineType__c', LINE_TYPE_PRODUCT_SERVICED)
            .whereEquals('IsAccessory__c', false)
            .orderBy('LineItemNumber')
            .execute();
    }

    private static List<ReceivingShellItem> toWorkOrderShellItems(
        WorkOrder workOrder,
        List<WorkOrderLineItem> lineItems,
        Decimal accessoryQuantity
    ) {
        List<ReceivingShellItem> rows = new List<ReceivingShellItem>();
        if (lineItems == null) {
            lineItems = new List<WorkOrderLineItem>();
        }
        // GW-5968 - One verification row for the Work Order quantity, with or without
        // lines. An Asset means each instrument is verified on its own.
        if (isInstrumentWorkOrder(workOrder) && !hasPopulatedInstrumentAsset(workOrder, lineItems)) {
            Id lineItemId = lineItems.isEmpty() ? null : lineItems[0].Id;
            ReceivingShellItem item = buildWorkOrderInstrumentQuantityItem(
                workOrder,
                lineItemId,
                workOrder.QuantityReceived__c,
                accessoryQuantity,
                isInstrumentRepairWarranty(workOrder, lineItems)
            );
            if (!lineItems.isEmpty()) {
                applyWorkOrderLineAssetAndProduct(item, lineItems[0]);
            }
            rows.add(item);
            return rows;
        }
        if (lineItems.isEmpty()) {
            return rows;
        }
        String woRecordType = workOrder.RecordType == null
            ? null
            : workOrder.RecordType.DeveloperName;
        Boolean isVendor = woRecordType == WO_RT_VENDOR;
        Boolean woRepairWarranty = workOrder.RepairWarranty__c == WARRANTY_YES;

        Integer itemNumber = 1;
        for (WorkOrderLineItem lineItem : lineItems) {
            rows.add(
                buildWorkOrderShellItem(
                    workOrder,
                    lineItem,
                    itemNumber,
                    isVendor,
                    accessoryQuantity,
                    woRepairWarranty
                )
            );
            itemNumber++;
        }
        return rows;
    }

    private static Boolean isInstrumentWorkOrder(WorkOrder workOrder) {
        return workOrder != null &&
            workOrder.RecordType != null &&
            workOrder.RecordType.DeveloperName == WO_RT_INSTRUMENTS;
    }

    /**
     * @description GW-5968 - Instrument WOs verify one quantity, not one row per line.
     *              A null line is a parent or a child that has not started evaluation yet.
     */
    private static ReceivingShellItem buildWorkOrderInstrumentQuantityItem(
        WorkOrder workOrder,
        Id lineItemId,
        Decimal quantity,
        Decimal accessoryQuantity,
        Boolean isRepairWarranty
    ) {
        ReceivingShellItem item = new ReceivingShellItem();
        item.itemNumber = 1;
        if (lineItemId == null) {
            item.itemKey = 'instrument-wo-' + String.valueOf(workOrder.Id);
        } else {
            item.itemKey = String.valueOf(lineItemId);
        }
        item.lineItemId = lineItemId;
        item.displayTitle = 'INSTRUMENT';
        item.headerTitle = 'Item 1: INSTRUMENT';
        // WO Instruments use quantity-only verify, not the RO instrument Mod Form UI.
        item.isInstrumentItem = false;
        item.showSerialVerify = false;
        item.showModelVerify = false;
        item.showQuantityVerify = true;
        item.showDisinfectedVerify = false;
        item.showOutsideVendor = false;
        item.isVendorRequired = false;
        item.vendorVerifiedDefault = false;
        item.quantityReturned = quantity;
        item.isPriorityRepair = workOrder.IsPriorityRepair__c == true;
        item.badges = buildWorkOrderItemBadges(
            item.itemKey,
            item.isPriorityRepair,
            isRepairWarranty == true,
            accessoryQuantity
        );
        return item;
    }

    private static Boolean hasPopulatedInstrumentAsset(
        WorkOrder workOrder,
        List<WorkOrderLineItem> lineItems
    ) {
        if (workOrder != null && workOrder.AssetId != null) {
            return true;
        }
        if (lineItems == null) {
            return false;
        }
        for (WorkOrderLineItem lineItem : lineItems) {
            if (lineItem.AssetId != null) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isInstrumentRepairWarranty(
        WorkOrder workOrder,
        List<WorkOrderLineItem> lineItems
    ) {
        if (workOrder != null && workOrder.RepairWarranty__c == WARRANTY_YES) {
            return true;
        }
        if (lineItems == null) {
            return false;
        }
        for (WorkOrderLineItem lineItem : lineItems) {
            if (lineItem.RepairWarranty__c == WARRANTY_YES) {
                return true;
            }
        }
        return false;
    }

    private static ReceivingShellItem buildWorkOrderShellItem(
        WorkOrder workOrder,
        WorkOrderLineItem lineItem,
        Integer itemNumber,
        Boolean isVendor,
        Decimal accessoryQuantity,
        Boolean woRepairWarranty
    ) {
        ReceivingShellItem item = new ReceivingShellItem();
        item.itemNumber = itemNumber;
        item.itemKey = String.valueOf(lineItem.Id);
        item.lineItemId = lineItem.Id;
        applyWorkOrderLineAssetAndProduct(item, lineItem);
        item.quantityReturned = lineItem.Quantity;
        item.serialNumber = lineItem.SerialNumber__c;
        item.model = firstNonBlank(lineItem.Model__c, lineItem.Product2?.Model__c);
        item.productCode = lineItem.Product2 == null ? null : lineItem.Product2.ProductCode;
        item.displayTitle = buildWorkOrderLineDisplayTitle(workOrder, lineItem, isVendor);
        item.headerTitle = isVendor
            ? item.displayTitle
            : 'Item ' + String.valueOf(itemNumber) + ': ' + item.displayTitle;
        item.isInstrumentItem = false;
        item.showOutsideVendor = false;
        item.isVendorRequired = false;
        item.showDisinfectedVerify = false;
        item.vendorVerifiedDefault = isVendor;
        item.isPriorityRepair = workOrder.IsPriorityRepair__c == true;
        // Vendor WO UI has no badge row (verify + toggle only).
        item.badges = isVendor
            ? new List<ReceivingBadge>()
            : buildWorkOrderItemBadges(
                  item.itemKey,
                  item.isPriorityRepair,
                  woRepairWarranty == true || lineItem.RepairWarranty__c == WARRANTY_YES,
                  accessoryQuantity
              );

        if (isVendor) {
            item.showSerialVerify = false;
            item.showModelVerify = false;
            item.showQuantityVerify = false;
        } else {
            Boolean isGenericModel = isGenericOrAnyModel(item.model);
            item.showQuantityVerify = false;
            item.showSerialVerify = true;
            item.showModelVerify = !isGenericModel;
            item.serialVerifyLabel = 'SN #' + blankToEmpty(item.serialNumber) + '?';
            item.modelVerifyLabel = 'MD #' + blankToEmpty(item.model) + '?';
        }
        return item;
    }

    /**
     * @description GW-5968 - Copies Asset and Product Ids from a WOLI onto the shell item.
     *              Product falls back to the Asset's Product when the WOLI has none.
     */
    private static void applyWorkOrderLineAssetAndProduct(
        ReceivingShellItem item,
        WorkOrderLineItem lineItem
    ) {
        item.assetId = lineItem.AssetId;
        Id resolvedProduct2Id = lineItem.Product2Id;
        if (resolvedProduct2Id == null && lineItem.Asset != null) {
            resolvedProduct2Id = lineItem.Asset.Product2Id;
        }
        item.product2Id = resolvedProduct2Id;
    }

    private static String buildWorkOrderLineDisplayTitle(
        WorkOrder workOrder,
        WorkOrderLineItem lineItem,
        Boolean isVendor
    ) {
        String productLine = upperOrEmpty(lineItem.Product2?.ProductLine__c);
        String subProductLine = upperOrEmpty(lineItem.Product2?.SubProductLine__c);
        String deviceType = upperOrEmpty(lineItem.Product2?.DeviceType__c);
        String serialNumber = blankToEmpty(lineItem.SerialNumber__c);
        String model = firstNonBlank(lineItem.Model__c, lineItem.Product2?.Model__c);
        Boolean isGenericModel = isGenericOrAnyModel(model);

        if (isVendor) {
            String hierarchy = joinNonBlank(new List<String>{ productLine, subProductLine, deviceType }, '.');
            if (String.isNotBlank(serialNumber) && !isGenericModel) {
                return hierarchy +
                    ' - Serial # ' +
                    serialNumber +
                    ' | Model # ' +
                    blankToEmpty(model);
            }
            if (String.isNotBlank(serialNumber) && isGenericModel) {
                return hierarchy + ' - Serial # ' + serialNumber;
            }
            String productCode = upperOrEmpty(lineItem.Product2?.ProductCode);
            String quantityText = lineItem.Quantity == null
                ? '0'
                : String.valueOf(lineItem.Quantity.intValue());
            return productCode + ' - ' + hierarchy + ' - Quantity ' + quantityText;
        }

        if (isGenericModel) {
            return productLine +
                ' - ' +
                deviceType +
                ' | Serial # ' +
                serialNumber;
        }
        return productLine +
            ' - Serial # ' +
            serialNumber +
            ' | Model # ' +
            blankToEmpty(model);
    }

    /**
     * @description GW-5968 - WO item badges: Priority Repair, Accessories(n), Repair Warranty.
     *              Contaminated and Customer Care reason codes are session overlays in the LWC.
     */
    private static List<ReceivingBadge> buildWorkOrderItemBadges(
        String itemKey,
        Boolean isPriorityRepair,
        Boolean isRepairWarranty,
        Decimal accessoryQuantity
    ) {
        BadgeAggregate aggregate = new BadgeAggregate();
        aggregate.isPriorityRepair = isPriorityRepair == true;
        aggregate.isRepairWarranty = isRepairWarranty == true;
        aggregate.accessoryQuantity = accessoryQuantity;
        return buildBadges(itemKey, aggregate);
    }

    private static Decimal sumAccessoryQuantityForWorkOrder(Id workOrderId) {
        if (workOrderId == null) {
            return 0;
        }
        List<WorkOrderLineItem> accessories = (List<WorkOrderLineItem>) new WorkOrderLineItemsSelector()
            .selectFields(new List<String>{ 'Id', 'Quantity' })
            .whereEquals('WorkOrderId', workOrderId)
            .whereEquals('IsAccessory__c', true)
            .execute();
        Decimal total = 0;
        if (accessories != null) {
            for (WorkOrderLineItem accessory : accessories) {
                if (accessory.Quantity != null) {
                    total += accessory.Quantity;
                }
            }
        }
        return total;
    }

    private static String upperOrEmpty(String value) {
        return String.isBlank(value) ? '' : value.toUpperCase();
    }

    private static String joinNonBlank(List<String> parts, String separator) {
        List<String> cleaned = new List<String>();
        if (parts != null) {
            for (String part : parts) {
                if (String.isNotBlank(part)) {
                    cleaned.add(part);
                }
            }
        }
        return String.join(cleaned, separator);
    }

    /**
     * @description GW-5968 - Saves Quantity Received from Scan Work Order verification.
     * @param workOrderId Work Order Id
     * @param quantityReceived Quantity entered on the verification screen
     */
    public static void saveWorkOrderQuantityReceived(Id workOrderId, Decimal quantityReceived) {
        if (workOrderId == null) {
            throw new ReceivingServiceException('Work Order is required.');
        }
        if (quantityReceived == null || quantityReceived < 0) {
            throw new ReceivingServiceException('Quantity Received is required.');
        }
        try {
            WorkOrder workOrder = requireWorkOrderForReceiving(workOrderId);
            if (workOrder.QuantityReceived__c == quantityReceived) {
                return;
            }
            WorkOrdersService.updateWorkOrders(new List<WorkOrder>{
                new WorkOrder(Id = workOrderId, QuantityReceived__c = quantityReceived)
            });
        } catch (ReceivingServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('ReceivingService.saveWorkOrderQuantityReceived: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to save Quantity Received: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5968 - Vendor WO Submit: set WO Status, receive the vendor return
     *              order's inbound lines, and set a parent Work Order to Received /
     *              Receive from Vendor. The vendor return order is Received once every
     *              inbound line on it is received.
     * @param workOrderId Vendor Work Order Id
     */
    public static void submitVendorWorkOrderReceiving(Id workOrderId) {
        if (workOrderId == null) {
            throw new ReceivingServiceException('Work Order is required.');
        }
        try {
            WorkOrder workOrder = requireWorkOrderForReceiving(workOrderId);
            if (workOrder.RecordType == null || workOrder.RecordType.DeveloperName != WO_RT_VENDOR) {
                throw new ReceivingServiceException(
                    'Submit is only available for Vendor Work Orders.'
                );
            }

            List<WorkOrderLineItem> lineItems = queryProductServicedLinesForReceiving(workOrder.Id);
            List<ReturnOrderLineItem> linesToUpdate = buildVendorInboundReceiveUpdates(
                workOrder,
                lineItems
            );

            workOrder.Status = WO_STATUS_RECEIVE_FROM_VENDOR;
            List<WorkOrder> workOrdersToUpdate = new List<WorkOrder>{ workOrder };
            WorkOrder parentWorkOrderUpdate = buildParentWorkOrderUpdateForVendorSubmit(workOrder);
            if (parentWorkOrderUpdate != null) {
                workOrdersToUpdate.add(parentWorkOrderUpdate);
            }
            WorkOrdersService.updateWorkOrders(workOrdersToUpdate);
            if (!linesToUpdate.isEmpty()) {
                ReturnOrderLineItemsService.updateReturnOrderLineItems(linesToUpdate);
            }
            markVendorReturnOrderReceivedWhenInboundComplete(workOrder.VendorReturnOrder__c);
        } catch (ReceivingServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                'ReceivingService.submitVendorWorkOrderReceiving: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to submit Vendor Work Order receiving: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5968 - Outbound vendor lines stored on the Work Order line items.
     * @param workOrderLineItemIds Product Serviced line Ids for the vendor Work Order
     * @return Vendor return order line Ids
     */
    private static Set<Id> selectVendorOutboundLineIds(Set<Id> workOrderLineItemIds) {
        Set<Id> outboundLineIds = new Set<Id>();
        if (workOrderLineItemIds == null || workOrderLineItemIds.isEmpty()) {
            return outboundLineIds;
        }
        List<WorkOrderLineItem> linkedLines = (List<WorkOrderLineItem>) new WorkOrderLineItemsSelector()
            .selectFields(new List<String>{ 'Id', 'VendorReturnOrderLineItem__c' })
            .whereIn('Id', new List<Id>(workOrderLineItemIds))
            .execute();
        for (WorkOrderLineItem lineItem : linkedLines) {
            if (lineItem.VendorReturnOrderLineItem__c != null) {
                outboundLineIds.add(lineItem.VendorReturnOrderLineItem__c);
            }
        }
        return outboundLineIds;
    }

    /**
     * @description GW-5968 - Inbound vendor lines for this Work Order. Lines are matched
     *              by Work Order Line Item, or by the outbound line stored on
     *              VendorReturnOrderLineItem__c (ParentROLI__c on the inbound line).
     * @param workOrder Vendor Work Order
     * @param lineItems Product Serviced lines on the vendor Work Order
     * @return Inbound line updates with Status Received and Quantity Received
     */
    private static List<ReturnOrderLineItem> buildVendorInboundReceiveUpdates(
        WorkOrder workOrder,
        List<WorkOrderLineItem> lineItems
    ) {
        List<ReturnOrderLineItem> updates = new List<ReturnOrderLineItem>();
        if (workOrder == null || workOrder.VendorReturnOrder__c == null) {
            return updates;
        }
        Set<Id> workOrderLineItemIds = new Set<Id>();
        if (lineItems != null) {
            for (WorkOrderLineItem lineItem : lineItems) {
                workOrderLineItemIds.add(lineItem.Id);
            }
        }
        Set<Id> outboundLineIds = selectVendorOutboundLineIds(workOrderLineItemIds);
        if (workOrderLineItemIds.isEmpty() && outboundLineIds.isEmpty()) {
            return updates;
        }

        List<ReturnOrderLineItem> inboundLines = (List<ReturnOrderLineItem>) new ReturnOrderLineItemsSelector()
            .selectFields(new List<String>{
                'Id',
                'Status__c',
                'QuantityReturned',
                'QuantityReceived',
                'WorkOrderLineItem__c',
                'ParentROLI__c'
            })
            .whereEquals('ReturnOrderId', workOrder.VendorReturnOrder__c)
            .whereEquals('LineType__c', LINE_TYPE_INBOUND)
            .execute();
        for (ReturnOrderLineItem lineItem : inboundLines) {
            Boolean linkedToWorkOrderLine = lineItem.WorkOrderLineItem__c != null
                && workOrderLineItemIds.contains(lineItem.WorkOrderLineItem__c);
            Boolean linkedToOutbound = lineItem.ParentROLI__c != null
                && outboundLineIds.contains(lineItem.ParentROLI__c);
            if (!linkedToWorkOrderLine && !linkedToOutbound) {
                continue;
            }
            if (
                lineItem.Status__c == STATUS_LINE_RECEIVED &&
                lineItem.QuantityReceived == lineItem.QuantityReturned
            ) {
                continue;
            }
            updates.add(
                new ReturnOrderLineItem(
                    Id = lineItem.Id,
                    Status__c = STATUS_LINE_RECEIVED,
                    QuantityReceived = lineItem.QuantityReturned
                )
            );
        }
        return updates;
    }

    /**
     * @description GW-5968 - Sets the vendor Return Order to Received when it has inbound
     *              lines and none of them are still Created.
     * @param vendorReturnOrderId Vendor Return Order Id
     */
    private static void markVendorReturnOrderReceivedWhenInboundComplete(Id vendorReturnOrderId) {
        if (vendorReturnOrderId == null) {
            return;
        }
        List<ReturnOrderLineItem> inboundLines = (List<ReturnOrderLineItem>) new ReturnOrderLineItemsSelector()
            .selectFields(new List<String>{ 'Id', 'Status__c' })
            .whereEquals('ReturnOrderId', vendorReturnOrderId)
            .whereEquals('LineType__c', LINE_TYPE_INBOUND)
            .execute();
        if (inboundLines.isEmpty()) {
            return;
        }
        for (ReturnOrderLineItem lineItem : inboundLines) {
            if (lineItem.Status__c == STATUS_LINE_CREATED) {
                return;
            }
        }
        ReturnOrdersService.updateReturnOrders(
            new List<ReturnOrder>{
                new ReturnOrder(Id = vendorReturnOrderId, Status = STATUS_RECEIVED)
            }
        );
    }

    /**
     * @description GW-5968 - A Vendor Work Order parent is Received / Receive from Vendor.
     * @param vendorWorkOrder Vendor Work Order already loaded for receiving
     * @return Parent Work Order update row, or null when the vendor work order has no parent
     */
    private static WorkOrder buildParentWorkOrderUpdateForVendorSubmit(WorkOrder vendorWorkOrder) {
        if (vendorWorkOrder == null || vendorWorkOrder.ParentWorkOrderId == null) {
            return null;
        }
        return new WorkOrder(
            Id = vendorWorkOrder.ParentWorkOrderId,
            Status = STATUS_RECEIVED,
            SubStatus__c = WO_STATUS_RECEIVE_FROM_VENDOR
        );
    }

    private static List<ReceivingShellItem> toShellItems(
        String returnOrderType,
        List<ReturnOrderLineItem> lineItems,
        Boolean returnOrderRepairWarranty,
        BadgeRelatedData relatedData
    ) {
        List<ReceivingShellItem> rows = new List<ReceivingShellItem>();
        if (lineItems == null || lineItems.isEmpty()) {
            return rows;
        }

        // GW-5492: Instruments are one Item for the entire return (not per ROLI).
        if (returnOrderType == TYPE_INSTRUMENTS) {
            rows.add(
                buildInstrumentItem(lineItems, returnOrderRepairWarranty, relatedData)
            );
            return rows;
        }

        Integer itemNumber = 1;
        for (ReturnOrderLineItem lineItem : lineItems) {
            rows.add(
                buildSerializedStyleItem(
                    returnOrderType,
                    lineItem,
                    itemNumber,
                    returnOrderRepairWarranty,
                    relatedData
                )
            );
            itemNumber++;
        }
        return rows;
    }

    private static ReceivingShellItem buildInstrumentItem(
        List<ReturnOrderLineItem> lineItems,
        Boolean returnOrderRepairWarranty,
        BadgeRelatedData relatedData
    ) {
        ReceivingShellItem item = new ReceivingShellItem();
        item.itemNumber = 1;
        item.itemKey = 'instrument-' + String.valueOf(lineItems[0].Id);
        item.lineItemId = lineItems[0].Id;
        item.displayTitle = 'INSTRUMENT';
        item.headerTitle = 'Item 1: INSTRUMENT';
        item.isInstrumentItem = true;
        item.showOutsideVendor = false;
        item.isVendorRequired = false;
        item.showSerialVerify = false;
        item.showModelVerify = false;
        item.showQuantityVerify = true;
        Decimal totalQuantity = 0;
        Boolean anyPriority = false;
        Boolean anyExchange = false;
        String disinfectedValue;
        for (ReturnOrderLineItem lineItem : lineItems) {
            if (lineItem.QuantityReturned != null) {
                totalQuantity += lineItem.QuantityReturned;
            }
            anyPriority = anyPriority || lineItem.IsPriorityRepair__c == true;
            anyExchange = anyExchange || lineItem.IsRepairExchange__c == true;
            if (String.isBlank(disinfectedValue) && String.isNotBlank(lineItem.Disinfected__c)) {
                disinfectedValue = lineItem.Disinfected__c;
            }
        }
        item.quantityReturned = totalQuantity;
        item.isPriorityRepair = anyPriority;
        item.isRepairExchange = anyExchange;
        item.disinfectedUiValue = toDisinfectedUiValue(disinfectedValue);
        item.badges = buildBadges(
            item.itemKey,
            aggregateBadges(lineItems, returnOrderRepairWarranty, relatedData)
        );
        return item;
    }

    private static ReceivingShellItem buildSerializedStyleItem(
        String returnOrderType,
        ReturnOrderLineItem lineItem,
        Integer itemNumber,
        Boolean returnOrderRepairWarranty,
        BadgeRelatedData relatedData
    ) {
        ReceivingShellItem item = new ReceivingShellItem();
        item.itemNumber = itemNumber;
        item.itemKey = String.valueOf(lineItem.Id);
        item.lineItemId = lineItem.Id;
        item.quantityReturned = lineItem.QuantityReturned;
        item.serialNumber = lineItem.SerialNumber__c;
        item.model = firstNonBlank(lineItem.Model__c, lineItem.Product2?.Model__c);
        item.productCode = lineItem.Product2 == null ? null : lineItem.Product2.ProductCode;
        item.displayTitle = buildLineItemDisplayTitle(returnOrderType, lineItem);
        item.headerTitle = 'Item ' + String.valueOf(itemNumber) + ': ' + item.displayTitle;
        Boolean isGenericModel = isGenericOrAnyModel(item.model);
        Boolean isOtherNonSerialized = returnOrderType == TYPE_OTHER_NON_SERIALIZED;
        item.isInstrumentItem = false;
        // GW-5492 / Josh: Other (Non-Serialized) always shows Outside Vendor (required).
        // Other (Serialized) shows Outside Vendor; required only when CMDT rule matches.
        item.showOutsideVendor =
            returnOrderType == TYPE_OTHER_SERIALIZED || isOtherNonSerialized;
        item.isVendorRequired =
            isOtherNonSerialized ||
            (returnOrderType == TYPE_OTHER_SERIALIZED && isVendorRequiredForProduct(lineItem));
        // Non-Serialized: quantity + Disinfected (no SN/MD). Serialized styles: SN (+ MD).
        item.showQuantityVerify = isOtherNonSerialized;
        item.showSerialVerify = !isOtherNonSerialized;
        // Scenario 2 (ANY/GENERIC): no MD verification; Scenario 1: SN + MD.
        item.showModelVerify = !isOtherNonSerialized && !isGenericModel;
        item.serialVerifyLabel = 'SN #' + blankToEmpty(item.serialNumber) + '?';
        item.modelVerifyLabel = 'MD #' + blankToEmpty(item.model) + '?';
        item.isPriorityRepair = lineItem.IsPriorityRepair__c == true;
        item.isRepairExchange = lineItem.IsRepairExchange__c == true;
        item.disinfectedUiValue = toDisinfectedUiValue(lineItem.Disinfected__c);
        item.badges = buildBadges(
            item.itemKey,
            aggregateBadges(
                new List<ReturnOrderLineItem>{ lineItem },
                returnOrderRepairWarranty,
                relatedData
            )
        );
        return item;
    }

    private static Boolean isGenericOrAnyModel(String model) {
        return String.isNotBlank(model) &&
            (model.equalsIgnoreCase(MODEL_ANY) || model.equalsIgnoreCase(MODEL_GENERIC));
    }

    /**
     * @description GW-5492 - True when product attributes match an active VendorRequiredProductRule__mdt.
     */
    @TestVisible
    private static Boolean isVendorRequiredForProduct(ReturnOrderLineItem lineItem) {
        String productLine = firstNonBlank(
            lineItem.ProductLine__c,
            lineItem.Product2?.ProductLine__c
        );
        String subProductLine = lineItem.Product2 == null
            ? null
            : lineItem.Product2.SubProductLine__c;
        String deviceType = lineItem.Product2 == null ? null : lineItem.Product2.DeviceType__c;
        return isVendorRequiredForAttributes(productLine, subProductLine, deviceType);
    }

    @TestVisible
    private static Boolean isVendorRequiredForAttributes(
        String productLine,
        String subProductLine,
        String deviceType
    ) {
        if (String.isBlank(productLine) || String.isBlank(subProductLine)) {
            return false;
        }
        for (VendorRequiredProductRule__mdt rule : getVendorRequiredRules()) {
            if (
                equalsIgnoreCaseTrimmed(rule.ProductLine__c, productLine) &&
                equalsIgnoreCaseTrimmed(rule.SubProductLine__c, subProductLine) &&
                (String.isBlank(rule.DeviceType__c) ||
                    equalsIgnoreCaseTrimmed(rule.DeviceType__c, deviceType))
            ) {
                return true;
            }
        }
        return false;
    }

    private static List<VendorRequiredProductRule__mdt> getVendorRequiredRules() {
        if (vendorRequiredRulesOverride != null) {
            return vendorRequiredRulesOverride;
        }
        return (List<VendorRequiredProductRule__mdt>) new VendorRequiredProductRulesSelector()
            .selectFields(
                new List<String>{
                    'ProductLine__c',
                    'SubProductLine__c',
                    'DeviceType__c',
                    'IsActive__c'
                }
            )
            .whereEquals('IsActive__c', true)
            .execute();
    }

    private static Boolean equalsIgnoreCaseTrimmed(String leftValue, String rightValue) {
        if (String.isBlank(leftValue) || String.isBlank(rightValue)) {
            return false;
        }
        return leftValue.trim().equalsIgnoreCase(rightValue.trim());
    }

    private static String toDisinfectedUiValue(String disinfectedApiValue) {
        if (disinfectedApiValue == DISINFECTED_YES) {
            return UI_CLEAN;
        }
        if (disinfectedApiValue == DISINFECTED_NO) {
            return UI_CONTAMINATED;
        }
        return null;
    }

    private static BadgeRelatedData loadBadgeRelatedData(List<ReturnOrderLineItem> lineItems) {
        BadgeRelatedData relatedData = new BadgeRelatedData();
        if (lineItems == null || lineItems.isEmpty()) {
            return relatedData;
        }
        Set<Id> lineItemIds = new Set<Id>();
        for (ReturnOrderLineItem lineItem : lineItems) {
            if (lineItem.Id != null) {
                lineItemIds.add(lineItem.Id);
            }
        }
        if (lineItemIds.isEmpty()) {
            return relatedData;
        }

        List<Id> lineItemIdList = new List<Id>(lineItemIds);
        // ReceivingService already uses WorkOrdersSelector for scan resolve; same pattern for badges.
        List<WorkOrder> workOrders = (List<WorkOrder>) new WorkOrdersSelector()
            .selectFields(
                new List<String>{ 'Id', 'ReturnOrderLineItemId', 'ReasonCode__c' }
            )
            .whereIn('ReturnOrderLineItemId', lineItemIdList)
            .execute();
        for (WorkOrder workOrder : workOrders) {
            if (workOrder.ReturnOrderLineItemId == null) {
                continue;
            }
            relatedData.hasWorkOrderByLineItemId.put(workOrder.ReturnOrderLineItemId, true);
            if (String.isBlank(workOrder.ReasonCode__c)) {
                continue;
            }
            List<String> codes = relatedData.reasonCodesByLineItemId.get(
                workOrder.ReturnOrderLineItemId
            );
            if (codes == null) {
                codes = new List<String>();
                relatedData.reasonCodesByLineItemId.put(
                    workOrder.ReturnOrderLineItemId,
                    codes
                );
            }
            for (String code : workOrder.ReasonCode__c.split(';')) {
                String trimmed = code == null ? null : code.trim();
                if (String.isNotBlank(trimmed) && !codes.contains(trimmed)) {
                    codes.add(trimmed);
                }
            }
        }

        List<WorkOrderLineItem> accessoryLines = (List<WorkOrderLineItem>) new WorkOrderLineItemsSelector()
            .selectFields(
                new List<String>{ 'Id', 'ReturnOrderLineItemId', 'Quantity', 'IsAccessory__c' }
            )
            .whereIn('ReturnOrderLineItemId', lineItemIdList)
            .whereEquals('IsAccessory__c', true)
            .execute();
        for (WorkOrderLineItem accessoryLine : accessoryLines) {
            if (accessoryLine.ReturnOrderLineItemId == null) {
                continue;
            }
            Decimal quantity = accessoryLine.Quantity != null && accessoryLine.Quantity > 0
                ? accessoryLine.Quantity
                : 1;
            Decimal current = relatedData.accessoryQuantityByLineItemId.get(
                accessoryLine.ReturnOrderLineItemId
            );
            relatedData.accessoryQuantityByLineItemId.put(
                accessoryLine.ReturnOrderLineItemId,
                (current == null ? 0 : current) + quantity
            );
        }
        return relatedData;
    }

    private static BadgeAggregate aggregateBadges(
        List<ReturnOrderLineItem> lineItems,
        Boolean returnOrderRepairWarranty,
        BadgeRelatedData relatedData
    ) {
        BadgeAggregate aggregate = new BadgeAggregate();
        aggregate.isPriorityRepair = false;
        aggregate.isRepairExchange = false;
        aggregate.isContaminated = false;
        aggregate.isRedirected = false;
        aggregate.hasWorkOrder = false;
        aggregate.isRepairWarranty = returnOrderRepairWarranty == true;
        aggregate.accessoryQuantity = 0;
        Set<String> reasonCodes = new Set<String>();

        if (lineItems == null) {
            return aggregate;
        }
        for (ReturnOrderLineItem lineItem : lineItems) {
            aggregate.isPriorityRepair =
                aggregate.isPriorityRepair || lineItem.IsPriorityRepair__c == true;
            aggregate.isRepairExchange =
                aggregate.isRepairExchange || lineItem.IsRepairExchange__c == true;
            aggregate.isContaminated =
                aggregate.isContaminated ||
                toDisinfectedUiValue(lineItem.Disinfected__c) == UI_CONTAMINATED;
            aggregate.isRedirected =
                aggregate.isRedirected || lineItem.Status__c == STATUS_LINE_REDIRECTED;
            aggregate.isRepairWarranty =
                aggregate.isRepairWarranty || lineItem.RepairWarranty__c == WARRANTY_YES;

            if (
                relatedData != null &&
                relatedData.hasWorkOrderByLineItemId.containsKey(lineItem.Id)
            ) {
                aggregate.hasWorkOrder = true;
            }
            if (
                relatedData != null &&
                relatedData.accessoryQuantityByLineItemId.containsKey(lineItem.Id)
            ) {
                aggregate.accessoryQuantity += relatedData.accessoryQuantityByLineItemId.get(
                    lineItem.Id
                );
            }
            if (
                relatedData != null &&
                relatedData.reasonCodesByLineItemId.containsKey(lineItem.Id)
            ) {
                reasonCodes.addAll(relatedData.reasonCodesByLineItemId.get(lineItem.Id));
            }
        }
        aggregate.customerCareReasonCodes = new List<String>(reasonCodes);
        aggregate.customerCareReasonCodes.sort();
        return aggregate;
    }

    @TestVisible
    private static List<ReceivingBadge> buildBadges(String itemKey, BadgeAggregate aggregate) {
        List<ReceivingBadge> badges = new List<ReceivingBadge>();
        if (aggregate == null) {
            return badges;
        }
        String keyPrefix = String.isBlank(itemKey) ? 'item' : itemKey;

        if (aggregate.isPriorityRepair == true) {
            badges.add(
                newBadge(
                    keyPrefix + '-PriorityRepair',
                    'Priority Repair',
                    BADGE_VARIANT_INFO,
                    BADGE_ICON_INFO
                )
            );
        }
        if (aggregate.isRepairExchange == true) {
            badges.add(
                newBadge(
                    keyPrefix + '-RepairExchange',
                    'Repair Exchange',
                    BADGE_VARIANT_INFO,
                    BADGE_ICON_INFO
                )
            );
        }
        if (aggregate.isContaminated == true) {
            badges.add(
                newBadge(
                    keyPrefix + '-Contaminated',
                    'Contaminated',
                    BADGE_VARIANT_ALERT,
                    BADGE_ICON_ALERT
                )
            );
        }
        if (aggregate.isRedirected == true) {
            badges.add(
                newBadge(
                    keyPrefix + '-Redirect',
                    'Redirect',
                    BADGE_VARIANT_REDIRECT,
                    BADGE_ICON_REDIRECT
                )
            );
        }
        if (aggregate.accessoryQuantity != null && aggregate.accessoryQuantity > 0) {
            Integer qty = aggregate.accessoryQuantity.intValue();
            badges.add(
                newBadge(
                    keyPrefix + '-Accessories',
                    'Accessories (' + String.valueOf(qty) + ')',
                    BADGE_VARIANT_INFO,
                    BADGE_ICON_INFO
                )
            );
        }
        if (aggregate.hasWorkOrder == true) {
            badges.add(
                newBadge(
                    keyPrefix + '-WorkOrderCreated',
                    'Work Order Created',
                    BADGE_VARIANT_COMPLETE,
                    BADGE_ICON_COMPLETE
                )
            );
        }
        if (aggregate.isRepairWarranty == true) {
            badges.add(
                newBadge(
                    keyPrefix + '-RepairWarranty',
                    'Repair Warranty',
                    BADGE_VARIANT_INFO,
                    BADGE_ICON_INFO
                )
            );
        }
        if (aggregate.customerCareReasonCodes != null) {
            for (String reasonCode : aggregate.customerCareReasonCodes) {
                if (String.isBlank(reasonCode)) {
                    continue;
                }
                badges.add(
                    newBadge(
                        keyPrefix + '-Care-' + reasonCode,
                        reasonCode,
                        BADGE_VARIANT_WARNING,
                        BADGE_ICON_WARNING
                    )
                );
            }
        }
        return badges;
    }

    /**
     * @description Test seam to exercise badge assembly without WO/accessory DML.
     */
    @TestVisible
    private static List<ReceivingBadge> buildBadgesForTest(
        String itemKey,
        Boolean isPriorityRepair,
        Boolean isRepairExchange,
        Boolean isContaminated,
        Boolean isRedirected,
        Boolean hasWorkOrder,
        Boolean isRepairWarranty,
        Decimal accessoryQuantity,
        List<String> customerCareReasonCodes
    ) {
        BadgeAggregate aggregate = new BadgeAggregate();
        aggregate.isPriorityRepair = isPriorityRepair == true;
        aggregate.isRepairExchange = isRepairExchange == true;
        aggregate.isContaminated = isContaminated == true;
        aggregate.isRedirected = isRedirected == true;
        aggregate.hasWorkOrder = hasWorkOrder == true;
        aggregate.isRepairWarranty = isRepairWarranty == true;
        aggregate.accessoryQuantity = accessoryQuantity;
        aggregate.customerCareReasonCodes = customerCareReasonCodes == null
            ? new List<String>()
            : customerCareReasonCodes;
        return buildBadges(itemKey, aggregate);
    }

    private static ReceivingBadge newBadge(
        String key,
        String label,
        String variant,
        String iconName
    ) {
        ReceivingBadge badge = new ReceivingBadge();
        badge.key = key;
        badge.label = label;
        badge.variant = variant;
        badge.iconName = iconName;
        return badge;
    }

    private static String buildLineItemDisplayTitle(
        String returnOrderType,
        ReturnOrderLineItem lineItem
    ) {
        String productLine = firstNonBlank(
            lineItem.ProductLine__c,
            lineItem.Product2?.ProductLine__c
        );
        String model = firstNonBlank(lineItem.Model__c, lineItem.Product2?.Model__c);
        String serialNumber = lineItem.SerialNumber__c;
        String deviceType = lineItem.Product2 == null ? null : lineItem.Product2.DeviceType__c;
        String productCode = lineItem.Product2 == null ? null : lineItem.Product2.ProductCode;
        String subProductLine = lineItem.Product2 == null
            ? null
            : lineItem.Product2.SubProductLine__c;

        if (returnOrderType == TYPE_SERIALIZED || returnOrderType == TYPE_OTHER_SERIALIZED) {
            if (isGenericOrAnyModel(model)) {
                return upperOrBlank(productLine) +
                    ' - ' +
                    upperOrBlank(deviceType) +
                    ' | Serial # ' +
                    blankToEmpty(serialNumber);
            }
            return upperOrBlank(productLine) +
                ' - Serial # ' +
                blankToEmpty(serialNumber) +
                ' | Model # ' +
                blankToEmpty(model);
        }

        if (returnOrderType == TYPE_OTHER_NON_SERIALIZED) {
            return upperOrBlank(productCode) +
                ' - ' +
                upperOrBlank(productLine) +
                '.' +
                upperOrBlank(subProductLine) +
                '.' +
                upperOrBlank(deviceType);
        }

        return firstNonBlank(lineItem.Product2?.Name, lineItem.Id);
    }

    private static String firstNonBlank(String firstValue, String secondValue) {
        if (String.isNotBlank(firstValue)) {
            return firstValue;
        }
        return secondValue;
    }

    private static String upperOrBlank(String value) {
        return String.isBlank(value) ? '' : value.toUpperCase();
    }

    private static String blankToEmpty(String value) {
        return value == null ? '' : value;
    }

    /**
     * @description GW-5492 - Resolves Operating Unit picklist label (e.g. STERIS US) from code (e.g. 82).
     * @param returnOrder Return Order with OperatingUnit__c and optional Account.OrgIDs__c
     * @return Display label when known; otherwise the stored code; null when blank
     */
    private static String resolveOperatingUnitDisplay(ReturnOrder returnOrder) {
        String operatingUnitCode = returnOrder.OperatingUnit__c;
        if (String.isBlank(operatingUnitCode) && returnOrder.Account != null) {
            operatingUnitCode = firstOrgIdToken(returnOrder.Account.OrgIDs__c);
        }
        if (String.isBlank(operatingUnitCode)) {
            return null;
        }
        String label = operatingUnitLabelsByValue().get(operatingUnitCode);
        return String.isNotBlank(label) ? label : operatingUnitCode;
    }

    private static String firstOrgIdToken(String orgIds) {
        if (String.isBlank(orgIds)) {
            return null;
        }
        return orgIds.trim().split('[;,]')[0].trim();
    }

    private static Map<String, String> operatingUnitLabelsByValue() {
        Map<String, String> labelsByValue = new Map<String, String>();
        Schema.DescribeFieldResult fieldDescribe = ReturnOrder.OperatingUnit__c.getDescribe();
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            labelsByValue.put(entry.getValue(), entry.getLabel());
        }
        return labelsByValue;
    }

    private static Id tryParseId(String value) {
        if (String.isBlank(value) || (value.length() != 15 && value.length() != 18)) {
            return null;
        }
        try {
            return Id.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description GW-5492 - Mod Form photo attached to a Return Order during Receiving.
     */
    public class ModFormPhoto {
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public String thumbnailUrl;
        @AuraEnabled public String imageDownloadUrl;
    }

    /**
     * @description GW-5492 - Stages a Mod Form photo/file and links it to the Return Order.
     * @param returnOrderId Return Order Id
     * @param base64Data File payload (optionally data-URL prefixed)
     * @param fileName Optional file name
     * @return Mod Form photo DTO
     */
    public static ModFormPhoto stageModFormPhoto(
        Id returnOrderId,
        String base64Data,
        String fileName
    ) {
        if (returnOrderId == null) {
            throw new ReceivingServiceException('Return Order is required.');
        }
        if (String.isBlank(base64Data)) {
            throw new ReceivingServiceException('File data is required.');
        }

        try {
            requireReturnOrderForReceiving(returnOrderId);

            String resolvedFileName = String.isBlank(fileName)
                ? 'ModForm-' + Datetime.now().format('yyyyMMdd-HHmmss') + '.jpg'
                : fileName.trim();
            if (!resolvedFileName.toLowerCase().contains('.')) {
                resolvedFileName += '.jpg';
            }

            String payload = base64Data;
            Integer commaIndex = payload.indexOf(',');
            if (payload.startsWith('data:') && commaIndex > -1) {
                payload = payload.substring(commaIndex + 1);
            }

            ContentVersion version = new ContentVersion();
            version.Title = resolvedFileName.contains('.')
                ? resolvedFileName.substring(0, resolvedFileName.lastIndexOf('.'))
                : resolvedFileName;
            version.PathOnClient = resolvedFileName;
            version.VersionData = EncodingUtil.base64Decode(payload);
            version.Description = MOD_FORM_FILE_DESCRIPTION;
            version.FirstPublishLocationId = returnOrderId;

            List<ContentVersion> createdVersions = ContentVersionsService.createContentVersions(
                new List<ContentVersion>{ version }
            );
            if (createdVersions.isEmpty()) {
                throw new ReceivingServiceException('Unable to save Mod Form photo.');
            }

            ContentVersion inserted = createdVersions[0];
            // FirstPublishLocationId usually creates the link; ensure ContentDocumentId is present.
            if (inserted.ContentDocumentId == null) {
                List<ContentVersion> refreshed = ContentVersionsService.getContentVersionsById(
                    new Set<Id>{ inserted.Id }
                );
                if (!refreshed.isEmpty()) {
                    inserted = refreshed[0];
                }
            }
            if (inserted.ContentDocumentId == null) {
                throw new ReceivingServiceException('Unable to link Mod Form photo.');
            }

            return toModFormPhoto(inserted);
        } catch (ReceivingServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('ReceivingService.stageModFormPhoto: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to save Mod Form photo: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5492 - Removes a Mod Form photo from a Return Order when owned by the user.
     * @param returnOrderId Return Order Id
     * @param contentDocumentId ContentDocument Id
     */
    public static void deleteModFormPhoto(Id returnOrderId, Id contentDocumentId) {
        if (returnOrderId == null || contentDocumentId == null) {
            throw new ReceivingServiceException('Return Order and file are required.');
        }
        try {
            requireReturnOrderForReceiving(returnOrderId);
            List<ContentDocumentLink> links =
                ContentDocumentLinksService.getLinksByDocumentsAndLinkedEntities(
                    new Set<Id>{ contentDocumentId },
                    new Set<Id>{ returnOrderId }
                );
            if (links.isEmpty()) {
                throw new ReceivingServiceException(
                    'Mod Form photo was not found on this Return Order.'
                );
            }
            Set<Id> linkIdsToDelete = new Set<Id>();
            for (ContentDocumentLink link : links) {
                linkIdsToDelete.add(link.Id);
            }
            ContentDocumentLinksService.deleteContentDocumentLinks(linkIdsToDelete);
            ContentDocumentsService.deleteContentDocuments(new Set<Id>{ contentDocumentId });
        } catch (ReceivingServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('ReceivingService.deleteModFormPhoto: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to remove Mod Form photo: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5492 - Renames a Mod Form photo Title linked to the Return Order.
     * @param returnOrderId Return Order Id
     * @param contentDocumentId ContentDocument Id
     * @param newTitle New title
     * @return Updated Mod Form photo DTO
     */
    public static ModFormPhoto renameModFormPhoto(
        Id returnOrderId,
        Id contentDocumentId,
        String newTitle
    ) {
        if (returnOrderId == null || contentDocumentId == null) {
            throw new ReceivingServiceException('Return Order and file are required.');
        }
        if (String.isBlank(newTitle)) {
            throw new ReceivingServiceException('Photo title is required.');
        }
        try {
            requireReturnOrderForReceiving(returnOrderId);
            List<ContentDocumentLink> links =
                ContentDocumentLinksService.getLinksByDocumentsAndLinkedEntities(
                    new Set<Id>{ contentDocumentId },
                    new Set<Id>{ returnOrderId }
                );
            if (links.isEmpty()) {
                throw new ReceivingServiceException(
                    'Mod Form photo was not found on this Return Order.'
                );
            }
            ContentVersion refreshed = ContentVersionsService.renamePhotoForDeviceEvaluation(
                contentDocumentId,
                newTitle
            );
            return toModFormPhoto(refreshed);
        } catch (ReceivingServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('ReceivingService.renameModFormPhoto: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to rename Mod Form photo: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5968 - Links staged Take a Pic files to a scanned Work Order.
     *              Already linked files are skipped. Return Order receiving still
     *              attaches photos later, when Finish Receiving creates the Work Order.
     * @param workOrderId Work Order that was scanned
     * @param contentDocumentIds Staged photo ContentDocument Ids
     */
    public static void attachReceivingPhotos(Id workOrderId, List<Id> contentDocumentIds) {
        if (workOrderId == null) {
            throw new ReceivingServiceException('Work Order is required.');
        }
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return;
        }
        Set<Id> documentIds = new Set<Id>();
        for (Id contentDocumentId : contentDocumentIds) {
            if (contentDocumentId != null) {
                documentIds.add(contentDocumentId);
            }
        }
        if (documentIds.isEmpty()) {
            return;
        }
        try {
            for (
                ContentDocumentLink existingLink :
                    ContentDocumentLinksSelector.selectByLinkedEntityIdForReceiving(workOrderId)
            ) {
                documentIds.remove(existingLink.ContentDocumentId);
            }
            if (documentIds.isEmpty()) {
                return;
            }
            List<ContentDocumentLink> links = new List<ContentDocumentLink>();
            for (Id contentDocumentId : documentIds) {
                links.add(
                    new ContentDocumentLink(
                        ContentDocumentId = contentDocumentId,
                        LinkedEntityId = workOrderId,
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    )
                );
            }
            Database.insert(links, AccessLevel.USER_MODE);
        } catch (ReceivingServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('ReceivingService.attachReceivingPhotos: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException('Unable to attach photos: ' + e.getMessage(), e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5492 - Stages a Take a Pic file without linking it.
     *              Finish Receiving attaches the file based on the receive scenario.
     * @param base64Data File payload (optionally data-URL prefixed)
     * @param fileName Optional file name
     * @return Staged photo DTO
     */
    public static ModFormPhoto stageReceivingPhoto(String base64Data, String fileName) {
        if (String.isBlank(base64Data)) {
            throw new ReceivingServiceException('File data is required.');
        }

        try {
            String resolvedFileName = String.isBlank(fileName)
                ? 'Receive-' + Datetime.now().format('yyyyMMdd-HHmmss') + '.jpg'
                : fileName.trim();
            if (!resolvedFileName.toLowerCase().contains('.')) {
                resolvedFileName += '.jpg';
            }

            String payload = base64Data;
            Integer commaIndex = payload.indexOf(',');
            if (payload.startsWith('data:') && commaIndex > -1) {
                payload = payload.substring(commaIndex + 1);
            }

            ContentVersion version = new ContentVersion();
            version.Title = resolvedFileName.contains('.')
                ? resolvedFileName.substring(0, resolvedFileName.lastIndexOf('.'))
                : resolvedFileName;
            version.PathOnClient = resolvedFileName;
            version.VersionData = EncodingUtil.base64Decode(payload);

            List<ContentVersion> createdVersions = ContentVersionsService.createContentVersions(
                new List<ContentVersion>{ version }
            );
            if (createdVersions.isEmpty()) {
                throw new ReceivingServiceException('Unable to stage photo.');
            }

            ContentVersion inserted = createdVersions[0];
            if (inserted.ContentDocumentId == null) {
                List<ContentVersion> refreshed = ContentVersionsService.getContentVersionsById(
                    new Set<Id>{ inserted.Id }
                );
                if (!refreshed.isEmpty()) {
                    inserted = refreshed[0];
                }
            }
            if (inserted.ContentDocumentId == null) {
                throw new ReceivingServiceException('Unable to stage photo.');
            }
            return toModFormPhoto(inserted);
        } catch (ReceivingServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('ReceivingService.stageReceivingPhoto: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException('Unable to stage photo: ' + e.getMessage(), e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5492 - Deletes a Take a Pic file that is not yet linked to a record.
     * @param contentDocumentId ContentDocument Id
     */
    public static void deleteReceivingPhoto(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw new ReceivingServiceException('File is required.');
        }
        try {
            ContentDocumentsService.deleteStagedPhotoForDeviceEvaluation(contentDocumentId);
        } catch (ReceivingServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('ReceivingService.deleteReceivingPhoto: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to remove photo: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5492 - Renames a staged Take a Pic file owned by the current user.
     * @param contentDocumentId ContentDocument Id
     * @param newTitle New title
     * @return Updated photo DTO
     */
    public static ModFormPhoto renameReceivingPhoto(Id contentDocumentId, String newTitle) {
        if (contentDocumentId == null) {
            throw new ReceivingServiceException('File is required.');
        }
        if (String.isBlank(newTitle)) {
            throw new ReceivingServiceException('Photo title is required.');
        }
        try {
            ContentVersion refreshed = ContentVersionsService.renamePhotoForDeviceEvaluation(
                contentDocumentId,
                newTitle
            );
            return toModFormPhoto(refreshed);
        } catch (ReceivingServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('ReceivingService.renameReceivingPhoto: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to rename photo: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    private static final Integer OVERRIDE_SERIAL_CHARACTER_LIMIT = 2;

    /**
     * @description GW-5492 - Result of an Override serial correction.
     */
    public class OverrideSerialResult {
        @AuraEnabled public Boolean assetUpdated;
        @AuraEnabled public Boolean lineUpdated;
        @AuraEnabled public String serialNumber;
    }

    /**
     * @description Applies a serial override of 2 characters or fewer.
     *              Updates the Return Order line and, when one matching Asset exists,
     *              that Asset's serial number and name.
     * @param lineItemId Return Order Line Item Id
     * @param correctedSerial Corrected serial number
     * @return Whether the line and Asset were updated
     */
    public static OverrideSerialResult applySerialOverride(Id lineItemId, String correctedSerial) {
        if (lineItemId == null) {
            throw new ReceivingServiceException('Return Order Line Item is required.');
        }
        String corrected = correctedSerial == null ? '' : correctedSerial.trim().toUpperCase();
        OverrideSerialResult result = new OverrideSerialResult();
        result.assetUpdated = false;
        result.lineUpdated = false;
        try {
            ReturnOrderLineItem lineItem = queryOverrideLineItem(lineItemId);
            String listedRaw = lineItem.SerialNumber__c;
            String listed = listedRaw == null ? '' : listedRaw.trim().toUpperCase();
            result.serialNumber = listed;
            if (String.isBlank(corrected) || corrected == listed) {
                return result;
            }
            if (characterDistance(listed, corrected) > OVERRIDE_SERIAL_CHARACTER_LIMIT) {
                return result;
            }

            lineItem.SerialNumber__c = corrected;
            ReturnOrderLineItemsService.updateReturnOrderLineItems(
                new List<ReturnOrderLineItem>{ lineItem }
            );
            result.lineUpdated = true;
            result.serialNumber = corrected;

            Set<String> serialCandidates = new Set<String>();
            if (String.isNotBlank(listedRaw)) {
                serialCandidates.add(listedRaw.trim());
            }
            if (String.isNotBlank(listed)) {
                serialCandidates.add(listed);
            }
            List<Asset> matches = AssetsService.getAssetsBySerialAndProductElevated(
                serialCandidates,
                lineItem.Product2Id
            );
            if (matches.size() > 1) {
                throw new ReceivingServiceException(
                    'More than one Asset matches this serial number and product.'
                );
            }
            if (matches.size() == 1) {
                Asset asset = matches[0];
                String productCode = lineItem.Product2 == null
                    ? null
                    : lineItem.Product2.ProductCode;
                asset.SerialNumber = corrected;
                asset.Name = String.isBlank(productCode)
                    ? corrected
                    : productCode.trim() + ' - ' + corrected;
                AssetsService.updateAssetsElevated(new List<Asset>{ asset });
                result.assetUpdated = true;
            }
            return result;
        } catch (ReceivingServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('ReceivingService.applySerialOverride: Unexpected error.', e);
            throw new ReceivingServiceException(
                'Unable to save the serial number override: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    private static ReturnOrderLineItem queryOverrideLineItem(Id lineItemId) {
        List<ReturnOrderLineItem> lineItems = (List<ReturnOrderLineItem>)
            new ReturnOrderLineItemsSelector()
                .selectFields(
                    new List<String>{
                        'Id',
                        'SerialNumber__c',
                        'Product2Id',
                        'Product2.ProductCode'
                    }
                )
                .whereEquals('Id', lineItemId)
                .execute();
        if (lineItems.isEmpty()) {
            throw new ReceivingServiceException('Return Order Line Item was not found.');
        }
        return lineItems[0];
    }

    /**
     * @description GW-5968 - Applies a serial override of 2 characters or fewer on a Work Order
     *              Product Serviced line.
     * @param workOrderLineItemId Product Serviced Work Order Line Item Id
     * @param correctedSerial Corrected serial number
     * @return Whether the line and Asset were updated
     */
    public static OverrideSerialResult applyWorkOrderSerialOverride(
        Id workOrderLineItemId,
        String correctedSerial
    ) {
        return applyWorkOrderSerialOverride(workOrderLineItemId, correctedSerial, null, null, null);
    }

    /**
     * @description GW-5968 - Applies a serial override of 2 characters or fewer, and a corrected
     *              model, on a scanned Work Order. Serial and model are written to the Work Order
     *              and the Product Serviced line. A matching Asset still gets the corrected serial.
     * @param workOrderLineItemId Product Serviced Work Order Line Item Id
     * @param correctedSerial Corrected serial number
     * @param correctedModel Corrected model
     * @return Whether the line and Asset were updated
     */
    public static OverrideSerialResult applyWorkOrderSerialOverride(
        Id workOrderLineItemId,
        String correctedSerial,
        String correctedModel
    ) {
        return applyWorkOrderSerialOverride(
            workOrderLineItemId,
            correctedSerial,
            correctedModel,
            null,
            null
        );
    }

    /**
     * @description GW-5968 - Applies a Work Order override. A serial within 2 characters and a
     *              corrected model are written to the Work Order and the Product Serviced line.
     *              Customer Care reason codes set Sub Status to Customer Care and save the notes.
     * @param workOrderLineItemId Product Serviced Work Order Line Item Id
     * @param correctedSerial Corrected serial number
     * @param correctedModel Corrected model
     * @param customerCareReasonCodes Reason codes selected on the override
     * @param customerCareNotes Customer Care notes
     * @return Whether the line and Asset were updated
     */
    public static OverrideSerialResult applyWorkOrderSerialOverride(
        Id workOrderLineItemId,
        String correctedSerial,
        String correctedModel,
        List<String> customerCareReasonCodes,
        String customerCareNotes
    ) {
        if (workOrderLineItemId == null) {
            throw new ReceivingServiceException('Work Order Line Item is required.');
        }
        String corrected = correctedSerial == null ? '' : correctedSerial.trim().toUpperCase();
        String model = correctedModel == null ? '' : correctedModel.trim().toUpperCase();
        List<String> reasonCodes = normalizedReasonCodes(customerCareReasonCodes);
        OverrideSerialResult result = new OverrideSerialResult();
        result.assetUpdated = false;
        result.lineUpdated = false;
        try {
            WorkOrderLineItem lineItem = queryWorkOrderOverrideLineItem(workOrderLineItemId);
            String listedRaw = lineItem.SerialNumber__c;
            String listed = listedRaw == null ? '' : listedRaw.trim().toUpperCase();
            String listedModel = lineItem.Model__c == null
                ? ''
                : lineItem.Model__c.trim().toUpperCase();
            result.serialNumber = listed;
            Boolean applySerial =
                String.isNotBlank(corrected) &&
                corrected != listed &&
                characterDistance(listed, corrected) <= OVERRIDE_SERIAL_CHARACTER_LIMIT;
            Boolean applyModel = String.isNotBlank(model) && model != listedModel;
            Boolean applyCare = !reasonCodes.isEmpty();
            if (!applySerial && !applyModel && !applyCare) {
                return result;
            }

            WorkOrder workOrderUpdate = new WorkOrder(Id = lineItem.WorkOrderId);
            if (applySerial || applyModel) {
                WorkOrderLineItem lineUpdate = new WorkOrderLineItem(Id = lineItem.Id);
                if (applySerial) {
                    lineUpdate.SerialNumber__c = corrected;
                    workOrderUpdate.SerialNumber__c = corrected;
                    result.serialNumber = corrected;
                }
                if (applyModel) {
                    lineUpdate.Model__c = model;
                    workOrderUpdate.Model__c = model;
                }
                WorkOrderLineItemsService.updateLineItems(
                    new List<WorkOrderLineItem>{ lineUpdate }
                );
                result.lineUpdated = true;
            }
            if (applyCare) {
                workOrderUpdate.SubStatus__c = WO_SUB_STATUS_CUSTOMER_CARE;
                workOrderUpdate.ReasonCode__c = String.join(reasonCodes, ';');
                workOrderUpdate.CustomerCareNotes__c = customerCareNotes == null
                    ? null
                    : customerCareNotes.trim();
            }
            if (lineItem.WorkOrderId != null) {
                WorkOrdersService.updateWorkOrders(new List<WorkOrder>{ workOrderUpdate });
            }

            if (applySerial) {
                updateMatchingAssetSerial(lineItem, listedRaw, listed, corrected, result);
            }
            return result;
        } catch (ReceivingServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('ReceivingService.applyWorkOrderSerialOverride: Unexpected error.', e);
            throw new ReceivingServiceException(
                'Unable to save the serial number override: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    private static List<String> normalizedReasonCodes(List<String> reasonCodes) {
        List<String> codes = new List<String>();
        if (reasonCodes == null) {
            return codes;
        }
        for (String reasonCode : reasonCodes) {
            String trimmed = reasonCode == null ? null : reasonCode.trim();
            if (String.isNotBlank(trimmed) && !codes.contains(trimmed)) {
                codes.add(trimmed);
            }
        }
        return codes;
    }

    private static void updateMatchingAssetSerial(
        WorkOrderLineItem lineItem,
        String listedRaw,
        String listed,
        String corrected,
        OverrideSerialResult result
    ) {
        Set<String> serialCandidates = new Set<String>();
        if (String.isNotBlank(listedRaw)) {
            serialCandidates.add(listedRaw.trim());
        }
        if (String.isNotBlank(listed)) {
            serialCandidates.add(listed);
        }
        Id productId = lineItem.Product2Id;
        if (productId == null && lineItem.Asset != null) {
            productId = lineItem.Asset.Product2Id;
        }
        List<Asset> matches = AssetsService.getAssetsBySerialAndProductElevated(
            serialCandidates,
            productId
        );
        if (matches.size() > 1) {
            throw new ReceivingServiceException(
                'More than one Asset matches this serial number and product.'
            );
        }
        if (matches.size() != 1) {
            return;
        }
        Asset asset = matches[0];
        String productCode = lineItem.Product2 == null ? null : lineItem.Product2.ProductCode;
        if (String.isBlank(productCode) && lineItem.Asset?.Product2 != null) {
            productCode = lineItem.Asset.Product2.ProductCode;
        }
        asset.SerialNumber = corrected;
        asset.Name = String.isBlank(productCode)
            ? corrected
            : productCode.trim() + ' - ' + corrected;
        AssetsService.updateAssetsElevated(new List<Asset>{ asset });
        result.assetUpdated = true;
    }

    private static WorkOrderLineItem queryWorkOrderOverrideLineItem(Id workOrderLineItemId) {
        WorkOrderLineItem lineItem = (WorkOrderLineItem) new WorkOrderLineItemsSelector()
            .selectFields(
                new List<String>{
                    'Id',
                    'WorkOrderId',
                    'SerialNumber__c',
                    'Model__c',
                    'Product2Id',
                    'Product2.ProductCode',
                    'AssetId',
                    'Asset.Product2Id',
                    'Asset.Product2.ProductCode'
                }
            )
            .whereEquals('Id', workOrderLineItemId)
            .first();
        if (lineItem == null) {
            throw new ReceivingServiceException('Work Order Line Item was not found.');
        }
        return lineItem;
    }

    /**
     * @description GW-5968 - Result of Resi-Test rerun / disinfection submit on a Work Order.
     */
    public class RerunResiTestResult {
        @AuraEnabled public String resiTestHistoryId;
        @AuraEnabled public String disinfectionLineItemId;
    }

    /**
     * @description GW-5968 - Rerun Resi-Test action for a Repair Center (non-Vendor) Work Order.
     *              Creates a Resi-Test History when the test was performed and always creates the
     *              Disinfection Service Code line under the Product Serviced line.
     *              Both writes roll back together on failure.
     * @param workOrderId Scanned Work Order Id
     * @param workOrderLineItemId Product Serviced Work Order Line Item Id
     * @param resiTestPerformed Whether a Resi-Test was performed
     * @param disinfectedUiValue Clean / Contaminated (required when resiTestPerformed is true)
     * @param quantityReceived Disinfection line quantity (defaults to 1 when blank)
     * @return Created record Ids
     */
    public static RerunResiTestResult submitWorkOrderRerunResiTest(
        Id workOrderId,
        Id workOrderLineItemId,
        Boolean resiTestPerformed,
        String disinfectedUiValue,
        Decimal quantityReceived
    ) {
        return submitWorkOrderRerunResiTest(
            workOrderId,
            workOrderLineItemId,
            resiTestPerformed,
            disinfectedUiValue,
            quantityReceived,
            null
        );
    }

    /**
     * @description GW-5968 - Rerun Resi-Test for a scanned Work Order. A Clean result moves Sub
     *              Status from Contaminated to Ready for Eval, or Customer Care when the Work
     *              Order is flagged. Contaminated keeps Sub Status Contaminated. Instrument
     *              orders with no line apply the rerun to the whole order.
     * @param workOrderId Scanned Work Order Id
     * @param workOrderLineItemId Product Serviced Work Order Line Item Id
     * @param resiTestPerformed Whether a Resi-Test was performed
     * @param disinfectedUiValue Clean / Contaminated
     * @param quantityReceived Disinfection line quantity (defaults to 1 when blank)
     * @param customerCareReasonCodes Reason codes flagged in this Receiving session
     * @return Created record Ids
     */
    public static RerunResiTestResult submitWorkOrderRerunResiTest(
        Id workOrderId,
        Id workOrderLineItemId,
        Boolean resiTestPerformed,
        String disinfectedUiValue,
        Decimal quantityReceived,
        List<String> customerCareReasonCodes
    ) {
        if (workOrderId == null) {
            throw new ReceivingServiceException('Work Order is required.');
        }
        Logger.setScenario('Receiving Rerun Resi-Test');
        Savepoint savepoint = Database.setSavepoint();
        try {
            WorkOrder workOrder = requireWorkOrderForReceiving(workOrderId);
            if (workOrder.RecordType != null && workOrder.RecordType.DeveloperName == WO_RT_VENDOR) {
                throw new ReceivingServiceException(
                    'Resi-Test is not available for Vendor Work Orders.'
                );
            }
            if (workOrderLineItemId == null) {
                return submitInstrumentOrderRerunResiTest(
                    workOrder,
                    resiTestPerformed,
                    disinfectedUiValue,
                    quantityReceived,
                    customerCareReasonCodes
                );
            }
            requireProductServicedLineOnWorkOrder(workOrderLineItemId, workOrderId);

            RerunResiTestResult result = new RerunResiTestResult();
            if (resiTestPerformed == true) {
                if (!UI_CLEAN.equalsIgnoreCase(disinfectedUiValue) &&
                    !UI_CONTAMINATED.equalsIgnoreCase(disinfectedUiValue)) {
                    throw new ReceivingServiceException(
                        'Disinfected must be Clean or Contaminated when a Resi-Test was performed.'
                    );
                }
                result.resiTestHistoryId = ResiTestHistoriesService.createForReceiving(
                    workOrderId,
                    workOrderLineItemId,
                    disinfectedUiValue
                );
            }
            Product2 disinfectionProduct = requireActiveDisinfectionProduct(
                workOrder.ProductLine_f__c
            );
            result.disinfectionLineItemId =
                WorkOrderLineItemsService.createReceivingDisinfectionCodeLine(
                    workOrderId,
                    workOrderLineItemId,
                    quantityReceived,
                    disinfectionProduct
                );
            applyRerunResiSubStatus(workOrderId, disinfectedUiValue, customerCareReasonCodes);
            return result;
        } catch (ReceivingServiceException e) {
            Database.rollback(savepoint);
            throw e;
        } catch (Exception e) {
            Database.rollback(savepoint);
            Logger.error('ReceivingService.submitWorkOrderRerunResiTest: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to submit Resi-Test: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5968 - Instrument quantity screen has no Product Serviced line.
     *              History and the Disinfection code are written on the Work Order.
     *              A blank Product Line uses INSTRUMENT.
     * @param workOrder Instrument Work Order
     * @param resiTestPerformed Whether a Resi-Test was performed
     * @param disinfectedUiValue Clean / Contaminated
     * @param quantityReceived Disinfection line quantity
     * @param customerCareReasonCodes Reason codes flagged in this Receiving session
     * @return Created record Ids
     */
    private static RerunResiTestResult submitInstrumentOrderRerunResiTest(
        WorkOrder workOrder,
        Boolean resiTestPerformed,
        String disinfectedUiValue,
        Decimal quantityReceived,
        List<String> customerCareReasonCodes
    ) {
        if (
            workOrder.RecordType == null ||
            workOrder.RecordType.DeveloperName != WO_RT_INSTRUMENTS
        ) {
            throw new ReceivingServiceException('Work Order Line Item is required.');
        }
        if (resiTestPerformed == true) {
            if (
                !UI_CLEAN.equalsIgnoreCase(disinfectedUiValue) &&
                !UI_CONTAMINATED.equalsIgnoreCase(disinfectedUiValue)
            ) {
                throw new ReceivingServiceException(
                    'Disinfected must be Clean or Contaminated when a Resi-Test was performed.'
                );
            }
        }
        String productLine = String.isNotBlank(workOrder.ProductLine_f__c)
            ? workOrder.ProductLine_f__c
            : 'INSTRUMENT';
        Product2 disinfectionProduct = requireActiveDisinfectionProduct(productLine);
        RerunResiTestResult result = new RerunResiTestResult();
        if (resiTestPerformed == true) {
            result.resiTestHistoryId = ResiTestHistoriesService.createForReceiving(
                workOrder.Id,
                null,
                disinfectedUiValue
            );
        }
        result.disinfectionLineItemId =
            WorkOrderLineItemsService.createReceivingOrderDisinfectionCodeLine(
                workOrder.Id,
                quantityReceived,
                disinfectionProduct
            );
        applyRerunResiSubStatus(workOrder.Id, disinfectedUiValue, customerCareReasonCodes);
        return result;
    }

    /**
     * @description Moves the scanned Work Order off Contaminated after a decontamination rerun.
     */
    private static void applyRerunResiSubStatus(
        Id workOrderId,
        String disinfectedUiValue,
        List<String> customerCareReasonCodes
    ) {
        if (
            !UI_CLEAN.equalsIgnoreCase(disinfectedUiValue) &&
            !UI_CONTAMINATED.equalsIgnoreCase(disinfectedUiValue)
        ) {
            return;
        }
        WorkOrder currentWorkOrder = (WorkOrder) new WorkOrdersSelector()
            .selectFields(new List<String>{ 'Id', 'SubStatus__c', 'ReasonCode__c' })
            .whereEquals('Id', workOrderId)
            .first();
        if (currentWorkOrder == null) {
            return;
        }
        WorkOrder workOrderUpdate = new WorkOrder(Id = workOrderId);
        if (UI_CONTAMINATED.equalsIgnoreCase(disinfectedUiValue)) {
            workOrderUpdate.SubStatus__c = WO_SUB_STATUS_CONTAMINATED;
            workOrderUpdate.Contaminated__c = true;
        } else {
            workOrderUpdate.Contaminated__c = false;
            workOrderUpdate.SubStatus__c = isCustomerCareFlagged(
                currentWorkOrder,
                customerCareReasonCodes
            )
                ? WO_SUB_STATUS_CUSTOMER_CARE
                : WO_SUB_STATUS_READY_FOR_EVAL;
        }
        WorkOrdersService.updateWorkOrders(new List<WorkOrder>{ workOrderUpdate });
    }

    private static Boolean isCustomerCareFlagged(
        WorkOrder workOrder,
        List<String> customerCareReasonCodes
    ) {
        if (workOrder != null && String.isNotBlank(workOrder.ReasonCode__c)) {
            return true;
        }
        if (workOrder != null && workOrder.SubStatus__c == WO_SUB_STATUS_CUSTOMER_CARE) {
            return true;
        }
        if (customerCareReasonCodes == null) {
            return false;
        }
        for (String reasonCode : customerCareReasonCodes) {
            if (String.isNotBlank(reasonCode)) {
                return true;
            }
        }
        return false;
    }

    private static void requireProductServicedLineOnWorkOrder(
        Id workOrderLineItemId,
        Id workOrderId
    ) {
        WorkOrderLineItem lineItem = (WorkOrderLineItem) new WorkOrderLineItemsSelector()
            .selectField('Id')
            .whereEquals('Id', workOrderLineItemId)
            .whereEquals('WorkOrderId', workOrderId)
            .whereEquals('LineType__c', LINE_TYPE_PRODUCT_SERVICED)
            .first();
        if (lineItem == null) {
            throw new ReceivingServiceException(
                'Product Serviced line was not found on this Work Order.'
            );
        }
    }

    /**
     * @description GW-5968 - Active Disinfection Product2 for the Work Order Product Line.
     *              Item Status (Status__c) is ignored. Active and Service Code Type are required.
     *              Process Service queries ProductsSelector (fluent) directly.
     * @param productLine Work Order ProductLine_f__c
     * @return Matching Product2
     */
    private static Product2 requireActiveDisinfectionProduct(String productLine) {
        if (String.isBlank(productLine)) {
            throw new ReceivingServiceException(
                'Work Order Product Line is required to find the Disinfection service code.'
            );
        }
        Product2 disinfectionProduct = (Product2) new ProductsSelector()
            .selectFields(
                new List<String>{ 'Id', 'Name', 'ProductCode', 'Description' }
            )
            .whereEquals('ServiceCodeType__c', SERVICE_CODE_TYPE_DISINFECTION)
            .whereEquals('ProductLine__c', productLine)
            .whereEquals('IsActive', true)
            .orderBy('ProductCode')
            .limitTo(1)
            .first();
        if (disinfectionProduct == null) {
            throw new ReceivingServiceException(
                'No active Disinfection service code product was found for Product Line ' +
                    productLine +
                    '.'
            );
        }
        return disinfectionProduct;
    }

    /**
     * @description GW-5968 - Re-print Travel Tag / Bin Tag for a scanned Repair Center Work Order.
     *              Delegates to PrinterService.printBinTags (shared Devices / Instruments path).
     * @param workOrderId Scanned Work Order Id
     * @return Success message for the Receiving LWC toast
     */
    public static String reprintWorkOrderTravelTag(Id workOrderId) {
        if (workOrderId == null) {
            throw new ReceivingServiceException('Work Order is required.');
        }
        Logger.setScenario('Receiving Travel Tag Print');
        try {
            WorkOrder workOrder = requireWorkOrderForReceiving(workOrderId);
            String recordTypeDeveloperName = workOrder.RecordType == null
                ? null
                : workOrder.RecordType.DeveloperName;
            if (recordTypeDeveloperName == WO_RT_VENDOR) {
                throw new ReceivingServiceException(
                    'Travel Tag print is not available for Vendor Work Orders.'
                );
            }
            if (
                recordTypeDeveloperName != WO_RT_DEVICES &&
                recordTypeDeveloperName != WO_RT_INSTRUMENTS
            ) {
                throw new ReceivingServiceException(
                    'Travel tags can only be printed for Repair Center Devices or Instruments Work Orders.'
                );
            }
            PrinterService.PrintLabelResult result = PrinterService.printBinTags(workOrderId);
            return 'Bin tag sent to printer ' + resolvePrintedTravelTagPrinterName(result) + '.';
        } catch (ReceivingServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('ReceivingService.reprintWorkOrderTravelTag: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                String.isBlank(e.getMessage())
                    ? 'Unable to print the Travel Tag.'
                    : e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    private static String resolvePrintedTravelTagPrinterName(PrinterService.PrintLabelResult result) {
        if (
            result != null &&
            result.request != null &&
            String.isNotBlank(result.request.PrinterName)
        ) {
            return result.request.PrinterName;
        }
        return 'the mapped travel-tag printer';
    }

    /**
     * @description Levenshtein distance between two serial numbers.
     */
    @TestVisible
    private static Integer characterDistance(String leftValue, String rightValue) {
        String leftText = leftValue == null ? '' : leftValue;
        String rightText = rightValue == null ? '' : rightValue;
        Integer leftLength = leftText.length();
        Integer rightLength = rightText.length();
        List<Integer> previousRow = new List<Integer>();
        List<Integer> currentRow = new List<Integer>();
        for (Integer column = 0; column <= rightLength; column++) {
            previousRow.add(column);
            currentRow.add(0);
        }
        for (Integer leftIndex = 1; leftIndex <= leftLength; leftIndex++) {
            currentRow[0] = leftIndex;
            String leftCharacter = leftText.substring(leftIndex - 1, leftIndex);
            for (Integer rightIndex = 1; rightIndex <= rightLength; rightIndex++) {
                Integer substitutionCost = leftCharacter ==
                    rightText.substring(rightIndex - 1, rightIndex)
                    ? 0
                    : 1;
                Integer deleteCost = previousRow[rightIndex] + 1;
                Integer insertCost = currentRow[rightIndex - 1] + 1;
                Integer replaceCost = previousRow[rightIndex - 1] + substitutionCost;
                currentRow[rightIndex] = Math.min(
                    deleteCost,
                    Math.min(insertCost, replaceCost)
                );
            }
            List<Integer> swapRow = previousRow;
            previousRow = currentRow;
            currentRow = swapRow;
        }
        return previousRow[rightLength];
    }

    private static ModFormPhoto toModFormPhoto(ContentVersion version) {
        ModFormPhoto photo = new ModFormPhoto();
        photo.contentDocumentId = version.ContentDocumentId;
        photo.contentVersionId = version.Id;
        photo.title = version.Title;
        photo.fileExtension = version.FileExtension;
        if (version.Id != null) {
            String versionId = String.valueOf(version.Id);
            // Prefer version download for immediate preview; renditions lag after capture.
            photo.imageDownloadUrl = '/sfc/servlet.shepherd/version/download/' + versionId;
            photo.thumbnailUrl =
                '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' +
                versionId;
        }
        return photo;
    }

    /**
     * @description GW-5492 - Accessory row submitted on Finish Receiving.
     */
    public class FinishAccessoryInput {
        @AuraEnabled public String accessoryType;
        @AuraEnabled public String condition;
        @AuraEnabled public String storageLocation;
        @AuraEnabled public Decimal quantity;
    }

    /**
     * @description GW-5492 - Per-item Finish Receiving request from the Receiving LWC.
     */
    public class FinishReceivingRequest {
        @AuraEnabled public Id returnOrderId;
        @AuraEnabled public Id lineItemId;
        @AuraEnabled public Id receiverId;
        @AuraEnabled public Datetime receivedDateTime;
        @AuraEnabled public Boolean isAdHoc;
        @AuraEnabled public Id assetId;
        @AuraEnabled public Id product2Id;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String model;
        @AuraEnabled public Decimal quantityReceived;
        @AuraEnabled public String disinfected;
        @AuraEnabled public Boolean resiTestPerformed;
        @AuraEnabled public Boolean resiTestFailed;
        @AuraEnabled public Boolean visualInspection;
        @AuraEnabled public Boolean bioBag;
        @AuraEnabled public List<String> customerCareReasonCodes;
        @AuraEnabled public String customerCareNotes;
        @AuraEnabled public String overrideCorrectedSerial;
        @AuraEnabled public String overrideCorrectedModel;
        @AuraEnabled public Boolean isRedirected;
        @AuraEnabled public Id redirectLocationId;
        @AuraEnabled public String redirectionNotes;
        @AuraEnabled public Id vendorAccountId;
        @AuraEnabled public String instructionsToVendor;
        @AuraEnabled public Id internalAccountId;
        @AuraEnabled public String internalRepairNotes;
        @AuraEnabled public List<FinishAccessoryInput> accessories;
        @AuraEnabled public List<Id> contentDocumentIds;
    }

    /**
     * @description GW-5492 - Finish Receiving result for badges and navigation.
     */
    public class FinishReceivingResult {
        @AuraEnabled public Boolean hasWorkOrderCreated;
        @AuraEnabled public Boolean isRedirected;
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public Id parentWorkOrderId;
        @AuraEnabled public Id redirectReturnOrderId;
        @AuraEnabled public String redirectReturnOrderNumber;
        @AuraEnabled public Boolean returnOrderFullyReceived;
    }

    /**
     * @description GW-4348 / GW-5996 - Summary line on Create Order review.
     */
    public class CreateOrderLineSummary {
        @AuraEnabled public String lineKey;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String model;
        @AuraEnabled public String quantityLabel;
    }

    /**
     * @description GW-4348 / GW-5996 - Proposed Create Order group (split by PL / PO / Ship-To).
     */
    public class CreateOrderGroup {
        @AuraEnabled public String groupKey;
        @AuraEnabled public Integer displayIndex;
        @AuraEnabled public String displayTitle;
        @AuraEnabled public String productLine;
        @AuraEnabled public Id repairCenterId;
        @AuraEnabled public String repairCenterName;
        @AuraEnabled public Integer lineCount;
        @AuraEnabled public String lineItemsJson;
        @AuraEnabled public List<CreateOrderLineSummary> lines;
    }

    /**
     * @description GW-4348 / GW-5996 - Result of Create Order submit.
     */
    public class CreateOrderSubmitResult {
        @AuraEnabled public List<Id> returnOrderIds;
        @AuraEnabled public List<String> returnOrderNumbers;
        @AuraEnabled public List<Id> workOrderIds;
        @AuraEnabled public Id navigationReturnOrderId;
        @AuraEnabled public Id navigationWorkOrderId;
    }

    /**
     * @description GW-4348 / GW-5996 - One created Work Order for Create Order confirmation.
     */
    public class CreateOrderCreatedWorkOrder {
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
    }

    /**
     * @description GW-5492 - Finish Receiving for one item (Actions menu).
     * @param request Item session payload
     * @return Result with WO / redirect identifiers
     */
    public static FinishReceivingResult finishReceivingItem(FinishReceivingRequest request) {
        Logger.setScenario('Receiving Finish');
        try {
            return ReceivingFinishService.finishItem(request);
        } catch (ReceivingServiceException e) {
            Logger.error('ReceivingService.finishReceivingItem: Business error.', e);
            Logger.saveLog();
            throw e;
        } catch (Exception e) {
            Logger.error('ReceivingService.finishReceivingItem: Unexpected error.', e);
            Logger.saveLog();
            throw new ReceivingServiceException(
                'Unable to finish receiving: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Business exception for Receiving orchestration.
     */
    public class ReceivingServiceException extends Exception {
    }
}