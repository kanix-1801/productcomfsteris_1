/**
 * @description GC-3519. Applies the PDM review decision on commercial opportunities.
 *              Not a Project Opportunity clears Project Opportunity? the first time it is saved.
 *              No Project Reason and No Project Comments are kept only while they still apply.
 */
public with sharing class ProjectOpportunityReviewService {
    @TestVisible
    private static final String DECISION_NOT_A_PROJECT = 'Not a Project Opportunity';
    @TestVisible
    private static final String REASON_OTHER = 'Other';
    private static final String LOGGER_TAG = 'GC-3519';

    public static void applyBeforeSave(List<Opportunity> opportunities, Map<Id, Opportunity> priorById) {
        if (opportunities == null || opportunities.isEmpty()) {
            return;
        }
        try {
            for (Opportunity opportunity : opportunities) {
                if (opportunity.PDMReviewDecision__c != DECISION_NOT_A_PROJECT) {
                    opportunity.NoProjectReason__c = null;
                    opportunity.NoProjectComments__c = null;
                    continue;
                }
                if (opportunity.NoProjectReason__c != REASON_OTHER) {
                    opportunity.NoProjectComments__c = null;
                }
                Opportunity prior = priorById == null || opportunity.Id == null
                    ? null
                    : priorById.get(opportunity.Id);
                if (prior == null || prior.PDMReviewDecision__c != opportunity.PDMReviewDecision__c) {
                    opportunity.ProjectOpportunity__c = false;
                }
            }
        } catch (Exception exceptionValue) {
            Logger.setScenario(LOGGER_TAG);
            Logger.error('Unable to apply the PDM review decision.', exceptionValue).addTag(LOGGER_TAG);
            Logger.saveLog();
            throw exceptionValue;
        }
    }
}