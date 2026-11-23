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
            throw aura('A quote is required to calculate pricing.');
        }
        try {
            return toResult(quoteId, runFlow(quoteId));
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw aura(ex.getMessage());
        }
    }

    private static String runFlow(Id quoteId) {
        if (bypassFlow) {
            return testFlowMessage;
        }
        Flow.Interview interview = Flow.Interview.createInterview(
            FLOW_NAME,
            new Map<String, Object>{ 'recordId' => new Quote(Id = quoteId) }
        );
        interview.start();
        return (String) interview.getVariableValue('OUT_TXT_Message');
    }

    private static PricingResult toResult(Id quoteId, String flowMessage) {
        List<Quote> quotes = [
            SELECT PricingStatus__c, PricingMessage__c
            FROM Quote
            WHERE Id = :quoteId
            LIMIT 1
        ];
        if (quotes.isEmpty()) {
            throw aura('Quote was not found.');
        }
        PricingResult result = new PricingResult();
        result.status = quotes[0].PricingStatus__c;
        result.message = String.isNotBlank(flowMessage) ? flowMessage : quotes[0].PricingMessage__c;
        if (String.isBlank(result.message)) {
            result.message = result.status == STATUS_PRICED ? SUCCESS_MESSAGE : FAILED_MESSAGE;
        }
        return result;
    }

    private static AuraHandledException aura(String message) {
        String text = String.isBlank(message) ? FAILED_MESSAGE : message;
        AuraHandledException ex = new AuraHandledException(text);
        ex.setMessage(text);
        return ex;
    }
}