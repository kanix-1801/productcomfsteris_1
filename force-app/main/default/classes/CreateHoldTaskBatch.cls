/**
 * @author PSL
 * @date 12-26-2025
 * @description Batch class to create hold tasks for orders
 * 3rd June 2026 SII-5 Exclude task creation for Lifescience order
 */
public class CreateHoldTaskBatch implements Database.Batchable<SObject> {

    @TestVisible private static Boolean throwInStart   = false;
    @TestVisible private static Boolean throwInExecute = false;
    @TestVisible private static Boolean throwInFinish  = false;

    @TestVisible private static Integer startCatchCount   = 0;
    @TestVisible private static Integer executeCatchCount = 0;
    @TestVisible private static Integer finishCatchCount  = 0;

    /**
     * @description Starts the batch process by querying orders that need hold tasks
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
                   AND parentCase__r.isCapitalSubCaseDeleted__c = false  AND (Account.CustomerClassCode__c!='SC' OR NoOfCapitalLines__c > 0) // CBM-609
            ]);
        } catch (Exception e) {
            startCatchCount++;
            ErrorLogger.logException(e, 'createHoldTaskBatch', 'start', ErrorLogger.Level.ERROR, null, null);
            throw e;
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            if (Test.isRunningTest() && throwInExecute) {
               throw new NullPointerException();
            }
            List<Order> orders = (List<Order>) scope;
            for (Order o : orders) {               
                    CreateTaskHandler.createTasksForHolds(o.OrderNumber__c);
                
            }
        } catch (Exception e) {
            executeCatchCount++;
            ErrorLogger.logException(e, 'createHoldTaskBatch', 'execute', ErrorLogger.Level.ERROR, null, null);
        }
    }

    public void finish(Database.BatchableContext bc) {
        try {
            if (Test.isRunningTest() && throwInFinish) {
                throw new DmlException();
            }
             System.debug('createHoldTaskBatch completed.');
            if (!Test.isRunningTest()){
                PopulateSLAForTasksBatch calculateTaskSLABatch = new PopulateSLAForTasksBatch();
                Database.executeBatch(calculateTaskSLABatch, 2);
            }
            
           
        } catch (Exception e) {
            finishCatchCount++;
            ErrorLogger.logException(e, 'createHoldTaskBatch', 'finish', ErrorLogger.Level.ERROR, null, null);
        }
    }
}