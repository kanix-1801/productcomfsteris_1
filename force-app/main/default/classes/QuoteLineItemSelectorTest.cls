/**
 * @description Tests for QuoteLineItemSelector (QACBM GC-3129 + SoqlQueryBuilder bind).
 */
@IsTest
private class QuoteLineItemSelectorTest {
    @IsTest
    static void testConstructor_bindsQuoteLineItemObject() {
        Test.startTest();
        QuoteLineItemSelector selector = new QuoteLineItemSelector();
        Test.stopTest();
        Assert.isNotNull(selector);
    }

    @IsTest
    static void testSelectByOpportunityIds_WhenBlankOrUnknown_ReturnsEmpty() {
        Test.startTest();
        List<QuoteLineItem> nullIds = QuoteLineItemSelector.selectByOpportunityIds(null);
        List<QuoteLineItem> emptyIds =
            QuoteLineItemSelector.selectByOpportunityIds(new Set<Id>());
        List<QuoteLineItem> unknownIds = QuoteLineItemSelector.selectByOpportunityIds(
            new Set<Id>{ UserInfo.getUserId() }
        );
        Test.stopTest();
        Assert.isTrue(nullIds.isEmpty());
        Assert.isTrue(emptyIds.isEmpty());
        Assert.isTrue(unknownIds.isEmpty());
    }

    @IsTest
    static void testSelectQuoteLineItemById_WhenBlank_ReturnsEmpty() {
        Test.startTest();
        List<QuoteLineItem> nullId =
            QuoteLineItemSelector.selectQuoteLineItemById(null, new List<String>{ 'Id' });
        List<QuoteLineItem> nullFields =
            QuoteLineItemSelector.selectQuoteLineItemById(UserInfo.getUserId(), null);
        List<QuoteLineItem> emptyFields =
            QuoteLineItemSelector.selectQuoteLineItemById(UserInfo.getUserId(), new List<String>());
        List<QuoteLineItem> unknownId = QuoteLineItemSelector.selectQuoteLineItemById(
            UserInfo.getUserId(),
            new List<String>{ 'Id' }
        );
        Test.stopTest();
        Assert.isTrue(nullId.isEmpty());
        Assert.isTrue(nullFields.isEmpty());
        Assert.isTrue(emptyFields.isEmpty());
        Assert.isTrue(unknownId.isEmpty());
    }
}