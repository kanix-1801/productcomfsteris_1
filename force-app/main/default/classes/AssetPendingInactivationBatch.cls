/**
 * @description GW-2459 - Batch that evaluates Assets in Pending Inactivation and sets
 *              Service Inactive when no open Work Orders or active contract lines exist.
 * @author STERIS
 * @see AssetPendingInactivationService
 * @see AssetPendingInactivationScheduler
 */
public with sharing class AssetPendingInactivationBatch implements Database.Batchable<SObject>, Database.Stateful {

    /**
     * @description Default batch scope size when submitting the job.
     */
    public static final Integer DEFAULT_BATCH_SIZE = 200;

    /**
     * @description When true in tests, forces start/execute/finish into the catch path.
     */
    @TestVisible
    private static Boolean forceExceptionForTest = false;

    /**
     * @description Nebula Logger transaction Id from start, used to link execute/finish logs.
     */
    private String originalTransactionId;

    /**
     * @description Assets evaluated across all execute chunks.
     */
    @TestVisible
    private Integer totalEvaluatedCount = 0;

    /**
     * @description Assets inactivated across all execute chunks.
     */
    @TestVisible
    private Integer totalInactivatedCount = 0;

    /**
     * @description Assets left in Pending Inactivation because of open dependencies.
     */
    @TestVisible
    private Integer totalBlockedCount = 0;

    /**
     * @description Returns Assets whose Status is Pending Inactivation.
     * @param bc Batchable context
     * @return QueryLocator of pending-inactivation Assets
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        this.originalTransactionId = Logger.getTransactionId();
        try {
            if (forceExceptionForTest == true) {
                throw new AssetPendingInactivationService.AssetPendingInactivationException(
                    'Forced batch start failure for test'
                );
            }
            Logger.info('AssetPendingInactivationBatch.start: loading Pending Inactivation QueryLocator');
            return AssetPendingInactivationSelector.selectPendingInactivationQueryLocator();
        } catch (Exception e) {
            Logger.error('AssetPendingInactivationBatch.start', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Evaluates the current chunk and inactivates Assets with no open dependencies.
     * @param bc Batchable context
     * @param scope Asset records in the current chunk
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            if (forceExceptionForTest == true) {
                throw new AssetPendingInactivationService.AssetPendingInactivationException(
                    'Forced batch execute failure for test'
                );
            }
            List<Asset> assetList = (List<Asset>) scope;
            Logger.debug(
                new LogMessage('AssetPendingInactivationBatch.execute: processing {0} Asset(s)', assetList.size())
            );
            AssetPendingInactivationService.EvaluationResult result =
                AssetPendingInactivationService.evaluatePendingInactivation(assetList);
            this.totalEvaluatedCount += result.evaluatedCount;
            this.totalInactivatedCount += result.inactivatedCount;
            this.totalBlockedCount += result.blockedCount;
        } catch (Exception e) {
            Logger.error('AssetPendingInactivationBatch.execute', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Completes the batch run and logs evaluation totals.
     * @param bc Batchable context
     */
    public void finish(Database.BatchableContext bc) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            if (forceExceptionForTest == true) {
                throw new AssetPendingInactivationService.AssetPendingInactivationException(
                    'Forced batch finish failure for test'
                );
            }
            Logger.info(
                'AssetPendingInactivationBatch.finish: evaluated=' +
                this.totalEvaluatedCount +
                ' inactivated=' +
                this.totalInactivatedCount +
                ' blocked=' +
                this.totalBlockedCount +
                ' timestamp=' +
                String.valueOf(System.now()) +
                ' userId=' +
                UserInfo.getUserId()
            );
        } catch (Exception e) {
            Logger.error('AssetPendingInactivationBatch.finish', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Relates execute/finish log entries to the start transaction.
     */
    private void linkExecuteAndFinishLogsToStartTransaction() {
        Logger.setParentLogTransactionId(this.originalTransactionId);
    }
}