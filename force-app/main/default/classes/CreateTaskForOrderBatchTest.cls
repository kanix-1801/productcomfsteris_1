/**
 * @author PSL
 * @date 12-23-2025
 * @description Test class for CreateTaskForOrderBatch batch class
 */
@IsTest(SeeAllData=false)
private class CreateTaskForOrderBatchTest {

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

        Id standardPricebookIdHeader = Test.getStandardPricebookId();
        List<Order> orders = new List<Order>{
            new Order(AccountId = account.Id, Status = 'Draft', EffectiveDate = Date.today(),
                      Pricebook2Id = standardPricebookIdHeader, OrderNumber__c = 'ORD-ELIG-1', parentCase__c = openCaseId1),
            new Order(AccountId = account.Id, Status = 'Draft', EffectiveDate = Date.today(),
                      Pricebook2Id = standardPricebookIdHeader, OrderNumber__c = 'ORD-ELIG-2', parentCase__c = openCaseId2),
            new Order(AccountId = account.Id, Status = 'Draft', EffectiveDate = Date.today(),
                      Pricebook2Id = standardPricebookIdHeader, OrderNumber__c = 'ORD-CLOSED', parentCase__c = closedCaseId),
            new Order(AccountId = account.Id, Status = 'Draft', EffectiveDate = Date.today(),
                      Pricebook2Id = standardPricebookIdHeader, OrderNumber__c = 'ORD-CANCEL', parentCase__c = cancelledCaseId),
            new Order(AccountId = account.Id, Status = 'Draft', EffectiveDate = Date.today(),
                      Pricebook2Id = standardPricebookIdHeader, OrderNumber__c = 'ORD-NOELIG', parentCase__c = openCaseId1)
        };
        insert orders;

        Product2 product = new Product2(Name = 'Test Product', IsActive = true);
        insert product;

        Id standardPricebookId = Test.getStandardPricebookId();
        PricebookEntry pricebookEntry = new PricebookEntry(Pricebook2Id = standardPricebookId, Product2Id = product.Id, UnitPrice = 10, IsActive = true);
        insert pricebookEntry;

        Case lineCase = new Case(Subject = 'Line Case', Status = 'New');
        Case subLineCase = new Case(Subject = 'Sub Line Case', Status = 'New');
        insert new List<Case>{ lineCase, subLineCase };

        List<OrderItem> orderItems = new List<OrderItem>{
            new OrderItem(OrderId = orders[0].Id, PricebookEntryId = pricebookEntry.Id, Quantity = 1, UnitPrice = 10, Case__c = null,        SubCase__c = null),
            new OrderItem(OrderId = orders[1].Id, PricebookEntryId = pricebookEntry.Id, Quantity = 2, UnitPrice = 10, Case__c = lineCase.Id,  SubCase__c = null),
            new OrderItem(OrderId = orders[2].Id, PricebookEntryId = pricebookEntry.Id, Quantity = 1, UnitPrice = 10, Case__c = null,        SubCase__c = null),
            new OrderItem(OrderId = orders[3].Id, PricebookEntryId = pricebookEntry.Id, Quantity = 1, UnitPrice = 10, Case__c = null,        SubCase__c = null),
            new OrderItem(OrderId = orders[4].Id, PricebookEntryId = pricebookEntry.Id, Quantity = 1, UnitPrice = 10, Case__c = lineCase.Id,  SubCase__c = subLineCase.Id)
        };
        insert orderItems;
    }

    private static Integer getStartScopeCount() {
        return [SELECT COUNT() FROM Order
                WHERE parentCase__c != null
                  AND parentCase__r.Status NOT IN ('Closed','Cancelled')];
    }

    private static void resetBatchTestState() {
        CreateTaskForOrderBatch.throwInStart   = false;
        CreateTaskForOrderBatch.throwInExecute = false;
        CreateTaskForOrderBatch.throwInFinish  = false;
        CreateTaskForOrderBatch.startCatchCount   = 0;
        CreateTaskForOrderBatch.executeCatchCount = 0;
        CreateTaskForOrderBatch.finishCatchCount  = 0;
    }

    @IsTest
    static void testHappyPathSingleChunk() {
        resetBatchTestState();
        Integer startCount = getStartScopeCount();

        Test.startTest();
        Id jobId = Database.executeBatch(new CreateTaskForOrderBatch(), startCount);
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assertEquals(0, CreateTaskForOrderBatch.startCatchCount);
        System.assertEquals(0, CreateTaskForOrderBatch.executeCatchCount);
        System.assertEquals(0, CreateTaskForOrderBatch.finishCatchCount);
    }

    @IsTest
    static void testStartThrowsAndRethrows() {
        resetBatchTestState();
        CreateTaskForOrderBatch.throwInStart = true;

        Test.startTest();
        Id jobId = Database.executeBatch(new CreateTaskForOrderBatch(), 200);
        try {
            Test.stopTest();
            System.assert(false, 'Expected exception from start()');
        } catch (Exception e) {
            System.assertNotEquals(null, e);
        }

        System.assertNotEquals(null, jobId);
        System.assertEquals(1, CreateTaskForOrderBatch.startCatchCount);
        System.assertEquals(0, CreateTaskForOrderBatch.executeCatchCount);
        System.assertEquals(0, CreateTaskForOrderBatch.finishCatchCount);
    }

    @IsTest
    static void testExecuteHandlesExceptionWithoutRethrow() {
        resetBatchTestState();
        CreateTaskForOrderBatch.throwInExecute = true;
        Integer startCount = getStartScopeCount();

        Test.startTest();
        Id jobId = Database.executeBatch(new CreateTaskForOrderBatch(), startCount);
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assertEquals(0, CreateTaskForOrderBatch.startCatchCount);
        System.assertEquals(1, CreateTaskForOrderBatch.executeCatchCount);
        System.assertEquals(0, CreateTaskForOrderBatch.finishCatchCount);
    }

    @IsTest
    static void testFinishHandlesExceptionWithoutRethrow() {
        resetBatchTestState();
        CreateTaskForOrderBatch.throwInFinish = true;
        Integer startCount = getStartScopeCount();

        Test.startTest();
        Id jobId = Database.executeBatch(new CreateTaskForOrderBatch(), startCount);
        try {
            Test.stopTest();
        } catch (Exception e) {
            System.assert(false, 'finish() should not rethrow');
        }

        System.assertNotEquals(null, jobId);
        System.assertEquals(0, CreateTaskForOrderBatch.startCatchCount);
        System.assertEquals(0, CreateTaskForOrderBatch.executeCatchCount);
        System.assertEquals(1, CreateTaskForOrderBatch.finishCatchCount);
    }

    @IsTest
    static void testExecuteBranchNoOrderNumbers() {
        resetBatchTestState();

        Case openParent = [SELECT Id FROM Case WHERE Status IN ('New','Working') LIMIT 1];
        Account account = [SELECT Id FROM Account LIMIT 1];
        Id standardPricebookIdHeader = Test.getStandardPricebookId();

        insert new Order(AccountId = account.Id, Status = 'Draft', EffectiveDate = Date.today(),
                         Pricebook2Id = standardPricebookIdHeader, OrderNumber__c = null, parentCase__c = openParent.Id);

        Integer startCount = getStartScopeCount();

        Test.startTest();
        Id jobId = Database.executeBatch(new CreateTaskForOrderBatch(), startCount);
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assertEquals(0, CreateTaskForOrderBatch.startCatchCount);
        System.assertEquals(0, CreateTaskForOrderBatch.executeCatchCount);
        System.assertEquals(0, CreateTaskForOrderBatch.finishCatchCount);
    }
}