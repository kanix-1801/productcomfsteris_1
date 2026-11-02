/**
 * @description GW-3997 - Batch that evaluates First Contact Resolution (IsFCR__c) for closed
 *              Inbox Support Cases in a 7-day lookback window.
 * @author STERIS
 * @see CaseFCRService
 * @see CaseFCRScheduler
 */
public with sharing class CaseFCRBatch implements Database.Batchable<SObject>, Database.Stateful {

    /**
     * @description Default batch scope size when submitting the job.
     */
    public static final Integer DEFAULT_BATCH_SIZE = 200;

    /**
     * @description When true in tests, forces start/execute/finish into the catch path for coverage.
     */
    @TestVisible
    private static Boolean forceExceptionForTest = false;

    /**
     * @description Nebula Logger transaction Id from start, used to link execute/finish logs.
     */
    private String originalTransactionId;

    /**
     * @description Returns Cases eligible for FCR evaluation.
     * @param bc Batchable context
     * @return QueryLocator of closed Inbox Support Cases in the lookback window
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        this.originalTransactionId = Logger.getTransactionId();
        try {
            if (forceExceptionForTest == true) {
                throw new CaseFCRService.CaseFCRServiceException('Forced batch start failure for test');
            }
            Logger.info('CaseFCRBatch.start: loading FCR evaluation QueryLocator');
            return CaseFCRService.getFcrEvaluationQueryLocator();
        } catch (Exception e) {
            Logger.error('CaseFCRBatch.start', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Evaluates and updates IsFCR__c for the current batch chunk.
     * @param bc Batchable context
     * @param scope Case records in the current chunk
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            if (forceExceptionForTest == true) {
                throw new CaseFCRService.CaseFCRServiceException('Forced batch execute failure for test');
            }
            List<Case> caseList = (List<Case>) scope;
            Logger.debug(
                new LogMessage('CaseFCRBatch.execute: processing {0} Case(s)', caseList.size())
            );
            CaseFCRService.processFcrEvaluation(caseList);
        } catch (Exception e) {
            Logger.error('CaseFCRBatch.execute', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Completes the batch run.
     * @param bc Batchable context
     */
    public void finish(Database.BatchableContext bc) {
        linkExecuteAndFinishLogsToStartTransaction();
        try {
            if (forceExceptionForTest == true) {
                throw new CaseFCRService.CaseFCRServiceException('Forced batch finish failure for test');
            }
            Logger.info('CaseFCRBatch.finish: completed');
        } catch (Exception e) {
            Logger.error('CaseFCRBatch.finish', e);
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