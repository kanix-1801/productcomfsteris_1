public class CBMCaseAutoCloseBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Status, Order__c, ParentId
            FROM Case
            WHERE RecordType.Name = 'CBM Case'
              AND ParentId = NULL            // Only parent cases
              AND Order__c != NULL
              AND Status NOT IN ('Closed', 'Cancelled')
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Case> casesBatch) {
        new CBMCaseAutoCloserHandler().evaluateAndUpdateCases(casesBatch);
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('CBMCaseAutoCloseBatch completed.');
        
        CreateTaskForOrderBatch orderTaskBatch = new CreateTaskForOrderBatch();

        Database.executeBatch(orderTaskBatch, 2);
    }
    
    
}