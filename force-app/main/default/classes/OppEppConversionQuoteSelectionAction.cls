/**
 * @description Gives the Convert to EPP flow the open Sales Connection quotes to review,
 *              and closes only the quotes the user selects.
 */
public with sharing class OppEppConversionQuoteSelectionAction {
    public class Request {
        @InvocableVariable(label='Opportunity Id' required=true)
        public Id opportunityId;

        @InvocableVariable(label='Close Selected Quotes')
        public Boolean closeSelectedQuotes;

        @InvocableVariable(label='Quotes To Close')
        public List<Quote> quotesToClose;
    }

    public class Response {
        @InvocableVariable(label='Open Quotes')
        public List<Quote> openQuotes;
    }

    @InvocableMethod(
        label='Review EPP conversion quotes'
        description='Returns open Sales Connection quotes, or closes the quotes selected before Capital to EPP conversion.'
        category='Opportunity'
    )
    public static List<Response> reviewQuotes(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }

        for (Request requestRecord : requests) {
            Response responseRecord = new Response();
            responseRecord.openQuotes = new List<Quote>();
            if (requestRecord == null || requestRecord.opportunityId == null) {
                responses.add(responseRecord);
                continue;
            }

            if (requestRecord.closeSelectedQuotes == true) {
                OppEppConversionQuoteService.closeSelectedQuotes(
                    requestRecord.opportunityId,
                    quoteIdsFrom(requestRecord.quotesToClose)
                );
            } else {
                responseRecord.openQuotes =
                    QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(requestRecord.opportunityId);
            }
            responses.add(responseRecord);
        }
        return responses;
    }

    private static Set<Id> quoteIdsFrom(List<Quote> quotes) {
        Set<Id> quoteIds = new Set<Id>();
        if (quotes == null) {
            return quoteIds;
        }
        for (Quote quoteRecord : quotes) {
            if (quoteRecord != null && quoteRecord.Id != null) {
                quoteIds.add(quoteRecord.Id);
            }
        }
        return quoteIds;
    }
}