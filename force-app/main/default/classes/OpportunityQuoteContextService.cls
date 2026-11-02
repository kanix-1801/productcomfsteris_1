/**
 * @description REST API for Sales Connection to validate employee access to an Opportunity Quote.
 *              Endpoint: POST /services/apexrest/v1/opportunity-quote-context
 *              Operation: getOpportunityQuoteContext
 * @group Sales Connection Integration
 * #GC-3131
 */
@RestResource(urlMapping='/v1/opportunity-quote-context/*')
global without sharing class OpportunityQuoteContextService {

    @TestVisible
    private static Boolean testHasReadAccessOverride;

    /**
     * @description Accepts opportunity/quote context from Sales Connection and returns access decision.
     */
    @HttpPost
    global static void getOpportunityQuoteContext() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            String requestBody = RestContext.request.requestBody == null
                ? null
                : RestContext.request.requestBody.toString();

            if (String.isBlank(requestBody)) {
                sendError(response, 400, 'Request body is required.');
                return;
            }

            RequestPayload payload = (RequestPayload) JSON.deserialize(requestBody, RequestPayload.class);
            ResponsePayload result = evaluateAccess(payload);

            response.statusCode = 200;
            response.responseBody = Blob.valueOf(JSON.serialize(result, true));
        } catch (JSONException e) {
            sendError(response, 400, 'Invalid JSON payload: ' + e.getMessage());
        } catch (OpportunityQuoteContextException e) {
            Integer statusCode = e.getMessage().startsWith('Opportunity not found') ? 404 : 400;
            sendError(response, statusCode, e.getMessage());
        } catch (Exception e) {
            sendError(response, 500, 'Unexpected error: ' + e.getMessage());
        }
    }

    @TestVisible
    private static ResponsePayload evaluateAccess(RequestPayload payload) {
        validateRequest(payload);

        List<Opportunity> opportunities = [
            SELECT Id
            FROM Opportunity
            WHERE Id = :payload.sfOpportunityId
            LIMIT 1
        ];

        if (opportunities.isEmpty()) {
            throw new OpportunityQuoteContextException(
                'Opportunity not found: ' + payload.sfOpportunityId
            );
        }

        Boolean hasAccess = resolveEmployeeHasAccess(
            payload.scEmployeeNumber,
            opportunities[0].Id
        );

        ResponsePayload response = new ResponsePayload();
        response.sfOpportunityId = payload.sfOpportunityId;
        response.sfQuoteId = payload.sfQuoteId;
        response.scEmployeeNumber = payload.scEmployeeNumber;
        response.scEmployeeHasAccess = hasAccess;

        return response;
    }

    private static Boolean resolveEmployeeHasAccess(
        String scEmployeeNumber,
        Id opportunityId
    ) {
        List<User> users = [
            SELECT Id
            FROM User
            WHERE IsActive = TRUE
            AND (
                EmployeeNumber__c = :scEmployeeNumber
                OR EmployeeNumber = :scEmployeeNumber
            )
            LIMIT 1
        ];

        if (users.isEmpty()) {
            return false;
        }

        if (Test.isRunningTest() && testHasReadAccessOverride != null) {
            return testHasReadAccessOverride;
        }

        List<UserRecordAccess> accessRows = [
            SELECT RecordId, HasReadAccess
            FROM UserRecordAccess
            WHERE UserId = :users[0].Id
            AND RecordId = :opportunityId
            LIMIT 1
        ];

        return !accessRows.isEmpty() && accessRows[0].HasReadAccess;
    }

    private static void validateRequest(RequestPayload payload) {
        if (payload == null) {
            throw new OpportunityQuoteContextException('Request payload is required.');
        }
        if (String.isBlank(payload.sfOpportunityId)) {
            throw new OpportunityQuoteContextException('sfOpportunityId is required.');
        }
        if (String.isBlank(payload.scEmployeeNumber)) {
            throw new OpportunityQuoteContextException('scEmployeeNumber is required.');
        }
    }

    private static void sendError(RestResponse response, Integer statusCode, String message) {
        response.statusCode = statusCode;
        response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'error' => message
        }));
    }

    global class RequestPayload {
        public String sfOpportunityId;
        public String sfQuoteId;
        public String scEmployeeNumber;
    }

    global class ResponsePayload {
        public String sfOpportunityId;
        public String sfQuoteId;
        public String scEmployeeNumber;
        public Boolean scEmployeeHasAccess;
    }

    public class OpportunityQuoteContextException extends Exception {}
}