/**
 * @description GW-5892: Shared test data for Field Service Quote tests.
 * @group Field Service Quote
 */
@IsTest
public class FieldServiceQuoteTestData {
	public static final String CURRENCY_CODE = 'USD';
	public static final String PART_CODE = 'GW5892-PART-1';
	public static final String UNPRICED_PART_CODE = 'GW5892-PART-NOPRICE';
	public static final Decimal PART_PRICE = 125;
	public static final String STATUS_DRAFT = 'Draft';
	public static final String PRICING_NOT_PRICED = 'Not Priced';
	public static final String LABOR_CODE = FieldServiceQuoteService.LABOR_PRODUCT_CODE;
	public static final String TRAVEL_CODE = FieldServiceQuoteService.TRAVEL_PRODUCT_CODE;
	public static final String EXPENSE_CODE = FieldServiceQuoteService.EXPENSE_PRODUCT_CODE;
	public static final Id QUOTE_RECORD_TYPE_ID = Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName()
		.get('Field_Service')
		.getRecordTypeId();

	/**
	 * @description Created records for a scenario.
	 */
	public class Scenario {
		public Account account;
		public RateList__c rateList;
		public WorkOrder workOrder;
		public Product2 part;
		public Product2 unpricedPart;
		public Map<String, Product2> productByCode = new Map<String, Product2>();
	}

	/**
	 * @description Account, Rate List, Work Order on the standard price book and products (part, labor, travel,
	 *              expense priced; one part without a price).
	 * @return Scenario
	 */
	public static Scenario createScenario() {
		Scenario scenario = new Scenario();
		scenario.rateList = new RateList__c(
			Name = 'GW5892 Rate List',
			LaborHour__c = 150,
			TravelHour__c = 100,
			PremiumRateHour__c = 200,
			TravelZone1__c = 95
		);
		insert scenario.rateList;

		scenario.account = new Account(
			Name = 'GW5892 Customer',
			SourceSystemID__c = 'ORACLE-GW5892-' + String.valueOf(Crypto.getRandomInteger()),
			RateList__c = scenario.rateList.Id
		);
		insert scenario.account;

		List<Product2> products = new List<Product2>{
			new Product2(Name = 'GW5892 Gasket', ProductCode = PART_CODE, IsActive = true),
			new Product2(Name = 'GW5892 Unpriced', ProductCode = UNPRICED_PART_CODE, IsActive = true),
			new Product2(Name = 'FS Labor', ProductCode = LABOR_CODE, IsActive = true),
			new Product2(Name = 'FS Travel', ProductCode = TRAVEL_CODE, IsActive = true),
			new Product2(Name = 'FS Expense', ProductCode = EXPENSE_CODE, IsActive = true)
		};
		insert products;
		for (Product2 product : products) {
			scenario.productByCode.put(product.ProductCode, product);
		}
		scenario.part = scenario.productByCode.get(PART_CODE);
		scenario.unpricedPart = scenario.productByCode.get(UNPRICED_PART_CODE);

		Id pricebookId = Test.getStandardPricebookId();
		List<PricebookEntry> entries = new List<PricebookEntry>();
		for (Product2 product : products) {
			if (product.Id == scenario.unpricedPart.Id) {
				continue;
			}
			entries.add(
				new PricebookEntry(
					Pricebook2Id = pricebookId,
					Product2Id = product.Id,
					UnitPrice = product.Id == scenario.part.Id ? PART_PRICE : 0,
					CurrencyIsoCode = CURRENCY_CODE,
					IsActive = true
				)
			);
		}
		insert entries;

		scenario.workOrder = new WorkOrder(
			AccountId = scenario.account.Id,
			Subject = 'GW5892 Field Service Quote WO',
			Pricebook2Id = pricebookId,
			CurrencyIsoCode = CURRENCY_CODE,
			RateList__c = scenario.rateList.Id
		);
		insert scenario.workOrder;
		return scenario;
	}

	/**
	 * @description Field Service quote on the scenario Work Order (as the mobile Create Quote flow builds it),
	 *              with its Field Service opportunity and one Parts line (part x2 at PART_PRICE).
	 * @param scenario Scenario from createScenario
	 * @return Quote Id
	 */
	public static Id createQuote(Scenario scenario) {
		Id pricebookId = Test.getStandardPricebookId();
		Quote quoteRecord = new Quote(
			RecordTypeId = QUOTE_RECORD_TYPE_ID,
			Name = 'GW5892 Quote',
			Status = STATUS_DRAFT,
			PricingStatus__c = PRICING_NOT_PRICED,
			QuoteAccountId = scenario.account.Id,
			WorkOrder__c = scenario.workOrder.Id,
			Pricebook2Id = pricebookId,
			CurrencyIsoCode = CURRENCY_CODE,
			RateList__c = scenario.rateList.Id,
			ExpirationDate = Date.today().addDays(FieldServiceQuoteService.QUOTE_VALIDITY_DAYS)
		);
		insert quoteRecord;
		FieldServiceQuoteService.ensureOpportunity(quoteRecord.Id);

		PricebookEntry entry = [
			SELECT Id, UnitPrice
			FROM PricebookEntry
			WHERE Product2Id = :scenario.part.Id AND Pricebook2Id = :pricebookId AND CurrencyIsoCode = :CURRENCY_CODE
		];
		insert new QuoteLineItem(
			QuoteId = quoteRecord.Id,
			PricebookEntryId = entry.Id,
			Product2Id = scenario.part.Id,
			Quantity = 2,
			UnitPrice = entry.UnitPrice,
			LineType__c = FieldServiceQuoteService.LINE_TYPE_PARTS,
			WorkOrder__c = scenario.workOrder.Id
		);
		return quoteRecord.Id;
	}
}