/**
 * @description GW-5102 - Selector for QuoteDocument (digital quote PDF) queries.
 */
public with sharing class QuoteDocumentsSelector {
    /**
     * @description Returns the latest QuoteDocument for a Quote, including the binary payload.
     * @param quoteId Quote Id
     * @return Latest QuoteDocument, or null
     */
    public static QuoteDocument selectLatestByQuoteId(Id quoteId) {
        if (quoteId == null) {
            return null;
        }

        List<QuoteDocument> documents = [
            SELECT Id, Name, QuoteId, Document
            FROM QuoteDocument
            WHERE QuoteId = :quoteId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return documents.isEmpty() ? null : documents[0];
    }
}