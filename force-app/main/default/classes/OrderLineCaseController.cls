public class OrderLineCaseController {
    public OrderItem orderLine { get; set; }
    public Case relatedCase { get; set; }

    public OrderLineCaseController(ApexPages.StandardController controller) {
        // Get the current Task record ID
        Id orderLineId = controller.getId();
        
        // Query the Task including the WhatId
        orderLine = [SELECT Id, Order.ParentCase__r.Id FROM OrderItem WHERE Id = :orderLineId LIMIT 1];
        
        // Check if WhatId points to a Case (prefix '500')
        if (orderLine.Order.ParentCase__r.Id != null && String.valueOf(orderLine.Order.ParentCase__r.Id).startsWith('500')) {
            relatedCase = [SELECT Id, CaseNumber, Subject, Status FROM Case WHERE Id = :orderLine.Order.ParentCase__r.Id LIMIT 1];
        }
    }
}