/**
 * @author Uptima Development Team
 * @date 2026-07-15
 * @description Tests for WorkOrderLineItemsService Allowed Unit evaluation.
 * @group Work Order Debrief
 * @see WorkOrderLineItemsService
 */
@IsTest
private class WorkOrderLineItemsAllowedUnitTest {
    /**
     * @description Creates an Account with required Source System Id for Allowed Unit tests.
     * @param name Account Name
     * @return Inserted Account
     */
    private static Account createAccount(String name) {
        Account account = new Account(
            Name = name,
            SourceSystemID__c = 'ORACLE-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert account;
        return account;
    }

    /**
     * @description Creates a mobile inventory Location for Product Item inserts.
     * @param name Location Name
     * @return Inserted Location
     */
    private static Schema.Location createInventoryLocation(String name) {
        Schema.Location loc = new Schema.Location(
            Name = name,
            LocationType = 'Warehouse',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert loc;
        return loc;
    }

    /**
     * @description Verifies evaluation is skipped when the Work Order has no Asset.
     */
    @IsTest
    static void testEvaluateAllowedUnitNoAsset() {
        Account account = createAccount('Allowed Unit Test Account');

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'Allowed Unit Test WO'
        );
        insert workOrder;

        Product2 product = new Product2(Name = 'Allowed Unit Test Part', IsActive = true);
        insert product;

        Test.startTest();
        AllowedUnitEvaluationDTO result =
            WorkOrderLineItemsService.evaluateAllowedUnit(workOrder.Id, product.Id);
        Test.stopTest();

        System.assertEquals(false, result.hasAsset, 'Expected no asset on Work Order');
        System.assertEquals(false, result.evaluated, 'Evaluation should be skipped without an Asset');
        System.assertEquals(null, result.allowedUnit, 'Allowed Unit should remain unset');
        System.assertEquals(null, result.criticalPart, 'Critical Part should remain unset');
    }

    /**
     * @description Verifies unevaluated DTO when required Ids are blank.
     */
    @IsTest
    static void testEvaluateAllowedUnitBlankIds() {
        Test.startTest();
        AllowedUnitEvaluationDTO result =
            WorkOrderLineItemsService.evaluateAllowedUnit(null, null);
        Test.stopTest();

        System.assertEquals(false, result.hasAsset);
        System.assertEquals(false, result.evaluated);
        System.assertEquals(null, result.allowedUnit);
        System.assertEquals(null, result.criticalPart);
    }

    /**
     * @description GW-4311 - Verifies unevaluated DTO when Product2 Allowed Unit Ids are blank.
     */
    @IsTest
    static void testEvaluateAllowedUnitByProductBlankIds() {
        Test.startTest();
        AllowedUnitEvaluationDTO result =
            WorkOrderLineItemsService.evaluateAllowedUnitByProduct(null, null);
        Test.stopTest();

        System.assertEquals(false, result.hasAsset);
        System.assertEquals(false, result.evaluated);
        System.assertEquals(null, result.allowedUnit);
        System.assertEquals(null, result.criticalPart);
    }

    /**
     * @description Verifies bulk evaluation returns empty maps for null/empty product sets.
     */
    @IsTest
    static void testEvaluateAllowedUnitsBulkEmptyProductSet() {
        Account account = createAccount('Allowed Unit Bulk Account');
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'Allowed Unit Bulk WO'
        );
        insert workOrder;

        Test.startTest();
        Map<Id, AllowedUnitEvaluationDTO> resultByProductItemIdMap =
            WorkOrderLineItemsService.evaluateAllowedUnits(workOrder.Id, new Set<Id>());
        Map<Id, AllowedUnitEvaluationDTO> nullSetResult =
            WorkOrderLineItemsService.evaluateAllowedUnits(workOrder.Id, null);
        Map<Id, AllowedUnitEvaluationDTO> nullWoResult =
            WorkOrderLineItemsService.evaluateAllowedUnits(null, new Set<Id>());
        Map<Id, AllowedUnitEvaluationDTO> emptyByProduct =
            WorkOrderLineItemsService.evaluateAllowedUnitsByProduct(workOrder.Id, new Set<Id>());
        Map<Id, AllowedUnitEvaluationDTO> nullByProduct =
            WorkOrderLineItemsService.evaluateAllowedUnitsByProduct(workOrder.Id, null);
        Test.stopTest();

        System.assertEquals(0, resultByProductItemIdMap.size(), 'Empty input should return empty map');
        System.assertEquals(0, nullSetResult.size());
        System.assertEquals(0, nullWoResult.size());
        System.assertEquals(0, emptyByProduct.size(), 'Empty Product2 set should return empty map');
        System.assertEquals(0, nullByProduct.size());
    }

    /**
     * @description Verifies Asset + Service BOM path marks allowed/critical parts correctly.
     */
    @IsTest
    static void testEvaluateAllowedUnit_withAssetAndBom_marksAllowedAndCritical() {
        Account account = createAccount('Allowed Unit Asset Account');

        ServiceBOM__c serviceBom = new ServiceBOM__c(
            Name = 'AU Test SBOM ' + String.valueOf(Crypto.getRandomInteger()),
            Type__c = 'ES Asset BOM'
        );
        insert serviceBom;

        Product2 assetProduct = new Product2(
            Name = 'AU Asset Product',
            IsActive = true,
            ProductType__c = 'Service Asset'
        );
        insert assetProduct;

        Product2 allowedPart = new Product2(
            Name = 'AU Allowed Part',
            ProductCode = 'AU-ALLOW-1',
            IsActive = true,
            ProductType__c = 'Part'
        );
        Product2 otherPart = new Product2(
            Name = 'AU Other Part',
            ProductCode = 'AU-OTHER-1',
            IsActive = true,
            ProductType__c = 'Part'
        );
        insert new List<Product2>{ allowedPart, otherPart };

        ProductRelatedMaterial bomComponent = new ProductRelatedMaterial(
            Name = 'AU BOM Component',
            ServiceBOM__c = serviceBom.Id,
            ProductId = assetProduct.Id,
            ProductComponentId = allowedPart.Id,
            QuantityPerProductUnit = 1,
            CriticalPart__c = true
        );
        insert bomComponent;

        Asset asset = new Asset(
            Name = 'AU Test Asset',
            AccountId = account.Id,
            Product2Id = assetProduct.Id,
            ServiceBOM__c = serviceBom.Id
        );
        insert asset;

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'AU Asset WO',
            AssetId = asset.Id
        );
        insert workOrder;

        Schema.Location loc = createInventoryLocation(
            'AU Loc ' + String.valueOf(Crypto.getRandomInteger())
        );

        ProductItem allowedItem = new ProductItem(
            Product2Id = allowedPart.Id,
            LocationId = loc.Id,
            QuantityOnHand = 3
        );
        ProductItem otherItem = new ProductItem(
            Product2Id = otherPart.Id,
            LocationId = loc.Id,
            QuantityOnHand = 2
        );
        insert new List<ProductItem>{ allowedItem, otherItem };

        Test.startTest();
        AllowedUnitEvaluationDTO allowedResult =
            WorkOrderLineItemsService.evaluateAllowedUnit(workOrder.Id, allowedItem.Id);
        AllowedUnitEvaluationDTO otherResult =
            WorkOrderLineItemsService.evaluateAllowedUnit(workOrder.Id, otherItem.Id);
        AllowedUnitEvaluationDTO missingItemResult =
            WorkOrderLineItemsService.evaluateAllowedUnit(workOrder.Id, allowedPart.Id);
        AllowedUnitEvaluationDTO allowedByProduct =
            WorkOrderLineItemsService.evaluateAllowedUnitByProduct(workOrder.Id, allowedPart.Id);
        AllowedUnitEvaluationDTO otherByProduct =
            WorkOrderLineItemsService.evaluateAllowedUnitByProduct(workOrder.Id, otherPart.Id);
        Test.stopTest();

        System.assertEquals(true, allowedResult.hasAsset);
        System.assertEquals(true, allowedResult.evaluated);
        System.assertEquals(true, allowedResult.allowedUnit);
        System.assertEquals(true, allowedResult.criticalPart);

        System.assertEquals(true, otherResult.evaluated);
        System.assertEquals(false, otherResult.allowedUnit);
        System.assertEquals(false, otherResult.criticalPart);

        System.assertEquals(true, missingItemResult.evaluated);
        System.assertEquals(false, missingItemResult.allowedUnit);

        System.assertEquals(true, allowedByProduct.hasAsset, 'Customer Stock should evaluate Product2 directly');
        System.assertEquals(true, allowedByProduct.evaluated);
        System.assertEquals(true, allowedByProduct.allowedUnit);
        System.assertEquals(true, allowedByProduct.criticalPart);
        System.assertEquals(true, otherByProduct.evaluated);
        System.assertEquals(false, otherByProduct.allowedUnit);
    }

    /**
     * @description Verifies Asset without Service BOM still evaluates as not allowed.
     */
    @IsTest
    static void testEvaluateAllowedUnit_withAssetNoBom_evaluatesDenied() {
        Account account = createAccount('Allowed Unit NoBom Account');

        Product2 assetProduct = new Product2(
            Name = 'AU NoBom Asset Product',
            IsActive = true,
            ProductType__c = 'Service Asset'
        );
        insert assetProduct;

        Product2 part = new Product2(
            Name = 'AU NoBom Part',
            ProductCode = 'AU-NOBOM-1',
            IsActive = true,
            ProductType__c = 'Part'
        );
        insert part;

        Asset asset = new Asset(
            Name = 'AU NoBom Asset',
            AccountId = account.Id,
            Product2Id = assetProduct.Id
        );
        insert asset;

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'AU NoBom WO',
            AssetId = asset.Id
        );
        insert workOrder;

        Schema.Location loc = createInventoryLocation(
            'AU NoBom Loc ' + String.valueOf(Crypto.getRandomInteger())
        );

        ProductItem item = new ProductItem(
            Product2Id = part.Id,
            LocationId = loc.Id,
            QuantityOnHand = 1
        );
        insert item;

        Test.startTest();
        AllowedUnitEvaluationDTO result =
            WorkOrderLineItemsService.evaluateAllowedUnit(workOrder.Id, item.Id);
        Test.stopTest();

        System.assertEquals(true, result.hasAsset);
        System.assertEquals(true, result.evaluated);
        System.assertEquals(false, result.allowedUnit);
        System.assertEquals(false, result.criticalPart);
    }

    /**
     * @description GW-4218: When Root PFCL SBOM Required is not Yes, skip SBOM cross-reference
     *              and leave Allowed Unit / Critical Part unevaluated.
     */
    @IsTest
    static void testEvaluateAllowedUnit_rootSbomNotRequired_skipsEvaluation() {
        Account account = createAccount('AU SBOM Not Required Account');

        Id rootRtId = Schema.SObjectType.PFCL__c.getRecordTypeInfosByDeveloperName()
            .get('RootPFCL')
            .getRecordTypeId();
        Id versionRtId = Schema.SObjectType.PFCL__c.getRecordTypeInfosByDeveloperName()
            .get('ESPFCL')
            .getRecordTypeId();

        String unique = String.valueOf(Crypto.getRandomInteger());
        PFCL__c rootPfcl = new PFCL__c(
            Name = 'AU-ROOT-' + unique,
            PFCL__c = 'AU-ROOT-NUM-' + unique,
            RecordTypeId = rootRtId,
            SBOMRequired__c = 'No'
        );
        insert rootPfcl;

        PFCL__c versionPfcl = new PFCL__c(
            Name = 'AU-VER-' + unique,
            PFCL__c = 'AU-VER-NUM-' + unique,
            RecordTypeId = versionRtId,
            Parent__c = rootPfcl.Id
        );
        insert versionPfcl;

        ServiceBOM__c serviceBom = new ServiceBOM__c(
            Name = 'AU SBOM Skip ' + unique,
            Type__c = 'ES Asset BOM'
        );
        insert serviceBom;

        Product2 assetProduct = new Product2(
            Name = 'AU SBOM Skip Asset Product',
            IsActive = true,
            ProductType__c = 'Service Asset',
            PFCL__c = versionPfcl.Id
        );
        insert assetProduct;

        Product2 part = new Product2(
            Name = 'AU SBOM Skip Part',
            ProductCode = 'AU-SKIP-1',
            IsActive = true,
            ProductType__c = 'Part'
        );
        insert part;

        ProductRelatedMaterial bomComponent = new ProductRelatedMaterial(
            Name = 'AU SBOM Skip Component',
            ServiceBOM__c = serviceBom.Id,
            ProductId = assetProduct.Id,
            ProductComponentId = part.Id,
            QuantityPerProductUnit = 1,
            CriticalPart__c = true
        );
        insert bomComponent;

        Asset asset = new Asset(
            Name = 'AU SBOM Skip Asset',
            AccountId = account.Id,
            Product2Id = assetProduct.Id,
            ServiceBOM__c = serviceBom.Id
        );
        insert asset;

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'AU SBOM Skip WO',
            AssetId = asset.Id
        );
        insert workOrder;

        Schema.Location loc = createInventoryLocation('AU SBOM Skip Loc ' + unique);
        ProductItem item = new ProductItem(
            Product2Id = part.Id,
            LocationId = loc.Id,
            QuantityOnHand = 1
        );
        insert item;

        Test.startTest();
        AllowedUnitEvaluationDTO result =
            WorkOrderLineItemsService.evaluateAllowedUnit(workOrder.Id, item.Id);
        Test.stopTest();

        System.assertEquals(true, result.hasAsset, 'Work Order still has an Asset');
        System.assertEquals(false, result.evaluated, 'SBOM Required No should skip evaluation');
        System.assertEquals(null, result.allowedUnit);
        System.assertEquals(null, result.criticalPart);
    }

    /**
     * @description Verifies QueryException is wrapped as WorkOrderLineItemsServiceException.
     */
    @IsTest
    static void testEvaluateAllowedUnits_queryException_wrapsServiceException() {
        WorkOrderLineItemsService.simulateQueryException = true;
        try {
            Test.startTest();
            WorkOrderLineItemsService.evaluateAllowedUnits(
                UserInfo.getUserId(),
                new Set<Id>{ UserInfo.getUserId() }
            );
            Test.stopTest();
            System.assert(false, 'Expected WorkOrderLineItemsService.WorkOrderLineItemsServiceException');
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            System.assert(e.getMessage().contains('Failed to evaluate Allowed Unit'));
        } finally {
            WorkOrderLineItemsService.simulateQueryException = false;
        }
    }

    /**
     * @description Verifies unexpected exceptions are wrapped as WorkOrderLineItemsServiceException.
     */
    @IsTest
    static void testEvaluateAllowedUnits_genericException_wrapsServiceException() {
        WorkOrderLineItemsService.simulateGenericException = true;
        try {
            Test.startTest();
            WorkOrderLineItemsService.evaluateAllowedUnits(
                UserInfo.getUserId(),
                new Set<Id>{ UserInfo.getUserId() }
            );
            Test.stopTest();
            System.assert(false, 'Expected WorkOrderLineItemsService.WorkOrderLineItemsServiceException');
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            System.assert(e.getMessage().contains('Failed to evaluate Allowed Unit'));
        } finally {
            WorkOrderLineItemsService.simulateGenericException = false;
        }
    }

    /**
     * @description Direct selector empty-input calls so CI coverage still passes when Mario's
     *              substring test mapping binds ServiceBOMsSelector to the wrong *Test class.
     */
    @IsTest
    static void testBomSelectors_emptyInputs_areCovered() {
        Test.startTest();
        System.assertEquals(0, PFCLsSelector.selectByAssetPfclValues(null).size());
        System.assertEquals(0, PFCLsSelector.selectByAssetPfclValues(new Set<String>()).size());
        System.assertEquals(0, PFCLServiceBOMsSelector.selectByPFCLId(null).size());
        System.assertEquals(0, PFCLServiceBOMsSelector.selectByPFCLId(new Set<Id>()).size());
        System.assertEquals(0, ServiceBOMsSelector.selectByPFCLId(null).size());
        System.assertEquals(0, ServiceBOMsSelector.selectByPFCLId(new Set<Id>()).size());
        System.assertEquals(0, ProductItemsSelector.selectById(null).size());
        System.assertEquals(0, ProductItemsSelector.selectById(new Set<Id>()).size());
        Test.stopTest();
    }
}