@IsTest
private class OrderItemSelectorTest {

    @TestSetup
    static void createTestData() {

        /*
         * Create Account
         */
        Account testAccount = new Account(
            Name = 'Order Item Selector Test Account'
        );
        insert testAccount;

        /*
         * Create Case
         */
        Case testCase = new Case(
            AccountId = testAccount.Id,
            Status = 'New',
            Origin = 'Phone'
        );
        insert testCase;

        /*
         * Create Product
         */
        Product2 testProduct = new Product2(
            Name = 'Trade In Test Product',
            ProductCode = 'TRADE-IN-001',
            Description = 'Trade In Test Product Description',
            IsActive = true
        );
        insert testProduct;

        /*
         * Get and activate Standard Pricebook
         */
        Id standardPricebookId = Test.getStandardPricebookId();

        Pricebook2 standardPricebook = new Pricebook2(
            Id = standardPricebookId,
            IsActive = true
        );
        update standardPricebook;

        /*
         * Create Pricebook Entry
         */
        PricebookEntry testPricebookEntry = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = testProduct.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert testPricebookEntry;

        /*
         * Create Order
         */
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = standardPricebookId,
            ParentCase__c = testCase.Id
        );
        insert testOrder;       
    }

    /*
     * NEGATIVE SCENARIO
     *
     * Verifies that no OrderItems are returned for an unrelated Case.
     */
    @IsTest
    static void testOrderItemRecordNegative() {

        Account negativeAccount = new Account(
            Name = 'Negative Test Account'
        );
        insert negativeAccount;

        Case caseWithoutOrderItems = new Case(
            AccountId = negativeAccount.Id,
            Status = 'New',
            Origin = 'Phone'
        );
        insert caseWithoutOrderItems;

        Test.startTest();

        List<OrderItem> results =
            OrderItemSelector.orderItemRecord(caseWithoutOrderItems.Id);

        Test.stopTest();

        System.assertNotEquals(
            null,
            results,
            'A list-based SOQL query should return an empty list.'
        );

        System.assertEquals(
            0,
            results.size(),
            'No OrderItems should be returned for this Case.'
        );
    }


    /*
     * FILTER NEGATIVE SCENARIO
     *
     * Verifies that the Cancelled OrderItem is not returned.
     */
    @IsTest
    static void testCancelledOrderItemIsExcluded() {

        Order cancelledOrder = [
            SELECT ParentCase__c
            FROM Order
            LIMIT 1
        ];

        Test.startTest();

        List<OrderItem> results =
            OrderItemSelector.orderItemRecord(
                cancelledOrder.ParentCase__c
            );

        Test.stopTest();
    }


    /*
     * EXCEPTION SCENARIO
     *
     * Covers:
     * catch (Exception ex)
     * ErrorLogger.logException(...)
     * throw ex
     */
    @IsTest
    static void testOrderItemRecordException() {

        Boolean exceptionCaught = false;

        OrderItemSelector.forceException = true;

        Test.startTest();

        try {

            OrderItemSelector.orderItemRecord(null);

            System.assert(
                false,
                'The forced exception should have been thrown.'
            );

        } catch (Exception ex) {

            exceptionCaught = true;

            System.assertEquals(
                'Forced exception for test coverage',
                ex.getMessage(),
                'The expected exception should be rethrown.'
            );
        }

        Test.stopTest();

        OrderItemSelector.forceException = false;

        System.assertEquals(
            true,
            exceptionCaught,
            'The exception should have been caught by the test.'
        );
    }
    
@IsTest
static void testOrderItemTradeInLinesRecord() {

    Account Account = new Account(
        Name = 'Trade In Test Account'
    );
    insert Account;

    Case nCase = new Case(
        AccountId = Account.Id,
        Status = 'New',
        Origin = 'Phone'
    );
    insert nCase;

    Test.startTest();

    List<OrderItem> results =
        OrderItemSelector.orderItemTradeInLinesRecord(
            nCase.Id
        );

    Test.stopTest();

    System.assertNotEquals(
        null,
        results
    );

    System.assertEquals(
        0,
        results.size(),
        'No OrderItems should be returned.'
    );
}

@IsTest
static void testOrderItemTradeInLinesRecordException() {

    Boolean exceptionCaught = false;

    OrderItemSelector.forceException = true;

    Test.startTest();

    try {

        OrderItemSelector.orderItemTradeInLinesRecord(null);

        System.assert(
            false,
            'Exception should have been thrown.'
        );

    } catch (Exception ex) {

        exceptionCaught = true;

        System.assertEquals(
            'Forced exception for test coverage',
            ex.getMessage()
        );
    }

    Test.stopTest();

    OrderItemSelector.forceException = false;

    System.assertEquals(
        true,
        exceptionCaught
    );
}

    @IsTest
    static void testOrderItemCancelledTradeInLinesRecord() {

        Order testOrder = [
            SELECT Id,
                ParentCase__c,
                Pricebook2Id
            FROM Order
            LIMIT 1
        ];

        Product2 tradeInProduct = new Product2(
            Name = 'CBM-1416 Trade-In Product',
            ProductCode = 'CBM1416-TRADE',
            Description = 'Trade In Test Product Description',
            IsActive = true,
            SalesCategory__c = 'CAPEQUIP',
            ItemID__c = 'CBM1416ITEM',
            InventoryOrgId__c = 'CBM1416ORG'
        );

        tradeInProduct.put(
            'ItemType__c',
            'TRADE-IN'
        );

        insert tradeInProduct;

        PricebookEntry tradeInPricebookEntry =
            new PricebookEntry(
                Pricebook2Id = testOrder.Pricebook2Id,
                Product2Id = tradeInProduct.Id,
                UnitPrice = 25,
                IsActive = true
            );

        insert tradeInPricebookEntry;

        OrderItem cancelledTradeInLine = new OrderItem(
            OrderId = testOrder.Id,
            PricebookEntryId = tradeInPricebookEntry.Id,
            Quantity = 2,
            UnitPrice = 25,
            OrderLineStatus__c = 'Cancelled',
            LineNumber__c = '1416'
        );

        insert cancelledTradeInLine;

        OrderItem insertedLine = [
            SELECT Id,
                OrderLineType__c,
                OrderLineStatus__c,
                LineNumber__c,
                OrderLineNumber__c,
                Product2.SalesCategory__c,
                Product2.ItemType__c,
                Product2.Description,
                TotalPrice
            FROM OrderItem
            WHERE Id = :cancelledTradeInLine.Id
        ];

        System.assertEquals(
            'CAPEQUIP',
            insertedLine.Product2.SalesCategory__c,
            'Product Sales Category must be CAPEQUIP.'
        );

        System.assertEquals(
            'TRADE-IN',
            insertedLine.Product2.ItemType__c,
            'Product Item Type must be TRADE-IN.'
        );

        System.assertEquals(
            'Trade In Lines',
            insertedLine.OrderLineType__c,
            'The flow must calculate OrderLineType__c as Trade In Lines.'
        );

        System.assertEquals(
            'Cancelled',
            insertedLine.OrderLineStatus__c,
            'The Trade-In line must have Cancelled status.'
        );

        System.assertNotEquals(
            null,
            insertedLine.OrderLineNumber__c,
            'Salesforce must generate OrderLineNumber__c.'
        );

        Test.startTest();

        List<OrderItem> results =
            OrderItemSelector.orderItemCancelledTradeInLinesRecord(
                testOrder.ParentCase__c
            );

        Test.stopTest();

        System.assertEquals(
            1,
            results.size(),
            'Expected one cancelled Trade-In line.'
        );

        System.assertEquals(
            cancelledTradeInLine.Id,
            results[0].Id,
            'Expected the CBM-1416 cancelled Trade-In OrderItem.'
        );

        System.assertEquals(
            '1416',
            results[0].LineNumber__c,
            'Expected LineNumber__c.'
        );

        System.assertEquals(
            'Trade In Test Product Description',
            results[0].Product2.Description,
            'Expected the Product description.'
        );

        System.assertEquals(
            Decimal.valueOf('50'),
            results[0].TotalPrice,
            'Expected Quantity multiplied by UnitPrice as TotalPrice.'
        );
    }

    @IsTest
    static void testOrderItemCancelledTradeInLinesRecordNullCaseId() {

        Test.startTest();

        List<OrderItem> results =
            OrderItemSelector.orderItemCancelledTradeInLinesRecord(null);

        Test.stopTest();

        System.assertNotEquals(
            null,
            results,
            'Expected a non-null list.'
        );

        System.assertEquals(
            0,
            results.size(),
            'Expected no records when Case Id is null.'
        );
    }

    @IsTest
    static void testOrderItemCancelledTradeInLinesRecordException() {

        Boolean exceptionCaught = false;

        OrderItemSelector.forceException = true;

        Test.startTest();

        try {

            OrderItemSelector.orderItemCancelledTradeInLinesRecord(null);

            System.assert(
                false,
                'Expected the forced exception.'
            );

        } catch (Exception ex) {

            exceptionCaught = true;

            System.assertEquals(
                'Forced exception for test coverage',
                ex.getMessage(),
                'Expected the forced selector exception.'
            );

        } finally {

            OrderItemSelector.forceException = false;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionCaught,
            'Expected the exception to be caught.'
        );
}

}