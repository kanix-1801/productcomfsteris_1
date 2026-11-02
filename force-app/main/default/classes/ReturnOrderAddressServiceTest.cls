/**
 * @description Tests for ReturnOrderAddressService.
 */
@IsTest
private class ReturnOrderAddressServiceTest {
    @IsTest
    static void testApplyBillToAddressToReturnOrderUsesAccountBillingAddress() {
        Account customerAccount = createCustomerAccount(
            'RO Customer',
            '100 Billing Street',
            'Cleveland',
            '44101',
            null
        );

        ReturnOrder returnOrder = new ReturnOrder(
            AccountId = customerAccount.Id,
            Status = 'Created'
        );

        Test.startTest();
        ReturnOrderAddressService.applyBillToAddressToReturnOrder(
            returnOrder,
            customerAccount.Id
        );
        Test.stopTest();

        System.assertEquals('100 Billing Street', returnOrder.ShipFromStreet);
        System.assertEquals('Cleveland', returnOrder.ShipFromCity);
        System.assertEquals('44101', returnOrder.ShipFromPostalCode);
    }

    @IsTest
    static void testApplyWorkOrderAddressesFromReturnOrder() {
        Account parentAccount = createCustomerAccount(
            'Parent Customer',
            '200 Parent Billing St',
            'Columbus',
            '43215',
            null
        );
        Account customerAccount = createCustomerAccount(
            'Child Customer',
            '300 Child Billing St',
            'Toledo',
            '43604',
            parentAccount.Id
        );

        ReturnOrder returnOrder = new ReturnOrder(
            AccountId = customerAccount.Id,
            Status = 'Created'
        );
        ReturnOrderAddressService.applyBillToAddressToReturnOrder(
            returnOrder,
            customerAccount.Id
        );

        WorkOrder workOrder = new WorkOrder(
            AccountId = customerAccount.Id,
            Status = 'New'
        );

        Test.startTest();
        ReturnOrderAddressService.applyWorkOrderAddressesFromReturnOrder(
            workOrder,
            returnOrder
        );
        Test.stopTest();

        System.assertEquals('300 Child Billing St', workOrder.Street);
        System.assertEquals('Toledo', workOrder.City);
        System.assertEquals('200 Parent Billing St', workOrder.BillToAddress__Street__s);
        System.assertEquals('Columbus', workOrder.BillToAddress__City__s);
    }

    private static Account createCustomerAccount(
        String name,
        String billingStreet,
        String billingCity,
        String billingPostalCode,
        Id parentAccountId
    ) {
        Account customerAccount = new Account(
            Name = name,
            Type = 'Customer',
            SourceSystemID__c = 'TEST-ADDR-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            BillingStreet = billingStreet,
            BillingCity = billingCity,
            BillingPostalCode = billingPostalCode,
            ParentId = parentAccountId
        );
        insert customerAccount;
        return customerAccount;
    }
}