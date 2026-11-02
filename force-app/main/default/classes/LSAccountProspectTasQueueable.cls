/**
 * @description Queueable processor for asynchronous Life Sciences Prospect Account
 *              TAS processing.
 *
 *              GCL-4: As Sales Leaders, I want Salesforce to trigger real-time TAS
 *              validation when a new Prospect Account is created so that rep assignments
 *              and territory visibility are established immediately.
 *
 *              Responsibilities:
 *              1. Receive eligible Life Sciences Prospect Account Ids from LSAccountService.
 *              2. Query Account fields required for the TAS request payload.
 *              3. Delegate real-time Boomi TAS callout and response processing
 *                 to LSAccountProspectTasIntegrationService.
 *
 *              Executes immediately after Prospect Account save (post-commit callout).
 */
public with sharing class LSAccountProspectTasQueueable
    implements Queueable, Database.AllowsCallouts {

    private Set<Id> accountIds;

    @TestVisible
    private static Boolean throwTestException = false;

    /**
     * @description Initializes the queueable with eligible Prospect Account Ids.
     * @param accountIds Set of Account Ids to process asynchronously.
     */
    public LSAccountProspectTasQueueable(Set<Id> accountIds) {
        this.accountIds = accountIds == null ? new Set<Id>() : new Set<Id>(accountIds);
    }

    /**
     * @description Queries the Accounts and delegates TAS processing to the Life Sciences
     *              integration service.
     * @param context Queueable context provided by the platform.
     */
    public void execute(QueueableContext context) {
        try {
            Logger.info('LSAccountProspectTasQueueable.execute: started');

            if (Test.isRunningTest() && throwTestException) {
                throw new LSAccountProspectTasQueueableException(
                    'Test exception for queueable execute catch coverage'
                );
            }

            if (accountIds == null || accountIds.isEmpty()) {
                Logger.warn('LSAccountProspectTasQueueable.execute: accountIds is null or empty');
                return;
            }

            List<Account> accounts = AccountSelector.selectByIds(accountIds);

            if (accounts.isEmpty()) {
                Logger.warn('LSAccountProspectTasQueueable.execute: no Account records found');
                return;
            }

            LSAccountProspectTasIntegrationService.processAccounts(accounts);
            Logger.info('LSAccountProspectTasQueueable.execute: completed');
        } catch (Exception e) {
            Logger.error('LSAccountProspectTasQueueable.execute', e);
        } finally {
            Logger.saveLog();
        }
    }

    public class LSAccountProspectTasQueueableException extends Exception {}
}