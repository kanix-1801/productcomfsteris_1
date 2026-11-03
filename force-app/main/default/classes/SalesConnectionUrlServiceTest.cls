/**
* @author Himanshu Chaurasia
* @date 2026/06/18
*
* @group Generate Quote
*
* @description Test class for SalesConnectionUrlService.
*/
@IsTest
private class SalesConnectionUrlServiceTest {
    private static final Id TEST_OPPORTUNITY_ID = '006Ou00000VxM2fIAF';
    private static final Id TEST_QUOTE_ID = '0Q0Ou000004QsdZKAS';
    private static final String TEST_EMPLOYEE_NUMBER = '12345';
    
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
            'https://integration-salesconnection.steris.com/#Quote|id=0&addressid=319163&accounttype=C&sfrequest=create&sfopportunityid=006Ou00000VxM2fIAF&sfquoteid=0Q0Ou000004QsdZKAS&employeenumber=12345',
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
            BillingState = getValidShippingState(),
            BillingPostalCode = '44101',
            BillingCountry = 'United States',
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
	    
    private static String getValidShippingState() {
        for (Schema.PicklistEntry picklistEntry : Account.BillingState.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }
        
        return 'Ohio';
    }
}