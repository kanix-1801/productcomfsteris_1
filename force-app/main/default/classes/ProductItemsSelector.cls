/**
 * @description Selector class for the ProductItem SObject.
 *              Centralizes all SOQL queries for Product Items.
 *              Centralizes Product Item SOQL. Classes run with sharing.
 */
public with sharing class ProductItemsSelector {

    private static final String BASE_FIELDS =
        'Id, ProductItemNumber, Product2Id, ProductName, LocationId, ' +
        'SerialNumber, QuantityOnHand, QuantityUnitOfMeasure, ' +
        'CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves ProductItem records by their Ids.
     * @param ids Set of ProductItem Ids to query.
     * @return List of ProductItem records matching the given Ids.
     */
    public static List<ProductItem> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ProductItem>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ProductItem' +
            ' WHERE Id IN :ids'
        );
    }

    /**
     * @description Retrieves ProductItem records by their related Product2 Ids.
     * @param product2Ids Set of Product2 Ids to filter by.
     * @return List of ProductItem records related to the given Products.
     */
    public static List<ProductItem> selectByProduct2Id(Set<Id> product2Ids) {
        if (product2Ids == null || product2Ids.isEmpty()) {
            return new List<ProductItem>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ProductItem' +
            ' WHERE Product2Id IN :product2Ids'
        );
    }
}