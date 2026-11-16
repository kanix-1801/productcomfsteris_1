/**
 * @author PWC Developer
 * @date 2026/11/05
 *
 * @group Lost Business Products
 *
 * @description
 * GC-3574 - Flow action that copies originating products onto a Lost Business opportunity
 * created from the standard New button.
 */
public with sharing class LostBusinessProductCopyAction {

    /**
     * @description
     * GC-3574 - One Lost Business opportunity passed by the after-save flow.
     */
    public class Request {
        @InvocableVariable(label='Lost Business Opportunity Id' required=true)
        public Id lostBusinessOpportunityId;
    }

    /**
     * @description
     * GC-3574 - Copies originating products for each Lost Business opportunity in the request.
     * Products already on the opportunity are not added again.
     *
     * @param requestList Lost Business opportunities created from the standard New button.
     *
     * @example
     * LostBusinessProductCopyAction.copyOriginatingProducts(requestList);
     */
    @InvocableMethod(
        label='Copy Originating Products to Lost Business'
        description='GC-3574 - Copies products from the originating opportunity. Skips a product that is already on the Lost Business opportunity.'
        category='Opportunity'
    )
    public static void copyOriginatingProducts(List<Request> requestList) {
        Set<Id> lostOpportunityIds = new Set<Id>();

        if (requestList != null) {
            for (Request request : requestList) {
                if (request != null && request.lostBusinessOpportunityId != null) {
                    lostOpportunityIds.add(request.lostBusinessOpportunityId);
                }
            }
        }

        LostBusinessProductService.copyOriginatingProducts(lostOpportunityIds);
    }
}