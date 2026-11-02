/**
 * @author Himanshu Chaurasia
 * @date 2026/10/14
 *
 * @description GC-3457 UC3 - Tests EPP conversion quote closure banner.
 */
@IsTest
private class OppEppConvQuoteBannerTest {
    private static final String TEST_OPPORTUNITY_NAME = 'EPP Conversion Quote Banner Test Opportunity';

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
        stampRunningUserHrisId();
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'EPP Conversion Quote 3', 'Open');
        quoteRecord.SalesConnectionQuoteID__c = '2283704';
        update quoteRecord;
        opportunityRecord.PendingEppConversionQuoteClosure__c = true;
        update opportunityRecord;
        ScOpportunityQuoteEventGateway.forceHardcodedResponse = true;

        Test.startTest();
        OppEppConversionQuoteBannerController.closeAllOpenQuotes(opportunityRecord.Id);
        Test.stopTest();

        ScOpportunityQuoteEventGateway.forceHardcodedResponse = false;

        Quote updatedQuote = [
            SELECT Status, ClosureDisposition__c, Forecast_Eligible__c
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
        System.assertEquals(
            OppEppConversionQuoteService.CONVERTED_TO_EPP_DISPOSITION,
            updatedQuote.ClosureDisposition__c
        );
        System.assertEquals(false, updatedQuote.Forecast_Eligible__c);
        System.assertEquals(false, updatedOpportunity.PendingEppConversionQuoteClosure__c);
    }

    @IsTest
    static void closeSelectedQuotesClosesOnlyTheChosenQuote() {
        stampRunningUserHrisId();
        Opportunity opportunityRecord = getTestOpportunity();
        Quote selectedQuote = insertQuote(opportunityRecord, 'EPP Selected Quote', 'Open');
        Quote otherQuote = insertQuote(opportunityRecord, 'EPP Unselected Quote', 'Open');
        selectedQuote.SalesConnectionQuoteID__c = '2283705';
        otherQuote.SalesConnectionQuoteID__c = '2283706';
        update new List<Quote>{ selectedQuote, otherQuote };
        ScOpportunityQuoteEventGateway.forceHardcodedResponse = true;

        Test.startTest();
        OppEppConversionQuoteService.closeSelectedQuotes(
            opportunityRecord.Id,
            new Set<Id>{ selectedQuote.Id }
        );
        Test.stopTest();

        ScOpportunityQuoteEventGateway.forceHardcodedResponse = false;

        Map<Id, Quote> quotesById = new Map<Id, Quote>([
            SELECT Status, ClosureDisposition__c, Forecast_Eligible__c
            FROM Quote
            WHERE Id IN :new Set<Id>{ selectedQuote.Id, otherQuote.Id }
        ]);
        System.assertEquals(QuoteSelector.CLOSED_STATUS_VALUE, quotesById.get(selectedQuote.Id).Status);
        System.assertEquals(
            OppEppConversionQuoteService.CONVERTED_TO_EPP_DISPOSITION,
            quotesById.get(selectedQuote.Id).ClosureDisposition__c
        );
        System.assertEquals(false, quotesById.get(selectedQuote.Id).Forecast_Eligible__c);
        System.assertNotEquals(QuoteSelector.CLOSED_STATUS_VALUE, quotesById.get(otherQuote.Id).Status);
        System.assertEquals(null, quotesById.get(otherQuote.Id).ClosureDisposition__c);
    }

    @IsTest
    static void reviewQuotesListsAndClosesTheSelectedQuote() {
        stampRunningUserHrisId();
        Opportunity opportunityRecord = getTestOpportunity();
        Quote selectedQuote = insertQuote(opportunityRecord, 'EPP Action Selected Quote', 'Open');
        Quote otherQuote = insertQuote(opportunityRecord, 'EPP Action Unselected Quote', 'Open');
        selectedQuote.SalesConnectionQuoteID__c = '2283707';
        otherQuote.SalesConnectionQuoteID__c = '2283708';
        update new List<Quote>{ selectedQuote, otherQuote };
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

        Test.startTest();
        System.assertEquals(0, OppEppConversionQuoteSelectionAction.reviewQuotes(null).size());
        List<OppEppConversionQuoteSelectionAction.Response> listed =
            OppEppConversionQuoteSelectionAction.reviewQuotes(
                new List<OppEppConversionQuoteSelectionAction.Request>{ null, listRequest }
            );
        OppEppConversionQuoteSelectionAction.reviewQuotes(
            new List<OppEppConversionQuoteSelectionAction.Request>{ closeRequest }
        );
        OppEppConversionQuoteService.closeSelectedQuotes(null, null);
        OppEppConversionQuoteService.closeSelectedQuotes(opportunityRecord.Id, new Set<Id>());
        OppEppConversionQuoteService.closeSelectedQuotes(
            opportunityRecord.Id,
            new Set<Id>{ otherQuote.Id }
        );
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

        System.assertEquals(2, listed[1].openQuotes.size());
        System.assertEquals(
            false,
            [SELECT PendingEppConversionQuoteClosure__c FROM Opportunity WHERE Id = :opportunityRecord.Id]
                .PendingEppConversionQuoteClosure__c
        );
    }

    private static void stampRunningUserHrisId() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(
                Id = UserInfo.getUserId(),
                EmployeeNumber__c = '3430001'
            );
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
        return new Opportunity(
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
    }

    private static Quote insertQuote(Opportunity opportunityRecord, String quoteName, String statusValue) {
        Quote quoteRecord = new Quote(
            Name = quoteName,
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            Status = resolveQuoteStatus(statusValue)
        );
        insert quoteRecord;
        return quoteRecord;
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