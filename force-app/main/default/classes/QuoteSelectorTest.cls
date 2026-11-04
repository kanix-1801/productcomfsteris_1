/**
 * @description Tests for QuoteSelector: QACBM quote/forecast queries plus Sprint 9
 *              Repair Center methods (GW-3600 / GW-5102 / GW-5333).
 */
@IsTest
private class QuoteSelectorTest {
    @IsTest
    static void testConstructor_bindsQuoteObject() {
        Test.startTest();
        QuoteSelector selector = new QuoteSelector();
        Test.stopTest();
        Assert.isNotNull(selector);
    }

    @IsTest
    static void testSelectByOpportunityIdWithLineItems_WhenNull_ReturnsEmpty() {
        Test.startTest();
        List<Quote> base = QuoteSelector.selectByOpportunityIdWithLineItems(null);
        List<Quote> withType = QuoteSelector.selectByOpportunityIdWithLineItems(null, 'Sales');
        List<Quote> withForecast = QuoteSelector.selectByOpportunityIdWithLineItems(null, null, true);
        List<Quote> withTrial = QuoteSelector.selectByOpportunityIdWithLineItems(
            null,
            null,
            false,
            null
        );
        List<Quote> withSample = QuoteSelector.selectByOpportunityIdWithLineItems(
            null,
            null,
            false,
            null,
            null
        );
        Test.stopTest();
        Assert.isTrue(base.isEmpty());
        Assert.isTrue(withType.isEmpty());
        Assert.isTrue(withForecast.isEmpty());
        Assert.isTrue(withTrial.isEmpty());
        Assert.isTrue(withSample.isEmpty());
    }

    @IsTest
    static void testCountByOpportunityId_WhenNull_ReturnsZero() {
        Test.startTest();
        Integer base = QuoteSelector.countByOpportunityId(null);
        Integer withType = QuoteSelector.countByOpportunityId(null, 'Sales');
        Integer withForecast = QuoteSelector.countByOpportunityId(null, null, true);
        Integer withTrial = QuoteSelector.countByOpportunityId(null, null, false, null);
        Integer withSample = QuoteSelector.countByOpportunityId(null, null, false, null, null);
        Test.stopTest();
        Assert.areEqual(0, base);
        Assert.areEqual(0, withType);
        Assert.areEqual(0, withForecast);
        Assert.areEqual(0, withTrial);
        Assert.areEqual(0, withSample);
    }

    @IsTest
    static void testSelectByIdAndIds_WhenBlank_ReturnsEmpty() {
        Test.startTest();
        Quote byId = QuoteSelector.selectById(null);
        List<Quote> byIdsNull = QuoteSelector.selectByIdsWithLineItems(null);
        List<Quote> byIdsEmpty = QuoteSelector.selectByIdsWithLineItems(new Set<Id>());
        Test.stopTest();
        Assert.isNull(byId);
        Assert.isTrue(byIdsNull.isEmpty());
        Assert.isTrue(byIdsEmpty.isEmpty());
    }

    @IsTest
    static void testForecastAndSalesConnectionGuards_WhenBlank_ReturnEmpty() {
        Test.startTest();
        List<Quote> openForecast =
            QuoteSelector.selectOpenForecastEligibleQuotesByOpportunityIds(null);
        Set<Id> openForecastIds =
            QuoteSelector.selectOpportunityIdsWithOpenForecastEligibleQuotes(new Set<Id>());
        List<Quote> forecastMgmt =
            QuoteSelector.selectForecastManagementQuotesByOpportunityId(null);
        List<Quote> salesConnForecast =
            QuoteSelector.selectSalesConnectionQuotesForForecastEligibleByOpportunityIds(null);
        Map<Id, Integer> propagateCounts =
            QuoteSelector.countPropagatableForecastConfidenceQuotesByOpportunityIds(new Set<Id>());
        List<Quote> propagateQuotes =
            QuoteSelector.selectPropagatableForecastConfidenceQuotesByOpportunityId(null);
        List<Quote> openSales =
            QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(null);
        Map<Id, Integer> openSalesCounts =
            QuoteSelector.countOpenSalesConnectionQuotesByOpportunityIds(null);
        Test.stopTest();
        Assert.isTrue(openForecast.isEmpty());
        Assert.isTrue(openForecastIds.isEmpty());
        Assert.isTrue(forecastMgmt.isEmpty());
        Assert.isTrue(salesConnForecast.isEmpty());
        Assert.isTrue(propagateCounts.isEmpty());
        Assert.isTrue(propagateQuotes.isEmpty());
        Assert.isTrue(openSales.isEmpty());
        Assert.isTrue(openSalesCounts.isEmpty());
    }

    @IsTest
    static void testSelectForQuoteEmailReplyById_WhenNull_ReturnsNull() {
        Test.startTest();
        Quote result = QuoteSelector.selectForQuoteEmailReplyById(null);
        Test.stopTest();
        Assert.isNull(result);
    }

    @IsTest
    static void testSelectForApproveRejectById_WhenNull_ReturnsNull() {
        Test.startTest();
        Quote result = QuoteSelector.selectForApproveRejectById(null);
        Test.stopTest();
        Assert.isNull(result);
    }

    @IsTest
    static void testSprint9AndCoreSelectors_WhenQuoteExists_ReturnsRows() {
        // Avoid forecast/Sales Connection paths that reference Quote.QuoteType__c (not on Dev).
        Quote quoteRecord = createQuote();

        Test.startTest();
        Quote emailQuote = QuoteSelector.selectForQuoteEmailReplyById(quoteRecord.Id);
        Quote approveQuote = QuoteSelector.selectForApproveRejectById(quoteRecord.Id);
        Quote byId = QuoteSelector.selectById(quoteRecord.Id);
        List<Quote> byIds = QuoteSelector.selectByIdsWithLineItems(new Set<Id>{ quoteRecord.Id });
        Test.stopTest();

        Assert.isNotNull(emailQuote);
        Assert.areEqual(quoteRecord.Id, emailQuote.Id);
        Assert.isNotNull(approveQuote);
        Assert.areEqual(quoteRecord.Id, approveQuote.Id);
        Assert.isNotNull(byId);
        Assert.areEqual(quoteRecord.Id, byId.Id);
        Assert.isFalse(byIds.isEmpty());
    }

    private static Quote createQuote() {
        adb_Product2 product = new adb_Product2().name('Quote Selector Product');
        new adb_PricebookEntry().product(product).unitPrice(1);
        adb_Account account = new adb_Account()
            .name('Quote Selector Account')
            .sourceSystemId('QUOTE-SEL-ACCT');
        adb_Contact contact = new adb_Contact().lastName('Quote Selector Contact').account(account);
        adb_Opportunity opportunity = new adb_Opportunity()
            .name('Quote Selector Opportunity')
            .account(account)
            .primaryContact(contact);
        adb_Quote quoteRecord = new adb_Quote().name('Quote Selector Quote').opportunity(opportunity);
        return (Quote) quoteRecord.persist();
    }
}