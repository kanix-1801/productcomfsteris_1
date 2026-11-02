/**
 * @description Selector class for the Asset SObject.
 *              Centralizes all SOQL queries for Assets.
 *              Enforces security via WITH SECURITY_ENFORCED.
 */
public with sharing class AssetsSelector extends SoqlQueryBuilder{

    private static final String BASE_FIELDS =
        'Id, Name, AccountId, ContactId, Product2Id, SerialNumber, ' +
        'InstallDate, PurchaseDate, UsageEndDate, Status, Quantity, ' +
        'Price, Description, OwnerId, ParentId, CreatedDate, LastModifiedDate';

    public AssetsSelector() {
        this.objectName = 'Asset';
    }

    /**
     * @description Retrieves Asset records by their Ids.
     * @param ids Set of Asset Ids to query.
     * @return List of Asset records matching the given Ids.
     */
    public static List<Asset> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<Asset>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS + ', Product2.PFCL__c, Product2.PFCL__r.Name' +
            ' FROM Asset' +
            ' WHERE Id IN :ids' +
            ' WITH USER_MODE'
        );
    }

    /**
     * @description Retrieves Asset records by Account Id.
     * @param accountIds Set of Account Ids to filter by.
     * @return List of Asset records for the given Accounts.
     */
    public static List<Asset> selectByAccountId(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Asset>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM Asset' +
            ' WHERE AccountId IN :accountIds' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY Name ASC'
        );
    }

    /**
     * @description Retrieves Asset records by Account Id.
     * @param accountIds Set of Account Ids to filter by and order by Serial Number.
     * @return List of Asset records for the given Accounts.
     */
    public static List<Asset> selectByAccountId(Set<Id> accountIds, Integer queryLimit, String orderByFields) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Asset>();
        }

        String query =
            'SELECT Id, SerialNumber, Name, Status, AccountId, AssetAccountName_f__c, ' +
            'Street, City, State, PostalCode, Country, InstallDate ' +
            'FROM Asset ' +
            'WHERE AccountId IN :accountIds ' +
            'WITH USER_MODE ' +
            (String.isNotBlank(orderByFields)? (' ORDER BY '+ orderByFields) : '') +
            ((queryLimit != null && queryLimit > 0) ? (' LIMIT ' + queryLimit) : '');

        return Database.query(query);
    }

    /**
     * @description Retrieves Asset records by Serial Number.
     * @param serialNumbers Set of serial numbers to filter by.
     * @return List of Asset records matching the given serial numbers.
     */
    public static List<Asset> selectBySerialNumber(Set<String> serialNumbers) {
        if (serialNumbers == null || serialNumbers.isEmpty()) {
            return new List<Asset>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM Asset' +
            ' WHERE SerialNumber IN :serialNumbers' +
            ' WITH SECURITY_ENFORCED'
        );
    }

    /**
     * @description Retrieves Asset records by account Id and search text.
     * @param accountId Account Id.
     * @param term Search Text by User.
     * @return List of Asset records with the given account id and term.
     */
    public static List<Asset> selectByAccountIdAndSearchText(Id accountId, String term, Integer SEARCH_LIMIT) {
        if (accountId == null || term == null || String.isBlank(term)) {
            return new List<Asset>();
        }
        return [
            SELECT Id, Name, SerialNumber, PFCL__c
            FROM Asset
            WHERE AccountId = :accountId
            AND (Name LIKE :term OR SerialNumber LIKE :term OR PFCL__c LIKE :term)
            WITH USER_MODE
            ORDER BY Name
            LIMIT :SEARCH_LIMIT
        ];
    }

    /**
     * @description Retrieves Asset records
     * @param All parameters supports dynamic values
     * @return List of Asset records
     */
    public static List<Asset> selectAssets(List<String> fields, String filterField, List<Object> filterValues, Integer queryLimit) {
        if (fields == null || fields.isEmpty() || String.isBlank(filterField) || filterValues == null || filterValues.isEmpty()) {
            return new List<Asset>();
        }

        return (List<Asset>) SoqlQueryBuilder.fromObject('Asset')
                                             .selectFields(fields)
                                             .whereField(filterField, 'IN', filterValues)
                                             .orderBy('SerialNumber', false, true)
                                             .orderBy('Name')
                                             .limitTo(queryLimit)
                                             .execute();
    }

    /**
     * @description Retrieves Asset records
     * @param accountId Account Id
     * @param term Search Term by User
     * @param fields List of fields to fetch
     * @param SEARCH_LIMIT Limit for records
     * @return List of Asset records
     */
    public static List<Asset> searchAssets(Id accountId, String term, List<String> fields, Integer SEARCH_LIMIT) {
        if (accountId == null || String.isBlank(term)) {
            return new List<Asset>();
        }

        return (List<Asset>) SoqlQueryBuilder.fromObject('Asset')
                                            .selectFields(fields)
                                            .whereEquals('AccountId', accountId)
                                            .whereField('Name', 'LIKE', term)
                                            .withFilterLogic('1 AND (2 OR 3 OR 4)')
                                            .whereField('SerialNumber', 'LIKE', term)
                                            .whereField('PFCL__c', 'LIKE', term)
                                            .orderBy('Name')
                                            .limitTo(SEARCH_LIMIT)
                                            .execute();
    }
}