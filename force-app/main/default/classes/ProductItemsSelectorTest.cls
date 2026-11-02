/**
 * @description Tests for ProductItemsSelector companion class (coverage for CBMQA dry-run).
 */
@IsTest
private class ProductItemsSelectorTest {
    @TestSetup
    static void setupData() {
        /********************************************
         * SETUP
         ********************************************/
        Product2 product = new Product2(Name = 'PI-SEL-Product', IsActive = true);
        insert product;

        Schema.Location locationRecord = new Schema.Location(
            Name = 'PI-SEL-Loc',
            LocationType = 'Warehouse',
            IsInventoryLocation = true
        );
        insert locationRecord;

        ProductItem item = new ProductItem(
            Product2Id = product.Id,
            LocationId = locationRecord.Id,
            QuantityOnHand = 1
        );
        insert item;
    }

    @IsTest
    static void testSelectById_WhenNullEmptyOrMatch_ReturnsExpected() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        ProductItem item = [SELECT Id FROM ProductItem LIMIT 1];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<ProductItem> nullResult = ProductItemsSelector.selectById(null);
            List<ProductItem> emptyResult = ProductItemsSelector.selectById(new Set<Id>());
            List<ProductItem> matchResult = ProductItemsSelector.selectById(new Set<Id>{ item.Id });
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, nullResult.size());
            Assert.areEqual(0, emptyResult.size());
            Assert.areEqual(1, matchResult.size());
            Assert.areEqual(item.Id, matchResult[0].Id);
        }
    }

    @IsTest
    static void testSelectByProduct2Id_WhenNullEmptyOrMatch_ReturnsExpected() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        ProductItem item = [SELECT Id, Product2Id FROM ProductItem LIMIT 1];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<ProductItem> nullResult = ProductItemsSelector.selectByProduct2Id(null);
            List<ProductItem> emptyResult = ProductItemsSelector.selectByProduct2Id(new Set<Id>());
            List<ProductItem> matchResult = ProductItemsSelector.selectByProduct2Id(
                new Set<Id>{ item.Product2Id }
            );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, nullResult.size());
            Assert.areEqual(0, emptyResult.size());
            Assert.isTrue(matchResult.size() >= 1);
            Assert.areEqual(item.Id, matchResult[0].Id);
        }
    }
}