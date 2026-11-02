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
     * @description Applies overhaul Service Code WOLIs for each Quote Id.
     * @param quoteIds Repair Center Quote Ids
     * @return Overhaul ProductCode per Quote Id (null when no mapping matched)
     */
    public static List<String> applyOverhaulCodes(List<Id> quoteIds) {
        List<String> overhaulProductCodes = new List<String>();
        if (quoteIds == null || quoteIds.isEmpty()) {
            return overhaulProductCodes;
        }

        List<Quote> quotes = [
            SELECT Id, WorkOrder__c, Pricebook2Id, RecordType.DeveloperName
            FROM Quote
            WHERE Id IN :quoteIds
        ];
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
        return quoteRecord != null
            && quoteRecord.RecordType != null
            && QUOTE_RECORD_TYPE_REPAIR_CENTER.equals(quoteRecord.RecordType.DeveloperName);
    }

    private static List<OverhaulCodeMapping__mdt> getMappings() {
        if (mappingOverride != null) {
            return mappingOverride;
        }
        return [
            SELECT Model__c, TriggerProductCode__c, OverhaulProductCode__c
            FROM OverhaulCodeMapping__mdt
        ];
    }

    private static Map<Id, List<WorkOrderLineItem>> loadServiceCodeLinesByParent(
        Set<Id> parentWorkOrderIds
    ) {
        Map<Id, List<WorkOrderLineItem>> linesByParent = new Map<Id, List<WorkOrderLineItem>>();
        if (parentWorkOrderIds.isEmpty()) {
            return linesByParent;
        }

        for (WorkOrderLineItem lineItem : [
            SELECT
                Id,
                WorkOrderId,
                TopLevelWorkOrder__c,
                ProductCodeWoli__c,
                Product2.ProductCode,
                Model__c,
                AssetId,
                Asset.SerialNumber,
                Asset.Product2Id,
                Asset.Product2.Model__c,
                Asset.Product2.ProductCode,
                Asset.Product2.Name,
                Asset.Product2.Description
            FROM WorkOrderLineItem
            WHERE TopLevelWorkOrder__c IN :parentWorkOrderIds
                AND LineType__c = :LINE_TYPE_SERVICE_CODE
        ]) {
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
        return new Map<Id, WorkOrder>([
            SELECT
                Id,
                AssetId,
                CurrencyIsoCode,
                EstimateRequired__c,
                ParentWorkOrderId,
                Pricebook2Id,
                ParentWorkOrder.Pricebook2Id,
                Asset.SerialNumber,
                Asset.Product2Id,
                Asset.Product2.Model__c,
                Asset.Product2.ProductCode,
                Asset.Product2.Name,
                Asset.Product2.Description
            FROM WorkOrder
            WHERE Id IN :workOrderIds
        ]);
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
        for (Product2 product : [
            SELECT Id, Name, ProductCode, Description
            FROM Product2
            WHERE ProductCode IN :productCodes
                AND IsActive = true
        ]) {
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
        List<PricebookEntry> entries;
        if (String.isNotBlank(currencyIsoCode)) {
            entries = [
                SELECT Id
                FROM PricebookEntry
                WHERE Product2Id = :productId
                    AND Pricebook2Id = :pricebookId
                    AND CurrencyIsoCode = :currencyIsoCode
                    AND IsActive = true
                LIMIT 1
            ];
        } else {
            entries = [
                SELECT Id
                FROM PricebookEntry
                WHERE Product2Id = :productId
                    AND Pricebook2Id = :pricebookId
                    AND IsActive = true
                LIMIT 1
            ];
        }
        return entries.isEmpty() ? null : entries[0].Id;
    }

    private static Id getRepairCodeRecordTypeId() {
        Schema.RecordTypeInfo info = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get(WOLI_RECORD_TYPE_REPAIR_CODE);
        return info == null ? null : info.getRecordTypeId();
    }

    private static String resolveRepairCodeWoliStatus(WorkOrder workOrder) {
        if (workOrder != null && ESTIMATE_REQUIRED_VALUE.equals(workOrder.EstimateRequired__c)) {
            return WOLI_STATUS_WAITING_APPROVAL;
        }
        return WOLI_STATUS_APPROVED;
    }

    private static Id getNewestProductServicedWoliId(Id workOrderId, Id assetId) {
        Schema.RecordTypeInfo info = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get(WOLI_RECORD_TYPE_PRODUCT_SERVICED);
        if (info == null || workOrderId == null) {
            return null;
        }
        Id recordTypeId = info.getRecordTypeId();
        List<WorkOrderLineItem> productServicedLines = [
            SELECT Id
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId
                AND RecordTypeId = :recordTypeId
                AND AssetId = :assetId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
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