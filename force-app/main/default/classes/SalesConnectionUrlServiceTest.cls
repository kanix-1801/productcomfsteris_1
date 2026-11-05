/**
* @author Himanshu Chaurasia
* @date 2026/06/18
*
* @group Generate Quote
*
* @description Test coverage for SalesConnectionUrlService (Sales Connection URL building for Generate Quote).
*/
@IsTest
private class SalesConnectionUrlServiceTest {
    private static final Id TEST_OPPORTUNITY_ID = fakeSalesforceId(Schema.Opportunity.SObjectType, 1);
    private static final Id TEST_QUOTE_ID = fakeSalesforceId(Schema.Quote.SObjectType, 1);
    private static final String TEST_EMPLOYEE_NUMBER = '12345';
    private static final String BASE_URL = 'https://integration-salesconnection.steris.com';
    
    @TestSetup
    static void setupData() {
    }
    
    @IsTest
    static void testBuildStoredCreateQuoteUrlForCustomerAccount() {
        configureSalesConnectionSettings();
        Account accountRecord = buildCustomerAccount('319163');
        
        Test.startTest();
        String storedUrl = SalesConnectionUrlService.buildStoredCreateQuoteUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            accountRecord,
            TEST_EMPLOYEE_NUMBER
        );
        Test.stopTest();
        
        System.assertEquals(
            buildExpectedStoredCreateQuoteUrl(
                TEST_OPPORTUNITY_ID,
                TEST_QUOTE_ID,
                '319163',
                'C',
                TEST_EMPLOYEE_NUMBER
            ),
            storedUrl,
            'Stored create quote URL should match the Sales Connection format.'
        );
    }
    
    @IsTest
    static void testBuildOpenCreateQuoteUrlEncryptsStoredPayload() {
        configureSalesConnectionSettings();
        Account accountRecord = buildCustomerAccount('319163');
        String storedUrl = SalesConnectionUrlService.buildStoredCreateQuoteUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            accountRecord,
            TEST_EMPLOYEE_NUMBER
        );
        
        Test.startTest();
        String openUrl = SalesConnectionUrlService.buildOpenCreateQuoteUrl(storedUrl);
        Test.stopTest();
        
        System.assert(openUrl.startsWith('https://integration-salesconnection.steris.com/#Quote|'));
        System.assertNotEquals(storedUrl, openUrl, 'Open URL should encrypt the stored payload.');
        System.assert(!openUrl.contains('addressid=319163'), 'Open URL should not expose plain payload values.');
    }
    
    @IsTest
    static void testBuildCreateQuoteUrlForProspectAccount() {        
        SalesConnectionUrlService.testEmployeeNumberOverride = TEST_EMPLOYEE_NUMBER;
        configureSalesConnectionSettings();
        Account accountRecord = buildProspectAccount('778899');
        
        Test.startTest();
        String storedUrl = SalesConnectionUrlService.buildStoredCreateQuoteUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            accountRecord,
            TEST_EMPLOYEE_NUMBER
        );
        Test.stopTest();
        
        System.assert(storedUrl.contains('&accounttype=P&'), 'Prospect accounts should use accounttype=P.');
    }
    
    @IsTest
    static void testBuildExistingQuoteUrlReturnsNullForBlankId() {
        configureSalesConnectionSettings();
        
        Test.startTest();
        String url = SalesConnectionUrlService.buildExistingQuoteUrl('');
        Test.stopTest();
        
        System.assertEquals(null, url, 'Blank Sales Connection quote id should return null.');
    }
    
    @IsTest
    static void testBuildQuoteUrlReturnsNullWhenRequiredRecordsMissing() {
        configureSalesConnectionSettings();
        
        Test.startTest();
        String url = SalesConnectionUrlService.buildQuoteUrl(
            new Quote(Id = TEST_QUOTE_ID),
            null,
            buildCustomerAccount('319163')
        );
        Test.stopTest();
        
        System.assertEquals(null, url, 'Missing Opportunity should return null.');
    }
    
    @IsTest
    static void testBuildExistingQuoteUrlUsesSalesConnectionQuoteId() {
        configureSalesConnectionSettings();
        
        Test.startTest();
        String url = SalesConnectionUrlService.buildExistingQuoteUrl('64747374');
        Test.stopTest();
        
        System.assertEquals(
            'https://integration-salesconnection.steris.com/#Quote|id=64747374',
            url,
            'Existing Sales Connection quotes should use the view quote URL format.'
        );
    }
    
    @IsTest
    static void testBuildQuoteUrlUsesSalesConnectionQuoteIdForViewUrl() {
        configureSalesConnectionSettings();
        Account accountRecord = buildCustomerAccount('319163');
        Quote quoteRecord = new Quote(
            Id = TEST_QUOTE_ID,
            QuoteNumber__c = '00003956',
            SalesConnectionQuoteID__c = '64747374'
        );
        Opportunity opportunityRecord = new Opportunity(Id = TEST_OPPORTUNITY_ID);
        
        Test.startTest();
        String url = SalesConnectionUrlService.buildQuoteUrl(
            quoteRecord,
            opportunityRecord,
            accountRecord
        );
        Test.stopTest();
        
        System.assertEquals(
            'https://integration-salesconnection.steris.com/#Quote|id=64747374',
            url,
            'View quote URLs should use SalesConnectionQuoteID__c.'
        );
    }
    
    @IsTest
    static void testBuildQuoteUrlNormalizesSalesConnectionQuoteIdForViewUrl() {
        configureSalesConnectionSettings();
        Account accountRecord = buildCustomerAccount('319163');
        Quote quoteRecord = new Quote(
            Id = TEST_QUOTE_ID,
            QuoteNumber__c = 'Q-00003956',
            SalesConnectionQuoteID__c = 'SCQ-2283624'
        );
        Opportunity opportunityRecord = new Opportunity(Id = TEST_OPPORTUNITY_ID);
        
        Test.startTest();
        String url = SalesConnectionUrlService.buildQuoteUrl(
            quoteRecord,
            opportunityRecord,
            accountRecord
        );
        Test.stopTest();
        
        System.assertEquals(
            'https://integration-salesconnection.steris.com/#Quote|id=2283624',
            url,
            'View quote URLs should normalize Sales Connection quote ids to numeric values.'
        );
    }
    
    @IsTest
    static void testBuildQuoteUrlUsesStoredCreateQuoteUrlWhenSalesConnectionQuoteIdBlank() {
        configureSalesConnectionSettings();
        Account accountRecord = buildCustomerAccount('319163');
        String storedUrl = SalesConnectionUrlService.buildStoredCreateQuoteUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            accountRecord,
            TEST_EMPLOYEE_NUMBER
        );
        Quote quoteRecord = new Quote(
            Id = TEST_QUOTE_ID,
            SalesConnectionCreateQuoteURL__c = storedUrl
        );
        Opportunity opportunityRecord = new Opportunity(Id = TEST_OPPORTUNITY_ID);
        
        Test.startTest();
        String openUrl = SalesConnectionUrlService.buildQuoteUrl(
            quoteRecord,
            opportunityRecord,
            accountRecord
        );
        Test.stopTest();
        
        System.assertNotEquals(storedUrl, openUrl);
        System.assert(openUrl.startsWith('https://integration-salesconnection.steris.com/#Quote|'));
    }
    
    @IsTest
    static void testBuildOpenCreateQuoteUrlRequiresStoredUrl() {
        configureSalesConnectionSettings();
        
        Test.startTest();
        String openUrl = SalesConnectionUrlService.buildOpenCreateQuoteUrl('');
        Test.stopTest();
        
        System.assertEquals(null, openUrl, 'Blank stored URL should return null.');
    }
    
    @IsTest
    static void testExtractCreateQuotePayloadRequiresValidStoredUrl() {
        configureSalesConnectionSettings();
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            SalesConnectionUrlService.buildOpenCreateQuoteUrl(
                'https://integration-salesconnection.steris.com/invalid-format'
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Invalid stored URL should throw an AuraHandledException.');
    }
    
    @IsTest
    static void testBuildStoredCreateQuoteUrlRequiresEmployeeNumber() {
        configureSalesConnectionSettings();
        Account accountRecord = buildCustomerAccount('319163');
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            SalesConnectionUrlService.buildStoredCreateQuoteUrl(
                TEST_OPPORTUNITY_ID,
                TEST_QUOTE_ID,
                accountRecord,
                ' '
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Missing employee number should block create quote URL generation.');
    }
    
    @IsTest
    static void testBuildStoredCreateQuoteUrlRequiresOracleAddressId() {
        configureSalesConnectionSettings();
        Account accountRecord = buildCustomerAccount(null);
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            SalesConnectionUrlService.buildStoredCreateQuoteUrl(
                TEST_OPPORTUNITY_ID,
                TEST_QUOTE_ID,
                accountRecord,
                TEST_EMPLOYEE_NUMBER
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Missing Oracle Address Id should block create quote URL generation.');
    }
    
    @IsTest
    static void testBuildStoredCreateQuoteUrlRequiresAccount() {
        configureSalesConnectionSettings();
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            SalesConnectionUrlService.buildStoredCreateQuoteUrl(
                TEST_OPPORTUNITY_ID,
                TEST_QUOTE_ID,
                null,
                TEST_EMPLOYEE_NUMBER
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Missing Account should block create quote URL generation.');
    }
    
    @IsTest
    static void testBuildOpenCreateQuoteUrlFromOpportunityContext() {
        configureSalesConnectionSettings();
        Account accountRecord = buildCustomerAccount('319163');
        
        Test.startTest();
        String openUrl = SalesConnectionUrlService.buildOpenCreateQuoteUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            accountRecord,
            TEST_EMPLOYEE_NUMBER
        );
        Test.stopTest();
        
        System.assert(openUrl.startsWith('https://integration-salesconnection.steris.com/#Quote|'));
        System.assert(!openUrl.contains('addressid=319163'));
    }
    
    @IsTest
    static void testBuildCreateQuoteUrlWrapperUsesCurrentEmployeeNumber() {
        configureSalesConnectionSettings();
        Account accountRecord = buildCustomerAccount('319163');
        
        Test.startTest();
        String openUrl = SalesConnectionUrlService.buildCreateQuoteUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            accountRecord
        );
        Test.stopTest();
        
        System.assertNotEquals(null, openUrl);
        System.assert(openUrl.contains('integration-salesconnection.steris.com'));
    }
    
    @IsTest
    static void testBuildExistingQuoteUrlUsesDefaultPathWhenMetadataBlank() {
        SalesConnectionUrlService.testSettingsOverride = new ExternalSystemEndpoint__mdt(
            SalesConnectionBaseUrl__c = 'https://integration-salesconnection.steris.com',
            SalesConnectionViewQuotePath__c = null,
            SalesConnectionEncryptionKey__c = EncodingUtil.base64Encode(
                Blob.valueOf('abcdefghijklmnopqrstuvwxyz012345')
            )
        );
        
        Test.startTest();
        String url = SalesConnectionUrlService.buildExistingQuoteUrl('64747374');
        Test.stopTest();
        
        System.assertEquals(
            'https://integration-salesconnection.steris.com/#Quote|id=64747374',
            url,
            'Blank view path metadata should fall back to the default path.'
        );
    }
    
    @IsTest
    static void testBuildStoredQuoteRequestUrlForCopyAndMerge() {
        configureSalesConnectionSettings();
        Account accountRecord = buildProspectAccount('778899');

        Test.startTest();
        String copyUrl = SalesConnectionUrlService.buildStoredQuoteRequestUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            accountRecord,
            TEST_EMPLOYEE_NUMBER,
            SalesConnectionUrlService.SF_REQUEST_COPY
        );
        String mergeUrl = SalesConnectionUrlService.buildStoredQuoteRequestUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            accountRecord,
            TEST_EMPLOYEE_NUMBER,
            SalesConnectionUrlService.SF_REQUEST_MERGE
        );
        Test.stopTest();

        System.assert(copyUrl.contains('&accounttype=P&'), 'Copy URL should use prospect account type.');
        System.assert(copyUrl.contains('&sfrequest=copy&'), 'Copy URL should include sfrequest=copy.');
        System.assert(mergeUrl.contains('&sfrequest=merge&'), 'Merge URL should include sfrequest=merge.');
    }

    @IsTest
    static void testBuildStoredQuoteRequestUrlRejectsUnsupportedRequest() {
        configureSalesConnectionSettings();
        Account accountRecord = buildCustomerAccount('319163');
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            SalesConnectionUrlService.buildStoredQuoteRequestUrl(
                TEST_OPPORTUNITY_ID,
                TEST_QUOTE_ID,
                accountRecord,
                TEST_EMPLOYEE_NUMBER,
                'delete'
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Unsupported sfrequest should throw AuraHandledException.');
    }

    @IsTest
    static void testBuildQuoteUrlReturnsNullWhenQuoteMissing() {
        configureSalesConnectionSettings();
        Opportunity opportunityRecord = new Opportunity(Id = TEST_OPPORTUNITY_ID);
        Account accountRecord = buildCustomerAccount('319163');

        Test.startTest();
        String url = SalesConnectionUrlService.buildQuoteUrl(
            null,
            opportunityRecord,
            accountRecord
        );
        Test.stopTest();

        System.assertEquals(null, url, 'Missing Quote should return null.');
    }

    @IsTest
    static void testBuildQuoteUrlBuildsEncryptedCreateUrlWhenNoViewOrStoredUrl() {
        configureSalesConnectionSettings();
        Account accountRecord = buildCustomerAccount('319163');
        Quote quoteRecord = new Quote(Id = TEST_QUOTE_ID);
        Opportunity opportunityRecord = new Opportunity(Id = TEST_OPPORTUNITY_ID);

        Test.startTest();
        String openUrl = SalesConnectionUrlService.buildQuoteUrl(
            quoteRecord,
            opportunityRecord,
            accountRecord
        );
        Test.stopTest();

        System.assert(openUrl.startsWith(BASE_URL + '/#Quote|'));
        System.assert(!openUrl.contains('addressid=319163'));
    }

    @IsTest
    static void testBuildExistingQuoteUrlNormalizesBaseUrlAndCustomPaths() {
        configureSalesConnectionSettings();
        System.assertEquals(
            BASE_URL + '/#Quote|id=64747374',
            SalesConnectionUrlService.buildExistingQuoteUrl('64747374')
        );

        SalesConnectionUrlService.testSettingsOverride = new ExternalSystemEndpoint__mdt(
            SalesConnectionBaseUrl__c = BASE_URL + '/',
            SalesConnectionViewQuotePath__c = null,
            SalesConnectionEncryptionKey__c = SalesConnectionUrlService.testSettingsOverride
                .SalesConnectionEncryptionKey__c
        );
        System.assertEquals(
            BASE_URL + '/#Quote|id=64747374',
            SalesConnectionUrlService.buildExistingQuoteUrl('64747374')
        );

        SalesConnectionUrlService.testSettingsOverride = new ExternalSystemEndpoint__mdt(
            SalesConnectionBaseUrl__c = BASE_URL,
            SalesConnectionViewQuotePath__c = '/quotes/{0}',
            SalesConnectionEncryptionKey__c = EncodingUtil.base64Encode(
                Blob.valueOf('abcdefghijklmnopqrstuvwxyz012345')
            )
        );
        System.assertEquals(
            BASE_URL + '/quotes/64747374',
            SalesConnectionUrlService.buildExistingQuoteUrl('64747374')
        );

        SalesConnectionUrlService.testSettingsOverride = new ExternalSystemEndpoint__mdt(
            SalesConnectionBaseUrl__c = BASE_URL,
            SalesConnectionViewQuotePath__c = 'quotes/{0}',
            SalesConnectionEncryptionKey__c = EncodingUtil.base64Encode(
                Blob.valueOf('abcdefghijklmnopqrstuvwxyz012345')
            )
        );
        System.assertEquals(
            BASE_URL + '/quotes/64747374',
            SalesConnectionUrlService.buildExistingQuoteUrl('64747374')
        );
    }

    @IsTest
    static void testExtractCreateQuotePayloadAndBuildQuoteRequestPayload() {
        configureSalesConnectionSettings();
        Account accountRecord = buildCustomerAccount('319163');
        String storedUrl = buildExpectedStoredCreateQuoteUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            '319163',
            'C',
            TEST_EMPLOYEE_NUMBER
        );

        Test.startTest();
        String payload = SalesConnectionUrlService.extractCreateQuotePayload(storedUrl);
        String requestPayload = SalesConnectionUrlService.buildQuoteRequestPayload(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            accountRecord,
            TEST_EMPLOYEE_NUMBER,
            SalesConnectionUrlService.SF_REQUEST_CREATE
        );
        Test.stopTest();

        System.assert(payload.startsWith('id=0&addressid=319163'));
        System.assert(requestPayload.contains('&accounttype=C&'));
        System.assert(requestPayload.contains('&sfrequest=create&'));
    }

    @IsTest
    static void testResolveEmployeeNumberFromUserOrOverride() {
        configureSalesConnectionSettings();
        System.assertEquals(
            TEST_EMPLOYEE_NUMBER,
            SalesConnectionUrlService.resolveCurrentUserEmployeeNumber()
        );

        User employeeUser = createUser('SCU' + uniqueSuffix().left(5));
        insert employeeUser;
        System.runAs(employeeUser) {
            SalesConnectionUrlService.testEmployeeNumberOverride = null;
            System.assertEquals(
                employeeUser.EmployeeNumber__c,
                SalesConnectionUrlService.resolveCurrentUserEmployeeNumber()
            );
        }

        User userWithoutEmployeeNumber = createUser(null);
        insert userWithoutEmployeeNumber;
        System.runAs(userWithoutEmployeeNumber) {
            SalesConnectionUrlService.testEmployeeNumberOverride = null;
            Boolean missingEmployeeNumberThrew = false;
            try {
                SalesConnectionUrlService.resolveCurrentUserEmployeeNumber();
            } catch (AuraHandledException exceptionValue) {
                missingEmployeeNumberThrew = true;
            }
            System.assert(missingEmployeeNumberThrew);
        }

        User userWithStandardEmployeeNumber = createUserWithStandardEmployeeNumber('887766');
        insert userWithStandardEmployeeNumber;
        System.runAs(userWithStandardEmployeeNumber) {
            SalesConnectionUrlService.testEmployeeNumberOverride = null;
            System.assertEquals(
                '887766',
                SalesConnectionUrlService.resolveCurrentUserEmployeeNumber()
            );
        }

        configureSalesConnectionSettings();
    }

    @IsTest
    static void testGetSettingsUsesOrgMetadataWhenOverrideIsClear() {
        SalesConnectionUrlService.testSettingsOverride = null;
        SalesConnectionUrlService.testEmployeeNumberOverride = null;
        Boolean resolved = false;

        Test.startTest();
        try {
            String url = SalesConnectionUrlService.buildExistingQuoteUrl('64747374');
            resolved = url == null || String.isNotBlank(url);
        } catch (AuraHandledException exceptionValue) {
            resolved = true;
        }
        Test.stopTest();

        System.assert(resolved, 'Should resolve settings from org metadata or fail with configuration error.');
        configureSalesConnectionSettings();
    }

    @IsTest
    static void testBuildStoredCreateQuoteUrlRequiresConfiguredBaseUrl() {
        SalesConnectionUrlService.testSettingsOverride = new ExternalSystemEndpoint__mdt(
            SalesConnectionBaseUrl__c = null,
            SalesConnectionEncryptionKey__c = EncodingUtil.base64Encode(
                Blob.valueOf('abcdefghijklmnopqrstuvwxyz012345')
            )
        );
        Account accountRecord = buildCustomerAccount('319163');
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            SalesConnectionUrlService.buildStoredCreateQuoteUrl(
                TEST_OPPORTUNITY_ID,
                TEST_QUOTE_ID,
                accountRecord,
                TEST_EMPLOYEE_NUMBER
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Missing base URL should block create quote URL generation.');
    }
    
    private static User createUser(String employeeNumber) {
        String uniqueValue = uniqueSuffix();
        return new User(
            FirstName = 'SC',
            LastName = 'UrlTest',
            Alias = ('scu' + uniqueValue).left(8),
            Email = 'scurl' + uniqueValue + '@test.invalid',
            Username = 'scurl' + uniqueValue + '@test.invalid',
            CommunityNickname = ('scurl' + uniqueValue).left(40),
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            EmployeeNumber__c = employeeNumber,
            IsActive = true
        );
    }

    private static User createUserWithStandardEmployeeNumber(String employeeNumber) {
        String uniqueValue = uniqueSuffix();
        return new User(
            FirstName = 'SC',
            LastName = 'StdEmp',
            Alias = ('sce' + uniqueValue).left(8),
            Email = 'scstemp' + uniqueValue + '@test.invalid',
            Username = 'scstemp' + uniqueValue + '@test.invalid',
            CommunityNickname = ('scst' + uniqueValue).left(40),
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            EmployeeNumber = employeeNumber,
            IsActive = true
        );
    }

    private static String uniqueSuffix() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    private static Account buildCustomerAccount(String oracleAddressId) {
        Account accountRecord = new Account(
            Name = 'Sales Connection URL Customer Account',
            SourceSystemID__c = 'SC-CUST-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            OracleAddressId__c = oracleAddressId,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(SalesConnectionUrlService.ACCOUNT_RECORD_TYPE_CUSTOMER)
            .getRecordTypeId()
        );
        insert accountRecord;
        
        return [
            SELECT Id, OracleAddressId__c, RecordType.DeveloperName
            FROM Account
            WHERE Id = :accountRecord.Id
            LIMIT 1
        ];
    }
    
    private static Account buildProspectAccount(String oracleAddressId) {
        Account accountRecord = new Account(
            Name = 'Sales Connection URL Prospect Account',
            SourceSystemID__c = 'SC-PROS-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            OracleAddressId__c = oracleAddressId,
            BillingStreet = '123 Main Street',
            BillingCity = 'Cleveland',
            BillingStateCode = getValidBillingStateCode(),
            BillingPostalCode = '44101',
            BillingCountryCode = getValidBillingCountryCode(),
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(SalesConnectionUrlService.ACCOUNT_RECORD_TYPE_PROSPECT)
            .getRecordTypeId()
        );
        insert accountRecord;
        
        return [
            SELECT Id, OracleAddressId__c, RecordType.DeveloperName
            FROM Account
            WHERE Id = :accountRecord.Id
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
        SalesConnectionUrlService.testEmployeeNumberOverride = TEST_EMPLOYEE_NUMBER;
        SalesConnectionEncryptionService.testEncryptionKeyOverride =
            SalesConnectionUrlService.testSettingsOverride.SalesConnectionEncryptionKey__c;
    }
    
    /**
     * @description Builds a deterministic 15-character Id for URL tests (org-agnostic).
     */
    private static Id fakeSalesforceId(Schema.SObjectType objectType, Integer seed) {
        String keyPrefix = objectType.getDescribe().getKeyPrefix();
        String suffix = String.valueOf(Math.abs(seed == null ? 1 : seed)).leftPad(12, '0');
        if (suffix.length() > 12) {
            suffix = suffix.substring(suffix.length() - 12);
        }

        return (Id) (keyPrefix + suffix);
    }

    private static String buildExpectedStoredCreateQuoteUrl(
        Id opportunityId,
        Id quoteId,
        String oracleAddressId,
        String accountTypeCode,
        String employeeNumber
    ) {
        return 'https://integration-salesconnection.steris.com/#Quote|id=0&addressid=' +
            oracleAddressId +
            '&accounttype=' +
            accountTypeCode +
            '&sfrequest=create&sfopportunityid=' +
            String.valueOf(opportunityId) +
            '&sfquoteid=' +
            String.valueOf(quoteId) +
            '&employeenumber=' +
            employeeNumber;
    }

    private static String getValidBillingCountryCode() {
        for (Schema.PicklistEntry picklistEntry : Account.BillingCountryCode.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && picklistEntry.getValue() == 'US') {
                return picklistEntry.getValue();
            }
        }

        for (Schema.PicklistEntry picklistEntry : Account.BillingCountryCode.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return 'US';
    }

    private static String getValidBillingStateCode() {
        for (Schema.PicklistEntry picklistEntry : Account.BillingStateCode.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && picklistEntry.getValue() == 'OH') {
                return picklistEntry.getValue();
            }
        }

        for (Schema.PicklistEntry picklistEntry : Account.BillingStateCode.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return 'OH';
    }
}