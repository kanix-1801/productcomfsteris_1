/**
 * @description GC-3088 - Test coverage for AccountSelector.
 */
@IsTest
private class AccountSelectorTest {

    private static final String ORACLE_ADDR_1 = 'ORACLE-ADDR-1';
    private static final String ORACLE_ADDR_2 = 'ORACLE-ADDR-2';
    private static final String ORACLE_ADDR_3 = 'ORACLE-ADDR-3';
    private static final String ORACLE_ADDR_4 = 'ORACLE-ADDR-4';
    private static final String ORACLE_ADDR_SHARED = 'ORACLE-ADDR-SHARED';

    @TestSetup
    static void setup() {
        adb_Account parentBuilder = new adb_Account()
            .name('Parent Health System')
            .accountNumber('PARENT-1')
            .sourceSystemId('123456');
        parentBuilder.set(Account.Type, 'Customer');
        parentBuilder.set(Account.OracleAddressId__c, ORACLE_ADDR_1);

        adb_Account acmeTech = new adb_Account()
            .name('Acme Technology Hospital')
            .accountNumber('1001')
            .sourceSystemId('SRC-1');
        acmeTech.parent(parentBuilder); // Note: adb_Account.parent() returns the parent builder, not this - don't chain after it.
        acmeTech.set(Account.Type, 'Customer');
        acmeTech.set(Account.OracleAddressId__c, ORACLE_ADDR_2);
        acmeTech.set(Account.OwnerId, UserInfo.getUserId());

        adb_Account acmeNoSource = new adb_Account()
            .name('Acme No Source System')
            .accountNumber('1002')
            .sourceSystemId('297354');
        acmeNoSource.parent(parentBuilder);
        acmeNoSource.set(Account.Type, 'Customer');
        acmeNoSource.set(Account.OracleAddressId__c, ORACLE_ADDR_3);

        adb_Account acmeAddress = new adb_Account()
            .name('Acme Address Location')
            .accountNumber('1003')
            .sourceSystemId('SRC-2');
        acmeAddress.parent(parentBuilder);
        acmeAddress.set(Account.Type, 'Address');
        acmeAddress.set(Account.OracleAddressId__c, ORACLE_ADDR_4);

        adb_Account globalGpo = new adb_Account()
            .name('Global GPO Cooperative')
            .accountNumber('2001')
            .sourceSystemId('9873544');
        globalGpo.parent(parentBuilder);
        globalGpo.set(Account.Type, 'GPO');

        adb_Account regionalIdn = new adb_Account()
            .name('Regional IDN Network')
            .accountNumber('3001')
            .sourceSystemId('0273543');
        regionalIdn.set(Account.Type, 'IDN');

        adb_Account blankAddress = new adb_Account()
            .name('Blank Oracle Address Account')
            .accountNumber('4001')
            .sourceSystemId('4192964497');
        blankAddress.set(Account.Type, 'Customer');
        blankAddress.set(Account.OracleAddressId__c, '');

        adb_DomainBuilder.save();
    }

    private static Id parentId() {
        return [SELECT Id FROM Account WHERE AccountNumber = 'PARENT-1' LIMIT 1].Id;
    }

    // ---- selectByIds ---------------------------------------------------------------------

    @IsTest
    static void selectByIds_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, AccountSelector.selectByIds(null).size());
        Assert.areEqual(0, AccountSelector.selectByIds(new Set<Id>()).size());
    }

    @IsTest
    static void selectByIds_validIds_returnsMatchingAccounts() {
        Account acc = [SELECT Id FROM Account WHERE AccountNumber = '1001' LIMIT 1];

        Test.startTest();
        List<Account> results = AccountSelector.selectByIds(new Set<Id>{ acc.Id });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual(acc.Id, results[0].Id);
        Assert.areEqual('Acme Technology Hospital', results[0].Name);
        Assert.areEqual(ORACLE_ADDR_2, results[0].OracleAddressId__c);
    }

    // ---- selectByParentIds -----------------------------------------------------------------

    @IsTest
    static void selectByParentIds_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, AccountSelector.selectByParentIds(null).size());
        Assert.areEqual(0, AccountSelector.selectByParentIds(new Set<Id>()).size());
    }

    @IsTest
    static void selectByParentIds_validIds_returnsDirectChildrenOnly() {
        Id parentAccountId = parentId();

        Test.startTest();
        List<Account> results = AccountSelector.selectByParentIds(new Set<Id>{ parentAccountId });
        Test.stopTest();

        Set<Id> resultIds = new Set<Id>();
        for (Account a : results) {
            Assert.areEqual(parentAccountId, a.ParentId);
            resultIds.add(a.Id);
        }
        // 4 of the 6 test children reference the parent account.
        Assert.areEqual(4, results.size());
    }

    // ---- selectCustomerAccountsForTasByIds -------------------------------------------------

    @IsTest
    static void selectCustomerAccountsForTasByIds_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, AccountSelector.selectCustomerAccountsForTasByIds(null).size());
        Assert.areEqual(0, AccountSelector.selectCustomerAccountsForTasByIds(new Set<Id>()).size());
    }

    @IsTest
    static void selectCustomerAccountsForTasByIds_validIds_returnsAccountsWithTasFields() {
        Account acc = [SELECT Id FROM Account WHERE AccountNumber = '1001' LIMIT 1];

        Test.startTest();
        List<Account> results = AccountSelector.selectCustomerAccountsForTasByIds(new Set<Id>{ acc.Id });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual(ORACLE_ADDR_2, results[0].OracleAddressId__c);
        Assert.areEqual('SRC-1', results[0].SourceSystemID__c);
    }

    // ---- selectAccountsByOracleAddressId ---------------------------------------------------

    @IsTest
    static void selectAccountsByOracleAddressId_nullOrEmptySet_returnsEmptyMap() {
        Assert.isTrue(AccountSelector.selectAccountsByOracleAddressId(null).isEmpty());
        Assert.isTrue(AccountSelector.selectAccountsByOracleAddressId(new Set<String>()).isEmpty());
    }

    @IsTest
    static void selectAccountsByOracleAddressId_distinctIds_mapsEachToItsAccount() {
        Test.startTest();
        Map<String, Account> results = AccountSelector.selectAccountsByOracleAddressId(
            new Set<String>{ ORACLE_ADDR_1, ORACLE_ADDR_2 }
        );
        Test.stopTest();

        Assert.areEqual(2, results.size());
        Assert.areEqual('Parent Health System', results.get(ORACLE_ADDR_1).Name);
        Assert.areEqual('Acme Technology Hospital', results.get(ORACLE_ADDR_2).Name);
    }

    @IsTest
    static void selectAccountsByOracleAddressId_blankAddressId_isSkipped() {
        Test.startTest();
        Map<String, Account> results = AccountSelector.selectAccountsByOracleAddressId(new Set<String>{ '' });
        Test.stopTest();

        Assert.isFalse(results.containsKey(''));
        Assert.isTrue(results.isEmpty());
    }

    // ---- selectChildAccountsByParentIds -----------------------------------------------------

    @IsTest
    static void selectChildAccountsByParentIds_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, AccountSelector.selectChildAccountsByParentIds(null).size());
        Assert.areEqual(0, AccountSelector.selectChildAccountsByParentIds(new Set<Id>()).size());
    }

    @IsTest
    static void selectChildAccountsByParentIds_validIds_returnsChildren() {
        Id parentAccountId = parentId();

        Test.startTest();
        List<Account> results = AccountSelector.selectChildAccountsByParentIds(new Set<Id>{ parentAccountId });
        Test.stopTest();

        Assert.areEqual(4, results.size());
        for (Account a : results) {
            Assert.areEqual(parentAccountId, a.ParentId);
        }
    }

    // ---- selectOracleAddressIdByAccountIds --------------------------------------------------

    @IsTest
    static void selectOracleAddressIdByAccountIds_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, AccountSelector.selectOracleAddressIdByAccountIds(null).size());
        Assert.areEqual(0, AccountSelector.selectOracleAddressIdByAccountIds(new Set<Id>()).size());
    }

    @IsTest
    static void selectOracleAddressIdByAccountIds_excludesAccountsWithoutOracleAddressId() {
        Account withAddress = [SELECT Id FROM Account WHERE AccountNumber = '1001' LIMIT 1];
        Account withoutAddress = [SELECT Id FROM Account WHERE AccountNumber = '2001' LIMIT 1];

        Test.startTest();
        List<Account> results = AccountSelector.selectOracleAddressIdByAccountIds(
            new Set<Id>{ withAddress.Id, withoutAddress.Id }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual(withAddress.Id, results[0].Id);
        Assert.areEqual(ORACLE_ADDR_2, results[0].OracleAddressId__c);
    }

    // ---- selectBySearchCriteria -------------------------------------------------------------

    @IsTest
    static void selectBySearchCriteria_searchAndGpoType_doesNotRequireSourceSystemId() {
        Test.startTest();
        List<Account> results = AccountSelector.selectBySearchCriteria('Global', 'GPO');
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual('Global GPO Cooperative', results[0].Name);
    }

    @IsTest
    static void selectBySearchCriteria_searchAndIdnType_doesNotRequireSourceSystemId() {
        Test.startTest();
        List<Account> results = AccountSelector.selectBySearchCriteria('Regional', 'IDN');
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual('Regional IDN Network', results[0].Name);
    }

    @IsTest
    static void selectBySearchCriteria_typeOnly_returnsAllAccountsOfThatType() {
        Test.startTest();
        List<Account> results = AccountSelector.selectBySearchCriteria(null, 'Customer');
        Test.stopTest();

        // All Customer-type accounts, regardless of SourceSystemID__c.
        Assert.areEqual(4, results.size());
        for (Account a : results) {
            Assert.areEqual('Customer', a.Type);
        }
    }

    // ---- selectAccountForSalesConnection ----------------------------------------------------

    @IsTest
    static void selectAccountForSalesConnection_nullId_returnsNull() {
        Assert.isNull(AccountSelector.selectAccountForSalesConnection(null));
    }

    @IsTest
    static void selectAccountForSalesConnection_validId_returnsAccountWithRecordType() {
        Account acc = [SELECT Id FROM Account WHERE AccountNumber = '1001' LIMIT 1];

        Test.startTest();
        Account result = AccountSelector.selectAccountForSalesConnection(acc.Id);
        Test.stopTest();

        Assert.isNotNull(result);
        Assert.areEqual(acc.Id, result.Id);
        Assert.areEqual(ORACLE_ADDR_2, result.OracleAddressId__c);
    }

    // ---- selectByOwnerIds ---------------------------------------------------------------------

    @IsTest
    static void selectByOwnerIds_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, AccountSelector.selectByOwnerIds(null).size());
        Assert.areEqual(0, AccountSelector.selectByOwnerIds(new Set<Id>()).size());
    }

    @IsTest
    static void selectByOwnerIds_validIds_returnsAccountsOwnedByThoseUsers() {
        Test.startTest();
        List<Account> results = AccountSelector.selectByOwnerIds(new Set<Id>{ UserInfo.getUserId() });
        Test.stopTest();

        Assert.isFalse(results.isEmpty());
        for (Account a : results) {
            Assert.areEqual(UserInfo.getUserId(), a.OwnerId);
        }
    }

    // ---- selectFacilityAccountsByParentId ---------------------------------------------------

    @IsTest
    static void selectFacilityAccountsByParentId_nullId_returnsEmptyList() {
        Assert.areEqual(0, AccountSelector.selectFacilityAccountsByParentId(null).size());
    }

    @IsTest
    static void selectFacilityAccountsByParentId_validId_excludesAccountsWithoutOracleAddressId() {
        Id parentAccountId = parentId();

        Test.startTest();
        List<Account> results = AccountSelector.selectFacilityAccountsByParentId(parentAccountId);
        Test.stopTest();

        // Of the 4 children, "Global GPO Cooperative" has no OracleAddressId__c and is excluded.
        Assert.areEqual(3, results.size());
        for (Account a : results) {
            Assert.isNotNull(a.OracleAddressId__c);
            Assert.areEqual(parentAccountId, a.ParentId);
        }
    }

    // ---- selectFacilityAccountsByParentIds --------------------------------------------------

    @IsTest
    static void selectFacilityAccountsByParentIds_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, AccountSelector.selectFacilityAccountsByParentIds(null).size());
        Assert.areEqual(0, AccountSelector.selectFacilityAccountsByParentIds(new Set<Id>()).size());
    }

    @IsTest
    static void selectFacilityAccountsByParentIds_validIds_excludesAccountsWithoutOracleAddressId() {
        Id parentAccountId = parentId();

        Test.startTest();
        List<Account> results = AccountSelector.selectFacilityAccountsByParentIds(new Set<Id>{ parentAccountId });
        Test.stopTest();

        Assert.areEqual(3, results.size());
        for (Account a : results) {
            Assert.isNotNull(a.OracleAddressId__c);
        }
    }

    // ---- Inherited SoqlQueryBuilder usage ---------------------------------------------------

    @IsTest
    static void builderUsage_selectFieldWhereEqualsLimitTo_returnsMatchingAccount() {
        Test.startTest();
        List<Account> results = (List<Account>) new AccountSelector()
            .selectField('Id')
            .whereEquals('AccountNumber', '1001')
            .limitTo(2)
            .execute();
        Test.stopTest();

        Assert.areEqual(1, results.size());
    }

    // ---- Remaining SoqlQueryBuilder paths ---------------------------------------------------

    @IsTest
    static void selectBySearchCriteria_noFilters_returnsOrderedAccounts() {
        Test.startTest();
        List<Account> results = AccountSelector.selectBySearchCriteria(null, null);
        Test.stopTest();
        Assert.isFalse(results.isEmpty());
    }

    @IsTest
    static void selectBySearchCriteria_searchOnly_returnsNameOrNumberMatches() {
        Test.startTest();
        List<Account> results = AccountSelector.selectBySearchCriteria('Acme', null);
        Test.stopTest();
        Assert.isFalse(results.isEmpty());
    }

    @IsTest
    static void selectBySearchCriteria_searchAndCustomerType_returnsMatches() {
        Test.startTest();
        List<Account> results = AccountSelector.selectBySearchCriteria('Acme', 'Customer');
        Test.stopTest();
        Assert.isFalse(results.isEmpty());
        for (Account row : results) {
            Assert.areEqual('Customer', row.Type);
        }
    }

    @IsTest
    static void selectShipToAddressAccountsByParentId_null_returnsEmpty() {
        Assert.areEqual(0, AccountSelector.selectShipToAddressAccountsByParentId(null).size());
    }

    @IsTest
    static void selectShipToAddressAccountsByParentId_primaryAddress_returnsRow() {
        Id parentAccountId = parentId();
        adb_Account shipToBuilder = new adb_Account()
            .name('Ship To Primary Address')
            .accountNumber('SHIP-1')
            .sourceSystemId('SHIP-SRC-1');
        shipToBuilder.set(Account.ParentId, parentAccountId);
        shipToBuilder.set(Account.Type, 'Address');
        shipToBuilder.set(Account.ShiptoAddressStatus__c, 'Primary');
        Account shipTo = (Account) shipToBuilder.persist();

        Test.startTest();
        List<Account> results = AccountSelector.selectShipToAddressAccountsByParentId(parentAccountId);
        Test.stopTest();

        Boolean found = false;
        for (Account row : results) {
            if (row.Id == shipTo.Id) {
                found = true;
                break;
            }
        }
        Assert.isTrue(found);
    }

    @IsTest
    static void selectForOraclePricingByIds_nullOrEmpty_returnsEmptyMap() {
        Assert.isTrue(AccountSelector.selectForOraclePricingByIds(null).isEmpty());
        Assert.isTrue(AccountSelector.selectForOraclePricingByIds(new Set<Id>()).isEmpty());
    }

    @IsTest
    static void selectForOraclePricingByIds_validIds_returnsMap() {
        Account acc = [SELECT Id FROM Account WHERE AccountNumber = '1001' LIMIT 1];
        Test.startTest();
        Map<Id, Account> results = AccountSelector.selectForOraclePricingByIds(new Set<Id>{ acc.Id });
        Test.stopTest();
        Assert.areEqual(1, results.size());
        Assert.isTrue(results.containsKey(acc.Id));
    }

    @IsTest
    static void selectOracleAddressAccountsForPricing_null_returnsEmpty() {
        Assert.areEqual(0, AccountSelector.selectOracleAddressAccountsForPricing(null).size());
    }

    @IsTest
    static void selectOracleAddressAccountsForPricing_primaryAddress_returnsRow() {
        Id parentAccountId = parentId();
        adb_Account shipToBuilder = new adb_Account()
            .name('Oracle Pricing Ship To')
            .accountNumber('ORACLE-SHIP-1')
            .sourceSystemId('ORACLE-SHIP-SRC-1');
        shipToBuilder.set(Account.ParentId, parentAccountId);
        shipToBuilder.set(Account.Type, 'Address');
        shipToBuilder.set(Account.ShiptoAddressStatus__c, 'Primary');
        Account shipTo = (Account) shipToBuilder.persist();

        Test.startTest();
        List<Account> results = AccountSelector.selectOracleAddressAccountsForPricing(parentAccountId);
        Test.stopTest();

        Boolean found = false;
        for (Account row : results) {
            if (row.Id == shipTo.Id) {
                found = true;
                break;
            }
        }
        Assert.isTrue(found);
    }

    @IsTest
    static void selectInternalAccountsForReceiving_returnsTypeI() {
        adb_Account internalBuilder = new adb_Account()
            .name('Receiving Internal Cover')
            .accountNumber('RECV-INT-COV')
            .sourceSystemId('RECV-INT-COV-SRC');
        internalBuilder.set(Account.Type, 'I');
        Account internalAccount = (Account) internalBuilder.persist();

        Test.startTest();
        List<Account> results = AccountSelector.selectInternalAccountsForReceiving();
        Test.stopTest();

        Boolean found = false;
        for (Account row : results) {
            if (row.Id == internalAccount.Id) {
                found = true;
                break;
            }
        }
        Assert.isTrue(found);
    }

    @IsTest
    static void selectVendorAccountsForReceiving_returnsVendor() {
        adb_Account vendorBuilder = new adb_Account()
            .name('Receiving Vendor Cover')
            .accountNumber('RECV-VEN-COV')
            .sourceSystemId('RECV-VEN-COV-SRC');
        vendorBuilder.set(Account.Type, 'Vendor');
        Account vendorAccount = (Account) vendorBuilder.persist();

        Test.startTest();
        List<Account> results = AccountSelector.selectVendorAccountsForReceiving();
        Test.stopTest();

        Boolean found = false;
        for (Account row : results) {
            if (row.Id == vendorAccount.Id) {
                found = true;
                break;
            }
        }
        Assert.isTrue(found);
    }

    @IsTest
    static void selectBillingAddressByIds_nullOrEmpty_returnsEmpty() {
        Assert.areEqual(0, AccountSelector.selectBillingAddressByIds(null).size());
        Assert.areEqual(0, AccountSelector.selectBillingAddressByIds(new Set<Id>()).size());
    }

    @IsTest
    static void selectBillingAddressByIds_validIds_returnsRow() {
        Account acc = [SELECT Id FROM Account WHERE AccountNumber = '1001' LIMIT 1];
        Test.startTest();
        List<Account> results = AccountSelector.selectBillingAddressByIds(new Set<Id>{ acc.Id });
        Test.stopTest();
        Assert.areEqual(1, results.size());
    }

    @IsTest
    static void selectAccountNumberByIdForReceiving_nullAndValid() {
        Account acc = [SELECT Id, AccountNumber FROM Account WHERE AccountNumber = '1001' LIMIT 1];
        Assert.areEqual(0, AccountSelector.selectAccountNumberByIdForReceiving(null).size());
        Test.startTest();
        List<Account> results = AccountSelector.selectAccountNumberByIdForReceiving(acc.Id);
        Test.stopTest();
        Assert.areEqual(1, results.size());
        Assert.areEqual('1001', results[0].AccountNumber);
    }

    @IsTest
    static void selectPrimaryBillToByAccountNumber_blankAndPrimary() {
        Assert.areEqual(0, AccountSelector.selectPrimaryBillToByAccountNumber(null).size());
        Assert.areEqual(0, AccountSelector.selectPrimaryBillToByAccountNumber('').size());

        adb_Account billToBuilder = new adb_Account()
            .name('Primary Bill To Cover')
            .accountNumber('1001')
            .sourceSystemId('BILL-COV-SRC');
        billToBuilder.set(Account.Type, 'Address');
        billToBuilder.set(Account.BilltoAddressStatus__c, 'Primary');
        Account billTo = (Account) billToBuilder.persist();

        Test.startTest();
        List<Account> results = AccountSelector.selectPrimaryBillToByAccountNumber('1001');
        Test.stopTest();
        Assert.areEqual(1, results.size());
        Assert.areEqual(billTo.Id, results[0].Id);
    }

    @IsTest
    static void selectAddressAccountsByOracleAddressIds_nullOrEmpty_returnsEmpty() {
        Assert.areEqual(0, AccountSelector.selectAddressAccountsByOracleAddressIds(null).size());
        Assert.areEqual(
            0,
            AccountSelector.selectAddressAccountsByOracleAddressIds(new Set<String>()).size()
        );
    }

    @IsTest
    static void selectAddressAccountsByOracleAddressIds_validIds_returnsAddress() {
        Account addressAcc = [
            SELECT Id, OracleAddressId__c
            FROM Account
            WHERE AccountNumber = '1003'
            LIMIT 1
        ];
        Test.startTest();
        List<Account> results = AccountSelector.selectAddressAccountsByOracleAddressIds(
            new Set<String>{ addressAcc.OracleAddressId__c }
        );
        Test.stopTest();
        Assert.isFalse(results.isEmpty());
    }

    @IsTest
    static void testSelectByIdsNullOrEmptyReturnsEmpty_sprint93Coverage() {
        Assert.areEqual(0, AccountSelector.selectByIds(null).size());
        Assert.areEqual(0, AccountSelector.selectByIds(new Set<Id>()).size());
    }

}