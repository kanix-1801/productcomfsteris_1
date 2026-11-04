/**
 * @description GC-3618 - Deletes incomplete Healthcare Quotes and their Quote Lines.
 *              A scheduled system job, so DML runs in system mode and is not limited
 *              by the scheduling user's sharing or field access.
 */
public without sharing class IncompleteHcQuoteCleanupService {
    private static final String LOGGER_TAG = 'GC-3618';
    @TestVisible
    private static Database.DeleteResult[] testLineDeleteResults;
    @TestVisible
    private static Database.DeleteResult[] testQuoteDeleteResults;

    /**
     * @description Counts from one cleanup chunk.
     */
    public class CleanupTotals {
        public Integer quotesDeleted = 0;
        public Integer linesDeleted = 0;
        public Integer failureCount = 0;
    }

    /**
     * @description Deletes Quote Lines first, then the parent Quote, for the given scope.
     *              A Quote is left in place when one of its lines fails to delete so the next run can retry it.
     * @param quoteScope HC Quotes selected by IncompleteHcQuoteCleanupSelector.
     * @return Deleted and failed row counts for this chunk.
     */
    public static CleanupTotals deleteIncompleteQuotes(List<Quote> quoteScope) {
        CleanupTotals totals = new CleanupTotals();
        if (quoteScope == null || quoteScope.isEmpty()) {
            Logger.warn('IncompleteHcQuoteCleanupService.deleteIncompleteQuotes: empty scope').addTag(LOGGER_TAG);
            return totals;
        }

        Map<Id, Quote> quotesById = new Map<Id, Quote>(quoteScope);
        List<QuoteLineItem> lineItems = IncompleteHcQuoteCleanupSelector.selectLineItemsByQuoteIds(quotesById.keySet());
        Set<Id> quoteIdsWithLineFailures = deleteLineItems(lineItems, totals);

        List<Quote> quotesToDelete = new List<Quote>();
        for (Quote quoteRecord : quoteScope) {
            if (!quoteIdsWithLineFailures.contains(quoteRecord.Id)) {
                quotesToDelete.add(quoteRecord);
            }
        }

        deleteQuotes(quotesToDelete, totals);
        Logger.info(
            'IncompleteHcQuoteCleanupService.deleteIncompleteQuotes: quotesDeleted=' + totals.quotesDeleted +
            ', linesDeleted=' + totals.linesDeleted +
            ', failureCount=' + totals.failureCount
        ).addTag(LOGGER_TAG);
        return totals;
    }

    private static Set<Id> deleteLineItems(List<QuoteLineItem> lineItems, CleanupTotals totals) {
        Set<Id> quoteIdsWithLineFailures = new Set<Id>();
        if (lineItems.isEmpty()) {
            return quoteIdsWithLineFailures;
        }

        Database.DeleteResult[] deleteResults = deleteRecords(lineItems, testLineDeleteResults);
        for (Integer index = 0; index < deleteResults.size(); index++) {
            if (deleteResults[index].isSuccess()) {
                totals.linesDeleted++;
                continue;
            }

            totals.failureCount++;
            quoteIdsWithLineFailures.add(lineItems[index].QuoteId);
            Logger.error(
                'IncompleteHcQuoteCleanupService quote line delete failed. quoteLineId=' +
                lineItems[index].Id +
                ', quoteId=' + lineItems[index].QuoteId +
                ', errors=' + formatErrors(deleteResults[index].getErrors())
            ).addTag(LOGGER_TAG);
        }
        return quoteIdsWithLineFailures;
    }

    private static void deleteQuotes(List<Quote> quotesToDelete, CleanupTotals totals) {
        if (quotesToDelete.isEmpty()) {
            return;
        }

        Database.DeleteResult[] deleteResults = deleteRecords(quotesToDelete, testQuoteDeleteResults);
        for (Integer index = 0; index < deleteResults.size(); index++) {
            if (deleteResults[index].isSuccess()) {
                totals.quotesDeleted++;
                continue;
            }

            totals.failureCount++;
            Logger.error(
                'IncompleteHcQuoteCleanupService quote delete failed. quoteId=' +
                quotesToDelete[index].Id +
                ', errors=' + formatErrors(deleteResults[index].getErrors())
            ).addTag(LOGGER_TAG);
        }
    }

    private static Database.DeleteResult[] deleteRecords(List<SObject> records, Database.DeleteResult[] stubResults) {
        if (Test.isRunningTest() && stubResults != null) {
            return stubResults;
        }
        return Database.delete(records, false, AccessLevel.SYSTEM_MODE);
    }

    @TestVisible
    private static String formatErrors(Database.Error[] errors) {
        List<String> messages = new List<String>();
        if (errors == null) {
            return '';
        }
        for (Database.Error errorValue : errors) {
            messages.add(errorValue.getStatusCode() + ': ' + errorValue.getMessage());
        }
        return String.join(messages, '; ');
    }
}