/**
 * Author: Akash Dahinde
 * Story: GC-2868
 * @description: Test class - Retrieves Opportunities from child Accounts related through Account.ParentId and AAR.
 */
@IsTest
private class ChildAccountOpportunityControllerTest {
    private static final String IDN_NAME = 'AC3 Test IDN';
    private static final String GPO_NAME = 'AC3 Test GPO';
    private static final String CUSTOMER_NAME = 'AC3 Test Customer';
    private static final String PARENT_CHILD_NAME = 'AC3 ParentId Child';
    private static final String AAR_CHILD_NAME = 'AC3 AAR Child';
    private static final String UNRELATED_NAME = 'AC3 Unrelated Customer';

    @TestSetup
    static void createData() {
        Id customerRtId = getCustomerRecordTypeId();

        Id healthcareSalesRtId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Healthcare_Sales').getRecordTypeId();
        
        Account idnAccount = createAccount(IDN_NAME, 'IDN', null, null, 'IDN001');
        Account gpoAccount = createAccount(GPO_NAME, 'GPO', null, null, 'GPO001');
        Account customerAccount = createAccount(CUSTOMER_NAME, 'Customer', customerRtId, null, 'CUS001');
        insert new List<Account>{ idnAccount, gpoAccount, customerAccount };

        Account parentChild = createAccount(PARENT_CHILD_NAME, 'Customer', customerRtId, idnAccount.Id, 'CHD001');
        Account aarChild = createAccount(AAR_CHILD_NAME, 'Customer', customerRtId, null, 'CHD002');
        Account gpoChild = createAccount('AC3 GPO Child', 'Customer', customerRtId, gpoAccount.Id, 'CHD003');
        Account customerChild = createAccount('AC3 Customer Child', 'Customer', customerRtId, customerAccount.Id, 'CHD004');
        Account unrelatedAccount = createAccount(UNRELATED_NAME, 'Customer', customerRtId, null, 'UNR001');
        insert new List<Account>{ parentChild, aarChild, gpoChild, customerChild, unrelatedAccount };

        String relationshipType = getValidRelationshipType();

        if (relationshipType != null) {
            insert new AccountAccountRelationship__c(
                ParentAccount__c = idnAccount.Id,
                ChildAccount__c = aarChild.Id,
                RelationshipType__c = relationshipType
            );
        }

        Contact cont = new Contact();
        cont.LastName = 'Test Contact';
        cont.AccountId = parentChild.Id;

        insert cont;

        String openStage = getOpenStage();

        insert new List<Opportunity>{
            new Opportunity(
                Name = 'ParentId Opportunity',
                AccountId = parentChild.Id,
                StageName = openStage,
                CloseDate = Date.today().addDays(30),
                Amount = 10000,
                Type='New Business',
                Probability = 10,
                PrimaryContact__c = cont.Id,
                RecordTypeId = healthcareSalesRtId
            ),
            new Opportunity(
                Name = 'AAR Opportunity',
                AccountId = aarChild.Id,
                StageName = openStage,
                CloseDate = Date.today().addDays(40),
                Amount = 20000,
                Type='New Business',
                Probability = 10,
                PrimaryContact__c = cont.Id,
                RecordTypeId = healthcareSalesRtId
            ),
            new Opportunity(
                Name = 'GPO Child Opportunity',
                AccountId = gpoChild.Id,
                StageName = openStage,
                CloseDate = Date.today().addDays(50),
                Amount = 30000,
                Type='New Business',
                Probability = 10,
                PrimaryContact__c = cont.Id,
                RecordTypeId = healthcareSalesRtId
            ),
            new Opportunity(
                Name = 'Customer Child Opportunity',
                AccountId = customerChild.Id,
                StageName = openStage,
                CloseDate = Date.today().addDays(60),
                Amount = 40000,
                Type='New Business',
                Probability = 10,
                PrimaryContact__c = cont.Id,
                RecordTypeId = healthcareSalesRtId
            ),
            new Opportunity(
                Name = 'Direct IDN Opportunity',
                AccountId = idnAccount.Id,
                StageName = openStage,
                CloseDate = Date.today().addDays(70),
                Amount = 50000,
                Type='New Business',
                Probability = 10,
                PrimaryContact__c = cont.Id,
                RecordTypeId = healthcareSalesRtId
            ),
            new Opportunity(
                Name = 'Unrelated Opportunity',
                AccountId = unrelatedAccount.Id,
                StageName = openStage,
                CloseDate = Date.today().addDays(80),
                Amount = 60000,
                Type='New Business',
                Probability = 10,
                PrimaryContact__c = cont.Id,
                RecordTypeId = healthcareSalesRtId
            )
        };
    }

    @IsTest
    static void testIdnChildOpportunities() {
        Account idnAccount = [SELECT Id FROM Account WHERE Name = :IDN_NAME LIMIT 1];

        Test.startTest();
        ChildAccountOpportunityController.ChildOpportunityResponse response =
            ChildAccountOpportunityController.getChildAccountOpportunities(idnAccount.Id);
        Test.stopTest();

        System.assertEquals(true, response.displayComponent);
        System.assert(response.childAccountCount >= 1);
        System.assert(response.totalOpportunityCount >= 1);

        Set<String> opportunityNames = new Set<String>();
        for (ChildAccountOpportunityController.OpportunityRow row : response.opportunities) {
            opportunityNames.add(row.opportunityName);
        }

        System.assert(opportunityNames.contains('ParentId Opportunity'));
        System.assert(!opportunityNames.contains('Direct IDN Opportunity'));
        System.assert(!opportunityNames.contains('Unrelated Opportunity'));
    }

    @IsTest
    static void testGpoChildOpportunities() {
        Account gpoAccount = [SELECT Id FROM Account WHERE Name = :GPO_NAME LIMIT 1];

        Test.startTest();
        ChildAccountOpportunityController.ChildOpportunityResponse response =
            ChildAccountOpportunityController.getChildAccountOpportunities(gpoAccount.Id);
        Test.stopTest();

        System.assertEquals(true, response.displayComponent);
        System.assertEquals(1, response.childAccountCount);
        System.assertEquals(1, response.totalOpportunityCount);
        System.assertEquals('GPO Child Opportunity', response.opportunities[0].opportunityName);
    }

    @IsTest
    static void testCustomerChildOpportunities() {
        Account customerAccount = [SELECT Id FROM Account WHERE Name = :CUSTOMER_NAME LIMIT 1];

        Test.startTest();
        ChildAccountOpportunityController.ChildOpportunityResponse response =
            ChildAccountOpportunityController.getChildAccountOpportunities(customerAccount.Id);
        Test.stopTest();

        System.assertEquals(true, response.displayComponent);
        System.assertEquals(1, response.childAccountCount);
        System.assertEquals(1, response.totalOpportunityCount);
        System.assertEquals('Customer Child Opportunity', response.opportunities[0].opportunityName);
    }

    @IsTest
    static void testNoChildAccounts() {
        Id customerRtId = getCustomerRecordTypeId();
        Account customerAccount = createAccount('AC3 Empty Customer', 'Customer', customerRtId, null, 'EMPTY001');
        insert customerAccount;

        Test.startTest();
        ChildAccountOpportunityController.ChildOpportunityResponse response =
            ChildAccountOpportunityController.getChildAccountOpportunities(customerAccount.Id);
        Test.stopTest();

        System.assertEquals(true, response.displayComponent);
        System.assertEquals(0, response.childAccountCount);
        System.assertEquals(0, response.totalOpportunityCount);
        System.assertEquals(0, response.opportunities.size());
    }

    @IsTest
    static void testNullAccountId() {
        Test.startTest();

        try {
            ChildAccountOpportunityController.getChildAccountOpportunities(null);
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
            Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getRecordTypeInfosByDeveloperName();

        if (recordTypes.containsKey('Customer')) {
            return recordTypes.get('Customer').getRecordTypeId();
        }

        for (Schema.RecordTypeInfo recordTypeInfo : Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getRecordTypeInfos()) {
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

    private static String getOpenStage() {
        List<OpportunityStage> stages = [SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder ASC LIMIT 1];
        System.assert(!stages.isEmpty(), 'An active open Opportunity Stage is required.');
        return stages[0].MasterLabel;
    }
}