/**
 * @description Selector class for the WorkOrderLineItem SObject.
 *              Centralizes all SOQL queries for Work Order Line Items.
 *              Centralizes Work Order Line Item SOQL. Classes run with sharing.
 */
public with sharing class WorkOrderLineItemsSelector extends SoqlQueryBuilder {
    
    public WorkOrderLineItemsSelector() {
        this.objectName = 'WorkOrderLineItem';
    }

    private static final String BASE_FIELDS =
        'Id, LineItemNumber, WorkOrderId, Status, ProductLine__c, ' +
        'Duration, DurationType, Description, ' +
        'PricebookEntryId, Quantity, UnitPrice, Discount, ' +
        'CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves WorkOrderLineItem records by their Ids.
     * @param ids Set of WorkOrderLineItem Ids to query.
     * @return List of WorkOrderLineItem records matching the given Ids.
     * @example
     * List<WorkOrderLineItem> results = WorkOrderLineItemsSelector.selectById(lineItemIdSet);
     */
    public static List<WorkOrderLineItem> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<WorkOrderLineItem>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM WorkOrderLineItem' +
            ' WHERE Id IN :ids'
        );
    }

    /**
     * @description Returns a line item when it belongs to the given Work Order.
     * @param lineItemId Work Order Line Item Id
     * @param workOrderId Parent Work Order Id
     * @return Matching line item rows (LIMIT 1); empty when not found or either Id is null
     */
    public static List<WorkOrderLineItem> selectByIdAndWorkOrderId(Id lineItemId, Id workOrderId) {
        if (lineItemId == null || workOrderId == null) {
            return new List<WorkOrderLineItem>();
        }
        return [
            SELECT Id
            FROM WorkOrderLineItem
            WHERE Id = :lineItemId
                AND WorkOrderId = :workOrderId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
    }

    /**
     * @description Retrieves WorkOrderLineItem records by their parent WorkOrder Ids.
     * @param workOrderIds Set of WorkOrder Ids to filter on.
     * @return List of WorkOrderLineItem records linked to the given Work Orders.
     * @example
     * List<WorkOrderLineItem> results = WorkOrderLineItemsSelector.selectByWorkOrderId(workOrderIdSet);
     */
    public static List<WorkOrderLineItem> selectByWorkOrderId(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrderLineItem>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM WorkOrderLineItem' +
            ' WHERE WorkOrderId IN :workOrderIds' +
            ' ORDER BY LineItemNumber ASC'
        );
    }

    /**
     * @description Retrieves WorkOrderLineItem records by Status.
     * @param statusValues Set of Status values to filter on.
     * @return List of WorkOrderLineItem records matching the given Status values.
     * @example
     * List<WorkOrderLineItem> results = WorkOrderLineItemsSelector.selectByStatus(new Set<String>{ 'New' });
     */
    public static List<WorkOrderLineItem> selectByStatus(Set<String> statusValues) {
        if (statusValues == null || statusValues.isEmpty()) {
            return new List<WorkOrderLineItem>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM WorkOrderLineItem' +
            ' WHERE Status IN :statusValues' +
            ' ORDER BY CreatedDate DESC'
        );
    }

    /**
     * @description Retrieves WorkOrderLineItem records grouped by their parent WorkOrder Id.
     * @param workOrderIds Set of WorkOrder Ids to filter on.
     * @return Map of WorkOrder Id to list of child WorkOrderLineItem records.
     * @example
     * Map<Id, List<WorkOrderLineItem>> lineItemsByWorkOrderId =
     *     WorkOrderLineItemsSelector.selectByWorkOrderIdAsMap(workOrderIdSet);
     */
    /**
     * @description GW-3880 - WOLIs for vendor consolidation ROLI creation.
     * @param workOrderIds Parent Work Order Ids
     * @return WOLIs ordered by CreatedDate within each Work Order
     */
    public static List<WorkOrderLineItem> selectForVendorConsolidationByWorkOrderIds(
        Set<Id> workOrderIds
    ) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrderLineItem>();
        }
        return [
            SELECT
                Id,
                WorkOrderId,
                Quantity,
                Product2Id,
                Product2.ProductLine__c,
                Product__c,
                Product__r.ProductLine__c,
                AssetId,
                SerialNumber__c,
                Model__c,
                WorkOrder.InstructionsToVendor__c,
                WorkOrder.VendorNotes__c,
                WorkOrder.VendorReferenceNumber__c,
                WorkOrder.VendorCost__c
            FROM WorkOrderLineItem
            WHERE WorkOrderId IN :workOrderIds
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ];
    }

    public static Map<Id, List<WorkOrderLineItem>> selectByWorkOrderIdAsMap(Set<Id> workOrderIds) {
        Map<Id, List<WorkOrderLineItem>> lineItemsByWorkOrderId = new Map<Id, List<WorkOrderLineItem>>();
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return lineItemsByWorkOrderId;
        }

        List<WorkOrderLineItem> lineItemList = Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM WorkOrderLineItem' +
            ' WHERE WorkOrderId IN :workOrderIds' +
            ' ORDER BY LineItemNumber ASC'
        );

        // Group line items by parent WorkOrder Id
        for (WorkOrderLineItem lineItem : lineItemList) {
            if (!lineItemsByWorkOrderId.containsKey(lineItem.WorkOrderId)) {
                lineItemsByWorkOrderId.put(lineItem.WorkOrderId, new List<WorkOrderLineItem>());
            }
            lineItemsByWorkOrderId.get(lineItem.WorkOrderId).add(lineItem);
        }

        return lineItemsByWorkOrderId;
    }

    /**
     * @description GW-3913 / GW-3096 - Selects Repair Code WOLIs with Product labels for Device Evaluation
     *              file listing (LIMIT 200, USER_MODE).
     * @param workOrderId Parent Work Order Id
     * @param repairCodeRtId Repair Code RecordType Id
     * @return Matching WorkOrderLineItem records
     */
    public static List<WorkOrderLineItem> selectRepairCodeLinesWithProduct(
        Id workOrderId,
        Id repairCodeRtId
    ) {
        if (workOrderId == null || repairCodeRtId == null) {
            return new List<WorkOrderLineItem>();
        }
        return [
            SELECT Id, Product__c, Product__r.ProductCode, Product__r.Name, Product__r.Description
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId
                AND RecordTypeId = :repairCodeRtId
                AND Product__c != null
            WITH USER_MODE
            LIMIT 200
        ];
    }

    /**
     * @description GW-3913 / GW-3096 - Selects Repair Code WOLI Ids for a Work Order (LIMIT 200, USER_MODE).
     * @param workOrderId Parent Work Order Id
     * @param repairCodeRtId Repair Code RecordType Id
     * @return Matching WorkOrderLineItem records (Id only)
     */
    public static List<WorkOrderLineItem> selectRepairCodeIds(Id workOrderId, Id repairCodeRtId) {
        if (workOrderId == null || repairCodeRtId == null) {
            return new List<WorkOrderLineItem>();
        }
        return [
            SELECT Id
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId
                AND RecordTypeId = :repairCodeRtId
            WITH USER_MODE
            LIMIT 200
        ];
    }

    /**
     * @description GW-3913 / GW-3096 - Selects Repair Code WOLIs for given Products (USER_MODE).
     * @param workOrderId Parent Work Order Id
     * @param repairCodeRtId Repair Code RecordType Id
     * @param productIds Product2 Ids to match on Product__c
     * @return Matching WorkOrderLineItem records (Id, Product__c)
     */
    public static List<WorkOrderLineItem> selectRepairCodeByWorkOrderAndProducts(
        Id workOrderId,
        Id repairCodeRtId,
        Set<Id> productIds
    ) {
        if (
            workOrderId == null ||
            repairCodeRtId == null ||
            productIds == null ||
            productIds.isEmpty()
        ) {
            return new List<WorkOrderLineItem>();
        }
        return [
            SELECT Id, Product__c
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId
                AND RecordTypeId = :repairCodeRtId
                AND Product__c IN :productIds
            WITH USER_MODE
        ];
    }

    /**
     * @description GW-3913 / GW-3096 - Selects Repair Code WOLIs for reconcile (Id, Product__c).
     * @param workOrderId Parent Work Order Id
     * @param repairCodeRtId Repair Code RecordType Id
     * @return Matching WorkOrderLineItem records
     */
    public static List<WorkOrderLineItem> selectRepairCodeLinesForReconcile(
        Id workOrderId,
        Id repairCodeRtId
    ) {
        if (workOrderId == null || repairCodeRtId == null) {
            return new List<WorkOrderLineItem>();
        }
        return [
            SELECT Id, Product__c
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId
                AND RecordTypeId = :repairCodeRtId
        ];
    }

    /**
     * @description GW-3913 / GW-3096 - Selects the newest Product Serviced WOLI Id for an Asset.
     * @param workOrderId Parent Work Order Id
     * @param assetId Asset Id
     * @param productServicedRtId ProductServiced RecordType Id
     * @return Newest WOLI Id or null
     */
    public static Id selectNewestProductServicedId(
        Id workOrderId,
        Id assetId,
        Id productServicedRtId
    ) {
        if (workOrderId == null || assetId == null || productServicedRtId == null) {
            return null;
        }
        List<WorkOrderLineItem> productServicedLines = [
            SELECT Id
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId
                AND RecordTypeId = :productServicedRtId
                AND AssetId = :assetId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return productServicedLines.isEmpty() ? null : productServicedLines[0].Id;
    }

    /**
     * @description GW-3913 / GW-3096 - Selects Product__c Ids from Repair Code WOLIs.
     * @param workOrderId Parent Work Order Id
     * @param repairCodeRtId Repair Code RecordType Id
     * @return Set of Product2 Ids
     */
    public static Set<Id> selectRepairCodeProductIds(Id workOrderId, Id repairCodeRtId) {
        Set<Id> selectedIds = new Set<Id>();
        if (workOrderId == null || repairCodeRtId == null) {
            return selectedIds;
        }
        for (WorkOrderLineItem lineItem : [
            SELECT Product__c
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId
                AND RecordTypeId = :repairCodeRtId
                AND Product__c != null
        ]) {
            selectedIds.add(lineItem.Product__c);
        }
        return selectedIds;
    }

    /**
     * @description GW-3400 - Selects Product Serviced and Repair Code lines for Instrument Evaluation.
     * @param workOrderId Parent Work Order Id
     * @param productServicedRtId ProductServiced RecordType Id
     * @param repairCodeRtId RepairCode RecordType Id
     * @return Matching WorkOrderLineItem records
     */

    /**
     * @description GW-5497 - Finds non-accessory Product Serviced WOLIs matching the WO Asset.
     * @param workOrderId Work Order Id
     * @param assetId Work Order Asset Id
     * @param productServicedRtId Product Serviced record type Id
     * @return All matching WOLIs; caller defaults only when exactly one exists
     */
    public static List<WorkOrderLineItem> selectQualityInspectionProductServiced(
        Id workOrderId,
        Id assetId,
        Id productServicedRtId
    ) {
        if (workOrderId == null || assetId == null || productServicedRtId == null) {
            return new List<WorkOrderLineItem>();
        }
        return [
            SELECT Id, LineItemNumber, Product2.Name
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId
                AND AssetId = :assetId
                AND RecordTypeId = :productServicedRtId
                AND LineType__c = 'Product Serviced'
                AND IsAccessory__c = FALSE
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ];
    }

    public static List<WorkOrderLineItem> selectInstrumentEvaluationLines(
        Id workOrderId,
        Id productServicedRtId,
        Id repairCodeRtId
    ) {
        if (workOrderId == null || productServicedRtId == null || repairCodeRtId == null) {
            return new List<WorkOrderLineItem>();
        }
        return [
            SELECT
                Id,
                RecordTypeId,
                ParentWorkOrderLineItemId,
                Status,
                Quantity,
                AssetId,
                SerialNumber__c,
                Model__c,
                Product2Id,
                Product__c,
                ProductCodeWoli__c,
                ProductDescription__c,
                LineType__c,
                ReturnOrderLineItems__c,
                VendorProcessingRequired__c,
                Vendor__c,
                VendorWorkOrder__c,
                InstructionsToVendor__c,
                VendorNotes__c,
                VendorReferenceNumber__c,
                VendorCost__c,
                Product__r.ProductCode,
                Product__r.Name,
                Product2.ProductCode,
                Product2.Name,
                CreatedDate
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId
                AND (
                    RecordTypeId = :productServicedRtId
                    OR RecordTypeId = :repairCodeRtId
                )
            ORDER BY CreatedDate ASC
        ];
    }

    /**
     * @description GW-3891 / GW-3400 - Product Serviced fields used to seed Warranty Repair Evaluation.
     * @param workOrderLineItemId Work Order Line Item Id
     * @return Matching WOLI or null
     */
    public static WorkOrderLineItem selectForWarrantyRepairEvaluationById(Id workOrderLineItemId) {
        if (workOrderLineItemId == null) {
            return null;
        }
        List<WorkOrderLineItem> rows = [
            SELECT
                Id,
                WorkOrderId,
                Quantity,
                SerialNumber__c,
                ProductDescription__c,
                Product2Id,
                Product2.Name,
                Product2.ProductCode,
                Product2.Manufacturer__c,
                Product2.Model__c,
                Product2.ProductLine__c,
                Product2.DeviceType__c
            FROM WorkOrderLineItem
            WHERE Id = :workOrderLineItemId
            WITH USER_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description GW-3398 - Service-code product codes on Work Order Line Items.
     * @param workOrderIds Parent Work Order Ids
     * @return Line items whose Product2.ProductCode is populated
     */
     public static List<WorkOrderLineItem> selectProductCodesByWorkOrderIds(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrderLineItem>();
        }
        // List<Id> must stay typed. whereIn(List<Object>) binds as ANY and is rejected for Id columns.
        return (List<WorkOrderLineItem>) new WorkOrderLineItemsSelector()
            .selectFields(new List<String>{ 'WorkOrderId', 'Product2.ProductCode' })
            .whereField('WorkOrderId', 'IN', new List<Id>(workOrderIds))
            .whereField('Product2.ProductCode', '!=', null)
            .execute();
    }

    /**
     * @description GW-4585 - Work Order lines used when pricing JSON does not include line rows.
     * @param workOrderIds Work Order header Ids
     * @return Work Order line items with product pricing fields
     */
    public static List<WorkOrderLineItem> selectForPricingFrameworkByWorkOrderIds(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrderLineItem>();
        }

        return [
            SELECT
                Id,
                Product2.ProductCode,
                Product2.PricingSource__c,
                PricebookEntry.Product2.ProductCode,
                PricebookEntry.Product2.PricingSource__c,
                Quantity
            FROM WorkOrderLineItem
            WHERE WorkOrderId IN :workOrderIds
        ];
    }

    /**
     * @description GW-4585 - Work Order lines used to build Salesforce Headless Pricing JSON.
     * @param lineIds Work Order line item Ids
     * @return Work Order line items with header and price book context
     */
    public static Map<Id, WorkOrderLineItem> selectForPricingFrameworkHeadlessByIds(Set<Id> lineIds) {
        if (lineIds == null || lineIds.isEmpty()) {
            return new Map<Id, WorkOrderLineItem>();
        }

        return new Map<Id, WorkOrderLineItem>([
            SELECT
                Id,
                WorkOrderId,
                Product2Id,
                Product2.ProductCode,
                Product2.PricingSource__c,
                PricebookEntryId,
                Quantity,
                PricebookEntry.Pricebook2Id,
                PricebookEntry.Product2.ProductCode,
                PricebookEntry.Product2.PricingSource__c,
                WorkOrder.AccountId,
                WorkOrder.Pricebook2Id,
                WorkOrder.CurrencyIsoCode
            FROM WorkOrderLineItem
            WHERE Id IN :lineIds
        ]);
    }

    /**
     * @description GW-312 / GW-6191 - Instrument lines that are not canceled, with the values used to
     *              complete an IMS child Work Order and to build the On Location End of Day Report.
     * @param workOrderIds Child Work Order Ids
     * @return Instrument lines ordered by Work Order Number and Line Item Number
     */
    public static List<WorkOrderLineItem> selectActiveInstrumentLines(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrderLineItem>();
        }
        return [
            SELECT
                Id,
                LineItemNumber,
                WorkOrderId,
                WorkOrder.WorkOrderNumber,
                WorkOrder.Asset.Name,
                Status,
                Product2Id,
                Product2.Name,
                AssetId,
                Asset.Name,
                RepairLevel__c,
                MobileDevicePictureCount__c,
                SendToRepairCenter__c,
                ReplacedWithIXchange__c,
                SerialNumber__c,
                Model__c,
                Quantity,
                ReportedProblem__c
            FROM WorkOrderLineItem
            WHERE WorkOrderId IN :workOrderIds
                AND LineType__c = 'Instrument'
                AND Status != 'Canceled'
            ORDER BY WorkOrder.WorkOrderNumber ASC, LineItemNumber ASC
        ];
    }

    /**
     * @description GW-6257 - Product Serviced lines of a CRSS site visit that are not canceled and have
     *              an Inspection Outcome, for the CRSS On Location End of Day Report.
     * @param workOrderId CRSS site visit Work Order Id
     * @return Inspected lines ordered by Line Item Number
     */
    public static List<WorkOrderLineItem> selectCrssInspectedLines(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WorkOrderLineItem>();
        }
        return [
            SELECT
                Id,
                LineItemNumber,
                AssetId,
                Asset.Name,
                Asset.SerialNumber,
                Asset.ManufacturerCalculated__c,
                Asset.ModelCalculated__c,
                InspectionOutcome__c,
                ReportedProblem__c
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId
                AND LineType__c = 'Product Serviced'
                AND Status != 'Canceled'
                AND InspectionOutcome__c != null
            ORDER BY LineItemNumber ASC
        ];
    }

    /**
     * @description GW-5748 - Service Code WOLIs for a single Work Order.
     * @param workOrderId Work Order Id
     * @return Service Code lines, empty when the Work Order Id is null
     */
    public static List<WorkOrderLineItem> selectServiceCodeLinesByWorkOrderId(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WorkOrderLineItem>();
        }
        return selectServiceCodeLinesByWorkOrderIds(new Set<Id>{ workOrderId });
    }

    /**
     * @description GW-5748 - Service Code WOLIs for Divide Instruments clone/reconcile.
     * @param workOrderIds Work Order Ids
     * @return Service Code lines, empty when the set is null or empty
     */
    public static List<WorkOrderLineItem> selectServiceCodeLinesByWorkOrderIds(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrderLineItem>();
        }
        return [
            SELECT
                Id,
                RecordTypeId,
                LineType__c,
                AssetId,
                SerialNumber__c,
                Model__c,
                Item__c,
                ItemCode__c,
                ItemDescription__c,
                PricebookEntryId,
                Product2Id,
                Product__c,
                ProductCodeWoli__c,
                ProductDescription__c,
                WorkOrderId,
                TopLevelWorkOrder__c,
                Quantity,
                Status
            FROM WorkOrderLineItem
            WHERE WorkOrderId IN :workOrderIds
                AND LineType__c = 'Service Code'
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ];
    }

    /**
     * @description GW-5845 - Non-accessory Product Serviced WOLIs for Quality Inspection
     *              Instrument Information when the Work Order has no Asset.
     * @param workOrderId Work Order Id
     * @return Product Serviced lines
     */
    public static List<WorkOrderLineItem> selectProductServicedNonAccessoryByWorkOrderId(
        Id workOrderId
    ) {
        if (workOrderId == null) {
            return new List<WorkOrderLineItem>();
        }
        return (List<WorkOrderLineItem>) new WorkOrderLineItemsSelector()
            .selectAllFields()
            .selectFields(
                new List<String>{
                    'Product2.Name',
                    'Product2.Model__c',
                    'Product2.Manufacturer__c',
                    'Product2.ProductLine__c',
                    'Product__r.Name',
                    'Product__r.Model__c',
                    'Product__r.Manufacturer__c',
                    'Product__r.ProductLine__c'
                }
            )
            .whereEquals('WorkOrderId', workOrderId)
            .whereEquals('LineType__c', 'Product Serviced')
            .whereEquals('IsAccessory__c', false)
            .orderBy('LineItemNumber')
            .execute();
    }

    /**
     * @description GW-5845 - Repair Code children used for Quality Inspection Repair Summary.
     * @param parentLineIds Product Serviced WOLI Ids
     * @return Child repair-code lines
     */
    public static List<WorkOrderLineItem> selectRepairCodeChildrenByParentIds(Set<Id> parentLineIds) {
        if (parentLineIds == null || parentLineIds.isEmpty()) {
            return new List<WorkOrderLineItem>();
        }
        return (List<WorkOrderLineItem>) new WorkOrderLineItemsSelector()
            .selectAllFields()
            .selectFields(
                new List<String>{
                    'Product2.Name',
                    'Product2.ProductCode',
                    'Product__r.Name',
                    'Product__r.ProductCode'
                }
            )
            .whereField('ParentWorkOrderLineItemId', 'IN', new List<Id>(parentLineIds))
            .whereField('LineType__c', '!=', 'Product Serviced')
            .orderBy('CreatedDate')
            .execute();
    }
}