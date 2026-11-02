/**
 * @author PSL
 * @date 12-31-2025
 * @description Trigger for CreateCase__e platform event to handle case creation and task creation based on order numbers from the event.
 * @modified PSL
 * @modification Skip CreateTaskHandler methods for Orders where Account.CustomerClassCode__c = 'SC' and 0 Capital Lines.
 */
trigger CreateCaseEventTrigger on CreateCase__e (after insert) {
	
	List<String> orderNumbers = new List<String>();

    for (CreateCase__e event : Trigger.new) {
        if (String.isNotBlank(event.OrderNumber__c)) {
            orderNumbers.add(event.OrderNumber__c.trim());
        }
    }
		
    if (!orderNumbers.isEmpty()) {
        CreateCaseHandler.createCase(orderNumbers);
        CreateCaseHandler.createSubCase(orderNumbers);
        UpdateCaseHandler.evaluateAndUpdateCaseStatus(orderNumbers);

        // Filter out SC (Life Science) orders - CreateTaskHandler methods are skipped for SC accounts
        List<String> nonScOrderNumbers = new List<String>();
        for (Order ord : [
            SELECT OrderNumber__c, Account.CustomerClassCode__c, NoOfCapitalLines__c
            FROM Order
            WHERE OrderNumber__c IN :orderNumbers
        ]) {
            if (ord.Account.CustomerClassCode__c != 'SC' || ord.NoOfCapitalLines__c > 0) {
                nonScOrderNumbers.add(ord.OrderNumber__c);
            }
        }

        if (!nonScOrderNumbers.isEmpty()) {
            // Call CreateTaskHandler methods to create tasks for orders
            CreateTaskHandler.createTasksForOrder(nonScOrderNumbers);

            // Call CreateTaskHandler methods to create tasks for order lines and order and order line hold
            // Only one Order record is passed from the Batch process.
            //// Although SOQLs and DMLs inside a loop is generally discouraged, this is a special case where single Order record will be passed.
            for (String ord : nonScOrderNumbers) {
                CreateTaskHandler.createTasksForOrderLine(ord);

                CreateTaskHandler.createTasksForHolds(ord);
            }

            CreateTaskHandler.calculateTaskSLA(nonScOrderNumbers);
        }
    }

}