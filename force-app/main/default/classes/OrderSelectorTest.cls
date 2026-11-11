@IsTest
private class OrderSelectorTest {

    @TestSetup
    static void setupData() {

        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;

        Case testCase = new Case(
            AccountId = testAccount.Id,
            Status = 'New',
            Origin = 'Phone'
        );
        insert testCase;

        Order testOrder = new Order(
            AccountId = testAccount.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            ParentCase__c = testCase.Id,
            FirstScheduledDateNonPreinstall__c = Date.today().addDays(5)
        );
        insert testOrder;
    }


    /*
     * POSITIVE SCENARIO
     */
    @IsTest
    static void testOrderRecordPositive() {

        Order testOrder = [
            SELECT Id,
                   ParentCase__c,
                   FirstScheduledDateNonPreinstall__c
            FROM Order
            LIMIT 1
        ];

        Test.startTest();

        List<Order> result =
            OrderSelector.orderRecord(testOrder.ParentCase__c);

        Test.stopTest();

        System.assertNotEquals(
            null,
            result
        );

        System.assertEquals(
            1,
            result.size()
        );

        System.assertEquals(
            testOrder.Id,
            result[0].Id
        );

        System.assertEquals(
            testOrder.FirstScheduledDateNonPreinstall__c,
            result[0].FirstScheduledDateNonPreinstall__c
        );
    }


    /*
     * NEGATIVE SCENARIO
     * No Order exists for Case.
     */
    @IsTest
    static void testOrderRecordNegative() {

        Account testAccount = new Account(
            Name = 'Negative Account'
        );
        insert testAccount;

        Case testCase = new Case(
            AccountId = testAccount.Id,
            Status = 'New',
            Origin = 'Phone'
        );
        insert testCase;

        Test.startTest();

        List<Order> result =
            OrderSelector.orderRecord(testCase.Id);

        Test.stopTest();

        System.assertEquals(
            null,
            result
        );
    }


    /*
     * EXCEPTION SCENARIO
     * Covers catch block.
     */
    @IsTest
    static void testOrderRecordException() {

        OrderSelector.throwTestException = true;

        Boolean exceptionCaught = false;

        Test.startTest();

        try {

            OrderSelector.orderRecord(null);

        } catch (Exception ex) {

            exceptionCaught = true;

            System.assertEquals(
                'Forced exception for test',
                ex.getMessage()
            );
        }

        Test.stopTest();

        OrderSelector.throwTestException = false;

        System.assertEquals(
            true,
            exceptionCaught,
            'Exception should be thrown and caught'
        );
    }
}