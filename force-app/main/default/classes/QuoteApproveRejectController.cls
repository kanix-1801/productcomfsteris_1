/**
 * GW-5333 LWC boundary for Approve/Reject Quote.
 *
 * @author Uptima
 * @date 2026-09-21
 * @group Repair Center
 * @description Thin LWC controller for GW-5333 Approve/Reject Quote.
 */
public with sharing class QuoteApproveRejectController {
    /**
     * @description GW-5333 - Loads the Approve/Reject Quote workspace for a Work Order.
     * @param workOrderId Work Order Id
     * @return Workspace DTO
     */
    @AuraEnabled
    public static QuoteService.ApproveRejectWorkspace getWorkspace(Id workOrderId) {
        try {
            return QuoteService.getApproveRejectWorkspace(workOrderId);
        } catch (QuoteService.ApproveRejectException e) {
            throw buildAuraException(e.getMessage());
        }
    }

    /**
     * @description GW-5333 - Saves Approve/Reject decisions for Product Serviced quote lines.
     * @param workOrderId Work Order Id
     * @param decisions Line-level Approve/Reject choices
     * @return Updated workspace DTO
     */
    @AuraEnabled
    public static QuoteService.ApproveRejectWorkspace saveDecisions(
        Id workOrderId,
        List<QuoteService.ApproveRejectDecision> decisions
    ) {
        try {
            return QuoteService.saveApproveRejectDecisions(workOrderId, decisions);
        } catch (QuoteService.ApproveRejectException e) {
            throw buildAuraException(e.getMessage());
        }
    }

    /**
     * @description GW-5333 - Saves Quote Comments immediately.
     * @param quoteLineItemId Quote Line Item Id
     * @param comments Quote Comments text
     * @return Saved comments
     */
    @AuraEnabled
    public static String saveComment(Id quoteLineItemId, String comments) {
        try {
            return QuoteService.saveApproveRejectComment(quoteLineItemId, comments);
        } catch (QuoteService.ApproveRejectException e) {
            throw buildAuraException(e.getMessage());
        }
    }

    /**
     * @description GW-5333 - Creates an AuraHandledException with a preserved client message.
     * @param message User-facing error message
     * @return AuraHandledException for the LWC
     */
    private static AuraHandledException buildAuraException(String message) {
        AuraHandledException exceptionResult = new AuraHandledException(message);
        exceptionResult.setMessage(message);
        return exceptionResult;
    }
}