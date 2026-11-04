/**
 * @author Sagar Anand
 * @date 2026-10-28
 * @description GW-6095 - Tests for the Component Tag lookup in WorkOrderLineItemsService and
 *              WoDebriefAllowedUnitController (Work Order Review - ES parts consumption).
 *              Test data is inserted in SYSTEM_MODE because API 67.0 DML runs in user mode.
 * @group Work Order Debrief
 * @see WorkOrderLineItemsService
 * @see WoDebriefAllowedUnitController
 */
@IsTest
private class WorkOrderLineItemsComponentTagTest {
    private static final String WO_WITH_ASSET = 'CT Asset WO';
    private static final String WO_WITHOUT_ASSET = 'CT No Asset WO';
    private static final String CODE_MULTI_TAG = 'CT-MULTI-1';
    private static final String CODE_SINGLE_TAG = 'CT-SINGLE-1';
    private static final String CODE_NO_TAG = 'CT-NOTAG-1';
    private static final String CODE_NOT_ALLOWED = 'CT-DENY-1';
    private static final String CODE_BULK_PREFIX = 'CT-BULK-';
    private static final Integer BULK_SIZE = 200;

    /**
     * @description Builds an Asset with a Service BOM whose BOM Components carry Component Tags:
     *              multi-tag part (SV11 + SV12 on one BOM Component, SV13 on a second one),
     *              single-tag part (SV21), allowed part without tags, a part not on the BOM,
     *              and 200 bulk parts with one tag each.
     */
    @TestSetup
    static void setup() {
        String unique = String.valueOf(Crypto.getRandomInteger());

        Account account = new Account(Name = 'CT Test Account', SourceSystemID__c = 'ORACLE-CT-' + unique);
        Database.insert(account, AccessLevel.SYSTEM_MODE);

        ServiceBOM__c serviceBom = new ServiceBOM__c(Name = 'CT Test SBOM ' + unique, Type__c = 'ES Asset BOM');
        Database.insert(serviceBom, AccessLevel.SYSTEM_MODE);

        Product2 assetProduct = buildProduct('CT Asset Product', null, 'Service Asset');
        Product2 secondParentProduct = buildProduct('CT Second Parent Product', null, 'Service Asset');
        Product2 multiTagPart = buildProduct('CT Multi Tag Part', CODE_MULTI_TAG, 'Part');
        Product2 singleTagPart = buildProduct('CT Single Tag Part', CODE_SINGLE_TAG, 'Part');
        Product2 noTagPart = buildProduct('CT No Tag Part', CODE_NO_TAG, 'Part');
        Product2 notAllowedPart = buildProduct('CT Not Allowed Part', CODE_NOT_ALLOWED, 'Part');
        List<Product2> products = new List<Product2>{
            assetProduct,
            secondParentProduct,
            multiTagPart,
            singleTagPart,
            noTagPart,
            notAllowedPart
        };
        List<Product2> bulkParts = new List<Product2>();
        for (Integer i = 0; i < BULK_SIZE; i++) {
            bulkParts.add(buildProduct('CT Bulk Part ' + i, CODE_BULK_PREFIX + i, 'Part'));
        }
        products.addAll(bulkParts);
        Database.insert(products, AccessLevel.SYSTEM_MODE);

        ProductRelatedMaterial multiTagComponent = buildBomComponent(serviceBom, assetProduct, multiTagPart);
        ProductRelatedMaterial multiTagSecondComponent = buildBomComponent(
            serviceBom,
            secondParentProduct,
            multiTagPart
        );
        ProductRelatedMaterial singleTagComponent = buildBomComponent(serviceBom, assetProduct, singleTagPart);
        ProductRelatedMaterial noTagComponent = buildBomComponent(serviceBom, assetProduct, noTagPart);
        List<ProductRelatedMaterial> bomComponents = new List<ProductRelatedMaterial>{
            multiTagComponent,
            multiTagSecondComponent,
            singleTagComponent,
            noTagComponent
        };
        List<ProductRelatedMaterial> bulkComponents = new List<ProductRelatedMaterial>();
        for (Product2 bulkPart : bulkParts) {
            bulkComponents.add(buildBomComponent(serviceBom, assetProduct, bulkPart));
        }
        bomComponents.addAll(bulkComponents);
        Database.insert(bomComponents, AccessLevel.SYSTEM_MODE);

        PartTag__c partTag = new PartTag__c(Name = 'CT Part Tag', TagDescription__c = 'CT Part Tag');
        Database.insert(partTag, AccessLevel.SYSTEM_MODE);

        // Inserted out of Name order to prove the options come back sorted by Name.
        List<ComponentTag__c> componentTags = new List<ComponentTag__c>{
            buildComponentTag('SV12', multiTagComponent, partTag),
            buildComponentTag('SV11', multiTagComponent, partTag),
            buildComponentTag('SV13', multiTagSecondComponent, partTag),
            buildComponentTag('SV21', singleTagComponent, partTag)
        };
        for (Integer i = 0; i < bulkComponents.size(); i++) {
            componentTags.add(buildComponentTag('CT-BULK-TAG-' + i, bulkComponents[i], partTag));
        }
        Database.insert(componentTags, AccessLevel.SYSTEM_MODE);

        Asset asset = new Asset(
            Name = 'CT Test Asset',
            AccountId = account.Id,
            Product2Id = assetProduct.Id,
            ServiceBOM__c = serviceBom.Id
        );
        Database.insert(asset, AccessLevel.SYSTEM_MODE);

        Database.insert(
            new List<WorkOrder>{
                new WorkOrder(AccountId = account.Id, Subject = WO_WITH_ASSET, AssetId = asset.Id),
                new WorkOrder(AccountId = account.Id, Subject = WO_WITHOUT_ASSET)
            },
            AccessLevel.SYSTEM_MODE
        );

        Schema.Location location = new Schema.Location(
            Name = 'CT Loc ' + unique,
            LocationType = 'Warehouse',
            IsInventoryLocation = true,
            IsMobile = true
        );
        Database.insert(location, AccessLevel.SYSTEM_MODE);

        Database.insert(
            new List<ProductItem>{
                new ProductItem(Product2Id = multiTagPart.Id, LocationId = location.Id, QuantityOnHand = 3),
                new ProductItem(Product2Id = notAllowedPart.Id, LocationId = location.Id, QuantityOnHand = 2)
            },
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * @description Allowed part with several Component Tags returns every tag record across all
     *              matching BOM Components, ordered by Name.
     */
    @IsTest
    static void testGetComponentTagsForProductMultipleTags() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId()); // current user: debrief permission sets vary by org

        System.runAs(contextUser) {
            // GIVEN: an Asset Work Order and a part with tags SV11 + SV12 + SV13 on two BOM Components
            Id workOrderId = workOrderId(WO_WITH_ASSET);
            Id product2Id = productId(CODE_MULTI_TAG);

            // WHEN: the Component Tags are requested for the part
            Test.startTest();
            List<WorkOrderLineItemsService.ComponentTagOption> options =
                WorkOrderLineItemsService.getComponentTagsForProduct(
                    workOrderId,
                    product2Id
                );
            Test.stopTest();

            // THEN: all three tag records come back, sorted by Name
            Assert.areEqual(3, options.size(), 'Every Component Tag record of the part should be returned');
            Assert.areEqual('SV11', options[0].label, 'Options should be ordered by Name');
            Assert.areEqual('SV12', options[1].label, 'Options should be ordered by Name');
            Assert.areEqual('SV13', options[2].label, 'Tags from the second BOM Component should be included');
            Assert.isNotNull(options[0].id, 'Option Id should be the Component Tag Id');
        }
    }

    /**
     * @description Allowed part with exactly one Component Tag returns a single option.
     */
    @IsTest
    static void testGetComponentTagsForProductSingleTag() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: a part with one Component Tag (SV21)
            Id workOrderId = workOrderId(WO_WITH_ASSET);
            Id product2Id = productId(CODE_SINGLE_TAG);

            // WHEN
            Test.startTest();
            List<WorkOrderLineItemsService.ComponentTagOption> options =
                WorkOrderLineItemsService.getComponentTagsForProduct(
                    workOrderId,
                    product2Id
                );
            Test.stopTest();

            // THEN: one option, which the LWC defaults automatically
            Assert.areEqual(1, options.size(), 'Single-tag part should return one option');
            Assert.areEqual('SV21', options[0].label, 'Label should be the Component Tag Name');
        }
    }

    /**
     * @description Allowed part whose BOM Component has no Component Tags returns no options.
     */
    @IsTest
    static void testGetComponentTagsForProductAllowedPartWithoutTags() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: a part on the allowed list without Component Tags
            Id workOrderId = workOrderId(WO_WITH_ASSET);
            Id product2Id = productId(CODE_NO_TAG);

            // WHEN
            Test.startTest();
            List<WorkOrderLineItemsService.ComponentTagOption> options =
                WorkOrderLineItemsService.getComponentTagsForProduct(
                    workOrderId,
                    product2Id
                );
            Test.stopTest();

            // THEN: no options, so the LWC shows the "no component tag" message
            Assert.isTrue(options.isEmpty(), 'Allowed part without tags should return no options');
        }
    }

    /**
     * @description Part that is not on the allowed parts list returns no options.
     */
    @IsTest
    static void testGetComponentTagsForProductNotAllowedPart() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: a part with no BOM Component on the Asset's Service BOM
            Id workOrderId = workOrderId(WO_WITH_ASSET);
            Id product2Id = productId(CODE_NOT_ALLOWED);

            // WHEN
            Test.startTest();
            List<WorkOrderLineItemsService.ComponentTagOption> options =
                WorkOrderLineItemsService.getComponentTagsForProduct(
                    workOrderId,
                    product2Id
                );
            Test.stopTest();

            // THEN
            Assert.isTrue(options.isEmpty(), 'Part not on the allowed list should return no options');
        }
    }

    /**
     * @description Work Order without an Asset returns no options (no allowed parts list).
     */
    @IsTest
    static void testGetComponentTagsForProductNoAsset() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: a Work Order without an Asset
            Id workOrderId = workOrderId(WO_WITHOUT_ASSET);
            Id product2Id = productId(CODE_MULTI_TAG);

            // WHEN
            Test.startTest();
            List<WorkOrderLineItemsService.ComponentTagOption> options =
                WorkOrderLineItemsService.getComponentTagsForProduct(
                    workOrderId,
                    product2Id
                );
            Test.stopTest();

            // THEN
            Assert.isTrue(options.isEmpty(), 'Work Order without Asset should return no options');
        }
    }

    /**
     * @description Trunk Stock: a Product Item resolves to its Product2 and returns that part's tags.
     */
    @IsTest
    static void testGetComponentTagsForProductItemMultipleTags() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: Product Items for the multi-tag part and for the part not on the allowed list
            Id workOrderId = workOrderId(WO_WITH_ASSET);
            Id multiTagItemId = productItemId(CODE_MULTI_TAG);
            Id notAllowedItemId = productItemId(CODE_NOT_ALLOWED);

            // WHEN
            Test.startTest();
            List<WorkOrderLineItemsService.ComponentTagOption> multiTagOptions =
                WorkOrderLineItemsService.getComponentTagsForProductItem(
                    workOrderId,
                    multiTagItemId
                );
            Map<Id, List<WorkOrderLineItemsService.ComponentTagOption>> optionsByProductItemIdMap =
                WorkOrderLineItemsService.getComponentTagsByProductItem(
                    workOrderId,
                    new Set<Id>{ multiTagItemId, notAllowedItemId, null }
                );
            Test.stopTest();

            // THEN
            Assert.areEqual(3, multiTagOptions.size(), 'Product Item should return the tags of its Product2');
            Assert.areEqual(2, optionsByProductItemIdMap.size(), 'Null Product Item Ids should be ignored');
            Assert.areEqual(3, optionsByProductItemIdMap.get(multiTagItemId).size());
            Assert.isTrue(
                optionsByProductItemIdMap.get(notAllowedItemId).isEmpty(),
                'Product Item of a part not on the allowed list should return no options'
            );
        }
    }

    /**
     * @description Blank inputs return empty results without querying.
     */
    @IsTest
    static void testGetComponentTagsBlankInputs() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: an Asset Work Order and a part
            Id workOrderId = workOrderId(WO_WITH_ASSET);
            Id product2Id = productId(CODE_MULTI_TAG);

            // WHEN: Ids or sets are missing
            Test.startTest();
            List<WorkOrderLineItemsService.ComponentTagOption> noWorkOrder =
                WorkOrderLineItemsService.getComponentTagsForProduct(
                    null,
                    product2Id
                );
            List<WorkOrderLineItemsService.ComponentTagOption> noProduct =
                WorkOrderLineItemsService.getComponentTagsForProduct(
                    workOrderId,
                    null
                );
            List<WorkOrderLineItemsService.ComponentTagOption> noProductItem =
                WorkOrderLineItemsService.getComponentTagsForProductItem(
                    workOrderId,
                    null
                );
            Map<Id, List<WorkOrderLineItemsService.ComponentTagOption>> nullProductSet =
                WorkOrderLineItemsService.getComponentTagsByProduct(
                    workOrderId,
                    null
                );
            Map<Id, List<WorkOrderLineItemsService.ComponentTagOption>> onlyNullProduct =
                WorkOrderLineItemsService.getComponentTagsByProduct(
                    workOrderId,
                    new Set<Id>{ null }
                );
            Map<Id, List<WorkOrderLineItemsService.ComponentTagOption>> emptyProductItemSet =
                WorkOrderLineItemsService.getComponentTagsByProductItem(
                    workOrderId,
                    new Set<Id>()
                );
            List<ComponentTag__c> noBomComponents = ComponentTagsSelector.selectByBomComponentIds(null);
            List<ComponentTag__c> onlyNullBomComponent = ComponentTagsSelector.selectByBomComponentIds(
                new Set<Id>{ null }
            );
            Test.stopTest();

            // THEN
            Assert.isTrue(noWorkOrder.isEmpty(), 'Missing Work Order should return no options');
            Assert.isTrue(noProduct.isEmpty(), 'Missing Product2 should return no options');
            Assert.isTrue(noProductItem.isEmpty(), 'Missing Product Item should return no options');
            Assert.isTrue(nullProductSet.isEmpty(), 'Null Product2 set should return an empty map');
            Assert.isTrue(onlyNullProduct.isEmpty(), 'Null Product2 Ids should be ignored');
            Assert.isTrue(emptyProductItemSet.isEmpty(), 'Empty Product Item set should return an empty map');
            Assert.isTrue(noBomComponents.isEmpty(), 'Null BOM Component set should return no tags');
            Assert.isTrue(onlyNullBomComponent.isEmpty(), 'Null BOM Component Ids should be ignored');
        }
    }

    /**
     * @description Bulk: 200 allowed parts with one tag each are resolved in one call.
     */
    @IsTest
    static void testGetComponentTagsByProductBulk() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: 200 parts on the allowed list, each with one Component Tag
            Id workOrderId = workOrderId(WO_WITH_ASSET);
            Set<Id> product2IdSet = new Map<Id, Product2>([SELECT Id FROM Product2 WHERE ProductCode LIKE 'CT-BULK-%'])
                .keySet();

            // WHEN
            Test.startTest();
            Map<Id, List<WorkOrderLineItemsService.ComponentTagOption>> optionsByProduct2IdMap =
                WorkOrderLineItemsService.getComponentTagsByProduct(
                    workOrderId,
                    product2IdSet
                );
            Test.stopTest();

            // THEN: every part has exactly its own tag
            Assert.areEqual(BULK_SIZE, product2IdSet.size(), 'Setup should create the bulk parts');
            Assert.areEqual(BULK_SIZE, optionsByProduct2IdMap.size(), 'Every requested part should have an entry');
            for (Id product2Id : product2IdSet) {
                Assert.areEqual(
                    1,
                    optionsByProduct2IdMap.get(product2Id).size(),
                    'Each bulk part should have one Component Tag'
                );
            }
        }
    }

    /**
     * @description QueryException is logged and wrapped as WorkOrderLineItemsServiceException.
     */
    @IsTest
    static void testGetComponentTagsByProductQueryExceptionWrapsServiceException() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: a simulated query failure
            WorkOrderLineItemsService.simulateQueryException = true;
            String message;

            // WHEN
            Test.startTest();
            try {
                WorkOrderLineItemsService.getComponentTagsForProduct(
                    workOrderId(WO_WITH_ASSET),
                    productId(CODE_MULTI_TAG)
                );
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            // THEN
            Assert.isNotNull(message, 'Expected WorkOrderLineItemsServiceException');
            Assert.isTrue(message.contains('Failed to load Component Tags'), 'Unexpected message: ' + message);
        }
    }

    /**
     * @description Unexpected exceptions are wrapped; the Product Item path rethrows the service exception.
     */
    @IsTest
    static void testGetComponentTagsByProductItemGenericExceptionWrapsServiceException() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: a simulated unexpected failure
            WorkOrderLineItemsService.simulateGenericException = true;
            String message;

            // WHEN
            Test.startTest();
            try {
                WorkOrderLineItemsService.getComponentTagsForProductItem(
                    workOrderId(WO_WITH_ASSET),
                    productItemId(CODE_MULTI_TAG)
                );
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            // THEN
            Assert.isNotNull(message, 'Expected WorkOrderLineItemsServiceException');
            Assert.isTrue(message.contains('Failed to load Component Tags'), 'Unexpected message: ' + message);
        }
    }

    /**
     * @description Controller delegates to the service for both Customer Stock and Trunk Stock.
     */
    @IsTest
    static void testControllerGetComponentTagsReturnsOptions() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN
            Id workOrderId = workOrderId(WO_WITH_ASSET);

            // WHEN
            Test.startTest();
            List<WorkOrderLineItemsService.ComponentTagOption> byProduct =
                WoDebriefAllowedUnitController.getComponentTagsForProduct(
                    workOrderId,
                    productId(CODE_SINGLE_TAG)
                );
            List<WorkOrderLineItemsService.ComponentTagOption> byProductItem =
                WoDebriefAllowedUnitController.getComponentTagsForProductItem(
                    workOrderId,
                    productItemId(CODE_MULTI_TAG)
                );
            Test.stopTest();

            // THEN
            Assert.areEqual(1, byProduct.size(), 'Customer Stock path should return the part tags');
            Assert.areEqual(3, byProductItem.size(), 'Trunk Stock path should return the part tags');
        }
    }

    /**
     * @description Controller surfaces service failures as AuraHandledException for both entry points.
     */
    @IsTest
    static void testControllerGetComponentTagsServiceExceptionThrowsAuraHandled() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: a simulated query failure
            Id workOrderId = workOrderId(WO_WITH_ASSET);
            Id product2Id = productId(CODE_MULTI_TAG);
            Id productItemId = productItemId(CODE_MULTI_TAG);
            WorkOrderLineItemsService.simulateQueryException = true;
            Integer auraExceptionCount = 0;

            // WHEN
            Test.startTest();
            try {
                WoDebriefAllowedUnitController.getComponentTagsForProduct(workOrderId, product2Id);
            } catch (AuraHandledException e) {
                auraExceptionCount++;
            }
            try {
                WoDebriefAllowedUnitController.getComponentTagsForProductItem(workOrderId, productItemId);
            } catch (AuraHandledException e) {
                auraExceptionCount++;
            }
            Test.stopTest();

            // THEN
            Assert.areEqual(2, auraExceptionCount, 'Both entry points should throw AuraHandledException');
        }
    }

    private static Product2 buildProduct(String name, String productCode, String productType) {
        return new Product2(Name = name, ProductCode = productCode, IsActive = true, ProductType__c = productType);
    }

    private static ProductRelatedMaterial buildBomComponent(
        ServiceBOM__c serviceBom,
        Product2 parentProduct,
        Product2 componentProduct
    ) {
        return new ProductRelatedMaterial(
            Name = 'CT BOM ' + componentProduct.Name,
            ServiceBOM__c = serviceBom.Id,
            ProductId = parentProduct.Id,
            ProductComponentId = componentProduct.Id,
            QuantityPerProductUnit = 1
        );
    }

    private static ComponentTag__c buildComponentTag(
        String name,
        ProductRelatedMaterial bomComponent,
        PartTag__c partTag
    ) {
        return new ComponentTag__c(Name = name, BomComponent__c = bomComponent.Id, ComponentTagId__c = partTag.Id);
    }

    private static Id workOrderId(String subject) {
        return [SELECT Id FROM WorkOrder WHERE Subject = :subject LIMIT 1].Id;
    }

    private static Id productId(String productCode) {
        return [SELECT Id FROM Product2 WHERE ProductCode = :productCode LIMIT 1].Id;
    }

    private static Id productItemId(String productCode) {
        return [SELECT Id FROM ProductItem WHERE Product2.ProductCode = :productCode LIMIT 1].Id;
    }
}