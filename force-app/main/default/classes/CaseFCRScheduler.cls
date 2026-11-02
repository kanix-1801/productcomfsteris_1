/**
 * @description GW-3997 - Schedulable entry point that submits CaseFCRBatch.
 * @author STERIS
 * @see CaseFCRBatch
 * @see CaseFCRService
 */
public with sharing class CaseFCRScheduler implements Schedulable {

    /**
     * @description Recommended schedulable job name for Setup → Schedule Apex.
     */
    public static final String SCHEDULE_JOB_NAME = 'Case FCR Evaluation';

    /**
     * @description Example daily cron expression (1:00 AM).
     */
    public static final String SCHEDULE_CRON_DAILY_1AM = '0 0 1 * * ?';

    /**
     * @description When true in tests, forces execute() into the catch path for coverage.
     */
    @TestVisible
    private static Boolean forceExceptionForTest = false;

    /**
     * @description Submits CaseFCRBatch for FCR evaluation.
     * @param sc Schedulable context
     */
    public void execute(SchedulableContext sc) {
        Logger.info('CaseFCRScheduler.execute: submitting CaseFCRBatch');
        try {
            if (forceExceptionForTest == true) {
                throw new CaseFCRService.CaseFCRServiceException('Forced scheduler failure for test');
            }
            Database.executeBatch(new CaseFCRBatch(), CaseFCRBatch.DEFAULT_BATCH_SIZE);
        } catch (Exception e) {
            Logger.error('CaseFCRScheduler.execute', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }
}