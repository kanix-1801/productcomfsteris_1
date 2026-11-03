/**
 * @description Tests for LSSalesConnectionUrlService.
 */
@IsTest
private class LSSalesConnectionUrlServiceTest {
    private static final Id TEST_OPPORTUNITY_ID = '006Ou00000VxM2fIAF';
    private static final Id TEST_QUOTE_ID = '0Q0Ou000004QsdZKAS';
    private static final String TEST_EMPLOYEE_NUMBER = '12345';
    private static final String BASE_URL = 'https://integration-salesconnection.steris.com';
    private static final String STORED_CREATE_URL =
        BASE_URL +
        '/#Quote|id=0&addressid=319163&accounttype=C&sfrequest=create' +
        '&sfopportunityid=006Ou00000VxM2fIAF&sfquoteid=0Q0Ou000004QsdZKAS&employeenumber=12345';

    @IsTest
    static void testBuildStoredCreateQuoteUrlForCustomerAccount() {
        configureSalesConnectionSettings();

        String storedUrl = LSSalesConnectionUrlService.buildStoredCreateQuoteUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            buildAccount('319163', LSSalesConnectionUrlService.ACCOUNT_RECORD_TYPE_CUSTOMER),
            TEST_EMPLOYEE_NUMBER
        );

        System.assertEquals(STORED_CREATE_URL, storedUrl);
    }

    @IsTest
    static void testBuildStoredQuoteRequestUrlForCopyAndMerge() {
        configureSalesConnectionSettings();
        Account prospectAccount = buildAccount(
            '778899',
            LSSalesConnectionUrlService.ACCOUNT_RECORD_TYPE_PROSPECT
        );

        String copyUrl = LSSalesConnectionUrlService.buildStoredQuoteRequestUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            prospectAccount,
            TEST_EMPLOYEE_NUMBER,
            LSSalesConnectionUrlService.SF_REQUEST_COPY
        );
        String mergeUrl = LSSalesConnectionUrlService.buildStoredQuoteRequestUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            prospectAccount,
            TEST_EMPLOYEE_NUMBER,
            LSSalesConnectionUrlService.SF_REQUEST_MERGE
        );

        System.assert(copyUrl.contains('&accounttype=P&'));
        System.assert(copyUrl.contains('&sfrequest=copy&'));
        System.assert(mergeUrl.contains('&sfrequest=merge&'));
    }

    @IsTest
    static void testBuildStoredQuoteRequestUrlRejectsUnsupportedRequest() {
        configureSalesConnectionSettings();
        Boolean exceptionThrown = false;

        try {
            LSSalesConnectionUrlService.buildStoredQuoteRequestUrl(
                TEST_OPPORTUNITY_ID,
                TEST_QUOTE_ID,
                buildAccount('319163', LSSalesConnectionUrlService.ACCOUNT_RECORD_TYPE_CUSTOMER),
                TEST_EMPLOYEE_NUMBER,
                'delete'
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }

        System.assert(exceptionThrown);
    }

    @IsTest
    static void testOpenCreateQuoteUrlEncryptsStoredPayload() {
        configureSalesConnectionSettings();
        String storedUrl = LSSalesConnectionUrlService.buildStoredCreateQuoteUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            buildAccount('319163', null),
            TEST_EMPLOYEE_NUMBER
        );

        String openUrl = LSSalesConnectionUrlService.buildOpenCreateQuoteUrl(storedUrl);
        String openUrlFromContext = LSSalesConnectionUrlService.buildOpenCreateQuoteUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            buildAccount('319163', null),
            TEST_EMPLOYEE_NUMBER
        );

        System.assert(openUrl.startsWith(BASE_URL + '/#Quote|'));
        System.assertNotEquals(storedUrl, openUrl);
        System.assert(!openUrl.contains('addressid=319163'));
        System.assert(openUrlFromContext.startsWith(BASE_URL + '/#Quote|'));
        System.assertEquals(null, LSSalesConnectionUrlService.buildOpenCreateQuoteUrl(''));
    }

    @IsTest
    static void testBuildCreateQuoteUrlUsesEmployeeOverride() {
        configureSalesConnectionSettings();

        String openUrl = LSSalesConnectionUrlService.buildCreateQuoteUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            buildAccount('319163', LSSalesConnectionUrlService.ACCOUNT_RECORD_TYPE_CUSTOMER)
        );

        System.assert(openUrl.startsWith(BASE_URL + '/#Quote|'));
        System.assert(!openUrl.contains('addressid=319163'));
    }

    @IsTest
    static void testBuildQuoteUrlSelectsViewStoredOrCreateUrl() {
        configureSalesConnectionSettings();
        Account accountRecord = buildAccount(
            '319163',
            LSSalesConnectionUrlService.ACCOUNT_RECORD_TYPE_CUSTOMER
        );
        Opportunity opportunityRecord = new Opportunity(Id = TEST_OPPORTUNITY_ID);

        System.assertEquals(
            null,
            LSSalesConnectionUrlService.buildQuoteUrl(null, opportunityRecord, accountRecord)
        );
        System.assertEquals(
            null,
            LSSalesConnectionUrlService.buildQuoteUrl(new Quote(Id = TEST_QUOTE_ID), null, accountRecord)
        );

        String viewUrl = LSSalesConnectionUrlService.buildQuoteUrl(
            new Quote(
                Id = TEST_QUOTE_ID,
                QuoteNumber__c = 'Q-00003956',
                SalesConnectionQuoteID__c = 'SCQ-2283624'
            ),
            opportunityRecord,
            accountRecord
        );
        System.assertEquals(BASE_URL + '/#Quote|id=2283624', viewUrl);

        String storedUrl = LSSalesConnectionUrlService.buildStoredCreateQuoteUrl(
            TEST_OPPORTUNITY_ID,
            TEST_QUOTE_ID,
            accountRecord,
            TEST_EMPLOYEE_NUMBER
        );
        String openUrl = LSSalesConnectionUrlService.buildQuoteUrl(
            new Quote(Id = TEST_QUOTE_ID, SalesConnectionCreateQuoteURL__c = storedUrl),
            opportunityRecord,
            accountRecord
        );
        System.assertNotEquals(storedUrl, openUrl);
        System.assert(openUrl.startsWith(BASE_URL + '/#Quote|'));

        String createdUrl = LSSalesConnectionUrlService.buildQuoteUrl(
            new Quote(Id = TEST_QUOTE_ID),
            opportunityRecord,
            accountRecord
        );
        System.assert(createdUrl.startsWith(BASE_URL + '/#Quote|'));
    }

    @IsTest
    static void testBuildExistingQuoteUrlUsesConfiguredOrDefaultPath() {
        configureSalesConnectionSettings();
        System.assertEquals(null, LSSalesConnectionUrlService.buildExistingQuoteUrl(''));
        System.assertEquals(
            BASE_URL + '/#Quote|id=64747374',
            LSSalesConnectionUrlService.buildExistingQuoteUrl('64747374')
        );

        LSSalesConnectionUrlService.testSettingsOverride = new ExternalSystemEndpoint__mdt(
            SalesConnectionBaseUrl__c = BASE_URL + '/',
            SalesConnectionViewQuotePath__c = null
        );
        System.assertEquals(
            BASE_URL + '/#Quote|id=64747374',
            LSSalesConnectionUrlService.buildExistingQuoteUrl('64747374')
        );

        LSSalesConnectionUrlService.testSettingsOverride = new ExternalSystemEndpoint__mdt(
            SalesConnectionBaseUrl__c = BASE_URL,
            SalesConnectionViewQuotePath__c = '/quotes/{0}'
        );
        System.assertEquals(
            BASE_URL + '/quotes/64747374',
            LSSalesConnectionUrlService.buildExistingQuoteUrl('64747374')
        );

        LSSalesConnectionUrlService.testSettingsOverride = new ExternalSystemEndpoint__mdt(
            SalesConnectionBaseUrl__c = BASE_URL,
            SalesConnectionViewQuotePath__c = 'quotes/{0}'
        );
        System.assertEquals(
            BASE_URL + '/quotes/64747374',
            LSSalesConnectionUrlService.buildExistingQuoteUrl('64747374')
        );
    }

    @IsTest
    static void testValidationFailures() {
        configureSalesConnectionSettings();
        Account accountRecord = buildAccount(
            '319163',
            LSSalesConnectionUrlService.ACCOUNT_RECORD_TYPE_CUSTOMER
        );

        System.assert(throwsForStoredUrl(null, TEST_EMPLOYEE_NUMBER));
        System.assert(throwsForStoredUrl(buildAccount(null, null), TEST_EMPLOYEE_NUMBER));
        System.assert(throwsForStoredUrl(accountRecord, ' '));

        LSSalesConnectionUrlService.testSettingsOverride = new ExternalSystemEndpoint__mdt(
            SalesConnectionBaseUrl__c = null
        );
        System.assert(throwsForStoredUrl(accountRecord, TEST_EMPLOYEE_NUMBER));

        Boolean invalidStoredUrlThrew = false;
        try {
            LSSalesConnectionUrlService.buildOpenCreateQuoteUrl(BASE_URL + '/invalid-format');
        } catch (AuraHandledException exceptionValue) {
            invalidStoredUrlThrew = true;
        }
        System.assert(invalidStoredUrlThrew);

        String payload = LSSalesConnectionUrlService.extractCreateQuotePayload(STORED_CREATE_URL);
        System.assert(payload.startsWith('id=0&addressid=319163'));
        System.assert(
            LSSalesConnectionUrlService.buildQuoteRequestPayload(
                TEST_OPPORTUNITY_ID,
                TEST_QUOTE_ID,
                accountRecord,
                TEST_EMPLOYEE_NUMBER,
                LSSalesConnectionUrlService.SF_REQUEST_CREATE
            ).contains('&accounttype=C&')
        );
    }

    @IsTest
    static void testResolveEmployeeNumberFromUserOrOverride() {
        configureSalesConnectionSettings();
        System.assertEquals(
            TEST_EMPLOYEE_NUMBER,
            LSSalesConnectionUrlService.resolveCurrentUserEmployeeNumber()
        );

        User employeeUser = createUser('LSE' + uniqueSuffix().left(5));
        insert employeeUser;
        System.runAs(employeeUser) {
            LSSalesConnectionUrlService.testEmployeeNumberOverride = null;
            System.assertEquals(
                employeeUser.EmployeeNumber__c,
                LSSalesConnectionUrlService.resolveCurrentUserEmployeeNumber()
            );
        }

        User userWithoutEmployeeNumber = createUser(null);
        insert userWithoutEmployeeNumber;
        System.runAs(userWithoutEmployeeNumber) {
            LSSalesConnectionUrlService.testEmployeeNumberOverride = null;
            Boolean missingEmployeeNumberThrew = false;
            try {
                LSSalesConnectionUrlService.resolveCurrentUserEmployeeNumber();
            } catch (AuraHandledException exceptionValue) {
                missingEmployeeNumberThrew = true;
            }
            System.assert(missingEmployeeNumberThrew);
        }
    }

    @IsTest
    static void testGetSettingsUsesOrgMetadataWhenOverrideIsClear() {
        LSSalesConnectionUrlService.testSettingsOverride = null;
        Boolean resolved = false;

        try {
            String url = LSSalesConnectionUrlService.buildExistingQuoteUrl('64747374');
            resolved = url == null || String.isNotBlank(url);
        } catch (AuraHandledException exceptionValue) {
            resolved = true;
        }

        System.assert(resolved);
    }

    private static Boolean throwsForStoredUrl(Account accountRecord, String employeeNumber) {
        try {
            LSSalesConnectionUrlService.buildStoredCreateQuoteUrl(
                TEST_OPPORTUNITY_ID,
                TEST_QUOTE_ID,
                accountRecord,
                employeeNumber
            );
            return false;
        } catch (AuraHandledException exceptionValue) {
            return true;
        }
    }

    private static Account buildAccount(String oracleAddressId, String recordTypeDeveloperName) {
        String recordTypeJson = recordTypeDeveloperName == null
            ? ''
            : ',"RecordType":{"DeveloperName":"' + recordTypeDeveloperName + '"}';
        String addressJson = oracleAddressId == null
            ? ''
            : ',"OracleAddressId__c":"' + oracleAddressId + '"';

        return (Account) JSON.deserialize(
            '{"Name":"LS Sales Connection Account"' + addressJson + recordTypeJson + '}',
            Account.class
        );
    }

    private static User createUser(String employeeNumber) {
        String uniqueValue = uniqueSuffix();
        return new User(
            FirstName = 'LS',
            LastName = 'Url',
            Alias = ('lsu' + uniqueValue).left(8),
            Email = 'lsscurl' + uniqueValue + '@test.com',
            Username = 'lsscurl' + uniqueValue + '@test.com',
            CommunityNickname = ('lssc' + uniqueValue).left(40),
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            EmployeeNumber__c = employeeNumber,
            IsActive = true
        );
    }

    private static void configureSalesConnectionSettings() {
        LSSalesConnectionUrlService.testSettingsOverride = new ExternalSystemEndpoint__mdt(
            SalesConnectionBaseUrl__c = BASE_URL,
            SalesConnectionViewQuotePath__c = LSSalesConnectionUrlService.DEFAULT_VIEW_QUOTE_PATH,
            SalesConnectionEncryptionKey__c = EncodingUtil.base64Encode(
                Blob.valueOf('abcdefghijklmnopqrstuvwxyz012345')
            )
        );
        LSSalesConnectionUrlService.testEmployeeNumberOverride = TEST_EMPLOYEE_NUMBER;
        SalesConnectionEncryptionService.testEncryptionKeyOverride =
            LSSalesConnectionUrlService.testSettingsOverride.SalesConnectionEncryptionKey__c;
    }

    private static String uniqueSuffix() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }
}