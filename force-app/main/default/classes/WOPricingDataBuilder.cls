public class WOPricingDataBuilder {

    public class Request {
        @InvocableVariable(label='Work Order Id' required=true)
        public String workOrderId;
    }

    public class Response {
        @InvocableVariable(label='Pricing Data JSON')
        public String pricingDataJson;

        @InvocableVariable(label='Item Count')
        public Integer itemCount;

        @InvocableVariable(label='Line Item IDs')
        public List<String> lineItemIds;
    }

    @InvocableMethod(
        label='Build WO Pricing Data JSON'
        description='Assembles the pricingData payload for aslmHeadlessPricing targeting WorkOrderPricingMapping in SalesTransactionContext_VS'
    )
    public static List<Response> buildPricingData(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            List<WorkOrderLineItem> wolis = [
                SELECT Id, Quantity
                FROM WorkOrderLineItem
                WHERE WorkOrderId = :req.workOrderId
                  AND PricebookEntryId != null
            ];

            // Default Quantity to 1 so pricing formulas always have a value to work with
            List<WorkOrderLineItem> needsQty = new List<WorkOrderLineItem>();
            for (WorkOrderLineItem woli : wolis) {
                if (woli.Quantity == null) {
                    woli.Quantity = 1;
                    needsQty.add(woli);
                }
            }
            if (!needsQty.isEmpty()) update needsQty;

            List<Map<String, Object>> items = new List<Map<String, Object>>();
            List<String> ids = new List<String>();
            for (WorkOrderLineItem woli : wolis) {
                items.add(new Map<String, Object>{
                    'id' => woli.Id,
                    'businessObjectType' => 'WorkOrderLineItem'
                });
                ids.add(woli.Id);
            }

            Map<String, Object> payload = new Map<String, Object>{
                'WorkOrder' => new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'id' => req.workOrderId,
                        'businessObjectType' => 'WorkOrder',
                        'WorkOrderLineItem' => items
                    }
                }
            };

            Response res = new Response();
            res.pricingDataJson = JSON.serialize(payload);
            res.itemCount       = wolis.size();
            res.lineItemIds     = ids;
            responses.add(res);
        }

        return responses;
    }
}