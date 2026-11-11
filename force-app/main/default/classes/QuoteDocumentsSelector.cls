/**
 * @description GW-5102 - Selector for QuoteDocument.
 *              Queries are built by QuoteDocumentsService (SYSTEM_MODE).
 */
public with sharing class QuoteDocumentsSelector extends SoqlQueryBuilder {
    /**
     * @description Binds this selector to QuoteDocument.
     */
    public QuoteDocumentsSelector() {
        super('QuoteDocument');
    }
}