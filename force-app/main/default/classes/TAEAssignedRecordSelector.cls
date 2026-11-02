/**
 * @author Suraj Thapliyal
 * @date 2026/08/13
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-3333 - SOQL-only selector for TAE_AssignedRecord__c dedupe during grant processing
 *           and UI list queries. Dedupe queries and UI read queries use WITH SYSTEM_MODE because
 *           sales permission sets grant read-only object access without parent lookup FLS.
 *           Dynamic SOQL uses Database.queryWithBinds with AccessLevel.SYSTEM_MODE because
 *           WITH SYSTEM_MODE is not supported in dynamic query strings.
 *           This class owns query logic only and does not perform business processing or DML.
 */
public with sharing class TAEAssignedRecordSelector {

    private static final String SORT_DIRECTION_ASC = 'ASC';
    private static final String SORT_DIRECTION_DESC = 'DESC';

    /**
     * @description GC-3333 - Loads existing TAE + Account composite keys for bulk dedupe before insert.
     * @param taeIds TemporaryAccessException__c Ids from successful grant plans.
     * @param accountIds Account Ids from successful grant plans.
     * @return Composite keys in taeId|accountId format for rows that already exist.
     */
    public static Set<String> selectExistingAccountKeys(Set<Id> taeIds, Set<Id> accountIds) {
        Set<String> keys = new Set<String>();
        if (taeIds == null || taeIds.isEmpty() || accountIds == null || accountIds.isEmpty()) {
            return keys;
        }
        for (TAE_AssignedRecord__c row : [
            SELECT TemporaryAccessException__c, Account__c
            FROM TAE_AssignedRecord__c
            WHERE TemporaryAccessException__c IN :taeIds
              AND Account__c IN :accountIds
            WITH SYSTEM_MODE
        ]) {
            keys.add(buildAccountKey(row.TemporaryAccessException__c, row.Account__c));
        }
        return keys;
    }

    /**
     * @description GC-3333 - Loads existing TAE + Opportunity composite keys for bulk dedupe before insert.
     * @param taeIds TemporaryAccessException__c Ids from successful grant plans.
     * @param opportunityIds Opportunity Ids from successful grant plans.
     * @return Composite keys in taeId|opportunityId format for rows that already exist.
     */
    public static Set<String> selectExistingOpportunityKeys(Set<Id> taeIds, Set<Id> opportunityIds) {
        Set<String> keys = new Set<String>();
        if (taeIds == null || taeIds.isEmpty() || opportunityIds == null || opportunityIds.isEmpty()) {
            return keys;
        }
        for (TAE_AssignedRecord__c row : [
            SELECT TemporaryAccessException__c, Opportunity__c
            FROM TAE_AssignedRecord__c
            WHERE TemporaryAccessException__c IN :taeIds
              AND Opportunity__c IN :opportunityIds
            WITH SYSTEM_MODE
        ]) {
            keys.add(buildOpportunityKey(row.TemporaryAccessException__c, row.Opportunity__c));
        }
        return keys;
    }

    /**
     * @description GC-3333 - Builds the TAE + Account composite key used for duplicate prevention.
     * @param taeId TemporaryAccessException__c Id.
     * @param accountId Account Id.
     * @return Composite key in taeId|accountId format.
     */
    public static String buildAccountKey(Id taeId, Id accountId) {
        return String.valueOf(taeId) + '|' + String.valueOf(accountId);
    }

    /**
     * @description GC-3333 - Builds the TAE + Opportunity composite key used for duplicate prevention.
     * @param taeId TemporaryAccessException__c Id.
     * @param opportunityId Opportunity Id.
     * @return Composite key in taeId|opportunityId format.
     */
    public static String buildOpportunityKey(Id taeId, Id opportunityId) {
        return String.valueOf(taeId) + '|' + String.valueOf(opportunityId);
    }

    /**
     * @description GC-3333 - Counts assigned Account rows for one TAE, optionally filtered by Account Name.
     * @param taeId TemporaryAccessException__c Id.
     * @param searchLikeTerm Optional LIKE bind term; null returns all Account assignment rows.
     * @return Count of matching TAE_AssignedRecord__c rows visible to the running user.
     */
    public static Integer countAccountAssignmentsByTaeId(Id taeId, String searchLikeTerm) {
        if (taeId == null) {
            return 0;
        }
        if (String.isBlank(searchLikeTerm)) {
            return [
                SELECT COUNT()
                FROM TAE_AssignedRecord__c
                WHERE TemporaryAccessException__c = :taeId
                  AND Account__c != NULL
                WITH SYSTEM_MODE
            ];
        }
        return [
            SELECT COUNT()
            FROM TAE_AssignedRecord__c
            WHERE TemporaryAccessException__c = :taeId
              AND Account__c != NULL
              AND Account__r.Name LIKE :searchLikeTerm
            WITH SYSTEM_MODE
        ];
    }

    /**
     * @description GC-3333 - Counts assigned Opportunity rows for one TAE, optionally filtered by Opportunity Name.
     * @param taeId TemporaryAccessException__c Id.
     * @param searchLikeTerm Optional LIKE bind term; null returns all Opportunity assignment rows.
     * @return Count of matching TAE_AssignedRecord__c rows visible to the running user.
     */
    public static Integer countOpportunityAssignmentsByTaeId(Id taeId, String searchLikeTerm) {
        if (taeId == null) {
            return 0;
        }
        if (String.isBlank(searchLikeTerm)) {
            return [
                SELECT COUNT()
                FROM TAE_AssignedRecord__c
                WHERE TemporaryAccessException__c = :taeId
                  AND Opportunity__c != NULL
                WITH SYSTEM_MODE
            ];
        }
        return [
            SELECT COUNT()
            FROM TAE_AssignedRecord__c
            WHERE TemporaryAccessException__c = :taeId
              AND Opportunity__c != NULL
              AND Opportunity__r.Name LIKE :searchLikeTerm
            WITH SYSTEM_MODE
        ];
    }

    /**
     * @description GC-3333 - Loads one page of assigned Account rows for UI display.
     * @param taeId TemporaryAccessException__c Id.
     * @param searchLikeTerm Optional LIKE bind term on Account Name.
     * @param pageSize Maximum rows to return.
     * @param offset SOQL OFFSET for pagination.
     * @param sortDirection ASC or DESC on Account Name.
     * @return Assigned Account rows for the requested page.
     */
    public static List<TAE_AssignedRecord__c> selectAccountAssignmentsByTaeId(
        Id taeId,
        String searchLikeTerm,
        Integer pageSize,
        Integer offset,
        String sortDirection
    ) {
        if (taeId == null) {
            return new List<TAE_AssignedRecord__c>();
        }
        String sortDir = normalizeSortDirection(sortDirection);
        Map<String, Object> binds = new Map<String, Object>{
            'taeId' => taeId,
            'pageSize' => pageSize,
            'offset' => offset
        };
        String nameFilter = '';
        if (String.isNotBlank(searchLikeTerm)) {
            nameFilter = ' AND Account__r.Name LIKE :searchLikeTerm';
            binds.put('searchLikeTerm', searchLikeTerm);
        }
        String soql =
            'SELECT Id, Account__c, Account__r.Name' +
            ' FROM TAE_AssignedRecord__c' +
            ' WHERE TemporaryAccessException__c = :taeId' +
            ' AND Account__c != NULL' +
            nameFilter +
            ' ORDER BY Account__r.Name ' + sortDir + ' NULLS LAST, Id ' + sortDir +
            ' LIMIT :pageSize OFFSET :offset';
        return Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    }

    /**
     * @description GC-3333 - Loads one page of assigned Opportunity rows for UI display.
     * @param taeId TemporaryAccessException__c Id.
     * @param searchLikeTerm Optional LIKE bind term on Opportunity Name.
     * @param pageSize Maximum rows to return.
     * @param offset SOQL OFFSET for pagination.
     * @param sortDirection ASC or DESC on Opportunity Name.
     * @return Assigned Opportunity rows for the requested page.
     */
    public static List<TAE_AssignedRecord__c> selectOpportunityAssignmentsByTaeId(
        Id taeId,
        String searchLikeTerm,
        Integer pageSize,
        Integer offset,
        String sortDirection
    ) {
        if (taeId == null) {
            return new List<TAE_AssignedRecord__c>();
        }
        String sortDir = normalizeSortDirection(sortDirection);
        Map<String, Object> binds = new Map<String, Object>{
            'taeId' => taeId,
            'pageSize' => pageSize,
            'offset' => offset
        };
        String nameFilter = '';
        if (String.isNotBlank(searchLikeTerm)) {
            nameFilter = ' AND Opportunity__r.Name LIKE :searchLikeTerm';
            binds.put('searchLikeTerm', searchLikeTerm);
        }
        String soql =
            'SELECT Id, Opportunity__c, Opportunity__r.Name' +
            ' FROM TAE_AssignedRecord__c' +
            ' WHERE TemporaryAccessException__c = :taeId' +
            ' AND Opportunity__c != NULL' +
            nameFilter +
            ' ORDER BY Opportunity__r.Name ' + sortDir + ' NULLS LAST, Id ' + sortDir +
            ' LIMIT :pageSize OFFSET :offset';
        return Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    }

    /**
     * @description GC-3333 - Normalizes UI sort direction to ASC or DESC for dynamic SOQL.
     *
     * @param sortDirection Raw sort direction from the service layer.
     * @return ASC or DESC.
     */
    private static String normalizeSortDirection(String sortDirection) {
        return SORT_DIRECTION_DESC.equalsIgnoreCase(sortDirection)
            ? SORT_DIRECTION_DESC
            : SORT_DIRECTION_ASC;
    }
}