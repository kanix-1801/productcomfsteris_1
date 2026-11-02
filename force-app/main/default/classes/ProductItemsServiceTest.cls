/**
 * @description Test class for ProductItemsService.
 *              Covers create, update, delete, and retrieval operations
 *              across positive, negative, bulk, and empty-input scenarios.
 */
@IsTest
private class ProductItemsServiceTest {

    @TestSetup
    static void setupTestData() {
        // Build a Product2, a Location, and 10 related Product Items
        Product2 product = new Product2(Name = 'Parent Product', IsActive = true);
        insert product;
        Schema.Location loc = new Schema.Location(
            Name = 'Parent Location',
            LocationType = 'Warehouse',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert loc;
        List<ProductItem> items = new List<ProductItem>();
        for (Integer i = 0; i < 10; i++) {
            items.add(
                new ProductItem(
                    Product2Id = product.Id,
                    LocationId = loc.Id,
                    QuantityOnHand = 5,
                    SerialNumber = 'SN-' + i
                )
            );
        }
        insert items;
    }

    // ── createProductItems ──────────────────────────────────────────────────

    @IsTest
    static void shouldCreateProductItems_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            ProductItem existing = [SELECT Product2Id, LocationId FROM ProductItem LIMIT 1];
            List<ProductItem> productItemList = new List<ProductItem>{
                new ProductItem(SerialNumber = 'NEW-1', QuantityOnHand = 2, Product2Id = existing.Product2Id, LocationId = existing.LocationId),
                new ProductItem(SerialNumber = 'NEW-2', QuantityOnHand = 2, Product2Id = existing.Product2Id, LocationId = existing.LocationId)
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductItemsService.createProductItems(productItemList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIds = new Map<Id, ProductItem>(productItemList).keySet();
            List<ProductItem> insertedList = [SELECT Id FROM ProductItem WHERE Id IN :insertedIds];
            Assert.areEqual(2, insertedList.size(), 'createProductItems should insert all 2 Product Items');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateProductItemsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM ProductItem];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductItemsService.createProductItems(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM ProductItem];
            Assert.areEqual(countBefore, countAfter, 'createProductItems with null should not insert any records');
        }
    }

    // ── updateProductItems ──────────────────────────────────────────────────

    @IsTest
    static void shouldUpdateProductItems_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ProductItem> productItemList = [SELECT Id, QuantityOnHand FROM ProductItem LIMIT 3];
            for (ProductItem productItem : productItemList) {
                productItem.QuantityOnHand = 99;
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductItemsService.updateProductItems(productItemList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIds = new Map<Id, ProductItem>(productItemList).keySet();
            List<ProductItem> updatedList = [SELECT Id, QuantityOnHand FROM ProductItem WHERE Id IN :updatedIds];
            for (ProductItem productItem : updatedList) {
                Assert.areEqual(99, productItem.QuantityOnHand, 'Quantity On Hand should be updated');
            }
        }
    }

    @IsTest
    static void shouldDoNothing_WhenUpdateProductItemsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductItemsService.updateProductItems(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(true, 'updateProductItems with null should complete without error');
        }
    }

    // ── deleteProductItems ──────────────────────────────────────────────────

    @IsTest
    static void shouldDeleteProductItems_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> productItemIdSet = new Map<Id, ProductItem>([SELECT Id FROM ProductItem LIMIT 3]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductItemsService.deleteProductItems(productItemIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM ProductItem WHERE Id IN :productItemIdSet];
            Assert.areEqual(0, remainingCount, 'deleteProductItems should delete all specified Product Items');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteProductItemsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM ProductItem];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductItemsService.deleteProductItems(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM ProductItem];
            Assert.areEqual(countBefore, countAfter, 'deleteProductItems with null should not delete any records');
        }
    }

    // ── getProductItemsById ─────────────────────────────────────────────────

    @IsTest
    static void shouldReturnProductItems_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> productItemIdSet = new Map<Id, ProductItem>([SELECT Id FROM ProductItem]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ProductItem> resultList = ProductItemsService.getProductItemsById(productItemIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(10, resultList.size(), 'getProductItemsById should return all 10 Product Items');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenGetByIdCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ProductItem> resultList = ProductItemsService.getProductItemsById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getProductItemsById with null should return an empty list');
        }
    }

    @IsTest
    static void shouldCoverSelectorByProduct2AndWrapDmlFailures() {
        ProductItem item = [SELECT Id, Product2Id FROM ProductItem LIMIT 1];
        Assert.isTrue(ProductItemsSelector.selectByProduct2Id(null).isEmpty());
        Assert.isFalse(
            ProductItemsSelector.selectByProduct2Id(new Set<Id>{ item.Product2Id }).isEmpty()
        );

        Boolean createThrew = false;
        try {
            ProductItemsService.createProductItems(
                new List<ProductItem>{ new ProductItem(Id = item.Id) }
            );
        } catch (ProductItemsService.ProductItemsServiceException e) {
            createThrew = true;
        }
        Boolean updateThrew = false;
        try {
            ProductItemsService.updateProductItems(
                new List<ProductItem>{
                    new ProductItem(
                        Id = (Id) (ProductItem.SObjectType.getDescribe().getKeyPrefix() + '000000000001')
                    )
                }
            );
        } catch (ProductItemsService.ProductItemsServiceException e) {
            updateThrew = true;
        }
        ProductItemsService.deleteProductItems(new Set<Id>{ UserInfo.getUserId() });
        Assert.isTrue(createThrew);
        Assert.isTrue(updateThrew);
        ProductItemsService.simulateUnexpectedException = true;
        try {
            Boolean getThrew = false;
            try {
                ProductItemsService.getProductItemsById(new Set<Id>{ item.Id });
            } catch (ProductItemsService.ProductItemsServiceException e) {
                getThrew = true;
            }
            Assert.isTrue(getThrew);
        } finally {
            ProductItemsService.simulateUnexpectedException = false;
        }
    }
}