/**
 * @description Selector for ProductRequired rows shown on a Work Order Product Request.
 */
public with sharing class ProductsRequiredSelector extends SoqlQueryBuilder {
    /**
     * @description Binds this selector to ProductRequired.
     */
    public ProductsRequiredSelector() {
        super('ProductRequired');
    }

    /**
     * @description Product Required rows for a Work Order.
     * @param parentRecordId Work Order Id stored on ProductRequired.ParentRecordId.
     * @return Product Required rows ordered by product name.
     * @example
     * ProductsRequiredSelector.selectByParentRecordId(workOrderId);
     */
    public static List<ProductRequired> selectByParentRecordId(Id parentRecordId) {
        if (parentRecordId == null) {
            return new List<ProductRequired>();
        }
        return (List<ProductRequired>) new ProductsRequiredSelector()
            .selectFields(new List<String>{
                'Id',
                'ParentRecordId',
                'Product2Id',
                'ProductName',
                'QuantityRequired',
                'QuantityUnitOfMeasure',
                'Product2.Name',
                'Product2.ProductCode',
                'Product2.QuantityUnitOfMeasure',
                'Product2.SubstitutePart__r.Name'
            })
            .whereEquals('ParentRecordId', parentRecordId)
            .orderBy('ProductName')
            .execute();
    }
}