/**
 * @author Himanshu Chaurasia
 * @date 2026/09/09
 *
 * @description Test class for Opportunity forecast confidence propagation banner.
 */
@IsTest
private class OppForecastConfBannerControllerTest {
    private static final String TEST_OPPORTUNITY_NAME =
        'Opportunity Forecast Confidence Propagate Test Opportunity';
    private static final String OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME = 'Healthcare_Sales';

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

        Opportunity opportunityRecord = buildOpportunity(
            TEST_OPPORTUNITY_NAME,
            accountRecord.Id,
            contactRecord.Id,
            standardPricebookId,
            resolveValidForecastConfidenceLevel('Pipeline')
        );
        insert opportunityRecord;
    }

    @IsTest
    static void testStagePropagateBannerWhenForecastConfidenceChanges() {
        Opportunity opportunityRecord = getTestOpportunity();
        insertQuote(opportunityRecord, 'Propagate Quote 1', 'Open');

        Opportunity oldOpportunityRecord = opportunityRecord.clone(true, true, true, true);
        String updatedForecastConfidence = resolveDifferentForecastConfidenceLevel(
            opportunityRecord.ForecastConfidenceLevel__c
        );
        System.assertNotEquals(null, updatedForecastConfidence, 'A second forecast confidence value is required.');

        opportunityRecord.ForecastConfidenceLevel__c = updatedForecastConfidence;

        Test.startTest();
        OppForecastConfPropagateService.stagePropagateBanner(
            new List<Opportunity>{ opportunityRecord },
            new Map<Id, Opportunity>{ oldOpportunityRecord.Id => oldOpportunityRecord }
        );
        update opportunityRecord;
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
        System.assertEquals(
            QuoteService.mapOpportunityForecastConfidenceToQuote(updatedForecastConfidence),
            updatedOpportunity.PendingQuoteForecastConfidence__c,
            'Pending quote forecast confidence should match the mapped Opportunity value.'
        );
    }

    @IsTest
    static void testGetBannerContextReturnsApplicableQuotes() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'Propagate Quote 2', 'Open');

        stageBannerForOpportunity(opportunityRecord);

        Test.startTest();
        OppForecastConfPropagateService.BannerContext bannerContext =
            OppForecastConfBannerController.getBannerContext(opportunityRecord.Id);
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
        update firstQuote;
        firstQuote = [
            SELECT Id, SalesConnectionQuoteID__c
            FROM Quote
            WHERE Id = :firstQuote.Id
            LIMIT 1
        ];
        System.assertEquals('2283703', firstQuote.SalesConnectionQuoteID__c);
        ScOpportunityQuoteEventGateway.forceHardcodedResponse = true;

        String updatedForecastConfidence = stageBannerForOpportunity(opportunityRecord);
        String expectedQuoteConfidence = QuoteService.mapOpportunityForecastConfidenceToQuote(
            updatedForecastConfidence
        );

        Test.startTest();
        OppForecastConfBannerController.propagateSelectedQuotes(
            opportunityRecord.Id,
            new List<Id>{ firstQuote.Id }
        );
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
        String updatedForecastConfidence = resolveDifferentForecastConfidenceLevel(
            opportunityRecord.ForecastConfidenceLevel__c
        );

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

        delete quoteRecord;

        Test.startTest();
        OppForecastConfPropagateService.syncBannerStateForOpportunityIds(
            new Set<Id>{ opportunityRecord.Id }
        );
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

    @IsTest
    static void testGetBannerContextIncludesTrialSampleAndGoodwillQuotes() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote trialQuote = insertQuote(opportunityRecord, 'Trial Propagate Quote', 'Open');
        Quote sampleQuote = insertQuote(opportunityRecord, 'Sample Propagate Quote', 'Open');
        Quote goodwillQuote = insertQuote(opportunityRecord, 'Goodwill Propagate Quote', 'Open');

        trialQuote.QuoteType__c = GenerateQuoteService.QUOTE_TYPE_TRIAL;
        trialQuote.IsForecastIneligible__c = true;
        sampleQuote.QuoteType__c = GenerateQuoteService.QUOTE_TYPE_SAMPLE;
        sampleQuote.IsForecastIneligible__c = true;
        goodwillQuote.QuoteType__c = GenerateQuoteService.QUOTE_TYPE_GOODWILL;
        goodwillQuote.IsForecastIneligible__c = true;
        update new List<Quote>{ trialQuote, sampleQuote, goodwillQuote };

        stageBannerForOpportunity(opportunityRecord);

        Test.startTest();
        OppForecastConfPropagateService.BannerContext bannerContext =
            OppForecastConfBannerController.getBannerContext(opportunityRecord.Id);
        Test.stopTest();

        System.assertEquals(true, bannerContext.showBanner);
        System.assertEquals(3, bannerContext.quotes.size(), 'Trial, Sample, and Goodwill quotes should be included.');
        Set<Id> returnedQuoteIds = new Set<Id>();
        for (OppForecastConfPropagateService.QuoteRow quoteRow : bannerContext.quotes) {
            returnedQuoteIds.add(quoteRow.id);
        }
        System.assertEquals(true, returnedQuoteIds.contains(trialQuote.Id));
        System.assertEquals(true, returnedQuoteIds.contains(sampleQuote.Id));
        System.assertEquals(true, returnedQuoteIds.contains(goodwillQuote.Id));
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
        OppForecastConfPropagateService.BannerContext bannerContext =
            OppForecastConfBannerController.getBannerContext(opportunityRecord.Id);
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

    private static String stageBannerForOpportunity(Opportunity opportunityRecord) {
        Opportunity oldOpportunityRecord = opportunityRecord.clone(true, true, true, true);
        String updatedForecastConfidence = resolveDifferentForecastConfidenceLevel(
            opportunityRecord.ForecastConfidenceLevel__c
        );
        System.assertNotEquals(null, updatedForecastConfidence, 'A second forecast confidence value is required.');

        opportunityRecord.ForecastConfidenceLevel__c = updatedForecastConfidence;
        OppForecastConfPropagateService.stagePropagateBanner(
            new List<Opportunity>{ opportunityRecord },
            new Map<Id, Opportunity>{ oldOpportunityRecord.Id => oldOpportunityRecord }
        );
        update opportunityRecord;
        return updatedForecastConfidence;
    }

    private static Opportunity getTestOpportunity() {
        return [
            SELECT Id,
                Pricebook2Id,
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

        Schema.RecordTypeInfo recordTypeInfo =
            recordTypesByDeveloperName.get(OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME);
        return recordTypeInfo.isAvailable() ? recordTypeInfo.getRecordTypeId() : null;
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

    private static String resolveDifferentForecastConfidenceLevel(String currentValue) {
        for (Schema.PicklistEntry picklistEntry :
            Opportunity.ForecastConfidenceLevel__c.getDescribe().getPicklistValues()) {
            if (!picklistEntry.isActive()) {
                continue;
            }

            if (currentValue == null || !picklistEntry.getValue().equalsIgnoreCase(currentValue)) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }
}