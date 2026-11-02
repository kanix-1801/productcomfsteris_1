/**
 * @author Himanshu Chaurasia
 * @date 2026/09/30
 *
 * @description GC-3457 - Tests Opportunity / Quote SC event mapping, enqueue rules,
 *              and gateway hardcoded responses (no live Boomi endpoint).
 */
@IsTest
private class ScOpportunityQuoteEventServiceTest {
    private static final String TEST_OPPORTUNITY_NAME =
        'SC Opportunity Quote Event Test Opportunity';

    private static Integer mockCallCount = 0;

    private class CapturingHttpMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            mockCallCount++;

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setStatus('OK');
            response.setHeader('Content-Type', 'application/json');
            response.setBody(buildEchoSuccessBody(request.getBody()));
            return response;
        }
    }

    @TestSetup
    static void setupData() {
        Id standardPricebookId = Test.getStandardPricebookId();

        Account accountRecord = new Account(
            Name = 'SC Opportunity Quote Event Test Account',
            SourceSystemID__c = 'SC-OQE-TEST',
            OracleAddressId__c = '638265'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'SC',
            LastName = 'Quote Event',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        insert buildOpportunity(
            TEST_OPPORTUNITY_NAME,
            accountRecord.Id,
            contactRecord.Id,
            standardPricebookId,
            resolveValidForecastConfidenceLevel('Pipeline')
        );
    }

    @IsTest
    static void mapperBuildsForecastConfidencePayload() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote firstQuote = insertQuoteWithScId(opportunityRecord, 'SC Event Quote 1', '435353');
        Quote secondQuote = insertQuoteWithScId(opportunityRecord, 'SC Event Quote 2', '757567');
        insertQuote(opportunityRecord, 'SC Event Quote 3', 'Open');

        Map<String, Object> payload = ScOpportunityQuoteEventMapper.toForecastConfidenceUpdateRequest(
            opportunityRecord.Id,
            'Upside',
            new List<Quote>{ firstQuote, secondQuote },
            new User(EmployeeNumber__c = '123456')
        ).toJsonMap();

        System.assertEquals('QUOTE_FORECAST_CONFIDENCE_UPDATE', payload.get('eventType'));
        System.assertEquals(String.valueOf(opportunityRecord.Id), payload.get('sfOpportunityId'));
        System.assertEquals('Upside', payload.get('forecastConfidence'));
        System.assertEquals('N/A', payload.get('opportunityStatus'));
        System.assertEquals('N/A', payload.get('quoteStatus'));
        System.assertEquals('123456', payload.get('updatedByHrisId'));

        List<Object> quotes = (List<Object>) payload.get('quotes');
        System.assertEquals(2, quotes.size());
    }

    @IsTest
    static void mapperBuildsClosedLostPayload() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote firstQuote = insertQuoteWithScId(opportunityRecord, 'SC Event Quote 4', '464646');
        Quote secondQuote = insertQuoteWithScId(opportunityRecord, 'SC Event Quote 5', '756757');

        Map<String, Object> payload = ScOpportunityQuoteEventMapper.toOpportunityClosedLostRequest(
            opportunityRecord.Id,
            new List<Quote>{ firstQuote, secondQuote },
            new User(EmployeeNumber__c = '123456')
        ).toJsonMap();

        System.assertEquals('OPPORTUNITY_CLOSED_LOST', payload.get('eventType'));
        System.assertEquals('Closed Lost', payload.get('opportunityStatus'));
        System.assertEquals('N/A', payload.get('forecastConfidence'));
        System.assertEquals('Closed', payload.get('quoteStatus'));

        List<Object> quotes = (List<Object>) payload.get('quotes');
        System.assertEquals(2, quotes.size());
    }

    @IsTest
    static void mapperBuildsEppConversionPayload() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote firstQuote = insertQuoteWithScId(opportunityRecord, 'SC Event Quote EPP 1', '464646');
        Quote secondQuote = insertQuoteWithScId(opportunityRecord, 'SC Event Quote EPP 2', '756757');

        Map<String, Object> payload =
            ScOpportunityQuoteEventMapper.toOpportunityConvertedToEppQuotesClosedRequest(
                opportunityRecord.Id,
                new List<Quote>{ firstQuote, secondQuote },
                new User(EmployeeNumber__c = '123456')
            ).toJsonMap();

        System.assertEquals(
            'OPPORTUNITY_CONVERTED_TO_EPP_QUOTES_CLOSED',
            payload.get('eventType')
        );
        System.assertEquals('N/A', payload.get('opportunityStatus'));
        System.assertEquals('N/A', payload.get('forecastConfidence'));
        System.assertEquals('Closed', payload.get('quoteStatus'));
        System.assertEquals('123456', payload.get('updatedByHrisId'));

        List<Object> quotes = (List<Object>) payload.get('quotes');
        System.assertEquals(2, quotes.size());
    }

    @IsTest
    static void synchronizeForecastConfidenceUpdatesQuoteAfterSuccessfulCallout() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuoteWithScId(opportunityRecord, 'SC Event Quote 6', '2283999');
        ScOpportunityQuoteEventGateway.forceHardcodedResponse = true;

        Test.startTest();
        ScOpportunityQuoteEventService.synchronizeForecastConfidenceUpdate(
            opportunityRecord.Id,
            'Upside',
            new Set<Id>{ quoteRecord.Id },
            UserInfo.getUserId()
        );
        Test.stopTest();

        Quote updatedQuote = [
            SELECT QuoteForecastConfidence__c
            FROM Quote
            WHERE Id = :quoteRecord.Id
            LIMIT 1
        ];
        System.assertEquals('Upside', updatedQuote.QuoteForecastConfidence__c);
        ScOpportunityQuoteEventGateway.forceHardcodedResponse = false;
    }

    @IsTest
    static void synchronizeClosedLostUpdatesQuoteStatusAfterSuccessfulCallout() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuoteWithScId(opportunityRecord, 'SC Event Quote 10', '2284010');
        ScOpportunityQuoteEventGateway.forceHardcodedResponse = true;

        Test.startTest();
        ScOpportunityQuoteEventService.synchronizeClosedLostQuoteClosure(
            opportunityRecord.Id,
            new Set<Id>{ quoteRecord.Id },
            UserInfo.getUserId()
        );
        Test.stopTest();

        Quote updatedQuote = [
            SELECT Status
            FROM Quote
            WHERE Id = :quoteRecord.Id
            LIMIT 1
        ];
        System.assertEquals(QuoteSelector.CLOSED_STATUS_VALUE, updatedQuote.Status);
        ScOpportunityQuoteEventGateway.forceHardcodedResponse = false;
    }

    @IsTest
    static void synchronizeForecastConfidenceFailsWithoutSalesConnectionQuoteId() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'SC Event Quote 7', 'Open');
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ScOpportunityQuoteEventService.synchronizeForecastConfidenceUpdate(
                opportunityRecord.Id,
                'Upside',
                new Set<Id>{ quoteRecord.Id },
                UserInfo.getUserId()
            );
        } catch (Exception exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Sync must fail when no Quote has a Sales Connection Quote Id.');
    }

    @IsTest
    static void synchronizeClosedLostFailsWithoutSalesConnectionQuoteId() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'SC Event Quote 7b', 'Open');
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ScOpportunityQuoteEventService.synchronizeClosedLostQuoteClosure(
                opportunityRecord.Id,
                new Set<Id>{ quoteRecord.Id },
                UserInfo.getUserId()
            );
        } catch (Exception exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown);
    }

    @IsTest
    static void validateSyncInputsRequiresOpportunityId() {
        Boolean exceptionThrown = false;

        try {
            ScOpportunityQuoteEventService.synchronizeForecastConfidenceUpdate(
                null,
                'Upside',
                new Set<Id>(),
                UserInfo.getUserId()
            );
        } catch (Exception exceptionValue) {
            exceptionThrown = true;
        }

        System.assert(exceptionThrown);
    }

    @IsTest
    static void applyServiceUpdatesForecastConfidenceDirectly() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'SC Event Quote Apply 1', 'Open');
        String expectedConfidence = getValidQuoteForecastConfidence();

        ScOpportunityQuoteEventApplyService.applyForecastConfidence(
            new Set<Id>{ quoteRecord.Id },
            expectedConfidence
        );

        quoteRecord = [
            SELECT QuoteForecastConfidence__c
            FROM Quote
            WHERE Id = :quoteRecord.Id
            LIMIT 1
        ];
        System.assertEquals(expectedConfidence, quoteRecord.QuoteForecastConfidence__c);
    }

    @IsTest
    static void applyServiceUpdatesQuoteStatusDirectly() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'SC Event Quote Apply 2', 'Open');

        ScOpportunityQuoteEventApplyService.applyQuoteStatus(
            new Set<Id>{ quoteRecord.Id },
            QuoteSelector.CLOSED_STATUS_VALUE
        );

        quoteRecord = [
            SELECT Status
            FROM Quote
            WHERE Id = :quoteRecord.Id
            LIMIT 1
        ];
        System.assertEquals(QuoteSelector.CLOSED_STATUS_VALUE, quoteRecord.Status);
    }

    @IsTest
    static void responseParserRecognizesSuccessStatus() {
        ScOpportunityQuoteEventResponse response = ScOpportunityQuoteEventResponse.parse(
            '{"status":"Success","quoteForecastConfidence":"Upside","quoteStatus":"N/A"}'
        );

        System.assertNotEquals(null, response);
        System.assertEquals(true, response.isSuccessStatus());
        System.assertEquals('Upside', response.quoteForecastConfidence);
    }

    @IsTest
    static void queueableProcessesForecastConfidenceWithHardcodedGateway() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuoteWithScId(opportunityRecord, 'SC Event Quote 8', '2284005');
        ScOpportunityQuoteEventGateway.forceHardcodedResponse = true;

        Test.startTest();
        new ScOpportunityQuoteEventQueueable(
            opportunityRecord.Id,
            ScOpportunityQuoteEventRequest.EVENT_TYPE_QUOTE_FORECAST_CONFIDENCE_UPDATE,
            'Upside',
            new Set<Id>{ quoteRecord.Id },
            UserInfo.getUserId()
        ).execute(null);
        Test.stopTest();

        ScOpportunityQuoteEventGateway.forceHardcodedResponse = false;
    }

    @IsTest
    static void queueableThrowsWhenQuotesHaveNoSalesConnectionId() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'SC Event Quote 11', 'Open');
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            new ScOpportunityQuoteEventQueueable(
                opportunityRecord.Id,
                ScOpportunityQuoteEventRequest.EVENT_TYPE_QUOTE_FORECAST_CONFIDENCE_UPDATE,
                'Upside',
                new Set<Id>{ quoteRecord.Id },
                UserInfo.getUserId()
            ).execute(null);
        } catch (Exception exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Queueable must surface missing Sales Connection Quote Id.');
    }

    @IsTest
    static void queueableProcessesClosedLostWithHardcodedGateway() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuoteWithScId(opportunityRecord, 'SC Event Quote 9', '2284006');
        ScOpportunityQuoteEventGateway.forceHardcodedResponse = true;

        Test.startTest();
        new ScOpportunityQuoteEventQueueable(
            opportunityRecord.Id,
            ScOpportunityQuoteEventRequest.EVENT_TYPE_OPPORTUNITY_CLOSED_LOST,
            null,
            new Set<Id>{ quoteRecord.Id },
            UserInfo.getUserId()
        ).execute(null);
        Test.stopTest();

        ScOpportunityQuoteEventGateway.forceHardcodedResponse = false;
    }

    @IsTest
    static void gatewayHardcodedResponseIsSuccessfulInTest() {
        ScOpportunityQuoteEventGateway.forceHardcodedResponse = true;

        ScOpportunityQuoteEventRequest request =
            ScOpportunityQuoteEventRequest.createForecastConfidenceUpdate(
                getTestOpportunity().Id,
                'Upside',
                new List<ScOpportunityQuoteEventRequest.QuoteEntry>{
                    buildQuoteEntry('464646', '0Q000000000000001')
                },
                '123456'
            );

        ScOpportunityQuoteEventGateway.CalloutResult result =
            ScOpportunityQuoteEventGateway.sendEvent(request);

        System.assertEquals(true, result.calloutSuccess);
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
            result.responseBody
        );
        List<Object> quotes = (List<Object>) responseMap.get('quotes');
        System.assertEquals(1, quotes.size());
        ScOpportunityQuoteEventGateway.forceHardcodedResponse = false;
    }

    @IsTest
    static void gatewayCanInvokeSoCalloutWithMockHttp() {
        registerCalloutMock();
        ScOpportunityQuoteEventRequest request =
            ScOpportunityQuoteEventRequest.createOpportunityClosedLost(
                getTestOpportunity().Id,
                'Closed Lost',
                new List<ScOpportunityQuoteEventRequest.QuoteEntry>{
                    buildQuoteEntry('464646', '0Q000000000000001')
                },
                '123456'
            );

        Test.startTest();
        ScOpportunityQuoteEventGateway.CalloutResult result =
            ScOpportunityQuoteEventGateway.sendEvent(request);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.calloutSuccess == true || String.isNotBlank(result.errorDetail));
    }

    @IsTest
    static void gatewayExtractsErrorDetailFromSoReturn() {
        System.assertEquals(
            'SO_Callout returned an empty response map',
            ScOpportunityQuoteEventGateway.extractErrorDetail(new Map<String, Object>())
        );
        System.assertEquals(
            'Boomi rejected the event',
            ScOpportunityQuoteEventGateway.extractErrorDetail(
                new Map<String, Object>{ 'SO_RETURN' => 'Boomi rejected the event' }
            )
        );
    }

    @IsTest
    static void gatewayExtractsResponseBodyFromServiceData() {
        System.assertEquals(
            '{"status":"success"}',
            ScOpportunityQuoteEventGateway.extractResponseBody(
                new Map<String, Object>{ 'SERVICE_DATA' => '{"status":"success"}' }
            )
        );
        System.assertEquals(
            null,
            ScOpportunityQuoteEventGateway.extractResponseBody(new Map<String, Object>())
        );
    }

    @IsTest
    static void gatewayExtractsErrorDetailFromHttpStatus() {
        System.assertEquals(
            'Opportunity Quote SC event callout failed with HTTP status 500: {"error":"failed"}',
            ScOpportunityQuoteEventGateway.extractErrorDetail(
                new Map<String, Object>{
                    'SERVICE_STATUS' => 500,
                    'SERVICE_DATA' => '{"error":"failed"}'
                }
            )
        );
        System.assertEquals(
            '200',
            ScOpportunityQuoteEventGateway.resolveHttpStatusForLog(
                new Map<String, Object>{ 'SERVICE_STATUS' => 200 }
            )
        );
        System.assertEquals(
            'n/a',
            ScOpportunityQuoteEventGateway.resolveHttpStatusForLog(new Map<String, Object>())
        );
    }

    private static Quote insertQuoteWithScId(
        Opportunity opportunityRecord,
        String quoteName,
        String salesConnectionQuoteId
    ) {
        Quote quoteRecord = insertQuote(opportunityRecord, quoteName, 'Open');
        quoteRecord.SalesConnectionQuoteID__c = salesConnectionQuoteId;
        update quoteRecord;
        return quoteRecord;
    }

    private static ScOpportunityQuoteEventRequest.QuoteEntry buildQuoteEntry(
        String salesConnectionQuoteId,
        String salesforceQuoteId
    ) {
        ScOpportunityQuoteEventRequest.QuoteEntry quoteEntry =
            new ScOpportunityQuoteEventRequest.QuoteEntry();
        quoteEntry.salesConnectionQuoteId = salesConnectionQuoteId;
        quoteEntry.salesforceQuoteId = salesforceQuoteId;
        return quoteEntry;
    }

    private static void registerCalloutMock() {
        mockCallCount = 0;
        Test.setMock(HttpCalloutMock.class, new CapturingHttpMock());
    }

    private static String buildEchoSuccessBody(String requestBody) {
        String forecastConfidence = 'Upside';
        String quoteStatus = 'N/A';
        List<Object> quotes = new List<Object>();

        if (String.isNotBlank(requestBody)) {
            Object deserialized = JSON.deserializeUntyped(requestBody);
            if (deserialized instanceof Map<String, Object>) {
                Map<String, Object> requestMap = (Map<String, Object>) deserialized;
                if (requestMap.get('forecastConfidence') != null) {
                    forecastConfidence = String.valueOf(requestMap.get('forecastConfidence'));
                }
                if (requestMap.get('quoteStatus') != null) {
                    quoteStatus = String.valueOf(requestMap.get('quoteStatus'));
                }
                Object quotesNode = requestMap.get('quotes');
                if (quotesNode instanceof List<Object>) {
                    quotes = (List<Object>) quotesNode;
                }
            }
        }

        return JSON.serialize(
            new Map<String, Object>{
                'status' => 'Success',
                'quoteStatus' => quoteStatus,
                'quoteForecastConfidence' => forecastConfidence,
                'quotes' => quotes
            }
        );
    }

    private static Opportunity getTestOpportunity() {
        return [
            SELECT Id, Pricebook2Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];
    }

    private static Opportunity buildOpportunity(
        String opportunityName,
        Id accountId,
        Id primaryContactId,
        Id pricebookId,
        String forecastConfidenceLevel
    ) {
        Opportunity opportunityRecord = new Opportunity(
            Name = opportunityName,
            AccountId = accountId,
            StageName = getValidStageName(),
            ForecastConfidenceLevel__c = forecastConfidenceLevel,
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

    private static Quote insertQuote(
        Opportunity opportunityRecord,
        String quoteName,
        String statusValue
    ) {
        Quote quoteRecord = buildQuote(opportunityRecord, quoteName, statusValue);
        insert quoteRecord;
        return quoteRecord;
    }

    private static Quote buildQuote(
        Opportunity opportunityRecord,
        String quoteName,
        String statusValue
    ) {
        Id hcSalesRecordTypeId = resolveHcSalesRecordTypeId();
        System.assertNotEquals(null, hcSalesRecordTypeId, 'HC_Sales quote record type is required.');

        return new Quote(
            Name = quoteName,
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            RecordTypeId = hcSalesRecordTypeId,
            Status = resolveQuoteStatus(statusValue),
            Forecast_Eligible__c = false,
            Quote_Total_Without_Freight__c = 1000,
            ExpirationDate = Date.today().addDays(30)
        );
    }

    private static Id resolveHcSalesRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName();

        if (!recordTypesByDeveloperName.containsKey(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME)) {
            return null;
        }

        Schema.RecordTypeInfo recordTypeInfo =
            recordTypesByDeveloperName.get(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME);
        return recordTypeInfo.isAvailable() ? recordTypeInfo.getRecordTypeId() : null;
    }

    private static String resolveQuoteStatus(String preferredValue) {
        if (String.isNotBlank(preferredValue)) {
            for (Schema.PicklistEntry picklistEntry : Quote.Status.getDescribe().getPicklistValues()) {
                if (picklistEntry.isActive() && picklistEntry.getValue().equalsIgnoreCase(preferredValue)) {
                    return picklistEntry.getValue();
                }
            }
        }

        for (Schema.PicklistEntry picklistEntry : Quote.Status.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return 'Open';
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

    @IsTest
    static void handleCalloutResultRejectsFailedCallout() {
        ScOpportunityQuoteEventGateway.CalloutResult calloutResult =
            new ScOpportunityQuoteEventGateway.CalloutResult();
        calloutResult.calloutSuccess = false;
        calloutResult.errorDetail = 'Boomi rejected the event';
        Boolean exceptionThrown = false;

        try {
            ScOpportunityQuoteEventService.handleCalloutResult(calloutResult);
        } catch (Exception exceptionValue) {
            exceptionThrown = true;
        }

        System.assert(exceptionThrown);
    }

    @IsTest
    static void validateSuccessResponseQuotesRejectsEmptyQuotesList() {
        ScOpportunityQuoteEventRequest request =
            ScOpportunityQuoteEventRequest.createForecastConfidenceUpdate(
                getTestOpportunity().Id,
                'Pipeline',
                new List<ScOpportunityQuoteEventRequest.QuoteEntry>{
                    buildQuoteEntry('2283624', '0Q000000000000001')
                },
                '123456'
            );
        Boolean exceptionThrown = false;

        try {
            ScOpportunityQuoteEventService.validateSuccessResponseQuotes(
                request,
                '{"status":"Success","quoteStatus":"N/A","quoteForecastConfidence":"Pipeline","quotes":[]}'
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
            System.assert(
                exceptionValue.getMessage()
                    .contains(ScOpportunityQuoteEventService.EMPTY_RESPONSE_QUOTES_MESSAGE)
            );
        }

        System.assert(exceptionThrown);
    }

    @IsTest
    static void resolveQuoteIdsFromResponseMatchesSalesConnectionQuoteId() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuoteWithScId(opportunityRecord, 'SC Match Quote', '2283624');
        String responseBody =
            '{"status":"Success","quoteForecastConfidence":"Upside","quoteStatus":"N/A","quotes":[' +
            '{"salesConnectionQuoteId":"2283624","salesforceQuoteId":"0Q000000000000099"}]}';

        Set<Id> matchedIds = ScOpportunityQuoteEventService.resolveQuoteIdsFromResponse(
            opportunityRecord.Id,
            responseBody,
            new Set<Id>{ quoteRecord.Id }
        );

        System.assertEquals(1, matchedIds.size());
        System.assert(matchedIds.contains(quoteRecord.Id));
    }

    @IsTest
    static void resolveQuoteIdsFromResponseRejectsUnknownSalesConnectionQuoteId() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuoteWithScId(opportunityRecord, 'SC Mismatch Quote', '2283624');
        Boolean exceptionThrown = false;

        try {
            ScOpportunityQuoteEventService.resolveQuoteIdsFromResponse(
                opportunityRecord.Id,
                '{"status":"Success","quotes":[{"salesConnectionQuoteId":"464646","salesforceQuoteId":"0Q0XXX"}]}',
                new Set<Id>{ quoteRecord.Id }
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }

        System.assert(exceptionThrown);
    }

    @IsTest
    static void parseQuoteEntriesReadsResponseQuotes() {
        List<ScOpportunityQuoteEventRequest.QuoteEntry> quoteEntries =
            ScOpportunityQuoteEventResponse.parseQuoteEntries(
                '{"status":"Success","quotes":[{"salesConnectionQuoteId":"464646","salesforceQuoteId":"0Q0XXX"}]}'
            );

        System.assertEquals(1, quoteEntries.size());
        System.assertEquals('464646', quoteEntries[0].salesConnectionQuoteId);
    }

    @IsTest
    static void resolveHelpersUseResponseValuesWhenPresent() {
        ScOpportunityQuoteEventResponse response = ScOpportunityQuoteEventResponse.parse(
            '{"status":"Success","quoteForecastConfidence":"Pipeline","quoteStatus":"Closed"}'
        );

        System.assertEquals(
            'Pipeline',
            ScOpportunityQuoteEventService.resolveForecastConfidenceForApply(response, 'Upside')
        );
        System.assertEquals(
            'Closed',
            ScOpportunityQuoteEventService.resolveQuoteStatusForApply(
                response,
                QuoteSelector.CLOSED_STATUS_VALUE
            )
        );
    }

    @IsTest
    static void hasQuotesWithSalesConnectionIdDetectsPopulatedField() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteWithScId = insertQuoteWithScId(opportunityRecord, 'SC Event Quote 13', '2283713');
        Quote quoteWithoutScId = insertQuote(opportunityRecord, 'SC Event Quote 14', 'Open');

        System.assertEquals(
            true,
            ScOpportunityQuoteEventService.hasQuotesWithSalesConnectionId(
                new Set<Id>{ quoteWithScId.Id, quoteWithoutScId.Id }
            )
        );
        System.assertEquals(
            false,
            ScOpportunityQuoteEventService.hasQuotesWithSalesConnectionId(
                new Set<Id>{ quoteWithoutScId.Id }
            )
        );
    }

    @IsTest
    static void applyServiceRejectsBlankForecastConfidence() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'SC Event Quote Apply 3', 'Open');
        Boolean exceptionThrown = false;

        try {
            ScOpportunityQuoteEventApplyService.applyForecastConfidence(
                new Set<Id>{ quoteRecord.Id },
                ''
            );
        } catch (Exception exceptionValue) {
            exceptionThrown = true;
        }

        System.assert(exceptionThrown);
    }

    @IsTest
    static void applyServiceUsesDefaultClosedStatusWhenBlank() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'SC Event Quote Apply 4', 'Open');

        ScOpportunityQuoteEventApplyService.applyQuoteStatus(
            new Set<Id>{ quoteRecord.Id },
            null
        );

        quoteRecord = [
            SELECT Status
            FROM Quote
            WHERE Id = :quoteRecord.Id
            LIMIT 1
        ];
        System.assertEquals(QuoteSelector.CLOSED_STATUS_VALUE, quoteRecord.Status);
    }

    @IsTest
    static void synchronizeForecastConfidenceRequiresForecastValue() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuoteWithScId(opportunityRecord, 'SC Event Quote 15', '2283715');
        Boolean exceptionThrown = false;

        try {
            ScOpportunityQuoteEventService.synchronizeForecastConfidenceUpdate(
                opportunityRecord.Id,
                '',
                new Set<Id>{ quoteRecord.Id },
                UserInfo.getUserId()
            );
        } catch (Exception exceptionValue) {
            exceptionThrown = true;
        }

        System.assert(exceptionThrown);
    }

    private static String getValidQuoteForecastConfidence() {
        for (Schema.PicklistEntry picklistEntry :
            Quote.QuoteForecastConfidence__c.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return 'Upside';
    }

    private static String resolveValidForecastConfidenceLevel(String preferredValue) {
        if (String.isNotBlank(preferredValue)) {
            for (Schema.PicklistEntry picklistEntry :
                Opportunity.ForecastConfidenceLevel__c.getDescribe().getPicklistValues()) {
                if (picklistEntry.isActive() && picklistEntry.getValue().equalsIgnoreCase(preferredValue)) {
                    return picklistEntry.getValue();
                }
            }
        }

        for (Schema.PicklistEntry picklistEntry :
            Opportunity.ForecastConfidenceLevel__c.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }
}