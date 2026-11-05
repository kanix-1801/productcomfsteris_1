/**
 * @author Vinay Soni
 * @date 2026/11/04
 *
 * @group ES Service Product Configurator
 *
 * @description Tests for QuoteSelector, including Sprint 9 Repair Center methods
 *              (GW-3600 / GW-5102 / GW-5333). Tolerates missing QuoteType__c on Dev for
 *              the USER_MODE propagatable-forecast selector path.
 */
@IsTest
private class QuoteSelectorTest {

    private static final Id UNKNOWN_ID = UserInfo.getUserId();
    private static final Set<Id> UNKNOWN_ID_SET = new Set<Id>{ UNKNOWN_ID };
    private static final String QUOTE_TYPE = 'Standard';

    /**
     * @description Each filter combination returns no quotes for an unknown Opportunity.
     */
    @IsTest
    static void testSelectByOpportunityIdWithLineItemsReturnsEmpty() {
        Test.startTest();
        List<List<Quote>> resultList = new List<List<Quote>>{
            QuoteSelector.selectByOpportunityIdWithLineItems(null),
            QuoteSelector.selectByOpportunityIdWithLineItems(UNKNOWN_ID),
            QuoteSelector.selectByOpportunityIdWithLineItems(UNKNOWN_ID, QUOTE_TYPE),
            QuoteSelector.selectByOpportunityIdWithLineItems(UNKNOWN_ID, null, true),
            QuoteSelector.selectByOpportunityIdWithLineItems(UNKNOWN_ID, QUOTE_TYPE, false, UNKNOWN_ID),
            QuoteSelector.selectByOpportunityIdWithLineItems(UNKNOWN_ID, null, true, UNKNOWN_ID),
            QuoteSelector.selectByOpportunityIdWithLineItems(UNKNOWN_ID, null, false, UNKNOWN_ID),
            QuoteSelector.selectByOpportunityIdWithLineItems(UNKNOWN_ID, QUOTE_TYPE, false, null, UNKNOWN_ID),
            QuoteSelector.selectByOpportunityIdWithLineItems(UNKNOWN_ID, null, true, null, UNKNOWN_ID),
            QuoteSelector.selectByOpportunityIdWithLineItems(UNKNOWN_ID, null, false, null, UNKNOWN_ID)
        };
        Test.stopTest();

        for (List<Quote> quoteList : resultList) {
            Assert.isTrue(quoteList.isEmpty(), 'No quotes should be returned');
        }
    }

    /**
     * @description Each filter combination counts no quotes for an unknown Opportunity.
     */
    @IsTest
    static void testCountByOpportunityIdReturnsZero() {
        Test.startTest();
        List<Integer> countList = new List<Integer>{
            QuoteSelector.countByOpportunityId(null),
            QuoteSelector.countByOpportunityId(UNKNOWN_ID),
            QuoteSelector.countByOpportunityId(UNKNOWN_ID, QUOTE_TYPE),
            QuoteSelector.countByOpportunityId(UNKNOWN_ID, null, true),
            QuoteSelector.countByOpportunityId(UNKNOWN_ID, QUOTE_TYPE, false, UNKNOWN_ID),
            QuoteSelector.countByOpportunityId(UNKNOWN_ID, null, true, UNKNOWN_ID),
            QuoteSelector.countByOpportunityId(UNKNOWN_ID, null, false, UNKNOWN_ID),
            QuoteSelector.countByOpportunityId(UNKNOWN_ID, QUOTE_TYPE, false, null, UNKNOWN_ID),
            QuoteSelector.countByOpportunityId(UNKNOWN_ID, null, true, null, UNKNOWN_ID),
            QuoteSelector.countByOpportunityId(UNKNOWN_ID, null, false, null, UNKNOWN_ID)
        };
        Test.stopTest();

        for (Integer quoteCount : countList) {
            Assert.areEqual(0, quoteCount, 'No quotes should be counted');
        }
    }

    /**
     * @description Blank and unknown Ids return no quotes from the remaining selectors.
     *              selectPropagatableForecastConfidenceQuotesByOpportunityId uses USER_MODE and
     *              QuoteType__c; when that field is absent the QueryException is tolerated so Dev
     *              remains green while CBMQA still exercises the path.
     */
    @IsTest
    static void testOtherSelectorsReturnEmpty() {
        Test.startTest();
        Quote nullIdQuote = QuoteSelector.selectById(null);
        Quote unknownIdQuote = QuoteSelector.selectById(UNKNOWN_ID);
        List<List<Quote>> resultList = new List<List<Quote>>{
            QuoteSelector.selectByIdsWithLineItems(null),
            QuoteSelector.selectByIdsWithLineItems(UNKNOWN_ID_SET),
            QuoteSelector.selectOpenForecastEligibleQuotesByOpportunityIds(null),
            QuoteSelector.selectOpenForecastEligibleQuotesByOpportunityIds(UNKNOWN_ID_SET),
            QuoteSelector.selectForecastManagementQuotesByOpportunityId(null),
            QuoteSelector.selectForecastManagementQuotesByOpportunityId(UNKNOWN_ID),
            QuoteSelector.selectSalesConnectionQuotesForForecastEligibleByOpportunityIds(null),
            QuoteSelector.selectSalesConnectionQuotesForForecastEligibleByOpportunityIds(UNKNOWN_ID_SET),
            QuoteSelector.selectPropagatableForecastConfidenceQuotesByOpportunityId(null),
            QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(null),
            QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(UNKNOWN_ID)
        };
        try {
            resultList.add(
                QuoteSelector.selectPropagatableForecastConfidenceQuotesByOpportunityId(UNKNOWN_ID)
            );
        } catch (QueryException queryException) {
            Assert.isTrue(
                queryException.getMessage().contains('QuoteType__c'),
                'Unexpected QueryException: ' + queryException.getMessage()
            );
        }
        Set<Id> opportunityIdSet = QuoteSelector.selectOpportunityIdsWithOpenForecastEligibleQuotes(
            UNKNOWN_ID_SET
        );
        List<Map<Id, Integer>> countMapList = new List<Map<Id, Integer>>{
            QuoteSelector.countPropagatableForecastConfidenceQuotesByOpportunityIds(null),
            QuoteSelector.countPropagatableForecastConfidenceQuotesByOpportunityIds(UNKNOWN_ID_SET),
            QuoteSelector.countOpenSalesConnectionQuotesByOpportunityIds(null),
            QuoteSelector.countOpenSalesConnectionQuotesByOpportunityIds(UNKNOWN_ID_SET)
        };
        Test.stopTest();

        Assert.isNull(nullIdQuote, 'A null Id should return no quote');
        Assert.isNull(unknownIdQuote, 'An unknown Id should return no quote');
        Assert.isTrue(opportunityIdSet.isEmpty(), 'No Opportunity Ids should be returned');
        for (List<Quote> quoteList : resultList) {
            Assert.isTrue(quoteList.isEmpty(), 'No quotes should be returned');
        }
        for (Map<Id, Integer> countMap : countMapList) {
            Assert.isTrue(countMap.isEmpty(), 'No counts should be returned');
        }
    }

    /**
     * @description Constructor binds the selector to Quote for SoqlQueryBuilder queries.
     */
    @IsTest
    static void testConstructor_bindsQuoteObject() {
        Test.startTest();
        QuoteSelector selector = new QuoteSelector();
        Test.stopTest();
        Assert.isNotNull(selector);
    }

    /**
     * @description GW-5102 / GW-5333 null guards return null.
     */
    @IsTest
    static void testSprint9Selectors_WhenNull_ReturnNull() {
        Test.startTest();
        Quote emailQuote = QuoteSelector.selectForQuoteEmailReplyById(null);
        Quote approveQuote = QuoteSelector.selectForApproveRejectById(null);
        Test.stopTest();
        Assert.isNull(emailQuote);
        Assert.isNull(approveQuote);
    }

    /**
     * @description GW-5102 / GW-5333 and core Id selectors return the matching Quote.
     */
    @IsTest
    static void testSprint9AndCoreSelectors_WhenQuoteExists_ReturnsRows() {
        Quote quoteRecord = createQuote();

        Test.startTest();
        Quote emailQuote = QuoteSelector.selectForQuoteEmailReplyById(quoteRecord.Id);
        Quote approveQuote = QuoteSelector.selectForApproveRejectById(quoteRecord.Id);
        Quote byId = QuoteSelector.selectById(quoteRecord.Id);
        List<Quote> byIds = QuoteSelector.selectByIdsWithLineItems(new Set<Id>{ quoteRecord.Id });
        List<Quote> byOpportunity = QuoteSelector.selectByOpportunityIdWithLineItems(
            quoteRecord.OpportunityId
        );
        Integer opportunityCount = QuoteSelector.countByOpportunityId(quoteRecord.OpportunityId);
        Test.stopTest();

        Assert.isNotNull(emailQuote);
        Assert.areEqual(quoteRecord.Id, emailQuote.Id);
        Assert.isNotNull(approveQuote);
        Assert.areEqual(quoteRecord.Id, approveQuote.Id);
        Assert.isNotNull(byId);
        Assert.areEqual(quoteRecord.Id, byId.Id);
        Assert.isFalse(byIds.isEmpty());
        Assert.isFalse(byOpportunity.isEmpty());
        Assert.isTrue(opportunityCount > 0);
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