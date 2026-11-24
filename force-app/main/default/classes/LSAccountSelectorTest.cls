/**
 * @description GCL-79 - Tests for the Life Sciences methods added to AccountSelector.
 *              Healthcare AccountSelector methods are not exercised here.
 */
@IsTest
private class LSAccountSelectorTest {

    private static final Set<String> LIFE_SCIENCES_CLASS_CODES = new Set<String>{ 'SC' };
    private static final Integer ROW_LIMIT = 200;

    /**
     * @description Turns off only the IDN/GPO creation rule so the IDN child in these tests is saved.
     *              Without it the IDN insert is blocked for users without Manage_IDN_GPO, the insert
     *              result is not checked, and the child count comes out one short.
     */
    @TestSetup
    static void allowIdnTestAccounts() {
        insert new Automation_Setting_Validation_Rule__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Account_IDN_GPO_Create__c = true
        );
    }

    @IsTest
    static void lifeSciencesAccountMethodsReturnOnlyMatchingCustomers() {
        Account customer = insertAccount('LS Selector Customer', 'LS-SEL-C', 'Customer', 'SC', null, 'LS-SEL-ADDR-1');
        insertAccount('LS Selector Other Class', 'LS-SEL-X', 'Customer', 'HC', null, 'LS-SEL-ADDR-X');
        Account child = insertAccount('LS Selector Child', 'LS-SEL-CH', 'Address', 'SC', customer.Id, 'LS-SEL-ADDR-2');
        insertAccount('LS Selector IDN Child', 'LS-SEL-IDN', 'IDN', 'SC', customer.Id, null);

        Test.startTest();
        List<Account> byName = AccountSelector.selectLifeSciencesCustomersByName(
            '%LS Selector Customer%',
            LIFE_SCIENCES_CLASS_CODES,
            ROW_LIMIT
        );
        List<Account> customers = AccountSelector.selectLifeSciencesCustomers(LIFE_SCIENCES_CLASS_CODES, ROW_LIMIT);
        List<Account> byId = AccountSelector.selectLifeSciencesAccountsByIds(new Set<Id>{ customer.Id });
        List<Account> byAddress = AccountSelector.selectLifeSciencesAccountsByOracleAddress(
            new Set<String>{ 'LS-SEL-ADDR-1' },
            ROW_LIMIT
        );
        List<Account> children = AccountSelector.selectLifeSciencesChildAccounts(new Set<Id>{ customer.Id });
        Test.stopTest();

        System.assertEquals(1, byName.size());
        System.assertEquals(customer.Id, byName[0].Id);
        System.assert(containsId(customers, customer.Id));
        System.assertEquals(1, byId.size());
        System.assertEquals(customer.Id, byId[0].Id);
        System.assertEquals(1, byAddress.size());
        System.assertEquals(customer.Id, byAddress[0].Id);
        System.assertEquals(2, children.size());
        System.assert(containsId(children, child.Id));
    }

    @IsTest
    static void lifeSciencesAccountMethodsRejectEmptyCriteria() {
        Test.startTest();
        System.assertEquals(0, AccountSelector.selectLifeSciencesCustomersByName(null, LIFE_SCIENCES_CLASS_CODES, ROW_LIMIT).size());
        System.assertEquals(0, AccountSelector.selectLifeSciencesCustomersByName('%LS%', null, ROW_LIMIT).size());
        System.assertEquals(0, AccountSelector.selectLifeSciencesCustomersByName('%LS%', LIFE_SCIENCES_CLASS_CODES, 0).size());
        System.assertEquals(0, AccountSelector.selectLifeSciencesCustomers(null, ROW_LIMIT).size());
        System.assertEquals(0, AccountSelector.selectLifeSciencesCustomers(new Set<String>(), ROW_LIMIT).size());
        System.assertEquals(0, AccountSelector.selectLifeSciencesAccountsByIds(null).size());
        System.assertEquals(0, AccountSelector.selectLifeSciencesAccountsByIds(new Set<Id>()).size());
        System.assertEquals(0, AccountSelector.selectLifeSciencesAccountsByOracleAddress(null, ROW_LIMIT).size());
        System.assertEquals(0, AccountSelector.selectLifeSciencesAccountsByOracleAddress(new Set<String>(), ROW_LIMIT).size());
        System.assertEquals(0, AccountSelector.selectLifeSciencesChildAccounts(null).size());
        System.assertEquals(0, AccountSelector.selectLifeSciencesChildAccounts(new Set<Id>()).size());
        Test.stopTest();
    }

    @IsTest
    static void accountLookupMethodsCoverBillToReturnOrderAndOwner() {
        Account customer = insertAccount(
            'LS Selector Lookup Customer',
            'LS-SEL-LK',
            'Customer',
            'SC',
            null,
            'LS-SEL-ADDR-LK'
        );
        Account billTo = insertAccount(
            'LS Selector Bill To',
            'LS-SEL-BT',
            'Address',
            'SC',
            customer.Id,
            'LS-SEL-ADDR-BT'
        );
        billTo.BilltoAddressStatus__c = 'Primary';
        update billTo;

        Test.startTest();
        System.assertEquals(0, AccountSelector.selectById(null).size());
        System.assertEquals(1, AccountSelector.selectById(customer.Id).size());
        System.assertEquals(0, AccountSelector.selectBillToAddressAccountsByParentId(null).size());
        List<Account> billToRows = AccountSelector.selectBillToAddressAccountsByParentId(customer.Id);
        System.assertEquals(0, AccountSelector.selectForCreateReturnOrderById(null).size());
        List<Account> returnOrderRows = AccountSelector.selectForCreateReturnOrderById(customer.Id);
        Test.stopTest();

        System.assertEquals(1, billToRows.size());
        System.assertEquals(billTo.Id, billToRows[0].Id);
        System.assertEquals(1, returnOrderRows.size());
        System.assertEquals(customer.Id, returnOrderRows[0].Id);
    }

    private static Boolean containsId(List<Account> accounts, Id accountId) {
        for (Account accountRecord : accounts) {
            if (accountRecord.Id == accountId) {
                return true;
            }
        }
        return false;
    }

    private static Account insertAccount(
        String name,
        String accountNumber,
        String accountType,
        String classCode,
        Id parentId,
        String oracleAddressId
    ) {
        Account accountRecord = new Account(
            Name = name,
            AccountNumber = accountNumber,
            Type = accountType,
            CustomerClassCode__c = classCode,
            ParentId = parentId,
            OracleAddressId__c = oracleAddressId
        );
        Database.SaveResult result = Database.insert(accountRecord, allowDuplicates());
        System.assert(result.isSuccess(), 'Test data insert failed for ' + name + ': ' + result.getErrors());
        return accountRecord;
    }

    private static Database.DMLOptions allowDuplicates() {
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        return options;
    }
}