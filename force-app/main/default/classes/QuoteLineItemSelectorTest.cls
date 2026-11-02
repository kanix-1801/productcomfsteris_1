/**
 * @description Tests for QuoteLineItemSelector including GW-5102 quote email reply queries.
 */
@IsTest
private class QuoteLineItemSelectorTest {
    @IsTest
    static void testSelectForQuoteEmailReplyByQuoteId_WhenNull_ReturnsEmpty() {
        Test.startTest();
        List<QuoteLineItem> results = QuoteLineItemSelector.selectForQuoteEmailReplyByQuoteId(null);
        Test.stopTest();
        Assert.isTrue(results.isEmpty());
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
}