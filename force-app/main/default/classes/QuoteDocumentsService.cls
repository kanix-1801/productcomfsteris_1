/**
 * @description GW-5102 - QuoteDocument (digital quote PDF) lookups.
 */
public with sharing class QuoteDocumentsService {
    /**
     * @description Returns the latest QuoteDocument for a Quote, including the binary payload.
     *              SYSTEM_MODE retained (builder is USER_MODE only).
     * @param quoteId Quote Id
     * @return Latest QuoteDocument, or null
     */
    public static QuoteDocument getLatestByQuoteId(Id quoteId) {
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