/**
 * @author Himanshu Chaurasia
 * @date 2026/07/29
 *
 * @description Test class for QuoteForecastChangeBannerController and QuoteForecastChangeNotificationService.
 */
@IsTest
private class QuoteForecastChangeBannerControllerTest {
    private static final String TEST_OPPORTUNITY_NAME = 'Forecast Banner Test Opportunity';

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
    }

    @IsTest
    static void testDismissNotificationClearsFlag() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

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
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

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
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

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
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord.Id,
            'Forecast Banner Trigger Quote',
            false,
            false
        );

        Test.startTest();
        insert quoteRecord;
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
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord.Id,
            'Forecast Eligible Change Quote',
            false,
            false
        );

        insert quoteRecord;

        Opportunity clearedOpportunity = new Opportunity(
            Id = opportunityRecord.Id,
            IsForecastChangeNotificationPending__c = false
        );
        update clearedOpportunity;

        Test.startTest();
        update new Quote(
            Id = quoteRecord.Id,
            Forecast_Eligible__c = true
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
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord.Id,
            'Forecast Ineligible Insert Quote',
            false,
            true
        );

        Test.startTest();
        insert quoteRecord;
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
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord.Id,
            'Trial Type Insert Quote',
            false,
            false
        );
        quoteRecord.QuoteType__c = GenerateQuoteService.QUOTE_TYPE_TRIAL;

        Test.startTest();
        insert quoteRecord;
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
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Quote quoteRecord = buildHcSalesQuote(
            opportunityRecord.Id,
            'Forecast Ineligible Update Quote',
            false,
            true
        );
        insert quoteRecord;

        Opportunity clearedOpportunity = new Opportunity(
            Id = opportunityRecord.Id,
            IsForecastChangeNotificationPending__c = false
        );
        update clearedOpportunity;

        Test.startTest();
        update new Quote(
            Id = quoteRecord.Id,
            Quote_Total_Without_Freight__c = 5000
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

    private static Quote buildHcSalesQuote(
        Id opportunityId,
        String quoteName,
        Boolean forecastEligible,
        Boolean isForecastIneligible
    ) {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName();

        Quote quoteRecord = new Quote(
            Name = quoteName,
            OpportunityId = opportunityId,
            Status = GenerateQuoteService.QUOTE_STATUS_DRAFT,
            ExpirationDate = Date.today().addDays(30),
            Forecast_Eligible__c = forecastEligible,
            IsForecastIneligible__c = isForecastIneligible == true
        );

        if (recordTypesByDeveloperName.containsKey(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME)) {
            quoteRecord.RecordTypeId = recordTypesByDeveloperName
                .get(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME)
                .getRecordTypeId();
        }

        return quoteRecord;
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

        String opportunityType = getValidOpportunityType();
        if (String.isNotBlank(opportunityType)) {
            opportunityRecord.Type = opportunityType;
        }

        if (pricebookId != null) {
            opportunityRecord.Pricebook2Id = pricebookId;
        }

        return opportunityRecord;
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