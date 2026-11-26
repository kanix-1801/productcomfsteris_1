/**
 * @description GW-5892 - Tests for Product2Selector (PSAM, catalog search, pricing and Field Service product lookups).
 * @group Field Service Quote
 * @see Product2Selector
 */
@IsTest
private class Product2SelectorTest {
    private static final String ACTIVE_CODE = 'P2SELTEST-ACTIVE';
    private static final String INACTIVE_CODE = 'P2SELTEST-INACTIVE';
    private static final String PERCENT_CODE = 'P2SELTEST-PCT';
    private static final String PERCENT_DECOY_CODE = 'P2SELTEST-500';
    private static final String UNDERSCORE_CODE = 'P2SELTEST_UND';
    private static final String UNDERSCORE_DECOY_CODE = 'P2SELTESTXUND';
    private static final String PERCENT_NAME = 'P2SelTest 50% Kit';
    private static final String PRICING_SOURCE_ORACLE = 'Oracle';
    private static final Integer ACTIVE_PRODUCT_COUNT = 5;

    /**
     * @description Five active products (including LIKE-wildcard look-alikes) and one inactive product.
     */
    @TestSetup
    static void setupData() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            insert new List<Product2>{
                new Product2(
                    Name = 'P2SelTest Active Gasket',
                    ProductCode = ACTIVE_CODE,
                    PricingSource__c = PRICING_SOURCE_ORACLE,
                    IsActive = true
                ),
                new Product2(Name = 'P2SelTest Inactive Gasket', ProductCode = INACTIVE_CODE, IsActive = false),
                new Product2(Name = PERCENT_NAME, ProductCode = PERCENT_CODE, IsActive = true),
                new Product2(Name = 'P2SelTest 500 Kit', ProductCode = PERCENT_DECOY_CODE, IsActive = true),
                new Product2(Name = 'P2SelTest Underscore Kit', ProductCode = UNDERSCORE_CODE, IsActive = true),
                new Product2(Name = 'P2SelTest Look-alike Kit', ProductCode = UNDERSCORE_DECOY_CODE, IsActive = true)
            };
        }
    }

    /**
     * @description Test products keyed by product code.
     * @return Map of product code to Product2
     */
    private static Map<String, Product2> productsByCode() {
        Map<String, Product2> productByCode = new Map<String, Product2>();
        for (Product2 product : [SELECT Id, Name, ProductCode, IsActive FROM Product2 WHERE ProductCode LIKE 'P2SELTEST%']) {
            productByCode.put(product.ProductCode, product);
        }
        return productByCode;
    }

    /**
     * @description Collects the product codes of the given rows.
     * @param products Product2 rows
     * @return Product codes
     */
    private static Set<String> codesOf(List<Product2> products) {
        Set<String> codes = new Set<String>();
        for (Product2 product : products) {
            codes.add(product.ProductCode);
        }
        return codes;
    }

    @IsTest
    static void nullOrEmptyInputs_returnEmptyResults() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Assert.areEqual(6, productsByCode().size(), 'Setup should create six products.');

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<Product2> psamNull = Product2Selector.selectPsamByIds(null);
            List<Product2> psamEmpty = Product2Selector.selectPsamByIds(new Set<Id>());
            List<Product2> activeNull = Product2Selector.selectActiveByIds(null);
            List<Product2> activeEmpty = Product2Selector.selectActiveByIds(new Set<Id>());
            List<Product2> pricingNull = Product2Selector.selectPricingSourceByProductCodes(null);
            List<Product2> pricingEmpty = Product2Selector.selectPricingSourceByProductCodes(new Set<String>());
            List<Product2> idsNull = Product2Selector.selectIdsByProductCodes(null);
            List<Product2> idsEmpty = Product2Selector.selectIdsByProductCodes(new Set<String>());
            List<ProductSellingModelOption> optionsNull = Product2Selector.selectSellingModelOptionsByProductIds(null);
            List<ProductSellingModelOption> optionsEmpty = Product2Selector.selectSellingModelOptionsByProductIds(
                new Set<Id>()
            );
            List<Product2> activeCodesNull = Product2Selector.selectActiveIdsByProductCodes(null);
            List<Product2> activeCodesEmpty = Product2Selector.selectActiveIdsByProductCodes(new Set<String>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, psamNull.size(), 'Null Ids should return no PSAM rows.');
            Assert.areEqual(0, psamEmpty.size(), 'Empty Ids should return no PSAM rows.');
            Assert.areEqual(0, activeNull.size(), 'Null Ids should return no active products.');
            Assert.areEqual(0, activeEmpty.size(), 'Empty Ids should return no active products.');
            Assert.areEqual(0, pricingNull.size(), 'Null codes should return no pricing source rows.');
            Assert.areEqual(0, pricingEmpty.size(), 'Empty codes should return no pricing source rows.');
            Assert.areEqual(0, idsNull.size(), 'Null codes should return no product Ids.');
            Assert.areEqual(0, idsEmpty.size(), 'Empty codes should return no product Ids.');
            Assert.areEqual(0, optionsNull.size(), 'Null Ids should return no selling model options.');
            Assert.areEqual(0, optionsEmpty.size(), 'Empty Ids should return no selling model options.');
            Assert.areEqual(0, activeCodesNull.size(), 'Null codes should return no active products.');
            Assert.areEqual(0, activeCodesEmpty.size(), 'Empty codes should return no active products.');
        }
    }

    @IsTest
    static void selectPsamByIds_returnsRequestedProducts() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Map<String, Product2> productByCode = productsByCode();
            Id activeId = productByCode.get(ACTIVE_CODE).Id;
            Id inactiveId = productByCode.get(INACTIVE_CODE).Id;

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<Product2> results = Product2Selector.selectPsamByIds(new Set<Id>{ activeId, inactiveId });
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Map<Id, Product2> resultsById = new Map<Id, Product2>(results);
            Assert.areEqual(2, resultsById.size(), 'PSAM lookup returns requested products regardless of status.');
            Assert.isTrue(resultsById.containsKey(activeId), 'Active product should be returned.');
            Assert.isTrue(resultsById.containsKey(inactiveId), 'Inactive product should be returned.');
            Assert.isNull(resultsById.get(activeId).PSAM__c, 'No PSAM was set in test data.');
        }
    }

    @IsTest
    static void selectActiveByIds_excludesInactiveProducts() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Map<String, Product2> productByCode = productsByCode();
            Id activeId = productByCode.get(ACTIVE_CODE).Id;
            Id inactiveId = productByCode.get(INACTIVE_CODE).Id;

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<Product2> results = Product2Selector.selectActiveByIds(new Set<Id>{ activeId, inactiveId });
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(1, results.size(), 'Only the active product should be returned.');
            Assert.areEqual(activeId, results[0].Id, 'Active product Id should be returned.');
            Assert.areEqual('P2SelTest Active Gasket', results[0].Name, 'Product Name should be selected.');
        }
    }

    @IsTest
    static void selectActiveBySearchKey_matchesNameOrCodeAndExcludesInactive() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Assert.isFalse(productsByCode().get(INACTIVE_CODE).IsActive, 'Inactive product should exist.');

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<Product2> byNamePrefix = Product2Selector.selectActiveBySearchKey('P2SelTest');
            List<Product2> byTrimmedCode = Product2Selector.selectActiveBySearchKey('  p2seltest-active  ');
            List<Product2> blankSearch = Product2Selector.selectActiveBySearchKey('   ');
            List<Product2> nullSearch = Product2Selector.selectActiveBySearchKey(null);
            List<Product2> noMatch = Product2Selector.selectActiveBySearchKey('NoSuchProduct-P2SelTest');
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<String> nameCodes = codesOf(byNamePrefix);
            Assert.areEqual(ACTIVE_PRODUCT_COUNT, byNamePrefix.size(), 'All active test products should match.');
            Assert.isFalse(nameCodes.contains(INACTIVE_CODE), 'Inactive products should be excluded.');

            Assert.areEqual(1, byTrimmedCode.size(), 'Trimmed, case-insensitive code search should match one.');
            Assert.areEqual(ACTIVE_CODE, byTrimmedCode[0].ProductCode, 'Product should match by code.');

            Set<String> blankCodes = codesOf(blankSearch);
            Assert.isTrue(blankCodes.contains(ACTIVE_CODE), 'Blank search should browse active products.');
            Assert.isFalse(blankCodes.contains(INACTIVE_CODE), 'Blank search should exclude inactive products.');
            Assert.areEqual(blankSearch.size(), nullSearch.size(), 'Null search should behave like blank search.');

            Assert.areEqual(0, noMatch.size(), 'Unknown search key should return no products.');
        }
    }

    @IsTest
    static void selectActiveBySearchKey_escapesLikeWildcards() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Map<String, Product2> productByCode = productsByCode();
            Assert.isTrue(productByCode.containsKey(PERCENT_DECOY_CODE), 'Percent look-alike product should exist.');
            Assert.isTrue(productByCode.containsKey(UNDERSCORE_DECOY_CODE), 'Underscore look-alike should exist.');

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<Product2> percentResults = Product2Selector.selectActiveBySearchKey('50%');
            List<Product2> underscoreResults = Product2Selector.selectActiveBySearchKey(UNDERSCORE_CODE);
            List<Product2> backslashResults = Product2Selector.selectActiveBySearchKey('P2SelTest\\');
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(1, percentResults.size(), '% should be matched literally, not as a wildcard.');
            Assert.areEqual(PERCENT_NAME, percentResults[0].Name, 'Only the product named with 50% should match.');

            Assert.areEqual(1, underscoreResults.size(), '_ should be matched literally, not as a wildcard.');
            Assert.areEqual(UNDERSCORE_CODE, underscoreResults[0].ProductCode, 'Only the underscore code should match.');

            Assert.areEqual(0, backslashResults.size(), 'Backslash should be matched literally.');
        }
    }

    @IsTest
    static void selectPricingSourceByProductCodes_returnsPricingSource() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<String> codes = new Set<String>{ ACTIVE_CODE, PERCENT_CODE };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<Product2> results = Product2Selector.selectPricingSourceByProductCodes(codes);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(2, results.size(), 'Both requested product codes should be returned.');
            for (Product2 result : results) {
                if (result.ProductCode == ACTIVE_CODE) {
                    Assert.areEqual(PRICING_SOURCE_ORACLE, result.PricingSource__c, 'PricingSource__c should be selected.');
                } else {
                    // Products inserted without a pricing source get the field default value.
                    Assert.areNotEqual(
                        PRICING_SOURCE_ORACLE,
                        result.PricingSource__c,
                        'Product without an explicit pricing source should not be Oracle.'
                    );
                }
            }
        }
    }

    @IsTest
    static void selectIdsByProductCodes_includesInactiveProducts() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Map<String, Product2> productByCode = productsByCode();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<Product2> results = Product2Selector.selectIdsByProductCodes(
                new Set<String>{ ACTIVE_CODE, INACTIVE_CODE, 'P2SELTEST-UNKNOWN' }
            );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Map<Id, Product2> resultsById = new Map<Id, Product2>(results);
            Assert.areEqual(2, resultsById.size(), 'Known codes should be returned regardless of status.');
            Assert.isTrue(resultsById.containsKey(productByCode.get(ACTIVE_CODE).Id), 'Active product expected.');
            Assert.isTrue(resultsById.containsKey(productByCode.get(INACTIVE_CODE).Id), 'Inactive product expected.');
        }
    }

    @IsTest
    static void selectActiveIdsByProductCodes_excludesInactiveProducts() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Map<String, Product2> productByCode = productsByCode();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<Product2> results = Product2Selector.selectActiveIdsByProductCodes(
                new Set<String>{ ACTIVE_CODE, PERCENT_CODE, INACTIVE_CODE }
            );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<String> codes = codesOf(results);
            Assert.areEqual(2, results.size(), 'Only the active products should be returned.');
            Assert.isTrue(codes.contains(ACTIVE_CODE), 'Active product should be returned.');
            Assert.isTrue(codes.contains(PERCENT_CODE), 'Active product should be returned.');
            Assert.isFalse(codes.contains(INACTIVE_CODE), 'Inactive product should be excluded.');
            Assert.isTrue(
                new Map<Id, Product2>(results).containsKey(productByCode.get(ACTIVE_CODE).Id),
                'Product Id should be selected.'
            );
        }
    }

    @IsTest
    static void sellingModelQueries_runWithoutSellingModelData() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Map<String, Product2> productByCode = productsByCode();
            Set<Id> productIds = new Set<Id>{ productByCode.get(ACTIVE_CODE).Id, productByCode.get(PERCENT_CODE).Id };
            List<ProductSellingModel> oneTimeModels = [
                SELECT Id
                FROM ProductSellingModel
                WHERE SellingModelType = 'OneTime'
                LIMIT 1
            ];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ProductSellingModelOption> options = Product2Selector.selectSellingModelOptionsByProductIds(productIds);
            Id oneTimeModelId = Product2Selector.selectOneTimeSellingModelId();
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, options.size(), 'Test products have no selling model options.');
            Assert.areEqual(
                oneTimeModels.isEmpty() ? null : oneTimeModels[0].Id,
                oneTimeModelId,
                'Selector should return the OneTime selling model when one exists, otherwise null.'
            );
        }
    }
}