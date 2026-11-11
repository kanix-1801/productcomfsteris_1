/**
 * @description GC-3618 - Tests incomplete Healthcare Quote cleanup.
 */
@IsTest(SeeAllData=false)
private class IncompleteHcQuoteCleanupBatchTest {
    @IsTest
    static void deletesIncompleteHcQuoteAndKeepsQuoteThatHasScId() {
        System.runAs(runningUser()) {
            QuoteFixture fixture = insertQuotes(true);

            Test.startTest();
            IncompleteHcQuoteCleanupBatch batchJob = new IncompleteHcQuoteCleanupBatch();
            batchJob.start(null);
            batchJob.execute(null, new List<Quote>{ new Quote(Id = fixture.incompleteQuoteId) });
            batchJob.finish(null);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Quote WHERE Id = :fixture.incompleteQuoteId],
                'Incomplete HC Quote is deleted'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM QuoteLineItem WHERE Id = :fixture.incompleteLineId],
                'Incomplete Quote Line is deleted'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Quote WHERE Id = :fixture.receivedQuoteId],
                'HC Quote with an SC Quote Id stays'
            );
        }
    }

    @IsTest
    static void queryLocatorReturnsOnlyIncompleteHcQuotes() {
        System.runAs(runningUser()) {
            QuoteFixture fixture = insertQuotes(true);

            Set<Id> selectedIds = new Set<Id>();
            Database.QueryLocatorIterator iterator = IncompleteHcQuoteCleanupSelector.getIncompleteQuoteQueryLocator()
                .iterator();
            while (iterator.hasNext()) {
                selectedIds.add(iterator.next().Id);
            }

            Assert.isTrue(selectedIds.contains(fixture.incompleteQuoteId), 'Blank SC Quote Id on an HC Quote is selected');
            Assert.isFalse(selectedIds.contains(fixture.receivedQuoteId), 'Populated SC Quote Id is excluded');
        }
    }

    @IsTest
    static void emptyScopeDoesNotDelete() {
        System.runAs(runningUser()) {
            IncompleteHcQuoteCleanupService.CleanupTotals totals = IncompleteHcQuoteCleanupService.deleteIncompleteQuotes(
                new List<Quote>()
            );
            IncompleteHcQuoteCleanupService.CleanupTotals nullTotals = IncompleteHcQuoteCleanupService.deleteIncompleteQuotes(
                null
            );

            Assert.areEqual(0, totals.quotesDeleted, 'Empty scope deletes no quotes');
            Assert.areEqual(0, totals.linesDeleted, 'Empty scope deletes no quote lines');
            Assert.areEqual(0, totals.failureCount, 'Empty scope records no failures');
            Assert.areEqual(0, nullTotals.quotesDeleted, 'Null scope deletes no quotes');
        }
    }

    @IsTest
    static void deletesQuoteThatHasNoLines() {
        System.runAs(runningUser()) {
            QuoteFixture fixture = insertQuotes(false);

            IncompleteHcQuoteCleanupService.CleanupTotals totals = IncompleteHcQuoteCleanupService.deleteIncompleteQuotes(
                new List<Quote>{ new Quote(Id = fixture.incompleteQuoteId) }
            );

            Assert.areEqual(1, totals.quotesDeleted, 'Quote with no lines is deleted');
            Assert.areEqual(0, totals.linesDeleted, 'No lines are deleted');
            Assert.areEqual(0, totals.failureCount, 'Quote delete has no failures');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Quote WHERE Id = :fixture.incompleteQuoteId],
                'Incomplete quote without lines is removed'
            );
        }
    }

    @IsTest
    static void lineDeleteFailureLeavesQuoteForRetry() {
        System.runAs(runningUser()) {
            QuoteFixture fixture = insertQuotes(true);
            IncompleteHcQuoteCleanupService.testLineDeleteResults = new List<Database.DeleteResult>{ failedDeleteResult() };

            IncompleteHcQuoteCleanupService.CleanupTotals totals = IncompleteHcQuoteCleanupService.deleteIncompleteQuotes(
                new List<Quote>{ new Quote(Id = fixture.incompleteQuoteId) }
            );

            Assert.areEqual(0, totals.linesDeleted, 'Failed line delete is not counted as deleted');
            Assert.areEqual(0, totals.quotesDeleted, 'Parent quote is not deleted after a line failure');
            Assert.areEqual(1, totals.failureCount, 'Line delete failure is counted');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Quote WHERE Id = :fixture.incompleteQuoteId],
                'Quote stays so the next run can retry it'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM QuoteLineItem WHERE Id = :fixture.incompleteLineId],
                'Quote line stays when the delete fails'
            );
        }
    }

    @IsTest
    static void quoteDeleteFailureIsCounted() {
        System.runAs(runningUser()) {
            QuoteFixture fixture = insertQuotes(false);
            IncompleteHcQuoteCleanupService.testQuoteDeleteResults = new List<Database.DeleteResult>{
                failedDeleteResult()
            };

            IncompleteHcQuoteCleanupService.CleanupTotals totals = IncompleteHcQuoteCleanupService.deleteIncompleteQuotes(
                new List<Quote>{ new Quote(Id = fixture.incompleteQuoteId) }
            );

            Assert.areEqual(0, totals.quotesDeleted, 'Failed quote delete is not counted as deleted');
            Assert.areEqual(1, totals.failureCount, 'Quote delete failure is counted');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Quote WHERE Id = :fixture.incompleteQuoteId],
                'Quote stays when the delete fails'
            );
            Assert.isTrue(
                IncompleteHcQuoteCleanupService.formatErrors(failedDeleteResult().getErrors()).contains('Delete blocked'),
                'Delete errors are formatted'
            );
            Assert.areEqual('', IncompleteHcQuoteCleanupService.formatErrors(null), 'Null errors format to an empty string');
        }
    }

    @IsTest
    static void schedulableSubmitsBatch() {
        System.runAs(runningUser()) {
            IncompleteHcQuoteCleanupBatch.skipFlexQueueCheckForTest = true;

            Test.startTest();
            System.schedule(
                'GC-3618 incomplete quote cleanup test',
                IncompleteHcQuoteCleanupBatch.SCHEDULE_CRON_SUNDAY_1AM,
                new IncompleteHcQuoteCleanupBatch()
            );
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = 'GC-3618 incomplete quote cleanup test'],
                'Sunday cleanup job is scheduled'
            );
        }
    }

    @IsTest
    static void flexQueueFullBlocksSubmit() {
        System.runAs(runningUser()) {
            IncompleteHcQuoteCleanupBatch.testFlexQueueHoldingCountOverride =
                IncompleteHcQuoteCleanupBatch.FLEX_QUEUE_MAX_BATCH_JOBS;

            try {
                IncompleteHcQuoteCleanupBatch.submitBatch();
                Assert.fail('A full flex queue should block the batch');
            } catch (IncompleteHcQuoteCleanupException exceptionValue) {
                Assert.isTrue(
                    exceptionValue.getMessage().contains('flex queue is full'),
                    'Flex queue message is returned'
                );
            }
        }
    }

    @IsTest
    static void startExecuteAndFinishCatchFailures() {
        System.runAs(runningUser()) {
            IncompleteHcQuoteCleanupBatch.throwInStart = true;
            IncompleteHcQuoteCleanupBatch batchJob = new IncompleteHcQuoteCleanupBatch();
            try {
                batchJob.start(null);
                Assert.fail('Start should rethrow the test failure');
            } catch (QueryException exceptionValue) {
                Assert.areEqual(1, IncompleteHcQuoteCleanupBatch.startCatchCount, 'Start failure is logged');
            }

            IncompleteHcQuoteCleanupBatch.throwInStart = false;
            IncompleteHcQuoteCleanupBatch.throwInExecute = true;
            batchJob.execute(null, new List<Quote>());
            Assert.areEqual(1, IncompleteHcQuoteCleanupBatch.executeCatchCount, 'Execute failure is logged');

            IncompleteHcQuoteCleanupBatch.throwInExecute = false;
            IncompleteHcQuoteCleanupBatch.throwInFinish = true;
            batchJob.finish(null);
            Assert.areEqual(1, IncompleteHcQuoteCleanupBatch.finishCatchCount, 'Finish failure is logged');
        }
    }

    @IsTest
    static void cleanupRestoresQuoteTriggerBypassState() {
        System.runAs(runningUser()) {
            QuoteFixture fixture = insertQuotes(true);
            TriggerHandler.bypass('QuoteLineItemTriggerHandler');

            IncompleteHcQuoteCleanupService.deleteIncompleteQuotes(
                new List<Quote>{ new Quote(Id = fixture.incompleteQuoteId) }
            );

            Assert.isFalse(
                TriggerHandler.isBypassed('QuoteTriggerHandler'),
                'Quote trigger bypass is released after cleanup'
            );
            Assert.isTrue(
                TriggerHandler.isBypassed('QuoteLineItemTriggerHandler'),
                'Quote line bypass set by the caller is left in place'
            );
            TriggerHandler.clearBypass('QuoteLineItemTriggerHandler');
        }
    }

    @IsTest
    static void validationBypassIsClearedAfterCleanup() {
        System.runAs(runningUser()) {
            QuoteFixture fixture = insertQuotes(false);
            List<Automation_Setting_Validation_Rule__c> beforeSettings = userValidationSettings();

            IncompleteHcQuoteCleanupService.deleteIncompleteQuotes(
                new List<Quote>{ new Quote(Id = fixture.incompleteQuoteId) }
            );

            List<Automation_Setting_Validation_Rule__c> afterSettings = userValidationSettings();
            Assert.areEqual(
                beforeSettings.size(),
                afterSettings.size(),
                'Cleanup does not leave a user validation setting behind'
            );
        }
    }

    @IsTest
    static void existingValidationSettingIsRestoredWhenDeleteFails() {
        System.runAs(runningUser()) {
            QuoteFixture fixture = insertQuotes(false);
            Automation_Setting_Validation_Rule__c setting = userValidationSetting();
            setting.disableAll__c = false;
            upsert setting;

            IncompleteHcQuoteCleanupService.testQuoteDeleteResults = new List<Database.DeleteResult>{
                failedDeleteResult()
            };
            try {
                IncompleteHcQuoteCleanupService.deleteIncompleteQuotes(
                    new List<Quote>{ new Quote(Id = fixture.incompleteQuoteId) }
                );
            } finally {
                IncompleteHcQuoteCleanupService.testQuoteDeleteResults = null;
            }

            Automation_Setting_Validation_Rule__c restored = userValidationSetting();
            Assert.areEqual(setting.Id, restored.Id, 'The existing user validation setting is kept');
            Assert.areEqual(false, restored.disableAll__c, 'disableAll is restored after a failed delete');
        }
    }

    @IsTest
    static void startFailureClearsValidationBypass() {
        System.runAs(runningUser()) {
            Integer beforeCount = userValidationSettings().size();
            IncompleteHcQuoteCleanupBatch.throwInStart = true;
            try {
                new IncompleteHcQuoteCleanupBatch().start(null);
                Assert.fail('Start should rethrow the test failure');
            } catch (QueryException exceptionValue) {
                Assert.areEqual(
                    beforeCount,
                    userValidationSettings().size(),
                    'A failed start removes the validation bypass it created'
                );
            } finally {
                IncompleteHcQuoteCleanupBatch.throwInStart = false;
            }
        }
    }

    private static Database.DeleteResult failedDeleteResult() {
        return (Database.DeleteResult) JSON.deserialize(
            '{"success":false,"errors":[{"message":"Delete blocked","statusCode":"FIELD_CUSTOM_VALIDATION_EXCEPTION","fields":[]}]}',
            Database.DeleteResult.class
        );
    }

    private static QuoteFixture insertQuotes(Boolean includeLine) {
        Price_List__c priceList = new Price_List__c(
            Name = 'GC-3618 Price List',
            Price_List_Id__c = 'PL-GC-3618'
        );
        insert priceList;

        Account accountRecord = new Account(
            Name = 'GC-3618 Prospect',
            RecordTypeId = accountRecordTypeId('Prospect'),
            CustomerClassCode__c = 'HC',
            OrgIDs__c = '83',
            Price_List__c = priceList.Id,
            BillingStreet = '123 Main St',
            BillingCity = 'Cleveland',
            BillingStateCode = 'OH',
            BillingCountryCode = 'US',
            BillingPostalCode = '44101',
            TAS_Retry__c = false
        );
        insert accountRecord;

        Id pricebookId = Test.getStandardPricebookId();
        Opportunity opportunityRecord = new Opportunity(
            Name = 'GC-3618 HC Opportunity',
            AccountId = accountRecord.Id,
            RecordTypeId = opportunityRecordTypeId('Healthcare_Sales'),
            StageName = 'Discovery',
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            Pricebook2Id = pricebookId,
            BypassValidations__c = true
        );
        insert opportunityRecord;

        Product2 productRecord = new Product2(
            Name = 'GC-3618 Product',
            IsActive = true,
            BusinessUnit__c = 'IMS'
        );
        insert productRecord;

        PricebookEntry pricebookEntry = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = productRecord.Id,
            UnitPrice = 100,
            IsActive = true,
            CurrencyIsoCode = UserInfo.getDefaultCurrency()
        );
        insert pricebookEntry;

        Id hcQuoteRecordTypeId = quoteRecordTypeId('HCSales');
        String currencyCode = UserInfo.getDefaultCurrency();

        TriggerHandler.bypass('QuoteTriggerHandler');
        TriggerHandler.bypass('QuoteLineItemTriggerHandler');
        QuoteFixture fixture = new QuoteFixture();
        try {
            Quote incompleteQuote = new Quote(
                Name = 'GC-3618 Incomplete',
                OpportunityId = opportunityRecord.Id,
                Pricebook2Id = pricebookId,
                RecordTypeId = hcQuoteRecordTypeId,
                Status = 'Draft',
                ExpirationDate = Date.today().addDays(30),
                QuoteType__c = 'Normal Quote',
                CurrencyIsoCode = currencyCode
            );
            Quote receivedQuote = new Quote(
                Name = 'GC-3618 Received',
                OpportunityId = opportunityRecord.Id,
                Pricebook2Id = pricebookId,
                RecordTypeId = hcQuoteRecordTypeId,
                Status = 'Draft',
                ExpirationDate = Date.today().addDays(30),
                QuoteType__c = 'Normal Quote',
                CurrencyIsoCode = currencyCode,
                SalesConnectionQuoteID__c = 'SC-3618'
            );
            Database.insert(new List<Quote>{ incompleteQuote, receivedQuote }, AccessLevel.SYSTEM_MODE);

            fixture.incompleteQuoteId = incompleteQuote.Id;
            fixture.receivedQuoteId = receivedQuote.Id;
            if (includeLine) {
                QuoteLineItem incompleteLine = new QuoteLineItem(
                    QuoteId = incompleteQuote.Id,
                    PricebookEntryId = pricebookEntry.Id,
                    Quantity = 1,
                    UnitPrice = 100
                );
                Database.insert(incompleteLine, AccessLevel.SYSTEM_MODE);
                fixture.incompleteLineId = incompleteLine.Id;
            }
        } finally {
            TriggerHandler.clearBypass('QuoteTriggerHandler');
            TriggerHandler.clearBypass('QuoteLineItemTriggerHandler');
        }
        return fixture;
    }

    private static User runningUser() {
        return new User(Id = UserInfo.getUserId());
    }

    private static List<Automation_Setting_Validation_Rule__c> userValidationSettings() {
        return [
            SELECT Id, disableAll__c
            FROM Automation_Setting_Validation_Rule__c
            WHERE SetupOwnerId = :UserInfo.getUserId()
        ];
    }

    private static Automation_Setting_Validation_Rule__c userValidationSetting() {
        List<Automation_Setting_Validation_Rule__c> settings = userValidationSettings();
        if (!settings.isEmpty()) {
            return settings[0];
        }
        return new Automation_Setting_Validation_Rule__c(SetupOwnerId = UserInfo.getUserId());
    }

    private static Id accountRecordTypeId(String developerName) {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(developerName)
            .getRecordTypeId();
    }

    private static Id opportunityRecordTypeId(String developerName) {
        return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get(developerName)
            .getRecordTypeId();
    }

    private static Id quoteRecordTypeId(String developerName) {
        return Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName()
            .get(developerName)
            .getRecordTypeId();
    }

    private class QuoteFixture {
        Id incompleteQuoteId;
        Id incompleteLineId;
        Id receivedQuoteId;
    }
}