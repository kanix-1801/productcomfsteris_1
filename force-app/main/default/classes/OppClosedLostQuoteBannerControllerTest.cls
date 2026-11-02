/**
 * @author Himanshu Chaurasia
 * @date 2026/09/09
 *
 * @description Test class for Closed Lost quote closure banner.
 */
@IsTest
private class OppClosedLostQuoteBannerControllerTest {
    private static final String TEST_OPPORTUNITY_NAME = 'Closed Lost Quote Banner Test Opportunity';
    private static final String CLOSED_LOST_STAGE = 'Closed Lost';
    private static final String OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME = 'Healthcare_Sales';
    private static final String QUOTE_AUTOMATION_RUN_AS_LAST_NAME = 'ClosedLostQuoteBannerRunAs';
    private static final String SALES_FIELD_REP_PSG_DEVELOPER_NAME = 'SalesFieldRepAccountManagerPSG';

    @TestSetup
    static void setupData() {
        User setupUser = new User(Id = UserInfo.getUserId());
        System.runAs(setupUser) {
            insert createQuoteAutomationRunAsUser();
        }
        assignSalesFieldRepAccountManagerPsg(getQuoteAutomationRunAsUser().Id);

        Id standardPricebookId = Test.getStandardPricebookId();

        Account accountRecord = new Account(
            Name = 'Closed Lost Quote Banner Test Account',
            SourceSystemID__c = 'CLQB-TEST-ACCT',
            OracleAddressId__c = '638265'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Closed',
            LastName = 'Lost Banner',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Opportunity opportunityRecord = buildOpportunity(
            TEST_OPPORTUNITY_NAME,
            accountRecord.Id,
            contactRecord.Id,
            standardPricebookId,
            getValidStageName()
        );
        insert opportunityRecord;
    }

    @IsTest
    static void testStageClosedLostBannerWhenOpenQuotesExist() {
        Opportunity opportunityRecord = getTestOpportunity();
        insertQuote(opportunityRecord, 'Closed Lost Quote 1', 'Open');

        Opportunity oldOpportunityRecord = opportunityRecord.clone(true, true, true, true);
        opportunityRecord.StageName = resolveClosedLostStageName();

        Test.startTest();
        stageClosedLostBannerAndUpdateOpportunity(opportunityRecord, oldOpportunityRecord);
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT IsOpportunityClosed__c, StageName
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(true, updatedOpportunity.IsOpportunityClosed__c);
        System.assertEquals(resolveClosedLostStageName(), updatedOpportunity.StageName);
    }

    @IsTest
    static void testStageClosedLostBannerClearsFlagWhenNoQuotesExist() {
        Opportunity opportunityRecord = getTestOpportunity();
        Opportunity oldOpportunityRecord = opportunityRecord.clone(true, true, true, true);
        opportunityRecord.IsOpportunityClosed__c = true;
        opportunityRecord.StageName = resolveClosedLostStageName();

        OppClosedLostQuoteService.stageClosedLostQuoteBanner(
            new List<Opportunity>{ opportunityRecord },
            new Map<Id, Opportunity>{ oldOpportunityRecord.Id => oldOpportunityRecord }
        );

        System.assertEquals(false, opportunityRecord.IsOpportunityClosed__c);
    }

    @IsTest
    static void testGetBannerContextReturnsOpenQuotes() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'Closed Lost Quote 2', 'Open');
        moveOpportunityToClosedLost(opportunityRecord);

        Test.startTest();
        OppClosedLostQuoteService.BannerContext bannerContext = getBannerContextAsAutomationUser(
            opportunityRecord.Id
        );
        Test.stopTest();

        System.assertEquals(true, bannerContext.showBanner);
        System.assertEquals(1, bannerContext.quotes.size());
        System.assertEquals(quoteRecord.Id, bannerContext.quotes[0].id);
    }

    @IsTest
    static void testCloseAllOpenQuotesUpdatesQuoteStatus() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'Closed Lost Quote 3', 'Open');
        quoteRecord.SalesConnectionQuoteID__c = '2283704';
        updateQuoteRecords(quoteRecord);
        quoteRecord = [
            SELECT Id, SalesConnectionQuoteID__c
            FROM Quote
            WHERE Id = :quoteRecord.Id
            LIMIT 1
        ];
        System.assertEquals('2283704', quoteRecord.SalesConnectionQuoteID__c);
        moveOpportunityToClosedLost(opportunityRecord);
        //ScOpportunityQuoteEventGateway.forceHardcodedResponse = true;

        Test.startTest();
        closeAllOpenQuotesAsAutomationUser(opportunityRecord.Id);
        Test.stopTest();

        //ScOpportunityQuoteEventGateway.forceHardcodedResponse = false;

        Quote updatedQuote = [
            SELECT Status
            FROM Quote
            WHERE Id = :quoteRecord.Id
            LIMIT 1
        ];
        Opportunity updatedOpportunity = [
            SELECT IsOpportunityClosed__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(QuoteSelector.CLOSED_STATUS_VALUE, updatedQuote.Status);
        System.assertEquals(false, updatedOpportunity.IsOpportunityClosed__c);
    }

    @IsTest
    static void testDismissBannerClearsFlagWithoutClosingQuotes() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'Closed Lost Quote 4', 'Open');
        moveOpportunityToClosedLost(opportunityRecord);

        Test.startTest();
        dismissBannerAsAutomationUser(opportunityRecord.Id);
        Test.stopTest();

        Quote unchangedQuote = [
            SELECT Status
            FROM Quote
            WHERE Id = :quoteRecord.Id
            LIMIT 1
        ];
        Opportunity updatedOpportunity = [
            SELECT IsOpportunityClosed__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals('Open', unchangedQuote.Status);
        System.assertEquals(false, updatedOpportunity.IsOpportunityClosed__c);
    }

    @IsTest
    static void testGetBannerContextIncludesTrialSampleAndGoodwillQuotes() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote normalQuote = insertQuote(opportunityRecord, 'Closed Lost Normal Quote', 'Open');
        Quote trialQuote = insertQuote(opportunityRecord, 'Closed Lost Trial Quote', 'Open');
        Quote sampleQuote = insertQuote(opportunityRecord, 'Closed Lost Sample Quote', 'Open');
        Quote goodwillQuote = insertQuote(opportunityRecord, 'Closed Lost Goodwill Quote', 'Open');

        normalQuote.Forecast_Eligible__c = true;
        List<Quote> quotesToUpdate = new List<Quote>{ normalQuote };
        Set<Id> expectedQuoteIds = new Set<Id>{ normalQuote.Id };

        if (isQuoteTypeAvailable(GenerateQuoteService.QUOTE_TYPE_TRIAL)) {
            trialQuote.QuoteType__c = GenerateQuoteService.QUOTE_TYPE_TRIAL;
            trialQuote.IsForecastIneligible__c = true;
            quotesToUpdate.add(trialQuote);
            expectedQuoteIds.add(trialQuote.Id);
        }

        if (isQuoteTypeAvailable(GenerateQuoteService.QUOTE_TYPE_SAMPLE)) {
            sampleQuote.QuoteType__c = GenerateQuoteService.QUOTE_TYPE_SAMPLE;
            sampleQuote.IsForecastIneligible__c = true;
            quotesToUpdate.add(sampleQuote);
            expectedQuoteIds.add(sampleQuote.Id);
        }

        if (isQuoteTypeAvailable(GenerateQuoteService.QUOTE_TYPE_GOODWILL)) {
            goodwillQuote.QuoteType__c = GenerateQuoteService.QUOTE_TYPE_GOODWILL;
            goodwillQuote.IsForecastIneligible__c = true;
            quotesToUpdate.add(goodwillQuote);
            expectedQuoteIds.add(goodwillQuote.Id);
        }

        updateQuoteRecords(quotesToUpdate);
        moveOpportunityToClosedLost(opportunityRecord);

        Test.startTest();
        OppClosedLostQuoteService.BannerContext bannerContext = getBannerContextAsAutomationUser(
            opportunityRecord.Id
        );
        Test.stopTest();

        System.assertEquals(true, bannerContext.showBanner);
        System.assertEquals(
            expectedQuoteIds.size(),
            bannerContext.quotes.size(),
            'Configured special quote types should be included with the normal quote.'
        );

        Set<Id> returnedQuoteIds = new Set<Id>();
        for (OppClosedLostQuoteService.QuoteRow quoteRow : bannerContext.quotes) {
            returnedQuoteIds.add(quoteRow.id);
        }

        System.assertEquals(true, returnedQuoteIds.containsAll(expectedQuoteIds));
    }

    @IsTest
    static void testSyncBannerStateClearsFlagWhenQuotesAreClosed() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'Closed Lost Quote 5', 'Open');
        moveOpportunityToClosedLost(opportunityRecord);

        quoteRecord.Status = resolveQuoteStatus('Closed');
        updateQuoteRecords(quoteRecord);

        Test.startTest();
        syncBannerStateAsAutomationUser(new Set<Id>{ opportunityRecord.Id });
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT IsOpportunityClosed__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(false, updatedOpportunity.IsOpportunityClosed__c);
    }

    private static void stageClosedLostBannerAndUpdateOpportunity(
        Opportunity opportunityRecord,
        Opportunity oldOpportunityRecord
    ) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            OppClosedLostQuoteService.stageClosedLostQuoteBanner(
                new List<Opportunity>{ opportunityRecord },
                new Map<Id, Opportunity>{ oldOpportunityRecord.Id => oldOpportunityRecord }
            );
            update opportunityRecord;
        }
    }

    private static OppClosedLostQuoteService.BannerContext getBannerContextAsAutomationUser(Id opportunityId) {
        OppClosedLostQuoteService.BannerContext bannerContext;
        System.runAs(getQuoteAutomationRunAsUser()) {
            bannerContext = OppClosedLostQuoteBannerController.getBannerContext(opportunityId);
        }
        return bannerContext;
    }

    private static void closeAllOpenQuotesAsAutomationUser(Id opportunityId) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            OppClosedLostQuoteBannerController.closeAllOpenQuotes(opportunityId);
        }
    }

    private static void dismissBannerAsAutomationUser(Id opportunityId) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            OppClosedLostQuoteBannerController.dismissBanner(opportunityId);
        }
    }

    private static void syncBannerStateAsAutomationUser(Set<Id> opportunityIds) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            OppClosedLostQuoteService.syncBannerStateForOpportunityIds(opportunityIds);
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
            Alias = 'clqbrn',
            Email = 'closed.lost.quote.banner.runas@test.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = QUOTE_AUTOMATION_RUN_AS_LAST_NAME,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username =
                'closed.lost.quote.banner.runas+' +
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
            SELECT Id
            FROM PermissionSetGroup
            WHERE DeveloperName = :SALES_FIELD_REP_PSG_DEVELOPER_NAME
            LIMIT 1
        ];

        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetGroupId = permissionSetGroupRecord.Id
        );

        Test.calculatePermissionSetGroup(permissionSetGroupRecord.Id);
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

    private static void moveOpportunityToClosedLost(Opportunity opportunityRecord) {
        Opportunity oldOpportunityRecord = [
            SELECT Id, StageName
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ][0].clone(true, true, true, true);

        opportunityRecord.StageName = resolveClosedLostStageName();
        stageClosedLostBannerAndUpdateOpportunity(opportunityRecord, oldOpportunityRecord);
    }

    private static Opportunity getTestOpportunity() {
        return [
            SELECT Id, Pricebook2Id, StageName
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
        String stageName
    ) {
        Opportunity opportunityRecord = new Opportunity(
            Name = opportunityName,
            AccountId = accountId,
            StageName = stageName,
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
            if (picklistEntry.isActive() && !CLOSED_LOST_STAGE.equalsIgnoreCase(picklistEntry.getValue())) {
                return picklistEntry.getValue();
            }
        }

        return 'Discovery';
    }

    private static String resolveClosedLostStageName() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && CLOSED_LOST_STAGE.equalsIgnoreCase(picklistEntry.getValue())) {
                return picklistEntry.getValue();
            }
        }

        return CLOSED_LOST_STAGE;
    }

    private static String getValidOpportunityType() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.Type.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }
}