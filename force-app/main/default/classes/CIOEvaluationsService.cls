/**
 * @description CIO Evaluation form context and list access for Repair Center evaluators. GW-4749
 */
public with sharing class CIOEvaluationsService {
    /**
     * @description Raised when a CIO Evaluation request cannot be completed.
     */
    public class CIOEvaluationsServiceException extends Exception {
    }

    /**
     * @description Defaults used by the questionnaire popup.
     */
    public class FormContext {
        public Id recordTypeId;
        public Id parentWorkOrderId;
        public Id technicianId;
        public Date evaluationDate;
    }

    /**
     * @description CIO Evaluations already saved for the Work Order.
     * @param workOrderId Work Order Id
     * @return Related CIO Evaluation records
     */
    public static List<CIOEvaluation__c> getByWorkOrderId(Id workOrderId) {
        return CIOEvaluationsSelector.selectByWorkOrderId(workOrderId);
    }

    /**
     * @description Record type, parent Work Order, technician, and date defaults for a new questionnaire.
     * @param workOrderId Current Work Order Id
     * @return Form defaults
     */
    public static FormContext getFormContext(Id workOrderId) {
        if (workOrderId == null) {
            throw new CIOEvaluationsServiceException('Work Order is required.');
        }
        WorkOrder workOrder = (WorkOrder) new WorkOrdersSelector()
            .selectFields(new List<String>{ 'Id', 'ParentWorkOrderId' })
            .whereEquals('Id', workOrderId)
            .first();
        if (workOrder == null) {
            throw new CIOEvaluationsServiceException('Work Order was not found.');
        }

        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.CIOEvaluation__c
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter');
        if (recordTypeInfo == null) {
            throw new CIOEvaluationsServiceException(
                'Repair Center record type is not available for CIO Evaluation.'
            );
        }

        FormContext context = new FormContext();
        context.recordTypeId = recordTypeInfo.getRecordTypeId();
        context.parentWorkOrderId = workOrder.ParentWorkOrderId;
        context.technicianId = UserInfo.getUserId();
        context.evaluationDate = Date.today();
        return context;
    }
}