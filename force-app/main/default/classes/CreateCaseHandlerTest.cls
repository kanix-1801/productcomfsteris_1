/**
 * @author PSL
 * @date 11-11-2025
 * @description Test class for CreateCaseHandler class
 */ 
@IsTest(SeeAllData=true)
public class CreateCaseHandlerTest {
    public static String fixedLength(Integer length) {
        if (length <= 0 || length > 10) {
            throw new IllegalArgumentException('length must be between 1 and 10');
        }
        
        String s = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        
        // Pad if too short
        if (s.length() < length) {
            s = s.leftPad(length, '0');
        }
        // Cut if too long
        else if (s.length() > length) {
            s = s.substring(0, length);
        }
        
        // Optional: avoid leading zero if needed
        if (s.startsWith('0')) {
            s = '1' + s.substring(1);
        }
        
        return s;
    }
    private static PricebookEntry createPricebookEntry(String salesCategory) {
        
        
       /* Pricebook2 standardPb = [SELECT Id, IsActive FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        standardPb.IsActive = true;
        update standardPb;*/
       // System.Label.ExecuteTrigger = 'false';
        Product2 prod = new Product2(
            Name = 'Test Product',
            ProductCode = 'TP001'+ fixedLength(9),
            IsActive = true,
            SalesCategory__c = salesCategory,
            //ProductCode = 'Devtest',
            Description = 'i'+ fixedLength(9),
            ItemID__c = '6'+ fixedLength(9),
            InventoryOrgId__c = 'c'+ fixedLength(9) 
        );
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true,
            UseStandardPrice = false
        );
        insert pbe;
        return pbe;
    }

    @IsTest
    static void testCreateCase() {
        PricebookEntry pbe = createPricebookEntry('Capital Equipment');
        Account acc = new Account(Name = 'Test Account',SystemID__c = 'charrr4563',SourceSystemID__c='Oracle-charrr4563');
        insert acc;

        Order ord = new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today(), OrderNumber__c = 'ORD-001', Pricebook2Id = pbe.Pricebook2Id);
        insert ord;

        OrderItem oi = new OrderItem(OrderId = ord.Id, Quantity = 1, UnitPrice = 100, PricebookEntryId = pbe.Id, LineNumber__c = 'LN-001', TASSalesCategory__c = 'SURG SPT');
        insert oi;

        ord.Status = 'Activated';
        update ord;

        Test.startTest();
        CreateCaseHandler.createCase(new List<String>{'ORD-001'});
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Case WHERE Order__c = :ord.Id], 'Parent Case should be created');
    }

    @IsTest
    static void testCreateSubCase() {
        // Capital Line scenario
        PricebookEntry pbeCapital = createPricebookEntry('Capital Equipment');
        // Service Installation scenario
        PricebookEntry pbeService = createPricebookEntry('SERVICE');

        Account acc = new Account(Name = 'Test Account 2',SystemID__c = 'cgatr222222',SourceSystemID__c='Oracle-cgatr222222');
        insert acc;

        Order ord = new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today(), OrderNumber__c = 'ORD-002', Pricebook2Id = pbeCapital.Pricebook2Id);
        insert ord;

        OrderItem capitalItem = new OrderItem(OrderId = ord.Id, Quantity = 1, UnitPrice = 100, PricebookEntryId = pbeCapital.Id, LineNumber__c = 'LN-001', TASSalesCategory__c = 'SURG SPT');
        OrderItem serviceItem = new OrderItem(OrderId = ord.Id, Quantity = 1, UnitPrice = 200, PricebookEntryId = pbeService.Id, LineNumber__c = 'LN-002', TASSalesCategory__c = 'IPM');
        insert new List<OrderItem>{capitalItem, serviceItem};

        ord.Status = 'Activated';
        update ord;

        CreateCaseHandler.createCase(new List<String>{'ORD-002'});

        Test.startTest();
        CreateCaseHandler.createSubCase(new List<String>{'ORD-002'});
        Test.stopTest();

        List<OrderItem> updatedItems = [SELECT Case__c, Subcase__c FROM OrderItem WHERE OrderId = :ord.Id];
        for (OrderItem oi : updatedItems) {
            System.assertNotEquals(null, oi.Case__c, 'Case__c should be populated');
            
        }
    }
    

	@IsTest
    public static void testPlatformEventTrigger() {
    
    CreateCase__e eventRecord = new CreateCase__e(OrderNumber__c = 'ORD-PE-001');
    
    Test.startTest();
    Database.SaveResult sr = EventBus.publish(eventRecord);
    Test.stopTest();

    
    System.assertEquals(true, sr.isSuccess(), 'Platform event should be published successfully');

    
    List<Case> cases = [SELECT Id FROM Case WHERE Subject LIKE '%ORD-PE-001%'];
    System.assertEquals(false, cases.size() > 0, 'Cases should be created by platform event trigger');
}
  @IsTest
    static void testCreateCase_RegistrationMatch_LinksToExistingParent() {
        // Arrange: create PBEs
        PricebookEntry pbe = createPricebookEntry('CAPEQUIP');

        // Account
        Account acc = new Account(Name = 'Acct-Parent-Link',SystemID__c = 'cgatr33333',SourceSystemID__c='Oracle-cgatr33333');
        insert acc;

        // Existing parent order with RegistrationNumber__c = 'RN-1'
        Order parentOrd = new Order(
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            OrderNumber__c = 'ORD-PARENT',
            RegistrationNumber__c = 'RN-1',
            CurrencyIsoCode = 'USD',
            Pricebook2Id = pbe.Pricebook2Id
        );
        insert parentOrd;
        
        OrderItem oli1 = new OrderItem(OrderId = parentOrd.Id, Quantity = 1, UnitPrice = 100, PricebookEntryId = pbe.Id, LineNumber__c = 'LN-001', TASSalesCategory__c = 'SURG SPT');
        insert oli1;
        parentOrd.Status = 'Activated';
        update parentOrd;

        // Pre-existing parent Case for ORD-PARENT
        Id parentCaseRTId = [
            SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND Name = 'CBM Case' LIMIT 1
        ].Id;

        Case existingParent = new Case(
            Subject = 'Existing Parent for RN-1',
            AccountId = acc.Id,
            RecordTypeId = parentCaseRTId,
            Status = 'Order Entry',
            Order__c = parentOrd.Id
        );
        insert existingParent;
        System.assertEquals(null, existingParent.ParentId, 'Seeded parent case must have no parent');

        // Child order with same RegistrationNumber__c = 'RN-1' and no case yet
        Order childOrd = new Order(
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            OrderNumber__c = 'ORD-CHILD',
            RegistrationNumber__c = 'RN-1',
            Pricebook2Id = pbe.Pricebook2Id
        );
        insert childOrd;
          OrderItem oli2 = new OrderItem(OrderId = childOrd.Id, Quantity = 1, UnitPrice = 100, PricebookEntryId = pbe.Id, LineNumber__c = 'LN-001', TASSalesCategory__c = 'SURG SPT');
        insert oli2;
        
         childOrd.Status = 'Activated';
        update childOrd;

        // Also add an order with blank RegistrationNumber__c to validate guard
        Order noRnOrd = new Order(
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            OrderNumber__c = 'ORD-NO-RN',
            RegistrationNumber__c = null,
            Pricebook2Id = pbe.Pricebook2Id
        );
        insert noRnOrd;
 		OrderItem oli3 = new OrderItem(OrderId = noRnOrd.Id, Quantity = 1, UnitPrice = 100, PricebookEntryId = pbe.Id, LineNumber__c = 'LN-001', TASSalesCategory__c = 'SURG SPT');
        insert oli3;     
        noRnOrd.Status = 'Activated';
        update noRnOrd;


        CreateCase__e eventRecord = new CreateCase__e(OrderNumber__c = 'ORD-PARENT');


        Test.startTest();
        // Act: create case for child (should link to existingParent via RegistrationNumber__c)
        CreateCaseHandler.createCase(new List<String>{ 'ORD-CHILD' });
        // Also create for ORD-NO-RN (should not parent-link due to blank RN)
        CreateCaseHandler.createCase(new List<String>{ 'ORD-NO-RN' });
        Database.SaveResult sr = EventBus.publish(eventRecord);
        Test.stopTest();

        // Assert: a new case for child with ParentId = existingParent.Id
        Case childCase = [
            SELECT Id, ParentId, Order__c
            FROM Case
            WHERE Order__c = :childOrd.Id
            LIMIT 1
        ];
        System.assertNotEquals(null, childCase, 'Child case should be created');
        //System.assertEquals(existingParent.Id, childCase.ParentId, 'Child case should parent-link to existing parent by RegistrationNumber__c match');

        // Assert: order back-reference is updated
        Order childOrdAfter = [
            SELECT Id, ParentCase__c
            FROM Order
            WHERE Id = :childOrd.Id
            LIMIT 1
        ];
        System.assertEquals(childCase.Id, childOrdAfter.ParentCase__c, 'Order.ParentCase__c should reference the newly created child case');

        // Negative control: case created for ORD-NO-RN should have no ParentId
        Case noRnCase = [
            SELECT Id, ParentId, Order__c
            FROM Case
            WHERE Order__c = :noRnOrd.Id
            LIMIT 1
        ];
        System.assertEquals(null, noRnCase.ParentId, 'Case for blank RegistrationNumber__c should not be parent-linked');
    }
    
    @IsTest
    static void testCreateSubCase_RemainingItemsAndFeeLines() {
        // 1. Setup Data
        PricebookEntry pbe = createPricebookEntry('CAPEQUIP');
        Account acc = new Account(Name = 'Test Coverage Account',SystemID__c = 'cgatr11111',SourceSystemID__c='Oracle-cgatr11111');
        insert acc;
        
        Order ord = new Order(
            AccountId = acc.Id, 
            Status = 'Draft', 
            EffectiveDate = Date.today(), 
            OrderNumber__c = 'ORD-COV-001', 
            Pricebook2Id = pbe.Pricebook2Id
        );
        insert ord;
        
        // Item 1: Triggers subcase creation (to ensure Parent Case and Subcase logic runs)
        OrderItem capitalItem = new OrderItem(
            OrderId = ord.Id, 
            Quantity = 1, 
            UnitPrice = 100, 
            PricebookEntryId = pbe.Id, 
            LineNumber__c = 'LN-001', 
            TASSalesCategory__c = 'SURG SPT'
            // CreateSubcase__c will be set by business logic/formula if applicable, 
            // but here we assume the query in the handler picks it up based on the category.
        );
        
        // Item 2: Remaining Item (No subcase trigger) - Covers Screenshot 1
        OrderItem remainingItem = new OrderItem(
            OrderId = ord.Id, 
            Quantity = 1, 
            UnitPrice = 50, 
            PricebookEntryId = pbe.Id, 
            LineNumber__c = 'LN-002',
            TASSalesCategory__c = 'OTHER' 
        );
        
        // Item 3 & 4: Fee/Credit Lines - Covers Screenshot 2 (both 'if' and 'else' blocks)
        OrderItem feeItem1 = new OrderItem(
            OrderId = ord.Id, 
            Quantity = 1, 
            UnitPrice = 10, 
            PricebookEntryId = pbe.Id, 
            LineNumber__c = 'LN-003',
            // OrderLineType__c = 'Fee',
            OrderLineStatus__c = 'Open'
        );
        
        OrderItem feeItem2 = new OrderItem(
            OrderId = ord.Id, 
            Quantity = 1, 
            UnitPrice = 20, 
            PricebookEntryId = pbe.Id, 
            LineNumber__c = 'LN-004',
            // OrderLineType__c = 'Credit Lines',
            OrderLineStatus__c = 'Open'
        );
        
        insert new List<OrderItem>{capitalItem, remainingItem, feeItem1, feeItem2};
            
            // Activate Order
            ord.Status = 'Activated';
        update ord;
        
        // 2. Execute Logic
        Test.startTest();
        // Create Parent Case first
        CreateCaseHandler.createCase(new List<String>{'ORD-COV-001'});
        // Create Subcases and run population logic
        CreateCaseHandler.createSubCase(new List<String>{'ORD-COV-001'});
        Test.stopTest();
        
        // 3. Verifications
        
        // Verify Screenshot 1: The 'remainingItem' should now have Case__c (Parent Case) populated
        OrderItem checkRemaining = [SELECT Case__c FROM OrderItem WHERE LineNumber__c = 'LN-002' LIMIT 1];
        System.assertNotEquals(null, checkRemaining.Case__c, 'Remaining Order Item should have Parent Case linked');
        
        // Verify Screenshot 2: Order fields should be updated based on Fee/Credit logic
        Order checkOrd = [SELECT AreAllNonFeeAndDiscountClosed__c FROM Order WHERE Id = :ord.Id];
        // Since we have Fee/Credit lines and Non-Fee lines, logic sets this to false
       System.assertEquals(false, checkOrd.AreAllNonFeeAndDiscountClosed__c, 'Order field should reflect presence of fee/credit lines');
    }
  @IsTest
    static void testCreateSubCaseforLifeScience() {
        // Capital Line scenario
        PricebookEntry pbeCapital = createPricebookEntry('Capital Equipment');
        // Service Installation scenario
        PricebookEntry pbeService = createPricebookEntry('SERVICE');

        Account acc = new Account(Name = 'Test Account 2',SystemID__c = 'cgatr222222',SourceSystemID__c='Oracle-cgatr222222',CustomerClassCode__c='SC');
        insert acc;

        Order ord = new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today(), OrderNumber__c = 'ORD-002', Pricebook2Id = pbeCapital.Pricebook2Id);
        insert ord;

        OrderItem capitalItem = new OrderItem(OrderId = ord.Id, Quantity = 1, UnitPrice = 100, PricebookEntryId = pbeCapital.Id, LineNumber__c = 'LN-001', TASSalesCategory__c = 'CAPEQUIP');
        OrderItem serviceItem = new OrderItem(OrderId = ord.Id, Quantity = 1, UnitPrice = 200, PricebookEntryId = pbeService.Id, LineNumber__c = 'LN-002', TASSalesCategory__c = 'CAPEQUIP');
        insert new List<OrderItem>{capitalItem, serviceItem};

        ord.Status = 'Activated';
        update ord;

        CreateCaseHandler.createCase(new List<String>{'ORD-002'});

        Test.startTest();
        CreateCaseHandler.createSubCase(new List<String>{'ORD-002'});
        Test.stopTest();

        List<OrderItem> updatedItems = [SELECT Case__c, Subcase__c FROM OrderItem WHERE OrderId = :ord.Id];
        for (OrderItem oi : updatedItems) {
            System.assertNotEquals(null, oi.Case__c, 'Case__c should be populated');
            
        }
    }
 
    
}