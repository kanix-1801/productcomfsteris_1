/**
 * @author Himanshu Chaurasia
 * @date 2026/07/23
 *
 * @group Forecast Eligible Quotes
 *
 * @description GC-3151 Controller for Update Forecast Eligible Quotes quick action LWC.
 */
public with sharing class UpdateForecastEligibleQuoteController {
    public static final String LOGGER_TAG = UpdateForecastEligibleQuoteService.LOGGER_TAG;
    public static final String SCENARIO = UpdateForecastEligibleQuoteService.SCENARIO;

    /**
     * @description Quote row displayed in the Forecast Eligible management UI.
     */
    public class QuoteRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String quoteNumber;
        @AuraEnabled public String quoteName;
        @AuraEnabled public String status;
        @AuraEnabled public String approvalStatus;
        @AuraEnabled public Decimal quoteTotalWithoutFreight;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public Boolean forecastEligible;
        @AuraEnabled public Boolean forecastEligibleReadOnly;
    }

    /**
     * @description Forecast Eligible update payload from the LWC.
     */
    public class QuoteUpdateRequest {
        @AuraEnabled public Id quoteId;
        @AuraEnabled public Boolean forecastEligible;
    }

    /**
     * @description Loads manageable quotes for an Opportunity.
     * @param opportunityId Opportunity Id.
     * @return Quote rows for display.
     */
    @AuraEnabled
    public static List<QuoteRow> getQuotes(Id opportunityId) {
        try {
            return UpdateForecastEligibleQuoteService.getManageableQuotes(opportunityId);
        } catch (Exception exceptionValue) {
            handleException('Unable to load forecast eligible quotes.', exceptionValue);
            return new List<QuoteRow>();
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Saves Forecast Eligible selections from the LWC.
     * @param opportunityId Opportunity Id.
     * @param updates Selected quote rows.
     */
    @AuraEnabled
    public static void saveForecastEligibleQuotes(Id opportunityId, String updatesJson) {
        try {
            UpdateForecastEligibleQuoteService.saveForecastEligibleSelections(
                opportunityId,
                UpdateForecastEligibleQuoteService.parseUpdateRequests(updatesJson)
            );
        } catch (Exception exceptionValue) {
            handleException('Unable to save forecast eligible quotes.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Logs and rethrows controller exceptions for the LWC.
     * @param message User-facing error message.
     * @param exceptionValue Original exception.
     */
    private static void handleException(String message, Exception exceptionValue) {
        Logger.setScenario(SCENARIO);
        Logger.error(message + ' ' + exceptionValue.getMessage()).addTag(LOGGER_TAG);

        if (exceptionValue instanceof AuraHandledException) {
            throw exceptionValue;
        }

        if (exceptionValue instanceof GenerateQuoteException) {
            throw new AuraHandledException(exceptionValue.getMessage());
        }

        throw new AuraHandledException(message);
    }
}