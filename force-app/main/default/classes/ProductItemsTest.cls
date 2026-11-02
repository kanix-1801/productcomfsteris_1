/**
 * @description Test class for ProductItems domain class.
 *              Covers constructor and domain exception.
 */
@IsTest
private class ProductItemsTest {

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
            List<ProductItem> productItemList = new List<ProductItem>{
                (ProductItem) new adb_ProductItem().serialNumber('SN-A').record,
                (ProductItem) new adb_ProductItem().serialNumber('SN-B').record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductItems domain = new ProductItems(productItemList);
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
            ProductItems domain = new ProductItems(new List<ProductItem>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    @IsTest
    static void shouldThrowProductItemsException_WhenExceptionIsRaised() {
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
                throw new ProductItems.ProductItemsException('Quantity On Hand cannot be negative.');
            } catch (ProductItems.ProductItemsException e) {
                Assert.areEqual(
                    'Quantity On Hand cannot be negative.',
                    e.getMessage(),
                    'Exception message should match the value provided at construction'
                );
            }
            Test.stopTest();
        }
    }
}