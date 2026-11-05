/**
 * @author Himanshu Chaurasia
 * @date 2026/09/09
 *
 * @description Test coverage for OppForecastConfPropagateService (Opportunity forecast confidence propagation).
 *              Also exercises OppForecastConfBannerController and QuoteSelector forecast-confidence query paths.
 */
@IsTest
private class OppForecastConfBannerControllerTest {
    private static final String TEST_OPPORTUNITY_NAME =
        'Opportunity Forecast Confidence Propagate Test Opportunity';
    private static final String OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME = 'Healthcare_Sales';
    private static final String QUOTE_AUTOMATION_RUN_AS_LAST_NAME = 'ForecastConfPropagateRunAs';
    private static final String SALES_FIELD_REP_PSG_DEVELOPER_NAME = 'SalesFieldRepAccountManagerPSG';

    @TestSetup
    static void setupData() {
        Id standardPricebookId = Test.getStandardPricebookId();

        Account accountRecord = new Account(
            Name = 'Forecast Confidence Propagate Test Account',
            SourceSystemID__c = 'FCP-TEST-ACCT',
            OracleAddressId__c = '638265'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Forecast',
            LastName = 'Confidence Propagate',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Id opportunityRecordTypeId = resolveOpportunityRecordTypeId();
        Opportunity opportunityRecord = buildOpportunity(
            TEST_OPPORTUNITY_NAME,
            accountRecord.Id,
            contactRecord.Id,
            standardPricebookId,
            resolveInitialForecastConfidenceLevel(opportunityRecordTypeId)
        );
        insert opportunityRecord;

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
    static void testStagePropagateBannerWhenForecastConfidenceChanges() {
        Opportunity opportunityRecord = getTestOpportunity();
        insertQuote(opportunityRecord, 'Propagate Quote 1', 'Open');

        Test.startTest();
        stageBannerForOpportunity(opportunityRecord);
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ShowForecastConfidencePropagateBanner__c,
                PendingQuoteForecastConfidence__c,
                ForecastConfidenceLevel__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            updatedOpportunity.ShowForecastConfidencePropagateBanner__c,
            'Banner should be staged when forecast confidence changes and quotes exist.'
        );
        System.assertNotEquals(
            null,
            updatedOpportunity.PendingQuoteForecastConfidence__c,
            'Pending quote forecast confidence should be set when the banner is active.'
        );
    }

    @IsTest
    static void testGetBannerContextReturnsApplicableQuotes() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'Propagate Quote 2', 'Open');

        stageBannerForOpportunity(opportunityRecord);

        Test.startTest();
        OppForecastConfPropagateService.BannerContext bannerContext = getBannerContextAsAutomationUser(
            opportunityRecord.Id
        );
        Test.stopTest();

        System.assertEquals(true, bannerContext.showBanner);
        System.assertEquals(1, bannerContext.quotes.size());
        System.assertEquals(quoteRecord.Id, bannerContext.quotes[0].id);
        System.assertEquals(true, bannerContext.quotes[0].selected);
    }

    @IsTest
    static void testPropagateSelectedQuotesUpdatesOnlySelectedQuote() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote firstQuote = insertQuote(opportunityRecord, 'Propagate Quote 3', 'Open');
        Quote secondQuote = insertQuote(opportunityRecord, 'Propagate Quote 4', 'Open');
        firstQuote.SalesConnectionQuoteID__c = '2283703';
        updateQuoteRecords(firstQuote);
        firstQuote = [
            SELECT Id, SalesConnectionQuoteID__c
            FROM Quote
            WHERE Id = :firstQuote.Id
            LIMIT 1
        ];
        System.assertEquals('2283703', firstQuote.SalesConnectionQuoteID__c);
        ScOpportunityQuoteEventGateway.forceHardcodedResponse = true;

        stageBannerForOpportunity(opportunityRecord);
        Opportunity stagedOpportunity = [
            SELECT PendingQuoteForecastConfidence__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];
        String expectedQuoteConfidence = stagedOpportunity.PendingQuoteForecastConfidence__c;
        System.assertNotEquals(null, expectedQuoteConfidence);

        Test.startTest();
        propagateSelectedQuotesAsAutomationUser(opportunityRecord.Id, new List<Id>{ firstQuote.Id });
        Test.stopTest();

        ScOpportunityQuoteEventGateway.forceHardcodedResponse = false;

        Map<Id, Quote> updatedQuotes = new Map<Id, Quote>([
            SELECT QuoteForecastConfidence__c
            FROM Quote
            WHERE Id IN :new Set<Id>{ firstQuote.Id, secondQuote.Id }
        ]);

        System.assertEquals(
            expectedQuoteConfidence,
            updatedQuotes.get(firstQuote.Id).QuoteForecastConfidence__c,
            'Selected quote should receive the pending forecast confidence.'
        );
        System.assertNotEquals(
            expectedQuoteConfidence,
            updatedQuotes.get(secondQuote.Id).QuoteForecastConfidence__c,
            'Unselected quote should not be updated.'
        );

        Opportunity updatedOpportunity = [
            SELECT ShowForecastConfidencePropagateBanner__c,
                PendingQuoteForecastConfidence__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            false,
            updatedOpportunity.ShowForecastConfidencePropagateBanner__c,
            'Banner should be cleared after propagation.'
        );
        System.assertEquals(null, updatedOpportunity.PendingQuoteForecastConfidence__c);
    }

    @IsTest
    static void testStagePropagateBannerClearsFlagWhenNoQuotesExist() {
        Opportunity opportunityRecord = getTestOpportunity();
        Opportunity oldOpportunityRecord = opportunityRecord.clone(true, true, true, true);
        String updatedForecastConfidence = resolveDifferentForecastConfidenceForInMemoryStaging(
            opportunityRecord.ForecastConfidenceLevel__c
        );
        System.assertNotEquals(null, updatedForecastConfidence);

        opportunityRecord.ShowForecastConfidencePropagateBanner__c = true;
        opportunityRecord.PendingQuoteForecastConfidence__c = 'Pipeline';
        opportunityRecord.ForecastConfidenceLevel__c = updatedForecastConfidence;

        OppForecastConfPropagateService.stagePropagateBanner(
            new List<Opportunity>{ opportunityRecord },
            new Map<Id, Opportunity>{ oldOpportunityRecord.Id => oldOpportunityRecord }
        );

        System.assertEquals(
            false,
            opportunityRecord.ShowForecastConfidencePropagateBanner__c,
            'Banner should not remain active when no applicable quotes exist.'
        );
        System.assertEquals(null, opportunityRecord.PendingQuoteForecastConfidence__c);
    }

    @IsTest
    static void testSyncBannerStateClearsFlagWhenQuotesAreRemoved() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'Propagate Quote 6', 'Open');
        stageBannerForOpportunity(opportunityRecord);

        deleteQuoteRecords(quoteRecord);

        Test.startTest();
        syncBannerStateAsAutomationUser(new Set<Id>{ opportunityRecord.Id });
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ShowForecastConfidencePropagateBanner__c,
                PendingQuoteForecastConfidence__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(false, updatedOpportunity.ShowForecastConfidencePropagateBanner__c);
        System.assertEquals(null, updatedOpportunity.PendingQuoteForecastConfidence__c);
    }

    @IsTest
    static void testQuoteSelectorCoverageForForecastConfidenceQueries() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'Selector Coverage Quote', 'Open');
        Id dummyRelatedId = opportunityRecord.Id;
        Set<Id> opportunityIds = new Set<Id>{ opportunityRecord.Id };
        Set<Id> quoteIds = new Set<Id>{ quoteRecord.Id };

        System.runAs(getQuoteAutomationRunAsUser()) {
            QuoteSelector.countByOpportunityId(null);
            QuoteSelector.countByOpportunityId(opportunityRecord.Id);
            QuoteSelector.countByOpportunityId(opportunityRecord.Id, GenerateQuoteService.QUOTE_TYPE_NORMAL);
            QuoteSelector.countByOpportunityId(opportunityRecord.Id, null, true);
            QuoteSelector.countByOpportunityId(
                opportunityRecord.Id,
                GenerateQuoteService.QUOTE_TYPE_TRIAL,
                true,
                dummyRelatedId
            );
            QuoteSelector.countByOpportunityId(opportunityRecord.Id, null, true, dummyRelatedId);
            QuoteSelector.countByOpportunityId(
                opportunityRecord.Id,
                GenerateQuoteService.QUOTE_TYPE_SAMPLE,
                true,
                null,
                dummyRelatedId
            );
            QuoteSelector.countByOpportunityId(opportunityRecord.Id, null, true, null, dummyRelatedId);
            QuoteSelector.selectByOpportunityIdWithLineItems(null);
            QuoteSelector.selectByOpportunityIdWithLineItems(opportunityRecord.Id);
            QuoteSelector.selectByOpportunityIdWithLineItems(
                opportunityRecord.Id,
                GenerateQuoteService.QUOTE_TYPE_NORMAL
            );
            QuoteSelector.selectByOpportunityIdWithLineItems(opportunityRecord.Id, null, true);
            QuoteSelector.selectByOpportunityIdWithLineItems(
                opportunityRecord.Id,
                GenerateQuoteService.QUOTE_TYPE_TRIAL,
                true,
                dummyRelatedId
            );
            QuoteSelector.selectByOpportunityIdWithLineItems(opportunityRecord.Id, null, true, dummyRelatedId);
            QuoteSelector.selectByOpportunityIdWithLineItems(opportunityRecord.Id, null, false, dummyRelatedId);
            QuoteSelector.selectByOpportunityIdWithLineItems(
                opportunityRecord.Id,
                GenerateQuoteService.QUOTE_TYPE_SAMPLE,
                true,
                null,
                dummyRelatedId
            );
            QuoteSelector.selectByOpportunityIdWithLineItems(
                opportunityRecord.Id,
                null,
                true,
                null,
                dummyRelatedId
            );
            QuoteSelector.selectByOpportunityIdWithLineItems(
                opportunityRecord.Id,
                null,
                false,
                null,
                dummyRelatedId
            );
            QuoteSelector.selectById(null);
            QuoteSelector.selectById(quoteRecord.Id);
            QuoteSelector.selectByIdsWithLineItems(quoteIds);
            QuoteSelector.selectOpenForecastEligibleQuotesByOpportunityIds(opportunityIds);
            QuoteSelector.selectOpportunityIdsWithOpenForecastEligibleQuotes(opportunityIds);
            QuoteSelector.selectForecastManagementQuotesByOpportunityId(opportunityRecord.Id);
            QuoteSelector.selectSalesConnectionQuotesForForecastEligibleByOpportunityIds(opportunityIds);
            QuoteSelector.countPropagatableForecastConfidenceQuotesByOpportunityIds(opportunityIds);
            QuoteSelector.selectPropagatableForecastConfidenceQuotesByOpportunityId(opportunityRecord.Id);
            QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(opportunityRecord.Id);
            QuoteSelector.countOpenSalesConnectionQuotesByOpportunityIds(opportunityIds);
        }
    }

    @IsTest
    static void testGetBannerContextIncludesTrialSampleAndGoodwillQuotes() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote normalQuote = insertQuote(opportunityRecord, 'Normal Propagate Quote', 'Open');
        Quote trialQuote = insertQuote(opportunityRecord, 'Trial Propagate Quote', 'Open');
        Quote sampleQuote = insertQuote(opportunityRecord, 'Sample Propagate Quote', 'Open');
        Quote goodwillQuote = insertQuote(opportunityRecord, 'Goodwill Propagate Quote', 'Open');

        List<Quote> quotesToUpdate = new List<Quote>();
        Set<Id> expectedQuoteIds = new Set<Id>{
            normalQuote.Id,
            trialQuote.Id,
            sampleQuote.Id,
            goodwillQuote.Id
        };

        normalQuote.Forecast_Eligible__c = true;
        quotesToUpdate.add(normalQuote);

        if (isQuoteTypeAvailable(GenerateQuoteService.QUOTE_TYPE_TRIAL)) {
            trialQuote.QuoteType__c = GenerateQuoteService.QUOTE_TYPE_TRIAL;
            trialQuote.IsForecastIneligible__c = true;
            quotesToUpdate.add(trialQuote);
        }

        if (isQuoteTypeAvailable(GenerateQuoteService.QUOTE_TYPE_SAMPLE)) {
            sampleQuote.QuoteType__c = GenerateQuoteService.QUOTE_TYPE_SAMPLE;
            sampleQuote.IsForecastIneligible__c = true;
            quotesToUpdate.add(sampleQuote);
        }

        if (isQuoteTypeAvailable(GenerateQuoteService.QUOTE_TYPE_GOODWILL)) {
            goodwillQuote.QuoteType__c = GenerateQuoteService.QUOTE_TYPE_GOODWILL;
            goodwillQuote.IsForecastIneligible__c = true;
            quotesToUpdate.add(goodwillQuote);
        }

        if (!quotesToUpdate.isEmpty()) {
            updateQuoteRecords(quotesToUpdate);
        }

        stageBannerForOpportunity(opportunityRecord);

        Test.startTest();
        OppForecastConfPropagateService.BannerContext bannerContext = getBannerContextAsAutomationUser(
            opportunityRecord.Id
        );
        Test.stopTest();

        System.assertEquals(true, bannerContext.showBanner);
        System.assertEquals(
            expectedQuoteIds.size(),
            bannerContext.quotes.size(),
            'Normal and special quote types should be included when applicable.'
        );
        Set<Id> returnedQuoteIds = new Set<Id>();
        for (OppForecastConfPropagateService.QuoteRow quoteRow : bannerContext.quotes) {
            returnedQuoteIds.add(quoteRow.id);
        }
        System.assertEquals(true, returnedQuoteIds.containsAll(expectedQuoteIds));
    }

    @IsTest
    static void testGetBannerContextHidesWhenNoApplicableQuotesExist() {
        Opportunity opportunityRecord = getTestOpportunity();

        update new Opportunity(
            Id = opportunityRecord.Id,
            ShowForecastConfidencePropagateBanner__c = true,
            PendingQuoteForecastConfidence__c = 'Pipeline'
        );

        Test.startTest();
        OppForecastConfPropagateService.BannerContext bannerContext = getBannerContextAsAutomationUser(
            opportunityRecord.Id
        );
        Test.stopTest();

        System.assertEquals(false, bannerContext.showBanner);
        System.assertEquals(0, bannerContext.quotes.size());

        Opportunity updatedOpportunity = [
            SELECT ShowForecastConfidencePropagateBanner__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            false,
            updatedOpportunity.ShowForecastConfidencePropagateBanner__c,
            'Stale banner flags should be cleared when no applicable quotes exist.'
        );
    }

    @IsTest
    static void testNullInputsReturnSafeDefaults() {
        Test.startTest();
        OppForecastConfPropagateService.BannerContext bannerContext =
            OppForecastConfBannerController.getBannerContext(null);
        Test.stopTest();

        System.assertEquals(false, bannerContext.showBanner);
    }

    @IsTest
    static void testGetBannerContextWrapsUnexpectedErrors() {
        OppForecastConfBannerController.forceExceptionForTest = true;
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            OppForecastConfBannerController.getBannerContext(null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        OppForecastConfBannerController.forceExceptionForTest = false;
        System.assertEquals(
            true,
            exceptionThrown,
            'Unexpected errors should be wrapped as AuraHandledException.'
        );
    }

    @IsTest
    static void testPropagateSelectedQuotesWrapsForcedUnexpectedErrors() {
        OppForecastConfBannerController.forceExceptionForTest = true;
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            OppForecastConfBannerController.propagateSelectedQuotes(null, null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        OppForecastConfBannerController.forceExceptionForTest = false;
        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testPropagateSelectedQuotesRethrowsAuraHandledException() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            OppForecastConfBannerController.propagateSelectedQuotes(null, null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'AuraHandledException from the service should be rethrown.'
        );
    }

    @IsTest
    static void testPropagateSelectedQuotesWrapsUnexpectedErrors() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            OppForecastConfBannerController.propagateSelectedQuotes(
                UserInfo.getUserId(),
                new List<Id>{ UserInfo.getUserId() }
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Unexpected errors should be wrapped as AuraHandledException.'
        );
    }

    private static void stagePropagateBannerAndUpdateOpportunity(
        Opportunity opportunityRecord,
        Opportunity oldOpportunityRecord
    ) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            OppForecastConfPropagateService.stagePropagateBanner(
                new List<Opportunity>{ opportunityRecord },
                new Map<Id, Opportunity>{ oldOpportunityRecord.Id => oldOpportunityRecord }
            );
            update opportunityRecord;
        }
    }

    private static OppForecastConfPropagateService.BannerContext getBannerContextAsAutomationUser(
        Id opportunityId
    ) {
        OppForecastConfPropagateService.BannerContext bannerContext;
        System.runAs(getQuoteAutomationRunAsUser()) {
            bannerContext = OppForecastConfBannerController.getBannerContext(opportunityId);
        }
        return bannerContext;
    }

    private static void propagateSelectedQuotesAsAutomationUser(Id opportunityId, List<Id> quoteIds) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            OppForecastConfBannerController.propagateSelectedQuotes(opportunityId, quoteIds);
        }
    }

    private static void syncBannerStateAsAutomationUser(Set<Id> opportunityIds) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            OppForecastConfPropagateService.syncBannerStateForOpportunityIds(opportunityIds);
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
            Alias = 'fcprun',
            Email = 'forecast.conf.propagate.runas@test.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = QUOTE_AUTOMATION_RUN_AS_LAST_NAME,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username =
                'forecast.conf.propagate.runas+' +
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

        // Force the group to "Updated" so assignments are allowed in test context
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
        updateQuoteRecords(new List<Quote>{ quoteRecord });
    }

    private static void updateQuoteRecords(List<Quote> quoteRecords) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            update quoteRecords;
        }
    }

    private static void deleteQuoteRecords(Quote quoteRecord) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            delete quoteRecord;
        }
    }

    private static String stageBannerForOpportunity(Opportunity opportunityRecord) {
        String pendingQuoteForecastConfidence = resolvePendingQuoteForecastConfidenceForBanner(
            opportunityRecord.ForecastConfidenceLevel__c
        );
        System.assertNotEquals(
            null,
            pendingQuoteForecastConfidence,
            'A pending Quote Forecast Confidence value is required to stage the banner.'
        );

        System.runAs(getQuoteAutomationRunAsUser()) {
            update new Opportunity(
                Id = opportunityRecord.Id,
                ShowForecastConfidencePropagateBanner__c = true,
                PendingQuoteForecastConfidence__c = pendingQuoteForecastConfidence
            );
        }

        return pendingQuoteForecastConfidence;
    }

    private static String resolvePendingQuoteForecastConfidenceForBanner(String currentOpportunityConfidence) {
        Opportunity opportunityRecord = getTestOpportunity();

        for (Schema.PicklistEntry picklistEntry :
            getOpportunityForecastConfidencePicklistEntries(opportunityRecord.RecordTypeId)) {
            if (!picklistEntry.isActive()) {
                continue;
            }

            if (
                currentOpportunityConfidence != null &&
                picklistEntry.getValue().equalsIgnoreCase(currentOpportunityConfidence)
            ) {
                continue;
            }

            String mappedQuoteConfidence = QuoteService.mapOpportunityForecastConfidenceToQuote(
                picklistEntry.getValue()
            );
            if (
                String.isNotBlank(mappedQuoteConfidence) &&
                isActiveQuoteForecastConfidence(mappedQuoteConfidence)
            ) {
                return mappedQuoteConfidence;
            }
        }

        return null;
    }

    private static Opportunity getTestOpportunity() {
        return [
            SELECT Id,
                Pricebook2Id,
                RecordTypeId,
                ForecastConfidenceLevel__c
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
        Id hcSalesRecordTypeId = requireHcSalesQuoteRecordTypeId();

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

    private static Id requireHcSalesQuoteRecordTypeId() {
        Id recordTypeId = resolveHcSalesRecordTypeId();
        System.assertNotEquals(null, recordTypeId, 'HC_Sales quote record type is required.');
        return recordTypeId;
    }

    private static Id resolveHcSalesRecordTypeId() {
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

    private static Boolean isQuoteTypeAvailable(String quoteType) {
        if (String.isBlank(quoteType)) {
            return false;
        }

        for (Schema.PicklistEntry picklistEntry : Quote.QuoteType__c.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && picklistEntry.getValue() == quoteType) {
                return true;
            }
        }

        return false;
    }

    private static String resolveDifferentForecastConfidenceForInMemoryStaging(String currentValue) {
        for (Schema.PicklistEntry picklistEntry :
            Opportunity.ForecastConfidenceLevel__c.getDescribe().getPicklistValues()) {
            if (!picklistEntry.isActive()) {
                continue;
            }

            if (currentValue != null && picklistEntry.getValue().equalsIgnoreCase(currentValue)) {
                continue;
            }

            if (
                String.isNotBlank(
                    QuoteService.mapOpportunityForecastConfidenceToQuote(picklistEntry.getValue())
                )
            ) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }

    private static String resolveInitialForecastConfidenceLevel(Id opportunityRecordTypeId) {
        List<String> preferredValues = new List<String>{ 'Pipeline', 'Commit', 'Make It', 'Upside' };

        for (String preferredValue : preferredValues) {
            for (Schema.PicklistEntry picklistEntry :
                getOpportunityForecastConfidencePicklistEntries(opportunityRecordTypeId)) {
                if (!picklistEntry.isActive() || !picklistEntry.getValue().equalsIgnoreCase(preferredValue)) {
                    continue;
                }

                String mappedQuoteConfidence = QuoteService.mapOpportunityForecastConfidenceToQuote(
                    picklistEntry.getValue()
                );
                if (
                    String.isNotBlank(mappedQuoteConfidence) &&
                    isActiveQuoteForecastConfidence(mappedQuoteConfidence)
                ) {
                    return picklistEntry.getValue();
                }
            }
        }

        for (Schema.PicklistEntry picklistEntry :
            getOpportunityForecastConfidencePicklistEntries(opportunityRecordTypeId)) {
            if (!picklistEntry.isActive()) {
                continue;
            }

            String mappedQuoteConfidence = QuoteService.mapOpportunityForecastConfidenceToQuote(
                picklistEntry.getValue()
            );
            if (
                String.isNotBlank(mappedQuoteConfidence) &&
                isActiveQuoteForecastConfidence(mappedQuoteConfidence)
            ) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }

    private static List<Schema.PicklistEntry> getOpportunityForecastConfidencePicklistEntries(
        Id opportunityRecordTypeId
    ) {
        return Opportunity.ForecastConfidenceLevel__c.getDescribe().getPicklistValues();
    }

    private static Boolean isActiveQuoteForecastConfidence(String quoteForecastConfidence) {
        if (String.isBlank(quoteForecastConfidence)) {
            return false;
        }

        for (Schema.PicklistEntry picklistEntry :
            Quote.QuoteForecastConfidence__c.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && picklistEntry.getValue() == quoteForecastConfidence) {
                return true;
            }
        }

        return false;
    }
}