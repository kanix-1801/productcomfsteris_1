/**
 * @author PWC Developer
 * @date 2026/11/04
 *
 * @group Generate Quote
 *
 * @description Unit and integration tests for GenerateQuoteService.
 */
@IsTest
private class GenerateQuoteServiceTest {
    private static final String TEST_OPPORTUNITY_NAME = 'Generate Quote Service Test Opportunity';
    private static final String SYSTEM_ADMIN = 'System Administrator';

    @TestSetup
    static void setupData() {
        Profile sysAdminProfile = [SELECT Id FROM Profile WHERE Name = :SYSTEM_ADMIN LIMIT 1];
        Long uniqueSeed = System.currentTimeMillis();

        User runningUser = new User(
            FirstName = 'Service',
            LastName = 'TestUser',
            Alias = ('svc' + String.valueOf(Math.abs(Crypto.getRandomInteger()))).left(8),
            Email = 'generatequoteservice+' + uniqueSeed + '@test.invalid',
            Username = 'generatequoteservice+' + uniqueSeed + '@test.invalid',
            CommunityNickname = ('gqsvc' + uniqueSeed).left(40),
            ProfileId = sysAdminProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            EmployeeNumber__c = 'GQSV' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            FederationIdentifier = 'GQSV' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true
        );
        insert runningUser;

        System.runAs(runningUser) {
            PermissionSetGroup psGroup = [
                SELECT Id, Status
                FROM PermissionSetGroup
                WHERE DeveloperName = 'SalesFieldRepAccountManagerPSG'
                LIMIT 1
            ];
            Test.calculatePermissionSetGroup(psGroup.Id);
            insert new PermissionSetAssignment(
                AssigneeId = runningUser.Id,
                PermissionSetGroupId = psGroup.Id
            );
        }

        Id standardPricebookId = Test.getStandardPricebookId();
        Id healthcareSalesRtId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('Healthcare_Sales')
            .getRecordTypeId();

        Account accountRecord = new Account(
            Name = 'Generate Quote Service Test Account',
            SourceSystemID__c = 'GQ-SVC-ACCT',
            OracleAddressId__c = '638265'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Service',
            LastName = 'Quote',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        insert new Opportunity(
            Name = TEST_OPPORTUNITY_NAME,
            AccountId = accountRecord.Id,
            StageName = getValidStageName(),
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = contactRecord.Id,
            Pricebook2Id = standardPricebookId,
            RecordTypeId = healthcareSalesRtId,
            Type = getValidOpportunityType()
        );
    }

    @IsTest
    static void testQuoteReferenceHelpersCoverNullAndPopulatedValues() {
        System.assertEquals(null, GenerateQuoteService.resolveQuoteNumber(null));
        System.assertEquals(null, GenerateQuoteService.resolveSalesConnectionQuoteId(null));
        System.assertEquals(null, GenerateQuoteService.resolveQuoteNumberLabel(null));
        System.assertEquals(null, GenerateQuoteService.resolveSalesConnectionViewQuoteId(null));
        System.assertEquals(null, GenerateQuoteService.normalizeSalesConnectionQuoteIdForStorage(null));
        System.assertEquals(null, GenerateQuoteService.normalizeQuoteNumberForStorage('   '));

        Quote quoteRecord = new Quote(
            QuoteNumber__c = '00001234',
            SalesConnectionQuoteID__c = 'SC-2283704',
            Source_System_ID__c = 'legacy-id'
        );

        System.assertEquals('00001234', GenerateQuoteService.resolveQuoteNumber(quoteRecord));
        System.assertEquals('SC-2283704', GenerateQuoteService.resolveSalesConnectionQuoteId(quoteRecord));
        System.assertEquals('00001234', GenerateQuoteService.resolveQuoteNumberLabel(quoteRecord));
        System.assertEquals('2283704', GenerateQuoteService.resolveSalesConnectionViewQuoteId(quoteRecord));
        System.assertEquals('2283704', GenerateQuoteService.normalizeSalesConnectionQuoteIdForStorage('SC-2283704'));
        System.assertEquals('00001234', GenerateQuoteService.normalizeQuoteNumberForStorage(' 00001234 '));

        quoteRecord.SalesConnectionQuoteID__c = null;
        System.assertEquals('legacy-id', GenerateQuoteService.resolveSalesConnectionQuoteId(quoteRecord));
    }

    @IsTest
    static void testQuoteTypeAndNameHelpers() {
        Opportunity opportunityRecord = new Opportunity(Name = 'Service Helper Opp');

        System.assertEquals(
            GenerateQuoteService.QUOTE_TYPE_NORMAL,
            GenerateQuoteService.resolveQuoteType('Unexpected')
        );
        System.assertEquals(
            GenerateQuoteService.QUOTE_TYPE_TRIAL,
            GenerateQuoteService.resolveQuoteType(GenerateQuoteService.QUOTE_TYPE_TRIAL)
        );
        System.assertEquals(true, GenerateQuoteService.isForecastIneligibleQuoteType(GenerateQuoteService.QUOTE_TYPE_TRIAL));
        System.assertEquals(true, GenerateQuoteService.isScopedQuoteType(GenerateQuoteService.QUOTE_TYPE_SAMPLE));
        System.assertEquals(
            'Quote - Service Helper Opp',
            GenerateQuoteService.resolveQuoteName(opportunityRecord, GenerateQuoteService.QUOTE_TYPE_NORMAL)
        );
        System.assertEquals(
            'Trial Quote - Service Helper Opp',
            GenerateQuoteService.resolveQuoteName(opportunityRecord, GenerateQuoteService.QUOTE_TYPE_TRIAL)
        );

        GenerateQuoteService.applyQuoteCurrencyFromOpportunity(null, opportunityRecord);
        GenerateQuoteService.applyQuoteCurrencyFromOpportunity(new Quote(), null);
    }

    @IsTest
    static void testValidateSalesConnectionSfRequestRejectsUnsupportedType() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            GenerateQuoteService.validateSalesConnectionSfRequest('unsupported');
        } catch (GenerateQuoteException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testGetQuotesOverloadChainReturnsEmptyList() {
        User runningUser = getRunningUser();
        Opportunity opportunityRecord = getTestOpportunity();

        System.runAs(runningUser) {
            Test.startTest();
            System.assertEquals(0, GenerateQuoteService.getQuotes(opportunityRecord.Id).size());
            System.assertEquals(
                0,
                GenerateQuoteService.getQuotes(opportunityRecord.Id, null).size()
            );
            System.assertEquals(
                0,
                GenerateQuoteService.getQuotes(opportunityRecord.Id, null, false).size()
            );
            System.assertEquals(
                0,
                GenerateQuoteService.getQuotes(opportunityRecord.Id, null, false, null).size()
            );
            System.assertEquals(
                0,
                GenerateQuoteService.getQuotes(opportunityRecord.Id, null, false, null, null).size()
            );
            Test.stopTest();
        }
    }

    @IsTest
    static void testCreateQuoteSingleArgumentOverloadCreatesShellQuote() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
            configureSalesConnectionSettings();
            Opportunity opportunityRecord = getTestOpportunity();

            Test.startTest();
            GenerateQuoteController.CreateQuoteResponse response =
                GenerateQuoteService.createQuote(opportunityRecord.Id);
            Test.stopTest();

            System.assertNotEquals(null, response.quoteId);
            System.assertEquals(
                0,
                [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :response.quoteId]
            );
        }
    }

    @IsTest
    static void testRefreshQuotesThrowsWhenAsyncRetryIsEnqueued() {
        User runningUser = getRunningUser();

        System.runAs(runningUser) {
            Opportunity opportunityRecord = getTestOpportunity();
            ShoutOut_Service_Setting__mdt serviceSetting = defaultRefreshServiceSetting();
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
                GenerateQuoteService.refreshQuotes(opportunityRecord.Id);
            } catch (GenerateQuoteException exceptionValue) {
                exceptionThrown = true;
                System.assert(
                    exceptionValue.getMessage().contains('async retry'),
                    'Expected retry-enqueued message but got: ' + exceptionValue.getMessage()
                );
            }
            Test.stopTest();

            System.assertEquals(true, exceptionThrown);
        }
    }

    @IsTest
    static void testResolveHcSalesQuoteRecordTypeIdDoesNotThrow() {
        Test.startTest();
        Id recordTypeId = GenerateQuoteService.resolveHcSalesQuoteRecordTypeId();
        Test.stopTest();

        if (recordTypeId != null) {
            Schema.RecordTypeInfo recordTypeInfo =
                Schema.SObjectType.Quote.getRecordTypeInfosById().get(recordTypeId);
            System.assertNotEquals(null, recordTypeInfo, 'Returned id should be a Quote record type.');
        }
    }

    private static User getRunningUser() {
        return [
            SELECT Id
            FROM User
            WHERE LastName = 'TestUser'
            LIMIT 1
        ];
    }

    private static Opportunity getTestOpportunity() {
        return [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];
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

    private static ShoutOut_Service_Setting__mdt defaultRefreshServiceSetting() {
        ShoutOut_Service_Setting__mdt cmdtRecord = new ShoutOut_Service_Setting__mdt();
        cmdtRecord.DeveloperName = 'SF_REFRESH_QUOTE';
        cmdtRecord.Framework_Callout_Name__c = 'SF_REFRESH_QUOTE';
        cmdtRecord.isActive__c = true;
        cmdtRecord.Label = 'SF_REFRESH_QUOTE';
        cmdtRecord.MasterLabel = 'SF_REFRESH_QUOTE';
        cmdtRecord.Named_Credential__c = 'Generate_Refresh_Quote';
        cmdtRecord.Provider_Class__c = 'SO_Provider_Simple';
        cmdtRecord.REST_Path__c = '/v1/796feb3d-b03b-4742-9274-34dc5d0fde7a';
        cmdtRecord.REST_Verb__c = 'POST';
        cmdtRecord.Service_Class__c = 'SO_ServiceAdapterBase_REST';
        cmdtRecord.Timeout__c = 20;
        return cmdtRecord;
    }

    private static String getValidStageName() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return 'Discovery';
    }

    private static String getValidOpportunityType() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.Type.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }
}