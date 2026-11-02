/**
 * @description Test class for ProductRelatedMaterials domain class.
 *              Covers constructor and domain exception.
 */
@IsTest
private class ProductRelatedMaterialsTest {

    @IsTest
    static void shouldConstructDomain_WhenValidRecordListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ProductRelatedMaterial> relatedMaterialList = new List<ProductRelatedMaterial>{
                (ProductRelatedMaterial) new adb_ProductRelatedMaterial().quantityPerProductUnit(2).record,
                (ProductRelatedMaterial) new adb_ProductRelatedMaterial().quantityPerProductUnit(3).record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRelatedMaterials domain = new ProductRelatedMaterials(relatedMaterialList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from a valid record list');
        }
    }

    @IsTest
    static void shouldConstructDomain_WhenEmptyListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRelatedMaterials domain = new ProductRelatedMaterials(new List<ProductRelatedMaterial>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    @IsTest
    static void shouldThrowProductRelatedMaterialsException_WhenExceptionIsRaised() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN / THEN
             ********************************************/
            Test.startTest();
            try {
                throw new ProductRelatedMaterials.ProductRelatedMaterialsException('Quantity Per Product Unit cannot be negative.');
            } catch (ProductRelatedMaterials.ProductRelatedMaterialsException e) {
                Assert.areEqual(
                    'Quantity Per Product Unit cannot be negative.',
                    e.getMessage(),
                    'Exception message should match the value provided at construction'
                );
            }
            Test.stopTest();
        }
    }
}