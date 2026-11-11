/**
 * @description GW-157 / GW-3377: Resolves and inserts the Overhaul Service Code WOLI
 *              for a Repair Center Quote from OverhaulCodeMapping__mdt.
 * @group Repair Center Quotes
 */
public with sharing class OverhaulCodeService {
    private static final String QUOTE_RECORD_TYPE_REPAIR_CENTER = 'RepairCenter';
    private static final String LINE_TYPE_SERVICE_CODE = 'Service Code';
    private static final String WOLI_RECORD_TYPE_REPAIR_CODE = 'RepairCode';
    private static final String WOLI_RECORD_TYPE_PRODUCT_SERVICED = 'ProductServiced';
    private static final String WOLI_STATUS_APPROVED = 'Approved';
    private static final String ESTIMATE_REQUIRED_VALUE = 'Estimate Required';
    private static final String WOLI_STATUS_WAITING_APPROVAL = 'Waiting for Approval';

    /** @description Test hook to replace Custom Metadata mappings. */
    @TestVisible
    private static List<OverhaulCodeMapping__mdt> mappingOverride;

    /**
     * @description Test hook for orgs where Quote.RepairCenter is not available to the
     *              running user. Production still requires that record type.
     */
    @TestVisible
    private static Boolean treatAsRepairCenterQuote = false;

    /** @description One describe per transaction for Work Order Line Item record types. */
    private static Map<String, Schema.RecordTypeInfo> workOrderLineItemRecordTypes;

    /**
     * @description Applies overhaul Service Code WOLIs for each Quote Id.
     * @param quoteIds Repair Center Quote Ids
     * @return Overhaul ProductCode per Quote Id (null when no mapping matched)
     */
    public static List<String> applyOverhaulCodes(List<Id> quoteIds) {
        List<String> overhaulProductCodes = new List<String>();
        if (quoteIds == null || quoteIds.isEmpty()) {
            return overhaulProductCodes;
        }

        List<Quote> quotes = (List<Quote>) new QuoteSelector()
            .selectFields(new List<String>{
                'Id',
                'WorkOrder__c',
                'Pricebook2Id',
                'RecordType.DeveloperName'
            })
            .whereField('Id', 'IN', quoteIds)
            .execute();
        Map<Id, Quote> quotesById = new Map<Id, Quote>(quotes);

        Set<Id> parentWorkOrderIds = new Set<Id>();
        for (Quote quoteRecord : quotes) {
            if (isRepairCenterQuote(quoteRecord) && quoteRecord.WorkOrder__c != null) {
                parentWorkOrderIds.add(quoteRecord.WorkOrder__c);
            }
        }

        Map<Id, List<WorkOrderLineItem>> serviceLinesByParentWorkOrderId =
            loadServiceCodeLinesByParent(parentWorkOrderIds);
        Map<Id, WorkOrder> workOrdersById = loadWorkOrdersForInsert(serviceLinesByParentWorkOrderId);
        List<OverhaulCodeMapping__mdt> mappings = getMappings();

        Map<String, Product2> overhaulProductsByCode = loadOverhaulProducts(mappings);
        Map<Id, List<WorkOrderLineItem>> linesToInsertByQuoteId =
            new Map<Id, List<WorkOrderLineItem>>();
        Map<Id, String> overhaulCodeByQuoteId = new Map<Id, String>();

        for (Id quoteId : quoteIds) {
            Quote quoteRecord = quotesById.get(quoteId);
            String overhaulProductCode = resolveAndStageInsert(
                quoteRecord,
                serviceLinesByParentWorkOrderId,
                workOrdersById,
                mappings,
                overhaulProductsByCode,
                linesToInsertByQuoteId
            );
            overhaulCodeByQuoteId.put(quoteId, overhaulProductCode);
        }

        insertStagedLines(linesToInsertByQuoteId);

        for (Id quoteId : quoteIds) {
            overhaulProductCodes.add(overhaulCodeByQuoteId.get(quoteId));
        }
        return overhaulProductCodes;
    }

    /**
     * @description Applies overhaul logic for a single Quote Id.
     * @param quoteId Quote Id
     * @return Overhaul ProductCode or null
     */
    public static String applyOverhaulCode(Id quoteId) {
        if (quoteId == null) {
            return null;
        }
        List<String> results = applyOverhaulCodes(new List<Id>{ quoteId });
        return results.isEmpty() ? null : results[0];
    }

    private static Boolean isRepairCenterQuote(Quote quoteRecord) {
        if (quoteRecord == null) {
            return false;
        }
        if (treatAsRepairCenterQuote) {
            return true;
        }
        return quoteRecord.RecordType != null
            && QUOTE_RECORD_TYPE_REPAIR_CENTER.equals(quoteRecord.RecordType.DeveloperName);
    }

    private static List<OverhaulCodeMapping__mdt> getMappings() {
        if (mappingOverride != null) {
            return mappingOverride;
        }
        return OverhaulCodeMappingSelector.selectAll();
    }

    private static Map<Id, List<WorkOrderLineItem>> loadServiceCodeLinesByParent(
        Set<Id> parentWorkOrderIds
    ) {
        Map<Id, List<WorkOrderLineItem>> linesByParent = new Map<Id, List<WorkOrderLineItem>>();
        if (parentWorkOrderIds.isEmpty()) {
            return linesByParent;
        }

        for (WorkOrderLineItem lineItem : (List<WorkOrderLineItem>) new WorkOrderLineItemsSelector()
            .selectFields(new List<String>{
                'Id',
                'WorkOrderId',
                'TopLevelWorkOrder__c',
                'ProductCodeWoli__c',
                'Product2.ProductCode',
                'Model__c',
                'AssetId',
                'Asset.SerialNumber',
                'Asset.Product2Id',
                'Asset.Product2.Model__c',
                'Asset.Product2.ProductCode',
                'Asset.Product2.Name',
                'Asset.Product2.Description'
            })
            .whereField('TopLevelWorkOrder__c', 'IN', new List<Id>(parentWorkOrderIds))
            .whereEquals('LineType__c', LINE_TYPE_SERVICE_CODE)
            .execute()
        ) {
            if (!linesByParent.containsKey(lineItem.TopLevelWorkOrder__c)) {
                linesByParent.put(lineItem.TopLevelWorkOrder__c, new List<WorkOrderLineItem>());
            }
            linesByParent.get(lineItem.TopLevelWorkOrder__c).add(lineItem);
        }
        return linesByParent;
    }

    private static Map<Id, WorkOrder> loadWorkOrdersForInsert(
        Map<Id, List<WorkOrderLineItem>> serviceLinesByParentWorkOrderId
    ) {
        Set<Id> workOrderIds = new Set<Id>();
        for (List<WorkOrderLineItem> lineItems : serviceLinesByParentWorkOrderId.values()) {
            for (WorkOrderLineItem lineItem : lineItems) {
                if (lineItem.WorkOrderId != null) {
                    workOrderIds.add(lineItem.WorkOrderId);
                }
            }
        }
        if (workOrderIds.isEmpty()) {
            return new Map<Id, WorkOrder>();
        }
        return new Map<Id, WorkOrder>(
            (List<WorkOrder>) new WorkOrdersSelector()
                .selectFields(new List<String>{
                    'Id',
                    'AssetId',
                    'CurrencyIsoCode',
                    'EstimateRequired__c',
                    'ParentWorkOrderId',
                    'Pricebook2Id',
                    'ParentWorkOrder.Pricebook2Id',
                    'Asset.SerialNumber',
                    'Asset.Product2Id',
                    'Asset.Product2.Model__c',
                    'Asset.Product2.ProductCode',
                    'Asset.Product2.Name',
                    'Asset.Product2.Description'
                })
                .whereField('Id', 'IN', new List<Id>(workOrderIds))
                .execute()
        );
    }

    private static Map<String, Product2> loadOverhaulProducts(
        List<OverhaulCodeMapping__mdt> mappings
    ) {
        Set<String> productCodes = new Set<String>();
        for (OverhaulCodeMapping__mdt mapping : mappings) {
            if (String.isNotBlank(mapping.OverhaulProductCode__c)) {
                productCodes.add(mapping.OverhaulProductCode__c);
            }
        }
        Map<String, Product2> productsByCode = new Map<String, Product2>();
        if (productCodes.isEmpty()) {
            return productsByCode;
        }
        for (Product2 product : (List<Product2>) new ProductsSelector()
            .selectFields(new List<String>{ 'Id', 'Name', 'ProductCode', 'Description' })
            .whereField('ProductCode', 'IN', new List<String>(productCodes))
            .whereEquals('IsActive', true)
            .execute()
        ) {
            productsByCode.put(product.ProductCode, product);
        }
        return productsByCode;
    }

    private static String resolveAndStageInsert(
        Quote quoteRecord,
        Map<Id, List<WorkOrderLineItem>> serviceLinesByParentWorkOrderId,
        Map<Id, WorkOrder> workOrdersById,
        List<OverhaulCodeMapping__mdt> mappings,
        Map<String, Product2> overhaulProductsByCode,
        Map<Id, List<WorkOrderLineItem>> linesToInsertByQuoteId
    ) {
        if (!isRepairCenterQuote(quoteRecord) || quoteRecord.WorkOrder__c == null) {
            return null;
        }

        List<WorkOrderLineItem> serviceLines =
            serviceLinesByParentWorkOrderId.get(quoteRecord.WorkOrder__c);
        if (serviceLines == null || serviceLines.isEmpty()) {
            return null;
        }

        Set<String> existingProductCodes = collectProductCodes(serviceLines);
        WorkOrderLineItem triggerLine = findFirstMatchingLine(serviceLines, mappings);
        if (triggerLine == null) {
            return null;
        }

        String model = resolveModel(triggerLine);
        OverhaulCodeMapping__mdt mapping = findMapping(model, existingProductCodes, mappings);
        if (mapping == null || String.isBlank(mapping.OverhaulProductCode__c)) {
            return null;
        }

        String overhaulProductCode = mapping.OverhaulProductCode__c;
        if (existingProductCodes.contains(overhaulProductCode)) {
            return overhaulProductCode;
        }

        WorkOrderLineItem newLine = buildOverhaulLine(
            triggerLine,
            workOrdersById.get(triggerLine.WorkOrderId),
            quoteRecord,
            overhaulProductsByCode.get(overhaulProductCode)
        );
        if (newLine == null) {
            return null;
        }

        if (!linesToInsertByQuoteId.containsKey(quoteRecord.Id)) {
            linesToInsertByQuoteId.put(quoteRecord.Id, new List<WorkOrderLineItem>());
        }
        linesToInsertByQuoteId.get(quoteRecord.Id).add(newLine);
        return overhaulProductCode;
    }

    private static Set<String> collectProductCodes(List<WorkOrderLineItem> serviceLines) {
        Set<String> productCodes = new Set<String>();
        for (WorkOrderLineItem lineItem : serviceLines) {
            if (String.isNotBlank(lineItem.ProductCodeWoli__c)) {
                productCodes.add(lineItem.ProductCodeWoli__c);
            }
            if (lineItem.Product2 != null && String.isNotBlank(lineItem.Product2.ProductCode)) {
                productCodes.add(lineItem.Product2.ProductCode);
            }
        }
        return productCodes;
    }

    private static WorkOrderLineItem findFirstMatchingLine(
        List<WorkOrderLineItem> serviceLines,
        List<OverhaulCodeMapping__mdt> mappings
    ) {
        for (WorkOrderLineItem lineItem : serviceLines) {
            String model = resolveModel(lineItem);
            Set<String> lineCodes = new Set<String>();
            if (String.isNotBlank(lineItem.ProductCodeWoli__c)) {
                lineCodes.add(lineItem.ProductCodeWoli__c);
            }
            if (lineItem.Product2 != null && String.isNotBlank(lineItem.Product2.ProductCode)) {
                lineCodes.add(lineItem.Product2.ProductCode);
            }
            if (findMapping(model, lineCodes, mappings) != null) {
                return lineItem;
            }
        }
        return null;
    }

    private static String resolveModel(WorkOrderLineItem lineItem) {
        if (lineItem == null) {
            return null;
        }
        if (String.isNotBlank(lineItem.Model__c)) {
            return lineItem.Model__c;
        }
        if (lineItem.Asset != null
            && lineItem.Asset.Product2 != null
            && String.isNotBlank(lineItem.Asset.Product2.Model__c)
        ) {
            return lineItem.Asset.Product2.Model__c;
        }
        return null;
    }

    private static OverhaulCodeMapping__mdt findMapping(
        String model,
        Set<String> productCodes,
        List<OverhaulCodeMapping__mdt> mappings
    ) {
        if (String.isBlank(model) || productCodes == null || productCodes.isEmpty()) {
            return null;
        }
        for (OverhaulCodeMapping__mdt mapping : mappings) {
            if (mapping == null
                || String.isBlank(mapping.Model__c)
                || String.isBlank(mapping.TriggerProductCode__c)
            ) {
                continue;
            }
            if (mapping.Model__c.equalsIgnoreCase(model)
                && productCodes.contains(mapping.TriggerProductCode__c)
            ) {
                return mapping;
            }
        }
        return null;
    }

    private static WorkOrderLineItem buildOverhaulLine(
        WorkOrderLineItem triggerLine,
        WorkOrder workOrder,
        Quote quoteRecord,
        Product2 overhaulProduct
    ) {
        if (triggerLine == null || workOrder == null || overhaulProduct == null) {
            Logger.warn(
                new LogMessage(
                    'OverhaulCodeService: cannot build WOLI quoteId={0} workOrderId={1} product={2}',
                    quoteRecord != null ? quoteRecord.Id : null,
                    workOrder != null ? workOrder.Id : null,
                    overhaulProduct != null ? overhaulProduct.ProductCode : null
                )
            );
            return null;
        }

        Id pricebookId = WorkOrdersService.resolvePricebookIdForDeviceEvaluation(workOrder);
        if (pricebookId == null && quoteRecord != null) {
            pricebookId = quoteRecord.Pricebook2Id;
        }
        if (pricebookId == null) {
            Logger.warn(
                new LogMessage(
                    'OverhaulCodeService: no Price Book for Work Order {0}',
                    workOrder.Id
                )
            );
            return null;
        }

        Id pricebookEntryId = getPricebookEntryId(
            overhaulProduct.Id,
            pricebookId,
            workOrder.CurrencyIsoCode
        );
        if (pricebookEntryId == null) {
            Logger.warn(
                new LogMessage(
                    'OverhaulCodeService: no Price Book Entry for {0} on pricebook {1}',
                    overhaulProduct.ProductCode,
                    pricebookId
                )
            );
            return null;
        }

        Product2 assetProduct = workOrder.Asset != null ? workOrder.Asset.Product2 : null;
        WorkOrderLineItem newLine = new WorkOrderLineItem();
        newLine.RecordTypeId = getRepairCodeRecordTypeId();
        newLine.WorkOrderId = workOrder.Id;
        newLine.AssetId = workOrder.AssetId;
        newLine.Status = resolveRepairCodeWoliStatus(workOrder);
        newLine.LineType__c = LINE_TYPE_SERVICE_CODE;
        newLine.SerialNumber__c =
            workOrder.Asset != null ? workOrder.Asset.SerialNumber : null;
        newLine.Model__c = assetProduct != null
            ? assetProduct.Model__c
            : triggerLine.Model__c;
        newLine.Item__c = workOrder.Asset != null ? workOrder.Asset.Product2Id : null;
        newLine.ItemCode__c = assetProduct != null ? assetProduct.ProductCode : null;
        newLine.ItemDescription__c = assetProduct != null
            ? (String.isNotBlank(assetProduct.Description)
                ? assetProduct.Description
                : assetProduct.Name)
            : null;
        newLine.Product__c = overhaulProduct.Id;
        newLine.RepairCode__c = overhaulProduct.Id;
        newLine.ProductCodeWoli__c = overhaulProduct.ProductCode;
        newLine.ProductDescription__c = String.isNotBlank(overhaulProduct.Description)
            ? overhaulProduct.Description
            : overhaulProduct.Name;
        newLine.PricebookEntryId = pricebookEntryId;
        newLine.Quantity = 1;
        newLine.TopLevelWorkOrder__c = triggerLine.TopLevelWorkOrder__c;
        newLine.ParentWorkOrderLineItemId = getNewestProductServicedWoliId(
            workOrder.Id,
            workOrder.AssetId
        );
        return newLine;
    }

    private static Id getPricebookEntryId(Id productId, Id pricebookId, String currencyIsoCode) {
        SoqlQueryBuilder query = new PricebookEntriesSelector()
            .selectField('Id')
            .whereEquals('Product2Id', productId)
            .whereEquals('Pricebook2Id', pricebookId)
            .whereEquals('IsActive', true)
            .limitTo(1);
        if (String.isNotBlank(currencyIsoCode)) {
            query.whereEquals('CurrencyIsoCode', currencyIsoCode);
        }
        List<PricebookEntry> entries = (List<PricebookEntry>) query.execute();
        return entries.isEmpty() ? null : entries[0].Id;
    }

    /**
     * @description Repair Code record type Id, cached for the transaction.
     * @return Record type Id, or null when the record type is unavailable
     */
    private static Id getRepairCodeRecordTypeId() {
        return cachedWorkOrderLineItemRecordTypeId(WOLI_RECORD_TYPE_REPAIR_CODE);
    }

    private static Id cachedWorkOrderLineItemRecordTypeId(String developerName) {
        if (workOrderLineItemRecordTypes == null) {
            workOrderLineItemRecordTypes =
                Schema.SObjectType.WorkOrderLineItem.getRecordTypeInfosByDeveloperName();
        }
        Schema.RecordTypeInfo info = workOrderLineItemRecordTypes.get(developerName);
        return info == null ? null : info.getRecordTypeId();
    }

    private static String resolveRepairCodeWoliStatus(WorkOrder workOrder) {
        if (workOrder != null && ESTIMATE_REQUIRED_VALUE.equals(workOrder.EstimateRequired__c)) {
            return WOLI_STATUS_WAITING_APPROVAL;
        }
        return WOLI_STATUS_APPROVED;
    }

    private static Id getNewestProductServicedWoliId(Id workOrderId, Id assetId) {
        Id recordTypeId = cachedWorkOrderLineItemRecordTypeId(WOLI_RECORD_TYPE_PRODUCT_SERVICED);
        if (recordTypeId == null || workOrderId == null) {
            return null;
        }
        List<WorkOrderLineItem> productServicedLines =
            (List<WorkOrderLineItem>) new WorkOrderLineItemsSelector()
                .selectField('Id')
                .whereEquals('WorkOrderId', workOrderId)
                .whereEquals('RecordTypeId', recordTypeId)
                .whereEquals('AssetId', assetId)
                .orderByDesc('CreatedDate')
                .limitTo(1)
                .execute();
        return productServicedLines.isEmpty() ? null : productServicedLines[0].Id;
    }

    private static void insertStagedLines(
        Map<Id, List<WorkOrderLineItem>> linesToInsertByQuoteId
    ) {
        List<WorkOrderLineItem> linesToInsert = new List<WorkOrderLineItem>();
        for (List<WorkOrderLineItem> quoteLines : linesToInsertByQuoteId.values()) {
            linesToInsert.addAll(quoteLines);
        }
        if (linesToInsert.isEmpty()) {
            return;
        }
        WorkOrderLineItemsService.createLineItems(linesToInsert);
    }
}