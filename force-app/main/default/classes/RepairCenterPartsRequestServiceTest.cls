/**
 * @description GW-5981 - Repair Center parts request creation from evaluation screens.
 */
@IsTest
private class RepairCenterPartsRequestServiceTest {
    @IsTest
    static void getBomParts_returnsActivePartsInSequence() {
        Fixture fixture = new Fixture().persist();
        insert new ProductRelatedMaterial(
            Name = 'Duplicate Bearing',
            ServiceBOM__c = fixture.serviceBom.Id,
            ProductId = fixture.parentProduct.Id,
            ProductComponentId = fixture.part.Id,
            QuantityPerProductUnit = 1,
            ComponentSequence__c = 5
        );

        Test.startTest();
        List<RepairCenterPartsRequestService.PartOption> parts =
            RepairCenterPartsRequestController.getBomParts(fixture.workOrder.Id);
        Test.stopTest();

        Assert.areEqual(1, parts.size(), 'Inactive parts, non-parts, and duplicates are excluded.');
        Assert.areEqual(fixture.part.Id, parts[0].productId);
        Assert.areEqual('MP.3557 Fiber Bearing, Storz', parts[0].label);
    }

    @IsTest
    static void getBomParts_usesAssetProductWhenWorkOrderProductIsBlank() {
        Fixture fixture = new Fixture();
        fixture.useWorkOrderProduct = false;
        fixture.persist();

        List<RepairCenterPartsRequestService.PartOption> parts =
            RepairCenterPartsRequestService.getBomParts(fixture.workOrder.Id);

        Assert.areEqual(1, parts.size());
        Assert.areEqual(fixture.part.Id, parts[0].productId);
    }

    @IsTest
    static void findScannedPart_matchesCodeOrId() {
        Fixture fixture = new Fixture().persist();

        RepairCenterPartsRequestService.PartOption byCode =
            RepairCenterPartsRequestService.findScannedPart('scan-9');
        RepairCenterPartsRequestService.PartOption byId =
            RepairCenterPartsRequestService.findScannedPart(fixture.scanProduct.Id);

        Assert.areEqual(fixture.scanProduct.Id, byCode.productId);
        Assert.areEqual('SCAN-9 Scan Part', byCode.label);
        Assert.areEqual(fixture.scanProduct.Id, byId.productId);
    }

    @IsTest
    static void findScannedPart_reportsTheEnteredValue() {
        try {
            RepairCenterPartsRequestController.findScannedPart('MISSING-1');
            Assert.fail('Expected a missing-part error.');
        } catch (AuraHandledException e) {
            Assert.areEqual(
                'No Product could be identified for the provided Part Number: MISSING-1.',
                e.getMessage()
            );
        }
    }

    @IsTest
    static void createPartsRequest_mapsHeaderAndLines() {
        Fixture fixture = new Fixture().persist();
        List<RepairCenterPartsRequestService.PartLineInput> lines =
            new List<RepairCenterPartsRequestService.PartLineInput>{
                line(fixture.part.Id, 2),
                line(fixture.scanProduct.Id, 1)
            };

        Test.startTest();
        RepairCenterPartsRequestService.CreateResult result =
            RepairCenterPartsRequestController.createPartsRequest(fixture.workOrder.Id, lines);
        Test.stopTest();

        ProductRequest header = ProductRequestsSelector.selectWithLinesByWorkOrderId(
            new Set<Id>{ fixture.workOrder.Id }
        )[0];
        Assert.areEqual('RepairCenter', header.RecordType.DeveloperName);
        Assert.areEqual('Parts', header.RequestType__c);
        Assert.areEqual(fixture.workOrder.Id, header.WorkOrderId);
        Assert.areEqual(fixture.repairCenter.Id, header.DestinationLocationId);
        Assert.areEqual('Submitted', header.Status);
        Assert.areEqual('Pick Up', header.ShipmentType);

        Map<Id, ProductRequestLineItem> linesByProduct = new Map<Id, ProductRequestLineItem>();
        for (ProductRequestLineItem requestLine : header.ProductRequestLineItems) {
            linesByProduct.put(requestLine.Product2Id, requestLine);
            Assert.areEqual('RepairCenter', requestLine.RecordType.DeveloperName);
            Assert.areEqual('Submitted', requestLine.Status);
        }
        Assert.areEqual(2, linesByProduct.get(fixture.part.Id).QuantityRequested);
        Assert.areEqual(1, linesByProduct.get(fixture.scanProduct.Id).QuantityRequested);

        List<RepairCenterPartsRequestService.RequestRow> rows =
            RepairCenterPartsRequestController.getProductRequests(fixture.workOrder.Id);
        Assert.areEqual(1, rows.size());
        Assert.areEqual(result.productRequestNumber, rows[0].productRequestNumber);
        Assert.areEqual('Parts', rows[0].requestType);
        Assert.areEqual(2, rows[0].lines.size());
        Set<String> displays = new Set<String>();
        for (RepairCenterPartsRequestService.LineDisplay display : rows[0].lines) {
            displays.add(display.displayText);
        }
        Assert.isTrue(displays.contains('MP.3557 Fiber Bearing, Storz (2)'));
        Assert.isTrue(displays.contains('SCAN-9 Scan Part (1)'));
    }

    @IsTest
    static void controller_hidesUnexpectedErrors() {
        AuraHandledException error = RepairCenterPartsRequestController.auraException(
            new NullPointerException()
        );
        Assert.areEqual(
            'Unable to complete the parts request. Please try again.',
            error.getMessage()
        );
    }

    @IsTest
    static void productRequestSelector_readsHeaderAndLines() {
        Fixture fixture = new Fixture().persist();
        RepairCenterPartsRequestService.CreateResult created =
            RepairCenterPartsRequestService.createPartsRequest(
                fixture.workOrder.Id,
                new List<RepairCenterPartsRequestService.PartLineInput>{ line(fixture.part.Id, 1) }
            );
        Id requestId = created.productRequestId;
        Set<Id> requestIds = new Set<Id>{ requestId };
        Set<Id> workOrderIds = new Set<Id>{ fixture.workOrder.Id };

        Assert.areEqual(0, ProductRequestsSelector.selectById(null).size());
        Assert.areEqual(0, ProductRequestsSelector.selectById(new Set<Id>()).size());
        Assert.areEqual(requestId, ProductRequestsSelector.selectById(requestIds)[0].Id);

        Assert.areEqual(0, ProductRequestsSelector.selectByStatus(null).size());
        Assert.areEqual(0, ProductRequestsSelector.selectByStatus(new Set<String>()).size());
        Assert.areEqual(
            requestId,
            ProductRequestsSelector.selectByStatus(new Set<String>{ 'Submitted' })[0].Id
        );

        Assert.areEqual(0, ProductRequestsSelector.selectByWorkOrderId(null).size());
        Assert.areEqual(0, ProductRequestsSelector.selectByWorkOrderId(new Set<Id>()).size());
        Assert.areEqual(
            requestId,
            ProductRequestsSelector.selectByWorkOrderId(workOrderIds)[0].Id
        );

        Assert.areEqual(0, ProductRequestsSelector.selectByIdWithLineItems(null).size());
        Assert.areEqual(0, ProductRequestsSelector.selectByIdWithLineItems(new Set<Id>()).size());
        Assert.areEqual(
            1,
            ProductRequestsSelector.selectByIdWithLineItems(requestIds)[0].ProductRequestLineItems.size()
        );

        Assert.areEqual(0, ProductRequestsSelector.selectForDpcLaunch(null).size());
        Assert.areEqual(0, ProductRequestsSelector.selectForDpcLaunch(new Set<Id>()).size());
        Assert.areEqual(requestId, ProductRequestsSelector.selectForDpcLaunch(requestIds)[0].Id);

        Assert.areEqual(null, ProductRequestsSelector.selectNumberById(null));
        Assert.areEqual(0, ProductRequestsSelector.selectWithLinesByWorkOrderId(null).size());
        Assert.areEqual(0, ProductRequestsSelector.selectWithLinesByWorkOrderId(new Set<Id>()).size());
    }

    @IsTest
    static void createPartsRequest_rejectsEmptyAndIneligibleWorkOrders() {
        Fixture fixture = new Fixture().persist();

        try {
            RepairCenterPartsRequestService.createPartsRequest(fixture.workOrder.Id, null);
            Assert.fail('Expected a line-item error.');
        } catch (RepairCenterPartsRequestService.RepairCenterPartsRequestException e) {
            Assert.areEqual('Add at least one part before saving.', e.getMessage());
        }

        fixture.workOrder.Status = 'New';
        update fixture.workOrder;
        try {
            RepairCenterPartsRequestService.createPartsRequest(
                fixture.workOrder.Id,
                new List<RepairCenterPartsRequestService.PartLineInput>{ line(fixture.part.Id, 1) }
            );
            Assert.fail('Expected a status error.');
        } catch (RepairCenterPartsRequestService.RepairCenterPartsRequestException e) {
            Assert.isTrue(e.getMessage().contains('Status is Repair'));
        }

        fixture.workOrder.Status = 'Repair';
        fixture.workOrder.RepairCenter__c = null;
        update fixture.workOrder;
        try {
            RepairCenterPartsRequestService.createPartsRequest(
                fixture.workOrder.Id,
                new List<RepairCenterPartsRequestService.PartLineInput>{ line(fixture.part.Id, 1) }
            );
            Assert.fail('Expected a repair center error.');
        } catch (RepairCenterPartsRequestService.RepairCenterPartsRequestException e) {
            Assert.isTrue(e.getMessage().contains('Repair Center'));
        }
    }

    private static RepairCenterPartsRequestService.PartLineInput line(Id productId, Decimal quantity) {
        RepairCenterPartsRequestService.PartLineInput input =
            new RepairCenterPartsRequestService.PartLineInput();
        input.productId = productId;
        input.quantity = quantity;
        return input;
    }

    private class Fixture {
        public Boolean useWorkOrderProduct = true;
        public Account account;
        public Schema.Location repairCenter;
        public ServiceBOM__c serviceBom;
        public Product2 parentProduct;
        public Product2 part;
        public Product2 inactivePart;
        public Product2 serviceProduct;
        public Product2 scanProduct;
        public Asset asset;
        public WorkOrder workOrder;

        public Fixture persist() {
            account = new Account(
                Name = 'GW5981 Account',
                SystemID__c = 'LEG-GW5981',
                SourceSystemID__c = 'SYS-GW5981',
                OrgIDs__c = '82'
            );
            insert account;

            repairCenter = new Schema.Location(
                Name = 'GW5981 Repair Center',
                LocationType = 'Repair Center',
                IsInventoryLocation = true
            );
            insert repairCenter;

            serviceBom = new ServiceBOM__c(
                Name = 'GW5981 SBOM',
                Type__c = 'ES Asset BOM'
            );
            insert serviceBom;

            parentProduct = product('Flexible Scope', 'FS.17243', 'Service Asset', true, null);
            part = product('Bearing', 'MP.3557', 'Part', true, 'Fiber Bearing, Storz');
            inactivePart = product('Old Bearing', 'MP.OLD', 'Part', false, 'Inactive');
            serviceProduct = product('Inspection', 'SVC.1', 'Service Asset', true, 'Not a part');
            scanProduct = product('Scan Part Name', 'SCAN-9', 'Part', true, 'Scan Part');
            insert new List<Product2>{
                parentProduct,
                part,
                inactivePart,
                serviceProduct,
                scanProduct
            };

            asset = new Asset(
                Name = 'GW5981 Asset',
                AccountId = account.Id,
                Product2Id = parentProduct.Id,
                ServiceBOM__c = serviceBom.Id
            );
            insert asset;

            insert new List<ProductRelatedMaterial>{
                component(part, 20),
                component(inactivePart, 30),
                component(serviceProduct, 40)
            };

            workOrder = new WorkOrder(
                AccountId = account.Id,
                Subject = 'GW5981 Parts',
                Status = 'Repair',
                AssetId = asset.Id,
                RepairCenter__c = repairCenter.Id,
                Product__c = useWorkOrderProduct ? parentProduct.Id : null
            );
            insert workOrder;
            return this;
        }

        private ProductRelatedMaterial component(Product2 componentProduct, Decimal sequence) {
            return new ProductRelatedMaterial(
                Name = 'BOM ' + componentProduct.ProductCode,
                ServiceBOM__c = serviceBom.Id,
                ProductId = parentProduct.Id,
                ProductComponentId = componentProduct.Id,
                QuantityPerProductUnit = 1,
                ComponentSequence__c = sequence
            );
        }
    }

    private static Product2 product(
        String name,
        String productCode,
        String productType,
        Boolean isActive,
        String description
    ) {
        return new Product2(
            Name = name,
            ProductCode = productCode,
            ProductType__c = productType,
            IsActive = isActive,
            Description = description
        );
    }
}