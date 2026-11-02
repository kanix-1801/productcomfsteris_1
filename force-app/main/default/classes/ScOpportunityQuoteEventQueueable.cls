/**
 * @author Himanshu Chaurasia
 * @date 2026/09/30
 *
 * @description GC-3457 - Deprecated async wrapper; production uses synchronous
 *              ScOpportunityQuoteEventService. Kept for backward-compatible tests.
 */
public with sharing class ScOpportunityQuoteEventQueueable
    implements Queueable, Database.AllowsCallouts {

    private final Id opportunityId;
    private final String eventType;
    private final String forecastConfidence;
    private final Set<Id> quoteIds;
    private final Id updatedByUserId;

    public ScOpportunityQuoteEventQueueable(
        Id opportunityId,
        String eventType,
        String forecastConfidence,
        Set<Id> quoteIds,
        Id updatedByUserId
    ) {
        this.opportunityId = opportunityId;
        this.eventType = eventType;
        this.forecastConfidence = forecastConfidence;
        this.quoteIds = quoteIds == null ? new Set<Id>() : new Set<Id>(quoteIds);
        this.updatedByUserId = updatedByUserId;
    }

    public void execute(QueueableContext context) {
        if (ScOpportunityQuoteEventRequest.EVENT_TYPE_QUOTE_FORECAST_CONFIDENCE_UPDATE.equals(eventType)) {
            ScOpportunityQuoteEventService.synchronizeForecastConfidenceUpdate(
                opportunityId,
                forecastConfidence,
                quoteIds,
                updatedByUserId
            );
            return;
        }

        if (ScOpportunityQuoteEventRequest.EVENT_TYPE_OPPORTUNITY_CLOSED_LOST.equals(eventType)) {
            ScOpportunityQuoteEventService.synchronizeClosedLostQuoteClosure(
                opportunityId,
                quoteIds,
                updatedByUserId
            );
            return;
        }

        if (
            ScOpportunityQuoteEventRequest.EVENT_TYPE_OPPORTUNITY_CONVERTED_TO_EPP_QUOTES_CLOSED.equals(
                eventType
            )
        ) {
            ScOpportunityQuoteEventService.synchronizeEppConversionQuoteClosure(
                opportunityId,
                quoteIds,
                updatedByUserId
            );
        }
    }
}