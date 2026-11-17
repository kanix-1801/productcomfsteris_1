/**
* @author Sarthak Pani
* @date 2026/10/28
*
* @group Generate Quote
*
* @description
* GCL-66 Controller class for Generate and Refresh Quote Button on Opportunity for LS.
*/
public with sharing class LSGenerateQuoteController {
    public static final String SCENARIO = 'LS Generate Quote';
    public static final String LOGGER_TAG = 'LSGenerateQuote';

    /**
     * @description Creates a Quote for an Opportunity.
     * @param opportunityId Opportunity Id.
     * @param quoteType Quote Type picklist value to assign on create.
     * @param trialId Optional Trial record Id for Trial Quote creation.
     * @param sampleId Optional Sample record Id for Sample Quote creation.
     * @return Create quote response DTO.
     */
    @AuraEnabled
    public static GenerateQuoteController.CreateQuoteResponse createQuote(
        Id opportunityId,
        String quoteType,
        Id trialId,
        Id sampleId
    ) {
        try {
            new GeneralUtility();   //GCL-66
            return GenerateQuoteService.createQuote(
                opportunityId,
                String.isBlank(quoteType) ? GenerateQuoteService.QUOTE_TYPE_NORMAL : quoteType,
                trialId,
                sampleId
            );
        } catch (Exception exceptionValue) {
            handleException('Unable to create quote.', exceptionValue);
            return null;
        } finally {
            Logger.saveLog();
        }
    }

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