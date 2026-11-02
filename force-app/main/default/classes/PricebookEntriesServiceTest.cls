/**
 * @description Test class for PricebookEntriesService (GW-3913 / GW-3096).
 */
@IsTest
private class PricebookEntriesServiceTest {
    private class SelectorException extends Exception {
    }

    private class ThrowingSelector implements PricebookEntriesService.IPricebookEntriesSelector {
        public List<PricebookEntry> selectActiveByPricebookProductAndCurrency(
            Id pricebookId,
            Set<Id> productIds,
            String currencyIsoCode
        ) {
            throw new SelectorException('selector failed');
        }
    }

    @TestSetup
    static void setupTestData() {
        Product2 product = new Product2(
            Name = 'PBE Service Product',
            ProductCode = 'PBE-SVC-001',
            IsActive = true
        );
        insert product;
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 25,
            IsActive = true
        );
    }

    @IsTest
    static void testGetPricebookEntryIdsByProductIdReturnsMap() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Product2 product = [SELECT Id FROM Product2 WHERE ProductCode = 'PBE-SVC-001' LIMIT 1];
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
            Map<Id, Id> results = PricebookEntriesService.getPricebookEntryIdsByProductId(
                entry.Pricebook2Id,
                new Set<Id>{ product.Id },
                entry.CurrencyIsoCode
            );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(1, results.size(), 'Should map one Product to its PricebookEntry');
            Assert.areEqual(entry.Id, results.get(product.Id));
        }
    }

    @IsTest
    static void testGetPricebookEntryIdsByProductIdNullGuards() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Product2 product = [SELECT Id FROM Product2 WHERE ProductCode = 'PBE-SVC-001' LIMIT 1];
            Id pricebookId = Test.getStandardPricebookId();

            Test.startTest();
            Map<Id, Id> nullPricebook = PricebookEntriesService.getPricebookEntryIdsByProductId(
                null,
                new Set<Id>{ product.Id },
                'USD'
            );
            Map<Id, Id> nullProducts = PricebookEntriesService.getPricebookEntryIdsByProductId(
                pricebookId,
                null,
                'USD'
            );
            Map<Id, Id> emptyProducts = PricebookEntriesService.getPricebookEntryIdsByProductId(
                pricebookId,
                new Set<Id>(),
                'USD'
            );
            Test.stopTest();

            Assert.isTrue(nullPricebook.isEmpty(), 'Null pricebook should return empty map');
            Assert.isTrue(nullProducts.isEmpty(), 'Null products should return empty map');
            Assert.isTrue(emptyProducts.isEmpty(), 'Empty products should return empty map');
        }
    }

    @IsTest
    static void testGetPricebookEntryIdsByProductId_selectorThrows() {
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntriesService.selectorOverride = new ThrowingSelector();
        try {
            Boolean threw = false;
            try {
                PricebookEntriesService.getPricebookEntryIdsByProductId(
                    Test.getStandardPricebookId(),
                    new Set<Id>{ product.Id },
                    'USD'
                );
            } catch (PricebookEntriesService.PricebookEntriesServiceException e) {
                threw = true;
                Assert.isNotNull(e.getCause(), 'Wrapped exception should retain its cause');
            }
            Assert.isTrue(threw, 'Selector failures should be wrapped');
        } finally {
            PricebookEntriesService.selectorOverride = null;
        }
    }
}