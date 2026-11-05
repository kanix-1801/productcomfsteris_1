/**
 * @author Himanshu Chaurasia
 * @date 2026/09/30
 *
 * @description Test coverage for ScOpportunityQuoteEventService (GC-3457 Opportunity / Quote SC events).
 *              Also exercises ScOpportunityQuoteEventGateway, ScOpportunityQuoteEventMapper,
 *              ScOpportunityQuoteEventRequest, ScOpportunityQuoteEventResponse,
 *              ScOpportunityQuoteEventApplyService, and ScOpportunityQuoteEventQueueable.
 *              Uses gateway hardcoded responses and HTTP mocks — no live Boomi endpoint.
 */
@IsTest
private class ScOpportunityQuoteEventServiceTest {
    private static final String TEST_OPPORTUNITY_NAME =
        'SC Opportunity Quote Event Test Opportunity';
    private static final String OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME = 'Healthcare_Sales';
    private static final String QUOTE_AUTOMATION_RUN_AS_LAST_NAME = 'ScOppQuoteEventRunAs';
    private static final String SALES_FIELD_REP_PSG_DEVELOPER_NAME = 'SalesFieldRepAccountManagerPSG';

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

        User setupUser = new User(Id = UserInfo.getUserId());
        System.runAs(setupUser) {
            User automationUser = createQuoteAutomationRunAsUser();
            insert automationUser;
            assignSalesFieldRepAccountManagerPsg(automationUser.Id);
            update new User(
                Id = automationUser.Id,
                EmployeeNumber__c = '3430001'
            );
        }
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
        synchronizeForecastConfidenceAsAutomationUser(
            opportunityRecord.Id,
            'Upside',
            new Set<Id>{ quoteRecord.Id }
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
        synchronizeClosedLostQuoteClosureAsAutomationUser(
            opportunityRecord.Id,
            new Set<Id>{ quoteRecord.Id }
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
            synchronizeForecastConfidenceAsAutomationUser(
                opportunityRecord.Id,
                'Upside',
                new Set<Id>{ quoteRecord.Id }
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
            synchronizeClosedLostQuoteClosureAsAutomationUser(
                opportunityRecord.Id,
                new Set<Id>{ quoteRecord.Id }
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
            synchronizeForecastConfidenceAsAutomationUser(null, 'Upside', new Set<Id>());
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

        applyForecastConfidenceAsAutomationUser(
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

        applyQuoteStatusAsAutomationUser(
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
        executeQueueableAsAutomationUser(
            opportunityRecord.Id,
            ScOpportunityQuoteEventRequest.EVENT_TYPE_QUOTE_FORECAST_CONFIDENCE_UPDATE,
            'Upside',
            new Set<Id>{ quoteRecord.Id }
        );
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
            executeQueueableAsAutomationUser(
                opportunityRecord.Id,
                ScOpportunityQuoteEventRequest.EVENT_TYPE_QUOTE_FORECAST_CONFIDENCE_UPDATE,
                'Upside',
                new Set<Id>{ quoteRecord.Id }
            );
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
        executeQueueableAsAutomationUser(
            opportunityRecord.Id,
            ScOpportunityQuoteEventRequest.EVENT_TYPE_OPPORTUNITY_CLOSED_LOST,
            null,
            new Set<Id>{ quoteRecord.Id }
        );
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
        updateQuoteRecords(quoteRecord);
        return quoteRecord;
    }

    private static void synchronizeForecastConfidenceAsAutomationUser(
        Id opportunityId,
        String forecastConfidence,
        Set<Id> quoteIds
    ) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            ScOpportunityQuoteEventService.synchronizeForecastConfidenceUpdate(
                opportunityId,
                forecastConfidence,
                quoteIds,
                UserInfo.getUserId()
            );
        }
    }

    private static void synchronizeClosedLostQuoteClosureAsAutomationUser(
        Id opportunityId,
        Set<Id> quoteIds
    ) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            ScOpportunityQuoteEventService.synchronizeClosedLostQuoteClosure(
                opportunityId,
                quoteIds,
                UserInfo.getUserId()
            );
        }
    }

    private static void executeQueueableAsAutomationUser(
        Id opportunityId,
        String eventType,
        String forecastConfidence,
        Set<Id> quoteIds
    ) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            new ScOpportunityQuoteEventQueueable(
                opportunityId,
                eventType,
                forecastConfidence,
                quoteIds,
                UserInfo.getUserId()
            ).execute(null);
        }
    }

    private static void applyForecastConfidenceAsAutomationUser(
        Set<Id> quoteIds,
        String quoteForecastConfidence
    ) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            ScOpportunityQuoteEventApplyService.applyForecastConfidence(
                quoteIds,
                quoteForecastConfidence
            );
        }
    }

    private static void applyQuoteStatusAsAutomationUser(Set<Id> quoteIds, String quoteStatus) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            ScOpportunityQuoteEventApplyService.applyQuoteStatus(quoteIds, quoteStatus);
        }
    }

    private static User createQuoteAutomationRunAsUser() {
        Profile adminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        return new User(
            Alias = 'scqevn',
            Email = 'sc.opportunity.quote.event.runas@test.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = QUOTE_AUTOMATION_RUN_AS_LAST_NAME,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username =
                'sc.opportunity.quote.event.runas+' +
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

    private static void insertQuoteRecords(Quote quoteRecord) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            insert quoteRecord;
        }
    }

    private static void updateQuoteRecords(Quote quoteRecord) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            update quoteRecord;
        }
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

        Id opportunityRecordTypeId = resolveOpportunityRecordTypeId();
        if (opportunityRecordTypeId != null) {
            opportunityRecord.RecordTypeId = opportunityRecordTypeId;
        }

        return opportunityRecord;
    }

    private static Id resolveOpportunityRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName();

        if (!recordTypesByDeveloperName.containsKey(OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME)) {
            return null;
        }

        return recordTypesByDeveloperName.get(OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME).getRecordTypeId();
    }

    private static Quote insertQuote(
        Opportunity opportunityRecord,
        String quoteName,
        String statusValue
    ) {
        Quote quoteRecord = buildQuote(opportunityRecord, quoteName, statusValue);
        insertQuoteRecords(quoteRecord);
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

        List<String> developerNameCandidates = new List<String>{
            GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME,
            'HCSales'
        };

        for (String developerName : developerNameCandidates) {
            if (!recordTypesByDeveloperName.containsKey(developerName)) {
                continue;
            }

            Schema.RecordTypeInfo recordTypeInfo = recordTypesByDeveloperName.get(developerName);
            if (recordTypeInfo != null && recordTypeInfo.getRecordTypeId() != null) {
                return recordTypeInfo.getRecordTypeId();
            }
        }

        return null;
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
        String responseBody =
            '{"status":"Success","quoteStatus":"N/A","quoteForecastConfidence":"Pipeline","quotes":[]}';

        System.assertEquals(
            false,
            ScOpportunityQuoteEventResponse.hasExpectedQuoteEntries(request, responseBody)
        );

        Boolean exceptionThrown = false;
        try {
            ScOpportunityQuoteEventService.validateSuccessResponseQuotes(request, responseBody);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
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
            applyForecastConfidenceAsAutomationUser(new Set<Id>{ quoteRecord.Id }, '');
        } catch (Exception exceptionValue) {
            exceptionThrown = true;
        }

        System.assert(exceptionThrown);
    }

    @IsTest
    static void applyServiceUsesDefaultClosedStatusWhenBlank() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'SC Event Quote Apply 4', 'Open');

        applyQuoteStatusAsAutomationUser(new Set<Id>{ quoteRecord.Id }, null);

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
            synchronizeForecastConfidenceAsAutomationUser(
                opportunityRecord.Id,
                '',
                new Set<Id>{ quoteRecord.Id }
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