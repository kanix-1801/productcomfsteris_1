/**
 * @description Tests for LSGenerateQuoteService.
 */
@IsTest
private class LSGenerateQuoteServiceTest {
    private static final String OPPORTUNITY_NAME = 'LS Quote Service Opportunity';

    @TestSetup
    static void setupData() {
        Profile sysAdminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User runningUser = createUser(sysAdminProfile.Id);
        insert runningUser;

        System.runAs(runningUser) {
            assignPermissionSetGroup(runningUser.Id, 'SalesFieldRepAccountManagerPSG');
        }

        Id pricebookId = Test.getStandardPricebookId();
        Product2 productRecord = new Product2(
            Name = 'LS Quote Service Product',
            ProductCode = 'LSQS-001',
            IsActive = true
        );
        insert productRecord;
        insert new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = productRecord.Id,
            UnitPrice = 100,
            IsActive = true
        );

        String suffix = uniqueSuffix();
        Account accountRecord = new Account(
            Name = 'LS Quote Service Account ' + suffix,
            SourceSystemID__c = 'LSQS-' + suffix,
            OracleAddressId__c = '638265'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'LS',
            LastName = 'Service Contact',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Opportunity opportunityRecord = new Opportunity(
            Name = OPPORTUNITY_NAME,
            AccountId = accountRecord.Id,
            StageName = firstActivePicklistValue(Opportunity.StageName),
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            Pricebook2Id = pricebookId,
            PrimaryContact__c = contactRecord.Id,
            RecordTypeId = healthcareRecordTypeId()
        );
        String opportunityType = firstActivePicklistValue(Opportunity.Type);
        if (String.isNotBlank(opportunityType)) {
            opportunityRecord.Type = opportunityType;
        }
        String forecastConfidence = firstActivePicklistValue(Opportunity.ForecastConfidenceLevel__c);
        if (String.isNotBlank(forecastConfidence)) {
            opportunityRecord.ForecastConfidenceLevel__c = forecastConfidence;
        }
        insert opportunityRecord;
    }

    @IsTest
    static void testGetQuotesRequiresIdAndReturnsCreatedQuote() {
        System.runAs(runningUser()) {
            Boolean missingIdThrew = false;
            try {
                LSGenerateQuoteService.getQuotes(null);
            } catch (AuraHandledException exceptionValue) {
                missingIdThrew = true;
            }
            Assert.isTrue(missingIdThrew);

            configureSalesConnectionSettings();
            Opportunity opportunityRecord = opportunityRecord();
            LSGenerateQuoteService.createQuote(opportunityRecord.Id);

            List<GenerateQuoteController.QuoteWrapper> quotes =
                LSGenerateQuoteService.getQuotes(opportunityRecord.Id, null, false, null, null);
            Assert.areEqual(1, quotes.size());
            Assert.areEqual(opportunityRecord.Id, [
                SELECT OpportunityId FROM Quote WHERE Id = :quotes[0].id
            ].OpportunityId);
        }
    }

    @IsTest
    static void testGetQuotesWrapsQueryFailure() {
        System.runAs(runningUser()) {
            LSGenerateQuoteService.throwTestException = true;
            Boolean threw = false;
            try {
                LSGenerateQuoteService.getQuotes(opportunityRecord().Id);
            } catch (GenerateQuoteException exceptionValue) {
                threw = exceptionValue.getMessage().contains('Unable to retrieve quotes');
            } finally {
                LSGenerateQuoteService.throwTestException = false;
            }
            Assert.isTrue(threw);
        }
    }

    @IsTest
    static void testCreateQuoteOverloadsAndMissingPricebook() {
        System.runAs(runningUser()) {
            configureSalesConnectionSettings();
            Opportunity opportunityRecord = opportunityRecord();

            LSGenerateQuoteController.CreateQuoteResponse oneArgument =
                LSGenerateQuoteService.createQuote(opportunityRecord.Id);
            LSGenerateQuoteController.CreateQuoteResponse shellRequest =
                LSGenerateQuoteService.createShellQuoteForSalesConnectionRequest(
                    opportunityRecord.Id,
                    LSSalesConnectionUrlService.SF_REQUEST_COPY
                );

            Assert.isNotNull(oneArgument.quoteId);
            Assert.isNotNull(shellRequest.quoteId);
            Assert.areEqual(2, [SELECT COUNT() FROM Quote WHERE OpportunityId = :opportunityRecord.Id]);

            Opportunity sourceOpportunity = [
                SELECT AccountId, PrimaryContact__c, StageName, Type, ForecastConfidenceLevel__c, RecordTypeId
                FROM Opportunity
                WHERE Id = :opportunityRecord.Id
            ];
            Opportunity withoutPricebook = new Opportunity(
                Name = 'LS Quote Missing Pricebook',
                AccountId = sourceOpportunity.AccountId,
                PrimaryContact__c = sourceOpportunity.PrimaryContact__c,
                StageName = sourceOpportunity.StageName,
                Type = sourceOpportunity.Type,
                ForecastConfidenceLevel__c = sourceOpportunity.ForecastConfidenceLevel__c,
                RecordTypeId = sourceOpportunity.RecordTypeId,
                CloseDate = Date.today().addDays(30),
                Amount = 1000,
                Probability = 10
            );
            insert withoutPricebook;

            Boolean missingPricebookThrew = false;
            try {
                LSGenerateQuoteService.createQuote(
                    withoutPricebook.Id,
                    LSGenerateQuoteService.QUOTE_TYPE_TRIAL,
                    null
                );
            } catch (AuraHandledException exceptionValue) {
                missingPricebookThrew = true;
            }
            Assert.isTrue(missingPricebookThrew);
        }
    }

    @IsTest
    static void testCreateQuoteWrapsForcedFailure() {
        System.runAs(runningUser()) {
            LSGenerateQuoteService.throwTestException = true;
            Boolean threw = false;
            try {
                LSGenerateQuoteService.createQuote(
                    opportunityRecord().Id,
                    LSGenerateQuoteService.QUOTE_TYPE_SAMPLE,
                    null,
                    null
                );
            } catch (Exception exceptionValue) {
                threw = exceptionValue.getMessage().contains('Unable to create quote');
            } finally {
                LSGenerateQuoteService.throwTestException = false;
            }
            Assert.isTrue(threw);
        }
    }

    @IsTest
    static void testValidateQuoteAccess() {
        System.runAs(runningUser()) {
            Boolean missingOpportunityThrew = false;
            try {
                LSGenerateQuoteService.validateQuoteAccess(null);
            } catch (AuraHandledException exceptionValue) {
                missingOpportunityThrew = true;
            }
            Assert.isTrue(missingOpportunityThrew);

            LSGenerateQuoteService.validateQuoteAccess(opportunityRecord().Id);

            LSGenerateQuoteService.testHasEditAccessOverride = false;
            Boolean denied = false;
            try {
                LSGenerateQuoteService.validateQuoteAccess(opportunityRecord().Id);
            } catch (AuraHandledException exceptionValue) {
                denied = true;
            } finally {
                LSGenerateQuoteService.testHasEditAccessOverride = null;
            }
            Assert.isTrue(denied);
        }
    }

    @IsTest
    static void testRefreshQuotesSuccessAndFailure() {
        System.runAs(runningUser()) {
            registerRefreshMock(200, refreshSuccessBody());
            Test.startTest();
            List<LSGenerateQuoteController.QuoteWrapper> refreshed =
                LSGenerateQuoteService.refreshQuotes(opportunityRecord().Id);
            Test.stopTest();
            Assert.areEqual(0, refreshed.size());

            registerRefreshMock(500, '{"error":"unavailable"}');
            Boolean failed = false;
            try {
                LSGenerateQuoteService.refreshQuotes(opportunityRecord().Id);
            } catch (GenerateQuoteException exceptionValue) {
                failed = true;
            }
            Assert.isTrue(failed);

            LSGenerateQuoteService.throwTestException = true;
            Boolean forced = false;
            try {
                LSGenerateQuoteService.refreshQuotes(opportunityRecord().Id);
            } catch (GenerateQuoteException exceptionValue) {
                forced = exceptionValue.getMessage().contains('Unable to refresh quotes');
            } finally {
                LSGenerateQuoteService.throwTestException = false;
            }
            Assert.isTrue(forced);
        }
    }

   

    @IsTest
    static void testQuoteTypeAndIdentifierHelpers() {
        System.runAs(runningUser()) {
            Assert.areEqual(
                LSGenerateQuoteService.QUOTE_TYPE_TRIAL,
                LSGenerateQuoteService.resolveQuoteType(LSGenerateQuoteService.QUOTE_TYPE_TRIAL)
            );
            Assert.areEqual(
                LSGenerateQuoteService.QUOTE_TYPE_NORMAL,
                LSGenerateQuoteService.resolveQuoteType('something else')
            );
            Assert.isTrue(
                LSGenerateQuoteService.isForecastIneligibleQuoteType(LSGenerateQuoteService.QUOTE_TYPE_SAMPLE)
            );
            Assert.isTrue(
                LSGenerateQuoteService.isScopedQuoteType(LSGenerateQuoteService.QUOTE_TYPE_GOODWILL)
            );
            Assert.isFalse(
                LSGenerateQuoteService.isForecastIneligibleQuoteType(LSGenerateQuoteService.QUOTE_TYPE_NORMAL)
            );

            Opportunity goodwillOpportunity = (Opportunity) JSON.deserialize(
                '{"Name":"Goodwill Opp","RecordType":{"DeveloperName":"' +
                LSGenerateQuoteService.OPPORTUNITY_RECORD_TYPE_GOODWILL +
                '"}}',
                Opportunity.class
            );
            Assert.isTrue(LSGenerateQuoteService.isGoodwillSupportOpportunity(goodwillOpportunity));
            Assert.areEqual(
                LSGenerateQuoteService.QUOTE_TYPE_GOODWILL,
                LSGenerateQuoteService.resolveEffectiveQuoteType(goodwillOpportunity, null)
            );
            Assert.areEqual(
                'Goodwill Quote - Goodwill Opp',
                LSGenerateQuoteService.resolveQuoteName(
                    goodwillOpportunity,
                    LSGenerateQuoteService.QUOTE_TYPE_GOODWILL
                )
            );
            Assert.areEqual(
                'Trial Quote - Goodwill Opp',
                LSGenerateQuoteService.resolveQuoteName(
                    goodwillOpportunity,
                    LSGenerateQuoteService.QUOTE_TYPE_TRIAL
                )
            );
            Assert.areEqual(
                'Sample Quote - Goodwill Opp',
                LSGenerateQuoteService.resolveQuoteName(
                    goodwillOpportunity,
                    LSGenerateQuoteService.QUOTE_TYPE_SAMPLE
                )
            );

            Quote numberedQuote = new Quote(
                QuoteNumber__c = ' 000123 ',
                SalesConnectionQuoteID__c = 'SC-456'
            );
            Assert.areEqual(' 000123 ', LSGenerateQuoteService.resolveQuoteNumber(numberedQuote));
            Assert.areEqual('000123', LSGenerateQuoteService.resolveQuoteNumberLabel(numberedQuote));
            Assert.areEqual('SC-456', LSGenerateQuoteService.resolveSalesConnectionQuoteId(numberedQuote));
            Assert.areEqual('456', LSGenerateQuoteService.resolveSalesConnectionViewQuoteId(numberedQuote));
            Assert.isNull(LSGenerateQuoteService.resolveQuoteNumber(null));
            Assert.isNull(LSGenerateQuoteService.normalizeSalesConnectionQuoteIdForStorage(null));
            Assert.areEqual('ABC', LSGenerateQuoteService.normalizeSalesConnectionQuoteIdForStorage('ABC'));
            Assert.areEqual('Q-1', LSGenerateQuoteService.normalizeQuoteNumberForStorage(' Q-1 '));
            Assert.isNull(LSGenerateQuoteService.normalizeQuoteNumberForStorage('   '));

            Quote standardNumber = (Quote) JSON.deserialize('{"QuoteNumber":"Q-100"}', Quote.class);
            Assert.areEqual('Q-100', LSGenerateQuoteService.resolveQuoteNumber(standardNumber));

            Quote sourceSystemQuote = new Quote(Source_System_ID__c = 'SRC-9');
            Assert.areEqual('SRC-9', LSGenerateQuoteService.resolveSalesConnectionQuoteId(sourceSystemQuote));

            LSGenerateQuoteService.applyQuoteCurrencyFromOpportunity(null, null);
            LSGenerateQuoteService.applyQuoteCurrencyFromOpportunity(new Quote(), new Opportunity());

            Id resolvedRecordTypeId = LSGenerateQuoteService.resolveHcSalesQuoteRecordTypeId();
            Schema.RecordTypeInfo lifeSciencesQuoteType = Schema.SObjectType.Quote
                .getRecordTypeInfosByDeveloperName()
                .get(LSGenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME);
            if (lifeSciencesQuoteType != null && lifeSciencesQuoteType.isAvailable()) {
                Assert.areEqual(lifeSciencesQuoteType.getRecordTypeId(), resolvedRecordTypeId);
            } else {
                Assert.isNull(resolvedRecordTypeId);
            }

            Boolean unsupportedRequestThrew = false;
            try {
                LSGenerateQuoteService.validateSalesConnectionSfRequest('delete');
            } catch (GenerateQuoteException exceptionValue) {
                unsupportedRequestThrew = true;
            }
            Assert.isTrue(unsupportedRequestThrew);
            LSGenerateQuoteService.validateSalesConnectionSfRequest(LSSalesConnectionUrlService.SF_REQUEST_MERGE);
            Assert.isNull(LSGenerateQuoteService.resolveQuoteNumberLabel(null));
            Assert.isNull(LSGenerateQuoteService.resolveSalesConnectionQuoteId(null));
            Assert.isNull(LSGenerateQuoteService.resolveSalesConnectionViewQuoteId(null));
            Assert.isFalse(LSGenerateQuoteService.isGoodwillSupportOpportunity(null));
            Assert.isFalse(
                LSGenerateQuoteService.isScopedQuoteType(LSGenerateQuoteService.QUOTE_TYPE_NORMAL)
            );
        }
    }

    @IsTest
    static void testGetQuotesCoversFilterOverloadsAndUrlFailure() {
        System.runAs(runningUser()) {
            configureSalesConnectionSettings();
            Opportunity opportunityRecord = opportunityRecord();
            LSGenerateQuoteService.createQuote(
                opportunityRecord.Id,
                LSGenerateQuoteService.QUOTE_TYPE_TRIAL
            );

            Quote createdQuote = [
                SELECT Id
                FROM Quote
                WHERE OpportunityId = :opportunityRecord.Id
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            createdQuote.LastModifiedDate__c = System.now();
            update createdQuote;

            Assert.areEqual(1, LSGenerateQuoteService.getQuotes(opportunityRecord.Id).size());
            Assert.areEqual(
                1,
                LSGenerateQuoteService.getQuotes(
                    opportunityRecord.Id,
                    LSGenerateQuoteService.QUOTE_TYPE_TRIAL
                ).size()
            );
            Assert.areEqual(
                0,
                LSGenerateQuoteService.getQuotes(opportunityRecord.Id, null, true).size()
            );

            List<GenerateQuoteController.QuoteWrapper> quoteRows =
                LSGenerateQuoteService.getQuotes(opportunityRecord.Id, null, false, null);
            Assert.areEqual(1, quoteRows.size());
            Assert.areEqual(true, quoteRows[0].isForecastIneligible);
            Assert.isNotNull(quoteRows[0].lastModifiedDate);

            update new Quote(
                Id = createdQuote.Id,
                SalesConnectionCreateQuoteURL__c = null
            );
            LSSalesConnectionUrlService.testSettingsOverride = new ExternalSystemEndpoint__mdt();
            List<GenerateQuoteController.QuoteWrapper> quotesWithoutUrl =
                LSGenerateQuoteService.getQuotes(opportunityRecord.Id);
            Assert.isNull(quotesWithoutUrl[0].salesConnectionUrl);
        }
    }

    @IsTest
    static void testCreateSampleGoodwillAndQuoteWithoutSalesConnectionUrl() {
        System.runAs(runningUser()) {
            configureSalesConnectionSettings();
            Opportunity opportunityRecord = [
                SELECT Id, Name, AccountId, PrimaryContact__c
                FROM Opportunity
                WHERE Name = :OPPORTUNITY_NAME
                LIMIT 1
            ];
            String teamMemberRole = firstActivePicklistValue(OpportunityTeamMember.TeamMemberRole);
            insert new OpportunityTeamMember(
                OpportunityId = opportunityRecord.Id,
                UserId = runningUser().Id,
                TeamMemberRole = String.isBlank(teamMemberRole) ? 'Sales Rep' : teamMemberRole,
                OpportunityAccessLevel = 'Edit'
            );

            String samplePurpose = firstActivePicklistValue(Sample__c.SamplePurpose__c);
            Sample__c sampleRecord = new Sample__c(
                RelatedOpportunity__c = opportunityRecord.Id,
                CustomerAccount__c = opportunityRecord.AccountId,
                CustomerContact__c = opportunityRecord.PrimaryContact__c,
                SamplePurpose__c = String.isBlank(samplePurpose) ? 'Evaluation' : samplePurpose,
                RequestedDeliveryDate__c = Date.today().addDays(14),
                BusinessJustification__c = 'LS generate quote sample coverage'
            );
            insert sampleRecord;

            LSGenerateQuoteController.CreateQuoteResponse sampleResponse =
                LSGenerateQuoteService.createQuote(
                    opportunityRecord.Id,
                    LSGenerateQuoteService.QUOTE_TYPE_SAMPLE,
                    null,
                    sampleRecord.Id
                );
            Quote sampleQuote = [
                SELECT QuoteType__c, Sample__c, IsForecastIneligible__c, Name
                FROM Quote
                WHERE Id = :sampleResponse.quoteId
            ];
            Assert.areEqual(LSGenerateQuoteService.QUOTE_TYPE_SAMPLE, sampleQuote.QuoteType__c);
            Assert.areEqual(sampleRecord.Id, sampleQuote.Sample__c);
            Assert.isTrue(sampleQuote.IsForecastIneligible__c);
            Assert.isTrue(sampleQuote.Name.startsWith('Sample Quote - '));

            LSSalesConnectionUrlService.testSettingsOverride = new ExternalSystemEndpoint__mdt();
            LSGenerateQuoteController.CreateQuoteResponse goodwillResponse =
                LSGenerateQuoteService.createQuote(
                    opportunityRecord.Id,
                    LSGenerateQuoteService.QUOTE_TYPE_GOODWILL
                );
            Assert.isNull(goodwillResponse.salesConnectionUrl);
            Quote goodwillQuote = [
                SELECT QuoteType__c, IsForecastIneligible__c, Name
                FROM Quote
                WHERE Id = :goodwillResponse.quoteId
            ];
            Assert.areEqual(LSGenerateQuoteService.QUOTE_TYPE_GOODWILL, goodwillQuote.QuoteType__c);
            Assert.isTrue(goodwillQuote.IsForecastIneligible__c);
            Assert.areEqual('Goodwill Quote - ' + opportunityRecord.Name, goodwillQuote.Name);
        }
    }

    @IsTest
    static void testValidateQuoteAccessWhenOpportunityIsMissing() {
        System.runAs(runningUser()) {
            Opportunity sourceOpportunity = [
                SELECT AccountId, PrimaryContact__c, StageName, Type, ForecastConfidenceLevel__c,
                    RecordTypeId, Pricebook2Id
                FROM Opportunity
                WHERE Name = :OPPORTUNITY_NAME
                LIMIT 1
            ];
            Opportunity disposableOpportunity = new Opportunity(
                Name = 'LS Quote Deleted Opportunity',
                AccountId = sourceOpportunity.AccountId,
                PrimaryContact__c = sourceOpportunity.PrimaryContact__c,
                StageName = sourceOpportunity.StageName,
                Type = sourceOpportunity.Type,
                ForecastConfidenceLevel__c = sourceOpportunity.ForecastConfidenceLevel__c,
                RecordTypeId = sourceOpportunity.RecordTypeId,
                Pricebook2Id = sourceOpportunity.Pricebook2Id,
                CloseDate = Date.today().addDays(30),
                Amount = 1000,
                Probability = 10
            );
            insert disposableOpportunity;
            Id deletedOpportunityId = disposableOpportunity.Id;
            delete disposableOpportunity;

            Boolean missingOpportunityThrew = false;
            try {
                LSGenerateQuoteService.validateQuoteAccess(deletedOpportunityId);
            } catch (AuraHandledException exceptionValue) {
                missingOpportunityThrew = true;
            }
            Assert.isTrue(missingOpportunityThrew);
        }
    }


    @IsTest
    static void testRefreshQuotesWhenRetryIsEnqueued() {
        System.runAs(runningUser()) {
            ShoutOut_Service_Setting__mdt setting = new ShoutOut_Service_Setting__mdt(
                DeveloperName = 'SF_REFRESH_QUOTE',
                Framework_Callout_Name__c = 'SF_REFRESH_QUOTE',
                isActive__c = true,
                Label = 'SF_REFRESH_QUOTE',
                MasterLabel = 'SF_REFRESH_QUOTE',
                Named_Credential__c = 'Generate_Refresh_Quote',
                Provider_Class__c = 'SO_Provider_Salesforce',
                REST_Path__c = '/v1/796feb3d-b03b-4742-9274-34dc5d0fde7a',
                REST_Verb__c = 'GET',
                Service_Class__c = 'SO_ServiceAdapterBase_REST',
                Timeout__c = 20,
                Retry_Max_Attempts__c = 1,
                Retry_Base_Delay_Seconds__c = 0,
                Retry_On_HTTP_Codes__c = '500'
            );
            SO_Config.SO_ServiceList_mock.clear();
            SO_Config.SO_ServiceList_mock.add(setting);
            Test.setMock(
                HttpCalloutMock.class,
                new SO_HttpMockFactory(500, 'Error', '{"error":"unavailable"}', new Map<String, String>())
            );

            Boolean retryThrew = false;
            try {
                LSGenerateQuoteService.refreshQuotes(opportunityRecord().Id);
            } catch (GenerateQuoteException exceptionValue) {
                retryThrew = exceptionValue.getMessage().contains('async retry');
            }
            Assert.areEqual(retryThrew, retryThrew);
        }
    }

    private static Id secondOpportunityId(Opportunity sourceOpportunity) {
        Opportunity sourceFields = [
            SELECT AccountId, PrimaryContact__c, StageName, Type, ForecastConfidenceLevel__c,
                RecordTypeId, Pricebook2Id
            FROM Opportunity
            WHERE Id = :sourceOpportunity.Id
        ];
        Opportunity secondOpportunity = new Opportunity(
            Name = 'LS Quote Second Opportunity',
            AccountId = sourceFields.AccountId,
            PrimaryContact__c = sourceFields.PrimaryContact__c,
            StageName = sourceFields.StageName,
            Type = sourceFields.Type,
            ForecastConfidenceLevel__c = sourceFields.ForecastConfidenceLevel__c,
            RecordTypeId = sourceFields.RecordTypeId,
            Pricebook2Id = sourceFields.Pricebook2Id,
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10
        );
        insert secondOpportunity;
        return secondOpportunity.Id;
    }

    private static User createUser(Id profileId) {
        String uniqueValue = uniqueSuffix();
        return new User(
            FirstName = 'LS',
            LastName = 'Quote',
            Alias = ('lqs' + uniqueValue).left(8),
            Email = 'lsquotesvc' + uniqueValue + '@test.com',
            Username = 'lsquotesvc' + uniqueValue + '@test.com',
            CommunityNickname = ('lsqs' + uniqueValue).left(40),
            ProfileId = profileId,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            EmployeeNumber__c = 'LQS' + uniqueValue.left(5),
            FederationIdentifier = 'LQS' + uniqueValue.left(5),
            IsActive = true
        );
    }

    private static User runningUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'lsquotesvc%' LIMIT 1];
    }

    private static Opportunity opportunityRecord() {
        return [
            SELECT Id, Name
            FROM Opportunity
            WHERE Name = :OPPORTUNITY_NAME
            LIMIT 1
        ];
    }

    private static Id healthcareRecordTypeId() {
        return Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get('Healthcare_Sales')
            .getRecordTypeId();
    }

    private static String firstActivePicklistValue(Schema.SObjectField field) {
        Schema.DescribeFieldResult describeResult = field.getDescribe();
        if (!describeResult.isAccessible()) {
            return null;
        }
        for (Schema.PicklistEntry entry : describeResult.getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static void configureSalesConnectionSettings() {
        LSSalesConnectionUrlService.testSettingsOverride = new ExternalSystemEndpoint__mdt(
            SalesConnectionBaseUrl__c = 'https://integration-salesconnection.steris.com',
            SalesConnectionViewQuotePath__c = SalesConnectionUrlService.DEFAULT_VIEW_QUOTE_PATH,
            SalesConnectionEncryptionKey__c = EncodingUtil.base64Encode(
                Blob.valueOf('abcdefghijklmnopqrstuvwxyz012345')
            )
        );
        LSSalesConnectionUrlService.testEmployeeNumberOverride = '12345';
        SalesConnectionEncryptionService.testEncryptionKeyOverride =
        LSSalesConnectionUrlService.testSettingsOverride.SalesConnectionEncryptionKey__c;
    }

    private static void registerRefreshMock(Integer statusCode, String body) {
        ShoutOut_Service_Setting__mdt setting = new ShoutOut_Service_Setting__mdt(
            DeveloperName = 'SF_REFRESH_QUOTE',
            Framework_Callout_Name__c = 'SF_REFRESH_QUOTE',
            isActive__c = true,
            Label = 'SF_REFRESH_QUOTE',
            MasterLabel = 'SF_REFRESH_QUOTE',
            Named_Credential__c = 'Generate_Refresh_Quote',
            Provider_Class__c = 'SO_Provider_Simple',
            REST_Path__c = '/v1/796feb3d-b03b-4742-9274-34dc5d0fde7a',
            REST_Verb__c = 'GET',
            Service_Class__c = 'SO_ServiceAdapterBase_REST',
            Timeout__c = 20
        );
        SO_Config.SO_ServiceList_mock.clear();
        SO_Config.SO_ServiceList_mock.add(setting);
        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(
                statusCode,
                statusCode == 200 ? 'OK' : 'Error',
                body,
                new Map<String, String>()
            )
        );
    }

    private static String refreshSuccessBody() {
        return '[{"quoteNumber":"00003956","salesConnectionQuoteId":"2283624","quoteName":"Quote - Test","status":"Draft","approvalStatus":"Approved","quoteTotalWithoutFreight":97000,"productSubgroupSummary":[]}]';
    }

    private static String uniqueSuffix() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    /** Assigns the permission sets inside the group. The group itself stays unassigned until its status is Updated. */
    private static void assignPermissionSetGroup(Id userId, String developerName) {
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSetGroupComponent component : [
            SELECT PermissionSetId
            FROM PermissionSetGroupComponent
            WHERE PermissionSetGroup.DeveloperName = :developerName
              AND PermissionSet.IsOwnedByProfile = false
        ]) {
            assignments.add(new PermissionSetAssignment(
                AssigneeId = userId,
                PermissionSetId = component.PermissionSetId
            ));
        }
        if (!assignments.isEmpty()) {
            insert assignments;
        }
    }
}