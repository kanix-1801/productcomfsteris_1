/**
 * @author Himanshu Chaurasia
 * @date 2026/07/23
 *
 * @group Forecast Eligible Quotes
 *
 * @description GC-3151 Loads and saves Forecast Eligible selections on Opportunity quotes.
 */
public with sharing class UpdateForecastEligibleQuoteService {
    public static final String LOGGER_TAG = 'UpdateForecastEligibleQuote';
    public static final String SCENARIO = 'Update Forecast Eligible Quotes';
    public static final String AT_LEAST_ONE_FORECAST_ELIGIBLE_ERROR =
        'At least one Quote must be selected as Forecast Eligible.';

    /**
     * @description Returns quotes that can be managed in the Forecast Eligible UI.
     *              Excludes forecast-ineligible quotes. Does not run auto-designation;
     *              the modal reflects current saved values and only user selections
     *              from Proceed should change Forecast Eligible.
     * @param opportunityId Opportunity Id.
     * @return Quote rows for the LWC.
     */
    public static List<UpdateForecastEligibleQuoteController.QuoteRow> getManageableQuotes(Id opportunityId) {
        GenerateQuoteService.validateQuoteAccess(opportunityId);

        List<Quote> quoteRecords = QuoteSelector.selectForecastManagementQuotesByOpportunityId(opportunityId);
        List<UpdateForecastEligibleQuoteController.QuoteRow> quoteRows =
            new List<UpdateForecastEligibleQuoteController.QuoteRow>();

        for (Quote quoteRecord : quoteRecords) {
            quoteRows.add(mapQuoteToRow(quoteRecord));
        }

        return quoteRows;
    }

    /**
     * @description Deserializes Forecast Eligible update payload from the LWC.
     * @param updatesJson JSON array of quoteId and forecastEligible values.
     * @return Parsed update requests.
     */
    public static List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest> parseUpdateRequests(
        String updatesJson
    ) {
        List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest> parsedUpdates =
            new List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest>();

        if (String.isBlank(updatesJson)) {
            return parsedUpdates;
        }

        Object deserializedPayload = JSON.deserializeUntyped(updatesJson);
        if (!(deserializedPayload instanceof List<Object>)) {
            throw new GenerateQuoteException('Invalid forecast eligible update payload.');
        }

        for (Object rowValue : (List<Object>) deserializedPayload) {
            if (!(rowValue instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> rowMap = (Map<String, Object>) rowValue;
            Object quoteIdValue = rowMap.get('quoteId');
            if (quoteIdValue == null) {
                continue;
            }

            UpdateForecastEligibleQuoteController.QuoteUpdateRequest updateRequest =
                new UpdateForecastEligibleQuoteController.QuoteUpdateRequest();
            updateRequest.quoteId = (Id) String.valueOf(quoteIdValue);
            updateRequest.forecastEligible = parseBooleanValue(rowMap.get('forecastEligible'));
            parsedUpdates.add(updateRequest);
        }

        return parsedUpdates;
    }

    /**
     * @description Persists Forecast Eligible checkbox selections for manageable quotes.
     * @param opportunityId Opportunity Id.
     * @param updates Parsed quote update requests from the LWC.
     */
    public static void saveForecastEligibleSelections(
        Id opportunityId,
        List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest> updates
    ) {
        GenerateQuoteService.validateQuoteAccess(opportunityId);

        if (updates == null || updates.isEmpty()) {
            throw new GenerateQuoteException('Select at least one quote to update.');
        }

        Map<Id, Quote> manageableQuotesById = new Map<Id, Quote>(
            QuoteSelector.selectForecastManagementQuotesByOpportunityId(opportunityId)
        );

        if (manageableQuotesById.isEmpty()) {
            throw new GenerateQuoteException('No forecast-eligible quotes are available to update.');
        }

        Map<Id, Boolean> finalForecastEligibleByQuoteId = buildFinalForecastEligibleSelections(
            manageableQuotesById,
            updates
        );

        if (!hasAtLeastOneForecastEligibleSelection(finalForecastEligibleByQuoteId)) {
            throw new GenerateQuoteException(AT_LEAST_ONE_FORECAST_ELIGIBLE_ERROR);
        }

        List<Quote> quotesToUpdate = new List<Quote>();
        Integer validUpdateCount = 0;

        for (UpdateForecastEligibleQuoteController.QuoteUpdateRequest updateRequest : updates) {
            if (updateRequest == null || updateRequest.quoteId == null) {
                continue;
            }

            validUpdateCount++;

            Quote existingQuote = manageableQuotesById.get(updateRequest.quoteId);
            if (existingQuote == null) {
                throw new GenerateQuoteException(
                    'One or more selected quotes are not eligible for forecast management.'
                );
            }

            Boolean requestedValue = finalForecastEligibleByQuoteId.get(updateRequest.quoteId) == true;
            if (existingQuote.Forecast_Eligible__c == requestedValue) {
                continue;
            }

            quotesToUpdate.add(
                new Quote(
                    Id = existingQuote.Id,
                    Forecast_Eligible__c = requestedValue
                )
            );
        }

        if (validUpdateCount == 0) {
            throw new GenerateQuoteException('Quote update payload was invalid.');
        }

        if (quotesToUpdate.isEmpty()) {
            return;
        }

        updateQuotes(quotesToUpdate);
    }

    /**
     * @description Parses boolean values from JSON payload entries.
     * @param rawValue Raw value from the LWC payload.
     * @return Parsed Boolean value.
     */
    private static Boolean parseBooleanValue(Object rawValue) {
        if (rawValue instanceof Boolean) {
            return (Boolean) rawValue;
        }

        if (rawValue instanceof String) {
            return 'true'.equalsIgnoreCase((String) rawValue);
        }

        return false;
    }

    /**
     * @description Builds the final Forecast Eligible selection map after applying UI updates.
     * @param manageableQuotesById Manageable quotes keyed by Quote Id.
     * @param updates Parsed update requests from the LWC.
     * @return Final Forecast Eligible value per manageable Quote Id.
     */
    @TestVisible
    private static Map<Id, Boolean> buildFinalForecastEligibleSelections(
        Map<Id, Quote> manageableQuotesById,
        List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest> updates
    ) {
        Map<Id, Boolean> finalSelections = new Map<Id, Boolean>();

        for (Quote quoteRecord : manageableQuotesById.values()) {
            finalSelections.put(quoteRecord.Id, quoteRecord.Forecast_Eligible__c == true);
        }

        if (updates == null) {
            return finalSelections;
        }

        for (UpdateForecastEligibleQuoteController.QuoteUpdateRequest updateRequest : updates) {
            if (updateRequest == null || updateRequest.quoteId == null) {
                continue;
            }

            if (!manageableQuotesById.containsKey(updateRequest.quoteId)) {
                continue;
            }

            finalSelections.put(updateRequest.quoteId, updateRequest.forecastEligible == true);
        }

        return finalSelections;
    }

    @TestVisible
    private static Boolean hasAtLeastOneForecastEligibleSelection(Map<Id, Boolean> finalSelections) {
        if (finalSelections == null || finalSelections.isEmpty()) {
            return false;
        }

        for (Boolean isSelected : finalSelections.values()) {
            if (isSelected == true) {
                return true;
            }
        }

        return false;
    }

    /**
     * @description Maps a Quote record to the Forecast Eligible management UI row.
     * @param quoteRecord Quote queried for the Opportunity.
     * @return UI row wrapper.
     */
    private static UpdateForecastEligibleQuoteController.QuoteRow mapQuoteToRow(Quote quoteRecord) {
        UpdateForecastEligibleQuoteController.QuoteRow quoteRow =
            new UpdateForecastEligibleQuoteController.QuoteRow();
        quoteRow.id = quoteRecord.Id;
        quoteRow.quoteNumber = quoteRecord.QuoteNumber__c;
        quoteRow.quoteName = quoteRecord.Name;
        quoteRow.status = quoteRecord.Status;
        quoteRow.approvalStatus = quoteRecord.Approval_Status__c;
        quoteRow.quoteTotalWithoutFreight = QuoteService.resolveQuoteTotalWithoutFreight(
            quoteRecord,
            quoteRecord.QuoteLineItems
        );
        quoteRow.lastModifiedDate = QuoteService.resolveLastModifiedDate(quoteRecord);
        quoteRow.forecastEligible = quoteRecord.Forecast_Eligible__c == true;
        quoteRow.forecastEligibleReadOnly = false;
        return quoteRow;
    }

    /**
     * @description Updates Forecast Eligible selections while bypassing QuoteTrigger automation.
     * @param quotesToUpdate Quote rows to persist.
     */
    private static void updateQuotes(List<Quote> quotesToUpdate) {
        TriggerHandler.bypass('QuoteTriggerHandler');

        try {
            Database.SaveResult[] saveResults = Database.update(quotesToUpdate, false, AccessLevel.SYSTEM_MODE);

            for (Database.SaveResult saveResult : saveResults) {
                if (saveResult.isSuccess()) {
                    continue;
                }

                List<String> errorMessages = new List<String>();
                for (Database.Error saveError : saveResult.getErrors()) {
                    errorMessages.add(saveError.getMessage());
                }

                throw new GenerateQuoteException(String.join(errorMessages, ' '));
            }

            QuoteForecastChangeNotificationHandler.stageFromForecastEligibleQuoteIds(
                new Map<Id, Quote>(quotesToUpdate).keySet()
            );
        } finally {
            TriggerHandler.clearBypass('QuoteTriggerHandler');
        }
    }
}