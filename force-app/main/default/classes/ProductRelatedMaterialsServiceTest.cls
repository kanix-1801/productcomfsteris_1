/**
 * @description Test class for ProductRelatedMaterialsService.
 *              Covers create, update, delete, and retrieval operations
 *              across positive, negative, and empty-input scenarios.
 */
@IsTest
private class ProductRelatedMaterialsServiceTest {
    private class ThrowingSelector
        implements ProductRelatedMaterialsService.IProductRelatedMaterialsSelector {
        public List<ProductRelatedMaterial> selectById(Set<Id> relatedMaterialIds) {
            ProductRelatedMaterial missing = [
                SELECT Id
                FROM ProductRelatedMaterial
                WHERE Id = null
            ];
            return new List<ProductRelatedMaterial>{ missing };
        }

        public List<ProductRelatedMaterial> selectBomComponentsForDeviceEvaluation(
            Set<Id> parentProductIds,
            Set<String> componentTypes
        ) {
            ProductRelatedMaterial missing = [
                SELECT Id
                FROM ProductRelatedMaterial
                WHERE Id = null
            ];
            return new List<ProductRelatedMaterial>{ missing };
        }
    }

    @TestSetup
    static void setupTestData() {
        // Build a parent Product2, a component Product2, a ServiceBOM, and 10 related materials
        Product2 parentProduct = new Product2(Name = 'Parent Product', IsActive = true);
        Product2 componentProduct = new Product2(Name = 'Component Product', IsActive = true);
        insert new List<Product2>{ parentProduct, componentProduct };
        ServiceBOM__c serviceBom = new ServiceBOM__c(Name = 'Parent Service BOM');
        insert serviceBom;
        List<ProductRelatedMaterial> materials = new List<ProductRelatedMaterial>();
        for (Integer i = 0; i < 10; i++) {
            materials.add(
                new ProductRelatedMaterial(
                    Name = 'PRM ' + i,
                    ProductId = parentProduct.Id,
                    ProductComponentId = componentProduct.Id,
                    ServiceBOM__c = serviceBom.Id,
                    QuantityPerProductUnit = 5
                )
            );
        }
        insert materials;
    }

    // ── createProductRelatedMaterials ────────────────────────────────────────

    @IsTest
    static void shouldCreateProductRelatedMaterials_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            ProductRelatedMaterial existing = [SELECT ProductId, ProductComponentId, ServiceBOM__c FROM ProductRelatedMaterial LIMIT 1];
            List<ProductRelatedMaterial> relatedMaterialList = new List<ProductRelatedMaterial>{
                new ProductRelatedMaterial(Name = 'Test PRM 1', ProductId = existing.ProductId, ProductComponentId = existing.ProductComponentId, ServiceBOM__c = existing.ServiceBOM__c, QuantityPerProductUnit = 2),
                new ProductRelatedMaterial(Name = 'Test PRM 2', ProductId = existing.ProductId, ProductComponentId = existing.ProductComponentId, ServiceBOM__c = existing.ServiceBOM__c, QuantityPerProductUnit = 2)
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRelatedMaterialsService.createProductRelatedMaterials(relatedMaterialList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIds = new Map<Id, ProductRelatedMaterial>(relatedMaterialList).keySet();
            List<ProductRelatedMaterial> insertedList = [SELECT Id FROM ProductRelatedMaterial WHERE Id IN :insertedIds];
            Assert.areEqual(2, insertedList.size(), 'createProductRelatedMaterials should insert all 2 records');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateProductRelatedMaterialsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM ProductRelatedMaterial];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRelatedMaterialsService.createProductRelatedMaterials(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM ProductRelatedMaterial];
            Assert.areEqual(countBefore, countAfter, 'createProductRelatedMaterials with null should not insert any records');
        }
    }

    // ── updateProductRelatedMaterials ────────────────────────────────────────

    @IsTest
    static void shouldUpdateProductRelatedMaterials_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ProductRelatedMaterial> relatedMaterialList = [SELECT Id, QuantityPerProductUnit FROM ProductRelatedMaterial LIMIT 3];
            for (ProductRelatedMaterial relatedMaterial : relatedMaterialList) {
                relatedMaterial.QuantityPerProductUnit = 99;
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRelatedMaterialsService.updateProductRelatedMaterials(relatedMaterialList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIds = new Map<Id, ProductRelatedMaterial>(relatedMaterialList).keySet();
            List<ProductRelatedMaterial> updatedList = [SELECT Id, QuantityPerProductUnit FROM ProductRelatedMaterial WHERE Id IN :updatedIds];
            for (ProductRelatedMaterial relatedMaterial : updatedList) {
                Assert.areEqual(99, relatedMaterial.QuantityPerProductUnit, 'Quantity Per Product Unit should be updated');
            }
        }
    }

    @IsTest
    static void shouldDoNothing_WhenUpdateProductRelatedMaterialsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRelatedMaterialsService.updateProductRelatedMaterials(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(true, 'updateProductRelatedMaterials with null should complete without error');
        }
    }

    // ── deleteProductRelatedMaterials ────────────────────────────────────────

    @IsTest
    static void shouldDeleteProductRelatedMaterials_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> relatedMaterialIdSet = new Map<Id, ProductRelatedMaterial>([SELECT Id FROM ProductRelatedMaterial LIMIT 3]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRelatedMaterialsService.deleteProductRelatedMaterials(relatedMaterialIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM ProductRelatedMaterial WHERE Id IN :relatedMaterialIdSet];
            Assert.areEqual(0, remainingCount, 'deleteProductRelatedMaterials should delete all specified records');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteProductRelatedMaterialsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM ProductRelatedMaterial];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRelatedMaterialsService.deleteProductRelatedMaterials(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM ProductRelatedMaterial];
            Assert.areEqual(countBefore, countAfter, 'deleteProductRelatedMaterials with null should not delete any records');
        }
    }

    // ── getProductRelatedMaterialsById ───────────────────────────────────────

    @IsTest
    static void shouldReturnProductRelatedMaterials_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> relatedMaterialIdSet = new Map<Id, ProductRelatedMaterial>([SELECT Id FROM ProductRelatedMaterial]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ProductRelatedMaterial> resultList = ProductRelatedMaterialsService.getProductRelatedMaterialsById(relatedMaterialIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(10, resultList.size(), 'getProductRelatedMaterialsById should return all 10 records');
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
            List<ProductRelatedMaterial> resultList = ProductRelatedMaterialsService.getProductRelatedMaterialsById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getProductRelatedMaterialsById with null should return an empty list');
        }
    }

    // ── buildRepairCodeCatalogForDeviceEvaluation (GW-3913 / GW-3096) ─────────

    @IsTest
    static void testBuildRepairCodeCatalogForDeviceEvaluation() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Product2 assetProduct = new Product2(
                Name = 'PRM DE Asset Product',
                ProductCode = 'PRM-DE-ASSET',
                ProductType__c = 'Service Asset',
                IsActive = true
            );
            Product2 categoryCode = new Product2(
                Name = 'PRM DE Category Code',
                ProductCode = 'PRM-DE-CT',
                ProductType__c = 'Category Code',
                EvalDisplayScreen__c = 'Y',
                IsActive = true
            );
            Product2 hiddenCategory = new Product2(
                Name = 'PRM DE Hidden Category',
                ProductCode = 'PRM-DE-HIDE',
                ProductType__c = 'Category Code',
                EvalDisplayScreen__c = 'N',
                IsActive = true
            );
            Product2 observationCode = new Product2(
                Name = 'PRM DE Observation Code',
                ProductCode = 'PRM-DE-OC',
                ProductType__c = 'Observation Code',
                EvalDisplayScreen__c = 'Y',
                IsActive = true
            );
            Product2 optionClass = new Product2(
                Name = 'PRM DE Option Class',
                ProductCode = 'PRM-DE-OPT',
                ProductType__c = 'Option Class',
                IsActive = true
            );
            Product2 nestedService = new Product2(
                Name = 'PRM DE Nested Service',
                ProductCode = 'PRM-DE-SC',
                ProductType__c = 'Service Code',
                EvalDisplayScreen__c = 'Y',
                IsActive = true
            );
            insert new List<Product2>{
                assetProduct,
                categoryCode,
                hiddenCategory,
                observationCode,
                optionClass,
                nestedService
            };

            insert new List<ProductRelatedMaterial>{
                new ProductRelatedMaterial(
                    Name = 'PRM-DE-BOM-CT',
                    ProductId = assetProduct.Id,
                    ProductComponentId = categoryCode.Id,
                    QuantityPerProductUnit = 1,
                    ComponentSequence__c = 10
                ),
                new ProductRelatedMaterial(
                    Name = 'PRM-DE-BOM-HIDE',
                    ProductId = assetProduct.Id,
                    ProductComponentId = hiddenCategory.Id,
                    QuantityPerProductUnit = 1,
                    ComponentSequence__c = 5
                ),
                new ProductRelatedMaterial(
                    Name = 'PRM-DE-BOM-OC',
                    ProductId = assetProduct.Id,
                    ProductComponentId = observationCode.Id,
                    QuantityPerProductUnit = 1,
                    ComponentSequence__c = 20
                ),
                new ProductRelatedMaterial(
                    Name = 'PRM-DE-BOM-OPT',
                    ProductId = assetProduct.Id,
                    ProductComponentId = optionClass.Id,
                    QuantityPerProductUnit = 1,
                    ComponentSequence__c = 15
                ),
                new ProductRelatedMaterial(
                    Name = 'PRM-DE-BOM-NEST',
                    ProductId = optionClass.Id,
                    ProductComponentId = nestedService.Id,
                    QuantityPerProductUnit = 1,
                    ComponentSequence__c = 1
                )
            };

            Test.startTest();
            ProductRelatedMaterialsService.RepairCodeCatalog catalog =
                ProductRelatedMaterialsService.buildRepairCodeCatalogForDeviceEvaluation(
                    assetProduct.Id
                );
            ProductRelatedMaterialsService.RepairCodeCatalog emptyCatalog =
                ProductRelatedMaterialsService.buildRepairCodeCatalogForDeviceEvaluation(null);
            Test.stopTest();

            Assert.isTrue(
                catalog.categoryCodeIds.contains(categoryCode.Id),
                'EvalDisplay Y Category Code should be selectable'
            );
            Assert.isFalse(
                catalog.categoryCodeIds.contains(hiddenCategory.Id),
                'EvalDisplay N should be excluded'
            );
            Assert.isTrue(
                catalog.observationCodeIds.contains(observationCode.Id),
                'Observation Code should be selectable'
            );
            Assert.isTrue(
                catalog.serviceCodeIds.contains(nestedService.Id),
                'Nested Option Class Service Code should be selectable'
            );
            Assert.areEqual(3, catalog.totalSelectableCount, 'Three selectable codes expected');
            Assert.areEqual(
                10,
                catalog.componentSequenceByProductId.get(categoryCode.Id),
                'Should track min Component Sequence'
            );
            Assert.areEqual(0, emptyCatalog.totalSelectableCount, 'Null asset product yields empty');
        }
    }

    /**
     * @description GW-3400 - Verifies Instrument Evaluation catalog drops observation codes.
     */
    @IsTest
    static void testBuildInstrumentEvaluationCatalogAndCodeCards() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Product2 assetProduct = new Product2(
                Name = 'PRM IE Asset Product',
                ProductCode = 'PRM-IE-ASSET',
                ProductType__c = 'Service Asset',
                IsActive = true
            );
            Product2 categoryCode = new Product2(
                Name = 'PRM IE Category Code',
                ProductCode = 'PRM-IE-CT',
                ProductType__c = 'Category Code',
                EvalDisplayScreen__c = 'Y',
                IsActive = true
            );
            Product2 observationCode = new Product2(
                Name = 'PRM IE Observation Code',
                ProductCode = 'PRM-IE-OC',
                ProductType__c = 'Observation Code',
                EvalDisplayScreen__c = 'Y',
                IsActive = true
            );
            Product2 serviceCode = new Product2(
                Name = 'PRM IE Service Code',
                ProductCode = 'PRM-IE-SC',
                ProductType__c = 'Service Code',
                EvalDisplayScreen__c = 'Y',
                IsActive = true
            );
            insert new List<Product2>{ assetProduct, categoryCode, observationCode, serviceCode };
            insert new List<ProductRelatedMaterial>{
                new ProductRelatedMaterial(
                    Name = 'PRM-IE-BOM-CT',
                    ProductId = assetProduct.Id,
                    ProductComponentId = categoryCode.Id,
                    QuantityPerProductUnit = 1,
                    ComponentSequence__c = 1
                ),
                new ProductRelatedMaterial(
                    Name = 'PRM-IE-BOM-OC',
                    ProductId = assetProduct.Id,
                    ProductComponentId = observationCode.Id,
                    QuantityPerProductUnit = 1,
                    ComponentSequence__c = 2
                ),
                new ProductRelatedMaterial(
                    Name = 'PRM-IE-BOM-SC',
                    ProductId = assetProduct.Id,
                    ProductComponentId = serviceCode.Id,
                    QuantityPerProductUnit = 1,
                    ComponentSequence__c = 3
                )
            };

            Test.startTest();
            ProductRelatedMaterialsService.RepairCodeCatalog catalog =
                ProductRelatedMaterialsService.buildInstrumentEvaluationCatalog(assetProduct.Id);
            ProductRelatedMaterialsService.InstrumentEvaluationCodeCards cards =
                ProductRelatedMaterialsService.buildInstrumentEvaluationCodeCards(assetProduct.Id);
            ProductRelatedMaterialsService.RepairCodeCatalog emptyCatalog =
                ProductRelatedMaterialsService.buildInstrumentEvaluationCatalog(null);
            Test.stopTest();

            Assert.isTrue(catalog.categoryCodeIds.contains(categoryCode.Id));
            Assert.isTrue(catalog.serviceCodeIds.contains(serviceCode.Id));
            Assert.isTrue(
                catalog.observationCodeIds.isEmpty(),
                'Instrument Evaluation catalog should omit observation codes'
            );
            Assert.areEqual(1, cards.categoryCodes.size());
            Assert.areEqual(1, cards.serviceCodes.size());
            Assert.areEqual(0, emptyCatalog.totalSelectableCount);
        }
    }

    @IsTest
    static void testBuildEvalCategoryTabsAndPricingCardsForDeviceEvaluation() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Product2 categoryCode = new Product2(
                Name = 'PRM Card Category',
                ProductCode = 'PRM-CARD-CT',
                ProductType__c = 'Category Code',
                EvalDisplayScreen__c = 'Y',
                IsActive = true
            );
            Product2 observationCode = new Product2(
                Name = 'PRM Card Observation',
                ProductCode = 'PRM-CARD-OC',
                ProductType__c = 'Observation Code',
                EvalDisplayScreen__c = 'Y',
                EvalCategory__c = 'DISTAL TIP',
                EvalRank__c = '20',
                Condition__c = 'Ok',
                IsActive = true
            );
            Product2 serviceCode = new Product2(
                Name = 'PRM Card Service',
                ProductCode = 'PRM-CARD-SC',
                ProductType__c = 'Service Code',
                EvalDisplayScreen__c = 'Y',
                EvalCategory__c = 'DISTAL TIP',
                EvalRank__c = '10',
                IsActive = true
            );
            insert new List<Product2>{ categoryCode, observationCode, serviceCode };

            ProductRelatedMaterialsService.RepairCodeCatalog catalog =
                new ProductRelatedMaterialsService.RepairCodeCatalog();
            catalog.categoryCodeIds.add(categoryCode.Id);
            catalog.observationCodeIds.add(observationCode.Id);
            catalog.serviceCodeIds.add(serviceCode.Id);
            catalog.componentSequenceByProductId.put(categoryCode.Id, 5);
            catalog.componentSequenceByProductId.put(observationCode.Id, 10);
            catalog.componentSequenceByProductId.put(serviceCode.Id, 15);

            Map<Id, Product2> productsById = new Map<Id, Product2>{
                categoryCode.Id => categoryCode,
                observationCode.Id => observationCode,
                serviceCode.Id => serviceCode
            };
            Set<Id> selectedIds = new Set<Id>{ observationCode.Id };

            Test.startTest();
            List<ProductRelatedMaterialsService.RepairCodeCardData> pricingCards =
                ProductRelatedMaterialsService.buildSortedPricingCardsForDeviceEvaluation(
                    catalog,
                    productsById,
                    selectedIds
                );
            List<ProductRelatedMaterialsService.EvalCategoryTabData> tabs =
                ProductRelatedMaterialsService.buildEvalCategoryTabsForDeviceEvaluation(
                    catalog,
                    productsById,
                    selectedIds
                );
            List<ProductRelatedMaterialsService.RepairCodeCardData> nullCatalogCards =
                ProductRelatedMaterialsService.buildSortedPricingCardsForDeviceEvaluation(
                    null,
                    productsById,
                    selectedIds
                );
            List<ProductRelatedMaterialsService.EvalCategoryTabData> nullTabs =
                ProductRelatedMaterialsService.buildEvalCategoryTabsForDeviceEvaluation(
                    null,
                    productsById,
                    selectedIds
                );
            Test.stopTest();

            Assert.areEqual(1, pricingCards.size(), 'One pricing card expected');
            Assert.areEqual(categoryCode.Id, pricingCards[0].productId);
            Assert.areEqual(1, tabs.size(), 'One eval category tab expected');
            Assert.areEqual('DISTAL TIP', tabs[0].categoryName);
            Assert.areEqual(1, tabs[0].observationCodes.size());
            Assert.isTrue(tabs[0].observationCodes[0].selected, 'Selected OC should be marked');
            Assert.areEqual(1, tabs[0].serviceCodes.size());
            Assert.areEqual('10', tabs[0].minEvalRank, 'Min rank should come from Service Code');
            Assert.isTrue(nullCatalogCards.isEmpty());
            Assert.isTrue(nullTabs.isEmpty());
        }
    }

    @IsTest
    static void testProductRelatedMaterialsSelectorQueryMethods() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            ProductRelatedMaterial existing = [
                SELECT Id, ProductId, ServiceBOM__c
                FROM ProductRelatedMaterial
                LIMIT 1
            ];

            Test.startTest();
            List<ProductRelatedMaterial> byId = ProductRelatedMaterialsSelector.selectById(
                new Set<Id>{ existing.Id }
            );
            List<ProductRelatedMaterial> byProduct =
                ProductRelatedMaterialsSelector.selectByProductId(new Set<Id>{ existing.ProductId });
            List<ProductRelatedMaterial> byBom =
                ProductRelatedMaterialsSelector.selectByServiceBomId(
                    new Set<Id>{ existing.ServiceBOM__c }
                );
            Assert.isTrue(ProductRelatedMaterialsSelector.selectById(null).isEmpty());
            Assert.isTrue(ProductRelatedMaterialsSelector.selectByProductId(null).isEmpty());
            Assert.isTrue(ProductRelatedMaterialsSelector.selectByServiceBomId(null).isEmpty());
            Assert.isTrue(
                ProductRelatedMaterialsSelector.selectBomComponentsForDeviceEvaluation(
                        null,
                        null
                    )
                    .isEmpty()
            );
            Test.stopTest();

            Assert.areEqual(1, byId.size());
            Assert.isFalse(byProduct.isEmpty());
            Assert.isFalse(byBom.isEmpty());
        }
    }

    @IsTest
    static void testBuildEvalCategoryTabs_invalidRankSortsLast() {
        Product2 ranked = new Product2(
            Name = 'Ranked Observation',
            ProductCode = 'PRM-RANKED',
            ProductType__c = 'Observation Code',
            EvalCategory__c = 'RANKED',
            EvalRank__c = '2',
            IsActive = true
        );
        Product2 invalid = new Product2(
            Name = 'Invalid Rank Observation',
            ProductCode = 'PRM-INVALID-RANK',
            ProductType__c = 'Observation Code',
            EvalCategory__c = 'INVALID',
            EvalRank__c = 'not-a-number',
            IsActive = true
        );
        insert new List<Product2>{ ranked, invalid };
        ProductRelatedMaterialsService.RepairCodeCatalog catalog =
            new ProductRelatedMaterialsService.RepairCodeCatalog();
        catalog.observationCodeIds.add(ranked.Id);
        catalog.observationCodeIds.add(invalid.Id);

        List<ProductRelatedMaterialsService.EvalCategoryTabData> tabs =
            ProductRelatedMaterialsService.buildEvalCategoryTabsForDeviceEvaluation(
                catalog,
                new Map<Id, Product2>{ ranked.Id => ranked, invalid.Id => invalid },
                null
            );

        Assert.areEqual(2, tabs.size());
        Assert.areEqual('RANKED', tabs[0].categoryName, 'Numeric rank should sort first');
        Assert.areEqual('INVALID', tabs[1].categoryName, 'Invalid rank should sort last');
        Assert.isNull(tabs[1].minEvalRank, 'Invalid rank should resolve to null');
    }

    @IsTest
    static void testResolveComponentType_usesProductComponentFallback() {
        ProductRelatedMaterial bomRow = new ProductRelatedMaterial();
        bomRow.ProductComponent = new Product2(ProductType__c = 'Service Code');

        Assert.areEqual(
            'Service Code',
            ProductRelatedMaterialsService.resolveComponentType(bomRow),
            'Product type should be used when ComponentType is blank'
        );
    }

    @IsTest
    static void testCreateProductRelatedMaterials_dmlFailureIsWrapped() {
        Boolean threw = false;
        Test.startTest();
        try {
            ProductRelatedMaterialsService.createProductRelatedMaterials(
                new List<ProductRelatedMaterial>{ new ProductRelatedMaterial() }
            );
        } catch (
            ProductRelatedMaterialsService.ProductRelatedMaterialsServiceException e
        ) {
            threw = true;
            Assert.isTrue(
                e.getCause() instanceof DmlException,
                'The service exception should preserve the DML cause'
            );
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Missing required relationships should fail creation');
    }

    @IsTest
    static void testUpdateProductRelatedMaterials_deletedRecordFailureIsWrapped() {
        ProductRelatedMaterial deletedMaterial = [
            SELECT Id, QuantityPerProductUnit
            FROM ProductRelatedMaterial
            LIMIT 1
        ];
        delete deletedMaterial;
        deletedMaterial.QuantityPerProductUnit = 999;

        Boolean threw = false;
        Test.startTest();
        try {
            ProductRelatedMaterialsService.updateProductRelatedMaterials(
                new List<ProductRelatedMaterial>{ deletedMaterial }
            );
        } catch (
            ProductRelatedMaterialsService.ProductRelatedMaterialsServiceException e
        ) {
            threw = true;
            Assert.isTrue(
                e.getCause() instanceof DmlException,
                'The service exception should preserve the DML cause'
            );
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Updating a deleted related material should fail');
    }

    @IsTest
    static void testSelectorFailuresAreWrapped() {
        ProductRelatedMaterial relatedMaterial = [
            SELECT Id, ProductId
            FROM ProductRelatedMaterial
            LIMIT 1
        ];
        ProductRelatedMaterialsService.selectorOverride = new ThrowingSelector();
        try {
            Boolean getThrew = false;
            Boolean deleteThrew = false;
            Boolean catalogThrew = false;
            try {
                ProductRelatedMaterialsService.getProductRelatedMaterialsById(
                    new Set<Id>{ relatedMaterial.Id }
                );
            } catch (
                ProductRelatedMaterialsService.ProductRelatedMaterialsServiceException e
            ) {
                getThrew = true;
            }
            try {
                ProductRelatedMaterialsService.deleteProductRelatedMaterials(
                    new Set<Id>{ relatedMaterial.Id }
                );
            } catch (
                ProductRelatedMaterialsService.ProductRelatedMaterialsServiceException e
            ) {
                deleteThrew = true;
            }
            try {
                ProductRelatedMaterialsService.buildRepairCodeCatalogForDeviceEvaluation(
                    relatedMaterial.ProductId
                );
            } catch (
                ProductRelatedMaterialsService.ProductRelatedMaterialsServiceException e
            ) {
                catalogThrew = true;
            }

            Assert.isTrue(getThrew, 'Get should wrap selector failures');
            Assert.isTrue(deleteThrew, 'Delete should wrap selector failures');
            Assert.isTrue(catalogThrew, 'Catalog should wrap selector failures');
        } finally {
            ProductRelatedMaterialsService.selectorOverride = null;
        }
    }
}