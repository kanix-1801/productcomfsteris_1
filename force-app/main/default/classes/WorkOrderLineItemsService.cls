/**
 * @description Service class for WorkOrderLineItem business operations.
 *              Entry point for all Work Order Line Item-related transactions.
 *              Performs DML directly — no Unit of Work.
 */
public with sharing class WorkOrderLineItemsService {
    /** @description Test hook to force QueryException wrapping in Allowed Unit unit tests. */
    @TestVisible private static Boolean simulateQueryException = false;
    /** @description Test hook to force generic Exception wrapping in Allowed Unit unit tests. */
    @TestVisible private static Boolean simulateGenericException = false;

    @TestVisible
    private static void throwIfSimulated() {
        if (Test.isRunningTest() && simulateGenericException) {
            throw new CalloutException('Simulated exception for coverage');
        }
    }

    @TestVisible
    private interface IWorkOrderLineItemsSelector {
        List<WorkOrderLineItem> selectById(Set<Id> lineItemIds);
        List<WorkOrderLineItem> selectByWorkOrderId(Set<Id> workOrderIds);
        List<WorkOrderLineItem> selectRepairCodeLinesWithProduct(
            Id workOrderId,
            Id repairCodeRtId
        );
        List<WorkOrderLineItem> selectRepairCodeIds(Id workOrderId, Id repairCodeRtId);
        List<WorkOrderLineItem> selectRepairCodeByWorkOrderAndProducts(
            Id workOrderId,
            Id repairCodeRtId,
            Set<Id> productIds
        );
        List<WorkOrderLineItem> selectRepairCodeLinesForReconcile(
            Id workOrderId,
            Id repairCodeRtId
        );
        Id selectNewestProductServicedId(Id workOrderId, Id assetId, Id productServicedRtId);
        Set<Id> selectRepairCodeProductIds(Id workOrderId, Id repairCodeRtId);
        List<WorkOrderLineItem> selectInstrumentEvaluationLines(
            Id workOrderId,
            Id productServicedRtId,
            Id repairCodeRtId
        );
        List<WorkOrderLineItem> selectQualityInspectionProductServiced(
            Id workOrderId,
            Id assetId,
            Id productServicedRtId
        );
    }

    private class DefaultWorkOrderLineItemsSelector implements IWorkOrderLineItemsSelector {
        public List<WorkOrderLineItem> selectById(Set<Id> lineItemIds) {
            return WorkOrderLineItemsSelector.selectById(lineItemIds);
        }
        public List<WorkOrderLineItem> selectByWorkOrderId(Set<Id> workOrderIds) {
            return WorkOrderLineItemsSelector.selectByWorkOrderId(workOrderIds);
        }
        public List<WorkOrderLineItem> selectRepairCodeLinesWithProduct(
            Id workOrderId,
            Id repairCodeRtId
        ) {
            return WorkOrderLineItemsSelector.selectRepairCodeLinesWithProduct(
                workOrderId,
                repairCodeRtId
            );
        }
        public List<WorkOrderLineItem> selectRepairCodeIds(
            Id workOrderId,
            Id repairCodeRtId
        ) {
            return WorkOrderLineItemsSelector.selectRepairCodeIds(
                workOrderId,
                repairCodeRtId
            );
        }
        public List<WorkOrderLineItem> selectRepairCodeByWorkOrderAndProducts(
            Id workOrderId,
            Id repairCodeRtId,
            Set<Id> productIds
        ) {
            return WorkOrderLineItemsSelector.selectRepairCodeByWorkOrderAndProducts(
                workOrderId,
                repairCodeRtId,
                productIds
            );
        }
        public List<WorkOrderLineItem> selectRepairCodeLinesForReconcile(
            Id workOrderId,
            Id repairCodeRtId
        ) {
            return WorkOrderLineItemsSelector.selectRepairCodeLinesForReconcile(
                workOrderId,
                repairCodeRtId
            );
        }
        public Id selectNewestProductServicedId(
            Id workOrderId,
            Id assetId,
            Id productServicedRtId
        ) {
            return WorkOrderLineItemsSelector.selectNewestProductServicedId(
                workOrderId,
                assetId,
                productServicedRtId
            );
        }
        public Set<Id> selectRepairCodeProductIds(Id workOrderId, Id repairCodeRtId) {
            return WorkOrderLineItemsSelector.selectRepairCodeProductIds(
                workOrderId,
                repairCodeRtId
            );
        }
        public List<WorkOrderLineItem> selectInstrumentEvaluationLines(
            Id workOrderId,
            Id productServicedRtId,
            Id repairCodeRtId
        ) {
            return WorkOrderLineItemsSelector.selectInstrumentEvaluationLines(
                workOrderId,
                productServicedRtId,
                repairCodeRtId
            );
        }
        public List<WorkOrderLineItem> selectQualityInspectionProductServiced(
            Id workOrderId,
            Id assetId,
            Id productServicedRtId
        ) {
            return WorkOrderLineItemsSelector.selectQualityInspectionProductServiced(
                workOrderId,
                assetId,
                productServicedRtId
            );
        }
    }

    @TestVisible
    private static IWorkOrderLineItemsSelector selectorOverride;

    private static IWorkOrderLineItemsSelector selector() {
        return selectorOverride == null
            ? new DefaultWorkOrderLineItemsSelector()
            : selectorOverride;
    }

    @TestVisible
    private static Id repairCodeRecordTypeIdOverride;

    private static final String WOLI_RECORD_TYPE_REPAIR_CODE = 'RepairCode';
    private static final String WOLI_RECORD_TYPE_PRODUCT_SERVICED = 'ProductServiced';
    private static final String WOLI_LINE_TYPE_PRODUCT_SERVICED = 'Product Serviced';
    /** GW-5328 - Instrument Evaluation Product Serviced WOLI Product Line. */
    private static final String WOLI_PRODUCT_LINE_INSTRUMENT = 'INSTRUMENT';
    private static final String COMPONENT_TYPE_CATEGORY_CODE = 'Category Code';
    private static final String COMPONENT_TYPE_SPECIAL_PRICING = 'Special Pricing';
    private static final String COMPONENT_TYPE_OBSERVATION_CODE = 'Observation Code';
    private static final String COMPONENT_TYPE_SERVICE_CODE = 'Service Code';
    private static final String ESTIMATE_REQUIRED_VALUE = 'Estimate Required';
    private static final String WOLI_STATUS_WAITING_APPROVAL = 'Waiting for Approval';
    private static final String WOLI_STATUS_APPROVED = 'Approved';
    private static final Set<String> PRICING_CODE_COMPONENT_TYPES = new Set<String>{
        COMPONENT_TYPE_CATEGORY_CODE,
        COMPONENT_TYPE_SPECIAL_PRICING
    };

    /**
     * @description Creates new WorkOrderLineItem records with validation.
     * @param lineItems List of WorkOrderLineItem records to create.
     * @throws WorkOrderLineItemsServiceException when the operation fails.
     * @example
     * WorkOrderLineItemsService.createLineItems(lineItemList);
     */
    public static void createLineItems(List<WorkOrderLineItem> lineItems) {
        if (lineItems == null || lineItems.isEmpty()) {
            return;
        }
        Logger.setScenario('Work Order Line Item Management');
        try {
            throwIfSimulated();
            // Apply defaults and validate via Domain
            WorkOrderLineItems domain = new WorkOrderLineItems(lineItems);
            // domain.applyDefaults();
            // domain.validate();

            // Perform DML
            insert lineItems;
            // GW-3458 - A new Service Code under an Item and Service modifier inherits that modifier.
            ModifierCodesService.inheritItemAndServiceModifier(lineItems);
        } catch (WorkOrderLineItems.WorkOrderLineItemsException e) {
            Logger.error(new LogMessage('WorkOrderLineItemsService.createLineItems: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(e.getMessage(), e);
        } catch (DmlException e) {
            Logger.error('WorkOrderLineItemsService.createLineItems: Unexpected error.', e);
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(
                'Unable to create Work Order Line Item records: ' + e.getDmlMessage(0),
                e
            );
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemsService.createLineItems: Unexpected error.', e);
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException('An unexpected error occurred while creating Work Order Line Item records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing WorkOrderLineItem records with validation.
     * @param lineItems List of WorkOrderLineItem records to update.
     * @throws WorkOrderLineItemsServiceException when the operation fails.
     * @example
     * WorkOrderLineItemsService.updateLineItems(lineItemList);
     */
    public static void updateLineItems(List<WorkOrderLineItem> lineItems) {
        if (lineItems == null || lineItems.isEmpty()) {
            return;
        }
        Logger.setScenario('Work Order Line Item Management');
        try {
            // Validate via Domain
            WorkOrderLineItems domain = new WorkOrderLineItems(lineItems);
            // domain.validate();

            // Perform DML
            update lineItems;
        } catch (WorkOrderLineItems.WorkOrderLineItemsException e) {
            Logger.error(new LogMessage('WorkOrderLineItemsService.updateLineItems: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemsService.updateLineItems: Unexpected error.', e);
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException('An unexpected error occurred while updating Work Order Line Item records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes WorkOrderLineItem records by their Ids.
     * @param lineItemIds Set of WorkOrderLineItem Ids to delete.
     * @throws WorkOrderLineItemsServiceException when the operation fails.
     * @example
     * WorkOrderLineItemsService.deleteLineItems(lineItemIdSet);
     */
    public static void deleteLineItems(Set<Id> lineItemIds) {
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Work Order Line Item Management');
        try {
            // Retrieve records via Selector
            List<WorkOrderLineItem> lineItemList = selector().selectById(lineItemIds);
            if (lineItemList.isEmpty()) {
                return;
            }

            // Perform DML
            delete lineItemList;
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemsService.deleteLineItems: Unexpected error.', e);
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException('An unexpected error occurred while deleting Work Order Line Item records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves WorkOrderLineItem records by their Ids.
     * @param lineItemIds Set of WorkOrderLineItem Ids to retrieve.
     * @return List of WorkOrderLineItem records.
     * @throws WorkOrderLineItemsServiceException when the operation fails.
     * @example
     * List<WorkOrderLineItem> results = WorkOrderLineItemsService.getLineItemsById(lineItemIdSet);
     */
    public static List<WorkOrderLineItem> getLineItemsById(Set<Id> lineItemIds) {
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            return new List<WorkOrderLineItem>();
        }
        try {
            return selector().selectById(lineItemIds);
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemsService.getLineItemsById: Unexpected error.', e);
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException('An unexpected error occurred while retrieving Work Order Line Item records.', e);
        }
    }

    /**
     * @description Returns a line item when it belongs to the given Work Order, or null when it does not.
     * @param lineItemId Work Order Line Item Id
     * @param workOrderId Parent Work Order Id
     * @return Matching WorkOrderLineItem or null
     * @throws WorkOrderLineItemsServiceException when the query fails
     */
    public static WorkOrderLineItem getLineItemByIdAndWorkOrderId(Id lineItemId, Id workOrderId) {
        if (lineItemId == null || workOrderId == null) {
            return null;
        }
        try {
            throwIfSimulated();
            List<WorkOrderLineItem> rows = WorkOrderLineItemsSelector.selectByIdAndWorkOrderId(
                lineItemId,
                workOrderId
            );
            return rows.isEmpty() ? null : rows[0];
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrderLineItemsService.getLineItemByIdAndWorkOrderId failed for {0}: {1}',
                    lineItemId,
                    e.getMessage()
                ),
                e
            );
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(
                'An unexpected error occurred while retrieving a Work Order Line Item.',
                e
            );
        }
    }

    /**
     * @description GW-3891 / GW-3400 - Returns a Product Serviced line for Warranty Repair Evaluation form defaults.
     * @param workOrderLineItemId Work Order Line Item Id
     * @return WorkOrderLineItem or null
     * @throws WorkOrderLineItemsServiceException when the operation fails
     */
    public static WorkOrderLineItem getLineItemForWarrantyRepairEvaluation(Id workOrderLineItemId) {
        if (workOrderLineItemId == null) {
            return null;
        }
        try {
            throwIfSimulated();
            return WorkOrderLineItemsSelector.selectForWarrantyRepairEvaluationById(workOrderLineItemId);
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrderLineItemsService.getLineItemForWarrantyRepairEvaluation failed for {0}',
                    workOrderLineItemId
                ),
                e
            );
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(
                'An unexpected error occurred while retrieving a Work Order Line Item for Warranty Repair Evaluation.',
                e
            );
        }
    }

    /**
     * @description Retrieves WorkOrderLineItem records for a set of parent WorkOrder Ids.
     * @param workOrderIds Set of WorkOrder Ids to retrieve line items for.
     * @return List of WorkOrderLineItem records linked to the given Work Orders.
     * @throws WorkOrderLineItemsServiceException when the operation fails.
     * @example
     * List<WorkOrderLineItem> results = WorkOrderLineItemsService.getLineItemsByWorkOrderId(workOrderIdSet);
     */
    public static List<WorkOrderLineItem> getLineItemsByWorkOrderId(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrderLineItem>();
        }
        try {
            return selector().selectByWorkOrderId(workOrderIds);
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemsService.getLineItemsByWorkOrderId: Unexpected error.', e);
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException('An unexpected error occurred while retrieving Work Order Line Items by Work Order.', e);
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Repair Code WOLIs with Product labels for Device Evaluation.
     * @param workOrderId Parent Work Order Id
     * @param repairCodeRtId Repair Code RecordType Id
     * @return Matching WorkOrderLineItem records
     * @throws WorkOrderLineItemsServiceException when the operation fails
     */
    public static List<WorkOrderLineItem> getRepairCodeLinesWithProduct(
        Id workOrderId,
        Id repairCodeRtId
    ) {
        if (workOrderId == null || repairCodeRtId == null) {
            return new List<WorkOrderLineItem>();
        }
        try {
            return selector().selectRepairCodeLinesWithProduct(
                workOrderId,
                repairCodeRtId
            );
        } catch (Exception e) {
            Logger.error(
                'WorkOrderLineItemsService.getRepairCodeLinesWithProduct: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(
                'An unexpected error occurred while retrieving Repair Code line items for Device Evaluation.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Repair Code WOLI Ids for Device Evaluation.
     * @param workOrderId Parent Work Order Id
     * @param repairCodeRtId Repair Code RecordType Id
     * @return Matching WorkOrderLineItem records (Id only)
     * @throws WorkOrderLineItemsServiceException when the operation fails
     */
    public static List<WorkOrderLineItem> getRepairCodeIds(Id workOrderId, Id repairCodeRtId) {
        if (workOrderId == null || repairCodeRtId == null) {
            return new List<WorkOrderLineItem>();
        }
        try {
            return selector().selectRepairCodeIds(workOrderId, repairCodeRtId);
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemsService.getRepairCodeIds: Unexpected error.', e);
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(
                'An unexpected error occurred while retrieving Repair Code Ids for Device Evaluation.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Repair Code WOLIs for selected Products.
     * @param workOrderId Parent Work Order Id
     * @param repairCodeRtId Repair Code RecordType Id
     * @param productIds Product2 Ids
     * @return Matching WorkOrderLineItem records
     * @throws WorkOrderLineItemsServiceException when the operation fails
     */
    public static List<WorkOrderLineItem> getRepairCodeByWorkOrderAndProducts(
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
        try {
            return selector().selectRepairCodeByWorkOrderAndProducts(
                workOrderId,
                repairCodeRtId,
                productIds
            );
        } catch (Exception e) {
            Logger.error(
                'WorkOrderLineItemsService.getRepairCodeByWorkOrderAndProducts: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(
                'An unexpected error occurred while retrieving Repair Code lines by Product for Device Evaluation.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Repair Code WOLIs for reconcile.
     * @param workOrderId Parent Work Order Id
     * @param repairCodeRtId Repair Code RecordType Id
     * @return Matching WorkOrderLineItem records
     * @throws WorkOrderLineItemsServiceException when the operation fails
     */
    public static List<WorkOrderLineItem> getRepairCodeLinesForReconcile(
        Id workOrderId,
        Id repairCodeRtId
    ) {
        if (workOrderId == null || repairCodeRtId == null) {
            return new List<WorkOrderLineItem>();
        }
        try {
            return selector().selectRepairCodeLinesForReconcile(
                workOrderId,
                repairCodeRtId
            );
        } catch (Exception e) {
            Logger.error(
                'WorkOrderLineItemsService.getRepairCodeLinesForReconcile: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(
                'An unexpected error occurred while retrieving Repair Code lines for reconcile.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Newest Product Serviced WOLI Id for an Asset.
     * @param workOrderId Parent Work Order Id
     * @param assetId Asset Id
     * @param productServicedRtId ProductServiced RecordType Id
     * @return Newest WOLI Id or null
     * @throws WorkOrderLineItemsServiceException when the operation fails
     */
    public static Id getNewestProductServicedId(
        Id workOrderId,
        Id assetId,
        Id productServicedRtId
    ) {
        if (workOrderId == null || assetId == null || productServicedRtId == null) {
            return null;
        }
        try {
            return selector().selectNewestProductServicedId(
                workOrderId,
                assetId,
                productServicedRtId
            );
        } catch (Exception e) {
            Logger.error(
                'WorkOrderLineItemsService.getNewestProductServicedId: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(
                'An unexpected error occurred while retrieving the newest Product Serviced line item.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Product Ids from Repair Code WOLIs.
     * @param workOrderId Parent Work Order Id
     * @param repairCodeRtId Repair Code RecordType Id
     * @return Set of Product2 Ids
     * @throws WorkOrderLineItemsServiceException when the operation fails
     */
    public static Set<Id> getRepairCodeProductIds(Id workOrderId, Id repairCodeRtId) {
        if (workOrderId == null || repairCodeRtId == null) {
            return new Set<Id>();
        }
        try {
            return selector().selectRepairCodeProductIds(workOrderId, repairCodeRtId);
        } catch (Exception e) {
            Logger.error(
                'WorkOrderLineItemsService.getRepairCodeProductIds: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(
                'An unexpected error occurred while retrieving Repair Code Product Ids.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Reconciles Repair Code WOLIs for Device Evaluation selection.
     *              Deletes deselected / duplicate lines and creates missing selected lines.
     * @param workOrder Work Order with Asset / Parent Price Book fields populated
     * @param selectedProductIds Selected repair-code Product Ids
     * @param catalog Repair-code catalog for Line Type resolution
     * @throws WorkOrderLineItemsServiceException for business validation failures
     * @throws DmlException when underlying DML fails (unwrapped for Aura savepoints)
     */
    public static void reconcileRepairCodeWolisForDeviceEvaluation(
        WorkOrder workOrder,
        Set<Id> selectedProductIds,
        ProductRelatedMaterialsService.RepairCodeCatalog catalog
    ) {
        if (workOrder == null || workOrder.Id == null) {
            throw new WorkOrderLineItemsServiceException('Work Order is required.');
        }
        Set<Id> selectedIds = selectedProductIds == null
            ? new Set<Id>()
            : new Set<Id>(selectedProductIds);
        selectedIds.remove(null);
        if (catalog == null) {
            catalog = new ProductRelatedMaterialsService.RepairCodeCatalog();
        }

        Id repairCodeRtId = getRepairCodeRecordTypeId();
        if (repairCodeRtId == null) {
            throw new WorkOrderLineItemsServiceException(
                'Repair Code Work Order Line Item record type was not found.'
            );
        }

        List<WorkOrderLineItem> existingLines =
            getRepairCodeLinesForReconcile(workOrder.Id, repairCodeRtId);

        Map<Id, WorkOrderLineItem> existingByProductId = new Map<Id, WorkOrderLineItem>();
        List<WorkOrderLineItem> linesToDelete = new List<WorkOrderLineItem>();
        for (WorkOrderLineItem lineItem : existingLines) {
            if (lineItem.Product2Id == null || !selectedIds.contains(lineItem.Product2Id)) {
                linesToDelete.add(lineItem);
                continue;
            }
            if (existingByProductId.containsKey(lineItem.Product2Id)) {
                linesToDelete.add(lineItem);
            } else {
                existingByProductId.put(lineItem.Product2Id, lineItem);
            }
        }
        if (!linesToDelete.isEmpty()) {
            deleteLineItemsRethrowDml(new Map<Id, WorkOrderLineItem>(linesToDelete).keySet());
        }

        Set<Id> productIdsToCreate = new Set<Id>();
        for (Id productId : selectedIds) {
            if (!existingByProductId.containsKey(productId)) {
                productIdsToCreate.add(productId);
            }
        }
        if (productIdsToCreate.isEmpty()) {
            return;
        }

        Map<Id, Product2> productsById =
            ProductsService.getProductsForDeviceEvaluationByIds(productIdsToCreate);
        Product2 assetProduct = workOrder.Asset != null ? workOrder.Asset.Product2 : null;
        Id parentProductServicedWoliId = getNewestProductServicedWoliId(
            workOrder.Id,
            workOrder.AssetId
        );
        Id topLevelWorkOrderId = workOrder.ParentWorkOrderId;
        Id pricebookId = WorkOrdersService.resolvePricebookIdForDeviceEvaluation(workOrder);
        if (pricebookId == null) {
            throw new WorkOrderLineItemsServiceException(
                'Work Order must have a Price Book on the Parent Work Order ' +
                '(or on the Work Order when no Parent exists) before Repair Code lines can be created.'
            );
        }
        if (String.isBlank(workOrder.CurrencyIsoCode)) {
            throw new WorkOrderLineItemsServiceException(
                'Work Order currency is required to resolve Price Book Entries for Repair Code lines.'
            );
        }
        Map<Id, Id> pricebookEntryIdsByProductId =
            PricebookEntriesService.getPricebookEntryIdsByProductId(
                pricebookId,
                productIdsToCreate,
                workOrder.CurrencyIsoCode
            );

        List<WorkOrderLineItem> linesToInsert = new List<WorkOrderLineItem>();
        for (Id productId : productIdsToCreate) {
            Product2 selectedProduct = productsById.get(productId);
            if (selectedProduct == null) {
                throw new WorkOrderLineItemsServiceException(
                    'A selected repair code product could not be loaded.'
                );
            }
            String lineType = resolveLineType(productId, catalog, selectedProduct);
            if (String.isBlank(lineType)) {
                throw new WorkOrderLineItemsServiceException(
                    'Unable to determine Line Type for product ' + selectedProduct.ProductCode + '.'
                );
            }
            Id pricebookEntryId = pricebookEntryIdsByProductId.get(productId);
            if (pricebookEntryId == null) {
                throw new WorkOrderLineItemsServiceException(
                    'No active Price Book Entry was found for product ' +
                    selectedProduct.ProductCode +
                    ' matching the Parent Work Order Price Book and Work Order currency. ' +
                    'Add an active entry and try again.'
                );
            }

            WorkOrderLineItem newLine = new WorkOrderLineItem();
            newLine.RecordTypeId = repairCodeRtId;
            newLine.WorkOrderId = workOrder.Id;
            newLine.AssetId = workOrder.AssetId;
            newLine.Status = resolveRepairCodeWoliStatus(workOrder);
            newLine.LineType__c = lineType;
            newLine.SerialNumber__c =
                workOrder.Asset != null ? workOrder.Asset.SerialNumber : null;
            newLine.Model__c = assetProduct != null ? assetProduct.Model__c : null;
            newLine.Item__c = workOrder.Asset != null ? workOrder.Asset.Product2Id : null;
            newLine.ItemCode__c = assetProduct != null ? assetProduct.ProductCode : null;
            newLine.ItemDescription__c = assetProduct != null
                ? (String.isNotBlank(assetProduct.Description)
                    ? assetProduct.Description
                    : assetProduct.Name)
                : null;
            newLine.RepairCode__c = selectedProduct.Id;
            newLine.ProductCodeWoli__c = selectedProduct.ProductCode;
            newLine.ProductDescription__c = String.isNotBlank(selectedProduct.Description)
                ? selectedProduct.Description
                : selectedProduct.Name;
            newLine.PricebookEntryId = pricebookEntryId;
            newLine.Quantity = 1;
            newLine.TopLevelWorkOrder__c = topLevelWorkOrderId;
            newLine.ParentWorkOrderLineItemId = parentProductServicedWoliId;
            if (lineType == COMPONENT_TYPE_OBSERVATION_CODE) {
                newLine.ObservationCodeCondition__c = selectedProduct.Condition__c;
            }
            linesToInsert.add(newLine);
        }
        if (!linesToInsert.isEmpty()) {
            createLineItemsRethrowDml(linesToInsert);
        }
    }

    /**
     * @description GW-3400 - Creates a Product Serviced line and child Repair Code lines.
     *              Child quantities match the Product Serviced quantity. Observation codes are not created.
     * @param workOrder Parent Work Order with Price Book and currency populated
     * @param productId Selected instrument Product2 Id
     * @param quantity Product Serviced quantity
     * @param repairCodeProductIds Selected category/service Product Ids
     * @return Created Product Serviced WorkOrderLineItem Id
     * @throws WorkOrderLineItemsServiceException for validation or unexpected failures
     */
    public static Id persistInstrumentEvaluationItem(
        WorkOrder workOrder,
        Id productId,
        Decimal quantity,
        List<Id> repairCodeProductIds
    ) {
        return persistInstrumentEvaluationItem(
            workOrder,
            productId,
            quantity,
            repairCodeProductIds,
            null
        );
    }

    /**
     * @description GW-5324 - Creates an Instrument Evaluation item with mapped RO Line numbers.
     * @param workOrder Parent Work Order with Price Book and currency populated
     * @param productId Selected instrument Product2 Id
     * @param quantity Product Serviced quantity
     * @param repairCodeProductIds Selected repair-code Product Ids
     * @param returnOrderLineItems Comma-separated Return Order Line Item numbers
     * @return Created Product Serviced WorkOrderLineItem Id
     */
    public static Id persistInstrumentEvaluationItem(
        WorkOrder workOrder,
        Id productId,
        Decimal quantity,
        List<Id> repairCodeProductIds,
        String returnOrderLineItems
    ) {
        Logger.setScenario('Instrument Evaluation');
        try {
            if (workOrder == null || workOrder.Id == null) {
                throw new WorkOrderLineItemsServiceException('Work Order is required.');
            }
            if (productId == null) {
                throw new WorkOrderLineItemsServiceException('Product is required.');
            }
            Decimal resolvedQuantity = quantity == null ? 1 : quantity;
            if (resolvedQuantity <= 0) {
                throw new WorkOrderLineItemsServiceException('Quantity must be greater than zero.');
            }

            Id productServicedRtId = getProductServicedRecordTypeId();
            if (productServicedRtId == null) {
                throw new WorkOrderLineItemsServiceException(
                    'Product Serviced Work Order Line Item record type was not found.'
                );
            }
            Id repairCodeRtId = getRepairCodeRecordTypeId();
            if (repairCodeRtId == null) {
                throw new WorkOrderLineItemsServiceException(
                    'Repair Code Work Order Line Item record type was not found.'
                );
            }

            Set<Id> selectedRepairCodeIds = new Set<Id>();
            if (repairCodeProductIds != null) {
                selectedRepairCodeIds.addAll(repairCodeProductIds);
            }
            selectedRepairCodeIds.remove(null);

            Set<Id> productsToLoad = new Set<Id>{ productId };
            productsToLoad.addAll(selectedRepairCodeIds);
            Map<Id, Product2> productsById =
                ProductsService.getProductsForDeviceEvaluationByIds(productsToLoad);
            Product2 instrumentProduct = productsById.get(productId);
            if (instrumentProduct == null) {
                throw new WorkOrderLineItemsServiceException(
                    'The selected instrument product could not be loaded.'
                );
            }

            ProductRelatedMaterialsService.RepairCodeCatalog catalog =
                ProductRelatedMaterialsService.buildInstrumentEvaluationCatalog(productId);

            WorkOrderLineItem productServicedLine = buildInstrumentEvaluationProductServicedLine(
                workOrder,
                instrumentProduct,
                productServicedRtId,
                resolvedQuantity,
                returnOrderLineItems
            );
            createLineItems(new List<WorkOrderLineItem>{ productServicedLine });

            if (!selectedRepairCodeIds.isEmpty()) {
                List<WorkOrderLineItem> repairCodeLines = buildInstrumentEvaluationRepairCodeLines(
                    workOrder,
                    instrumentProduct,
                    productServicedLine.Id,
                    repairCodeRtId,
                    selectedRepairCodeIds,
                    productsById,
                    catalog,
                    resolvedQuantity
                );
                if (!repairCodeLines.isEmpty()) {
                    createLineItems(repairCodeLines);
                }
            }
            return productServicedLine.Id;
        } catch (WorkOrderLineItemsServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrderLineItemsService.persistInstrumentEvaluationItem failed for {0}: {1}',
                    workOrder == null ? null : workOrder.Id,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrderLineItemsServiceException(
                'An unexpected error occurred while saving the Instrument Evaluation item.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3400 - Updates quantity on the Product Serviced line and its child Repair
     *              Code lines, and adds any missing repair-code WOLIs (used when Item Summary
     *              edits are Quick Saved).
     * @param workOrder Parent Work Order
     * @param productServicedId Existing Product Serviced WOLI Id
     * @param productId Instrument Product2 Id (must match the Product Serviced line)
     * @param quantity Updated quantity
     * @param repairCodeProductIds Desired repair-code Product Ids (existing codes are kept)
     * @return The Product Serviced Id
     * @throws WorkOrderLineItemsServiceException for validation or unexpected failures
     */
    public static Id syncInstrumentEvaluationItem(
        WorkOrder workOrder,
        Id productServicedId,
        Id productId,
        Decimal quantity,
        List<Id> repairCodeProductIds
    ) {
        return syncInstrumentEvaluationItem(
            workOrder,
            productServicedId,
            productId,
            quantity,
            repairCodeProductIds,
            null
        );
    }

    /**
     * @description GW-5324 - Updates an Instrument Evaluation item and its RO Line mapping.
     * @param workOrder Parent Work Order
     * @param productServicedId Existing Product Serviced WOLI Id
     * @param productId Instrument Product2 Id
     * @param quantity Updated quantity
     * @param repairCodeProductIds Desired repair-code Product Ids
     * @param returnOrderLineItems Comma-separated Return Order Line Item numbers; null keeps current
     * @return Product Serviced WOLI Id
     */
    public static Id syncInstrumentEvaluationItem(
        WorkOrder workOrder,
        Id productServicedId,
        Id productId,
        Decimal quantity,
        List<Id> repairCodeProductIds,
        String returnOrderLineItems
    ) {
        Logger.setScenario('Instrument Evaluation');
        try {
            if (workOrder == null || workOrder.Id == null) {
                throw new WorkOrderLineItemsServiceException('Work Order is required.');
            }
            if (productServicedId == null) {
                throw new WorkOrderLineItemsServiceException(
                    'Product Serviced line is required to update an evaluation item.'
                );
            }
            if (productId == null) {
                throw new WorkOrderLineItemsServiceException('Product is required.');
            }
            Decimal resolvedQuantity = quantity == null ? 1 : quantity;
            if (resolvedQuantity <= 0) {
                throw new WorkOrderLineItemsServiceException('Quantity must be greater than zero.');
            }

            Id productServicedRtId = getProductServicedRecordTypeId();
            Id repairCodeRtId = getRepairCodeRecordTypeId();
            if (productServicedRtId == null || repairCodeRtId == null) {
                throw new WorkOrderLineItemsServiceException(
                    'Instrument Evaluation Work Order Line Item record types were not found.'
                );
            }

            List<WorkOrderLineItem> existingLines = selector().selectInstrumentEvaluationLines(
                workOrder.Id,
                productServicedRtId,
                repairCodeRtId
            );
            WorkOrderLineItem productServicedLine = null;
            Set<Id> existingRepairCodeProductIds = new Set<Id>();
            List<WorkOrderLineItem> existingRepairCodeLines = new List<WorkOrderLineItem>();
            for (WorkOrderLineItem lineItem : existingLines) {
                if (lineItem.Id == productServicedId) {
                    productServicedLine = lineItem;
                    continue;
                }
                if (
                    lineItem.ParentWorkOrderLineItemId == productServicedId &&
                    lineItem.RecordTypeId == repairCodeRtId
                ) {
                    existingRepairCodeLines.add(lineItem);
                    if (lineItem.Product2Id != null) {
                        existingRepairCodeProductIds.add(lineItem.Product2Id);
                    }
                }
            }
            if (productServicedLine == null) {
                throw new WorkOrderLineItemsServiceException(
                    'The Product Serviced line to update was not found on this Work Order.'
                );
            }
            Id existingProductId = productServicedLine.Product2Id;
            if (existingProductId != null && existingProductId != productId) {
                throw new WorkOrderLineItemsServiceException(
                    'The Product Serviced line product does not match the draft item.'
                );
            }

            Boolean quantityChanged =
                productServicedLine.Quantity == null ||
                productServicedLine.Quantity != resolvedQuantity;
            Boolean returnOrderLinesChanged =
                returnOrderLineItems != null &&
                productServicedLine.ReturnOrderLineItems__c != returnOrderLineItems;
            List<WorkOrderLineItem> linesToUpdate = new List<WorkOrderLineItem>();
            if (quantityChanged || returnOrderLinesChanged) {
                productServicedLine.Quantity = resolvedQuantity;
                if (returnOrderLineItems != null) {
                    productServicedLine.ReturnOrderLineItems__c = returnOrderLineItems;
                }
                linesToUpdate.add(productServicedLine);
            }
            if (quantityChanged) {
                for (WorkOrderLineItem repairCodeLine : existingRepairCodeLines) {
                    if (
                        repairCodeLine.Quantity == null ||
                        repairCodeLine.Quantity != resolvedQuantity
                    ) {
                        repairCodeLine.Quantity = resolvedQuantity;
                        linesToUpdate.add(repairCodeLine);
                    }
                }
            }
            if (!linesToUpdate.isEmpty()) {
                updateLineItems(linesToUpdate);
            }

            Set<Id> selectedRepairCodeIds = new Set<Id>();
            if (repairCodeProductIds != null) {
                selectedRepairCodeIds.addAll(repairCodeProductIds);
            }
            selectedRepairCodeIds.remove(null);
            selectedRepairCodeIds.removeAll(existingRepairCodeProductIds);
            if (selectedRepairCodeIds.isEmpty()) {
                return productServicedId;
            }

            Set<Id> productsToLoad = new Set<Id>{ productId };
            productsToLoad.addAll(selectedRepairCodeIds);
            Map<Id, Product2> productsById =
                ProductsService.getProductsForDeviceEvaluationByIds(productsToLoad);
            Product2 instrumentProduct = productsById.get(productId);
            if (instrumentProduct == null) {
                throw new WorkOrderLineItemsServiceException(
                    'The selected instrument product could not be loaded.'
                );
            }
            ProductRelatedMaterialsService.RepairCodeCatalog catalog =
                ProductRelatedMaterialsService.buildInstrumentEvaluationCatalog(productId);
            List<WorkOrderLineItem> repairCodeLines = buildInstrumentEvaluationRepairCodeLines(
                workOrder,
                instrumentProduct,
                productServicedId,
                repairCodeRtId,
                selectedRepairCodeIds,
                productsById,
                catalog,
                resolvedQuantity
            );
            if (!repairCodeLines.isEmpty()) {
                createLineItems(repairCodeLines);
            }
            return productServicedId;
        } catch (WorkOrderLineItemsServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrderLineItemsService.syncInstrumentEvaluationItem failed for {0}: {1}',
                    workOrder == null ? null : workOrder.Id,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrderLineItemsServiceException(
                'An unexpected error occurred while updating the Instrument Evaluation item.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3400 - Loads Product Serviced and Repair Code lines for Instrument Evaluation.
     * @param workOrderId Parent Work Order Id
     * @return Matching WorkOrderLineItem records
     * @throws WorkOrderLineItemsServiceException when the operation fails
     */
    public static List<WorkOrderLineItem> getInstrumentEvaluationLines(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WorkOrderLineItem>();
        }
        try {
            Id productServicedRtId = getProductServicedRecordTypeId();
            Id repairCodeRtId = getRepairCodeRecordTypeId();
            if (productServicedRtId == null || repairCodeRtId == null) {
                return new List<WorkOrderLineItem>();
            }
            return selector().selectInstrumentEvaluationLines(
                workOrderId,
                productServicedRtId,
                repairCodeRtId
            );
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrderLineItemsService.getInstrumentEvaluationLines failed for {0}: {1}',
                    workOrderId,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrderLineItemsServiceException(
                'An unexpected error occurred while loading Instrument Evaluation items.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3400 - Removes Product Serviced lines omitted from the draft snapshot,
     *              including child Repair Code lines, linked WREs, and vendor WO adjustments.
     * @param workOrderId Parent Work Order Id
     * @param retainedProductServicedIds Product Serviced WOLI Ids still on the evaluation
     */
    public static void reconcileInstrumentEvaluationRemovedLines(
        Id workOrderId,
        Set<Id> retainedProductServicedIds
    ) {
        if (workOrderId == null) {
            return;
        }
        Logger.setScenario('Instrument Evaluation');
        try {
            Set<Id> retainedIds = retainedProductServicedIds == null
                ? new Set<Id>()
                : new Set<Id>(retainedProductServicedIds);
            retainedIds.remove(null);

            Id productServicedRtId = getProductServicedRecordTypeId();
            if (productServicedRtId == null) {
                return;
            }

            List<WorkOrderLineItem> existingProductServicedLines =
                WorkOrderLineItemsSelector.selectProductServicedIdsByWorkOrder(
                    workOrderId,
                    productServicedRtId
                );
            for (WorkOrderLineItem lineItem : existingProductServicedLines) {
                if (lineItem.Id != null && !retainedIds.contains(lineItem.Id)) {
                    deleteInstrumentEvaluationItem(lineItem.Id);
                }
            }
        } catch (WorkOrderLineItemsServiceException e) {
            throw e;
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw new WorkOrderLineItemsServiceException(e.getMessage(), e);
        } catch (WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException e) {
            throw new WorkOrderLineItemsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrderLineItemsService.reconcileInstrumentEvaluationRemovedLines failed for {0}: {1}',
                    workOrderId,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrderLineItemsServiceException(
                'An unexpected error occurred while removing Instrument Evaluation items.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3400 - Deletes an Instrument Evaluation Product Serviced line and dependents.
     * @param productServicedId Product Serviced Work Order Line Item Id
     */
    public static void deleteInstrumentEvaluationItem(Id productServicedId) {
        if (productServicedId == null) {
            return;
        }
        Logger.setScenario('Instrument Evaluation');
        try {
            assertInstrumentEvaluationItemDeletable(productServicedId);
            WarrantyRepairEvaluationsService.assertNoEvaluationsLinkedToWorkOrderLineItems(
                new Set<Id>{ productServicedId }
            );
            WorkOrdersService.clearVendorFromInstrumentEvaluationLine(productServicedId);

            Id repairCodeRtId = getRepairCodeRecordTypeId();
            Set<Id> repairCodeLineIds = new Set<Id>();
            if (repairCodeRtId != null) {
                for (WorkOrderLineItem repairCodeLine :
                    WorkOrderLineItemsSelector.selectRepairCodeIdsByParent(
                        productServicedId,
                        repairCodeRtId
                    )
                ) {
                    repairCodeLineIds.add(repairCodeLine.Id);
                }
            }

            if (!repairCodeLineIds.isEmpty()) {
                deleteRepairCenterTeamMembersForLineItems(repairCodeLineIds);
                deleteLineItems(repairCodeLineIds);
            }
            deleteLineItems(new Set<Id>{ productServicedId });
        } catch (WorkOrderLineItemsServiceException e) {
            throw e;
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw new WorkOrderLineItemsServiceException(e.getMessage(), e);
        } catch (WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException e) {
            throw new WorkOrderLineItemsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrderLineItemsService.deleteInstrumentEvaluationItem failed for {0}: {1}',
                    productServicedId,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrderLineItemsServiceException(
                'An unexpected error occurred while deleting the Instrument Evaluation item.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Blocks delete of the default Product Serviced line on asset Instrument WOs.
     * @param productServicedId Product Serviced Work Order Line Item Id
     */
    @TestVisible
    private static void assertInstrumentEvaluationItemDeletable(Id productServicedId) {
        if (productServicedId == null) {
            return;
        }
        List<WorkOrderLineItem> lines =
            WorkOrderLineItemsSelector.selectWithWorkOrderAssetById(productServicedId);
        if (lines.isEmpty()) {
            return;
        }
        if (lines[0].WorkOrder != null && lines[0].WorkOrder.AssetId != null) {
            throw new WorkOrderLineItemsServiceException(
                'This item cannot be deleted because the Work Order has an Asset.'
            );
        }
    }

    /**
     * @description Removes Work Performed signatures tied to deleted Repair Code WOLIs.
     * @param lineItemIds Repair Code Work Order Line Item Ids
     */
    private static void deleteRepairCenterTeamMembersForLineItems(Set<Id> lineItemIds) {
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            return;
        }
        List<RepairCenterTeamMember__c> signatures =
            RepairCenterTeamMembersSelector.selectIdsByWorkOrderLineItemIds(lineItemIds);
        if (!signatures.isEmpty()) {
            delete signatures;
        }
    }

    /**
     * @description GW-3400 - Product Serviced RecordType Id for Instrument Evaluation.
     * @return RecordType Id or null when unavailable
     */
    public static Id getProductServicedRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> infos =
            Schema.SObjectType.WorkOrderLineItem.getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo info = infos.get(WOLI_RECORD_TYPE_PRODUCT_SERVICED);
        return info == null ? null : info.getRecordTypeId();
    }

    /**
     * @description GW-3913 / GW-3096 - Repair Code RecordType Id for Device Evaluation.
     * @return RecordType Id or null when unavailable
     */
    public static Id getRepairCodeRecordTypeId() {
        if (repairCodeRecordTypeIdOverride != null) {
            return repairCodeRecordTypeIdOverride;
        }
        Map<String, Schema.RecordTypeInfo> infos =
            Schema.SObjectType.WorkOrderLineItem.getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo info = infos.get(WOLI_RECORD_TYPE_REPAIR_CODE);
        return info == null ? null : info.getRecordTypeId();
    }

    /**
     * @description Repair Code WOLI Status from Work Order Estimate Required on create.
     */
    @TestVisible
    private static String resolveRepairCodeWoliStatus(WorkOrder workOrder) {
        if (workOrder != null && ESTIMATE_REQUIRED_VALUE.equals(workOrder.EstimateRequired__c)) {
            return WOLI_STATUS_WAITING_APPROVAL;
        }
        return WOLI_STATUS_APPROVED;
    }

    /**
     * @description Resolves Line Type for a selected repair-code Product.
     */
    @TestVisible
    private static String resolveLineType(
        Id productId,
        ProductRelatedMaterialsService.RepairCodeCatalog catalog,
        Product2 product
    ) {
        if (catalog != null && catalog.categoryCodeIds.contains(productId)) {
            if (
                product != null &&
                PRICING_CODE_COMPONENT_TYPES.contains(product.ProductType__c)
            ) {
                return product.ProductType__c;
            }
            return COMPONENT_TYPE_CATEGORY_CODE;
        }
        if (catalog != null && catalog.observationCodeIds.contains(productId)) {
            return COMPONENT_TYPE_OBSERVATION_CODE;
        }
        if (catalog != null && catalog.serviceCodeIds.contains(productId)) {
            return COMPONENT_TYPE_SERVICE_CODE;
        }
        return product != null ? product.ProductType__c : null;
    }

    private static Id getNewestProductServicedWoliId(Id workOrderId, Id assetId) {
        if (workOrderId == null || assetId == null) {
            return null;
        }
        Id productServicedRtId = getProductServicedRecordTypeId();
        if (productServicedRtId == null) {
            return null;
        }
        return getNewestProductServicedId(workOrderId, assetId, productServicedRtId);
    }

    /**
     * @description GW-3400 / GW-3938 - Builds Product Serviced WOLI for Instrument Evaluation
     *              using On Save/Completion mapping (plus DE asset-path clarifications).
     */
    private static WorkOrderLineItem buildInstrumentEvaluationProductServicedLine(
        WorkOrder workOrder,
        Product2 instrumentProduct,
        Id productServicedRtId,
        Decimal quantity,
        String returnOrderLineItems
    ) {
        // GW-3938 #11 - Price Book Entry from WO.Price Book + Item + currency.
        Id pricebookId = workOrder.Pricebook2Id;
        Id pricebookEntryId = null;
        if (pricebookId != null && String.isNotBlank(workOrder.CurrencyIsoCode)) {
            Map<Id, Id> pricebookEntryIdsByProductId =
                PricebookEntriesService.getPricebookEntryIdsByProductId(
                    pricebookId,
                    new Set<Id>{ instrumentProduct.Id },
                    workOrder.CurrencyIsoCode
                );
            pricebookEntryId = pricebookEntryIdsByProductId.get(instrumentProduct.Id);
        }

        WorkOrderLineItem productServicedLine = new WorkOrderLineItem();
        // #4 Record Type / #5 Line Type
        productServicedLine.RecordTypeId = productServicedRtId;
        productServicedLine.LineType__c = WOLI_LINE_TYPE_PRODUCT_SERVICED;
        // GW-5328 - Product Line is always INSTRUMENT for IE Product Serviced lines.
        productServicedLine.ProductLine__c = WOLI_PRODUCT_LINE_INSTRUMENT;
        // #2 Work Order
        productServicedLine.WorkOrderId = workOrder.Id;
        // #1 Top Level Work Order = WO.Parent Work Order (no self fallback per GW-3938)
        productServicedLine.TopLevelWorkOrder__c = workOrder.ParentWorkOrderId;
        // Return Order / Return Order Line Item intentionally not mapped (future sprint).
        // #6 Subject / #7 Description
        productServicedLine.Subject = workOrder.Subject;
        productServicedLine.Description = workOrder.Description;
        // Asset path: WO.Model (DE mapping). No matching asset: Item.Model (GW-3938 #8).
        Boolean attachAsset = assetMatchesInstrumentProduct(workOrder, instrumentProduct.Id);
        productServicedLine.Model__c = attachAsset
            ? workOrder.Model__c
            : instrumentProduct.Model__c;
        // #9 Tray Name
        productServicedLine.TrayName__c = workOrder.TrayName__c;
        // #10 Quantity
        productServicedLine.Quantity = quantity;
        productServicedLine.ReturnOrderLineItems__c = returnOrderLineItems;
        /*
         * #11 / #12 - Quantity requires a product (PBE or Product2Id).
         * Prefer PricebookEntryId (GW-3938). With AssetId, do not also set Product2Id
         * (FIELD_INTEGRITY_EXCEPTION); PBE for the same product is safe with Asset (receiving).
         */
        if (pricebookEntryId != null) {
            productServicedLine.PricebookEntryId = pricebookEntryId;
        } else {
            productServicedLine.Product2Id = instrumentProduct.Id;
        }
        // #13 Product Code / #14 Product Description
        productServicedLine.ProductCodeWoli__c = instrumentProduct.ProductCode;
        productServicedLine.ProductDescription__c = instrumentProduct.Description;
        // #15 Status
        productServicedLine.Status = resolveRepairCodeWoliStatus(workOrder);

        // Stamp Asset only when it is the item product AND PBE supplies Product2Id.
        // Asset + Product2Id together is rejected; Asset alone fails Quantity validation.
        if (attachAsset && pricebookEntryId != null) {
            productServicedLine.AssetId = workOrder.AssetId;
            productServicedLine.SerialNumber__c = workOrder.Asset.SerialNumber;
        }
        return productServicedLine;
    }

    /**
     * @description True when the Work Order Asset is the same Product2 as the IE instrument item.
     * @param workOrder Parent Work Order
     * @param instrumentProductId Selected instrument Product2 Id
     * @return Whether AssetId may be stamped on the Product Serviced / Repair Code line
     */
    private static Boolean assetMatchesInstrumentProduct(WorkOrder workOrder, Id instrumentProductId) {
        return workOrder != null &&
            workOrder.AssetId != null &&
            workOrder.Asset != null &&
            instrumentProductId != null &&
            workOrder.Asset.Product2Id == instrumentProductId;
    }

    private static List<WorkOrderLineItem> buildInstrumentEvaluationRepairCodeLines(
        WorkOrder workOrder,
        Product2 instrumentProduct,
        Id parentProductServicedWoliId,
        Id repairCodeRtId,
        Set<Id> selectedRepairCodeIds,
        Map<Id, Product2> productsById,
        ProductRelatedMaterialsService.RepairCodeCatalog catalog,
        Decimal quantity
    ) {
        Id pricebookId = WorkOrdersService.resolvePricebookIdForDeviceEvaluation(workOrder);
        if (pricebookId == null) {
            throw new WorkOrderLineItemsServiceException(
                'Work Order must have a Price Book on the Parent Work Order ' +
                '(or on the Work Order when no Parent exists) before Repair Code lines can be created.'
            );
        }
        if (String.isBlank(workOrder.CurrencyIsoCode)) {
            throw new WorkOrderLineItemsServiceException(
                'Work Order currency is required to resolve Price Book Entries for Repair Code lines.'
            );
        }
        Map<Id, Id> pricebookEntryIdsByProductId =
            PricebookEntriesService.getPricebookEntryIdsByProductId(
                pricebookId,
                selectedRepairCodeIds,
                workOrder.CurrencyIsoCode
            );

        List<WorkOrderLineItem> repairCodeLines = new List<WorkOrderLineItem>();
        for (Id repairCodeProductId : selectedRepairCodeIds) {
            Product2 selectedProduct = productsById.get(repairCodeProductId);
            if (selectedProduct == null) {
                throw new WorkOrderLineItemsServiceException(
                    'A selected repair code product could not be loaded.'
                );
            }
            String lineType = resolveLineType(repairCodeProductId, catalog, selectedProduct);
            if (String.isBlank(lineType) || lineType == COMPONENT_TYPE_OBSERVATION_CODE) {
                throw new WorkOrderLineItemsServiceException(
                    'Unable to determine Line Type for product ' + selectedProduct.ProductCode + '.'
                );
            }
            Id pricebookEntryId = pricebookEntryIdsByProductId.get(repairCodeProductId);
            if (pricebookEntryId == null) {
                throw new WorkOrderLineItemsServiceException(
                    'No active Price Book Entry was found for product ' +
                    selectedProduct.ProductCode +
                    ' matching the Parent Work Order Price Book and Work Order currency. ' +
                    'Add an active entry and try again.'
                );
            }

            WorkOrderLineItem repairCodeLine = new WorkOrderLineItem();
            repairCodeLine.RecordTypeId = repairCodeRtId;
            repairCodeLine.WorkOrderId = workOrder.Id;
            if (assetMatchesInstrumentProduct(workOrder, instrumentProduct.Id)) {
                repairCodeLine.AssetId = workOrder.AssetId;
                repairCodeLine.SerialNumber__c = workOrder.Asset.SerialNumber;
            }
            repairCodeLine.Status = resolveRepairCodeWoliStatus(workOrder);
            repairCodeLine.LineType__c = lineType;
            repairCodeLine.Model__c = instrumentProduct.Model__c;
            repairCodeLine.Item__c = instrumentProduct.Id;
            repairCodeLine.ItemCode__c = instrumentProduct.ProductCode;
            repairCodeLine.ItemDescription__c = String.isNotBlank(instrumentProduct.Description)
                ? instrumentProduct.Description
                : instrumentProduct.Name;
            repairCodeLine.RepairCode__c = selectedProduct.Id;
            repairCodeLine.ProductCodeWoli__c = selectedProduct.ProductCode;
            repairCodeLine.ProductDescription__c = selectedProduct.Description;
            repairCodeLine.PricebookEntryId = pricebookEntryId;
            repairCodeLine.Quantity = quantity;
            // GW-3938 - Top Level Work Order = WO.Parent Work Order
            repairCodeLine.TopLevelWorkOrder__c = workOrder.ParentWorkOrderId;
            repairCodeLine.ParentWorkOrderLineItemId = parentProductServicedWoliId;
            repairCodeLines.add(repairCodeLine);
        }
        return repairCodeLines;
    }

    private static void createLineItemsRethrowDml(List<WorkOrderLineItem> lineItems) {
        try {
            createLineItems(lineItems);
        } catch (WorkOrderLineItemsServiceException e) {
            if (e.getCause() instanceof DmlException) {
                throw (DmlException) e.getCause();
            }
            throw e;
        }
    }

    private static void deleteLineItemsRethrowDml(Set<Id> lineItemIds) {
        try {
            deleteLineItems(lineItemIds);
        } catch (WorkOrderLineItemsServiceException e) {
            if (e.getCause() instanceof DmlException) {
                throw (DmlException) e.getCause();
            }
            throw e;
        }
    }

    /**
     * @description Evaluates Allowed Unit for one Product Item on a Work Order.
     * @param workOrderId Work Order Id
     * @param productItemId Selected Product Item Id
     * @return Allowed Unit evaluation DTO
     */
    public static AllowedUnitEvaluationDTO evaluateAllowedUnit(Id workOrderId, Id productItemId) {
        if (workOrderId == null || productItemId == null) {
            return AllowedUnitEvaluationDTO.unevaluated();
        }

        Map<Id, AllowedUnitEvaluationDTO> resultByProductItemIdMap =
            evaluateAllowedUnits(workOrderId, new Set<Id>{ productItemId });
        if (resultByProductItemIdMap.containsKey(productItemId)) {
            return resultByProductItemIdMap.get(productItemId);
        }
        return AllowedUnitEvaluationDTO.unevaluated();
    }

    /**
     * @description GW-4311 - Evaluates Allowed Unit for one Product2 (Customer Stock) on a Work Order.
     * @param workOrderId Work Order Id
     * @param product2Id Selected Product2 Id
     * @return Allowed Unit evaluation DTO
     */
    public static AllowedUnitEvaluationDTO evaluateAllowedUnitByProduct(Id workOrderId, Id product2Id) {
        if (workOrderId == null || product2Id == null) {
            return AllowedUnitEvaluationDTO.unevaluated();
        }

        Map<Id, AllowedUnitEvaluationDTO> resultByProduct2IdMap =
            evaluateAllowedUnitsByProduct(workOrderId, new Set<Id>{ product2Id });
        if (resultByProduct2IdMap.containsKey(product2Id)) {
            return resultByProduct2IdMap.get(product2Id);
        }
        return AllowedUnitEvaluationDTO.unevaluated();
    }

    /**
     * @description Bulk Evaluates Allowed Unit for Product Items on a Work Order.
     * @param workOrderId Work Order Id
     * @param productItemIdSet Product Item Ids to evaluate
     * @return Map of Product Item Id to evaluation DTO
     */
    public static Map<Id, AllowedUnitEvaluationDTO> evaluateAllowedUnits(
        Id workOrderId,
        Set<Id> productItemIdSet
    ) {
        Map<Id, AllowedUnitEvaluationDTO> resultByProductItemIdMap =
            new Map<Id, AllowedUnitEvaluationDTO>();

        try {
            if (Test.isRunningTest() && simulateQueryException) {
                throw new QueryException('Simulated query failure');
            }
            if (Test.isRunningTest() && simulateGenericException) {
                throw new IllegalArgumentException('Simulated unexpected failure');
            }

            Logger.debug(
                new LogMessage(
                    'WorkOrderLineItemsService.evaluateAllowedUnits workOrderId={0} productItemCount={1}',
                    workOrderId,
                    productItemIdSet == null ? 0 : productItemIdSet.size()
                )
            );

            if (workOrderId == null || productItemIdSet == null || productItemIdSet.isEmpty()) {
                return resultByProductItemIdMap;
            }

            for (Id productItemId : productItemIdSet) {
                resultByProductItemIdMap.put(productItemId, AllowedUnitEvaluationDTO.unevaluated());
            }

            Map<Id, Id> product2IdByProductItemIdMap = mapProduct2IdsByProductItem(productItemIdSet);
            Set<Id> product2IdSet = new Set<Id>(product2IdByProductItemIdMap.values());
            Map<Id, AllowedUnitEvaluationDTO> resultByProduct2IdMap =
                evaluateAllowedUnitsByProduct(workOrderId, product2IdSet);

            Boolean resolvedHasAsset = false;
            Boolean workOrderHasAsset = false;

            for (Id productItemId : productItemIdSet) {
                Id product2Id = product2IdByProductItemIdMap.get(productItemId);
                if (product2Id == null) {
                    // Product Item has no Product2 — still respect WO Asset for DTO flags.
                    if (!resolvedHasAsset) {
                        List<WorkOrder> workOrderList =
                            WorkOrdersSelector.selectByIdsForAllowedUnit(new Set<Id>{ workOrderId });
                        workOrderHasAsset =
                            !workOrderList.isEmpty() && workOrderList[0].AssetId != null;
                        resolvedHasAsset = true;
                    }
                    resultByProductItemIdMap.put(
                        productItemId,
                        workOrderHasAsset
                            ? AllowedUnitEvaluationDTO.evaluated(false)
                            : AllowedUnitEvaluationDTO.unevaluated()
                    );
                    continue;
                }
                AllowedUnitEvaluationDTO productResult = resultByProduct2IdMap.get(product2Id);
                resultByProductItemIdMap.put(
                    productItemId,
                    productResult != null ? productResult : AllowedUnitEvaluationDTO.unevaluated()
                );
            }

            return resultByProductItemIdMap;
        } catch (WorkOrderLineItemsServiceException e) {
            throw e;
        } catch (QueryException e) {
            Logger.error('WorkOrderLineItemsService.evaluateAllowedUnits query failed', e);
            throw new WorkOrderLineItemsServiceException(
                'Failed to evaluate Allowed Unit: ' + e.getMessage(),
                e
            );
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemsService.evaluateAllowedUnits failed', e);
            throw new WorkOrderLineItemsServiceException(
                'Failed to evaluate Allowed Unit: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-4311 - Bulk Evaluates Allowed Unit for Product2 Ids on a Work Order.
     * @param workOrderId Work Order Id
     * @param product2IdSet Product2 Ids to evaluate
     * @return Map of Product2 Id to evaluation DTO
     */
    public static Map<Id, AllowedUnitEvaluationDTO> evaluateAllowedUnitsByProduct(
        Id workOrderId,
        Set<Id> product2IdSet
    ) {
        Map<Id, AllowedUnitEvaluationDTO> resultByProduct2IdMap =
            new Map<Id, AllowedUnitEvaluationDTO>();

        try {
            if (Test.isRunningTest() && simulateQueryException) {
                throw new QueryException('Simulated query failure');
            }
            if (Test.isRunningTest() && simulateGenericException) {
                throw new IllegalArgumentException('Simulated unexpected failure');
            }

            Logger.debug(
                new LogMessage(
                    'WorkOrderLineItemsService.evaluateAllowedUnitsByProduct workOrderId={0} productCount={1}',
                    workOrderId,
                    product2IdSet == null ? 0 : product2IdSet.size()
                )
            );

            if (workOrderId == null || product2IdSet == null || product2IdSet.isEmpty()) {
                return resultByProduct2IdMap;
            }

            for (Id product2Id : product2IdSet) {
                resultByProduct2IdMap.put(product2Id, AllowedUnitEvaluationDTO.unevaluated());
            }

            List<WorkOrder> workOrderList =
                WorkOrdersSelector.selectByIdsForAllowedUnit(new Set<Id>{ workOrderId });
            if (workOrderList.isEmpty() || workOrderList[0].AssetId == null) {
                Logger.debug('Allowed Unit skipped: Work Order has no Asset');
                return resultByProduct2IdMap;
            }

            WorkOrder workOrder = workOrderList[0];
            Set<Id> serviceBomIdSet = collectServiceBomIdSet(workOrder);
            if (serviceBomIdSet == null) {
                Logger.debug(
                    'Allowed Unit skipped: Root PFCL SBOM Required is not Yes'
                );
                for (Id product2Id : product2IdSet) {
                    resultByProduct2IdMap.put(
                        product2Id,
                        AllowedUnitEvaluationDTO.sbomCrossReferenceNotRequired()
                    );
                }
                return resultByProduct2IdMap;
            }

            Set<Id> allowedProduct2IdSet = new Set<Id>();

            if (!serviceBomIdSet.isEmpty() && !product2IdSet.isEmpty()) {
                List<ProductRelatedMaterial> bomComponentList =
                    ProductRelatedMaterialsSelector.selectByServiceBomAndProductComponents(
                        serviceBomIdSet,
                        product2IdSet
                    );
                for (ProductRelatedMaterial bomComponent : bomComponentList) {
                    if (bomComponent.ProductComponentId != null) {
                        allowedProduct2IdSet.add(bomComponent.ProductComponentId);
                    }
                }
            }

            for (Id product2Id : product2IdSet) {
                Boolean isAllowed = allowedProduct2IdSet.contains(product2Id);
                resultByProduct2IdMap.put(
                    product2Id,
                    AllowedUnitEvaluationDTO.evaluated(isAllowed)
                );
            }

            Logger.debug(
                new LogMessage(
                    'Allowed Unit by Product complete serviceBomCount={0} allowedProductCount={1}',
                    serviceBomIdSet.size(),
                    allowedProduct2IdSet.size()
                )
            );
            return resultByProduct2IdMap;
        } catch (QueryException e) {
            Logger.error('WorkOrderLineItemsService.evaluateAllowedUnitsByProduct query failed', e);
            throw new WorkOrderLineItemsServiceException(
                'Failed to evaluate Allowed Unit: ' + e.getMessage(),
                e
            );
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemsService.evaluateAllowedUnitsByProduct failed', e);
            throw new WorkOrderLineItemsServiceException(
                'Failed to evaluate Allowed Unit: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Builds the Allowed Parts Service BOM Id union for a Work Order Asset.
     *              When a Root PFCL is resolved and its SBOMRequired__c is not "Yes",
     *              returns null so callers skip SBOM cross-reference entirely (GW-4218).
     * @param workOrder Work Order with Asset.PFCL__c and Asset.ServiceBOM__c populated
     * @return Distinct Service BOM Ids, or null when SBOM cross-reference is not required
     */
    private static Set<Id> collectServiceBomIdSet(WorkOrder workOrder) {
        Set<Id> serviceBomIdSet = new Set<Id>();
        Set<Id> pfclIdSet = new Set<Id>();

        String assetPfcl = workOrder.Asset?.PFCL__c;
        Id versionPfclId;
        Id rootPfclId;
        PFCL__c matchedPfcl;

        if (String.isNotBlank(assetPfcl)) {
            List<PFCL__c> versionPfclList =
                PFCLsSelector.selectByAssetPfclValues(new Set<String>{ assetPfcl });
            for (PFCL__c versionPfcl : versionPfclList) {
                Boolean matchesName = assetPfcl.equals(versionPfcl.Name);
                Boolean matchesPfclNumber = assetPfcl.equals(versionPfcl.PFCL__c);
                if (matchesName || matchesPfclNumber) {
                    matchedPfcl = versionPfcl;
                    versionPfclId = versionPfcl.Id;
                    rootPfclId = versionPfcl.Parent__c;
                    break;
                }
            }
        }

        if (versionPfclId != null && rootPfclId == null) {
            rootPfclId = versionPfclId;
            versionPfclId = null;
        }

        if (rootPfclId != null && matchedPfcl != null) {
            String rootSbomRequired = matchedPfcl.Parent__c != null
                ? matchedPfcl.Parent__r.SBOMRequired__c
                : matchedPfcl.SBOMRequired__c;
            if (rootSbomRequired != 'Yes') {
                return null;
            }
        }

        if (rootPfclId != null) {
            pfclIdSet.add(rootPfclId);
        }
        if (versionPfclId != null) {
            pfclIdSet.add(versionPfclId);
        }

        if (!pfclIdSet.isEmpty()) {
            for (PFCLServiceBOM__c junction : PFCLServiceBOMsSelector.selectByPFCLId(pfclIdSet)) {
                if (junction.ServiceBOM__c != null) {
                    serviceBomIdSet.add(junction.ServiceBOM__c);
                }
            }
            for (ServiceBOM__c serviceBom : ServiceBOMsSelector.selectByPFCLId(pfclIdSet)) {
                serviceBomIdSet.add(serviceBom.Id);
            }
        }

        if (workOrder.Asset?.ServiceBOM__c != null) {
            serviceBomIdSet.add(workOrder.Asset.ServiceBOM__c);
        }

        return serviceBomIdSet;
    }

    /**
     * @description Maps Product Item Id to Product2 Id.
     * @param productItemIdSet Product Item Ids
     * @return Map of Product Item Id to Product2 Id
     */
    private static Map<Id, Id> mapProduct2IdsByProductItem(Set<Id> productItemIdSet) {
        Map<Id, Id> product2IdByProductItemIdMap = new Map<Id, Id>();
        for (ProductItem productItem : ProductItemsSelector.selectById(productItemIdSet)) {
            product2IdByProductItemIdMap.put(productItem.Id, productItem.Product2Id);
        }
        return product2IdByProductItemIdMap;
    }

    /**
     * @description GW-3600 - Loads family Work Order Line Items for Repair Center document generation.
     * @param familyRootId Top-level parent Work Order Id.
     * @return Parent and direct-child lines ordered by CreatedDate, or an empty list when the Id is null.
     */
    public static List<WorkOrderLineItem> selectForRepairCenterDocumentGeneration(Id familyRootId) {
        if (familyRootId == null) {
            return new List<WorkOrderLineItem>();
        }
        return (List<WorkOrderLineItem>) new WorkOrderLineItemsSelector()
            .selectFields(
                new List<String>{
                    'Id',
                    'LineType__c',
                    'ParentWorkOrderLineItemId',
                    'SerialNumber__c',
                    'ProductCode__c',
                    'ProductDescription__c',
                    'Status',
                    'TurnTime__c',
                    'Quantity',
                    'TotalPrice',
                    'NetTotalPrice__c',
                    'ReturnOrderLineItems__c',
                    'ObservationCodeCondition__c',
                    'WorkOrderId',
                    'WorkOrder.EvaluationNotes__c',
                    'WorkOrder.Status',
                    'WorkOrder.ActualShipDate__c',
                    'Product2.QuantityUnitOfMeasure'
                }
            )
            .whereEquals('WorkOrderId', familyRootId)
            .whereEquals('WorkOrder.ParentWorkOrderId', familyRootId)
            .withFilterLogic('1 OR 2')
            .orderBy('CreatedDate')
            .execute();
    }

    /**
     * @description GW-4117 - Loads Work Order Line Items used to stamp Repair Center product lines.
     * @param lineItemIds Work Order Line Item Ids.
     * @return Matching lines, or an empty list when no Ids are provided.
     */
    public static List<WorkOrderLineItem> selectForRepairCenterPreApproval(Set<Id> lineItemIds) {
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            return new List<WorkOrderLineItem>();
        }
        SoqlQueryBuilder query = new WorkOrderLineItemsSelector()
            .selectFields(
                new List<String>{
                    'Id',
                    'ProductLine__c',
                    'PricebookEntry.Product2.ProductLine__c'
                }
            );
        List<String> idFilterNumbers = new List<String>();
        Integer filterNumber = 1;
        for (Id lineItemId : lineItemIds) {
            if (lineItemId == null) {
                continue;
            }
            query.whereEquals('Id', lineItemId);
            idFilterNumbers.add(String.valueOf(filterNumber));
            filterNumber++;
        }
        if (idFilterNumbers.isEmpty()) {
            return new List<WorkOrderLineItem>();
        }
        if (idFilterNumbers.size() > 1) {
            query.withFilterLogic(String.join(idFilterNumbers, ' OR '));
        }
        return (List<WorkOrderLineItem>) query.execute();
    }

    /**
     * @description Thrown when a Work Order Line Item service operation fails.
     */
    /**
     * @description GW-5497 - Returns Product Serviced WOLIs eligible to default on an NCR.
     * @param workOrderId Work Order Id
     * @param assetId Work Order Asset Id
     * @return Matching WOLIs
     */
    public static List<WorkOrderLineItem> getQualityInspectionProductServiced(
        Id workOrderId,
        Id assetId
    ) {
        Id productServicedRtId = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get(WOLI_RECORD_TYPE_PRODUCT_SERVICED)
            .getRecordTypeId();
        return selector().selectQualityInspectionProductServiced(
            workOrderId,
            assetId,
            productServicedRtId
        );
    }

    /**
     * @description Product, asset, and quantity values for a Product Serviced line created
     *              during receiving. The receiving process maps its own payload into this type.
     */
    public class ReceivingProductServicedInput {
        public Id product2Id;
        public Id assetId;
        public String serialNumber;
        public String model;
        public Decimal quantityReceived;
    }

    /**
     * @description Accessory values for a Product Serviced accessory line created during receiving.
     */
    public class ReceivingAccessoryInput {
        public String accessoryType;
        public String storageLocation;
        public String condition;
        public Decimal quantity;
    }

    /**
     * @description GW-5492 - Creates Product Serviced WOLI for a receiving Work Order.
     * @param workOrderId Child or vendor Work Order Id
     * @param topLevelWorkOrderId Parent / top-level Work Order Id
     * @param returnOrderId Return Order Id
     * @param lineItem Source ROLI (nullable for ad hoc)
     * @param request Product and quantity values from receiving
     * @return Created WOLI Id or null
     */
    public static Id createReceivingProductServicedLine(
        Id workOrderId,
        Id topLevelWorkOrderId,
        Id returnOrderId,
        ReturnOrderLineItem lineItem,
        ReceivingProductServicedInput request
    ) {
        if (workOrderId == null) {
            return null;
        }
        Id product2Id = lineItem != null ? lineItem.Product2Id : null;
        if (product2Id == null && request != null) {
            product2Id = request.product2Id;
        }
        if (product2Id == null) {
            return null;
        }
        Id productServicedRtId = getProductServicedRecordTypeId();
        if (productServicedRtId == null) {
            throw new WorkOrderLineItemsServiceException(
                'Product Serviced work order line item record type is not available.'
            );
        }

        Product2 productDetails = resolveProductDetails(product2Id);
        WorkOrder pricedWorkOrder = loadReceivingWorkOrderPricebook(workOrderId);
        Id pricebookEntryId = resolvePricebookEntryId(
            resolveReceivingLinePricebookId(pricedWorkOrder),
            product2Id,
            resolveReceivingLineCurrency(pricedWorkOrder)
        );

        WorkOrderLineItem woli = new WorkOrderLineItem();
        woli.WorkOrderId = workOrderId;
        woli.TopLevelWorkOrder__c = topLevelWorkOrderId;
        woli.RecordTypeId = productServicedRtId;
        woli.LineType__c = WOLI_LINE_TYPE_PRODUCT_SERVICED;
        woli.Quantity = resolveReceivingProductServicedQuantity(lineItem, request);
        if (pricebookEntryId != null) {
            woli.PricebookEntryId = pricebookEntryId;
        } else if (pricedWorkOrder == null || pricedWorkOrder.Pricebook2Id == null) {
            woli.Product2Id = product2Id;
        } else {
            throw new WorkOrderLineItemsServiceException(
                'This product has no price book entry, so the work order line could not be created.'
            );
        }
        if (lineItem != null) {
            woli.ReturnOrderLineItemId = lineItem.Id;
            woli.AssetId = lineItem.AssetId;
            woli.SerialNumber__c = lineItem.SerialNumber__c;
            woli.Model__c = lineItem.Model__c;
            woli.TrayName__c = lineItem.HospitalReferencedTrayName__c;
            woli.ReturnOrderLineItems__c = lineItem.ReturnOrderLineItemNumber;
            woli.ProductLine__c = lineItem.ProductLine__c;
            woli.ModRequest__c = lineItem.ModRequest__c == true;
            woli.IsPriorityRepair__c = lineItem.IsPriorityRepair__c == true;
        } else if (request != null) {
            woli.AssetId = request.assetId;
            woli.SerialNumber__c = request.serialNumber;
            woli.Model__c = request.model;
        }
        if (productDetails != null) {
            woli.ProductCodeWoli__c = productDetails.ProductCode;
            woli.ProductDescription__c = productDetails.Description;
        }
        woli.Status = resolveReceivingProductServicedStatus(lineItem, pricedWorkOrder);
        try {
            Database.insert(new List<WorkOrderLineItem>{ woli }, AccessLevel.USER_MODE);
        } catch (DmlException e) {
            Logger.error(
                'WorkOrderLineItemsService.createReceivingProductServicedLine: DML error.',
                e
            );
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(
                e.getNumDml() > 0 ? e.getDmlMessage(0) : e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
        return woli.Id;
    }

    /**
     * @description GW-5492 - Creates accessory Product Serviced WOLIs.
     *              Copies Asset, Serial Number, and Model from the child Work Order.
     * @param workOrderId Work Order Id
     * @param parentWoliId Parent Product Serviced WOLI Id
     * @param product2Id Product Id for Item lookup
     * @param accessories Accessory inputs
     */
    public static void createReceivingAccessoryLines(
        Id workOrderId,
        Id parentWoliId,
        Id product2Id,
        List<ReceivingAccessoryInput> accessories
    ) {
        if (
            workOrderId == null ||
            accessories == null ||
            accessories.isEmpty()
        ) {
            return;
        }
        Id productServicedRtId = getProductServicedRecordTypeId();
        if (productServicedRtId == null) {
            return;
        }
        Product2 productDetails = resolveProductDetails(product2Id);
        WorkOrder pricedWorkOrder = loadReceivingWorkOrderPricebook(workOrderId);
        Id pricebookEntryId = resolvePricebookEntryId(
            resolveReceivingLinePricebookId(pricedWorkOrder),
            product2Id,
            resolveReceivingLineCurrency(pricedWorkOrder)
        );
        List<WorkOrderLineItem> lines = new List<WorkOrderLineItem>();
        for (ReceivingAccessoryInput accessory : accessories) {
            if (
                accessory == null ||
                String.isBlank(accessory.accessoryType) ||
                String.isBlank(accessory.storageLocation)
            ) {
                continue;
            }
            WorkOrderLineItem woli = new WorkOrderLineItem();
            woli.WorkOrderId = workOrderId;
            woli.RecordTypeId = productServicedRtId;
            woli.LineType__c = 'Accessory';
            woli.IsAccessory__c = true;
            woli.AccessoryType__c = accessory.accessoryType.trim();
            woli.StorageLocation__c = accessory.storageLocation.trim();
            if (String.isNotBlank(accessory.condition)) {
                woli.Condition__c = accessory.condition.trim();
            }
            Decimal quantity = accessory.quantity != null && accessory.quantity > 0
                ? accessory.quantity
                : 1;
            woli.UnitQty__c = quantity;
            woli.Quantity = quantity;
            if (pricebookEntryId != null) {
                woli.PricebookEntryId = pricebookEntryId;
            }
            if (parentWoliId != null) {
                woli.ParentWorkOrderLineItemId = parentWoliId;
            }
            if (product2Id != null) {
                woli.Item__c = product2Id;
            }
            if (productDetails != null) {
                woli.ItemCode__c = productDetails.ProductCode;
                woli.ItemDescription__c = productDetails.Description;
            }
            if (pricedWorkOrder != null) {
                woli.AssetId = pricedWorkOrder.AssetId;
                woli.SerialNumber__c = pricedWorkOrder.SerialNumber__c;
                woli.Model__c = pricedWorkOrder.Model__c;
            }
            lines.add(woli);
        }
        if (!lines.isEmpty()) {
            try {
                Database.insert(lines, AccessLevel.USER_MODE);
            } catch (DmlException e) {
                Logger.error(
                    'WorkOrderLineItemsService.createReceivingAccessoryLines: DML error.',
                    e
                );
                Logger.saveLog();
                throw new WorkOrderLineItemsServiceException(
                    e.getNumDml() > 0 ? e.getDmlMessage(0) : e.getMessage(),
                    e
                );
            } finally {
                Logger.saveLog();
            }
        }
    }

    /**
     * @description GW-5968 - Creates the Disinfection Service Code (Repair Code) line for a
     *              Receiving Rerun Resi-Test. Caller resolves the Disinfection Product;
     *              this method owns WOLI insert and Price Book Entry resolution.
     * @param workOrderId Scanned Work Order Id
     * @param productServicedWoliId Product Serviced WOLI Id (parent of the new line)
     * @param quantity Quantity received (defaults to 1 when blank or not positive)
     * @param disinfectionProduct Active Disinfection Product2 resolved by the caller
     * @return Created Disinfection WOLI Id
     * @throws WorkOrderLineItemsServiceException when the product, Price Book Entry, or insert fails
     */
    public static Id createReceivingDisinfectionCodeLine(
        Id workOrderId,
        Id productServicedWoliId,
        Decimal quantity,
        Product2 disinfectionProduct
    ) {
        if (workOrderId == null) {
            throw new WorkOrderLineItemsServiceException('Work Order is required.');
        }
        if (productServicedWoliId == null) {
            throw new WorkOrderLineItemsServiceException('Product Serviced line is required.');
        }
        if (disinfectionProduct == null || disinfectionProduct.Id == null) {
            throw new WorkOrderLineItemsServiceException('Disinfection product is required.');
        }
        try {
            WorkOrder workOrder = WorkOrdersService.getWorkOrderForDeviceEvaluationById(workOrderId);
            if (workOrder == null) {
                throw new WorkOrderLineItemsServiceException('Work Order was not found.');
            }
            WorkOrderLineItem productServiced = queryReceivingProductServicedLine(
                productServicedWoliId,
                workOrderId
            );
            Id repairCodeRtId = getRepairCodeRecordTypeId();
            if (repairCodeRtId == null) {
                throw new WorkOrderLineItemsServiceException(
                    'Repair Code Work Order Line Item record type was not found.'
                );
            }
            Id pricebookEntryId = requireDisinfectionPricebookEntryId(
                workOrder,
                disinfectionProduct
            );

            WorkOrderLineItem line = buildReceivingDisinfectionLine(
                workOrder,
                productServiced,
                disinfectionProduct,
                repairCodeRtId,
                pricebookEntryId,
                quantity
            );
            Database.insert(new List<WorkOrderLineItem>{ line }, AccessLevel.USER_MODE);
            return line.Id;
        } catch (WorkOrderLineItemsServiceException e) {
            throw e;
        } catch (DmlException e) {
            Logger.error(
                new LogMessage(
                    'WorkOrderLineItemsService.createReceivingDisinfectionCodeLine: DML error for WO {0}.',
                    workOrderId
                ),
                e
            );
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(
                e.getNumDml() > 0 ? e.getDmlMessage(0) : e.getMessage(),
                e
            );
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrderLineItemsService.createReceivingDisinfectionCodeLine: Unexpected error for WO {0}.',
                    workOrderId
                ),
                e
            );
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(
                'Unable to create the Disinfection line: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5968 - Disinfection Service Code on an instrument Work Order that has
     *              no Product Serviced line. The line is not parented to another line.
     * @param workOrderId Work Order Id
     * @param quantity Disinfection quantity
     * @param disinfectionProduct Active Disinfection product
     * @return Created Work Order Line Item Id
     */
    public static Id createReceivingOrderDisinfectionCodeLine(
        Id workOrderId,
        Decimal quantity,
        Product2 disinfectionProduct
    ) {
        if (workOrderId == null) {
            throw new WorkOrderLineItemsServiceException('Work Order is required.');
        }
        if (disinfectionProduct == null || disinfectionProduct.Id == null) {
            throw new WorkOrderLineItemsServiceException('Disinfection product is required.');
        }
        try {
            WorkOrder workOrder = WorkOrdersService.getWorkOrderForDeviceEvaluationById(workOrderId);
            if (workOrder == null) {
                throw new WorkOrderLineItemsServiceException('Work Order was not found.');
            }
            Id repairCodeRtId = getRepairCodeRecordTypeId();
            if (repairCodeRtId == null) {
                throw new WorkOrderLineItemsServiceException(
                    'Repair Code Work Order Line Item record type was not found.'
                );
            }
            Id pricebookEntryId = requireDisinfectionPricebookEntryId(
                workOrder,
                disinfectionProduct
            );
            WorkOrderLineItem line = buildReceivingOrderDisinfectionLine(
                workOrder,
                disinfectionProduct,
                repairCodeRtId,
                pricebookEntryId,
                quantity
            );
            Database.insert(new List<WorkOrderLineItem>{ line }, AccessLevel.USER_MODE);
            return line.Id;
        } catch (WorkOrderLineItemsServiceException e) {
            throw e;
        } catch (DmlException e) {
            Logger.error(
                new LogMessage(
                    'WorkOrderLineItemsService.createReceivingOrderDisinfectionCodeLine: DML error for WO {0}.',
                    workOrderId
                ),
                e
            );
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(
                e.getNumDml() > 0 ? e.getDmlMessage(0) : e.getMessage(),
                e
            );
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrderLineItemsService.createReceivingOrderDisinfectionCodeLine: Unexpected error for WO {0}.',
                    workOrderId
                ),
                e
            );
            Logger.saveLog();
            throw new WorkOrderLineItemsServiceException(
                'Unable to create the Disinfection line: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    private static WorkOrderLineItem queryReceivingProductServicedLine(
        Id productServicedWoliId,
        Id workOrderId
    ) {
        WorkOrderLineItem productServiced = (WorkOrderLineItem) new WorkOrderLineItemsSelector()
            .selectFields(
                new List<String>{
                    'Id',
                    'AssetId',
                    'SerialNumber__c',
                    'Model__c',
                    'Product2Id',
                    'Asset.SerialNumber',
                    'Asset.Product2Id',
                    'Asset.Product2.Name',
                    'Asset.Product2.ProductCode',
                    'Asset.Product2.Model__c',
                    'Asset.Product2.Description'
                }
            )
            .whereEquals('Id', productServicedWoliId)
            .whereEquals('WorkOrderId', workOrderId)
            .first();
        if (productServiced == null) {
            throw new WorkOrderLineItemsServiceException(
                'Product Serviced line was not found on this Work Order.'
            );
        }
        return productServiced;
    }

    private static Id requireDisinfectionPricebookEntryId(
        WorkOrder workOrder,
        Product2 disinfectionProduct
    ) {
        Id pricebookId = WorkOrdersService.resolvePricebookIdForDeviceEvaluation(workOrder);
        if (pricebookId == null) {
            throw new WorkOrderLineItemsServiceException(
                'Work Order must have a Price Book on the Parent Work Order ' +
                '(or on the Work Order when no Parent exists) before the Disinfection line can be created.'
            );
        }
        if (String.isBlank(workOrder.CurrencyIsoCode)) {
            throw new WorkOrderLineItemsServiceException(
                'Work Order currency is required to resolve the Disinfection Price Book Entry.'
            );
        }
        Map<Id, Id> pricebookEntryIdsByProductId =
            PricebookEntriesService.getPricebookEntryIdsByProductId(
                pricebookId,
                new Set<Id>{ disinfectionProduct.Id },
                workOrder.CurrencyIsoCode
            );
        Id pricebookEntryId = pricebookEntryIdsByProductId.get(disinfectionProduct.Id);
        if (pricebookEntryId == null) {
            throw new WorkOrderLineItemsServiceException(
                'No active Price Book Entry was found for Disinfection product ' +
                disinfectionProduct.ProductCode +
                ' matching the Work Order Price Book and currency. Add an active entry and try again.'
            );
        }
        return pricebookEntryId;
    }

    private static WorkOrderLineItem buildReceivingDisinfectionLine(
        WorkOrder workOrder,
        WorkOrderLineItem productServiced,
        Product2 disinfectionProduct,
        Id repairCodeRtId,
        Id pricebookEntryId,
        Decimal quantity
    ) {
        Asset workOrderAsset = workOrder.Asset;
        Boolean useWorkOrderAsset = workOrder.AssetId != null && workOrderAsset != null;
        Id assetId = useWorkOrderAsset ? workOrder.AssetId : productServiced.AssetId;
        Asset sourceAsset = useWorkOrderAsset ? workOrderAsset : productServiced.Asset;
        Product2 assetProduct = sourceAsset == null ? null : sourceAsset.Product2;

        WorkOrderLineItem line = new WorkOrderLineItem();
        line.RecordTypeId = repairCodeRtId;
        line.WorkOrderId = workOrder.Id;
        line.AssetId = assetId;
        line.Status = WOLI_STATUS_APPROVED;
        line.LineType__c = COMPONENT_TYPE_SERVICE_CODE;
        line.SerialNumber__c = sourceAsset != null && String.isNotBlank(sourceAsset.SerialNumber)
            ? sourceAsset.SerialNumber
            : productServiced.SerialNumber__c;
        line.Model__c = assetProduct != null && String.isNotBlank(assetProduct.Model__c)
            ? assetProduct.Model__c
            : productServiced.Model__c;
        line.Item__c = sourceAsset != null && sourceAsset.Product2Id != null
            ? sourceAsset.Product2Id
            : productServiced.Product2Id;
        line.ItemCode__c = assetProduct == null ? null : assetProduct.ProductCode;
        line.ItemDescription__c = assetProduct == null
            ? null
            : (String.isNotBlank(assetProduct.Description) ? assetProduct.Description : assetProduct.Name);
        line.RepairCode__c = disinfectionProduct.Id;
        line.ProductCodeWoli__c = disinfectionProduct.ProductCode;
        line.ProductDescription__c = String.isNotBlank(disinfectionProduct.Description)
            ? disinfectionProduct.Description
            : disinfectionProduct.Name;
        line.PricebookEntryId = pricebookEntryId;
        line.Quantity = quantity == null || quantity <= 0 ? 1 : quantity;
        line.TopLevelWorkOrder__c = workOrder.ParentWorkOrderId;
        line.ParentWorkOrderLineItemId = productServiced.Id;
        return line;
    }

    private static WorkOrderLineItem buildReceivingOrderDisinfectionLine(
        WorkOrder workOrder,
        Product2 disinfectionProduct,
        Id repairCodeRtId,
        Id pricebookEntryId,
        Decimal quantity
    ) {
        WorkOrderLineItem line = new WorkOrderLineItem();
        line.RecordTypeId = repairCodeRtId;
        line.WorkOrderId = workOrder.Id;
        line.Status = WOLI_STATUS_APPROVED;
        line.LineType__c = COMPONENT_TYPE_SERVICE_CODE;
        line.RepairCode__c = disinfectionProduct.Id;
        line.ProductCodeWoli__c = disinfectionProduct.ProductCode;
        line.ProductDescription__c = String.isNotBlank(disinfectionProduct.Description)
            ? disinfectionProduct.Description
            : disinfectionProduct.Name;
        line.PricebookEntryId = pricebookEntryId;
        line.Quantity = quantity == null || quantity <= 0 ? 1 : quantity;
        line.TopLevelWorkOrder__c = workOrder.ParentWorkOrderId;
        return line;
    }

    private static Product2 resolveProductDetails(Id product2Id) {
        if (product2Id == null) {
            return null;
        }
        List<Product2> products = ProductsService.getProductsById(new Set<Id>{ product2Id });
        return products.isEmpty() ? null : products[0];
    }

    /**
     * @description Quantity for a Product Serviced line created during receiving.
     *              Uses the quantity the receiver confirmed, then the return line quantity.
     * @param lineItem Source return line
     * @param request Product and quantity values from receiving
     * @return Quantity greater than zero
     */
    private static Decimal resolveReceivingProductServicedQuantity(
        ReturnOrderLineItem lineItem,
        ReceivingProductServicedInput request
    ) {
        if (request != null && request.quantityReceived != null && request.quantityReceived > 0) {
            return request.quantityReceived;
        }
        if (
            lineItem != null &&
            lineItem.getPopulatedFieldsAsMap().containsKey('QuantityReturned') &&
            lineItem.QuantityReturned != null &&
            lineItem.QuantityReturned > 0
        ) {
            return lineItem.QuantityReturned;
        }
        return 1;
    }

    /**
     * @description Product Serviced status on receive. Waiting for Approval when
     *              Estimate Required is Estimate Required. Otherwise Approved.
     *              Uses the child Work Order value, which is copied from the return line.
     * @param lineItem Source return line
     * @param workOrder Child Work Order the line is created on
     * @return Waiting for Approval or Approved
     */
    private static String resolveReceivingProductServicedStatus(
        ReturnOrderLineItem lineItem,
        WorkOrder workOrder
    ) {
        String estimateRequired = null;
        if (
            workOrder != null &&
            workOrder.getPopulatedFieldsAsMap().containsKey('EstimateRequired__c')
        ) {
            estimateRequired = workOrder.EstimateRequired__c;
        } else if (
            lineItem != null &&
            lineItem.getPopulatedFieldsAsMap().containsKey('EstimateRequired__c')
        ) {
            estimateRequired = lineItem.EstimateRequired__c;
        }
        if (ESTIMATE_REQUIRED_VALUE.equals(estimateRequired)) {
            return WOLI_STATUS_WAITING_APPROVAL;
        }
        return WOLI_STATUS_APPROVED;
    }

    private static WorkOrder loadReceivingWorkOrderPricebook(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }
        List<WorkOrder> workOrders =
            WorkOrdersSelector.selectByIdForReceivingWoliCreate(workOrderId);
        return workOrders.isEmpty() ? null : workOrders[0];
    }

    private static Id resolveReceivingLinePricebookId(WorkOrder workOrder) {
        if (workOrder != null && workOrder.Pricebook2Id != null) {
            return workOrder.Pricebook2Id;
        }
        if (Test.isRunningTest()) {
            return Test.getStandardPricebookId();
        }
        return null;
    }

    private static String resolveReceivingLineCurrency(WorkOrder workOrder) {
        if (workOrder != null && String.isNotBlank(workOrder.CurrencyIsoCode)) {
            return workOrder.CurrencyIsoCode;
        }
        return UserInfo.getDefaultCurrency();
    }

    private static Id resolvePricebookEntryId(
        Id pricebookId,
        Id product2Id,
        String currencyIsoCode
    ) {
        if (pricebookId == null || product2Id == null) {
            return null;
        }
        String entryCurrency = String.isBlank(currencyIsoCode)
            ? UserInfo.getDefaultCurrency()
            : currencyIsoCode;
        Id existingId = findActivePricebookEntryId(pricebookId, product2Id, entryCurrency);
        if (existingId != null) {
            return existingId;
        }
        try {
            ensureStandardPricebookEntry(pricebookId, product2Id, entryCurrency);
            PricebookEntry created = new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = product2Id,
                UnitPrice = 0,
                IsActive = true,
                CurrencyIsoCode = entryCurrency
            );
            insert created;
            return created.Id;
        } catch (Exception e) {
            Logger.warn(
                new LogMessage(
                    'WorkOrderLineItemsService.resolvePricebookEntryId: unable to create PBE. {0}',
                    e.getMessage()
                )
            );
            Logger.saveLog();
            return null;
        }
    }

    /**
     * @description A custom price book entry requires a standard price for the same currency.
     *              Without that price, the line insert is rejected because the work order
     *              already has a price book.
     */
    private static void ensureStandardPricebookEntry(
        Id targetPricebookId,
        Id product2Id,
        String currencyIsoCode
    ) {
        Id standardPricebookId = resolveStandardPricebookId();
        if (standardPricebookId == null || standardPricebookId == targetPricebookId) {
            return;
        }
        List<PricebookEntry> standardEntries =
            PricebookEntriesSelector.selectByStandardPricebookProductCurrency(
                standardPricebookId,
                product2Id,
                currencyIsoCode
            );
        if (standardEntries.isEmpty()) {
            insert new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id = product2Id,
                UnitPrice = 0,
                IsActive = true,
                CurrencyIsoCode = currencyIsoCode
            );
            return;
        }
        if (standardEntries[0].IsActive != true) {
            update new PricebookEntry(Id = standardEntries[0].Id, IsActive = true);
        }
    }

    private static Id findActivePricebookEntryId(
        Id pricebookId,
        Id product2Id,
        String currencyIsoCode
    ) {
        List<PricebookEntry> entries =
            PricebookEntriesSelector.selectActiveIdByPricebookProductCurrency(
                pricebookId,
                product2Id,
                currencyIsoCode
            );
        return entries.isEmpty() ? null : entries[0].Id;
    }

    private static Id resolveStandardPricebookId() {
        if (Test.isRunningTest()) {
            return Test.getStandardPricebookId();
        }
        List<Pricebook2> pricebooks = PricebooksSelector.selectActiveStandard();
        return pricebooks.isEmpty() ? null : pricebooks[0].Id;
    }

    /****************************************************************************************
     * GW-6095 - COMPONENT TAGS FOR ALLOWED PARTS
     * New methods only. They reuse collectServiceBomIdSet / mapProduct2IdsByProductItem and
     * ProductRelatedMaterialsSelector unchanged; the Allowed Unit methods above are not modified.
     ****************************************************************************************/

    /**
     * @description GW-6095 - Component Tag option shown in the Work Order Review - ES (woDebriefES)
     *              parts form.
     */
    public class ComponentTagOption {
        /** @description ComponentTag__c Id, saved on WorkOrderLineItem.ComponentTag__c. */
        @AuraEnabled
        public Id id;
        /** @description Option label: the Component Tag Name. */
        @AuraEnabled
        public String label;

        /**
         * @description Builds an option from a Component Tag record.
         * @param componentTag Component Tag with Id and Name queried
         */
        public ComponentTagOption(ComponentTag__c componentTag) {
            this.id = componentTag.Id;
            this.label = componentTag.Name;
        }
    }

    /**
     * @description GW-6095 - Returns the Component Tag options for one Product2 (Customer Stock)
     *              on a Work Order.
     * @param workOrderId Work Order Id
     * @param product2Id Selected Product2 Id
     * @return Component Tag options (empty when none apply)
     * @throws WorkOrderLineItemsServiceException when the lookup fails
     * @example
     * List<ComponentTagOption> options =
     *     WorkOrderLineItemsService.getComponentTagsForProduct(workOrderId, product2Id);
     */
    public static List<ComponentTagOption> getComponentTagsForProduct(Id workOrderId, Id product2Id) {
        if (workOrderId == null || product2Id == null) {
            return new List<ComponentTagOption>();
        }
        List<ComponentTagOption> options =
            getComponentTagsByProduct(workOrderId, new Set<Id>{ product2Id }).get(product2Id);
        return options == null ? new List<ComponentTagOption>() : options;
    }

    /**
     * @description GW-6095 - Returns the Component Tag options for one Product Item (Trunk Stock)
     *              on a Work Order.
     * @param workOrderId Work Order Id
     * @param productItemId Selected Product Item Id
     * @return Component Tag options (empty when none apply)
     * @throws WorkOrderLineItemsServiceException when the lookup fails
     * @example
     * List<ComponentTagOption> options =
     *     WorkOrderLineItemsService.getComponentTagsForProductItem(workOrderId, productItemId);
     */
    public static List<ComponentTagOption> getComponentTagsForProductItem(Id workOrderId, Id productItemId) {
        if (workOrderId == null || productItemId == null) {
            return new List<ComponentTagOption>();
        }
        List<ComponentTagOption> options =
            getComponentTagsByProductItem(workOrderId, new Set<Id>{ productItemId }).get(productItemId);
        return options == null ? new List<ComponentTagOption>() : options;
    }

    /**
     * @description GW-6095 - Bulk: Component Tag options for Product2 Ids on a Work Order. Uses the
     *              same Allowed Parts Service BOMs as the Allowed Unit check, finds the BOM Components
     *              whose Product Component is the part, and returns their Component Tag child records.
     *              Every requested Product2 gets an entry; it is empty when the Work Order has no Asset,
     *              SBOM cross-reference is not required, the part is not on the allowed list, or the
     *              BOM Component has no Component Tags.
     * @param workOrderId Work Order Id
     * @param product2IdSet Product2 Ids
     * @return Map of Product2 Id to Component Tag options ordered by Name
     * @throws WorkOrderLineItemsServiceException when the lookup fails
     * @example
     * Map<Id, List<ComponentTagOption>> optionsByProduct2IdMap =
     *     WorkOrderLineItemsService.getComponentTagsByProduct(workOrderId, product2IdSet);
     */
    public static Map<Id, List<ComponentTagOption>> getComponentTagsByProduct(
        Id workOrderId,
        Set<Id> product2IdSet
    ) {
        Map<Id, List<ComponentTagOption>> optionsByProduct2IdMap =
            new Map<Id, List<ComponentTagOption>>();

        try {
            if (Test.isRunningTest() && simulateQueryException) {
                throw new QueryException('Simulated query failure');
            }
            if (Test.isRunningTest() && simulateGenericException) {
                throw new IllegalArgumentException('Simulated unexpected failure');
            }

            if (workOrderId == null || product2IdSet == null || product2IdSet.isEmpty()) {
                return optionsByProduct2IdMap;
            }
            for (Id product2Id : product2IdSet) {
                if (product2Id != null) {
                    optionsByProduct2IdMap.put(product2Id, new List<ComponentTagOption>());
                }
            }
            if (optionsByProduct2IdMap.isEmpty()) {
                return optionsByProduct2IdMap;
            }

            List<WorkOrder> workOrderList =
                WorkOrdersSelector.selectByIdsForAllowedUnit(new Set<Id>{ workOrderId });
            if (workOrderList.isEmpty() || workOrderList[0].AssetId == null) {
                Logger.debug('Component Tags skipped: Work Order has no Asset');
                return optionsByProduct2IdMap;
            }

            Set<Id> serviceBomIdSet = collectServiceBomIdSet(workOrderList[0]);
            if (serviceBomIdSet == null || serviceBomIdSet.isEmpty()) {
                Logger.debug('Component Tags skipped: no Service BOM to cross-reference');
                return optionsByProduct2IdMap;
            }

            Map<Id, Id> product2IdByBomComponentIdMap = new Map<Id, Id>();
            for (
                ProductRelatedMaterial bomComponent :
                ProductRelatedMaterialsSelector.selectByServiceBomAndProductComponents(
                    serviceBomIdSet,
                    optionsByProduct2IdMap.keySet()
                )
            ) {
                if (bomComponent.ProductComponentId != null) {
                    product2IdByBomComponentIdMap.put(bomComponent.Id, bomComponent.ProductComponentId);
                }
            }
            if (product2IdByBomComponentIdMap.isEmpty()) {
                return optionsByProduct2IdMap;
            }

            Integer componentTagCount = 0;
            for (
                ComponentTag__c componentTag :
                ComponentTagsSelector.selectByBomComponentIds(product2IdByBomComponentIdMap.keySet())
            ) {
                Id product2Id = product2IdByBomComponentIdMap.get(componentTag.BomComponent__c);
                if (product2Id != null) {
                    optionsByProduct2IdMap.get(product2Id).add(new ComponentTagOption(componentTag));
                    componentTagCount++;
                }
            }

            Logger.debug(
                new LogMessage(
                    'Component Tags by Product complete bomComponentCount={0} componentTagCount={1}',
                    product2IdByBomComponentIdMap.size(),
                    componentTagCount
                )
            );
            return optionsByProduct2IdMap;
        } catch (QueryException e) {
            Logger.error('WorkOrderLineItemsService.getComponentTagsByProduct query failed', e);
            throw new WorkOrderLineItemsServiceException(
                'Failed to load Component Tags: ' + e.getMessage(),
                e
            );
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemsService.getComponentTagsByProduct failed', e);
            throw new WorkOrderLineItemsServiceException(
                'Failed to load Component Tags: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-6095 - Bulk: Component Tag options for Product Item Ids on a Work Order.
     *              Resolves each Product Item to its Product2 and delegates to getComponentTagsByProduct.
     * @param workOrderId Work Order Id
     * @param productItemIdSet Product Item Ids
     * @return Map of Product Item Id to Component Tag options ordered by Name
     * @throws WorkOrderLineItemsServiceException when the lookup fails
     * @example
     * Map<Id, List<ComponentTagOption>> optionsByProductItemIdMap =
     *     WorkOrderLineItemsService.getComponentTagsByProductItem(workOrderId, productItemIdSet);
     */
    public static Map<Id, List<ComponentTagOption>> getComponentTagsByProductItem(
        Id workOrderId,
        Set<Id> productItemIdSet
    ) {
        Map<Id, List<ComponentTagOption>> optionsByProductItemIdMap =
            new Map<Id, List<ComponentTagOption>>();

        try {
            if (workOrderId == null || productItemIdSet == null || productItemIdSet.isEmpty()) {
                return optionsByProductItemIdMap;
            }

            Map<Id, Id> product2IdByProductItemIdMap = mapProduct2IdsByProductItem(productItemIdSet);
            Map<Id, List<ComponentTagOption>> optionsByProduct2IdMap = getComponentTagsByProduct(
                workOrderId,
                new Set<Id>(product2IdByProductItemIdMap.values())
            );

            for (Id productItemId : productItemIdSet) {
                if (productItemId == null) {
                    continue;
                }
                Id product2Id = product2IdByProductItemIdMap.get(productItemId);
                List<ComponentTagOption> options =
                    product2Id == null ? null : optionsByProduct2IdMap.get(product2Id);
                optionsByProductItemIdMap.put(
                    productItemId,
                    options == null ? new List<ComponentTagOption>() : options
                );
            }
            return optionsByProductItemIdMap;
        } catch (WorkOrderLineItemsServiceException e) {
            throw e;
        } catch (QueryException e) {
            Logger.error('WorkOrderLineItemsService.getComponentTagsByProductItem query failed', e);
            throw new WorkOrderLineItemsServiceException(
                'Failed to load Component Tags: ' + e.getMessage(),
                e
            );
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemsService.getComponentTagsByProductItem failed', e);
            throw new WorkOrderLineItemsServiceException(
                'Failed to load Component Tags: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Thrown when a Work Order Line Item service operation fails.
     */
    /** @description GW-1738 / GW-2001: Billing Type when no prior warrantable consumption exists. */
    public static final String BILLING_TYPE_BILLABLE = 'Billable';
    /** @description GW-1738 / GW-2001: Billing Type when the same part was consumed on the same asset within 90 days. */
    public static final String BILLING_TYPE_SVC_WARRANTY = 'SVC Warranty';

    /**
     * @description GW-1738 / GW-2001: Billing Type for a Product Item on a Work Order.
     * @param workOrderId Current Work Order Id
     * @param productItemId Selected Product Item Id
     * @return Billable or SVC Warranty
     */
    public static String evaluateBillingTypeForProductItem(Id workOrderId, Id productItemId) {
        if (productItemId == null) {
            return BILLING_TYPE_BILLABLE;
        }
        Map<Id, Id> product2IdByProductItemIdMap = mapProduct2IdsByProductItem(new Set<Id>{ productItemId });
        return evaluateBillingType(workOrderId, product2IdByProductItemIdMap.get(productItemId));
    }

    /**
     * @description GW-1738 / GW-2001: Billing Type for a Product2 on a Work Order.
     *              SVC Warranty when the same product was consumed on another WO for the same
     *              asset in the last 90 days; otherwise Billable.
     * @param workOrderId Current Work Order Id
     * @param product2Id Selected Product2 Id
     * @return Billable or SVC Warranty
     */
    public static String evaluateBillingType(Id workOrderId, Id product2Id) {
        if (workOrderId == null || product2Id == null) {
            return BILLING_TYPE_BILLABLE;
        }

        try {
            if (Test.isRunningTest() && simulateQueryException) {
                throw new QueryException('Simulated query failure');
            }
            if (Test.isRunningTest() && simulateGenericException) {
                throw new IllegalArgumentException('Simulated unexpected failure');
            }

            List<WorkOrder> workOrders = WorkOrdersSelector.selectAssetIdById(workOrderId);
            if (workOrders.isEmpty() || workOrders[0].AssetId == null) {
                return BILLING_TYPE_BILLABLE;
            }

            Datetime sinceDatetime = Datetime.now().addDays(-90);
            Id assetId = workOrders[0].AssetId;
            List<WorkOrderLineItem> priorParts =
                WorkOrderLineItemsSelector.selectPriorPartsForBillingType(
                    workOrderId,
                    assetId,
                    product2Id,
                    sinceDatetime
                );
            if (!priorParts.isEmpty()) {
                return BILLING_TYPE_SVC_WARRANTY;
            }
            return BILLING_TYPE_BILLABLE;
        } catch (QueryException e) {
            Logger.error('WorkOrderLineItemsService.evaluateBillingType query failed', e);
            throw new WorkOrderLineItemsServiceException(
                'Unable to evaluate billing type.',
                e
            );
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemsService.evaluateBillingType failed', e);
            throw new WorkOrderLineItemsServiceException(
                'Unable to evaluate billing type.',
                e
            );
        }
    }

    public class WorkOrderLineItemsServiceException extends Exception {}
}