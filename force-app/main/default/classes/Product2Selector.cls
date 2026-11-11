/**
 * @author PWC Developer
 * @date 2026/07/23
 *
 * @group Product Sub-Group Detail
 *
 * @description
 * GC-3129 - SOQL selector for Product2 PSAM lookup used when deriving Product Sub-Group Detail on Opportunity.
 */
public with sharing class Product2Selector extends SoqlQueryBuilder {
    /**
     * @description Binds this selector to Product2 for SoqlQueryBuilder queries.
     */
    public Product2Selector() {
        this.objectName = 'Product2';
    }

    /**
     * @description
     * GC-3230 - Maximum number of active products returned to the Free Good Task product search.
     * The full result set is paginated client side, so the cap only guards the governor limit.
     */
    public static final Integer PRODUCT_SEARCH_LIMIT = 2000;

    /**
     * @description Returns Product2 rows with PSAM lookup for the given Product Ids.
     * @param product2Ids Product2 Id set.
     * @return Product2 rows with Id and PSAM__c.
     */
    public static List<Product2> selectPsamByIds(Set<Id> product2Ids) {
        if (product2Ids == null || product2Ids.isEmpty()) {
            return new List<Product2>();
        }

        return [
            SELECT Id, PSAM__c
            FROM Product2
            WHERE Id IN :product2Ids
            WITH SYSTEM_MODE
        ];
    }

    /**
     * @description
     * GC-3230 - Returns active products whose Name or Product Code matches the search key.
     * A blank search key returns the first page of active products so the user can browse the catalog.
     *
     * @param searchKey User-entered product name or product code fragment.
     * @return Matching active Product2 rows ordered by Name.
     *
     * @example
     * Product2Selector.selectActiveBySearchKey('sterilizer');
     */
    public static List<Product2> selectActiveBySearchKey(String searchKey) {
        String searchPattern = '%' + escapeLikeWildcards(searchKey) + '%';
        Integer searchLimit = PRODUCT_SEARCH_LIMIT;

        return [
            SELECT Id, Name, ProductCode, Family, Description
            FROM Product2
            WHERE IsActive = TRUE
            AND (Name LIKE :searchPattern OR ProductCode LIKE :searchPattern)
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT :searchLimit
        ];
    }

    /**
     * @description
     * GC-3230 - Returns active products for the given Product Ids, used to validate the user's selection on save.
     *
     * @param product2Ids Product2 Id set.
     * @return Active Product2 rows with Id and Name.
     *
     * @example
     * Product2Selector.selectActiveByIds(productIdSet);
     */
    public static List<Product2> selectActiveByIds(Set<Id> product2Ids) {
        if (product2Ids == null || product2Ids.isEmpty()) {
            return new List<Product2>();
        }

        return [
            SELECT Id, Name
            FROM Product2
            WHERE Id IN :product2Ids
            AND IsActive = TRUE
            WITH SYSTEM_MODE
        ];
    }

    /**
     * @description GW-4585 - PricingSource__c by product code for pricing line hydration.
     * @param productCodes Product codes to resolve
     * @return Matching Product2 rows
     */
    public static List<Product2> selectPricingSourceByProductCodes(Set<String> productCodes) {
        if (productCodes == null || productCodes.isEmpty()) {
            return new List<Product2>();
        }
        return [
            SELECT ProductCode, PricingSource__c
            FROM Product2
            WHERE ProductCode IN :productCodes
        ];
    }

    /**
     * @description GW-4585 - Product Ids keyed by product code for Headless Pricing JSON.
     * @param productCodes Product codes to resolve
     * @return Matching Product2 rows
     */
    public static List<Product2> selectIdsByProductCodes(Set<String> productCodes) {
        if (productCodes == null || productCodes.isEmpty()) {
            return new List<Product2>();
        }
        return [
            SELECT Id, ProductCode
            FROM Product2
            WHERE ProductCode IN :productCodes
        ];
    }

    /**
     * @description GW-4585 - Selling model options for Headless Pricing line items.
     * @param productIds Product2 Ids
     * @return ProductSellingModelOption rows ordered by CreatedDate
     */
    public static List<ProductSellingModelOption> selectSellingModelOptionsByProductIds(
        Set<Id> productIds
    ) {
        if (productIds == null || productIds.isEmpty()) {
            return new List<ProductSellingModelOption>();
        }
        return [
            SELECT Product2Id, ProductSellingModelId
            FROM ProductSellingModelOption
            WHERE Product2Id IN :productIds
            ORDER BY CreatedDate
        ];
    }

    /**
     * @description GW-4585 - Default OneTime selling model for Headless Pricing.
     * @return ProductSellingModel Id, or null
     */
    public static Id selectOneTimeSellingModelId() {
        List<ProductSellingModel> models = [
            SELECT Id
            FROM ProductSellingModel
            WHERE SellingModelType = 'OneTime'
            LIMIT 1
        ];
        return models.isEmpty() ? null : models[0].Id;
    }

    /**
     * @description Active Part products whose name or product code contains the search text.
     * @param searchKey Name or product code fragment.
     * @param rowLimit Maximum rows to return.
     * @return Matching Product2 rows ordered by Name.
     * @example
     * Product2Selector.selectActivePartsBySearchKey('seal', 25);
     */
    public static List<Product2> selectActivePartsBySearchKey(String searchKey, Integer rowLimit) {
        if (String.isBlank(searchKey)) {
            return new List<Product2>();
        }
        String searchPattern = '%' + escapeLikeWildcards(searchKey) + '%';
        Integer searchLimit = rowLimit == null || rowLimit <= 0 ? 25 : rowLimit;
        return (List<Product2>) SoqlQueryBuilder.fromObject('Product2')
            .selectFields(new List<String>{
                'Id', 'Name', 'ProductCode', 'QuantityUnitOfMeasure', 'SubstitutePart__r.Name'
            })
            .whereEquals('IsActive', true)
            .whereEquals('ProductType__c', 'Part')
            .whereField('Name', 'LIKE', searchPattern)
            .whereField('ProductCode', 'LIKE', searchPattern)
            .withFilterLogic('1 AND 2 AND (3 OR 4)')
            .orderBy('Name')
            .limitTo(searchLimit)
            .execute();
    }

    /**
     * @description Active Part products for the Ids selected on a Product Request.
     * @param product2Ids Product2 Ids.
     * @return Matching active Part products, including the unit of measure and description.
     * @example
     * Product2Selector.selectActivePartsByIds(productIdSet);
     */
    public static List<Product2> selectActivePartsByIds(Set<Id> product2Ids) {
        if (product2Ids == null || product2Ids.isEmpty()) {
            return new List<Product2>();
        }
        return (List<Product2>) SoqlQueryBuilder.fromObject('Product2')
            .selectFields(new List<String>{
                'Id', 'Name', 'ProductCode', 'QuantityUnitOfMeasure', 'Description'
            })
            .whereField('Id', 'IN', new List<Id>(product2Ids))
            .whereEquals('IsActive', true)
            .whereEquals('ProductType__c', 'Part')
            .execute();
    }

    /**
     * @description Escapes SOQL LIKE wildcards so user input is matched literally.
     * @param searchKey Raw user-entered search text.
     * @return Search text with % and _ escaped, or an empty string when blank.
     * @example
     * Product2Selector.escapeLikeWildcards('50%');
     */
    private static String escapeLikeWildcards(String searchKey) {
        if (String.isBlank(searchKey)) {
            return '';
        }

        return searchKey.trim().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }
}