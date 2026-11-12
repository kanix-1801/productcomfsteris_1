/**
 * @description GW-5892: Tests for FieldServiceQuoteService, FieldServiceQuoteCreateAction and the
 *              Quote_AfterSave_SyncFieldServiceOpportunity flow.
 * @see FieldServiceQuoteService
 * @see FieldServiceQuoteCreateAction
 */
@IsTest
private class FieldServiceQuoteServiceTest {
    @IsTest
    static void createFromWorkOrder_createsHeaderOpportunityAndPartLines() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();

        Test.startTest();
        FieldServiceQuoteService.CreateResult result = FieldServiceQuoteService.createFromWorkOrder(
            scenario.workOrder.Id
        );
        Test.stopTest();

        Quote quoteRecord = [
            SELECT Name, Status, PricingStatus__c, WorkOrder__c, QuoteAccountId, RateList__c, Pricebook2Id,
                CurrencyIsoCode, OwnerId, RecordType.DeveloperName, OpportunityId, AccountId, ExpirationDate
            FROM Quote
            WHERE Id = :result.quoteId
        ];
        WorkOrder workOrder = [SELECT WorkOrderNumber FROM WorkOrder WHERE Id = :scenario.workOrder.Id];
        System.assertEquals(FieldServiceQuoteService.QUOTE_RECORD_TYPE, quoteRecord.RecordType.DeveloperName);
        System.assertEquals(workOrder.WorkOrderNumber + ' - GW5892 Customer', quoteRecord.Name);
        System.assertEquals(FieldServiceQuoteService.STATUS_DRAFT, quoteRecord.Status);
        System.assertEquals(FieldServiceQuoteService.PRICING_NOT_PRICED, quoteRecord.PricingStatus__c);
        System.assertEquals(scenario.workOrder.Id, quoteRecord.WorkOrder__c);
        System.assertEquals(scenario.account.Id, quoteRecord.QuoteAccountId);
        System.assertEquals(scenario.rateList.Id, quoteRecord.RateList__c);
        System.assertEquals(Test.getStandardPricebookId(), quoteRecord.Pricebook2Id);
        System.assertEquals(UserInfo.getUserId(), quoteRecord.OwnerId);
        System.assertEquals(scenario.account.Id, quoteRecord.AccountId, 'Account comes from the opportunity');

        Opportunity opportunityRecord = [
            SELECT RecordType.DeveloperName, StageName, WorkOrder__c, AccountId, OwnerId, CloseDate
            FROM Opportunity
            WHERE Id = :quoteRecord.OpportunityId
        ];
        System.assertEquals(FieldServiceQuoteService.OPPORTUNITY_RECORD_TYPE, opportunityRecord.RecordType.DeveloperName);
        System.assertEquals(FieldServiceQuoteService.STAGE_OPEN, opportunityRecord.StageName);
        System.assertEquals(scenario.workOrder.Id, opportunityRecord.WorkOrder__c);
        System.assertEquals(scenario.account.Id, opportunityRecord.AccountId);
        System.assertEquals(quoteRecord.ExpirationDate, opportunityRecord.CloseDate);

        List<QuoteLineItem> lines = [
            SELECT LineType__c, Product2Id, Quantity, UnitPrice, WorkOrder__c
            FROM QuoteLineItem
            WHERE QuoteId = :result.quoteId
        ];
        System.assertEquals(1, lines.size(), 'Only the priced Product Required becomes a line');
        System.assertEquals(FieldServiceQuoteService.LINE_TYPE_PARTS, lines[0].LineType__c);
        System.assertEquals(scenario.part.Id, lines[0].Product2Id);
        System.assertEquals(2, lines[0].Quantity);
        System.assertEquals(FieldServiceQuoteTestData.PART_PRICE, lines[0].UnitPrice);
        System.assertEquals(scenario.workOrder.Id, lines[0].WorkOrder__c);
        System.assertEquals(
            new List<String>{ FieldServiceQuoteTestData.UNPRICED_PART_CODE },
            result.skippedProductCodes
        );
    }

    @IsTest
    static void createFromWorkOrder_secondQuote_reusesWorkOrderOpportunity() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();

        Test.startTest();
        Id firstQuoteId = FieldServiceQuoteService.createFromWorkOrder(scenario.workOrder.Id).quoteId;
        Id secondQuoteId = FieldServiceQuoteService.createFromWorkOrder(scenario.workOrder.Id).quoteId;
        Test.stopTest();

        Map<Id, Quote> quotes = new Map<Id, Quote>(
            [SELECT OpportunityId FROM Quote WHERE Id IN :new Set<Id>{ firstQuoteId, secondQuoteId }]
        );
        System.assertEquals(quotes.get(firstQuoteId).OpportunityId, quotes.get(secondQuoteId).OpportunityId);
        System.assertEquals(1, [SELECT COUNT() FROM Opportunity WHERE WorkOrder__c = :scenario.workOrder.Id]);
    }

    @IsTest
    static void createFromWorkOrder_withoutPricebook_throwsAndCreatesNothing() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
        update new WorkOrder(Id = scenario.workOrder.Id, Pricebook2Id = null);

        Test.startTest();
        String message;
        try {
            FieldServiceQuoteService.createFromWorkOrder(scenario.workOrder.Id);
        } catch (FieldServiceQuoteService.FieldServiceQuoteException ex) {
            message = ex.getMessage();
        }
        Test.stopTest();

        System.assert(message != null && message.contains('Price Book'), message);
        System.assertEquals(0, [SELECT COUNT() FROM Quote WHERE WorkOrder__c = :scenario.workOrder.Id]);
    }

    @IsTest
    static void createQuotesAction_returnsQuoteIdAndWarning() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
        FieldServiceQuoteCreateAction.Request request = new FieldServiceQuoteCreateAction.Request();
        request.workOrderId = scenario.workOrder.Id;

        Test.startTest();
        FieldServiceQuoteCreateAction.Result result = FieldServiceQuoteCreateAction.createQuotes(
            new List<FieldServiceQuoteCreateAction.Request>{ request }
        )[0];
        Test.stopTest();

        System.assert(result.isSuccess);
        System.assertNotEquals(null, result.quoteId);
        System.assert(result.hasWarnings);
        System.assert(result.message.contains(FieldServiceQuoteTestData.UNPRICED_PART_CODE), result.message);
    }

    @IsTest
    static void createQuotesAction_missingWorkOrder_returnsError() {
        FieldServiceQuoteCreateAction.Request request = new FieldServiceQuoteCreateAction.Request();

        Test.startTest();
        FieldServiceQuoteCreateAction.Result result = FieldServiceQuoteCreateAction.createQuotes(
            new List<FieldServiceQuoteCreateAction.Request>{ request }
        )[0];
        Test.stopTest();

        System.assert(!result.isSuccess);
        System.assertEquals(null, result.quoteId);
        System.assert(String.isNotBlank(result.message));
    }

    @IsTest
    static void ensureOpportunity_quoteWithoutOpportunity_createsOne() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
        Quote quoteRecord = FieldServiceQuoteService.buildQuoteHeader(
            [
                SELECT Id, WorkOrderNumber, AccountId, Account.Name, Account.RateList__c, Account.CustomerClassCode__c,
                    ContactId, AssetId, Asset.Name, ShipTo__c, ShipToAddressAccount__c, BillToAddressAccount__c,
                    CurrencyIsoCode, Pricebook2Id, RateList__c, RegionalControl__c,
                    Street, City, StateCode, PostalCode, Country, CountryCode
                FROM WorkOrder
                WHERE Id = :scenario.workOrder.Id
            ]
        );
        insert quoteRecord;

        Test.startTest();
        FieldServiceQuoteService.ensureOpportunity(quoteRecord.Id);
        Test.stopTest();

        Quote refreshed = [SELECT OpportunityId, Opportunity.WorkOrder__c FROM Quote WHERE Id = :quoteRecord.Id];
        System.assertNotEquals(null, refreshed.OpportunityId);
        System.assertEquals(scenario.workOrder.Id, refreshed.Opportunity.WorkOrder__c);
    }

    @IsTest
    static void quoteStatusAccepted_closesOpportunityWon() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
        Id quoteId = FieldServiceQuoteService.createFromWorkOrder(scenario.workOrder.Id).quoteId;

        Test.startTest();
        update new Quote(Id = quoteId, Status = 'Accepted');
        Test.stopTest();

        Opportunity opportunityRecord = [
            SELECT StageName
            FROM Opportunity
            WHERE Id IN (SELECT OpportunityId FROM Quote WHERE Id = :quoteId)
        ];
        System.assertEquals('Closed Won', opportunityRecord.StageName);
    }

    @IsTest
    static void quoteStatusDenied_closesOpportunityLost() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
        Id quoteId = FieldServiceQuoteService.createFromWorkOrder(scenario.workOrder.Id).quoteId;

        Test.startTest();
        update new Quote(Id = quoteId, Status = 'Denied');
        Test.stopTest();

        Opportunity opportunityRecord = [
            SELECT StageName
            FROM Opportunity
            WHERE Id IN (SELECT OpportunityId FROM Quote WHERE Id = :quoteId)
        ];
        System.assertEquals('Closed Lost', opportunityRecord.StageName);
    }

    @IsTest
    static void quoteOwnerChange_syncsOpportunityOwner() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
        Id quoteId = FieldServiceQuoteService.createFromWorkOrder(scenario.workOrder.Id).quoteId;
        User newOwner = new User(
            ProfileId = UserInfo.getProfileId(),
            LastName = 'GW5892 Owner',
            Alias = 'gw5892',
            Email = 'gw5892.owner@example.com',
            Username = 'gw5892.owner.' + String.valueOf(Crypto.getRandomInteger()) + '@example.com',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert newOwner;
        }

        Test.startTest();
        update new Quote(Id = quoteId, OwnerId = newOwner.Id);
        Test.stopTest();

        Opportunity opportunityRecord = [
            SELECT OwnerId
            FROM Opportunity
            WHERE Id IN (SELECT OpportunityId FROM Quote WHERE Id = :quoteId)
        ];
        System.assertEquals(newOwner.Id, opportunityRecord.OwnerId);
    }
}