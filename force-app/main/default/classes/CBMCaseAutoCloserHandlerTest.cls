@isTest
private class CBMCaseAutoCloserHandlerTest {

    @testSetup
    static void setupData() {

        // 1) Always-safe way to get the Standard Price Book in tests
        Id standardPbId = Test.getStandardPricebookId();

        // 2) Create a Product
        Product2 prod = new Product2(Name = 'Test Product', IsActive = true);
        insert prod;

        // 3) Create STANDARD PricebookEntry (REQUIRED before any custom PBE)
        PricebookEntry stdPbe = new PricebookEntry(
            Pricebook2Id = standardPbId,
            Product2Id   = prod.Id,
            UnitPrice    = 10,
            IsActive     = true
        );
        insert stdPbe;

        // 4) Create a custom Price Book
        Pricebook2 customPb = new Pricebook2(Name = 'UT Custom PB', IsActive = true);
        insert customPb;

        // 5) Create CUSTOM PricebookEntry (to use on Orders)
        PricebookEntry customPbe = new PricebookEntry(
            Pricebook2Id = customPb.Id,
            Product2Id   = prod.Id,
            UnitPrice    = 10,
            IsActive     = true
        );
        insert customPbe;

        // 6) Create Account
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // 7) Create & Activate Contract (common org requirement for Orders)
        Contract con = new Contract(
            AccountId    = acc.Id,
            Status       = 'Draft',
            StartDate    = Date.today(),
            ContractTerm = 12
        );
        insert con;
        con.Status = 'Activated';
        update con;

        // 8) Create Orders pointing to the CUSTOM price book
        List<Order> orders = new List<Order>();
        for (Integer i = 0; i < 4; i++) {
            orders.add(new Order(
                AccountId     = acc.Id,
                EffectiveDate = Date.today(),
                Status        = 'Draft',     // Draft is fine in most orgs; change to 'Activated' if yours requires it
                ContractId    = con.Id,
                Pricebook2Id  = customPb.Id  // IMPORTANT
            ));
        }
        insert orders;

        // 9) Create Cases linked to those Orders
        List<Case> cases = new List<Case>{
            new Case(Subject = 'Case All Closed',     Order__c = orders[0].Id, Status = 'New', AccountId = acc.Id),
            new Case(Subject = 'Case All Cancelled',  Order__c = orders[1].Id, Status = 'New', AccountId = acc.Id),
            new Case(Subject = 'Case With Open Task', Order__c = orders[2].Id, Status = 'New', AccountId = acc.Id),
            new Case(Subject = 'Case With Open Line', Order__c = orders[3].Id, Status = 'New', AccountId = acc.Id)
        };
        insert cases;
    }

    // Helper – get the custom PBE we created (not the standard one)
    private static PricebookEntry getCustomPbe() {
        return [
            SELECT Id, UnitPrice
            FROM PricebookEntry
            WHERE IsActive = TRUE
            AND Pricebook2.IsStandard = FALSE
            LIMIT 1
        ];
    }

    @isTest
    static void testCaseShouldCloseWhenAllLinesClosed() {
        Case c = [SELECT Id, Order__c, Status FROM Case WHERE Subject = 'Case All Closed' LIMIT 1];
        PricebookEntry pbe = getCustomPbe();

        // Two closed/complete lines
        insert new List<OrderItem>{
            new OrderItem(
                OrderId = c.Order__c, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 10,
                OrderLineStatus__c = 'closed'
            ),
            new OrderItem(
                OrderId = c.Order__c, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 10,
                OrderLineStatus__c = 'Complete'
            )
        };

        Test.startTest();
        new CBMCaseAutoCloserHandler().evaluateAndUpdateCases(new List<Case>{ c });
        Test.stopTest();

        Case updated = [SELECT Status FROM Case WHERE Id = :c.Id];
        System.assertEquals('Closed', updated.Status, 'Case should be closed when all lines are closed/complete.');
    }

    @isTest
    static void testCaseShouldCancelWhenAllLinesCancelled() {
        Case c = [SELECT Id, Order__c, Status FROM Case WHERE Subject = 'Case All Cancelled' LIMIT 1];
        PricebookEntry pbe = getCustomPbe();

        insert new OrderItem(
            OrderId = c.Order__c, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 10,
            OrderLineStatus__c = 'cancelled'
        );

        Test.startTest();
        new CBMCaseAutoCloserHandler().evaluateAndUpdateCases(new List<Case>{ c });
        Test.stopTest();

        Case updated = [SELECT Status FROM Case WHERE Id = :c.Id];
        System.assertEquals('Cancelled', updated.Status, 'Case should be cancelled when all lines are cancelled.');
    }

    @isTest
    static void testCaseShouldNotCloseIfOpenTaskExists() {
        Case c = [SELECT Id, Order__c, Status FROM Case WHERE Subject = 'Case With Open Task' LIMIT 1];
        PricebookEntry pbe = getCustomPbe();

        insert new OrderItem(
            OrderId = c.Order__c, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 10,
            OrderLineStatus__c = 'closed'
        );

        // Open task on Case prevents closure
        insert new Task(Subject = 'Call Client', WhatId = c.Id, Status = 'Not Started');

        Test.startTest();
        new CBMCaseAutoCloserHandler().evaluateAndUpdateCases(new List<Case>{ c });
        Test.stopTest();

        Case updated = [SELECT Status FROM Case WHERE Id = :c.Id];
        System.assertNotEquals('Closed', updated.Status, 'Case should NOT close if there is an open task.');
    }

    @isTest
    static void testCaseShouldNotCloseIfLinesAreInProgress() {
        Case c = [SELECT Id, Order__c, Status FROM Case WHERE Subject = 'Case With Open Line' LIMIT 1];
        PricebookEntry pbe = getCustomPbe();

        insert new List<OrderItem>{
            new OrderItem(
                OrderId = c.Order__c, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 10,
                OrderLineStatus__c = 'closed'
            ),
            new OrderItem(
                OrderId = c.Order__c, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 10,
                OrderLineStatus__c = 'In Progress'
            )
        };

        Test.startTest();
        new CBMCaseAutoCloserHandler().evaluateAndUpdateCases(new List<Case>{ c });
        Test.stopTest();

        Case updated = [SELECT Status FROM Case WHERE Id = :c.Id];
        System.assertEquals('New', updated.Status, 'Case should remain New if any line is not closed/cancelled.');
    }

    @isTest
    static void testEmptyListPerformance() {
        Test.startTest();
        CBMCaseAutoCloserHandler handler = new CBMCaseAutoCloserHandler();
        handler.evaluateAndUpdateCases(null);
        handler.evaluateAndUpdateCases(new List<Case>());
        Test.stopTest();

        System.assert(true, 'Handler should safely ignore null/empty lists.');
    }
}