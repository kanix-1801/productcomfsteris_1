/**
 * @description Covers QuoteSelector queries that deploy with the overhaul builder constructor.
 */
@IsTest
private class CoverageForQuoteSelectorTest {
	@IsTest
	static void selectorQueries_whenOpportunityAndQuoteExist_execute() {
		Opportunity opportunityRecord = insertOpportunity();
		Id trialId = fakeId(Trial__c.SObjectType);
		Id sampleId = fakeId(Sample__c.SObjectType);
		Quote quoteRecord = insertQuote(opportunityRecord);
		Set<Id> opportunityIds = new Set<Id>{ opportunityRecord.Id };
		Set<Id> quoteIds = new Set<Id>{ quoteRecord.Id };

		Test.startTest();
		QuoteSelector selector = new QuoteSelector();
		Integer nullCount = QuoteSelector.countByOpportunityId(null);
		Integer opportunityCount = QuoteSelector.countByOpportunityId(
			opportunityRecord.Id
		);
		Integer normalTypeCount = QuoteSelector.countByOpportunityId(
			opportunityRecord.Id,
			GenerateQuoteService.QUOTE_TYPE_NORMAL
		);
		Integer forecastEligibleCount = QuoteSelector.countByOpportunityId(
			opportunityRecord.Id,
			null,
			true
		);
		Integer trialTypeCount = QuoteSelector.countByOpportunityId(
			opportunityRecord.Id,
			GenerateQuoteService.QUOTE_TYPE_TRIAL,
			true,
			trialId
		);
		Integer trialForecastCount = QuoteSelector.countByOpportunityId(
			opportunityRecord.Id,
			null,
			true,
			trialId
		);
		Integer trialCount = QuoteSelector.countByOpportunityId(
			opportunityRecord.Id,
			null,
			false,
			trialId
		);
		Integer sampleTypeCount = QuoteSelector.countByOpportunityId(
			opportunityRecord.Id,
			GenerateQuoteService.QUOTE_TYPE_SAMPLE,
			true,
			null,
			sampleId
		);
		Integer sampleForecastCount = QuoteSelector.countByOpportunityId(
			opportunityRecord.Id,
			null,
			true,
			null,
			sampleId
		);
		Integer sampleCount = QuoteSelector.countByOpportunityId(
			opportunityRecord.Id,
			null,
			false,
			null,
			sampleId
		);

		List<Quote> nullQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
			null
		);
		List<Quote> opportunityQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
			opportunityRecord.Id
		);
		List<Quote> normalTypeQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
			opportunityRecord.Id,
			GenerateQuoteService.QUOTE_TYPE_NORMAL
		);
		List<Quote> forecastEligibleQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
			opportunityRecord.Id,
			null,
			true
		);
		List<Quote> trialTypeQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
			opportunityRecord.Id,
			GenerateQuoteService.QUOTE_TYPE_TRIAL,
			true,
			trialId
		);
		List<Quote> trialForecastQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
			opportunityRecord.Id,
			null,
			true,
			trialId
		);
		List<Quote> trialQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
			opportunityRecord.Id,
			null,
			false,
			trialId
		);
		List<Quote> sampleTypeQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
			opportunityRecord.Id,
			GenerateQuoteService.QUOTE_TYPE_SAMPLE,
			true,
			null,
			sampleId
		);
		List<Quote> sampleForecastQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
			opportunityRecord.Id,
			null,
			true,
			null,
			sampleId
		);
		List<Quote> sampleQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
			opportunityRecord.Id,
			null,
			false,
			null,
			sampleId
		);

		Quote selectedQuote = QuoteSelector.selectById(quoteRecord.Id);
		List<Quote> selectedQuotes = QuoteSelector.selectByIdsWithLineItems(
			quoteIds
		);
		List<Quote> openForecastQuotes = QuoteSelector.selectOpenForecastEligibleQuotesByOpportunityIds(
			opportunityIds
		);
		Set<Id> forecastOpportunityIds = QuoteSelector.selectOpportunityIdsWithOpenForecastEligibleQuotes(
			opportunityIds
		);
		List<Quote> forecastManagementQuotes = QuoteSelector.selectForecastManagementQuotesByOpportunityId(
			opportunityRecord.Id
		);
		List<Quote> salesConnectionQuotes = QuoteSelector.selectSalesConnectionQuotesForForecastEligibleByOpportunityIds(
			opportunityIds
		);
		Map<Id, Integer> propagatableCounts = QuoteSelector.countPropagatableForecastConfidenceQuotesByOpportunityIds(
			opportunityIds
		);
		List<Quote> propagatableQuotes = QuoteSelector.selectPropagatableForecastConfidenceQuotesByOpportunityId(
			opportunityRecord.Id
		);
		List<Quote> openSalesConnectionQuotes = QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(
			opportunityRecord.Id
		);
		Map<Id, Integer> openSalesConnectionCounts = QuoteSelector.countOpenSalesConnectionQuotesByOpportunityIds(
			opportunityIds
		);
		Test.stopTest();

		Assert.isNotNull(
			selector,
			'The overhaul builder constructor should be callable'
		);
		Assert.areEqual(0, nullCount);
		Assert.isTrue(
			opportunityCount >= 1,
			'The inserted quote should be counted'
		);
		Assert.areEqual(
			0,
			normalTypeCount,
			'The quote is a Trial Quote, not a Normal Quote'
		);
		Assert.isTrue(
			forecastEligibleCount >= 1,
			'A quote that is not marked forecast ineligible should be counted'
		);
		Assert.areEqual(0, trialTypeCount);
		Assert.areEqual(0, trialForecastCount);
		Assert.areEqual(0, trialCount);
		Assert.areEqual(0, sampleTypeCount);
		Assert.areEqual(0, sampleForecastCount);
		Assert.areEqual(0, sampleCount);
		Assert.isTrue(nullQuotes.isEmpty());
		Assert.isFalse(
			opportunityQuotes.isEmpty(),
			'The inserted quote should be returned'
		);
		Assert.areEqual(quoteRecord.Id, opportunityQuotes[0].Id);
		Assert.isTrue(normalTypeQuotes.isEmpty());
		Assert.areEqual(quoteRecord.Id, forecastEligibleQuotes[0].Id);
		Assert.isTrue(trialTypeQuotes.isEmpty());
		Assert.isTrue(trialForecastQuotes.isEmpty());
		Assert.isTrue(trialQuotes.isEmpty());
		Assert.isTrue(sampleTypeQuotes.isEmpty());
		Assert.isTrue(sampleForecastQuotes.isEmpty());
		Assert.isTrue(sampleQuotes.isEmpty());
		Assert.areEqual(quoteRecord.Id, selectedQuote.Id);
		Assert.areEqual(quoteRecord.Id, selectedQuotes[0].Id);
		Assert.isTrue(QuoteSelector.selectByIdsWithLineItems(null).isEmpty());
		Assert.isTrue(
			QuoteSelector.selectByIdsWithLineItems(new Set<Id>()).isEmpty()
		);
		Assert.isTrue(
			openForecastQuotes.isEmpty(),
			'A quote that is not forecast eligible should be excluded'
		);
		Assert.isTrue(
			QuoteSelector.selectOpenForecastEligibleQuotesByOpportunityIds(null)
				.isEmpty()
		);
		Assert.isTrue(forecastOpportunityIds.isEmpty());
		Assert.isTrue(
			QuoteSelector.selectOpportunityIdsWithOpenForecastEligibleQuotes(
					new Set<Id>()
				)
				.isEmpty()
		);
		Assert.isTrue(
			forecastManagementQuotes.isEmpty(),
			'Draft quotes are outside forecast management'
		);
		Assert.isTrue(
			QuoteSelector.selectForecastManagementQuotesByOpportunityId(null)
				.isEmpty()
		);
		Assert.areEqual(quoteRecord.Id, salesConnectionQuotes[0].Id);
		Assert.isTrue(
			QuoteSelector.selectSalesConnectionQuotesForForecastEligibleByOpportunityIds(
					null
				)
				.isEmpty()
		);
		Assert.isNull(
			propagatableCounts.get(opportunityRecord.Id),
			'Without Opportunity forecast confidence, no quotes are propagatable'
		);
		Assert.isTrue(
			propagatableQuotes.isEmpty(),
			'Without Opportunity forecast confidence, no quotes are propagatable'
		);
		Assert.isTrue(
			QuoteSelector.countPropagatableForecastConfidenceQuotesByOpportunityIds(
					null
				)
				.isEmpty()
		);
		Assert.isTrue(
			QuoteSelector.selectPropagatableForecastConfidenceQuotesByOpportunityId(
					null
				)
				.isEmpty()
		);
		Assert.areEqual(quoteRecord.Id, openSalesConnectionQuotes[0].Id);
		Assert.isTrue(
			QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(null)
				.isEmpty()
		);
		Assert.areEqual(1, openSalesConnectionCounts.get(opportunityRecord.Id));
		Assert.isTrue(
			QuoteSelector.countOpenSalesConnectionQuotesByOpportunityIds(
					new Set<Id>()
				)
				.isEmpty()
		);
		Assert.isNull(QuoteSelector.selectById(null));
	}

	@IsTest
	static void countPropagatable_whenOpportunityConfidenceDiffers_returnsQuote() {
		Opportunity opportunityRecord = insertOpportunity();
		String opportunityForecastConfidence = mappableOpportunityForecastConfidence();
		Assert.isNotNull(
			opportunityForecastConfidence,
			'A mappable Opportunity ForecastConfidenceLevel__c value is required'
		);
		opportunityRecord.ForecastConfidenceLevel__c = opportunityForecastConfidence;
		opportunityRecord.BypassValidations__c = true;
		update opportunityRecord;

		Quote quoteRecord = insertForecastEligiblePropagatableQuote(opportunityRecord);

		Test.startTest();
		Map<Id, Integer> propagatableCounts = QuoteSelector.countPropagatableForecastConfidenceQuotesByOpportunityIds(
			new Set<Id>{ opportunityRecord.Id }
		);
		List<Quote> propagatableQuotes = QuoteSelector.selectPropagatableForecastConfidenceQuotesByOpportunityId(
			opportunityRecord.Id
		);
		Test.stopTest();

		Assert.areEqual(1, propagatableCounts.get(opportunityRecord.Id));
		Assert.areEqual(quoteRecord.Id, propagatableQuotes[0].Id);
	}

	private static String mappableOpportunityForecastConfidence() {
		for (
			Schema.PicklistEntry picklistEntry : Opportunity.ForecastConfidenceLevel__c.getDescribe()
				.getPicklistValues()
		) {
			if (!picklistEntry.isActive()) {
				continue;
			}
			if (
				String.isNotBlank(
					QuoteService.mapOpportunityForecastConfidenceToQuote(picklistEntry.getValue())
				)
			) {
				return picklistEntry.getValue();
			}
		}
		return null;
	}

	private static Quote insertForecastEligiblePropagatableQuote(Opportunity opportunityRecord) {
		Schema.RecordTypeInfo quoteRecordType = Schema.SObjectType.Quote
			.getRecordTypeInfosByDeveloperName()
			.get(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME);
		Assert.isNotNull(
			quoteRecordType,
			'HC Sales quote record type is required'
		);

		Quote quoteRecord = new Quote(
			Name = 'Quote Selector Propagatable Quote',
			OpportunityId = opportunityRecord.Id,
			Pricebook2Id = opportunityRecord.Pricebook2Id,
			RecordTypeId = quoteRecordType.getRecordTypeId(),
			Status = 'Draft',
			QuoteType__c = GenerateQuoteService.QUOTE_TYPE_NORMAL,
			Forecast_Eligible__c = true,
			QuoteForecastConfidence__c = null,
			Quote_Total_Without_Freight__c = 1000,
			ExpirationDate = Date.today().addDays(30)
		);

		TriggerHandler.bypass('QuoteTriggerHandler');
		try {
			insert quoteRecord;
		} finally {
			TriggerHandler.clearBypass('QuoteTriggerHandler');
		}
		return quoteRecord;
	}

	private static Opportunity insertOpportunity() {
		Account accountRecord = new Account(
			Name = 'Quote Selector Coverage Account'
		);
		insert accountRecord;
		Contact contactRecord = new Contact(
			FirstName = 'Quote',
			LastName = 'Selector',
			AccountId = accountRecord.Id
		);
		insert contactRecord;

		Schema.RecordTypeInfo opportunityRecordType = Schema.SObjectType.Opportunity
			.getRecordTypeInfosByDeveloperName()
			.get('Healthcare_Sales');
		Assert.isNotNull(
			opportunityRecordType,
			'HC Sales opportunity record type is required'
		);
		Assert.isTrue(
			opportunityRecordType.isAvailable(),
			'HC Sales opportunity record type is required'
		);

		Opportunity opportunityRecord = new Opportunity(
			Name = 'Quote Selector Coverage Opportunity',
			AccountId = accountRecord.Id,
			RecordTypeId = opportunityRecordType.getRecordTypeId(),
			StageName = 'Discovery',
			Type = 'New Business',
			CloseDate = Date.today().addDays(30),
			Amount = 1000,
			Probability = 10,
			PrimaryContact__c = contactRecord.Id,
			Pricebook2Id = Test.getStandardPricebookId()
		);
		insert opportunityRecord;
		return opportunityRecord;
	}

	private static Quote insertQuote(Opportunity opportunityRecord) {
		Schema.RecordTypeInfo quoteRecordType = Schema.SObjectType.Quote
			.getRecordTypeInfosByDeveloperName()
			.get(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME);
		Assert.isNotNull(
			quoteRecordType,
			'HC Sales quote record type is required'
		);

		Quote quoteRecord = new Quote(
			Name = 'Quote Selector Coverage Quote',
			OpportunityId = opportunityRecord.Id,
			Pricebook2Id = opportunityRecord.Pricebook2Id,
			RecordTypeId = quoteRecordType.getRecordTypeId(),
			Status = 'Draft',
			QuoteType__c = GenerateQuoteService.QUOTE_TYPE_TRIAL,
			Forecast_Eligible__c = false,
			Quote_Total_Without_Freight__c = 1000,
			ExpirationDate = Date.today().addDays(30)
		);
		insert quoteRecord;
		return quoteRecord;
	}

	private static Id fakeId(Schema.SObjectType sobjectType) {
		return (Id) (sobjectType.getDescribe().getKeyPrefix() + '000000000001');
	}
}