/**
 * @description
 * GC-2615 - SOQL selector for Account-scoped Key Account Process Review history.
 * All queries enforce the running user's object and field permissions.
 */
public with sharing class KeyAccountProcessReviewHistorySelector {
    /**
     * @description GC-2615 - Selects the Account context required by the history service.
     * @param accountId Account record Id.
     * @return Matching Account, or an empty list.
     */
    public static List<Account> selectAccountById(Id accountId) {
        if (accountId == null) {
            return new List<Account>();
        }

        return [
            SELECT Id, Type
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
    }

    /**
     * @description GC-2615 - Selects AAR child Accounts for the current IDN.
     * @param parentAccountId IDN Account record Id.
     * @return AAR rows containing child Account Ids.
     */
    public static List<AccountAccountRelationship__c> selectChildrenByParentId(
        Id parentAccountId
    ) {
        if (parentAccountId == null) {
            return new List<AccountAccountRelationship__c>();
        }

        return [
            SELECT ChildAccount__c
            FROM AccountAccountRelationship__c
            WHERE ParentAccount__c = :parentAccountId
              AND ChildAccount__c != null
            WITH USER_MODE
        ];
    }

    /**
     * @description GC-2615 - Selects KAPR records associated with the supplied Accounts.
     * @param accountIds Customer or facility Account Ids.
     * @param rowLimit Maximum number of rows to retrieve.
     * @return KAPR records ordered newest assessment first.
     */
    public static List<KeyAccountProcessReview__c> selectReviewsByAccountIds(
        Set<Id> accountIds,
        Integer rowLimit
    ) {
        if (accountIds == null || accountIds.isEmpty() || rowLimit == null || rowLimit <= 0) {
            return new List<KeyAccountProcessReview__c>();
        }

        return [
            SELECT
                Id,
                Name,
                AssessmentDate__c,
                CustomerAccountOrfacility__c,
                CustomerAccountOrfacility__r.Name,
                Department__c,
                ClinicalUser__c,
                CustomerChampion__c,
                CustomerChampion__r.Name,
                ShipToAddress__c,
                ShipToAddress__r.Name,
                Completed__c,
                CreatedDate
            FROM KeyAccountProcessReview__c
            WHERE CustomerAccountOrfacility__c IN :accountIds
            WITH USER_MODE
            ORDER BY AssessmentDate__c DESC NULLS LAST, CreatedDate DESC
            LIMIT :rowLimit
        ];
    }
}