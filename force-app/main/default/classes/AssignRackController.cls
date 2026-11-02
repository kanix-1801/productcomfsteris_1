/**
 * @author Uptima
 * @date 2026-08-15
 * @group Repair Center
 * @description Aura entry point for the Assign Rack LWC (GW-3816).
 *              Validates Aura I/O and delegates business logic / DML to WorkOrdersService.
 *              Uses without sharing so shop-floor scanners can invoke the service regardless
 *              of record-level sharing on Location.
 */
public without sharing class AssignRackController {
    /**
     * @description Result DTO returned to the Assign Rack LWC.
     */
    public class AssignResult {
        /** Updated Work Order Id. */
        @AuraEnabled public Id workOrderId { get; set; }
        /** Updated Work Order Number. */
        @AuraEnabled public String workOrderNumber { get; set; }
        /** Assigned Rack Location Id. */
        @AuraEnabled public Id rackId { get; set; }
        /** Assigned Rack Location Name. */
        @AuraEnabled public String rackName { get; set; }
        /** Created Rack WO Assignment History Id when tracking is enabled. */
        @AuraEnabled public Id assignmentHistoryId { get; set; }
    }

    /**
     * @description Assigns a Rack Location to the Work Order identified by record Id or
     *              Work Order Number. Delegates to WorkOrdersService.assignRack.
     * @param workOrderInput Work Order Id or WorkOrderNumber
     * @param rackInput Rack Location Id or Name
     * @return AssignResult with Work Order and Rack identifiers
     * @example
     * AssignRackController.AssignResult result =
     *     AssignRackController.assignRack('00001234', 'RACK-01');
     */
    @AuraEnabled
    public static AssignResult assignRack(String workOrderInput, String rackInput) {
        try {
            WorkOrdersService.AssignRackResult serviceResult =
                WorkOrdersService.assignRack(workOrderInput, rackInput);
            return toAssignResult(serviceResult);
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw toAuraHandledException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.setScenario('Assign Rack');
            Logger.error(
                new LogMessage(
                    'AssignRackController.assignRack unexpected error for WO {0} / Rack {1}: {2}',
                    workOrderInput,
                    rackInput,
                    e.getMessage()
                ),
                e
            );
            Logger.saveLog();
            throw toAuraHandledException('Unable to assign rack: ' + e.getMessage());
        }
    }

    private static AssignResult toAssignResult(WorkOrdersService.AssignRackResult serviceResult) {
        AssignResult result = new AssignResult();
        if (serviceResult == null) {
            return result;
        }
        result.workOrderId = serviceResult.workOrderId;
        result.workOrderNumber = serviceResult.workOrderNumber;
        result.rackId = serviceResult.rackId;
        result.rackName = serviceResult.rackName;
        result.assignmentHistoryId = serviceResult.assignmentHistoryId;
        return result;
    }

    private static AuraHandledException toAuraHandledException(String message) {
        AuraHandledException auraException = new AuraHandledException(message);
        auraException.setMessage(message);
        return auraException;
    }
}