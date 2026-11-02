/**
 * Author: Akash Dahinde
 * Story: GC-2868
 *@description - Test class- Retrieves Contacts from child Accounts related to the current
 */
@IsTest
private class ChildAccountContactControllerTest {
    private static final String IDN_NAME = 'AC6 Test IDN';
    private static final String GPO_NAME = 'AC6 Test GPO';
    private static final String CUSTOMER_NAME = 'AC6 Test Customer';
    private static final String PARENT_CHILD_NAME = 'AC6 ParentId Child';
    private static final String AAR_CHILD_NAME = 'AC6 AAR Child';
    private static final String UNRELATED_NAME = 'AC6 Unrelated Customer';

    @TestSetup
    static void createData() {
        Id customerRtId = getCustomerRecordTypeId();

        Account idnAccount = createAccount(IDN_NAME, 'IDN', null, null, 'IDN101');
        Account gpoAccount = createAccount(GPO_NAME, 'GPO', null, null, 'GPO101');
        Account customerAccount = createAccount(CUSTOMER_NAME, 'Customer', customerRtId, null, 'CUS101');
        insert new List<Account>{ idnAccount, gpoAccount, customerAccount };

        Account parentChild = createAccount(PARENT_CHILD_NAME, 'Customer', customerRtId, idnAccount.Id, 'CHD101');
        Account aarChild = createAccount(AAR_CHILD_NAME, 'Customer', customerRtId, null, 'CHD102');
        Account gpoChild = createAccount('AC6 GPO Child', 'Customer', customerRtId, gpoAccount.Id, 'CHD103');
        Account customerChild = createAccount('AC6 Customer Child', 'Customer', customerRtId, customerAccount.Id, 'CHD104');
        Account unrelatedAccount = createAccount(UNRELATED_NAME, 'Customer', customerRtId, null, 'UNR101');
        insert new List<Account>{ parentChild, aarChild, gpoChild, customerChild, unrelatedAccount };

        String relationshipType = getValidRelationshipType();

        if (relationshipType != null) {
            insert new AccountAccountRelationship__c(
                ParentAccount__c = idnAccount.Id,
                ChildAccount__c = aarChild.Id,
                RelationshipType__c = relationshipType
            );
        }

        insert new List<Contact>{
            new Contact(
                FirstName = 'ParentId',
                LastName = 'Contact',
                AccountId = parentChild.Id,
                Email = 'parentid@example.com',
                Phone = '555-1001',
                MobilePhone = '555-2001'
            ),
            new Contact(
                FirstName = 'AAR',
                LastName = 'Contact',
                AccountId = aarChild.Id,
                Email = 'aar@example.com',
                Phone = '555-1002',
                MobilePhone = '555-2002'
            ),
            new Contact(
                FirstName = 'GPO',
                LastName = 'Contact',
                AccountId = gpoChild.Id,
                Email = 'gpo@example.com',
                Phone = '555-1003',
                MobilePhone = '555-2003'
            ),
            new Contact(
                FirstName = 'Customer',
                LastName = 'Contact',
                AccountId = customerChild.Id,
                Email = 'customer@example.com',
                Phone = '555-1004',
                MobilePhone = '555-2004'
            ),
            new Contact(
                FirstName = 'Direct',
                LastName = 'IDN Contact',
                AccountId = idnAccount.Id,
                Email = 'direct@example.com'
            ),
            new Contact(
                FirstName = 'Unrelated',
                LastName = 'Contact',
                AccountId = unrelatedAccount.Id,
                Email = 'unrelated@example.com'
            )
        };
    }

    @IsTest
    static void testIdnChildContacts() {
        Account idnAccount = [SELECT Id FROM Account WHERE Name = :IDN_NAME LIMIT 1];

        Test.startTest();
        ChildAccountContactController.ChildAccountContactResponse response =
            ChildAccountContactController.getChildAccountContacts(idnAccount.Id);
        Test.stopTest();

        System.assertEquals(true, response.displayComponent);
        System.assert(response.childAccountCount >= 1);
        System.assert(response.totalContactCount >= 1);

        Set<String> contactNames = new Set<String>();
        for (ChildAccountContactController.ContactRow row : response.contacts) {
            contactNames.add(row.contactName);
        }

        System.assert(contactNames.contains('ParentId Contact'));
        System.assert(!contactNames.contains('Direct IDN Contact'));
        System.assert(!contactNames.contains('Unrelated Contact'));
    }

    @IsTest
    static void testGpoChildContacts() {
        Account gpoAccount = [SELECT Id FROM Account WHERE Name = :GPO_NAME LIMIT 1];

        Test.startTest();
        ChildAccountContactController.ChildAccountContactResponse response =
            ChildAccountContactController.getChildAccountContacts(gpoAccount.Id);
        Test.stopTest();

        System.assertEquals(true, response.displayComponent);
        System.assertEquals(1, response.childAccountCount);
        System.assertEquals(1, response.totalContactCount);
        System.assertEquals('GPO Contact', response.contacts[0].contactName);
    }

    @IsTest
    static void testCustomerChildContacts() {
        Account customerAccount = [SELECT Id FROM Account WHERE Name = :CUSTOMER_NAME LIMIT 1];

        Test.startTest();
        ChildAccountContactController.ChildAccountContactResponse response =
            ChildAccountContactController.getChildAccountContacts(customerAccount.Id);
        Test.stopTest();

        System.assertEquals(true, response.displayComponent);
        System.assertEquals(1, response.childAccountCount);
        System.assertEquals(1, response.accountsWithContactsCount);
        System.assertEquals(1, response.totalContactCount);
        System.assertEquals('Customer Contact', response.contacts[0].contactName);
    }

    @IsTest
    static void testNoChildAccounts() {
        Id customerRtId = getCustomerRecordTypeId();
        Account customerAccount = createAccount('AC6 Empty Customer', 'Customer', customerRtId, null, 'EMPTY101');
        insert customerAccount;

        Test.startTest();
        ChildAccountContactController.ChildAccountContactResponse response =
            ChildAccountContactController.getChildAccountContacts(customerAccount.Id);
        Test.stopTest();

        System.assertEquals(true, response.displayComponent);
        System.assertEquals(0, response.childAccountCount);
        System.assertEquals(0, response.totalContactCount);
        System.assertEquals(0, response.contacts.size());
    }

    @IsTest
    static void testNullAccountId() {
        Test.startTest();

        try {
            ChildAccountContactController.getChildAccountContacts(null);
            System.assert(false, 'Expected AuraHandledException.');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e);
        }

        Test.stopTest();
    }

    private static Account createAccount(
        String name,
        String type,
        Id recordTypeId,
        Id parentId,
        String uniqueCode
    ) {
        Account accountRecord = new Account(
            Name = name,
            Type = type,
            ParentId = parentId,
            OrgIDs__c = '82',
            OracleAddressId__c = 'ADDR-' + uniqueCode,
            SourceSystemID__c = 'SRC-' + uniqueCode
        );

        if (recordTypeId != null) {
            accountRecord.RecordTypeId = recordTypeId;
        }

        return accountRecord;
    }

    private static Id getCustomerRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypes =
            Account.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();

        if (recordTypes.containsKey('Customer')) {
            return recordTypes.get('Customer').getRecordTypeId();
        }

        for (Schema.RecordTypeInfo recordTypeInfo : Account.SObjectType.getDescribe().getRecordTypeInfos()) {
            if (!recordTypeInfo.isMaster() && recordTypeInfo.getName() == 'Customer') {
                return recordTypeInfo.getRecordTypeId();
            }
        }

        System.assert(false, 'Customer Account Record Type not found.');
        return null;
    }

    private static String getValidRelationshipType() {
        Set<String> configuredTypes = new Set<String>{
            AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_GPO_MEMBER,
            AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_IDN_MEMBER,
            AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_IS_IDN_MEMBER_OF,
            AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_IS_GPO_MEMBER_OF
        };

        for (Schema.PicklistEntry entry : AccountAccountRelationship__c.RelationshipType__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && configuredTypes.contains(entry.getValue())) {
                return entry.getValue();
            }
        }

        return null;
    }
}