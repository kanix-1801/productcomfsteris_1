/**
 * @description Test class for PricebookEntriesSelector (GW-3913 / GW-3096).
 */
@IsTest
private class PricebookEntriesSelectorTest {

    @TestSetup
    static void setupTestData() {
        adb_Product2 productBuilder = new adb_Product2()
            .name('PBE Selector Product')
            .productCode('PBE-SEL-001');
        new adb_PricebookEntry()
            .product(productBuilder)
            .unitPrice(10)
            .persist();
    }

    @IsTest
    static void testSelectActiveByPricebookProductAndCurrencyReturnsRows() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Product2 product = [SELECT Id FROM Product2 WHERE ProductCode = 'PBE-SEL-001' LIMIT 1];
            PricebookEntry entry = [
                SELECT Id, Pricebook2Id, Product2Id, CurrencyIsoCode
                FROM PricebookEntry
                WHERE Product2Id = :product.Id
                LIMIT 1
            ];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<PricebookEntry> results =
                PricebookEntriesSelector.selectActiveByPricebookProductAndCurrency(
                    entry.Pricebook2Id,
                    new Set<Id>{ product.Id },
                    entry.CurrencyIsoCode
                );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(1, results.size(), 'Should return the active PricebookEntry');
            Assert.areEqual(entry.Id, results[0].Id);
            Assert.areEqual(product.Id, results[0].Product2Id);
        }
    }

    @IsTest
    static void testSelectActiveByPricebookProductAndCurrencyNullGuards() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Product2 product = [SELECT Id FROM Product2 WHERE ProductCode = 'PBE-SEL-001' LIMIT 1];
            Id pricebookId = Test.getStandardPricebookId();

            Test.startTest();
            List<PricebookEntry> nullPricebook =
                PricebookEntriesSelector.selectActiveByPricebookProductAndCurrency(
                    null,
                    new Set<Id>{ product.Id },
                    'USD'
                );
            List<PricebookEntry> nullProducts =
                PricebookEntriesSelector.selectActiveByPricebookProductAndCurrency(
                    pricebookId,
                    null,
                    'USD'
                );
            List<PricebookEntry> emptyProducts =
                PricebookEntriesSelector.selectActiveByPricebookProductAndCurrency(
                    pricebookId,
                    new Set<Id>(),
                    'USD'
                );
            Test.stopTest();

            Assert.isTrue(nullPricebook.isEmpty(), 'Null pricebook should return empty');
            Assert.isTrue(nullProducts.isEmpty(), 'Null products should return empty');
            Assert.isTrue(emptyProducts.isEmpty(), 'Empty products should return empty');
        }
    }

    /**
     * @description GW-5102 - With-product variant returns Product fields for quote email / inspection fee.
     */
    @IsTest
    static void testSelectActiveWithProductByPricebookProductAndCurrencyReturnsRows() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Product2 product = [
                SELECT Id, Name, ProductCode
                FROM Product2
                WHERE ProductCode = 'PBE-SEL-001'
                LIMIT 1
            ];
            PricebookEntry entry = [
                SELECT Id, Pricebook2Id, Product2Id, CurrencyIsoCode
                FROM PricebookEntry
                WHERE Product2Id = :product.Id
                LIMIT 1
            ];

            Test.startTest();
            List<PricebookEntry> results =
                PricebookEntriesSelector.selectActiveWithProductByPricebookProductAndCurrency(
                    entry.Pricebook2Id,
                    new Set<Id>{ product.Id },
                    entry.CurrencyIsoCode
                );
            Test.stopTest();

            Assert.areEqual(1, results.size(), 'Should return the active PricebookEntry');
            Assert.areEqual(entry.Id, results[0].Id);
            Assert.areEqual(product.Id, results[0].Product2Id);
            Assert.areEqual(product.Name, results[0].Product2.Name);
            Assert.areEqual(product.ProductCode, results[0].Product2.ProductCode);
        }
    }

    @IsTest
    static void testSelectActiveWithProductByPricebookProductAndCurrencyNullGuards() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Product2 product = [SELECT Id FROM Product2 WHERE ProductCode = 'PBE-SEL-001' LIMIT 1];
            Id pricebookId = Test.getStandardPricebookId();

            Test.startTest();
            Assert.isTrue(
                PricebookEntriesSelector.selectActiveWithProductByPricebookProductAndCurrency(
                        null,
                        new Set<Id>{ product.Id },
                        'USD'
                    )
                    .isEmpty(),
                'Null pricebook should return empty'
            );
            Assert.isTrue(
                PricebookEntriesSelector.selectActiveWithProductByPricebookProductAndCurrency(
                        pricebookId,
                        null,
                        'USD'
                    )
                    .isEmpty(),
                'Null products should return empty'
            );
            Assert.isTrue(
                PricebookEntriesSelector.selectActiveWithProductByPricebookProductAndCurrency(
                        pricebookId,
                        new Set<Id>(),
                        'USD'
                    )
                    .isEmpty(),
                'Empty products should return empty'
            );
            Test.stopTest();
        }
    }
}