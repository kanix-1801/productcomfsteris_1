/**
 * @description Service class for WorkOrder business operations.
 *              Entry point for all Work Order-related transactions, including Outside Vendor
 *              Work Order create/sync for Device and Instrument Evaluation (GW-3850 / GW-4616).
 *              Performs DML directly — no Unit of Work / Domain dependency.
 */
public with sharing class WorkOrdersService {
    /** GW-1295 - Repair Center Work Order RecordType DeveloperNames included in repair history. */
    @TestVisible
    private static final List<String> REPAIR_CENTER_RECORD_TYPES = new List<String>{
        'RepairCenterDevices',
        'RepairCenterInstruments',
        'RepairCenterOther',
        'RepairCenterVendor'
    };

    /** Test-only: force catch (Exception) paths for coverage. */
    @TestVisible
    private static Boolean simulateGenericException = false;
    /** Test-only: force WOAssignmentHistoriesServiceException catch paths. */
    @TestVisible
    private static Boolean simulateWahException = false;
    /** Test-only: force ProductRelatedMaterialsServiceException catch paths. */
    @TestVisible
    private static Boolean simulatePrmException = false;

    /** GW-3377 - Records whether Complete ran pricing before the status update. */
    @TestVisible
    static List<String> evaluationPersistSteps = new List<String>();

    @TestVisible
    private static void throwIfSimulated() {
        if (!Test.isRunningTest()) {
            return;
        }
        if (simulateWahException) {
            throw new WOAssignmentHistoriesService.WOAssignmentHistoriesServiceException(
                'Simulated WAH exception for coverage'
            );
        }
        if (simulatePrmException) {
            throw new ProductRelatedMaterialsService.ProductRelatedMaterialsServiceException(
                'Simulated PRM exception for coverage'
            );
        }
        if (simulateGenericException) {
            throw new CalloutException('Simulated exception for coverage');
        }
    }


    private static final String WO_STATUS_RECEIVED = 'Received';
    private static final String WO_STATUS_EVALUATE = 'Evaluate';
    private static final String WO_STATUS_REPAIR = 'Repair';
    private static final String WO_STATUS_QC = 'QC';
    @TestVisible
    private static final String QC_FAIL_NCR_REQUIRED_MESSAGE =
        'An NCR is required to set Sub Status = QC Fail';
    private static final String WO_STATUS_QUOTE = 'Quote';
    private static final String WO_STATUS_READY_FOR_REPAIR = 'Ready for Repair';
    private static final String WO_SUB_STATUS_EVAL = 'Eval';
    private static final String WO_SUB_STATUS_REQUOTE_REQUIRED = 'Re-Quote Required';
    private static final String WO_SUB_STATUS_READY_FOR_QC = 'Ready for QC';
    private static final String WO_SUB_STATUS_WAITING_APPROVAL = 'Waiting for Approval';
    private static final String WO_SUB_STATUS_PO_REQUIRED = 'PO Required';
    private static final String WO_SUB_STATUS_REJECTED = 'Rejected';
    private static final String WO_SUB_STATUS_SHIP_TO_VENDOR = 'Ship to Vendor';
    private static final String SHIP_TO_VENDOR_COMPLETE_BLOCKED_MESSAGE =
        'Repair cannot be completed if sending to a Vendor. Please \'Save & Close\' ' +
        'to commit your changes';
    private static final String ESTIMATE_REQUIRED_VALUE = 'Estimate Required';
    private static final String PHOTO_REQUIRED_MESSAGE =
        'Photos are required for this item. Please upload photos, or if unable to do so, ' +
        'check that you are ‘Unable to Take Photo’.';
    private static final String IE_PHOTOS_REQUIRED_WORK_ORDER_MESSAGE =
        'The Customer Requires Photos for this Work Order.  Please upload at least one photo on any item, or if unable to do so, check that you are ‘Unable to Take Photo’';
    private static final Integer REPAIR_HISTORY_MONTHS = 12;
    private static final String MOD_REQUEST_EMAIL_TEMPLATE_NAME = 'Mod_Request_Form_Request';
    private static final String MOD_REQUEST_FORM_DOCUMENT_NAME = 'WI-INS-MOD.F01';
    private static final String MOD_REQUEST_EMAIL_OPERATION_PREVIEW = 'Preview';
    private static final String MOD_REQUEST_EMAIL_OPERATION_SEND = 'Send';
    private static final String MOD_REQUEST_SUB_STATUS_MOD_HOLD = 'Mod Hold';
    private static final Integer MOD_REQUEST_EMAIL_CHUNK_SIZE = 100;

    /**
     * @description GW-3913 / GW-3096 - Domain context for Device Evaluation workspace mapping.
     */
    public class DeviceEvaluationContext {
        public WorkOrder workOrder;
        public Boolean photosRequired;
        public String productLine;
        public String manufacturer;
        public String model;
        public String serialNumber;
        public String deviceIdentityLine;
        public List<Id> selectedProductIds = new List<Id>();
        public List<CustomerPreference__c> customerPreferences = new List<CustomerPreference__c>();
        public List<WorkOrder> repairHistory = new List<WorkOrder>();
        public Boolean repairHistoryHasMore = false;
        public List<ProductRelatedMaterialsService.RepairCodeCardData> categoryCodes =
            new List<ProductRelatedMaterialsService.RepairCodeCardData>();
        public List<ProductRelatedMaterialsService.EvalCategoryTabData> evalCategoryTabs =
            new List<ProductRelatedMaterialsService.EvalCategoryTabData>();
        public List<ContentDocumentLinksService.DeviceEvaluationFileData> attachedFiles =
            new List<ContentDocumentLinksService.DeviceEvaluationFileData>();
        public Integer selectableCardCount = 0;
        public Integer categoryCodeCount = 0;
        public Integer observationCodeCount = 0;
        public Integer serviceCodeCount = 0;
        public ProductRelatedMaterialsService.RepairCodeCatalog catalog;
        /** GW-3377 - Repair Code net total before the latest save. */
        public Decimal originalNetTotalPrice;
        /** GW-3377 - Repair Code net total after Execute Pricing. */
        public Decimal newNetTotalPrice;
        /** GW-3377 - Warning when a Repair save exceeds the approved cost. */
        public String requoteWarning;
    }

    /**
     * @description GW-3400 - Domain context for Instrument Evaluation workspace mapping.
     */
    public class InstrumentEvaluationContext {
        public WorkOrder workOrder;
        public Boolean photosRequired;
        public String productLine;
        public String manufacturer;
        public String model;
        public String serialNumber;
        public String assetIdentityLine;
        public Boolean hasAsset;
        public Boolean showItemSelection;
        public Boolean canAddItems;
        public List<CustomerPreference__c> customerPreferences = new List<CustomerPreference__c>();
        public List<WorkOrder> repairHistory = new List<WorkOrder>();
        public Boolean repairHistoryHasMore = false;
        /** GW-3377 - Repair Code net total before the latest save. */
        public Decimal originalNetTotalPrice;
        /** GW-3377 - Repair Code net total after Execute Pricing. */
        public Decimal newNetTotalPrice;
        /** GW-3377 - Warning when a Repair save exceeds the approved cost. */
        public String requoteWarning;
    }

    /**
     * @description GW-5883 - Contamination locations captured when Sub Status is Contaminated.
     */
    public class ContaminationInformation {
        @AuraEnabled public Boolean isInsertionTubeChannelDistalEnd;
        @AuraEnabled public Boolean isElevatorIrrigationChannel;
        @AuraEnabled public Boolean isAuxiliaryWaterPort;
        @AuraEnabled public Boolean isBiopsyPort;
        @AuraEnabled public Boolean isAirWaterPort;
        @AuraEnabled public Boolean isSuctionPort;
        @AuraEnabled public Boolean isLightGuideTubes;
        @AuraEnabled public Boolean isAirWaterConnectors;
        @AuraEnabled public Boolean isEyePiece;
        @AuraEnabled public Boolean isShaft;
        @AuraEnabled public Boolean isPowerCord;
        @AuraEnabled public Boolean isInstrument;
        @AuraEnabled public Boolean isLockingMechanism;
        @AuraEnabled public Boolean isFootPedal;
        @AuraEnabled public Boolean isOphthalmic;
        @AuraEnabled public String contaminationOther;
    }

    /**
     * @description GW-3400 - Eval Category card for the Item Selection wizard.
     */
    public class InstrumentEvalCategoryCard {
        public String evalCategory;
        public String evalRank;
    }

    /**
     * @description GW-3400 - Product card for the Item Selection wizard.
     */
    public class InstrumentProductCard {
        public Id productId;
        public String productCode;
        public String productName;
        public String evalCategory;
    }

    /**
     * @description GW-3400 - Draft Instrument Evaluation item held in the LWC until Next/Complete.
     */
    public class InstrumentEvaluationDraftItem {
        /** When set, syncs repair codes onto this existing Product Serviced WOLI. */
        public Id productServicedId;
        public Id productId;
        public Decimal quantity;
        /** GW-5324 - Return Order Line Items selected for this Product Serviced row. */
        public List<Id> returnOrderLineItemIds;
        public List<Id> repairCodeProductIds;
        public List<Id> contentDocumentIds;
        public Boolean vendorProcessingRequired;
        public Id vendorAccountId;
        public String instructionsToVendor;
        public String sterisPurchaseOrderToVendor;
        public String vendorNotes;
        public String vendorReferenceNumber;
        public Decimal vendorCost;
        public Date shippedToVendorDate;
        public String trackingNumber;
    }

    /**
     * @description GW-3400 - Persisted Product Serviced row with child repair codes.
     */
    public class InstrumentEvaluationItem {
        public Id productServicedId;
        public String status;
        public Id productId;
        public String productCode;
        public String productName;
        public Decimal quantity;
        public String returnOrderLineItems;
        public Boolean vendorProcessingRequired;
        public Id vendorAccountId;
        public String instructionsToVendor;
        public String sterisPurchaseOrderToVendor;
        public String vendorNotes;
        public String vendorReferenceNumber;
        public Decimal vendorCost;
        public Date shippedToVendorDate;
        public String trackingNumber;
        public Boolean vendorWorkOrderLocked;
        public Id vendorWorkOrderId;
        public List<ProductRelatedMaterialsService.RepairCodeCardData> repairCodes =
            new List<ProductRelatedMaterialsService.RepairCodeCardData>();
        public List<ContentDocumentLinksService.DeviceEvaluationFileData> photos =
            new List<ContentDocumentLinksService.DeviceEvaluationFileData>();
    }

    /**
     * @description GW-5324 - One Return Order Line Item displayed in the assignment modal.
     */
    public class InstrumentReturnOrderLineOption {
        public Id id;
        public String lineItemNumber;
        public String serialNumber;
        public Id productId;
        public String productName;
        public String itemDescription;
        public String model;
        public Decimal quantity;
        public Boolean selected;
    }

    /**
     * @description GW-5324 - Return Order Line assignment modal data.
     */
    public class InstrumentReturnOrderLineAssignment {
        public String returnOrderNumber;
        public List<InstrumentReturnOrderLineOption> options =
            new List<InstrumentReturnOrderLineOption>();
    }


    /**
     * @description Creates new WorkOrder records.
     * @param workOrders List of WorkOrder records to create.
     * @throws WorkOrdersServiceException when the operation fails.
     * @example
     * WorkOrdersService.createWorkOrders(workOrderList);
     */
    public static void createWorkOrders(List<WorkOrder> workOrders) {
        if (workOrders == null || workOrders.isEmpty()) {
            return;
        }
        Logger.setScenario('Work Order Management');
        try {
            throwIfSimulated();
            insert workOrders;
        } catch (Exception e) {
            Logger.error('WorkOrdersService.createWorkOrders: Unexpected error.', e);
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while creating Work Order records.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing WorkOrder records.
     * @param workOrders List of WorkOrder records to update.
     * @throws WorkOrdersServiceException when the operation fails.
     * @example
     * WorkOrdersService.updateWorkOrders(workOrderList);
     */
    public static void updateWorkOrders(List<WorkOrder> workOrders) {
        if (workOrders == null || workOrders.isEmpty()) {
            return;
        }
        Logger.setScenario('Work Order Management');
        try {
            throwIfSimulated();
            update workOrders;
        } catch (Exception e) {
            Logger.error('WorkOrdersService.updateWorkOrders: Unexpected error.', e);
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while updating Work Order records.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5333 - Loads Work Orders for Approve/Reject Quote.
     * @param workOrderIds Work Order Ids
     * @return Matching Work Order rows
     */
    public static List<WorkOrder> getWorkOrdersForApproveRejectQuote(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        try {
            return WorkOrdersSelector.selectForApproveRejectQuoteByIds(workOrderIds);
        } catch (Exception e) {
            Logger.error('WorkOrdersService.getWorkOrdersForApproveRejectQuote: Unexpected error.', e);
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while retrieving Work Orders for Approve/Reject Quote.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes WorkOrder records by their Ids.
     * @param workOrderIds Set of WorkOrder Ids to delete.
     * @throws WorkOrdersServiceException when the operation fails.
     * @example
     * WorkOrdersService.deleteWorkOrders(workOrderIdSet);
     */
    public static void deleteWorkOrders(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Work Order Management');
        try {
            throwIfSimulated();
            List<WorkOrder> workOrderList = WorkOrdersSelector.selectById(workOrderIds);
            if (workOrderList.isEmpty()) {
                return;
            }
            delete workOrderList;
        } catch (Exception e) {
            Logger.error('WorkOrdersService.deleteWorkOrders: Unexpected error.', e);
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while deleting Work Order records.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves WorkOrder records by their Ids.
     * @param workOrderIds Set of WorkOrder Ids to retrieve.
     * @return List of WorkOrder records.
     * @throws WorkOrdersServiceException when the operation fails.
     * @example
     * List<WorkOrder> results = WorkOrdersService.getWorkOrdersById(workOrderIdSet);
     */
    public static List<WorkOrder> getWorkOrdersById(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        try {
            throwIfSimulated();
            return WorkOrdersSelector.selectById(workOrderIds);
        } catch (Exception e) {
            Logger.error('WorkOrdersService.getWorkOrdersById: Unexpected error.', e);
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while retrieving Work Order records.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves WorkOrder records with their related Line Items.
     * @param workOrderIds Set of WorkOrder Ids to retrieve.
     * @return List of WorkOrder records with child WorkOrderLineItem records.
     * @throws WorkOrdersServiceException when the operation fails.
     * @example
     * List<WorkOrder> results = WorkOrdersService.getWorkOrdersWithLineItems(workOrderIdSet);
     */
    public static List<WorkOrder> getWorkOrdersWithLineItems(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        try {
            throwIfSimulated();
            return WorkOrdersSelector.selectByIdWithLineItems(workOrderIds);
        } catch (Exception e) {
            Logger.error('WorkOrdersService.getWorkOrdersWithLineItems: Unexpected error.', e);
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while retrieving Work Orders with Line Items.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-2860 - Returns Work Orders with Account and Asset product-line fields needed by
     *              Work Order Customer Preferences on the WO record page.
     * @param workOrderIds Set of WorkOrder Ids to retrieve
     * @return List of WorkOrder records (empty when none / null-empty input)
     * @throws WorkOrdersServiceException when the operation fails
     */
    public static List<WorkOrder> getWorkOrdersForCustomerPreferences(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        try {
            throwIfSimulated();
            return WorkOrdersSelector.selectByIdForCustomerPreferences(workOrderIds);
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrdersService.getWorkOrdersForCustomerPreferences failed: {0}',
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while retrieving Work Orders for Customer Preferences.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-1295 - Returns Work Orders with Asset fields needed by Repair Order History
     *              on the WO record page.
     * @param workOrderIds Set of WorkOrder Ids to retrieve
     * @return List of WorkOrder records (empty when none / null-empty input)
     * @throws WorkOrdersServiceException when the operation fails
     */
    public static List<WorkOrder> getWorkOrdersForRepairHistory(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        try {
            throwIfSimulated();
            return WorkOrdersSelector.selectByIdForRepairHistory(workOrderIds);
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrdersService.getWorkOrdersForRepairHistory failed: {0}',
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while retrieving Work Orders for Repair History.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-1295 - Returns prior Repair Center Work Orders for an Asset (Actual Ship Date
     *              required), excluding the current Work Order.
     * @param assetId Asset whose repair history is requested
     * @param currentWorkOrderId Current Work Order Id to exclude
     * @return Prior shipped Repair Center Work Orders ordered by Actual Ship Date DESC
     * @throws WorkOrdersServiceException when the operation fails
     */
    public static List<WorkOrder> getRepairHistoryByAsset(Id assetId, Id currentWorkOrderId) {
        if (assetId == null) {
            return new List<WorkOrder>();
        }
        try {
            throwIfSimulated();
            Set<Id> recordTypeIds = getRepairCenterRecordTypeIds();
            return WorkOrdersSelector.selectRepairHistoryByAsset(
                assetId,
                currentWorkOrderId,
                recordTypeIds
            );
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrdersService.getRepairHistoryByAsset failed for Asset {0}: {1}',
                    assetId,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while retrieving Repair Order History.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Returns prior Repair Center Work Orders for Device Evaluation
     *              repair history (Account + Asset), excluding the current Work Order. Preserves
     *              Device Evaluation query behavior (Account filter, LIMIT 100). Distinct from
     *              GW-1295 getRepairHistoryByAsset, which does not filter by Account.
     * @param accountId Account that must match the history Work Orders
     * @param assetId Asset whose repair history is requested
     * @param currentWorkOrderId Current Work Order Id to exclude
     * @return Repair Center Work Orders ordered by Completion Timestamp DESC
     * @throws WorkOrdersServiceException when the operation fails
     */
    public static List<WorkOrder> getRepairHistoryForDeviceEvaluation(
        Id accountId,
        Id assetId,
        Id currentWorkOrderId
    ) {
        if (accountId == null || assetId == null) {
            return new List<WorkOrder>();
        }
        try {
            throwIfSimulated();
            Set<Id> recordTypeIds = getRepairCenterRecordTypeIds();
            return WorkOrdersSelector.selectRepairHistoryForDeviceEvaluation(
                accountId,
                assetId,
                currentWorkOrderId,
                recordTypeIds
            );
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrdersService.getRepairHistoryForDeviceEvaluation failed for Account {0}, Asset {1}: {2}',
                    accountId,
                    assetId,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while retrieving Device Evaluation Repair Order History.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-4495 - True when at least one history Work Order is outside the default
     *              12-month Completion Timestamp window (including rows with no timestamp).
     * @param history Repair history Work Orders
     * @return True when View All should be offered
     */
    @TestVisible
    private static Boolean hasRepairHistoryOutsideLastTwelveMonths(List<WorkOrder> history) {
        if (history == null || history.isEmpty()) {
            return false;
        }
        Datetime cutoff = Datetime.now().addMonths(-REPAIR_HISTORY_MONTHS);
        for (WorkOrder historyWorkOrder : history) {
            if (
                historyWorkOrder.CompletedTimestamp__c == null ||
                historyWorkOrder.CompletedTimestamp__c < cutoff
            ) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description GW-3913 / GW-3096 - Returns a Work Order for Device Evaluation by WorkOrderNumber,
     *              or null when not found (caller throws AuraHandledException).
     * @param workOrderNumber Work Order number to query
     * @return WorkOrder or null
     * @throws WorkOrdersServiceException when the operation fails
     */
    public static WorkOrder getWorkOrderForDeviceEvaluationByNumber(String workOrderNumber) {
        if (String.isBlank(workOrderNumber)) {
            return null;
        }
        try {
            throwIfSimulated();
            List<WorkOrder> workOrders = WorkOrdersSelector.selectForDeviceEvaluationByNumber(
                workOrderNumber
            );
            return workOrders.isEmpty() ? null : workOrders[0];
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrdersService.getWorkOrderForDeviceEvaluationByNumber failed for {0}: {1}',
                    workOrderNumber,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while retrieving a Work Order for Device Evaluation.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Returns a Work Order for Device Evaluation by Id,
     *              or null when not found (caller throws AuraHandledException).
     * @param workOrderId Work Order Id to query
     * @return WorkOrder or null
     * @throws WorkOrdersServiceException when the operation fails
     */
    public static WorkOrder getWorkOrderForDeviceEvaluationById(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }
        try {
            throwIfSimulated();
            List<WorkOrder> workOrders = WorkOrdersSelector.selectForDeviceEvaluationById(workOrderId);
            return workOrders.isEmpty() ? null : workOrders[0];
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrdersService.getWorkOrderForDeviceEvaluationById failed for {0}: {1}',
                    workOrderId,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while retrieving a Work Order for Device Evaluation.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Returns Sub Status for a Work Order by Id, or null when not found.
     * @param workOrderId Work Order Id to query
     * @return SubStatus__c value, or null when not found / blank input
     * @throws WorkOrdersServiceException when the operation fails
     */
    public static String getSubStatusById(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }
        try {
            throwIfSimulated();
            List<WorkOrder> workOrders = WorkOrdersSelector.selectSubStatusById(workOrderId);
            return workOrders.isEmpty() ? null : workOrders[0].SubStatus__c;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrdersService.getSubStatusById failed for {0}: {1}',
                    workOrderId,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while retrieving Work Order Sub Status.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3891 - Returns a Work Order for Warranty Repair Evaluation form defaults.
     * @param workOrderId Work Order Id to query
     * @return WorkOrder or null
     * @throws WorkOrdersServiceException when the operation fails
     */
    public static WorkOrder getWorkOrderForWarrantyRepairEvaluation(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }
        try {
            throwIfSimulated();
            return WorkOrdersSelector.selectForWarrantyRepairEvaluationById(workOrderId);
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrdersService.getWorkOrderForWarrantyRepairEvaluation failed for {0}: {1}',
                    workOrderId,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while retrieving a Work Order for Warranty Repair Evaluation.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Resolves Price Book for Device Evaluation PBE lookup:
     *              Parent WO Pricebook2Id, then fall back to scanned WO Pricebook2Id.
     * @param workOrder Work Order with ParentWorkOrder.Pricebook2Id and/or Pricebook2Id populated
     * @return Resolved Price Book Id, or null when workOrder is null / both blank
     */
    public static Id resolvePricebookIdForDeviceEvaluation(WorkOrder workOrder) {
        if (workOrder == null) {
            return null;
        }
        if (workOrder.ParentWorkOrder != null && workOrder.ParentWorkOrder.Pricebook2Id != null) {
            return workOrder.ParentWorkOrder.Pricebook2Id;
        }
        return workOrder.Pricebook2Id;
    }

    /**
     * @description GW-3400 - Requires WorkOrder.Pricebook2Id before Instrument Evaluation WOLI
     *              inserts (Product Serviced PBE uses WO.Price Book). Does not stamp from
     *              Parent — Divide Instruments should populate Price Book on child WOs.
     * @param workOrder Evaluation Work Order
     * @throws WorkOrdersServiceException when Price Book is blank
     */
    public static void ensurePricebookForEvaluationLineItems(WorkOrder workOrder) {
        if (workOrder == null || workOrder.Id == null) {
            throw new WorkOrdersServiceException('Work Order is required.');
        }
        if (workOrder.Pricebook2Id == null) {
            throw new WorkOrdersServiceException(
                'Work Order must have a Price Book before items can be saved.'
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Initializes a Work Order for Device Evaluation and returns context.
     * @param workOrderInput Work Order Salesforce Id or WorkOrderNumber (non-blank; caller validates blank)
     * @return DeviceEvaluationContext for Aura DTO mapping
     * @throws WorkOrdersServiceException for business validation
     * @throws DmlException when Work Order update fails
     */
    public static DeviceEvaluationContext initializeDeviceEvaluation(String workOrderInput) {
        WorkOrder workOrder = resolveWorkOrderForDeviceEvaluation(workOrderInput);
        if (workOrder == null) {
            throw new WorkOrdersServiceException('Work Order was not found.');
        }
        validateWorkOrderForEvaluation(workOrder);

        ProductRelatedMaterialsService.RepairCodeCatalog catalog =
            ProductRelatedMaterialsService.buildRepairCodeCatalogForDeviceEvaluation(
                workOrder.Asset.Product2Id
            );
        if (catalog.totalSelectableCount == 0) {
            throw new WorkOrdersServiceException(
                'No evaluation codes are available for this Work Order\'s product. ' +
                'Pricing Codes and Observation/Service codes must have Eval Display Screen = Y.'
            );
        }

        // Photos Required: exact Product Line = WO.Asset.Product Line (blank Product Line prefs excluded)
        Boolean photosRequired = CustomerPreferencesService.isPhotosRequiredExactProductLine(
            workOrder.AccountId,
            resolveProductLine(workOrder)
        );

        applyInitializeStatusUpdates(workOrder);
        workOrder.PhotosRequired__c = photosRequired;
        persistWorkOrderForDeviceEvaluation(workOrder);

        workOrder = requireWorkOrderById(workOrder.Id);
        return buildDeviceEvaluationContext(workOrder, photosRequired, catalog);
    }

    /**
     * @description GW-3913 / GW-3096 - Persists editable Device Evaluation header / notes fields.
     * @return DeviceEvaluationContext for Aura DTO mapping
     * @throws WorkOrdersServiceException for business validation
     * @throws DmlException when Work Order update fails
     */
    public static DeviceEvaluationContext saveDeviceEvaluationWorkOrderFields(
        Id workOrderId,
        String subStatus,
        Boolean unableToTakePhoto,
        Decimal turnTime,
        String usageCount,
        String evaluationNotes,
        String internalEvaluationNotes,
        String internalSpecialistEvaluationNotes
    ) {
        if (workOrderId == null) {
            throw new WorkOrdersServiceException('Work Order is required.');
        }

        WorkOrder workOrder = requireWorkOrderById(workOrderId);
        workOrder.SubStatus__c = subStatus;
        workOrder.UnableToTakePhoto__c = unableToTakePhoto == true;
        workOrder.TurnTime__c = turnTime;
        workOrder.UsageCount__c = usageCount;
        if (String.isNotBlank(usageCount)) {
            workOrder.UsageCountDate__c = Date.today();
        } else {
            workOrder.UsageCountDate__c = null;
        }
        workOrder.EvaluationNotes__c = evaluationNotes;
        workOrder.InternalEvaluationNotes__c = internalEvaluationNotes;
        workOrder.InternalSpecialistEvaluationNotes__c = internalSpecialistEvaluationNotes;
        persistWorkOrderForDeviceEvaluation(workOrder);

        workOrder = requireWorkOrderById(workOrderId);
        Boolean photosRequired = CustomerPreferencesService.isPhotosRequiredExactProductLine(
            workOrder.AccountId,
            resolveProductLine(workOrder)
        );
        if (workOrder.PhotosRequired__c != photosRequired) {
            workOrder.PhotosRequired__c = photosRequired;
            persistWorkOrderForDeviceEvaluation(workOrder);
            workOrder = requireWorkOrderById(workOrderId);
        }

        ProductRelatedMaterialsService.RepairCodeCatalog catalog =
            ProductRelatedMaterialsService.buildRepairCodeCatalogForDeviceEvaluation(
                workOrder.Asset.Product2Id
            );
        return buildDeviceEvaluationContext(workOrder, photosRequired, catalog);
    }

    /**
     * @description GW-3913 / GW-3096 - Shared Save / Complete persistence for Device Evaluation.
     *              When applyCompletionRules is true, enforces photo validation and applies
     *              Evaluate Quote / Ready for Repair or Repair Ready for QC rules after WOLI reconcile.
     * @return DeviceEvaluationContext for Aura DTO mapping (also used by Complete for side effects)
     * @throws WorkOrdersServiceException for business validation
     * @throws DmlException when underlying DML fails
     */
    public static DeviceEvaluationContext persistDeviceEvaluationDraft(
        Id workOrderId,
        String subStatus,
        Boolean unableToTakePhoto,
        Decimal turnTime,
        String usageCount,
        String evaluationNotes,
        String internalEvaluationNotes,
        String internalSpecialistEvaluationNotes,
        List<Id> selectedProductIds,
        List<ContentDocumentLinksService.StagedPhotoAssignment> stagedPhotos,
        Boolean applyCompletionRules
    ) {
        if (workOrderId == null) {
            throw new WorkOrdersServiceException('Work Order is required.');
        }

        WorkOrder workOrder = requireWorkOrderById(workOrderId);
        validateWorkOrderForEvaluation(workOrder);

        Boolean photosRequired = CustomerPreferencesService.isPhotosRequiredExactProductLine(
            workOrder.AccountId,
            resolveProductLine(workOrder)
        );
        Boolean unable = unableToTakePhoto == true;
        Boolean hasStagedPhotos = hasStagedPhotoAssignments(stagedPhotos);
        if (
            applyCompletionRules == true &&
            photosRequired &&
            !unable &&
            !hasStagedPhotos &&
            !ContentDocumentLinksService.repairCodeWolisHaveFilesForDeviceEvaluation(workOrderId)
        ) {
            throw new WorkOrdersServiceException(PHOTO_REQUIRED_MESSAGE);
        }
        if (applyCompletionRules == true && WO_SUB_STATUS_SHIP_TO_VENDOR.equals(subStatus)) {
            throw new WorkOrdersServiceException(SHIP_TO_VENDOR_COMPLETE_BLOCKED_MESSAGE);
        }

        Set<Id> selectedIds = selectedProductIds == null
            ? new Set<Id>()
            : new Set<Id>(selectedProductIds);
        selectedIds.remove(null);

        ProductRelatedMaterialsService.RepairCodeCatalog catalog =
            ProductRelatedMaterialsService.buildRepairCodeCatalogForDeviceEvaluation(
                workOrder.Asset.Product2Id
            );
        Set<Id> selectableIds = catalog.allProductIds();
        for (Id selectedId : selectedIds) {
            if (!selectableIds.contains(selectedId)) {
                throw new WorkOrdersServiceException(
                    'One or more selected repair codes are not valid for this Work Order.'
                );
            }
        }

        String priorStatus = workOrder.Status;
        String priorSubStatus = workOrder.SubStatus__c;

        applyEditableWorkOrderFields(
            workOrder,
            unable,
            turnTime,
            usageCount,
            evaluationNotes,
            internalEvaluationNotes,
            internalSpecialistEvaluationNotes
        );
        workOrder.PhotosRequired__c = photosRequired;
        persistWorkOrderForDeviceEvaluation(workOrder);

        Boolean requoteGate = WorkOrderRepairPricingService.requiresRequoteGate(workOrder);
        Decimal originalTotal = requoteGate
            ? WorkOrderRepairPricingService.sumRepairCodeNetTotal(workOrder)
            : null;
        WorkOrderLineItemsService.reconcileRepairCodeWolisForDeviceEvaluation(
            workOrder,
            selectedIds,
            catalog
        );
        ContentDocumentLinksService.attachStagedPhotosToWolisForDeviceEvaluation(
            workOrder.Id,
            stagedPhotos,
            selectedIds
        );
        if (requoteGate) {
            captureUnpricedRepairTotals(workOrder, originalTotal);
        }

        workOrder.SubStatus__c = subStatus;
        if (applyCompletionRules == true) {
            applyCompletionStatus(workOrder);
            applyParentGenerateQuoteOnComplete(workOrder);
        }
        if (
            workOrder.Status != priorStatus ||
            workOrder.SubStatus__c != priorSubStatus
        ) {
            persistWorkOrderForDeviceEvaluation(
                new WorkOrder(
                    Id = workOrder.Id,
                    RecordTypeId = workOrder.RecordTypeId,
                    Status = workOrder.Status,
                    SubStatus__c = workOrder.SubStatus__c
                )
            );
        }

        workOrder = requireWorkOrderById(workOrderId);
        return buildDeviceEvaluationContext(workOrder, photosRequired, catalog);
    }

    /**
     * @description GW-3377 - Runs Execute Pricing after WOLI DML has committed, then
     *              optionally applies Complete Status. Call from a separate Aura request
     *              so the Oracle callout is not in the same transaction as line DML.
     */
    public static DeviceEvaluationContext finalizeDeviceEvaluationAfterPricing(
        Id workOrderId,
        Decimal originalTotal,
        Boolean applyCompletion,
        List<Id> restoreProductIds,
        String subStatus
    ) {
        if (workOrderId == null) {
            throw new WorkOrdersServiceException('Work Order is required.');
        }
        WorkOrder workOrder = requireWorkOrderById(workOrderId);
        validateWorkOrderForEvaluation(workOrder);
        Boolean photosRequired = CustomerPreferencesService.isPhotosRequiredExactProductLine(
            workOrder.AccountId,
            resolveProductLine(workOrder)
        );
        if (
            applyCompletion == true &&
            photosRequired &&
            workOrder.UnableToTakePhoto__c != true &&
            !ContentDocumentLinksService.repairCodeWolisHaveFilesForDeviceEvaluation(workOrderId)
        ) {
            throw new WorkOrdersServiceException(PHOTO_REQUIRED_MESSAGE);
        }
        if (applyCompletion == true && WO_SUB_STATUS_SHIP_TO_VENDOR.equals(subStatus)) {
            throw new WorkOrdersServiceException(SHIP_TO_VENDOR_COMPLETE_BLOCKED_MESSAGE);
        }

        ProductRelatedMaterialsService.RepairCodeCatalog catalog =
            ProductRelatedMaterialsService.buildRepairCodeCatalogForDeviceEvaluation(
                workOrder.Asset.Product2Id
            );
        Boolean requoteGate = WorkOrderRepairPricingService.requiresRequoteGate(workOrder);
        Boolean shouldPrice =
            requoteGate ||
            (applyCompletion == true &&
            WorkOrderRepairPricingService.shouldPriceBeforeStatusChange(workOrder));
        evaluationPersistSteps = new List<String>();
        if (shouldPrice) {
            evaluationPersistSteps.add('pricing');
            try {
                WorkOrderRepairPricingService.lastTotals =
                    WorkOrderRepairPricingService.priceAfterLineChanges(
                        workOrder,
                        requoteGate,
                        originalTotal,
                        applyCompletion == true
                    );
            } catch (Exception e) {
                restoreDeviceEvaluationRepairCodes(workOrder, catalog, restoreProductIds);
                throw e;
            }
        }

        String priorStatus = workOrder.Status;
        String priorSubStatus = workOrder.SubStatus__c;
        if (subStatus != null) {
            workOrder.SubStatus__c = subStatus;
        }
        if (applyCompletion == true) {
            evaluationPersistSteps.add('status');
            applyCompletionStatus(workOrder);
            applyParentGenerateQuoteOnComplete(workOrder);
        }
        if (workOrder.Status != priorStatus || workOrder.SubStatus__c != priorSubStatus) {
            persistWorkOrderForDeviceEvaluation(
                new WorkOrder(
                    Id = workOrder.Id,
                    RecordTypeId = workOrder.RecordTypeId,
                    Status = workOrder.Status,
                    SubStatus__c = workOrder.SubStatus__c
                )
            );
        }
        workOrder = requireWorkOrderById(workOrderId);
        return buildDeviceEvaluationContext(workOrder, photosRequired, catalog);
    }

    /**
     * @description GW-3377 - Runs Execute Pricing after Instrument Evaluation line DML
     *              has committed, then optionally applies Complete Status.
     *              Quote generation stays on the Dev rule (GW-5830).
     */
    public static void finalizeInstrumentEvaluationAfterPricing(
        Id workOrderId,
        Decimal originalTotal,
        Boolean applyCompletion
    ) {
        if (workOrderId == null) {
            throw new WorkOrdersServiceException('Work Order is required.');
        }
        WorkOrder workOrder = requireInstrumentEvaluationWorkOrder(workOrderId);
        Boolean requoteGate = WorkOrderRepairPricingService.requiresRequoteGate(workOrder);
        Boolean shouldPrice =
            requoteGate ||
            (applyCompletion == true &&
            WorkOrderRepairPricingService.shouldPriceBeforeStatusChange(workOrder));
        evaluationPersistSteps = new List<String>();
        if (shouldPrice) {
            evaluationPersistSteps.add('pricing');
            WorkOrderRepairPricingService.lastTotals =
                WorkOrderRepairPricingService.priceAfterLineChanges(
                    workOrder,
                    requoteGate,
                    originalTotal,
                    applyCompletion == true
                );
        }
        if (applyCompletion == true) {
            List<WorkOrderLineItem> existingLines =
                WorkOrderLineItemsService.getInstrumentEvaluationLines(workOrder.Id);
            if (existingLines == null || existingLines.isEmpty()) {
                throw new WorkOrdersServiceException(
                    'Add at least one instrument before continuing.'
                );
            }
            evaluationPersistSteps.add('status');
            applyInstrumentEvaluationCompletionStatus(workOrder);
            Boolean shouldGenerateQuoteOnParent =
                workOrder.Status == WO_STATUS_EVALUATE_AND_QUOTE &&
                shouldGenerateParentQuoteOnComplete(workOrder);
            persistWorkOrderForDeviceEvaluation(
                new WorkOrder(
                    Id = workOrder.Id,
                    Status = workOrder.Status,
                    SubStatus__c = workOrder.SubStatus__c
                )
            );
            if (shouldGenerateQuoteOnParent) {
                persistWorkOrderForDeviceEvaluation(
                    new WorkOrder(Id = workOrder.ParentWorkOrderId, GenerateQuote__c = true)
                );
            }
        }
    }

    /**
     * @description GW-3377 - Stores pre/post line totals without invoking Execute Pricing.
     */
    private static void captureUnpricedRepairTotals(WorkOrder workOrder, Decimal originalTotal) {
        WorkOrderRepairPricingService.PricingTotals totals =
            new WorkOrderRepairPricingService.PricingTotals();
        totals.workOrderId = workOrder == null ? null : workOrder.Id;
        totals.originalNetTotal = originalTotal == null ? 0 : originalTotal;
        totals.newNetTotal = WorkOrderRepairPricingService.sumRepairCodeNetTotal(workOrder);
        WorkOrderRepairPricingService.lastTotals = totals;
    }

    /**
     * @description GW-3377 - Restores Device Evaluation Repair Codes after a requote block.
     */
    private static void restoreDeviceEvaluationRepairCodes(
        WorkOrder workOrder,
        ProductRelatedMaterialsService.RepairCodeCatalog catalog,
        List<Id> restoreProductIds
    ) {
        if (workOrder == null || catalog == null || restoreProductIds == null) {
            return;
        }
        Set<Id> restoreIds = new Set<Id>(restoreProductIds);
        restoreIds.remove(null);
        WorkOrderLineItemsService.reconcileRepairCodeWolisForDeviceEvaluation(
            workOrder,
            restoreIds,
            catalog
        );
    }

    private static void stampRepairCostTotals(
        WorkOrder workOrder,
        DeviceEvaluationContext context
    ) {
        WorkOrderRepairPricingService.PricingTotals totals =
            WorkOrderRepairPricingService.lastTotals;
        context.requoteWarning = WorkOrderRepairPricingService.lastRequoteWarning;
        WorkOrderRepairPricingService.lastRequoteWarning = null;
        if (totals != null && workOrder != null && totals.workOrderId == workOrder.Id) {
            context.originalNetTotalPrice = totals.originalNetTotal;
            context.newNetTotalPrice = totals.newNetTotal;
            WorkOrderRepairPricingService.lastTotals = null;
            return;
        }
        if (workOrder != null && workOrder.Status == WO_STATUS_REPAIR) {
            context.originalNetTotalPrice =
                WorkOrderRepairPricingService.sumRepairCodeNetTotal(workOrder);
            context.newNetTotalPrice = 0;
        }
    }

    private static void stampRepairCostTotals(
        WorkOrder workOrder,
        InstrumentEvaluationContext context
    ) {
        WorkOrderRepairPricingService.PricingTotals totals =
            WorkOrderRepairPricingService.lastTotals;
        context.requoteWarning = WorkOrderRepairPricingService.lastRequoteWarning;
        WorkOrderRepairPricingService.lastRequoteWarning = null;
        if (totals != null && workOrder != null && totals.workOrderId == workOrder.Id) {
            context.originalNetTotalPrice = totals.originalNetTotal;
            context.newNetTotalPrice = totals.newNetTotal;
            WorkOrderRepairPricingService.lastTotals = null;
            return;
        }
        if (workOrder != null && workOrder.Status == WO_STATUS_REPAIR) {
            context.originalNetTotalPrice =
                WorkOrderRepairPricingService.sumRepairCodeNetTotal(workOrder);
            context.newNetTotalPrice = 0;
        }
    }

    /**
     * @description GW-3095 / GW-3400 - Return to Eval after pending evaluation changes are saved.
     *              Devices: Status = Evaluate, Sub Status = Re-Quote Required.
     *              Instruments: Status = Evaluate & Quote, Sub Status blank.
     * @param workOrderId Work Order to return to evaluation
     */
    public static void returnWorkOrderToEvaluation(Id workOrderId) {
        if (workOrderId == null) {
            throw new WorkOrdersServiceException('Work Order is required.');
        }
        WorkOrder workOrder = requireWorkOrderById(workOrderId);
        if (
            workOrder.RecordType != null &&
            workOrder.RecordType.DeveloperName == RECORD_TYPE_INSTRUMENTS
        ) {
            workOrder.Status = WO_STATUS_EVALUATE_AND_QUOTE;
            workOrder.SubStatus__c = null;
        } else {
            workOrder.Status = WO_STATUS_EVALUATE;
            workOrder.SubStatus__c = WO_SUB_STATUS_REQUOTE_REQUIRED;
        }
        persistWorkOrderForDeviceEvaluation(workOrder);
    }

    /**
     * @description GW-3913 / GW-3096 - Builds Device Evaluation context for UI mapping.
     * @param workOrder Work Order with Device Evaluation fields / Asset relationships
     * @param photosRequired Photos-required flag
     * @param catalog Repair-code catalog
     * @return Populated DeviceEvaluationContext
     */
    public static DeviceEvaluationContext buildDeviceEvaluationContext(
        WorkOrder workOrder,
        Boolean photosRequired,
        ProductRelatedMaterialsService.RepairCodeCatalog catalog
    ) {
        DeviceEvaluationContext context = new DeviceEvaluationContext();
        if (workOrder == null) {
            return context;
        }
        if (catalog == null) {
            catalog = new ProductRelatedMaterialsService.RepairCodeCatalog();
        }

        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        Set<Id> selectedIds = repairCodeRtId == null
            ? new Set<Id>()
            : WorkOrderLineItemsService.getRepairCodeProductIds(workOrder.Id, repairCodeRtId);
        Map<Id, Product2> productsById =
            ProductsService.getProductsForDeviceEvaluationByIds(catalog.allProductIds());

        context.workOrder = workOrder;
        context.photosRequired = photosRequired;
        context.catalog = catalog;
        context.productLine = resolveProductLine(workOrder);
        context.manufacturer = resolveManufacturer(workOrder);
        context.model = resolveModel(workOrder);
        context.serialNumber = workOrder.Asset != null ? workOrder.Asset.SerialNumber : null;
        context.deviceIdentityLine = buildDeviceIdentityLine(
            context.serialNumber,
            context.manufacturer,
            context.model,
            context.productLine
        );
        context.selectedProductIds = new List<Id>(selectedIds);
        context.customerPreferences = CustomerPreferencesService.getActiveImsPreferences(
            workOrder.AccountId,
            context.productLine
        );
        context.repairHistory = getRepairHistoryForDeviceEvaluation(
            workOrder.AccountId,
            workOrder.AssetId,
            workOrder.Id
        );
        context.repairHistoryHasMore = hasRepairHistoryOutsideLastTwelveMonths(context.repairHistory);
        context.categoryCodes =
            ProductRelatedMaterialsService.buildSortedPricingCardsForDeviceEvaluation(
                catalog,
                productsById,
                selectedIds
            );
        context.evalCategoryTabs =
            ProductRelatedMaterialsService.buildEvalCategoryTabsForDeviceEvaluation(
                catalog,
                productsById,
                selectedIds
            );
        context.attachedFiles =
            ContentDocumentLinksService.getRepairCodeWoliFilesForDeviceEvaluation(workOrder.Id);
        context.selectableCardCount = catalog.totalSelectableCount;
        context.categoryCodeCount = catalog.categoryCodeIds.size();
        context.observationCodeCount = catalog.observationCodeIds.size();
        context.serviceCodeCount = catalog.serviceCodeIds.size();
        stampRepairCostTotals(workOrder, context);
        return context;
    }

    /**
     * @description Validates Work Order has Account, Asset, and Asset Product for evaluation.
     */
    @TestVisible
    private static void validateWorkOrderForEvaluation(WorkOrder workOrder) {
        if (workOrder == null) {
            throw new WorkOrdersServiceException('Work Order was not found.');
        }
        if (workOrder.AccountId == null) {
            throw new WorkOrdersServiceException('This Work Order is missing an Account.');
        }
        if (workOrder.AssetId == null || workOrder.Asset == null) {
            throw new WorkOrdersServiceException('This Work Order is missing an Asset.');
        }
        if (workOrder.Asset.Product2Id == null || workOrder.Asset.Product2 == null) {
            throw new WorkOrdersServiceException(
                'This Work Order\'s Asset is missing a Product.'
            );
        }
    }

    @TestVisible
    private static String resolveProductLine(WorkOrder workOrder) {
        if (workOrder == null || workOrder.Asset == null) {
            return null;
        }
        if (String.isNotBlank(workOrder.Asset.ProductLineCalculated__c)) {
            return workOrder.Asset.ProductLineCalculated__c;
        }
        if (
            workOrder.Asset.Product2 != null &&
            String.isNotBlank(workOrder.Asset.Product2.ProductLine__c)
        ) {
            return workOrder.Asset.Product2.ProductLine__c;
        }
        return null;
    }

    @TestVisible
    private static String resolveManufacturer(WorkOrder workOrder) {
        if (workOrder == null || workOrder.Asset == null) {
            return null;
        }
        if (String.isNotBlank(workOrder.Asset.ManufacturerCalculated__c)) {
            return workOrder.Asset.ManufacturerCalculated__c;
        }
        if (workOrder.Asset.Product2 != null) {
            return workOrder.Asset.Product2.Manufacturer__c;
        }
        return null;
    }

    @TestVisible
    private static String resolveModel(WorkOrder workOrder) {
        if (workOrder == null || workOrder.Asset == null) {
            return null;
        }
        if (String.isNotBlank(workOrder.Asset.ModelCalculated__c)) {
            return workOrder.Asset.ModelCalculated__c;
        }
        if (workOrder.Asset.Product2 != null) {
            return workOrder.Asset.Product2.Model__c;
        }
        return null;
    }

    @TestVisible
    private static String buildDeviceIdentityLine(
        String serialNumber,
        String manufacturer,
        String model,
        String productLine
    ) {
        List<String> productParts = new List<String>();
        if (String.isNotBlank(manufacturer)) {
            productParts.add(manufacturer);
        }
        if (String.isNotBlank(model)) {
            productParts.add(model);
        }
        String productIdentity = String.join(productParts, ' ');

        if (String.isNotBlank(serialNumber) && String.isNotBlank(productIdentity)) {
            if (String.isNotBlank(productLine)) {
                return serialNumber + ' - ' + productIdentity + ' (' + productLine + ')';
            }
            return serialNumber + ' - ' + productIdentity;
        }
        if (String.isNotBlank(serialNumber)) {
            return String.isNotBlank(productLine)
                ? serialNumber + ' (' + productLine + ')'
                : serialNumber;
        }
        if (String.isNotBlank(productIdentity)) {
            return String.isNotBlank(productLine)
                ? productIdentity + ' (' + productLine + ')'
                : productIdentity;
        }
        return productLine;
    }

    /** GW-5883 - Sub Status that requires a contamination location or Other. */
    @TestVisible
    private static final String SUB_STATUS_CONTAMINATED = 'Contaminated';

    /** GW-5687 - Save message when Contaminated has no location and Other is blank. */
    @TestVisible
    private static final String CONTAMINATION_REQUIRED_MESSAGE =
        'Please navigate to the Contamination Information section under the Work Order Details tab and specify what is contaminated.';

    /**
     * @description GW-5687 - Deserializes contamination JSON from evaluation LWCs.
     *              Prefer JSON over a typed Aura parameter so checkbox selections are not dropped.
     * @param contaminationJson Serialized ContaminationInformation from the LWC. Blank returns null.
     * @return Parsed DTO, or null when the payload is blank
     */
    public static ContaminationInformation parseContaminationInformation(String contaminationJson) {
        if (String.isBlank(contaminationJson)) {
            return null;
        }
        return (ContaminationInformation) JSON.deserialize(
            contaminationJson,
            ContaminationInformation.class
        );
    }

    /**
     * @description GW-5687 - Loads contamination fields for the evaluation workspace.
     * @param workOrder Work Order whose Id is queried. Null returns an empty DTO.
     * @return Contamination values, or an empty DTO when the Work Order is missing
     */
    public static ContaminationInformation toContaminationInformation(WorkOrder workOrder) {
        ContaminationInformation info = new ContaminationInformation();
        if (workOrder == null || workOrder.Id == null) {
            return info;
        }
        WorkOrder loaded = (WorkOrder) new WorkOrdersSelector()
            .selectFields(contaminationFieldNames())
            .whereEquals('Id', workOrder.Id)
            .first();
        if (loaded == null) {
            return info;
        }
        info.isInsertionTubeChannelDistalEnd = loaded.IsInsertionTubeChannelDistalEnd__c == true;
        info.isElevatorIrrigationChannel = loaded.IsElevatorIrrigationChannel__c == true;
        info.isAuxiliaryWaterPort = loaded.IsAuxiliaryWaterPort__c == true;
        info.isBiopsyPort = loaded.IsBiopsyPort__c == true;
        info.isAirWaterPort = loaded.IsAirWaterPort__c == true;
        info.isSuctionPort = loaded.IsSuctionPort__c == true;
        info.isLightGuideTubes = loaded.IsLightGuideTubes__c == true;
        info.isAirWaterConnectors = loaded.IsAirWaterConnectors__c == true;
        info.isEyePiece = loaded.IsEyePiece__c == true;
        info.isShaft = loaded.IsShaft__c == true;
        info.isPowerCord = loaded.IsPowerCord__c == true;
        info.isInstrument = loaded.IsInstrument__c == true;
        info.isLockingMechanism = loaded.IsLockingMechanism__c == true;
        info.isFootPedal = loaded.IsFootPedal__c == true;
        info.isOphthalmic = loaded.IsOphthalmic__c == true;
        info.contaminationOther = loaded.ContaminationOther__c;
        return info;
    }

    private static List<String> contaminationFieldNames() {
        return new List<String>{
            'IsInsertionTubeChannelDistalEnd__c',
            'IsElevatorIrrigationChannel__c',
            'IsAuxiliaryWaterPort__c',
            'IsBiopsyPort__c',
            'IsAirWaterPort__c',
            'IsSuctionPort__c',
            'IsLightGuideTubes__c',
            'IsAirWaterConnectors__c',
            'IsEyePiece__c',
            'IsShaft__c',
            'IsPowerCord__c',
            'IsInstrument__c',
            'IsLockingMechanism__c',
            'IsFootPedal__c',
            'IsOphthalmic__c',
            'ContaminationOther__c'
        };
    }

    /**
     * @description GW-5883 - Saves contamination fields. When Sub Status is Contaminated,
     *              at least one location checkbox or Other is required.
     * @param workOrderId Work Order to update
     * @param subStatus Sub Status being saved
     * @param info Contamination values from the evaluation LWC. Null skips the update.
     * @throws WorkOrdersServiceException when Contaminated is saved with no location and blank Other
     */
    public static void applyContaminationInformation(
        Id workOrderId,
        String subStatus,
        ContaminationInformation info
    ) {
        if (info == null || workOrderId == null) {
            return;
        }
        String otherValue = info.contaminationOther == null
            ? null
            : info.contaminationOther.trim();
        if (String.isBlank(otherValue)) {
            otherValue = null;
        }
        if (
            SUB_STATUS_CONTAMINATED.equalsIgnoreCase(subStatus) &&
            !hasContaminationSelection(info, otherValue)
        ) {
            throw new WorkOrdersServiceException(CONTAMINATION_REQUIRED_MESSAGE);
        }

        WorkOrder updateRow = new WorkOrder(Id = workOrderId);
        updateRow.IsInsertionTubeChannelDistalEnd__c = info.isInsertionTubeChannelDistalEnd == true;
        updateRow.IsElevatorIrrigationChannel__c = info.isElevatorIrrigationChannel == true;
        updateRow.IsAuxiliaryWaterPort__c = info.isAuxiliaryWaterPort == true;
        updateRow.IsBiopsyPort__c = info.isBiopsyPort == true;
        updateRow.IsAirWaterPort__c = info.isAirWaterPort == true;
        updateRow.IsSuctionPort__c = info.isSuctionPort == true;
        updateRow.IsLightGuideTubes__c = info.isLightGuideTubes == true;
        updateRow.IsAirWaterConnectors__c = info.isAirWaterConnectors == true;
        updateRow.IsEyePiece__c = info.isEyePiece == true;
        updateRow.IsShaft__c = info.isShaft == true;
        updateRow.IsPowerCord__c = info.isPowerCord == true;
        updateRow.IsInstrument__c = info.isInstrument == true;
        updateRow.IsLockingMechanism__c = info.isLockingMechanism == true;
        updateRow.IsFootPedal__c = info.isFootPedal == true;
        updateRow.IsOphthalmic__c = info.isOphthalmic == true;
        updateRow.ContaminationOther__c = otherValue;
        persistWorkOrderForDeviceEvaluation(updateRow);
    }

    private static Boolean hasContaminationSelection(
        ContaminationInformation info,
        String otherValue
    ) {
        return info.isInsertionTubeChannelDistalEnd == true ||
            info.isElevatorIrrigationChannel == true ||
            info.isAuxiliaryWaterPort == true ||
            info.isBiopsyPort == true ||
            info.isAirWaterPort == true ||
            info.isSuctionPort == true ||
            info.isLightGuideTubes == true ||
            info.isAirWaterConnectors == true ||
            info.isEyePiece == true ||
            info.isShaft == true ||
            info.isPowerCord == true ||
            info.isInstrument == true ||
            info.isLockingMechanism == true ||
            info.isFootPedal == true ||
            info.isOphthalmic == true ||
            String.isNotBlank(otherValue);
    }

    @TestVisible
    private static void applyEditableWorkOrderFields(
        WorkOrder workOrder,
        Boolean unableToTakePhoto,
        Decimal turnTime,
        String usageCount,
        String evaluationNotes,
        String internalEvaluationNotes,
        String internalSpecialistEvaluationNotes
    ) {
        workOrder.UnableToTakePhoto__c = unableToTakePhoto == true;
        workOrder.TurnTime__c = turnTime;
        workOrder.UsageCount__c = usageCount;
        if (String.isNotBlank(usageCount)) {
            workOrder.UsageCountDate__c = Date.today();
        } else {
            workOrder.UsageCountDate__c = null;
        }
        workOrder.EvaluationNotes__c = evaluationNotes;
        workOrder.InternalEvaluationNotes__c = internalEvaluationNotes;
        workOrder.InternalSpecialistEvaluationNotes__c = internalSpecialistEvaluationNotes;
    }

    /**
     * @description GW-3820 - Applies Continue status mapping when Device Evaluation is initialized.
     *              Received → Evaluate + Eval (sets Owner; Evaluator only if blank).
     *              Ready for Repair → Repair with Sub Status cleared. Other statuses are unchanged.
     * @param workOrder Work Order being initialized
     */
    @TestVisible
    private static void applyInitializeStatusUpdates(WorkOrder workOrder) {
        if (workOrder == null) {
            return;
        }
        if (workOrder.Status == WO_STATUS_RECEIVED) {
            workOrder.Status = WO_STATUS_EVALUATE;
            workOrder.SubStatus__c = WO_SUB_STATUS_EVAL;
            workOrder.OwnerId = UserInfo.getUserId();
            if (workOrder.Evaluator__c == null) {
                workOrder.Evaluator__c = UserInfo.getUserId();
            }
            return;
        }
        if (workOrder.Status == WO_STATUS_READY_FOR_REPAIR) {
            workOrder.Status = WO_STATUS_REPAIR;
            workOrder.SubStatus__c = null;
        }
    }

    /**
     * @description GW-1512 / GW-5830 - Complete Status / Sub Status mapping for Device Evaluation.
     *              On Evaluate: Estimate Required → Quote / Waiting for Approval; missing Customer
     *              PO → Quote / PO Required; otherwise Ready for Repair with blank Sub Status.
     * @param workOrder Work Order being completed
     */
    @TestVisible
    private static void applyCompletionStatus(WorkOrder workOrder) {
        if (workOrder == null) {
            return;
        }
        if (workOrder.Status == WO_STATUS_REPAIR) {
            workOrder.SubStatus__c = WO_SUB_STATUS_READY_FOR_QC;
            return;
        }

        Boolean estimateRequired = ESTIMATE_REQUIRED_VALUE.equals(workOrder.EstimateRequired__c);

        if (estimateRequired) {
            workOrder.Status = WO_STATUS_QUOTE;
            workOrder.SubStatus__c = WO_SUB_STATUS_WAITING_APPROVAL;
        } else if (isMissingRequiredCustomerPo(workOrder)) {
            workOrder.Status = WO_STATUS_QUOTE;
            workOrder.SubStatus__c = WO_SUB_STATUS_PO_REQUIRED;
        } else {
            workOrder.Status = WO_STATUS_READY_FOR_REPAIR;
            workOrder.SubStatus__c = null;
        }
    }

    /**
     * @description GW-3820 / GW-5830 - On Complete, sets parent Work Order Generate Quote to true
     *              when Estimate Required = Estimate Required, or when Sub Status is PO Required,
     *              and a parent Work Order exists.
     * @param workOrder Completed child Work Order
     */
    @TestVisible
    private static void applyParentGenerateQuoteOnComplete(WorkOrder workOrder) {
        if (!shouldGenerateParentQuoteOnComplete(workOrder)) {
            return;
        }
        persistWorkOrderForDeviceEvaluation(
            new WorkOrder(Id = workOrder.ParentWorkOrderId, GenerateQuote__c = true)
        );
    }

    /**
     * @description GW-3820 / GW-5830 - Parent Generate Quote is set for Estimate Required and for
     *              Sub Status PO Required when a parent Work Order exists.
     * @param workOrder Child Work Order after completion status mapping
     * @return True when the parent Generate Quote flag should be set
     */
    @TestVisible
    private static Boolean shouldGenerateParentQuoteOnComplete(WorkOrder workOrder) {
        if (workOrder == null || workOrder.ParentWorkOrderId == null) {
            return false;
        }
        return ESTIMATE_REQUIRED_VALUE.equals(workOrder.EstimateRequired__c) ||
            workOrder.SubStatus__c == WO_SUB_STATUS_PO_REQUIRED;
    }

    private static Boolean hasStagedPhotoAssignments(
        List<ContentDocumentLinksService.StagedPhotoAssignment> stagedPhotos
    ) {
        if (stagedPhotos == null || stagedPhotos.isEmpty()) {
            return false;
        }
        for (ContentDocumentLinksService.StagedPhotoAssignment assignment : stagedPhotos) {
            if (
                assignment != null &&
                assignment.contentDocumentId != null &&
                assignment.productId != null
            ) {
                return true;
            }
        }
        return false;
    }

    private static WorkOrder requireWorkOrderByNumber(String workOrderNumber) {
        WorkOrder workOrder = getWorkOrderForDeviceEvaluationByNumber(workOrderNumber);
        if (workOrder == null) {
            throw new WorkOrdersServiceException('Work Order was not found.');
        }
        return workOrder;
    }

    private static WorkOrder requireWorkOrderById(Id workOrderId) {
        WorkOrder workOrder = getWorkOrderForDeviceEvaluationById(workOrderId);
        if (workOrder == null) {
            throw new WorkOrdersServiceException('Work Order was not found.');
        }
        return workOrder;
    }

    /**
     * @description Resolves a Device Evaluation Work Order from Salesforce Id or WorkOrderNumber.
     * @param workOrderInput Work Order Id or Number
     * @return Matching Work Order, or null when not found
     */
    private static WorkOrder resolveWorkOrderForDeviceEvaluation(String workOrderInput) {
        if (String.isBlank(workOrderInput)) {
            return null;
        }
        String trimmed = workOrderInput.trim();
        if (trimmed.length() == 15 || trimmed.length() == 18) {
            try {
                throwIfSimulated();
                Id candidateId = Id.valueOf(trimmed);
                if (candidateId.getSObjectType() == WorkOrder.SObjectType) {
                    List<WorkOrder> byId = WorkOrdersSelector.selectForDeviceEvaluationById(
                        candidateId
                    );
                    if (!byId.isEmpty()) {
                        return byId[0];
                    }
                }
            } catch (Exception ignore) {
                Logger.debug(
                    new LogMessage(
                        'WorkOrdersService: input is not a valid Work Order Id ({0}); falling back to WorkOrderNumber lookup.',
                        ignore.getMessage()
                    )
                );
            }
        }
        List<WorkOrder> byNumber = WorkOrdersSelector.selectForDeviceEvaluationByNumber(trimmed);
        return byNumber.isEmpty() ? null : byNumber[0];
    }

    private static void persistWorkOrderForDeviceEvaluation(WorkOrder workOrder) {
        try {
            throwIfSimulated();
            updateWorkOrders(new List<WorkOrder>{ workOrder });
        } catch (WorkOrdersServiceException e) {
            if (e.getCause() instanceof DmlException) {
                throw (DmlException) e.getCause();
            }
            throw e;
        }
    }

    /**
     * @description GW-1295 - Resolves Repair Center Devices, Instruments, and Other RecordType Ids.
     * @return Available Repair Center Work Order RecordType Ids
     */
    @TestVisible
    private static Set<Id> getRepairCenterRecordTypeIds() {
        Set<Id> recordTypeIds = new Set<Id>();
        Map<String, Schema.RecordTypeInfo> recordTypes =
            Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName();
        for (String developerName : REPAIR_CENTER_RECORD_TYPES) {
            Schema.RecordTypeInfo recordType = recordTypes.get(developerName);
            if (recordType != null) {
                recordTypeIds.add(recordType.getRecordTypeId());
            }
        }
        return recordTypeIds;
    }

    /****************************************************************************************
     * ADDITIVES FOR SHIP DATE CALCULATION (GW-3164)
     ****************************************************************************************/

    /**
     * @description GW-3164 - Calculates Scheduled Ship Date from Flow.
     * @param inputWorkOrderList List of Work Orders passed from Flow
     */
    @InvocableMethod(label='Calculate Scheduled Ship Date' description='Calculates ship date factoring Turn Time, timezone, and holidays')
    public static void calculateScheduledShipDate(List<WorkOrder> inputWorkOrderList) {
        if (inputWorkOrderList == null || inputWorkOrderList.isEmpty()) {
            return;
        }

        try {
            throwIfSimulated();
            Set<Id> workOrderIdSet = new Set<Id>();
            for (WorkOrder wo : inputWorkOrderList) {
                if (wo.Id != null) {
                    workOrderIdSet.add(wo.Id);
                }
            }
            
            List<WorkOrder> queriedWorkOrderList = WorkOrdersSelector.selectWorkOrdersWithOperatingHours(workOrderIdSet);
            if (queriedWorkOrderList.isEmpty()) {
                return;
            }

            Map<Id, WorkOrder> queriedWorkOrderMap = new Map<Id, WorkOrder>(queriedWorkOrderList);
            Set<Id> operatingHoursIdSet = new Set<Id>();
            
            for (WorkOrder wo : queriedWorkOrderList) {
                if (wo.RepairCenter__r?.OperatingHours__c != null) {
                    operatingHoursIdSet.add(wo.RepairCenter__r.OperatingHours__c);
                }
            }

            List<OperatingHoursHoliday> holidayList = WorkOrdersSelector.selectOperatingHoursHolidays(operatingHoursIdSet);
            Map<Id, Set<Date>> holidayDatesByOperatingHoursIdMap = new Map<Id, Set<Date>>();
            
            for (OperatingHoursHoliday ohh : holidayList) {
                if (!holidayDatesByOperatingHoursIdMap.containsKey(ohh.OperatingHoursId)) {
                    holidayDatesByOperatingHoursIdMap.put(ohh.OperatingHoursId, new Set<Date>());
                }
                if (ohh.Holiday?.ActivityDate != null) {
                    holidayDatesByOperatingHoursIdMap.get(ohh.OperatingHoursId).add(ohh.Holiday.ActivityDate);
                }
            }

            List<WorkOrder> workOrdersToUpdateList = new List<WorkOrder>();

            for (WorkOrder flowWo : inputWorkOrderList) {
                WorkOrder queriedWo = queriedWorkOrderMap.get(flowWo.Id);
                if (queriedWo == null) {
                    continue;
                }
                
                String timeZoneStr = queriedWo.RepairCenter__r?.OperatingHours__r?.TimeZone;
                if (String.isBlank(timeZoneStr) || flowWo.TurnTime__c == null) {
                    continue; 
                }

                Datetime referenceTime = flowWo.DateReadyforRepair__c != null ? flowWo.DateReadyforRepair__c : System.now();
                
                // Parse hour and date strictly in the Location's Timezone
                Integer hourOfDay = Integer.valueOf(referenceTime.format('H', timeZoneStr));
                Date currentDate = Date.valueOf(referenceTime.format('yyyy-MM-dd', timeZoneStr));
                
                // If it is 10:00 AM or later, base start date pushes to tomorrow
                if (hourOfDay >= 10) {
                    currentDate = currentDate.addDays(1);
                }

                Set<Date> centerHolidayDateSet = holidayDatesByOperatingHoursIdMap.containsKey(queriedWo.RepairCenter__r.OperatingHours__c) 
                    ? holidayDatesByOperatingHoursIdMap.get(queriedWo.RepairCenter__r.OperatingHours__c) 
                    : new Set<Date>();

                // Ensure the base start date is not a weekend or holiday
                while (true) {
                    Datetime dtFormat = Datetime.newInstance(currentDate, Time.newInstance(12, 0, 0, 0));
                    String dayOfWeek = dtFormat.format('E');
                    if (dayOfWeek == 'Sat' || dayOfWeek == 'Sun' || centerHolidayDateSet.contains(currentDate)) {
                        currentDate = currentDate.addDays(1);
                    } else {
                        break; 
                    }
                }

                // Calculate using the fresh Turn Time from the Flow (Which already includes aeration days via GW-3459)
                Integer turnTimeDays = Integer.valueOf(flowWo.TurnTime__c);

                Integer daysToAdd = turnTimeDays > 0 ? turnTimeDays - 1 : 0;
                Integer daysAdded = 0;
                
                while (daysAdded < daysToAdd) {
                    currentDate = currentDate.addDays(1);
                    Datetime dtFormat = Datetime.newInstance(currentDate, Time.newInstance(12, 0, 0, 0));
                    String dayOfWeek = dtFormat.format('E');
                    
                    if (dayOfWeek != 'Sat' && dayOfWeek != 'Sun' && !centerHolidayDateSet.contains(currentDate)) {
                        daysAdded++;
                    }
                }

                // Construct a new record instance for update 
                workOrdersToUpdateList.add(new WorkOrder(
                    Id = flowWo.Id,
                    ScheduledShipDate__c = currentDate
                ));
            }

            if (!workOrdersToUpdateList.isEmpty()) {
                update workOrdersToUpdateList;
            }

        } catch (Exception e) {
            Logger.error('Error calculating Scheduled Ship Date: ' + e.getMessage());
        } finally {
            Logger.saveLog();
        }
    }

    /****************************************************************************************
     * ADDITIVES FOR DIVIDE INSTRUMENTS (GW-2891)
     ****************************************************************************************/

    private static final String WO_STATUS_DIVIDE = 'Divide';
    private static final String WO_STATUS_EVALUATE_AND_QUOTE = 'Evaluate & Quote';
    private static final String WO_SUB_STATUS_WARRANTY_INSPECTION = 'Warranty Inspection';
    private static final String WO_SUB_STATUS_STERIS = 'STERIS';
    private static final String ESTIMATE_PRE_APPROVED = 'Pre-Approved';
    private static final String ESTIMATE_ORDER_ACKNOWLEDGEMENT = 'Order Acknowledgement';
    private static final String WARRANTY_YES = 'Yes';
    private static final String WARRANTY_NO = 'No';
    private static final String RECORD_TYPE_INSTRUMENTS = 'RepairCenterInstruments';
    private static final String QUANTITY_MISMATCH_MESSAGE =
        'Your total quantity does not match the quantity received.  ' +
        'Please make the necessary corrections before proceeding';
    private static final String INSTRUMENT_EVAL_QUANTITY_RECEIVED_REQUIRED_MESSAGE =
        'Quantity Received is required.';
    private static final String INSTRUMENT_EVAL_QUANTITY_MISMATCH_MESSAGE =
        'Total item quantity must equal Quantity Received before continuing to Summary.';
    private static final String LABELS_NOT_WIRED_MESSAGE =
        'Child Work Orders were created. Bin labels are not wired yet.';
    @TestVisible
    private static final String DIVIDE_INSTRUMENTS_RT_REQUIRED_MESSAGE =
        'Divide Instruments applies only to Repair Center - Instruments Work Orders.';
    @TestVisible
    private static final String DIVIDE_PARENT_WO_REQUIRED_MESSAGE =
        'Divide Instruments applies only to parent Work Orders.';
    /** Exact Product Line for Instrument Eval / Divide Instruments Photos Required prefs. */
    @TestVisible
    private static final String INSTRUMENT_PHOTOS_REQUIRED_PRODUCT_LINE = 'Instrument';
    @TestVisible
    private static final String DIVIDE_PHOTOS_REQUIRED_PRODUCT_LINE =
        INSTRUMENT_PHOTOS_REQUIRED_PRODUCT_LINE;
    @TestVisible
    private static final Integer BIN_QTY_MIN = 1;
    @TestVisible
    private static final Integer BIN_QTY_MAX = 99;

    /**
     * @description GW-2891 - One bin row from the Divide Instruments repeater.
     */
    public class DivideInstrumentsBin {
        public Id childWorkOrderId;
        public String repairCategory;
        public Decimal quantity;
        public Decimal turnTime;
    }

    /**
     * @description GW-2891 - Parent Work Order context for the Divide Instruments LWC.
     */
    public class DivideInstrumentsContext {
        public WorkOrder workOrder;
        public Id instrumentsRecordTypeId;
        public String labelsWarning;
        public List<DivideInstrumentsBin> existingBins = new List<DivideInstrumentsBin>();
    }

    /**
     * @description GW-2891 - Loads the Work Order by Id and sets Status = Divide, Owner = current user.
     * @param workOrderId Salesforce Id of the scanned Work Order
     * @return DivideInstrumentsContext
     */
    public static DivideInstrumentsContext initializeDivideInstruments(Id workOrderId) {
        if (workOrderId == null) {
            throw new WorkOrdersServiceException('Work Order is required.');
        }
        WorkOrder workOrder = requireWorkOrderForDivide(workOrderId);
        workOrder.Status = WO_STATUS_DIVIDE;
        workOrder.OwnerId = UserInfo.getUserId();
        updateWorkOrders(new List<WorkOrder>{ workOrder });
        return buildDivideInstrumentsContext(requireWorkOrderForDivide(workOrderId), null);
    }

    /**
     * @description GW-2891 / GW-5748 - Validates bin quantities and reconciles child Work Orders
     *              (insert, update, delete) to match the bin rows. Sets parent Status to the
     *              same resolved Status as the children and clears parent Sub Status. Clones
     *              parent Service Code WOLIs onto each child using the bin Quantity.
     * @param workOrderId Parent Work Order Id
     * @param quantityReceived Quantity Received from the UI
     * @param bins Bin rows
     * @return DivideInstrumentsContext including a labels stub warning
     */
    public static DivideInstrumentsContext completeDivideInstruments(
        Id workOrderId,
        Decimal quantityReceived,
        List<DivideInstrumentsBin> bins
    ) {
        if (workOrderId == null) {
            throw new WorkOrdersServiceException('Work Order is required.');
        }
        if (quantityReceived == null) {
            throw new WorkOrdersServiceException('Quantity Received is required.');
        }
        validateBins(bins);

        Decimal binTotal = 0;
        Set<String> categories = new Set<String>();
        for (DivideInstrumentsBin bin : bins) {
            binTotal += bin.quantity;
            categories.add(bin.repairCategory);
        }
        if (binTotal != quantityReceived) {
            throw new WorkOrdersServiceException(QUANTITY_MISMATCH_MESSAGE);
        }

        WorkOrder parent = requireWorkOrderForDivide(workOrderId);
        parent.QuantityReceived__c = quantityReceived;
        parent.Status = resolveChildStatus(parent);
        parent.SubStatus__c = null;
        updateWorkOrders(new List<WorkOrder>{ parent });
        parent = requireWorkOrderForDivide(workOrderId);

        Map<Id, WorkOrder> existingChildrenById = mapExistingChildWorkOrdersForDivide(workOrderId);
        validateChildWorkOrderReferences(workOrderId, bins, existingChildrenById);

        Set<Id> referencedChildIds = new Set<Id>();
        for (DivideInstrumentsBin bin : bins) {
            if (bin.childWorkOrderId != null) {
                referencedChildIds.add(bin.childWorkOrderId);
            }
        }
        Set<Id> orphanChildIds = new Set<Id>(existingChildrenById.keySet());
        orphanChildIds.removeAll(referencedChildIds);

        Map<String, Id> rackIdByCategory = mapFirstRackIdByCategory(categories);
        Boolean photosRequired = resolveDivideInstrumentsPhotosRequired(parent);
        List<WorkOrder> childrenToInsert = new List<WorkOrder>();
        List<WorkOrder> childrenToUpdate = new List<WorkOrder>();
        for (DivideInstrumentsBin bin : bins) {
            if (bin.childWorkOrderId != null) {
                WorkOrder child = existingChildrenById.get(bin.childWorkOrderId);
                applyChildFieldValues(parent, child, bin, rackIdByCategory, photosRequired);
                childrenToUpdate.add(child);
            } else {
                childrenToInsert.add(
                    buildChildWorkOrder(parent, bin, rackIdByCategory, photosRequired)
                );
            }
        }

        deleteWorkOrders(orphanChildIds);
        updateWorkOrders(childrenToUpdate);
        createWorkOrders(childrenToInsert);
        syncServiceCodeLinesForDivideChildren(parent, bins, childrenToInsert);

        List<WorkOrder> childrenForShipDate = new List<WorkOrder>();
        childrenForShipDate.addAll(childrenToUpdate);
        childrenForShipDate.addAll(childrenToInsert);
        applyDivideChildScheduledShipDates(childrenForShipDate);
        rollupDivideParentTurnTimeAndShipDate(parent.Id);

        return buildDivideInstrumentsContext(
            requireWorkOrderForDivide(workOrderId),
            LABELS_NOT_WIRED_MESSAGE
        );
    }

    /**
     * @description GW-5748 - Clones parent Service Code WOLIs onto each Divide child Work Order.
     *              Quantity is the bin quantity for that child. Existing clones (matched by
     *              Price Book Entry / Product) are updated instead of duplicated.
     *              ParentWorkOrderLineItemId is not copied: Salesforce requires parent and
     *              child WOLIs to belong to the same Work Order.
     * @param parent Parent Instrument Work Order
     * @param bins Bin rows used to create or update children
     * @param insertedChildren Child Work Orders inserted in this transaction (Ids populated)
     */
    private static void syncServiceCodeLinesForDivideChildren(
        WorkOrder parent,
        List<DivideInstrumentsBin> bins,
        List<WorkOrder> insertedChildren
    ) {
        List<WorkOrderLineItem> parentServiceCodes =
            WorkOrderLineItemsSelector.selectServiceCodeLinesByWorkOrderId(parent.Id);
        if (parentServiceCodes.isEmpty()) {
            return;
        }

        Map<Id, Decimal> quantityByChildId = mapDivideChildQuantities(bins, insertedChildren);
        if (quantityByChildId.isEmpty()) {
            return;
        }

        List<WorkOrderLineItem> existingChildLines =
            WorkOrderLineItemsSelector.selectServiceCodeLinesByWorkOrderIds(
                quantityByChildId.keySet()
            );
        Map<String, WorkOrderLineItem> existingByChildAndProduct =
            new Map<String, WorkOrderLineItem>();
        for (WorkOrderLineItem existingLine : existingChildLines) {
            existingByChildAndProduct.put(
                existingLine.WorkOrderId + '-' + divideServiceCodeMatchKey(existingLine),
                existingLine
            );
        }

        List<WorkOrderLineItem> linesToInsert = new List<WorkOrderLineItem>();
        List<WorkOrderLineItem> linesToUpdate = new List<WorkOrderLineItem>();
        for (Id childWorkOrderId : quantityByChildId.keySet()) {
            Decimal childQuantity = quantityByChildId.get(childWorkOrderId);
            for (WorkOrderLineItem parentLine : parentServiceCodes) {
                String existingKey =
                    childWorkOrderId + '-' + divideServiceCodeMatchKey(parentLine);
                WorkOrderLineItem existingLine = existingByChildAndProduct.get(existingKey);
                if (existingLine != null) {
                    if (existingLine.Quantity != childQuantity) {
                        existingLine.Quantity = childQuantity;
                        linesToUpdate.add(existingLine);
                    }
                } else {
                    linesToInsert.add(
                        cloneServiceCodeLineForDivideChild(
                            parentLine,
                            parent.Id,
                            childWorkOrderId,
                            childQuantity
                        )
                    );
                }
            }
        }

        try {
            WorkOrderLineItemsService.createLineItems(linesToInsert);
            WorkOrderLineItemsService.updateLineItems(linesToUpdate);
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            throw new WorkOrdersServiceException(e.getMessage(), e);
        }
    }

    /**
     * @description Maps each Divide child Work Order Id to its bin Quantity.
     * @param bins Bin rows in the same order used to insert children
     * @param insertedChildren Newly inserted children, parallel to bins without childWorkOrderId
     * @return Child Work Order Id to Quantity
     */
    private static Map<Id, Decimal> mapDivideChildQuantities(
        List<DivideInstrumentsBin> bins,
        List<WorkOrder> insertedChildren
    ) {
        Map<Id, Decimal> quantityByChildId = new Map<Id, Decimal>();
        Integer insertIndex = 0;
        for (DivideInstrumentsBin bin : bins) {
            if (bin.childWorkOrderId != null) {
                quantityByChildId.put(bin.childWorkOrderId, bin.quantity);
            } else if (
                insertedChildren != null &&
                insertIndex < insertedChildren.size() &&
                insertedChildren[insertIndex].Id != null
            ) {
                quantityByChildId.put(insertedChildren[insertIndex].Id, bin.quantity);
                insertIndex++;
            } else if (insertedChildren != null) {
                insertIndex++;
            }
        }
        return quantityByChildId;
    }

    /**
     * @description GW-5748 - Builds a child Service Code WOLI from the parent line.
     * @param parentLine Parent Service Code Work Order Line Item
     * @param parentWorkOrderId Parent Instrument Work Order Id (Top Level fallback)
     * @param childWorkOrderId Child Work Order Id
     * @param quantity Quantity Specified during Divide for this child
     * @return Child WOLI ready to insert
     */
    private static WorkOrderLineItem cloneServiceCodeLineForDivideChild(
        WorkOrderLineItem parentLine,
        Id parentWorkOrderId,
        Id childWorkOrderId,
        Decimal quantity
    ) {
        WorkOrderLineItem childLine = new WorkOrderLineItem();
        childLine.RecordTypeId = parentLine.RecordTypeId;
        childLine.LineType__c = parentLine.LineType__c;
        childLine.AssetId = parentLine.AssetId;
        childLine.SerialNumber__c = parentLine.SerialNumber__c;
        childLine.Model__c = parentLine.Model__c;
        childLine.Item__c = parentLine.Item__c;
        childLine.ItemCode__c = parentLine.ItemCode__c;
        childLine.ItemDescription__c = parentLine.ItemDescription__c;
        if (parentLine.PricebookEntryId != null) {
            childLine.PricebookEntryId = parentLine.PricebookEntryId;
        } else if (parentLine.Product2Id != null) {
            childLine.Product2Id = parentLine.Product2Id;
        }
        childLine.ProductCodeWoli__c = parentLine.ProductCodeWoli__c;
        childLine.ProductDescription__c = parentLine.ProductDescription__c;
        childLine.WorkOrderId = childWorkOrderId;
        childLine.TopLevelWorkOrder__c = parentLine.TopLevelWorkOrder__c != null
            ? parentLine.TopLevelWorkOrder__c
            : parentWorkOrderId;
        childLine.Quantity = quantity;
        childLine.Status = parentLine.Status;
        return childLine;
    }

    /**
     * @description GW-5748 - Matches a parent Service Code to an existing child clone.
     *              Standard ParentWorkOrderLineItemId cannot point across Work Orders.
     * @param line Service Code Work Order Line Item
     * @return Stable match key
     */
    private static String divideServiceCodeMatchKey(WorkOrderLineItem line) {
        if (line.PricebookEntryId != null) {
            return String.valueOf(line.PricebookEntryId);
        }
        if (line.Product2Id != null) {
            return 'P:' + line.Product2Id;
        }
        if (String.isNotBlank(line.ProductCodeWoli__c)) {
            return 'C:' + line.ProductCodeWoli__c;
        }
        return 'I:' + line.Id;
    }

    /**
     * @description RecordType Id for Repair Center - Instruments (dynamic Repair Category picklist).
     * @return RecordType Id, or null when the record type is not in the org
     */
    public static Id getInstrumentsRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'WorkOrder'
                AND DeveloperName = :RECORD_TYPE_INSTRUMENTS
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }

    @TestVisible
    static String resolveChildStatus(WorkOrder parent) {
        Boolean estimateOk =
            parent.EstimateRequired__c == ESTIMATE_PRE_APPROVED ||
            parent.EstimateRequired__c == ESTIMATE_ORDER_ACKNOWLEDGEMENT;
        Boolean poOk =
            parent.CustomerPORequired__c != true ||
            String.isNotBlank(parent.CustomerPO__c);
        // Blank Repair Warranty is not warranty repair; only explicit Yes blocks Ready for Repair.
        Boolean warrantyNo = parent.RepairWarranty__c != WARRANTY_YES;
        Boolean cioFalse = parent.ContinuousImprovementOpportunity__c != true;
        if (estimateOk && poOk && warrantyNo && cioFalse) {
            return WO_STATUS_READY_FOR_REPAIR;
        }
        return WO_STATUS_EVALUATE_AND_QUOTE;
    }

    /**
     * @description GW-2891 - Resolves child Sub Status. Warranty / CIO sets Warranty Inspection.
     *              Estimate Required / missing Customer PO leave Sub Status blank (no Waiting for Approval).
     * @param parent Parent Instruments Work Order
     * @return Sub Status value, or null when blank / Ready for Repair path
     */
    @TestVisible
    static String resolveChildSubStatus(WorkOrder parent) {
        if (
            parent.RepairWarranty__c == WARRANTY_YES ||
            parent.ContinuousImprovementOpportunity__c == true
        ) {
            return WO_SUB_STATUS_WARRANTY_INSPECTION;
        }
        return null;
    }

    private static void validateBins(List<DivideInstrumentsBin> bins) {
        if (bins == null || bins.isEmpty()) {
            throw new WorkOrdersServiceException('Add at least one bin before completing.');
        }
        for (DivideInstrumentsBin bin : bins) {
            if (bin == null || String.isBlank(bin.repairCategory)) {
                throw new WorkOrdersServiceException('Repair Category is required for each bin.');
            }
            if (bin.quantity == null || bin.quantity != bin.quantity.intValue()) {
                throw new WorkOrdersServiceException('Qty must be a whole number between 1 and 99.');
            }
            Integer qty = bin.quantity.intValue();
            if (qty < BIN_QTY_MIN || qty > BIN_QTY_MAX) {
                throw new WorkOrdersServiceException('Qty must be a whole number between 1 and 99.');
            }
            if (bin.turnTime == null || bin.turnTime != bin.turnTime.intValue()) {
                throw new WorkOrdersServiceException(
                    'Turn Time must be a whole number between 1 and 99.'
                );
            }
            Integer turnTime = bin.turnTime.intValue();
            if (turnTime < BIN_QTY_MIN || turnTime > BIN_QTY_MAX) {
                throw new WorkOrdersServiceException(
                    'Turn Time must be a whole number between 1 and 99.'
                );
            }
        }
    }

    private static Map<String, Id> mapFirstRackIdByCategory(Set<String> categories) {
        Map<String, Id> rackIdByCategory = new Map<String, Id>();
        for (Schema.Location rack : LocationsSelector.selectRacksByRepairCategories(categories)) {
            if (!rackIdByCategory.containsKey(rack.Repair_Category__c)) {
                rackIdByCategory.put(rack.Repair_Category__c, rack.Id);
            }
        }
        return rackIdByCategory;
    }

    private static WorkOrder buildChildWorkOrder(
        WorkOrder parent,
        DivideInstrumentsBin bin,
        Map<String, Id> rackIdByCategory,
        Boolean photosRequired
    ) {
        WorkOrder child = new WorkOrder();
        applyChildFieldValues(parent, child, bin, rackIdByCategory, photosRequired);
        return child;
    }

    /**
     * @description GW-2891 - Applies parent/bin field values onto a child Work Order.
     *              Photos Required is set from active IMS Customer Preferences (Preference Type =
     *              Photos required; Product Line = Instrument exact), not copied from the parent
     *              Photos Required checkbox.
     */
    private static void applyChildFieldValues(
        WorkOrder parent,
        WorkOrder child,
        DivideInstrumentsBin bin,
        Map<String, Id> rackIdByCategory,
        Boolean photosRequired
    ) {
        String status = resolveChildStatus(parent);
        child.RecordTypeId = parent.RecordTypeId;
        child.ParentWorkOrderId = parent.Id;
        child.Status = status;
        child.SubStatus__c = resolveChildSubStatus(parent);
        child.Department__c = parent.Department__c;
        child.CustomerPO__c = parent.CustomerPO__c;
        child.CustomerPORequired__c = parent.CustomerPORequired__c;
        child.AccountId = parent.AccountId;
        child.ContactId = parent.ContactId;
        child.EstimateContact__c = parent.EstimateContact__c;
        child.AssignedSalesPerson__c = parent.AssignedSalesPerson__c;
        child.CreditStatusCode__c = parent.CreditStatusCode__c;
        child.ReturnOrderLineItemId = parent.ReturnOrderLineItemId;
        child.ReturnOrder__c = parent.ReturnOrder__c;
        child.RepairCenter__c = parent.RepairCenter__c;
        child.OperatingUnit__c = parent.OperatingUnit__c;
        child.LocationId = parent.LocationId;
        child.Receiver__c = parent.Receiver__c;
        child.QuantityReceived__c = bin.quantity;
        child.WarrantyNotes__c = parent.WarrantyNotes__c;
        child.RepairWarranty__c = parent.RepairWarranty__c;
        child.ContinuousImprovementOpportunity__c = parent.ContinuousImprovementOpportunity__c;
        child.EstimateRequired__c = parent.EstimateRequired__c;
        child.RepairCategory__c = bin.repairCategory;
        child.TurnTime__c = bin.turnTime;
        child.Subject = parent.Subject;
        child.Description = parent.Description;
        // GW-5677: child Instrument Work Orders keep the parent's additional services list.
        child.AdditionalServicesRequested__c = parent.AdditionalServicesRequested__c;
        // GW-2891 / GW-3400 - IE Complete uses WO.Price Book for Product Serviced PBEs
        child.Pricebook2Id = parent.Pricebook2Id;
        child.CurrencyIsoCode = parent.CurrencyIsoCode;
        child.OwnerId = UserInfo.getUserId();
        child.CustomerReference__c = parent.CustomerReference__c;
        child.Contaminated__c = parent.Contaminated__c;
        child.PhotosRequired__c = photosRequired == true;
        child.CaseId = parent.CaseId;
        child.ModRequest__c = parent.ModRequest__c;
        if (status == WO_STATUS_READY_FOR_REPAIR) {
            child.Rack__c = rackIdByCategory.get(bin.repairCategory);
            // GW-2891: stamp Date Ready for Repair on create (and when still blank on update)
            if (child.DateReadyforRepair__c == null) {
                child.DateReadyforRepair__c = System.now();
            }
        } else {
            child.Rack__c = null;
        }
    }

    /**
     * @description GW-3400 - Calculates Scheduled Ship Date for Divide Instruments children via the
     *              shared invocable used by Work Order Updated After Save.
     * @param children Inserted or updated child Work Orders (must include Id and Turn Time)
     */
    @TestVisible
    private static void applyDivideChildScheduledShipDates(List<WorkOrder> children) {
        if (children == null || children.isEmpty()) {
            return;
        }
        List<WorkOrder> shipDateInputs = new List<WorkOrder>();
        for (WorkOrder child : children) {
            if (child == null || child.Id == null || child.TurnTime__c == null) {
                continue;
            }
            shipDateInputs.add(
                new WorkOrder(
                    Id = child.Id,
                    TurnTime__c = child.TurnTime__c,
                    DateReadyforRepair__c = child.DateReadyforRepair__c
                )
            );
        }
        if (!shipDateInputs.isEmpty()) {
            calculateScheduledShipDate(shipDateInputs);
        }
    }

    /**
     * @description GW-3400 / GW-2891 - Sets parent Turn Time to the largest child Turn Time and parent
     *              Scheduled Ship Date to the latest child Scheduled Ship Date.
     * @param parentWorkOrderId Parent Work Order Id
     */
    @TestVisible
    private static void rollupDivideParentTurnTimeAndShipDate(Id parentWorkOrderId) {
        if (parentWorkOrderId == null) {
            return;
        }
        Decimal maxTurnTime = null;
        Date latestShipDate = null;
        for (WorkOrder child : WorkOrdersSelector.selectChildWorkOrdersForDivideInstruments(
            parentWorkOrderId
        )) {
            if (child.TurnTime__c != null && (maxTurnTime == null || child.TurnTime__c > maxTurnTime)) {
                maxTurnTime = child.TurnTime__c;
            }
            if (
                child.ScheduledShipDate__c != null &&
                (latestShipDate == null || child.ScheduledShipDate__c > latestShipDate)
            ) {
                latestShipDate = child.ScheduledShipDate__c;
            }
        }
        updateWorkOrders(
            new List<WorkOrder>{
                new WorkOrder(
                    Id = parentWorkOrderId,
                    TurnTime__c = maxTurnTime,
                    ScheduledShipDate__c = latestShipDate
                )
            }
        );
    }

    /**
     * @description GW-2891 - Resolves Photos Required for Divide Instruments child Work Orders from
     *              Customer Preferences (Account + IMS RT + Photos required + date window + Product
     *              Line = Instrument exact match).
     * @param parent Parent Work Order
     * @return True when a matching preference exists
     */
    @TestVisible
    private static Boolean resolveDivideInstrumentsPhotosRequired(WorkOrder parent) {
        if (parent == null || parent.AccountId == null) {
            return false;
        }
        try {
            throwIfSimulated();
            return CustomerPreferencesService.isPhotosRequiredExactProductLine(
                parent.AccountId,
                DIVIDE_PHOTOS_REQUIRED_PRODUCT_LINE
            );
        } catch (CustomerPreferencesService.CustomerPreferencesServiceException e) {
            throw new WorkOrdersServiceException(e.getMessage(), e);
        }
    }

    private static Map<Id, WorkOrder> mapExistingChildWorkOrdersForDivide(Id parentWorkOrderId) {
        Map<Id, WorkOrder> childrenById = new Map<Id, WorkOrder>();
        for (WorkOrder child : WorkOrdersSelector.selectChildWorkOrdersForDivideInstruments(
            parentWorkOrderId
        )) {
            childrenById.put(child.Id, child);
        }
        return childrenById;
    }

    private static void validateChildWorkOrderReferences(
        Id parentWorkOrderId,
        List<DivideInstrumentsBin> bins,
        Map<Id, WorkOrder> existingChildrenById
    ) {
        Set<Id> referencedChildIds = new Set<Id>();
        for (DivideInstrumentsBin bin : bins) {
            if (bin == null || bin.childWorkOrderId == null) {
                continue;
            }
            if (referencedChildIds.contains(bin.childWorkOrderId)) {
                throw new WorkOrdersServiceException(
                    'Each child Work Order can only appear once in the bin list.'
                );
            }
            referencedChildIds.add(bin.childWorkOrderId);
            WorkOrder existingChild = existingChildrenById.get(bin.childWorkOrderId);
            if (existingChild == null || existingChild.ParentWorkOrderId != parentWorkOrderId) {
                throw new WorkOrdersServiceException(
                    'One or more bin rows reference an invalid child Work Order.'
                );
            }
        }
    }

    private static List<DivideInstrumentsBin> mapExistingDivideBins(Id parentWorkOrderId) {
        List<DivideInstrumentsBin> existingBins = new List<DivideInstrumentsBin>();
        for (WorkOrder child : WorkOrdersSelector.selectChildWorkOrdersForDivideInstruments(
            parentWorkOrderId
        )) {
            DivideInstrumentsBin bin = new DivideInstrumentsBin();
            bin.childWorkOrderId = child.Id;
            bin.repairCategory = child.RepairCategory__c;
            bin.quantity = child.QuantityReceived__c;
            bin.turnTime = child.TurnTime__c;
            existingBins.add(bin);
        }
        return existingBins;
    }

    private static WorkOrder requireWorkOrderForDivide(Id workOrderId) {
        List<WorkOrder> workOrders = WorkOrdersSelector.selectForDivideInstrumentsById(workOrderId);
        if (workOrders.isEmpty()) {
            throw new WorkOrdersServiceException('Work Order was not found.');
        }
        WorkOrder workOrder = workOrders[0];
        validateWorkOrderEligibleForDivide(workOrder);
        return workOrder;
    }

    private static void validateWorkOrderEligibleForDivide(WorkOrder workOrder) {
        if (
            workOrder.RecordType == null ||
            workOrder.RecordType.DeveloperName != RECORD_TYPE_INSTRUMENTS
        ) {
            throw new WorkOrdersServiceException(DIVIDE_INSTRUMENTS_RT_REQUIRED_MESSAGE);
        }
        if (workOrder.ParentWorkOrderId != null) {
            throw new WorkOrdersServiceException(DIVIDE_PARENT_WO_REQUIRED_MESSAGE);
        }
    }

    private static DivideInstrumentsContext buildDivideInstrumentsContext(
        WorkOrder workOrder,
        String labelsWarning
    ) {
        DivideInstrumentsContext context = new DivideInstrumentsContext();
        context.workOrder = workOrder;
        context.instrumentsRecordTypeId = getInstrumentsRecordTypeId();
        context.labelsWarning = labelsWarning;
        context.existingBins = mapExistingDivideBins(workOrder.Id);
        return context;
    }

    /****************************************************************************************
     * ADDITIVES FOR INSTRUMENT EVALUATION (GW-3400)
     ****************************************************************************************/

    @TestVisible
    private static final String INSTRUMENT_EVALUATION_RT_REQUIRED_MESSAGE =
        'Instrument Evaluation applies only to Repair Center - Instruments Work Orders.';
    @TestVisible
    private static final String INSTRUMENT_EVALUATION_CHILD_WO_REQUIRED_MESSAGE =
        'Instrument Evaluation applies only to child Work Orders.';
    private static final String INSTRUMENT_EVALUATION_PRODUCT_LINE = 'Instruments';
    @TestVisible
    private static final String INSTRUMENT_EVALUATION_STATUS_NOT_ELIGIBLE_MESSAGE =
        'This Work Order Status is not eligible for Instrument Evaluation.';

    /**
     * @description GW-3400 - Initializes a child Repair Center - Instruments Work Order and returns
     *              context. Eligible Status values: Evaluate & Quote, Ready for Repair, Repair.
     *              Evaluate & Quote: Owner = current user; Evaluator if blank.
     *              Ready for Repair: Status = Repair, Sub Status = STERIS.
     * @param workOrderInput Work Order Salesforce Id or WorkOrderNumber
     * @return InstrumentEvaluationContext for Aura DTO mapping
     * @throws WorkOrdersServiceException for validation or retrieve failures
     */
    public static InstrumentEvaluationContext initializeInstrumentEvaluation(String workOrderInput) {
        WorkOrder workOrder = resolveWorkOrderForInstrumentEvaluation(workOrderInput);
        if (workOrder == null) {
            throw new WorkOrdersServiceException('Work Order was not found.');
        }
        validateWorkOrderEligibleForInstrumentEvaluation(workOrder);

        // Photos Required: exact Product Line = Instrument (blank Product Line prefs excluded)
        Boolean photosRequired = CustomerPreferencesService.isPhotosRequiredExactProductLine(
            workOrder.AccountId,
            INSTRUMENT_PHOTOS_REQUIRED_PRODUCT_LINE
        );
        Boolean dirty = applyInstrumentEvaluationInitializeUpdates(workOrder);
        if (workOrder.PhotosRequired__c != photosRequired) {
            workOrder.PhotosRequired__c = photosRequired;
            dirty = true;
        }
        if (dirty) {
            persistWorkOrderForDeviceEvaluation(workOrder);
            workOrder = requireWorkOrderById(workOrder.Id);
        }
        return buildInstrumentEvaluationContext(workOrder, photosRequired);
    }

    /**
     * @description GW-3400 - Resolves a Work Order by Salesforce Id (Work Order type only) or
     *              WorkOrderNumber. Avoids treating arbitrary 15/18-character values as Ids of
     *              other SObjects, which can resolve the wrong record in tests with bulk setup data.
     * @param workOrderInput Work Order Id or Number
     * @return Matching Work Order, or null when not found
     */
    private static WorkOrder resolveWorkOrderForInstrumentEvaluation(String workOrderInput) {
        if (String.isBlank(workOrderInput)) {
            return null;
        }
        String trimmed = workOrderInput.trim();
        if (trimmed.length() == 15 || trimmed.length() == 18) {
            try {
                throwIfSimulated();
                Id candidateId = Id.valueOf(trimmed);
                if (candidateId.getSObjectType() == WorkOrder.SObjectType) {
                    List<WorkOrder> byId = WorkOrdersSelector.selectForDeviceEvaluationById(
                        candidateId
                    );
                    if (!byId.isEmpty()) {
                        return byId[0];
                    }
                }
            } catch (Exception ignore) {
                Logger.debug(
                    new LogMessage(
                        'WorkOrdersService: input is not a valid Work Order Id ({0}); falling back to WorkOrderNumber lookup.',
                        ignore.getMessage()
                    )
                );
            }
        }
        List<WorkOrder> byNumber = WorkOrdersSelector.selectForInstrumentEvaluationByNumber(trimmed);
        if (byNumber.isEmpty()) {
            return null;
        }
        // Prefer Instruments Work Orders when WorkOrderNumber is duplicated (parent or child).
        for (WorkOrder candidate : byNumber) {
            if (
                candidate.RecordType != null &&
                candidate.RecordType.DeveloperName == RECORD_TYPE_INSTRUMENTS
            ) {
                return candidate;
            }
        }
        return byNumber[0];
    }

    /**
     * @description GW-3400 - Persists editable Instrument Evaluation header and notes fields.
     * @param workOrderId Parent Work Order Id
     * @param subStatus Sub Status value
     * @param unableToTakePhoto Unable To Take Photo checkbox
     * @param turnTime Turn Time
     * @param quantityReceived Quantity Received (required)
     * @param evaluationNotes Customer-facing evaluation notes
     * @param internalEvaluationNotes Internal evaluation notes
     * @param internalSpecialistEvaluationNotes Internal specialist notes
     * @return InstrumentEvaluationContext for Aura DTO mapping
     * @throws WorkOrdersServiceException for validation or DML failures
     */
    public static InstrumentEvaluationContext saveInstrumentEvaluationWorkOrderFields(
        Id workOrderId,
        String subStatus,
        Boolean unableToTakePhoto,
        Decimal turnTime,
        Decimal quantityReceived,
        String evaluationNotes,
        String internalEvaluationNotes,
        String internalSpecialistEvaluationNotes
    ) {
        if (workOrderId == null) {
            throw new WorkOrdersServiceException('Work Order is required.');
        }
        if (quantityReceived == null) {
            throw new WorkOrdersServiceException('Quantity Received is required.');
        }
        WorkOrder workOrder = requireWorkOrderById(workOrderId);
        validateWorkOrderEligibleForInstrumentEvaluation(workOrder);
        validateInstrumentEvaluationSubStatusChange(workOrder, subStatus);
        workOrder.SubStatus__c = subStatus;
        workOrder.UnableToTakePhoto__c = unableToTakePhoto == true;
        workOrder.TurnTime__c = turnTime;
        workOrder.QuantityReceived__c = quantityReceived;
        workOrder.EvaluationNotes__c = evaluationNotes;
        workOrder.InternalEvaluationNotes__c = internalEvaluationNotes;
        workOrder.InternalSpecialistEvaluationNotes__c = internalSpecialistEvaluationNotes;
        persistWorkOrderForDeviceEvaluation(workOrder);

        workOrder = requireWorkOrderById(workOrderId);
        Boolean photosRequired = CustomerPreferencesService.isPhotosRequiredExactProductLine(
            workOrder.AccountId,
            INSTRUMENT_PHOTOS_REQUIRED_PRODUCT_LINE
        );
        if (workOrder.PhotosRequired__c != photosRequired) {
            workOrder.PhotosRequired__c = photosRequired;
            persistWorkOrderForDeviceEvaluation(workOrder);
            workOrder = requireWorkOrderById(workOrderId);
        }
        return buildInstrumentEvaluationContext(workOrder, photosRequired);
    }

    /**
     * @description GW-3400 - Returns unique Eval Category cards for the Item Selection wizard.
     *              Blank Work Order Repair Category includes products across all Sub Product Lines.
     * @param workOrderId Parent Work Order Id
     * @return Eval Category cards sorted by Eval Rank
     * @throws WorkOrdersServiceException for validation or unexpected failures
     */
    public static List<InstrumentEvalCategoryCard> getInstrumentEvaluationEvalCategories(
        Id workOrderId
    ) {
        Logger.setScenario('Instrument Evaluation');
        try {
            throwIfSimulated();
            WorkOrder workOrder = requireInstrumentEvaluationWorkOrder(workOrderId);
            List<Product2> products = ProductsSelector.selectForInstrumentEvaluation(
                INSTRUMENT_EVALUATION_PRODUCT_LINE,
                workOrder.RepairCategory__c
            );
            return buildUniqueEvalCategoryCards(products);
        } catch (WorkOrdersServiceException e) {
            throw e;
        } catch (Exception e) {
            logInstrumentEvaluationUnexpectedError(
                'getInstrumentEvaluationEvalCategories',
                workOrderId,
                e
            );
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while loading evaluation categories.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3400 - Returns products for a selected Eval Category.
     *              Blank Work Order Repair Category includes products across all Sub Product Lines.
     * @param workOrderId Parent Work Order Id
     * @param evalCategory Selected Eval Category
     * @return Product cards ordered by item number
     * @throws WorkOrdersServiceException for validation or unexpected failures
     */
    public static List<InstrumentProductCard> getInstrumentEvaluationProducts(
        Id workOrderId,
        String evalCategory
    ) {
        Logger.setScenario('Instrument Evaluation');
        try {
            throwIfSimulated();
            if (String.isBlank(evalCategory)) {
                throw new WorkOrdersServiceException('Eval Category is required.');
            }
            WorkOrder workOrder = requireInstrumentEvaluationWorkOrder(workOrderId);
            List<Product2> products = ProductsSelector.selectForInstrumentEvaluationByEvalCategory(
                INSTRUMENT_EVALUATION_PRODUCT_LINE,
                workOrder.RepairCategory__c,
                evalCategory
            );
            return mapInstrumentProductCards(products);
        } catch (WorkOrdersServiceException e) {
            throw e;
        } catch (Exception e) {
            logInstrumentEvaluationUnexpectedError(
                'getInstrumentEvaluationProducts',
                workOrderId,
                e
            );
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while loading evaluation products.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3400 - Returns category and service repair-code cards for a product.
     *              When productId is blank and the Work Order has an Asset, uses the Asset Product.
     * @param workOrderId Parent Work Order Id
     * @param productId Instrument Product2 Id, or null to use the Asset Product
     * @return Category and service code cards (no observation)
     * @throws WorkOrdersServiceException for validation or unexpected failures
     */
    public static ProductRelatedMaterialsService.InstrumentEvaluationCodeCards
        getInstrumentEvaluationRepairCodes(Id workOrderId, Id productId) {
        Logger.setScenario('Instrument Evaluation');
        try {
            throwIfSimulated();
            WorkOrder workOrder = requireInstrumentEvaluationWorkOrder(workOrderId);
            Id resolvedProductId = productId;
            if (resolvedProductId == null && workOrder.Asset != null) {
                resolvedProductId = workOrder.Asset.Product2Id;
            }
            if (resolvedProductId == null) {
                throw new WorkOrdersServiceException('Product is required.');
            }
            return ProductRelatedMaterialsService.buildInstrumentEvaluationCodeCards(
                resolvedProductId
            );
        } catch (WorkOrdersServiceException e) {
            throw e;
        } catch (ProductRelatedMaterialsService.ProductRelatedMaterialsServiceException e) {
            throw new WorkOrdersServiceException(e.getMessage(), e);
        } catch (Exception e) {
            logInstrumentEvaluationUnexpectedError(
                'getInstrumentEvaluationRepairCodes',
                workOrderId,
                e
            );
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while loading repair codes.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3400 - Persists a Product Serviced item and selected repair-code children.
     * @param workOrderId Parent Work Order Id
     * @param productId Selected instrument Product2 Id
     * @param quantity Product Serviced quantity
     * @param repairCodeProductIds Selected category/service Product Ids
     * @return Created Product Serviced Id
     * @throws WorkOrdersServiceException for validation or unexpected failures
     */
    public static Id persistInstrumentEvaluationItem(
        Id workOrderId,
        Id productId,
        Decimal quantity,
        List<Id> repairCodeProductIds
    ) {
        Logger.setScenario('Instrument Evaluation');
        try {
            throwIfSimulated();
            WorkOrder workOrder = requireInstrumentEvaluationWorkOrder(workOrderId);
            ensurePricebookForEvaluationLineItems(workOrder);
            Boolean requoteGate = WorkOrderRepairPricingService.requiresRequoteGate(workOrder);
            Decimal originalTotal = requoteGate
                ? WorkOrderRepairPricingService.sumRepairCodeNetTotal(workOrder)
                : null;
            Savepoint requoteSavepoint = requoteGate ? Database.setSavepoint() : null;
            try {
                Id productServicedId = WorkOrderLineItemsService.persistInstrumentEvaluationItem(
                    workOrder,
                    productId,
                    quantity,
                    repairCodeProductIds
                );
                if (requoteGate) {
                    captureUnpricedRepairTotals(workOrder, originalTotal);
                }
                return productServicedId;
            } catch (Exception e) {
                if (requoteSavepoint != null) {
                    Database.rollback(requoteSavepoint);
                }
                throw e;
            }
        } catch (WorkOrdersServiceException e) {
            throw e;
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            throw new WorkOrdersServiceException(e.getMessage(), e);
        } catch (Exception e) {
            logInstrumentEvaluationUnexpectedError(
                'persistInstrumentEvaluationItem',
                workOrderId,
                e
            );
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while saving the Instrument Evaluation item.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3400 - Persists draft Instrument Evaluation items, links staged
     *              photos, and creates Vendor Work Orders when requested. Does not change
     *              Status / Sub Status (use completeInstrumentEvaluationDraft for that).
     * @param workOrderId Parent Work Order Id
     * @param draftItems Draft entries from the LWC (item + repair-code set + staged photos)
     * @return Created Product Serviced WOLI Ids in draft order
     */
    public static List<Id> saveInstrumentEvaluationDraft(
        Id workOrderId,
        List<InstrumentEvaluationDraftItem> draftItems
    ) {
        return saveInstrumentEvaluationDraft(workOrderId, draftItems, false);
    }

    /**
     * @description GW-5324 - Loads RO Lines and determines the initial selection for one
     *              Product Serviced item. Saved mappings win; otherwise the story's asset,
     *              serial/product, and product/model/quantity criteria are applied.
     * @param workOrderId Instrument Work Order Id
     * @param productServicedId Product Serviced WorkOrderLineItem Id
     * @return Assignment modal data
     */
    public static InstrumentReturnOrderLineAssignment getInstrumentReturnOrderLineAssignment(
        Id workOrderId,
        Id productServicedId
    ) {
        Logger.setScenario('Instrument Evaluation');
        try {
            WorkOrder workOrder = requireInstrumentEvaluationWorkOrder(workOrderId);
            if (productServicedId == null) {
                throw new WorkOrdersServiceException('Product Serviced item is required.');
            }
            WorkOrderLineItem productServicedLine;
            for (
                WorkOrderLineItem line :
                WorkOrderLineItemsService.getInstrumentEvaluationLines(workOrder.Id)
            ) {
                if (line.Id == productServicedId) {
                    productServicedLine = line;
                    break;
                }
            }
            if (productServicedLine == null) {
                throw new WorkOrdersServiceException(
                    'The Product Serviced item was not found on this Work Order.'
                );
            }

            Id returnOrderId = workOrder.ReturnOrder__c != null
                ? workOrder.ReturnOrder__c
                : workOrder.ReturnOrderId;
            List<ReturnOrderLineItem> returnOrderLines =
                ReturnOrderLineItemsService.getInstrumentEvaluationLineItems(returnOrderId);
            return buildInstrumentReturnOrderLineAssignment(
                productServicedLine,
                returnOrderLines
            );
        } catch (WorkOrdersServiceException e) {
            throw e;
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            throw new WorkOrdersServiceException(e.getMessage(), e);
        } catch (
            ReturnOrderLineItemsService.ReturnOrderLineItemsServiceException e
        ) {
            throw new WorkOrdersServiceException(e.getMessage(), e);
        } catch (Exception e) {
            logInstrumentEvaluationUnexpectedError(
                'getInstrumentReturnOrderLineAssignment',
                workOrderId,
                e
            );
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while loading Return Order Line Items.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    @TestVisible
    private static InstrumentReturnOrderLineAssignment
        buildInstrumentReturnOrderLineAssignment(
            WorkOrderLineItem productServicedLine,
            List<ReturnOrderLineItem> returnOrderLines
        ) {
        InstrumentReturnOrderLineAssignment assignment =
            new InstrumentReturnOrderLineAssignment();
        Set<String> savedLineNumbers =
            parseReturnOrderLineItemNumbers(productServicedLine.ReturnOrderLineItems__c);
        Boolean hasSavedSelection = !savedLineNumbers.isEmpty();
        for (ReturnOrderLineItem returnOrderLine : returnOrderLines) {
            if (
                String.isBlank(assignment.returnOrderNumber) &&
                returnOrderLine.ReturnOrder != null
            ) {
                assignment.returnOrderNumber =
                    returnOrderLine.ReturnOrder.ReturnOrderNumber;
            }
            InstrumentReturnOrderLineOption option =
                new InstrumentReturnOrderLineOption();
            option.id = returnOrderLine.Id;
            option.lineItemNumber = returnOrderLine.ReturnOrderLineItemNumber;
            option.serialNumber = returnOrderLine.SerialNumber__c;
            option.productId = returnOrderLine.Product2Id;
            option.productName =
                returnOrderLine.Product2 == null ? null : returnOrderLine.Product2.Name;
            option.itemDescription = returnOrderLine.ItemDescription__c;
            option.model = returnOrderLine.Model__c;
            option.quantity = returnOrderLine.QuantityReceived;
            option.selected = hasSavedSelection
                ? savedLineNumbers.contains(returnOrderLine.ReturnOrderLineItemNumber)
                : matchesInstrumentReturnOrderLine(productServicedLine, returnOrderLine);
            assignment.options.add(option);
        }
        return assignment;
    }

    private static Set<String> parseReturnOrderLineItemNumbers(String value) {
        Set<String> lineNumbers = new Set<String>();
        if (String.isBlank(value)) {
            return lineNumbers;
        }
        for (String token : value.split(',')) {
            if (String.isNotBlank(token)) {
                lineNumbers.add(token.trim());
            }
        }
        return lineNumbers;
    }

    private static Boolean matchesInstrumentReturnOrderLine(
        WorkOrderLineItem productServicedLine,
        ReturnOrderLineItem returnOrderLine
    ) {
        if (productServicedLine == null || returnOrderLine == null) {
            return false;
        }
        if (
            productServicedLine.AssetId != null &&
            productServicedLine.AssetId == returnOrderLine.AssetId
        ) {
            return true;
        }
        Id productId = productServicedLine.Product2Id;
        Boolean sameProduct =
            productId != null && productId == returnOrderLine.Product2Id;
        if (
            sameProduct &&
            stringsMatch(productServicedLine.SerialNumber__c, returnOrderLine.SerialNumber__c)
        ) {
            return true;
        }
        return sameProduct &&
            stringsMatch(productServicedLine.Model__c, returnOrderLine.Model__c) &&
            productServicedLine.Quantity != null &&
            productServicedLine.Quantity == returnOrderLine.QuantityReceived;
    }

    private static Boolean stringsMatch(String leftValue, String rightValue) {
        return String.isNotBlank(leftValue) &&
            String.isNotBlank(rightValue) &&
            leftValue.trim().equalsIgnoreCase(rightValue.trim());
    }

    /**
     * @description GW-3400 - Persists draft Instrument Evaluation items, links staged
     *              photos, and creates Vendor Work Orders when requested. Does not change
     *              Status / Sub Status (use completeInstrumentEvaluationDraft for that).
     * @param workOrderId Parent Work Order Id
     * @param draftItems Draft entries from the LWC (item + repair-code set + staged photos)
     * @param reconcileRemovedLines When true, deletes Product Serviced lines omitted from draftItems
     * @return Created Product Serviced WOLI Ids in draft order
     */
    public static List<Id> saveInstrumentEvaluationDraft(
        Id workOrderId,
        List<InstrumentEvaluationDraftItem> draftItems,
        Boolean reconcileRemovedLines
    ) {
        Logger.setScenario('Instrument Evaluation');
        try {
            throwIfSimulated();
            WorkOrder workOrder = requireInstrumentEvaluationWorkOrder(workOrderId);
            List<InstrumentEvaluationDraftItem> normalizedDraftItems = draftItems == null
                ? new List<InstrumentEvaluationDraftItem>()
                : draftItems;
            Boolean shouldReconcile = reconcileRemovedLines == true;
            if (normalizedDraftItems.isEmpty() && !shouldReconcile) {
                return new List<Id>();
            }
            ensurePricebookForEvaluationLineItems(workOrder);
            Boolean requoteGate = WorkOrderRepairPricingService.requiresRequoteGate(workOrder);
            Decimal originalTotal = requoteGate
                ? WorkOrderRepairPricingService.sumRepairCodeNetTotal(workOrder)
                : null;
            Savepoint requoteSavepoint = requoteGate ? Database.setSavepoint() : null;
            try {
                List<Id> productServicedIds = persistInstrumentEvaluationDraftItems(
                    workOrder,
                    normalizedDraftItems,
                    reconcileRemovedLines == true
                );
                if (requoteGate) {
                    captureUnpricedRepairTotals(workOrder, originalTotal);
                }
                return productServicedIds;
            } catch (Exception e) {
                if (requoteSavepoint != null) {
                    Database.rollback(requoteSavepoint);
                }
                throw e;
            }
        } catch (WorkOrdersServiceException e) {
            throw e;
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            throw new WorkOrdersServiceException(e.getMessage(), e);
        } catch (ContentDocumentLinksService.ContentDocumentLinksServiceException e) {
            throw new WorkOrdersServiceException(e.getMessage(), e);
        } catch (Exception e) {
            logInstrumentEvaluationUnexpectedError(
                'saveInstrumentEvaluationDraft',
                workOrderId,
                e
            );
            String detail = e.getMessage();
            if (e.getCause() != null && String.isNotBlank(e.getCause().getMessage())) {
                detail = detail + ' | Cause: ' + e.getCause().getMessage();
            }
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while saving Instrument Evaluation items. ' +
                    detail,
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3400 - Persists draft Instrument Evaluation items, links staged
     *              photos to each Product Serviced WOLI, then applies Complete Status / Sub Status
     *              and parent Generate Quote rules. Enforces Photos Required with at least one
     *              photo on any item unless Unable To Take Photo is set on the Work Order. When draftItems is empty,
     *              requires at least one existing Instrument Evaluation Product Serviced line
     *              and only applies completion status (supports Quick Save then Complete).
     * @param workOrderId Parent Work Order Id
     * @param draftItems Draft entries from the LWC (item + repair-code set + staged photos)
     * @return Created Product Serviced WOLI Ids in draft order
     */
    public static List<Id> completeInstrumentEvaluationDraft(
        Id workOrderId,
        List<InstrumentEvaluationDraftItem> draftItems
    ) {
        Logger.setScenario('Instrument Evaluation');
        try {
            throwIfSimulated();
            WorkOrder workOrder = requireInstrumentEvaluationWorkOrder(workOrderId);
            Boolean hasNewDrafts = draftItems != null && !draftItems.isEmpty();
            if (!hasNewDrafts) {
                List<WorkOrderLineItem> existingLines =
                    WorkOrderLineItemsService.getInstrumentEvaluationLines(workOrder.Id);
                if (existingLines == null || existingLines.isEmpty()) {
                    throw new WorkOrdersServiceException(
                        'Add at least one instrument before continuing.'
                    );
                }
            }
            validateInstrumentEvaluationQuantityReceived(workOrder, draftItems);
            ensurePricebookForEvaluationLineItems(workOrder);

            Boolean photosRequired = workOrder.PhotosRequired__c == true;
            Boolean unableToTakePhoto = workOrder.UnableToTakePhoto__c == true;
            if (hasNewDrafts && photosRequired && !unableToTakePhoto) {
                validateInstrumentEvaluationPhotosRequired(workOrder, draftItems);
            }

            List<Id> productServicedIds = hasNewDrafts
                ? persistInstrumentEvaluationDraftItems(workOrder, draftItems, true)
                : new List<Id>();

            // GW-3400 / GW-5830 - Status / Sub Status / parent Generate Quote on Complete
            applyInstrumentEvaluationCompletionStatus(workOrder);
            Boolean shouldGenerateQuoteOnParent =
                workOrder.Status == WO_STATUS_EVALUATE_AND_QUOTE &&
                shouldGenerateParentQuoteOnComplete(workOrder);
            persistWorkOrderForDeviceEvaluation(
                new WorkOrder(
                    Id = workOrder.Id,
                    Status = workOrder.Status,
                    SubStatus__c = workOrder.SubStatus__c
                )
            );
            if (shouldGenerateQuoteOnParent) {
                persistWorkOrderForDeviceEvaluation(
                    new WorkOrder(Id = workOrder.ParentWorkOrderId, GenerateQuote__c = true)
                );
            }

            return productServicedIds;
        } catch (WorkOrdersServiceException e) {
            throw e;
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            throw new WorkOrdersServiceException(e.getMessage(), e);
        } catch (ContentDocumentLinksService.ContentDocumentLinksServiceException e) {
            throw new WorkOrdersServiceException(e.getMessage(), e);
        } catch (Exception e) {
            logInstrumentEvaluationUnexpectedError(
                'completeInstrumentEvaluationDraft',
                workOrderId,
                e
            );
            String detail = e.getMessage();
            if (e.getCause() != null && String.isNotBlank(e.getCause().getMessage())) {
                detail = detail + ' | Cause: ' + e.getCause().getMessage();
            }
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while completing Instrument Evaluation items. ' +
                    detail,
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3400 - Creates Product Serviced / Repair Code lines, attaches photos,
     *              and creates Vendor Work Orders when requested.
     * @param workOrder Parent Work Order
     * @param draftItems Draft entries
     * @return Created Product Serviced Ids in draft order
     */
    private static List<Id> persistInstrumentEvaluationDraftItems(
        WorkOrder workOrder,
        List<InstrumentEvaluationDraftItem> draftItems,
        Boolean reconcileRemovedLines
    ) {
        if (reconcileRemovedLines == true) {
            reconcileInstrumentEvaluationRemovedLines(workOrder, draftItems);
        }
        List<Id> productServicedIds = new List<Id>();
        List<VendorLineInput> vendorLines =
            new List<VendorLineInput>();
        Map<Id, ReturnOrderLineItem> returnOrderLinesById =
            loadInstrumentReturnOrderLinesById(workOrder);
        for (InstrumentEvaluationDraftItem draftItem : draftItems) {
            if (draftItem == null) {
                continue;
            }
            String returnOrderLineItems = formatSelectedReturnOrderLineItems(
                draftItem.returnOrderLineItemIds,
                returnOrderLinesById
            );
            Id productServicedId = draftItem.productServicedId != null
                ? WorkOrderLineItemsService.syncInstrumentEvaluationItem(
                      workOrder,
                      draftItem.productServicedId,
                      draftItem.productId,
                      draftItem.quantity,
                      draftItem.repairCodeProductIds,
                      returnOrderLineItems
                  )
                : WorkOrderLineItemsService.persistInstrumentEvaluationItem(
                      workOrder,
                      draftItem.productId,
                      draftItem.quantity,
                      draftItem.repairCodeProductIds,
                      returnOrderLineItems
                  );
            productServicedIds.add(productServicedId);
            ContentDocumentLinksService.attachDocumentsToLinkedEntity(
                productServicedId,
                draftItem.contentDocumentIds
            );
            // Create Vendor WO for new or existing Product Serviced rows flagged for vendor.
            if (draftItem.vendorProcessingRequired == true) {
                VendorLineInput vendorLine =
                    new VendorLineInput();
                vendorLine.childProductServicedId = productServicedId;
                vendorLine.productId = draftItem.productId;
                vendorLine.quantity = draftItem.quantity;
                vendorLine.vendorAccountId = draftItem.vendorAccountId;
                vendorLine.instructionsToVendor = draftItem.instructionsToVendor;
                vendorLine.sterisPurchaseOrderToVendor = draftItem.sterisPurchaseOrderToVendor;
                vendorLine.vendorNotes = draftItem.vendorNotes;
                vendorLine.vendorReferenceNumber = draftItem.vendorReferenceNumber;
                vendorLine.vendorCost = draftItem.vendorCost;
                vendorLine.shippedToVendorDate = draftItem.shippedToVendorDate;
                vendorLine.trackingNumber = draftItem.trackingNumber;
                vendorLines.add(vendorLine);
            } else {
                clearVendorFromInstrumentEvaluationLine(productServicedId);
            }
        }
        if (!vendorLines.isEmpty()) {
            createForInstrumentEvaluation(workOrder.Id, vendorLines);
        }
        return productServicedIds;
    }

    private static Map<Id, ReturnOrderLineItem> loadInstrumentReturnOrderLinesById(
        WorkOrder workOrder
    ) {
        Id returnOrderId = workOrder == null
            ? null
            : (workOrder.ReturnOrder__c != null
                ? workOrder.ReturnOrder__c
                : workOrder.ReturnOrderId);
        return new Map<Id, ReturnOrderLineItem>(
            ReturnOrderLineItemsService.getInstrumentEvaluationLineItems(returnOrderId)
        );
    }

    @TestVisible
    private static String formatSelectedReturnOrderLineItems(
        List<Id> selectedIds,
        Map<Id, ReturnOrderLineItem> availableLinesById
    ) {
        if (selectedIds == null) {
            return null;
        }
        Set<Id> uniqueSelectedIds = new Set<Id>(selectedIds);
        uniqueSelectedIds.remove(null);
        if (uniqueSelectedIds.isEmpty()) {
            return '';
        }
        if (
            availableLinesById == null ||
            !availableLinesById.keySet().containsAll(uniqueSelectedIds)
        ) {
            throw new WorkOrdersServiceException(
                'One or more selected Return Order Line Items do not belong to this Return Order.'
            );
        }
        List<String> lineNumbers = new List<String>();
        for (ReturnOrderLineItem lineItem : availableLinesById.values()) {
            if (uniqueSelectedIds.contains(lineItem.Id)) {
                lineNumbers.add(lineItem.ReturnOrderLineItemNumber);
            }
        }
        lineNumbers.sort();
        String value = String.join(lineNumbers, ', ');
        if (value.length() > 255) {
            throw new WorkOrdersServiceException(
                'The selected Return Order Line Item numbers exceed the field limit.'
            );
        }
        return value;
    }

    /**
     * @description GW-3400 - Deletes Product Serviced lines removed from the Item Summary snapshot.
     * @param workOrder Parent Work Order
     * @param draftItems Remaining draft entries from the LWC
     */
    private static void reconcileInstrumentEvaluationRemovedLines(
        WorkOrder workOrder,
        List<InstrumentEvaluationDraftItem> draftItems
    ) {
        Set<Id> retainedProductServicedIds = new Set<Id>();
        if (draftItems != null) {
            for (InstrumentEvaluationDraftItem draftItem : draftItems) {
                if (draftItem != null && draftItem.productServicedId != null) {
                    retainedProductServicedIds.add(draftItem.productServicedId);
                }
            }
        }
        WorkOrderLineItemsService.reconcileInstrumentEvaluationRemovedLines(
            workOrder.Id,
            retainedProductServicedIds
        );
    }

    /**
     * @description GW-3400 - Requires at least one photo on any Instrument Evaluation item when
     *              Photos Required is set and Unable To Take Photo is false. Counts staged photos
     *              in the current draft batch and any photos already linked to Product Serviced WOLIs.
     * @param workOrder Parent Work Order
     * @param draftItems Draft entries in the current Complete request
     */
    private static void validateInstrumentEvaluationPhotosRequired(
        WorkOrder workOrder,
        List<InstrumentEvaluationDraftItem> draftItems
    ) {
        Integer stagedPhotoCount = 0;
        if (draftItems != null) {
            for (InstrumentEvaluationDraftItem draftItem : draftItems) {
                if (draftItem != null && draftItem.contentDocumentIds != null) {
                    stagedPhotoCount += draftItem.contentDocumentIds.size();
                }
            }
        }
        if (stagedPhotoCount > 0) {
            return;
        }
        List<WorkOrderLineItem> lines =
            WorkOrderLineItemsService.getInstrumentEvaluationLines(workOrder.Id);
        Set<Id> productServicedIds = new Set<Id>();
        if (lines != null) {
            for (WorkOrderLineItem line : lines) {
                if (line != null && line.Id != null) {
                    productServicedIds.add(line.Id);
                }
            }
        }
        if (
            !productServicedIds.isEmpty() &&
            ContentDocumentLinksService.countLinksByLinkedEntityIds(productServicedIds) > 0
        ) {
            return;
        }
        throw new WorkOrdersServiceException(IE_PHOTOS_REQUIRED_WORK_ORDER_MESSAGE);
    }

    /**
     * @description GW-3400 - Returns persisted Product Serviced items with child repair codes.
     * @param workOrderId Parent Work Order Id
     * @return Evaluation items in create order
     * @throws WorkOrdersServiceException for validation or unexpected failures
     */
    public static List<InstrumentEvaluationItem> getInstrumentEvaluationItems(Id workOrderId) {
        Logger.setScenario('Instrument Evaluation');
        try {
            throwIfSimulated();
            WorkOrder workOrder = requireInstrumentEvaluationWorkOrder(workOrderId);
            List<WorkOrderLineItem> lines =
                WorkOrderLineItemsService.getInstrumentEvaluationLines(workOrder.Id);
            return mapInstrumentEvaluationItems(lines);
        } catch (WorkOrdersServiceException e) {
            throw e;
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            throw new WorkOrdersServiceException(e.getMessage(), e);
        } catch (ContentDocumentLinksService.ContentDocumentLinksServiceException e) {
            throw new WorkOrdersServiceException(e.getMessage(), e);
        } catch (Exception e) {
            logInstrumentEvaluationUnexpectedError(
                'getInstrumentEvaluationItems',
                workOrderId,
                e
            );
            throw new WorkOrdersServiceException(
                'An unexpected error occurred while loading Instrument Evaluation items.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3400 - Requires Instruments record type, child WO, an Account, and an
     *              eligible Status (Evaluate & Quote, Ready for Repair, or Repair).
     * @param workOrder Work Order to validate
     */
    private static void validateWorkOrderEligibleForInstrumentEvaluation(WorkOrder workOrder) {
        if (workOrder == null) {
            throw new WorkOrdersServiceException('Work Order was not found.');
        }
        if (
            workOrder.RecordType == null ||
            workOrder.RecordType.DeveloperName != RECORD_TYPE_INSTRUMENTS
        ) {
            throw new WorkOrdersServiceException(INSTRUMENT_EVALUATION_RT_REQUIRED_MESSAGE);
        }
        if (workOrder.AccountId == null) {
            throw new WorkOrdersServiceException('This Work Order is missing an Account.');
        }
        if (!isInstrumentEvaluationStatusEligible(workOrder.Status)) {
            throw new WorkOrdersServiceException(INSTRUMENT_EVALUATION_STATUS_NOT_ELIGIBLE_MESSAGE);
        }
        if (workOrder.ParentWorkOrderId == null) {
            throw new WorkOrdersServiceException(INSTRUMENT_EVALUATION_CHILD_WO_REQUIRED_MESSAGE);
        }
    }

    /**
     * @description GW-3400 - Status values allowed to open Instrument Evaluation.
     * @param status Work Order Status
     * @return True when Status is Evaluate & Quote, Ready for Repair, or Repair
     */
    @TestVisible
    private static Boolean isInstrumentEvaluationStatusEligible(String status) {
        return status == WO_STATUS_EVALUATE_AND_QUOTE ||
            status == WO_STATUS_READY_FOR_REPAIR ||
            status == WO_STATUS_REPAIR;
    }

    /**
     * @description GW-3400 - Continue/init mapping for Instrument Evaluation.
     *              Ready for Repair → Repair + Sub Status STERIS. Evaluate & Quote keeps Status
     *              and only stamps Owner / Evaluator when needed.
     * @param workOrder Work Order being initialized
     * @return True when any field was changed and must be persisted
     */
    @TestVisible
    private static Boolean applyInstrumentEvaluationInitializeUpdates(WorkOrder workOrder) {
        if (workOrder == null) {
            return false;
        }
        if (workOrder.Status == WO_STATUS_EVALUATE_AND_QUOTE) {
            Boolean dirty = false;
            if (workOrder.OwnerId != UserInfo.getUserId()) {
                workOrder.OwnerId = UserInfo.getUserId();
                dirty = true;
            }
            if (workOrder.Evaluator__c == null) {
                workOrder.Evaluator__c = UserInfo.getUserId();
                dirty = true;
            }
            return dirty;
        }
        if (workOrder.Status == WO_STATUS_READY_FOR_REPAIR) {
            Boolean dirty = false;
            if (workOrder.Status != WO_STATUS_REPAIR) {
                workOrder.Status = WO_STATUS_REPAIR;
                dirty = true;
            }
            if (workOrder.SubStatus__c != WO_SUB_STATUS_STERIS) {
                workOrder.SubStatus__c = WO_SUB_STATUS_STERIS;
                dirty = true;
            }
            return dirty;
        }
        return false;
    }

    /**
     * @description GW-3400 / GW-5830 - Complete Status / Sub Status mapping for Instrument
     *              Evaluation. On Evaluate & Quote: Estimate Required → Waiting for Approval;
     *              missing Customer PO → PO Required; otherwise Ready for Repair with blank Sub Status.
     * @param workOrder Work Order being completed
     */
    @TestVisible
    private static void applyInstrumentEvaluationCompletionStatus(WorkOrder workOrder) {
        if (workOrder == null) {
            return;
        }
        if (workOrder.Status == WO_STATUS_REPAIR) {
            workOrder.SubStatus__c = WO_SUB_STATUS_READY_FOR_QC;
            return;
        }
        if (workOrder.Status != WO_STATUS_EVALUATE_AND_QUOTE) {
            return;
        }

        if (ESTIMATE_REQUIRED_VALUE.equals(workOrder.EstimateRequired__c)) {
            workOrder.Status = WO_STATUS_EVALUATE_AND_QUOTE;
            workOrder.SubStatus__c = WO_SUB_STATUS_WAITING_APPROVAL;
        } else if (isMissingRequiredCustomerPo(workOrder)) {
            workOrder.Status = WO_STATUS_EVALUATE_AND_QUOTE;
            workOrder.SubStatus__c = WO_SUB_STATUS_PO_REQUIRED;
        } else {
            workOrder.Status = WO_STATUS_READY_FOR_REPAIR;
            workOrder.SubStatus__c = null;
        }
    }

    private static Boolean isMissingRequiredCustomerPo(WorkOrder workOrder) {
        return workOrder != null &&
            workOrder.CustomerPORequired__c == true &&
            String.isBlank(workOrder.CustomerPO__c);
    }

    /**
     * @description GW-3400 - Whether Item Selection may add products (story rule).
     *              Status = Evaluate & Quote, or Estimate Required = Order Acknowledgement /
     *              Pre-Approved.
     * @param workOrder Work Order
     * @return True when items may be added
     */
    @TestVisible
    private static Boolean canAddInstrumentEvaluationItems(WorkOrder workOrder) {
        if (workOrder == null) {
            return false;
        }
        if (workOrder.Status == WO_STATUS_EVALUATE_AND_QUOTE) {
            return true;
        }
        return workOrder.EstimateRequired__c == ESTIMATE_ORDER_ACKNOWLEDGEMENT ||
            workOrder.EstimateRequired__c == ESTIMATE_PRE_APPROVED;
    }

    /**
     * @description GW-3400 - Resolves Product Line from Asset, then Work Order formula.
     * @param workOrder Work Order
     * @return Product Line value, or null
     */
    private static String resolveInstrumentEvaluationProductLine(WorkOrder workOrder) {
        String productLine = resolveProductLine(workOrder);
        if (String.isNotBlank(productLine)) {
            return productLine;
        }
        return workOrder == null ? null : workOrder.ProductLine_f__c;
    }

    /**
     * @description GW-3400 - Builds LWC context for Instrument Evaluation.
     * @param workOrder Parent Work Order
     * @param photosRequired Photos-required flag
     * @return Populated InstrumentEvaluationContext
     */
    private static InstrumentEvaluationContext buildInstrumentEvaluationContext(
        WorkOrder workOrder,
        Boolean photosRequired
    ) {
        InstrumentEvaluationContext context = new InstrumentEvaluationContext();
        if (workOrder == null) {
            return context;
        }
        Boolean hasAsset = workOrder.AssetId != null && workOrder.Asset != null;
        String productLine = resolveInstrumentEvaluationProductLine(workOrder);
        context.workOrder = workOrder;
        context.photosRequired = photosRequired == true;
        context.productLine = productLine;
        context.manufacturer = resolveManufacturer(workOrder);
        context.model = resolveModel(workOrder);
        context.serialNumber = hasAsset ? workOrder.Asset.SerialNumber : null;
        context.hasAsset = hasAsset;
        context.showItemSelection = !hasAsset;
        context.canAddItems = canAddInstrumentEvaluationItems(workOrder);
        context.assetIdentityLine = hasAsset
            ? buildDeviceIdentityLine(
                context.serialNumber,
                context.manufacturer,
                context.model,
                context.productLine
            )
            : workOrder.RepairCategory__c;
        // Customer Preferences tab: Account + IMS RT + (Product Line blank OR Instrument) + active dates.
        context.customerPreferences = CustomerPreferencesService.getActiveImsPreferences(
            workOrder.AccountId,
            INSTRUMENT_PHOTOS_REQUIRED_PRODUCT_LINE
        );
        if (hasAsset) {
            context.repairHistory = getRepairHistoryForDeviceEvaluation(
                workOrder.AccountId,
                workOrder.AssetId,
                workOrder.Id
            );
            context.repairHistoryHasMore = hasRepairHistoryOutsideLastTwelveMonths(
                context.repairHistory
            );
        }
        stampRepairCostTotals(workOrder, context);
        return context;
    }

    /**
     * @description GW-3400 - Loads and validates a parent Instruments Work Order.
     * @param workOrderId Parent Work Order Id
     * @return Work Order
     */
    private static WorkOrder requireInstrumentEvaluationWorkOrder(Id workOrderId) {
        if (workOrderId == null) {
            throw new WorkOrdersServiceException('Work Order is required.');
        }
        WorkOrder workOrder = requireWorkOrderById(workOrderId);
        validateWorkOrderEligibleForInstrumentEvaluation(workOrder);
        return workOrder;
    }

    /**
     * @description GW-3400 / GW-5830 - When Status is Evaluate & Quote, users may not set Sub
     *              Status to Waiting for Approval, Rejected, or PO Required from Instrument Evaluation.
     * @param workOrder Current Work Order
     * @param newSubStatus Requested Sub Status
     */
    @TestVisible
    private static void validateInstrumentEvaluationSubStatusChange(
        WorkOrder workOrder,
        String newSubStatus
    ) {
        if (workOrder == null || workOrder.Status != WO_STATUS_EVALUATE_AND_QUOTE) {
            return;
        }
        if (
            newSubStatus != WO_SUB_STATUS_WAITING_APPROVAL &&
            newSubStatus != WO_SUB_STATUS_REJECTED &&
            newSubStatus != WO_SUB_STATUS_PO_REQUIRED
        ) {
            return;
        }
        if (newSubStatus == workOrder.SubStatus__c) {
            return;
        }
        throw new WorkOrdersServiceException(
            'When Status is Evaluate & Quote, Sub Status cannot be set to Waiting for Approval, Rejected, or PO Required.'
        );
    }

    /**
     * @description GW-3400 - Quantity Received is required and must equal the sum of Product
     *              Serviced item quantities (existing lines plus any draft creates/updates).
     * @param workOrder Parent Work Order
     * @param draftItems Draft creates/updates being completed (may be empty)
     */
    @TestVisible
    private static void validateInstrumentEvaluationQuantityReceived(
        WorkOrder workOrder,
        List<InstrumentEvaluationDraftItem> draftItems
    ) {
        if (workOrder == null || workOrder.QuantityReceived__c == null) {
            throw new WorkOrdersServiceException(INSTRUMENT_EVAL_QUANTITY_RECEIVED_REQUIRED_MESSAGE);
        }

        Map<Id, Decimal> quantityByProductServicedId = new Map<Id, Decimal>();
        List<WorkOrderLineItem> existingLines =
            WorkOrderLineItemsService.getInstrumentEvaluationLines(workOrder.Id);
        Id productServicedRtId = WorkOrderLineItemsService.getProductServicedRecordTypeId();
        if (existingLines != null && productServicedRtId != null) {
            for (WorkOrderLineItem lineItem : existingLines) {
                if (lineItem == null || lineItem.RecordTypeId != productServicedRtId) {
                    continue;
                }
                quantityByProductServicedId.put(
                    lineItem.Id,
                    lineItem.Quantity == null ? 0 : lineItem.Quantity
                );
            }
        }

        Decimal newItemQuantity = 0;
        if (draftItems != null) {
            for (InstrumentEvaluationDraftItem draftItem : draftItems) {
                if (draftItem == null) {
                    continue;
                }
                Decimal draftQuantity = draftItem.quantity == null ? 0 : draftItem.quantity;
                if (draftItem.productServicedId != null) {
                    quantityByProductServicedId.put(draftItem.productServicedId, draftQuantity);
                } else {
                    newItemQuantity += draftQuantity;
                }
            }
        }

        Decimal totalItemQuantity = newItemQuantity;
        for (Decimal quantity : quantityByProductServicedId.values()) {
            totalItemQuantity += quantity == null ? 0 : quantity;
        }

        if (totalItemQuantity != workOrder.QuantityReceived__c) {
            throw new WorkOrdersServiceException(
                INSTRUMENT_EVAL_QUANTITY_MISMATCH_MESSAGE +
                    ' (items: ' +
                    totalItemQuantity +
                    ', received: ' +
                    workOrder.QuantityReceived__c +
                    ').'
            );
        }
    }

    /**
     * @description GW-3400 - Logs unexpected Instrument Evaluation errors with Work Order context.
     * @param methodName Public service method name
     * @param workOrderId Parent Work Order Id
     * @param caught Unexpected exception
     */
    private static void logInstrumentEvaluationUnexpectedError(
        String methodName,
        Id workOrderId,
        Exception caught
    ) {
        Logger.error(
            new LogMessage(
                'WorkOrdersService.{0} failed for {1}: {2}',
                methodName,
                workOrderId,
                caught == null ? null : caught.getMessage()
            ),
            caught
        );
    }

    /**
     * @description GW-3400 - Builds unique Eval Category cards sorted by Eval Rank then name.
     * @param products Catalog products
     * @return Unique category cards
     */
    private static List<InstrumentEvalCategoryCard> buildUniqueEvalCategoryCards(
        List<Product2> products
    ) {
        Map<String, InstrumentEvalCategoryCard> cardsByCategory =
            new Map<String, InstrumentEvalCategoryCard>();
        if (products == null) {
            return new List<InstrumentEvalCategoryCard>();
        }
        for (Product2 product : products) {
            if (product == null || String.isBlank(product.EvalCategory__c)) {
                continue;
            }
            InstrumentEvalCategoryCard existing = cardsByCategory.get(product.EvalCategory__c);
            if (existing == null) {
                InstrumentEvalCategoryCard card = new InstrumentEvalCategoryCard();
                card.evalCategory = product.EvalCategory__c;
                card.evalRank = product.EvalRank__c;
                cardsByCategory.put(product.EvalCategory__c, card);
                continue;
            }
            if (compareEvalRank(product.EvalRank__c, existing.evalRank) < 0) {
                existing.evalRank = product.EvalRank__c;
            }
        }
        List<InstrumentEvalCategoryCard> cards = new List<InstrumentEvalCategoryCard>(
            cardsByCategory.values()
        );
        cards.sort(new InstrumentEvalCategoryComparator());
        return cards;
    }

    /**
     * @description GW-3400 - Maps catalog products to product cards.
     * @param products Catalog products
     * @return Product cards
     */
    private static List<InstrumentProductCard> mapInstrumentProductCards(List<Product2> products) {
        List<InstrumentProductCard> cards = new List<InstrumentProductCard>();
        if (products == null) {
            return cards;
        }
        for (Product2 product : products) {
            InstrumentProductCard card = new InstrumentProductCard();
            card.productId = product.Id;
            card.productCode = product.ProductCode;
            card.productName = product.Name;
            card.evalCategory = product.EvalCategory__c;
            cards.add(card);
        }
        return cards;
    }

    /**
     * @description GW-3400 - Groups Product Serviced parents with child Repair Code cards.
     * @param lines Product Serviced and Repair Code WOLIs
     * @return Evaluation items
     */
    private static List<InstrumentEvaluationItem> mapInstrumentEvaluationItems(
        List<WorkOrderLineItem> lines
    ) {
        List<InstrumentEvaluationItem> items = new List<InstrumentEvaluationItem>();
        if (lines == null || lines.isEmpty()) {
            return items;
        }
        Id productServicedRtId = WorkOrderLineItemsService.getProductServicedRecordTypeId();
        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        Map<Id, InstrumentEvaluationItem> itemsById = new Map<Id, InstrumentEvaluationItem>();
        Set<Id> vendorWorkOrderIds = new Set<Id>();
        for (WorkOrderLineItem lineItem : lines) {
            if (lineItem == null || lineItem.RecordTypeId != productServicedRtId) {
                continue;
            }
            if (lineItem.VendorWorkOrder__c != null) {
                vendorWorkOrderIds.add(lineItem.VendorWorkOrder__c);
            }
        }
        Map<Id, WorkOrder> vendorWorkOrdersById = vendorWorkOrderIds.isEmpty()
            ? new Map<Id, WorkOrder>()
            : new Map<Id, WorkOrder>(
                  [
                      SELECT
                          Id,
                          Vendor__c,
                          VendorReturnOrder__c,
                          InstructionsToVendor__c,
                          VendorNotes__c,
                          VendorReferenceNumber__c,
                          VendorCost__c,
                          STERISPurchaseOrdertoVendor__c,
                          ShippedToVendorDate__c
                      FROM WorkOrder
                      WHERE Id IN :vendorWorkOrderIds
                      WITH USER_MODE
                  ]
              );
        // GW-6358: tracking number comes from the first Shipment on the Vendor Return Order.
        Map<Id, String> trackingNumberByReturnOrderIdMap = ShipmentsService.getInitialTrackingNumberByReturnOrderId(
            collectVendorReturnOrderIds(vendorWorkOrdersById.values())
        );
        for (WorkOrderLineItem lineItem : lines) {
            if (lineItem == null || lineItem.RecordTypeId != productServicedRtId) {
                continue;
            }
            InstrumentEvaluationItem item = new InstrumentEvaluationItem();
            item.productServicedId = lineItem.Id;
            item.productId = lineItem.Product2Id;
            item.productCode = String.isNotBlank(lineItem.ProductCodeWoli__c)
                ? lineItem.ProductCodeWoli__c
                : (lineItem.Product2 != null ? lineItem.Product2.ProductCode : null);
            item.productName = String.isNotBlank(lineItem.ProductDescription__c)
                ? lineItem.ProductDescription__c
                : (lineItem.Product2 != null ? lineItem.Product2.Name : null);
            item.quantity = lineItem.Quantity;
            item.returnOrderLineItems = lineItem.ReturnOrderLineItems__c;
            item.vendorProcessingRequired = lineItem.VendorProcessingRequired__c == true;
            item.vendorAccountId = lineItem.Vendor__c;
            // Prefer Vendor WO header (shared per vendor); fall back to WOLI for legacy rows.
            WorkOrder vendorWo = lineItem.VendorWorkOrder__c != null
                ? vendorWorkOrdersById.get(lineItem.VendorWorkOrder__c)
                : null;
            if (vendorWo != null) {
                if (item.vendorAccountId == null) {
                    item.vendorAccountId = vendorWo.Vendor__c;
                }
                item.vendorWorkOrderId = vendorWo.Id;
                item.vendorWorkOrderLocked = vendorWo.VendorReturnOrder__c != null;
                item.instructionsToVendor = vendorWo.InstructionsToVendor__c;
                item.sterisPurchaseOrderToVendor = vendorWo.STERISPurchaseOrdertoVendor__c;
                item.vendorNotes = vendorWo.VendorNotes__c;
                item.vendorReferenceNumber = vendorWo.VendorReferenceNumber__c;
                item.vendorCost = vendorWo.VendorCost__c;
                item.shippedToVendorDate = vendorWo.ShippedToVendorDate__c;
                item.trackingNumber = trackingNumberByReturnOrderIdMap.get(vendorWo.VendorReturnOrder__c);
            } else {
                item.vendorWorkOrderId = lineItem.VendorWorkOrder__c;
                item.vendorWorkOrderLocked = false;
                item.instructionsToVendor = lineItem.InstructionsToVendor__c;
                item.vendorNotes = lineItem.VendorNotes__c;
                item.vendorReferenceNumber = lineItem.VendorReferenceNumber__c;
                item.vendorCost = lineItem.VendorCost__c;
            }
            item.repairCodes = new List<ProductRelatedMaterialsService.RepairCodeCardData>();
            item.photos = new List<ContentDocumentLinksService.DeviceEvaluationFileData>();
            itemsById.put(lineItem.Id, item);
            items.add(item);
        }
        for (WorkOrderLineItem lineItem : lines) {
            if (
                lineItem == null ||
                lineItem.RecordTypeId != repairCodeRtId ||
                lineItem.ParentWorkOrderLineItemId == null
            ) {
                continue;
            }
            InstrumentEvaluationItem parent = itemsById.get(lineItem.ParentWorkOrderLineItemId);
            if (parent == null) {
                continue;
            }
            ProductRelatedMaterialsService.RepairCodeCardData card =
                new ProductRelatedMaterialsService.RepairCodeCardData();
            card.workOrderLineItemId = lineItem.Id;
            card.productId = lineItem.Product2Id;
            card.productCode = resolveInstrumentEvalLineProductCode(lineItem);
            card.productName = resolveInstrumentEvalLineProductName(lineItem);
            card.codeType = lineItem.LineType__c;
            card.selected = true;
            parent.repairCodes.add(card);
        }
        attachInstrumentEvaluationPhotos(itemsById);
        return items;
    }

    /**
     * @description GW-3400 - Loads ContentDocuments linked to each Product Serviced WOLI.
     * @param itemsById Product Serviced Id → evaluation item
     */
    private static void attachInstrumentEvaluationPhotos(
        Map<Id, InstrumentEvaluationItem> itemsById
    ) {
        if (itemsById == null || itemsById.isEmpty()) {
            return;
        }
        for (
            ContentDocumentLinksService.DeviceEvaluationFileData file :
            ContentDocumentLinksService.getFilesForLinkedEntities(itemsById.keySet())
        ) {
            if (file == null || file.linkedEntityId == null) {
                continue;
            }
            InstrumentEvaluationItem item = itemsById.get(file.linkedEntityId);
            if (item == null) {
                continue;
            }
            item.photos.add(file);
        }
    }

    private static String resolveInstrumentEvalLineProductCode(WorkOrderLineItem lineItem) {
        if (lineItem == null) {
            return null;
        }
        if (lineItem.Product2 != null && String.isNotBlank(lineItem.Product2.ProductCode)) {
            return lineItem.Product2.ProductCode;
        }
        return lineItem.ProductCodeWoli__c;
    }

    private static String resolveInstrumentEvalLineProductName(WorkOrderLineItem lineItem) {
        if (lineItem == null) {
            return null;
        }
        if (lineItem.Product2 != null && String.isNotBlank(lineItem.Product2.Name)) {
            return lineItem.Product2.Name;
        }
        return lineItem.ProductDescription__c;
    }

    /**
     * @description GW-3400 - Compares Eval Rank strings; blank ranks sort last.
     * @param left Left rank
     * @param right Right rank
     * @return Negative when left is earlier
     */
    private static Integer compareEvalRank(String left, String right) {
        Boolean leftBlank = String.isBlank(left);
        Boolean rightBlank = String.isBlank(right);
        if (leftBlank && rightBlank) {
            return 0;
        }
        if (leftBlank) {
            return 1;
        }
        if (rightBlank) {
            return -1;
        }
        return left.compareTo(right);
    }

    /**
     * @description GW-3400 - Sorts Eval Category cards by rank then category name.
     */
    private class InstrumentEvalCategoryComparator implements Comparator<InstrumentEvalCategoryCard> {
        public Integer compare(
            InstrumentEvalCategoryCard left,
            InstrumentEvalCategoryCard right
        ) {
            if (left == null && right == null) {
                return 0;
            }
            if (left == null) {
                return 1;
            }
            if (right == null) {
                return -1;
            }
            Integer rankCompare = compareEvalRank(left.evalRank, right.evalRank);
            if (rankCompare != 0) {
                return rankCompare;
            }
            String leftName = left.evalCategory == null ? '' : left.evalCategory;
            String rightName = right.evalCategory == null ? '' : right.evalCategory;
            return leftName.compareTo(rightName);
        }
    }

    /****************************************************************************************
     * ASSIGN RACK (GW-3816)
     ****************************************************************************************/

    private static final Set<String> ASSIGN_RACK_BLOCKED_STATUSES = new Set<String>{
        'Received',
        'Divide',
        'Evaluate',
        'Evaluate & Quote',
        'Quote'
    };

    @TestVisible
    private static final String ASSIGN_RACK_STATUS_BLOCKED_MESSAGE =
        'Only Work Orders that have advanced to Ready for Repair can be assigned to a Rack';

    /**
     * @description GW-3816 - Result of assigning a Rack Location to a Work Order.
     */
    public class AssignRackResult {
        public Id workOrderId;
        public String workOrderNumber;
        public Id rackId;
        public String rackName;
        public Id assignmentHistoryId;
    }

    /**
     * @description GW-3816 - Assigns a Rack Location to the Work Order identified by record Id
     *              or Work Order Number. Rack is resolved by Location Name (barcode) or Id
     *              where LocationType = Rack. Optionally creates Rack WAH and ends open
     *              Technician WAH rows.
     * @param workOrderInput Work Order Id or WorkOrderNumber
     * @param rackInput Rack Location Id or Name
     * @return AssignRackResult with Work Order and Rack identifiers
     * @throws WorkOrdersServiceException when validation fails or the operation cannot complete
     * @example
     * WorkOrdersService.AssignRackResult result =
     *     WorkOrdersService.assignRack('00001234', 'RACK-01');
     */
    public static AssignRackResult assignRack(String workOrderInput, String rackInput) {
        Logger.setScenario('Assign Rack');
        try {
            throwIfSimulated();
            return new AssignRackWorker().run(workOrderInput, rackInput);
        } catch (WorkOrdersServiceException e) {
            throw e;
        } catch (WOAssignmentHistoriesService.WOAssignmentHistoriesServiceException e) {
            Logger.error(
                new LogMessage(
                    'WorkOrdersService.assignRack WAH failed for WO {0} / Rack {1}: {2}',
                    workOrderInput,
                    rackInput,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrdersServiceException('Unable to assign rack: ' + e.getMessage(), e);
        } catch (DmlException e) {
            Logger.error(
                new LogMessage(
                    'WorkOrdersService.assignRack DML failed for WO {0} / Rack {1}: {2}',
                    workOrderInput,
                    rackInput,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrdersServiceException(
                'Unable to assign rack: ' + e.getDmlMessage(0),
                e
            );
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrdersService.assignRack unexpected error for WO {0} / Rack {1}: {2}',
                    workOrderInput,
                    rackInput,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrdersServiceException('Unable to assign rack: ' + e.getMessage(), e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5692 - When Status Assignment is populated, copies Status and Sub Status
     *              Assignment onto the Work Order. Sub Status Assignment is not applied alone.
     * @param workOrder Work Order being assigned a Rack
     * @param rack Assigned Rack
     */
    public static void applyRackStatusAssignment(WorkOrder workOrder, Schema.Location rack) {
        if (workOrder == null || rack == null) {
            return;
        }
        if (String.isNotBlank(rack.StatusAssignment__c)) {
            workOrder.Status = rack.StatusAssignment__c;
            workOrder.SubStatus__c = rack.SubStatusAssignment__c;
        }
    }

    /**
     * @description GW-6074 - Persists Rack assignment field updates. Status and Sub Status
     *              cannot be saved in one DML when Status Assignment changes the controlling picklist.
     * @param workOrder Work Order with Rack assignment values applied
     * @param rack Assigned Rack
     */
    public static void updateWorkOrderAfterRackAssignment(
        WorkOrder workOrder,
        Schema.Location rack
    ) {
        Boolean twoStepStatusThenSubStatus =
            String.isNotBlank(rack.StatusAssignment__c) &&
            String.isNotBlank(rack.SubStatusAssignment__c);
        if (twoStepStatusThenSubStatus) {
            workOrder.SubStatus__c = null;
        }
        Database.update(workOrder, AccessLevel.SYSTEM_MODE);
        if (twoStepStatusThenSubStatus) {
            workOrder.SubStatus__c = rack.SubStatusAssignment__c;
            Database.update(workOrder, AccessLevel.SYSTEM_MODE);
        }
    }

    /**
     * @description Shop-floor Assign Rack runs without sharing so scanners can resolve
     *              Work Orders / Racks regardless of record-level Location sharing.
     *              FLS-sensitive Location / WAH access remains SYSTEM_MODE in selectors/services.
     */
    private without sharing class AssignRackWorker {
        public AssignRackResult run(String workOrderInput, String rackInput) {
            if (String.isBlank(workOrderInput)) {
                throw new WorkOrdersServiceException('Work Order is required.');
            }
            if (String.isBlank(rackInput)) {
                throw new WorkOrdersServiceException('Rack is required.');
            }

            String trimmedWorkOrder = workOrderInput.trim();
            String trimmedRack = rackInput.trim();

            WorkOrder workOrder = WorkOrdersSelector.selectByIdOrNumber(trimmedWorkOrder);
            if (workOrder == null) {
                throw new WorkOrdersServiceException(
                    'Work Order "' + trimmedWorkOrder + '" was not found.'
                );
            }
            if (ASSIGN_RACK_BLOCKED_STATUSES.contains(workOrder.Status)) {
                throw new WorkOrdersServiceException(ASSIGN_RACK_STATUS_BLOCKED_MESSAGE);
            }

            Schema.Location rack = LocationsSelector.selectRackByIdOrName(trimmedRack);
            if (rack == null) {
                throw new WorkOrdersServiceException(
                    'Rack "' + trimmedRack + '" was not found.'
                );
            }

            Datetime now = Datetime.now();
            workOrder.Rack__c = rack.Id;
            if (String.isNotBlank(rack.Repair_Category__c)) {
                workOrder.RepairCategory__c = rack.Repair_Category__c;
            }
            applyRackStatusAssignment(workOrder, rack);
            updateWorkOrderAfterRackAssignment(workOrder, rack);

            Id rackHistoryId = null;
            if (rack.TrackRackAssignmentHistory__c == true) {
                rackHistoryId = WOAssignmentHistoriesService.createRackAssignment(
                    workOrder.Id,
                    rack.Id,
                    now
                );
            }
            WOAssignmentHistoriesService.endOpenTechnicianAssignments(workOrder.Id, now);

            AssignRackResult result = new AssignRackResult();
            result.workOrderId = workOrder.Id;
            result.workOrderNumber = workOrder.WorkOrderNumber;
            result.rackId = rack.Id;
            result.rackName = rack.Name;
            result.assignmentHistoryId = rackHistoryId;
            return result;
        }
    }

    /****************************************************************************************
     * ASSIGN TECHNICIAN (GW-3816 / GW-5455)
     ****************************************************************************************/

    private static final Set<String> ASSIGN_TECHNICIAN_BLOCKED_STATUSES = new Set<String>{
        'Received',
        'Divide',
        'Evaluate',
        'Evaluate & Quote',
        'Quote'
    };

    @TestVisible
    private static final String ASSIGN_TECHNICIAN_STATUS_BLOCKED_MESSAGE =
        'Only Work Orders that have advanced to Ready for Repair can be assigned to a Technician';

    /**
     * @description GW-3816 - Result of assigning a Technician to a Work Order.
     */
    public class AssignTechnicianResult {
        public Id workOrderId;
        public String workOrderNumber;
        public Id assignmentHistoryId;
    }

    /**
     * @description GW-3816 / GW-5455 - Assigns the running user as Technician on the Work Order
     *              identified by record Id or Work Order Number. Ends open Rack WAH, ends open
     *              Technician WAH owned by other users, creates a Technician WAH only when the
     *              running user does not already have one, and sets Work Order Owner.
     * @param workOrderInput Work Order Id or WorkOrderNumber
     * @return AssignTechnicianResult with Work Order and assignment history identifiers
     * @throws WorkOrdersServiceException when validation fails or the operation cannot complete
     * @example
     * WorkOrdersService.AssignTechnicianResult result =
     *     WorkOrdersService.assignTechnician('00001234');
     */
    public static AssignTechnicianResult assignTechnician(String workOrderInput) {
        Logger.setScenario('Assign Technician');
        try {
            throwIfSimulated();
            return new AssignTechnicianWorker().run(workOrderInput);
        } catch (WorkOrdersServiceException e) {
            throw e;
        } catch (WOAssignmentHistoriesService.WOAssignmentHistoriesServiceException e) {
            Logger.error(
                new LogMessage(
                    'WorkOrdersService.assignTechnician WAH failed for WO {0}: {1}',
                    workOrderInput,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrdersServiceException(
                'Unable to assign technician: ' + e.getMessage(),
                e
            );
        } catch (DmlException e) {
            Logger.error(
                new LogMessage(
                    'WorkOrdersService.assignTechnician DML failed for WO {0}: {1}',
                    workOrderInput,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrdersServiceException(
                'Unable to assign technician: ' + e.getDmlMessage(0),
                e
            );
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrdersService.assignTechnician unexpected error for WO {0}: {1}',
                    workOrderInput,
                    e.getMessage()
                ),
                e
            );
            throw new WorkOrdersServiceException(
                'Unable to assign technician: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Shop-floor Assign Technician runs without sharing so scanners can resolve
     *              Work Orders regardless of record-level sharing. WAH DML remains SYSTEM_MODE
     *              in WOAssignmentHistoriesService.
     */
    private without sharing class AssignTechnicianWorker {
        public AssignTechnicianResult run(String workOrderInput) {
            if (String.isBlank(workOrderInput)) {
                throw new WorkOrdersServiceException('Work Order is required.');
            }

            String trimmedWorkOrder = workOrderInput.trim();
            WorkOrder workOrder = WorkOrdersSelector.selectByIdOrNumber(trimmedWorkOrder);
            if (workOrder == null) {
                throw new WorkOrdersServiceException(
                    'Work Order "' + trimmedWorkOrder + '" was not found.'
                );
            }
            if (ASSIGN_TECHNICIAN_BLOCKED_STATUSES.contains(workOrder.Status)) {
                throw new WorkOrdersServiceException(ASSIGN_TECHNICIAN_STATUS_BLOCKED_MESSAGE);
            }

            Id technicianUserId = UserInfo.getUserId();
            Id assignmentHistoryId =
                WOAssignmentHistoriesService.assignCurrentUserAsTechnician(workOrder.Id);

            workOrder.OwnerId = technicianUserId;
            Database.update(workOrder, AccessLevel.SYSTEM_MODE);

            AssignTechnicianResult result = new AssignTechnicianResult();
            result.workOrderId = workOrder.Id;
            result.workOrderNumber = workOrder.WorkOrderNumber;
            result.assignmentHistoryId = assignmentHistoryId;
            return result;
        }
    }

    // =========================================================================
    // OUTSIDE VENDOR (GW-3850 / GW-4616)
    // Creates/reuses Outside Vendor Work Orders for Device and Instrument Evaluation.
    // =========================================================================

    private static final String WO_RECORD_TYPE_VENDOR = 'RepairCenterVendor';
    private static final String WOLI_RECORD_TYPE_PRODUCT_SERVICED = 'ProductServiced';
    private static final String WOLI_LINE_TYPE_PRODUCT_SERVICED = 'Product Serviced';
    private static final String WO_STATUS_CANCELED = 'Canceled';
    private static final String WOLI_STATUS_WAITING = 'Waiting for Approval';
    private static final String WOLI_STATUS_APPROVED = 'Approved';
    private static final String MSG_VENDOR_WO_LOCKED =
        'This item cannot be removed from the Vendor Work Order because a Vendor Return Order exists. ' +
        'Create a new Vendor Work Order for additional vendor items.';

    /**
     * @description GW-3850 / GW-4616 - Vendor details + line context for Instrument Evaluation Complete.
     */
    public class VendorLineInput {
        public Id productId;
        public Decimal quantity;
        public Id vendorAccountId;
        public String instructionsToVendor;
        public String sterisPurchaseOrderToVendor;
        public String vendorNotes;
        public String vendorReferenceNumber;
        public Decimal vendorCost;
        public Date shippedToVendorDate;
        public String trackingNumber;
        public Id childProductServicedId;
    }

    /**
     * @description GW-3850 / GW-4616 / GW-5865 - Vendor header details for Device Evaluation Vendor Information tab.
     */
    public class VendorHeaderDetails {
        public Id vendorAccountId;
        public String instructionsToVendor;
        public String sterisPurchaseOrderToVendor;
        public String vendorNotes;
        public String vendorReferenceNumber;
        public Decimal vendorCost;
        public Date shippedToVendorDate;
        public String trackingNumber;
    }

    /**
     * @description GW-3850 / GW-4616 - Billing address display for the selected Vendor Account.
     */
    public class VendorAddressResult {
        @AuraEnabled
        public Id accountId { get; set; }
        @AuraEnabled
        public String formattedAddress { get; set; }
    }

    /**
     * @description GW-3850 / GW-4616 - Returns a single-line billing address for a Vendor Account.
     * @param accountId Account Id
     * @return Address result (blank formattedAddress when unavailable)
     */
    public static VendorAddressResult getVendorAddress(Id accountId) {
        VendorAddressResult result = new VendorAddressResult();
        result.accountId = accountId;
        result.formattedAddress = '';
        if (accountId == null) {
            return result;
        }
        List<Account> accounts = [
            SELECT
                BillingStreet,
                BillingCity,
                BillingState,
                BillingPostalCode,
                BillingCountry
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            return result;
        }
        result.formattedAddress = formatBillingAddress(accounts[0]);
        return result;
    }

    /**
     * @description GW-3850 / GW-4616 - Returns vendor header fields from a Vendor Work Order for
     *              evaluation display. FedEx / Consolidate Vendor Shipment updates Tracking Number
     *              on the Vendor WO; Device and Instrument Evaluation should read from that header
     *              when linked.
     * @param vendorWorkOrderId Vendor Work Order Id
     * @return Header details, or null when the Vendor WO is not found
     */
    public static VendorHeaderDetails getVendorWorkOrderHeaderDetails(Id vendorWorkOrderId) {
        if (vendorWorkOrderId == null) {
            return null;
        }
        List<WorkOrder> vendorWorkOrders = [
            SELECT
                Vendor__c,
                VendorReturnOrder__c,
                InstructionsToVendor__c,
                VendorNotes__c,
                VendorReferenceNumber__c,
                VendorCost__c,
                STERISPurchaseOrdertoVendor__c,
                ShippedToVendorDate__c
            FROM WorkOrder
            WHERE Id = :vendorWorkOrderId
            WITH USER_MODE
            LIMIT 1
        ];
        if (vendorWorkOrders.isEmpty()) {
            return null;
        }
        WorkOrder vendorWorkOrder = vendorWorkOrders[0];
        VendorHeaderDetails details = new VendorHeaderDetails();
        details.vendorAccountId = vendorWorkOrder.Vendor__c;
        details.instructionsToVendor = vendorWorkOrder.InstructionsToVendor__c;
        details.sterisPurchaseOrderToVendor = vendorWorkOrder.STERISPurchaseOrdertoVendor__c;
        details.vendorNotes = vendorWorkOrder.VendorNotes__c;
        details.vendorReferenceNumber = vendorWorkOrder.VendorReferenceNumber__c;
        details.vendorCost = vendorWorkOrder.VendorCost__c;
        details.shippedToVendorDate = vendorWorkOrder.ShippedToVendorDate__c;
        // GW-6358: tracking number comes from the first Shipment on the Vendor Return Order.
        if (vendorWorkOrder.VendorReturnOrder__c != null) {
            details.trackingNumber = ShipmentsService.getInitialTrackingNumberByReturnOrderId(
                    new Set<Id>{ vendorWorkOrder.VendorReturnOrder__c }
                )
                .get(vendorWorkOrder.VendorReturnOrder__c);
        }
        return details;
    }

    /**
     * @description GW-3850 / GW-4616 - Clears vendor processing from an Instrument Evaluation Product
     *              Serviced line and removes the mirrored line from the Vendor Work Order when present.
     * @param childProductServicedId Instrument Evaluation Product Serviced WOLI Id
     */
    public static void clearVendorFromInstrumentEvaluationLine(Id childProductServicedId) {
        if (childProductServicedId == null) {
            return;
        }
        List<WorkOrderLineItem> children = [
            SELECT
                Id,
                VendorProcessingRequired__c,
                VendorWorkOrder__c,
                Vendor__c,
                Quantity,
                Product2Id,
                PricebookEntry.Product2Id
            FROM WorkOrderLineItem
            WHERE Id = :childProductServicedId
            WITH USER_MODE
        ];
        if (children.isEmpty()) {
            return;
        }
        WorkOrderLineItem child = children[0];
        Id vendorWorkOrderId = child.VendorWorkOrder__c;
        Decimal lineQuantity = child.Quantity == null ? 1 : child.Quantity;
        Id productId = child.Product2Id != null
            ? child.Product2Id
            : child.PricebookEntry != null ? child.PricebookEntry.Product2Id : null;

        update new WorkOrderLineItem(
            Id = child.Id,
            VendorProcessingRequired__c = false,
            Vendor__c = null,
            VendorWorkOrder__c = null,
            InstructionsToVendor__c = null,
            VendorNotes__c = null,
            VendorReferenceNumber__c = null,
            VendorCost__c = null
        );

        if (vendorWorkOrderId == null) {
            return;
        }
        assertVendorWorkOrderUnlockedForItemRemoval(vendorWorkOrderId);

        Id productServicedRtId = getProductServicedRecordTypeId();
        if (productServicedRtId == null) {
            return;
        }
        List<WorkOrderLineItem> vendorPsLines = [
            SELECT Id, Quantity, Product2Id, PricebookEntry.Product2Id
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :vendorWorkOrderId
                AND RecordTypeId = :productServicedRtId
            WITH USER_MODE
        ];
        VendorLineInput matchInput = new VendorLineInput();
        matchInput.productId = productId;
        matchInput.quantity = lineQuantity;
        WorkOrderLineItem vendorPsLine = findMatchingVendorProductServicedLine(
            vendorPsLines,
            matchInput,
            new Set<Id>()
        );
        // If product/qty match fails but this Vendor WO has a single PS line, remove it —
        // IE clear-vendor / item-delete must not leave an orphan Vendor WOLI (Josh).
        if (vendorPsLine == null && vendorPsLines.size() == 1) {
            vendorPsLine = vendorPsLines[0];
        }
        if (vendorPsLine != null) {
            delete vendorPsLine;
        }

        List<WorkOrder> vendorWorkOrders = [
            SELECT Id, QuantityReceived__c, Status
            FROM WorkOrder
            WHERE Id = :vendorWorkOrderId
            WITH USER_MODE
        ];
        if (!vendorWorkOrders.isEmpty()) {
            WorkOrder vendorWorkOrder = vendorWorkOrders[0];
            Decimal currentQty =
                vendorWorkOrder.QuantityReceived__c == null ? 0 : vendorWorkOrder.QuantityReceived__c;
            Decimal newQty = currentQty - lineQuantity;
            if (newQty < 0) {
                newQty = 0;
            }
            update new WorkOrder(Id = vendorWorkOrder.Id, QuantityReceived__c = newQty);
        }
        cancelVendorWorkOrderWhenNoProductServicedLines(vendorWorkOrderId, productServicedRtId);
    }

    /**
     * @description GW-3850 / GW-4616 - After IE Product Serviced lines are created on the eval WO,
     *              create or reuse one Vendor WO per distinct Vendor, add PS lines, stamp child WOLIs,
     *              and sync vendor field updates onto already-linked Vendor WO / WOLI records.
     * @param sourceWorkOrderId Eval / child Work Order Id
     * @param vendorLines Vendor-flagged draft lines with childProductServicedId populated
     */
    public static void createForInstrumentEvaluation(
        Id sourceWorkOrderId,
        List<VendorLineInput> vendorLines
    ) {
        if (sourceWorkOrderId == null || vendorLines == null || vendorLines.isEmpty()) {
            return;
        }

        List<VendorLineInput> actionable = new List<VendorLineInput>();
        Set<Id> childProductServicedIds = new Set<Id>();
        for (VendorLineInput line : vendorLines) {
            if (line == null || line.vendorAccountId == null || line.childProductServicedId == null) {
                continue;
            }
            if (String.isBlank(line.instructionsToVendor)) {
                throw new WorkOrdersServiceException(
                    'Instructions to Vendor is required when Vendor Processing Required is checked.'
                );
            }
            actionable.add(line);
            childProductServicedIds.add(line.childProductServicedId);
        }
        if (actionable.isEmpty()) {
            return;
        }

        Map<Id, WorkOrderLineItem> existingChildrenById = new Map<Id, WorkOrderLineItem>(
            [
                SELECT Id, VendorWorkOrder__c, Product2Id, PricebookEntry.Product2Id, Quantity
                FROM WorkOrderLineItem
                WHERE Id IN :childProductServicedIds
                WITH USER_MODE
            ]
        );
        List<VendorLineInput> linesToSync = new List<VendorLineInput>();
        List<VendorLineInput> linesNeedingVendorWo = new List<VendorLineInput>();
        for (VendorLineInput line : actionable) {
            WorkOrderLineItem existingChild = existingChildrenById.get(line.childProductServicedId);
            if (existingChild != null && existingChild.VendorWorkOrder__c != null) {
                linesToSync.add(line);
            } else {
                linesNeedingVendorWo.add(line);
            }
        }

        WorkOrder sourceWorkOrder = selectSourceWorkOrder(sourceWorkOrderId);
        Id otherRecordTypeId = getRepairCenterVendorRecordTypeId();
        Id productServicedRtId = getProductServicedRecordTypeId();
        if (otherRecordTypeId == null) {
            throw new WorkOrdersServiceException(
                'Repair Center - Vendor Work Order record type was not found.'
            );
        }
        if (productServicedRtId == null) {
            throw new WorkOrdersServiceException(
                'Product Serviced Work Order Line Item record type was not found.'
            );
        }

        if (!linesToSync.isEmpty()) {
            syncInstrumentVendorLines(
                sourceWorkOrder,
                linesToSync,
                existingChildrenById,
                otherRecordTypeId,
                productServicedRtId
            );
        }
        if (linesNeedingVendorWo.isEmpty()) {
            return;
        }

        Map<Id, List<VendorLineInput>> linesByVendorId = new Map<Id, List<VendorLineInput>>();
        Set<Id> productIds = new Set<Id>();
        Set<Id> vendorAccountIds = new Set<Id>();
        for (VendorLineInput line : linesNeedingVendorWo) {
            if (!linesByVendorId.containsKey(line.vendorAccountId)) {
                linesByVendorId.put(line.vendorAccountId, new List<VendorLineInput>());
            }
            linesByVendorId.get(line.vendorAccountId).add(line);
            vendorAccountIds.add(line.vendorAccountId);
            if (line.productId != null) {
                productIds.add(line.productId);
            }
        }

        Map<Id, Product2> productsById = selectProductsById(productIds);
        Map<Id, WorkOrder> existingVendorWoByVendorId = selectVendorWorkOrdersByVendor(
            sourceWorkOrder.Id,
            vendorAccountIds,
            otherRecordTypeId
        );

        List<WorkOrder> vendorWorkOrdersToInsert = new List<WorkOrder>();
        List<WorkOrder> vendorWorkOrdersToUpdate = new List<WorkOrder>();
        Map<Id, WorkOrder> newVendorWoByVendorId = new Map<Id, WorkOrder>();

        for (Id vendorAccountId : linesByVendorId.keySet()) {
            List<VendorLineInput> groupLines = linesByVendorId.get(vendorAccountId);
            VendorLineInput first = groupLines[0];
            Decimal quantityReceived = 0;
            for (VendorLineInput line : groupLines) {
                quantityReceived += line.quantity == null ? 0 : line.quantity;
            }

            WorkOrder existingVendorWo = existingVendorWoByVendorId.get(vendorAccountId);
            if (existingVendorWo != null) {
                applyVendorHeaderFields(existingVendorWo, vendorAccountId, first);
                Decimal currentQty = existingVendorWo.QuantityReceived__c == null
                    ? 0
                    : existingVendorWo.QuantityReceived__c;
                existingVendorWo.QuantityReceived__c = currentQty + quantityReceived;
                vendorWorkOrdersToUpdate.add(existingVendorWo);
            } else {
                WorkOrder vendorWorkOrder = buildVendorWorkOrder(
                    sourceWorkOrder,
                    otherRecordTypeId,
                    vendorAccountId,
                    first,
                    quantityReceived
                );
                vendorWorkOrdersToInsert.add(vendorWorkOrder);
                newVendorWoByVendorId.put(vendorAccountId, vendorWorkOrder);
            }
        }

        if (!vendorWorkOrdersToInsert.isEmpty()) {
            insert vendorWorkOrdersToInsert;
            for (Id vendorAccountId : newVendorWoByVendorId.keySet()) {
                existingVendorWoByVendorId.put(
                    vendorAccountId,
                    newVendorWoByVendorId.get(vendorAccountId)
                );
            }
        }
        if (!vendorWorkOrdersToUpdate.isEmpty()) {
            update vendorWorkOrdersToUpdate;
        }

        List<WorkOrderLineItem> vendorProductServicedLines = new List<WorkOrderLineItem>();
        List<WorkOrderLineItem> childUpdates = new List<WorkOrderLineItem>();

        for (Id vendorAccountId : linesByVendorId.keySet()) {
            WorkOrder vendorWorkOrder = existingVendorWoByVendorId.get(vendorAccountId);
            for (VendorLineInput line : linesByVendorId.get(vendorAccountId)) {
                Product2 product = productsById.get(line.productId);
                vendorProductServicedLines.add(
                    buildVendorProductServicedLine(
                        sourceWorkOrder,
                        vendorWorkOrder.Id,
                        productServicedRtId,
                        product,
                        line
                    )
                );
                childUpdates.add(buildChildVendorStamp(line, vendorWorkOrder.Id, vendorAccountId));
            }
        }

        if (!vendorProductServicedLines.isEmpty()) {
            insert vendorProductServicedLines;
        }
        if (!childUpdates.isEmpty()) {
            update childUpdates;
        }
    }

    /**
     * @description GW-3850 / GW-4616 - Persists Device Evaluation vendor header fields and creates
     *              a Vendor WO when Sub Status changes to Ship to Vendor and Vendor Work Order is
     *              still blank.
     * @param sourceWorkOrderId Device Evaluation Work Order Id
     * @param priorSubStatus Sub Status before save
     * @param newSubStatus Sub Status after save
     * @param details Vendor header values from the LWC
     * @return Created Vendor Work Order Id when created; otherwise existing VendorWorkOrder__c
     */

    /**
     * @description GW-3850 / GW-4616 - Outside Vendor header + Vendor WO create (LWC 3-arg entry).
     */
    public static Id handleDeviceEvaluationOutsideVendor(
        Id sourceWorkOrderId,
        String newSubStatus,
        VendorHeaderDetails details
    ) {
        return handleDeviceEvaluationOutsideVendor(
            sourceWorkOrderId,
            null,
            newSubStatus,
            details
        );
    }
    public static Id handleDeviceEvaluationOutsideVendor(
        Id sourceWorkOrderId,
        String priorSubStatus,
        String newSubStatus,
        VendorHeaderDetails details
    ) {
        if (sourceWorkOrderId == null) {
            throw new WorkOrdersServiceException('Work Order is required.');
        }
        WorkOrder sourceWorkOrder = selectSourceWorkOrder(sourceWorkOrderId);

        WorkOrder headerUpdate = new WorkOrder(Id = sourceWorkOrderId);
        if (details != null) {
            headerUpdate.Vendor__c = details.vendorAccountId;
            headerUpdate.InstructionsToVendor__c = details.instructionsToVendor;
            headerUpdate.STERISPurchaseOrdertoVendor__c = details.sterisPurchaseOrderToVendor;
            headerUpdate.VendorNotes__c = details.vendorNotes;
            headerUpdate.VendorReferenceNumber__c = details.vendorReferenceNumber;
            headerUpdate.VendorCost__c = details.vendorCost;
            headerUpdate.ShippedToVendorDate__c = details.shippedToVendorDate;
            update headerUpdate;
            sourceWorkOrder = selectSourceWorkOrder(sourceWorkOrderId);
        }

        if (sourceWorkOrder.VendorWorkOrder__c != null) {
            if (details != null) {
                syncDeviceVendorWorkOrder(
                    sourceWorkOrder.VendorWorkOrder__c,
                    details,
                    sourceWorkOrder
                );
            }
            return sourceWorkOrder.VendorWorkOrder__c;
        }

        Boolean changedToOutsideVendor =
            WO_SUB_STATUS_SHIP_TO_VENDOR.equals(newSubStatus) &&
            !WO_SUB_STATUS_SHIP_TO_VENDOR.equals(priorSubStatus);
        if (!changedToOutsideVendor) {
            return sourceWorkOrder.VendorWorkOrder__c;
        }
        if (sourceWorkOrder.Vendor__c == null) {
            throw new WorkOrdersServiceException(
                'Vendor is required when Sub Status is Ship to Vendor.'
            );
        }
        if (String.isBlank(sourceWorkOrder.InstructionsToVendor__c)) {
            throw new WorkOrdersServiceException(
                'Instructions to Vendor is required when Sub Status is Ship to Vendor.'
            );
        }

        Id otherRecordTypeId = getRepairCenterVendorRecordTypeId();
        Id productServicedRtId = getProductServicedRecordTypeId();
        if (otherRecordTypeId == null || productServicedRtId == null) {
            throw new WorkOrdersServiceException(
                'Required Outside Vendor record types were not found.'
            );
        }

        VendorLineInput detailsAsLine = new VendorLineInput();
        detailsAsLine.vendorAccountId = sourceWorkOrder.Vendor__c;
        detailsAsLine.instructionsToVendor = sourceWorkOrder.InstructionsToVendor__c;
        detailsAsLine.sterisPurchaseOrderToVendor = sourceWorkOrder.STERISPurchaseOrdertoVendor__c;
        detailsAsLine.vendorNotes = sourceWorkOrder.VendorNotes__c;
        detailsAsLine.vendorReferenceNumber = sourceWorkOrder.VendorReferenceNumber__c;
        detailsAsLine.vendorCost = sourceWorkOrder.VendorCost__c;
        detailsAsLine.shippedToVendorDate = sourceWorkOrder.ShippedToVendorDate__c;
        detailsAsLine.quantity = sourceWorkOrder.QuantityReceived__c == null
            ? 1
            : sourceWorkOrder.QuantityReceived__c;
        detailsAsLine.productId =
            sourceWorkOrder.Product__c != null
                ? sourceWorkOrder.Product__c
                : (sourceWorkOrder.Asset != null ? sourceWorkOrder.Asset.Product2Id : null);

        WorkOrder vendorWorkOrder = buildVendorWorkOrder(
            sourceWorkOrder,
            otherRecordTypeId,
            sourceWorkOrder.Vendor__c,
            detailsAsLine,
            detailsAsLine.quantity
        );
        insert vendorWorkOrder;

        Product2 product = null;
        if (detailsAsLine.productId != null) {
            List<Product2> products = [
                SELECT Id, Name, ProductCode, Description, Model__c
                FROM Product2
                WHERE Id = :detailsAsLine.productId
                WITH USER_MODE
                LIMIT 1
            ];
            product = products.isEmpty() ? null : products[0];
        }
        insert buildVendorProductServicedLine(
            sourceWorkOrder,
            vendorWorkOrder.Id,
            productServicedRtId,
            product,
            detailsAsLine
        );

        update new WorkOrder(Id = sourceWorkOrderId, VendorWorkOrder__c = vendorWorkOrder.Id);
        stampChildProductServicedForDevice(
            sourceWorkOrder,
            vendorWorkOrder.Id,
            detailsAsLine
        );
        return vendorWorkOrder.Id;
    }

    private static void stampChildProductServicedForDevice(
        WorkOrder sourceWorkOrder,
        Id vendorWorkOrderId,
        VendorLineInput details
    ) {
        Id productServicedRtId = getProductServicedRecordTypeId();
        if (productServicedRtId == null) {
            return;
        }
        List<WorkOrderLineItem> childLines = [
            SELECT Id
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :sourceWorkOrder.Id
                AND RecordTypeId = :productServicedRtId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (childLines.isEmpty()) {
            return;
        }
        update new WorkOrderLineItem(
            Id = childLines[0].Id,
            VendorProcessingRequired__c = true,
            VendorWorkOrder__c = vendorWorkOrderId,
            Vendor__c = details.vendorAccountId,
            InstructionsToVendor__c = details.instructionsToVendor,
            VendorNotes__c = details.vendorNotes,
            VendorReferenceNumber__c = details.vendorReferenceNumber,
            VendorCost__c = details.vendorCost
        );
    }

    /**
     * @description Pushes Device Evaluation vendor header edits onto the existing Vendor WO,
     *              its Product Serviced lines, and the eval child Product Serviced stamp.
     */
    private static void syncDeviceVendorWorkOrder(
        Id vendorWorkOrderId,
        VendorHeaderDetails details,
        WorkOrder sourceWorkOrder
    ) {
        WorkOrder vendorUpdate = new WorkOrder(Id = vendorWorkOrderId);
        applyVendorHeaderFields(vendorUpdate, details.vendorAccountId, toLineInput(details));
        update vendorUpdate;

        Id productServicedRtId = getProductServicedRecordTypeId();
        if (productServicedRtId != null) {
            List<WorkOrderLineItem> vendorLines = [
                SELECT Id
                FROM WorkOrderLineItem
                WHERE WorkOrderId = :vendorWorkOrderId
                    AND RecordTypeId = :productServicedRtId
                WITH USER_MODE
            ];
            List<WorkOrderLineItem> vendorLineUpdates = new List<WorkOrderLineItem>();
            for (WorkOrderLineItem vendorLine : vendorLines) {
                vendorLineUpdates.add(
                    buildVendorLineFieldUpdate(vendorLine.Id, details.vendorAccountId, toLineInput(details))
                );
            }
            if (!vendorLineUpdates.isEmpty()) {
                update vendorLineUpdates;
            }
        }

        VendorLineInput asLine = toLineInput(details);
        stampChildProductServicedForDevice(sourceWorkOrder, vendorWorkOrderId, asLine);
    }

    /**
     * @description Syncs vendor field edits for Instrument lines already linked to a Vendor WO.
     *              Same vendor keeps/reuses that WO; a different vendor moves the line to the
     *              matching Vendor WO (create if needed).
     */
    private static void syncInstrumentVendorLines(
        WorkOrder sourceWorkOrder,
        List<VendorLineInput> linesToSync,
        Map<Id, WorkOrderLineItem> existingChildrenById,
        Id otherRecordTypeId,
        Id productServicedRtId
    ) {
        Set<Id> currentVendorWoIds = new Set<Id>();
        Set<Id> targetVendorIds = new Set<Id>();
        Set<Id> productIds = new Set<Id>();
        for (VendorLineInput line : linesToSync) {
            WorkOrderLineItem child = existingChildrenById.get(line.childProductServicedId);
            if (child != null && child.VendorWorkOrder__c != null) {
                currentVendorWoIds.add(child.VendorWorkOrder__c);
            }
            targetVendorIds.add(line.vendorAccountId);
            if (line.productId != null) {
                productIds.add(line.productId);
            }
        }

        Map<Id, WorkOrder> vendorWoById = new Map<Id, WorkOrder>(
            [
                SELECT
                    Id,
                    Vendor__c,
                    VendorReturnOrder__c,
                    QuantityReceived__c,
                    InstructionsToVendor__c,
                    VendorNotes__c,
                    VendorReferenceNumber__c,
                    VendorCost__c,
                    STERISPurchaseOrdertoVendor__c,
                    ShippedToVendorDate__c
                FROM WorkOrder
                WHERE Id IN :currentVendorWoIds
                WITH USER_MODE
            ]
        );
        Map<Id, WorkOrder> vendorWoByVendorId = selectVendorWorkOrdersByVendor(
            sourceWorkOrder.Id,
            targetVendorIds,
            otherRecordTypeId
        );
        for (WorkOrder vendorWo : vendorWoById.values()) {
            if (vendorWo.Vendor__c != null && vendorWo.VendorReturnOrder__c == null) {
                vendorWoByVendorId.put(vendorWo.Vendor__c, vendorWo);
            }
        }

        Map<Id, Product2> productsById = selectProductsById(productIds);

        // Phase 1: ensure a Vendor WO exists for every target vendor (insert new ones first).
        Map<Id, WorkOrder> pendingNewVendorWoByVendorId = new Map<Id, WorkOrder>();
        List<WorkOrder> vendorWoInserts = new List<WorkOrder>();
        for (VendorLineInput line : linesToSync) {
            if (vendorWoByVendorId.containsKey(line.vendorAccountId)) {
                continue;
            }
            if (
                hasLineLinkedToLockedVendorWorkOrder(
                    line.vendorAccountId,
                    linesToSync,
                    existingChildrenById,
                    vendorWoById
                )
            ) {
                continue;
            }
            if (pendingNewVendorWoByVendorId.containsKey(line.vendorAccountId)) {
                continue;
            }
            Decimal quantityReceived = line.quantity == null ? 1 : line.quantity;
            WorkOrder newVendorWo = buildVendorWorkOrder(
                sourceWorkOrder,
                otherRecordTypeId,
                line.vendorAccountId,
                line,
                quantityReceived
            );
            vendorWoInserts.add(newVendorWo);
            pendingNewVendorWoByVendorId.put(line.vendorAccountId, newVendorWo);
        }
        if (!vendorWoInserts.isEmpty()) {
            insert vendorWoInserts;
            for (Id vendorAccountId : pendingNewVendorWoByVendorId.keySet()) {
                vendorWoByVendorId.put(
                    vendorAccountId,
                    pendingNewVendorWoByVendorId.get(vendorAccountId)
                );
            }
        }

        Set<Id> allVendorWoIds = new Set<Id>(vendorWoById.keySet());
        allVendorWoIds.addAll(new Map<Id, WorkOrder>(vendorWoByVendorId.values()).keySet());
        Map<Id, List<WorkOrderLineItem>> vendorPsLinesByWoId = selectVendorProductServicedLinesByWoId(
            allVendorWoIds,
            productServicedRtId
        );

        List<WorkOrder> vendorWoUpdates = new List<WorkOrder>();
        List<WorkOrderLineItem> vendorPsInserts = new List<WorkOrderLineItem>();
        List<WorkOrderLineItem> vendorPsUpdates = new List<WorkOrderLineItem>();
        List<WorkOrderLineItem> childUpdates = new List<WorkOrderLineItem>();
        Set<Id> claimedVendorPsLineIds = new Set<Id>();

        for (VendorLineInput line : linesToSync) {
            WorkOrderLineItem child = existingChildrenById.get(line.childProductServicedId);
            if (child == null || child.VendorWorkOrder__c == null) {
                continue;
            }
            WorkOrder currentVendorWo = vendorWoById.get(child.VendorWorkOrder__c);
            WorkOrder targetVendorWo = vendorWoByVendorId.get(line.vendorAccountId);
            if (
                targetVendorWo == null &&
                currentVendorWo != null &&
                currentVendorWo.VendorReturnOrder__c != null &&
                currentVendorWo.Vendor__c == line.vendorAccountId
            ) {
                targetVendorWo = currentVendorWo;
            }
            if (targetVendorWo == null) {
                continue;
            }

            Boolean sameVendorWo =
                currentVendorWo != null && currentVendorWo.Id == targetVendorWo.Id;
            applyVendorHeaderFields(targetVendorWo, line.vendorAccountId, line);
            vendorWoUpdates.add(targetVendorWo);

            if (sameVendorWo) {
                WorkOrderLineItem matchedPs = findMatchingVendorProductServicedLine(
                    vendorPsLinesByWoId.get(targetVendorWo.Id),
                    line,
                    claimedVendorPsLineIds
                );
                if (matchedPs != null) {
                    claimedVendorPsLineIds.add(matchedPs.Id);
                    vendorPsUpdates.add(
                        buildVendorLineFieldUpdate(matchedPs.Id, line.vendorAccountId, line)
                    );
                } else if (currentVendorWo != null && currentVendorWo.VendorReturnOrder__c != null) {
                    WorkOrder unlockedVendorWo = resolveUnlockedVendorWorkOrderForAdd(
                        sourceWorkOrder,
                        line,
                        otherRecordTypeId,
                        vendorWoByVendorId,
                        pendingNewVendorWoByVendorId
                    );
                    if (unlockedVendorWo != null) {
                        Product2 product = productsById.get(line.productId);
                        vendorPsInserts.add(
                            buildVendorProductServicedLine(
                                sourceWorkOrder,
                                unlockedVendorWo.Id,
                                productServicedRtId,
                                product,
                                line
                            )
                        );
                        childUpdates.add(
                            buildChildVendorStamp(
                                line,
                                unlockedVendorWo.Id,
                                line.vendorAccountId
                            )
                        );
                    }
                } else {
                    Product2 product = productsById.get(line.productId);
                    vendorPsInserts.add(
                        buildVendorProductServicedLine(
                            sourceWorkOrder,
                            targetVendorWo.Id,
                            productServicedRtId,
                            product,
                            line
                        )
                    );
                }
            } else {
                Product2 product = productsById.get(line.productId);
                vendorPsInserts.add(
                    buildVendorProductServicedLine(
                        sourceWorkOrder,
                        targetVendorWo.Id,
                        productServicedRtId,
                        product,
                        line
                    )
                );
            }
            childUpdates.add(
                buildChildVendorStamp(line, targetVendorWo.Id, line.vendorAccountId)
            );
        }

        if (!vendorWoUpdates.isEmpty()) {
            Map<Id, WorkOrder> uniqueVendorUpdates = new Map<Id, WorkOrder>();
            for (WorkOrder vendorWo : vendorWoUpdates) {
                if (vendorWo.Id != null) {
                    uniqueVendorUpdates.put(vendorWo.Id, vendorWo);
                }
            }
            update uniqueVendorUpdates.values();
        }
        if (!vendorPsInserts.isEmpty()) {
            insert vendorPsInserts;
        }
        if (!vendorPsUpdates.isEmpty()) {
            update vendorPsUpdates;
        }
        if (!childUpdates.isEmpty()) {
            update childUpdates;
        }
    }

    private static VendorLineInput toLineInput(VendorHeaderDetails details) {
        VendorLineInput line = new VendorLineInput();
        if (details == null) {
            return line;
        }
        line.vendorAccountId = details.vendorAccountId;
        line.instructionsToVendor = details.instructionsToVendor;
        line.sterisPurchaseOrderToVendor = details.sterisPurchaseOrderToVendor;
        line.vendorNotes = details.vendorNotes;
        line.vendorReferenceNumber = details.vendorReferenceNumber;
        line.vendorCost = details.vendorCost;
        line.shippedToVendorDate = details.shippedToVendorDate;
        line.trackingNumber = details.trackingNumber;
        return line;
    }

    private static void applyVendorHeaderFields(
        WorkOrder vendorWorkOrder,
        Id vendorAccountId,
        VendorLineInput details
    ) {
        Boolean locked = isVendorWorkOrderLocked(vendorWorkOrder);
        if (!locked) {
            vendorWorkOrder.Vendor__c = vendorAccountId;
            if (details != null) {
                vendorWorkOrder.InstructionsToVendor__c = details.instructionsToVendor;
                if (details.shippedToVendorDate != null) {
                    vendorWorkOrder.ShippedToVendorDate__c = details.shippedToVendorDate;
                }
            }
        }
        if (details == null) {
            return;
        }
        vendorWorkOrder.STERISPurchaseOrdertoVendor__c = details.sterisPurchaseOrderToVendor;
        vendorWorkOrder.VendorNotes__c = details.vendorNotes;
        vendorWorkOrder.VendorReferenceNumber__c = details.vendorReferenceNumber;
        vendorWorkOrder.VendorCost__c = details.vendorCost;
    }

    private static Boolean isVendorWorkOrderLocked(WorkOrder vendorWorkOrder) {
        if (vendorWorkOrder == null) {
            return false;
        }
        if (vendorWorkOrder.VendorReturnOrder__c != null) {
            return true;
        }
        return vendorWorkOrder.Id != null && vendorWorkOrderHasReturnOrder(vendorWorkOrder.Id);
    }

    private static WorkOrderLineItem buildChildVendorStamp(
        VendorLineInput line,
        Id vendorWorkOrderId,
        Id vendorAccountId
    ) {
        // GW-4616 / Josh: vendor detail fields live on the Vendor WO header, not the WOLI.
        return new WorkOrderLineItem(
            Id = line.childProductServicedId,
            VendorProcessingRequired__c = true,
            VendorWorkOrder__c = vendorWorkOrderId,
            Vendor__c = vendorAccountId
        );
    }

    private static WorkOrderLineItem buildVendorLineFieldUpdate(
        Id vendorLineId,
        Id vendorAccountId,
        VendorLineInput details
    ) {
        // Product Serviced lines on the Vendor WO only carry the Vendor lookup; details are header-level.
        return new WorkOrderLineItem(
            Id = vendorLineId,
            Vendor__c = vendorAccountId
        );
    }

    private static WorkOrderLineItem findMatchingVendorProductServicedLine(
        List<WorkOrderLineItem> vendorLines,
        VendorLineInput line,
        Set<Id> claimedIds
    ) {
        if (vendorLines == null || vendorLines.isEmpty()) {
            return null;
        }
        WorkOrderLineItem productMatch = null;
        for (WorkOrderLineItem vendorLine : vendorLines) {
            if (claimedIds.contains(vendorLine.Id)) {
                continue;
            }
            Id lineProductId = resolveProductId(vendorLine);
            if (line.productId != null && lineProductId == line.productId) {
                Decimal lineQty = line.quantity == null ? 1 : line.quantity;
                Decimal vendorQty = vendorLine.Quantity == null ? 1 : vendorLine.Quantity;
                if (lineQty == vendorQty) {
                    return vendorLine;
                }
                if (productMatch == null) {
                    productMatch = vendorLine;
                }
            }
        }
        if (productMatch != null) {
            return productMatch;
        }
        for (WorkOrderLineItem vendorLine : vendorLines) {
            if (!claimedIds.contains(vendorLine.Id)) {
                return vendorLine;
            }
        }
        return null;
    }

    private static Id resolveProductId(WorkOrderLineItem line) {
        if (line == null) {
            return null;
        }
        if (line.Product2Id != null) {
            return line.Product2Id;
        }
        return line.PricebookEntry != null ? line.PricebookEntry.Product2Id : null;
    }

    private static Map<Id, Product2> selectProductsById(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new Map<Id, Product2>();
        }
        return new Map<Id, Product2>(
            [
                SELECT Id, Name, ProductCode, Description, Model__c
                FROM Product2
                WHERE Id IN :productIds
                WITH USER_MODE
            ]
        );
    }

    private static Map<Id, WorkOrder> selectVendorWorkOrdersByVendor(
        Id sourceWorkOrderId,
        Set<Id> vendorAccountIds,
        Id otherRecordTypeId
    ) {
        Map<Id, WorkOrder> byVendorId = new Map<Id, WorkOrder>();
        if (
            sourceWorkOrderId == null ||
            vendorAccountIds == null ||
            vendorAccountIds.isEmpty() ||
            otherRecordTypeId == null
        ) {
            return byVendorId;
        }
        for (WorkOrder vendorWo : [
            SELECT
                Id,
                Vendor__c,
                VendorReturnOrder__c,
                QuantityReceived__c,
                InstructionsToVendor__c,
                VendorNotes__c,
                VendorReferenceNumber__c,
                VendorCost__c,
                STERISPurchaseOrdertoVendor__c,
                ShippedToVendorDate__c
            FROM WorkOrder
            WHERE
                ParentWorkOrderId = :sourceWorkOrderId
                AND RecordTypeId = :otherRecordTypeId
                AND Vendor__c IN :vendorAccountIds
                AND Status != :WO_STATUS_CANCELED
                AND VendorReturnOrder__c = null
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ]) {
            if (vendorWo.Vendor__c != null && !byVendorId.containsKey(vendorWo.Vendor__c)) {
                byVendorId.put(vendorWo.Vendor__c, vendorWo);
            }
        }
        return byVendorId;
    }

    private static Map<Id, List<WorkOrderLineItem>> selectVendorProductServicedLinesByWoId(
        Set<Id> vendorWorkOrderIds,
        Id productServicedRtId
    ) {
        Map<Id, List<WorkOrderLineItem>> byWoId = new Map<Id, List<WorkOrderLineItem>>();
        if (
            vendorWorkOrderIds == null ||
            vendorWorkOrderIds.isEmpty() ||
            productServicedRtId == null
        ) {
            return byWoId;
        }
        // List query (not SOQL for-loop): multiple binds in a for-loop SOQL can throw tmpVar1.
        List<WorkOrderLineItem> lines = [
            SELECT
                Id,
                WorkOrderId,
                Product2Id,
                PricebookEntry.Product2Id,
                Quantity,
                Vendor__c,
                InstructionsToVendor__c,
                VendorNotes__c,
                VendorReferenceNumber__c,
                VendorCost__c
            FROM WorkOrderLineItem
            WHERE WorkOrderId IN :vendorWorkOrderIds
                AND RecordTypeId = :productServicedRtId
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ];
        for (WorkOrderLineItem line : lines) {
            if (!byWoId.containsKey(line.WorkOrderId)) {
                byWoId.put(line.WorkOrderId, new List<WorkOrderLineItem>());
            }
            byWoId.get(line.WorkOrderId).add(line);
        }
        return byWoId;
    }

    private static WorkOrder buildVendorWorkOrder(
        WorkOrder sourceWorkOrder,
        Id otherRecordTypeId,
        Id vendorAccountId,
        VendorLineInput details,
        Decimal quantityReceived
    ) {
        WorkOrder vendorWorkOrder = new WorkOrder();
        vendorWorkOrder.RecordTypeId = otherRecordTypeId;
        vendorWorkOrder.ParentWorkOrderId = sourceWorkOrder.Id;
        vendorWorkOrder.AccountId = sourceWorkOrder.AccountId;
        vendorWorkOrder.ContactId = sourceWorkOrder.ContactId;
        vendorWorkOrder.RepairCenter__c = sourceWorkOrder.RepairCenter__c;
        vendorWorkOrder.OperatingUnit__c = sourceWorkOrder.OperatingUnit__c;
        vendorWorkOrder.Department__c = sourceWorkOrder.Department__c;
        vendorWorkOrder.AssetId = sourceWorkOrder.AssetId;
        vendorWorkOrder.Product__c =
            sourceWorkOrder.Product__c != null
                ? sourceWorkOrder.Product__c
                : (sourceWorkOrder.Asset != null ? sourceWorkOrder.Asset.Product2Id : null);
        vendorWorkOrder.Subject = sourceWorkOrder.Subject;
        vendorWorkOrder.Description = sourceWorkOrder.Description;
        vendorWorkOrder.CustomerPO__c = sourceWorkOrder.CustomerPO__c;
        vendorWorkOrder.QuantityReceived__c = quantityReceived;
        vendorWorkOrder.EstimateRequired__c = sourceWorkOrder.EstimateRequired__c;
        vendorWorkOrder.Pricebook2Id = sourceWorkOrder.Pricebook2Id;
        vendorWorkOrder.CurrencyIsoCode = sourceWorkOrder.CurrencyIsoCode;
        vendorWorkOrder.Vendor__c = vendorAccountId;
        vendorWorkOrder.InstructionsToVendor__c = details.instructionsToVendor;
        vendorWorkOrder.STERISPurchaseOrdertoVendor__c = details.sterisPurchaseOrderToVendor;
        vendorWorkOrder.VendorNotes__c = details.vendorNotes;
        vendorWorkOrder.VendorReferenceNumber__c = details.vendorReferenceNumber;
        vendorWorkOrder.VendorCost__c = details.vendorCost;
        vendorWorkOrder.ShippedToVendorDate__c =
            details.shippedToVendorDate == null ? Date.today() : details.shippedToVendorDate;
        vendorWorkOrder.Status = WO_STATUS_RECEIVED;
        vendorWorkOrder.SubStatus__c = WO_SUB_STATUS_SHIP_TO_VENDOR;
        return vendorWorkOrder;
    }

    private static WorkOrderLineItem buildVendorProductServicedLine(
        WorkOrder sourceWorkOrder,
        Id vendorWorkOrderId,
        Id productServicedRtId,
        Product2 product,
        VendorLineInput details
    ) {
        WorkOrderLineItem line = new WorkOrderLineItem();
        line.RecordTypeId = productServicedRtId;
        line.LineType__c = WOLI_LINE_TYPE_PRODUCT_SERVICED;
        line.WorkOrderId = vendorWorkOrderId;
        line.TopLevelWorkOrder__c = sourceWorkOrder.ParentWorkOrderId;
        line.Subject = sourceWorkOrder.Subject;
        line.Description = sourceWorkOrder.Description;
        line.TrayName__c = sourceWorkOrder.TrayName__c;
        line.Quantity = details.quantity == null || details.quantity < 1 ? 1 : details.quantity;
        line.Model__c =
            product != null && String.isNotBlank(product.Model__c)
                ? product.Model__c
                : sourceWorkOrder.Model__c;
        /*
         * Quantity requires PBE or Product2Id. Asset + Product2Id is rejected when they conflict;
         * Asset + matching PBE is allowed (receiving pattern). Prefer PBE for the item product.
         */
        Id pricebookEntryId = null;
        if (
            product != null &&
            sourceWorkOrder.Pricebook2Id != null &&
            String.isNotBlank(sourceWorkOrder.CurrencyIsoCode)
        ) {
            Map<Id, Id> pricebookEntryIdsByProductId =
                PricebookEntriesService.getPricebookEntryIdsByProductId(
                    sourceWorkOrder.Pricebook2Id,
                    new Set<Id>{ product.Id },
                    sourceWorkOrder.CurrencyIsoCode
                );
            pricebookEntryId = pricebookEntryIdsByProductId.get(product.Id);
        }
        Boolean assetMatchesProduct =
            product != null &&
            sourceWorkOrder.AssetId != null &&
            sourceWorkOrder.Asset != null &&
            sourceWorkOrder.Asset.Product2Id == product.Id;
        if (pricebookEntryId != null) {
            line.PricebookEntryId = pricebookEntryId;
        } else if (product != null) {
            line.Product2Id = product.Id;
        }
        if (product != null) {
            line.ProductCodeWoli__c = product.ProductCode;
            line.ProductDescription__c = product.Description;
        }
        if (assetMatchesProduct && pricebookEntryId != null) {
            line.AssetId = sourceWorkOrder.AssetId;
            line.SerialNumber__c = sourceWorkOrder.Asset.SerialNumber;
        } else if (product == null && sourceWorkOrder.AssetId != null) {
            line.AssetId = sourceWorkOrder.AssetId;
            line.SerialNumber__c =
                sourceWorkOrder.Asset != null ? sourceWorkOrder.Asset.SerialNumber : null;
        }
        line.Vendor__c = details.vendorAccountId;
        line.Status = ESTIMATE_REQUIRED_VALUE.equals(sourceWorkOrder.EstimateRequired__c)
            ? WOLI_STATUS_WAITING
            : WOLI_STATUS_APPROVED;
        return line;
    }

    private static WorkOrder selectSourceWorkOrder(Id workOrderId) {
        List<WorkOrder> rows = [
            SELECT
                Id,
                AccountId,
                ContactId,
                RepairCenter__c,
                OperatingUnit__c,
                Department__c,
                AssetId,
                Product__c,
                Subject,
                Description,
                CustomerPO__c,
                QuantityReceived__c,
                EstimateRequired__c,
                Pricebook2Id,
                CurrencyIsoCode,
                ParentWorkOrderId,
                Model__c,
                TrayName__c,
                Vendor__c,
                VendorWorkOrder__c,
                InstructionsToVendor__c,
                VendorNotes__c,
                VendorReferenceNumber__c,
                VendorCost__c,
                STERISPurchaseOrdertoVendor__c,
                ShippedToVendorDate__c,
                Asset.SerialNumber,
                Asset.Product2Id
            FROM WorkOrder
            WHERE Id = :workOrderId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new WorkOrdersServiceException('Work Order was not found.');
        }
        return rows[0];
    }

    private static String formatBillingAddress(Account accountRow) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(accountRow.BillingStreet)) {
            parts.add(accountRow.BillingStreet);
        }
        List<String> cityStateZip = new List<String>();
        if (String.isNotBlank(accountRow.BillingCity)) {
            cityStateZip.add(accountRow.BillingCity);
        }
        if (String.isNotBlank(accountRow.BillingState)) {
            cityStateZip.add(accountRow.BillingState);
        }
        if (String.isNotBlank(accountRow.BillingPostalCode)) {
            cityStateZip.add(accountRow.BillingPostalCode);
        }
        if (!cityStateZip.isEmpty()) {
            parts.add(String.join(cityStateZip, ', '));
        }
        if (String.isNotBlank(accountRow.BillingCountry)) {
            parts.add(accountRow.BillingCountry);
        }
        return String.join(parts, ' · ');
    }

    private static Id getRepairCenterVendorRecordTypeId() {
        Schema.RecordTypeInfo info = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get(WO_RECORD_TYPE_VENDOR);
        return info != null ? info.getRecordTypeId() : null;
    }

    private static Id getProductServicedRecordTypeId() {
        Schema.RecordTypeInfo info = Schema.SObjectType.WorkOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get(WOLI_RECORD_TYPE_PRODUCT_SERVICED);
        return info != null ? info.getRecordTypeId() : null;
    }

    /**
     * @description GW-4616 - Cancels a Vendor Work Order when its last Product Serviced line is removed.
     * @param vendorWorkOrderId Vendor Work Order Id
     * @param productServicedRtId Product Serviced WOLI RecordType Id
     */
    /**
     * @description True when the Vendor WO has a Vendor Return Order (GW-5298).
     * @param vendorWorkOrderId Vendor Work Order Id
     * @return Whether VendorReturnOrder__c is populated
     */
    private static Boolean vendorWorkOrderHasReturnOrder(Id vendorWorkOrderId) {
        if (vendorWorkOrderId == null) {
            return false;
        }
        List<WorkOrder> rows = [
            SELECT VendorReturnOrder__c
            FROM WorkOrder
            WHERE Id = :vendorWorkOrderId
            WITH USER_MODE
            LIMIT 1
        ];
        return !rows.isEmpty() && rows[0].VendorReturnOrder__c != null;
    }

    private static void assertVendorWorkOrderUnlockedForItemRemoval(Id vendorWorkOrderId) {
        if (vendorWorkOrderHasReturnOrder(vendorWorkOrderId)) {
            throw new WorkOrdersServiceException(MSG_VENDOR_WO_LOCKED);
        }
    }

    private static Boolean hasLineLinkedToLockedVendorWorkOrder(
        Id vendorAccountId,
        List<VendorLineInput> lines,
        Map<Id, WorkOrderLineItem> existingChildrenById,
        Map<Id, WorkOrder> vendorWoById
    ) {
        if (vendorAccountId == null || lines == null || lines.isEmpty()) {
            return false;
        }
        for (VendorLineInput line : lines) {
            if (line == null || line.vendorAccountId != vendorAccountId) {
                continue;
            }
            WorkOrderLineItem child = existingChildrenById.get(line.childProductServicedId);
            if (child == null || child.VendorWorkOrder__c == null) {
                continue;
            }
            WorkOrder vendorWo = vendorWoById.get(child.VendorWorkOrder__c);
            if (
                vendorWo != null &&
                vendorWo.Vendor__c == vendorAccountId &&
                vendorWo.VendorReturnOrder__c != null
            ) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Returns an unlocked Vendor WO for a new line when the prior Vendor WO has RO.
     */
    private static WorkOrder resolveUnlockedVendorWorkOrderForAdd(
        WorkOrder sourceWorkOrder,
        VendorLineInput line,
        Id otherRecordTypeId,
        Map<Id, WorkOrder> vendorWoByVendorId,
        Map<Id, WorkOrder> pendingNewVendorWoByVendorId
    ) {
        if (line == null || line.vendorAccountId == null) {
            return null;
        }
        WorkOrder unlockedVendorWo = vendorWoByVendorId.get(line.vendorAccountId);
        if (unlockedVendorWo != null) {
            return unlockedVendorWo;
        }
        if (pendingNewVendorWoByVendorId.containsKey(line.vendorAccountId)) {
            return pendingNewVendorWoByVendorId.get(line.vendorAccountId);
        }
        Decimal quantityReceived = line.quantity == null ? 1 : line.quantity;
        WorkOrder newVendorWo = buildVendorWorkOrder(
            sourceWorkOrder,
            otherRecordTypeId,
            line.vendorAccountId,
            line,
            quantityReceived
        );
        insert newVendorWo;
        pendingNewVendorWoByVendorId.put(line.vendorAccountId, newVendorWo);
        vendorWoByVendorId.put(line.vendorAccountId, newVendorWo);
        return newVendorWo;
    }

    private static void cancelVendorWorkOrderWhenNoProductServicedLines(
        Id vendorWorkOrderId,
        Id productServicedRtId
    ) {
        if (vendorWorkOrderId == null || productServicedRtId == null) {
            return;
        }
        Integer remainingLineCount = [
            SELECT COUNT()
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :vendorWorkOrderId
                AND RecordTypeId = :productServicedRtId
            WITH USER_MODE
        ];
        if (remainingLineCount == 0) {
            update new WorkOrder(Id = vendorWorkOrderId, Status = WO_STATUS_CANCELED);
        }
    }

    // ── GW-3880 Consolidate Vendor Shipment ────────────────────────────────────

    private static final String VCS_WO_STATUS_SHIP_TO_VENDOR = 'Ship to Vendor';

    /**
     * @description GW-3880 - Row returned by getVendorWorkOrdersForConsolidation.
     */
    public class VendorConsolidationWorkOrderRow {
        public Id id;
        public String workOrderNumber;
        public Id parentWorkOrderId;
        public String parentWorkOrderNumber;
        public String status;
        public String subStatus;
        public Id vendorId;
        public String vendorName;
        public String vendorAddress;
        public Boolean hasVendorAddress;
        public Id repairCenterId;
        public String repairCenterName;
        public String customerPo;
        public String groupKey;
    }

    /**
     * @description GW-3880 - Init payload for Consolidate Vendor Shipment LWC.
     */
    public class VendorConsolidationInitResult {
        public Id repairCenterId;
        public String repairCenterName;
        public Boolean hasRepairCenterAddress;
        public List<VendorConsolidationWorkOrderRow> workOrders;
        public String errorMessage;
    }

    /**
     * @description Loads Outside Vendor work orders for the running user's Repair Center.
     * @return Init context and eligible Work Order rows
     */
    public static VendorConsolidationInitResult getVendorWorkOrdersForConsolidation() {
        VendorConsolidationInitResult result = new VendorConsolidationInitResult();
        result.workOrders = new List<VendorConsolidationWorkOrderRow>();

        Id repairCenterId = ServiceResourcesService.getRepairCenterIdForCurrentUser();
        if (repairCenterId == null) {
            result.errorMessage =
                'No active Service Resource with a Repair Center was found for your user. ' +
                'Ask an administrator to assign a Service Resource Repair Center.';
            return result;
        }

        List<Schema.Location> repairCenters = LocationsSelector.selectById(
            new Set<Id>{ repairCenterId }
        );
        Schema.Location repairCenter = repairCenters.isEmpty() ? null : repairCenters[0];
        if (repairCenter == null) {
            result.errorMessage = 'Repair Center was not found for your user.';
            return result;
        }

        result.repairCenterId = repairCenter.Id;
        result.repairCenterName = repairCenter.Name;
        result.hasRepairCenterAddress = ReturnOrdersService.hasRepairCenterAddress(repairCenter.Id);
        if (!result.hasRepairCenterAddress) {
            result.errorMessage =
                'Repair Center "' +
                repairCenter.Name +
                '" address is incomplete (needs Street, City, State, and Postal Code). ' +
                'Add a full address on the Location before consolidating vendor shipments.';
            return result;
        }

        Id otherRtId = getRepairCenterVendorRecordTypeId();
        List<WorkOrder> workOrders = WorkOrdersSelector.selectOutsideVendorForConsolidation(
            repairCenterId,
            otherRtId,
            WO_SUB_STATUS_SHIP_TO_VENDOR
        );

        Set<Id> vendorIds = new Set<Id>();
        for (WorkOrder wo : workOrders) {
            if (wo.Vendor__c != null) {
                vendorIds.add(wo.Vendor__c);
            }
        }
        Map<Id, Account> vendorAccountById = new VendorAddressAccess().getAccountsById(vendorIds);
        Map<Id, String> relatedAddressByVendorId = new VendorAddressAccess()
            .getRelatedAddressDisplayByAccountId(vendorIds);

        for (WorkOrder wo : workOrders) {
            Account vendorAccount = wo.Vendor__c == null
                ? null
                : vendorAccountById.get(wo.Vendor__c);
            result.workOrders.add(
                toVendorConsolidationWorkOrderRow(wo, vendorAccount, relatedAddressByVendorId)
            );
        }
        return result;
    }

    /**
     * @description GW-3880 - Loads Work Orders selected for vendor consolidation Complete.
     * @param workOrderIds Selected Work Order Ids
     * @return Matching Work Order rows
     */
    public static List<WorkOrder> getWorkOrdersForVendorConsolidationComplete(List<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        return WorkOrdersSelector.selectForVendorConsolidationComplete(new Set<Id>(workOrderIds));
    }

    /**
     * @description GW-3880 - Validates selected Work Orders before vendor consolidation Complete.
     * @param workOrders Work Orders to validate
     * @param userRepairCenterId Running user's Repair Center Id
     */
    public static void validateWorkOrdersForVendorConsolidation(
        List<WorkOrder> workOrders,
        Id userRepairCenterId
    ) {
        if (workOrders == null || workOrders.isEmpty()) {
            throw new WorkOrdersServiceException('No matching work orders were found.');
        }

        Set<Id> vendorIds = new Set<Id>();
        Id otherRtId = getRepairCenterVendorRecordTypeId();
        for (WorkOrder wo : workOrders) {
            if (wo.RecordTypeId != otherRtId) {
                throw new WorkOrdersServiceException(
                    'Work Order ' +
                        wo.WorkOrderNumber +
                        ' must be Repair Center Vendor record type.'
                );
            }
            if (wo.SubStatus__c != WO_SUB_STATUS_SHIP_TO_VENDOR) {
                throw new WorkOrdersServiceException(
                    'Work Order ' +
                        wo.WorkOrderNumber +
                        ' is not in Ship to Vendor sub status.'
                );
            }
            if (wo.RepairCenter__c != userRepairCenterId) {
                throw new WorkOrdersServiceException(
                    'Work Order ' +
                        wo.WorkOrderNumber +
                        ' does not belong to your Repair Center.'
                );
            }
            if (wo.Vendor__c == null) {
                throw new WorkOrdersServiceException(
                    'Work Order ' +
                        wo.WorkOrderNumber +
                        ' does not have a Vendor assigned.'
                );
            }
            if (wo.VendorReturnOrder__c != null) {
                throw new WorkOrdersServiceException(
                    'Work Order ' +
                        wo.WorkOrderNumber +
                        ' already has a Vendor Return Order and cannot be consolidated again.'
                );
            }
            vendorIds.add(wo.Vendor__c);
        }

        if (vendorIds.size() > 1) {
            throw new WorkOrdersServiceException(
                'All selected Work Orders must have the same Vendor.'
            );
        }

        Map<Id, Account> vendorAccountById = new VendorAddressAccess().getAccountsById(vendorIds);
        Map<Id, String> relatedAddressByVendorId = new VendorAddressAccess()
            .getRelatedAddressDisplayByAccountId(vendorIds);
        for (WorkOrder wo : workOrders) {
            Account vendorAccount = wo.Vendor__c == null
                ? null
                : vendorAccountById.get(wo.Vendor__c);
            if (vendorAccount == null) {
                vendorAccount = wo.Vendor__r;
            }
            if (!vendorHasConsolidationAddress(vendorAccount, relatedAddressByVendorId.get(wo.Vendor__c))) {
                String vendorName = vendorAccount == null || String.isBlank(vendorAccount.Name)
                    ? (wo.Vendor__r == null || String.isBlank(wo.Vendor__r.Name)
                          ? 'the selected Vendor'
                          : wo.Vendor__r.Name)
                    : vendorAccount.Name;
                throw new WorkOrdersServiceException(
                    'Vendor "' +
                        vendorName +
                        '" must have a complete ship-to address (Street, City, State, Postal Code) ' +
                        'on the Account or a related Address record.'
                );
            }
        }

        String vendorNameForFedEx = workOrders[0].Vendor__r == null
            ? null
            : workOrders[0].Vendor__r.Name;
        List<Schema.Location> repairCenters = LocationsSelector.selectById(
            new Set<Id>{ userRepairCenterId }
        );
        Schema.Location repairCenter = repairCenters.isEmpty() ? null : repairCenters[0];
        String addressError = ReturnOrdersService.getShipmentAddressValidationError(
            workOrders[0].Vendor__c,
            vendorNameForFedEx,
            userRepairCenterId,
            repairCenter == null ? null : repairCenter.Name
        );
        if (String.isNotBlank(addressError)) {
            throw new WorkOrdersServiceException(addressError);
        }
    }

    /**
     * @description GW-3880 - WOLIs grouped by Work Order Id for vendor consolidation.
     * @param workOrders Source Work Orders
     * @return Map of Work Order Id to WOLI list
     */
    public static Map<Id, List<WorkOrderLineItem>> getWorkOrderLineItemsForVendorConsolidation(
        List<WorkOrder> workOrders
    ) {
        Set<Id> workOrderIds = new Set<Id>();
        for (WorkOrder wo : workOrders) {
            workOrderIds.add(wo.Id);
        }
        Map<Id, List<WorkOrderLineItem>> byWorkOrderId = new Map<Id, List<WorkOrderLineItem>>();
        if (workOrderIds.isEmpty()) {
            return byWorkOrderId;
        }
        for (WorkOrderLineItem woli : WorkOrderLineItemsSelector.selectForVendorConsolidationByWorkOrderIds(
            workOrderIds
        )) {
            if (!byWorkOrderId.containsKey(woli.WorkOrderId)) {
                byWorkOrderId.put(woli.WorkOrderId, new List<WorkOrderLineItem>());
            }
            byWorkOrderId.get(woli.WorkOrderId).add(woli);
        }
        return byWorkOrderId;
    }

    /**
     * @description GW-3880 - Sets Status to Ship to Vendor and clears Sub Status on source WOs.
     * @param workOrders Work Orders to update
     */
    public static void updateWorkOrderStatusToShipToVendor(List<WorkOrder> workOrders) {
        List<WorkOrder> toUpdate = new List<WorkOrder>();
        for (WorkOrder wo : workOrders) {
            WorkOrder updateWo = new WorkOrder(
                Id = wo.Id,
                Status = VCS_WO_STATUS_SHIP_TO_VENDOR
            );
            updateWo.put('SubStatus__c', null);
            toUpdate.add(updateWo);
        }
        if (!toUpdate.isEmpty()) {
            new VendorShipmentDml().updateRecords(toUpdate);
        }
    }

    /**
     * @description GW-5298 - Links source WOLIs/WOs to the new Vendor Return Order and Outbound ROLI.
     *              Writes VendorReturnOrder__c / VendorReturnOrderLineItem__c only so Customer
     *              Return Order mappings on ReturnOrder__c / ReturnOrderId / ReturnOrderLineItemId
     *              are left unchanged.
     * @param outboundLines Inserted Outbound ROLIs
     * @param outboundSourceWolis Matching source WOLIs
     */
    public static void linkSourceRecordsToVendorShipment(
        List<ReturnOrderLineItem> outboundLines,
        List<WorkOrderLineItem> outboundSourceWolis
    ) {
        if (
            outboundLines == null ||
            outboundSourceWolis == null ||
            outboundLines.isEmpty() ||
            outboundLines.size() != outboundSourceWolis.size()
        ) {
            return;
        }

        List<WorkOrderLineItem> wolisToUpdate = new List<WorkOrderLineItem>();
        Map<Id, Id> vendorReturnOrderIdByWorkOrderId = new Map<Id, Id>();
        for (Integer i = 0; i < outboundLines.size(); i++) {
            ReturnOrderLineItem outbound = outboundLines[i];
            WorkOrderLineItem sourceWoli = outboundSourceWolis[i];
            WorkOrderLineItem woliUpdate = new WorkOrderLineItem(Id = sourceWoli.Id);
            woliUpdate.put('VendorReturnOrder__c', outbound.ReturnOrderId);
            woliUpdate.put('VendorReturnOrderLineItem__c', outbound.Id);
            wolisToUpdate.add(woliUpdate);
            if (sourceWoli.WorkOrderId != null) {
                vendorReturnOrderIdByWorkOrderId.put(sourceWoli.WorkOrderId, outbound.ReturnOrderId);
            }
        }
        new VendorShipmentDml().updateRecords(wolisToUpdate);

        List<WorkOrder> workOrdersToUpdate = new List<WorkOrder>();
        for (Id workOrderId : vendorReturnOrderIdByWorkOrderId.keySet()) {
            WorkOrder woUpdate = new WorkOrder(Id = workOrderId);
            woUpdate.put('VendorReturnOrder__c', vendorReturnOrderIdByWorkOrderId.get(workOrderId));
            workOrdersToUpdate.add(woUpdate);
        }
        if (!workOrdersToUpdate.isEmpty()) {
            new VendorShipmentDml().updateRecords(workOrdersToUpdate);
        }
    }

    /**
     * @description GW-6358 - Parent Work Order Id of each Work Order.
     * @param workOrderIdSet Work Order Ids
     * @return Parent Work Order Id by Work Order Id (null value when a Work Order has no parent)
     * @example
     * Map<Id, Id> parentIdByWorkOrderIdMap = WorkOrdersService.getParentWorkOrderIdByWorkOrderId(workOrderIdSet);
     */
    public static Map<Id, Id> getParentWorkOrderIdByWorkOrderId(Set<Id> workOrderIdSet) {
        Map<Id, Id> parentWorkOrderIdByWorkOrderIdMap = new Map<Id, Id>();
        if (workOrderIdSet == null || workOrderIdSet.isEmpty()) {
            return parentWorkOrderIdByWorkOrderIdMap;
        }
        List<String> workOrderIdList = new List<String>();
        for (Id workOrderId : workOrderIdSet) {
            workOrderIdList.add(workOrderId);
        }
        List<WorkOrder> workOrderList = (List<WorkOrder>) new WorkOrdersSelector()
            .selectFields(new List<String>{ 'Id', 'ParentWorkOrderId' })
            .whereIn('Id', workOrderIdList)
            .execute();
        for (WorkOrder workOrderRecord : workOrderList) {
            parentWorkOrderIdByWorkOrderIdMap.put(workOrderRecord.Id, workOrderRecord.ParentWorkOrderId);
        }
        return parentWorkOrderIdByWorkOrderIdMap;
    }

    /**
     * @description GW-6358 - Vendor Return Order Ids of the given Vendor Work Orders.
     * @param vendorWorkOrders Vendor Work Orders with VendorReturnOrder__c queried
     * @return Vendor Return Order Ids
     */
    private static Set<Id> collectVendorReturnOrderIds(List<WorkOrder> vendorWorkOrders) {
        Set<Id> returnOrderIdSet = new Set<Id>();
        for (WorkOrder vendorWorkOrder : vendorWorkOrders) {
            if (vendorWorkOrder.VendorReturnOrder__c != null) {
                returnOrderIdSet.add(vendorWorkOrder.VendorReturnOrder__c);
            }
        }
        return returnOrderIdSet;
    }

    /**
     * @description GW-3880 - Work Orders for vendor FedEx packing slip rendering.
     * @param workOrderIds Grouped Work Order Ids
     * @return Work Order rows keyed by Id via caller
     */
    public static Map<Id, WorkOrder> getWorkOrdersByIdForVendorFedExShipment(Set<Id> workOrderIds) {
        return new Map<Id, WorkOrder>(
            WorkOrdersSelector.selectByIdForVendorFedExShipment(workOrderIds)
        );
    }

    private static VendorConsolidationWorkOrderRow toVendorConsolidationWorkOrderRow(
        WorkOrder wo,
        Account vendorAccount,
        Map<Id, String> relatedAddressByVendorId
    ) {
        VendorConsolidationWorkOrderRow row = new VendorConsolidationWorkOrderRow();
        row.id = wo.Id;
        row.workOrderNumber = wo.WorkOrderNumber;
        row.parentWorkOrderId = wo.ParentWorkOrderId;
        row.parentWorkOrderNumber = wo.ParentWorkOrder == null
            ? null
            : wo.ParentWorkOrder.WorkOrderNumber;
        row.status = wo.Status;
        row.subStatus = (String) wo.get('SubStatus__c');
        row.vendorId = (Id) wo.get('Vendor__c');
        row.vendorName = vendorAccount != null && String.isNotBlank(vendorAccount.Name)
            ? vendorAccount.Name
            : (wo.Vendor__r == null ? null : wo.Vendor__r.Name);
        String relatedAddress = row.vendorId == null || relatedAddressByVendorId == null
            ? null
            : relatedAddressByVendorId.get(row.vendorId);
        Account addressSource = vendorAccount != null ? vendorAccount : wo.Vendor__r;
        row.vendorAddress = resolveVendorAddressDisplay(addressSource, relatedAddress);
        row.hasVendorAddress = String.isNotBlank(row.vendorAddress);
        row.repairCenterId = (Id) wo.get('RepairCenter__c');
        row.repairCenterName = wo.RepairCenter__r == null
            ? null
            : wo.RepairCenter__r.Name;
        row.customerPo = (String) wo.get('CustomerPO__c');
        row.groupKey = row.vendorId == null
            ? 'NO_VENDOR'
            : String.valueOf(row.vendorId);
        return row;
    }

    private static Boolean vendorHasConsolidationAddress(Account vendor, String relatedAddress) {
        return String.isNotBlank(resolveVendorAddressDisplay(vendor, relatedAddress));
    }

    private static String resolveVendorAddressDisplay(Account vendor, String relatedAddress) {
        String accountAddress = formatVendorAccountAddress(vendor);
        if (String.isNotBlank(accountAddress)) {
            return accountAddress;
        }
        return String.isNotBlank(relatedAddress) ? relatedAddress : null;
    }

    private static String formatVendorAccountAddress(Account vendor) {
        if (vendor == null) {
            return null;
        }
        String billingState = String.isNotBlank(vendor.BillingStateCode)
            ? vendor.BillingStateCode
            : vendor.BillingState;
        String billing = formatVendorAddressParts(
            vendor.BillingStreet,
            vendor.BillingCity,
            billingState,
            vendor.BillingPostalCode,
            vendor.BillingCountry
        );
        if (String.isNotBlank(billing)) {
            return billing;
        }
        String shippingState = String.isNotBlank(vendor.ShippingStateCode)
            ? vendor.ShippingStateCode
            : vendor.ShippingState;
        return formatVendorAddressParts(
            vendor.ShippingStreet,
            vendor.ShippingCity,
            shippingState,
            vendor.ShippingPostalCode,
            vendor.ShippingCountry
        );
    }

    private static String formatVendorAddressParts(
        String street,
        String city,
        String state,
        String postalCode,
        String country
    ) {
        if (
            String.isBlank(street) ||
            String.isBlank(city) ||
            String.isBlank(state) ||
            String.isBlank(postalCode)
        ) {
            return null;
        }
        List<String> parts = new List<String>{ street, city, state, postalCode };
        if (String.isNotBlank(country)) {
            parts.add(country);
        }
        return String.join(parts, ', ');
    }

    /**
     * @description Elevates Account / Address reads for vendor ship-to display and validation.
     */
    private without sharing class VendorAddressAccess {
        private Map<Id, Account> getAccountsById(Set<Id> accountIds) {
            Map<Id, Account> byId = new Map<Id, Account>();
            if (accountIds == null || accountIds.isEmpty()) {
                return byId;
            }
            for (Account accountRecord : [
                SELECT
                    Id,
                    Name,
                    BillingStreet,
                    BillingCity,
                    BillingState,
                    BillingStateCode,
                    BillingPostalCode,
                    BillingCountry,
                    ShippingStreet,
                    ShippingCity,
                    ShippingState,
                    ShippingStateCode,
                    ShippingPostalCode,
                    ShippingCountry
                FROM Account
                WHERE Id IN :accountIds
            ]) {
                byId.put(accountRecord.Id, accountRecord);
            }
            return byId;
        }

        private Map<Id, String> getRelatedAddressDisplayByAccountId(Set<Id> accountIds) {
            Map<Id, String> byAccountId = new Map<Id, String>();
            if (accountIds == null || accountIds.isEmpty()) {
                return byAccountId;
            }
            for (SObject addressRecord : Database.query(
                'SELECT Customer__c, Street, City, State, StateCode, PostalCode, Country ' +
                    'FROM Address ' +
                    'WHERE Customer__c IN :accountIds ' +
                    'ORDER BY CreatedDate ASC'
            )) {
                Id accountId = (Id) addressRecord.get('Customer__c');
                if (accountId == null || byAccountId.containsKey(accountId)) {
                    continue;
                }
                String stateValue = (String) addressRecord.get('StateCode');
                if (String.isBlank(stateValue)) {
                    stateValue = (String) addressRecord.get('State');
                }
                String formatted = formatVendorAddressParts(
                    (String) addressRecord.get('Street'),
                    (String) addressRecord.get('City'),
                    stateValue,
                    (String) addressRecord.get('PostalCode'),
                    (String) addressRecord.get('Country')
                );
                if (String.isNotBlank(formatted)) {
                    byAccountId.put(accountId, formatted);
                }
            }
            return byAccountId;
        }
    }

    /**
     * @description Elevates vendor consolidation DML when Repair Center techs lack Account sharing.
     */
    private without sharing class VendorShipmentDml {
        private void updateRecords(List<SObject> records) {
            update records;
        }
    }

    /****************************************************************************************
     * GW-4006 MOD REQUEST FORM EMAIL
     ****************************************************************************************/

    /**
     * @description GW-4006 - Flow/invocable input for Mod Request Form email preview or send.
     */
    public class ModRequestFormEmailRequest {
        public Id workOrderId;
        public String operation;
        public String toAddress;
        public String subject;
        public String htmlBody;
    }

    /**
     * @description GW-4006 - Flow/invocable output for Mod Request Form email preview or send.
     */
    public class ModRequestFormEmailResponse {
        public Boolean eligible;
        public String toAddress;
        public String subject;
        public String htmlBody;
        public String templateName;
        public Boolean success;
        public String errorMessage;
    }

    /**
     * @description GW-4006 - Previews or sends Mod Request Form emails for Work Orders on Mod Hold.
     * @param requests Preview or Send commands from the Screen Flow invocable
     * @return One response per request, in the same order
     */
    public static List<ModRequestFormEmailResponse> processModRequestFormEmails(
        List<ModRequestFormEmailRequest> requests
    ) {
        List<ModRequestFormEmailResponse> responses = new List<ModRequestFormEmailResponse>();
        if (requests == null) {
            return responses;
        }

        try {
            throwIfSimulated();
            Set<Id> workOrderIds = getModRequestEmailWorkOrderIds(requests);
            Map<Id, WorkOrder> workOrdersById = new Map<Id, WorkOrder>(
                WorkOrdersSelector.selectByIdForModRequestFormEmail(workOrderIds)
            );
            EmailTemplate emailTemplate =
                workOrderIds.isEmpty() ? null : queryModRequestEmailTemplate();
            Messaging.EmailFileAttachment modFormAttachment =
                hasModRequestEmailSendOperation(requests)
                    ? buildModRequestFormAttachment()
                    : null;
            List<Messaging.SingleEmailMessage> emailsToSend =
                new List<Messaging.SingleEmailMessage>();
            List<Integer> sendResponseIndexes = new List<Integer>();
            List<Id> sendWorkOrderIds = new List<Id>();

            for (ModRequestFormEmailRequest request : requests) {
                ModRequestFormEmailResponse response = buildModRequestFormEmailResponse(
                    request,
                    workOrdersById,
                    emailTemplate
                );
                responses.add(response);

                if (response.success != true ||
                    request == null ||
                    !MOD_REQUEST_EMAIL_OPERATION_SEND.equalsIgnoreCase(
                        String.valueOf(request.operation)
                    )) {
                    continue;
                }

                emailsToSend.add(
                    buildModRequestOutboundEmail(
                        request.workOrderId,
                        response.toAddress,
                        response.subject,
                        response.htmlBody,
                        modFormAttachment
                    )
                );
                sendResponseIndexes.add(responses.size() - 1);
                sendWorkOrderIds.add(request.workOrderId);
                response.success = false;
            }

            sendModRequestFormEmails(
                emailsToSend,
                sendResponseIndexes,
                sendWorkOrderIds,
                responses
            );
        } catch (Exception caught) {
            Logger.error(
                new LogMessage(
                    'WorkOrdersService.processModRequestFormEmails failed for Work Orders {0}: {1}',
                    getModRequestEmailWorkOrderIds(requests),
                    caught.getMessage()
                ),
                caught
            );
            throw caught;
        } finally {
            Logger.saveLog();
        }

        return responses;
    }

    private static Set<Id> getModRequestEmailWorkOrderIds(
        List<ModRequestFormEmailRequest> requests
    ) {
        Set<Id> workOrderIds = new Set<Id>();
        if (requests == null) {
            return workOrderIds;
        }

        for (ModRequestFormEmailRequest request : requests) {
            if (request != null && request.workOrderId != null) {
                workOrderIds.add(request.workOrderId);
            }
        }
        return workOrderIds;
    }

    private static Boolean hasModRequestEmailSendOperation(
        List<ModRequestFormEmailRequest> requests
    ) {
        if (requests == null) {
            return false;
        }

        for (ModRequestFormEmailRequest request : requests) {
            if (request != null &&
                MOD_REQUEST_EMAIL_OPERATION_SEND.equalsIgnoreCase(
                    String.valueOf(request.operation)
                )) {
                return true;
            }
        }
        return false;
    }

    @TestVisible
    private static ModRequestFormEmailResponse buildModRequestFormEmailResponse(
        ModRequestFormEmailRequest request,
        Map<Id, WorkOrder> workOrdersById,
        EmailTemplate emailTemplate
    ) {
        ModRequestFormEmailResponse response = new ModRequestFormEmailResponse();
        response.eligible = false;
        response.success = false;

        if (request == null || request.workOrderId == null) {
            response.errorMessage = 'Work Order Id is required.';
            return response;
        }

        WorkOrder workOrder = workOrdersById.get(request.workOrderId);
        if (workOrder == null) {
            response.errorMessage = 'Work Order was not found.';
            return response;
        }

        if (!isEligibleForModRequestFormEmail(workOrder)) {
            response.errorMessage =
                'This action is only available when Mod Request is checked and Sub Status is Mod Hold.';
            return response;
        }

        response.eligible = true;

        if (emailTemplate == null) {
            response.errorMessage = 'Email template Mod Request Form Request was not found.';
            return response;
        }

        response.templateName = emailTemplate.Name;

        String resolvedToAddress = resolveModRequestToAddress(workOrder, request.toAddress);
        if (String.isBlank(resolvedToAddress)) {
            response.errorMessage = 'Mod Request Contact Email is required before sending.';
            return response;
        }

        try {
            throwIfSimulated();
            Messaging.SingleEmailMessage renderedEmail = renderModRequestEmail(
                emailTemplate.Id,
                workOrder
            );
            String renderedBody = resolveModRequestRenderedBody(renderedEmail);
            renderedBody = applyContactSalutation(renderedBody, resolveModRequestContactName(workOrder));

            response.toAddress = resolvedToAddress;
            response.subject = String.isNotBlank(request.subject)
                ? request.subject.trim()
                : renderedEmail.getSubject();
            response.htmlBody = String.isNotBlank(request.htmlBody) ? request.htmlBody : renderedBody;
        } catch (Exception caught) {
            logModRequestFormEmailError(request.workOrderId, caught);
            response.errorMessage = caught.getMessage();
            return response;
        }

        if (MOD_REQUEST_EMAIL_OPERATION_PREVIEW.equalsIgnoreCase(String.valueOf(request.operation))) {
            response.success = true;
            return response;
        }

        if (!MOD_REQUEST_EMAIL_OPERATION_SEND.equalsIgnoreCase(String.valueOf(request.operation))) {
            response.errorMessage = 'Unsupported operation. Use Preview or Send.';
            return response;
        }

        response.success = true;
        return response;
    }

    private static Boolean isEligibleForModRequestFormEmail(WorkOrder workOrder) {
        return workOrder.ModRequest__c == true &&
            workOrder.SubStatus__c == MOD_REQUEST_SUB_STATUS_MOD_HOLD;
    }

    private static EmailTemplate queryModRequestEmailTemplate() {
        List<EmailTemplate> templates = [
            SELECT Id, Name, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = :MOD_REQUEST_EMAIL_TEMPLATE_NAME
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0];
    }

    private static String resolveModRequestToAddress(WorkOrder workOrder, String requestedToAddress) {
        if (String.isNotBlank(requestedToAddress)) {
            return requestedToAddress.trim();
        }
        if (String.isNotBlank(workOrder.ModRequestContactEmail__c)) {
            return workOrder.ModRequestContactEmail__c.trim();
        }
        if (workOrder.ModRequestContact__r != null &&
            String.isNotBlank(workOrder.ModRequestContact__r.Email)) {
            return workOrder.ModRequestContact__r.Email.trim();
        }
        return null;
    }

    private static Messaging.SingleEmailMessage renderModRequestEmail(
        Id templateId,
        WorkOrder workOrder
    ) {
        Messaging.SingleEmailMessage renderedEmail = Messaging.renderStoredEmailTemplate(
            templateId,
            workOrder.ModRequestContact__c,
            workOrder.Id
        );
        if (renderedEmail == null) {
            throw new WorkOrdersServiceException(
                'Unable to render Mod Request Form email template.'
            );
        }
        return renderedEmail;
    }

    private static String resolveModRequestRenderedBody(Messaging.SingleEmailMessage renderedEmail) {
        if (String.isNotBlank(renderedEmail.getHtmlBody())) {
            return renderedEmail.getHtmlBody();
        }
        return renderedEmail.getPlainTextBody();
    }

    private static String resolveModRequestContactName(WorkOrder workOrder) {
        if (workOrder.ModRequestContact__r != null &&
            String.isNotBlank(workOrder.ModRequestContact__r.Name)) {
            return workOrder.ModRequestContact__r.Name.trim();
        }
        return null;
    }

    /**
     * @description GW-4006 - Replaces an empty Dear salutation with the Mod Request Contact name.
     * @param body Rendered email body
     * @param contactName Mod Request Contact name
     * @return Body with contact salutation applied
     */
    @TestVisible
    private static String applyContactSalutation(String body, String contactName) {
        if (String.isBlank(contactName)) {
            return body;
        }

        String salutation = 'Dear ' + contactName.trim() + ',';
        if (String.isBlank(body)) {
            return salutation;
        }

        String normalizedBody = body.startsWith('Dear') ? body : salutation + '\n\n' + body;
        Integer commaIndex = normalizedBody.indexOf(',');
        if (normalizedBody.startsWith('Dear') && commaIndex > 0) {
            return salutation + normalizedBody.substring(commaIndex + 1);
        }

        return salutation + '\n\n' + body;
    }

    private static Messaging.SingleEmailMessage buildModRequestOutboundEmail(
        Id workOrderId,
        String toAddress,
        String subject,
        String htmlBody,
        Messaging.EmailFileAttachment modFormAttachment
    ) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setWhatId(workOrderId);
        email.setSaveAsActivity(true);
        email.setTargetObjectId(null);
        email.setToAddresses(new List<String>{ toAddress });
        email.setSubject(subject);
        if (String.isBlank(htmlBody)) {
            email.setPlainTextBody('');
        } else if (htmlBody.contains('<') && htmlBody.contains('>')) {
            email.setHtmlBody(htmlBody);
        } else {
            email.setPlainTextBody(htmlBody);
        }

        if (modFormAttachment != null) {
            email.setFileAttachments(
                new List<Messaging.EmailFileAttachment>{ modFormAttachment }
            );
        }
        return email;
    }

    private static Messaging.EmailFileAttachment buildModRequestFormAttachment() {
        List<Document> documents = [
            SELECT Body, ContentType, Name
            FROM Document
            WHERE Name = :MOD_REQUEST_FORM_DOCUMENT_NAME
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (documents.isEmpty()) {
            return null;
        }

        Document modFormDocument = documents[0];
        Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
        attachment.setFileName(modFormDocument.Name);
        attachment.setBody(modFormDocument.Body);
        attachment.setContentType(
            String.isNotBlank(modFormDocument.ContentType)
                ? modFormDocument.ContentType
                : 'application/pdf'
        );
        return attachment;
    }

    private static void sendModRequestFormEmails(
        List<Messaging.SingleEmailMessage> emailsToSend,
        List<Integer> sendResponseIndexes,
        List<Id> sendWorkOrderIds,
        List<ModRequestFormEmailResponse> responses
    ) {
        if (emailsToSend == null || emailsToSend.isEmpty()) {
            return;
        }

        List<Messaging.SingleEmailMessage> firstEmailChunk =
            new List<Messaging.SingleEmailMessage>();
        List<Integer> firstResponseIndexChunk = new List<Integer>();
        List<Id> firstWorkOrderIdChunk = new List<Id>();
        List<Messaging.SingleEmailMessage> secondEmailChunk =
            new List<Messaging.SingleEmailMessage>();
        List<Integer> secondResponseIndexChunk = new List<Integer>();
        List<Id> secondWorkOrderIdChunk = new List<Id>();

        for (Integer emailIndex = 0; emailIndex < emailsToSend.size(); emailIndex++) {
            if (emailIndex < MOD_REQUEST_EMAIL_CHUNK_SIZE) {
                firstEmailChunk.add(emailsToSend[emailIndex]);
                firstResponseIndexChunk.add(sendResponseIndexes[emailIndex]);
                firstWorkOrderIdChunk.add(sendWorkOrderIds[emailIndex]);
            } else {
                secondEmailChunk.add(emailsToSend[emailIndex]);
                secondResponseIndexChunk.add(sendResponseIndexes[emailIndex]);
                secondWorkOrderIdChunk.add(sendWorkOrderIds[emailIndex]);
            }
        }

        sendModRequestFormEmailChunk(
            firstEmailChunk,
            firstResponseIndexChunk,
            firstWorkOrderIdChunk,
            responses
        );
        sendModRequestFormEmailChunk(
            secondEmailChunk,
            secondResponseIndexChunk,
            secondWorkOrderIdChunk,
            responses
        );
    }

    private static void sendModRequestFormEmailChunk(
        List<Messaging.SingleEmailMessage> emailChunk,
        List<Integer> responseIndexChunk,
        List<Id> workOrderIdChunk,
        List<ModRequestFormEmailResponse> responses
    ) {
        if (emailChunk.isEmpty()) {
            return;
        }

        try {
            throwIfSimulated();
            List<Messaging.SendEmailResult> sendResults = Messaging.sendEmail(emailChunk, false);
            for (Integer resultIndex = 0; resultIndex < sendResults.size(); resultIndex++) {
                Integer responseIndex = responseIndexChunk[resultIndex];
                Messaging.SendEmailResult sendResult = sendResults[resultIndex];
                if (sendResult.isSuccess()) {
                    responses[responseIndex].success = true;
                    continue;
                }

                String errorMessage = 'Unable to send Mod Request Form email.';
                if (sendResult.getErrors() != null && !sendResult.getErrors().isEmpty()) {
                    errorMessage = sendResult.getErrors()[0].getMessage();
                }
                responses[responseIndex].success = false;
                responses[responseIndex].errorMessage = errorMessage;
                logModRequestFormEmailError(
                    workOrderIdChunk[resultIndex],
                    new WorkOrdersServiceException(errorMessage)
                );
            }
        } catch (Exception caught) {
            for (Integer resultIndex = 0; resultIndex < responseIndexChunk.size(); resultIndex++) {
                Integer responseIndex = responseIndexChunk[resultIndex];
                responses[responseIndex].success = false;
                responses[responseIndex].errorMessage = caught.getMessage();
                logModRequestFormEmailError(workOrderIdChunk[resultIndex], caught);
            }
        }
    }

    private static void logModRequestFormEmailError(Id workOrderId, Exception caught) {
        Logger.error(
            new LogMessage(
                'WorkOrdersService.processModRequestFormEmails failed for {0}: {1}',
                workOrderId,
                caught == null ? null : caught.getMessage()
            ),
            caught
        );
    }

    /**
     * @description GW-3600 - Loads a Work Order header for Repair Center document generation.
     * @param workOrderId Work Order Id (parent or child).
     * @return Work Order header, or null when the Id is null or no row matches.
     */
    public static WorkOrder selectForRepairCenterDocumentGeneration(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }
        return (WorkOrder) new WorkOrdersSelector()
            .selectFields(
                new List<String>{
                    'Id',
                    'WorkOrderNumber',
                    'CurrencyIsoCode',
                    'Status',
                    'ActualShipDate__c',
                    'CustomerPO__c',
                    'CustomerReference__c',
                    'AccountManager__c',
                    'DepartmentName__c',
                    'ReturnOrderNumber__c',
                    'EvaluationNotes__c',
                    'OperatingUnit__c',
                    'ParentWorkOrderId',
                    'BillToAddress__Street__s',
                    'BillToAddress__City__s',
                    'BillToAddress__StateCode__s',
                    'BillToAddress__PostalCode__s',
                    'BillToAddress__CountryCode__s',
                    'Street',
                    'City',
                    'State',
                    'StateCode',
                    'PostalCode',
                    'Country',
                    'CountryCode',
                    'Account.Name',
                    'Account.AccountNumber',
                    'Contact.Name',
                    'RecordType.DeveloperName'
                }
            )
            .whereEquals('Id', workOrderId)
            .first();
    }

    /**
     * @description GW-3600 - Resolves the top-level Work Order Id for an Order Acknowledgement family.
     * @param workOrderRecord Work Order that triggered document generation.
     * @return Parent Work Order Id when present; otherwise the Work Order Id.
     */
    public static Id resolveDocumentFamilyRootId(WorkOrder workOrderRecord) {
        if (workOrderRecord == null) {
            return null;
        }
        return workOrderRecord.ParentWorkOrderId != null
            ? workOrderRecord.ParentWorkOrderId
            : workOrderRecord.Id;
    }

    /**
     * @description GW-4329 - Loads Work Orders passed into SubFlow_GenerateRepairCenterWOQuote.
     * @param workOrderIds Triggering Work Order Ids.
     * @return Work Orders with the fields the SubFlow reads, or an empty list when no Ids are provided.
     */
    public static List<WorkOrder> selectForRepairCenterQuoteSubFlow(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        SoqlQueryBuilder query = new WorkOrdersSelector()
            .selectFields(
                new List<String>{
                    'Id',
                    'IsParent__c',
                    'ParentWorkOrderId',
                    'WorkOrderNumber',
                    'Product__c',
                    'RecordType.DeveloperName',
                    'ParentWorkOrder.RecordType.DeveloperName'
                }
            );
        List<String> idFilterNumbers = new List<String>();
        Integer filterNumber = 1;
        for (Id workOrderId : workOrderIds) {
            if (workOrderId == null) {
                continue;
            }
            query.whereEquals('Id', workOrderId);
            idFilterNumbers.add(String.valueOf(filterNumber));
            filterNumber++;
        }
        if (idFilterNumbers.isEmpty()) {
            return new List<WorkOrder>();
        }
        if (idFilterNumbers.size() > 1) {
            query.withFilterLogic(String.join(idFilterNumbers, ' OR '));
        }
        return (List<WorkOrder>) query.execute();
    }

    /**
     * @description Thrown when a Work Order service operation fails.
     */
    /**
     * @description GW-5497 - Validates and starts a Quality Inspection session.
     * @param workOrderInput Work Order Id or Work Order Number
     * @return Quality Inspection workspace
     */
    public static QualityInspectionWorkspace initializeQualityInspection(String workOrderInput) {
        try {
            WorkOrder workOrder = WorkOrdersSelector.selectForQualityInspection(workOrderInput);
            if (workOrder == null) {
                throw new WorkOrdersServiceException('Work Order was not found.');
            }
            validateQualityInspectionEligibility(workOrder);

            WorkOrder updateRecord = new WorkOrder(
                Id = workOrder.Id,
                OwnerId = UserInfo.getUserId(),
                QCInspector__c = UserInfo.getUserId()
            );
            if (workOrder.Status == 'Repair') {
                updateRecord.Status = 'QC';
                updateRecord.SubStatus__c = 'Inspection';
            }
            Database.update(updateRecord, AccessLevel.USER_MODE);
            WOAssignmentHistoriesService.startQualityInspectionAssignment(workOrder.Id);
            return buildQualityInspectionWorkspace(
                WorkOrdersSelector.selectForQualityInspection(String.valueOf(workOrder.Id))
            );
        } catch (WorkOrdersServiceException exceptionValue) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            Logger.error('WorkOrdersService.initializeQualityInspection failed.', exceptionValue);
            throw new WorkOrdersServiceException(
                'Unable to start Quality Inspection: ' + exceptionValue.getMessage(),
                exceptionValue
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5497 - Returns active picklist values used by Quality Inspection.
     * @return Options keyed by UI field name
     */
    public static Map<String, List<QualityInspectionOption>> getQualityInspectionOptions() {
        return new Map<String, List<QualityInspectionOption>>{
            'subStatus' => getQualityInspectionQcSubStatusOptions(),
            'ncrType' => toQualityInspectionOptions(
                NonconformanceReport__c.NCRType__c.getDescribe()
            ),
            'ncrSource' => toQualityInspectionOptions(
                NonconformanceReportLineItem__c.NCRSource__c.getDescribe()
            ),
            'repairRelated' => toQualityInspectionOptions(
                NonconformanceReportLineItem__c.RepairRelated__c.getDescribe()
            ),
            'productLine' => toQualityInspectionOptions(
                NonconformanceReportLineItem__c.ProductLine__c.getDescribe()
            ),
            'ncrStatus' => toQualityInspectionOptions(
                NonconformanceReportLineItem__c.NCRStatus__c.getDescribe()
            ),
            'ncrHeaderStatus' => toQualityInspectionOptions(
                NonconformanceReport__c.NCRStatus__c.getDescribe()
            ),
            'severityRating' => toQualityInspectionOptions(
                NonconformanceReportLineItem__c.SeverityRating__c.getDescribe()
            ),
            'severityJustification' => toQualityInspectionOptions(
                NonconformanceReportLineItem__c.SeverityJustification__c.getDescribe()
            ),
            'occurrenceRating' => toQualityInspectionOptions(
                NonconformanceReportLineItem__c.OccurrenceRating__c.getDescribe()
            ),
            'ncrOwner' => toQualityInspectionOptions(
                NonconformanceReportLineItem__c.NCROwner__c.getDescribe()
            )
        };
    }

    /**
     * @description GW-5497 - Returns NCR Reasons valid for the selected Product Line.
     * @param productLine Controlling Product Line API value
     * @return Valid dependent NCR Reason options
     */
    public static List<QualityInspectionOption> getQualityInspectionNcrReasonOptions(
        String productLine
    ) {
        return getQualityInspectionDependentOptions(
            NonconformanceReportLineItem__c.ProductLine__c.getDescribe(),
            NonconformanceReportLineItem__c.NCRReason__c.getDescribe(),
            productLine
        );
    }

    /**
     * @description GW-5497 - Returns NCR Location Context values valid for the NCR Reason.
     * @param ncrReason Controlling NCR Reason API value
     * @return Valid dependent NCR Location Context options
     */
    public static List<QualityInspectionOption> getQualityInspectionNcrLocationOptions(
        String ncrReason
    ) {
        return getQualityInspectionDependentOptions(
            NonconformanceReportLineItem__c.NCRReason__c.getDescribe(),
            NonconformanceReportLineItem__c.NCRLocationContext__c.getDescribe(),
            ncrReason
        );
    }

    private static List<QualityInspectionOption> getQualityInspectionQcSubStatusOptions() {
        return getQualityInspectionDependentOptions(
            WorkOrder.Status.getDescribe(),
            WorkOrder.SubStatus__c.getDescribe(),
            WO_STATUS_QC
        );
    }

    private static List<QualityInspectionOption> toQualityInspectionOptions(
        Schema.DescribeFieldResult fieldDescribe
    ) {
        List<QualityInspectionOption> options = new List<QualityInspectionOption>();
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new QualityInspectionOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    private static List<QualityInspectionOption> getQualityInspectionDependentOptions(
        Schema.DescribeFieldResult controllingField,
        Schema.DescribeFieldResult dependentField,
        String controllingValue
    ) {
        List<Schema.PicklistEntry> controllingEntries = controllingField.getPicklistValues();
        Integer controllingIndex = -1;
        for (Integer index = 0; index < controllingEntries.size(); index++) {
            if (controllingEntries[index].getValue() == controllingValue) {
                controllingIndex = index;
                break;
            }
        }
        if (controllingIndex < 0) {
            return new List<QualityInspectionOption>();
        }

        List<QualityInspectionOption> options = new List<QualityInspectionOption>();
        for (Schema.PicklistEntry entry : dependentField.getPicklistValues()) {
            if (
                entry.isActive() &&
                isQualityInspectionPicklistEntryValidFor(entry, controllingIndex)
            ) {
                options.add(new QualityInspectionOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    private static Boolean isQualityInspectionPicklistEntryValidFor(
        Schema.PicklistEntry entry,
        Integer controllingIndex
    ) {
        Map<String, Object> serializedEntry =
            (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(entry));
        String validFor = (String) serializedEntry.get('validFor');
        if (String.isBlank(validFor)) {
            return true;
        }
        String base64Characters =
            'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
        Integer characterIndex = controllingIndex / 6;
        if (characterIndex >= validFor.length()) {
            return false;
        }
        Integer bitShift = 5 - Math.mod(controllingIndex, 6);
        Integer bitValue = base64Characters.indexOf(
            validFor.substring(characterIndex, characterIndex + 1)
        );
        return bitValue >= 0 && (bitValue & (1 << bitShift)) != 0;
    }

    /**
     * @description GW-5497 - Saves editable Quality Inspection Work Order fields.
     * @param workOrderId Work Order Id
     * @param subStatus Required Sub Status
     * @param pressureGaugeSerialNumber Pressure Gauge Serial Number
     * @param inspectionNotes QC Inspection Notes
     * @return Updated workspace
     */
    public static QualityInspectionWorkspace saveQualityInspection(
        Id workOrderId,
        String subStatus,
        String pressureGaugeSerialNumber,
        String inspectionNotes
    ) {
        return saveQualityInspection(
            workOrderId,
            subStatus,
            pressureGaugeSerialNumber,
            inspectionNotes,
            null
        );
    }

    /**
     * @description GW-5497 - Saves QC fields and, when an NCR exists, its header values.
     * @param workOrderId Work Order Id
     * @param subStatus Required Sub Status
     * @param pressureGaugeSerialNumber Pressure Gauge Serial Number
     * @param inspectionNotes QC Inspection Notes
     * @param ncrInput NCR Type, Source, Status, and Department. Ignored when no NCR exists.
     * @return Updated workspace
     */
    public static QualityInspectionWorkspace saveQualityInspection(
        Id workOrderId,
        String subStatus,
        String pressureGaugeSerialNumber,
        String inspectionNotes,
        QualityInspectionNcrInput ncrInput
    ) {
        if (workOrderId == null || String.isBlank(subStatus)) {
            throw new WorkOrdersServiceException('Work Order and Sub Status are required.');
        }
        if (
            !hasQualityInspectionOptionValue(
                getQualityInspectionQcSubStatusOptions(),
                subStatus
            )
        ) {
            throw new WorkOrdersServiceException('Select a Sub Status valid for QC.');
        }
        try {
            if (subStatus == 'QC Pass' && hasOpenQualityInspectionNcrLines(workOrderId)) {
                throw new WorkOrdersServiceException(
                    'QC cannot be passed until all NCR Line Items are Closed.'
                );
            }
            if (subStatus == 'QC Fail') {
                assertQualityInspectionNcrExistsForQcFail(workOrderId);
            }
            WorkOrder updateRecord = new WorkOrder(
                Id = workOrderId,
                SubStatus__c = subStatus,
                PressureGaugeSerialNumber__c = pressureGaugeSerialNumber,
                QCInspectionNotes__c = inspectionNotes
            );
            Database.update(updateRecord, AccessLevel.USER_MODE);
            updateQualityInspectionNcrHeader(workOrderId, ncrInput);
            return buildQualityInspectionWorkspace(
                WorkOrdersSelector.selectForQualityInspection(String.valueOf(workOrderId))
            );
        } catch (WorkOrdersServiceException exceptionValue) {
            throw exceptionValue;
        } catch (DmlException exceptionValue) {
            Logger.error('WorkOrdersService.saveQualityInspection failed.', exceptionValue);
            throw new WorkOrdersServiceException(
                'Unable to save Quality Inspection: ' + exceptionValue.getDmlMessage(0),
                exceptionValue
            );
        } catch (Exception exceptionValue) {
            Logger.error('WorkOrdersService.saveQualityInspection failed.', exceptionValue);
            throw new WorkOrdersServiceException(
                'Unable to save Quality Inspection: ' + exceptionValue.getMessage(),
                exceptionValue
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5497 - Creates an NCR/header line, creates another line, or edits a line.
     * @param workOrderId Work Order Id
     * @param reportInput NCR header values used when no header exists
     * @param lineInput NCR line values
     * @return Updated workspace
     */
    public static QualityInspectionWorkspace saveQualityInspectionNcr(
        Id workOrderId,
        QualityInspectionNcrInput reportInput,
        QualityInspectionNcrLineInput lineInput
    ) {
        return saveQualityInspectionNcr(workOrderId, reportInput, lineInput, null);
    }

    /**
     * @description GW-5497 - Saves an NCR line and keeps inspection edits made before that save.
     * @param workOrderId Work Order Id
     * @param reportInput NCR header values used when no header exists
     * @param lineInput NCR line values
     * @param inspectionDraft Sub Status, Pressure Gauge Serial Number, and QC Inspection Notes.
     *        Null leaves those Work Order fields unchanged.
     * @return Updated workspace
     */
    public static QualityInspectionWorkspace saveQualityInspectionNcr(
        Id workOrderId,
        QualityInspectionNcrInput reportInput,
        QualityInspectionNcrLineInput lineInput,
        QualityInspectionDraft inspectionDraft
    ) {
        if (workOrderId == null || lineInput == null) {
            throw new WorkOrdersServiceException('Work Order and NCR Line are required.');
        }
        validateQualityInspectionNcrLine(lineInput);
        try {
            WorkOrder workOrder =
                WorkOrdersSelector.selectForQualityInspection(String.valueOf(workOrderId));
            if (workOrder == null) {
                throw new WorkOrdersServiceException('Work Order was not found.');
            }
            List<NonconformanceReport__c> reports =
                NonconformanceReportsService.getByWorkOrderId(workOrderId);
            Boolean isExistingLine = lineInput.lineId != null;
            Id requestedReportId =
                reportInput == null ? null : toQualityInspectionId(reportInput.reportId);
            NonconformanceReport__c report;
            Boolean isNewReport = false;
            if (isExistingLine) {
                report = findQualityInspectionNcr(reports, requestedReportId);
            } else if (requestedReportId != null) {
                report = findQualityInspectionNcr(reports, requestedReportId);
            } else if (workOrder.AssetId != null && !reports.isEmpty()) {
                report = reports[0];
            } else {
                validateCanCreateQualityInspectionNcr(workOrder, reports);
                validateQualityInspectionNcrHeader(reportInput);
                report = createQualityInspectionNcr(workOrder, reportInput);
                isNewReport = true;
            }
            NonconformanceReportLineItem__c lineRecord = buildQualityInspectionNcrLine(
                isExistingLine ? null : report.Id,
                lineInput
            );
            if (isExistingLine) {
                lineRecord.Id = toQualityInspectionId(lineInput.lineId);
                NonconformanceReportLineItemsService.updateLine(lineRecord);
            } else {
                NonconformanceReportLineItemsService.createLine(lineRecord);
            }
            synchronizeQualityInspectionNcrStatus(report.Id);
            if (!isNewReport) {
                retainQualityInspectionNcrTypeAndSource(report.Id, reportInput);
            }
            persistQualityInspectionDraft(
                workOrderId,
                workOrder.SubStatus__c,
                inspectionDraft
            );
            return buildQualityInspectionWorkspace(
                WorkOrdersSelector.selectForQualityInspection(String.valueOf(workOrderId))
            );
        } catch (WorkOrdersServiceException exceptionValue) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            Logger.error('WorkOrdersService.saveQualityInspectionNcr failed.', exceptionValue);
            throw new WorkOrdersServiceException(
                'Unable to save NCR information: ' + exceptionValue.getMessage(),
                exceptionValue
            );
        } finally {
            Logger.saveLog();
        }
    }

    private static void validateQualityInspectionEligibility(WorkOrder workOrder) {
        // Eligible when Status is QC, or Status is Repair and Sub Status is Ready for QC.
        Boolean isQc = workOrder.Status == WO_STATUS_QC;
        Boolean isRepairReadyForQc =
            workOrder.Status == WO_STATUS_REPAIR &&
            workOrder.SubStatus__c == WO_SUB_STATUS_READY_FOR_QC;
        if (!isQc && !isRepairReadyForQc) {
            throw new WorkOrdersServiceException(
                'This Work Order Status is not eligible for QC Inspection'
            );
        }
    }

    private static QualityInspectionWorkspace buildQualityInspectionWorkspace(
        WorkOrder workOrder
    ) {
        QualityInspectionWorkspace workspace = new QualityInspectionWorkspace();
        workspace.workOrderId = workOrder.Id;
        workspace.workOrderNumber = workOrder.WorkOrderNumber;
        workspace.recordTypeId = workOrder.RecordTypeId;
        workspace.status = workOrder.Status;
        workspace.subStatus = workOrder.SubStatus__c;
        workspace.returnOrderNumber =
            workOrder.ReturnOrder__r == null ? null : workOrder.ReturnOrder__r.ReturnOrderNumber;
        workspace.reportedProblem = workOrder.Description;
        workspace.pressureGaugeSerialNumber = workOrder.PressureGaugeSerialNumber__c;
        workspace.inspectionNotes = workOrder.QCInspectionNotes__c;
        workspace.showPressureGauge =
            workOrder.ProductLine__c == 'FLEXIBLE SCOPE' ||
            workOrder.ProductLine__c == 'ENDOCAM';
        workspace.productLine = workOrder.ProductLine__c;
        workspace.continuousImprovementOpportunity =
            workOrder.ContinuousImprovementOpportunity__c == true;
        workspace.shipComplete = workOrder.ShipComplete__c == true;
        workspace.accountName = workOrder.Account == null ? null : workOrder.Account.Name;
        workspace.repairCenterName =
            workOrder.RepairCenter__r == null ? null : workOrder.RepairCenter__r.Name;
        workspace.serviceTeamId = workOrder.ServiceTeam__c;
        workspace.departmentName =
            workOrder.ServiceTeam__r == null ? null : workOrder.ServiceTeam__r.Name;
        if (String.isBlank(workspace.departmentName) && workOrder.Department__r != null) {
            workspace.departmentName = workOrder.Department__r.Name;
        }
        workspace.departmentOptions = mapQualityInspectionDepartmentOptions(workOrder);
        mapQualityInspectionAsset(workspace, workOrder);

        List<NonconformanceReport__c> reports =
            NonconformanceReportsService.getByWorkOrderId(workOrder.Id);
        workspace.hasNcr = !reports.isEmpty();
        workspace.showAssetInformation = workOrder.AssetId != null;
        workspace.showInstrumentInformation = workOrder.AssetId == null;
        workspace.instrumentLines = workOrder.AssetId == null
            ? mapQualityInspectionInstrumentLines(workOrder.Id)
            : new List<QualityInspectionInstrumentLine>();
        workspace.ncrs = new List<QualityInspectionNcr>();
        workspace.ncrLines = new List<QualityInspectionNcrLine>();
        for (NonconformanceReport__c report : reports) {
            workspace.ncrs.add(mapQualityInspectionNcr(report, workOrder));
        }
        if (!reports.isEmpty()) {
            workspace.ncr = workspace.ncrs[0];
            Set<Id> reportIds = new Map<Id, NonconformanceReport__c>(reports).keySet();
            for (
                NonconformanceReportLineItem__c line :
                NonconformanceReportLineItemsService.getByReportIds(reportIds)
            ) {
                workspace.ncrLines.add(mapQualityInspectionNcrLine(line));
            }
        } else if (workOrder.AssetId != null) {
            List<WorkOrderLineItem> candidates =
                WorkOrderLineItemsService.getQualityInspectionProductServiced(
                    workOrder.Id,
                    workOrder.AssetId
                );
            if (candidates.size() == 1) {
                workspace.defaultWorkOrderLineItemId = candidates[0].Id;
                workspace.defaultWorkOrderLineItemProductName =
                    candidates[0].Product2 == null ? null : candidates[0].Product2.Name;
            }
        }
        assignQualityInspectionDefaultInstrumentLine(workspace, reports);
        workspace.canCreateNcr = canCreateQualityInspectionNcr(
            workOrder,
            reports,
            workspace.instrumentLines.size()
        );
        return workspace;
    }

    private static void mapQualityInspectionAsset(
        QualityInspectionWorkspace workspace,
        WorkOrder workOrder
    ) {
        if (workOrder.Asset == null) {
            return;
        }
        workspace.assetId = workOrder.AssetId;
        workspace.assetName = workOrder.Asset.Name;
        workspace.serialNumber = workOrder.Asset.SerialNumber;
        if (workOrder.Asset.Product2 != null) {
            workspace.productId = workOrder.Asset.Product2Id;
            workspace.productName = workOrder.Asset.Product2.Name;
            workspace.model = workOrder.Asset.Product2.Model__c;
            workspace.manufacturer = workOrder.Asset.Product2.Manufacturer__c;
        }
    }

    private static NonconformanceReport__c createQualityInspectionNcr(
        WorkOrder workOrder,
        QualityInspectionNcrInput input
    ) {
        if (input == null) {
            input = new QualityInspectionNcrInput();
        }
        NonconformanceReport__c report = new NonconformanceReport__c(
            WorkOrder__c = workOrder.Id,
            WorkOrderLineItem__c = toQualityInspectionId(input.workOrderLineItemId),
            Account__c = workOrder.AccountId,
            RepairCenter__c = workOrder.RepairCenter__c,
            Department__c = resolveQualityInspectionDepartment(workOrder, input),
            NCRType__c = qualityInspectionNcrType(input),
            NCRStatus__c = String.isBlank(input.ncrStatus) ? 'Open' : input.ncrStatus,
            Asset__c = workOrder.AssetId,
            ProductLine__c = workOrder.ProductLine__c
        );
        if (workOrder.Asset != null) {
            report.SerialNumber__c = workOrder.Asset.SerialNumber;
            if (workOrder.Asset.Product2 != null) {
                report.Product__c = workOrder.Asset.Product2Id;
                report.Model__c = workOrder.Asset.Product2.Model__c;
                report.Manufacturer__c = workOrder.Asset.Product2.Manufacturer__c;
            }
        } else {
            applyQualityInspectionNcrFromWorkOrderLine(report, input);
        }
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.NonconformanceReport__c
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter');
        if (recordTypeInfo != null) {
            report.RecordTypeId = recordTypeInfo.getRecordTypeId();
        }
        return NonconformanceReportsService.createReport(report);
    }

    private static NonconformanceReportLineItem__c buildQualityInspectionNcrLine(
        Id reportId,
        QualityInspectionNcrLineInput input
    ) {
        String riskRating = calculateQualityInspectionRiskRating(
            input.severityRating,
            input.occurrenceRating
        );
        NonconformanceReportLineItem__c line = new NonconformanceReportLineItem__c(
            RepairRelated__c = input.repairRelated,
            NCRDate__c = input.ncrDate,
            InitiatedBy__c = toQualityInspectionId(input.initiatedById),
            QualityInspector__c = toQualityInspectionId(input.qualityInspectorId),
            ProductLine__c = input.productLine,
            NCRReason__c = input.ncrReason,
            NCRLocationContext__c = input.ncrLocationContext,
            Comments__c = input.comments,
            NCRStatus__c = input.ncrStatus,
            NCRSource__c = input.ncrSource,
            SeverityRating__c = input.severityRating,
            SeverityJustification__c = input.severityJustification,
            OccurrenceRating__c = input.occurrenceRating,
            RiskRating__c = riskRating,
            QuantityRejected__c = input.quantityRejected,
            CAPANumber__c = input.capaNumber,
            NCROwner__c = 'Internal',
            NCRDescription__c = input.ncrDescription,
            RiskJustification__c = calculateQualityInspectionRiskJustification(input)
        );
        if (reportId != null) {
            line.NonconformanceReport__c = reportId;
        }
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.NonconformanceReportLineItem__c
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter');
        if (recordTypeInfo != null && reportId != null) {
            line.RecordTypeId = recordTypeInfo.getRecordTypeId();
        }
        return line;
    }

    private static Id toQualityInspectionId(String value) {
        return String.isBlank(value) ? null : Id.valueOf(value);
    }

    private static void assertQualityInspectionNcrExistsForQcFail(Id workOrderId) {
        if (NonconformanceReportsService.getByWorkOrderId(workOrderId).isEmpty()) {
            throw new WorkOrdersServiceException(QC_FAIL_NCR_REQUIRED_MESSAGE);
        }
    }

    private static Boolean canCreateQualityInspectionNcr(
        WorkOrder workOrder,
        List<NonconformanceReport__c> reports,
        Integer productServicedCount
    ) {
        Integer ncrCount = reports == null ? 0 : reports.size();
        if (workOrder.AssetId != null) {
            return ncrCount == 0;
        }
        return ncrCount < productServicedCount;
    }

    private static void validateCanCreateQualityInspectionNcr(
        WorkOrder workOrder,
        List<NonconformanceReport__c> reports
    ) {
        Integer productServicedCount = workOrder.AssetId == null
            ? WorkOrderLineItemsSelector.selectProductServicedNonAccessoryByWorkOrderId(
                    workOrder.Id
                )
                .size()
            : 0;
        if (!canCreateQualityInspectionNcr(workOrder, reports, productServicedCount)) {
            throw new WorkOrdersServiceException(
                'Cannot create another Nonconformance Report for this Work Order.'
            );
        }
    }

    private static NonconformanceReport__c findQualityInspectionNcr(
        List<NonconformanceReport__c> reports,
        Id reportId
    ) {
        if (reports == null || reports.isEmpty()) {
            throw new WorkOrdersServiceException('Nonconformance Report was not found.');
        }
        if (reportId == null) {
            return reports[0];
        }
        for (NonconformanceReport__c report : reports) {
            if (report.Id == reportId) {
                return report;
            }
        }
        throw new WorkOrdersServiceException('Nonconformance Report was not found.');
    }

    private static void applyQualityInspectionNcrFromWorkOrderLine(
        NonconformanceReport__c report,
        QualityInspectionNcrInput input
    ) {
        Id workOrderLineItemId = toQualityInspectionId(
            input == null ? null : input.workOrderLineItemId
        );
        if (workOrderLineItemId == null) {
            throw new WorkOrdersServiceException(
                'Work Order Line Item is required to create an NCR.'
            );
        }
        WorkOrderLineItem source;
        for (
            WorkOrderLineItem line :
            WorkOrderLineItemsSelector.selectProductServicedNonAccessoryByWorkOrderId(
                report.WorkOrder__c
            )
        ) {
            if (line.Id == workOrderLineItemId) {
                source = line;
                break;
            }
        }
        if (source == null) {
            throw new WorkOrdersServiceException(
                'Select a Product Serviced Work Order Line Item.'
            );
        }
        for (
            NonconformanceReport__c existing :
            NonconformanceReportsService.getByWorkOrderId(report.WorkOrder__c)
        ) {
            if (existing.WorkOrderLineItem__c == workOrderLineItemId) {
                throw new WorkOrdersServiceException(
                    'An NCR already exists for this Work Order Line Item.'
                );
            }
        }
        report.WorkOrderLineItem__c = source.Id;
        report.SerialNumber__c = source.SerialNumber__c;
        report.Product__c = source.Product2Id;
        report.Model__c = firstNonBlank(
            source.Model__c,
            source.Product2 == null ? null : source.Product2.Model__c
        );
        report.Manufacturer__c = source.Product2 == null
            ? null
            : source.Product2.Manufacturer__c;
        String productLine = firstNonBlank(
            source.ProductLine__c,
            source.Product2 == null ? null : source.Product2.ProductLine__c
        );
        if (String.isNotBlank(productLine)) {
            report.ProductLine__c = productLine;
        }
    }

    private static List<QualityInspectionInstrumentLine> mapQualityInspectionInstrumentLines(
        Id workOrderId
    ) {
        List<QualityInspectionInstrumentLine> rows = new List<QualityInspectionInstrumentLine>();
        List<WorkOrderLineItem> lines =
            WorkOrderLineItemsSelector.selectProductServicedNonAccessoryByWorkOrderId(
                workOrderId
            );
        if (lines.isEmpty()) {
            return rows;
        }
        Map<Id, List<QualityInspectionOption>> repairSummaryByParentId =
            new Map<Id, List<QualityInspectionOption>>();
        Set<Id> parentIds = new Map<Id, WorkOrderLineItem>(lines).keySet();
        for (
            WorkOrderLineItem child :
            WorkOrderLineItemsSelector.selectRepairCodeChildrenByParentIds(parentIds)
        ) {
            if (!repairSummaryByParentId.containsKey(child.ParentWorkOrderLineItemId)) {
                repairSummaryByParentId.put(
                    child.ParentWorkOrderLineItemId,
                    new List<QualityInspectionOption>()
                );
            }
            repairSummaryByParentId.get(child.ParentWorkOrderLineItemId)
                .add(
                    new QualityInspectionOption(
                        qualityInspectionRepairCodeLabel(child),
                        String.valueOf(child.Id)
                    )
                );
        }
        for (WorkOrderLineItem line : lines) {
            QualityInspectionInstrumentLine row = new QualityInspectionInstrumentLine();
            row.lineId = line.Id;
            row.lineNumber = line.LineItemNumber;
            row.quantity = line.Quantity;
            row.productName = line.Product2 == null ? null : line.Product2.Name;
            row.model = firstNonBlank(
                line.Model__c,
                line.Product2 == null ? null : line.Product2.Model__c
            );
            row.manufacturer = line.Product2 == null
                ? null
                : line.Product2.Manufacturer__c;
            row.productLine = firstNonBlank(
                line.ProductLine__c,
                line.Product2 == null ? null : line.Product2.ProductLine__c
            );
            row.serialNumber = line.SerialNumber__c;
            row.repairSummary = repairSummaryByParentId.containsKey(line.Id)
                ? repairSummaryByParentId.get(line.Id)
                : new List<QualityInspectionOption>();
            rows.add(row);
        }
        return rows;
    }

    private static String qualityInspectionRepairCodeLabel(WorkOrderLineItem child) {
        String productCode = firstNonBlank(
            child.ProductCodeWoli__c,
            child.Product2 == null ? null : child.Product2.ProductCode
        );
        String productName = child.Product2 == null ? null : child.Product2.Name;
        if (String.isBlank(productName)) {
            return productCode;
        }
        if (String.isBlank(productCode) || productName.contains(productCode)) {
            return productName;
        }
        return productCode + ' ' + productName;
    }

    private static void assignQualityInspectionDefaultInstrumentLine(
        QualityInspectionWorkspace workspace,
        List<NonconformanceReport__c> reports
    ) {
        if (workspace == null || workspace.instrumentLines == null) {
            return;
        }
        Set<Id> usedLineIds = new Set<Id>();
        if (reports != null) {
            for (NonconformanceReport__c report : reports) {
                if (report.WorkOrderLineItem__c != null) {
                    usedLineIds.add(report.WorkOrderLineItem__c);
                }
            }
        }
        for (QualityInspectionInstrumentLine line : workspace.instrumentLines) {
            if (!usedLineIds.contains(line.lineId)) {
                workspace.defaultWorkOrderLineItemId = line.lineId;
                workspace.defaultWorkOrderLineItemProductName = line.productName;
                return;
            }
        }
    }

    private static String firstNonBlank(String firstValue, String secondValue) {
        if (String.isNotBlank(firstValue)) {
            return firstValue;
        }
        return String.isBlank(secondValue) ? null : secondValue;
    }

    private static String firstNonBlank(
        String firstValue,
        String secondValue,
        String thirdValue
    ) {
        String resolved = firstNonBlank(firstValue, secondValue);
        return resolved != null ? resolved : firstNonBlank(thirdValue, null);
    }

    /**
     * @description GW-4621 - Resolves the NCR Department from the selected Service Team.
     *              A blank selection clears it. An omitted selection defaults to the Work Order team.
     */
    private static Id resolveQualityInspectionDepartment(
        WorkOrder workOrder,
        QualityInspectionNcrInput input
    ) {
        Id departmentId = workOrder.ServiceTeam__c;
        if (input != null && input.departmentId != null) {
            departmentId = toQualityInspectionId(input.departmentId);
        }
        if (departmentId == null) {
            return null;
        }
        if (departmentId.getSObjectType() != ServiceTeam__c.SObjectType) {
            throw new WorkOrdersServiceException('Department must be a Service Team.');
        }

        Set<Id> allowedTeamIds = new Set<Id>(
            new Map<Id, ServiceTeam__c>(
                ServiceTeamsService.getActiveServiceTeamsByLocationId(workOrder.RepairCenter__c)
            ).keySet()
        );
        if (workOrder.ServiceTeam__c != null) {
            allowedTeamIds.add(workOrder.ServiceTeam__c);
        }
        if (!allowedTeamIds.contains(departmentId)) {
            throw new WorkOrdersServiceException(
                'Select a Service Team for this Repair Center.'
            );
        }
        return departmentId;
    }

    private static List<QualityInspectionOption> mapQualityInspectionDepartmentOptions(
        WorkOrder workOrder
    ) {
        List<QualityInspectionOption> options = new List<QualityInspectionOption>();
        Set<Id> includedTeamIds = new Set<Id>();
        for (
            ServiceTeam__c serviceTeam : ServiceTeamsService.getActiveServiceTeamsByLocationId(
                workOrder.RepairCenter__c
            )
        ) {
            options.add(new QualityInspectionOption(serviceTeam.Name, serviceTeam.Id));
            includedTeamIds.add(serviceTeam.Id);
        }
        if (
            workOrder.ServiceTeam__c != null &&
            !includedTeamIds.contains(workOrder.ServiceTeam__c) &&
            workOrder.ServiceTeam__r != null
        ) {
            options.add(
                new QualityInspectionOption(
                    workOrder.ServiceTeam__r.Name,
                    workOrder.ServiceTeam__c
                )
            );
        }
        return options;
    }

    private static String qualityInspectionNcrType(QualityInspectionNcrInput input) {
        if (input == null || String.isBlank(input.ncrType)) {
            return 'Customer Equipment';
        }
        return input.ncrType;
    }

    private static void validateQualityInspectionNcrHeader(QualityInspectionNcrInput input) {
        if (input == null) {
            return;
        }
        if (
            String.isNotBlank(input.ncrType) &&
            !hasQualityInspectionOptionValue(
                toQualityInspectionOptions(NonconformanceReport__c.NCRType__c.getDescribe()),
                input.ncrType
            )
        ) {
            throw new WorkOrdersServiceException('Select a valid NCR Type.');
        }
        if (
            String.isNotBlank(input.ncrStatus) &&
            !hasQualityInspectionOptionValue(
                toQualityInspectionOptions(NonconformanceReport__c.NCRStatus__c.getDescribe()),
                input.ncrStatus
            )
        ) {
            throw new WorkOrdersServiceException('Select an NCR Status of Open or Closed.');
        }
    }

    private static void validateQualityInspectionNcrLine(QualityInspectionNcrLineInput input) {
        if (
            String.isBlank(input.repairRelated) ||
            input.ncrDate == null ||
            input.initiatedById == null ||
            input.qualityInspectorId == null ||
            String.isBlank(input.productLine) ||
            String.isBlank(input.ncrReason) ||
            String.isBlank(input.ncrStatus) ||
            String.isBlank(input.ncrSource)
        ) {
            throw new WorkOrdersServiceException(
                'Repair Related, NCR Date, Initiated By, Quality Inspector, Product Line, ' +
                    'NCR Reason, NCR Status, and NCR Source are required.'
            );
        }
        if (
            !hasQualityInspectionOptionValue(
                toQualityInspectionOptions(
                    NonconformanceReportLineItem__c.NCRSource__c.getDescribe()
                ),
                input.ncrSource
            )
        ) {
            throw new WorkOrdersServiceException('Select a valid NCR Source.');
        }
        if (
            !hasQualityInspectionOptionValue(
                getQualityInspectionNcrReasonOptions(input.productLine),
                input.ncrReason
            )
        ) {
            throw new WorkOrdersServiceException(
                'Select an NCR Reason valid for the selected Product Line.'
            );
        }
        if (
            String.isNotBlank(input.ncrLocationContext) &&
            !hasQualityInspectionOptionValue(
                getQualityInspectionNcrLocationOptions(input.ncrReason),
                input.ncrLocationContext
            )
        ) {
            throw new WorkOrdersServiceException(
                'Select an NCR Location Context valid for the selected NCR Reason.'
            );
        }
    }

    private static Boolean hasQualityInspectionOptionValue(
        List<QualityInspectionOption> options,
        String value
    ) {
        for (QualityInspectionOption option : options) {
            if (option.value == value) {
                return true;
            }
        }
        return false;
    }

    private static Boolean hasOpenQualityInspectionNcrLines(Id workOrderId) {
        List<NonconformanceReport__c> reports =
            NonconformanceReportsService.getByWorkOrderId(workOrderId);
        if (reports.isEmpty()) {
            return false;
        }
        Set<Id> reportIds = new Map<Id, NonconformanceReport__c>(reports).keySet();
        for (
            NonconformanceReportLineItem__c line :
            NonconformanceReportLineItemsService.getByReportIds(reportIds)
        ) {
            if (line.NCRStatus__c != 'Closed') {
                return true;
            }
        }
        return false;
    }

    private static void synchronizeQualityInspectionNcrStatus(Id reportId) {
        List<NonconformanceReportLineItem__c> lines =
            NonconformanceReportLineItemsService.getByReportIds(new Set<Id>{ reportId });
        Boolean allClosed = !lines.isEmpty();
        for (NonconformanceReportLineItem__c line : lines) {
            if (line.NCRStatus__c != 'Closed') {
                allClosed = false;
                break;
            }
        }
        NonconformanceReportsService.updateReports(
            new List<NonconformanceReport__c>{
                new NonconformanceReport__c(
                    Id = reportId,
                    NCRStatus__c = allClosed ? 'Closed' : 'Open'
                )
            }
        );
    }

    private static String calculateQualityInspectionRiskRating(
        String severity,
        String occurrence
    ) {
        if (String.isBlank(severity) || String.isBlank(occurrence)) {
            return null;
        }
        if (
            (severity == 'Low' && occurrence != 'High') ||
            (severity == 'Medium' && occurrence == 'Low')
        ) {
            return 'Low';
        }
        if (
            (severity == 'Low' && occurrence == 'High') ||
            (severity == 'Medium' && occurrence == 'Medium') ||
            (severity == 'High' && occurrence == 'Low')
        ) {
            return 'Medium';
        }
        return 'High';
    }

    private static String calculateQualityInspectionRiskJustification(
        QualityInspectionNcrLineInput input
    ) {
        if (String.isBlank(input.severityRating) || String.isBlank(input.occurrenceRating)) {
            return null;
        }
        QualityInspectionRiskTexts texts = getQualityInspectionRiskTexts();
        String severityText = texts.severityTexts.get(
            input.severityRating + '|' + input.severityJustification
        );
        String occurrenceText = texts.occurrenceTexts.get(input.occurrenceRating);
        return 'Severity = ' +
            input.severityRating +
            ' - ' +
            blankQualityInspectionText(input.severityJustification) +
            '; ' +
            blankQualityInspectionText(severityText) +
            ' Occurrence = ' +
            input.occurrenceRating +
            '; ' +
            blankQualityInspectionText(occurrenceText);
    }

    /**
     * @description GW-5497 - Returns the configured Risk Justification sentences.
     * @return Severity sentences keyed by rating and category, and occurrence sentences by rating
     */
    public static QualityInspectionRiskTexts getQualityInspectionRiskTexts() {
        Map<String, String> severityTexts = new Map<String, String>();
        Map<String, String> occurrenceTexts = new Map<String, String>();
        for (QualityInspectionRiskText__mdt riskText : [
            SELECT Dimension__c, Rating__c, Category__c, Description__c
            FROM QualityInspectionRiskText__mdt
            WHERE IsActive__c = TRUE
        ]) {
            if (riskText.Dimension__c == 'Severity') {
                severityTexts.put(
                    riskText.Rating__c + '|' + riskText.Category__c,
                    riskText.Description__c
                );
            } else if (riskText.Dimension__c == 'Occurrence') {
                occurrenceTexts.put(riskText.Rating__c, riskText.Description__c);
            }
        }
        return new QualityInspectionRiskTexts(severityTexts, occurrenceTexts);
    }

    private static String blankQualityInspectionText(String value) {
        return value == null ? '' : value;
    }

    private static Map<String, String> qualityInspectionNcrReasonLabelByValue;
    private static Map<String, String> qualityInspectionNcrLocationLabelByValue;

    private static Map<String, String> qualityInspectionNcrReasonLabels() {
        if (qualityInspectionNcrReasonLabelByValue == null) {
            qualityInspectionNcrReasonLabelByValue = qualityInspectionPicklistLabels(
                NonconformanceReportLineItem__c.NCRReason__c.getDescribe()
            );
        }
        return qualityInspectionNcrReasonLabelByValue;
    }

    private static Map<String, String> qualityInspectionNcrLocationLabels() {
        if (qualityInspectionNcrLocationLabelByValue == null) {
            qualityInspectionNcrLocationLabelByValue = qualityInspectionPicklistLabels(
                NonconformanceReportLineItem__c.NCRLocationContext__c.getDescribe()
            );
        }
        return qualityInspectionNcrLocationLabelByValue;
    }

    private static Map<String, String> qualityInspectionPicklistLabels(
        Schema.DescribeFieldResult fieldDescribe
    ) {
        Map<String, String> labelsByValue = new Map<String, String>();
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            labelsByValue.put(entry.getValue(), entry.getLabel());
        }
        return labelsByValue;
    }

    private static String qualityInspectionPicklistLabel(
        Map<String, String> labelsByValue,
        String value
    ) {
        if (String.isBlank(value)) {
            return null;
        }
        String label = labelsByValue.get(value);
        return String.isBlank(label) ? value : label;
    }

    /**
     * @description Keeps NCR Type and Source edited on the page when another line is saved.
     *              Header status stays with line synchronization.
     */
    private static void retainQualityInspectionNcrTypeAndSource(
        Id reportId,
        QualityInspectionNcrInput ncrInput
    ) {
        if (ncrInput == null || String.isBlank(ncrInput.ncrType)) {
            return;
        }
        if (
            !hasQualityInspectionOptionValue(
                toQualityInspectionOptions(NonconformanceReport__c.NCRType__c.getDescribe()),
                ncrInput.ncrType
            )
        ) {
            throw new WorkOrdersServiceException('Select a valid NCR Type.');
        }
        NonconformanceReportsService.updateReports(
            new List<NonconformanceReport__c>{
                new NonconformanceReport__c(
                    Id = reportId,
                    NCRType__c = ncrInput.ncrType
                )
            }
        );
    }

    /**
     * @description Writes inspection fields captured before an NCR save.
     *              Gauge serial and notes are always written. Sub Status is written only when
     *              the page value differs from the Work Order. An unsaved QC Pass is left
     *              unchanged while any NCR line is still Open, so closing one line is not
     *              rolled back by the QC Pass check. QC Pass is applied with the line save
     *              once every line is Closed.
     */
    private static void persistQualityInspectionDraft(
        Id workOrderId,
        String currentSubStatus,
        QualityInspectionDraft draft
    ) {
        if (draft == null) {
            return;
        }
        WorkOrder updateRecord = new WorkOrder(
            Id = workOrderId,
            PressureGaugeSerialNumber__c = draft.pressureGaugeSerialNumber,
            QCInspectionNotes__c = draft.inspectionNotes
        );
        if (String.isNotBlank(draft.subStatus) && draft.subStatus != currentSubStatus) {
            if (
                !hasQualityInspectionOptionValue(
                    getQualityInspectionQcSubStatusOptions(),
                    draft.subStatus
                )
            ) {
                throw new WorkOrdersServiceException('Select a Sub Status valid for QC.');
            }
            Boolean qcPassStillBlocked =
                draft.subStatus == 'QC Pass' &&
                hasOpenQualityInspectionNcrLines(workOrderId);
            if (draft.subStatus == 'QC Fail') {
                assertQualityInspectionNcrExistsForQcFail(workOrderId);
            }
            if (!qcPassStillBlocked) {
                updateRecord.SubStatus__c = draft.subStatus;
            }
        }
        Database.update(updateRecord, AccessLevel.USER_MODE);
    }

    private static void updateQualityInspectionNcrHeader(
        Id workOrderId,
        QualityInspectionNcrInput ncrInput
    ) {
        if (ncrInput == null) {
            return;
        }
        List<NonconformanceReport__c> reports =
            NonconformanceReportsService.getByWorkOrderId(workOrderId);
        if (reports.isEmpty()) {
            return;
        }
        Id requestedReportId = toQualityInspectionId(ncrInput.reportId);
        NonconformanceReport__c targetReport;
        if (requestedReportId != null) {
            targetReport = findQualityInspectionNcr(reports, requestedReportId);
        } else if (reports.size() == 1) {
            targetReport = reports[0];
        } else {
            return;
        }
        if (String.isBlank(ncrInput.ncrStatus)) {
            throw new WorkOrdersServiceException('NCR Status is required.');
        }
        String ncrType = qualityInspectionNcrType(ncrInput);
        if (
            !hasQualityInspectionOptionValue(
                toQualityInspectionOptions(NonconformanceReport__c.NCRType__c.getDescribe()),
                ncrType
            )
        ) {
            throw new WorkOrdersServiceException('Select a valid NCR Type.');
        }
        if (
            !hasQualityInspectionOptionValue(
                toQualityInspectionOptions(NonconformanceReport__c.NCRStatus__c.getDescribe()),
                ncrInput.ncrStatus
            )
        ) {
            throw new WorkOrdersServiceException('Select an NCR Status of Open or Closed.');
        }
        NonconformanceReport__c reportUpdate = new NonconformanceReport__c(
            Id = targetReport.Id,
            NCRType__c = ncrType,
            NCRStatus__c = ncrInput.ncrStatus
        );
        if (ncrInput.departmentId != null) {
            WorkOrder workOrder = WorkOrdersSelector.selectForQualityInspection(
                String.valueOf(workOrderId)
            );
            reportUpdate.Department__c = resolveQualityInspectionDepartment(workOrder, ncrInput);
        }
        NonconformanceReportsService.updateReports(
            new List<NonconformanceReport__c>{ reportUpdate }
        );
    }

    private static QualityInspectionNcr mapQualityInspectionNcr(
        NonconformanceReport__c report,
        WorkOrder workOrder
    ) {
        QualityInspectionNcr dto = new QualityInspectionNcr();
        dto.reportId = report.Id;
        dto.reportNumber = report.Name;
        dto.workOrderLineItemId = report.WorkOrderLineItem__c;
        dto.ncrType = report.NCRType__c;
        dto.ncrStatus = report.NCRStatus__c;
        dto.accountName = report.Account__r != null
            ? report.Account__r.Name
            : (workOrder.Account == null ? null : workOrder.Account.Name);
        dto.repairCenterName = report.RepairCenter__r != null
            ? report.RepairCenter__r.Name
            : (workOrder.RepairCenter__r == null ? null : workOrder.RepairCenter__r.Name);
        String departmentName = workOrder.Department__r == null
            ? null
            : workOrder.Department__r.Name;
        if (String.isBlank(departmentName) && workOrder.ServiceTeam__r != null) {
            departmentName = workOrder.ServiceTeam__r.Name;
        }
        dto.departmentId = report.Department__c == null
            ? null
            : String.valueOf(report.Department__c);
        dto.departmentName = report.Department__r != null
            ? report.Department__r.Name
            : departmentName;
        dto.workOrderLineItemName = report.WorkOrderLineItem__r == null
            ? null
            : report.WorkOrderLineItem__r.LineItemNumber;
        dto.serialNumber = report.SerialNumber__c;
        dto.productName = report.Product__r == null ? null : report.Product__r.Name;
        dto.productLine = report.ProductLine__c;
        dto.model = report.Model__c;
        dto.manufacturer = report.Manufacturer__c;
        return dto;
    }

    private static QualityInspectionNcrLine mapQualityInspectionNcrLine(
        NonconformanceReportLineItem__c line
    ) {
        QualityInspectionNcrLine dto = new QualityInspectionNcrLine();
        dto.lineId = line.Id;
        dto.lineNumber = line.Name;
        dto.reportId = line.NonconformanceReport__c;
        dto.reportNumber =
            line.NonconformanceReport__r == null ? null : line.NonconformanceReport__r.Name;
        dto.repairRelated = line.RepairRelated__c;
        dto.ncrDate = line.NCRDate__c;
        dto.initiatedById = line.InitiatedBy__c;
        dto.initiatedByName = line.InitiatedBy__r == null ? null : line.InitiatedBy__r.Name;
        dto.qualityInspectorId = line.QualityInspector__c;
        dto.qualityInspectorName =
            line.QualityInspector__r == null ? null : line.QualityInspector__r.Name;
        dto.productLine = line.ProductLine__c;
        dto.ncrReason = line.NCRReason__c;
        dto.ncrReasonLabel = qualityInspectionPicklistLabel(
            qualityInspectionNcrReasonLabels(),
            line.NCRReason__c
        );
        dto.ncrLocationContext = line.NCRLocationContext__c;
        dto.ncrLocationContextLabel = qualityInspectionPicklistLabel(
            qualityInspectionNcrLocationLabels(),
            line.NCRLocationContext__c
        );
        dto.comments = line.Comments__c;
        dto.ncrStatus = line.NCRStatus__c;
        dto.ncrSource = line.NCRSource__c;
        dto.severityRating = line.SeverityRating__c;
        dto.severityJustification = line.SeverityJustification__c;
        dto.occurrenceRating = line.OccurrenceRating__c;
        dto.riskRating = line.RiskRating__c;
        dto.quantityRejected = line.QuantityRejected__c;
        dto.capaNumber = line.CAPANumber__c;
        dto.ncrOwner = line.NCROwner__c;
        dto.ncrDescription = line.NCRDescription__c;
        dto.riskJustification = line.RiskJustification__c;
        return dto;
    }

    /** @description GW-5497 workspace DTO. */
    public class QualityInspectionWorkspace {
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public Id recordTypeId { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String subStatus { get; set; }
        @AuraEnabled public String returnOrderNumber { get; set; }
        @AuraEnabled public String reportedProblem { get; set; }
        @AuraEnabled public String pressureGaugeSerialNumber { get; set; }
        @AuraEnabled public String inspectionNotes { get; set; }
        @AuraEnabled public Boolean showPressureGauge { get; set; }
        @AuraEnabled public Boolean showAssetInformation { get; set; }
        @AuraEnabled public Boolean showInstrumentInformation { get; set; }
        @AuraEnabled public Boolean canCreateNcr { get; set; }
        @AuraEnabled public List<QualityInspectionInstrumentLine> instrumentLines { get; set; }
        @AuraEnabled public List<QualityInspectionNcr> ncrs { get; set; }
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public Id productId { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public String productLine { get; set; }
        @AuraEnabled public Boolean continuousImprovementOpportunity { get; set; }
        /** GW-5696 - Customer requires ship complete. */
        @AuraEnabled public Boolean shipComplete { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public String repairCenterName { get; set; }
        @AuraEnabled public Id serviceTeamId { get; set; }
        @AuraEnabled public String departmentName { get; set; }
        @AuraEnabled public List<QualityInspectionOption> departmentOptions { get; set; }
        @AuraEnabled public Boolean hasNcr { get; set; }
        @AuraEnabled public Id defaultWorkOrderLineItemId { get; set; }
        @AuraEnabled public String defaultWorkOrderLineItemProductName { get; set; }
        @AuraEnabled public QualityInspectionNcr ncr { get; set; }
        @AuraEnabled public List<QualityInspectionNcrLine> ncrLines { get; set; }
    }

    /** @description GW-5497 NCR header DTO. */
    public class QualityInspectionNcr {
        @AuraEnabled public Id reportId { get; set; }
        @AuraEnabled public String reportNumber { get; set; }
        @AuraEnabled public Id workOrderLineItemId { get; set; }
        @AuraEnabled public String ncrType { get; set; }
        @AuraEnabled public String ncrStatus { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public String repairCenterName { get; set; }
        @AuraEnabled public String departmentId { get; set; }
        @AuraEnabled public String departmentName { get; set; }
        @AuraEnabled public String workOrderLineItemName { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public String productLine { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
    }

    /** @description GW-5845 Product Serviced row for Instrument Information. */
    public class QualityInspectionInstrumentLine {
        @AuraEnabled public Id lineId { get; set; }
        @AuraEnabled public String lineNumber { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String productLine { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public List<QualityInspectionOption> repairSummary { get; set; }
    }

    /**
     * @description GW-5497 inspection values entered before an NCR save.
     *              Passed with the NCR so a workspace reload does not drop them.
     */
    public class QualityInspectionDraft {
        @AuraEnabled public String subStatus { get; set; }
        @AuraEnabled public String pressureGaugeSerialNumber { get; set; }
        @AuraEnabled public String inspectionNotes { get; set; }
    }

    /** @description GW-5497 inbound NCR header DTO. */
    public class QualityInspectionNcrInput {
        @AuraEnabled public String reportId { get; set; }
        @AuraEnabled public String workOrderLineItemId { get; set; }
        @AuraEnabled public String ncrType { get; set; }
        @AuraEnabled public String ncrStatus { get; set; }
        @AuraEnabled public String departmentId { get; set; }
    }

    /** @description GW-5497 NCR line DTO. */
    public class QualityInspectionNcrLine {
        @AuraEnabled public Id lineId { get; set; }
        @AuraEnabled public String lineNumber { get; set; }
        @AuraEnabled public Id reportId { get; set; }
        @AuraEnabled public String reportNumber { get; set; }
        @AuraEnabled public String repairRelated { get; set; }
        @AuraEnabled public Date ncrDate { get; set; }
        @AuraEnabled public Id initiatedById { get; set; }
        @AuraEnabled public String initiatedByName { get; set; }
        @AuraEnabled public Id qualityInspectorId { get; set; }
        @AuraEnabled public String qualityInspectorName { get; set; }
        @AuraEnabled public String productLine { get; set; }
        @AuraEnabled public String ncrReason { get; set; }
        @AuraEnabled public String ncrReasonLabel { get; set; }
        @AuraEnabled public String ncrLocationContext { get; set; }
        @AuraEnabled public String ncrLocationContextLabel { get; set; }
        @AuraEnabled public String comments { get; set; }
        @AuraEnabled public String ncrStatus { get; set; }
        @AuraEnabled public String ncrSource { get; set; }
        @AuraEnabled public String severityRating { get; set; }
        @AuraEnabled public String severityJustification { get; set; }
        @AuraEnabled public String occurrenceRating { get; set; }
        @AuraEnabled public String riskRating { get; set; }
        @AuraEnabled public Decimal quantityRejected { get; set; }
        @AuraEnabled public String capaNumber { get; set; }
        @AuraEnabled public String ncrOwner { get; set; }
        @AuraEnabled public String ncrDescription { get; set; }
        @AuraEnabled public String riskJustification { get; set; }
    }

    /** @description GW-5497 inbound NCR line DTO. */
    public class QualityInspectionNcrLineInput {
        @AuraEnabled public String lineId { get; set; }
        @AuraEnabled public String repairRelated { get; set; }
        @AuraEnabled public Date ncrDate { get; set; }
        @AuraEnabled public String initiatedById { get; set; }
        @AuraEnabled public String qualityInspectorId { get; set; }
        @AuraEnabled public String productLine { get; set; }
        @AuraEnabled public String ncrReason { get; set; }
        @AuraEnabled public String ncrLocationContext { get; set; }
        @AuraEnabled public String comments { get; set; }
        @AuraEnabled public String ncrSource { get; set; }
        @AuraEnabled public String ncrStatus { get; set; }
        @AuraEnabled public String severityRating { get; set; }
        @AuraEnabled public String severityJustification { get; set; }
        @AuraEnabled public String occurrenceRating { get; set; }
        @AuraEnabled public Decimal quantityRejected { get; set; }
        @AuraEnabled public String capaNumber { get; set; }
        @AuraEnabled public String ncrOwner { get; set; }
        @AuraEnabled public String ncrDescription { get; set; }
    }

    /** @description GW-5497 configured Risk Justification sentences. */
    public class QualityInspectionRiskTexts {
        /** @description Creates the sentence maps returned to Quality Inspection. */
        public QualityInspectionRiskTexts(
            Map<String, String> severityTexts,
            Map<String, String> occurrenceTexts
        ) {
            this.severityTexts = severityTexts;
            this.occurrenceTexts = occurrenceTexts;
        }
        @AuraEnabled public Map<String, String> severityTexts { get; set; }
        @AuraEnabled public Map<String, String> occurrenceTexts { get; set; }
    }

    /** @description GW-5497 combobox option DTO. */
    public class QualityInspectionOption {
        /** @description Creates a combobox option. */
        public QualityInspectionOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
    }

    /**
     * @description GW-5492 - Result of receiving Work Order creation.
     */
    public class ReceivingWorkOrderCreateResult {
        public Id parentWorkOrderId;
        public Id navigationWorkOrderId;
        public Id productServicedLineItemId;
    }

    /**
     * @description GW-5492 - Counts Work Orders linked to a Return Order.
     * @param returnOrderId Return Order Id
     * @return Count
     */
    public static Integer countByReturnOrderId(Id returnOrderId) {
        return WorkOrdersSelector.countByReturnOrderId(returnOrderId);
    }

    /**
     * @description GW-5492 - Inserts Work Orders for Finish Receiving with DML detail.
     * @param workOrders Work Orders to insert
     */
    public static void createReceivingWorkOrders(List<WorkOrder> workOrders) {
        if (workOrders == null || workOrders.isEmpty()) {
            return;
        }
        try {
            Database.insert(workOrders, AccessLevel.USER_MODE);
        } catch (DmlException e) {
            Logger.error('WorkOrdersService.createReceivingWorkOrders: DML error.', e);
            Logger.saveLog();
            throw new WorkOrdersServiceException(
                e.getNumDml() > 0 ? e.getDmlMessage(0) : e.getMessage(),
                e
            );
        } catch (Exception e) {
            Logger.error('WorkOrdersService.createReceivingWorkOrders: Unexpected error.', e);
            Logger.saveLog();
            throw new WorkOrdersServiceException(
                'Unable to create receiving Work Orders: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    public class WorkOrdersServiceException extends Exception {}
}