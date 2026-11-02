/**
 * @description Aura entry point for the Work Order Repair Order History LWC (GW-1295).
 *              Controllers call WorkOrdersService (not the Selector) per STERIS layering.
 * @author Uptima
 * @date 2026-07-16
 */
public with sharing class WorkOrderRepairHistoryController {
    @TestVisible
    private interface IRepairHistoryClient {
        List<WorkOrder> getWorkOrdersForRepairHistory(Set<Id> workOrderIds);
        List<WorkOrder> getRepairHistoryByAsset(Id assetId, Id excludedWorkOrderId);
    }

    private class DefaultRepairHistoryClient implements IRepairHistoryClient {
        public List<WorkOrder> getWorkOrdersForRepairHistory(Set<Id> workOrderIds) {
            return WorkOrdersService.getWorkOrdersForRepairHistory(workOrderIds);
        }

        public List<WorkOrder> getRepairHistoryByAsset(Id assetId, Id excludedWorkOrderId) {
            return WorkOrdersService.getRepairHistoryByAsset(assetId, excludedWorkOrderId);
        }
    }

    @TestVisible
    private static IRepairHistoryClient facadeOverride;

    private static IRepairHistoryClient repairHistoryClient() {
        return facadeOverride == null ? new DefaultRepairHistoryClient() : facadeOverride;
    }

    /**
     * @description Row DTO for the Repair Order History LWC.
     */
    public class HistoryRow {
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public Date actualShipDate;
        @AuraEnabled public String evaluatorName;
        @AuraEnabled public String recordUrl;
    }

    /**
     * @description Payload for the Work Order record-page / View All LWC.
     */
    public class HistoryListResult {
        /** False when Asset is blank — LWC should render nothing. */
        @AuraEnabled public Boolean isVisible;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public List<HistoryRow> history;
    }

    /**
     * @description GW-1295 - Loads prior Repair Center Work Orders for the Asset on a Work Order.
     *              Visible only when AssetId is populated. Asset-only filter; Actual Ship Date required;
     *              sorted by Actual Ship Date DESC. Evaluation Notes are intentionally omitted for now.
     *              Work Order context and history are loaded via WorkOrdersService (not direct SOQL).
     * @param workOrderId Work Order Id from the record page
     * @return HistoryListResult with visibility flag and history rows
     */
    @AuraEnabled(cacheable=true)
    public static HistoryListResult getRepairHistoryForWorkOrder(Id workOrderId) {
        HistoryListResult result = new HistoryListResult();
        result.isVisible = false;
        result.history = new List<HistoryRow>();

        try {
            if (workOrderId == null) {
                return result;
            }

            List<WorkOrder> workOrders = repairHistoryClient().getWorkOrdersForRepairHistory(
                new Set<Id>{ workOrderId }
            );
            if (workOrders.isEmpty()) {
                return result;
            }

            WorkOrder workOrder = workOrders[0];
            result.workOrderNumber = workOrder.WorkOrderNumber;
            if (workOrder.AssetId == null) {
                return result;
            }

            result.isVisible = true;
            List<WorkOrder> history = repairHistoryClient().getRepairHistoryByAsset(
                workOrder.AssetId,
                workOrder.Id
            );
            result.history = mapHistoryRows(history);
            return result;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrderRepairHistoryController.getRepairHistoryForWorkOrder failed for {0}: {1}',
                    workOrderId,
                    e.getMessage()
                ),
                e
            );
            try {
                Logger.saveLog(Logger.SaveMethod.SYNCHRONOUS_DML);
            } catch (Exception saveEx) {
                Logger.saveLog();
            }
            AuraHandledException auraEx = new AuraHandledException(
                'Unable to load Repair Order History: ' + e.getMessage()
            );
            auraEx.setMessage('Unable to load Repair Order History: ' + e.getMessage());
            throw auraEx;
        }
    }

    private static List<HistoryRow> mapHistoryRows(List<WorkOrder> history) {
        List<HistoryRow> rows = new List<HistoryRow>();
        if (history == null || history.isEmpty()) {
            return rows;
        }
        for (WorkOrder historyWorkOrder : history) {
            HistoryRow row = new HistoryRow();
            row.workOrderId = historyWorkOrder.Id;
            row.workOrderNumber = historyWorkOrder.WorkOrderNumber;
            row.actualShipDate = historyWorkOrder.ActualShipDate__c;
            row.evaluatorName =
                historyWorkOrder.Evaluator__r != null
                    ? historyWorkOrder.Evaluator__r.Name
                    : null;
            row.recordUrl = '/' + historyWorkOrder.Id;
            rows.add(row);
        }
        return rows;
    }
}