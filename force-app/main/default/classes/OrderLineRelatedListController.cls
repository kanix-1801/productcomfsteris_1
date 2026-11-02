/**
* @author PSL
* @date 02-04-2026
* @description controller class for showing Order products on Order screen and Parent Case screen 
*/


public without sharing class OrderLineRelatedListController {

    /* =========================
     * DTO FOR LWC
     * ========================= */
    public class OrderLineDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Decimal orderLineNumber;

        // Order Page
        @AuraEnabled public String productName;
        @AuraEnabled public String productUrl;

        // Case Page
        @AuraEnabled public String itemNumber;
        @AuraEnabled public String productDescription;
        @AuraEnabled public Date ActualShipmentDate;
        @AuraEnabled public String Warehouse;
        @AuraEnabled public String SalesRep;

        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal extendedPrice;

        @AuraEnabled public String orderLineType;
        @AuraEnabled public String orderLineStatus;

        @AuraEnabled public String subcaseNumber;
        @AuraEnabled public String subcaseUrl;

        @AuraEnabled public Date requestDate;
        @AuraEnabled public Date scheduledDate;
    }

   
   
   /**
    * @description to get all order lines as per the parent object.
    * @param parentRecordId,parentObject,limitSize 
    * @return List
    */
   // GET ORDER LINES
    @AuraEnabled(cacheable=true)
    public static List<OrderLineDTO> getOrderLines(
        Id parentRecordId,
        String parentObject,
        Integer limitSize
    ) {
        Id orderId;

        if (parentObject == 'Order') {
            orderId = parentRecordId;
        } else {
            orderId = [
                SELECT Order__c
                FROM Case
                WHERE Id = :parentRecordId
                LIMIT 1
            ].Order__c;
        }

        if (orderId == null) {
            return new List<OrderLineDTO>();
        }

        List<OrderItem> orderItems;

        /* ORDER PAGE → ALL ORDER LINES */
        if (parentObject == 'Order') {

            orderItems = [
                SELECT
                    Id,
                    orderLineNumber__c,
                    Product2.Id,
                    Product2.Name,
                    Description,
                    Quantity,
                    UnitPrice,
                    ExtendedPrice__c,
                    Subcase__c,
                    Subcase__r.CaseNumber,
                    OrderLineType__c,
                    toLabel(OrderLineStatus__c),
                    RequestDate__c,
                    ScheduledDate__c
                FROM OrderItem
                WHERE OrderId = :orderId
                  AND orderLineNumber__c != 0
                ORDER BY orderLineNumber__c
                LIMIT :limitSize
            ];
        }
        // CASE PAGE
        else {

            orderItems = [
                SELECT
                    Id,
                    orderLineNumber__c,
                    ItemNumber__c,
                    ProductDescription__c,
                    Quantity,
                    UnitPrice,
                    ExtendedPrice__c,
                	Case__c,  
                    Warehouse__c,
                	Sales_Rep__c,
                    ActualShipmentDate__c,
                    Subcase__r.CaseNumber,
                    OrderLineType__c,
                    toLabel(OrderLineStatus__c),
                    RequestDate__c,
                    ScheduledDate__c
                FROM OrderItem
                WHERE OrderId = :orderId
                  AND Case__c   = :parentRecordId
                  AND orderLineNumber__c != 0
                ORDER BY orderLineNumber__c
                LIMIT :limitSize
            ];
        }

        List<OrderLineDTO> result = new List<OrderLineDTO>();

        for (OrderItem oi : orderItems) {
            OrderLineDTO dto = new OrderLineDTO();

            dto.id = oi.Id;
            dto.orderLineNumber = oi.orderLineNumber__c;

            /* ORDER PAGE VIEW */
            if (parentObject == 'Order') {
                if (String.isNotBlank(oi.Description)) {
                    dto.productName = oi.Description;
                } else if (oi.Product2 != null) {
                    dto.productName = oi.Product2.Name;
                    dto.productUrl = '/' + oi.Id;
                }
            }

            /* CASE PAGE VIEW */
            if (parentObject == 'Case') {
                dto.itemNumber = oi.ItemNumber__c;
                dto.productDescription = oi.ProductDescription__c;
                dto.ActualShipmentDate = oi.ActualShipmentDate__c;
                dto.Warehouse = oi.Warehouse__c;
                dto.SalesRep = oi.Sales_Rep__c;
            }

            dto.quantity = oi.Quantity;
            dto.unitPrice = oi.UnitPrice;
            dto.extendedPrice = oi.ExtendedPrice__c;

            dto.subcaseNumber = oi.Subcase__r != null ? oi.Subcase__r.CaseNumber : null;
            dto.subcaseUrl = oi.Subcase__c != null ? '/' + oi.Subcase__c : null;

            dto.orderLineType = oi.OrderLineType__c;
            dto.orderLineStatus = String.valueOf(oi.get('OrderLineStatus__c'));

            dto.requestDate = oi.RequestDate__c;
            dto.scheduledDate = oi.ScheduledDate__c;

            result.add(dto);
        }

        return result;
    }

    /* =========================
     * COUNT METHOD
     * ========================= */
    /**
    * @description to show the count of order lines in datatable
    * @param parentRecordId,parentObject
    * @return List
    */
    @AuraEnabled(cacheable=true)
    public static Integer getOrderLineCount(
        Id parentRecordId,
        String parentObject
    ) {
        Id orderId;

        if (parentObject == 'Order') {
            orderId = parentRecordId;
        } else {
            orderId = [
                SELECT Order__c
                FROM Case
                WHERE Id = :parentRecordId
                LIMIT 1
            ].Order__c;
        }

        if (orderId == null) return 0;

        if (parentObject == 'Order') {
            return [
                SELECT COUNT()
                FROM OrderItem
                WHERE OrderId = :orderId
                  AND orderLineNumber__c != 0
            ];
        } else {
            return [
                SELECT COUNT()
                FROM OrderItem
                WHERE OrderId = :orderId
                  AND Case__c = :parentRecordId
                  AND orderLineNumber__c != 0
            ];
        }
    }
}