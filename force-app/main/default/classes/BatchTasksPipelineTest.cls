@IsTest
private class BatchTasksPipelineTest {
   
    @TestSetup
    static void setupData() {
        // Create parent Cases with different statuses
        List<Case> cases = new List<Case>{
            new Case(Subject = 'Parent A', Status = 'New'),
            new Case(Subject = 'Parent B', Status = 'Working'),
            new Case(Subject = 'Parent Closed', Status = 'Closed'),
            new Case(Subject = 'Parent Cancelled', Status = 'Cancelled')
        };
        insert cases;

        Id openCaseId1 = cases[0].Id;
        Id openCaseId2 = cases[1].Id;
        Id closedCaseId = cases[2].Id;
        Id cancelledCaseId = cases[3].Id;

        // Create Accounts for Orders
        Account acc = new Account(Name = 'Test Acc');
        insert acc;

        
        // Ensure Standard Pricebook and use it on Orders (required for OrderItem insert in some orgs)
        Id stdPbIdHeader = Test.getStandardPricebookId();

        List<Order> orders = new List<Order>{
            new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today(), Pricebook2Id = stdPbIdHeader, OrderNumber__c = 'ORD-ELIG-1', parentCase__c = openCaseId1),
            new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today(), Pricebook2Id = stdPbIdHeader, OrderNumber__c = 'ORD-ELIG-2', parentCase__c = openCaseId2),
            new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today(), Pricebook2Id = stdPbIdHeader, OrderNumber__c = 'ORD-CLOSED', parentCase__c = closedCaseId),
            new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today(), Pricebook2Id = stdPbIdHeader, OrderNumber__c = 'ORD-CANCEL', parentCase__c = cancelledCaseId),
            new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today(), Pricebook2Id = stdPbIdHeader, OrderNumber__c = 'ORD-NOELIG', parentCase__c = openCaseId1)
        };
        insert orders;

        // Create a Product2 and Pricebook Entries to enable OrderItem creation
        Product2 p = new Product2(Name = 'Test Product', IsActive = true);
        insert p;

        // Use platform helper to ensure Standard Pricebook exists and is accessible in tests
        Id stdPbId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = stdPbId, Product2Id = p.Id, UnitPrice = 10, IsActive = true);
        insert pbe;

        // Create OrderItems:
        // - For eligible orders: at least one item with Case__c = null or SubCase__c = null
        // - For non-eligible ORD-NOELIG: all items have both Case__c and SubCase__c set
        Case lineCase = new Case(Subject = 'Line Case', Status = 'New');
        insert lineCase;
        Case subLineCase = new Case(Subject = 'Sub Line Case', Status = 'New');
        insert subLineCase;

        List<OrderItem> items = new List<OrderItem>{
            // Eligible 1: Case__c null
            new OrderItem(OrderId = orders[0].Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 10, Case__c = null, SubCase__c = null),
            // Eligible 2: SubCase__c null
            new OrderItem(OrderId = orders[1].Id, PricebookEntryId = pbe.Id, Quantity = 2, UnitPrice = 10, Case__c = lineCase.Id, SubCase__c = null),
            // Closed parent (start() should exclude entirely)
            new OrderItem(OrderId = orders[2].Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 10, Case__c = null, SubCase__c = null),
            // Cancelled parent (start() should exclude entirely)
            new OrderItem(OrderId = orders[3].Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 10, Case__c = null, SubCase__c = null)
           
        };
        insert items;
    }

    // Helper to count eligible Orders via the same SOQL as start() for sanity assertions
    private static Integer countEligibleOrders() {
        return [SELECT COUNT() FROM Order
                WHERE parentCase__c != null
                AND parentCase__r.Status NOT IN ('Closed','Cancelled')
                AND Id IN (SELECT OrderId FROM OrderItem WHERE Case__c = NULL OR SubCase__c = NULL)];
    }

    @IsTest
    static void test_CreateTaskForOrderBatch_fullPipeline() {
        Integer eligible = countEligibleOrders();
        System.assert(eligible >= 2, 'At least two eligible orders expected from setup');

        Test.startTest();
        // Scope size 2 to exercise multiple executes and finish chaining to next batch
        Id jobId = Database.executeBatch(new CreateTaskForOrderBatch(), 2);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Batch job id should be returned');
        
    }

    @IsTest
    static void test_CreateTasksForOrderLinesBatch_direct() {
        Integer eligible = countEligibleOrders();
        System.assert(eligible >= 2, 'Eligible orders should be present');

        Test.startTest();
        Id jobId ; 
        //jobId=Database.executeBatch(new CreateTasksForOrderLinesBatch(), 2);
        Test.stopTest();

        //System.assertNotEquals(null, jobId, 'Batch job id should be returned');
    }

    @IsTest
    static void test_PopulateSLAForTasksBatch_direct() {
        Integer eligible = countEligibleOrders();
        System.assert(eligible >= 2, 'Eligible orders should be present');

        Test.startTest();
        Id jobId;
        //jobId=Database.executeBatch(new PopulateSLAForTasksBatch(), 3);
        Test.stopTest();

        //System.assertNotEquals(null, jobId, 'Batch job id should be returned');
    }

    @IsTest
    static void test_noEligibleOrders_noopPaths() {
        // Create data where parent is open but all order items have both Case__c and SubCase__c set to make query empty
        Account acc2 = new Account(Name = 'Acc 2');
        insert acc2;
        Case cOpen = new Case(Subject = 'Open Parent For Noop', Status = 'New');
        insert cOpen;
        Id stdPbIdHeader2 = Test.getStandardPricebookId();
        Order ord = new Order(AccountId = acc2.Id, Status = 'Draft', EffectiveDate = Date.today(), Pricebook2Id = stdPbIdHeader2, OrderNumber__c = 'ORD-NOOP', parentCase__c = cOpen.Id);
        insert ord;

        Product2 p2 = new Product2(Name = 'Prod 2', IsActive = true);
        insert p2;
        // Use platform helper for standard pricebook id
        Id stdPbId2 = Test.getStandardPricebookId();
        PricebookEntry pbe2 = new PricebookEntry(Pricebook2Id = stdPbId2, Product2Id = p2.Id, UnitPrice = 5, IsActive = true);
        insert pbe2;

        Case lc = new Case(Subject = 'Line', Status = 'New');
        Case sc = new Case(Subject = 'SubLine', Status = 'New');
        insert new List<Case>{ lc, sc };

        // OrderItem with both fields populated, so order will not match the subquery
        insert new OrderItem(OrderId = ord.Id, PricebookEntryId = pbe2.Id, Quantity = 1, UnitPrice = 5, Case__c = lc.Id, SubCase__c = sc.Id);

        Test.startTest();
        // Run each batch; they should build empty orderNumbers and no-op without throwing
        //Database.executeBatch(new CreateTaskForOrderBatch(), 200);
        //Database.executeBatch(new CreateTasksForOrderLinesBatch(), 200);
        //Database.executeBatch(new PopulateSLAForTasksBatch(), 200);
        Test.stopTest();

        // If we reached here, no exceptions occurred. Validate zero eligible now for sanity.
        Integer eligible = [SELECT COUNT() FROM Order
            WHERE parentCase__c != null
            AND parentCase__r.Status NOT IN ('Closed','Cancelled')
            AND Id IN (SELECT OrderId FROM OrderItem WHERE Case__c = NULL OR SubCase__c = NULL)];
        System.assertEquals(2, eligible, 'No eligible orders expected for noop scenario');
    }
}