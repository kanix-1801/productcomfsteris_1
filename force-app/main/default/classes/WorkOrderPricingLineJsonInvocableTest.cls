/**
 * @description GW-5477: Tests for WorkOrderPricingLineJsonInvocable.
 */
@IsTest
private class WorkOrderPricingLineJsonInvocableTest {
    /**
     * @description Builds pricing line JSON for every Work Order Line Item on the Work Order.
     */
    @IsTest
    static void build_includesAllWorkOrderLineItems() {
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder();
        workOrderBuilder.persist();

        WorkOrderLineItem firstLineItem = new WorkOrderLineItem(
            WorkOrderId = workOrderBuilder.id,
            Status = 'New'
        );
        WorkOrderLineItem secondLineItem = new WorkOrderLineItem(
            WorkOrderId = workOrderBuilder.id,
            Status = 'New'
        );
        insert new List<WorkOrderLineItem>{ firstLineItem, secondLineItem };

        WorkOrderPricingLineJsonInvocable.Request request = new WorkOrderPricingLineJsonInvocable.Request();
        request.workOrderId = workOrderBuilder.id;

        Test.startTest();
        List<WorkOrderPricingLineJsonInvocable.Result> results = WorkOrderPricingLineJsonInvocable.build(
            new List<WorkOrderPricingLineJsonInvocable.Request>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One Work Order request should return one JSON result');
        System.assert(
            results[0].pricingLineJson.contains(firstLineItem.Id),
            'Pricing line JSON should include the first Work Order Line Item Id'
        );
        System.assert(
            results[0].pricingLineJson.contains(secondLineItem.Id),
            'Pricing line JSON should include the second Work Order Line Item Id'
        );
    }

    /**
     * @description Returns an empty JSON array when the Work Order has no line items.
     */
    @IsTest
    static void build_returnsEmptyArrayWhenNoLineItems() {
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder();
        workOrderBuilder.persist();

        WorkOrderPricingLineJsonInvocable.Request request = new WorkOrderPricingLineJsonInvocable.Request();
        request.workOrderId = workOrderBuilder.id;

        Test.startTest();
        List<WorkOrderPricingLineJsonInvocable.Result> results = WorkOrderPricingLineJsonInvocable.build(
            new List<WorkOrderPricingLineJsonInvocable.Request>{ request }
        );
        Test.stopTest();

        System.assertEquals('[]', results[0].pricingLineJson, 'Work Orders with no line items should return []');
    }
}