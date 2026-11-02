/**
 * @description Selector for WarrantyRepairEvaluation__c (GW-3891 Device Evaluation).
 */
public with sharing class WarrantyRepairEvaluationsSelector {
    private static final String WRE_DETAIL_FIELD_LIST =
        'Id, Name, WorkOrder__c, WorkOrderLineItem__c, ParentWorkOrder__c, ParentWorkOrder__r.WorkOrderNumber, ' +
        'RelatedReturnOrder__c, RelatedReturnOrder__r.ReturnOrderNumber, ' +
        'CustomerNumber__c, DateReceived__c, ItemCount__c, ReasonForReturn__c, ' +
        'SignsOfDamageWearFailure__c, OriginalReturnOrder__c, PreviousRepairQCTechnician__c, ' +
        'PreviousRepairDate__c, DeviceType__c, ManufacturerOfTheDeviceInstrument__c, ' +
        'ModelNumberOfTheDeviceInstrument__c, SerialNumberOfTheDeviceInstrument__c, ' +
        'Disposition__c, ConfirmedCustomerReportedIssue__c, IssueRelatedToPreviousRepair__c, ' +
        'PreviousWorkPerformed__c, WorkPerformedAndRecommendation__c, TechnicianPerformingWork__c, ' +
        'Date__c, TeamLeader__c, TeamLeaderSignOff__c, Autoclaved__c, CorrectiveActionTaken__c, ' +
        'CorrectiveActionAdditionalDetails__c, ContributingFactor__c, ComponentNCRCreated__c, ' +
        'NCRNumber__c, PartNumber__c, LotNumber__c, RecordTypeId';

    /**
     * @description Related-list rows for a Work Order, optionally scoped to a Product Serviced WOLI.
     */
    public static List<WarrantyRepairEvaluation__c> selectByWorkOrderId(Id workOrderId) {
        return selectByWorkOrderId(workOrderId, null);
    }

    /**
     * @description Related-list rows for a Work Order, optionally scoped to a Product Serviced WOLI.
     * @param workOrderId Parent Work Order Id
     * @param workOrderLineItemId Optional Product Serviced WOLI filter (GW-3400 / GW-3891)
     */
    public static List<WarrantyRepairEvaluation__c> selectByWorkOrderId(
        Id workOrderId,
        Id workOrderLineItemId
    ) {
        if (workOrderId == null) {
            return new List<WarrantyRepairEvaluation__c>();
        }
        if (workOrderLineItemId == null) {
            return [
                SELECT
                    Id,
                    Name,
                    WorkOrderLineItem__c,
                    Disposition__c,
                    Date__c,
                    TechnicianPerformingWork__r.Name
                FROM WarrantyRepairEvaluation__c
                WHERE WorkOrder__c = :workOrderId
                WITH USER_MODE
                ORDER BY CreatedDate DESC
            ];
        }
        return [
            SELECT
                Id,
                Name,
                WorkOrderLineItem__c,
                Disposition__c,
                Date__c,
                TechnicianPerformingWork__r.Name
            FROM WarrantyRepairEvaluation__c
            WHERE WorkOrder__c = :workOrderId
                AND WorkOrderLineItem__c = :workOrderLineItemId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
        ];
    }

    /**
     * @description Single evaluation for edit, scoped to the owning Work Order.
     */
    public static WarrantyRepairEvaluation__c selectByIdForWorkOrder(Id recordId, Id workOrderId) {
        if (recordId == null || workOrderId == null) {
            return null;
        }
        String soql =
            'SELECT ' +
            WRE_DETAIL_FIELD_LIST +
            ' FROM WarrantyRepairEvaluation__c ' +
            'WHERE Id = :recordId AND WorkOrder__c = :workOrderId LIMIT 1';
        List<WarrantyRepairEvaluation__c> rows = Database.query(soql);
        return rows.isEmpty() ? null : rows[0];
    }
}