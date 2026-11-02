/**
 * @author Himanshu Chaurasia
 * @date 2026/08/19
 *
 * @description Visibility logic for the Missing Forecast Eligible Quote banner on Opportunity.
 */
public with sharing class MissingForecastEligibleBannerController {
    @TestVisible
    private static final Set<String> BANNER_QUOTE_STATUSES = new Set<String>{
        'Draft',
        'Test',
        'Budget'
    };

    @TestVisible
    private static final Set<String> FORECAST_INELIGIBLE_QUOTE_TYPES = new Set<String>{
        GenerateQuoteService.QUOTE_TYPE_TRIAL,
        GenerateQuoteService.QUOTE_TYPE_SAMPLE,
        GenerateQuoteService.QUOTE_TYPE_GOODWILL
    };

    /**
     * @description Returns true when the banner should display for an Opportunity.
     * @param opportunityId Opportunity record Id.
     * @return True when a non-ineligible quote is Draft/Test/Budget and none are Forecast Eligible.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isBannerVisible(Id opportunityId) {
        if (opportunityId == null) {
            return false;
        }

        Id salesConnectionRecordTypeId = resolveHcSalesRecordTypeId();
        if (salesConnectionRecordTypeId == null) {
            return false;
        }

        List<String> forecastIneligibleQuoteTypes = new List<String>(FORECAST_INELIGIBLE_QUOTE_TYPES);
        Boolean hasDraftTestOrBudgetQuote = false;
        Boolean hasForecastEligibleQuote = false;

        for (Quote quoteRecord : [
            SELECT Status, Forecast_Eligible__c
            FROM Quote
            WHERE OpportunityId = :opportunityId
            AND RecordTypeId = :salesConnectionRecordTypeId
            AND IsForecastIneligible__c != TRUE
            AND (QuoteType__c = NULL OR QuoteType__c NOT IN :forecastIneligibleQuoteTypes)
            WITH USER_MODE
        ]) {
            if (quoteRecord.Forecast_Eligible__c == true) {
                hasForecastEligibleQuote = true;
            }

            if (BANNER_QUOTE_STATUSES.contains(quoteRecord.Status)) {
                hasDraftTestOrBudgetQuote = true;
            }
        }

        return hasDraftTestOrBudgetQuote && !hasForecastEligibleQuote;
    }

    private static Id resolveHcSalesRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName();

        if (!recordTypesByDeveloperName.containsKey(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME)) {
            return null;
        }

        Schema.RecordTypeInfo recordTypeInfo =
            recordTypesByDeveloperName.get(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME);
        return recordTypeInfo.isAvailable() ? recordTypeInfo.getRecordTypeId() : null;
    }
}