/**
 * GW-5231 LWC boundary for Repair Coordinator Actions.
 *
 * @author Uptima
 * @date 2026-09-21
 * @group Repair Center
 * @description Thin LWC controller for GW-5231 Repair Coordinator Actions.
 */
public with sharing class RepairCoordinatorActionsController {
    /**
     * @description GW-5231 - Delegates a barcode scan to the coordinator actions service.
     * @param currentWorkOrderId Current Work Order Id, or null before the first scan
     * @param scanValue Barcode value
     * @return Current Work Order assignment state
     */
    @AuraEnabled
    public static WorkOrderCoordinatorActionsService.ScanResult processScan(
        Id currentWorkOrderId,
        String scanValue
    ) {
        try {
            return WorkOrderCoordinatorActionsService.processScan(
                currentWorkOrderId,
                scanValue
            );
        } catch (WorkOrderCoordinatorActionsService.CoordinatorActionsException e) {
            throw buildAuraException(e.getMessage());
        }
    }

    /**
     * @description GW-5231 - Delegates an ambiguous Rack/Service Team choice.
     * @param workOrderId Current Work Order Id
     * @param assignmentType RACK or SERVICE_TEAM
     * @param assignmentId Selected record Id
     * @return Updated Work Order assignment state
     */
    @AuraEnabled
    public static WorkOrderCoordinatorActionsService.ScanResult assignCandidate(
        Id workOrderId,
        String assignmentType,
        Id assignmentId
    ) {
        try {
            return WorkOrderCoordinatorActionsService.assignCandidate(
                workOrderId,
                assignmentType,
                assignmentId
            );
        } catch (WorkOrderCoordinatorActionsService.CoordinatorActionsException e) {
            throw buildAuraException(e.getMessage());
        }
    }

    /**
     * @description GW-5231 - Removes the Rack from the current Work Order.
     * @param workOrderId Current Work Order Id
     * @return Updated Work Order assignment state
     */
    @AuraEnabled
    public static WorkOrderCoordinatorActionsService.ScanResult removeRack(Id workOrderId) {
        try {
            return WorkOrderCoordinatorActionsService.removeRack(workOrderId);
        } catch (WorkOrderCoordinatorActionsService.CoordinatorActionsException e) {
            throw buildAuraException(e.getMessage());
        }
    }

    /**
     * @description GW-5231 - Removes the Service Team from the current Work Order.
     * @param workOrderId Current Work Order Id
     * @return Updated Work Order assignment state
     */
    @AuraEnabled
    public static WorkOrderCoordinatorActionsService.ScanResult removeServiceTeam(
        Id workOrderId
    ) {
        try {
            return WorkOrderCoordinatorActionsService.removeServiceTeam(workOrderId);
        } catch (WorkOrderCoordinatorActionsService.CoordinatorActionsException e) {
            throw buildAuraException(e.getMessage());
        }
    }

    /**
     * @description GW-5231 - Creates an AuraHandledException with a preserved client message.
     * @param message User-facing error message
     * @return AuraHandledException for the LWC
     */
    private static AuraHandledException buildAuraException(String message) {
        AuraHandledException exceptionResult = new AuraHandledException(message);
        exceptionResult.setMessage(message);
        return exceptionResult;
    }
}