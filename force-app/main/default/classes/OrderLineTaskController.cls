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
        Task t = [
            SELECT Id, Order__c, Phase__c, Subject
            FROM Task
            WHERE Id = :taskId
            LIMIT 1
        ];

        if (t.Order__c == null) {
            return new List<OrderItem>();
        }

        // TRADE-IN TASK: Fetch Trade-In Order Lines directly
        if (t.Subject == 'Create Trade-In Contact') {

            List<OrderItem> tradeInLines = [
                SELECT Id,
                       OrderLineNumber__c,
                       OrderItemNumber,
                       LineNumber__c,
                       Product2.Name,
                       ScheduledDate__c,
                       ActualShipmentDate__c,
                       RequestDate__c,
                       Active__c,
                       OrderLineType__c
                FROM OrderItem
                WHERE OrderId = :t.Order__c
                AND OrderLineNumber__c != 0
                AND OrderLineType__c = 'Trade In Lines'
                ORDER BY OrderLineNumber__c ASC
            ];

            return tradeInLines;
        }

        
        List<Task> t2 = [
            SELECT Id, OrderLine__c, Phase__c, Subject
            FROM Task
            WHERE Order__c = :t.Order__c
            AND Phase__c = :t.Phase__c
            AND Subject = :t.Subject
        ];
		
		// set of OrderLine IDs from the tasks
        Set<Id> orderLineIds = new Set<Id>();

        for (Task taskRec : t2) {
            if (taskRec.OrderLine__c != null) {
                orderLineIds.add(taskRec.OrderLine__c);
            }
        }

        if (orderLineIds.isEmpty()) {
            return new List<OrderItem>();
        }

        List<OrderItem> lines = [
            SELECT Id,
                   OrderLineNumber__c,
                   OrderItemNumber,
                   LineNumber__c,
                   Product2.Name,
                   ScheduledDate__c,
                   ActualShipmentDate__c,
                   RequestDate__c,
                   Active__c
            FROM OrderItem
            WHERE Id IN :orderLineIds
            AND OrderLineNumber__c != 0
            ORDER BY OrderLineNumber__c ASC
        ];

        return lines;
    }
}