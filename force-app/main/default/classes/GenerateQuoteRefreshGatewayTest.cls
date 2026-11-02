/**
 * @author PWC Developer
 * @date 2026/07/08
 *
 * @group Generate Quote
 *
 * @description Test class for GenerateQuoteRefreshGateway using the ShoutOut framework pattern.
 */
@IsTest
private class GenerateQuoteRefreshGatewayTest {
    @IsTest
    static void refreshQuotesSuccess() {
        ShoutOut_Service_Setting__mdt serviceSetting = defaultRefreshServiceSetting();
        String responseBody = buildMockRefreshResponseJson();
        SO_HttpMockFactory httpMock = new SO_HttpMockFactory(
            200,
            'OK',
            responseBody,
            new Map<String, String>()
        );
        RefreshQuoteRequest requestBody = RefreshQuoteRequest.fromOpportunityId(
            UserInfo.getUserId()
        );

        SO_Config.SO_ServiceList_mock.add(serviceSetting);
        Test.setMock(HttpCalloutMock.class, httpMock);

        Test.startTest();
        GenerateQuoteRefreshGateway.CalloutResult result =
            GenerateQuoteRefreshGateway.refreshQuotes(requestBody);
        Test.stopTest();

        System.assertEquals(true, result.calloutSuccess);
        System.assertEquals(1, result.parsedResponse.size());
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

        SO_Config.SO_ServiceList_mock.add(serviceSetting);
        Test.setMock(HttpCalloutMock.class, httpMock);

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
    }

    @IsTest
    static void refreshQuotesParsesTruncatedMockDatetime() {
        ShoutOut_Service_Setting__mdt serviceSetting = defaultRefreshServiceSetting();
        String responseBody =
            '[{"id":"0Q0xxxxxxxxxxxx","quoteNumber":"00003956","quoteName":"Quote - Test","expirationDate":"2026-08-05","lastModifiedDate":"2026-07-08T...","status":"Draft","approvalStatus":"Approved","quoteTotalWithoutFreight":97000,"productSubgroupSummary":[]}]';
        RefreshQuoteRequest requestBody = RefreshQuoteRequest.fromOpportunityId(
            UserInfo.getUserId()
        );

        SO_Config.SO_ServiceList_mock.add(serviceSetting);
        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(200, 'OK', responseBody, new Map<String, String>())
        );

        Test.startTest();
        GenerateQuoteRefreshGateway.CalloutResult result =
            GenerateQuoteRefreshGateway.refreshQuotes(requestBody);
        Test.stopTest();

        System.assertEquals(true, result.calloutSuccess);
        System.assertEquals(1, result.parsedResponse.size());
        System.assertEquals(null, result.parsedResponse[0].lastModifiedDate);
    }

    @IsTest
    static void refreshQuotesUsesHardcodedMockResponse() {
        Id standardPricebookId = Test.getStandardPricebookId();
        Account accountRecord = new Account(
            Name = 'Refresh Mock Account',
            SourceSystemID__c = 'MOCK-REFRESH-ACCT',
            OracleAddressId__c = '638265'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Refresh',
            LastName = 'Mock Contact',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Opportunity opportunityRecord = new Opportunity(
            Name = 'Refresh Mock Opportunity',
            AccountId = accountRecord.Id,
            StageName = getValidStageName(),
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            Pricebook2Id = standardPricebookId,
            Type = getValidOpportunityType(),
            PrimaryContact__c = contactRecord.Id
        );
        insert opportunityRecord;

        Quote quoteRecord = new Quote(
            Name = 'Refresh Mock Quote',
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = standardPricebookId,
            Status = 'Draft',
            ExpirationDate = Date.today().addDays(30)
        );
        insert quoteRecord;

        GenerateQuoteRefreshGateway.forceHardcodedRefreshResponse = true;
        RefreshQuoteRequest requestBody = RefreshQuoteRequest.fromOpportunityId(opportunityRecord.Id);

        Test.startTest();
        GenerateQuoteRefreshGateway.CalloutResult result =
            GenerateQuoteRefreshGateway.refreshQuotes(requestBody);
        Test.stopTest();

        GenerateQuoteRefreshGateway.forceHardcodedRefreshResponse = false;

        System.assertEquals(true, result.calloutSuccess);
        System.assertEquals(1, result.parsedResponse.size());
        System.assertEquals(quoteRecord.Id, result.parsedResponse[0].id);
        System.assertEquals('Refresh Mock Quote', result.parsedResponse[0].quoteName);
        System.assertEquals('Open', result.parsedResponse[0].status);
        System.assert(result.parsedResponse[0].productSubgroupSummary.size() > 0);
    }

    @IsTest
    static void refreshQuotesHardcodedReturnsEmptyForOpportunityWithoutQuotes() {
        Id standardPricebookId = Test.getStandardPricebookId();
        Account accountRecord = new Account(
            Name = 'Refresh Empty Account',
            SourceSystemID__c = 'MOCK-REFRESH-EMPTY',
            OracleAddressId__c = '638266'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Refresh',
            LastName = 'Empty Contact',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Opportunity opportunityRecord = new Opportunity(
            Name = 'Refresh Empty Opportunity',
            AccountId = accountRecord.Id,
            StageName = getValidStageName(),
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            Pricebook2Id = standardPricebookId,
            Type = getValidOpportunityType(),
            PrimaryContact__c = contactRecord.Id
        );
        insert opportunityRecord;

        GenerateQuoteRefreshGateway.forceHardcodedRefreshResponse = true;
        RefreshQuoteRequest requestBody = RefreshQuoteRequest.fromOpportunityId(opportunityRecord.Id);

        Test.startTest();
        GenerateQuoteRefreshGateway.CalloutResult result =
            GenerateQuoteRefreshGateway.refreshQuotes(requestBody);
        Test.stopTest();

        GenerateQuoteRefreshGateway.forceHardcodedRefreshResponse = false;

        System.assertEquals(true, result.calloutSuccess);
        System.assertEquals(0, result.parsedResponse.size());
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

    private static ShoutOut_Service_Setting__mdt defaultRefreshServiceSetting() {
        ShoutOut_Service_Setting__mdt cmdtRecord = new ShoutOut_Service_Setting__mdt();
        cmdtRecord.DeveloperName = 'SF_REFRESH_QUOTE';
        cmdtRecord.Framework_Callout_Name__c = 'SF_REFRESH_QUOTE';
        cmdtRecord.isActive__c = true;
        cmdtRecord.Label = 'SF_REFRESH_QUOTE';
        cmdtRecord.MasterLabel = 'SF_REFRESH_QUOTE';
        cmdtRecord.Named_Credential__c = 'Generate_Refresh_Quote';
        cmdtRecord.Provider_Class__c = 'SO_Provider_Salesforce';
        cmdtRecord.REST_Path__c = '/v1/796feb3d-b03b-4742-9274-34dc5d0fde7a';
        cmdtRecord.REST_Verb__c = 'GET';
        cmdtRecord.Service_Class__c = 'SO_ServiceAdapterBase_REST';
        cmdtRecord.Timeout__c = 20;
        return cmdtRecord;
    }
}