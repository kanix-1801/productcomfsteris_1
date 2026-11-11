/**
 * @description GC-3618 - Deletes incomplete Healthcare Quotes and their Quote Lines.
 *              A scheduled system job, so DML runs in system mode and is not limited
 *              by the scheduling user's sharing or field access.
 *              Opportunity validation rules are suspended for the running user during the delete
 *              and restored immediately afterward.
 */
public without sharing class IncompleteHcQuoteCleanupService {
    private static final String LOGGER_TAG = 'GC-3618';
    private static final String QUOTE_TRIGGER_HANDLER = 'QuoteTriggerHandler';
    private static final String QUOTE_LINE_ITEM_TRIGGER_HANDLER = 'QuoteLineItemTriggerHandler';
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
     * @description User-level validation setting touched by one cleanup transaction.
     *              Held on the stateful batch from start through finish.
     */
    public class ValidationRuleBypass {
        public Id settingId;
        public Boolean createdHere = false;
        public Boolean previousDisableAll = false;
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

        List<String> handlersBypassedHere = bypassQuoteTriggers();
        try {
            ValidationRuleBypass validationBypass = beginValidationRuleBypass();
            try {
                Map<Id, Quote> quotesById = new Map<Id, Quote>(quoteScope);
                List<QuoteLineItem> lineItems = IncompleteHcQuoteCleanupSelector.selectLineItemsByQuoteIds(
                    quotesById.keySet()
                );
                Set<Id> quoteIdsWithLineFailures = deleteLineItems(lineItems, totals);

                List<Quote> quotesToDelete = new List<Quote>();
                for (Quote quoteRecord : quoteScope) {
                    if (!quoteIdsWithLineFailures.contains(quoteRecord.Id)) {
                        quotesToDelete.add(quoteRecord);
                    }
                }

                deleteQuotes(quotesToDelete, totals);
            } finally {
                endValidationRuleBypass(validationBypass);
            }
        } finally {
            releaseQuoteTriggerBypass(handlersBypassedHere);
        }
        Logger.info(
            'IncompleteHcQuoteCleanupService.deleteIncompleteQuotes: quotesDeleted=' + totals.quotesDeleted +
            ', linesDeleted=' + totals.linesDeleted +
            ', failureCount=' + totals.failureCount
        ).addTag(LOGGER_TAG);
        return totals;
    }

    /**
     * @description Skips the Quote and Quote Line trigger handlers for this cleanup only.
     *              Those handlers run forecast notification and opportunity recalculation on delete,
     *              which fail for incomplete quotes (no commercial commitment type) and for Closed Won
     *              opportunities. A handler already bypassed by the caller is left as it was.
     * @return Handler names this call bypassed, so only those are restored.
     */
    private static List<String> bypassQuoteTriggers() {
        List<String> handlersBypassedHere = new List<String>();
        for (String handlerName : new List<String>{ QUOTE_TRIGGER_HANDLER, QUOTE_LINE_ITEM_TRIGGER_HANDLER }) {
            if (!TriggerHandler.isBypassed(handlerName)) {
                TriggerHandler.bypass(handlerName);
                handlersBypassedHere.add(handlerName);
            }
        }
        return handlersBypassedHere;
    }

    /**
     * @description Turns off Opportunity validation rules for the running user.
     *              A setting created here is removed by endValidationRuleBypass.
     *              A setting that already existed is switched on and later restored.
     * @return State required to restore the previous value.
     */
    public static ValidationRuleBypass beginValidationRuleBypass() {
        ValidationRuleBypass bypass = new ValidationRuleBypass();
        Id userId = UserInfo.getUserId();
        List<Automation_Setting_Validation_Rule__c> existingSettings = [
            SELECT Id, disableAll__c
            FROM Automation_Setting_Validation_Rule__c
            WHERE SetupOwnerId = :userId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (existingSettings.isEmpty()) {
            Automation_Setting_Validation_Rule__c setting = new Automation_Setting_Validation_Rule__c(
                SetupOwnerId = userId,
                disableAll__c = true
            );
            Database.insert(setting, true, AccessLevel.SYSTEM_MODE);
            bypass.settingId = setting.Id;
            bypass.createdHere = true;
            return bypass;
        }

        bypass.settingId = existingSettings[0].Id;
        bypass.previousDisableAll = existingSettings[0].disableAll__c == true;
        if (existingSettings[0].disableAll__c != true) {
            existingSettings[0].disableAll__c = true;
            Database.update(existingSettings[0], true, AccessLevel.SYSTEM_MODE);
        }
        return bypass;
    }

    /**
     * @description Restores the validation setting captured by beginValidationRuleBypass.
     * @param bypass State from begin. Null is ignored.
     */
    public static void endValidationRuleBypass(ValidationRuleBypass bypass) {
        if (bypass == null || bypass.settingId == null) {
            return;
        }
        if (bypass.createdHere) {
            Database.delete(
                new Automation_Setting_Validation_Rule__c(Id = bypass.settingId),
                true,
                AccessLevel.SYSTEM_MODE
            );
            return;
        }
        if (bypass.previousDisableAll != true) {
            Database.update(
                new Automation_Setting_Validation_Rule__c(
                    Id = bypass.settingId,
                    disableAll__c = false
                ),
                true,
                AccessLevel.SYSTEM_MODE
            );
        }
    }

    private static void releaseQuoteTriggerBypass(List<String> handlersBypassedHere) {
        for (String handlerName : handlersBypassedHere) {
            TriggerHandler.clearBypass(handlerName);
        }
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