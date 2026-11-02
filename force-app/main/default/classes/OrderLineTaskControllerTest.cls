@IsTest
private class OrderLineTaskControllerTest {

    @testSetup
    static void setupData() {
        // 1) Account
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // 2) Order (with Standard Pricebook)
        Id pricebookId = Test.getStandardPricebookId();
        Order ord = new Order(
            AccountId     = acc.Id,
            EffectiveDate = Date.today(),
            Status        = 'Draft',
            Pricebook2Id  = pricebookId
        );
        insert ord;

        // 3) Product
        Product2 prod = new Product2(
            Name     = 'Test Product',
            IsActive = true
        );
        insert prod;

        // 4) PricebookEntry (Standard)
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id   = prod.Id,
            UnitPrice    = 100,
            IsActive     = true
        );
        insert pbe;

        // 5) OrderItems (Order Lines)
        OrderItem oi1 = new OrderItem(
            OrderId          = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 1,
            UnitPrice        = 100
        );
        OrderItem oi2 = new OrderItem(
            OrderId          = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 2,
            UnitPrice        = 200
        );
        insert new List<OrderItem>{ oi1, oi2 };

        // 6) Tasks linked to the Order and Order Lines
        // phase__c is treated as a numeric/Decimal field
        Task t1 = new Task(
            Subject      = 'Main Task',
            Order__c     = ord.Id,
            OrderLine__c = oi1.Id,
            phase__c     = 1,
            Status       = 'Not Started',
            Priority     = 'Normal'
        );
        Task t2 = new Task(
            Subject      = 'Secondary Task',
            Order__c     = ord.Id,
            OrderLine__c = oi2.Id,
            phase__c     = 1,
            Status       = 'Not Started',
            Priority     = 'Normal'
        );
        insert new List<Task>{ t1, t2 };
    }

    @IsTest
    static void testGetRelatedOrderLinesSuccess() {
        // Arrange: main task for phase=1 on the same Order as another task
        Task mainTask = [
            SELECT Id, Order__c, OrderLine__c, phase__c
            FROM Task
            WHERE Subject = 'Main Task'
            LIMIT 1
        ];

        // Act
        Test.startTest();
        List<OrderItem> results = OrderLineTaskController.getRelatedOrderLines(mainTask.Id);
        Test.stopTest();

        // Assert (robust & implementation-agnostic):
        // We expect at least one related line given our dataset has two tasks on same order & phase.
        System.assertNotEquals(null, results, 'Results list should not be null.');
        System.assert(results.size() >= 1,
            'Should return at least one related order item for same Order and phase.');

        // All returned lines must belong to the same Order as the main task
        Set<Id> nonMatchingOrderLineIds = new Set<Id>();
        for (OrderItem oi : results) {
            Id oiOrderId = [SELECT OrderId FROM OrderItem WHERE Id = :oi.Id].OrderId;
            if (oiOrderId != mainTask.Order__c) {
                nonMatchingOrderLineIds.add(oi.Id);
            }
        }
        System.assertEquals(
            0, nonMatchingOrderLineIds.size(),
            'All returned order items must belong to the same Order as the main task.'
        );

        // Optional (safe informational checks): verify either the same line or the other line is present.
        // This avoids hard-coding behavior if the controller includes the main line.
        // We'll just ensure the returned set is a subset of the known two lines we created.
        Set<Id> validLineIds = new Set<Id>();
        for (OrderItem oiCheck : [
            SELECT Id FROM OrderItem ORDER BY CreatedDate ASC LIMIT 2
        ]) {
            validLineIds.add(oiCheck.Id);
        }
        for (OrderItem returned : results) {
            System.assert(validLineIds.contains(returned.Id),
                'Returned item must be one of the created order lines.');
        }
    }

    @IsTest
    static void testGetRelatedOrderLinesNoOrder() {
        // Arrange: a task with no Order__c
        Task standaloneTask = new Task(
            Subject = 'Standalone',
            Status  = 'Not Started',
            Priority= 'Normal'
        );
        insert standaloneTask;

        // Act
        Test.startTest();
        List<OrderItem> results = OrderLineTaskController.getRelatedOrderLines(standaloneTask.Id);
        Test.stopTest();

        // Assert
        System.assertEquals(0, results.size(),
            'A task without an Order should return 0 related order items.');
    }

    @IsTest
    static void testGetRelatedOrderLinesNoOrderLinesOnTasks() {
        // Arrange: create a task on an Order but without OrderLine__c and with a different phase
        Order ord = [SELECT Id FROM Order LIMIT 1];
        Task taskNoLine = new Task(
            Subject  = 'No Line Task',
            Order__c = ord.Id,
            phase__c = 2,
            Status   = 'Not Started',
            Priority = 'Normal'
        );
        insert taskNoLine;

        // Act
        Test.startTest();
        List<OrderItem> results = OrderLineTaskController.getRelatedOrderLines(taskNoLine.Id);
        Test.stopTest();

        // Assert
        System.assertEquals(0, results.size(),
            'Task with no OrderLine__c and a phase with no matching peers should return 0.');
    }
}