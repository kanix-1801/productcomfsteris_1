/**
 * @description GC-3521 . Keeps a Master Project Opportunity out of the sales forecast.
 *              Forecast Category is Omitted and Forecast Confidence is cleared.
 *              Probability stays on the stage default, except Deferred / On Hold keeps the prior probability.
 */
public with sharing class ProjectOpportunityForecastService {
    @TestVisible
    private static final String RECORD_TYPE_DEVELOPER_NAME = 'HCProjectOpportunity';
    @TestVisible
    private static final String STAGE_DEFERRED = 'Deferred / On Hold';
    @TestVisible
    private static final String FORECAST_CATEGORY_OMITTED = 'Omitted';
    private static final String LOGGER_TAG = 'GC-3521';

    public static void applyBeforeSave(List<Opportunity> opportunities, Map<Id, Opportunity> priorById) {
        if (opportunities == null || opportunities.isEmpty()) {
            return;
        }
        try {
            Id projectRecordTypeId = projectRecordTypeId();
            if (projectRecordTypeId == null) {
                return;
            }
            for (Opportunity opportunity : opportunities) {
                if (opportunity.RecordTypeId != projectRecordTypeId) {
                    continue;
                }
                opportunity.ForecastCategoryName = FORECAST_CATEGORY_OMITTED;
                opportunity.ForecastConfidenceLevel__c = null;
                restoreProbabilityWhenDeferred(opportunity, priorById);
            }
        } catch (Exception exceptionValue) {
            Logger.setScenario(LOGGER_TAG);
            Logger.error('Unable to apply project opportunity forecast treatment.', exceptionValue).addTag(LOGGER_TAG);
            Logger.saveLog();
            throw exceptionValue;
        }
    }

    private static void restoreProbabilityWhenDeferred(Opportunity opportunity, Map<Id, Opportunity> priorById) {
        Opportunity prior = priorById == null || opportunity.Id == null
            ? null
            : priorById.get(opportunity.Id);
        if (prior == null || prior.Probability == null) {
            return;
        }
        if (opportunity.StageName == STAGE_DEFERRED && prior.StageName != STAGE_DEFERRED) {
            opportunity.Probability = prior.Probability;
        }
    }

    private static Id projectRecordTypeId() {
        Schema.RecordTypeInfo recordType = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get(RECORD_TYPE_DEVELOPER_NAME);
        return recordType == null ? null : recordType.getRecordTypeId();
    }
}