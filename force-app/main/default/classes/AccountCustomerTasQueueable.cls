/**
* @author Akash Dahinde
* @date 07-01-2026
* @description Queueable processor for asynchronous Customer Account TAS processing.
*              Runs immediately after Customer Account insert/update (post-commit callout).
* GC-3021
*/
    public with sharing class AccountCustomerTasQueueable
    implements Queueable, Database.AllowsCallouts {
        private static final String CLASS_NAME = 'AccountCustomerTasQueueable';
        private Set<Id> accountIds;
    
/**
* @description Initializes the queueable with eligible Customer Account Ids.
* @param accountIds Set of Account Ids to process asynchronously.
*/
    public AccountCustomerTasQueueable(Set<Id> accountIds) {
        this.accountIds = accountIds == null ? new Set<Id>() : new Set<Id>(accountIds);
    }
    
    public void execute(QueueableContext context) {
        try {
            Logger.setScenario('Customer TAS Boomi Integration');
            Logger.info(CLASS_NAME + '.execute: started, accountCount=' + (accountIds == null ? 0 : accountIds.size()));
            
            if (accountIds == null || accountIds.isEmpty()) {
                Logger.warn(CLASS_NAME + '.execute: accountIds is null or empty');
                return;
            }
            
            List<Account> accounts = AccountSelector.selectCustomerAccountsForTasByIds(accountIds);
            
            if (accounts.isEmpty()) {
                Logger.warn('AccountCustomerTasQueueable.execute: no Account records found');
                return;
            }
            
            AccountCustomerTasIntegrationService.processAccounts(accounts);
            Logger.info('AccountCustomerTasQueueable.execute: completed');
        } catch (Exception e) {
            Logger.error('AccountCustomerTasQueueable.execute', e);
        } finally {
            Logger.saveLog();
        }
    }
}