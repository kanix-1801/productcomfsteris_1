/**
 * @author Himanshu Chaurasia
 * @date 2026/07/23
 *
 * @group Forecast Eligible Quotes
 *
 * @description Test class for UpdateForecastEligibleQuoteController and service.
 */
@IsTest
private class UpdateForecastEligibleQuoteTest {
    private static final String TEST_OPPORTUNITY_NAME = 'Forecast Eligible Quote Test Opportunity';

    @TestSetup
    static void setupData() {
        Id standardPricebookId = Test.getStandardPricebookId();

        Account accountRecord = new Account(
            Name = 'Forecast Eligible Test Account',
            SourceSystemID__c = 'FE-TEST-ACCT',
            OracleAddressId__c = '638265'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Forecast',
            LastName = 'Eligible Contact',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Opportunity opportunityRecord = buildOpportunity(
            TEST_OPPORTUNITY_NAME,
            accountRecord.Id,
            contactRecord.Id,
            standardPricebookId
        );
        insert opportunityRecord;

        insert new List<Quote>{
            buildQuote(opportunityRecord, 'Open Quote Oldest', 'Open', false, Datetime.now().addDays(-10)),
            buildQuote(opportunityRecord, 'Open Quote Newer', 'Open', false, Datetime.now().addDays(-1)),
            buildQuote(opportunityRecord, 'Open Quote Ineligible', 'Open', false, Datetime.now().addDays(-2), true),
            buildQuote(opportunityRecord, 'Closed Quote', 'Closed', false, null),
            buildQuote(opportunityRecord, 'Draft Quote', 'Draft', false, null),
            buildQuote(opportunityRecord, 'Budget Quote', 'Budget', false, null)
        };
    }

    @IsTest
    static void testGetQuotesReturnsOnlyForecastManageableQuotes() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Test.startTest();
        List<UpdateForecastEligibleQuoteController.QuoteRow> quoteRows =
            UpdateForecastEligibleQuoteController.getQuotes(opportunityRecord.Id);
        Test.stopTest();

        System.assertEquals(2, quoteRows.size(), 'Draft, Budget, and Closed quotes should be excluded.');

        Map<String, UpdateForecastEligibleQuoteController.QuoteRow> rowsByName =
            new Map<String, UpdateForecastEligibleQuoteController.QuoteRow>();
        for (UpdateForecastEligibleQuoteController.QuoteRow quoteRow : quoteRows) {
            rowsByName.put(quoteRow.quoteName, quoteRow);
        }

        System.assertEquals(true, rowsByName.containsKey('Open Quote Oldest'));
        System.assertEquals(true, rowsByName.containsKey('Open Quote Newer'));
        System.assertEquals(false, rowsByName.containsKey('Closed Quote'));
        System.assertEquals(false, rowsByName.get('Open Quote Oldest').forecastEligibleReadOnly);
        System.assertEquals(false, rowsByName.get('Open Quote Newer').forecastEligibleReadOnly);
    }

    @IsTest
    static void testGetQuotesDoesNotAutoDesignateForecastEligibleQuote() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Quote oldestOpenQuote = [
            SELECT Id
            FROM Quote
            WHERE Name = 'Open Quote Oldest'
            LIMIT 1
        ];

        Quote newerOpenQuote = [
            SELECT Id
            FROM Quote
            WHERE Name = 'Open Quote Newer'
            LIMIT 1
        ];

        TriggerHandler.bypass('QuoteTriggerHandler');
        update new List<Quote>{
            new Quote(Id = oldestOpenQuote.Id, Forecast_Eligible__c = false),
            new Quote(Id = newerOpenQuote.Id, Forecast_Eligible__c = true)
        };
        TriggerHandler.clearBypass('QuoteTriggerHandler');

        Test.startTest();
        List<UpdateForecastEligibleQuoteController.QuoteRow> quoteRows =
            UpdateForecastEligibleQuoteController.getQuotes(opportunityRecord.Id);
        Test.stopTest();

        Map<String, UpdateForecastEligibleQuoteController.QuoteRow> rowsByName =
            new Map<String, UpdateForecastEligibleQuoteController.QuoteRow>();
        for (UpdateForecastEligibleQuoteController.QuoteRow quoteRow : quoteRows) {
            rowsByName.put(quoteRow.quoteName, quoteRow);
        }

        System.assertEquals(
            false,
            rowsByName.get('Open Quote Oldest').forecastEligible,
            'Opening the modal should not auto-designate the earliest Open quote.'
        );
        System.assertEquals(
            true,
            rowsByName.get('Open Quote Newer').forecastEligible,
            'Existing Forecast Eligible selections should display unchanged.'
        );
    }

    @IsTest
    static void testSaveForecastEligibleQuotesUpdatesSelections() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        List<UpdateForecastEligibleQuoteController.QuoteRow> quoteRows =
            UpdateForecastEligibleQuoteController.getQuotes(opportunityRecord.Id);

        UpdateForecastEligibleQuoteController.QuoteRow newerOpenQuoteRow;

        for (UpdateForecastEligibleQuoteController.QuoteRow quoteRow : quoteRows) {
            if (quoteRow.quoteName == 'Open Quote Newer') {
                newerOpenQuoteRow = quoteRow;
            }
        }

        System.assertNotEquals(null, newerOpenQuoteRow, 'Expected editable Open quote row.');

        List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest> updates =
            new List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest>{
                buildUpdateRequest(newerOpenQuoteRow.id, true)
            };

        Test.startTest();
        UpdateForecastEligibleQuoteController.saveForecastEligibleQuotes(
            opportunityRecord.Id,
            buildUpdatesJson(updates)
        );
        Test.stopTest();

        Quote updatedQuote = [
            SELECT Id, Forecast_Eligible__c
            FROM Quote
            WHERE Id = :newerOpenQuoteRow.id
            LIMIT 1
        ];

        System.assertEquals(true, updatedQuote.Forecast_Eligible__c);
    }

    @IsTest
    static void testSaveRejectsWhenNoForecastEligibleQuotesSelected() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Quote oldestOpenQuote = [
            SELECT Id
            FROM Quote
            WHERE Name = 'Open Quote Oldest'
            LIMIT 1
        ];

        Quote newerOpenQuote = [
            SELECT Id
            FROM Quote
            WHERE Name = 'Open Quote Newer'
            LIMIT 1
        ];

        List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest> updates =
            new List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest>{
                buildUpdateRequest(oldestOpenQuote.Id, false),
                buildUpdateRequest(newerOpenQuote.Id, false)
            };

        Boolean exceptionThrown = false;
        String exceptionMessage;

        Test.startTest();
        try {
            UpdateForecastEligibleQuoteService.saveForecastEligibleSelections(
                opportunityRecord.Id,
                updates
            );
        } catch (GenerateQuoteException exceptionValue) {
            exceptionThrown = true;
            exceptionMessage = exceptionValue.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Saving with no selected quotes should fail.');
        System.assertEquals(
            UpdateForecastEligibleQuoteService.AT_LEAST_ONE_FORECAST_ELIGIBLE_ERROR,
            exceptionMessage
        );
    }

    @IsTest
    static void testSaveAllowsDeselectingOldestOpenQuoteWhenAnotherRemainsSelected() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Quote oldestOpenQuote = [
            SELECT Id, Forecast_Eligible__c
            FROM Quote
            WHERE Name = 'Open Quote Oldest'
            LIMIT 1
        ];

        Quote newerOpenQuote = [
            SELECT Id
            FROM Quote
            WHERE Name = 'Open Quote Newer'
            LIMIT 1
        ];

        List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest> updates =
            new List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest>{
                buildUpdateRequest(oldestOpenQuote.Id, false),
                buildUpdateRequest(newerOpenQuote.Id, true)
            };

        Test.startTest();
        UpdateForecastEligibleQuoteController.saveForecastEligibleQuotes(
            opportunityRecord.Id,
            buildUpdatesJson(updates)
        );
        Test.stopTest();

        oldestOpenQuote = [
            SELECT Id, Forecast_Eligible__c
            FROM Quote
            WHERE Id = :oldestOpenQuote.Id
            LIMIT 1
        ];

        Quote updatedNewerOpenQuote = [
            SELECT Id, Forecast_Eligible__c
            FROM Quote
            WHERE Id = :newerOpenQuote.Id
            LIMIT 1
        ];

        System.assertEquals(false, oldestOpenQuote.Forecast_Eligible__c);
        System.assertEquals(true, updatedNewerOpenQuote.Forecast_Eligible__c);
    }

    @IsTest
    static void testSaveRejectsClosedQuoteOutsideManageableSet() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Quote closedQuote = [
            SELECT Id
            FROM Quote
            WHERE Name = 'Closed Quote'
            LIMIT 1
        ];

        List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest> updates =
            new List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest>{
                buildUpdateRequest(closedQuote.Id, true)
            };

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            UpdateForecastEligibleQuoteController.saveForecastEligibleQuotes(
                opportunityRecord.Id,
                buildUpdatesJson(updates)
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Closed quote should not be savable through this UI.');
    }

    @IsTest
    static void testSaveRejectsQuoteOutsideManageableSet() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Quote draftQuote = [
            SELECT Id
            FROM Quote
            WHERE Name = 'Draft Quote'
            LIMIT 1
        ];

        List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest> updates =
            new List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest>{
                buildUpdateRequest(draftQuote.Id, true)
            };

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            UpdateForecastEligibleQuoteController.saveForecastEligibleQuotes(
                opportunityRecord.Id,
                buildUpdatesJson(updates)
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Draft quote should not be savable through this UI.');
    }

    @IsTest
    static void testGetQuotesExcludesForecastIneligibleQuotes() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Test.startTest();
        List<UpdateForecastEligibleQuoteController.QuoteRow> quoteRows =
            UpdateForecastEligibleQuoteController.getQuotes(opportunityRecord.Id);
        Test.stopTest();

        Map<String, UpdateForecastEligibleQuoteController.QuoteRow> rowsByName =
            new Map<String, UpdateForecastEligibleQuoteController.QuoteRow>();
        for (UpdateForecastEligibleQuoteController.QuoteRow quoteRow : quoteRows) {
            rowsByName.put(quoteRow.quoteName, quoteRow);
        }

        System.assertEquals(2, quoteRows.size(), 'Forecast-ineligible Open quotes should be excluded.');
        System.assertEquals(false, rowsByName.containsKey('Open Quote Ineligible'));
    }

    @IsTest
    static void testSaveRejectsForecastIneligibleQuoteOutsideManageableSet() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Quote ineligibleQuote = [
            SELECT Id
            FROM Quote
            WHERE Name = 'Open Quote Ineligible'
            LIMIT 1
        ];

        List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest> updates =
            new List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest>{
                buildUpdateRequest(ineligibleQuote.Id, true)
            };

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            UpdateForecastEligibleQuoteController.saveForecastEligibleQuotes(
                opportunityRecord.Id,
                buildUpdatesJson(updates)
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Forecast-ineligible quote should not be savable through this UI.'
        );
    }

    private static Quote buildQuote(
        Opportunity opportunityRecord,
        String quoteName,
        String statusValue,
        Boolean forecastEligible,
        Datetime lastModifiedDate
    ) {
        return buildQuote(
            opportunityRecord,
            quoteName,
            statusValue,
            forecastEligible,
            lastModifiedDate,
            false
        );
    }

    private static Quote buildQuote(
        Opportunity opportunityRecord,
        String quoteName,
        String statusValue,
        Boolean forecastEligible,
        Datetime lastModifiedDate,
        Boolean isForecastIneligible
    ) {
        Quote quoteRecord = new Quote(
            Name = quoteName,
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            Status = resolveQuoteStatus(statusValue),
            Forecast_Eligible__c = forecastEligible,
            IsForecastIneligible__c = isForecastIneligible == true,
            Quote_Total_Without_Freight__c = 1000,
            ExpirationDate = Date.today().addDays(30)
        );

        if (lastModifiedDate != null) {
            quoteRecord.LastModifiedDate__c = lastModifiedDate;
        }

        return quoteRecord;
    }

    private static UpdateForecastEligibleQuoteController.QuoteUpdateRequest buildUpdateRequest(
        Id quoteId,
        Boolean forecastEligible
    ) {
        UpdateForecastEligibleQuoteController.QuoteUpdateRequest updateRequest =
            new UpdateForecastEligibleQuoteController.QuoteUpdateRequest();
        updateRequest.quoteId = quoteId;
        updateRequest.forecastEligible = forecastEligible;
        return updateRequest;
    }

    private static String buildUpdatesJson(
        List<UpdateForecastEligibleQuoteController.QuoteUpdateRequest> updates
    ) {
        List<Map<String, Object>> payload = new List<Map<String, Object>>();

        for (UpdateForecastEligibleQuoteController.QuoteUpdateRequest updateRequest : updates) {
            payload.add(
                new Map<String, Object>{
                    'quoteId' => updateRequest.quoteId,
                    'forecastEligible' => updateRequest.forecastEligible
                }
            );
        }

        return JSON.serialize(payload);
    }

    private static String resolveQuoteStatus(String statusValue) {
        for (Schema.PicklistEntry picklistEntry : Quote.Status.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && picklistEntry.getValue().equalsIgnoreCase(statusValue)) {
                return picklistEntry.getValue();
            }
        }

        return statusValue;
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

    private static String getValidOpportunityType() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.Type.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
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

}