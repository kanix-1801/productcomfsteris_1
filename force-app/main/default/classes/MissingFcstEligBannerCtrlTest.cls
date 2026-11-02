/**
 * @author Himanshu Chaurasia
 * @date 2026/08/19
 *
 * @description Test class for MissingForecastEligibleBannerController.
 */
@IsTest
private class MissingFcstEligBannerCtrlTest {
    private static final String TEST_OPPORTUNITY_NAME = 'Missing Forecast Eligible Banner Opportunity';
    private static final String OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME = 'Healthcare_Sales';

    @TestSetup
    static void setupData() {
        Id standardPricebookId = Test.getStandardPricebookId();

        Account accountRecord = new Account(
            Name = 'Missing Forecast Banner Account',
            SourceSystemID__c = 'MFB-TEST-ACCT'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Missing',
            LastName = 'Forecast Banner',
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
    static void testIsBannerVisibleReturnsFalseForNullOpportunity() {
        System.assertEquals(
            false,
            MissingForecastEligibleBannerController.isBannerVisible(null)
        );
    }

    @IsTest
    static void testIsBannerVisibleReturnsFalseWhenNoQuotesExist() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        System.assertEquals(
            false,
            MissingForecastEligibleBannerController.isBannerVisible(opportunityRecord.Id)
        );
    }

    @IsTest
    static void testIsBannerVisibleReturnsTrueForDraftQuoteWithoutForecastEligible() {
        Opportunity opportunityRecord = [
            SELECT Id, Pricebook2Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        insert buildHcSalesQuote(
            opportunityRecord.Id,
            opportunityRecord.Pricebook2Id,
            'Draft Missing Forecast Quote',
            'Draft',
            false,
            false,
            null
        );

        System.assertEquals(
            true,
            MissingForecastEligibleBannerController.isBannerVisible(opportunityRecord.Id)
        );
    }

    @IsTest
    static void testIsBannerVisibleReturnsFalseWhenForecastEligibleQuoteExists() {
        Opportunity opportunityRecord = [
            SELECT Id, Pricebook2Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        insert buildHcSalesQuote(
            opportunityRecord.Id,
            opportunityRecord.Pricebook2Id,
            'Draft Missing Forecast Quote',
            'Draft',
            false,
            false,
            null
        );

        Test.startTest();
        insert buildHcSalesQuote(
            opportunityRecord.Id,
            opportunityRecord.Pricebook2Id,
            'Open Forecast Eligible Quote',
            'Open',
            false,
            false,
            null
        );
        Test.stopTest();

        System.assertEquals(
            false,
            MissingForecastEligibleBannerController.isBannerVisible(opportunityRecord.Id)
        );
    }

    @IsTest
    static void testIsBannerVisibleReturnsFalseForOpenQuoteWithoutForecastEligible() {
        Opportunity opportunityRecord = [
            SELECT Id, Pricebook2Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        insert buildHcSalesQuote(
            opportunityRecord.Id,
            opportunityRecord.Pricebook2Id,
            'Open Missing Forecast Quote',
            'Open',
            false,
            false,
            null
        );

        System.assertEquals(
            false,
            MissingForecastEligibleBannerController.isBannerVisible(opportunityRecord.Id)
        );
    }

    @IsTest
    static void testIsBannerVisibleExcludesForecastIneligibleQuotes() {
        Opportunity opportunityRecord = [
            SELECT Id, Pricebook2Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        insert buildHcSalesQuote(
            opportunityRecord.Id,
            opportunityRecord.Pricebook2Id,
            'Ineligible Draft Quote',
            'Draft',
            false,
            true,
            GenerateQuoteService.QUOTE_TYPE_TRIAL
        );

        System.assertEquals(
            false,
            MissingForecastEligibleBannerController.isBannerVisible(opportunityRecord.Id)
        );
    }

    @IsTest
    static void testIsBannerVisibleReturnsTrueForBudgetQuoteWithoutForecastEligible() {
        Opportunity opportunityRecord = [
            SELECT Id, Pricebook2Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        insert buildHcSalesQuote(
            opportunityRecord.Id,
            opportunityRecord.Pricebook2Id,
            'Budget Missing Forecast Quote',
            'Budget',
            false,
            false,
            null
        );

        System.assertEquals(
            true,
            MissingForecastEligibleBannerController.isBannerVisible(opportunityRecord.Id)
        );
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

    private static Quote buildHcSalesQuote(
        Id opportunityId,
        Id pricebookId,
        String quoteName,
        String statusValue,
        Boolean forecastEligible,
        Boolean isForecastIneligible,
        String quoteType
    ) {
        Quote quoteRecord = new Quote(
            Name = quoteName,
            OpportunityId = opportunityId,
            Pricebook2Id = pricebookId,
            Status = statusValue,
            ExpirationDate = Date.today().addDays(30),
            Forecast_Eligible__c = forecastEligible,
            IsForecastIneligible__c = isForecastIneligible == true,
            QuoteType__c = quoteType,
            Quote_Total_Without_Freight__c = 1000
        );

        Id recordTypeId = resolveHcSalesRecordTypeId();
        if (recordTypeId != null) {
            quoteRecord.RecordTypeId = recordTypeId;
        }

        return quoteRecord;
    }

    private static Id resolveHcSalesRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName();

        if (!recordTypesByDeveloperName.containsKey(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME)) {
            return null;
        }

        return recordTypesByDeveloperName
            .get(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME)
            .getRecordTypeId();
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
        for (Schema.PicklistEntry picklistEntry :
            Opportunity.ForecastConfidenceLevel__c.getDescribe().getPicklistValues()) {
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