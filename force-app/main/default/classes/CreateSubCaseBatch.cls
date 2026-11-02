/**
 * @author PSL
 * @date 11-12-2025
 * @description Batch class to create sub cases for order lines
 */
global class CreateSubCaseBatch implements Database.Batchable<SObject>, Database.Stateful {
    
    /**
     * @description  It will create subcases for orderLines whoes case__c and SubCase__C lookup is blank
     * @param        orderNumbers - List of OrderNumber__c values (Text) for which cases and subcase need to be created.
     * @return       void     
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
       
        return Database.getQueryLocator([
            SELECT Id, OrderNumber__c,parentCase__c
            FROM Order
            WHERE parentCase__c!=null AND parentCase__r.status NOT IN('Closed','Cancelled')
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Order> scope) {
        List<String> orderNumbers = new List<String>();
        for (Order ord : scope) {
            if (ord.OrderNumber__c != null) {
                orderNumbers.add(ord.OrderNumber__c);
            }
        }

        if (!orderNumbers.isEmpty()) {
            
            CreateCaseHandler.createSubCase(orderNumbers);
        }
    }

    global void finish(Database.BatchableContext bc) {
       
        System.debug('CreateSubCaseBatch completed.');

        UpdateSubCaseBatch subCaseBatch = new UpdateSubCaseBatch();

        Database.executeBatch(subCaseBatch, 2);
    }
}