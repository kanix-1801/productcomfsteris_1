/**
 * @description GW-5890: Starts quote pricing for the Field Service mobile editor.
 *              The mobile app cannot render an embedded screen flow, so the editor calls this
 *              instead of lightning-flow and shows the message the flow returns.
 * @group Field Service Quote
 * @see fieldServiceQuoteEditor
 */
public with sharing class FieldServiceQuotePricingService {
    @TestVisible
    private static final String FLOW_NAME = 'Quote_AL_CalculatePricing';
    private static final String FLOW_INPUT_RECORD = 'recordId';
    private static final String FLOW_OUTPUT_MESSAGE = 'OUT_TXT_Message';
    private static final String STATUS_PRICED = 'Priced';
    private static final String SUCCESS_MESSAGE = 'Pricing calculated.';
    private static final String FAILED_MESSAGE = 'Pricing could not be completed.';

    @TestVisible
    private static Boolean bypassFlow = Test.isRunningTest();
    @TestVisible
    private static String testFlowMessage;

    /** @description Pricing outcome shown in the quote editor. */
    public class PricingResult {
        @AuraEnabled public String status;
        @AuraEnabled public String message;
    }

    /**
     * @description Prices the quote and returns the status and the message to show the technician.
     * @param quoteId Quote Id from the editor
     * @return Status and message
     */
    @AuraEnabled
    public static PricingResult calculatePricing(Id quoteId) {
        if (quoteId == null) {
            throw PlatformUtilities.buildAuraException('A quote is required to calculate pricing.');
        }
        try {
            String flowMessage = bypassFlow
                ? testFlowMessage
                : (String) PlatformUtilities.runFlow(
                      FLOW_NAME,
                      new Map<String, Object>{ FLOW_INPUT_RECORD => new Quote(Id = quoteId) },
                      FLOW_OUTPUT_MESSAGE
                  );
            return toResult(quoteId, flowMessage);
        } catch (Exception ex) {
            throw PlatformUtilities.buildAuraException(PlatformUtilities.firstNonBlank(ex.getMessage(), FAILED_MESSAGE));
        }
    }

    private static PricingResult toResult(Id quoteId, String flowMessage) {
        List<Quote> quotes = QuoteSelector.selectFieldServiceQuoteById(quoteId);
        if (quotes.isEmpty()) {
            throw new FieldServiceQuoteService.FieldServiceQuoteException('Quote was not found.');
        }
        PricingResult result = new PricingResult();
        result.status = quotes[0].PricingStatus__c;
        result.message = String.isNotBlank(flowMessage) ? flowMessage : quotes[0].PricingMessage__c;
        if (String.isBlank(result.message)) {
            result.message = result.status == STATUS_PRICED ? SUCCESS_MESSAGE : FAILED_MESSAGE;
        }
        return result;
    }
}