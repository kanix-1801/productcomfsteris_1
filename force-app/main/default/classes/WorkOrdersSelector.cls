/**
 * @author Uptima
 * @date 2026-08-15
 * @group Selectors
 * @description Selector class for the WorkOrder SObject.
 *              Centralizes all SOQL queries for Work Orders.
 *              Centralizes Work Order SOQL. Classes run with sharing.
 */
public with sharing class WorkOrdersSelector extends SoqlQueryBuilder {
    /**
     * @description GW-3600 - Binds this selector to WorkOrder for SoqlQueryBuilder queries.
     */
    public WorkOrdersSelector() {
        this.objectName = 'WorkOrder';
    }

    private static final String BASE_FIELDS =
        'Id, Subject, Status, Priority, WorkTypeId, ' +
        'AccountId, ContactId, AssetId, LocationId, ' +
        'StartDate, EndDate, Duration, DurationType, ' +
        'Description, OwnerId, CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves WorkOrder records by their Ids.
     *              Used by GW-2891 Divide Instruments when deleting orphan child Work Orders.
     * @param ids Set of WorkOrder Ids to query.
     * @return List of WorkOrder records matching the given Ids.
     * @example
     * List<WorkOrder> results = WorkOrdersSelector.selectById(workOrderIdSet);
     */
    public static List<WorkOrder> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<WorkOrder>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM WorkOrder' +
            ' WHERE Id IN :ids'
        );
    }

    /**
     * @description Retrieves WorkOrder records by Status.
     * @param statusValues Set of Status values to filter on.
     * @return List of WorkOrder records matching the given Status values.
     * @example
     * List<WorkOrder> openOrders = WorkOrdersSelector.selectByStatus(new Set<String>{ 'New', 'In Progress' });
     */
    public static List<WorkOrder> selectByStatus(Set<String> statusValues) {
        if (statusValues == null || statusValues.isEmpty()) {
            return new List<WorkOrder>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM WorkOrder' +
            ' WHERE Status IN :statusValues' +
            ' ORDER BY CreatedDate DESC'
        );
    }

    /**
     * @description Retrieves WorkOrder records by Account Id.
     * @param accountIds Set of Account Ids to filter on.
     * @return List of WorkOrder records linked to the given Accounts.
     * @example
     * List<WorkOrder> orders = WorkOrdersSelector.selectByAccountId(accountIdSet);
     */
    public static List<WorkOrder> selectByAccountId(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM WorkOrder' +
            ' WHERE AccountId IN :accountIds' +
            ' ORDER BY CreatedDate DESC'
        );
    }

    /**
     * @description Retrieves WorkOrder records with their related Work Order Line Items.
     * @param ids Set of WorkOrder Ids to query.
     * @return List of WorkOrder records with child WorkOrderLineItem records.
     * @example
     * List<WorkOrder> ordersWithLines = WorkOrdersSelector.selectByIdWithLineItems(workOrderIdSet);
     */
    public static List<WorkOrder> selectByIdWithLineItems(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<WorkOrder>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ', (SELECT Id, Description, Duration, DurationType, Status, LineItemNumber FROM WorkOrderLineItems)' +
            ' FROM WorkOrder' +
            ' WHERE Id IN :ids'
        );
    }

    /**
     * @description Selects Work Orders with Asset PFCL / Service BOM fields for Allowed Unit evaluation.
     * @param workOrderIdSet Work Order Ids
     * @return Matching Work Order records
     */
    public static List<WorkOrder> selectByIdsForAllowedUnit(Set<Id> workOrderIdSet) {
        if (workOrderIdSet == null || workOrderIdSet.isEmpty()) {
            return new List<WorkOrder>();
        }

        return [
            SELECT Id, AssetId, Asset.PFCL__c, Asset.ServiceBOM__c
            FROM WorkOrder
            WHERE Id IN :workOrderIdSet
           
        ];
    }



    /****************************************************************************************
     * ADDITIVES FOR RATE LIST (GW-2967)
     ****************************************************************************************/

    /**
     * @description Selects Work Orders with Work Order and Account Rate List lookups for ES debrief travel pricing.
     * @param workOrderIdSet Work Order Ids
     * @return Matching Work Order records
     */
    public static List<WorkOrder> selectByIdsForRateList(Set<Id> workOrderIdSet) {
        if (workOrderIdSet == null || workOrderIdSet.isEmpty()) {
            return new List<WorkOrder>();
        }

        return [
            SELECT Id, AccountId, Account.RateList__c, RateList__c
            FROM WorkOrder
            WHERE Id IN :workOrderIdSet
        ];
    }

    /**
     * @description Selects Work Orders with Price Book and currency for IMS Child debrief price book entry resolve.
     * @param workOrderIdSet Work Order Ids
     * @return Matching Work Order records
     */
    public static List<WorkOrder> selectByIdsForPricebook(Set<Id> workOrderIdSet) {
        if (workOrderIdSet == null || workOrderIdSet.isEmpty()) {
            return new List<WorkOrder>();
        }

        return [
            SELECT Id, Pricebook2Id, CurrencyIsoCode
            FROM WorkOrder
            WHERE Id IN :workOrderIdSet
        ];
    }

    /****************************************************************************************
     * ADDITIVES FOR CUSTOMER PREFERENCES (GW-2860)
     * Methods below this banner were added for Repair Center LWC Batch 9 (not Dev baseline).
     ****************************************************************************************/

    /**
     * @description GW-2860 - Selects Work Orders with Account and Asset product-line context for
     *              Work Order Customer Preferences (IMS preference matching on the WO record page).
     * @param ids Set of WorkOrder Ids to query
     * @return List of WorkOrder records with AccountId and Asset product-line related fields
     */
    public static List<WorkOrder> selectByIdForCustomerPreferences(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<WorkOrder>();
        }
        return [
            SELECT
                Id,
                WorkOrderNumber,
                AccountId,
                AssetId,
                Asset.ProductLineCalculated__c,
                Asset.Product2.ProductLine__c
            FROM WorkOrder
            WHERE Id IN :ids
           
        ];
    }


    /****************************************************************************************
     * ADDITIVES FOR REPAIR ORDER HISTORY (GW-1295)
     * Methods below this banner were added for Repair Center LWC Batch 9 (not Dev baseline).
     ****************************************************************************************/

    /**
     * @description GW-1295 - Selects Work Orders with Asset context for Repair Order History
     *              on the Work Order record page.
     * @param ids Set of WorkOrder Ids to query
     * @return List of WorkOrder records with WorkOrderNumber and AssetId
     */
    public static List<WorkOrder> selectByIdForRepairHistory(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<WorkOrder>();
        }
        return [
            SELECT Id, WorkOrderNumber, AssetId
            FROM WorkOrder
            WHERE Id IN :ids
           
        ];
    }

    /**
     * @description GW-1295 - Selects prior Repair Center Work Orders for an Asset that have an
     *              Actual Ship Date, excluding the current Work Order.
     * @param assetId Asset whose repair history is requested
     * @param currentWorkOrderId Current Work Order Id to exclude
     * @param recordTypeIds Repair Center Work Order RecordType Ids
     * @return Prior shipped Repair Center Work Orders ordered by Actual Ship Date DESC
     */
    public static List<WorkOrder> selectRepairHistoryByAsset(
        Id assetId,
        Id currentWorkOrderId,
        Set<Id> recordTypeIds
    ) {
        if (assetId == null || recordTypeIds == null || recordTypeIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        return [
            SELECT Id, WorkOrderNumber, ActualShipDate__c, Evaluator__c, Evaluator__r.Name
            FROM WorkOrder
            WHERE AssetId = :assetId
                AND ActualShipDate__c != null
                AND RecordTypeId IN :recordTypeIds
                AND Id != :currentWorkOrderId
           
            ORDER BY ActualShipDate__c DESC
        ];
    }


    /****************************************************************************************
     * ADDITIVES FOR DEVICE EVALUATION (GW-3913 / GW-3096)
     * Methods below this banner were added for Repair Center LWC Batch 9 (not Dev baseline).
     ****************************************************************************************/

    /** GW-3913 / GW-3096 - Device Evaluation query cap for repair history rows. */
    @TestVisible
    private static final Integer DEVICE_EVALUATION_REPAIR_HISTORY_QUERY_LIMIT = 100;

    /**
     * GW-3913 / GW-3096 - Device Evaluation Work Order field list (matches DeviceEvaluationController).
     * TODO GW-3400: Rename/extract this list and selectForDeviceEvaluationById / ByNumber into a shared
     * Repair Center evaluation selector. See docs/GW-3400/follow-up-shared-eval-selector.md.
     * GW-3400 added RecordType.DeveloperName, Subject, Description, QuantityReceived__c,
     * RepairCategory__c, ReturnOrderId, ReturnOrder__c for Instrument Evaluation.
     * GW-5453 added QCInspectionNotes__c for Evaluation Notes tab display.
     */
    @TestVisible
    private static final String DEVICE_EVALUATION_FIELD_LIST =
        'Id, WorkOrderNumber, RecordTypeId, RecordType.DeveloperName, Status, SubStatus__c, ' +
        'AccountId, AssetId, OwnerId, Evaluator__c, ' +
        'PhotosRequired__c, UnableToTakePhoto__c, TurnTime__c, UsageCount__c, UsageCountDate__c, ' +
        'EstimateRequired__c, RepairWarranty__c, ContinuousImprovementOpportunity__c, ' +
        'CustomerPORequired__c, CustomerPO__c, ShipComplete__c, STERISPurchaseOrdertoVendor__c, ' +
        'EvaluationNotes__c, InternalEvaluationNotes__c, ' +
        'InternalSpecialistEvaluationNotes__c, QCInspectionNotes__c, ParentWorkOrderId, ' +
        'Pricebook2Id, CurrencyIsoCode, ' +
        'ProductLine_f__c, ParentWorkOrder.Id, ParentWorkOrder.Pricebook2Id, ' +
        'Subject, Description, QuantityReceived__c, RepairCategory__c, ReturnOrderId, ReturnOrder__c, ' +
        'ReturnOrderLineItemId, Model__c, TrayName__c, ' +
        'Vendor__c, VendorWorkOrder__c, InstructionsToVendor__c, VendorNotes__c, ' +
        'VendorReferenceNumber__c, VendorCost__c, ShippedToVendorDate__c, ' +
        'ContactId, RepairCenter__c, Department__c, Product__c, ' +
        'Asset.Id, Asset.Name, Asset.SerialNumber, Asset.Product2Id, ' +
        'Asset.ManufacturerCalculated__c, Asset.ModelCalculated__c, Asset.ProductLineCalculated__c, ' +
        'Asset.Product2.Id, Asset.Product2.Name, Asset.Product2.ProductCode, Asset.Product2.Description, ' +
        'Asset.Product2.ProductLine__c, Asset.Product2.Manufacturer__c, Asset.Product2.Model__c';

    /**
     * @description GW-3913 / GW-3096 - Selects a Work Order for Device Evaluation by WorkOrderNumber.
     * @param workOrderNumber Work Order number to query
     * @return List of matching Work Order records (LIMIT 1); empty when not found / blank input
     */
    public static List<WorkOrder> selectForDeviceEvaluationByNumber(String workOrderNumber) {
        if (String.isBlank(workOrderNumber)) {
            return new List<WorkOrder>();
        }
        String soql =
            'SELECT ' +
            DEVICE_EVALUATION_FIELD_LIST +
            ' FROM WorkOrder WHERE WorkOrderNumber = :workOrderNumber LIMIT 1';
        return Database.query(soql);
    }

    /**
     * @description GW-3400 - Selects Work Orders by WorkOrderNumber for Instrument Evaluation.
     *              WorkOrderNumber is not unique in this org, so callers may receive multiple rows.
     * @param workOrderNumber Work Order number to query
     * @return Matching WorkOrder records (no LIMIT)
     */
    public static List<WorkOrder> selectForInstrumentEvaluationByNumber(String workOrderNumber) {
        if (String.isBlank(workOrderNumber)) {
            return new List<WorkOrder>();
        }
        String soql =
            'SELECT ' +
            DEVICE_EVALUATION_FIELD_LIST +
            ' FROM WorkOrder WHERE WorkOrderNumber = :workOrderNumber';
        return Database.query(soql);
    }

    /**
     * @description GW-3913 / GW-3096 - Selects a Work Order for Device Evaluation by Id.
     *              GW-3400 Instrument Evaluation also uses this query (shared field list).
     *              TODO GW-3400: extract a shared Repair Center evaluation selector name.
     * @param workOrderId Work Order Id to query
     * @return List of matching WorkOrder records (LIMIT 1); empty when not found / null input
     */
    public static List<WorkOrder> selectForDeviceEvaluationById(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WorkOrder>();
        }
        String soql =
            'SELECT ' +
            DEVICE_EVALUATION_FIELD_LIST +
            ' FROM WorkOrder WHERE Id = :workOrderId LIMIT 1';
        return Database.query(soql);
    }

    /**
     * @description Returns Sub Status for a Work Order by Id (LIMIT 1).
     * @param workOrderId Work Order Id to query
     * @return Matching WorkOrder rows with SubStatus__c; empty when not found / null input
     */
    public static List<WorkOrder> selectSubStatusById(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WorkOrder>();
        }
        return [
            SELECT SubStatus__c
            FROM WorkOrder
            WHERE Id = :workOrderId
            WITH USER_MODE
            LIMIT 1
        ];
    }

    /**
     * @description GW-3891 - Work Order fields for Warranty Repair Evaluation auto-population.
     */
    @TestVisible
    private static final String WRE_WORK_ORDER_FIELD_LIST =
        'Id, WorkOrderNumber, Description, CreatedDate, QuantityReceived__c, PreviousReturnOrder__c, ' +
        'ParentWorkOrderId, ParentWorkOrder.WorkOrderNumber, ReturnOrder__c, ' +
        'ReturnOrder__r.ReturnOrderNumber, Account.AccountNumber, ProductLine_f__c, AssetId, ' +
        'RecordType.DeveloperName, Asset.SerialNumber, Asset.ManufacturerCalculated__c, Asset.ModelCalculated__c, ' +
        'Asset.ProductLineCalculated__c, Asset.Product2.Manufacturer__c, Asset.Product2.Model__c, ' +
        'Asset.Product2.ProductLine__c, Asset.Product2.DeviceType__c';

    /**
     * @description GW-3891 - Selects a Work Order for Warranty Repair Evaluation form defaults.
     */
    public static WorkOrder selectForWarrantyRepairEvaluationById(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }
        String soql =
            'SELECT ' +
            WRE_WORK_ORDER_FIELD_LIST +
            ' FROM WorkOrder WHERE Id = :workOrderId LIMIT 1';
        List<WorkOrder> rows = Database.query(soql);
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description GW-3891 - Prior Repair Center Devices Work Order for the same Asset.
     */
    public static WorkOrder selectMostRecentRepairCenterDeviceByAsset(
        Id assetId,
        Id excludeWorkOrderId,
        Id repairCenterDevicesRecordTypeId
    ) {
        if (assetId == null || repairCenterDevicesRecordTypeId == null) {
            return null;
        }
        List<WorkOrder> rows = [
            SELECT Id, ActualShipDate__c
            FROM WorkOrder
            WHERE AssetId = :assetId
                AND RecordTypeId = :repairCenterDevicesRecordTypeId
                AND ActualShipDate__c != NULL
                AND Id != :excludeWorkOrderId
            WITH USER_MODE
            ORDER BY ActualShipDate__c DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description GW-4495 / GW-3913 - Selects Repair Center Work Orders for Device and Instrument
     *              Evaluation repair history: same Account and Asset, excluding the current Work
     *              Order. Caps at 100 rows. The 12-month Completion Timestamp default view and View
     *              All (full asset history) are applied by the caller. Distinct from GW-1295
     *              selectRepairHistoryByAsset, which does not filter by Account.
     * @param accountId Account that must match the history Work Orders
     * @param assetId Asset whose repair history is requested
     * @param currentWorkOrderId Current Work Order Id to exclude
     * @param recordTypeIds Repair Center Work Order RecordType Ids
     * @return Repair Center Work Orders ordered by Completion Timestamp DESC
     */
    public static List<WorkOrder> selectRepairHistoryForDeviceEvaluation(
        Id accountId,
        Id assetId,
        Id currentWorkOrderId,
        Set<Id> recordTypeIds
    ) {
        if (
            accountId == null ||
            assetId == null ||
            recordTypeIds == null ||
            recordTypeIds.isEmpty()
        ) {
            return new List<WorkOrder>();
        }
        return [
            SELECT
                Id,
                WorkOrderNumber,
                Description,
                ActualShipDate__c,
                CompletedTimestamp__c,
                EvaluationNotes__c,
                InternalEvaluationNotes__c,
                Evaluator__c,
                Evaluator__r.Name,
                RepairCenter__c,
                RepairCenter__r.Name,
                (
                    SELECT
                        Id,
                        Product2Id,
                        Product2.ProductCode,
                        Product2.Name,
                        Product2.ProductType__c
                    FROM WorkOrderLineItems
                    WHERE Product2Id != null
                        AND Product2.ProductType__c IN ('Category Code', 'Service Code')
                )
            FROM WorkOrder
            WHERE AccountId = :accountId
                AND AssetId = :assetId
                AND RecordTypeId IN :recordTypeIds
                AND Id != :currentWorkOrderId
            ORDER BY CompletedTimestamp__c DESC NULLS LAST
            LIMIT :DEVICE_EVALUATION_REPAIR_HISTORY_QUERY_LIMIT
        ];
    }

    /****************************************************************************************
     * ADDITIVES FOR ASSIGN TECHNICIAN / ASSIGN RACK (GW-3816 / GW-5783)
     ****************************************************************************************/

    /**
     * @description GW-3816 / GW-2891 / GW-5783 - Selects a Work Order by Salesforce Id (when input
     *              looks like an Id) or by Work Order Number. Includes Rack__c so Assign Rack can
     *              detect a rack change.
     * @param workOrderInput Work Order Id or WorkOrderNumber
     * @return Matching WorkOrder, or null when not found / blank input
     * @example
     * WorkOrder wo = WorkOrdersSelector.selectByIdOrNumber('00001234');
     */
    public static WorkOrder selectByIdOrNumber(String workOrderInput) {
        if (String.isBlank(workOrderInput)) {
            return null;
        }

        if (PlatformUtilities.isSalesforceId(workOrderInput)) {
            Map<String, Object> byIdBinds = new Map<String, Object>{ 'workOrderInput' => workOrderInput };
            List<WorkOrder> byIdList = Database.queryWithBinds(
                'SELECT Id, WorkOrderNumber, Status, Rack__c FROM WorkOrder ' +
                    'WHERE Id = :workOrderInput LIMIT 1',
                byIdBinds,
                AccessLevel.SYSTEM_MODE
            );
            if (!byIdList.isEmpty()) {
                return byIdList[0];
            }
        }

        Map<String, Object> byNumberBinds = new Map<String, Object>{ 'workOrderInput' => workOrderInput };
        List<WorkOrder> byNumberList = Database.queryWithBinds(
            'SELECT Id, WorkOrderNumber, Status, Rack__c FROM WorkOrder ' +
                'WHERE WorkOrderNumber = :workOrderInput LIMIT 1',
            byNumberBinds,
            AccessLevel.SYSTEM_MODE
        );
        return byNumberList.isEmpty() ? null : byNumberList[0];
    }

    /****************************************************************************************
     * ADDITIVES FOR DIVIDE INSTRUMENTS (GW-2891)
     ****************************************************************************************/

    private static final String DIVIDE_INSTRUMENTS_FIELD_LIST =
        'Id, WorkOrderNumber, Status, OwnerId, RecordTypeId, RecordType.DeveloperName, ' +
        'ParentWorkOrderId, AccountId, ContactId, LocationId, CaseId, ReturnOrderId, ' +
        'ReturnOrderLineItemId, ReturnOrder__c, ' +
        'Subject, Description, ' +
        'EstimateRequired__c, CustomerPORequired__c, CustomerPO__c, RepairWarranty__c, ' +
        'QuantityReceived__c, ContinuousImprovementOpportunity__c, Department__c, ' +
        'EstimateContact__c, AssignedSalesPerson__c, CreditStatusCode__c, RepairCenter__c, ' +
        'OperatingUnit__c, ' +
        'Receiver__c, WarrantyNotes__c, RepairCategory__c, Rack__c, TurnTime__c, ' +
        'CustomerReference__c, Contaminated__c, PhotosRequired__c, ModRequest__c, ' +
        'Pricebook2Id, CurrencyIsoCode, ' +
        'AssetId, Asset.ProductLineCalculated__c, Asset.Product2.ProductLine__c';

    /**
     * @description GW-2891 - Selects a parent Work Order for Divide Instruments by Salesforce Id.
     * @param workOrderId Work Order Id
     * @return Matching Work Orders (LIMIT 1)
     */
    public static List<WorkOrder> selectForDivideInstrumentsById(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WorkOrder>();
        }
        String soql =
            'SELECT ' +
            DIVIDE_INSTRUMENTS_FIELD_LIST +
            ' FROM WorkOrder WHERE Id = :workOrderId LIMIT 1';
        return Database.query(soql);
    }

    /**
     * @description GW-2891 - Selects child Work Orders for Divide Instruments reconcile.
     * @param parentWorkOrderId Parent Work Order Id
     * @return Child Work Orders ordered by Work Order Number
     */
    public static List<WorkOrder> selectChildWorkOrdersForDivideInstruments(Id parentWorkOrderId) {
        if (parentWorkOrderId == null) {
            return new List<WorkOrder>();
        }
        return [
            SELECT
                Id,
                ParentWorkOrderId,
                WorkOrderNumber,
                RepairCategory__c,
                QuantityReceived__c,
                TurnTime__c,
                ScheduledShipDate__c,
                DateReadyforRepair__c,
                Status
            FROM WorkOrder
            WHERE ParentWorkOrderId = :parentWorkOrderId
            WITH SECURITY_ENFORCED
            ORDER BY WorkOrderNumber
        ];
    }

    /****************************************************************************************
     * ADDITIVES FOR SHIP DATE CALCULATION (GW-3164)
     * Methods below this banner are ship-date additives (not original Dev CRUD/query baseline).
     ****************************************************************************************/

/**
     * @description GW-3164 - Queries Work Orders and related Repair Center Operating Hours.
     * @param workOrderIdSet Set of Work Order IDs
     * @return List of Work Orders
     */
    public static List<WorkOrder> selectWorkOrdersWithOperatingHours(Set<Id> workOrderIdSet) {
        return [
            SELECT Id, TurnTime__c, DateReadyforRepair__c, ScheduledShipDate__c,
                   RepairCenter__c, SubStatus__c,
                   RepairCenter__r.OperatingHours__c, 
                   RepairCenter__r.OperatingHours__r.TimeZone
            FROM WorkOrder
            WHERE Id IN :workOrderIdSet
           
        ];
    }

    /**
     * @description GW-3164 - Queries Holidays for given Operating Hours.
     * @param operatingHoursIdSet Set of Operating Hours IDs
     * @return List of OperatingHoursHoliday records
     */
    public static List<OperatingHoursHoliday> selectOperatingHoursHolidays(Set<Id> operatingHoursIdSet) {
        return [
            SELECT OperatingHoursId, Holiday.ActivityDate 
            FROM OperatingHoursHoliday 
            WHERE OperatingHoursId IN :operatingHoursIdSet
           
        ];
    }

    /**
     * @description GW-3816 / GW-2891 - Returns true when the value can be coerced to a Salesforce Id.
     *              Used by selectByIdOrNumber for Assign Technician / Assign Rack and Divide Instruments.
     * @param value Candidate Id or Work Order Number
     * @return True when value is an 15/18-character Salesforce Id
     */

    // --- START RELEVANT TO GW-4637 ---
    /**
     * @description GW-4637 - Selects Work Orders with Repair Center, Return Order, parent WO,
     *              and Asset product fields needed to merge Zebra bin tag print payloads.
     * @param ids Set of WorkOrder Ids to query
     * @return Matching Work Order records
     */
    public static List<WorkOrder> selectByIdForBinTagPrint(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<WorkOrder>();
        }
        return [
            SELECT
                Id,
                WorkOrderNumber,
                WorkOrderType__c,
                ProductLine_f__c,
                ParentWorkOrderId,
                ParentWorkOrder.WorkOrderNumber,
                RepairCenter__c,
                AccountId,
                Account.BillingCountry,
                Account.ShippingCountry,
                ReturnOrderId,
                ReturnOrder.ReturnOrderNumber,
                ReturnOrder__c,
                ReturnOrder__r.ReturnOrderNumber,
                AssetId,
                Asset.ProductLineCalculated__c,
                Asset.Product2.ProductLine__c,
                Asset.Product2.Description
            FROM WorkOrder
            WHERE Id IN :ids
            WITH SECURITY_ENFORCED
        ];
    }
    // --- END RELEVANT TO GW-4637 ---

    public static List<WorkOrder> selectOutsideVendorForConsolidation(
        Id repairCenterId,
        Id otherRecordTypeId,
        String subStatus
    ) {
        if (repairCenterId == null || otherRecordTypeId == null) {
            return new List<WorkOrder>();
        }
        return [
            SELECT
                Id,
                WorkOrderNumber,
                Status,
                SubStatus__c,
                ParentWorkOrderId,
                ParentWorkOrder.WorkOrderNumber,
                Vendor__c,
                Vendor__r.Name,
                Vendor__r.BillingStreet,
                Vendor__r.BillingCity,
                Vendor__r.BillingState,
                Vendor__r.BillingStateCode,
                Vendor__r.BillingPostalCode,
                Vendor__r.BillingCountry,
                Vendor__r.ShippingStreet,
                Vendor__r.ShippingCity,
                Vendor__r.ShippingState,
                Vendor__r.ShippingStateCode,
                Vendor__r.ShippingPostalCode,
                Vendor__r.ShippingCountry,
                RepairCenter__c,
                RepairCenter__r.Name,
                CustomerPO__c,
                ReturnOrder__c,
                VendorReturnOrder__c
            FROM WorkOrder
            WHERE
                RepairCenter__c = :repairCenterId
                AND SubStatus__c = :subStatus
                AND RecordTypeId = :otherRecordTypeId
                AND VendorReturnOrder__c = NULL
            WITH USER_MODE
            ORDER BY Vendor__r.Name NULLS LAST, WorkOrderNumber
            LIMIT 2000
        ];
    }

    public static List<WorkOrder> selectForVendorConsolidationComplete(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        return [
            SELECT
                Id,
                WorkOrderNumber,
                Status,
                SubStatus__c,
                RecordTypeId,
                AccountId,
                Vendor__c,
                Vendor__r.Name,
                Vendor__r.OrgIDs__c,
                Vendor__r.BillingStreet,
                Vendor__r.BillingCity,
                Vendor__r.BillingState,
                Vendor__r.BillingStateCode,
                Vendor__r.BillingPostalCode,
                Vendor__r.BillingCountry,
                Vendor__r.ShippingStreet,
                Vendor__r.ShippingCity,
                Vendor__r.ShippingState,
                Vendor__r.ShippingStateCode,
                Vendor__r.ShippingPostalCode,
                Vendor__r.ShippingCountry,
                RepairCenter__c,
                AssetId,
                Product__c,
                ReturnOrderId,
                ReturnOrder__c,
                VendorReturnOrder__c,
                ReturnOrderLineItemId,
                Model__c,
                Department__c,
                CustomerPO__c,
                InstructionsToVendor__c,
                VendorNotes__c,
                VendorReferenceNumber__c,
                VendorCost__c
            FROM WorkOrder
            WHERE Id IN :workOrderIds
            WITH USER_MODE
        ];
    }

    public static List<WorkOrder> selectByVendorReturnOrderIds(Set<Id> returnOrderIds) {
        if (returnOrderIds == null || returnOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        return [
            SELECT Id, VendorReturnOrder__c
            FROM WorkOrder
            WHERE VendorReturnOrder__c IN :returnOrderIds
            WITH USER_MODE
        ];
    }

    public static List<WorkOrder> selectByIdForVendorFedExShipment(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        return [
            SELECT Id, WorkOrderNumber, Vendor__c
            FROM WorkOrder
            WHERE Id IN :workOrderIds
            WITH USER_MODE
        ];
    }

    public static List<WorkOrder> selectByIdForModRequestFormEmail(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        return [
            SELECT
                Id,
                ModRequest__c,
                SubStatus__c,
                ModRequestContact__c,
                ModRequestContactEmail__c,
                ModRequestContact__r.Name,
                ModRequestContact__r.Email
            FROM WorkOrder
            WHERE Id IN :workOrderIds
            WITH SECURITY_ENFORCED
        ];
    }

    public static WorkOrder selectMostRecentRepairCenterWorkOrderByAsset(
        Id assetId,
        Id excludeWorkOrderId,
        Id recordTypeId
    ) {
        if (assetId == null || recordTypeId == null) {
            return null;
        }
        List<WorkOrder> rows = [
            SELECT
                Id,
                ActualShipDate__c,
                PreviousReturnOrder__c,
                ReturnOrder__c,
                ReturnOrder__r.ReturnOrderNumber
            FROM WorkOrder
            WHERE AssetId = :assetId
                AND RecordTypeId = :recordTypeId
                AND ActualShipDate__c != NULL
                AND Id != :excludeWorkOrderId
            WITH USER_MODE
            ORDER BY ActualShipDate__c DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }


    /**
     * @description GW-5497 - Loads a Work Order by Salesforce Id or exact Work Order Number.
     * @param workOrderInput Work Order Id or Work Order Number
     * @return Matching Work Order, or null
     */
    public static WorkOrder selectForQualityInspection(String workOrderInput) {
        if (String.isBlank(workOrderInput)) {
            return null;
        }
        String trimmedInput = workOrderInput.trim();
        Id workOrderId;
        try {
            Id candidateId = Id.valueOf(trimmedInput);
            if (candidateId.getSObjectType() == WorkOrder.SObjectType) {
                workOrderId = candidateId;
            }
        } catch (StringException ignored) {
            workOrderId = null;
        }

        List<WorkOrder> workOrders = [
            SELECT
                Id,
                WorkOrderNumber,
                RecordTypeId,
                RecordType.DeveloperName,
                Status,
                SubStatus__c,
                OwnerId,
                QCInspector__c,
                PressureGaugeSerialNumber__c,
                QCInspectionNotes__c,
                ContinuousImprovementOpportunity__c,
                ShipComplete__c,
                Description,
                ReturnOrder__c,
                ReturnOrder__r.ReturnOrderNumber,
                AccountId,
                Account.Name,
                AssetId,
                Asset.Name,
                Asset.SerialNumber,
                Asset.Product2Id,
                Asset.Product2.Name,
                Asset.Product2.ProductLine__c,
                Asset.Product2.Model__c,
                Asset.Product2.Manufacturer__c,
                RepairCenter__c,
                RepairCenter__r.Name,
                Department__c,
                Department__r.Name,
                ServiceTeam__c,
                ServiceTeam__r.Name,
                ProductLine__c,
                ProductLine_f__c
            FROM WorkOrder
            WHERE Id = :workOrderId OR WorkOrderNumber = :trimmedInput
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return workOrders.isEmpty() ? null : workOrders[0];
    }

    /****************************************************************************************
     * ADDITIVES FOR REPAIR COORDINATOR ACTIONS (GW-5231)
     ****************************************************************************************/

    /**
     * @description GW-5231 - Selects a Work Order by Salesforce Id or Work Order Number
     *              for Repair Coordinator Actions, including Rack and Service Team assignment fields.
     * @param workOrderInput Work Order Id or Work Order Number
     * @return Matching Work Order, or null
     */
    public static WorkOrder selectForCoordinatorActionsByIdOrNumber(String workOrderInput) {
        if (String.isBlank(workOrderInput)) {
            return null;
        }

        String trimmedInput = workOrderInput.trim();
        if (PlatformUtilities.isSalesforceId(trimmedInput)) {
            List<WorkOrder> workOrdersById = [
                SELECT
                    Id,
                    WorkOrderNumber,
                    Status,
                    RepairCategory__c,
                    Rack__c,
                    ServiceTeam__c,
                    RepairCenter__c
                FROM WorkOrder
                WHERE Id = :trimmedInput
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!workOrdersById.isEmpty()) {
                return workOrdersById[0];
            }
        }

        List<WorkOrder> workOrdersByNumber = [
            SELECT
                Id,
                WorkOrderNumber,
                Status,
                RepairCategory__c,
                Rack__c,
                ServiceTeam__c,
                RepairCenter__c
            FROM WorkOrder
            WHERE WorkOrderNumber = :trimmedInput
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return workOrdersByNumber.isEmpty() ? null : workOrdersByNumber[0];
    }

    /**
     * @description GW-5231 - Selects a Work Order by Id for Repair Coordinator assignment updates.
     * @param workOrderId Work Order Id
     * @return Matching Work Order, or null
     */
    public static WorkOrder selectForCoordinatorActionsById(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }
        List<WorkOrder> workOrders = [
            SELECT
                Id,
                WorkOrderNumber,
                Status,
                RepairCategory__c,
                Rack__c,
                ServiceTeam__c,
                RepairCenter__c
            FROM WorkOrder
            WHERE Id = :workOrderId
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        return workOrders.isEmpty() ? null : workOrders[0];
    }

    /**
     * @description GW-3398 - Asset model product code for overhaul resolution.
     * @param workOrderIds Work Order Ids
     * @return Work Orders with Asset.Product2.ProductCode
     */
     public static List<WorkOrder> selectAssetProductCodesByIds(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        // List<Id> must stay typed. whereIn(List<Object>) binds as ANY and is rejected for Id columns.
        return (List<WorkOrder>) new WorkOrdersSelector()
            .selectFields(new List<String>{ 'Id', 'Asset.Product2.ProductCode' })
            .whereField('Id', 'IN', new List<Id>(workOrderIds))
            .execute();
    }

    /**
     * @description GW-4585 - Ship-to and bill-to address accounts for Oracle pricing on a Work Order.
     * @param workOrderId Work Order Id
     * @return Work Order with address account lookups, or null
     */
    public static WorkOrder selectPricingFrameworkAccountOverrides(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }
        List<WorkOrder> workOrders = [
            SELECT Id, AccountId, ShipToAddressAccount__c, BillToAddressAccount__c
            FROM WorkOrder
            WHERE Id = :workOrderId
            LIMIT 1
        ];
        return workOrders.isEmpty() ? null : workOrders[0];
    }

    /**
     * @description GW-312 / GW-6191 - Completed child Work Orders of IMS site visits.
     * @param parentWorkOrderIds Site visit Work Order Ids
     * @param ownerId Only child Work Orders owned by this user. Null returns every owner.
     * @return Completed child Work Orders ordered by Work Order Number
     */
    public static List<WorkOrder> selectCompletedChildWorkOrders(Set<Id> parentWorkOrderIds, Id ownerId) {
        if (parentWorkOrderIds == null || parentWorkOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        if (ownerId == null) {
            return [
                SELECT Id, WorkOrderNumber, ParentWorkOrderId, Status, OwnerId, AssetId, Asset.Name, Asset.SerialNumber
                FROM WorkOrder
                WHERE ParentWorkOrderId IN :parentWorkOrderIds
                    AND Status = 'Completed'
                ORDER BY WorkOrderNumber ASC
            ];
        }
        return [
            SELECT Id, WorkOrderNumber, ParentWorkOrderId, Status, OwnerId, AssetId, Asset.Name, Asset.SerialNumber
            FROM WorkOrder
            WHERE ParentWorkOrderId IN :parentWorkOrderIds
                AND Status = 'Completed'
                AND OwnerId = :ownerId
            ORDER BY WorkOrderNumber ASC
        ];
    }

    /**
     * @description GW-5102 - Loads a Work Order for Repair Center quote email reply processing.
     * @param workOrderInput Work Order Id or Work Order Number
     * @return Matching Work Order, or null
     */
    public static WorkOrder selectForQuoteEmailReply(String workOrderInput) {
        if (String.isBlank(workOrderInput)) {
            return null;
        }

        String trimmedInput = workOrderInput.trim();
        Id workOrderId;
        if (PlatformUtilities.isSalesforceId(trimmedInput)) {
            try {
                Id candidateId = Id.valueOf(trimmedInput);
                if (candidateId.getSObjectType() == WorkOrder.SObjectType) {
                    workOrderId = candidateId;
                }
            } catch (Exception ignored) {
                workOrderId = null;
            }
        }

        List<WorkOrder> workOrders = (List<WorkOrder>) SoqlQueryBuilder.fromObject('WorkOrder')
            .selectFields(
                new List<String>{
                    'Id',
                    'WorkOrderNumber',
                    'RecordType.DeveloperName',
                    'Status',
                    'SubStatus__c',
                    'ParentWorkOrderId',
                    'ActiveQuote__c',
                    'CurrencyIsoCode',
                    'Pricebook2Id',
                    'CustomerPORequired__c',
                    'CustomerPO__c',
                    'AccountId',
                    'Account.Name',
                    'ContactId',
                    'Contact.Email',
                    'EstimateContact__c',
                    'EstimateContact__r.Email',
                    'EstimateContact__r.Name'
                }
            )
            .whereEquals('Id', workOrderId)
            .whereEquals('WorkOrderNumber', trimmedInput)
            .withFilterLogic('1 OR 2')
            .orderByDesc('CreatedDate')
            .limitTo(1)
            .execute();
        return workOrders.isEmpty() ? null : workOrders[0];
    }

    /**
     * @description GW-5102 - Child Work Orders with an Active Quote under the given parents.
     * @param parentWorkOrderIds Parent Work Order Ids
     * @return Matching child Work Orders
     */
    public static List<WorkOrder> selectChildrenWithActiveQuoteByParentIds(Set<Id> parentWorkOrderIds) {
        if (parentWorkOrderIds == null || parentWorkOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }

        return [
            SELECT
                Id,
                WorkOrderNumber,
                Status,
                SubStatus__c,
                ParentWorkOrderId,
                ActiveQuote__c,
                CurrencyIsoCode,
                Pricebook2Id,
                CustomerPORequired__c,
                CustomerPO__c,
                AccountId,
                Account.Name,
                ContactId,
                Contact.Email,
                EstimateContact__c,
                EstimateContact__r.Email,
                EstimateContact__r.Name
            FROM WorkOrder
            WHERE ParentWorkOrderId IN :parentWorkOrderIds
                AND ActiveQuote__c != NULL
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
        ];
    }

/**
     * @description GW-5333 - Selects Work Orders for Approve/Reject Quote, including Active Quote.
     * @param workOrderIds Work Order Ids
     * @return Matching Work Order rows
     */
    public static List<WorkOrder> selectForApproveRejectQuoteByIds(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }

        return [
            SELECT
                Id,
                WorkOrderNumber,
                CurrencyIsoCode,
                Pricebook2Id,
                ParentWorkOrderId,
                TurnTime__c,
                ScheduledShipDate__c,
                ActiveQuote__c
            FROM WorkOrder
            WHERE Id IN :workOrderIds
            WITH SYSTEM_MODE
        ];
    }

    /**
     * @description Vendor Work Order already created for this Return Order and vendor.
     *              Used when another Other (Non-Serialized) item is received for the same vendor.
     * @param returnOrderId Return Order Id
     * @param vendorAccountId Vendor Account Id
     * @return Matching Vendor Work Order, or null
     */
    public static WorkOrder selectReceivingVendorWorkOrder(Id returnOrderId, Id vendorAccountId) {
        if (returnOrderId == null || vendorAccountId == null) {
            return null;
        }
        return (WorkOrder) new WorkOrdersSelector()
            .selectFields(
                new List<String>{
                    'Id',
                    'InstructionsToVendor__c',
                    'Vendor__c',
                    'IsPriorityRepair__c'
                }
            )
            .whereEquals('ReturnOrder__c', returnOrderId)
            .whereEquals('Vendor__c', vendorAccountId)
            .whereEquals('ParentWorkOrderId', null)
            // CBMQA: RepairCenterVendor (GW-6359) not present; use Other until Sprint 10.
            .whereEquals('RecordType.DeveloperName', 'RepairCenterOther')
            .orderBy('CreatedDate')
            .first();
    }

    /**
     * @description GW-5492 - Child Work Order statuses for a receiving parent.
     * @param parentWorkOrderId Parent Work Order Id
     * @return Child Work Orders with Status, or an empty list
     */
    public static List<WorkOrder> selectChildStatusesForReceiving(Id parentWorkOrderId) {
        if (parentWorkOrderId == null) {
            return new List<WorkOrder>();
        }
        return (List<WorkOrder>) new WorkOrdersSelector()
            .selectFields(new List<String>{ 'Id', 'Status' })
            .whereEquals('ParentWorkOrderId', parentWorkOrderId)
            .execute();
    }

    /**
     * @description GW-5492 - Parent receiving Work Order for a Return Order (no parent WO).
     * @param returnOrderId Return Order Id
     * @return Parent Work Order Id or null
     */
    public static Id selectReceivingParentWorkOrderId(Id returnOrderId) {
        if (returnOrderId == null) {
            return null;
        }
        WorkOrder parentWorkOrder = (WorkOrder) new WorkOrdersSelector()
            .selectField('Id')
            .whereEquals('ReturnOrder__c', returnOrderId)
            .whereEquals('ParentWorkOrderId', null)
            .orderBy('CreatedDate')
            .first();
        return parentWorkOrder == null ? null : parentWorkOrder.Id;
    }

    /**
     * @description GW-4348 / GW-5996 - Work Order number for Create Order confirmation.
     * @param workOrderId Work Order Id
     * @return Work Order with Id and WorkOrderNumber, or null
     */
    public static WorkOrder selectWorkOrderNumberById(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }
        return (WorkOrder) new WorkOrdersSelector()
            .selectFields(new List<String>{ 'Id', 'WorkOrderNumber' })
            .whereEquals('Id', workOrderId)
            .first();
    }

    /**
     * @description GW-5492 - Counts Work Orders linked to a Return Order.
     * @param returnOrderId Return Order Id
     * @return Count
     */
    public static Integer countByReturnOrderId(Id returnOrderId) {
        if (returnOrderId == null) {
            return 0;
        }
        return new WorkOrdersSelector()
            .whereEquals('ReturnOrder__c', returnOrderId)
            .count();
    }

    /**
     * @description GW-3377 - Own and parent Active Quote GrandTotal for the requote gate.
     * @param workOrderId Work Order Id
     * @return The Work Order, or an empty list when the Id is null
     */
    public static List<WorkOrder> selectActiveQuoteGrandTotalById(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WorkOrder>();
        }
        return (List<WorkOrder>) new WorkOrdersSelector()
            .selectFields(new List<String>{
                'ParentWorkOrderId',
                'ActiveQuote__r.GrandTotal',
                'ParentWorkOrder.ActiveQuote__r.GrandTotal'
            })
            .whereEquals('Id', workOrderId)
            .limitTo(1)
            .execute();
    }

    /**
     * @description GW-3458 - Shipped work orders for an asset, newest completion first.
     *              Used by the Modifier Reason Code and Order Reference dropdowns.
     * @param assetId Asset whose prior repairs are requested
     * @return Work orders with an Actual Ship Date, ordered by Completed Timestamp descending
     */
    public static List<WorkOrder> selectShippedByAsset(Id assetId) {
        if (assetId == null) {
            return new List<WorkOrder>();
        }
        return (List<WorkOrder>) new WorkOrdersSelector()
            .selectFields(new List<String>{
                'Id',
                'WorkOrderNumber',
                'AssetId',
                'ActualShipDate__c',
                'CompletedTimestamp__c'
            })
            .whereEquals('AssetId', assetId)
            .whereField('ActualShipDate__c', '!=', null)
            .orderBy('CompletedTimestamp__c', true, true)
            .orderByDesc('ActualShipDate__c')
            .limitTo(200)
            .execute();
    }

    /**
     * @description GW-3458 - Loads a work order chosen as a modifier reason or order reference.
     * @param workOrderId Work Order Id
     * @return Matching work order, or an empty list
     */
    public static List<WorkOrder> selectForModifierReference(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WorkOrder>();
        }
        return (List<WorkOrder>) new WorkOrdersSelector()
            .selectFields(new List<String>{ 'Id', 'AssetId', 'ActualShipDate__c', 'WorkOrderNumber' })
            .whereEquals('Id', workOrderId)
            .limitTo(1)
            .execute();
    }

    /**
     * @description GW-1509 - Work Order fields for Create Return Order launch context.
     * @param workOrderId Work Order Id
     * @return Matching WorkOrder rows (LIMIT 1)
     */
    public static List<WorkOrder> selectForCreateReturnOrderContext(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WorkOrder>();
        }
        return (List<WorkOrder>) SoqlQueryBuilder.fromObject('WorkOrder')
            .selectFields(
                new List<String>{
                    'AccountId',
                    'ContactId',
                    'Contact.Name',
                    'AssetId',
                    'WorkOrderNumber',
                    'RecordType.DeveloperName'
                }
            )
            .whereEquals('Id', workOrderId)
            .limitTo(1)
            .execute();
    }


    /**
     * @description GW-5492 - Work Order fields needed when creating receiving WOLIs.
     *              Note: SoqlQueryBuilder/DynamicSoqlQuery runs USER_MODE. Callers that previously
     *              relied on SYSTEM_MODE for same-transaction Pricebook2Id visibility may need review.
     * @param workOrderId Work Order Id
     * @return Matching Work Order rows (LIMIT 1)
     */
    public static List<WorkOrder> selectByIdForReceivingWoliCreate(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WorkOrder>();
        }
        return (List<WorkOrder>) SoqlQueryBuilder.fromObject('WorkOrder')
            .selectFields(
                new List<String>{
                    'Pricebook2Id',
                    'CurrencyIsoCode',
                    'AssetId',
                    'SerialNumber__c',
                    'Model__c',
                    'EstimateRequired__c'
                }
            )
            .whereEquals('Id', workOrderId)
            .limitTo(1)
            .execute();
    }

    /**
     * @description GW-1738 / GW-2001 - Work Order AssetId for billing type evaluation.
     * @param workOrderId Work Order Id
     * @return Matching Work Order rows (LIMIT 1)
     */
    public static List<WorkOrder> selectAssetIdById(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WorkOrder>();
        }
        return (List<WorkOrder>) SoqlQueryBuilder.fromObject('WorkOrder')
            .selectFields(new List<String>{ 'Id', 'AssetId' })
            .whereEquals('Id', workOrderId)
            .limitTo(1)
            .execute();
    }
}