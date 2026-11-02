/**
 * @author Himanshu Chaurasia
 * @date 2026/09/30
 *
 * @description GC-3457 - Synchronous Sales Connection Opportunity / Quote events:
 *              callout to Boomi first, then Salesforce Quote DML on Success response.
 */
public with sharing class ScOpportunityQuoteEventService {
    private static final String CLASS_NAME = 'ScOpportunityQuoteEventService';
    public static final String NO_SALES_CONNECTION_QUOTE_ID_MESSAGE =
        'At least one Quote must have a Sales Connection Quote Id before Salesforce can sync with Sales Connection.';
    public static final String EMPTY_RESPONSE_QUOTES_MESSAGE =
        'Sales Connection returned Success but did not return the synced quotes in the response body. ' +
        'The integration must echo each salesConnectionQuoteId and salesforceQuoteId in the quotes array.';
    public static final String NO_MATCHING_RESPONSE_QUOTES_MESSAGE =
        'Sales Connection returned quotes that could not be matched to the selected Salesforce Quotes ' +
        'by Sales Connection Quote Id on this Opportunity.';

    /**
     * @description Sends forecast confidence to SC and updates Quote records when Boomi succeeds.
     */
    public static void synchronizeForecastConfidenceUpdate(
        Id opportunityId,
        String forecastConfidence,
        Set<Id> quoteIds,
        Id updatedByUserId
    ) {
        Logger.setScenario('GC-3457 Opportunity Quote SC Events');

        try {
            validateSyncInputs(opportunityId, quoteIds, updatedByUserId);
            if (String.isBlank(forecastConfidence)) {
                throw new AuraHandledException('Forecast confidence is required for Sales Connection sync.');
            }

            List<Quote> quoteRecords = ScOpportunityQuoteEventSelector.selectQuotesByIds(quoteIds);
            User updatedByUser = resolveUpdatedByUser(updatedByUserId);
            ScOpportunityQuoteEventRequest requestBody =
                ScOpportunityQuoteEventMapper.toForecastConfidenceUpdateRequest(
                    opportunityId,
                    forecastConfidence,
                    quoteRecords,
                    updatedByUser
                );

            Set<Id> quoteIdsWithSalesConnectionId = filterQuoteIdsWithSalesConnectionId(quoteRecords);
            requireQuotesWithSalesConnectionId(quoteIdsWithSalesConnectionId);

            ScOpportunityQuoteEventGateway.CalloutResult calloutResult =
                ScOpportunityQuoteEventGateway.sendEvent(requestBody);
            handleCalloutResult(calloutResult);
            validateSuccessResponseQuotes(requestBody, calloutResult.responseBody);

            ScOpportunityQuoteEventResponse response =
                ScOpportunityQuoteEventResponse.parse(calloutResult.responseBody);
            String appliedConfidence = resolveForecastConfidenceForApply(
                response,
                forecastConfidence
            );
            Set<Id> quoteIdsToUpdate = resolveQuoteIdsFromResponse(
                opportunityId,
                calloutResult.responseBody,
                quoteIdsWithSalesConnectionId
            );
            ScOpportunityQuoteEventApplyService.applyForecastConfidence(
                quoteIdsToUpdate,
                appliedConfidence
            );
        } catch (AuraHandledException exceptionValue) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            Logger.error(CLASS_NAME + '.synchronizeForecastConfidenceUpdate', exceptionValue)
                .addTag('GC-3457');
            throw new AuraHandledException(
                'Unable to sync forecast confidence with Sales Connection: ' + exceptionValue.getMessage()
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Sends Capital → EPP quote closure to SC and updates Quote status when Boomi succeeds (UC3).
     */
    public static void synchronizeEppConversionQuoteClosure(
        Id opportunityId,
        Set<Id> quoteIds,
        Id updatedByUserId
    ) {
        Logger.setScenario('GC-3457 Opportunity Quote SC Events');

        try {
            validateSyncInputs(opportunityId, quoteIds, updatedByUserId);

            List<Quote> quoteRecords = ScOpportunityQuoteEventSelector.selectQuotesByIds(quoteIds);
            User updatedByUser = resolveUpdatedByUser(updatedByUserId);
            ScOpportunityQuoteEventRequest requestBody =
                ScOpportunityQuoteEventMapper.toOpportunityConvertedToEppQuotesClosedRequest(
                    opportunityId,
                    quoteRecords,
                    updatedByUser
                );

            Set<Id> quoteIdsWithSalesConnectionId = filterQuoteIdsWithSalesConnectionId(quoteRecords);
            requireQuotesWithSalesConnectionId(quoteIdsWithSalesConnectionId);

            ScOpportunityQuoteEventGateway.CalloutResult calloutResult =
                ScOpportunityQuoteEventGateway.sendEvent(requestBody);
            handleCalloutResult(calloutResult);
            validateSuccessResponseQuotes(requestBody, calloutResult.responseBody);

            ScOpportunityQuoteEventResponse response =
                ScOpportunityQuoteEventResponse.parse(calloutResult.responseBody);
            String appliedStatus = resolveQuoteStatusForApply(
                response,
                ScOpportunityQuoteEventRequest.QUOTE_STATUS_CLOSED
            );
            Set<Id> quoteIdsToUpdate = resolveQuoteIdsFromResponse(
                opportunityId,
                calloutResult.responseBody,
                quoteIdsWithSalesConnectionId
            );
            ScOpportunityQuoteEventApplyService.applyQuoteStatus(
                quoteIdsToUpdate,
                appliedStatus
            );
        } catch (AuraHandledException exceptionValue) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            Logger.error(CLASS_NAME + '.synchronizeEppConversionQuoteClosure', exceptionValue)
                .addTag('GC-3457');
            throw new AuraHandledException(
                'Unable to close quotes in Sales Connection after EPP conversion: ' +
                exceptionValue.getMessage()
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Sends Closed Lost quote closure to SC and updates Quote status when Boomi succeeds.
     */
    public static void synchronizeClosedLostQuoteClosure(
        Id opportunityId,
        Set<Id> quoteIds,
        Id updatedByUserId
    ) {
        Logger.setScenario('GC-3457 Opportunity Quote SC Events');

        try {
            validateSyncInputs(opportunityId, quoteIds, updatedByUserId);

            List<Quote> quoteRecords = ScOpportunityQuoteEventSelector.selectQuotesByIds(quoteIds);
            User updatedByUser = resolveUpdatedByUser(updatedByUserId);
            ScOpportunityQuoteEventRequest requestBody =
                ScOpportunityQuoteEventMapper.toOpportunityClosedLostRequest(
                    opportunityId,
                    quoteRecords,
                    updatedByUser
                );

            Set<Id> quoteIdsWithSalesConnectionId = filterQuoteIdsWithSalesConnectionId(quoteRecords);
            requireQuotesWithSalesConnectionId(quoteIdsWithSalesConnectionId);

            ScOpportunityQuoteEventGateway.CalloutResult calloutResult =
                ScOpportunityQuoteEventGateway.sendEvent(requestBody);
            handleCalloutResult(calloutResult);
            validateSuccessResponseQuotes(requestBody, calloutResult.responseBody);

            ScOpportunityQuoteEventResponse response =
                ScOpportunityQuoteEventResponse.parse(calloutResult.responseBody);
            String appliedStatus = resolveQuoteStatusForApply(
                response,
                ScOpportunityQuoteEventRequest.QUOTE_STATUS_CLOSED
            );
            Set<Id> quoteIdsToUpdate = resolveQuoteIdsFromResponse(
                opportunityId,
                calloutResult.responseBody,
                quoteIdsWithSalesConnectionId
            );
            ScOpportunityQuoteEventApplyService.applyQuoteStatus(
                quoteIdsToUpdate,
                appliedStatus
            );
        } catch (AuraHandledException exceptionValue) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            Logger.error(CLASS_NAME + '.synchronizeClosedLostQuoteClosure', exceptionValue)
                .addTag('GC-3457');
            throw new AuraHandledException(
                'Unable to close quotes in Sales Connection: ' + exceptionValue.getMessage()
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description True when at least one quote in the set has a Sales Connection Quote Id.
     */
    public static Boolean hasQuotesWithSalesConnectionId(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return false;
        }

        for (Quote quoteRecord : ScOpportunityQuoteEventSelector.selectQuotesByIds(quoteIds)) {
            if (String.isNotBlank(quoteRecord.SalesConnectionQuoteID__c)) {
                return true;
            }
        }

        return false;
    }

    @TestVisible
    private static void requireQuotesWithSalesConnectionId(Set<Id> quoteIdsWithSalesConnectionId) {
        if (quoteIdsWithSalesConnectionId == null || quoteIdsWithSalesConnectionId.isEmpty()) {
            throw new AuraHandledException(NO_SALES_CONNECTION_QUOTE_ID_MESSAGE);
        }
    }

    @TestVisible
    private static Set<Id> filterQuoteIdsWithSalesConnectionId(List<Quote> quoteRecords) {
        Set<Id> quoteIdsWithSalesConnectionId = new Set<Id>();

        if (quoteRecords == null) {
            return quoteIdsWithSalesConnectionId;
        }

        for (Quote quoteRecord : quoteRecords) {
            if (quoteRecord == null || quoteRecord.Id == null) {
                continue;
            }

            if (String.isNotBlank(quoteRecord.SalesConnectionQuoteID__c)) {
                quoteIdsWithSalesConnectionId.add(quoteRecord.Id);
            }
        }

        return quoteIdsWithSalesConnectionId;
    }

    @TestVisible
    private static void validateSyncInputs(Id opportunityId, Set<Id> quoteIds, Id updatedByUserId) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }

        if (quoteIds == null || quoteIds.isEmpty()) {
            throw new AuraHandledException('At least one Quote is required.');
        }

        if (updatedByUserId == null) {
            throw new AuraHandledException('The user who performed this action could not be resolved.');
        }
    }

    /**
     * @description Resolves Salesforce Quote Ids to update from the SC response quotes array,
     *              matching Quote.SalesConnectionQuoteID__c on the Opportunity (selected quotes only).
     */
    @TestVisible
    private static Set<Id> resolveQuoteIdsFromResponse(
        Id opportunityId,
        String responseBody,
        Set<Id> requestedQuoteIdsWithSalesConnectionId
    ) {
        if (requestedQuoteIdsWithSalesConnectionId == null || requestedQuoteIdsWithSalesConnectionId.isEmpty()) {
            throw new AuraHandledException(NO_SALES_CONNECTION_QUOTE_ID_MESSAGE);
        }

        Set<String> salesConnectionQuoteIds = collectSalesConnectionQuoteIdsFromResponse(responseBody);
        Set<Id> matchedQuoteIds = new Set<Id>();

        if (!salesConnectionQuoteIds.isEmpty()) {
            for (Quote quoteRecord : ScOpportunityQuoteEventSelector.selectQuotesBySalesConnectionIds(
                opportunityId,
                salesConnectionQuoteIds
            )) {
                if (
                    quoteRecord != null &&
                    quoteRecord.Id != null &&
                    requestedQuoteIdsWithSalesConnectionId.contains(quoteRecord.Id)
                ) {
                    matchedQuoteIds.add(quoteRecord.Id);
                }
            }
        }

        if (matchedQuoteIds.isEmpty()) {
            throw new AuraHandledException(NO_MATCHING_RESPONSE_QUOTES_MESSAGE);
        }

        return matchedQuoteIds;
    }

    @TestVisible
    private static Set<String> collectSalesConnectionQuoteIdsFromResponse(String responseBody) {
        Set<String> salesConnectionQuoteIds = new Set<String>();

        for (ScOpportunityQuoteEventRequest.QuoteEntry quoteEntry :
            ScOpportunityQuoteEventResponse.parseQuoteEntries(responseBody)
        ) {
            if (quoteEntry == null || String.isBlank(quoteEntry.salesConnectionQuoteId)) {
                continue;
            }

            salesConnectionQuoteIds.add(quoteEntry.salesConnectionQuoteId.trim());
        }

        return salesConnectionQuoteIds;
    }

    @TestVisible
    private static void validateSuccessResponseQuotes(
        ScOpportunityQuoteEventRequest requestBody,
        String responseBody
    ) {
        if (
            !ScOpportunityQuoteEventResponse.hasExpectedQuoteEntries(requestBody, responseBody)
        ) {
            throw new AuraHandledException(EMPTY_RESPONSE_QUOTES_MESSAGE);
        }
    }

    @TestVisible
    private static void handleCalloutResult(ScOpportunityQuoteEventGateway.CalloutResult calloutResult) {
        if (calloutResult == null) {
            throw new AuraHandledException('Sales Connection did not return a response.');
        }

        if (calloutResult.retryEnqueued == true) {
            throw new AuraHandledException(
                'Sales Connection sync was queued for retry. Quote records were not updated.'
            );
        }

        if (calloutResult.calloutSuccess != true) {
            String detail = String.isNotBlank(calloutResult.errorDetail)
                ? calloutResult.errorDetail
                : 'Sales Connection rejected the update.';
            throw new AuraHandledException(detail);
        }
    }

    @TestVisible
    private static String resolveForecastConfidenceForApply(
        ScOpportunityQuoteEventResponse response,
        String requestForecastConfidence
    ) {
        if (response != null && String.isNotBlank(response.quoteForecastConfidence)) {
            return response.quoteForecastConfidence.trim();
        }

        return requestForecastConfidence;
    }

    @TestVisible
    private static String resolveQuoteStatusForApply(
        ScOpportunityQuoteEventResponse response,
        String defaultStatus
    ) {
        if (response != null && String.isNotBlank(response.quoteStatus)) {
            String responseStatus = response.quoteStatus.trim();
            if (!ScOpportunityQuoteEventRequest.NOT_APPLICABLE_VALUE.equalsIgnoreCase(responseStatus)) {
                return responseStatus;
            }
        }

        return defaultStatus;
    }

    @TestVisible
    private static User resolveUpdatedByUser(Id userId) {
        List<User> users = UserSelector.selectByIds(new Set<Id>{ userId });
        return users.isEmpty() ? null : users[0];
    }
}