/**
 * @author Himanshu Chaurasia
 * @date 2026/10/09
 *
 * @description GC-3457 - Boomi business response body for Opportunity / Quote SC events.
 */
public with sharing class ScOpportunityQuoteEventResponse {
    public static final String STATUS_SUCCESS = 'Success';
    public static final String NOT_APPLICABLE = 'N/A';

    public String status { get; private set; }
    public String quoteStatus { get; private set; }
    public String quoteForecastConfidence { get; private set; }

    @TestVisible
    private ScOpportunityQuoteEventResponse() {
    }

    /**
     * @description Parses the Boomi JSON body; returns null when the body is blank.
     */
    public static ScOpportunityQuoteEventResponse parse(String responseBody) {
        if (String.isBlank(responseBody)) {
            return null;
        }

        Object deserialized = JSON.deserializeUntyped(responseBody.trim());

        if (!(deserialized instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> responseMap = (Map<String, Object>) deserialized;
        ScOpportunityQuoteEventResponse response = new ScOpportunityQuoteEventResponse();
        response.status = stringValue(responseMap.get('status'));
        response.quoteStatus = stringValue(responseMap.get('quoteStatus'));
        response.quoteForecastConfidence = stringValue(responseMap.get('quoteForecastConfidence'));
        return response;
    }

    /**
     * @description Parses the quotes array from a Success response body.
     */
    public static List<ScOpportunityQuoteEventRequest.QuoteEntry> parseQuoteEntries(String responseBody) {
        List<ScOpportunityQuoteEventRequest.QuoteEntry> quoteEntries =
            new List<ScOpportunityQuoteEventRequest.QuoteEntry>();

        if (String.isBlank(responseBody)) {
            return quoteEntries;
        }

        Object deserialized = JSON.deserializeUntyped(responseBody.trim());

        if (!(deserialized instanceof Map<String, Object>)) {
            return quoteEntries;
        }

        Map<String, Object> responseMap = (Map<String, Object>) deserialized;
        Object quotesNode = responseMap.get('quotes');

        if (!(quotesNode instanceof List<Object>)) {
            return quoteEntries;
        }

        for (Object quoteNode : (List<Object>) quotesNode) {
            if (!(quoteNode instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> quoteMap = (Map<String, Object>) quoteNode;
            ScOpportunityQuoteEventRequest.QuoteEntry quoteEntry =
                new ScOpportunityQuoteEventRequest.QuoteEntry();
            quoteEntry.salesConnectionQuoteId = stringValue(quoteMap.get('salesConnectionQuoteId'));
            quoteEntry.salesforceQuoteId = stringValue(quoteMap.get('salesforceQuoteId'));
            quoteEntries.add(quoteEntry);
        }

        return quoteEntries;
    }

    /**
     * @description True when Success responses include a quotes list matching the request count.
     */
    public static Boolean hasExpectedQuoteEntries(
        ScOpportunityQuoteEventRequest requestBody,
        String responseBody
    ) {
        if (requestBody == null || requestBody.quotes == null || requestBody.quotes.isEmpty()) {
            return true;
        }

        Integer requestCount = 0;
        for (ScOpportunityQuoteEventRequest.QuoteEntry quoteEntry : requestBody.quotes) {
            if (quoteEntry != null) {
                requestCount++;
            }
        }

        if (requestCount == 0) {
            return true;
        }

        return parseQuoteEntries(responseBody).size() >= requestCount;
    }

    public Boolean isSuccessStatus() {
        return String.isNotBlank(status) && STATUS_SUCCESS.equalsIgnoreCase(status.trim());
    }

    @TestVisible
    private static String stringValue(Object rawValue) {
        return rawValue == null ? null : String.valueOf(rawValue);
    }
}