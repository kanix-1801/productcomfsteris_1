/**
 * @description Selector class for the Asset SObject.
 *              Centralizes all SOQL queries for Assets.
 *              Enforces security via WITH SECURITY_ENFORCED.
 */
public with sharing class AssetsSelector extends SoqlQueryBuilder{

    private static final List<String> BASE_FIELDS = new List<String>{
        'Id',
        'Name',
        'AccountId',
        'ContactId',
        'Product2Id',
        'SerialNumber',
        'InstallDate',
        'PurchaseDate',
        'UsageEndDate',
        'Status',
        'Quantity',
        'Price',
        'Description',
        'OwnerId',
        'ParentId',
        'CreatedDate',
        'LastModifiedDate'
    };

    private static final List<String> BASE_FIELDS_WITH_PFCL = new List<String>{
        'Id',
        'Name',
        'AccountId',
        'ContactId',
        'Product2Id',
        'SerialNumber',
        'InstallDate',
        'PurchaseDate',
        'UsageEndDate',
        'Status',
        'Quantity',
        'Price',
        'Description',
        'OwnerId',
        'ParentId',
        'CreatedDate',
        'LastModifiedDate',
        'Product2.PFCL__c',
        'Product2.PFCL__r.Name'
    };

    private static final List<String> ACCOUNT_LIST_FIELDS = new List<String>{
        'Id',
        'SerialNumber',
        'Name',
        'Status',
        'AccountId',
        'AssetAccountName_f__c',
        'Street',
        'City',
        'State',
        'PostalCode',
        'Country',
        'InstallDate'
    };

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
        return (List<Asset>) SoqlQueryBuilder.fromObject('Asset')
            .selectFields(BASE_FIELDS_WITH_PFCL)
            .whereField('Id', 'IN', new List<Id>(ids))
            .execute();
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
        return (List<Asset>) SoqlQueryBuilder.fromObject('Asset')
            .selectFields(BASE_FIELDS)
            .whereField('AccountId', 'IN', new List<Id>(accountIds))
            .orderBy('Name')
            .execute();
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

        SoqlQueryBuilder builder = SoqlQueryBuilder.fromObject('Asset')
            .selectFields(ACCOUNT_LIST_FIELDS)
            .whereField('AccountId', 'IN', new List<Id>(accountIds));
        if (String.isNotBlank(orderByFields)) {
            applyOrderByClause(builder, orderByFields);
        }
        if (queryLimit != null && queryLimit > 0) {
            builder.limitTo(queryLimit);
        }
        return (List<Asset>) builder.execute();
    }

    /**
     * @description Applies a simple ORDER BY clause such as "Name" or "Name DESC".
     * @param builder Target builder
     * @param orderByFields Caller-supplied order clause (field[, ASC|DESC])
     */
    private static void applyOrderByClause(SoqlQueryBuilder builder, String orderByFields) {
        String normalized = orderByFields.trim().replaceAll('\\s+', ' ');
        List<String> parts = normalized.split(' ');
        String fieldName = parts[0];
        Boolean descending =
            parts.size() > 1 && 'DESC'.equalsIgnoreCase(parts[1]);
        if (descending) {
            builder.orderByDesc(fieldName);
        } else {
            builder.orderBy(fieldName);
        }
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
        return (List<Asset>) SoqlQueryBuilder.fromObject('Asset')
            .selectFields(BASE_FIELDS)
            .whereField('SerialNumber', 'IN', new List<String>(serialNumbers))
            .execute();
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
        SoqlQueryBuilder builder = SoqlQueryBuilder.fromObject('Asset')
            .selectFields(new List<String>{ 'Id', 'Name', 'SerialNumber', 'PFCL__c' })
            .whereEquals('AccountId', accountId)
            .whereField('Name', 'LIKE', term)
            .whereField('SerialNumber', 'LIKE', term)
            .whereField('PFCL__c', 'LIKE', term)
            .withFilterLogic('1 AND (2 OR 3 OR 4)')
            .orderBy('Name');
        if (SEARCH_LIMIT != null && SEARCH_LIMIT > 0) {
            builder.limitTo(SEARCH_LIMIT);
        }
        return (List<Asset>) builder.execute();
    }

    private static final List<String> CREATE_RETURN_ORDER_LINE_FIELDS = new List<String>{
        'Id',
        'SerialNumber',
        'ModelCalculated__c',
        'Department__c',
        'Product2Id',
        'Product2.ProductLine__c',
        'Product2.Name',
        'Product2.Manufacturer__c'
    };

    /**
     * @description GW-1509 - Assets for an Account used by Create Return Order line selection.
     * @param accountId Account Id
     * @return Matching Asset rows
     */
    public static List<Asset> selectForCreateReturnOrderByAccountId(Id accountId) {
        if (accountId == null) {
            return new List<Asset>();
        }
        return (List<Asset>) SoqlQueryBuilder.fromObject('Asset')
            .selectFields(CREATE_RETURN_ORDER_LINE_FIELDS)
            .whereEquals('AccountId', accountId)
            .orderBy('SerialNumber', false, true)
            .orderBy('Name')
            .execute();
    }

    /**
     * @description GW-1509 - Assets by Id used by Create Return Order line selection.
     * @param assetIds Asset Ids
     * @return Matching Asset rows
     */
    public static List<Asset> selectForCreateReturnOrderByIds(Set<Id> assetIds) {
        if (assetIds == null || assetIds.isEmpty()) {
            return new List<Asset>();
        }
        return (List<Asset>) SoqlQueryBuilder.fromObject('Asset')
            .selectFields(CREATE_RETURN_ORDER_LINE_FIELDS)
            .whereField('Id', 'IN', new List<Id>(assetIds))
            .execute();
    }

    /**
     * @description GW-1509 - Assets matching a serial number for Create Return Order scan.
     * @param serialNumber Exact SerialNumber
     * @return Matching Asset rows (LIMIT 50)
     */
    public static List<Asset> selectForCreateReturnOrderBySerialNumber(String serialNumber) {
        if (String.isBlank(serialNumber)) {
            return new List<Asset>();
        }
        return (List<Asset>) SoqlQueryBuilder.fromObject('Asset')
            .selectFields(
                new List<String>{
                    'Id',
                    'SerialNumber',
                    'ModelCalculated__c',
                    'Department__c',
                    'Product2Id',
                    'Product2.ProductLine__c',
                    'Product2.Name',
                    'AccountId',
                    'Account.Name'
                }
            )
            .whereEquals('SerialNumber', serialNumber)
            .orderBy('Account.Name', false, true)
            .orderBy('SerialNumber', false, true)
            .limitTo(50)
            .execute();
    }

    /**
     * @description GW-1509 - Asset Id/AccountId for Create Return Order launch context.
     * @param assetIds Asset Ids
     * @return Matching Asset rows
     */
    public static List<Asset> selectAccountIdsByIds(Set<Id> assetIds) {
        if (assetIds == null || assetIds.isEmpty()) {
            return new List<Asset>();
        }
        return (List<Asset>) SoqlQueryBuilder.fromObject('Asset')
            .selectFields(new List<String>{ 'Id', 'AccountId' })
            .whereField('Id', 'IN', new List<Id>(assetIds))
            .execute();
    }

}