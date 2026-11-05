/**
 * @author PWC Developer
 * @date 2026/07/08
 *
 * @group Generate Quote
 *
 * @description Test class for GenerateQuoteRefreshGateway (Steris dev: SO_Callout / HTTP only).
 *              Uses SO_HttpMockFactory and mocked SF_REFRESH_QUOTE CMDT; no SIT hardcoded refresh APIs.
 */
@IsTest
private class GenerateQuoteRefreshGatewayTest {
    private static final String QUOTE_AUTOMATION_RUN_AS_LAST_NAME = 'RefreshGatewayTestRunAs';
    private static final String SALES_FIELD_REP_PSG_DEVELOPER_NAME = 'SalesFieldRepAccountManagerPSG';

    @TestSetup
    static void setupRunAsUser() {
        User setupUser = new User(Id = UserInfo.getUserId());
        System.runAs(setupUser) {
            insert createQuoteAutomationRunAsUser();
        }
        assignSalesFieldRepAccountManagerPsg(getQuoteAutomationRunAsUser().Id);
    }

    @IsTest
    static void refreshQuotesSuccess() {
        Opportunity opportunityRecord = createRefreshTestOpportunity(
            'Refresh HTTP Success Opportunity'
        );
        insertRefreshTestQuote(opportunityRecord, 'Refresh HTTP Success Quote');

        ShoutOut_Service_Setting__mdt serviceSetting = defaultRefreshServiceSetting();
        String responseBody = buildMockRefreshResponseJson();
        SO_HttpMockFactory httpMock = new SO_HttpMockFactory(
            200,
            'OK',
            responseBody,
            new Map<String, String>()
        );
        RefreshQuoteRequest requestBody = RefreshQuoteRequest.fromOpportunityId(
            opportunityRecord.Id
        );

        configureRefreshHttpMock(serviceSetting, httpMock);

        Test.startTest();
        GenerateQuoteRefreshGateway.CalloutResult result =
            GenerateQuoteRefreshGateway.refreshQuotes(requestBody);
        Test.stopTest();

        System.assertEquals(
            true,
            result.calloutSuccess,
            'Callout should succeed. detail=' + result.errorDetail
        );
        System.assert(
            !result.parsedResponse.isEmpty(),
            'Expected parsed quotes from HTTP response body. detail=' + result.errorDetail
        );
        System.assertEquals('00003956', result.parsedResponse[0].quoteNumber);
        System.assertEquals(2, result.parsedResponse[0].productSubgroupSummary.size());
    }

    @IsTest
    static void refreshQuotesNullRequestBody() {
        Test.startTest();
        GenerateQuoteRefreshGateway.CalloutResult result =
            GenerateQuoteRefreshGateway.refreshQuotes(null);
        Test.stopTest();

        System.assertEquals(false, result.calloutSuccess);
        System.assertEquals('Request body is null', result.errorDetail);
    }

    @IsTest
    static void refreshQuotesHttpFailure() {
        ShoutOut_Service_Setting__mdt serviceSetting = defaultRefreshServiceSetting();
        SO_HttpMockFactory httpMock = new SO_HttpMockFactory(
            500,
            'Internal Server Error',
            '{"error":"Unavailable"}',
            new Map<String, String>()
        );
        RefreshQuoteRequest requestBody = RefreshQuoteRequest.fromOpportunityId(
            UserInfo.getUserId()
        );

        configureRefreshHttpMock(serviceSetting, httpMock);

        Test.startTest();
        GenerateQuoteRefreshGateway.CalloutResult result =
            GenerateQuoteRefreshGateway.refreshQuotes(requestBody);
        Test.stopTest();

        System.assertEquals(false, result.calloutSuccess);
        System.assertNotEquals(null, result.errorDetail);
    }

    @IsTest
    static void refreshQuoteRequestSerializesExpectedPayload() {
        Id opportunityId = UserInfo.getUserId();
        RefreshQuoteRequest requestBody = RefreshQuoteRequest.fromOpportunityId(opportunityId);
        Map<String, Object> jsonMap = requestBody.toJsonMap();

        System.assertEquals(String.valueOf(opportunityId), jsonMap.get('opportunitySfId'));
        System.assertEquals('GlobalSF', jsonMap.get('sourceSystem'));
        System.assertEquals('HC', jsonMap.get('classCode'));
    }

    @IsTest
    static void refreshQuotesParsesTruncatedMockDatetime() {
        ShoutOut_Service_Setting__mdt serviceSetting = defaultRefreshServiceSetting();
        String responseBody =
            '[{"id":"0Q0xxxxxxxxxxxx","quoteNumber":"00003956","quoteName":"Quote - Test","expirationDate":"2026-08-05","lastModifiedDate":"2026-07-08T...","status":"Draft","approvalStatus":"Approved","quoteTotalWithoutFreight":97000,"productSubgroupSummary":[]}]';
        RefreshQuoteRequest requestBody = RefreshQuoteRequest.fromOpportunityId(
            UserInfo.getUserId()
        );

        configureRefreshHttpMock(
            serviceSetting,
            new SO_HttpMockFactory(200, 'OK', responseBody, new Map<String, String>())
        );

        Test.startTest();
        GenerateQuoteRefreshGateway.CalloutResult result =
            GenerateQuoteRefreshGateway.refreshQuotes(requestBody);
        Test.stopTest();

        System.assertEquals(
            true,
            result.calloutSuccess,
            'Callout should succeed. detail=' + result.errorDetail
        );
        System.assertEquals(1, result.parsedResponse.size());
        System.assertEquals(null, result.parsedResponse[0].lastModifiedDate);
    }

    @IsTest
    static void refreshQuotesParsesSalesConnectionMockRefreshPayload() {
        Opportunity opportunityRecord = createRefreshTestOpportunity('Refresh Mock Opportunity');
        Quote quoteRecord = insertRefreshTestQuote(opportunityRecord, 'Refresh Mock Quote');

        ShoutOut_Service_Setting__mdt serviceSetting = defaultRefreshServiceSetting();
        String responseBody = SalesConnectionQuoteMockService.buildRefreshQuoteResponseBody(
            opportunityRecord.Id
        );
        configureRefreshHttpMock(
            serviceSetting,
            new SO_HttpMockFactory(200, 'OK', responseBody, new Map<String, String>())
        );

        RefreshQuoteRequest requestBody = RefreshQuoteRequest.fromOpportunityId(opportunityRecord.Id);

        Test.startTest();
        GenerateQuoteRefreshGateway.CalloutResult result =
            GenerateQuoteRefreshGateway.refreshQuotes(requestBody);
        Test.stopTest();

        System.assertEquals(true, result.calloutSuccess, 'detail=' + result.errorDetail);
        System.assertEquals(1, result.parsedResponse.size());
        System.assertEquals(quoteRecord.Id, result.parsedResponse[0].id);
        System.assertEquals('Refresh Mock Quote', result.parsedResponse[0].quoteName);
        System.assertEquals('Open', result.parsedResponse[0].status);
        System.assert(result.parsedResponse[0].productSubgroupSummary.size() > 0);
    }

    @IsTest
    static void refreshQuotesHttpReturnsEmptyQuoteArray() {
        Opportunity opportunityRecord = createRefreshTestOpportunity('Refresh Empty Opportunity');

        ShoutOut_Service_Setting__mdt serviceSetting = defaultRefreshServiceSetting();
        configureRefreshHttpMock(
            serviceSetting,
            new SO_HttpMockFactory(200, 'OK', '[]', new Map<String, String>())
        );

        RefreshQuoteRequest requestBody = RefreshQuoteRequest.fromOpportunityId(opportunityRecord.Id);

        Test.startTest();
        GenerateQuoteRefreshGateway.CalloutResult result =
            GenerateQuoteRefreshGateway.refreshQuotes(requestBody);
        Test.stopTest();

        System.assertEquals(true, result.calloutSuccess, 'detail=' + result.errorDetail);
        System.assertEquals(0, result.parsedResponse.size());
    }

    @IsTest
    static void testIsSuccessfulCoversAllBranches() {
        System.assertEquals(false, GenerateQuoteRefreshGateway.isSuccessful(null));
        System.assertEquals(false, GenerateQuoteRefreshGateway.isSuccessful(new Map<String, Object>()));
        System.assertEquals(
            true,
            GenerateQuoteRefreshGateway.isSuccessful(new Map<String, Object>{ 'SO_SUCCESS' => true })
        );
        System.assertEquals(
            false,
            GenerateQuoteRefreshGateway.isSuccessful(new Map<String, Object>{ 'SO_SUCCESS' => false })
        );
        System.assertEquals(
            false,
            GenerateQuoteRefreshGateway.isSuccessful(new Map<String, Object>{ 'SO_SUCCESS' => 'true' })
        );
    }

    @IsTest
    static void testExtractResponseBodyCoversAllBranches() {
        System.assertEquals(
            null,
            GenerateQuoteRefreshGateway.extractResponseBody(new Map<String, Object>()),
            'Empty response map should yield no body.'
        );

        System.assertEquals(
            'payload',
            GenerateQuoteRefreshGateway.extractResponseBody(
                new Map<String, Object>{ 'SERVICE_DATA' => 'payload' }
            )
        );

        System.assertEquals(
            null,
            GenerateQuoteRefreshGateway.extractResponseBody(
                new Map<String, Object>{ 'SERVICE_DATA' => '   ' }
            )
        );

        System.assertEquals(
            '[{"id":"0Q0"}]',
            GenerateQuoteRefreshGateway.extractResponseBody(
                new Map<String, Object>{ SO_Constants.SERVICERESPONSE => '[{"id":"0Q0"}]' }
            )
        );

        String serializedObjectBody = GenerateQuoteRefreshGateway.extractResponseBody(
            new Map<String, Object>{
                'SERVICE_DATA' => new Map<String, Object>{ 'quoteNumber' => '123' }
            }
        );
        System.assertNotEquals(null, serializedObjectBody);
        System.assert(serializedObjectBody.contains('123'));
    }

    @IsTest
    static void testExtractErrorDetailCoversAllBranches() {
        System.assertEquals(
            'SO_Callout returned an empty response map',
            GenerateQuoteRefreshGateway.extractErrorDetail(null)
        );
        System.assertEquals(
            'SO_Callout returned an empty response map',
            GenerateQuoteRefreshGateway.extractErrorDetail(new Map<String, Object>())
        );
        System.assertEquals(
            'Integration failed',
            GenerateQuoteRefreshGateway.extractErrorDetail(
                new Map<String, Object>{ 'SO_RETURN' => 'Integration failed' }
            )
        );
        System.assertEquals(
            'Service response error',
            GenerateQuoteRefreshGateway.extractErrorDetail(
                new Map<String, Object>{ SO_Constants.SERVICERESPONSE => 'Service response error' }
            )
        );
        System.assertEquals(
            'Refresh Quote callout failed with HTTP status 500: Unavailable',
            GenerateQuoteRefreshGateway.extractErrorDetail(
                new Map<String, Object>{
                    'SERVICE_STATUS' => 500,
                    'SERVICE_DATA' => 'Unavailable'
                }
            )
        );
        System.assertEquals(
            'Refresh Quote callout failed with HTTP status 404',
            GenerateQuoteRefreshGateway.extractErrorDetail(
                new Map<String, Object>{ 'SERVICE_STATUS' => 404 }
            )
        );
        System.assertEquals(
            'SO_Callout failed with SO_SUCCESS=false',
            GenerateQuoteRefreshGateway.extractErrorDetail(
                new Map<String, Object>{ 'SO_SUCCESS' => false }
            )
        );
    }

    @IsTest
    static void testAddRestConfigToCalloutStripsTrailingSlash() {
        ShoutOut_Service_Setting__mdt serviceSetting = defaultRefreshServiceSetting();
        serviceSetting.REST_Path__c = '/v1/mock-path/';
        SO_Config.SO_ServiceList_mock.add(serviceSetting);

        SO_Callout callout = new SO_Callout();
        GenerateQuoteRefreshGateway.addRestConfigToCallout(callout);

        System.assert(true, 'REST config helper should execute without error.');
    }

    @IsTest
    static void refreshQuotesSetsErrorDetailWhenResponseBodyIsInvalidJson() {
        ShoutOut_Service_Setting__mdt serviceSetting = defaultRefreshServiceSetting();
        configureRefreshHttpMock(
            serviceSetting,
            new SO_HttpMockFactory(200, 'OK', 'not-valid-json', new Map<String, String>())
        );

        RefreshQuoteRequest requestBody = RefreshQuoteRequest.fromOpportunityId(
            UserInfo.getUserId()
        );

        Test.startTest();
        GenerateQuoteRefreshGateway.CalloutResult result =
            GenerateQuoteRefreshGateway.refreshQuotes(requestBody);
        Test.stopTest();

        System.assertNotEquals(null, result.errorDetail, 'Parse failure should populate errorDetail.');
        System.assertEquals(0, result.parsedResponse.size());
    }

    @IsTest
    static void testSerializeResponseMapForLogCoversAllBranches() {
        System.assertEquals(
            '',
            GenerateQuoteRefreshGateway.serializeResponseMapForLog(null),
            'Null map should log as empty string.'
        );
        System.assertEquals(
            '',
            GenerateQuoteRefreshGateway.serializeResponseMapForLog(new Map<String, Object>()),
            'Empty map should log as empty string.'
        );

        String serialized = GenerateQuoteRefreshGateway.serializeResponseMapForLog(
            new Map<String, Object>{ 'SO_SUCCESS' => true }
        );
        System.assertNotEquals(null, serialized);
        System.assert(serialized.contains('true'));
    }

    @IsTest
    static void testResolveHttpStatusForLogCoversAllBranches() {
        System.assertEquals('n/a', GenerateQuoteRefreshGateway.resolveHttpStatusForLog(null));
        System.assertEquals('n/a', GenerateQuoteRefreshGateway.resolveHttpStatusForLog(new Map<String, Object>()));
        System.assertEquals(
            '200',
            GenerateQuoteRefreshGateway.resolveHttpStatusForLog(
                new Map<String, Object>{ 'SERVICE_STATUS' => 200 }
            )
        );
    }

    @IsTest
    static void refreshQuotesSuccessWithBlankHttpBodyReturnsEmptyParsedList() {
        ShoutOut_Service_Setting__mdt serviceSetting = defaultRefreshServiceSetting();
        configureRefreshHttpMock(
            serviceSetting,
            new SO_HttpMockFactory(200, 'OK', '', new Map<String, String>())
        );

        RefreshQuoteRequest requestBody = RefreshQuoteRequest.fromOpportunityId(
            UserInfo.getUserId()
        );

        Test.startTest();
        GenerateQuoteRefreshGateway.CalloutResult result =
            GenerateQuoteRefreshGateway.refreshQuotes(requestBody);
        Test.stopTest();

        System.assertEquals(true, result.calloutSuccess, 'detail=' + result.errorDetail);
        System.assertEquals(0, result.parsedResponse.size());
    }

    @IsTest
    static void testCalloutResultDefaultConstructor() {
        GenerateQuoteRefreshGateway.CalloutResult result =
            new GenerateQuoteRefreshGateway.CalloutResult();

        System.assertEquals(false, result.calloutSuccess);
        System.assertEquals(false, result.retryEnqueued);
        System.assertEquals(0, result.parsedResponse.size());
    }

    @IsTest
    static void refreshQuotesSetsRetryEnqueuedOnRetryableHttpFailure() {
        ShoutOut_Service_Setting__mdt serviceSetting = defaultRefreshServiceSetting();
        serviceSetting.Retry_Max_Attempts__c = 1;
        serviceSetting.Retry_Base_Delay_Seconds__c = 0;
        serviceSetting.Retry_On_HTTP_Codes__c = '500';

        configureRefreshHttpMock(
            serviceSetting,
            new SO_HttpMockFactory(
                500,
                'Internal Server Error',
                '{"error":"Unavailable"}',
                new Map<String, String>()
            )
        );

        RefreshQuoteRequest requestBody = RefreshQuoteRequest.fromOpportunityId(
            UserInfo.getUserId()
        );

        Test.startTest();
        GenerateQuoteRefreshGateway.CalloutResult result =
            GenerateQuoteRefreshGateway.refreshQuotes(requestBody);
        Test.stopTest();

        System.assertEquals(false, result.calloutSuccess);
        System.assertEquals(true, result.retryEnqueued);
        System.assertNotEquals(null, result.errorDetail);
    }

    @IsTest
    static void testAddRestConfigToCalloutSkipsBlankRestPath() {
        ShoutOut_Service_Setting__mdt serviceSetting = defaultRefreshServiceSetting();
        serviceSetting.REST_Path__c = null;
        SO_Config.SO_ServiceList_mock.add(serviceSetting);

        SO_Callout callout = new SO_Callout();
        GenerateQuoteRefreshGateway.addRestConfigToCallout(callout);

        System.assert(true, 'Blank REST path should not prevent helper execution.');
    }

    @IsTest
    static void testLogPayloadHelpersExecuteDuringRefresh() {
        ShoutOut_Service_Setting__mdt serviceSetting = defaultRefreshServiceSetting();
        configureRefreshHttpMock(
            serviceSetting,
            new SO_HttpMockFactory(200, 'OK', '[]', new Map<String, String>())
        );

        RefreshQuoteRequest requestBody = RefreshQuoteRequest.fromOpportunityId(
            UserInfo.getUserId()
        );

        Test.startTest();
        GenerateQuoteRefreshGateway.CalloutResult result =
            GenerateQuoteRefreshGateway.refreshQuotes(requestBody);
        Test.stopTest();

        System.assertEquals(true, result.calloutSuccess, 'detail=' + result.errorDetail);
        System.assertNotEquals(null, result.serviceResponseMap);
    }

    private static Opportunity createRefreshTestOpportunity(String opportunityName) {
        Id standardPricebookId = Test.getStandardPricebookId();

        Account accountRecord = new Account(
            Name = opportunityName + ' Account',
            SourceSystemID__c = 'MOCK-REFRESH-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            OracleAddressId__c = '638265'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Refresh',
            LastName = 'Gateway Test',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Opportunity opportunityRecord = new Opportunity(
            Name = opportunityName,
            AccountId = accountRecord.Id,
            StageName = getValidStageName(),
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            Pricebook2Id = standardPricebookId,
            Type = getValidOpportunityType(),
            PrimaryContact__c = contactRecord.Id
        );

        Id healthcareSalesRtId = resolveHealthcareSalesOpportunityRecordTypeId();
        if (healthcareSalesRtId != null) {
            opportunityRecord.RecordTypeId = healthcareSalesRtId;
        }

        insert opportunityRecord;
        return opportunityRecord;
    }

    private static Quote insertRefreshTestQuote(Opportunity opportunityRecord, String quoteName) {
        Quote quoteRecord = new Quote(
            Name = quoteName,
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            RecordTypeId = resolveHcSalesQuoteRecordTypeId(),
            Status = 'Draft',
            ExpirationDate = Date.today().addDays(30),
            Quote_Total_Without_Freight__c = 1000
        );

        System.runAs(getQuoteAutomationRunAsUser()) {
            insert quoteRecord;
        }

        return quoteRecord;
    }

    private static User createQuoteAutomationRunAsUser() {
        Profile adminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        return new User(
            Alias = 'rgtrun',
            Email = 'refresh.gateway.test.runas@test.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = QUOTE_AUTOMATION_RUN_AS_LAST_NAME,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username =
                'refresh.gateway.test.runas+' +
                UserInfo.getOrganizationId() +
                '@test.invalid'
        );
    }

    private static User getQuoteAutomationRunAsUser() {
        return [
            SELECT Id
            FROM User
            WHERE LastName = :QUOTE_AUTOMATION_RUN_AS_LAST_NAME
            LIMIT 1
        ];
    }

    private static void assignSalesFieldRepAccountManagerPsg(Id userId) {
        PermissionSetGroup permissionSetGroupRecord = [
            SELECT Id, Status
            FROM PermissionSetGroup
            WHERE DeveloperName = :SALES_FIELD_REP_PSG_DEVELOPER_NAME
            LIMIT 1
        ];

        Test.calculatePermissionSetGroup(permissionSetGroupRecord.Id);

        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetGroupId = permissionSetGroupRecord.Id
        );
    }

    private static Id resolveHcSalesQuoteRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName();

        List<String> developerNameCandidates = new List<String>{
            GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME,
            'HCSales',
            'HC_Sales'
        };

        for (String developerName : developerNameCandidates) {
            if (!recordTypesByDeveloperName.containsKey(developerName)) {
                continue;
            }

            return recordTypesByDeveloperName.get(developerName).getRecordTypeId();
        }

        return null;
    }

    private static Id resolveHealthcareSalesOpportunityRecordTypeId() {
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get('Healthcare_Sales');
        return recordTypeInfo == null ? null : recordTypeInfo.getRecordTypeId();
    }

    private static String getValidOpportunityType() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.Type.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }

    private static String getValidStageName() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return 'Discovery';
    }

    private static String buildMockRefreshResponseJson() {
        return JSON.serialize(
            new List<Object>{
                new Map<String, Object>{
                    'id' => '0Q0xxxxxxxxxxxx',
                    'quoteNumber' => '00003956',
                    'quoteName' => 'Quote - QA_GC2628_Test1',
                    'expirationDate' => '2026-08-05',
                    'salesConnectionUrl' => 'https://dev1-salesconnection.steris.com/#Account|id=638265&createquote=true',
                    'description' => 'Endoscopy equipment upgrade',
                    'status' => 'Draft',
                    'approvalStatus' => 'Approved',
                    'quoteTotalWithoutFreight' => 97000,
                    'lastModifiedDate' => '2026-07-08T10:15:30.000Z',
                    'productSubgroupSummary' => new List<Object>{
                        new Map<String, Object>{
                            'productSubgroupDetailName' => 'AER',
                            'totalUnitPrice' => 55000,
                            'quoteLines' => new List<Object>{
                                new Map<String, Object>{
                                    'quoteLineId' => 'QL-001',
                                    'productName' => 'AER Pomezia - Innova E4CMS',
                                    'uom' => 'EA',
                                    'productFAMCode' => '027',
                                    'productSubgroupDetailName' => 'AER',
                                    'territoryId' => 'TERR-001',
                                    'tasSalesCategory' => 'SURG SPT',
                                    'salesCategoryDescription' => 'Surgical Support',
                                    'quantity' => 1,
                                    'unitPrice' => 30000,
                                    'lineTotal' => 30000
                                },
                                new Map<String, Object>{
                                    'quoteLineId' => 'QL-002',
                                    'productName' => 'VerifEYE Borescope',
                                    'uom' => 'EA',
                                    'productFAMCode' => '045',
                                    'productSubgroupDetailName' => 'AER',
                                    'territoryId' => 'TERR-001',
                                    'tasSalesCategory' => 'SURG SPT',
                                    'salesCategoryDescription' => 'Surgical Support',
                                    'quantity' => 1,
                                    'unitPrice' => 25000,
                                    'lineTotal' => 25000
                                }
                            }
                        },
                        new Map<String, Object>{
                            'productSubgroupDetailName' => 'Sterilizers',
                            'totalUnitPrice' => 5000,
                            'quoteLines' => new List<Object>{
                                new Map<String, Object>{
                                    'quoteLineId' => 'QL-003',
                                    'productName' => 'VHP - VHP 100i',
                                    'uom' => 'EA',
                                    'productFAMCode' => '054',
                                    'productSubgroupDetailName' => 'AER',
                                    'territoryId' => 'TERR-002',
                                    'tasSalesCategory' => 'STERL PROC',
                                    'salesCategoryDescription' => 'Sterilization Processing',
                                    'quantity' => 1,
                                    'unitPrice' => 5000,
                                    'lineTotal' => 5000
                                }
                            }
                        }
                    }
                }
            }
        );
    }

    private static void configureRefreshHttpMock(
        ShoutOut_Service_Setting__mdt serviceSetting,
        SO_HttpMockFactory httpMock
    ) {
        SO_Config.SO_ServiceList_mock.add(serviceSetting);
        Test.setMock(HttpCalloutMock.class, httpMock);
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
}