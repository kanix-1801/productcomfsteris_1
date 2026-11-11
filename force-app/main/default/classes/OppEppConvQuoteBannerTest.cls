/**
 * @author Himanshu Chaurasia
 * @date 2026/10/14
 *
 * @description Test coverage for OppEppConversionQuoteService (GC-3457 UC3 EPP conversion quote closure).
 *              Also exercises OppEppConversionQuoteBannerController, OppEppConversionQuoteSelectionAction,
 *              and OppEppConversionQuoteClosureAction.
 */
@IsTest
private class OppEppConvQuoteBannerTest {
    private static final String TEST_OPPORTUNITY_NAME = 'EPP Conversion Quote Banner Test Opportunity';
    private static final String OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME = 'Healthcare_Sales';
    private static final String QUOTE_AUTOMATION_RUN_AS_LAST_NAME = 'EppConvQuoteBannerRunAs';
    private static final String SALES_FIELD_REP_PSG_DEVELOPER_NAME = 'SalesFieldRepAccountManagerPSG';

    @TestSetup
    static void setupData() {
        Id standardPricebookId = Test.getStandardPricebookId();

        Account accountRecord = new Account(
            Name = 'EPP Conversion Quote Banner Test Account',
            SourceSystemID__c = 'EPPCQB-TEST-ACCT',
            OracleAddressId__c = '638265'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'EPP',
            LastName = 'Conversion Banner',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        insert buildOpportunity(
            TEST_OPPORTUNITY_NAME,
            accountRecord.Id,
            contactRecord.Id,
            standardPricebookId
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
    static void stageBannerAfterConversionSetsFlagWhenOpenQuotesExist() {
        Opportunity opportunityRecord = getTestOpportunity();
        insertQuote(opportunityRecord, 'EPP Conversion Quote 1', 'Open');

        Test.startTest();
        OppEppConversionQuoteService.stageBannerAfterConversion(opportunityRecord.Id);
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT PendingEppConversionQuoteClosure__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(true, updatedOpportunity.PendingEppConversionQuoteClosure__c);
    }

    @IsTest
    static void flowClosureActionIgnoresNullAndBlankInputs() {
        Test.startTest();
        OppEppConversionQuoteClosureAction.stageBanner(null);
        OppEppConversionQuoteClosureAction.FlowInput blankInput =
            new OppEppConversionQuoteClosureAction.FlowInput();
        OppEppConversionQuoteClosureAction.stageBanner(
            new List<OppEppConversionQuoteClosureAction.FlowInput>{ null, blankInput }
        );
        Test.stopTest();
    }

    @IsTest
    static void flowClosureActionStagesBannerWhenOpenQuotesExist() {
        Opportunity opportunityRecord = getTestOpportunity();
        insertQuote(opportunityRecord, 'EPP Flow Closure Quote', 'Open');

        OppEppConversionQuoteClosureAction.FlowInput flowInput =
            new OppEppConversionQuoteClosureAction.FlowInput();
        flowInput.opportunityId = opportunityRecord.Id;

        Test.startTest();
        OppEppConversionQuoteClosureAction.stageBanner(
            new List<OppEppConversionQuoteClosureAction.FlowInput>{ flowInput }
        );
        Test.stopTest();

        System.assertEquals(
            true,
            [
                SELECT PendingEppConversionQuoteClosure__c
                FROM Opportunity
                WHERE Id = :opportunityRecord.Id
            ].PendingEppConversionQuoteClosure__c
        );
    }

    @IsTest
    static void stageBannerAfterConversionClearsFlagWhenNoOpenQuotesExist() {
        Opportunity opportunityRecord = getTestOpportunity();
        opportunityRecord.PendingEppConversionQuoteClosure__c = true;
        update opportunityRecord;

        Test.startTest();
        OppEppConversionQuoteService.stageBannerAfterConversion(opportunityRecord.Id);
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT PendingEppConversionQuoteClosure__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(false, updatedOpportunity.PendingEppConversionQuoteClosure__c);
    }

    @IsTest
    static void syncBannerStateClearsPendingFlagWhenQuotesAreClosed() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'EPP Sync Clear Quote', 'Open');
        opportunityRecord.PendingEppConversionQuoteClosure__c = true;
        update opportunityRecord;

        quoteRecord.Status = resolveQuoteStatus('Closed');
        updateQuoteRecords(quoteRecord);

        Test.startTest();
        OppEppConversionQuoteService.syncBannerStateForOpportunityIds(
            new Set<Id>{ opportunityRecord.Id }
        );
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT PendingEppConversionQuoteClosure__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(false, updatedOpportunity.PendingEppConversionQuoteClosure__c);
    }

    @IsTest
    static void getBannerContextReturnsHiddenWhenFlagSetButNoOpenQuotes() {
        Opportunity opportunityRecord = getTestOpportunity();
        opportunityRecord.PendingEppConversionQuoteClosure__c = true;
        update opportunityRecord;

        Test.startTest();
        OppEppConversionQuoteService.BannerContext bannerContext =
            OppEppConversionQuoteService.getBannerContext(opportunityRecord.Id);
        Test.stopTest();

        System.assertEquals(false, bannerContext.showBanner);
        System.assertEquals(0, bannerContext.openQuoteCount);
    }

    @IsTest
    static void reconcileStaleBannerClearsPendingFlagWhenNoOpenQuotes() {
        Opportunity opportunityRecord = getTestOpportunity();
        opportunityRecord.PendingEppConversionQuoteClosure__c = true;
        update opportunityRecord;

        Test.startTest();
        OppEppConversionQuoteService.reconcileStaleBanner(opportunityRecord.Id);
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT PendingEppConversionQuoteClosure__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(false, updatedOpportunity.PendingEppConversionQuoteClosure__c);
    }

    @IsTest
    static void closeAllOpenQuotesThrowsWhenBannerInactive() {
        Opportunity opportunityRecord = getTestOpportunity();
        insertQuote(opportunityRecord, 'EPP Inactive Banner Quote', 'Open');
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            OppEppConversionQuoteService.closeAllOpenQuotes(opportunityRecord.Id);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testGetBannerContextWrapsUnexpectedErrors() {
        OppEppConversionQuoteBannerController.forceExceptionForTest = true;
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            OppEppConversionQuoteBannerController.getBannerContext(null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        OppEppConversionQuoteBannerController.forceExceptionForTest = false;
        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testCloseAllOpenQuotesWrapsForcedUnexpectedErrors() {
        OppEppConversionQuoteBannerController.forceExceptionForTest = true;
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            OppEppConversionQuoteBannerController.closeAllOpenQuotes(null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        OppEppConversionQuoteBannerController.forceExceptionForTest = false;
        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testCloseAllOpenQuotesRethrowsAuraHandledException() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            OppEppConversionQuoteBannerController.closeAllOpenQuotes(null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testReconcileStaleBannerWrapsUnexpectedErrors() {
        OppEppConversionQuoteBannerController.forceExceptionForTest = true;
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            OppEppConversionQuoteBannerController.reconcileStaleBanner(null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        OppEppConversionQuoteBannerController.forceExceptionForTest = false;
        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testDismissBannerWrapsUnexpectedErrors() {
        OppEppConversionQuoteBannerController.forceExceptionForTest = true;
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            OppEppConversionQuoteBannerController.dismissBanner(null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        OppEppConversionQuoteBannerController.forceExceptionForTest = false;
        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void closeAllOpenQuotesRequiresOpportunityId() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            OppEppConversionQuoteService.closeAllOpenQuotes(null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void controllerReconcileStaleBannerClearsPendingFlag() {
        Opportunity opportunityRecord = getTestOpportunity();
        opportunityRecord.PendingEppConversionQuoteClosure__c = true;
        update opportunityRecord;

        Test.startTest();
        OppEppConversionQuoteBannerController.reconcileStaleBanner(opportunityRecord.Id);
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT PendingEppConversionQuoteClosure__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(false, updatedOpportunity.PendingEppConversionQuoteClosure__c);
    }

    @IsTest
    static void getBannerContextReturnsOpenQuotes() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'EPP Conversion Quote 2', 'Open');
        opportunityRecord.PendingEppConversionQuoteClosure__c = true;
        update opportunityRecord;

        Test.startTest();
        OppEppConversionQuoteService.BannerContext bannerContext =
            OppEppConversionQuoteBannerController.getBannerContext(opportunityRecord.Id);
        Test.stopTest();

        System.assertEquals(true, bannerContext.showBanner);
        System.assertEquals(1, bannerContext.quotes.size());
        System.assertEquals(quoteRecord.Id, bannerContext.quotes[0].id);
    }

    @IsTest
    static void closeAllOpenQuotesUpdatesQuoteStatus() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'EPP Conversion Quote 3', 'Open');
        quoteRecord.SalesConnectionQuoteID__c = '2283704';
        updateQuoteRecords(quoteRecord);
        opportunityRecord.PendingEppConversionQuoteClosure__c = true;
        update opportunityRecord;
        ScOpportunityQuoteEventGateway.forceHardcodedResponse = true;

        Test.startTest();
        closeAllOpenQuotesAsAutomationUser(opportunityRecord.Id);
        Test.stopTest();

        ScOpportunityQuoteEventGateway.forceHardcodedResponse = false;

        Quote updatedQuote = [
            SELECT Status
            FROM Quote
            WHERE Id = :quoteRecord.Id
            LIMIT 1
        ];
        Opportunity updatedOpportunity = [
            SELECT PendingEppConversionQuoteClosure__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(QuoteSelector.CLOSED_STATUS_VALUE, updatedQuote.Status);
        System.assertEquals(false, updatedOpportunity.PendingEppConversionQuoteClosure__c);
    }

    @IsTest
    static void closeSelectedQuotesClosesOnlyTheChosenQuote() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote selectedQuote = insertQuote(opportunityRecord, 'EPP Selected Quote', 'Open');
        Quote otherQuote = insertQuote(opportunityRecord, 'EPP Unselected Quote', 'Open');
        selectedQuote.SalesConnectionQuoteID__c = '2283705';
        otherQuote.SalesConnectionQuoteID__c = '2283706';
        updateQuoteRecords(new List<Quote>{ selectedQuote, otherQuote });
        ScOpportunityQuoteEventGateway.forceHardcodedResponse = true;

        Test.startTest();
        closeSelectedQuotesAsAutomationUser(
            opportunityRecord.Id,
            new Set<Id>{ selectedQuote.Id }
        );
        Test.stopTest();

        ScOpportunityQuoteEventGateway.forceHardcodedResponse = false;

        Map<Id, Quote> quotesById = new Map<Id, Quote>([
            SELECT Status
            FROM Quote
            WHERE Id IN :new Set<Id>{ selectedQuote.Id, otherQuote.Id }
        ]);
        System.assertEquals(QuoteSelector.CLOSED_STATUS_VALUE, quotesById.get(selectedQuote.Id).Status);
        System.assertNotEquals(QuoteSelector.CLOSED_STATUS_VALUE, quotesById.get(otherQuote.Id).Status);
    }

    @IsTest
    static void reviewQuotesListsAndClosesTheSelectedQuote() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote selectedQuote = insertQuote(opportunityRecord, 'EPP Action Selected Quote', 'Open');
        Quote otherQuote = insertQuote(opportunityRecord, 'EPP Action Unselected Quote', 'Open');
        selectedQuote.SalesConnectionQuoteID__c = '2283707';
        otherQuote.SalesConnectionQuoteID__c = '2283708';
        updateQuoteRecords(new List<Quote>{ selectedQuote, otherQuote });
        opportunityRecord.PendingEppConversionQuoteClosure__c = true;
        update opportunityRecord;
        ScOpportunityQuoteEventGateway.forceHardcodedResponse = true;

        OppEppConversionQuoteSelectionAction.Request listRequest =
            new OppEppConversionQuoteSelectionAction.Request();
        listRequest.opportunityId = opportunityRecord.Id;
        listRequest.closeSelectedQuotes = false;

        OppEppConversionQuoteSelectionAction.Request closeRequest =
            new OppEppConversionQuoteSelectionAction.Request();
        closeRequest.opportunityId = opportunityRecord.Id;
        closeRequest.closeSelectedQuotes = true;
        closeRequest.quotesToClose = new List<Quote>{
            selectedQuote,
            null,
            new Quote()
        };

        List<OppEppConversionQuoteSelectionAction.Response> listed;
        System.runAs(getQuoteAutomationRunAsUser()) {
            Test.startTest();
            System.assertEquals(0, OppEppConversionQuoteSelectionAction.reviewQuotes(null).size());
            listed =
                OppEppConversionQuoteSelectionAction.reviewQuotes(
                    new List<OppEppConversionQuoteSelectionAction.Request>{ null, listRequest }
                );
            OppEppConversionQuoteSelectionAction.reviewQuotes(
                new List<OppEppConversionQuoteSelectionAction.Request>{ closeRequest }
            );
            OppEppConversionQuoteService.closeSelectedQuotes(null, null);
            OppEppConversionQuoteService.closeSelectedQuotes(opportunityRecord.Id, new Set<Id>());
            OppEppConversionQuoteService.dismissBanner(opportunityRecord.Id);
            OppEppConversionQuoteService.dismissBanner(null);
            OppEppConversionQuoteService.stageBannerAfterConversion(null);
            OppEppConversionQuoteService.syncBannerStateForOpportunityIds(null);
            OppEppConversionQuoteService.syncBannerStateForOpportunityIds(
                new Set<Id>{ opportunityRecord.Id }
            );
            OppEppConversionQuoteService.reconcileStaleBanner(null);
            OppEppConversionQuoteService.reconcileStaleBanner(opportunityRecord.Id);
            OppEppConversionQuoteService.getBannerContext(null);
            Test.stopTest();
        }

        ScOpportunityQuoteEventGateway.forceHardcodedResponse = false;

        System.assertEquals(2, listed[1].openQuotes.size());
        System.assertEquals(
            false,
            [SELECT PendingEppConversionQuoteClosure__c FROM Opportunity WHERE Id = :opportunityRecord.Id]
                .PendingEppConversionQuoteClosure__c
        );
    }

    private static void closeAllOpenQuotesAsAutomationUser(Id opportunityId) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            OppEppConversionQuoteBannerController.closeAllOpenQuotes(opportunityId);
        }
    }

    private static void closeSelectedQuotesAsAutomationUser(Id opportunityId, Set<Id> quoteIds) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            OppEppConversionQuoteService.closeSelectedQuotes(opportunityId, quoteIds);
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
            Alias = 'eppqbr',
            Email = 'epp.conversion.quote.banner.runas@test.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = QUOTE_AUTOMATION_RUN_AS_LAST_NAME,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username =
                'epp.conversion.quote.banner.runas+' +
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
        updateQuoteRecords(new List<Quote>{ quoteRecord });
    }

    private static void updateQuoteRecords(List<Quote> quoteRecords) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            update quoteRecords;
        }
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
        Id pricebookId
    ) {
        Opportunity opportunityRecord = new Opportunity(
            Name = opportunityName,
            AccountId = accountId,
            StageName = getValidStageName(),
            ForecastConfidenceLevel__c = getValidForecastConfidenceLevel(),
            CloseDate = Date.today().addDays(30),
            Amount = 100,
            Probability = 10,
            Type = getValidOpportunityType(),
            PrimaryContact__c = primaryContactId,
            Pricebook2Id = pricebookId
        );

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

    private static Quote insertQuote(Opportunity opportunityRecord, String quoteName, String statusValue) {
        Quote quoteRecord = buildQuote(opportunityRecord, quoteName, statusValue);
        insertQuoteRecords(quoteRecord);
        return quoteRecord;
    }

    private static Quote buildQuote(
        Opportunity opportunityRecord,
        String quoteName,
        String statusValue
    ) {
        return new Quote(
            Name = quoteName,
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            RecordTypeId = requireHcSalesQuoteRecordTypeId(),
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
        for (Schema.PicklistEntry picklistEntry : Quote.Status.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && picklistEntry.getValue().equalsIgnoreCase(preferredValue)) {
                return picklistEntry.getValue();
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

        return 'Extension';
    }

    private static String getValidForecastConfidenceLevel() {
        for (
            Schema.PicklistEntry picklistEntry :
            Opportunity.ForecastConfidenceLevel__c.getDescribe().getPicklistValues()
        ) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }
}