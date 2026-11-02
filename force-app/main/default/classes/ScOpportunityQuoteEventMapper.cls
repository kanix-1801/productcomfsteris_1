/**
 * @author Himanshu Chaurasia
 * @date 2026/09/30
 *
 * @description GC-3457 - Maps Salesforce Opportunity / Quote data to SC event payloads.
 */
public with sharing class ScOpportunityQuoteEventMapper {
    private static final String CLOSED_LOST_STATUS = 'Closed Lost';

    /**
     * @description Builds a forecast confidence propagation payload.
     */
    public static ScOpportunityQuoteEventRequest toForecastConfidenceUpdateRequest(
        Id opportunityId,
        String forecastConfidence,
        List<Quote> quoteRecords,
        User updatedByUser
    ) {
        if (opportunityId == null) {
            throw new IllegalArgumentException('Opportunity Id is required.');
        }

        if (String.isBlank(forecastConfidence)) {
            throw new IllegalArgumentException('Forecast confidence is required.');
        }

        return ScOpportunityQuoteEventRequest.createForecastConfidenceUpdate(
            opportunityId,
            forecastConfidence,
            toQuoteEntries(quoteRecords),
            resolveHrisId(updatedByUser)
        );
    }

    /**
     * @description Builds a Closed Lost quote closure payload.
     */
    public static ScOpportunityQuoteEventRequest toOpportunityClosedLostRequest(
        Id opportunityId,
        List<Quote> quoteRecords,
        User updatedByUser
    ) {
        if (opportunityId == null) {
            throw new IllegalArgumentException('Opportunity Id is required.');
        }

        return ScOpportunityQuoteEventRequest.createOpportunityClosedLost(
            opportunityId,
            CLOSED_LOST_STATUS,
            toQuoteEntries(quoteRecords),
            resolveHrisId(updatedByUser)
        );
    }

    /**
     * @description Builds Capital → EPP conversion quote closure payload (UC3).
     */
    public static ScOpportunityQuoteEventRequest toOpportunityConvertedToEppQuotesClosedRequest(
        Id opportunityId,
        List<Quote> quoteRecords,
        User updatedByUser
    ) {
        if (opportunityId == null) {
            throw new IllegalArgumentException('Opportunity Id is required.');
        }

        return ScOpportunityQuoteEventRequest.createOpportunityConvertedToEppQuotesClosed(
            opportunityId,
            toQuoteEntries(quoteRecords),
            resolveHrisId(updatedByUser)
        );
    }

    @TestVisible
    private static List<ScOpportunityQuoteEventRequest.QuoteEntry> toQuoteEntries(List<Quote> quoteRecords) {
        List<ScOpportunityQuoteEventRequest.QuoteEntry> quoteEntries =
            new List<ScOpportunityQuoteEventRequest.QuoteEntry>();

        if (quoteRecords == null || quoteRecords.isEmpty()) {
            return quoteEntries;
        }

        for (Quote quoteRecord : quoteRecords) {
            if (quoteRecord == null || quoteRecord.Id == null) {
                continue;
            }

            if (String.isBlank(quoteRecord.SalesConnectionQuoteID__c)) {
                continue;
            }

            ScOpportunityQuoteEventRequest.QuoteEntry quoteEntry =
                new ScOpportunityQuoteEventRequest.QuoteEntry();
            quoteEntry.salesConnectionQuoteId = quoteRecord.SalesConnectionQuoteID__c.trim();
            quoteEntry.salesforceQuoteId = String.valueOf(quoteRecord.Id);
            quoteEntries.add(quoteEntry);
        }

        return quoteEntries;
    }

    @TestVisible
    private static String resolveHrisId(User updatedByUser) {
        if (updatedByUser == null) {
            return null;
        }

        if (String.isNotBlank(updatedByUser.EmployeeNumber__c)) {
            return updatedByUser.EmployeeNumber__c.trim();
        }

        if (String.isNotBlank(updatedByUser.EmployeeNumber)) {
            return updatedByUser.EmployeeNumber.trim();
        }

        return null;
    }
}