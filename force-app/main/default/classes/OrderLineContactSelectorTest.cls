/**
 * @author PSL
 * @date 27-10-2026
 * @description Test class for OrderLineContactSelectorTest that validates helper methods for email functionality
 */
@IsTest
private class OrderLineContactSelectorTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'Test Account'
        );
        insert acc;

        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft'
        );
        insert ord;
        Case caseRecord = new Case(
            Subject = 'Test Case',
            Status = 'New',
            Origin = 'Phone',
            Order__c = ord.Id
        );
        insert caseRecord;
    }

    @IsTest
    static void testGetOrderLineContact_NoContact() {

        Account acc = new Account(
            Name = 'Account Without Contact'
        );
        insert acc;

        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft'
        );
        insert ord;

        Case caseRecord = new Case(
            Subject = 'Case Without Order Line Contact',
            Status = 'New',
            Origin = 'Phone',
            Order__c = ord.Id
        );
        insert caseRecord;

        Test.startTest();

        List<OrderLineContact__c> result =
            OrderLineContactSelector.getOrderLineContact(caseRecord);

        Test.stopTest();

        System.assertEquals(
            null,
            result,
            'Method should return null when no Order Line Contacts exist.'
        );
    }
}