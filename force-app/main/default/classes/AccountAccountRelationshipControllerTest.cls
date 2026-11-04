/**
 * @author Divya Sree
 * @date 2026/07/20
 *
 * @group AccountAccountRelationship
 *
 * @description
 * Unit tests for AccountAccountRelationshipController. Related story: GC-3126.
 */
@IsTest
private class AccountAccountRelationshipControllerTest {

    @TestSetup
    static void makeData() {
        Account customerAccount = new Account(
            Name = 'Test Customer',
            Type = 'Customer',
            SourceSystemID__c = 'TEST-CUST-001'
        );
        Account addressAccount = new Account(
            Name = 'Test Address',
            Type = 'Address',
            SourceSystemID__c = 'TEST-ADDR-001'
        );
        Account idnAccount = new Account(
            Name = 'Test IDN',
            Type = 'IDN',
            SourceSystemID__c = 'TEST-IDN-001'
        );
        Account gpoAccount = new Account(
            Name = 'Test GPO',
            Type = 'GPO',
            SourceSystemID__c = 'TEST-GPO-001'
        );
        insert new List<Account>{ customerAccount, addressAccount, idnAccount, gpoAccount };

        insert new List<AccountAccountRelationship__c>{
            new AccountAccountRelationship__c(
                ChildAccount__c = customerAccount.Id,
                ParentAccount__c = idnAccount.Id,
                RelationshipType__c = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_IS_IDN_MEMBER_OF,
                InverseRelationshipType__c = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_IDN_MEMBER
            ),
            new AccountAccountRelationship__c(
                ChildAccount__c = addressAccount.Id,
                ParentAccount__c = gpoAccount.Id,
                RelationshipType__c = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_IS_GPO_MEMBER_OF,
                InverseRelationshipType__c = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_GPO_MEMBER
            )
        };
    }

    /**
     * @description Customer Accounts return Child-side relationships.
     */
    @IsTest
    static void testGetRelationshipsCustomerAccountReturnsParentSideRecords() {

        /********************************************
        * SETUP
        ********************************************/
        Account customerAccount = [SELECT Id FROM Account WHERE Type = 'Customer' LIMIT 1];

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(1, [
            SELECT Count()
            FROM AccountAccountRelationship__c
            WHERE ChildAccount__c = :customerAccount.Id
        ]);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        List<AccountAccountRelationship__c> resultList =
            AccountAccountRelationshipController.getRelationships(customerAccount.Id);
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, resultList.size(), 'Expected one relationship for the Customer Account.');
        System.assertEquals(customerAccount.Id, resultList[0].ChildAccount__c);
    }

    /**
     * @description Address Accounts also return Child-side relationships.
     */
    @IsTest
    static void testGetRelationshipsAddressAccountReturnsChildSideRecords() {

        /********************************************
        * SETUP
        ********************************************/
        Account addressAccount = [SELECT Id FROM Account WHERE Type = 'Address' LIMIT 1];

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(1, [
            SELECT Count()
            FROM AccountAccountRelationship__c
            WHERE ChildAccount__c = :addressAccount.Id
        ]);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        List<AccountAccountRelationship__c> resultList =
            AccountAccountRelationshipController.getRelationships(addressAccount.Id);
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, resultList.size(), 'Expected one relationship for the Address Account.');
        System.assertEquals(addressAccount.Id, resultList[0].ChildAccount__c);
    }

    /**
     * @description IDN Accounts return Parent-side records with Has IDN Member.
     */
    @IsTest
    static void testGetRelationshipsIdnAccountReturnsParentSideRecords() {

        /********************************************
        * SETUP
        ********************************************/
        Account idnAccount = [SELECT Id FROM Account WHERE Type = 'IDN' LIMIT 1];

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(1, [
            SELECT Count()
            FROM AccountAccountRelationship__c
            WHERE ParentAccount__c = :idnAccount.Id
            AND InverseRelationshipType__c = :AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_IDN_MEMBER
        ]);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        List<AccountAccountRelationship__c> resultList =
            AccountAccountRelationshipController.getRelationships(idnAccount.Id);
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, resultList.size(), 'Expected one relationship for the IDN Account.');
        System.assertEquals(idnAccount.Id, resultList[0].ParentAccount__c);
        System.assertEquals(
            AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_IDN_MEMBER,
            resultList[0].InverseRelationshipType__c
        );
    }

    /**
     * @description GPO Accounts return Parent-side records with Has GPO Member.
     */
    @IsTest
    static void testGetRelationshipsGpoAccountReturnsParentSideRecords() {

        /********************************************
        * SETUP
        ********************************************/
        Account gpoAccount = [SELECT Id FROM Account WHERE Type = 'GPO' LIMIT 1];

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(1, [
            SELECT Count()
            FROM AccountAccountRelationship__c
            WHERE ParentAccount__c = :gpoAccount.Id
            AND InverseRelationshipType__c = :AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_GPO_MEMBER
        ]);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        List<AccountAccountRelationship__c> resultList =
            AccountAccountRelationshipController.getRelationships(gpoAccount.Id);
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, resultList.size(), 'Expected one relationship for the GPO Account.');
        System.assertEquals(gpoAccount.Id, resultList[0].ParentAccount__c);
        System.assertEquals(
            AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_GPO_MEMBER,
            resultList[0].InverseRelationshipType__c
        );
    }

    /**
     * @description Unrelated Account types return an empty list.
     */
    @IsTest
    static void testGetRelationshipsUnrelatedAccountTypeReturnsEmptyList() {

        /********************************************
        * SETUP
        ********************************************/
        Account prospectAccount = new Account(
            Name = 'Test Prospect',
            Type = 'Prospect',
            SourceSystemID__c = 'TEST-PROSPECT-001'
        );
        insert prospectAccount;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, [
            SELECT Count()
            FROM AccountAccountRelationship__c
            WHERE ChildAccount__c = :prospectAccount.Id
            OR ParentAccount__c = :prospectAccount.Id
        ]);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        List<AccountAccountRelationship__c> resultList =
            AccountAccountRelationshipController.getRelationships(prospectAccount.Id);
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(0, resultList.size(), 'Expected no relationships for an unrelated Account type.');
    }

    /**
     * @description IDN views exclude Parent-side rows that are not Has IDN Member.
     */
    @IsTest
    static void testGetRelationshipsIdnAccountExcludesNonIdnInverseTypes() {

        /********************************************
        * SETUP
        ********************************************/
        Account idnAccount = [SELECT Id FROM Account WHERE Type = 'IDN' LIMIT 1];
        Account gpoAccount = [SELECT Id FROM Account WHERE Type = 'GPO' LIMIT 1];

        insert new AccountAccountRelationship__c(
            ChildAccount__c = gpoAccount.Id,
            ParentAccount__c = idnAccount.Id,
            RelationshipType__c = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_IS_IDN_MEMBER_OF,
            InverseRelationshipType__c = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_GPO_MEMBER
        );

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(2, [
            SELECT Count()
            FROM AccountAccountRelationship__c
            WHERE ParentAccount__c = :idnAccount.Id
        ]);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        List<AccountAccountRelationship__c> resultList =
            AccountAccountRelationshipController.getRelationships(idnAccount.Id);
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            1,
            resultList.size(),
            'Expected only Has IDN Member Parent-side relationships for an IDN Account.'
        );
        System.assertEquals(
            AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_IDN_MEMBER,
            resultList[0].InverseRelationshipType__c
        );
    }

    /**
     * @description Service errors are wrapped as AuraHandledException.
     */
    @IsTest
    static void testGetRelationshipsThrowsAuraHandledExceptionOnServiceError() {

        /********************************************
        * SETUP
        ********************************************/
        Account customerAccount = [SELECT Id FROM Account WHERE Type = 'Customer' LIMIT 1];
        AccountAccountRelationshipService.forceExceptionForTest = true;
        Boolean auraHandledExceptionThrown = false;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(true, AccountAccountRelationshipService.forceExceptionForTest);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        try {
            AccountAccountRelationshipController.getRelationships(customerAccount.Id);
        } catch (AuraHandledException ex) {
            auraHandledExceptionThrown = true;
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            true,
            auraHandledExceptionThrown,
            'Expected AuraHandledException to be thrown when the Service layer errors.'
        );
    }

    /**
     * @description getAccountType returns the Account Type used by the LWC.
     */
    @IsTest
    static void testGetAccountTypeReturnsCorrectType() {

        /********************************************
        * SETUP
        ********************************************/
        Account customerAccount = [SELECT Id FROM Account WHERE Type = 'Customer' LIMIT 1];

        /********************************************
        * GIVEN
        ********************************************/
        System.assertNotEquals(null, customerAccount.Id);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        String resultType = AccountAccountRelationshipController.getAccountType(customerAccount.Id);
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals('Customer', resultType);
    }

    /**
     * @description getAccountType wraps unexpected errors as AuraHandledException.
     */
    @IsTest
    static void testGetAccountTypeThrowsAuraHandledExceptionOnForcedError() {

        /********************************************
        * SETUP
        ********************************************/
        Account customerAccount = [SELECT Id FROM Account WHERE Type = 'Customer' LIMIT 1];
        AccountAccountRelationshipController.forceExceptionForTest = true;
        Boolean auraHandledExceptionThrown = false;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(true, AccountAccountRelationshipController.forceExceptionForTest);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        try {
            AccountAccountRelationshipController.getAccountType(customerAccount.Id);
        } catch (AuraHandledException ex) {
            auraHandledExceptionThrown = true;
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            true,
            auraHandledExceptionThrown,
            'Expected AuraHandledException to be thrown when getAccountType errors.'
        );
    }

    /**
     * @description isSystemAdministrator matches the running user's Profile.
     */
    @IsTest
    static void testIsSystemAdministratorReturnsProfileMatch() {

        /********************************************
        * SETUP
        ********************************************/
        Boolean expectedIsSystemAdministrator = [
            SELECT Profile.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ].Profile.Name == 'System Administrator';

        /********************************************
        * GIVEN
        ********************************************/
        System.assertNotEquals(null, UserInfo.getUserId());

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        Boolean resultIsSystemAdministrator = AccountAccountRelationshipController.isSystemAdministrator();
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            expectedIsSystemAdministrator,
            resultIsSystemAdministrator,
            'Expected isSystemAdministrator to match the running user Profile.'
        );
    }

    /**
     * @description isSystemAdministrator wraps unexpected errors as AuraHandledException.
     */
    @IsTest
    static void testIsSystemAdministratorThrowsAuraHandledExceptionOnForcedError() {

        /********************************************
        * SETUP
        ********************************************/
        AccountAccountRelationshipController.forceExceptionForTest = true;
        Boolean auraHandledExceptionThrown = false;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(true, AccountAccountRelationshipController.forceExceptionForTest);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        try {
            AccountAccountRelationshipController.isSystemAdministrator();
        } catch (AuraHandledException ex) {
            auraHandledExceptionThrown = true;
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            true,
            auraHandledExceptionThrown,
            'Expected AuraHandledException to be thrown when isSystemAdministrator errors.'
        );
    }
}