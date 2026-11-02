/**
 * @author Chandini Singarapu
 * @date 2026/06/10
 *
 * @description
 * SOQL-only selector for stale Opportunity batch processing.
 * This class owns query logic only and does not perform business processing or DML.
 */
public with sharing class OpportunityStaleSelector {

    /**
     * @description Query locator for open Opportunities eligible for stale evaluation.
     *
     * @return Query locator for open Opportunity records
     */
    public static Database.QueryLocator getOpenOpportunitiesQueryLocator() {

        return Database.getQueryLocator([
            SELECT Id,
                   RecordType.DeveloperName,
                   StageName,
                   CloseDate,
                   LastModifiedDate,
                   LastStageChangeDate__c,
                   LastQualifyingActivityDate__c,
                   isStaleOpportunity__c,
                   StaleReason__c,
                   DaysSinceLastActivity__c,
                   DaysSinceLastStageChange__c,
                   IsPastDueDate_f__c
            FROM Opportunity
            WHERE IsClosed = FALSE
            WITH USER_MODE
        ]);
    }

    /**
     * @description Loads Opportunity stale configuration records from Custom Metadata.
     *              Records are keyed by BusinessType__c and Stage__c.
     *
     * @return Map of configuration records keyed by business type and stage
     */
    public static Map<String, OpportunityStaleConfigSettings__mdt> selectStaleConfigByBusinessTypeAndStage() {
        Map<String, OpportunityStaleConfigSettings__mdt> configByKey =
            new Map<String, OpportunityStaleConfigSettings__mdt>();

        for (OpportunityStaleConfigSettings__mdt config : [
            SELECT DeveloperName,
                   BusinessType__c,
                   Stage__c,
                   StaleDaysThreshold__c
            FROM OpportunityStaleConfigSettings__mdt
        ]) {
            String key = buildConfigKey(config.BusinessType__c, config.Stage__c);
            configByKey.put(key, config);
        }

        return configByKey;
    }

    /**
     * @description Finds the latest Task activity date for each Opportunity.
     *
     * @param opportunityIds Opportunity Ids from the current batch chunk
     * @return Map of Opportunity Id to latest Task ActivityDate
     */
    public static Map<Id, Date> selectLatestTaskActivityDateByOpportunityId(Set<Id> opportunityIds) {
        Map<Id, Date> latestDateByOpportunityId = new Map<Id, Date>();

        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return latestDateByOpportunityId;
        }

        for (Task taskRecord : [
            SELECT WhatId, ActivityDate
            FROM Task
            WHERE WhatId IN :opportunityIds
              AND ActivityDate != null
            ORDER BY ActivityDate DESC
        ]) {
            if (!latestDateByOpportunityId.containsKey(taskRecord.WhatId)) {
                latestDateByOpportunityId.put(taskRecord.WhatId, taskRecord.ActivityDate);
            }
        }

        return latestDateByOpportunityId;
    }

    /**
     * @description Finds the latest Event activity date for each Opportunity.
     *
     * @param opportunityIds Opportunity Ids from the current batch chunk
     * @return Map of Opportunity Id to latest Event ActivityDate
     */
    public static Map<Id, Date> selectLatestEventActivityDateByOpportunityId(Set<Id> opportunityIds) {
        Map<Id, Date> latestDateByOpportunityId = new Map<Id, Date>();

        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return latestDateByOpportunityId;
        }

        for (Event eventRecord : [
            SELECT WhatId, ActivityDate
            FROM Event
            WHERE WhatId IN :opportunityIds
              AND ActivityDate != null
            ORDER BY ActivityDate DESC
        ]) {
            if (!latestDateByOpportunityId.containsKey(eventRecord.WhatId)) {
                latestDateByOpportunityId.put(eventRecord.WhatId, eventRecord.ActivityDate);
            }
        }

        return latestDateByOpportunityId;
    }

    /**
     * @description Builds the config key used to match Opportunity RecordType and Stage
     *              against stale Custom Metadata configuration.
     *
     * @param businessType Business type or RecordType DeveloperName
     * @param stage Opportunity StageName
     * @return Composite key in businessType|stage format
     */
    public static String buildConfigKey(String businessType, String stage) {
        return String.valueOf(businessType) + '|' + String.valueOf(stage);
    }
}