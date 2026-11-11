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
}