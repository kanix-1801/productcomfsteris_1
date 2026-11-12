/**
 * @description GW-5892 / GW-6710: Flow action behind the Work Order "Create Quote" button.
 *              Creates the Field Service quote (header, opportunity, Parts lines from Products Required).
 * @group Field Service Quote
 * @see FieldServiceQuoteService
 */
public with sharing class FieldServiceQuoteCreateAction {
    /**
     * @description Flow input.
     */
    public class Request {
        @InvocableVariable(label='Work Order Id' required=true)
        public Id workOrderId;
    }

    /**
     * @description Flow output.
     */
    public class Result {
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess = false;
        @InvocableVariable(label='Quote Id')
        public Id quoteId;
        @InvocableVariable(label='Has Warnings')
        public Boolean hasWarnings = false;
        @InvocableVariable(label='Message')
        public String message;
    }

    /**
     * @description Creates one Field Service quote per request. Business errors are returned, not thrown,
     *              so the flow can show them on screen.
     * @param requests Flow requests
     * @return One result per request
     */
    @InvocableMethod(
        label='Create Field Service Quote'
        description='GW-5892: Creates a Field Service quote from a Work Order and returns the Quote Id.'
        category='Field Service Quote'
    )
    public static List<Result> createQuotes(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request request : requests) {
            results.add(createQuote(request));
        }
        return results;
    }

    private static Result createQuote(Request request) {
        Result result = new Result();
        try {
            FieldServiceQuoteService.CreateResult created = FieldServiceQuoteService.createFromWorkOrder(
                request?.workOrderId
            );
            result.isSuccess = true;
            result.quoteId = created.quoteId;
            if (!created.skippedProductCodes.isEmpty()) {
                result.hasWarnings = true;
                result.message =
                    'The quote was created, but these Products Required were skipped because they have no active ' +
                    'price in the quote price book and currency: ' +
                    String.join(created.skippedProductCodes, ', ');
            }
        } catch (DmlException ex) {
            result.message = ex.getDmlMessage(0);
        } catch (Exception ex) {
            result.message = ex.getMessage();
        }
        return result;
    }
}