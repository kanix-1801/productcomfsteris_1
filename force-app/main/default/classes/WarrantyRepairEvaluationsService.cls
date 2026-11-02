/**
 * @description Service for WarrantyRepairEvaluation__c — Device Evaluation WRE panel (GW-3891).
 */
public with sharing class WarrantyRepairEvaluationsService {
    private static final String WRE_RECORD_TYPE_REPAIR_CENTER = 'RepairCenter';
    private static final String WO_RECORD_TYPE_REPAIR_CENTER_DEVICES = 'RepairCenterDevices';
    private static final String WO_RECORD_TYPE_REPAIR_CENTER_INSTRUMENTS = 'RepairCenterInstruments';
    private static final String WO_ASSIGNMENT_TYPE_TECHNICIAN = 'Technician';
    private static final String YES_VALUE = 'Yes';

    public class WarrantyRepairEvaluationsServiceException extends Exception {
    }

    public class PreviousRepairContext {
        public Id technicianId;
        public Date repairDate;
        public String originalReturnOrder;
        public String previousWorkPerformed;
    }

    /**
     * @description Returns related-list rows for the Work Order.
     */
    public static List<WarrantyRepairEvaluation__c> getEvaluationsByWorkOrderId(Id workOrderId) {
        return getEvaluationsByWorkOrderId(workOrderId, null);
    }

    /**
     * @description Returns related-list rows for the Work Order, optionally scoped to a Product Serviced WOLI.
     * @param workOrderId Parent Work Order Id
     * @param workOrderLineItemId Optional Product Serviced WOLI Id (GW-3400)
     */
    public static List<WarrantyRepairEvaluation__c> getEvaluationsByWorkOrderId(
        Id workOrderId,
        Id workOrderLineItemId
    ) {
        if (workOrderId == null) {
            return new List<WarrantyRepairEvaluation__c>();
        }
        try {
            return WarrantyRepairEvaluationsSelector.selectByWorkOrderId(
                workOrderId,
                workOrderLineItemId
            );
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WarrantyRepairEvaluationsService.getEvaluationsByWorkOrderId failed for {0}',
                    workOrderId
                ),
                e
            );
            throw new WarrantyRepairEvaluationsServiceException(
                'Unable to load Warranty Repair Evaluations.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-4502 - Users may not delete Product Serviced lines that have a saved WRE.
     * @param workOrderLineItemIds Product Serviced Work Order Line Item Ids
     */
    public static void assertNoEvaluationsLinkedToWorkOrderLineItems(Set<Id> workOrderLineItemIds) {
        if (workOrderLineItemIds == null || workOrderLineItemIds.isEmpty()) {
            return;
        }
        List<WarrantyRepairEvaluation__c> evaluations = [
            SELECT Id
            FROM WarrantyRepairEvaluation__c
            WHERE WorkOrderLineItem__c IN :workOrderLineItemIds
            WITH USER_MODE
            LIMIT 1
        ];
        if (!evaluations.isEmpty()) {
            throw new WarrantyRepairEvaluationsServiceException(
                'This item cannot be deleted because it has a Warranty Repair Evaluation.'
            );
        }
    }

    /**
     * @description GW-3400 - Deletes Warranty Repair Evaluations linked to Product Serviced WOLIs.
     * @param workOrderLineItemIds Product Serviced Work Order Line Item Ids
     */
    public static void deleteByWorkOrderLineItemIds(Set<Id> workOrderLineItemIds) {
        if (workOrderLineItemIds == null || workOrderLineItemIds.isEmpty()) {
            return;
        }
        try {
            List<WarrantyRepairEvaluation__c> evaluations = [
                SELECT Id
                FROM WarrantyRepairEvaluation__c
                WHERE WorkOrderLineItem__c IN :workOrderLineItemIds
                WITH USER_MODE
            ];
            if (!evaluations.isEmpty()) {
                delete evaluations;
            }
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WarrantyRepairEvaluationsService.deleteByWorkOrderLineItemIds failed: {0}',
                    e.getMessage()
                ),
                e
            );
            throw new WarrantyRepairEvaluationsServiceException(
                'Unable to delete Warranty Repair Evaluations for the removed item.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Builds a new or existing evaluation form shell for the LWC.
     */
    public static WarrantyRepairEvaluation__c buildEvaluationForForm(
        Id workOrderId,
        Id recordId
    ) {
        return buildEvaluationForForm(workOrderId, recordId, null);
    }

    /**
     * @description Builds a new or existing evaluation form shell for the LWC.
     * @param workOrderId Parent Work Order Id
     * @param recordId Existing WRE Id when editing; null for New
     * @param workOrderLineItemId Optional Product Serviced WOLI to stamp/seed (GW-3400)
     */
    public static WarrantyRepairEvaluation__c buildEvaluationForForm(
        Id workOrderId,
        Id recordId,
        Id workOrderLineItemId
    ) {
        if (workOrderId == null) {
            throw new WarrantyRepairEvaluationsServiceException('Work Order is required.');
        }

        WorkOrder workOrder = WorkOrdersSelector.selectForWarrantyRepairEvaluationById(workOrderId);
        if (workOrder == null) {
            throw new WarrantyRepairEvaluationsServiceException('Work Order was not found.');
        }

        WarrantyRepairEvaluation__c evaluation;
        if (recordId != null) {
            evaluation = WarrantyRepairEvaluationsSelector.selectByIdForWorkOrder(
                recordId,
                workOrderId
            );
            if (evaluation == null) {
                throw new WarrantyRepairEvaluationsServiceException(
                    'Warranty Repair Evaluation was not found for this Work Order.'
                );
            }
            return evaluation;
        }

        PreviousRepairContext previousRepair = resolvePreviousRepairContext(workOrder);
        evaluation = new WarrantyRepairEvaluation__c();
        evaluation.WorkOrder__c = workOrder.Id;
        evaluation.WorkOrderLineItem__c = workOrderLineItemId;
        evaluation.ParentWorkOrder__c = workOrder.ParentWorkOrderId;
        evaluation.RelatedReturnOrder__c = workOrder.ReturnOrder__c;
        evaluation.CustomerNumber__c =
            workOrder.Account != null ? workOrder.Account.AccountNumber : null;
        evaluation.DateReceived__c = workOrder.CreatedDate.date();
        evaluation.ItemCount__c = workOrder.QuantityReceived__c;
        evaluation.ReasonForReturn__c = workOrder.Description;
        evaluation.OriginalReturnOrder__c = String.isNotBlank(previousRepair.originalReturnOrder)
            ? previousRepair.originalReturnOrder
            : workOrder.PreviousReturnOrder__c;
        evaluation.PreviousRepairQCTechnician__c = previousRepair.technicianId;
        evaluation.PreviousRepairDate__c = previousRepair.repairDate;
        evaluation.PreviousWorkPerformed__c = previousRepair.previousWorkPerformed;
        evaluation.DeviceType__c = resolveDeviceType(workOrder);
        evaluation.ManufacturerOfTheDeviceInstrument__c = resolveManufacturer(workOrder);
        evaluation.ModelNumberOfTheDeviceInstrument__c = resolveModel(workOrder);
        evaluation.SerialNumberOfTheDeviceInstrument__c = resolveSerialNumber(workOrder);
        evaluation.TechnicianPerformingWork__c = UserInfo.getUserId();
        evaluation.Date__c = Date.today();
        evaluation.RecordTypeId = getRepairCenterRecordTypeId();
        applyProductServicedDefaults(evaluation, workOrderLineItemId);
        return evaluation;
    }

    /**
     * @description Validates and upserts a Warranty Repair Evaluation, then returns refreshed rows.
     */
    public static List<WarrantyRepairEvaluation__c> saveEvaluation(
        WarrantyRepairEvaluation__c evaluation
    ) {
        if (evaluation == null) {
            throw new WarrantyRepairEvaluationsServiceException('Work Order is required.');
        }

        Id workOrderId = resolveWorkOrderIdForSave(evaluation);
        if (workOrderId == null) {
            throw new WarrantyRepairEvaluationsServiceException('Work Order is required.');
        }

        validateRequiredFields(evaluation, workOrderId);

        Id workOrderLineItemId = evaluation.WorkOrderLineItem__c;
        try {
            if (evaluation.Id == null) {
                evaluation.WorkOrder__c = workOrderId;
                if (evaluation.RecordTypeId == null) {
                    evaluation.RecordTypeId = getRepairCenterRecordTypeId();
                }
                insert evaluation;
            } else {
                update buildUpdatePayload(evaluation);
            }
            return WarrantyRepairEvaluationsSelector.selectByWorkOrderId(
                workOrderId,
                workOrderLineItemId
            );
        } catch (DmlException e) {
            Logger.error('WarrantyRepairEvaluationsService.saveEvaluation DML', e);
            throw new WarrantyRepairEvaluationsServiceException(
                'Unable to save Warranty Repair Evaluation: ' + e.getDmlMessage(0),
                e
            );
        } catch (Exception e) {
            Logger.error('WarrantyRepairEvaluationsService.saveEvaluation failed', e);
            throw new WarrantyRepairEvaluationsServiceException(
                'Unable to save Warranty Repair Evaluation: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    @TestVisible
    private static PreviousRepairContext resolvePreviousRepairContext(WorkOrder workOrder) {
        PreviousRepairContext context = new PreviousRepairContext();
        if (workOrder == null || workOrder.AssetId == null) {
            return context;
        }

        Id priorRecordTypeId = resolvePriorRepairWorkOrderRecordTypeId(workOrder);
        if (priorRecordTypeId == null) {
            return context;
        }

        WorkOrder previousWorkOrder = WorkOrdersSelector.selectMostRecentRepairCenterWorkOrderByAsset(
            workOrder.AssetId,
            workOrder.Id,
            priorRecordTypeId
        );
        if (previousWorkOrder == null) {
            return context;
        }

        context.repairDate = previousWorkOrder.ActualShipDate__c;
        List<WOAssignmentHistory__c> assignments =
            WOAssignmentHistoriesSelector.selectMostRecentClosedByWorkOrderIdAndType(
                previousWorkOrder.Id,
                WO_ASSIGNMENT_TYPE_TECHNICIAN
            );
        if (!assignments.isEmpty()) {
            context.technicianId = assignments[0].Technician__c;
        }
        context.originalReturnOrder = resolveOriginalReturnOrderFromWorkOrder(previousWorkOrder);
        context.previousWorkPerformed = buildPreviousWorkPerformedDescription(previousWorkOrder.Id);
        return context;
    }

    /**
     * @description Master-detail WorkOrder__c is insert-only. Updates resolve the parent Id from the row.
     */
    @TestVisible
    private static Id resolveWorkOrderIdForSave(WarrantyRepairEvaluation__c evaluation) {
        if (evaluation == null) {
            return null;
        }
        if (evaluation.Id == null) {
            return evaluation.WorkOrder__c;
        }
        List<WarrantyRepairEvaluation__c> existingRows = [
            SELECT WorkOrder__c
            FROM WarrantyRepairEvaluation__c
            WHERE Id = :evaluation.Id
            WITH USER_MODE
            LIMIT 1
        ];
        return existingRows.isEmpty() ? null : existingRows[0].WorkOrder__c;
    }

    @TestVisible
    private static WarrantyRepairEvaluation__c buildUpdatePayload(
        WarrantyRepairEvaluation__c evaluation
    ) {
        return new WarrantyRepairEvaluation__c(
            Id = evaluation.Id,
            WorkOrderLineItem__c = evaluation.WorkOrderLineItem__c,
            ParentWorkOrder__c = evaluation.ParentWorkOrder__c,
            RelatedReturnOrder__c = evaluation.RelatedReturnOrder__c,
            CustomerNumber__c = evaluation.CustomerNumber__c,
            DateReceived__c = evaluation.DateReceived__c,
            ItemCount__c = evaluation.ItemCount__c,
            ReasonForReturn__c = evaluation.ReasonForReturn__c,
            SignsOfDamageWearFailure__c = evaluation.SignsOfDamageWearFailure__c,
            OriginalReturnOrder__c = evaluation.OriginalReturnOrder__c,
            PreviousRepairQCTechnician__c = evaluation.PreviousRepairQCTechnician__c,
            PreviousRepairDate__c = evaluation.PreviousRepairDate__c,
            DeviceType__c = evaluation.DeviceType__c,
            ManufacturerOfTheDeviceInstrument__c = evaluation.ManufacturerOfTheDeviceInstrument__c,
            ModelNumberOfTheDeviceInstrument__c = evaluation.ModelNumberOfTheDeviceInstrument__c,
            SerialNumberOfTheDeviceInstrument__c = evaluation.SerialNumberOfTheDeviceInstrument__c,
            Disposition__c = evaluation.Disposition__c,
            ConfirmedCustomerReportedIssue__c = evaluation.ConfirmedCustomerReportedIssue__c,
            IssueRelatedToPreviousRepair__c = evaluation.IssueRelatedToPreviousRepair__c,
            PreviousWorkPerformed__c = evaluation.PreviousWorkPerformed__c,
            WorkPerformedAndRecommendation__c = evaluation.WorkPerformedAndRecommendation__c,
            TechnicianPerformingWork__c = evaluation.TechnicianPerformingWork__c,
            Date__c = evaluation.Date__c,
            TeamLeader__c = evaluation.TeamLeader__c,
            TeamLeaderSignOff__c = evaluation.TeamLeaderSignOff__c,
            Autoclaved__c = evaluation.Autoclaved__c,
            CorrectiveActionTaken__c = evaluation.CorrectiveActionTaken__c,
            CorrectiveActionAdditionalDetails__c = evaluation.CorrectiveActionAdditionalDetails__c,
            ContributingFactor__c = evaluation.ContributingFactor__c,
            ComponentNCRCreated__c = evaluation.ComponentNCRCreated__c,
            NCRNumber__c = evaluation.NCRNumber__c,
            PartNumber__c = evaluation.PartNumber__c,
            LotNumber__c = evaluation.LotNumber__c
        );
    }

    /**
     * @description Prefer Product Serviced WOLI values when WO Asset defaults are blank (IE path).
     */
    @TestVisible
    private static void applyProductServicedDefaults(
        WarrantyRepairEvaluation__c evaluation,
        Id workOrderLineItemId
    ) {
        if (evaluation == null || workOrderLineItemId == null) {
            return;
        }
        WorkOrderLineItem lineItem =
            WorkOrderLineItemsSelector.selectForWarrantyRepairEvaluationById(workOrderLineItemId);
        if (lineItem == null) {
            return;
        }
        evaluation.WorkOrderLineItem__c = lineItem.Id;
        evaluation.ItemCount__c = 1;
        if (String.isBlank(evaluation.DeviceType__c) && lineItem.Product2 != null) {
            evaluation.DeviceType__c = String.isNotBlank(lineItem.Product2.DeviceType__c)
                ? lineItem.Product2.DeviceType__c
                : lineItem.Product2.ProductLine__c;
        }
        if (
            String.isBlank(evaluation.ManufacturerOfTheDeviceInstrument__c) &&
            lineItem.Product2 != null
        ) {
            evaluation.ManufacturerOfTheDeviceInstrument__c = lineItem.Product2.Manufacturer__c;
        }
        if (String.isBlank(evaluation.ModelNumberOfTheDeviceInstrument__c)) {
            if (lineItem.Product2 != null && String.isNotBlank(lineItem.Product2.Model__c)) {
                evaluation.ModelNumberOfTheDeviceInstrument__c = lineItem.Product2.Model__c;
            } else if (String.isNotBlank(lineItem.ProductDescription__c)) {
                evaluation.ModelNumberOfTheDeviceInstrument__c = lineItem.ProductDescription__c;
            }
        }
        if (
            String.isBlank(evaluation.SerialNumberOfTheDeviceInstrument__c) &&
            String.isNotBlank(lineItem.SerialNumber__c)
        ) {
            evaluation.SerialNumberOfTheDeviceInstrument__c = lineItem.SerialNumber__c;
        }
    }

    @TestVisible
    private static void validateRequiredFields(
        WarrantyRepairEvaluation__c evaluation,
        Id workOrderId
    ) {
        List<String> missing = new List<String>();
        WorkOrder workOrder = WorkOrdersSelector.selectForWarrantyRepairEvaluationById(workOrderId);
        String deviceTypeLabel = resolveDeviceTypeFieldLabel(evaluation, workOrder);
        requireField(evaluation.ReasonForReturn__c, 'Describe Reason for Return', missing);
        requireField(
            evaluation.SignsOfDamageWearFailure__c,
            'Signs of Damage, Excessive Wear, Component Failure or Process Failure',
            missing
        );
        Boolean requireAssetBasedPreviousRepairFields = requiresAssetBasedPreviousRepairFields(
            workOrder
        );
        if (requireAssetBasedPreviousRepairFields) {
            requireField(evaluation.OriginalReturnOrder__c, 'Original Return Order', missing);
            requireField(
                evaluation.PreviousRepairQCTechnician__c,
                'Previous Repair/QC Technician',
                missing
            );
            requireField(evaluation.PreviousRepairDate__c, 'Previous Repair Date', missing);
        }
        requireField(evaluation.DeviceType__c, deviceTypeLabel, missing);
        requireField(
            evaluation.ManufacturerOfTheDeviceInstrument__c,
            'Manufacturer of the Device/Instrument',
            missing
        );
        requireField(
            evaluation.ModelNumberOfTheDeviceInstrument__c,
            'Model Number of the Device/Instrument',
            missing
        );
        if (requireAssetBasedPreviousRepairFields) {
            requireField(
                evaluation.SerialNumberOfTheDeviceInstrument__c,
                'Serial Number of the Device/Instrument',
                missing
            );
        }
        requireField(evaluation.Disposition__c, 'Disposition', missing);
        requireField(
            evaluation.ConfirmedCustomerReportedIssue__c,
            'Did the lab confirm the Customer\'s reported issue?',
            missing
        );
        requireField(
            evaluation.IssueRelatedToPreviousRepair__c,
            'Was the issue related to the previous repair in any way?',
            missing
        );
        if (requireAssetBasedPreviousRepairFields) {
            requireField(
                evaluation.PreviousWorkPerformed__c,
                'Describe work performed to address the issue (Previous Repair)',
                missing
            );
        }
        requireField(
            evaluation.WorkPerformedAndRecommendation__c,
            'Describe work performed to address the issue (Evaluation/Repair Recommendation)',
            missing
        );
        requireField(
            evaluation.TechnicianPerformingWork__c,
            'Technician Performing Work',
            missing
        );
        requireField(evaluation.Date__c, 'Technician Sign-Off Date', missing);
        requireField(evaluation.Autoclaved__c, 'Autoclaved', missing);
        requireField(
            evaluation.CorrectiveActionTaken__c,
            'Were there any corrective action(s) implemented, and/or in process?',
            missing
        );
        requireField(
            evaluation.ContributingFactor__c,
            'Select one of the following as a contributing factor',
            missing
        );
        requireField(evaluation.ComponentNCRCreated__c, 'Component NCR Created', missing);

        if (YES_VALUE.equals(evaluation.CorrectiveActionTaken__c)) {
            requireField(
                evaluation.CorrectiveActionAdditionalDetails__c,
                'If yes, please provide additional detail (could include but not limited to work instruction updates, training, etc.)',
                missing
            );
        }
        if (YES_VALUE.equals(evaluation.ComponentNCRCreated__c)) {
            requireField(evaluation.NCRNumber__c, 'NCR Number', missing);
            requireField(evaluation.PartNumber__c, 'Part Number', missing);
        }

        if (!missing.isEmpty()) {
            String message = missing.size() == 1
                ? 'Please complete the required field: ' + missing[0]
                : 'Please complete the following required fields: ' +
                  String.join(missing, '; ');
            throw new WarrantyRepairEvaluationsServiceException(message);
        }
    }

    private static void requireField(Object value, String label, List<String> missing) {
        if (value == null || (value instanceof String && String.isBlank((String) value))) {
            missing.add(label);
        }
    }

    /**
     * @description Josh / GW-4502 — Original Return Order, Previous Repair/QC Technician,
     *              Previous Repair Date, Serial Number, and Previous Work Performed are required
     *              only when the Work Order has an Asset (Instrument asset path and Device Eval).
     */
    @TestVisible
    private static Boolean requiresAssetBasedPreviousRepairFields(WorkOrder workOrder) {
        return workOrder != null && workOrder.AssetId != null;
    }

    @TestVisible
    private static String resolveDeviceType(WorkOrder workOrder) {
        if (workOrder == null) {
            return null;
        }
        if (
            workOrder.Asset != null &&
            workOrder.Asset.Product2 != null &&
            String.isNotBlank(workOrder.Asset.Product2.DeviceType__c)
        ) {
            return workOrder.Asset.Product2.DeviceType__c;
        }
        if (String.isNotBlank(workOrder.ProductLine_f__c)) {
            return workOrder.ProductLine_f__c;
        }
        if (workOrder.Asset != null && String.isNotBlank(workOrder.Asset.ProductLineCalculated__c)) {
            return workOrder.Asset.ProductLineCalculated__c;
        }
        if (
            workOrder.Asset != null &&
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
        return workOrder.Asset.Product2 != null
            ? workOrder.Asset.Product2.Manufacturer__c
            : null;
    }

    @TestVisible
    private static String resolveModel(WorkOrder workOrder) {
        if (workOrder == null || workOrder.Asset == null) {
            return null;
        }
        if (String.isNotBlank(workOrder.Asset.ModelCalculated__c)) {
            return workOrder.Asset.ModelCalculated__c;
        }
        return workOrder.Asset.Product2 != null ? workOrder.Asset.Product2.Model__c : null;
    }

    @TestVisible
    private static String resolveSerialNumber(WorkOrder workOrder) {
        if (workOrder == null) {
            return null;
        }
        return workOrder.Asset != null ? workOrder.Asset.SerialNumber : null;
    }

    @TestVisible
    private static String resolveDeviceTypeFieldLabel(
        WarrantyRepairEvaluation__c evaluation,
        WorkOrder workOrder
    ) {
        Boolean instrumentItemContext =
            evaluation != null &&
            evaluation.WorkOrderLineItem__c != null &&
            workOrder != null &&
            workOrder.AssetId == null;
        return instrumentItemContext ? 'Instrument Type' : 'Device Type';
    }

    @TestVisible
    private static String resolveOriginalReturnOrderFromWorkOrder(WorkOrder workOrder) {
        if (workOrder == null) {
            return null;
        }
        if (
            workOrder.ReturnOrder__r != null &&
            String.isNotBlank(workOrder.ReturnOrder__r.ReturnOrderNumber)
        ) {
            return workOrder.ReturnOrder__r.ReturnOrderNumber;
        }
        return workOrder.PreviousReturnOrder__c;
    }

    @TestVisible
    private static String buildPreviousWorkPerformedDescription(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }
        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        if (repairCodeRtId == null) {
            return null;
        }
        List<WorkOrderLineItem> lines = [
            SELECT
                ProductDescription__c,
                Product2.Description,
                Product2.ProductType__c,
                Product__r.Description,
                Product__r.ProductType__c
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId AND RecordTypeId = :repairCodeRtId
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ];
        List<String> descriptions = new List<String>();
        for (WorkOrderLineItem line : lines) {
            String productType = line.Product2 != null ? line.Product2.ProductType__c : null;
            if (productType == null && line.Product__r != null) {
                productType = line.Product__r.ProductType__c;
            }
            if (productType == 'Category Code' || productType == 'Service Code') {
                String description = resolveRepairCodeLineDescription(line);
                if (String.isNotBlank(description)) {
                    descriptions.add(description);
                }
            }
        }
        return descriptions.isEmpty() ? null : String.join(descriptions, '\n');
    }

    @TestVisible
    private static String resolveRepairCodeLineDescription(WorkOrderLineItem line) {
        if (line == null) {
            return null;
        }
        if (String.isNotBlank(line.ProductDescription__c)) {
            return line.ProductDescription__c;
        }
        if (line.Product2 != null && String.isNotBlank(line.Product2.Description)) {
            return line.Product2.Description;
        }
        if (line.Product__r != null && String.isNotBlank(line.Product__r.Description)) {
            return line.Product__r.Description;
        }
        return null;
    }

    @TestVisible
    private static Id resolvePriorRepairWorkOrderRecordTypeId(WorkOrder workOrder) {
        if (workOrder == null || workOrder.RecordType == null) {
            return null;
        }
        String recordTypeDeveloperName = workOrder.RecordType.DeveloperName;
        if (recordTypeDeveloperName == WO_RECORD_TYPE_REPAIR_CENTER_INSTRUMENTS) {
            return getRepairCenterInstrumentsRecordTypeId();
        }
        if (recordTypeDeveloperName == WO_RECORD_TYPE_REPAIR_CENTER_DEVICES) {
            return getRepairCenterDevicesRecordTypeId();
        }
        return null;
    }

    private static Id getRepairCenterRecordTypeId() {
        Schema.RecordTypeInfo recordType = Schema.SObjectType.WarrantyRepairEvaluation__c.getRecordTypeInfosByDeveloperName()
            .get(WRE_RECORD_TYPE_REPAIR_CENTER);
        return recordType != null ? recordType.getRecordTypeId() : null;
    }

    private static Id getRepairCenterDevicesRecordTypeId() {
        Schema.RecordTypeInfo recordType = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get(WO_RECORD_TYPE_REPAIR_CENTER_DEVICES);
        return recordType != null ? recordType.getRecordTypeId() : null;
    }

    private static Id getRepairCenterInstrumentsRecordTypeId() {
        Schema.RecordTypeInfo recordType = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get(WO_RECORD_TYPE_REPAIR_CENTER_INSTRUMENTS);
        return recordType != null ? recordType.getRecordTypeId() : null;
    }
}