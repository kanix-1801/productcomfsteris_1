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
    private static final String QUOTE_AUTOMATION_RUN_AS_LAST_NAME = 'MissingFcstEligBannerRunAs';
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
        Opportunity opportunityRecord = getTestOpportunity();

        System.assertEquals(
            false,
            isBannerVisibleAsAutomationUser(opportunityRecord.Id)
        );
    }

    @IsTest
    static void testIsBannerVisibleReturnsTrueForDraftQuoteWithoutForecastEligible() {
        Opportunity opportunityRecord = getTestOpportunity();

        insertQuoteRecords(
            buildHcSalesQuote(
                opportunityRecord.Id,
                opportunityRecord.Pricebook2Id,
                'Draft Missing Forecast Quote',
                'Draft',
                false,
                false,
                null
            )
        );

        System.assertEquals(
            true,
            isBannerVisibleAsAutomationUser(opportunityRecord.Id)
        );
    }

    @IsTest
    static void testIsBannerVisibleReturnsFalseWhenForecastEligibleQuoteExists() {
        Opportunity opportunityRecord = getTestOpportunity();

        insertQuoteRecords(
            buildHcSalesQuote(
                opportunityRecord.Id,
                opportunityRecord.Pricebook2Id,
                'Draft Missing Forecast Quote',
                'Draft',
                false,
                false,
                null
            )
        );

        Test.startTest();
        insertQuoteRecords(
            buildHcSalesQuote(
                opportunityRecord.Id,
                opportunityRecord.Pricebook2Id,
                'Open Forecast Eligible Quote',
                'Open',
                false,
                false,
                null
            )
        );
        Test.stopTest();

        System.assertEquals(
            false,
            isBannerVisibleAsAutomationUser(opportunityRecord.Id)
        );
    }

    @IsTest
    static void testIsBannerVisibleReturnsFalseForOpenQuoteWithoutForecastEligible() {
        Opportunity opportunityRecord = getTestOpportunity();

        insertQuoteRecords(
            buildHcSalesQuote(
                opportunityRecord.Id,
                opportunityRecord.Pricebook2Id,
                'Open Missing Forecast Quote',
                'Open',
                false,
                false,
                null
            )
        );

        System.assertEquals(
            false,
            isBannerVisibleAsAutomationUser(opportunityRecord.Id)
        );
    }

    @IsTest
    static void testIsBannerVisibleExcludesForecastIneligibleQuotes() {
        Opportunity opportunityRecord = getTestOpportunity();

        insertQuoteRecords(
            buildHcSalesQuote(
                opportunityRecord.Id,
                opportunityRecord.Pricebook2Id,
                'Ineligible Draft Quote',
                'Draft',
                false,
                true,
                GenerateQuoteService.QUOTE_TYPE_TRIAL
            )
        );

        System.assertEquals(
            false,
            isBannerVisibleAsAutomationUser(opportunityRecord.Id)
        );
    }

    @IsTest
    static void testIsBannerVisibleReturnsTrueForBudgetQuoteWithoutForecastEligible() {
        Opportunity opportunityRecord = getTestOpportunity();

        insertQuoteRecords(
            buildHcSalesQuote(
                opportunityRecord.Id,
                opportunityRecord.Pricebook2Id,
                'Budget Missing Forecast Quote',
                'Budget',
                false,
                false,
                null
            )
        );

        System.assertEquals(
            true,
            isBannerVisibleAsAutomationUser(opportunityRecord.Id)
        );
    }

    private static Boolean isBannerVisibleAsAutomationUser(Id opportunityId) {
        Boolean isVisible;
        System.runAs(getQuoteAutomationRunAsUser()) {
            isVisible = MissingForecastEligibleBannerController.isBannerVisible(opportunityId);
        }
        return isVisible;
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
            Alias = 'mfbrun',
            Email = 'missing.fcst.elig.banner.runas@test.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = QUOTE_AUTOMATION_RUN_AS_LAST_NAME,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username =
                'missing.fcst.elig.banner.runas+' +
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

        return recordTypesByDeveloperName.get(OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME).getRecordTypeId();
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
            RecordTypeId = requireHcSalesQuoteRecordTypeId(),
            Status = resolveQuoteStatus(statusValue),
            ExpirationDate = Date.today().addDays(30),
            Forecast_Eligible__c = forecastEligible,
            IsForecastIneligible__c = isForecastIneligible == true,
            QuoteType__c = quoteType,
            Quote_Total_Without_Freight__c = 1000
        );

        return quoteRecord;
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

    private static String resolveQuoteStatus(String statusValue) {
        for (Schema.PicklistEntry picklistEntry : Quote.Status.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && picklistEntry.getValue().equalsIgnoreCase(statusValue)) {
                return picklistEntry.getValue();
            }
        }

        return statusValue;
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