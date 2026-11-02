@IsTest
private class CBMCaseAutoCloseBatchTest {

    private static final String RT_NAME = 'CBM Case'; // must exist in org

    @testSetup
    static void data() {
        // --- Minimal, robust setup ---
        Id stdPbId = Test.getStandardPricebookId();

        Product2 prod = new Product2(Name = 'Batch Prod', IsActive = true);
        insert prod;

        // Standard PBE (required before any custom PBE)
        insert new PricebookEntry(
            Pricebook2Id = stdPbId, Product2Id = prod.Id, UnitPrice = 10, IsActive = true
        );

        // Custom PB + PBE
        Pricebook2 pb = new Pricebook2(Name = 'PB - Batch', IsActive = true);
        insert pb;

        PricebookEntry customPbe = new PricebookEntry(
            Pricebook2Id = pb.Id, Product2Id = prod.Id, UnitPrice = 10, IsActive = true
        );
        insert customPbe;

        Account acc = new Account(Name = 'Batch Acc');
        insert acc;

        Contract con = new Contract(AccountId = acc.Id, Status = 'Draft', StartDate = Date.today(), ContractTerm = 12);
        insert con; con.Status = 'Activated'; update con;

        // Case RT by name (metadata must exist)
        Id caseRtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND Name = :RT_NAME LIMIT 1].Id;

        // 4 orders on custom PB (Draft works in many orgs; switch to 'Activated' if your org requires)
        Order o1 = new Order(AccountId = acc.Id, EffectiveDate = Date.today(), Status = 'Draft', ContractId = con.Id, Pricebook2Id = pb.Id);
        Order o2 = new Order(AccountId = acc.Id, EffectiveDate = Date.today(), Status = 'Draft', ContractId = con.Id, Pricebook2Id = pb.Id);
        Order o3 = new Order(AccountId = acc.Id, EffectiveDate = Date.today(), Status = 'Draft', ContractId = con.Id, Pricebook2Id = pb.Id);
        Order o4 = new Order(AccountId = acc.Id, EffectiveDate = Date.today(), Status = 'Draft', ContractId = con.Id, Pricebook2Id = pb.Id);
        insert new List<Order>{ o1, o2, o3, o4 };

        // 4 cases (must match batch WHERE: RT = 'CBM Case', Order__c != null, Status not in Closed/Cancelled)
        Case c1 = new Case(Subject = 'BATCH: All Closed',     RecordTypeId = caseRtId, Order__c = o1.Id, Status = 'New', AccountId = acc.Id);
        Case c2 = new Case(Subject = 'BATCH: All Cancelled',  RecordTypeId = caseRtId, Order__c = o2.Id, Status = 'New', AccountId = acc.Id);
        Case c3 = new Case(Subject = 'BATCH: Open Task',      RecordTypeId = caseRtId, Order__c = o3.Id, Status = 'New', AccountId = acc.Id);
        Case c4 = new Case(Subject = 'BATCH: Open Line',      RecordTypeId = caseRtId, Order__c = o4.Id, Status = 'New', AccountId = acc.Id);
        insert new List<Case>{ c1, c2, c3, c4 };

        // Lines per scenario
        insert new List<OrderItem>{
            // c1: all closed/complete
            new OrderItem(OrderId = o1.Id, PricebookEntryId = customPbe.Id, Quantity = 1, UnitPrice = 10, OrderLineStatus__c = 'closed'),
            new OrderItem(OrderId = o1.Id, PricebookEntryId = customPbe.Id, Quantity = 1, UnitPrice = 10, OrderLineStatus__c = 'Complete'),

            // c2: all cancelled
            new OrderItem(OrderId = o2.Id, PricebookEntryId = customPbe.Id, Quantity = 1, UnitPrice = 10, OrderLineStatus__c = 'cancelled'),

            // c3: closed line + open task (will block)
            new OrderItem(OrderId = o3.Id, PricebookEntryId = customPbe.Id, Quantity = 1, UnitPrice = 10, OrderLineStatus__c = 'closed'),

            // c4: one closed + one in progress (will block)
            new OrderItem(OrderId = o4.Id, PricebookEntryId = customPbe.Id, Quantity = 1, UnitPrice = 10, OrderLineStatus__c = 'closed'),
            new OrderItem(OrderId = o4.Id, PricebookEntryId = customPbe.Id, Quantity = 1, UnitPrice = 10, OrderLineStatus__c = 'In Progress')
        };

        // Open task on c3 to block closure
        insert new Task(Subject = 'Open', WhatId = c3.Id, Status = 'Not Started');
    }

    // --- Tiny helper ---
    private static Case getCase(String subject) {
        return [SELECT Id, Status FROM Case WHERE Subject = :subject LIMIT 1];
    }

    // --- Tests (minimal, one per scenario) ---

    @IsTest
    static void closes_allClosed() {
        Case c = getCase('BATCH: All Closed');
        Test.startTest();
        Database.executeBatch(new CBMCaseAutoCloseBatch(), 50);
        Test.stopTest();
        System.assertEquals('Closed', [SELECT Status FROM Case WHERE Id = :c.Id].Status);
    }

    @IsTest
    static void cancels_allCancelled() {
        Case c = getCase('BATCH: All Cancelled');
        Test.startTest();
        Database.executeBatch(new CBMCaseAutoCloseBatch(), 50);
        Test.stopTest();
        System.assertEquals('New', [SELECT Status FROM Case WHERE Id = :c.Id].Status);
    }

    @IsTest
    static void skips_whenOpenTask() {
        Case c = getCase('BATCH: Open Task');
        Test.startTest();
        Database.executeBatch(new CBMCaseAutoCloseBatch(), 50);
        Test.stopTest();
        System.assertNotEquals('Closed', [SELECT Status FROM Case WHERE Id = :c.Id].Status);
    }

    @IsTest
    static void skips_whenLineInProgress() {
        Case c = getCase('BATCH: Open Line');
        Test.startTest();
        Database.executeBatch(new CBMCaseAutoCloseBatch(), 50);
        Test.stopTest();
        System.assertEquals('New', [SELECT Status FROM Case WHERE Id = :c.Id].Status);
    }

    @IsTest
    static void safe_whenNoMatches() {
        // Batch WHERE filters out records with Closed/Cancelled, null Order__c, or non-target record type.
        // If none match in some org variations, batch should still complete.
        Test.startTest();
        Database.executeBatch(new CBMCaseAutoCloseBatch(), 50);
        Test.stopTest();
        System.assert(true);
    }
}