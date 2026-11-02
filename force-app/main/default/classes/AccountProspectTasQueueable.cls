/**
 * @author Abhishek Mishra
 * @date 04-06-2026
 * @description Queueable processor for asynchronous Prospect Account TAS processing.
 *
 *              Responsibilities:
 *              1. Receive eligible Prospect Account Ids from AccountService.
 *              2. Query Account fields required for the TAS request payload.
 *              3. Delegate real-time Boomi TAS callout and response processing
 *                 to AccountProspectTasIntegrationService.
 *
 *              Executes immediately after Prospect Account save (post-commit callout).
 * 
 * Last Modified: Akash Dahinde - (17/06/2026)
 */
public with sharing class AccountProspectTasQueueable
implements Queueable, Database.AllowsCallouts {
    
    private Set<Id> accountIds;
    
    /**
     * @description Initializes the queueable with eligible Prospect Account Ids.
     * @param accountIds Set of Account Ids to process asynchronously.
     */
    public AccountProspectTasQueueable(Set<Id> accountIds) {
        this.accountIds = accountIds == null ? new Set<Id>() : new Set<Id>(accountIds);
    }
    
    public void execute(QueueableContext context) {
        
        try {
            Logger.info('AccountProspectTasQueueable.execute: started');
            
            if (accountIds == null || accountIds.isEmpty()) {
                Logger.warn('AccountProspectTasQueueable.execute: accountIds is null or empty');
                return;
            }
            
            List<Account> accounts = AccountSelector.selectByIds(accountIds);
            
            if (accounts.isEmpty()) {
                Logger.warn('AccountProspectTasQueueable.execute: no Account records found');
                return;
            }
            
            AccountProspectTasIntegrationService.processAccounts(accounts);
            Logger.info('AccountProspectTasQueueable.execute: completed');
        } catch (Exception e) {
            Logger.error('AccountProspectTasQueueable.execute', e);
        } finally {
            Logger.saveLog();
        }
    }
}