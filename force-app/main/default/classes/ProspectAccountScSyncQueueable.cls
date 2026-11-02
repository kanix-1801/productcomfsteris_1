/**
 * @description GC-3441 - Post-commit processor that loads the latest Prospect Account
 *              and sends it to Sales Connection through Boomi.
 */
public with sharing class ProspectAccountScSyncQueueable
    implements Queueable, Database.AllowsCallouts {

    @TestVisible
    private static final Integer MAX_CALLOUTS_PER_JOB = 90;

    @TestVisible
    private static Integer maxCalloutsForTest;

    private final Set<Id> accountIds;

    @TestVisible
    private static Integer calloutLimit() {
        return maxCalloutsForTest == null ? MAX_CALLOUTS_PER_JOB : maxCalloutsForTest;
    }

    public ProspectAccountScSyncQueueable(Set<Id> accountIds) {
        this.accountIds = accountIds == null ? new Set<Id>() : new Set<Id>(accountIds);
    }

    public void execute(QueueableContext context) {
        Logger.setScenario('GC-3441 Prospect Account SC Sync');

        try {
            if (accountIds.isEmpty()) {
                Logger.warn(
                    'ProspectAccountScSyncQueueable.execute: no Account Ids supplied'
                ).addTag('GC-3441');
                return;
            }

            List<Account> accounts =
                ProspectAccountScSyncSelector.selectAccountsForSync(accountIds);
            Set<Id> remainingAccountIds = new Set<Id>();
            Integer processedCount = 0;

            for (Account accountRecord : accounts) {
                if (processedCount >= calloutLimit()) {
                    remainingAccountIds.add(accountRecord.Id);
                    continue;
                }

                ProspectAccountScSyncRequest request =
                    ProspectAccountScSyncMapper.toRequest(accountRecord);
                ProspectAccountScSyncGateway.CalloutResult calloutResult =
                    ProspectAccountScSyncGateway.sendAccountUpdate(request);

                if (calloutResult.retryEnqueued == true) {
                    Logger.warn(
                        'Boomi retry enqueued for Prospect Account ' + accountRecord.Id
                    ).addTag('GC-3441');
                } else if (calloutResult.calloutSuccess != true) {
                    Logger.error(
                        'Prospect Account SC sync failed. accountId=' +
                        accountRecord.Id + ', detail=' + calloutResult.errorDetail
                    ).addTag('GC-3441');
                }

                processedCount++;
            }

            if (!remainingAccountIds.isEmpty()) {
                System.enqueueJob(new ProspectAccountScSyncQueueable(remainingAccountIds));
            }

            Logger.info(
                'ProspectAccountScSyncQueueable.execute: processed=' +
                processedCount + ', remaining=' + remainingAccountIds.size()
            ).addTag('GC-3441');
        } catch (Exception exceptionValue) {
            Logger.error('ProspectAccountScSyncQueueable.execute', exceptionValue)
                .addTag('GC-3441');
        } finally {
            Logger.saveLog();
        }
    }
}