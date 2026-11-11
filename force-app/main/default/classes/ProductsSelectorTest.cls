/**
 * @description Tests for ProductsSelector including Device Evaluation queries (GW-3913 / GW-3096).
 */
@IsTest
private class ProductsSelectorTest {

    @TestSetup
    static void setupTestData() {
        new adb_Product2()
            .name('Products Selector Active')
            .productCode('PS-SEL-001')
            .productType('Category Code')
            .evalCategory('ANY')
            .evalRank('10')
            .persist();
    }

    @IsTest
    static void testSelectMethodsHappyPathAndGuards() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Product2 product = [SELECT Id, Name, ProductCode FROM Product2 LIMIT 1];

            Test.startTest();
            List<Product2> byId = ProductsSelector.selectById(new Set<Id>{ product.Id });
            List<Product2> byName = ProductsSelector.selectByName(new Set<String>{ product.Name });
            List<Product2> byCode = ProductsSelector.selectByProductCode(
                new Set<String>{ product.ProductCode }
            );
            List<Product2> forEval = ProductsSelector.selectForDeviceEvaluationByIds(
                new Set<Id>{ product.Id }
            );
            List<Product2> labels = ProductsSelector.selectLabelsById(product.Id);

            Assert.isTrue(ProductsSelector.selectById(null).isEmpty());
            Assert.isTrue(ProductsSelector.selectById(new Set<Id>()).isEmpty());
            Assert.isTrue(ProductsSelector.selectByName(null).isEmpty());
            Assert.isTrue(ProductsSelector.selectByProductCode(null).isEmpty());
            Assert.isTrue(ProductsSelector.selectForDeviceEvaluationByIds(null).isEmpty());
            Assert.isTrue(ProductsSelector.selectLabelsById(null).isEmpty());
            Test.stopTest();

            Assert.areEqual(1, byId.size());
            Assert.areEqual(1, byName.size());
            Assert.areEqual(1, byCode.size());
            Assert.areEqual(1, forEval.size());
            Assert.areEqual('Category Code', forEval[0].ProductType__c);
            Assert.areEqual(1, labels.size());
            Assert.areEqual(product.ProductCode, labels[0].ProductCode);
        }
    }

    /**
     * @description GW-3400 - Verifies Instrument Evaluation catalog filters and guards.
     */
    @IsTest
    static void testSelectForInstrumentEvaluation_WhenFiltersAndGuards() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            new adb_Product2()
                .name('IE Selector Match')
                .productCode('IE-SEL-A')
                .productType('Service Asset')
                .productLine('Instruments')
                .subProductLine('Stainless')
                .evalDisplayScreen('Y')
                .evalCategory('Forceps')
                .evalRank('10')
                .persist();
            new adb_Product2()
                .name('IE Selector Hidden')
                .productCode('IE-SEL-HIDE')
                .productType('Service Asset')
                .productLine('Instruments')
                .subProductLine('Stainless')
                .evalDisplayScreen('N')
                .evalCategory('Forceps')
                .evalRank('10')
                .persist();
            new adb_Product2()
                .name('IE Selector Other Category')
                .productCode('IE-SEL-B')
                .productType('Service Asset')
                .productLine('Instruments')
                .subProductLine('Stainless')
                .evalDisplayScreen('Y')
                .evalCategory('Scissors')
                .evalRank('20')
                .persist();
            new adb_Product2()
                .name('IE Selector Specialty')
                .productCode('IE-SEL-C')
                .productType('Service Asset')
                .productLine('Instruments')
                .subProductLine('Specialty')
                .evalDisplayScreen('Y')
                .evalCategory('Forceps')
                .evalRank('15')
                .persist();

            Test.startTest();
            List<Product2> allMatching = ProductsSelector.selectForInstrumentEvaluation(
                'Instruments',
                'Stainless'
            );
            List<Product2> forceps = ProductsSelector.selectForInstrumentEvaluationByEvalCategory(
                'Instruments',
                'Stainless',
                'Forceps'
            );
            List<Product2> allSubLines = ProductsSelector.selectForInstrumentEvaluation(
                'Instruments',
                null
            );
            List<Product2> forcepsAllSubLines =
                ProductsSelector.selectForInstrumentEvaluationByEvalCategory(
                    'Instruments',
                    null,
                    'Forceps'
                );
            Test.stopTest();

            Assert.isTrue(ProductsSelector.selectForInstrumentEvaluation(null, 'Stainless').isEmpty());
            Assert.isTrue(
                ProductsSelector.selectForInstrumentEvaluationByEvalCategory(
                        'Instruments',
                        'Stainless',
                        null
                    )
                    .isEmpty()
            );
            Set<String> codes = new Set<String>();
            for (Product2 product : allMatching) {
                codes.add(product.ProductCode);
            }
            Assert.isTrue(codes.contains('IE-SEL-A'));
            Assert.isTrue(codes.contains('IE-SEL-B'));
            Assert.isFalse(codes.contains('IE-SEL-HIDE'));
            Assert.isFalse(codes.contains('IE-SEL-C'), 'Stainless filter should exclude Specialty');
            Assert.areEqual(1, forceps.size());
            Assert.areEqual('IE-SEL-A', forceps[0].ProductCode);

            Set<String> allCodes = new Set<String>();
            for (Product2 product : allSubLines) {
                allCodes.add(product.ProductCode);
            }
            Assert.isTrue(allCodes.contains('IE-SEL-A'));
            Assert.isTrue(allCodes.contains('IE-SEL-B'));
            Assert.isTrue(allCodes.contains('IE-SEL-C'));
            Assert.isFalse(allCodes.contains('IE-SEL-HIDE'));

            Set<String> forcepsCodes = new Set<String>();
            for (Product2 product : forcepsAllSubLines) {
                forcepsCodes.add(product.ProductCode);
            }
            Assert.isTrue(forcepsCodes.contains('IE-SEL-A'));
            Assert.isTrue(forcepsCodes.contains('IE-SEL-C'));
            Assert.isFalse(forcepsCodes.contains('IE-SEL-B'));
        }
    }

    /**
     * @description GW-3400 - Product Line / Sub Product Line matching is case-insensitive and
     *              treats Instruments / INSTRUMENT as equivalent.
     */
    @IsTest
    static void testSelectForInstrumentEvaluation_WhenCasingDiffers_StillMatches() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            new adb_Product2()
                .name('IE Case Match Product')
                .productCode('IE-CASE-01')
                .productType('Service Asset')
                .productLine('INSTRUMENT')
                .subProductLine('SPECIALTY')
                .evalDisplayScreen('Y')
                .evalCategory('LAP')
                .evalRank('10')
                .persist();

            Test.startTest();
            List<Product2> byLine = ProductsSelector.selectForInstrumentEvaluation(
                'Instruments',
                'Specialty'
            );
            List<Product2> byCategory =
                ProductsSelector.selectForInstrumentEvaluationByEvalCategory(
                    'Instruments',
                    'specialty',
                    'lap'
                );
            Test.stopTest();

            Set<String> codes = new Set<String>();
            for (Product2 product : byLine) {
                codes.add(product.ProductCode);
            }
            Assert.isTrue(
                codes.contains('IE-CASE-01'),
                'INSTRUMENT/SPECIALTY should match Instruments/Specialty'
            );
            Assert.areEqual(1, byCategory.size());
            Assert.areEqual('IE-CASE-01', byCategory[0].ProductCode);
        }
    }

    @IsTest
    static void testSelectCreateReturnOrderMethods_happyPathAndGuards() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Product2 defaultProduct = new Product2(
                Name = 'Default Product',
                IsActive = true,
                ProductType__c = 'Service Asset',
                ProductLine__c = 'INSTRUMENT',
                ProductCode = 'CRO-DEF-001',
                Model__c = 'Model-Def'
            );
            Product2 otherProduct = new Product2(
                Name = 'CRO Other Product',
                IsActive = true,
                ProductType__c = 'Category Code',
                ProductLine__c = 'INSTRUMENT',
                ProductCode = 'CRO-OTH-001',
                Model__c = 'Model-Oth'
            );
            insert new List<Product2>{ defaultProduct, otherProduct };

            Test.startTest();
            List<Product2> byDefaultName =
                ProductsSelector.selectDefaultActiveByName('Default Product');
            List<Product2> blankDefault =
                ProductsSelector.selectDefaultActiveByName(' ');
            List<Product2> detailsServiceAsset =
                ProductsSelector.selectActiveDetailsForCreateReturnOrder(defaultProduct.Id, true);
            List<Product2> detailsAnyType =
                ProductsSelector.selectActiveDetailsForCreateReturnOrder(otherProduct.Id, false);
            List<Product2> detailsNull =
                ProductsSelector.selectActiveDetailsForCreateReturnOrder(null, true);
            List<Product2> filtered =
                ProductsSelector.selectForCreateReturnOrderLine(
                    'INSTRUMENT',
                    true,
                    '%CRO-DEF%',
                    50
                );
            List<Product2> routing =
                ProductsSelector.selectForCreateReturnOrderRouting(
                    new Set<Id>{ defaultProduct.Id, otherProduct.Id }
                );
            List<Product2> routingNull =
                ProductsSelector.selectForCreateReturnOrderRouting(null);
            List<Product2> approveReject =
                ProductsSelector.selectForApproveRejectByIds(new Set<Id>{ defaultProduct.Id });
            List<Product2> quoteEmail =
                ProductsSelector.selectForQuoteEmailReplyByIds(new Set<Id>{ defaultProduct.Id });
            Test.stopTest();

            Assert.areEqual(1, byDefaultName.size());
            Assert.areEqual(defaultProduct.Id, byDefaultName[0].Id);
            Assert.isTrue(blankDefault.isEmpty());
            Assert.areEqual(1, detailsServiceAsset.size());
            Assert.areEqual(1, detailsAnyType.size());
            Assert.isTrue(detailsNull.isEmpty());
            Assert.areEqual(1, filtered.size());
            Assert.areEqual(defaultProduct.Id, filtered[0].Id);
            Assert.areEqual(2, routing.size());
            Assert.isTrue(routingNull.isEmpty());
            Assert.areEqual(1, approveReject.size());
            Assert.areEqual(1, quoteEmail.size());
        }
    }
}