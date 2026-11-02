/**
 * @author Chandini Singarapu
 * @date 2026/06/10
 *
 * @description
 * Processes Opportunity stale evaluation.
 * Evaluates stale status using configured thresholds, latest qualifying activity,
 * last stage movement, and past due close date.
 */
public with sharing class OpportunityStaleService {

    private static final String STAGE_PROPOSAL = 'Proposal';
    private static final String STAGE_COMMIT = 'Commit';

    private static final String REASON_ACTIVITY_AND_STAGE =
        'No Recent Activity and No Stage Movement';
    private static final String REASON_ACTIVITY =
        'No Recent Activity';
    private static final String REASON_STAGE =
        'No Stage Movement';
    private static final String REASON_PAST_DUE =
        'Opportunity is Past Due Date';

    /**
     * @description Entry point for batch execute. Evaluates stale values and updates Opportunities.
     *
     * @param scope Opportunity records from the batch query locator
     */
    public static void process(List<Opportunity> scope) {
        if (scope == null || scope.isEmpty()) {
            Logger.warn('OpportunityStaleService.process: empty scope');
            return;
        }

        Map<Id, Date> latestActivityByOpportunityId = getLatestActivityDates(scope);

        Map<String, OpportunityStaleConfigSettings__mdt> configByKey =
            OpportunityStaleSelector.selectStaleConfigByBusinessTypeAndStage();

        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
        Date todayDate = Date.today();
		
        for (Opportunity opp : scope) {
            Opportunity evaluatedOpportunity =
                evaluateOpportunity(opp, latestActivityByOpportunityId, configByKey, todayDate);

            opportunitiesToUpdate.add(evaluatedOpportunity);
        }

        updateOpportunities(opportunitiesToUpdate);
    }

    /**
     * @description Evaluates one Opportunity and prepares field updates.
     *
     * @param opp Opportunity record from scope
     * @param latestActivityByOpportunityId Map of Opportunity Id to latest Task/Event date
     * @param configByKey Custom Metadata config keyed by business type and stage
     * @param todayDate Current date used for day calculations
     * @return Opportunity record containing updated stale fields
     */
    private static Opportunity evaluateOpportunity(
        Opportunity opp,
        Map<Id, Date> latestActivityByOpportunityId,
        Map<String, OpportunityStaleConfigSettings__mdt> configByKey,
        Date todayDate
    ) {
        Date latestActivityDate = latestActivityByOpportunityId.get(opp.Id);

        Integer daysSinceActivity = calculateDaysBetween(latestActivityDate, todayDate);
        Integer daysSinceStageChange = calculateDaysBetween(opp.LastStageChangeDate__c, todayDate);

        Boolean isTargetStage = isTargetStage(opp.StageName);

        String configKey = OpportunityStaleSelector.buildConfigKey(
            opp.RecordType.DeveloperName,
            opp.StageName
        );

        OpportunityStaleConfigSettings__mdt config = configByKey.get(configKey);

        Boolean staleByActivity = false;
        Boolean staleByStage = false;

        if (config != null && isTargetStage) {
            Integer thresholdDays = Integer.valueOf(config.StaleDaysThreshold__c);

            staleByActivity =
                latestActivityDate == null ||
                daysSinceActivity >= thresholdDays;

            staleByStage =
                opp.LastStageChangeDate__c == null ||
                daysSinceStageChange >= thresholdDays;
        }
        
        Boolean staleByThreshold = staleByActivity || staleByStage;
        Boolean staleByPastDueDate = !staleByThreshold && opp.IsPastDueDate_f__c == true;
        Boolean isStale = staleByThreshold || staleByPastDueDate;
        return new Opportunity(
            Id = opp.Id,
            LastQualifyingActivityDate__c = latestActivityDate,
            DaysSinceLastActivity__c = daysSinceActivity,
            DaysSinceLastStageChange__c = daysSinceStageChange,
            isStaleOpportunity__c = isStale,
            StaleReason__c = resolveStaleReason(
                staleByActivity,
                staleByStage,
                staleByPastDueDate
            )
        );
    }

    /**
     * @description Returns true when Opportunity is in Proposal or Commit stage.
     *
     * @param stageName Opportunity StageName
     * @return True when the stage is eligible for threshold-based stale evaluation
     */
    private static Boolean isTargetStage(String stageName) {
        return stageName == STAGE_PROPOSAL || stageName == STAGE_COMMIT;
    }

    /**
     * @description Calculates number of days between source date and today.
     *
     * @param sourceDate Date to compare from
     * @param todayDate Current date
     * @return Number of days, or null when source date is null
     */
    private static Integer calculateDaysBetween(Date sourceDate, Date todayDate) {
        if (sourceDate == null) {
            return null;
        }

        return sourceDate.daysBetween(todayDate);
    }

    /**
     * @description Resolves stale reason based on stale evaluation results.
     *
     * @param staleByActivity True when stale due to missing or old activity
     * @param staleByStage True when stale due to missing or old stage movement
     * @param staleByPastDueDate True when stale only because Close Date is past due
     * @return Stale reason text, or null when not stale
     */
    private static String resolveStaleReason(
        Boolean staleByActivity,
        Boolean staleByStage,
        Boolean staleByPastDueDate
    ) {
        if (staleByActivity && staleByStage) {
            return REASON_ACTIVITY_AND_STAGE;
        }

        if (staleByActivity) {
            return REASON_ACTIVITY;
        }

        if (staleByStage) {
            return REASON_STAGE;
        }

        if (staleByPastDueDate) {
            return REASON_PAST_DUE;
        }

        return null;
    }

    /**
     * @description Finds the latest activity date for each Opportunity using related Task and Event records.
     *
     * @param opportunities Opportunity records from the current batch chunk
     * @return Map of Opportunity Id to latest related Task or Event activity date
     */
    private static Map<Id, Date> getLatestActivityDates(List<Opportunity> opportunities) {
        Set<Id> opportunityIds = new Set<Id>();

        for (Opportunity opp : opportunities) {
            opportunityIds.add(opp.Id);
        }

        Map<Id, Date> latestDateByOpportunityId =
            OpportunityStaleSelector.selectLatestTaskActivityDateByOpportunityId(opportunityIds);

        Map<Id, Date> latestEventDateByOpportunityId =
            OpportunityStaleSelector.selectLatestEventActivityDateByOpportunityId(opportunityIds);

        for (Id opportunityId : latestEventDateByOpportunityId.keySet()) {
            Date eventDate = latestEventDateByOpportunityId.get(opportunityId);

            if (!latestDateByOpportunityId.containsKey(opportunityId) ||
                latestDateByOpportunityId.get(opportunityId) < eventDate) {
                latestDateByOpportunityId.put(opportunityId, eventDate);
            }
        }

        return latestDateByOpportunityId;
    }

    /**
     * @description Updates Opportunities with partial success and logs DML failures.
     *
     * @param opportunitiesToUpdate Opportunities containing stale field updates
     */
    private static void updateOpportunities(List<Opportunity> opportunitiesToUpdate) {
        if (opportunitiesToUpdate == null || opportunitiesToUpdate.isEmpty()) {
            Logger.warn('OpportunityStaleService.updateOpportunities: no records to update');
            return;
        }

        Logger.info(
            'OpportunityStaleService.updateOpportunities: updateCount=' +
            opportunitiesToUpdate.size()
        );

        List<Database.SaveResult> results =
            Database.update(opportunitiesToUpdate, false, AccessLevel.USER_MODE);

        Integer failureCount = 0;

        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                failureCount++;
                logDmlErrors(results[i].getErrors(), 'updateOpportunities');
            }
        }

        if (failureCount > 0) {
            Logger.warn(
                'OpportunityStaleService.updateOpportunities: partial failure, failures=' +
                failureCount
            );
        }
    }

    /**
     * @description Logs each DML error message for the given context.
     *
     * @param errors Database.Error list from a SaveResult
     * @param logContext Method name suffix for Logger.error
     */
    private static void logDmlErrors(List<Database.Error> errors, String logContext) {
        if (errors == null) {
            return;
        }

        for (Database.Error err : errors) {
            Logger.error(
                'OpportunityStaleService.' + logContext + ': ' + err.getMessage()
            );
        }

        Logger.saveLog();
    }
}