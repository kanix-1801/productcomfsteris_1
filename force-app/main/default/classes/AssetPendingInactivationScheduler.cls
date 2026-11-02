/**
 * @description GW-2459 - Schedulable entry point that submits AssetPendingInactivationBatch.
 * @author STERIS
 * @see AssetPendingInactivationBatch
 */
public with sharing class AssetPendingInactivationScheduler implements Schedulable {

    /**
     * @description Recommended schedulable job name for Setup → Schedule Apex.
     */
    public static final String SCHEDULE_JOB_NAME = 'Asset Pending Inactivation Evaluation';

    /**
     * @description Example daily cron expression (1:00 AM).
     */
    public static final String SCHEDULE_CRON_DAILY_1AM = '0 0 1 * * ?';

    /**
     * @description When true in tests, forces execute() into the catch path.
     */
    @TestVisible
    private static Boolean forceExceptionForTest = false;

    /**
     * @description Submits AssetPendingInactivationBatch.
     * @param sc Schedulable context
     */
    public void execute(SchedulableContext sc) {
        Logger.info('AssetPendingInactivationScheduler.execute: submitting AssetPendingInactivationBatch');
        try {
            if (forceExceptionForTest == true) {
                throw new AssetPendingInactivationService.AssetPendingInactivationException(
                    'Forced scheduler failure for test'
                );
            }
            Database.executeBatch(
                new AssetPendingInactivationBatch(),
                AssetPendingInactivationBatch.DEFAULT_BATCH_SIZE
            );
        } catch (Exception e) {
            Logger.error('AssetPendingInactivationScheduler.execute', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }
}