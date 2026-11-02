/**
 * @author Surya Manindra
 * @date 2026-06-10
 *
 * @group Opportunity
 *
 * @description
 * Invocable Apex class to clone an Opportunity with only
 * Update bypassfield to uncheck after the clone record
 * Called from Opportunity_ScreenFlow_CloneReview Screen Flow.
 * #GC-3145
 */
public class OpportunityCloneService {
	@InvocableMethod (label='Reset Bypay sets BypassValidations__ss Validation Flag (Async)'  description='Asynchronouslc to false via Queueable.')
	public static void resetBypassFlag(List<Id> OpportunityId) {
    	resetBypassFlagAsync(OpportunityId);
    }
    
    @future
    public static void resetBypassFlagAsync(List<Id> opportunityIds) {
        List<Opportunity> updateOpportunities = new List<Opportunity>();
        List<Opportunity> lstOpportunity = [SELECT Id,
                                            BypassValidations__c 
                                            FROM Opportunity WHERE Id in :opportunityIds ];
        for(Opportunity Opp : lstOpportunity) {
            opp.BypassValidations__c = false;
            updateOpportunities.add(opp);
        }
        update updateOpportunities;
    }    
}