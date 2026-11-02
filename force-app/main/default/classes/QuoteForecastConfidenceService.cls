/**
 * @description Active Quote Forecast Confidence picklist values for Generate Quote.
 */
public with sharing class QuoteForecastConfidenceService {
    public class Option {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
    }

    /**
     * @description Returns every active Quote Forecast Confidence value, not filtered by record type.
     * @return Label/value options for the quote list.
     */
    @AuraEnabled(cacheable=true)
    public static List<Option> getActiveOptions() {
        List<Option> options = new List<Option>();

        for (
            Schema.PicklistEntry picklistEntry :
            Quote.QuoteForecastConfidence__c.getDescribe().getPicklistValues()
        ) {
            if (!picklistEntry.isActive()) {
                continue;
            }

            Option option = new Option();
            option.label = picklistEntry.getLabel();
            option.value = picklistEntry.getValue();
            options.add(option);
        }

        return options;
    }
}