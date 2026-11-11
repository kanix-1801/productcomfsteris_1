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
        return (List<WorkOrderLineItem>) SoqlQueryBuilder.fromObject('WorkOrderLineItem')
            .selectFields(
                new List<String>{
                    'Id',
                    'WorkOrderId',
                    'Quantity',
                    'Product2Id',
                    'Product2.ProductLine__c',
                    'Product__c',
                    'Product__r.ProductLine__c',
                    'AssetId',
                    'SerialNumber__c',
                    'Model__c',
                    'WorkOrder.InstructionsToVendor__c',
                    'WorkOrder.VendorNotes__c',
                    'WorkOrder.VendorReferenceNumber__c',
                    'WorkOrder.VendorCost__c'
                }
            )
            .whereField('WorkOrderId', 'IN', new List<Id>(workOrderIds))
            .orderBy('CreatedDate')
            .execute();
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
        return (List<WorkOrderLineItem>) SoqlQueryBuilder.fromObject('WorkOrderLineItem')
            .selectFields(
                new List<String>{
                    'Id',
                    'Product2Id',
                    'Product2.ProductCode',
                    'Product2.Name',
                    'Product2.Description'
                }
            )
            .whereEquals('WorkOrderId', workOrderId)
            .whereEquals('RecordTypeId', repairCodeRtId)
            .whereField('Product2Id', '!=', null)
            .limitTo(200)
            .execute();
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
     * @param productIds Product2 Ids to match on Product2Id
     * @return Matching WorkOrderLineItem records (Id, Product2Id)
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
        return (List<WorkOrderLineItem>) SoqlQueryBuilder.fromObject('WorkOrderLineItem')
            .selectFields(new List<String>{ 'Id', 'Product2Id' })
            .whereEquals('WorkOrderId', workOrderId)
            .whereEquals('RecordTypeId', repairCodeRtId)
            .whereField('Product2Id', 'IN', new List<Id>(productIds))
            .execute();
    }

    /**
     * @description GW-3913 / GW-3096 - Selects Repair Code WOLIs for reconcile (Id, Product2Id).
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
        return (List<WorkOrderLineItem>) SoqlQueryBuilder.fromObject('WorkOrderLineItem')
            .selectFields(new List<String>{ 'Id', 'Product2Id' })
            .whereEquals('WorkOrderId', workOrderId)
            .whereEquals('RecordTypeId', repairCodeRtId)
            .execute();
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
     * @description GW-3913 / GW-3096 - Selects Product2Id values from Repair Code WOLIs.
     * @param workOrderId Parent Work Order Id
     * @param repairCodeRtId Repair Code RecordType Id
     * @return Set of Product2 Ids
     */
    public static Set<Id> selectRepairCodeProductIds(Id workOrderId, Id repairCodeRtId) {
        Set<Id> selectedIds = new Set<Id>();
        if (workOrderId == null || repairCodeRtId == null) {
            return selectedIds;
        }
        List<WorkOrderLineItem> lineItems = (List<WorkOrderLineItem>) SoqlQueryBuilder.fromObject(
                'WorkOrderLineItem'
            )
            .selectFields(new List<String>{ 'Product2Id' })
            .whereEquals('WorkOrderId', workOrderId)
            .whereEquals('RecordTypeId', repairCodeRtId)
            .whereField('Product2Id', '!=', null)
            .execute();
        for (WorkOrderLineItem lineItem : lineItems) {
            selectedIds.add(lineItem.Product2Id);
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
        return (List<WorkOrderLineItem>) SoqlQueryBuilder.fromObject('WorkOrderLineItem')
            .selectFields(
                new List<String>{
                    'Id',
                    'RecordTypeId',
                    'ParentWorkOrderLineItemId',
                    'Status',
                    'Quantity',
                    'AssetId',
                    'SerialNumber__c',
                    'Model__c',
                    'Product2Id',
                    'ProductCodeWoli__c',
                    'ProductDescription__c',
                    'LineType__c',
                    'ReturnOrderLineItems__c',
                    'VendorProcessingRequired__c',
                    'Vendor__c',
                    'VendorWorkOrder__c',
                    'InstructionsToVendor__c',
                    'VendorNotes__c',
                    'VendorReferenceNumber__c',
                    'VendorCost__c',
                    'Product2.ProductCode',
                    'Product2.Name',
                    'CreatedDate'
                }
            )
            .whereEquals('WorkOrderId', workOrderId)
            .whereEquals('RecordTypeId', productServicedRtId)
            .whereEquals('RecordTypeId', repairCodeRtId)
            .withFilterLogic('1 AND (2 OR 3)')
            .orderBy('CreatedDate')
            .execute();
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
     * @description GW-3377 - Sums Repair Code TotalPrice for a Work Order or its top-level parent.
     * @param workOrderId Work Order Id (used when the WO has no parent)
     * @param topLevelWorkOrderId Parent Work Order Id, or the Work Order Id when standalone
     * @param repairCodeRtId Repair Code record type Id
     * @return Sum of TotalPrice (0 when none)
     */
    public static Decimal sumRepairCodeTotalPrice(
        Id workOrderId,
        Id topLevelWorkOrderId,
        Id repairCodeRtId
    ) {
        if (repairCodeRtId == null || (workOrderId == null && topLevelWorkOrderId == null)) {
            return 0;
        }
        List<AggregateResult> aggregates;
        if (workOrderId == topLevelWorkOrderId || topLevelWorkOrderId == null) {
            aggregates = [
                SELECT SUM(TotalPrice) totalPrice
                FROM WorkOrderLineItem
                WHERE WorkOrderId = :workOrderId
                    AND RecordTypeId = :repairCodeRtId
            ];
        } else {
            aggregates = [
                SELECT SUM(TotalPrice) totalPrice
                FROM WorkOrderLineItem
                WHERE RecordTypeId = :repairCodeRtId
                    AND TopLevelWorkOrder__c = :topLevelWorkOrderId
            ];
        }
        if (aggregates.isEmpty() || aggregates[0].get('totalPrice') == null) {
            return 0;
        }
        return (Decimal) aggregates[0].get('totalPrice');
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
                SendToRepairCenter__c,
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
        return (List<WorkOrderLineItem>) SoqlQueryBuilder.fromObject('WorkOrderLineItem')
            .selectFields(
                new List<String>{
                    'Id',
                    'RecordTypeId',
                    'LineType__c',
                    'AssetId',
                    'SerialNumber__c',
                    'Model__c',
                    'Item__c',
                    'ItemCode__c',
                    'ItemDescription__c',
                    'PricebookEntryId',
                    'Product2Id',
                    'ProductCodeWoli__c',
                    'ProductDescription__c',
                    'WorkOrderId',
                    'TopLevelWorkOrder__c',
                    'Quantity',
                    'Status'
                }
            )
            .whereField('WorkOrderId', 'IN', new List<Id>(workOrderIds))
            .whereEquals('LineType__c', 'Service Code')
            .orderBy('CreatedDate')
            .execute();
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
                    'Product2.ProductLine__c'
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
                    'Product2.ProductCode'
                }
            )
            .whereField('ParentWorkOrderLineItemId', 'IN', new List<Id>(parentLineIds))
            .whereField('LineType__c', '!=', 'Product Serviced')
            .orderBy('CreatedDate')
            .execute();
    }

    /**
     * @description GW-3458 - Product Serviced and modifier-eligible service lines for one Work Order.
     * @param workOrderId Work Order Id
     * @return Lines the Modifier Codes tab can display
     */
    public static List<WorkOrderLineItem> selectForModifierCodes(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WorkOrderLineItem>();
        }
        return (List<WorkOrderLineItem>) new WorkOrderLineItemsSelector()
            .selectFields(new List<String>{
                'Id',
                'WorkOrderId',
                'WorkOrder.AssetId',
                'WorkOrder.Asset.SerialNumber',
                'WorkOrder.Asset.ManufacturerCalculated__c',
                'AssetId',
                'Asset.SerialNumber',
                'Asset.ManufacturerCalculated__c',
                'LineType__c',
                'IsAccessory__c',
                'ParentWorkOrderLineItemId',
                'SerialNumber__c',
                'Model__c',
                'Quantity',
                'ProductCodeWoli__c',
                'ProductDescription__c',
                'CategoryCodeDiscount__c',
                // GW-3458 PricingModifier/ModifierReason/OrderReference omitted for CBMQA
                'Product2.Name',
                'Product2.ProductCode',
                'Product2.Manufacturer__c',
                'Product2.Model__c',
                'Product2.EvalCategory__c',
                'Product2.Description',
                'Product__c',
                'Product__r.Name',
                'Product__r.ProductCode',
                'Product__r.Manufacturer__c',
                'Product__r.Model__c',
                'Product__r.EvalCategory__c',
                'Product__r.Description',
                'RepairCode__c',
                'RepairCode__r.Name',
                'RepairCode__r.ProductCode',
                'RepairCode__r.Model__c',
                'RepairCode__r.EvalCategory__c',
                'RepairCode__r.Description'
            })
            .whereEquals('WorkOrderId', workOrderId)
            .whereField(
                'LineType__c',
                'IN',
                new List<String>{
                    'Product Serviced',
                    'Service Code',
                    'Category Code',
                    'Special Pricing'
                }
            )
            .execute();
    }

    /**
     * @description GW-3458 - Loads one line for a modifier save or removal.
     * @param lineItemId Work Order Line Item Id
     * @return Matching line, or an empty list
     */
    public static List<WorkOrderLineItem> selectForModifierUpdate(Id lineItemId) {
        if (lineItemId == null) {
            return new List<WorkOrderLineItem>();
        }
        return (List<WorkOrderLineItem>) new WorkOrderLineItemsSelector()
            .selectFields(new List<String>{
                'Id',
                'WorkOrderId',
                'WorkOrder.AssetId',
                'AssetId',
                'LineType__c',
                'IsAccessory__c',
                'ParentWorkOrderLineItemId',
                'CategoryCodeDiscount__c'
                // GW-3458 PricingModifier/ModifierReason/OrderReference omitted for CBMQA
            })
            .whereEquals('Id', lineItemId)
            .limitTo(1)
            .execute();
    }

    /**
     * @description GW-3458 - Parent lines used when a new Service Code inherits an item modifier.
     * @param lineItemIds Parent Work Order Line Item Ids
     * @return Parents with the modifier package currently stored on the item
     */
    public static List<WorkOrderLineItem> selectModifierParents(Set<Id> lineItemIds) {
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            return new List<WorkOrderLineItem>();
        }
        return (List<WorkOrderLineItem>) new WorkOrderLineItemsSelector()
            .selectFields(new List<String>{
                'Id'
                // GW-3458 PricingModifier/ModifierReason/OrderReference omitted for CBMQA
            })
            .whereField('Id', 'IN', new List<Id>(lineItemIds))
            .execute();
    }

    /**
     * @description GW-3458 - Service Code children of one Product Serviced line.
     * @param parentLineItemId Product Serviced Work Order Line Item Id
     * @return Service Code lines parented to that item
     */
    public static List<WorkOrderLineItem> selectServiceCodeChildren(Id parentLineItemId) {
        if (parentLineItemId == null) {
            return new List<WorkOrderLineItem>();
        }
        return (List<WorkOrderLineItem>) new WorkOrderLineItemsSelector()
            .selectFields(new List<String>{ 'Id', 'LineType__c' })
            .whereEquals('ParentWorkOrderLineItemId', parentLineItemId)
            .whereEquals('LineType__c', 'Service Code')
            .execute();
    }

    /**
     * @description GW-1353 / GW-1509 - Child Work Order lines marked Send to Repair Center for a site visit.
     * @param parentWorkOrderId Parent (site visit) Work Order Id
     * @return Matching WorkOrderLineItem rows
     */
    public static List<WorkOrderLineItem> selectSiteVisitRepairCenterLines(Id parentWorkOrderId) {
        if (parentWorkOrderId == null) {
            return new List<WorkOrderLineItem>();
        }
        // No USER_MODE: Create Return Order prefill must not be blocked by field permissions.
        return [
            SELECT
                Id,
                Quantity,
                Description,
                Product2Id,
                Product2.Name,
                Product2.Description,
                Product2.Model__c,
                Model__c,
                Department__c,
                ReportedProblem__c,
                AdditionalServices__c,
                InsulationPowderCoating__c
            FROM WorkOrderLineItem
            WHERE WorkOrder.ParentWorkOrderId = :parentWorkOrderId
                AND SendToRepairCenter__c = TRUE
            ORDER BY WorkOrder.WorkOrderNumber ASC, LineItemNumber ASC NULLS LAST
        ];
    }

    /**
     * @description GW-6017 / GW-1509 - CRSS lines marked Send to Repair Center for Create Return Order prefill.
     * @param workOrderId Work Order Id
     * @return Matching WorkOrderLineItem rows
     */
    public static List<WorkOrderLineItem> selectCrssRepairCenterAssetsByWorkOrderId(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WorkOrderLineItem>();
        }
        return (List<WorkOrderLineItem>) SoqlQueryBuilder.fromObject('WorkOrderLineItem')
            .selectFields(
                new List<String>{ 'AssetId', 'Department__c', 'ReportedProblem__c' }
            )
            .whereEquals('WorkOrderId', workOrderId)
            .whereField('AssetId', '!=', null)
            .whereEquals('SendToRepairCenter__c', true)
            .orderBy('LineItemNumber', false, true)
            .orderBy('CreatedDate')
            .execute();
    }

    /**
     * @description GW-6017 / GW-1509 - CRSS Send to Repair Center lines to clear after RO create.
     *              Uses static SOQL without USER_MODE to match the original controller query.
     * @param workOrderId Work Order Id
     * @param recordTypeDeveloperName Work Order RecordType DeveloperName
     * @param assetIds Asset Ids placed on the return order
     * @return Matching WorkOrderLineItem Ids
     */
    public static List<WorkOrderLineItem> selectCrssSendToRepairCenterIdsByAsset(
        Id workOrderId,
        String recordTypeDeveloperName,
        Set<Id> assetIds
    ) {
        if (
            workOrderId == null ||
            String.isBlank(recordTypeDeveloperName) ||
            assetIds == null ||
            assetIds.isEmpty()
        ) {
            return new List<WorkOrderLineItem>();
        }
        return [
            SELECT Id
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId
                AND WorkOrder.RecordType.DeveloperName = :recordTypeDeveloperName
                AND AssetId IN :assetIds
                AND SendToRepairCenter__c = TRUE
        ];
    }

    /**
     * @description GW-1509 - Distinct Asset Ids on a Work Order for Create Return Order context.
     * @param workOrderId Work Order Id
     * @return Matching WorkOrderLineItem rows
     */
    public static List<WorkOrderLineItem> selectAssetIdsByWorkOrderId(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WorkOrderLineItem>();
        }
        return (List<WorkOrderLineItem>) SoqlQueryBuilder.fromObject('WorkOrderLineItem')
            .selectFields(new List<String>{ 'AssetId' })
            .whereEquals('WorkOrderId', workOrderId)
            .whereField('AssetId', '!=', null)
            .orderBy('LineItemNumber', false, true)
            .orderBy('CreatedDate')
            .execute();
    }

    /**
     * @description GW-1353 / GW-1509 - Send to Repair Center lines to clear after RO create.
     *              Uses static SOQL without USER_MODE to match the controller.
     * @param workOrderLineItemIds Work Order Line Item Ids
     * @return Matching WorkOrderLineItem Ids
     */
    public static List<WorkOrderLineItem> selectSendToRepairCenterIds(Set<Id> workOrderLineItemIds) {
        if (workOrderLineItemIds == null || workOrderLineItemIds.isEmpty()) {
            return new List<WorkOrderLineItem>();
        }
        return [
            SELECT Id
            FROM WorkOrderLineItem
            WHERE Id IN :workOrderLineItemIds AND SendToRepairCenter__c = TRUE
        ];
    }


    /**
     * @description GW-3400 - Product Serviced Ids for Instrument Evaluation reconcile.
     * @param workOrderId Parent Work Order Id
     * @param productServicedRtId Product Serviced RecordType Id
     * @return Matching WorkOrderLineItem rows (Id only)
     */
    public static List<WorkOrderLineItem> selectProductServicedIdsByWorkOrder(
        Id workOrderId,
        Id productServicedRtId
    ) {
        if (workOrderId == null || productServicedRtId == null) {
            return new List<WorkOrderLineItem>();
        }
        return (List<WorkOrderLineItem>) SoqlQueryBuilder.fromObject('WorkOrderLineItem')
            .selectFields(new List<String>{ 'Id' })
            .whereEquals('WorkOrderId', workOrderId)
            .whereEquals('RecordTypeId', productServicedRtId)
            .execute();
    }

    /**
     * @description GW-3400 - Repair Code children under a Product Serviced line.
     * @param parentLineId Product Serviced WorkOrderLineItem Id
     * @param repairCodeRtId Repair Code RecordType Id
     * @return Matching WorkOrderLineItem rows (Id only)
     */
    public static List<WorkOrderLineItem> selectRepairCodeIdsByParent(
        Id parentLineId,
        Id repairCodeRtId
    ) {
        if (parentLineId == null || repairCodeRtId == null) {
            return new List<WorkOrderLineItem>();
        }
        return (List<WorkOrderLineItem>) SoqlQueryBuilder.fromObject('WorkOrderLineItem')
            .selectFields(new List<String>{ 'Id' })
            .whereEquals('ParentWorkOrderLineItemId', parentLineId)
            .whereEquals('RecordTypeId', repairCodeRtId)
            .execute();
    }

    /**
     * @description GW-3400 - Product Serviced line with parent Work Order Asset for delete guard.
     * @param productServicedId Product Serviced WorkOrderLineItem Id
     * @return Matching rows (LIMIT 1)
     */
    public static List<WorkOrderLineItem> selectWithWorkOrderAssetById(Id productServicedId) {
        if (productServicedId == null) {
            return new List<WorkOrderLineItem>();
        }
        return (List<WorkOrderLineItem>) SoqlQueryBuilder.fromObject('WorkOrderLineItem')
            .selectFields(new List<String>{ 'Id', 'WorkOrder.AssetId' })
            .whereEquals('Id', productServicedId)
            .limitTo(1)
            .execute();
    }

    /**
     * @description GW-1738 / GW-2001 - Prior Parts WOLI for same asset product (billing type).
     * @param workOrderId Current Work Order Id to exclude
     * @param assetId Asset Id
     * @param product2Id Product2 Id
     * @param sinceDatetime CreatedDate lower bound on related Work Orders
     * @return Matching WorkOrderLineItem rows (LIMIT 1)
     */
    public static List<WorkOrderLineItem> selectPriorPartsForBillingType(
        Id workOrderId,
        Id assetId,
        Id product2Id,
        Datetime sinceDatetime
    ) {
        if (workOrderId == null || assetId == null || product2Id == null || sinceDatetime == null) {
            return new List<WorkOrderLineItem>();
        }
        return (List<WorkOrderLineItem>) SoqlQueryBuilder.fromObject('WorkOrderLineItem')
            .selectFields(new List<String>{ 'Id' })
            .whereField('LineType__c', 'IN', new List<String>{ 'Parts', 'Part' })
            .whereField('WorkOrderId', '!=', workOrderId)
            .whereEquals('WorkOrder.AssetId', assetId)
            .whereField('WorkOrder.CreatedDate', '>=', sinceDatetime)
            .whereEquals('ProductItem__r.Product2Id', product2Id)
            .whereEquals('Product2Id', product2Id)
            .withFilterLogic('1 AND 2 AND 3 AND 4 AND (5 OR 6)')
            .limitTo(1)
            .execute();
    }
}