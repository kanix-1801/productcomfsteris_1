/**
 * @description
 * GC-2868 
 * Test class Tasks and Events associated with Customer/Address Accounts
 */
@IsTest
private class EnterpriseActivityControllerTest {
    private static final String IDN_NAME = 'AC5 Test IDN';
    private static final String GPO_NAME = 'AC5 Test GPO';
    private static final String FACILITY_ONE_NAME = 'AC5 Facility One';
    private static final String FACILITY_TWO_NAME = 'AC5 Facility Two';
    private static final String CUSTOMER_NAME = 'AC5 Customer';

    @TestSetup
    static void createData() {
        Id customerRtId = getCustomerRecordTypeId();

        Account idnAccount = createAccount(IDN_NAME, 'IDN', null, 'IDN001');
        Account gpoAccount = createAccount(GPO_NAME, 'GPO', null, 'GPO001');
        Account facilityOne = createAccount(FACILITY_ONE_NAME, 'Customer', customerRtId, 'FAC001');
        Account facilityTwo = createAccount(FACILITY_TWO_NAME, 'Customer', customerRtId, 'FAC002');
        Account customerAccount = createAccount(CUSTOMER_NAME, 'Customer', customerRtId, 'CUS001');

        insert new List<Account>{ idnAccount, gpoAccount, facilityOne, facilityTwo, customerAccount };

        String relationshipType = getActiveRelationshipType();

        insert new List<AccountAccountRelationship__c>{
            new AccountAccountRelationship__c(
                ParentAccount__c = idnAccount.Id,
                ChildAccount__c = facilityOne.Id,
                RelationshipType__c = relationshipType
            ),
            new AccountAccountRelationship__c(
                ParentAccount__c = idnAccount.Id,
                ChildAccount__c = facilityTwo.Id,
                RelationshipType__c = relationshipType
            ),
            new AccountAccountRelationship__c(
                ParentAccount__c = gpoAccount.Id,
                ChildAccount__c = facilityOne.Id,
                RelationshipType__c = relationshipType
            )
        };

        String taskStatus = getActiveTaskStatus();

        insert new List<Task>{
            new Task(
                Subject = 'Facility One Follow-up',
                Status = taskStatus,
                Priority = 'Normal',
                ActivityDate = Date.today().addDays(5),
                WhatId = facilityOne.Id,
                OwnerId = UserInfo.getUserId()
            ),
            new Task(
                Subject = 'Facility Two Call',
                Status = taskStatus,
                Priority = 'Normal',
                ActivityDate = Date.today().addDays(10),
                WhatId = facilityTwo.Id,
                OwnerId = UserInfo.getUserId()
            ),
            new Task(
                Subject = 'Customer Task',
                Status = taskStatus,
                Priority = 'Normal',
                ActivityDate = Date.today().addDays(15),
                WhatId = customerAccount.Id,
                OwnerId = UserInfo.getUserId()
            )
        };

        Datetime startOne = System.now().addDays(2);
        Datetime startTwo = System.now().addDays(3);

        insert new List<Event>{
            new Event(
                Subject = 'Facility One Meeting',
                StartDateTime = startOne,
                EndDateTime = startOne.addHours(1),
                WhatId = facilityOne.Id,
                OwnerId = UserInfo.getUserId()
            ),
            new Event(
                Subject = 'Facility Two Meeting',
                StartDateTime = startTwo,
                EndDateTime = startTwo.addHours(1),
                WhatId = facilityTwo.Id,
                OwnerId = UserInfo.getUserId()
            )
        };
    }

    @IsTest
    static void testIdnActivities() {
        Account idnAccount = [SELECT Id FROM Account WHERE Name = :IDN_NAME LIMIT 1];

        Test.startTest();
        EnterpriseActivityController.EnterpriseActivityResponse response =
            EnterpriseActivityController.getEnterpriseActivities(idnAccount.Id);
        Test.stopTest();

        System.assertEquals(true, response.displayComponent);
        System.assertEquals(true, response.isEnterpriseView);
        System.assertEquals(2, response.relatedAccountCount);
        System.assertEquals(2, response.taskCount);
        System.assertEquals(2, response.eventCount);
        System.assertEquals(4, response.totalActivityCount);
        System.assertEquals(4, response.activities.size());
    }

    @IsTest
    static void testGpoActivities() {
        Account gpoAccount = [SELECT Id FROM Account WHERE Name = :GPO_NAME LIMIT 1];

        Test.startTest();
        EnterpriseActivityController.EnterpriseActivityResponse response =
            EnterpriseActivityController.getEnterpriseActivities(gpoAccount.Id);
        Test.stopTest();

        System.assertEquals(true, response.displayComponent);
        System.assertEquals(true, response.isEnterpriseView);
        System.assertEquals(1, response.relatedAccountCount);
        System.assertEquals(1, response.taskCount);
        System.assertEquals(1, response.eventCount);
        System.assertEquals(2, response.totalActivityCount);
    }

    @IsTest
    static void testCustomerActivities() {
        Account customerAccount = [SELECT Id FROM Account WHERE Name = :CUSTOMER_NAME LIMIT 1];

        Test.startTest();
        EnterpriseActivityController.EnterpriseActivityResponse response =
            EnterpriseActivityController.getEnterpriseActivities(customerAccount.Id);
        Test.stopTest();

        System.assertEquals(true, response.displayComponent);
        System.assertEquals(false, response.isEnterpriseView);
        System.assertEquals(1, response.relatedAccountCount);
        System.assertEquals(1, response.taskCount);
        System.assertEquals(0, response.eventCount);
        System.assertEquals(1, response.totalActivityCount);
    }

    @IsTest
    static void testIdnWithoutRelationships() {
        Account idnAccount = createAccount('AC5 Empty IDN', 'IDN', null, 'IDN002');
        insert idnAccount;

        Test.startTest();
        EnterpriseActivityController.EnterpriseActivityResponse response =
            EnterpriseActivityController.getEnterpriseActivities(idnAccount.Id);
        Test.stopTest();

        System.assertEquals(true, response.displayComponent);
        System.assertEquals(true, response.isEnterpriseView);
        System.assertEquals(0, response.relatedAccountCount);
        System.assertEquals(0, response.totalActivityCount);
    }

    @IsTest
    static void testNullAccountId() {
        Test.startTest();

        try {
            EnterpriseActivityController.getEnterpriseActivities(null);
            System.assert(false, 'Expected AuraHandledException.');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e);
        }

        Test.stopTest();
    }

    private static Account createAccount(String name, String type, Id recordTypeId, String uniqueCode) {
        Account accountRecord = new Account(
            Name = name,
            Type = type,
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

    private static String getActiveRelationshipType() {
        for (Schema.PicklistEntry entry : AccountAccountRelationship__c.RelationshipType__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        System.assert(false, 'No active RelationshipType__c value found.');
        return null;
    }

    private static String getActiveTaskStatus() {
        for (Schema.PicklistEntry entry : Task.Status.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        System.assert(false, 'No active Task Status found.');
        return null;
    }
}