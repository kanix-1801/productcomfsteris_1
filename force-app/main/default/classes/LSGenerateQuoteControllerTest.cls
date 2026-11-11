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
            assignPermissionSetGroup(runningUser.Id, 'SalesFieldRepAccountManagerPSG');
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
            LSGenerateQuoteController.CreateQuoteResponse response =
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

    @IsTest
    static void testCopyAndMergeQuote() {
        System.runAs(runningUser()) {
            configureSalesConnectionSettings();
            Id opportunityId = opportunityRecord().Id;

            Test.startTest();
            LSGenerateQuoteController.CreateQuoteResponse copyResponse =
                LSGenerateQuoteController.copyQuote(opportunityId);
            LSGenerateQuoteController.CreateQuoteResponse mergeResponse =
                LSGenerateQuoteController.mergeQuote(opportunityId);
            Test.stopTest();

            Assert.isNotNull(copyResponse.quoteId);
            Assert.isNotNull(mergeResponse.quoteId);
            Assert.areEqual(2, [SELECT COUNT() FROM Quote WHERE OpportunityId = :opportunityId]);
        }
    }

    @IsTest
    static void testCopyAndMergeWrapServiceFailure() {
        System.runAs(runningUser()) {
            LSGenerateQuoteService.throwTestException = true;
            Boolean copyThrew = false;
            Boolean mergeThrew = false;
            try {
                LSGenerateQuoteController.copyQuote(opportunityRecord().Id);
            } catch (AuraHandledException exceptionValue) {
                copyThrew = true;
            }
            try {
                LSGenerateQuoteController.mergeQuote(opportunityRecord().Id);
            } catch (AuraHandledException exceptionValue) {
                mergeThrew = true;
            } finally {
                LSGenerateQuoteService.throwTestException = false;
            }
            Assert.isTrue(copyThrew);
            Assert.isTrue(mergeThrew);
        }
    }

    @IsTest
    static void testCreateQuoteKeepsExplicitQuoteType() {
        System.runAs(runningUser()) {
            configureSalesConnectionSettings();
            Id opportunityId = opportunityRecord().Id;

            Test.startTest();
            LSGenerateQuoteController.CreateQuoteResponse response =
                LSGenerateQuoteController.createQuote(
                    opportunityId,
                    LSGenerateQuoteService.QUOTE_TYPE_TRIAL,
                    null,
                    null
                );
            Test.stopTest();

            Assert.areEqual(
                LSGenerateQuoteService.QUOTE_TYPE_TRIAL,
                [SELECT QuoteType__c FROM Quote WHERE Id = :response.quoteId].QuoteType__c
            );
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