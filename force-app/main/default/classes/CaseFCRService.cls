/**
 * @description GW-3997 - Service orchestration for Case First Contact Resolution (IsFCR__c) evaluation.
 * @author STERIS
 * @see Cases
 * @see CasesSelector
 * @see CaseFCRBatch
 */
public with sharing class CaseFCRService {

    /**
     * @description Inclusive ClosedDate lookback start offset in days from today (calendar day 7 days ago).
     */
    @TestVisible
    private static final Integer FCR_CLOSED_LOOKBACK_START_DAYS = -7;

    /**
     * @description Exclusive ClosedDate lookback end offset in days from today.
     */
    @TestVisible
    private static final Integer FCR_CLOSED_LOOKBACK_END_DAYS = -6;

    /**
     * @description Related CreatedDate window size in days around Case Created/Closed.
     */
    @TestVisible
    private static final Integer FCR_RELATED_WINDOW_DAYS = 7;

    /**
     * @description Custom exception for Case FCR Service operations.
     */
    public class CaseFCRServiceException extends Exception {}

    /**
     * @description When true in tests, treats Case.IsFCR__c as not updateable.
     */
    @TestVisible
    private static Boolean forceIsFcrNotUpdateableForTest = false;

    /**
     * @description When true in tests, forces processFcrEvaluation into the generic catch path.
     */
    @TestVisible
    private static Boolean forceExceptionForTest = false;

    /**
     * @description Returns the QueryLocator for Cases eligible for FCR evaluation.
     * @return QueryLocator for closed Inbox Support Cases in the lookback window
     */
    public static Database.QueryLocator getFcrEvaluationQueryLocator() {
        Date closedDateStart = Date.today().addDays(FCR_CLOSED_LOOKBACK_START_DAYS);
        Date closedDateEnd = Date.today().addDays(FCR_CLOSED_LOOKBACK_END_DAYS);
        return CasesSelector.selectClosedInboxSupportForFcrQueryLocator(closedDateStart, closedDateEnd);
    }

    /**
     * @description Orchestrates FCR evaluation for a batch of closed Cases and updates IsFCR__c.
     * @param caseList Closed Cases from the batch scope
     */
    public static void processFcrEvaluation(List<Case> caseList) {
        if (caseList == null || caseList.isEmpty()) {
            return;
        }

        try {
            Cases casesDomain = new Cases(caseList);
            casesDomain.checkSecurity('update');
            if (forceIsFcrNotUpdateableForTest == true
                || !Schema.sObjectType.Case.fields.IsFCR__c.isUpdateable()) {
                throw new Cases.SecurityException('User does not have permission to update Case.IsFCR__c');
            }

            Set<Id> caseIdSet = new Set<Id>();
            Set<String> categorySet = new Set<String>();
            Set<Id> contactIdSet = new Set<Id>();
            Set<Id> assetIdSet = new Set<Id>();
            Set<String> serialNumberSet = new Set<String>();
            Set<String> suppliedEmailSet = new Set<String>();
            Datetime minCreatedDateBound;
            Datetime maxCreatedDateBound;

            // Collect identifier and date bounds used by the related-Case selector.
            for (Case caseRecord : caseList) {
                if (caseRecord.ClosedDate == null || String.isBlank(caseRecord.Category__c)) {
                    continue;
                }
                caseIdSet.add(caseRecord.Id);
                if (caseRecord.Category__c != null) {
                    categorySet.add(caseRecord.Category__c);
                }
                if (caseRecord.ContactId != null) {
                    contactIdSet.add(caseRecord.ContactId);
                }
                if (caseRecord.AssetId != null) {
                    assetIdSet.add(caseRecord.AssetId);
                }
                if (caseRecord.SerialNumber__c != null) {
                    serialNumberSet.add(caseRecord.SerialNumber__c);
                }
                if (caseRecord.SuppliedEmail != null) {
                    suppliedEmailSet.add(caseRecord.SuppliedEmail);
                }

                Datetime caseMinCreatedDate = caseRecord.CreatedDate.addDays(-FCR_RELATED_WINDOW_DAYS);
                Datetime caseMaxCreatedDate = caseRecord.ClosedDate.addDays(FCR_RELATED_WINDOW_DAYS);
                if (minCreatedDateBound == null || caseMinCreatedDate < minCreatedDateBound) {
                    minCreatedDateBound = caseMinCreatedDate;
                }
                if (maxCreatedDateBound == null || caseMaxCreatedDate > maxCreatedDateBound) {
                    maxCreatedDateBound = caseMaxCreatedDate;
                }
            }

            if (caseIdSet.isEmpty()) {
                return;
            }
            if (forceExceptionForTest == true) {
                throw new QueryException('Forced FCR processing failure for test');
            }

            Map<Id, Integer> sentEmailCountByCaseIdMap =
                EmailMessagesSelector.countSentByParentCaseIds(caseIdSet);
            Map<Id, Integer> voiceCallCountByCaseIdMap =
                VoiceCallsSelector.countByRelatedCaseIds(caseIdSet);
            List<Case> relatedCaseList = CasesSelector.selectRelatedCasesForFcr(
                categorySet,
                contactIdSet,
                assetIdSet,
                serialNumberSet,
                suppliedEmailSet,
                minCreatedDateBound,
                maxCreatedDateBound
            );

            List<Case> caseToUpdateList = casesDomain.applyFcrEvaluation(
                sentEmailCountByCaseIdMap,
                voiceCallCountByCaseIdMap,
                relatedCaseList
            );

            if (!caseToUpdateList.isEmpty()) {
                List<Case> fcrUpdateList = new List<Case>();
                for (Case caseToUpdate : caseToUpdateList) {
                    fcrUpdateList.add(new Case(
                        Id = caseToUpdate.Id,
                        IsFCR__c = caseToUpdate.IsFCR__c
                    ));
                }
                update fcrUpdateList;
                Logger.info(
                    new LogMessage(
                        'CaseFCRService.processFcrEvaluation: updated IsFCR__c on {0} Case(s)',
                        fcrUpdateList.size()
                    )
                );
            }
        } catch (Cases.SecurityException e) {
            Logger.error('Security check failed during Case FCR evaluation', e);
            throw e;
        } catch (Exception e) {
            Logger.error('CaseFCRService.processFcrEvaluation failed', e);
            throw new CaseFCRServiceException(
                'Failed to process Case FCR evaluation: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }
}