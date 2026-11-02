/**
 * @author PSL
 * @date 11-12-2025
 * @description Batch class to create parent Cases for Orders that do not yet have a Parent Case, then schedules subcase creation
 */
global class CreateCasesBatch implements Database.Batchable<SObject> {
    
    /**
     * @description Queries Orders with no Parent Case assigned for batch processing, preparing for case creation.
     * @param bc Batchable context for execution
     * @return QueryLocator for Order records requiring case creation
     */

    /**
     * @description Start method for batch execution to retrieve Order records without Parent Case for case creation only (no subcase yet).
     * @param bc Batchable context for execution
     * @return QueryLocator for Order records requiring case creation
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        
        return Database.getQueryLocator([
            SELECT Id, OrderNumber__c
            FROM Order
            WHERE ParentCase__c = NULL
        ]);
    }

    /**
     * @description Executes batch logic to create Cases for qualifying Orders, then schedules subcase batch execution.
     * @param bc Batchable context for execution
     * @param scope List of Order records to process in this batch
     * @return void
     */
    global void execute(Database.BatchableContext bc, List<Order> scope) {
       
        Set<Id> orderIds = new Set<Id>();
        List<String> orderNumbersForParentCase = new List<String>();
        for (Order ord : scope) {
            if (ord.OrderNumber__c != null) {
                orderNumbersForParentCase.add(ord.OrderNumber__c);
                orderIds.add(ord.Id);
            }
        }

       
        Map<Id, Integer> orderItemCountMap = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT OrderId, COUNT(Id) cnt
            FROM OrderItem
            WHERE OrderId IN :orderIds
            GROUP BY OrderId
        ]) {
            orderItemCountMap.put((Id)ar.get('OrderId'), (Integer)ar.get('cnt'));
        }

       
        List<String> orderNumbersForSubCase = new List<String>();
        for (Order ord : scope) {
            if (orderItemCountMap.containsKey(ord.Id) && orderItemCountMap.get(ord.Id) > 0) {
                orderNumbersForSubCase.add(ord.OrderNumber__c);
            }
        }

       
        if (!orderNumbersForParentCase.isEmpty()) {
            CreateCaseHandler.createCase(orderNumbersForParentCase);
        }
     /*   if (!orderNumbersForSubCase.isEmpty()) {
            CreateCaseHandler.createSubCase(orderNumbersForSubCase);
        }*/
    }

    /**
     * @description Final method called after all batches complete, schedules execution of CreateSubCaseBatch for subcase creation.
     * @param bc Batchable context for execution
     * @return void
     */
    global void finish(Database.BatchableContext bc) {
        
        CreateSubCaseBatch subcaseBatch = new CreateSubCaseBatch();
		Database.executeBatch(subcaseBatch, 2);
        System.debug('CreateCases batch completed successfully.');
    }
}