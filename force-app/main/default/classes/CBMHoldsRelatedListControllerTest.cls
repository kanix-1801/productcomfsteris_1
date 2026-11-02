@IsTest
private class CBMHoldsRelatedListControllerTest {
    
    @testSetup
    static void setupData() {
        // 1. Get Standard Pricebook ID
        Id pricebookId = Test.getStandardPricebookId();
        
        // 2. Create a Test User
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'tuser', Email='testuser@ford.com', 
            EmailEncodingKey='UTF-8', LastName='Testing', LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', ProfileId = p.Id, 
            TimeZoneSidKey='America/Los_Angeles', UserName='testuser' + DateTime.now().getTime() + '@ford.com',
            IsActive = true
        );
        insert testUser;
        
        // 3. Create Account
        Account acc = new Account(Name = 'Test Account', SourceSystemID__c = 'TEST001', SystemID__c = 'SYSID001');
        insert acc;
        
        // 4. Create Case (RecordType CBMCase)
        Id caseRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('CBMCase').getRecordTypeId();
        Case c = new Case(
            Subject = 'Test Case',
            AccountId = acc.Id,
            RecordTypeId = caseRecordTypeId,
            UrgentOrder__c = true,
            Status = 'New'
        );
        insert c;
        
        // 5. Create Order - ASSIGN PRICEBOOK HERE
        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            OrderNumber__c = 'ORD123',
            ParentCase__c = c.Id,
            RegistrationNumber__c = 'REG123',
            OrderClassification__c = 'New',
            CurrencyIsoCode = 'USD',
            AllCapitalLinesClosedDate__c = date.Today() - 7,
            FirstScheduledDateNonPreinstall__c = date.Today() + 70,
            Pricebook2Id = pricebookId // Required to add OrderItems
        );
        insert ord;
        
        // Link Case back to Order (Case.Order__c is used in the helper queries)
        c.Order__c = ord.Id;
        update c;
        
        // 6. Create Product and PricebookEntry
        Product2 prod = new Product2(Name = 'Test Product', IsActive = true, SalesCategory__c = 'Capital Equipment');
        insert prod;
        
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pricebookId, 
            Product2Id = prod.Id, 
            UnitPrice = 100, 
            IsActive = true
        );
        insert pbe;
        
        // 7. Create OrderItem (Order Line)
        OrderItem line = new OrderItem(
            OrderId = ord.Id,
            TASSalesCategory__c = 'ORI',
            PricebookEntryId = pbe.Id,
            LineNumber__c = '1.1',
            Quantity = 1,
            UnitPrice = 100 ,
           ScheduledDate__c = Date.today().addDays(5)
        );
        insert line;
        HoldMatrix__c holdtest = new HoldMatrix__c(
            
            Name = 'Credit Check Failure'
        );
        insert holdtest;
        
        
        // 8. Create OrderAndOrderLineHold__c        
        insert new List<OrderAndOrderLineHold__c>{
            new OrderAndOrderLineHold__c(
                Order__c = ord.Id,
                OrderLine__c = line.Id,
                ReasonCode__c = 'ADR',
                HoldMatrix__c = holdtest.Id
            ),
            new OrderAndOrderLineHold__c(
                Order__c = ord.Id,
                OrderLine__c = line.Id,
                ReasonCode__c = 'IOA',
                HoldMatrix__c = holdtest.Id
            ),
            new OrderAndOrderLineHold__c(
                Order__c = ord.Id,
                OrderLine__c = line.Id,
                ReasonCode__c = 'ENG',
                HoldMatrix__c = holdtest.Id
            ),
            new OrderAndOrderLineHold__c(
                Order__c = ord.Id,
                OrderLine__c = line.Id,
                ReasonCode__c = 'C1',
                HoldMatrix__c = holdtest.Id
            )
        };
        
        // 9. Case Team Setup
        // Ensure a role exists. If not, this might need a try/catch or manual creation of role in some orgs.
        CaseTeamRole role = [SELECT Id FROM CaseTeamRole LIMIT 1];
        CaseTeamMember ctm = new CaseTeamMember(
            ParentId = c.Id,
            MemberId = testUser.Id,
            TeamRoleId = role.Id
        );
        insert ctm;
    }

    @IsTest
    static void groupsRecordsAndIgnoresBlankFifthValues() {

        Order parentRecord = [SELECT Id, OrderNumber__c, ParentCase__c FROM Order LIMIT 1];

        
        Test.startTest();
        List<CBMHoldsRelatedListController.GroupedRecordRow> rows =
            CBMHoldsRelatedListController.getGroupedRecords(parentRecord.ParentCase__c);
        Test.stopTest();

        Map<String, String> valuesByFirstField = new Map<String, String>();
        for (CBMHoldsRelatedListController.GroupedRecordRow row : rows) {
            valuesByFirstField.put(row.lineNumber, row.holdCodes);
        }

        System.assertEquals('ADR, C1, ENG, IOA', valuesByFirstField.get('1.1'));
    }

    @IsTest
    static void returnsEmptyListForNullRecordId() {
        Test.startTest();
        List<CBMHoldsRelatedListController.GroupedRecordRow> rows =
            CBMHoldsRelatedListController.getGroupedRecords(null);
        Test.stopTest();

        System.assertEquals(0, rows.size());
    }
}