/**
 * @description Tests for QuoteDocumentsSelector (GW-5102).
 */
@IsTest
private class QuoteDocumentsSelectorTest {
    @IsTest
    static void testSelectLatestByQuoteId_WhenNull_ReturnsNull() {
        Test.startTest();
        QuoteDocument document = QuoteDocumentsSelector.selectLatestByQuoteId(null);
        QuoteDocument missing = QuoteDocumentsSelector.selectLatestByQuoteId(UserInfo.getUserId());
        Test.stopTest();
        Assert.isNull(document);
        Assert.isNull(missing);
    }
}