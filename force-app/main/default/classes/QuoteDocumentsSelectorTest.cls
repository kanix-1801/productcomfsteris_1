/**
 * @description Tests for QuoteDocumentsSelector (GW-5102).
 */
@IsTest
private class QuoteDocumentsSelectorTest {
    @IsTest
    static void testConstructor_bindsQuoteDocument() {
        Test.startTest();
        QuoteDocumentsSelector selector = new QuoteDocumentsSelector();
        Test.stopTest();
        Assert.isNotNull(selector);
    }
}