/**
 * @description GW-4006 Mod Request Form email preview and send for Instrument Work Orders on Mod Hold.
 */
public with sharing class ModRequestFormEmailService {
    /**
     * @description Flow input for Mod Request Form email preview or send.
     */
    public class Request {
        @InvocableVariable(label='Work Order Id' required=true)
        public Id workOrderId;

        @InvocableVariable(label='Operation' required=true description='Preview or Send')
        public String operation;

        @InvocableVariable(label='To Address')
        public String toAddress;

        @InvocableVariable(label='Subject')
        public String subject;

        @InvocableVariable(label='HTML Body')
        public String htmlBody;
    }

    /**
     * @description Flow output for Mod Request Form email preview or send.
     */
    public class Response {
        @InvocableVariable(label='Eligible')
        public Boolean eligible;

        @InvocableVariable(label='To Address')
        public String toAddress;

        @InvocableVariable(label='Subject')
        public String subject;

        @InvocableVariable(label='HTML Body')
        public String htmlBody;

        @InvocableVariable(label='Template Name')
        public String templateName;

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    /**
     * @description Delegates the Screen Flow request to the Work Order service layer.
     * @param requests Flow requests to preview or send Mod Request Form emails
     * @return One Flow response per request, in the same order
     */
    @InvocableMethod(
        label='Mod Request Form Email'
        description='GW-4006 Preview or send Mod Request Form email from a Work Order.'
    )
    public static List<Response> process(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }

        List<WorkOrdersService.ModRequestFormEmailRequest> serviceRequests =
            new List<WorkOrdersService.ModRequestFormEmailRequest>();
        for (Request request : requests) {
            serviceRequests.add(toServiceRequest(request));
        }
        for (WorkOrdersService.ModRequestFormEmailResponse serviceResponse :
            WorkOrdersService.processModRequestFormEmails(serviceRequests)) {
            responses.add(toFlowResponse(serviceResponse));
        }
        return responses;
    }

    private static WorkOrdersService.ModRequestFormEmailRequest toServiceRequest(
        Request request
    ) {
        if (request == null) {
            return null;
        }

        WorkOrdersService.ModRequestFormEmailRequest serviceRequest =
            new WorkOrdersService.ModRequestFormEmailRequest();
        serviceRequest.workOrderId = request.workOrderId;
        serviceRequest.operation = request.operation;
        serviceRequest.toAddress = request.toAddress;
        serviceRequest.subject = request.subject;
        serviceRequest.htmlBody = request.htmlBody;
        return serviceRequest;
    }

    private static Response toFlowResponse(
        WorkOrdersService.ModRequestFormEmailResponse serviceResponse
    ) {
        Response response = new Response();
        if (serviceResponse == null) {
            response.eligible = false;
            response.success = false;
            response.errorMessage = 'Unable to process Mod Request Form email.';
            return response;
        }

        response.eligible = serviceResponse.eligible;
        response.toAddress = serviceResponse.toAddress;
        response.subject = serviceResponse.subject;
        response.htmlBody = serviceResponse.htmlBody;
        response.templateName = serviceResponse.templateName;
        response.success = serviceResponse.success;
        response.errorMessage = serviceResponse.errorMessage;
        return response;
    }
}