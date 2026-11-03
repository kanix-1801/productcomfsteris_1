/**
 * @description Tests for LSGenerateQuoteController.
 */
@IsTest
private class LSGenerateQuoteControllerTest {
    private static final String OPPORTUNITY_NAME = 'LS Quote Controller Opportunity';

    @TestSetup
    static void setupData() {
        Profile sysAdminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User runningUser = createUser(sysAdminProfile.Id);
        insert runningUser;

        System.runAs(runningUser) {
            PermissionSetGroup psGroup = [
                SELECT Id
                FROM PermissionSetGroup
                WHERE DeveloperName = 'SalesFieldRepAccountManagerPSG'
                LIMIT 1
            ];
            insert new PermissionSetAssignment(
                AssigneeId = runningUser.Id,
                PermissionSetGroupId = psGroup.Id
            );
        }

        Id pricebookId = Test.getStandardPricebookId();
        Product2 productRecord = new Product2(
            Name = 'LS Quote Controller Product',
            ProductCode = 'LSQC-001',
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
            Name = 'LS Quote Controller Account ' + suffix,
            SourceSystemID__c = 'LSQC-' + suffix,
            OracleAddressId__c = '638265'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'LS',
            LastName = 'Quote Contact',
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
    static void testIsOpportunityOnHold() {
        System.runAs(runningUser()) {
            Assert.isFalse(LSGenerateQuoteController.isOpportunityOnHold(null));

            Opportunity opportunityRecord = opportunityRecord();
            Assert.isFalse(LSGenerateQuoteController.isOpportunityOnHold(opportunityRecord.Id));

            opportunityRecord.OnHold__c = true;
            update opportunityRecord;
            Assert.isTrue(LSGenerateQuoteController.isOpportunityOnHold(opportunityRecord.Id));
        }
    }

    @IsTest
    static void testValidateQuoteAccessRequiresOpportunityAndAllowsOwner() {
        System.runAs(runningUser()) {
            Boolean missingIdThrew = false;
            try {
                LSGenerateQuoteController.validateQuoteAccess(null);
            } catch (AuraHandledException exceptionValue) {
                missingIdThrew = true;
            }
            Assert.isTrue(missingIdThrew);

            LSGenerateQuoteController.validateQuoteAccess(opportunityRecord().Id);
        }
    }

    @IsTest
    static void testValidateQuoteAccessDeniesWhenOverrideIsFalse() {
        System.runAs(runningUser()) {
            LSGenerateQuoteService.testHasEditAccessOverride = false;
            Boolean denied = false;
            try {
                LSGenerateQuoteController.validateQuoteAccess(opportunityRecord().Id);
            } catch (AuraHandledException exceptionValue) {
                denied = true;
            } finally {
                LSGenerateQuoteService.testHasEditAccessOverride = null;
            }
            Assert.isTrue(denied);
        }
    }

    @IsTest
    static void testCreateQuoteUsesNormalTypeWhenQuoteTypeIsBlank() {
        System.runAs(runningUser()) {
            configureSalesConnectionSettings();
            Opportunity opportunityRecord = opportunityRecord();

            Test.startTest();
            GenerateQuoteController.CreateQuoteResponse response =
                LSGenerateQuoteController.createQuote(opportunityRecord.Id, '   ', null, null);
            Test.stopTest();

            Assert.isNotNull(response.quoteId);
            Quote createdQuote = [
                SELECT Name, Status, QuoteType__c, RecordTypeId, RecordType.DeveloperName
                FROM Quote
                WHERE Id = :response.quoteId
            ];
            Assert.areEqual(LSGenerateQuoteService.QUOTE_STATUS_OPEN, createdQuote.Status);
            Assert.areEqual(LSGenerateQuoteService.QUOTE_TYPE_NORMAL, createdQuote.QuoteType__c);
            Assert.areEqual('Quote - ' + opportunityRecord.Name, createdQuote.Name);
            if (createdQuote.RecordTypeId != null) {
                Assert.areEqual(
                    LSGenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME,
                    createdQuote.RecordType.DeveloperName
                );
            }
        }
    }

    @IsTest
    static void testCreateQuoteWrapsServiceFailure() {
        System.runAs(runningUser()) {
            LSGenerateQuoteService.throwTestException = true;
            Boolean threw = false;
            try {
                LSGenerateQuoteController.createQuote(opportunityRecord().Id, null, null, null);
            } catch (AuraHandledException exceptionValue) {
                threw = true;
            } finally {
                LSGenerateQuoteService.throwTestException = false;
            }
            Assert.isTrue(threw);
        }
    }

    private static User createUser(Id profileId) {
        String uniqueValue = uniqueSuffix();
        return new User(
            FirstName = 'LS',
            LastName = 'Quote',
            Alias = ('lsq' + uniqueValue).left(8),
            Email = 'lsquotectrl' + uniqueValue + '@test.com',
            Username = 'lsquotectrl' + uniqueValue + '@test.com',
            CommunityNickname = ('lsqc' + uniqueValue).left(40),
            ProfileId = profileId,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            EmployeeNumber__c = 'LQC' + uniqueValue.left(5),
            FederationIdentifier = 'LQC' + uniqueValue.left(5),
            IsActive = true
        );
    }

    private static User runningUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'lsquotectrl%' LIMIT 1];
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
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
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

    private static String uniqueSuffix() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }
}