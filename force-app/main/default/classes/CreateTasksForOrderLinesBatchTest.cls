/**
 * @author PSL
 * @date 12-26-2025
 * @description Test class for CreateTasksForOrderLinesBatch batch class
 */
@IsTest(SeeAllData=false)
private class CreateTasksForOrderLinesBatchTest {

    @TestSetup
    static void setupData() {
        List<Case> parentCases = new List<Case>{
            new Case(Subject = 'Parent A', Status = 'New'),
            new Case(Subject = 'Parent B', Status = 'Working'),
            new Case(Subject = 'Parent Closed', Status = 'Closed'),
            new Case(Subject = 'Parent Cancelled', Status = 'Cancelled')
        };
        insert parentCases;

        Id openCaseId1 = parentCases[0].Id;
        Id openCaseId2 = parentCases[1].Id;
        Id closedCaseId = parentCases[2].Id;
        Id cancelledCaseId = parentCases[3].Id;

        Account account = new Account(Name = 'Test Acc');
        insert account;

        Id standardPricebookId = Test.getStandardPricebookId();
        List<Order> orders = new List<Order>{
            new Order(AccountId = account.Id, Status = 'Draft', EffectiveDate = Date.today(),
                      Pricebook2Id = standardPricebookId, OrderNumber__c = 'ORD-ELIG-1', parentCase__c = openCaseId1),
            new Order(AccountId = account.Id, Status = 'Draft', EffectiveDate = Date.today(),
                      Pricebook2Id = standardPricebookId, OrderNumber__c = 'ORD-ELIG-2', parentCase__c = openCaseId2),
            new Order(AccountId = account.Id, Status = 'Draft', EffectiveDate = Date.today(),
                      Pricebook2Id = standardPricebookId, OrderNumber__c = 'ORD-CLOSED', parentCase__c = closedCaseId),
            new Order(AccountId = account.Id, Status = 'Draft', EffectiveDate = Date.today(),
                      Pricebook2Id = standardPricebookId, OrderNumber__c = 'ORD-CANCEL', parentCase__c = cancelledCaseId),
            new Order(AccountId = account.Id, Status = 'Draft', EffectiveDate = Date.today(),
                      Pricebook2Id = standardPricebookId, OrderNumber__c = 'ORD-NOELIG', parentCase__c = openCaseId1)
        };
        insert orders;
    }

    private static Integer getStartScopeCount() {
        return [SELECT COUNT() FROM Order
                WHERE parentCase__c != null
                  AND parentCase__r.Status NOT IN ('Closed','Cancelled')];
    }

    private static void resetBatchTestState() {
        CreateTasksForOrderLinesBatch.throwInStart   = false;
        CreateTasksForOrderLinesBatch.throwInExecute = false;
        CreateTasksForOrderLinesBatch.throwInFinish  = false;
        CreateTasksForOrderLinesBatch.startCatchCount   = 0;
        CreateTasksForOrderLinesBatch.executeCatchCount = 0;
        CreateTasksForOrderLinesBatch.finishCatchCount  = 0;
    }

    @IsTest
    static void testHappyPathSingleChunk() {
        resetBatchTestState();
        Integer startCount = getStartScopeCount();

        Test.startTest();
        Id jobId = Database.executeBatch(new CreateTasksForOrderLinesBatch(), startCount);
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assertEquals(0, CreateTasksForOrderLinesBatch.startCatchCount);
        System.assertEquals(0, CreateTasksForOrderLinesBatch.executeCatchCount);
        System.assertEquals(0, CreateTasksForOrderLinesBatch.finishCatchCount);
    }

    @IsTest
    static void testStartThrowsAndRethrows() {
        resetBatchTestState();
        CreateTasksForOrderLinesBatch.throwInStart = true;

        Test.startTest();
        Id jobId = Database.executeBatch(new CreateTasksForOrderLinesBatch(), 200);
        try {
            Test.stopTest();
            System.assert(false, 'Expected exception from start()');
        } catch (Exception e) {
            System.assertNotEquals(null, e);
        }

        System.assertNotEquals(null, jobId);
        System.assertEquals(1, CreateTasksForOrderLinesBatch.startCatchCount);
        System.assertEquals(0, CreateTasksForOrderLinesBatch.executeCatchCount);
        System.assertEquals(0, CreateTasksForOrderLinesBatch.finishCatchCount);
    }

    @IsTest
    static void testExecuteHandlesExceptionWithoutRethrow() {
        resetBatchTestState();
        CreateTasksForOrderLinesBatch.throwInExecute = true;
        Integer startCount = getStartScopeCount();

        Test.startTest();
        Id jobId = Database.executeBatch(new CreateTasksForOrderLinesBatch(), startCount);
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assertEquals(0, CreateTasksForOrderLinesBatch.startCatchCount);
        System.assertEquals(1, CreateTasksForOrderLinesBatch.executeCatchCount);
        System.assertEquals(0, CreateTasksForOrderLinesBatch.finishCatchCount);
    }

    @IsTest
    static void testFinishHandlesExceptionWithoutRethrow() {
        resetBatchTestState();
        CreateTasksForOrderLinesBatch.throwInFinish = true;
        Integer startCount = getStartScopeCount();

        Test.startTest();
        Id jobId = Database.executeBatch(new CreateTasksForOrderLinesBatch(), startCount);
        try {
            Test.stopTest();
        } catch (Exception e) {
            System.assert(false, 'finish() should not rethrow');
        }

        System.assertNotEquals(null, jobId);
        System.assertEquals(0, CreateTasksForOrderLinesBatch.startCatchCount);
        System.assertEquals(0, CreateTasksForOrderLinesBatch.executeCatchCount);
        System.assertEquals(1, CreateTasksForOrderLinesBatch.finishCatchCount);
    }

    @IsTest
    static void testExecuteBranchNoOrderNumbers() {
        resetBatchTestState();

        Case openParent = [SELECT Id FROM Case WHERE Status IN ('New','Working') LIMIT 1];
        Account account = [SELECT Id FROM Account LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();

        insert new Order(AccountId = account.Id, Status = 'Draft', EffectiveDate = Date.today(),
                         Pricebook2Id = standardPricebookId, OrderNumber__c = null, parentCase__c = openParent.Id);

        Integer startCount = getStartScopeCount();

        Test.startTest();
        Id jobId = Database.executeBatch(new CreateTasksForOrderLinesBatch(), startCount);
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assertEquals(0, CreateTasksForOrderLinesBatch.startCatchCount);
        System.assertEquals(0, CreateTasksForOrderLinesBatch.executeCatchCount);
        System.assertEquals(0, CreateTasksForOrderLinesBatch.finishCatchCount);
    }
}