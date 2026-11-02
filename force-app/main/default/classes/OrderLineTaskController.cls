/**
 * @author PSL
 * @date 31-12-2025
 * @description Helper class for creating Tasks related to Orders, Order Lines, and Holds based on TaskSLAConfig metadata.
 *              Provides methods for task creation, owner resolution, SLA calculation, and formula evaluation.
 */

public without sharing class OrderLineTaskController {
    /**
     * @description Creates tasks for Order Lines based on TaskSLAConfig records where Object__c = 'OrderItem'.
     * @param orderNumber The Order Number of the order received from Oracle to create tasks
     * @return void
     */
    @AuraEnabled(cacheable=true)
    public static List<OrderItem> getRelatedOrderLines(Id taskId) {
        // 1. Get the Task. 
        // IMPORTANT: Verify if 'Order__c' is the correct API Name in Object Manager
        Task t = [SELECT Id, Order__c, phase__c, Subject FROM Task WHERE Id = :taskId LIMIT 1];
        
        
        
        if (t.Order__c == null) {
            return new List<OrderItem>();
        }
        
        List<Task> t2 = [select Id,OrderLine__c,phase__c, Subject From Task where order__c = : t.order__c and phase__c = : t.phase__c and Subject = :t.Subject and Status != 'Completed'];
        
        
       // set of OrderLine IDs from the tasks
        Set<Id> orderLineIds = new Set<Id>();
        for (Task taskRec : t2) {
            if (taskRec.OrderLine__c != null) {
                orderLineIds.add(taskRec.OrderLine__c);
            }
        }
         
        
        List<OrderItem> lines = [SELECT Id,orderLineNumber__c,OrderItemNumber,LineNumber__c,Product2.Name,ScheduledDate__c,ActualShipmentDate__c,RequestDate__c,Active__c 
        FROM OrderItem 
                         WHERE Id IN :orderLineIds AND orderLineNumber__c != 0 
                         ORDER BY orderLineNumber__c ASC];
        return lines;
    }
}