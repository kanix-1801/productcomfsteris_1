public class OrderCaseController {
    public Order order { get; set; }
    public Case relatedCase { get; set; }

    public OrderCaseController(ApexPages.StandardController controller) {
        // Get the current Task record ID
        Id orderId = controller.getId();
        
        // Query the Task including the WhatId
        order = [SELECT Id, ParentCase__r.Id FROM Order WHERE Id = :orderId LIMIT 1];
        
        // Check if WhatId points to a Case (prefix '500')
        if (order.ParentCase__r.Id != null && String.valueOf(order.ParentCase__r.Id).startsWith('500')) {
            relatedCase = [SELECT Id, CaseNumber, Subject, Status FROM Case WHERE Id = :order.ParentCase__r.Id LIMIT 1];
        }
    }
}