/**
 * Enforces that an Opportunity cannot be closed (Closed Won or Closed Lost)
 * while it has one or more Forecast Eligible Quotes that are not in Closed status.
 * GC-3188
 */
public with sharing class OpportunityClosureValidationService {

    private static final String CLASS_NAME = 'OpportunityClosureValidationService';

    /**
     * Blocks closure of Opportunities transitioning to Closed Won/Closed Lost
     * when any associated Forecast Eligible Quote is not yet Closed.
     * Adds a record-level error (addError) on the Opportunity so the DML fails
     * with a user-facing message; does not throw or log at ERROR since this is
     * an expected business-rule enforcement, not a system defect.
     *
     * @param newOpportunities Trigger.new Opportunity list.
     * @param oldOpportunityMap Trigger.oldMap of prior Opportunity values.
     */
    public static void validateForecastEligibleQuoteClosure(
        List<Opportunity> newOpportunities,
        Map<Id, Opportunity> oldOpportunityMap
    ) {
        Id healthcareSalesRtId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Healthcare_Sales').getRecordTypeId();
        Id HCSalesConsumablesRtId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('HCSalesConsumables').getRecordTypeId();
        Id InstrumentProcessingRtId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('InstrumentProcessing').getRecordTypeId();
        Set<Id> recordTypeIds = new Set<Id>{healthcareSalesRtId, HCSalesConsumablesRtId, InstrumentProcessingRtId};
        try {
            if (newOpportunities == null || newOpportunities.isEmpty() || oldOpportunityMap == null) {
                return;
            }

            Set<Id> closingOpportunityIds = new Set<Id>();

            for (Opportunity opp : newOpportunities) {
                Opportunity oldOpp = oldOpportunityMap.get(opp.Id);

                if (oldOpp == null) {
                    continue;
                }
				
                if (opp.IsClosed && !oldOpp.IsClosed && recordTypeIds.contains(opp.RecordtypeId)) {
                    closingOpportunityIds.add(opp.Id);
                }
            }

            if (closingOpportunityIds.isEmpty()) {
                return;
            }

            List<Quote> openForecastEligibleQuotes =
                QuoteSelector.selectOpenForecastEligibleQuotesByOpportunityIds(closingOpportunityIds);

            Set<Id> opportunityIdsWithOpenQuotes = new Set<Id>();
            for (Quote q : openForecastEligibleQuotes) {
                opportunityIdsWithOpenQuotes.add(q.OpportunityId);
            }

            if (opportunityIdsWithOpenQuotes.isEmpty()) {
                return;
            }

            for (Opportunity opp : newOpportunities) {
                if (opportunityIdsWithOpenQuotes.contains(opp.Id)) {
                    
                    opp.addError(Label.Opp_Closure_Blocked_Forecast_Eligible_Quotes);

                    Logger.info(
                        CLASS_NAME + '.validateForecastEligibleQuoteClosure: blocked closure OpportunityId=' +
                        opp.Id
                    )
                        .addTag('Opportunity')
                        .setRecord(opp);
                }
            }

        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.validateForecastEligibleQuoteClosure', e);
        } finally {
            Logger.saveLog();
        }
    }
}