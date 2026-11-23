/**
 * @description SOQL selector for CIO Evaluation records. GW-4749
 */
public with sharing class CIOEvaluationsSelector extends SoqlQueryBuilder {
    private static final List<String> LIST_FIELDS = new List<String>{
        'Id',
        'Name',
        'WorkOrder__c',
        'ParentWorkOrder__c',
        'ConfirmedCustomerReportedIssue__c',
        'IdentifiableRootCause__c',
        'IssueRelatedToPreviousRepair__c',
        'SignsOfDamageWearFailure__c',
        'DetermineExtentOfUsage__c',
        'CorrectiveActionTaken__c',
        'Technician__c',
        'Technician__r.Name',
        'Date__c'
    };

    /**
     * @description Binds this selector to CIOEvaluation__c.
     */
    public CIOEvaluationsSelector() {
        this.objectName = 'CIOEvaluation__c';
    }

    /**
     * @description CIO Evaluations for a Work Order, newest first.
     * @param workOrderId Work Order Id
     * @return Matching CIO Evaluation records. Empty when the Id is null.
     */
    public static List<CIOEvaluation__c> selectByWorkOrderId(Id workOrderId) {
        if (workOrderId == null) {
            return new List<CIOEvaluation__c>();
        }
        return (List<CIOEvaluation__c>) new CIOEvaluationsSelector()
            .selectFields(LIST_FIELDS)
            .whereEquals('WorkOrder__c', workOrderId)
            .orderByDesc('CreatedDate')
            .execute();
    }
}