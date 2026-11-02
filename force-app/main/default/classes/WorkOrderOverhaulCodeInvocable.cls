/**
 * @description GW-3398: Determines the Repair Center overhaul service-code product from the asset model
 *              product code and the service codes already on the Work Order Line Items.
 *              Rules are the FLEX LARGE matrix in overhaul_codes_for_salesforce_31_JUL_26.
 * @group Repair Center
 */
public with sharing class WorkOrderOverhaulCodeInvocable {
    /**
     * @description Flow request. Record Id is the Work Order being saved.
     */
    public class Request {
        @InvocableVariable(label='Record Id' description='Work Order Id' required=true)
        public Id recordId;
    }

    /**
     * @description Flow result. Blank when no overhaul code applies.
     */
    public class Result {
        @InvocableVariable(label='Overhaul Product Code' description='Product code to select, for example SC.FER902')
        public String overhaulProductCode;
    }

    /**
     * @description Returns one overhaul product code for each Work Order Id.
     * @param requests Flow requests
     * @return Overhaul product code for each request, in the same order
     */
    @InvocableMethod(
        label='Determine Overhaul Product Code'
        description='Returns the Repair Center overhaul service-code product code for a Work Order.'
    )
    public static List<Result> determineOverhaulProductCode(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        List<Id> workOrderIds = new List<Id>();
        for (Request request : requests) {
            workOrderIds.add(request == null ? null : request.recordId);
        }

        for (String overhaulProductCode : WorkOrderOverhaulCodeService.determineOverhaulProductCodes(workOrderIds)) {
            Result result = new Result();
            result.overhaulProductCode = overhaulProductCode;
            results.add(result);
        }
        return results;
    }
}