/**
 * @author Himanshu Chaurasia
 * @date 2026/09/15
 *
 * @group GC-3235
 *
 * @description Aura-enabled entry point for the Strategic Contract deal approval panel on Opportunity.
 *              Delegates to OppDealApprovalService and surfaces user-friendly errors to the LWC.
 */
public with sharing class OppDealApprovalController {
    /**
     * @description Loads panel visibility, mode, approver rows, and decision permissions for the Opportunity.
     * @param opportunityId Opportunity record Id displayed on the record page.
     * @return Approval context DTO for the deal approval LWC.
     */
    @AuraEnabled
    public static OppDealApprovalService.ApprovalContext getApprovalContext(Id opportunityId) {
        try {
            return OppDealApprovalService.getApprovalContext(opportunityId);
        } catch (AuraHandledException exceptionValue) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(exceptionValue, 'OppDealApprovalController', 'getApprovalContext');
            throw new AuraHandledException('Unable to load deal approval details.');
        }
    }

    /**
     * @description Records an approve or reject decision for the current user's pending approver row.
     * @param approverRecordId DealApprovalApprover__c Id assigned to the running user.
     * @param decision Approved or Rejected picklist value.
     * @param comments Required when rejecting; optional approval notes otherwise.
     * @return Refreshed approval context after the decision is persisted.
     */
    @AuraEnabled
    public static OppDealApprovalService.ApprovalContext decide(
        Id approverRecordId,
        String decision,
        String comments
    ) {
        try {
            return OppDealApprovalService.decide(approverRecordId, decision, comments);
        } catch (AuraHandledException exceptionValue) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(exceptionValue, 'OppDealApprovalController', 'decide');
            throw new AuraHandledException('Unable to record the approval decision.');
        }
    }
}