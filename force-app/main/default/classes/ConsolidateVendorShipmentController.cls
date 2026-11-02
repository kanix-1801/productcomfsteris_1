/**
 * @description Thin Apex controller for the Consolidate Vendor Shipment LWC (GW-3880).
 *              Delegates init and Complete orchestration to WorkOrdersService and ReturnOrdersService.
 * @author Uptima Development Team
 * @date 2026-09-03
 * @group Controllers
 */
public with sharing class ConsolidateVendorShipmentController {
    @TestVisible
    private interface IConsolidateVendorShipmentClient {
        WorkOrdersService.VendorConsolidationInitResult getVendorWorkOrdersForConsolidation();
        ReturnOrdersService.VendorConsolidationCompleteResult completeVendorShipment(
            List<Id> workOrderIds
        );
    }

    private class DefaultClient implements IConsolidateVendorShipmentClient {
        public WorkOrdersService.VendorConsolidationInitResult getVendorWorkOrdersForConsolidation() {
            return WorkOrdersService.getVendorWorkOrdersForConsolidation();
        }

        public ReturnOrdersService.VendorConsolidationCompleteResult completeVendorShipment(
            List<Id> workOrderIds
        ) {
            return ReturnOrdersService.completeVendorShipment(workOrderIds);
        }
    }

    @TestVisible
    private static IConsolidateVendorShipmentClient clientOverride;

    private static IConsolidateVendorShipmentClient client() {
        return clientOverride == null ? new DefaultClient() : clientOverride;
    }

    public class WorkOrderRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public Id parentWorkOrderId;
        @AuraEnabled public String parentWorkOrderNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String subStatus;
        @AuraEnabled public Id vendorId;
        @AuraEnabled public String vendorName;
        @AuraEnabled public String vendorAddress;
        @AuraEnabled public Boolean hasVendorAddress;
        @AuraEnabled public Id repairCenterId;
        @AuraEnabled public String repairCenterName;
        @AuraEnabled public String customerPo;
        @AuraEnabled public String groupKey;
    }

    public class InitResult {
        @AuraEnabled public Id repairCenterId;
        @AuraEnabled public String repairCenterName;
        @AuraEnabled public Boolean hasRepairCenterAddress;
        @AuraEnabled public List<WorkOrderRow> workOrders;
        @AuraEnabled public String errorMessage;
    }

    public class CompleteResult {
        @AuraEnabled public List<Id> returnOrderIds;
        @AuraEnabled public List<String> returnOrderNumbers;
        @AuraEnabled public Integer workOrderCount;
        @AuraEnabled public String message;
    }

    /**
     * @description Loads Outside Vendor work orders for the running user's Repair Center.
     * @return InitResult with repair center context and Work Order rows
     */
    @AuraEnabled
    public static InitResult getVendorWorkOrders() {
        InitResult result = new InitResult();
        result.workOrders = new List<WorkOrderRow>();

        try {
            WorkOrdersService.VendorConsolidationInitResult serviceResult =
                client().getVendorWorkOrdersForConsolidation();
            result.repairCenterId = serviceResult.repairCenterId;
            result.repairCenterName = serviceResult.repairCenterName;
            result.hasRepairCenterAddress = serviceResult.hasRepairCenterAddress;
            result.errorMessage = serviceResult.errorMessage;
            if (serviceResult.workOrders != null) {
                for (WorkOrdersService.VendorConsolidationWorkOrderRow row : serviceResult.workOrders) {
                    result.workOrders.add(toWorkOrderRow(row));
                }
            }
            return result;
        } catch (AuraHandledException e) {
            logAndRethrow('getVendorWorkOrders', e);
            return result;
        } catch (Exception e) {
            logAndRethrow(
                'getVendorWorkOrders',
                buildAuraException('Error loading vendor work orders: ' + e.getMessage())
            );
            return result;
        }
    }

    /**
     * @description Creates Vendor Return Order(s) for the selected work orders.
     * @param workOrderIds Selected Work Order Ids
     * @return CompleteResult with created Return Order Ids, numbers, and a status message
     */
    @AuraEnabled
    public static CompleteResult completeShipment(List<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            throw new AuraHandledException(
                'Select at least one work order before completing.'
            );
        }

        try {
            ReturnOrdersService.VendorConsolidationCompleteResult serviceResult =
                client().completeVendorShipment(workOrderIds);
            CompleteResult result = new CompleteResult();
            result.returnOrderIds = serviceResult.returnOrderIds;
            result.returnOrderNumbers = serviceResult.returnOrderNumbers;
            result.workOrderCount = serviceResult.workOrderCount;
            result.message = serviceResult.message;
            return result;
        } catch (AuraHandledException e) {
            logAndRethrow('completeShipment', e);
            return null;
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            logAndRethrow(
                'completeShipment',
                buildAuraException('Error creating vendor return order: ' + e.getMessage())
            );
            return null;
        } catch (DmlException e) {
            logAndRethrow(
                'completeShipment',
                buildAuraException('Error creating vendor return order: ' + e.getDmlMessage(0))
            );
            return null;
        } catch (Exception e) {
            logAndRethrow(
                'completeShipment',
                buildAuraException('Error creating vendor return order: ' + e.getMessage())
            );
            return null;
        }
    }

    private static WorkOrderRow toWorkOrderRow(WorkOrdersService.VendorConsolidationWorkOrderRow row) {
        WorkOrderRow auraRow = new WorkOrderRow();
        auraRow.id = row.id;
        auraRow.workOrderNumber = row.workOrderNumber;
        auraRow.parentWorkOrderId = row.parentWorkOrderId;
        auraRow.parentWorkOrderNumber = row.parentWorkOrderNumber;
        auraRow.status = row.status;
        auraRow.subStatus = row.subStatus;
        auraRow.vendorId = row.vendorId;
        auraRow.vendorName = row.vendorName;
        auraRow.vendorAddress = row.vendorAddress;
        auraRow.hasVendorAddress = row.hasVendorAddress;
        auraRow.repairCenterId = row.repairCenterId;
        auraRow.repairCenterName = row.repairCenterName;
        auraRow.customerPo = row.customerPo;
        auraRow.groupKey = row.groupKey;
        return auraRow;
    }

    private static AuraHandledException buildAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    private static void logAndRethrow(String methodName, Exception e) {
        Logger.error(
            new LogMessage(
                'ConsolidateVendorShipmentController.{0} failed: {1}',
                methodName,
                e.getMessage()
            ),
            e
        );
        Logger.saveLog();
        throw e;
    }
}