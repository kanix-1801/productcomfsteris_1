/**
 * @description Flow Apex Action: apply Overhaul Service Code for a Repair Center Quote (GW-157 / GW-3377).
 * @group Flow Actions
 */
public with sharing class OverhaulCodeInvocable {
    /**
     * @description Flow request with the triggering Quote Id.
     */
    public class Request {
        /** @description Quote record Id from the after-save flow. */
        @InvocableVariable(required=true label='Record ID')
        public Id recordId;
    }

    /**
     * @description Flow response with the resolved Overhaul ProductCode.
     */
    public class Response {
        /** @description Overhaul ProductCode inserted or already present; blank when no match. */
        @InvocableVariable(label='Overhaul Product Code')
        public String overhaulProductCode;
    }

    /**
     * @description Resolves and inserts the Overhaul Service Code WOLI for each Quote.
     * @param requests Flow requests
     * @return One response per request
     */
    @InvocableMethod(
        label='Apply Overhaul Code'
        description='Adds the mapped Overhaul Service Code WOLI for a Repair Center Quote when trigger codes and Model match.'
    )
    public static List<Response> applyOverhaulCodes(List<Request> requests) {
        List<Response> responses = new List<Response>();
        try {
            if (requests == null || requests.isEmpty()) {
                return responses;
            }

            List<Id> quoteIds = new List<Id>();
            for (Request request : requests) {
                quoteIds.add(request == null ? null : request.recordId);
            }

            List<String> overhaulProductCodes = OverhaulCodeService.applyOverhaulCodes(quoteIds);
            for (String overhaulProductCode : overhaulProductCodes) {
                Response response = new Response();
                response.overhaulProductCode = overhaulProductCode;
                responses.add(response);
            }
            return responses;
        } catch (Exception e) {
            Logger.error('OverhaulCodeInvocable.applyOverhaulCodes failed', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }
}