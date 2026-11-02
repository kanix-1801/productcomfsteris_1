/**
 * @author Himanshu Chaurasia
 * @date 2026/10/09
 *
 * @description GC-3457 - Applies Salesforce Quote updates after a successful SC / Boomi response.
 */
public with sharing class ScOpportunityQuoteEventApplyService {
    /**
     * @description Updates Quote Forecast Confidence for the given quotes.
     */
    public static void applyForecastConfidence(Set<Id> quoteIds, String quoteForecastConfidence) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return;
        }

        if (String.isBlank(quoteForecastConfidence)) {
            throw new AuraHandledException(
                'Sales Connection did not return a Quote Forecast Confidence value.'
            );
        }

        List<Quote> quotesToUpdate = new List<Quote>();

        for (Id quoteId : quoteIds) {
            if (quoteId == null) {
                continue;
            }

            quotesToUpdate.add(
                new Quote(
                    Id = quoteId,
                    QuoteForecastConfidence__c = quoteForecastConfidence
                )
            );
        }

        updateQuotes(quotesToUpdate);
    }

    /**
     * @description Updates Quote status (typically Closed) for the given quotes.
     */
    public static void applyQuoteStatus(Set<Id> quoteIds, String quoteStatus) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return;
        }

        String resolvedStatus = String.isBlank(quoteStatus)
            ? QuoteSelector.CLOSED_STATUS_VALUE
            : quoteStatus.trim();

        List<Quote> quotesToUpdate = new List<Quote>();

        for (Id quoteId : quoteIds) {
            if (quoteId == null) {
                continue;
            }

            quotesToUpdate.add(
                new Quote(
                    Id = quoteId,
                    Status = resolvedStatus
                )
            );
        }

        updateQuotes(quotesToUpdate);
    }

    @TestVisible
    private static void updateQuotes(List<Quote> quotesToUpdate) {
        if (quotesToUpdate == null || quotesToUpdate.isEmpty()) {
            return;
        }

        Database.SaveResult[] saveResults = Database.update(quotesToUpdate, false, AccessLevel.SYSTEM_MODE);

        for (Database.SaveResult saveResult : saveResults) {
            if (saveResult.isSuccess()) {
                continue;
            }

            List<String> errorMessages = new List<String>();
            for (Database.Error saveError : saveResult.getErrors()) {
                errorMessages.add(saveError.getMessage());
            }

            throw new AuraHandledException(String.join(errorMessages, ' '));
        }
    }
}