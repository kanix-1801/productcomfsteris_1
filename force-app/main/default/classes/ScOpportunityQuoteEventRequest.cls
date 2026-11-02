/**
 * @author Himanshu Chaurasia
 * @date 2026/09/30
 *
 * @description GC-3457 - Outbound payload DTO for Opportunity / Quote events to
 *              Sales Connection via Boomi (ShoutOut SO_Callout).
 */
public with sharing class ScOpportunityQuoteEventRequest {
    public static final String EVENT_TYPE_QUOTE_FORECAST_CONFIDENCE_UPDATE =
        'QUOTE_FORECAST_CONFIDENCE_UPDATE';
    public static final String EVENT_TYPE_OPPORTUNITY_CLOSED_LOST = 'OPPORTUNITY_CLOSED_LOST';
    public static final String EVENT_TYPE_OPPORTUNITY_CONVERTED_TO_EPP_QUOTES_CLOSED =
        'OPPORTUNITY_CONVERTED_TO_EPP_QUOTES_CLOSED';
    public static final String NOT_APPLICABLE_VALUE = 'N/A';
    public static final String QUOTE_STATUS_CLOSED = 'Closed';

    public String eventType { get; private set; }
    public String sfOpportunityId { get; private set; }
    public String forecastConfidence { get; private set; }
    public String opportunityStatus { get; private set; }
    public String quoteStatus { get; private set; }
    public String updatedByHrisId { get; private set; }
    public List<QuoteEntry> quotes { get; private set; }

    public class QuoteEntry {
        public String salesConnectionQuoteId { get; set; }
        public String salesforceQuoteId { get; set; }
    }

    public static ScOpportunityQuoteEventRequest createForecastConfidenceUpdate(
        Id opportunityId,
        String forecastConfidenceValue,
        List<QuoteEntry> quoteEntries,
        String updatedByHrisIdValue
    ) {
        ScOpportunityQuoteEventRequest request = new ScOpportunityQuoteEventRequest();
        request.eventType = EVENT_TYPE_QUOTE_FORECAST_CONFIDENCE_UPDATE;
        request.sfOpportunityId = String.valueOf(opportunityId);
        request.forecastConfidence = forecastConfidenceValue;
        request.opportunityStatus = NOT_APPLICABLE_VALUE;
        request.quoteStatus = NOT_APPLICABLE_VALUE;
        request.updatedByHrisId = updatedByHrisIdValue;
        request.quotes = quoteEntries == null ? new List<QuoteEntry>() : quoteEntries;
        return request;
    }

    public static ScOpportunityQuoteEventRequest createOpportunityClosedLost(
        Id opportunityId,
        String opportunityStatusValue,
        List<QuoteEntry> quoteEntries,
        String updatedByHrisIdValue
    ) {
        ScOpportunityQuoteEventRequest request = new ScOpportunityQuoteEventRequest();
        request.eventType = EVENT_TYPE_OPPORTUNITY_CLOSED_LOST;
        request.sfOpportunityId = String.valueOf(opportunityId);
        request.opportunityStatus = opportunityStatusValue;
        request.forecastConfidence = NOT_APPLICABLE_VALUE;
        request.quoteStatus = QUOTE_STATUS_CLOSED;
        request.updatedByHrisId = updatedByHrisIdValue;
        request.quotes = quoteEntries == null ? new List<QuoteEntry>() : quoteEntries;
        return request;
    }

    public static ScOpportunityQuoteEventRequest createOpportunityConvertedToEppQuotesClosed(
        Id opportunityId,
        List<QuoteEntry> quoteEntries,
        String updatedByHrisIdValue
    ) {
        ScOpportunityQuoteEventRequest request = new ScOpportunityQuoteEventRequest();
        request.eventType = EVENT_TYPE_OPPORTUNITY_CONVERTED_TO_EPP_QUOTES_CLOSED;
        request.sfOpportunityId = String.valueOf(opportunityId);
        request.opportunityStatus = NOT_APPLICABLE_VALUE;
        request.forecastConfidence = NOT_APPLICABLE_VALUE;
        request.quoteStatus = QUOTE_STATUS_CLOSED;
        request.updatedByHrisId = updatedByHrisIdValue;
        request.quotes = quoteEntries == null ? new List<QuoteEntry>() : quoteEntries;
        return request;
    }

    /**
     * @description Serializes the payload with the agreed JSON keys.
     */
    public Map<String, Object> toJsonMap() {
        List<Map<String, Object>> quoteMaps = new List<Map<String, Object>>();

        if (quotes != null) {
            for (QuoteEntry quoteEntry : quotes) {
                if (quoteEntry == null) {
                    continue;
                }

                quoteMaps.add(
                    new Map<String, Object>{
                        'salesConnectionQuoteId' => quoteEntry.salesConnectionQuoteId,
                        'salesforceQuoteId' => quoteEntry.salesforceQuoteId
                    }
                );
            }
        }

        Map<String, Object> payload = new Map<String, Object>{
            'eventType' => eventType,
            'sfOpportunityId' => sfOpportunityId,
            'updatedByHrisId' => updatedByHrisId,
            'quotes' => quoteMaps
        };

        if (EVENT_TYPE_QUOTE_FORECAST_CONFIDENCE_UPDATE.equals(eventType)) {
            payload.put('forecastConfidence', forecastConfidence);
            payload.put('opportunityStatus', opportunityStatus);
            payload.put('quoteStatus', quoteStatus);
        }

        if (EVENT_TYPE_OPPORTUNITY_CLOSED_LOST.equals(eventType)) {
            payload.put('opportunityStatus', opportunityStatus);
            payload.put('forecastConfidence', forecastConfidence);
            payload.put('quoteStatus', quoteStatus);
        }

        if (EVENT_TYPE_OPPORTUNITY_CONVERTED_TO_EPP_QUOTES_CLOSED.equals(eventType)) {
            payload.put('opportunityStatus', opportunityStatus);
            payload.put('forecastConfidence', forecastConfidence);
            payload.put('quoteStatus', quoteStatus);
        }

        return payload;
    }
}