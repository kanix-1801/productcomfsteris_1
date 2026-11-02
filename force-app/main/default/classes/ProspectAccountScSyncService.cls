/**
 * @description GC-3441 - Salesforce to pass Prospect Account info to Sales Connection
 *              when a Prospect Account is updated.
 *
 *              Applies callout entry criteria and enqueues ProspectAccountScSyncQueueable
 *              so the Boomi callout does not run in trigger context.
 */
public with sharing class ProspectAccountScSyncService {
    /**
     * @description Called from Account after-update. Stops when the Account is not an
     * eligible Prospect with a watched field change and an HC Sales Opportunity/Quote.
     */
    public static void enqueueEligibleAccounts(
        List<Account> updatedAccounts,
        Map<Id, Account> oldAccountMap
    ) {
        Logger.setScenario('GC-3441 Prospect Account SC Sync');

        try {
            Set<Id> candidateAccountIds = collectProspectsWithWatchedFieldChange(
                updatedAccounts,
                oldAccountMap
            );

            if (candidateAccountIds.isEmpty()) {
                return;
            }

            Set<Id> eligibleAccountIds =
                ProspectAccountScSyncSelector.selectAccountIdsWithHcSalesQuote(
                    candidateAccountIds
                );

            if (eligibleAccountIds.isEmpty()) {
                Logger.info(
                    'ProspectAccountScSyncService.enqueueEligibleAccounts: ' +
                    'no HC Sales Opportunity/Quote match'
                ).addTag('GC-3441');
                return;
            }

            Id jobId = System.enqueueJob(
                new ProspectAccountScSyncQueueable(eligibleAccountIds)
            );
            Logger.info(
                'ProspectAccountScSyncService.enqueueEligibleAccounts: submitted jobId=' +
                jobId + ', accountCount=' + eligibleAccountIds.size()
            ).addTag('GC-3441');
        } catch (Exception exceptionValue) {
            Logger.error(
                'ProspectAccountScSyncService.enqueueEligibleAccounts',
                exceptionValue
            ).addTag('GC-3441');
        } finally {
            Logger.saveLog();
        }
    }

    @TestVisible
    private static Set<Id> collectProspectsWithWatchedFieldChange(
        List<Account> updatedAccounts,
        Map<Id, Account> oldAccountMap
    ) {
        Set<Id> accountIds = new Set<Id>();

        if (
            updatedAccounts == null ||
            updatedAccounts.isEmpty() ||
            oldAccountMap == null ||
            oldAccountMap.isEmpty()
        ) {
            return accountIds;
        }

        Schema.RecordTypeInfo prospectRecordType =
            Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get(ProspectAccountScSyncSelector.ACCOUNT_RECORD_TYPE_PROSPECT);

        if (prospectRecordType == null) {
            return accountIds;
        }

        Id prospectRecordTypeId = prospectRecordType.getRecordTypeId();

        for (Account accountRecord : updatedAccounts) {
            if (accountRecord == null || accountRecord.Id == null) {
                continue;
            }

            Account oldAccount = oldAccountMap.get(accountRecord.Id);
            if (oldAccount == null) {
                continue;
            }

            if (accountRecord.RecordTypeId != prospectRecordTypeId) {
                continue;
            }

            if (hasWatchedFieldChanged(accountRecord, oldAccount)) {
                accountIds.add(accountRecord.Id);
            }
        }

        return accountIds;
    }

    @TestVisible
    private static Boolean hasWatchedFieldChanged(Account newAccount, Account oldAccount) {
        return newAccount.Name != oldAccount.Name
            || newAccount.BillingStreet != oldAccount.BillingStreet
            || newAccount.BillingCity != oldAccount.BillingCity
            || newAccount.BillingState != oldAccount.BillingState
            || newAccount.BillingPostalCode != oldAccount.BillingPostalCode
            || newAccount.BillingCountry != oldAccount.BillingCountry
            || newAccount.Price_List__c != oldAccount.Price_List__c
            || newAccount.OrgIDs__c != oldAccount.OrgIDs__c
            || newAccount.CustomerClassCode__c != oldAccount.CustomerClassCode__c;
    }
}