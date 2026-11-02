/**
 * @author Uptima
 * @date 2026-08-15
 * @group Repair Center
 * @description Aura entry point for the Assign Technician LWC (GW-3816).
 *              Validates Aura I/O and delegates business logic / DML to WorkOrdersService.
 *              Uses without sharing so shop-floor scanners can invoke the service regardless
 *              of record-level sharing on Work Order.
 */
public without sharing class AssignTechnicianController {
    /**
     * @description Result DTO returned to the Assign Technician LWC.
     */
    public class AssignResult {
        /** Assigned Work Order Id. */
        @AuraEnabled public Id workOrderId { get; set; }
        /** Assigned Work Order Number. */
        @AuraEnabled public String workOrderNumber { get; set; }
        /** Created Technician WO Assignment History Id. */
        @AuraEnabled public Id assignmentHistoryId { get; set; }
    }

    /**
     * @description Assigns the running user as Technician on the Work Order identified by
     *              record Id or Work Order Number. Delegates to WorkOrdersService.assignTechnician.
     * @param workOrderInput Work Order Id or WorkOrderNumber
     * @return AssignResult with Work Order and assignment history identifiers
     * @example
     * AssignTechnicianController.AssignResult result =
     *     AssignTechnicianController.assignTechnician('00001234');
     */
    @AuraEnabled
    public static AssignResult assignTechnician(String workOrderInput) {
        try {
            WorkOrdersService.AssignTechnicianResult serviceResult =
                WorkOrdersService.assignTechnician(workOrderInput);
            return toAssignResult(serviceResult);
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw toAuraHandledException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.setScenario('Assign Technician');
            Logger.error(
                new LogMessage(
                    'AssignTechnicianController.assignTechnician unexpected error for WO {0}: {1}',
                    workOrderInput,
                    e.getMessage()
                ),
                e
            );
            Logger.saveLog();
            throw toAuraHandledException('Unable to assign technician: ' + e.getMessage());
        }
    }

    private static AssignResult toAssignResult(
        WorkOrdersService.AssignTechnicianResult serviceResult
    ) {
        AssignResult result = new AssignResult();
        if (serviceResult == null) {
            return result;
        }
        result.workOrderId = serviceResult.workOrderId;
        result.workOrderNumber = serviceResult.workOrderNumber;
        result.assignmentHistoryId = serviceResult.assignmentHistoryId;
        return result;
    }

    private static AuraHandledException toAuraHandledException(String message) {
        AuraHandledException auraException = new AuraHandledException(message);
        auraException.setMessage(message);
        return auraException;
    }
}