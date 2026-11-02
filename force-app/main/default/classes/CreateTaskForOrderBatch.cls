/**
 * @author PSL
 * @date 12-19-2025
 * @description Batch class to create tasks for orders
 * * 3rd June 2026 SII-5 Exclude task creation for Lifescience order
 */
public class CreateTaskForOrderBatch implements Database.Batchable<SObject> {

    // Test-only hooks & counters
    @TestVisible private static Boolean throwInStart   = false;
    @TestVisible private static Boolean throwInExecute = false;
    @TestVisible private static Boolean throwInFinish  = false;

    @TestVisible private static Integer startCatchCount   = 0;
    @TestVisible private static Integer executeCatchCount = 0;
    @TestVisible private static Integer finishCatchCount  = 0;

    /**
     * @description Starts the batch process by querying orders that need tasks
     * @param bc Batchable context
     * @return Query locator for orders
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        try {
            if (Test.isRunningTest() && throwInStart) {
                throw new QueryException();
            }
            return Database.getQueryLocator([
                SELECT Id, OrderNumber__c, parentCase__c
                FROM Order
                WHERE parentCase__c != null
                  AND parentCase__r.Status NOT IN ('Closed','Cancelled')
                 AND parentCase__r.isCapitalSubCaseDeleted__c = false AND (Account.CustomerClassCode__c!='SC' OR NoOfCapitalLines__c > 0) // CBM-609
            ]);
        } catch (Exception e) {
            startCatchCount++;
            ErrorLogger.logException(e, 'CreateTaskForOrderBatch', 'start', ErrorLogger.Level.ERROR, null, null);
            throw e; // keep original behavior
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            if (Test.isRunningTest() && throwInExecute) {
               throw new NullPointerException();
            }

            List<Order> orders = (List<Order>) scope;
            List<String> orderNumbers = new List<String>();
            for (Order o : orders) {
                if (String.isNotBlank(o.OrderNumber__c)) {
                    orderNumbers.add(o.OrderNumber__c.trim());
                }
            }
            if (!orderNumbers.isEmpty()) {
                CreateTaskHandler.createTasksForOrder(orderNumbers);
            }
        } catch (Exception e) {
            executeCatchCount++;
            ErrorLogger.logException(e, 'CreateTaskForOrderBatch', 'execute', ErrorLogger.Level.ERROR, null, null);
            // execute does not rethrow
        }
    }

    public void finish(Database.BatchableContext bc) {
        try {
            if (Test.isRunningTest() && throwInFinish) {
                throw new DmlException();
            }
                if (!Test.isRunningTest()){
                    CreateTasksForOrderLinesBatch orderLineTaskBatch = new CreateTasksForOrderLinesBatch();
                    Database.executeBatch(orderLineTaskBatch, 2);
                    System.debug('CreateTaskForOrderBatch completed.');
                }
            
        } catch (Exception e) {
            finishCatchCount++;
            ErrorLogger.logException(e, 'CreateTaskForOrderBatch', 'finish', ErrorLogger.Level.ERROR, null, null);
            // finish does not rethrow
        }
    }
}