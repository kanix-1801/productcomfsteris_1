/**
 * @description GW-4329: Runs SubFlow_GenerateRepairCenterWOQuote in a separate transaction
 *              so Device Evaluation / heavy WO saves are not sharing SOQL limits with Quote
 *              create, Overhaul, and DocGen. Invocable entry enqueues this same class (no
 *              separate helper) for RepairCenterWorkOrder_Updated_AfterSave.
 */
public with sharing class GenerateRepairCenterWOQuoteQueueable implements Queueable {
    @TestVisible
    private static final String FLOW_API_NAME = 'SubFlow_GenerateRepairCenterWOQuote';

    @TestVisible
    private static Boolean bypassSubFlow = false;

    @TestVisible
    private static Integer subFlowStartCount = 0;

    private final Set<Id> workOrderIds;

    /**
     * @description Stores Work Order Ids that should drive quote generation.
     * @param workOrderIds Triggering Work Order Ids (typically child WOs with a parent)
     */
    public GenerateRepairCenterWOQuoteQueueable(Set<Id> workOrderIds) {
        this.workOrderIds = workOrderIds == null ? new Set<Id>() : new Set<Id>(workOrderIds);
    }

    /**
     * @description Flow request wrapper for a single Work Order Id.
     */
    public class Request {
        @InvocableVariable(required=true label='Work Order Id')
        public Id workOrderId;
    }

    /**
     * @description Enqueues quote generation for the given Work Order Ids.
     * @param requests Flow requests containing Work Order Ids
     */
    @InvocableMethod(
        label='Enqueue Generate Repair Center WO Quote'
        description='Queues SubFlow_GenerateRepairCenterWOQuote in a new transaction.'
        category='Repair Center'
    )
    public static void enqueue(List<Request> requests) {
        Set<Id> ids = new Set<Id>();
        if (requests != null) {
            for (Request request : requests) {
                if (request != null && request.workOrderId != null) {
                    ids.add(request.workOrderId);
                }
            }
        }
        if (ids.isEmpty()) {
            return;
        }
        System.enqueueJob(new GenerateRepairCenterWOQuoteQueueable(ids));
    }

    /**
     * @description Reloads each Work Order and starts the quote SubFlow.
     * @param context Queueable context
     */
    public void execute(QueueableContext context) {
        if (workOrderIds.isEmpty()) {
            return;
        }

        // Fields must cover every IN_OBJWO.* reference in SubFlow_GenerateRepairCenterWOQuote
        // (Flow.Interview only sees queried fields, unlike $Record from a record-triggered flow).
        List<WorkOrder> workOrders = WorkOrdersService.selectForRepairCenterQuoteSubFlow(
            workOrderIds
        );

        for (WorkOrder workOrder : workOrders) {
            startSubFlow(workOrder);
        }
    }

    /**
     * @description Starts SubFlow_GenerateRepairCenterWOQuote with IN_OBJWO.
     * @param workOrder Work Order passed into the SubFlow
     */
    @TestVisible
    static void startSubFlow(WorkOrder workOrder) {
        if (workOrder == null || workOrder.Id == null) {
            return;
        }
        if (bypassSubFlow == true) {
            return;
        }

        Map<String, Object> inputs = new Map<String, Object>{ 'IN_OBJWO' => workOrder };
        subFlowStartCount++;
        Flow.Interview interview = Flow.Interview.createInterview(FLOW_API_NAME, inputs);
        interview.start();
    }
}