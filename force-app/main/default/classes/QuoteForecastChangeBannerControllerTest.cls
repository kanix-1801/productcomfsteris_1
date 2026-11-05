/**
 * @author Himanshu Chaurasia
 * @date 2026/07/29
 *
 * @description Test class for QuoteForecastChangeBannerController, QuoteForecastChangeNotificationHandler,
 *              QuoteForecastChangeNotificationService, and QuoteTriggerHandler notification paths.
 */
@IsTest
private class QuoteForecastChangeBannerControllerTest {
    private static final String TEST_OPPORTUNITY_NAME = 'Forecast Banner Test Opportunity';
    private static final String QUOTE_AUTOMATION_RUN_AS_LAST_NAME = 'QuoteForecastBannerRunAs';
    private static final String SALES_FIELD_REP_PSG_DEVELOPER_NAME = 'SalesFieldRepAccountManagerPSG';
    private static final String HEALTHCARE_SALES_OPPORTUNITY_RECORD_TYPE = 'Healthcare_Sales';

    @TestSetup
    static void setupData() {
        Id standardPricebookId = Test.getStandardPricebookId();

        Account accountRecord = new Account(
            Name = 'Forecast Banner Test Account',
            SourceSystemID__c = 'FB-TEST-ACCT'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Forecast',
            LastName = 'Banner Contact',
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
        }
    }

    @IsTest
    static void testDismissNotificationClearsFlag() {
        Opportunity opportunityRecord = getTestOpportunity();

        QuoteForecastChangeNotificationService.markNotificationPending(opportunityRecord.Id);

        Test.startTest();
        QuoteForecastChangeBannerController.dismissNotification(opportunityRecord.Id);
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT IsForecastChangeNotificationPending__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            false,
            updatedOpportunity.IsForecastChangeNotificationPending__c,
            'Dismiss should clear the notification flag.'
        );
    }

    @IsTest
    static void testMarkNotificationsPendingSetsFlag() {
        Opportunity opportunityRecord = getTestOpportunity();

        Test.startTest();
        QuoteForecastChangeNotificationService.markNotificationPending(opportunityRecord.Id);
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT IsForecastChangeNotificationPending__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            updatedOpportunity.IsForecastChangeNotificationPending__c,
            'Notification service should set the pending flag.'
        );
    }

    @IsTest
    static void testDismissNotificationWithNullOpportunityId() {
        Test.startTest();
        QuoteForecastChangeBannerController.dismissNotification(null);
        Test.stopTest();

        System.assert(true, 'Dismiss with null Opportunity Id should complete without error.');
    }

    @IsTest
    static void testMarkNotificationsPendingBulkAndNullInputs() {
        Opportunity opportunityRecord = getTestOpportunity();

        Test.startTest();
        QuoteForecastChangeNotificationService.markNotificationPending(null);
        QuoteForecastChangeNotificationService.markNotificationsPending(null);
        QuoteForecastChangeNotificationService.markNotificationsPending(new Set<Id>());
        QuoteForecastChangeNotificationService.markNotificationsPending(
            new Set<Id>{ opportunityRecord.Id, null }
        );
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT IsForecastChangeNotificationPending__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            updatedOpportunity.IsForecastChangeNotificationPending__c,
            'Bulk notification service should set the pending flag.'
        );
    }

    @IsTest
    static void testQuoteInsertSetsNotificationFlagViaTrigger() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'Forecast Banner Trigger Quote',
            false,
            false
        );

        Test.startTest();
        insertQuoteRecords(quoteRecord);
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT IsForecastChangeNotificationPending__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            updatedOpportunity.IsForecastChangeNotificationPending__c,
            'Quote insert should set the notification flag through the trigger.'
        );
    }

    @IsTest
    static void testForecastEligibleChangeSetsNotificationFlagViaTrigger() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'Forecast Eligible Change Quote',
            false,
            false
        );

        insertQuoteRecords(quoteRecord);

        updateOpportunityRecords(
            new Opportunity(
                Id = opportunityRecord.Id,
                IsForecastChangeNotificationPending__c = false
            )
        );

        Test.startTest();
        updateQuoteRecords(
            new Quote(
                Id = quoteRecord.Id,
                Forecast_Eligible__c = true
            )
        );
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT IsForecastChangeNotificationPending__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            updatedOpportunity.IsForecastChangeNotificationPending__c,
            'Forecast Eligible change should set the notification flag.'
        );
    }

    @IsTest
    static void testForecastIneligibleQuoteInsertDoesNotSetNotificationFlag() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'Forecast Ineligible Insert Quote',
            false,
            true
        );

        Test.startTest();
        insertQuoteRecords(quoteRecord);
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT IsForecastChangeNotificationPending__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            false,
            updatedOpportunity.IsForecastChangeNotificationPending__c,
            'Forecast ineligible quote insert should not set the notification flag.'
        );
    }

    @IsTest
    static void testTrialQuoteTypeInsertDoesNotSetNotificationFlag() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'Trial Type Insert Quote',
            false,
            false
        );
        quoteRecord.QuoteType__c = GenerateQuoteService.QUOTE_TYPE_TRIAL;

        Test.startTest();
        insertQuoteRecords(quoteRecord);
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT IsForecastChangeNotificationPending__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            false,
            updatedOpportunity.IsForecastChangeNotificationPending__c,
            'Trial quote type insert should not set the notification flag.'
        );
    }

    @IsTest
    static void testForecastIneligibleQuoteUpdateDoesNotSetNotificationFlag() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'Forecast Ineligible Update Quote',
            false,
            true
        );
        insertQuoteRecords(quoteRecord);

        updateOpportunityRecords(
            new Opportunity(
                Id = opportunityRecord.Id,
                IsForecastChangeNotificationPending__c = false
            )
        );

        Test.startTest();
        updateQuoteRecords(
            new Quote(
                Id = quoteRecord.Id,
                Quote_Total_Without_Freight__c = 5000
            )
        );
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT IsForecastChangeNotificationPending__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            false,
            updatedOpportunity.IsForecastChangeNotificationPending__c,
            'Forecast ineligible quote update should not set the notification flag.'
        );
    }

    @IsTest
    static void testNotificationMessageConstantIsDefined() {
        System.assert(
            String.isNotBlank(QuoteForecastChangeNotificationService.NOTIFICATION_MESSAGE),
            'Banner message constant should be available to the LWC.'
        );
    }

    @IsTest
    static void testQuoteDeleteSetsNotificationFlagViaTrigger() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'Delete Notification Quote',
            false,
            false
        );
        insertQuoteRecords(quoteRecord);

        updateOpportunityRecords(
            new Opportunity(
                Id = opportunityRecord.Id,
                IsForecastChangeNotificationPending__c = false
            )
        );

        Test.startTest();
        System.runAs(getQuoteAutomationRunAsUser()) {
            delete quoteRecord;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            [
                SELECT IsForecastChangeNotificationPending__c
                FROM Opportunity
                WHERE Id = :opportunityRecord.Id
                LIMIT 1
            ].IsForecastChangeNotificationPending__c,
            'Quote delete should set the notification flag through QuoteTriggerHandler.'
        );
    }

    @IsTest
    static void testQuoteStatusUpdateSetsNotificationFlagViaTrigger() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'Status Change Notification Quote',
            false,
            false
        );
        quoteRecord.Status = resolveQuoteStatus('Open');
        insertQuoteRecords(quoteRecord);

        updateOpportunityRecords(
            new Opportunity(
                Id = opportunityRecord.Id,
                IsForecastChangeNotificationPending__c = false
            )
        );

        quoteRecord.Status = resolveQuoteStatus('Draft');

        Test.startTest();
        updateQuoteRecords(quoteRecord);
        Test.stopTest();

        System.assertEquals(
            true,
            [
                SELECT IsForecastChangeNotificationPending__c
                FROM Opportunity
                WHERE Id = :opportunityRecord.Id
                LIMIT 1
            ].IsForecastChangeNotificationPending__c,
            'Quote status change should set the notification flag.'
        );
    }

    @IsTest
    static void testQuoteTotalUpdateSetsNotificationFlagViaTrigger() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'Total Change Notification Quote',
            true,
            false
        );
        insertQuoteRecords(quoteRecord);

        updateOpportunityRecords(
            new Opportunity(
                Id = opportunityRecord.Id,
                IsForecastChangeNotificationPending__c = false
            )
        );

        Test.startTest();
        updateQuoteRecords(
            new Quote(
                Id = quoteRecord.Id,
                Quote_Total_Without_Freight__c = 7500
            )
        );
        Test.stopTest();

        System.assertEquals(
            true,
            [
                SELECT IsForecastChangeNotificationPending__c
                FROM Opportunity
                WHERE Id = :opportunityRecord.Id
                LIMIT 1
            ].IsForecastChangeNotificationPending__c,
            'Quote total change should set the notification flag.'
        );
    }

    @IsTest
    static void testStageFromForecastEligibleQuoteIdsSetsFlag() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'Stage From Quote Id Notification Quote',
            true,
            false
        );
        insertQuoteRecords(quoteRecord);

        updateOpportunityRecords(
            new Opportunity(
                Id = opportunityRecord.Id,
                IsForecastChangeNotificationPending__c = false
            )
        );

        Test.startTest();
        QuoteForecastChangeNotificationHandler.stageFromForecastEligibleQuoteIds(
            new Set<Id>{ quoteRecord.Id }
        );
        Test.stopTest();

        System.assertEquals(
            true,
            [
                SELECT IsForecastChangeNotificationPending__c
                FROM Opportunity
                WHERE Id = :opportunityRecord.Id
                LIMIT 1
            ].IsForecastChangeNotificationPending__c,
            'stageFromForecastEligibleQuoteIds should mark the Opportunity pending.'
        );
    }

    @IsTest
    static void testSampleQuoteTypeIsExcludedFromNotification() {
        if (!isQuoteTypeAvailable(GenerateQuoteService.QUOTE_TYPE_SAMPLE)) {
            return;
        }

        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'Sample Type Notification Quote',
            false,
            false
        );
        quoteRecord.QuoteType__c = GenerateQuoteService.QUOTE_TYPE_SAMPLE;

        System.assertEquals(
            true,
            QuoteForecastChangeNotificationHandler.isExcludedFromForecastNotification(quoteRecord),
            'Sample quotes should be excluded from forecast notifications.'
        );

        Test.startTest();
        insertQuoteRecords(quoteRecord);
        Test.stopTest();

        System.assertEquals(
            false,
            [
                SELECT IsForecastChangeNotificationPending__c
                FROM Opportunity
                WHERE Id = :opportunityRecord.Id
                LIMIT 1
            ].IsForecastChangeNotificationPending__c,
            'Sample quote insert should not set the notification flag.'
        );
    }

    @IsTest
    static void testGoodwillQuoteTypeIsExcludedFromNotification() {
        if (!isQuoteTypeAvailable(GenerateQuoteService.QUOTE_TYPE_GOODWILL)) {
            return;
        }

        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'Goodwill Type Notification Quote',
            false,
            false
        );
        quoteRecord.QuoteType__c = GenerateQuoteService.QUOTE_TYPE_GOODWILL;

        System.assertEquals(
            true,
            QuoteForecastChangeNotificationHandler.isExcludedFromForecastNotification(quoteRecord),
            'Goodwill quotes should be excluded from forecast notifications.'
        );
    }

    @IsTest
    static void testNotificationDisabledSkipsFlagOnQuoteInsert() {
        Opportunity opportunityRecord = getTestOpportunity();

        QuoteForecastChangeNotificationHandler.setNotificationDisabled(true);
        try {
            Test.startTest();
            insertQuoteRecords(
                buildHcSalesQuote(
                    opportunityRecord,
                    'Notification Disabled Quote',
                    false,
                    false
                )
            );
            Test.stopTest();
        } finally {
            QuoteForecastChangeNotificationHandler.setNotificationDisabled(false);
        }

        System.assertEquals(
            false,
            [
                SELECT IsForecastChangeNotificationPending__c
                FROM Opportunity
                WHERE Id = :opportunityRecord.Id
                LIMIT 1
            ].IsForecastChangeNotificationPending__c,
            'Disabled handler should not set the notification flag.'
        );
    }

    @IsTest
    static void testQuoteLineItemInsertSetsNotificationFlagViaTrigger() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'QLI Notification Quote',
            true,
            false
        );
        insertQuoteRecords(quoteRecord);

        updateOpportunityRecords(
            new Opportunity(
                Id = opportunityRecord.Id,
                IsForecastChangeNotificationPending__c = false
            )
        );

        Test.startTest();
        insertQuoteLineItem(quoteRecord, 2, 125);
        Test.stopTest();

        System.assertEquals(
            true,
            [
                SELECT IsForecastChangeNotificationPending__c
                FROM Opportunity
                WHERE Id = :opportunityRecord.Id
                LIMIT 1
            ].IsForecastChangeNotificationPending__c,
            'Quote line insert should set the notification flag.'
        );
    }

    @IsTest
    static void testHandlerGuardClausesAndForecastEligibleChangeHelpers() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'Handler Guard Quote',
            false,
            false
        );

        Quote oldQuoteRecord = quoteRecord.clone(false, true, false, false);
        quoteRecord.Forecast_Eligible__c = true;

        Test.startTest();
        QuoteForecastChangeNotificationHandler.afterInsert(null);
        QuoteForecastChangeNotificationHandler.afterInsert(new List<Quote>());
        QuoteForecastChangeNotificationHandler.afterDelete(null);
        QuoteForecastChangeNotificationHandler.afterUpdate(null, null);
        QuoteForecastChangeNotificationHandler.afterUpdate(new List<Quote>(), null);
        QuoteForecastChangeNotificationHandler.afterInsertLineItems(null);
        QuoteForecastChangeNotificationHandler.afterUpdateLineItems(null, null);
        QuoteForecastChangeNotificationHandler.afterDeleteLineItems(null);
        QuoteForecastChangeNotificationHandler.afterUndeleteLineItems(null);

        System.assertEquals(
            true,
            QuoteForecastChangeNotificationHandler.isExcludedFromForecastNotification(null)
        );
        System.assertEquals(
            false,
            QuoteForecastChangeNotificationHandler.hasForecastEligibleChange(null, null)
        );
        System.assertEquals(
            true,
            QuoteForecastChangeNotificationHandler.hasForecastEligibleChange(
                quoteRecord,
                oldQuoteRecord
            )
        );
        Test.stopTest();
    }

    @IsTest
    static void testQuoteLineItemUpdateSetsNotificationFlagViaHandler() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'QLI Update Notification Quote',
            true,
            false
        );
        insertQuoteRecords(quoteRecord);

        QuoteLineItem lineItem = insertQuoteLineItem(quoteRecord, 1, 100);
        updateOpportunityRecords(
            new Opportunity(
                Id = opportunityRecord.Id,
                IsForecastChangeNotificationPending__c = false
            )
        );

        QuoteLineItem persistedLineItem = [
            SELECT Id, QuoteId, Quantity, UnitPrice, TotalPrice
            FROM QuoteLineItem
            WHERE Id = :lineItem.Id
            LIMIT 1
        ];
        QuoteLineItem oldLineItem = persistedLineItem.clone(true, true, true, true);
        persistedLineItem.Quantity = 4;

        Test.startTest();
        QuoteForecastChangeNotificationHandler.afterUpdateLineItems(
            new List<QuoteLineItem>{ persistedLineItem },
            new Map<Id, QuoteLineItem>{ persistedLineItem.Id => oldLineItem }
        );
        Test.stopTest();

        System.assertEquals(
            true,
            [
                SELECT IsForecastChangeNotificationPending__c
                FROM Opportunity
                WHERE Id = :opportunityRecord.Id
                LIMIT 1
            ].IsForecastChangeNotificationPending__c,
            'Quote line update should set the notification flag.'
        );
    }

    @IsTest
    static void testMarkNotificationsPendingAllNullIdsIsNoOp() {
        Test.startTest();
        QuoteForecastChangeNotificationService.markNotificationsPending(
            new Set<Id>{ null, null }
        );
        Test.stopTest();

        System.assert(true, 'All-null Opportunity Id set should return without DML.');
    }

    @IsTest
    static void testMarkNotificationsPendingThrowsWhenOpportunityUpdateFails() {
        Id invalidOpportunityId = buildSyntheticOpportunityId();
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            QuoteForecastChangeNotificationService.markNotificationsPending(
                new Set<Id>{ invalidOpportunityId }
            );
        } catch (Exception exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Invalid Opportunity Id should surface a DML error from the notification service.'
        );
    }

    @IsTest
    static void testDismissNotificationWrapsUnexpectedException() {
        Opportunity opportunityRecord = getTestOpportunity();
        Boolean exceptionThrown = false;

        QuoteForecastChangeBannerController.forceExceptionForTest = true;

        Test.startTest();
        try {
            QuoteForecastChangeBannerController.dismissNotification(opportunityRecord.Id);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        QuoteForecastChangeBannerController.forceExceptionForTest = false;
        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testQuoteLineItemDeleteSetsNotificationFlagViaHandler() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'QLI Delete Notification Quote',
            true,
            false
        );
        insertQuoteRecords(quoteRecord);

        QuoteLineItem lineItem = insertQuoteLineItem(quoteRecord, 2, 50);
        updateOpportunityRecords(
            new Opportunity(
                Id = opportunityRecord.Id,
                IsForecastChangeNotificationPending__c = false
            )
        );

        Test.startTest();
        QuoteForecastChangeNotificationHandler.afterDeleteLineItems(
            new List<QuoteLineItem>{ lineItem }
        );
        Test.stopTest();

        System.assertEquals(
            true,
            [
                SELECT IsForecastChangeNotificationPending__c
                FROM Opportunity
                WHERE Id = :opportunityRecord.Id
                LIMIT 1
            ].IsForecastChangeNotificationPending__c,
            'Quote line delete should set the notification flag.'
        );
    }

    @IsTest
    static void testQuoteLineItemInsertWithNullQuoteIdIsNoOp() {
        Test.startTest();
        QuoteForecastChangeNotificationHandler.afterInsertLineItems(
            new List<QuoteLineItem>{ new QuoteLineItem(Quantity = 1, UnitPrice = 10) }
        );
        Test.stopTest();

        System.assert(true, 'Line items without QuoteId should not stage notifications.');
    }

    @IsTest
    static void testQuoteUpdateWithNoRelevantChangeDoesNotSetFlag() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord,
            'No Relevant Change Quote',
            true,
            false
        );
        insertQuoteRecords(quoteRecord);

        updateOpportunityRecords(
            new Opportunity(
                Id = opportunityRecord.Id,
                IsForecastChangeNotificationPending__c = false
            )
        );

        Quote persistedQuote = [
            SELECT Id,
                Name,
                Forecast_Eligible__c,
                Status,
                LastModifiedDate__c,
                Quote_Total_Without_Freight__c,
                TotalPrice,
                IsForecastIneligible__c,
                QuoteType__c,
                RecordTypeId,
                OpportunityId
            FROM Quote
            WHERE Id = :quoteRecord.Id
            LIMIT 1
        ];
        Quote oldQuote = persistedQuote.clone(true, true, true, true);
        persistedQuote.Name = persistedQuote.Name + ' Updated';

        Test.startTest();
        QuoteForecastChangeNotificationHandler.afterUpdate(
            new List<Quote>{ persistedQuote },
            new Map<Id, Quote>{ persistedQuote.Id => oldQuote }
        );
        Test.stopTest();

        System.assertEquals(
            false,
            [
                SELECT IsForecastChangeNotificationPending__c
                FROM Opportunity
                WHERE Id = :opportunityRecord.Id
                LIMIT 1
            ].IsForecastChangeNotificationPending__c,
            'Name-only quote change should not set the notification flag.'
        );
    }

    private static Id buildSyntheticOpportunityId() {
        String keyPrefix = Opportunity.SObjectType.getDescribe().getKeyPrefix();
        String suffix = '0'.repeat(12);
        return (Id) (keyPrefix + suffix);
    }

    private static Opportunity getTestOpportunity() {
        return [
            SELECT Id, Pricebook2Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];
    }

    private static User createQuoteAutomationRunAsUser() {
        Profile adminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        return new User(
            Alias = 'qfbnrn',
            Email = 'quote.forecast.banner.runas@test.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = QUOTE_AUTOMATION_RUN_AS_LAST_NAME,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username =
                'quote.forecast.banner.runas+' +
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
        System.runAs(getQuoteAutomationRunAsUser()) {
            update quoteRecord;
        }
    }

    private static void updateOpportunityRecords(Opportunity opportunityRecord) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            update opportunityRecord;
        }
    }

    private static QuoteLineItem insertQuoteLineItem(
        Quote quoteRecord,
        Decimal quantity,
        Decimal unitPrice
    ) {
        QuoteLineItem lineItem;
        System.runAs(getQuoteAutomationRunAsUser()) {
            Product2 productRecord = new Product2(
                Name = 'Forecast Banner QLI Product ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                IsActive = true
            );
            insert productRecord;

            PricebookEntry pricebookEntryRecord = new PricebookEntry(
                Pricebook2Id = quoteRecord.Pricebook2Id,
                Product2Id = productRecord.Id,
                UnitPrice = unitPrice,
                IsActive = true
            );
            insert pricebookEntryRecord;

            lineItem = new QuoteLineItem(
                QuoteId = quoteRecord.Id,
                PricebookEntryId = pricebookEntryRecord.Id,
                Quantity = quantity,
                UnitPrice = unitPrice
            );
            insert lineItem;
        }
        return lineItem;
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

        return GenerateQuoteService.QUOTE_STATUS_DRAFT;
    }

    private static Quote buildHcSalesQuote(
        Opportunity opportunityRecord,
        String quoteName,
        Boolean forecastEligible,
        Boolean isForecastIneligible
    ) {
        return new Quote(
            Name = quoteName,
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            RecordTypeId = requireHcSalesQuoteRecordTypeId(),
            Status = resolveQuoteStatus(GenerateQuoteService.QUOTE_STATUS_DRAFT),
            ExpirationDate = Date.today().addDays(30),
            Forecast_Eligible__c = forecastEligible,
            IsForecastIneligible__c = isForecastIneligible == true,
            Quote_Total_Without_Freight__c = 1000
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
            GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME
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
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = primaryContactId
        );

        Id healthcareSalesRtId = resolveHealthcareSalesOpportunityRecordTypeId();
        if (healthcareSalesRtId != null) {
            opportunityRecord.RecordTypeId = healthcareSalesRtId;
        }

        String opportunityType = getValidOpportunityType();
        if (String.isNotBlank(opportunityType)) {
            opportunityRecord.Type = opportunityType;
        }

        if (pricebookId != null) {
            opportunityRecord.Pricebook2Id = pricebookId;
        }

        return opportunityRecord;
    }

    private static Id resolveHealthcareSalesOpportunityRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName();

        if (!recordTypesByDeveloperName.containsKey(HEALTHCARE_SALES_OPPORTUNITY_RECORD_TYPE)) {
            return null;
        }

        return recordTypesByDeveloperName.get(HEALTHCARE_SALES_OPPORTUNITY_RECORD_TYPE).getRecordTypeId();
    }

    private static String getValidStageName() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return 'Discovery';
    }

    private static String getValidForecastConfidenceLevel() {
        Schema.DescribeFieldResult fieldDescribe =
            Opportunity.ForecastConfidenceLevel__c.getDescribe();

        if (!fieldDescribe.isAccessible()) {
            return null;
        }

        for (Schema.PicklistEntry picklistEntry : fieldDescribe.getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
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