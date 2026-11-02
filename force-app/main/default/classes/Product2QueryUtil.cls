/**
 * @author Uptima Development Team
 * @date 2026-06-14
 * @description Shared Product2 query helpers for return order create, receive, and line correction flows.
 * @group Return Order Process
 * @see CreateReturnOrderController
 * @see ReturnOrderReceivingController
 */
public with sharing class Product2QueryUtil {
    /** @description ProductType__c value for serialized/service asset products used on return lines. */
    public static final String PRODUCT_TYPE_SERVICE_ASSET = 'Service Asset';
    /** @description Name of the default placeholder product for instrument return lines. */
    public static final String DEFAULT_PRODUCT_NAME = 'Default Product';

    private static final String PICKLIST_FIELDS =
        'Id, Name, ProductCode, Model__c, Description';
    private static final String DETAIL_FIELDS =
        'Id, Name, Description, ProductLine__c, ProductType__c, ProductCode, Model__c';
    private static final String CORRECTION_PICKLIST_FIELDS = 'Id, Name, ProductCode';
    private static final Integer DEFAULT_QUERY_LIMIT = 200;

    /**
     * @description Loads the active Default Product used when instrument lines omit a product selection.
     * @return Default Product2 row, or null when not configured.
     */
    public static Product2 queryDefaultProduct() {
        List<Product2> products = [
            SELECT Id, Name, Description, ProductLine__c, ProductCode, Model__c
            FROM Product2
            WHERE Name = :DEFAULT_PRODUCT_NAME AND IsActive = TRUE
            WITH USER_MODE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return products.isEmpty() ? null : products[0];
    }

    /**
     * @description Loads a single active product by Id, optionally enforcing Service Asset type.
     * @param productId Product2 Id to load.
     * @param requireServiceAssetType When true, restricts to ProductType__c = Service Asset.
     * @return Matching Product2, or null when not found or inactive.
     */
    public static Product2 getProductById(Id productId, Boolean requireServiceAssetType) {
        if (productId == null) {
            return null;
        }

        Boolean requireServiceAsset = requireServiceAssetType == null
            ? true
            : requireServiceAssetType;

        String query =
            'SELECT ' +
            DETAIL_FIELDS +
            ' FROM Product2 WHERE Id = :productId AND IsActive = TRUE';
        Map<String, Object> binds = new Map<String, Object>{ 'productId' => productId };

        if (requireServiceAsset) {
            query += ' AND ProductType__c = :serviceAssetType';
            binds.put('serviceAssetType', PRODUCT_TYPE_SERVICE_ASSET);
        }

        query += ' LIMIT 1';
        List<Product2> products = Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
        return products.isEmpty() ? null : products[0];
    }

    /**
     * @description Searches active products for return order line picklists.
     * @param productLine Optional ProductLine__c filter.
     * @param requireServiceAssetType When true, restricts to Service Asset products.
     * @param searchTerm Optional name, code, or model search term.
     * @return Up to 200 matching products ordered by name.
     */
    public static List<Product2> queryProductsForReturnOrderPicklist(
        String productLine,
        Boolean requireServiceAssetType,
        String searchTerm
    ) {
        Boolean requireServiceAsset = requireServiceAssetType == null
            ? true
            : requireServiceAssetType;
        Boolean filterByProductLine = String.isNotBlank(productLine);

        if (!filterByProductLine && !requireServiceAsset) {
            return new List<Product2>();
        }

        String normalizedProductLine = filterByProductLine ? productLine.trim() : null;
        String searchLikeTerm = buildSearchLikeTerm(searchTerm);

        return queryActiveProducts(
            PICKLIST_FIELDS,
            normalizedProductLine,
            filterByProductLine,
            requireServiceAsset,
            searchLikeTerm
        );
    }

    /**
     * @description Loads products for receive-line correction when filtered by product line.
     * @param productLine ProductLine__c value to match.
     * @param requireServiceAssetType When true, restricts to Service Asset products.
     * @return Matching active products ordered by name.
     */
    public static List<Product2> queryProductsByProductLineForCorrection(
        String productLine,
        Boolean requireServiceAssetType
    ) {
        if (String.isBlank(productLine)) {
            return new List<Product2>();
        }

        Boolean requireServiceAsset = requireServiceAssetType == null
            ? true
            : requireServiceAssetType;

        return queryActiveProducts(
            CORRECTION_PICKLIST_FIELDS,
            productLine.trim(),
            true,
            requireServiceAsset,
            null
        );
    }

    /**
     * @description Loads minimal product fields for a correction picklist selection.
     * @param productId Product2 Id to load.
     * @return Product2 with Id, Name, and ProductCode, or null when not found.
     */
    public static Product2 queryProductByIdForCorrection(Id productId) {
        if (productId == null) {
            return null;
        }

        List<Product2> products = [
            SELECT Id, Name, ProductCode
            FROM Product2
            WHERE Id = :productId
            WITH USER_MODE
            LIMIT 1
        ];
        return products.isEmpty() ? null : products[0];
    }

    private static List<Product2> queryActiveProducts(
        String selectFields,
        String normalizedProductLine,
        Boolean filterByProductLine,
        Boolean requireServiceAsset,
        String searchLikeTerm
    ) {
        String query = 'SELECT ' + selectFields + ' FROM Product2 WHERE IsActive = TRUE';
        Map<String, Object> binds = new Map<String, Object>();

        if (requireServiceAsset) {
            query += ' AND ProductType__c = :serviceAssetType';
            binds.put('serviceAssetType', PRODUCT_TYPE_SERVICE_ASSET);
        }
        if (filterByProductLine) {
            query += ' AND ProductLine__c = :normalizedProductLine';
            binds.put('normalizedProductLine', normalizedProductLine);
        }
        if (searchLikeTerm != null) {
            query +=
                ' AND (Name LIKE :searchLikeTerm' +
                ' OR ProductCode LIKE :searchLikeTerm' +
                ' OR Model__c LIKE :searchLikeTerm)';
            binds.put('searchLikeTerm', searchLikeTerm);
        }

        query += ' ORDER BY Name ASC LIMIT ' + DEFAULT_QUERY_LIMIT;
        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }

    private static String buildSearchLikeTerm(String searchTerm) {
        if (String.isBlank(searchTerm)) {
            return null;
        }
        return '%' + searchTerm.trim() + '%';
    }
}