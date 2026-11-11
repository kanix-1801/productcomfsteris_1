/**
* @author PWC Developer
* @date 2026/06/10
*
* @group Generate Quote
*
* @description
* GC-2642 Test class for GenerateQuoteControllerClass.
*/
@IsTest
private class GenerateQuoteControllerTest {
    private static final String TEST_OPPORTUNITY_NAME = 'Generate Quote Test Opportunity';
    private static final String SYSTEM_ADMIN = 'System Administrator';

    /**
     * @description Creates User.
     */
    private static User createUser(
        Id profileId,
        String username,
        String employeeNumber
    ) {
        String uniqueValue =
            String.valueOf(
                Math.abs(
                    Crypto.getRandomInteger()
                )
            );

        return new User(
            FirstName = 'Test',
            LastName = 'User',
            Alias =
                ('u' + uniqueValue).left(8),
            Email = username,
            Username = username,
            CommunityNickname =
                ('custtas' + uniqueValue).left(40),
            ProfileId = profileId,
            TimeZoneSidKey =
                'America/New_York',
            LocaleSidKey =
                'en_US',
            EmailEncodingKey =
                'UTF-8',
            LanguageLocaleKey =
                'en_US',
            EmployeeNumber__c =
                employeeNumber,
            FederationIdentifier =
                employeeNumber,
            IsActive = true
        );
    }
    
    @TestSetup
    static void setupData() {

        Profile sysAdminProfile = [SELECT Id FROM Profile WHERE Name = :SYSTEM_ADMIN LIMIT 1];

        Long uniqueSeed = System.currentTimeMillis();

        User runningUser = createUser(
            sysAdminProfile.Id,
            'custrunninguser' + uniqueSeed + '@test.com',
            'CRUN' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );

        insert runningUser;

        System.runAs(runningUser){
            PermissionSetGroup psGroup = [
            SELECT Id, Status
            FROM PermissionSetGroup
            WHERE DeveloperName = 'SalesFieldRepAccountManagerPSG'
            LIMIT 1
        ];

        // Force the group to "Updated" so assignments are allowed in test context
        Test.calculatePermissionSetGroup(psGroup.Id);
        
        insert new PermissionSetAssignment(
            AssigneeId = runningUser.Id,
            PermissionSetGroupId = psGroup.Id
        );
        }
        

        Id standardPricebookId = Test.getStandardPricebookId();
        Id healthcareSalesRtId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Healthcare_Sales').getRecordTypeId();
        Product2 productRecord = new Product2(
            Name = 'Generate Quote Test Product',
            ProductCode = 'GQ-TEST-001',
            IsActive = true
        );
        insert productRecord;

        PricebookEntry pricebookEntryRecord = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = productRecord.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pricebookEntryRecord;

        Account accountRecord = new Account(
            Name = 'Generate Quote Test Account',
            SourceSystemID__c = 'GQ-TEST-ACCT',
            OracleAddressId__c = '638265'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Generate',
            LastName = 'Quote Contact',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Opportunity opportunityRecord = buildOpportunity(
            TEST_OPPORTUNITY_NAME,
            accountRecord.Id,
            contactRecord.Id,
            standardPricebookId
        );
        opportunityRecord.recordtypeid = healthcareSalesRtId;
        insert opportunityRecord;

        insert new OpportunityLineItem(
            OpportunityId = opportunityRecord.Id,
            PricebookEntryId = pricebookEntryRecord.Id,
            Quantity = 2,
            UnitPrice = 100
        );

        insert new List<PSAM__c>{
            buildPsamRecord('AER 027', '027', 'AER'),
            buildPsamRecord('AER 045', '045', 'AER'),
            buildPsamRecord('VHP 054', '054', 'AER'),
            buildPsamRecord('Barrier 700', '700', 'Barrier Products'),
            buildPsamRecord('Barrier 703', '703', 'Barrier Products')
        };
    }

    /**
     * @description Returns running test User.
     */
    private static User getRunningUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'custrunninguser%' LIMIT 1];
    }


    private static PSAM__c buildPsamRecord(String name, String famCode, String detailName) {
        return new PSAM__c(
            Name = name,
            ProductFAMCode__c = famCode,
            ProductGroupName__c = 'Test Group',
            ProductSubgroupName__c = 'Test Subgroup',
            ProductSubgroupDetailName__c = detailName
        );
    }

    private static Opportunity buildOpportunity(
        String opportunityName,
        Id accountId,
        Id primaryContactId,
        Id pricebookId
    ) {
        Opportunity opportunityRecord = new Opportunity(
            Name = opportunityName,
            AccountId = accountId,
            StageName = getValidStageName(),
            ForecastConfidenceLevel__c = getValidForecastConfidenceLevel(),
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = primaryContactId
        );

        String opportunityType = getValidOpportunityType();
        if (String.isNotBlank(opportunityType)) {
            opportunityRecord.Type = opportunityType;
        }

        if (pricebookId != null) {
            opportunityRecord.Pricebook2Id = pricebookId;
        }

        return opportunityRecord;
    }

    private static String getValidStageName() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return 'Discovery';
    }

    private static String getValidForecastConfidenceLevel() {
        Schema.DescribeFieldResult fieldDescribe =
            Opportunity.ForecastConfidenceLevel__c.getDescribe();

        if (!fieldDescribe.isAccessible()) {
            return null;
        }

        for (Schema.PicklistEntry picklistEntry : fieldDescribe.getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }

    private static String getValidOpportunityType() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.Type.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }

    private static String getValidOpportunityTeamMemberRole() {
        for (Schema.PicklistEntry picklistEntry :
            OpportunityTeamMember.TeamMemberRole.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return 'Sales Rep';
    }

    private static User createTestUser(String aliasPrefix) {
        return createTestUser(aliasPrefix, false);
    }

    private static User createTestUser(String aliasPrefix, Boolean assignRole) {
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Id roleId = null;
        if (assignRole) {
            List<UserRole> roles = [SELECT Id FROM UserRole WHERE PortalType = 'None' LIMIT 1];
            if (!roles.isEmpty()) {
                roleId = roles[0].Id;
            }
        }

        User userRecord = new User(
            FirstName = aliasPrefix,
            LastName = 'User',
            Alias = (aliasPrefix + suffix).left(8),
            Email = aliasPrefix + '.' + suffix + '@test.com',
            Username = aliasPrefix + '.' + suffix + '@test.com',
            CommunityNickname = aliasPrefix + 'nick' + suffix,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            UserRoleId = roleId,
            IsActive = true
        );
        insert userRecord;
        return userRecord;
    }

    private static void assignSalesAdminPermissionSetGroup(Id userId) {
        PermissionSetGroup psGroup = [
            SELECT Id
            FROM PermissionSetGroup
            WHERE DeveloperName = 'SalesFieldRepAccountManagerPSG'
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetGroupId = psGroup.Id
        );
    }

    private static void addOpportunityTeamMember(Id opportunityId, Id userId, String accessLevel) {
        insert new OpportunityTeamMember(
            OpportunityId = opportunityId,
            UserId = userId,
            TeamMemberRole = getValidOpportunityTeamMemberRole(),
            OpportunityAccessLevel = accessLevel
        );
    }

@IsTest
static void testRefreshQuotesReturnsIntegrationPayload() {
    User runningUser = getRunningUser();

    System.runAs(runningUser) {
    configureSalesConnectionSettings();

    Opportunity opportunityRecord = [
        SELECT Id
        FROM Opportunity
        WHERE Name = :TEST_OPPORTUNITY_NAME
        LIMIT 1
    ];

    GenerateQuoteController.CreateQuoteResponse createResponse =
        GenerateQuoteController.createQuote(opportunityRecord.Id, null, null, null);
    Quote seededQuote = [SELECT Id, Name FROM Quote WHERE Id = :createResponse.quoteId];

    configureRefreshQuoteHttpMock(opportunityRecord.Id);

    Test.startTest();
    List<GenerateQuoteController.QuoteWrapper> quoteWrapperList =
        GenerateQuoteController.refreshQuotes(opportunityRecord.Id);
    Test.stopTest();

    System.assertEquals(
        0,
        quoteWrapperList.size(),
        'Steris dev refresh is ack-only; service returns an empty list on HTTP success.'
    );
    System.assertNotEquals(null, seededQuote.Id, 'Seeded quote should still exist after refresh ack.');
    }
}

    @IsTest
    static void testRefreshQuotesHandlesServiceException() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        GenerateQuoteService.throwTestException = true;
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            GenerateQuoteController.refreshQuotes(opportunityRecord.Id);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        GenerateQuoteService.throwTestException = false;
        System.assert(exceptionThrown, 'AuraHandledException should be thrown when refresh fails.');
    }
    }

    @IsTest
    static void testRefreshQuotesHandlesCalloutFailure() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        ShoutOut_Service_Setting__mdt serviceSetting = new ShoutOut_Service_Setting__mdt();
        serviceSetting.DeveloperName = 'SF_REFRESH_QUOTE';
        serviceSetting.Framework_Callout_Name__c = 'SF_REFRESH_QUOTE';
        serviceSetting.isActive__c = true;
        serviceSetting.Label = 'SF_REFRESH_QUOTE';
        serviceSetting.MasterLabel = 'SF_REFRESH_QUOTE';
        serviceSetting.Named_Credential__c = 'Generate_Refresh_Quote';
        serviceSetting.Provider_Class__c = 'SO_Provider_Salesforce';
        serviceSetting.REST_Path__c = '/v1/796feb3d-b03b-4742-9274-34dc5d0fde7a';
        serviceSetting.REST_Verb__c = 'GET';
        serviceSetting.Service_Class__c = 'SO_ServiceAdapterBase_REST';
        serviceSetting.Timeout__c = 20;
        SO_Config.SO_ServiceList_mock.add(serviceSetting);

        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(
                500,
                'Internal Server Error',
                '{"error":"Unavailable"}',
                new Map<String, String>()
            )
        );

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            GenerateQuoteController.refreshQuotes(opportunityRecord.Id);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'AuraHandledException should be thrown when callout fails.');
    }
    }

    @IsTest
    static void testRefreshQuotesHandlesRetryEnqueued() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
            Opportunity opportunityRecord = [
                SELECT Id
                FROM Opportunity
                WHERE Name = :TEST_OPPORTUNITY_NAME
                LIMIT 1
            ];

            ShoutOut_Service_Setting__mdt serviceSetting = new ShoutOut_Service_Setting__mdt();
            serviceSetting.DeveloperName = 'SF_REFRESH_QUOTE';
            serviceSetting.Framework_Callout_Name__c = 'SF_REFRESH_QUOTE';
            serviceSetting.isActive__c = true;
            serviceSetting.Label = 'SF_REFRESH_QUOTE';
            serviceSetting.MasterLabel = 'SF_REFRESH_QUOTE';
            serviceSetting.Named_Credential__c = 'Generate_Refresh_Quote';
            serviceSetting.Provider_Class__c = 'SO_Provider_Simple';
            serviceSetting.REST_Path__c = '/v1/796feb3d-b03b-4742-9274-34dc5d0fde7a';
            serviceSetting.REST_Verb__c = 'POST';
            serviceSetting.Service_Class__c = 'SO_ServiceAdapterBase_REST';
            serviceSetting.Timeout__c = 20;
            serviceSetting.Retry_Max_Attempts__c = 1;
            serviceSetting.Retry_Base_Delay_Seconds__c = 0;
            serviceSetting.Retry_On_HTTP_Codes__c = '500';
            SO_Config.SO_ServiceList_mock.add(serviceSetting);

            Test.setMock(
                HttpCalloutMock.class,
                new SO_HttpMockFactory(
                    500,
                    'Internal Server Error',
                    '{"error":"Unavailable"}',
                    new Map<String, String>()
                )
            );

            Boolean exceptionThrown = false;

            Test.startTest();
            try {
                GenerateQuoteController.refreshQuotes(opportunityRecord.Id);
            } catch (AuraHandledException exceptionValue) {
                exceptionThrown = true;
            }
            Test.stopTest();

            System.assertEquals(true, exceptionThrown);
        }
    }

    @IsTest
    static void testGetQuotesReturnsEmptyListWhenNoQuotesExist() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Test.startTest();
        List<GenerateQuoteController.QuoteWrapper> resultList =
            GenerateQuoteController.getQuotes(opportunityRecord.Id, null, false, null, null);
        Test.stopTest();

        System.assertEquals(0, resultList.size(), 'No quotes should exist before creation.');
        }
    }

    @IsTest
    static void testGetQuotesRequiresOpportunityId() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            GenerateQuoteController.getQuotes(null, null, false, null, null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'AuraHandledException should be thrown for null Opportunity Id.');
    }
    }

    @IsTest
    static void testCreateTrialQuoteDoesNotSetForecastNotificationFlag() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        configureSalesConnectionSettings();

        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Test.startTest();
        GenerateQuoteController.CreateQuoteResponse response =
            GenerateQuoteController.createQuote(
                opportunityRecord.Id,
                GenerateQuoteService.QUOTE_TYPE_TRIAL,
                null,
                null
            );
        Test.stopTest();

        System.assertNotEquals(null, response.quoteId, 'Trial quote Id should be returned.');

        Quote createdQuote = [
            SELECT IsForecastIneligible__c, QuoteType__c, QuoteForecastConfidence__c
            FROM Quote
            WHERE Id = :response.quoteId
            LIMIT 1
        ];
        System.assertEquals(true, createdQuote.IsForecastIneligible__c);
        System.assertEquals(GenerateQuoteService.QUOTE_TYPE_TRIAL, createdQuote.QuoteType__c);
        System.assertEquals(
            null,
            createdQuote.QuoteForecastConfidence__c,
            'Trial quotes should not copy Opportunity Forecast Confidence on create.'
        );

        Opportunity updatedOpportunity = [
            SELECT IsForecastChangeNotificationPending__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];
        System.assertEquals(
            false,
            updatedOpportunity.IsForecastChangeNotificationPending__c,
            'Generate Trial Quote should not set the forecast change notification flag.'
        );
        }
    }

    @IsTest
    static void testCreateSampleQuoteForSampleRecord() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        configureSalesConnectionSettings();

        Opportunity opportunityRecord = [
            SELECT Id, AccountId, PrimaryContact__c
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        addOpportunityTeamMember(opportunityRecord.Id, runningUser.Id, 'Edit');

        Sample__c sampleRecord = new Sample__c(
            RelatedOpportunity__c = opportunityRecord.Id,
            CustomerAccount__c = opportunityRecord.AccountId,
            CustomerContact__c = opportunityRecord.PrimaryContact__c,
            SamplePurpose__c = getValidSamplePurpose(),
            RequestedDeliveryDate__c = Date.today().addDays(14),
            BusinessJustification__c = 'Generate quote sample test'
        );
        insert sampleRecord;

        Test.startTest();
        GenerateQuoteController.CreateQuoteResponse response =
            GenerateQuoteController.createQuote(
                opportunityRecord.Id,
                GenerateQuoteService.QUOTE_TYPE_SAMPLE,
                null,
                sampleRecord.Id
            );
        Test.stopTest();

        System.assertNotEquals(null, response.quoteId, 'Sample quote Id should be returned.');

        Quote createdQuote = [
            SELECT IsForecastIneligible__c, QuoteType__c, Sample__c, Name, QuoteForecastConfidence__c
            FROM Quote
            WHERE Id = :response.quoteId
            LIMIT 1
        ];
        System.assertEquals(true, createdQuote.IsForecastIneligible__c);
        System.assertEquals(GenerateQuoteService.QUOTE_TYPE_SAMPLE, createdQuote.QuoteType__c);
        System.assertEquals(
            null,
            createdQuote.QuoteForecastConfidence__c,
            'Sample quotes should not copy Opportunity Forecast Confidence on create.'
        );
        System.assertEquals(sampleRecord.Id, createdQuote.Sample__c);
        System.assert(
            createdQuote.Name.startsWith('Sample Quote - '),
            'Sample quote name should use the Sample prefix.'
        );

        Opportunity updatedOpportunity = [
            SELECT IsForecastChangeNotificationPending__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];
        System.assertEquals(
            false,
            updatedOpportunity.IsForecastChangeNotificationPending__c,
            'Generate Sample Quote should not set the forecast change notification flag.'
        );
        }
    }

    private static String getValidSamplePurpose() {
        for (
            Schema.PicklistEntry picklistEntry :
            Sample__c.SamplePurpose__c.getDescribe().getPicklistValues()
        ) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return 'Evaluation';
    }

    @IsTest
    static void testCreateNormalQuoteForGoodwillOpportunity() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        Id goodwillRecordTypeId = getGoodwillOpportunityRecordTypeId();
        if (goodwillRecordTypeId == null) {
            System.assert(true, 'Goodwill Opportunity record type is not available in this org.');
            return;
        }

        configureSalesConnectionSettings();

        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];
        opportunityRecord.RecordTypeId = goodwillRecordTypeId;
        update opportunityRecord;

        Test.startTest();
        GenerateQuoteController.CreateQuoteResponse response =
            GenerateQuoteController.createQuote(opportunityRecord.Id, null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, response.quoteId, 'Quote Id should be returned.');

        Quote createdQuote = [
            SELECT IsForecastIneligible__c, QuoteType__c, Name
            FROM Quote
            WHERE Id = :response.quoteId
            LIMIT 1
        ];
        System.assertEquals(false, createdQuote.IsForecastIneligible__c);
        System.assertEquals(GenerateQuoteService.QUOTE_TYPE_NORMAL, createdQuote.QuoteType__c);
        System.assert(
            createdQuote.Name.startsWith('Quote - '),
            'Quote name should use the standard prefix on Goodwill Opportunities.'
        );
    }
    }

    private static Id getGoodwillOpportunityRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName();

        if (
            !recordTypesByDeveloperName.containsKey(
                GenerateQuoteService.OPPORTUNITY_RECORD_TYPE_GOODWILL
            )
        ) {
            return null;
        }

        Schema.RecordTypeInfo recordTypeInfo =
            recordTypesByDeveloperName.get(GenerateQuoteService.OPPORTUNITY_RECORD_TYPE_GOODWILL);
        return recordTypeInfo.isAvailable() ? recordTypeInfo.getRecordTypeId() : null;
    }

    @IsTest
    static void testCreateQuoteCreatesQuoteAndLineItems() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        configureSalesConnectionSettings();

        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Test.startTest();
        GenerateQuoteController.CreateQuoteResponse response =
            GenerateQuoteController.createQuote(opportunityRecord.Id, null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, response.quoteId, 'Quote Id should be returned.');
        System.assertNotEquals(null, response.salesConnectionUrl, 'Sales Connection URL should be returned.');
        System.assert(
            response.salesConnectionUrl.startsWith('https://integration-salesconnection.steris.com/#Quote|'),
            'Sales Connection open URL should use the encrypted #Quote| format.'
        );
        System.assert(
            !response.salesConnectionUrl.contains('sfrequest=create'),
            'Sales Connection open URL should not expose the plain create-quote payload.'
        );

        Quote createdQuote = [
            SELECT Id,
                Status,
                SalesConnectionQuoteID__c,
                QuoteNumber__c,
                SalesConnectionCreateQuoteURL__c,
                RecordType.DeveloperName,
                (SELECT Id FROM QuoteLineItems)
            FROM Quote
            WHERE Id = :response.quoteId
            LIMIT 1
        ];

        System.assertEquals(
            0,
            createdQuote.QuoteLineItems.size(),
            'Shell quote creation should not insert Quote Line Items until Refresh Quote sync.'
        );
        System.assertEquals(
            GenerateQuoteService.QUOTE_STATUS_OPEN,
            createdQuote.Status,
            'Generated shell quote should use Open status.'
        );
        System.assertEquals(
            null,
            createdQuote.SalesConnectionQuoteID__c,
            'Sales Connection quote id should remain blank until Refresh Quote sync.'
        );
        System.assertEquals(
            null,
            createdQuote.QuoteNumber__c,
            'Quote number should remain blank until Refresh Quote sync.'
        );
        System.assertNotEquals(
            null,
            createdQuote.SalesConnectionCreateQuoteURL__c,
            'Plain-text Sales Connection create-quote URL should be stored on the Quote.'
        );
        System.assert(
            createdQuote.SalesConnectionCreateQuoteURL__c.contains('sfrequest=create'),
            'Stored Sales Connection URL should contain the plain create-quote payload.'
        );
        System.assert(
            createdQuote.SalesConnectionCreateQuoteURL__c.contains(
                'sfquoteid=' + String.valueOf(response.quoteId)
            ),
            'Stored Sales Connection URL should contain the Salesforce Quote Id.'
        );

        Id expectedQuoteRecordTypeId = resolveQuoteRecordTypeIdForTest();
        if (expectedQuoteRecordTypeId != null) {
            System.assertEquals(
                GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME,
                createdQuote.RecordType.DeveloperName,
                'Generated quote should use the HCSales record type.'
            );
        }

        List<GenerateQuoteController.QuoteWrapper> quoteWrapperList =
            GenerateQuoteController.getQuotes(opportunityRecord.Id, null, false, null, null);

        System.assertEquals(1, quoteWrapperList.size(), 'One quote wrapper should be returned.');
        System.assertEquals(
            0,
            quoteWrapperList[0].productSubgroupSummary.size(),
            'Shell quote should not expose subgroup lines until Refresh Quote sync.'
        );
    }
    }

    @IsTest
    static void testCreateQuoteUsesRotatingMockTemplate() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        configureSalesConnectionSettings();

        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        GenerateQuoteController.CreateQuoteResponse firstResponse =
            GenerateQuoteController.createQuote(opportunityRecord.Id, null, null, null);

        Test.startTest();
        GenerateQuoteController.CreateQuoteResponse secondResponse =
            GenerateQuoteController.createQuote(opportunityRecord.Id, null, null, null);
        Test.stopTest();

        System.assertNotEquals(firstResponse.quoteId, secondResponse.quoteId);

        List<Quote> opportunityQuotes = [
            SELECT Id, Status, (SELECT Id FROM QuoteLineItems)
            FROM Quote
            WHERE OpportunityId = :opportunityRecord.Id
        ];

        System.assertEquals(2, opportunityQuotes.size(), 'Each generate action should create a shell quote.');
        for (Quote quoteRecord : opportunityQuotes) {
            System.assertEquals(GenerateQuoteService.QUOTE_STATUS_OPEN, quoteRecord.Status);
            System.assertEquals(0, quoteRecord.QuoteLineItems.size());
        }
    }
}

    @IsTest
    static void testCopyQuoteCreatesShellQuoteWithoutLineItems() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
            configureSalesConnectionSettings();

            Opportunity opportunityRecord = [
                SELECT Id
                FROM Opportunity
                WHERE Name = :TEST_OPPORTUNITY_NAME
                LIMIT 1
            ];

            Test.startTest();
            GenerateQuoteController.CreateQuoteResponse response =
                GenerateQuoteController.copyQuote(opportunityRecord.Id);
            Test.stopTest();

            System.assertNotEquals(null, response.quoteId);
            System.assertNotEquals(null, response.salesConnectionUrl);
            System.assert(
                !response.salesConnectionUrl.contains('sfrequest=copy'),
                'Open URL should encrypt the copy payload.'
            );

            Quote createdQuote = [
                SELECT SalesConnectionCreateQuoteURL__c, (SELECT Id FROM QuoteLineItems)
                FROM Quote
                WHERE Id = :response.quoteId
                LIMIT 1
            ];
            System.assertEquals(
                0,
                createdQuote.QuoteLineItems.size(),
                'Copy quote shell should not create quote line items.'
            );
            System.assert(
                createdQuote.SalesConnectionCreateQuoteURL__c.contains('sfrequest=copy'),
                'Stored URL should contain sfrequest=copy.'
            );
        }
    }

    @IsTest
    static void testMergeQuoteCreatesShellQuoteWithoutLineItems() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
            configureSalesConnectionSettings();

            Opportunity opportunityRecord = [
                SELECT Id
                FROM Opportunity
                WHERE Name = :TEST_OPPORTUNITY_NAME
                LIMIT 1
            ];

            Test.startTest();
            GenerateQuoteController.CreateQuoteResponse response =
                GenerateQuoteController.mergeQuote(opportunityRecord.Id);
            Test.stopTest();

            System.assertNotEquals(null, response.quoteId);

            Quote createdQuote = [
                SELECT SalesConnectionCreateQuoteURL__c, (SELECT Id FROM QuoteLineItems)
                FROM Quote
                WHERE Id = :response.quoteId
                LIMIT 1
            ];
            System.assertEquals(0, createdQuote.QuoteLineItems.size());
            System.assert(
                createdQuote.SalesConnectionCreateQuoteURL__c.contains('sfrequest=merge'),
                'Stored URL should contain sfrequest=merge.'
            );
        }
    }

    @IsTest
    static void testCopyQuoteHandlesServiceException() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
            Opportunity opportunityRecord = [
                SELECT Id
                FROM Opportunity
                WHERE Name = :TEST_OPPORTUNITY_NAME
                LIMIT 1
            ];

            GenerateQuoteService.throwTestException = true;
            Boolean exceptionThrown = false;

            Test.startTest();
            try {
                GenerateQuoteController.copyQuote(opportunityRecord.Id);
            } catch (AuraHandledException exceptionValue) {
                exceptionThrown = true;
            }
            Test.stopTest();

            GenerateQuoteService.throwTestException = false;
            System.assertEquals(true, exceptionThrown);
        }
    }

    @IsTest
    static void testGetSalesConnectionQuoteUrlBuildsEncryptedUrl() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
            configureSalesConnectionSettings();

            Test.startTest();
            String encryptedUrl = GenerateQuoteController.getSalesConnectionQuoteUrl('2283704');
            Test.stopTest();

            System.assertNotEquals(null, encryptedUrl);
            System.assert(
                encryptedUrl.contains('2283704'),
                'View URL should include the normalized Sales Connection quote id.'
            );
            System.assert(
                encryptedUrl.contains('integration-salesconnection.steris.com'),
                'View URL should use the configured Sales Connection base URL.'
            );
        }
    }

    @IsTest
    static void testGetSalesConnectionQuoteUrlRequiresQuoteId() {
        User runningUser = getRunningUser();
        Boolean exceptionThrown = false;

        System.runAs(runningUser) {
            Test.startTest();
            try {
                GenerateQuoteController.getSalesConnectionQuoteUrl(null);
            } catch (AuraHandledException exceptionValue) {
                exceptionThrown = true;
            }
            Test.stopTest();
        }

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testSyncQuoteForecastConfidenceHandlesServiceException() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
            Opportunity opportunityRecord = [
                SELECT Id
                FROM Opportunity
                WHERE Name = :TEST_OPPORTUNITY_NAME
                LIMIT 1
            ];

            GenerateQuoteService.throwTestException = true;
            Boolean exceptionThrown = false;

            Test.startTest();
            try {
                GenerateQuoteController.syncQuoteForecastConfidence(
                    opportunityRecord.Id,
                    opportunityRecord.Id,
                    'Upside',
                    false
                );
            } catch (AuraHandledException exceptionValue) {
                exceptionThrown = true;
            }
            Test.stopTest();

            GenerateQuoteService.throwTestException = false;
            System.assertEquals(true, exceptionThrown);
        }
    }

    @IsTest
    static void testCreateQuoteRequiresActivePricebookEntries() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        configureSalesConnectionSettings();

        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        PricebookEntrySelector.returnNullInTest = true;

        try {
            Test.startTest();
            GenerateQuoteController.CreateQuoteResponse response =
                GenerateQuoteController.createQuote(opportunityRecord.Id, null, null, null);
            Test.stopTest();

            System.assertNotEquals(
                null,
                response.quoteId,
                'Shell quote creation should not depend on PricebookEntrySelector.'
            );
        } finally {
            PricebookEntrySelector.returnNullInTest = false;
        }
    }
    }

    @IsTest
    static void testGetQuotesReturnsSalesConnectionHeaderAndSubgroupData() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        configureSalesConnectionSettings();

        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        GenerateQuoteController.createQuote(opportunityRecord.Id, null, null, null);

        Test.startTest();
        List<GenerateQuoteController.QuoteWrapper> quoteWrapperList =
            GenerateQuoteController.getQuotes(opportunityRecord.Id, null, false, null, null);
        Test.stopTest();

        System.assertEquals(1, quoteWrapperList.size());
        System.assertEquals(GenerateQuoteService.QUOTE_STATUS_OPEN, quoteWrapperList[0].status);
        System.assertNotEquals(null, quoteWrapperList[0].salesConnectionUrl);
        System.assertEquals(
            0,
            quoteWrapperList[0].productSubgroupSummary.size(),
            'Shell quote rows should not include subgroup lines until Refresh Quote sync.'
        );
    }
    }

  
@IsTest
static void testPricebookEntrySelectorCoverage() {
    User runningUser = getRunningUser();
    Id standardPricebookId = Test.getStandardPricebookId();

    System.runAs(runningUser) {
        System.assertEquals(
            0,
            PricebookEntrySelector.selectActiveByPricebookId(null, 5).size(),
            'Null Price Book Id should return no entries.'
        );
        System.assertEquals(
            null,
            PricebookEntrySelector.selectFirstActiveByPricebookId(null),
            'Null Price Book Id should return no first entry.'
        );

        PricebookEntry firstEntryOneArg =
            PricebookEntrySelector.selectFirstActiveByPricebookId(standardPricebookId);
        System.assertNotEquals(
            null,
            firstEntryOneArg,
            'Standard Price Book should have an active entry from @TestSetup.'
        );

        List<PricebookEntry> activeEntriesTwoArg =
            PricebookEntrySelector.selectActiveByPricebookId(standardPricebookId, 10);
        System.assert(
            !activeEntriesTwoArg.isEmpty(),
            'Two-arg overload should return active entries.'
        );

        String currencyIsoCode = resolvePricebookEntryCurrencyIsoCode(standardPricebookId);
        PricebookEntry firstWithCurrency = PricebookEntrySelector.selectFirstActiveByPricebookId(
            standardPricebookId,
            currencyIsoCode
        );
        List<PricebookEntry> entriesWithCurrency = PricebookEntrySelector.selectActiveByPricebookId(
            standardPricebookId,
            1,
            currencyIsoCode
        );
        System.assertNotEquals(
            null,
            firstWithCurrency,
            'Currency overload should return the first active entry.'
        );
        System.assertEquals(
            1,
            entriesWithCurrency.size(),
            'Three-arg overload with row limit 1 should return one entry.'
        );

        System.assert(
            !PricebookEntrySelector.selectActiveByPricebookId(standardPricebookId, null, null)
                .isEmpty(),
            'Null row limit should default and still return entries.'
        );
        System.assert(
            !PricebookEntrySelector.selectActiveByPricebookId(standardPricebookId, 0, null)
                .isEmpty(),
            'Non-positive row limit should default and still return entries.'
        );

        Pricebook2 emptyPricebook = new Pricebook2(
            Name = 'Generate Quote Empty Price Book',
            IsActive = true
        );
        insert emptyPricebook;

        System.assertEquals(
            null,
            PricebookEntrySelector.selectFirstActiveByPricebookId(emptyPricebook.Id),
            'Price Book with no entries should return null for first active entry.'
        );

        PricebookEntrySelector.returnNullInTest = true;
        try {
            System.assertEquals(
                null,
                PricebookEntrySelector.selectFirstActiveByPricebookId(standardPricebookId),
                'Test flag should force empty list and null first entry.'
            );
            System.assertEquals(
                0,
                PricebookEntrySelector.selectActiveByPricebookId(standardPricebookId, 1, null)
                    .size()
            );
        } finally {
            PricebookEntrySelector.returnNullInTest = false;
        }
    }
}

private static String resolvePricebookEntryCurrencyIsoCode(Id pricebookId) {
    List<PricebookEntry> setupEntries = [
        SELECT CurrencyIsoCode
        FROM PricebookEntry
        WHERE Pricebook2Id = :pricebookId
          AND IsActive = true
        LIMIT 1
    ];
    if (!setupEntries.isEmpty() && String.isNotBlank(setupEntries[0].CurrencyIsoCode)) {
        return setupEntries[0].CurrencyIsoCode;
    }
    if (UserInfo.isMultiCurrencyOrganization()) {
        return UserInfo.getDefaultCurrency();
    }
    return 'USD';
}

    @IsTest
    static void testQuoteSelectorCoverage() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        System.assertEquals(0, QuoteSelector.countByOpportunityId(null));
        System.assertEquals(0, QuoteSelector.countByOpportunityId(opportunityRecord.Id));
        System.assertEquals(0, QuoteSelector.selectByOpportunityIdWithLineItems(null).size());
        System.assertEquals(null, QuoteSelector.selectById(null));
        }
    }

    @IsTest
    static void testCreateQuoteRequiresPricebook() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        Account accountRecord = new Account(
            Name = 'No Pricebook Account',
            SourceSystemID__c = 'GQ-NO-PB-ACCT'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'No',
            LastName = 'Pricebook Contact',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Opportunity opportunityRecord = buildOpportunity(
            'No Pricebook Opportunity',
            accountRecord.Id,
            contactRecord.Id,
            null
        );
        insert opportunityRecord;

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            GenerateQuoteController.createQuote(opportunityRecord.Id, null, null, null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'AuraHandledException should be thrown when Price Book is missing.');
    }
    }

    @IsTest
    static void testGetQuotesHandlesServiceException() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        GenerateQuoteService.throwTestException = true;
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            GenerateQuoteController.getQuotes(opportunityRecord.Id, null, false, null, null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        GenerateQuoteService.throwTestException = false;
        System.assert(exceptionThrown, 'AuraHandledException should be thrown when service fails.');
    }
    }

    @IsTest
    static void testOpportunitySelectorCoverage() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        System.assertEquals(
            0,
            OpportunitySelector.selectByAccountIds(new Set<Id>()).size(),
            'Empty account Id set should return no opportunities.'
        );

        Opportunity opportunityRecord = [
            SELECT Id, AccountId
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        System.assertEquals(
            1,
            OpportunitySelector.selectByAccountIds(new Set<Id>{ opportunityRecord.AccountId }).size(),
            'Account Id set should return related opportunities.'
        );

        System.assertNotEquals(
            null,
            OpportunitySelector.selectById(opportunityRecord.Id),
            'Opportunity Id should return the opportunity record.'
        );
        System.assertEquals(
            null,
            OpportunitySelector.selectById(null),
            'Null Opportunity Id should return null.'
        );

        System.assertEquals(
            0,
            OpportunitySelector.selectByIds(new Set<Id>()).size(),
            'Empty Opportunity Id set should return no opportunities.'
        );
        System.assertEquals(
            1,
            OpportunitySelector.selectByIds(new Set<Id>{ opportunityRecord.Id }).size(),
            'Opportunity Id set should return the opportunity record.'
        );

        System.assertEquals(
            0,
            OpportunitySelector.selectByOwnerIds(new Set<Id>()).size(),
            'Empty owner Id set should return no opportunities.'
        );

        Opportunity opportunityWithOwner = [
            SELECT OwnerId
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];
        System.assertEquals(
            null,
            AccountSelector.selectAccountForSalesConnection(null),
            'Null Account Id should return null.'
        );
        System.assertNotEquals(
            null,
            AccountSelector.selectAccountForSalesConnection(opportunityRecord.AccountId),
            'Account Id should return the related Account for Sales Connection URLs.'
        );
        }
    }

    @IsTest
    static void testValidateQuoteAccessAllowsOwner() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Test.startTest();
        GenerateQuoteController.validateQuoteAccess(opportunityRecord.Id);
        Test.stopTest();

        System.assert(true, 'Opportunity owner should have edit access for quote actions.');
        }
    }

    @IsTest
    static void testValidateQuoteAccessAllowsTeamMember() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];
        User teamMemberUser = createTestUser('QuoteTeamMember', true);
        assignSalesAdminPermissionSetGroup(teamMemberUser.Id);
        addOpportunityTeamMember(opportunityRecord.Id, teamMemberUser.Id, 'Edit');

        Test.startTest();
        System.runAs(teamMemberUser) {
            GenerateQuoteController.validateQuoteAccess(opportunityRecord.Id);
        }
        Test.stopTest();

        System.assert(true, 'User with edit access on the Opportunity should pass quote access validation.');
        }
    }

    @IsTest
    static void testValidateQuoteAccessDeniesReadOnlyTeamMember() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];
        User readOnlyTeamMemberUser = createTestUser('QuoteReadOnlyTeamMember');
        Boolean exceptionThrown = false;

        insert new OpportunityTeamMember(
            OpportunityId = opportunityRecord.Id,
            UserId = readOnlyTeamMemberUser.Id,
            TeamMemberRole = getValidOpportunityTeamMemberRole(),
            OpportunityAccessLevel = 'Read'
        );

        Test.startTest();
        System.runAs(readOnlyTeamMemberUser) {
            GenerateQuoteService.testHasEditAccessOverride = false;
            try {
                try {
                    GenerateQuoteController.validateQuoteAccess(opportunityRecord.Id);
                } catch (AuraHandledException exceptionValue) {
                    exceptionThrown = true;
                }
            } finally {
                GenerateQuoteService.testHasEditAccessOverride = null;
            }
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'User without edit access on the Opportunity should be blocked.');
    }
    }

    @IsTest
    static void testValidateQuoteAccessDeniesUnauthorizedUser() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];
        User unauthorizedUser = createTestUser('QuoteUnauthorized');
        Boolean exceptionThrown = false;

        Test.startTest();
        System.runAs(unauthorizedUser) {
            GenerateQuoteService.testHasEditAccessOverride = false;
            try {
                try {
                    GenerateQuoteController.validateQuoteAccess(opportunityRecord.Id);
                } catch (AuraHandledException exceptionValue) {
                    exceptionThrown = true;
                }
            } finally {
                GenerateQuoteService.testHasEditAccessOverride = null;
            }
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'User without Opportunity edit access should be blocked.');
    }
    }

    @IsTest
    static void testCreateQuoteHandlesServiceException() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        GenerateQuoteService.throwTestException = true;
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            GenerateQuoteController.createQuote(opportunityRecord.Id, null, null, null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        GenerateQuoteService.throwTestException = false;
        System.assert(exceptionThrown, 'AuraHandledException should be thrown when service fails.');
    }
    }

    private static Id resolveQuoteRecordTypeIdForTest() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName();

        if (!recordTypesByDeveloperName.containsKey(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME)) {
            return null;
        }

        Schema.RecordTypeInfo recordTypeInfo =
            recordTypesByDeveloperName.get(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME);
        return recordTypeInfo.isAvailable() ? recordTypeInfo.getRecordTypeId() : null;
    }

    private static void configureRefreshQuoteHttpMock(Id opportunityId) {
        ShoutOut_Service_Setting__mdt serviceSetting = new ShoutOut_Service_Setting__mdt();
        serviceSetting.DeveloperName = 'SF_REFRESH_QUOTE';
        serviceSetting.Framework_Callout_Name__c = 'SF_REFRESH_QUOTE';
        serviceSetting.isActive__c = true;
        serviceSetting.Label = 'SF_REFRESH_QUOTE';
        serviceSetting.MasterLabel = 'SF_REFRESH_QUOTE';
        serviceSetting.Named_Credential__c = 'Generate_Refresh_Quote';
        serviceSetting.Provider_Class__c = 'SO_Provider_Simple';
        serviceSetting.REST_Path__c = '/v1/796feb3d-b03b-4742-9274-34dc5d0fde7a';
        serviceSetting.REST_Verb__c = 'POST';
        serviceSetting.Service_Class__c = 'SO_ServiceAdapterBase_REST';
        serviceSetting.Timeout__c = 20;
        SO_Config.SO_ServiceList_mock.add(serviceSetting);

        String responseBody = '[]';
        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(200, 'OK', responseBody, new Map<String, String>())
        );
    }

    private static void configureSalesConnectionSettings() {
        SalesConnectionUrlService.testSettingsOverride = new ExternalSystemEndpoint__mdt(
            SalesConnectionBaseUrl__c = 'https://integration-salesconnection.steris.com',
            SalesConnectionViewQuotePath__c = SalesConnectionUrlService.DEFAULT_VIEW_QUOTE_PATH,
            SalesConnectionEncryptionKey__c = EncodingUtil.base64Encode(
                Blob.valueOf('abcdefghijklmnopqrstuvwxyz012345')
            )
        );
        SalesConnectionUrlService.testEmployeeNumberOverride = '12345';
        SalesConnectionEncryptionService.testEncryptionKeyOverride =
            SalesConnectionUrlService.testSettingsOverride.SalesConnectionEncryptionKey__c;
    }

    @IsTest
    static void testGetQuotesReturnsQuoteForecastConfidenceFields() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        configureSalesConnectionSettings();
        Opportunity opportunityRecord = [
            SELECT Id, ForecastConfidenceLevel__c
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Test.startTest();
        GenerateQuoteController.CreateQuoteResponse createResponse =
            GenerateQuoteController.createQuote(opportunityRecord.Id, null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, createResponse);

        List<GenerateQuoteController.QuoteWrapper> quoteRows = GenerateQuoteController.getQuotes(
            opportunityRecord.Id,
            null,
            false,
            null,
            null
        );

        System.assertEquals(1, quoteRows.size());
        System.assertEquals(
            opportunityRecord.ForecastConfidenceLevel__c,
            quoteRows[0].opportunityForecastConfidence
        );
        }
    }

    @IsTest
    static void testSyncQuoteForecastConfidenceFromOpportunity() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        configureSalesConnectionSettings();
        Opportunity opportunityRecord = [
            SELECT Id, ForecastConfidenceLevel__c
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        GenerateQuoteController.createQuote(opportunityRecord.Id, null, null, null);
        Quote quoteRecord = [
            SELECT Id
            FROM Quote
            WHERE OpportunityId = :opportunityRecord.Id
            LIMIT 1
        ];

        String expectedQuoteConfidence = QuoteService.mapOpportunityForecastConfidenceToQuote(
            opportunityRecord.ForecastConfidenceLevel__c
        );

        Test.startTest();
        GenerateQuoteController.QuoteWrapper updatedQuoteRow =
            GenerateQuoteController.syncQuoteForecastConfidence(
                opportunityRecord.Id,
                quoteRecord.Id,
                null,
                true
            );
        Test.stopTest();

        Quote updatedQuote = [
            SELECT QuoteForecastConfidence__c
            FROM Quote
            WHERE Id = :quoteRecord.Id
            LIMIT 1
        ];

        System.assertEquals(expectedQuoteConfidence, updatedQuote.QuoteForecastConfidence__c);
        System.assertEquals(expectedQuoteConfidence, updatedQuoteRow.quoteForecastConfidence);
        }
    }

    @IsTest
    static void testSyncQuoteForecastConfidenceSavesManualSelection() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
        configureSalesConnectionSettings();
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        GenerateQuoteController.createQuote(opportunityRecord.Id, null, null, null);
        Quote quoteRecord = [
            SELECT Id
            FROM Quote
            WHERE OpportunityId = :opportunityRecord.Id
            LIMIT 1
        ];
        quoteRecord.SalesConnectionQuoteID__c = '2283999';
        update quoteRecord;

        ScOpportunityQuoteEventGateway.forceHardcodedResponse = true;

        Test.startTest();
        GenerateQuoteController.QuoteWrapper updatedQuoteRow =
            GenerateQuoteController.syncQuoteForecastConfidence(
                opportunityRecord.Id,
                quoteRecord.Id,
                'Upside',
                false
            );
        Test.stopTest();

        ScOpportunityQuoteEventGateway.forceHardcodedResponse = false;

        Quote updatedQuote = [
            SELECT QuoteForecastConfidence__c
            FROM Quote
            WHERE Id = :quoteRecord.Id
            LIMIT 1
        ];

        System.assertEquals('Upside', updatedQuote.QuoteForecastConfidence__c);
        System.assertEquals('Upside', updatedQuoteRow.quoteForecastConfidence);
    }
}
}