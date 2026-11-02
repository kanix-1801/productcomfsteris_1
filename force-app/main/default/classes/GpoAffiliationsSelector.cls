/**
 * @description
 * Selector layer for GPO Affiliation queries via AccountAccountRelation.
 */
public without sharing class GpoAffiliationsSelector {
    /**
     * @description
     * Test-only override for AccountAccountRelation query results.
     */
    @TestVisible
    private static List<AccountAccountRelation> testAccountAccountRelations;

    /**
     * @description
     * Returns AccountAccountRelation records where RelatedAccountId matches the given Account Id.
     *
     * @param accountId The Id of the related Account to filter by.
     * @return List of AccountAccountRelation records, or empty list if accountId is null.
     */

    public static List<AccountAccountRelation> getAccountAccountRelationsByRelatedAccountId(Id accountId) {
        if (accountId == null) {
            return new List<AccountAccountRelation>();
        }

        if (Test.isRunningTest() && testAccountAccountRelations != null) {
            return testAccountAccountRelations;
        }

        return [
            SELECT Id,
                   Name,
                   AccountId,
                   Account.Name,
                   RelatedAccountId,
                   Status__c,
                   StartDate,
                   EndDate,
                   ContractType__c
            FROM AccountAccountRelation
            WHERE RelatedAccountId = :accountId
            WITH USER_MODE
            ORDER BY StartDate DESC NULLS LAST
            LIMIT 200
        ];
    }

    /**
     * @description
     * GC-3180 - Returns AccountAccountRelation records for multiple related Account Ids.
     *
     * @param accountIds Related Account Ids used to resolve GPO/IDN affiliations.
     * @return Matching AccountAccountRelation records.
     */
    public static List<AccountAccountRelation> getAccountAccountRelationsByRelatedAccountIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<AccountAccountRelation>();
        }

        if (Test.isRunningTest() && testAccountAccountRelations != null) {
            return testAccountAccountRelations;
        }

        return [
            SELECT Id,
                   AccountId,
                   Account.Name,
                   Account.Type,
                   RelatedAccountId,
                   ContractType__c
            FROM AccountAccountRelation
            WHERE RelatedAccountId IN :accountIds
            WITH USER_MODE
        ];
    }

    /**
     * @description
     * GC-3180 AC2 - Returns AccountAccountRelation records for selected GPO/IDN Account Ids.
     *
     * @param accountIds GPO/IDN Account Ids selected for overlay assignment.
     * @return Affiliation records where AccountId matches the selected GPO/IDN accounts.
     */
    public static List<AccountAccountRelation> getAccountAccountRelationsByAccountIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<AccountAccountRelation>();
        }

        if (Test.isRunningTest() && testAccountAccountRelations != null) {
            return testAccountAccountRelations;
        }

        return [
            SELECT Id,
                   AccountId,
                   RelatedAccountId,
                   ContractType__c
            FROM AccountAccountRelation
            WHERE AccountId IN :accountIds
            WITH USER_MODE
        ];
    }
}