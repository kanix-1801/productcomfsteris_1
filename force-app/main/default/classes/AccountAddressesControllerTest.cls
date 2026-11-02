@IsTest
public class AccountAddressesControllerTest {

    @IsTest
    static void testGetAddressesSuccess() {
        Account accountRecord = new Account(
            Name = 'Test Account',
            SourceSystemID__c = 'Test123'
        );
        insert accountRecord;

        SObject mockAddress =Schema.getGlobalDescribe().get('Address').newSObject();

        mockAddress.put('Id', 'a00000000000001AAA');
        mockAddress.put('Street', '123 Main St');
        mockAddress.put('AddressType', 'Shipping');
        mockAddress.put('City', 'Chicago');
        mockAddress.put('State', 'IL');
        mockAddress.put('PostalCode', '60601');

        AccountAddressesSelector.testAddresses =
            new List<SObject>{ mockAddress };

        Test.startTest();
        List<AccountAddressesService.AccountAddressWrapper> resultList =
            AccountAddressesController.getAddresses(accountRecord.Id);
        Test.stopTest();

        System.assertEquals(1, resultList.size());
        System.assertEquals('123 Main St', resultList[0].street);
    }

    @IsTest
    static void testGetAddressesNullAccountId() {
        Test.startTest();
        List<AccountAddressesService.AccountAddressWrapper> resultList =
            AccountAddressesController.getAddresses(null);
        Test.stopTest();

        System.assertEquals(0, resultList.size());
    }

    @IsTest
    static void testGetAddressesException() {
        Account accountRecord = new Account(
            Name = 'Exception Test Account',
            SourceSystemID__c = 'Test456'
        );
        insert accountRecord;

        AccountAddressesService.throwExceptionForTest = true;

        Boolean wasExceptionThrown = false;

        Test.startTest();
        try {
            AccountAddressesController.getAddresses(accountRecord.Id);
        } catch (AuraHandledException exceptionRecord) {
            wasExceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, wasExceptionThrown);

        AccountAddressesService.throwExceptionForTest = false;
    }
    @IsTest
static void testSelectorNullAccountId() {
    AccountAddressesSelector.testAddresses = null;

    List<SObject> resultList =
        AccountAddressesSelector.selectByAccountId(null);

    System.assertEquals(0, resultList.size());
}

@IsTest
static void testSelectorMockData() {
SObject mockAddress =
    Schema.getGlobalDescribe().get('Address').newSObject();
    mockAddress.put('Id', 'a00000000000002AAA');

    AccountAddressesSelector.testAddresses =
        new List<SObject>{ mockAddress };

    List<SObject> resultList =
        AccountAddressesSelector.selectByAccountId(UserInfo.getUserId());

    System.assertEquals(1, resultList.size());
}
@IsTest
static void testSelectorRealQueryNoRecords() {
    Account accountRecord = new Account(
        Name = 'Selector Real Query Test Account',
        SourceSystemID__c = 'SelectorRealQuery12'
    );
    insert accountRecord;

    AccountAddressesSelector.testAddresses = null;

    Test.startTest();
    List<SObject> resultList =
        AccountAddressesSelector.selectByAccountId(accountRecord.Id);
    Test.stopTest();

    System.assertEquals(0, resultList.size());
}
}