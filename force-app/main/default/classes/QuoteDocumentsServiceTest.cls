/**
 * @description Tests for QuoteDocumentsService (GW-5102).
 */
@IsTest
private class QuoteDocumentsServiceTest {
    @IsTest
    static void testGetLatestByQuoteId_WhenNullOrUnknown_ReturnsNull() {
        Test.startTest();
        QuoteDocument document = QuoteDocumentsService.getLatestByQuoteId(null);
        QuoteDocument missing = QuoteDocumentsService.getLatestByQuoteId(UserInfo.getUserId());
        Test.stopTest();
        Assert.isNull(document);
        Assert.isNull(missing);
    }
}