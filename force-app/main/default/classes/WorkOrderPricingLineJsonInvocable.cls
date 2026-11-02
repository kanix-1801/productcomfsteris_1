/**
 * @description GW-5477 - Builds Oracle pricing line JSON from all Work Order Line Items on a Work Order.
 * @group Pricing Framework
 */
public with sharing class WorkOrderPricingLineJsonInvocable {
    /**
     * @description Invocable request with the Work Order that launched Execute Pricing.
     */
    public class Request {
        @InvocableVariable(label='Work Order Id' required=true)
        public Id workOrderId;
    }

    /**
     * @description Invocable result with Oracle pricing line JSON.
     */
    public class Result {
        @InvocableVariable(label='Pricing Line JSON')
        public String pricingLineJson;
    }

    /**
     * @description Builds [{"lineId","productCode","quantity"}] for every WOLI under each Work Order Id.
     * @param requests Flow requests
     * @return Pricing line JSON for each request
     */
    @InvocableMethod(
        label='Build Work Order Pricing Line JSON'
        description='Builds Oracle pricing line JSON from all Work Order Line Items on a Work Order.'
    )
    public static List<Result> build(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<Id> workOrderIds = new Set<Id>();
        for (Request request : requests) {
            if (request != null && request.workOrderId != null) {
                workOrderIds.add(request.workOrderId);
            }
        }

        Map<Id, List<WorkOrderLineItem>> lineItemsByWorkOrderId = new Map<Id, List<WorkOrderLineItem>>();
        if (!workOrderIds.isEmpty()) {
            for (WorkOrderLineItem lineItem : [
                SELECT Id, WorkOrderId, Quantity, Product2.ProductCode
                FROM WorkOrderLineItem
                WHERE WorkOrderId IN :workOrderIds
                ORDER BY LineItemNumber, CreatedDate, Id
            ]) {
                if (!lineItemsByWorkOrderId.containsKey(lineItem.WorkOrderId)) {
                    lineItemsByWorkOrderId.put(lineItem.WorkOrderId, new List<WorkOrderLineItem>());
                }
                lineItemsByWorkOrderId.get(lineItem.WorkOrderId).add(lineItem);
            }
        }

        for (Request request : requests) {
            Result result = new Result();
            Id workOrderId = request == null ? null : request.workOrderId;
            result.pricingLineJson = toPricingLineJson(lineItemsByWorkOrderId.get(workOrderId));
            results.add(result);
        }
        return results;
    }

    private static String toPricingLineJson(List<WorkOrderLineItem> lineItems) {
        List<Map<String, Object>> lines = new List<Map<String, Object>>();
        if (lineItems == null) {
            return JSON.serialize(lines);
        }

        for (WorkOrderLineItem lineItem : lineItems) {
            lines.add(
                new Map<String, Object>{
                    'lineId' => lineItem.Id,
                    'productCode' => lineItem.Product2 == null ? null : lineItem.Product2.ProductCode,
                    'quantity' => lineItem.Quantity == null ? 1 : lineItem.Quantity
                }
            );
        }
        return JSON.serialize(lines);
    }
}