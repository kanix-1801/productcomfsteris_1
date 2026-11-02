/**
 * @description Queueable processor for asynchronous Life Sciences Customer Account
 *              TAS processing.
 *
 *              Responsibilities:
 *              1. Receive eligible Life Sciences Customer Account Ids from LSAccountService.
 *              2. Query Account fields required for the TAS request payload.
 *              3. Delegate the Boomi TAS callout and response processing
 *                 to LSAccountCustomerTasIntegrationService.
 *
 *              Executes immediately after Customer Account save (post-commit callout).
 *              Class code SC (Life Science) is enforced before this job is enqueued.
 * #GCL-83 
 */
public with sharing class LSAccountCustomerTasQueueable implements Queueable, Database.AllowsCallouts {

    private Set<Id> accountIds;

    @TestVisible
    private static Boolean throwTestException = false;

    /**
     * @description Initializes the queueable with eligible Customer Account Ids.
     * @param accountIds Set of Account Ids to process asynchronously.
     * #GCL-83 
     */
    public LSAccountCustomerTasQueueable(Set<Id> accountIds) {
        this.accountIds = accountIds == null ? new Set<Id>() : new Set<Id>(accountIds);
    }

    /**
     * @description Queries the Accounts and delegates TAS processing to the Life Sciences
     *              Customer integration service.
     * @param context Queueable context provided by the platform.
     * #GCL-83 
     */
    public void execute(QueueableContext context) {
        try {
            Logger.info('LSAccountCustomerTasQueueable.execute: started');

            if (Test.isRunningTest() && throwTestException) {
                throw new LSAccountCustomerTasQueueableException(
                    'Test exception for queueable execute catch coverage'
                );
            }

            if (accountIds == null || accountIds.isEmpty()) {
                Logger.warn('LSAccountCustomerTasQueueable.execute: accountIds is null or empty');
                return;
            }

            List<Account> accounts = AccountSelector.selectByIds(accountIds);

            if (accounts.isEmpty()) {
                Logger.warn('LSAccountCustomerTasQueueable.execute: no Account records found');
                return;
            }

            LSAccountCustomerTasIntegrationService.processAccounts(accounts);
            Logger.info('LSAccountCustomerTasQueueable.execute: completed');
        } catch (Exception e) {
            Logger.error('LSAccountCustomerTasQueueable.execute', e);
        } finally {
            Logger.saveLog();
        }
    }

    public class LSAccountCustomerTasQueueableException extends Exception {}
}