/**
 * @description Test class for ProductsService.
 *              Includes Dev baseline CRUD/retrieval tests plus Batch 9 Device Evaluation additives
 *              (GW-3913 / GW-3096) in a dedicated section.
 */
@IsTest
private class ProductsServiceTest {
    private class SelectorException extends Exception {
    }

    private class ThrowingSelector implements ProductsService.IProductsSelector {
        public List<Product2> selectById(Set<Id> productIds) {
            throw new SelectorException('selectById failed');
        }

        public List<Product2> selectForDeviceEvaluationByIds(Set<Id> productIds) {
            throw new SelectorException('selectForDeviceEvaluationByIds failed');
        }

        public List<Product2> selectLabelsById(Id productId) {
            throw new SelectorException('selectLabelsById failed');
        }

        public List<Product2> selectForApproveRejectByIds(Set<Id> productIds) {
            throw new SelectorException('selectForApproveRejectByIds failed');
        }
    }

    @TestSetup
    static void setupTestData() {
        // Build and persist 10 Products
        List<Product2> productList = new List<Product2>();
        for (Integer i = 0; i < 10; i++) {
            productList.add(new Product2(Name = 'Test Product ' + i, IsActive = true));
        }
        insert productList;
    }

    // ── createProducts ────────────────────────────────────────────────────────

    @IsTest
    static void shouldCreateProducts_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<Product2> productList = new List<Product2>{
                new Product2(Name = 'New Product 1', IsActive = true),
                new Product2(Name = 'New Product 2', IsActive = true)
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductsService.createProducts(productList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIds = new Map<Id, Product2>(productList).keySet();
            List<Product2> insertedList = [SELECT Id FROM Product2 WHERE Id IN :insertedIds];
            Assert.areEqual(2, insertedList.size(), 'createProducts should insert all 2 Products');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateProductsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM Product2];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductsService.createProducts(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM Product2];
            Assert.areEqual(countBefore, countAfter, 'createProducts with null should not insert any records');
        }
    }

    // ── updateProducts ────────────────────────────────────────────────────────

    @IsTest
    static void shouldUpdateProducts_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<Product2> productList = [SELECT Id, Description FROM Product2 LIMIT 3];
            for (Product2 p : productList) {
                p.Description = 'Updated Description';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductsService.updateProducts(productList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIds = new Map<Id, Product2>(productList).keySet();
            List<Product2> updatedList = [SELECT Id, Description FROM Product2 WHERE Id IN :updatedIds];
            for (Product2 p : updatedList) {
                Assert.areEqual('Updated Description', p.Description, 'Description should be updated');
            }
        }
    }

    @IsTest
    static void shouldDoNothing_WhenUpdateProductsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductsService.updateProducts(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(true, 'updateProducts with null should complete without error');
        }
    }

    // ── deleteProducts ────────────────────────────────────────────────────────

    @IsTest
    static void shouldDeleteProducts_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> productIdSet = new Map<Id, Product2>([SELECT Id FROM Product2 LIMIT 3]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductsService.deleteProducts(productIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM Product2 WHERE Id IN :productIdSet];
            Assert.areEqual(0, remainingCount, 'deleteProducts should delete all specified Products');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteProductsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM Product2];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductsService.deleteProducts(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM Product2];
            Assert.areEqual(countBefore, countAfter, 'deleteProducts with null should not delete any records');
        }
    }

    // ── getProductsById ───────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnProducts_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> productIdSet = new Map<Id, Product2>([SELECT Id FROM Product2]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<Product2> resultList = ProductsService.getProductsById(productIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(10, resultList.size(), 'getProductsById should return all 10 Products');
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
            List<Product2> resultList = ProductsService.getProductsById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getProductsById with null should return an empty list');
        }
    }

    // ── Device Evaluation (GW-3913 / GW-3096) ─────────────────────────────────

    @IsTest
    static void testGetProductsForDeviceEvaluationByIds() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Product2 product = [SELECT Id FROM Product2 LIMIT 1];

            Test.startTest();
            Map<Id, Product2> byIds = ProductsService.getProductsForDeviceEvaluationByIds(
                new Set<Id>{ product.Id }
            );
            Map<Id, Product2> empty = ProductsService.getProductsForDeviceEvaluationByIds(null);
            Product2 labels = ProductsService.getProductLabelsById(product.Id);
            Product2 nullLabels = ProductsService.getProductLabelsById(null);
            Test.stopTest();

            Assert.areEqual(1, byIds.size(), 'Should return one Device Evaluation product');
            Assert.isTrue(byIds.containsKey(product.Id));
            Assert.isTrue(empty.isEmpty(), 'Null Ids should return empty map');
            Assert.isNotNull(labels, 'Labels lookup should return a Product');
            Assert.isNull(nullLabels, 'Null productId should return null');
        }
    }

    @IsTest
    static void testGetProductLabelsById_notFoundReturnsNull() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Test.startTest();
            Product2 missing = ProductsService.getProductLabelsById(UserInfo.getUserId());
            Test.stopTest();
            Assert.isNull(missing, 'Non-product Id should return null labels');
        }
    }

    @IsTest
    static void shouldCoverProductsSelectorQueries() {
        Product2 product = [SELECT Id, Name FROM Product2 LIMIT 1];
        Test.startTest();
        Assert.isTrue(ProductsSelector.selectByName(null).isEmpty());
        Assert.isFalse(ProductsSelector.selectByName(new Set<String>{ product.Name }).isEmpty());
        Assert.isTrue(ProductsSelector.selectByProductCode(new Set<String>()).isEmpty());
        ProductsSelector.selectByProductCode(new Set<String>{ 'NO-SUCH-CODE' });
        Assert.isTrue(ProductsSelector.selectForDeviceEvaluationByIds(null).isEmpty());
        Assert.isFalse(
            ProductsSelector.selectForDeviceEvaluationByIds(new Set<Id>{ product.Id }).isEmpty()
        );
        Assert.isTrue(ProductsSelector.selectLabelsById(null).isEmpty());
        Assert.isFalse(ProductsSelector.selectLabelsById(product.Id).isEmpty());
        Test.stopTest();
    }

    @IsTest
    static void testCreateProducts_dmlFailureWrapsException() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Boolean threw = false;
            try {
                // Duplicate Id forces DML failure on insert.
                Product2 existing = [SELECT Id, Name FROM Product2 LIMIT 1];
                ProductsService.createProducts(
                    new List<Product2>{
                        new Product2(Id = existing.Id, Name = 'Should Not Insert')
                    }
                );
            } catch (ProductsService.ProductsServiceException e) {
                threw = true;
                Assert.isNotNull(e.getCause());
            }
            Assert.isTrue(threw, 'Insert with existing Id should wrap DML failure');
        }
    }

    @IsTest
    static void testDeleteProducts_selectorThrows() {
        assertSelectorFailure('delete');
    }

    @IsTest
    static void testGetProductsById_selectorThrows() {
        assertSelectorFailure('getById');
    }

    @IsTest
    static void testGetProductsForDeviceEvaluationByIds_selectorThrows() {
        assertSelectorFailure('deviceEvaluation');
    }

    @IsTest
    static void testGetProductLabelsById_selectorThrows() {
        assertSelectorFailure('labels');
    }

    @IsTest
    static void testGetProductsForApproveRejectById_selectorThrows() {
        assertSelectorFailure('approveReject');
    }

    private static void assertSelectorFailure(String operation) {
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        ProductsService.selectorOverride = new ThrowingSelector();
        try {
            Boolean threw = false;
            try {
                if (operation == 'delete') {
                    ProductsService.deleteProducts(new Set<Id>{ product.Id });
                } else if (operation == 'getById') {
                    ProductsService.getProductsById(new Set<Id>{ product.Id });
                } else if (operation == 'deviceEvaluation') {
                    ProductsService.getProductsForDeviceEvaluationByIds(
                        new Set<Id>{ product.Id }
                    );
                } else if (operation == 'approveReject') {
                    ProductsService.getProductsForApproveRejectById(
                        new Set<Id>{ product.Id }
                    );
                } else {
                    ProductsService.getProductLabelsById(product.Id);
                }
            } catch (ProductsService.ProductsServiceException e) {
                threw = true;
                Assert.isNotNull(e.getCause(), 'Wrapped exception should retain its cause');
            }
            Assert.isTrue(threw, operation + ' should wrap selector failures');
        } finally {
            ProductsService.selectorOverride = null;
        }
    }
}