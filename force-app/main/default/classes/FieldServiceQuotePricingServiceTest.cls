/**
 * @description GW-5890: Covers the mobile pricing result without starting the Oracle flow.
 *              Quotes come from FieldServiceQuoteTestData (Field Service quote and opportunity), so the test does
 *              not depend on Healthcare Sales opportunity validation rules.
 */
@IsTest
private class FieldServiceQuotePricingServiceTest {
	@IsTest
	static void calculatePricingRequiresAQuote() {
		AuraHandledException thrown;
		try {
			FieldServiceQuotePricingService.calculatePricing(null);
		} catch (AuraHandledException ex) {
			thrown = ex;
		}
		System.assertNotEquals(null, thrown, 'A missing quote should be rejected.');
		System.assert(thrown.getMessage().contains('quote'), thrown.getMessage());
	}

	@IsTest
	static void calculatePricingReturnsTheQuoteMessage() {
		Quote quoteRecord = insertQuote('Pricing Error', 'Account Org ID is required for Oracle pricing.');

		Test.startTest();
		FieldServiceQuotePricingService.PricingResult result = FieldServiceQuotePricingService.calculatePricing(quoteRecord.Id);
		Test.stopTest();

		System.assertEquals('Pricing Error', result.status);
		System.assertEquals('Account Org ID is required for Oracle pricing.', result.message);
	}

	@IsTest
	static void calculatePricingPrefersTheFlowFault() {
		Quote quoteRecord = insertQuote(null, null);
		FieldServiceQuotePricingService.testFlowMessage = 'Ship-to account 1001 has no Oracle org id.';

		Test.startTest();
		FieldServiceQuotePricingService.PricingResult result = FieldServiceQuotePricingService.calculatePricing(quoteRecord.Id);
		Test.stopTest();

		System.assertEquals('Ship-to account 1001 has no Oracle org id.', result.message);
	}

	@IsTest
	static void calculatePricingReportsSuccessWhenTheQuoteIsPriced() {
		Quote quoteRecord = insertQuote('Priced', null);

		Test.startTest();
		FieldServiceQuotePricingService.PricingResult result = FieldServiceQuotePricingService.calculatePricing(quoteRecord.Id);
		Test.stopTest();

		System.assertEquals('Priced', result.status);
		System.assertEquals('Pricing calculated.', result.message);
	}

	@IsTest
	static void calculatePricingReportsAMissingQuote() {
		Quote quoteRecord = insertQuote(null, null);
		delete quoteRecord;

		AuraHandledException thrown;
		Test.startTest();
		try {
			FieldServiceQuotePricingService.calculatePricing(quoteRecord.Id);
		} catch (AuraHandledException ex) {
			thrown = ex;
		}
		Test.stopTest();

		System.assertNotEquals(null, thrown, 'A deleted quote should be reported.');
		System.assert(thrown.getMessage().contains('not found'), thrown.getMessage());
	}

	@IsTest
	static void calculatePricingReportsFailureWhenNothingWasPriced() {
		Quote quoteRecord = insertQuote(null, null);
		FieldServiceQuotePricingService.testFlowMessage = '   ';

		Test.startTest();
		FieldServiceQuotePricingService.PricingResult result = FieldServiceQuotePricingService.calculatePricing(quoteRecord.Id);
		Test.stopTest();

		System.assertEquals('Pricing could not be completed.', result.message);
	}

	private static Quote insertQuote(String pricingStatus, String pricingMessage) {
		Quote quoteRecord = new Quote(
			Id = FieldServiceQuoteTestData.createQuote(FieldServiceQuoteTestData.createScenario()),
			PricingStatus__c = pricingStatus,
			PricingMessage__c = pricingMessage
		);
		update quoteRecord;
		return quoteRecord;
	}
}