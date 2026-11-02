/**
 * @description Tests for WoDebriefProductItemController barcode Product Item lookup.
 * @see WoDebriefProductItemController
 */
@IsTest
private class WoDebriefProductItemControllerTest {
    /**
     * @description Verifies blank product code or null Service Resource returns an empty match.
     */
    @IsTest
    static void findByProductCode_blankInputs_returnsEmpty() {
        Test.startTest();
        WoDebriefProductItemController.MatchResult blankCode =
            WoDebriefProductItemController.findByProductCode('  ', null);
        WoDebriefProductItemController.MatchResult nullResource =
            WoDebriefProductItemController.findByProductCode('ABC123', null);
        Test.stopTest();

        System.assertEquals(0, blankCode.matchCount, 'Blank code should not match');
        System.assertEquals(null, blankCode.productItemId, 'Blank code should have no Id');
        System.assertEquals(0, nullResource.matchCount, 'Null resource should not match');
        System.assertEquals(null, nullResource.productItemId, 'Null resource should have no Id');
    }

    /**
     * @description Verifies Service Resource without LocationId returns an empty match.
     */
    @IsTest
    static void findByProductCode_resourceWithoutLocation_returnsEmpty() {
        ServiceResource resource = new ServiceResource(
            Name = 'Debrief PI No Location',
            IsActive = true,
            RelatedRecordId = UserInfo.getUserId(),
            ExternalID__c = 'DEBRIEF-PI-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert resource;

        Test.startTest();
        WoDebriefProductItemController.MatchResult result =
            WoDebriefProductItemController.findByProductCode('CODE-1', resource.Id);
        Test.stopTest();

        System.assertEquals(0, result.matchCount);
        System.assertEquals(null, result.productItemId);
        System.assertEquals(null, result.locationId);
    }

    /**
     * @description Verifies unknown Service Resource Id returns an empty match.
     */
    @IsTest
    static void findByProductCode_unknownResource_returnsEmpty() {
        Id fakeResourceId = ServiceResource.SObjectType.getDescribe()
            .getKeyPrefix() + '000000000001';

        Test.startTest();
        WoDebriefProductItemController.MatchResult result =
            WoDebriefProductItemController.findByProductCode('CODE-1', fakeResourceId);
        Test.stopTest();

        System.assertEquals(0, result.matchCount);
        System.assertEquals(null, result.productItemId);
    }

    /**
     * @description Verifies in-stock Product Item at the resource location is returned by Product Code.
     */
    @IsTest
    static void findByProductCode_match_returnsProductItem() {
        Schema.Location trunk = new Schema.Location(
            Name = 'Debrief Trunk ' + String.valueOf(Crypto.getRandomInteger()),
            LocationType = 'Warehouse',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert trunk;

        ServiceResource resource = new ServiceResource(
            Name = 'Debrief PI Resource',
            IsActive = true,
            RelatedRecordId = UserInfo.getUserId(),
            LocationId = trunk.Id,
            ExternalID__c = 'DEBRIEF-PI-LOC-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert resource;

        Product2 product = new Product2(
            Name = 'Debrief Scan Part',
            ProductCode = 'SCAN-PART-001',
            IsActive = true,
            ProductType__c = 'Part',
            IsReturnable__c = true
        );
        insert product;

        ProductItem item = new ProductItem(
            Product2Id = product.Id,
            LocationId = trunk.Id,
            QuantityOnHand = 5
        );
        insert item;

        Test.startTest();
        WoDebriefProductItemController.MatchResult noMatch =
            WoDebriefProductItemController.findByProductCode('NO-MATCH', resource.Id);
        WoDebriefProductItemController.MatchResult match =
            WoDebriefProductItemController.findByProductCode(' SCAN-PART-001 ', resource.Id);
        Test.stopTest();

        System.assertEquals(0, noMatch.matchCount);
        System.assertEquals(null, noMatch.productItemId);
        System.assertEquals(trunk.Id, noMatch.locationId);

        System.assertEquals(1, match.matchCount);
        System.assertEquals(item.Id, match.productItemId);
        System.assertEquals(product.Id, match.product2Id);
        System.assertEquals(true, match.isReturnable);
        System.assertEquals(trunk.Id, match.locationId);
        System.assertNotEquals(null, match.productName);
        System.assertEquals(null, match.refurbishedProductId);
    }

    /**
     * @description Verifies a Product Item scan returns the product's refurbished part when one is set.
     */
    @IsTest
    static void findByProductCode_refurbishedProduct_returnsRefurbishedPart() {
        Schema.Location trunk = new Schema.Location(
            Name = 'Debrief Trunk Refurb ' + String.valueOf(Crypto.getRandomInteger()),
            LocationType = 'Warehouse',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert trunk;

        ServiceResource resource = new ServiceResource(
            Name = 'Debrief PI Refurb Resource',
            IsActive = true,
            RelatedRecordId = UserInfo.getUserId(),
            LocationId = trunk.Id,
            ExternalID__c = 'DEBRIEF-PI-REF-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert resource;

        Product2 refurbished = new Product2(
            Name = 'Refurbished Scan Part',
            ProductCode = 'SCAN-PART-REF',
            IsActive = true,
            ProductType__c = 'Part'
        );
        insert refurbished;

        Product2 product = new Product2(
            Name = 'Debrief Scan Part With Refurb',
            ProductCode = 'SCAN-PART-002',
            IsActive = true,
            ProductType__c = 'Part',
            RefurbishedProduct__c = refurbished.Id
        );
        insert product;

        insert new ProductItem(
            Product2Id = product.Id,
            LocationId = trunk.Id,
            QuantityOnHand = 2
        );

        Test.startTest();
        WoDebriefProductItemController.MatchResult itemMatch =
            WoDebriefProductItemController.findByProductCode('SCAN-PART-002', resource.Id);
        WoDebriefProductItemController.MatchResult productMatch =
            WoDebriefProductItemController.findProductByProductCode('SCAN-PART-002', null);
        Test.stopTest();

        System.assertEquals(product.Id, itemMatch.product2Id);
        System.assertEquals(refurbished.Id, itemMatch.refurbishedProductId);
        System.assertEquals('Refurbished Scan Part', itemMatch.refurbishedProductName);
        System.assertEquals(refurbished.Id, productMatch.refurbishedProductId);
        System.assertEquals('Refurbished Scan Part', productMatch.refurbishedProductName);
    }

    /**
     * @description Verifies Location Id is returned for any Service Resource with a trunk location.
     */
    @IsTest
    static void getLocationIdForServiceResource_returnsLocation() {
        Schema.Location trunk = new Schema.Location(
            Name = 'Debrief Loc ' + String.valueOf(Crypto.getRandomInteger()),
            LocationType = 'Warehouse',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert trunk;

        ServiceResource resource = new ServiceResource(
            Name = 'Debrief Loc Resource',
            IsActive = true,
            RelatedRecordId = UserInfo.getUserId(),
            LocationId = trunk.Id,
            ExternalID__c = 'DEBRIEF-LOC-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert resource;

        Test.startTest();
        Id locationId = WoDebriefProductItemController.getLocationIdForServiceResource(resource.Id);
        Id blankId = WoDebriefProductItemController.getLocationIdForServiceResource(null);
        Test.stopTest();

        System.assertEquals(trunk.Id, locationId);
        System.assertEquals(null, blankId);
    }

    /**
     * @description GW-4311 - Verifies global Product2 barcode lookup by Product Code.
     */
    @IsTest
    static void findProductByProductCode_match_returnsProduct() {
        Product2 product = new Product2(
            Name = 'Customer Stock Part',
            ProductCode = 'CUST-PART-001',
            Description = 'Customer stock description',
            IsActive = true,
            ProductType__c = 'Part',
            IsReturnable__c = false
        );
        insert product;

        Test.startTest();
        WoDebriefProductItemController.MatchResult blank =
            WoDebriefProductItemController.findProductByProductCode('  ', null);
        WoDebriefProductItemController.MatchResult noMatch =
            WoDebriefProductItemController.findProductByProductCode('NO-MATCH', null);
        WoDebriefProductItemController.MatchResult match =
            WoDebriefProductItemController.findProductByProductCode(' CUST-PART-001 ', null);
        Test.stopTest();

        System.assertEquals(0, blank.matchCount);
        System.assertEquals(0, noMatch.matchCount);
        System.assertEquals(1, match.matchCount);
        System.assertEquals(product.Id, match.product2Id);
        System.assertEquals('CUST-PART-001', match.productCode);
        System.assertEquals('Customer stock description', match.description);
        System.assertEquals(false, match.isReturnable);
    }

    /**
     * @description GW-2965 — Product Type filter matches Instrument vs Repair Code scans.
     */
    @IsTest
    static void findProductByProductCode_productTypeFilter_returnsMatchingType() {
        Product2 partProduct = new Product2(
            Name = 'Instrument Part',
            ProductCode = 'INST-SCAN-001',
            IsActive = true,
            ProductType__c = 'Part'
        );
        Product2 serviceCodeProduct = new Product2(
            Name = 'Repair Service Code',
            ProductCode = 'RPR-SCAN-001',
            IsActive = true,
            ProductType__c = 'Service Code'
        );
        insert new List<Product2>{ partProduct, serviceCodeProduct };

        Test.startTest();
        WoDebriefProductItemController.MatchResult partMatch =
            WoDebriefProductItemController.findProductByProductCode('INST-SCAN-001', 'Part');
        WoDebriefProductItemController.MatchResult partWrongType =
            WoDebriefProductItemController.findProductByProductCode('INST-SCAN-001', 'Service Code');
        WoDebriefProductItemController.MatchResult repairMatch =
            WoDebriefProductItemController.findProductByProductCode('RPR-SCAN-001', 'Service Code');
        Test.stopTest();

        System.assertEquals(partProduct.Id, partMatch.product2Id, 'Part scan should return the Part product');
        System.assertEquals(0, partWrongType.matchCount, 'Part code should not match Service Code filter');
        System.assertEquals(
            serviceCodeProduct.Id,
            repairMatch.product2Id,
            'Repair Code scan should return the Service Code product'
        );
    }

    /**
     * @description Verifies Device Type service-code lookup delegates for a null product Id.
     */
    @IsTest
    static void getRepairCodesForProduct_nullProduct_returnsEmpty() {
        Test.startTest();
        WoDebriefProductItemController.RepairCodesForProductResult result =
            WoDebriefProductItemController.getRepairCodesForProduct(null);
        Test.stopTest();

        System.assertEquals('', result.baseServiceCode);
        System.assertEquals(0, result.options.size());
    }

    /**
     * @description Verifies pricebook-entry resolve delegates for blank Ids.
     */
    @IsTest
    static void resolvePricebookEntryId_blankInputs_returnsNull() {
        Test.startTest();
        Id result = WoDebriefProductItemController.resolvePricebookEntryId(null, null);
        Test.stopTest();

        System.assertEquals(null, result);
    }

    /**
     * @description Verifies UsageConsumption record type lookup for woDebriefES.
     */
    @IsTest
    static void getUsageConsumptionRecordTypeId_returnsRecordTypeWhenPresent() {
        Id expectedId;
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'WorkOrderLineItem'
                AND DeveloperName = 'UsageConsumption'
            LIMIT 1
        ];
        if (!recordTypes.isEmpty()) {
            expectedId = recordTypes[0].Id;
        }

        Test.startTest();
        Id actualId = WoDebriefProductItemController.getUsageConsumptionRecordTypeId();
        Test.stopTest();

        System.assertEquals(expectedId, actualId);
    }

    /**
     * @description Verifies ProductServiced record type lookup for woDebrief.
     */
    @IsTest
    static void getProductServicedRecordTypeId_returnsRecordTypeWhenPresent() {
        Id expectedId;
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'WorkOrderLineItem'
                AND DeveloperName = 'ProductServiced'
            LIMIT 1
        ];
        if (!recordTypes.isEmpty()) {
            expectedId = recordTypes[0].Id;
        }

        Test.startTest();
        Id actualId = WoDebriefProductItemController.getProductServicedRecordTypeId();
        Test.stopTest();

        System.assertEquals(expectedId, actualId);
    }
}