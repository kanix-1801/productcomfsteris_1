/**
 * @description GW-134 / GW-6703 - Appends an asset product type to the CRSS work order
 *              Device Inspection Summary when a Product Serviced line gains an Asset.
 *              One call handles every line in the save, so several assets added together
 *              all land on the work order and an existing value is not repeated.
 */
public without sharing class DeviceInspectionSummaryService {
    /** @description CRSS work order record type. */
    public static final String CRSS_RECORD_TYPE = 'CRSSFieldRepair';
    /** @description Product Serviced work order line record type. */
    public static final String PRODUCT_SERVICED_RECORD_TYPE = 'ProductServiced';
    /** @description Separator between product type values on the work order. */
    public static final String LIST_SEPARATOR = '; ';
    private static final String PART_SEPARATOR = ' - ';

    /**
     * @description Flow input. The line Id is enough; the service reads the asset and the parent work order.
     */
    public class Request {
        /** @description Work Order Line Item that was saved with an Asset. */
        @InvocableVariable(label='Work Order Line Item Id' required=true)
        public Id workOrderLineItemId;
    }

    /**
     * @description Appends each qualifying product type to its work order.
     * @param requests Line items from the after-save flow
     */
    @InvocableMethod(
        label='Append Device Inspection Summary'
        description='Appends the asset product type to the CRSS work order Device Inspection Summary when that exact value is not already there.'
        category='Work Order'
    )
    public static void append(List<Request> requests) {
        Set<Id> lineIds = new Set<Id>();
        if (requests != null) {
            for (Request request : requests) {
                if (request != null && request.workOrderLineItemId != null) {
                    lineIds.add(request.workOrderLineItemId);
                }
            }
        }
        if (lineIds.isEmpty()) {
            return;
        }

        Map<Id, WorkOrderLineItem> linesById = new Map<Id, WorkOrderLineItem>([
            SELECT
                Id,
                RecordType.DeveloperName,
                Asset.ProductLineCalculated__c,
                Asset.SubProductLineCalculated__c,
                WorkOrderId,
                WorkOrder.RecordType.DeveloperName,
                WorkOrder.DeviceInspectionSummary__c
            FROM WorkOrderLineItem
            WHERE Id IN :lineIds
        ]);

        Map<Id, String> originalByWorkOrderId = new Map<Id, String>();
        Map<Id, String> summaryByWorkOrderId = new Map<Id, String>();
        for (Request request : requests) {
            if (request == null || request.workOrderLineItemId == null) {
                continue;
            }
            WorkOrderLineItem line = linesById.get(request.workOrderLineItemId);
            if (!qualifies(line)) {
                continue;
            }
            String token = buildToken(
                line.Asset.ProductLineCalculated__c,
                line.Asset.SubProductLineCalculated__c
            );
            if (token == null) {
                continue;
            }
            if (!summaryByWorkOrderId.containsKey(line.WorkOrderId)) {
                String original = line.WorkOrder.DeviceInspectionSummary__c;
                originalByWorkOrderId.put(line.WorkOrderId, original);
                summaryByWorkOrderId.put(line.WorkOrderId, original);
            }
            String current = summaryByWorkOrderId.get(line.WorkOrderId);
            if (containsToken(current, token)) {
                continue;
            }
            summaryByWorkOrderId.put(
                line.WorkOrderId,
                String.isBlank(current) ? token : current + LIST_SEPARATOR + token
            );
        }

        List<WorkOrder> workOrders = new List<WorkOrder>();
        for (Id workOrderId : summaryByWorkOrderId.keySet()) {
            String updated = summaryByWorkOrderId.get(workOrderId);
            if (updated == originalByWorkOrderId.get(workOrderId)) {
                continue;
            }
            workOrders.add(new WorkOrder(
                Id = workOrderId,
                DeviceInspectionSummary__c = updated
            ));
        }
        if (!workOrders.isEmpty()) {
            update workOrders;
        }
    }

    /**
     * @description CRSS Product Serviced line with an Asset.
     * @param line Line item from the query
     * @return true when the line can contribute a product type
     */
    private static Boolean qualifies(WorkOrderLineItem line) {
        return line != null
            && line.WorkOrderId != null
            && line.Asset != null
            && line.RecordType != null
            && line.RecordType.DeveloperName == PRODUCT_SERVICED_RECORD_TYPE
            && line.WorkOrder != null
            && line.WorkOrder.RecordType != null
            && line.WorkOrder.RecordType.DeveloperName == CRSS_RECORD_TYPE;
    }

    /**
     * @description Product Line, or Product Line - Sub Product Line. Blank product line is skipped.
     * @param productLine Asset product line
     * @param subProductLine Asset sub product line
     * @return Token, or null when the product line is blank
     */
    private static String buildToken(String productLine, String subProductLine) {
        if (String.isBlank(productLine)) {
            return null;
        }
        String line = productLine.trim();
        if (String.isBlank(subProductLine)) {
            return line;
        }
        return line + PART_SEPARATOR + subProductLine.trim();
    }

    /**
     * @description True when the token is already a whole value in the semicolon-separated field.
     * @param summary Current Device Inspection Summary
     * @param token Product type to look for
     * @return true when that exact value is already present
     */
    private static Boolean containsToken(String summary, String token) {
        if (String.isBlank(summary)) {
            return false;
        }
        for (String existing : summary.split(';')) {
            if (existing.trim() == token) {
                return true;
            }
        }
        return false;
    }
}