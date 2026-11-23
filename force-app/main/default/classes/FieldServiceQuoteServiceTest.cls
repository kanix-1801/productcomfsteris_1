/**
 * @description GW-5892: Tests for FieldServiceQuoteService and the Quote_AfterSave_SyncFieldServiceOpportunity flow.
 * @see FieldServiceQuoteService
 */
@IsTest
private class FieldServiceQuoteServiceTest {
	private static Opportunity opportunityOf(Id quoteId) {
		return [
			SELECT Id, RecordType.DeveloperName, StageName, WorkOrder__c, AccountId, OwnerId, CloseDate
			FROM Opportunity
			WHERE Id IN (SELECT OpportunityId FROM Quote WHERE Id = :quoteId)
		];
	}

	@IsTest
	static void ensureOpportunity_quoteWithoutOpportunity_createsWorkOrderOpportunity() {
		FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();

		Test.startTest();
		Id quoteId = FieldServiceQuoteTestData.createQuote(scenario);
		Test.stopTest();

		Quote quoteRecord = [SELECT AccountId, ExpirationDate FROM Quote WHERE Id = :quoteId];
		Opportunity opportunityRecord = opportunityOf(quoteId);
		System.assertEquals(FieldServiceQuoteService.OPPORTUNITY_RECORD_TYPE, opportunityRecord.RecordType.DeveloperName);
		System.assertEquals(FieldServiceQuoteService.STAGE_OPEN, opportunityRecord.StageName);
		System.assertEquals(scenario.workOrder.Id, opportunityRecord.WorkOrder__c);
		System.assertEquals(scenario.account.Id, opportunityRecord.AccountId);
		System.assertEquals(UserInfo.getUserId(), opportunityRecord.OwnerId);
		System.assertEquals(quoteRecord.ExpirationDate, opportunityRecord.CloseDate);
		System.assertEquals(scenario.account.Id, quoteRecord.AccountId, 'Account comes from the opportunity');
	}

	@IsTest
	static void ensureOpportunity_secondQuote_reusesWorkOrderOpportunity() {
		FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();

		Test.startTest();
		Id firstQuoteId = FieldServiceQuoteTestData.createQuote(scenario);
		Id secondQuoteId = FieldServiceQuoteTestData.createQuote(scenario);
		Test.stopTest();

		System.assertEquals(opportunityOf(firstQuoteId).Id, opportunityOf(secondQuoteId).Id);
		System.assertEquals(1, [SELECT COUNT() FROM Opportunity WHERE WorkOrder__c = :scenario.workOrder.Id]);
	}

	@IsTest
	static void ensureOpportunity_accountOnlyQuote_linkedToWorkOrderLater() {
		FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
		Quote quoteRecord = new Quote(
			RecordTypeId = FieldServiceQuoteTestData.QUOTE_RECORD_TYPE_ID,
			Name = 'GW5892 Account Quote',
			QuoteAccountId = scenario.account.Id,
			Pricebook2Id = Test.getStandardPricebookId(),
			CurrencyIsoCode = FieldServiceQuoteTestData.CURRENCY_CODE
		);
		insert quoteRecord;

		Test.startTest();
		FieldServiceQuoteService.ensureOpportunity(quoteRecord.Id);
		System.assertEquals(null, opportunityOf(quoteRecord.Id).WorkOrder__c, 'Account-only opportunity');
		update new Quote(Id = quoteRecord.Id, WorkOrder__c = scenario.workOrder.Id);
		FieldServiceQuoteService.ensureOpportunity(quoteRecord.Id);
		Test.stopTest();

		System.assertEquals(scenario.workOrder.Id, opportunityOf(quoteRecord.Id).WorkOrder__c);
	}

	@IsTest
	static void selectPricebookEntries_returnsOnlyPricedProducts() {
		FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();

		Test.startTest();
		Map<Id, PricebookEntry> entries = FieldServiceQuoteService.selectPricebookEntries(
			Test.getStandardPricebookId(),
			FieldServiceQuoteTestData.CURRENCY_CODE,
			new Set<Id>{ scenario.part.Id, scenario.unpricedPart.Id }
		);
		Map<Id, PricebookEntry> none = FieldServiceQuoteService.selectPricebookEntries(null, 'USD', new Set<Id>());
		Test.stopTest();

		System.assert(entries.containsKey(scenario.part.Id));
		System.assert(!entries.containsKey(scenario.unpricedPart.Id));
		System.assertEquals(FieldServiceQuoteTestData.PART_PRICE, entries.get(scenario.part.Id).UnitPrice);
		System.assert(none.isEmpty());
	}

	@IsTest
	static void quoteStatusAccepted_closesOpportunityWon() {
		FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
		Id quoteId = FieldServiceQuoteTestData.createQuote(scenario);

		Test.startTest();
		update new Quote(Id = quoteId, Status = 'Accepted');
		Test.stopTest();

		System.assertEquals('Closed Won', opportunityOf(quoteId).StageName);
	}

	@IsTest
	static void quoteStatusDenied_closesOpportunityLost() {
		FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
		Id quoteId = FieldServiceQuoteTestData.createQuote(scenario);

		Test.startTest();
		update new Quote(Id = quoteId, Status = 'Denied');
		Test.stopTest();

		System.assertEquals('Closed Lost', opportunityOf(quoteId).StageName);
	}

	@IsTest
	static void quoteOwnerChange_syncsOpportunityOwner() {
		FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
		Id quoteId = FieldServiceQuoteTestData.createQuote(scenario);
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

		System.assertEquals(newOwner.Id, opportunityOf(quoteId).OwnerId);
	}
}