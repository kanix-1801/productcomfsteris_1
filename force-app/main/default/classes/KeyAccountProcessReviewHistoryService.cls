/**
 * @description
 * GC-2615 - Business logic and response mapping for Account-scoped KAPR history.
 */
public with sharing class KeyAccountProcessReviewHistoryService {
    private static final String IDN_ACCOUNT_TYPE = 'IDN';
    private static final String SCENARIO = 'Key Account Process Review History';
    private static final String USER_ERROR_MESSAGE =
        'Unable to load Key Account Process Review history.';
    private static final Integer MAX_REVIEW_ROWS = 2000;

    @TestVisible
    private static Integer reviewRowLimitOverride;

    @TestVisible
    private static String forcedExceptionMethodName;

    /**
     * @description GC-2615 - Returns Process Reviews in the scope of the current Account.
     * @param accountId Current Account record Id.
     * @return Account-scoped Process Review response.
     */
    public static ProcessReviewHistoryResponse getProcessReviewHistory(Id accountId) {
        if (accountId == null) {
            throw new KaprHistoryException('Account Id is required.');
        }

        Boolean shouldSaveLog = false;

        try {
            throwForcedTestExceptionIfRequested('getProcessReviewHistory');
            return buildHistoryResponse(accountId);
        } catch (KaprHistoryException expectedException) {
            throw expectedException;
        } catch (Exception exceptionRecord) {
            shouldSaveLog = true;
            Logger.setScenario(SCENARIO);
            Logger.error(
                'Unable to retrieve KAPR history. Error: ' + exceptionRecord.getMessage(),
                exceptionRecord
            )
                .addTag('GC-2615')
                .addTag('KAPR History')
                .setRecord(new Account(Id = accountId));
            throw new KaprHistoryException(USER_ERROR_MESSAGE);
        } finally {
            if (shouldSaveLog) {
                Logger.saveLog();
            }
        }
    }

    private static ProcessReviewHistoryResponse buildHistoryResponse(Id accountId) {
        List<Account> currentAccounts =
            KeyAccountProcessReviewHistorySelector.selectAccountById(accountId);

        if (currentAccounts.isEmpty()) {
            throw new KaprHistoryException(
                'The Account does not exist or you do not have access to it.'
            );
        }

        Boolean isIdnView = currentAccounts[0].Type == IDN_ACCOUNT_TYPE;
        Set<Id> reviewAccountIds = resolveReviewAccountIds(accountId, isIdnView);
        ProcessReviewHistoryResponse response =
            initializeResponse(isIdnView, reviewAccountIds.size());

        if (reviewAccountIds.isEmpty()) {
            return response;
        }

        response.reviews = KeyAccountProcessReviewHistorySelector.selectReviewsByAccountIds(
            reviewAccountIds,
            getQueryRowLimit()
        );
        applyDisplayLimit(response);
        response.totalReviewCount = response.reviews.size();
        return response;
    }

    private static void applyDisplayLimit(ProcessReviewHistoryResponse response) {
        Integer maxReviewRows = getMaxReviewRows();
        if (response.reviews.size() <= maxReviewRows) {
            return;
        }

        response.resultLimitReached = true;
        response.reviews.remove(response.reviews.size() - 1);
    }

    private static Integer getMaxReviewRows() {
        if (Test.isRunningTest() && reviewRowLimitOverride != null) {
            return reviewRowLimitOverride;
        }

        return MAX_REVIEW_ROWS;
    }

    private static Integer getQueryRowLimit() {
        return getMaxReviewRows() + 1;
    }

    private static void throwForcedTestExceptionIfRequested(String methodName) {
        if (Test.isRunningTest() && forcedExceptionMethodName == methodName) {
            throw new QueryException('Forced KAPR history test exception.');
        }
    }

    private static Set<Id> resolveReviewAccountIds(Id accountId, Boolean isIdnView) {
        Set<Id> reviewAccountIds = new Set<Id>();

        if (!isIdnView) {
            reviewAccountIds.add(accountId);
            return reviewAccountIds;
        }

        for (
            AccountAccountRelationship__c relationshipRecord :
            KeyAccountProcessReviewHistorySelector.selectChildrenByParentId(accountId)
        ) {
            reviewAccountIds.add(relationshipRecord.ChildAccount__c);
        }
        return reviewAccountIds;
    }

    private static ProcessReviewHistoryResponse initializeResponse(
        Boolean isIdnView,
        Integer relatedAccountCount
    ) {
        ProcessReviewHistoryResponse response = new ProcessReviewHistoryResponse();
        response.isIdnView = isIdnView;
        response.relatedAccountCount = relatedAccountCount;
        response.resultLimitReached = false;
        response.totalReviewCount = 0;
        response.reviews = new List<KeyAccountProcessReview__c>();
        return response;
    }

    /**
     * @description GC-2615 - Response consumed by the KAPR history LWC.
     */
    public class ProcessReviewHistoryResponse {
        @AuraEnabled public Boolean isIdnView;
        @AuraEnabled public Boolean resultLimitReached;
        @AuraEnabled public Integer relatedAccountCount;
        @AuraEnabled public Integer totalReviewCount;
        @AuraEnabled public List<KeyAccountProcessReview__c> reviews;
    }

    /**
     * @description GC-2615 - Safe service exception surfaced by the controller.
     */
    public class KaprHistoryException extends Exception {
    }
}