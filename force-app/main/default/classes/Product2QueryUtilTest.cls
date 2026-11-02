/**
 * @description Tests for Product2QueryUtil.
 */
@IsTest
private class Product2QueryUtilTest {
    @TestSetup
    static void setupData() {
        insert new Product2(
            Name = Product2QueryUtil.DEFAULT_PRODUCT_NAME,
            IsActive = true,
            ProductLine__c = 'Device Line',
            ProductType__c = Product2QueryUtil.PRODUCT_TYPE_SERVICE_ASSET
        );
    }

    @IsTest
    static void testQueryDefaultProductReturnsConfiguredDefault() {
        Product2 defaultProduct = Product2QueryUtil.queryDefaultProduct();
        System.assertNotEquals(null, defaultProduct);
        System.assertEquals(Product2QueryUtil.DEFAULT_PRODUCT_NAME, defaultProduct.Name);
    }

    @IsTest
    static void testGetProductByIdFiltersServiceAssetType() {
        Product2 serviceAssetProduct = new Product2(
            Name = 'Util Service Asset Product',
            IsActive = true,
            ProductType__c = Product2QueryUtil.PRODUCT_TYPE_SERVICE_ASSET,
            ProductLine__c = 'Device Line'
        );
        Product2 otherProduct = new Product2(
            Name = 'Util Non Service Asset Product',
            IsActive = true,
            ProductLine__c = 'Device Line'
        );
        insert new List<Product2>{ serviceAssetProduct, otherProduct };

        System.assertNotEquals(
            null,
            Product2QueryUtil.getProductById(serviceAssetProduct.Id, true)
        );
        System.assertEquals(
            null,
            Product2QueryUtil.getProductById(otherProduct.Id, true)
        );
        System.assertNotEquals(
            null,
            Product2QueryUtil.getProductById(otherProduct.Id, false)
        );
    }

    @IsTest
    static void testQueryProductsForReturnOrderPicklistCombinesFilters() {
        Product2 matchingProduct = new Product2(
            Name = 'Picklist Search Match',
            ProductCode = 'PICK-001',
            IsActive = true,
            ProductType__c = Product2QueryUtil.PRODUCT_TYPE_SERVICE_ASSET,
            ProductLine__c = 'INSTRUMENT'
        );
        insert matchingProduct;

        List<Product2> products = Product2QueryUtil.queryProductsForReturnOrderPicklist(
            'INSTRUMENT',
            true,
            'Picklist Search'
        );

        System.assertEquals(1, products.size());
        System.assertEquals(matchingProduct.Id, products[0].Id);
    }

    @IsTest
    static void testQueryProductsByProductLineForCorrectionAndLookupById() {
        Product2 correctionProduct = new Product2(
            Name = 'Correction Product',
            ProductCode = 'CORR-001',
            IsActive = true,
            ProductType__c = Product2QueryUtil.PRODUCT_TYPE_SERVICE_ASSET,
            ProductLine__c = 'FLEXIBLE'
        );
        insert correctionProduct;

        List<Product2> products = Product2QueryUtil.queryProductsByProductLineForCorrection(
            'FLEXIBLE',
            true
        );
        System.assertEquals(1, products.size());
        System.assertEquals(correctionProduct.Id, products[0].Id);

        Product2 loadedProduct = Product2QueryUtil.queryProductByIdForCorrection(
            correctionProduct.Id
        );
        System.assertEquals(correctionProduct.Id, loadedProduct.Id);
        System.assertEquals(null, Product2QueryUtil.queryProductByIdForCorrection(null));
        System.assertEquals(
            0,
            Product2QueryUtil.queryProductsByProductLineForCorrection('', true).size()
        );
    }
}