/**
 * @description Tests for ConsolidateVendorShipmentController.
 * @author Uptima Development Team
 * @date 2026-08-13
 */
@IsTest
private class ConsolidateVendorShipmentControllerTest {
    private static final String WO_SUB_STATUS_SHIP_TO_VENDOR = 'Ship to Vendor';

    @TestSetup
    static void setupData() {
        Account customer = new Account(
            Name = 'Customer Consolidate Test',
            SystemID__c = 'LEG-CVS-CUST',
            SourceSystemID__c = 'TEST-ORACLE-CVS-CUST',
            OrgIDs__c = '82'
        );
        Account vendor = new Account(
            Name = 'Vendor Consolidate Test',
            SystemID__c = 'LEG-CVS-1001',
            SourceSystemID__c = 'TEST-ORACLE-CVS-001',
            OrgIDs__c = '82',
            BillingStreet = '100 Vendor Lane',
            BillingCity = 'Cleveland',
            BillingStateCode = 'OH',
            BillingPostalCode = '44114',
            BillingCountryCode = 'US'
        );
        Account vendorTwo = new Account(
            Name = 'Vendor Two Consolidate Test',
            SystemID__c = 'LEG-CVS-1002',
            SourceSystemID__c = 'TEST-ORACLE-CVS-002',
            OrgIDs__c = '82',
            BillingStreet = '200 Vendor Ave',
            BillingCity = 'Columbus',
            BillingStateCode = 'OH',
            BillingPostalCode = '43215',
            BillingCountryCode = 'US'
        );
        insert new List<Account>{ customer, vendor, vendorTwo };

        Product2 defaultProduct = new Product2(
            Name = 'Default Product',
            ProductCode = 'CVS-DEFAULT',
            IsActive = true
        );
        Product2 lineProduct = new Product2(
            Name = 'CVS Line Product',
            ProductCode = 'CVS-LINE-001',
            Description = 'CVS Line Product Description',
            Model__c = 'MODEL-CVS-1',
            IsActive = true
        );
        lineProduct.put('ProductLine__c', 'CVS-PL');
        insert new List<Product2>{ defaultProduct, lineProduct };

        Id standardPricebookId = Test.getStandardPricebookId();
        insert new List<PricebookEntry>{
            new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id = defaultProduct.Id,
                UnitPrice = 1,
                IsActive = true
            ),
            new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id = lineProduct.Id,
                UnitPrice = 1,
                IsActive = true
            )
        };
        PricebookEntry linePbe = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :lineProduct.Id
            AND Pricebook2Id = :standardPricebookId
            LIMIT 1
        ];

        Schema.Location repairCenter = new Schema.Location(
            Name = 'CVS Test Repair Center',
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert repairCenter;

        Schema.SObjectType addressType = Schema.getGlobalDescribe().get('Address');
        SObject repairCenterAddress = addressType.newSObject();
        repairCenterAddress.put('ParentId', repairCenter.Id);
        repairCenterAddress.put('LocationType', 'Business');
        repairCenterAddress.put('Street', '5960 Heisley Road');
        repairCenterAddress.put('City', 'Mentor');
        repairCenterAddress.put('StateCode', 'OH');
        repairCenterAddress.put('PostalCode', '44060');
        repairCenterAddress.put('CountryCode', 'US');
        insert repairCenterAddress;

        insert new ServiceResource(
            Name = 'CVS Test Service Resource',
            RelatedRecordId = UserInfo.getUserId(),
            LocationId = repairCenter.Id,
            IsActive = true,
            ResourceType = 'T'
        );
        ServiceResource testResource = [
            SELECT Id
            FROM ServiceResource
            WHERE RelatedRecordId = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        testResource.put('RepairCenter__c', repairCenter.Id);
        update testResource;

        ReturnOrder parentRo = new ReturnOrder(
            AccountId = customer.Id,
            Status = 'Created',
            DestinationLocationId = repairCenter.Id,
            CreationSource__c = 'Salesforce'
        );
        parentRo.put('OperatingUnit__c', '82');
        parentRo.put('ReturnOrderType__c', 'Serialized');
        parentRo.put('CustomerPO__c', 'PO-PARENT-001');
        parentRo.put('CustomerReference__c', 'CREF-PARENT-001');
        parentRo.put('HospitalReferencedTrayName__c', 'Tray Parent');
        parentRo.put('WarrantyNotes__c', 'Parent warranty notes');
        insert parentRo;

        ReturnOrderLineItem parentRoli = new ReturnOrderLineItem(
            ReturnOrderId = parentRo.Id,
            Product2Id = lineProduct.Id,
            QuantityReturned = 1
        );
        parentRoli.put('Model__c', 'MODEL-CVS-1');
        parentRoli.put('CustomerPO__c', 'PO-LINE-001');
        parentRoli.put('Status__c', 'Created');
        insert parentRoli;

        Id otherRtId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterVendor')
            ?.getRecordTypeId();

        WorkOrder parentWo = new WorkOrder(
            Subject = 'CVS Parent WO',
            Status = 'Received',
            AccountId = customer.Id,
            RepairCenter__c = repairCenter.Id,
            Pricebook2Id = standardPricebookId
        );
        insert parentWo;

        // Org RT picklist matrix allows Ship to Vendor under Status=Received.
        // List filters Other RT Vendor WOs.
        WorkOrder wo1 = new WorkOrder(
            Subject = 'CVS Vendor WO 1',
            Status = 'Received',
            AccountId = customer.Id,
            Vendor__c = vendor.Id,
            RepairCenter__c = repairCenter.Id,
            ParentWorkOrderId = parentWo.Id,
            Product__c = lineProduct.Id,
            Pricebook2Id = standardPricebookId
        );
        if (otherRtId != null) {
            wo1.RecordTypeId = otherRtId;
        }
        wo1.put('SubStatus__c', WO_SUB_STATUS_SHIP_TO_VENDOR);
        // Parent Customer RO via standard ROLI link (ReturnOrderId is not writeable).
        // Customer RO on ReturnOrder__c must not hide these WOs from the consolidate list (GW-5298).
        wo1.ReturnOrderLineItemId = parentRoli.Id;
        wo1.put('ReturnOrder__c', parentRo.Id);
        wo1.put('CustomerPO__c', 'PO-WO-001');
        wo1.put('InstructionsToVendor__c', 'Handle with care');
        wo1.put('VendorNotes__c', 'Vendor note');
        wo1.put('VendorReferenceNumber__c', 'VREF-001');
        wo1.put('VendorCost__c', 25.50);

        WorkOrder wo2 = new WorkOrder(
            Subject = 'CVS Vendor WO 2',
            Status = 'Received',
            AccountId = customer.Id,
            Vendor__c = vendor.Id,
            RepairCenter__c = repairCenter.Id,
            Product__c = lineProduct.Id,
            Pricebook2Id = standardPricebookId
        );
        if (otherRtId != null) {
            wo2.RecordTypeId = otherRtId;
        }
        wo2.put('SubStatus__c', WO_SUB_STATUS_SHIP_TO_VENDOR);
        wo2.ReturnOrderLineItemId = parentRoli.Id;
        wo2.put('ReturnOrder__c', parentRo.Id);
        wo2.put('CustomerPO__c', 'PO-WO-001');
        wo2.put('InstructionsToVendor__c', 'Handle with care');
        wo2.put('VendorNotes__c', 'Vendor note');
        wo2.put('VendorReferenceNumber__c', 'VREF-001');
        wo2.put('VendorCost__c', 25.50);

        WorkOrder woOtherVendor = new WorkOrder(
            Subject = 'CVS Vendor WO Other',
            Status = 'Received',
            AccountId = customer.Id,
            Vendor__c = vendorTwo.Id,
            RepairCenter__c = repairCenter.Id,
            Product__c = lineProduct.Id,
            Pricebook2Id = standardPricebookId
        );
        if (otherRtId != null) {
            woOtherVendor.RecordTypeId = otherRtId;
        }
        woOtherVendor.put('SubStatus__c', WO_SUB_STATUS_SHIP_TO_VENDOR);
        woOtherVendor.ReturnOrderLineItemId = parentRoli.Id;
        woOtherVendor.put('ReturnOrder__c', parentRo.Id);
        woOtherVendor.put('CustomerPO__c', 'PO-WO-OTHER');
        woOtherVendor.put('InstructionsToVendor__c', 'Handle with care');
        woOtherVendor.put('VendorNotes__c', 'Vendor note');
        woOtherVendor.put('VendorReferenceNumber__c', 'VREF-001');
        woOtherVendor.put('VendorCost__c', 25.50);

        insert new List<WorkOrder>{ wo1, wo2, woOtherVendor };

        List<WorkOrderLineItem> wolis = new List<WorkOrderLineItem>();
        for (WorkOrder wo : new List<WorkOrder>{ wo1, wo2, woOtherVendor }) {
            WorkOrderLineItem woli = new WorkOrderLineItem(
                WorkOrderId = wo.Id,
                PricebookEntryId = linePbe.Id,
                Quantity = 1
            );
            woli.put('Product__c', lineProduct.Id);
            woli.put('Model__c', 'MODEL-CVS-1');
            woli.put('SerialNumber__c', 'SN-CVS-1');
            woli.ReturnOrderLineItemId = parentRoli.Id;
            // Intentionally different from WO — ROLI mapping must use Work Order values.
            woli.put('InstructionsToVendor__c', 'WOLI should be ignored');
            woli.put('VendorNotes__c', 'WOLI note ignored');
            woli.put('VendorReferenceNumber__c', 'WOLI-VREF');
            woli.put('VendorCost__c', 99.99);
            wolis.add(woli);
        }
        insert wolis;
    }

    @IsTest
    static void testGetVendorWorkOrders_returnsOutsideVendorRows() {
        // Setup — TestSetup links the running user to a Repair Center via Service Resource

        // When
        Test.startTest();
        ConsolidateVendorShipmentController.InitResult result =
            ConsolidateVendorShipmentController.getVendorWorkOrders();
        Test.stopTest();

        // Then
        System.assertEquals(null, result.errorMessage);
        System.assertNotEquals(null, result.repairCenterId);
        System.assertEquals(3, result.workOrders.size());
        System.assertNotEquals(null, result.workOrders[0].workOrderNumber);
        System.assertEquals(WO_SUB_STATUS_SHIP_TO_VENDOR, result.workOrders[0].subStatus);
    }

    @IsTest
    static void testGetVendorWorkOrders_excludesVendorReturnOrderNotCustomerReturnOrder() {
        ReturnOrder parentRo = [
            SELECT Id
            FROM ReturnOrder
            WHERE CustomerPO__c = 'PO-PARENT-001'
            LIMIT 1
        ];
        WorkOrder alreadyVendorShipped = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'CVS Vendor WO 1'
            LIMIT 1
        ];
        alreadyVendorShipped.put('VendorReturnOrder__c', parentRo.Id);
        update alreadyVendorShipped;

        Test.startTest();
        ConsolidateVendorShipmentController.InitResult result =
            ConsolidateVendorShipmentController.getVendorWorkOrders();
        Test.stopTest();

        System.assertEquals(null, result.errorMessage);
        System.assertEquals(2, result.workOrders.size());
        for (ConsolidateVendorShipmentController.WorkOrderRow row : result.workOrders) {
            System.assertNotEquals(alreadyVendorShipped.Id, row.id);
        }
    }

    @IsTest
    static void testGetVendorWorkOrders_missingRepairCenter() {
        List<ServiceResource> resources = [
            SELECT Id, IsActive
            FROM ServiceResource
            WHERE RelatedRecordId = :UserInfo.getUserId()
        ];
        for (ServiceResource resource : resources) {
            resource.IsActive = false;
        }
        update resources;

        Test.startTest();
        ConsolidateVendorShipmentController.InitResult result =
            ConsolidateVendorShipmentController.getVendorWorkOrders();
        Test.stopTest();

        System.assertNotEquals(null, result.errorMessage);
        System.assertEquals(0, result.workOrders.size());
    }

    @IsTest
    static void testCompleteShipment_createsVendorReturnOrders() {
        ReturnOrder parentRo = [
            SELECT Id
            FROM ReturnOrder
            WHERE CustomerPO__c = 'PO-PARENT-001'
            LIMIT 1
        ];
        List<WorkOrder> workOrders = [
            SELECT Id, Vendor__c, ReturnOrder__c
            FROM WorkOrder
            WHERE SubStatus__c = :WO_SUB_STATUS_SHIP_TO_VENDOR
            ORDER BY Vendor__r.Name, WorkOrderNumber
        ];
        System.assertEquals(3, workOrders.size());

        // Same-vendor validation: select only the primary vendor's work orders.
        Id primaryVendorId = workOrders[0].Vendor__c;
        List<Id> selectedIds = new List<Id>();
        for (WorkOrder wo : workOrders) {
            if (wo.Vendor__c == primaryVendorId) {
                selectedIds.add(wo.Id);
            }
        }
        System.assertEquals(2, selectedIds.size());

        // When
        Test.startTest();
        ConsolidateVendorShipmentController.CompleteResult result =
            ConsolidateVendorShipmentController.completeShipment(selectedIds);
        Test.stopTest();

        // Then
        System.assertEquals(1, result.returnOrderIds.size(), 'One RO for the single vendor');
        System.assertEquals(2, result.workOrderCount);

        Id vendorReturnRtId = Schema.SObjectType.ReturnOrder.getRecordTypeInfosByDeveloperName()
            .get('VendorReturn')
            .getRecordTypeId();
        Id outboundRtId = Schema.SObjectType.ReturnOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get('Outbound')
            .getRecordTypeId();
        Id inboundRtId = Schema.SObjectType.ReturnOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get('Inbound')
            .getRecordTypeId();

        List<ReturnOrder> createdOrders = [
            SELECT
                Id,
                AccountId,
                Status,
                RecordTypeId,
                SourceLocationId,
                DestinationLocationId,
                CreationSource__c,
                WorkOrder__c,
                OperatingUnit__c,
                ParentReturnOrder__c,
                ReturnOrderType__c,
                CustomerPO__c,
                CustomerReference__c,
                HospitalReferencedTrayName__c,
                WarrantyNotes__c
            FROM ReturnOrder
            WHERE Id IN :result.returnOrderIds
        ];
        System.assertEquals(1, createdOrders.size());
        for (ReturnOrder ro : createdOrders) {
            System.assertEquals(vendorReturnRtId, ro.RecordTypeId);
            System.assertEquals('Created', ro.Status);
            System.assertEquals('Salesforce', ro.CreationSource__c);
            System.assertNotEquals(null, ro.SourceLocationId);
            System.assertEquals(ro.DestinationLocationId, ro.SourceLocationId);
            System.assertEquals('82', ro.OperatingUnit__c);
            System.assertEquals(parentRo.Id, ro.ParentReturnOrder__c);
            System.assertEquals('Vendor', ro.ReturnOrderType__c);
            System.assertEquals('PO-WO-001', ro.CustomerPO__c);
            System.assertNotEquals('PO-PARENT-001', ro.CustomerPO__c);
            System.assertEquals('CREF-PARENT-001', ro.CustomerReference__c);
            System.assertEquals('Tray Parent', ro.HospitalReferencedTrayName__c);
            System.assertEquals('Parent warranty notes', ro.WarrantyNotes__c);
        }

        List<ReturnOrderLineItem> lines = [
            SELECT
                Id,
                ReturnOrderId,
                RecordTypeId,
                QuantityReturned,
                ParentROLI__c,
                Product2Id,
                Model__c,
                LineType__c,
                ProductLine__c,
                InstructionsToVendor__c,
                VendorNotes__c,
                VendorReferenceNumber__c,
                VendorCost__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId IN :result.returnOrderIds
        ];
        // One Outbound + one Inbound per selected WO's WOLI (2 WOs x 1 WOLI => 4 lines)
        System.assertEquals(4, lines.size(), 'Two ROLIs per selected work order line item');

        Integer outboundCount = 0;
        Integer inboundCount = 0;
        for (ReturnOrderLineItem line : lines) {
            System.assertNotEquals(null, line.Product2Id);
            System.assertEquals('MODEL-CVS-1', line.Model__c);
            System.assertEquals('Handle with care', line.InstructionsToVendor__c);
            System.assertEquals('Vendor note', line.VendorNotes__c);
            System.assertEquals('VREF-001', line.VendorReferenceNumber__c);
            System.assertEquals(25.50, line.VendorCost__c);
            if (line.RecordTypeId == outboundRtId) {
                outboundCount++;
                System.assertEquals('Outbound', line.LineType__c);
                System.assertEquals(null, line.ParentROLI__c);
            } else if (line.RecordTypeId == inboundRtId) {
                inboundCount++;
                System.assertEquals('Inbound', line.LineType__c);
                System.assertNotEquals(null, line.ParentROLI__c);
            }
        }
        System.assertEquals(2, outboundCount);
        System.assertEquals(2, inboundCount);

        List<WorkOrder> afterComplete = [
            SELECT Id, Status, SubStatus__c, ReturnOrder__c, VendorReturnOrder__c
            FROM WorkOrder
            WHERE Id IN :selectedIds
        ];
        for (WorkOrder wo : afterComplete) {
            System.assertEquals(
                'Ship to Vendor',
                wo.Status,
                'Source WO Status must be set to Ship to Vendor after Complete'
            );
            System.assertEquals(
                null,
                wo.SubStatus__c,
                'Source WO Sub Status must be cleared after Complete'
            );
            System.assertEquals(
                parentRo.Id,
                wo.ReturnOrder__c,
                'Customer Return Order on the Vendor WO must be unchanged'
            );
            System.assertEquals(
                result.returnOrderIds[0],
                wo.VendorReturnOrder__c,
                'Source WO Vendor Return Order must point to the new Vendor RO'
            );
        }

        ReturnOrderLineItem parentRoli = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :parentRo.Id
            LIMIT 1
        ];
        List<WorkOrderLineItem> linkedWolis = [
            SELECT
                Id,
                ReturnOrderId,
                ReturnOrderLineItemId,
                VendorReturnOrder__c,
                VendorReturnOrderLineItem__c,
                WorkOrderId
            FROM WorkOrderLineItem
            WHERE WorkOrderId IN :selectedIds
        ];
        System.assertEquals(2, linkedWolis.size());
        for (WorkOrderLineItem woli : linkedWolis) {
            System.assertEquals(
                parentRoli.Id,
                woli.ReturnOrderLineItemId,
                'Customer ROLI on the Vendor WOLI must be unchanged'
            );
            System.assertEquals(result.returnOrderIds[0], woli.VendorReturnOrder__c);
            System.assertNotEquals(null, woli.VendorReturnOrderLineItem__c);
        }

        List<ReturnOrderLineItem> vendorMappedLines = [
            SELECT
                InstructionsToVendor__c,
                VendorNotes__c,
                VendorReferenceNumber__c,
                VendorCost__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId IN :result.returnOrderIds
        ];
        for (ReturnOrderLineItem line : vendorMappedLines) {
            System.assertEquals('Handle with care', line.InstructionsToVendor__c);
            System.assertEquals('Vendor note', line.VendorNotes__c);
            System.assertEquals('VREF-001', line.VendorReferenceNumber__c);
            System.assertEquals(25.50, line.VendorCost__c);
        }

        List<ReturnOrder> shippedOrders = [
            SELECT Id, ReturnOrderNumber, InboundTrackingNumber__c
            FROM ReturnOrder
            WHERE Id IN :result.returnOrderIds
        ];
        for (ReturnOrder ro : shippedOrders) {
            System.assertEquals(
                '794900000000',
                ro.InboundTrackingNumber__c,
                'FedEx tracking should be stored on the Vendor Return Order'
            );
        }

        List<WorkOrder> trackedWorkOrders = [
            SELECT Id, TrackingNumber__c
            FROM WorkOrder
            WHERE Id IN :selectedIds
        ];
        for (WorkOrder wo : trackedWorkOrders) {
            System.assertEquals(
                '794900000000',
                wo.TrackingNumber__c,
                'Tracking should be copied to each vendor work order'
            );
        }

        List<ContentVersion> shipmentFiles = [
            SELECT Title, PathOnClient, FileExtension
            FROM ContentVersion
            WHERE
                CreatedById = :UserInfo.getUserId()
                AND (Title LIKE 'Shipping Label%' OR Title LIKE 'Packing Slip%')
        ];
        System.assertEquals(
            2,
            shipmentFiles.size(),
            'Each Vendor RO should receive a shipping label and packing slip'
        );
        Boolean foundPackingSlipPdf = false;
        for (ContentVersion file : shipmentFiles) {
            if (file.Title != null && file.Title.startsWith('Packing Slip')) {
                foundPackingSlipPdf = true;
                System.assertEquals(
                    'pdf',
                    file.FileExtension,
                    'Packing slip must be stored as PDF'
                );
                System.assert(
                    file.PathOnClient != null && file.PathOnClient.endsWith('.pdf'),
                    file.PathOnClient
                );
            }
        }
        System.assertEquals(true, foundPackingSlipPdf, 'Packing slip PDF should be attached');
    }

    @IsTest
    static void testCompleteShipment_multipleVendors_throws() {
        List<WorkOrder> workOrders = [
            SELECT Id
            FROM WorkOrder
            WHERE SubStatus__c = :WO_SUB_STATUS_SHIP_TO_VENDOR
        ];
        System.assertEquals(3, workOrders.size());

        List<Id> selectedIds = new List<Id>();
        for (WorkOrder wo : workOrders) {
            selectedIds.add(wo.Id);
        }

        Boolean threw = false;
        try {
            Test.startTest();
            ConsolidateVendorShipmentController.completeShipment(selectedIds);
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(
                e.getMessage().contains('same Vendor') ||
                    e.getMessage().contains('Script-thrown exception'),
                e.getMessage()
            );
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testCompleteShipment_alreadyHasVendorReturnOrder_throws() {
        ReturnOrder parentRo = [
            SELECT Id
            FROM ReturnOrder
            WHERE CustomerPO__c = 'PO-PARENT-001'
            LIMIT 1
        ];
        WorkOrder wo = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'CVS Vendor WO 1'
            LIMIT 1
        ];
        wo.put('VendorReturnOrder__c', parentRo.Id);
        update wo;

        Boolean threw = false;
        try {
            Test.startTest();
            ConsolidateVendorShipmentController.completeShipment(new List<Id>{ wo.Id });
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(
                e.getMessage().contains('Vendor Return Order') ||
                    e.getMessage().contains('Script-thrown exception'),
                e.getMessage()
            );
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testCompleteShipment_missingVendorAddress_throws() {
        Account vendor = [
            SELECT Id
            FROM Account
            WHERE Name = 'Vendor Consolidate Test'
            LIMIT 1
        ];
        vendor.BillingStreet = null;
        vendor.BillingCity = null;
        vendor.BillingState = null;
        vendor.BillingStateCode = null;
        vendor.BillingPostalCode = null;
        vendor.BillingCountry = null;
        vendor.BillingCountryCode = null;
        vendor.ShippingStreet = null;
        vendor.ShippingCity = null;
        vendor.ShippingState = null;
        vendor.ShippingStateCode = null;
        vendor.ShippingPostalCode = null;
        vendor.ShippingCountry = null;
        vendor.ShippingCountryCode = null;
        update vendor;

        WorkOrder wo = [
            SELECT Id
            FROM WorkOrder
            WHERE Vendor__c = :vendor.Id AND SubStatus__c = :WO_SUB_STATUS_SHIP_TO_VENDOR
            LIMIT 1
        ];

        Boolean threw = false;
        try {
            Test.startTest();
            ConsolidateVendorShipmentController.completeShipment(new List<Id>{ wo.Id });
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(
                e.getMessage().contains('address') ||
                    e.getMessage().contains('Script-thrown exception'),
                e.getMessage()
            );
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testCompleteShipment_incompleteVendorAddress_throws() {
        Account vendor = [
            SELECT Id
            FROM Account
            WHERE Name = 'Vendor Consolidate Test'
            LIMIT 1
        ];
        // Street only — FedEx HTTP 400 for missing City / State / PostalCode.
        vendor.BillingStreet = '100 Vendor Lane';
        vendor.BillingCity = null;
        vendor.BillingState = null;
        vendor.BillingStateCode = null;
        vendor.BillingPostalCode = null;
        vendor.BillingCountry = null;
        vendor.BillingCountryCode = null;
        vendor.ShippingStreet = null;
        vendor.ShippingCity = null;
        vendor.ShippingState = null;
        vendor.ShippingStateCode = null;
        vendor.ShippingPostalCode = null;
        vendor.ShippingCountry = null;
        vendor.ShippingCountryCode = null;
        update vendor;

        WorkOrder wo = [
            SELECT Id
            FROM WorkOrder
            WHERE Vendor__c = :vendor.Id AND SubStatus__c = :WO_SUB_STATUS_SHIP_TO_VENDOR
            LIMIT 1
        ];

        Boolean threw = false;
        try {
            Test.startTest();
            ConsolidateVendorShipmentController.completeShipment(new List<Id>{ wo.Id });
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(
                e.getMessage().contains('incomplete') ||
                    e.getMessage().contains('address') ||
                    e.getMessage().contains('Script-thrown exception'),
                e.getMessage()
            );
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testCompleteShipment_missingRepairCenterAddress_throws() {
        Schema.Location repairCenter = [
            SELECT Id
            FROM Location
            WHERE Name = 'CVS Test Repair Center'
            LIMIT 1
        ];
        List<SObject> addresses = Database.query(
            'SELECT Id FROM Address WHERE ParentId = \'' +
                String.escapeSingleQuotes(repairCenter.Id) +
                '\''
        );
        if (!addresses.isEmpty()) {
            delete addresses;
        }

        WorkOrder wo = [
            SELECT Id
            FROM WorkOrder
            WHERE SubStatus__c = :WO_SUB_STATUS_SHIP_TO_VENDOR
            LIMIT 1
        ];

        Boolean threw = false;
        try {
            Test.startTest();
            ConsolidateVendorShipmentController.completeShipment(new List<Id>{ wo.Id });
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(
                e.getMessage().contains('Repair Center') ||
                    e.getMessage().contains('Script-thrown exception'),
                e.getMessage()
            );
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testGetVendorWorkOrders_usesRelatedAddress() {
        Account vendor = [
            SELECT Id
            FROM Account
            WHERE Name = 'Vendor Consolidate Test'
            LIMIT 1
        ];
        vendor.BillingStreet = null;
        vendor.BillingCity = null;
        vendor.BillingState = null;
        vendor.BillingStateCode = null;
        vendor.BillingPostalCode = null;
        vendor.BillingCountry = null;
        vendor.BillingCountryCode = null;
        vendor.ShippingStreet = null;
        vendor.ShippingCity = null;
        vendor.ShippingState = null;
        vendor.ShippingStateCode = null;
        vendor.ShippingPostalCode = null;
        vendor.ShippingCountry = null;
        vendor.ShippingCountryCode = null;
        update vendor;

        Schema.Location repairCenter = [
            SELECT Id
            FROM Location
            WHERE Name = 'CVS Test Repair Center'
            LIMIT 1
        ];

        SObject relatedAddress = Schema.getGlobalDescribe().get('Address').newSObject();
        relatedAddress.put('ParentId', repairCenter.Id);
        relatedAddress.put('Customer__c', vendor.Id);
        relatedAddress.put('LocationType', 'Business');
        relatedAddress.put('Street', '500 Related Vendor Way');
        relatedAddress.put('City', 'Cleveland');
        relatedAddress.put('StateCode', 'OH');
        relatedAddress.put('PostalCode', '44114');
        relatedAddress.put('CountryCode', 'US');
        insert relatedAddress;

        Test.startTest();
        ConsolidateVendorShipmentController.InitResult result =
            ConsolidateVendorShipmentController.getVendorWorkOrders();
        Test.stopTest();

        System.assertEquals(null, result.errorMessage);
        Boolean foundRelatedAddress = false;
        for (ConsolidateVendorShipmentController.WorkOrderRow row : result.workOrders) {
            if (row.vendorId == vendor.Id) {
                System.assertEquals(true, row.hasVendorAddress);
                System.assert(
                    row.vendorAddress != null && row.vendorAddress.contains('500 Related Vendor Way'),
                    row.vendorAddress
                );
                foundRelatedAddress = true;
            }
        }
        System.assertEquals(true, foundRelatedAddress);
    }

    @IsTest
    static void testCompleteShipment_emptySelection_throws() {
        Boolean threw = false;
        try {
            Test.startTest();
            ConsolidateVendorShipmentController.completeShipment(new List<Id>());
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(
                e.getMessage().contains('at least one') ||
                e.getMessage().contains('Script-thrown exception'),
                e.getMessage()
            );
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testCompleteShipment_missingVendor_throws() {
        WorkOrder wo = [
            SELECT Id
            FROM WorkOrder
            WHERE SubStatus__c = :WO_SUB_STATUS_SHIP_TO_VENDOR
            LIMIT 1
        ];
        wo.Vendor__c = null;
        update wo;

        Boolean threw = false;
        try {
            Test.startTest();
            ConsolidateVendorShipmentController.completeShipment(new List<Id>{ wo.Id });
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testPackingSlip_containsTrackingAndWorkOrder() {
        ReturnOrder parentRo = [
            SELECT
                Id,
                ReturnOrderNumber,
                AccountId,
                Account.Name,
                Account.AccountNumber,
                SalesRep__r.Name
            FROM ReturnOrder
            WHERE CustomerPO__c = 'PO-PARENT-001'
            LIMIT 1
        ];
        List<WorkOrder> workOrders = [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE SubStatus__c = :WO_SUB_STATUS_SHIP_TO_VENDOR
            LIMIT 1
        ];

        Blob packingSlip = ReturnOrdersService.buildVendorPackingSlip(
            parentRo,
            workOrders,
            null,
            '794912345678'
        );
        System.assertNotEquals(null, packingSlip);
        System.assert(packingSlip.size() > 0, 'Packing slip PDF should have content');

        Product2 lineProduct = [
            SELECT Id, Description
            FROM Product2
            WHERE ProductCode = 'CVS-LINE-001'
            LIMIT 1
        ];
        ReturnOrderLineItem packingLine = new ReturnOrderLineItem(
            ReturnOrderId = parentRo.Id,
            Product2Id = lineProduct.Id,
            QuantityReturned = 1
        );
        packingLine.put('Model__c', 'MODEL-CVS-1');
        packingLine.put('SerialNumber__c', 'SN-CVS-PACK');
        insert packingLine;

        packingLine = [
            SELECT
                QuantityReturned,
                SerialNumber__c,
                Model__c,
                Product2.Description
            FROM ReturnOrderLineItem
            WHERE Id = :packingLine.Id
        ];

        String html = ReturnOrdersService.buildVendorPackingSlipHtml(
            parentRo,
            workOrders,
            new List<ReturnOrderLineItem>{ packingLine },
            '794912345678'
        );
        System.assert(html.contains('794912345678'), html);
        System.assert(html.contains('FedEx'), html);
        System.assert(
            html.contains('CVS Line Product Description'),
            'Item column should use Product2.Description'
        );
        System.assert(html.contains('MODEL-CVS-1'), html);
        System.assert(html.contains('SN-CVS-PACK'), html);
    }

    @IsTest
    static void testCreateShipments_missingVendorAddress_throws() {
        Account vendor = [
            SELECT Id
            FROM Account
            WHERE Name = 'Vendor Consolidate Test'
            LIMIT 1
        ];
        vendor.BillingStreet = null;
        vendor.BillingCity = null;
        vendor.BillingState = null;
        vendor.BillingStateCode = null;
        vendor.BillingPostalCode = null;
        vendor.BillingCountry = null;
        vendor.BillingCountryCode = null;
        update vendor;

        Schema.Location repairCenter = [
            SELECT Id
            FROM Location
            WHERE Name = 'CVS Test Repair Center'
            LIMIT 1
        ];
        Id vendorReturnRtId = Schema.SObjectType.ReturnOrder.getRecordTypeInfosByDeveloperName()
            .get('VendorReturn')
            .getRecordTypeId();
        ReturnOrder vendorRo = new ReturnOrder(
            RecordTypeId = vendorReturnRtId,
            AccountId = vendor.Id,
            Status = 'Created',
            SourceLocationId = repairCenter.Id
        );
        vendorRo.put('OperatingUnit__c', '82');
        insert vendorRo;

        Boolean threw = false;
        try {
            // When
            Test.startTest();
            ReturnOrdersService.createVendorFedExShipments(
                new Map<Id, List<Id>>{ vendorRo.Id => new List<Id>() }
            );
            Test.stopTest();
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            threw = true;
            System.assert(
                e.getMessage() != null &&
                    (e.getMessage().contains('ship-to address') ||
                        e.getMessage().contains('incomplete')),
                e.getMessage()
            );
        } catch (Exception e) {
            threw =
                e.getMessage() != null &&
                (e.getMessage().contains('ship-to address') ||
                    e.getMessage().contains('incomplete'));
        }

        // Then
        System.assertEquals(true, threw);
    }

    private class AuraThrowingClient implements ConsolidateVendorShipmentController.IConsolidateVendorShipmentClient {
        public WorkOrdersService.VendorConsolidationInitResult getVendorWorkOrdersForConsolidation() {
            AuraHandledException ex = new AuraHandledException('Forced aura get');
            ex.setMessage('Forced aura get');
            throw ex;
        }

        public ReturnOrdersService.VendorConsolidationCompleteResult completeVendorShipment(
            List<Id> workOrderIds
        ) {
            AuraHandledException ex = new AuraHandledException('Forced aura complete');
            ex.setMessage('Forced aura complete');
            throw ex;
        }
    }

    private class GenericThrowingClient implements ConsolidateVendorShipmentController.IConsolidateVendorShipmentClient {
        public WorkOrdersService.VendorConsolidationInitResult getVendorWorkOrdersForConsolidation() {
            throw new System.NullPointerException();
        }

        public ReturnOrdersService.VendorConsolidationCompleteResult completeVendorShipment(
            List<Id> workOrderIds
        ) {
            throw new System.NullPointerException();
        }
    }

    private class DmlThrowingClient implements ConsolidateVendorShipmentController.IConsolidateVendorShipmentClient {
        public WorkOrdersService.VendorConsolidationInitResult getVendorWorkOrdersForConsolidation() {
            return WorkOrdersService.getVendorWorkOrdersForConsolidation();
        }

        public ReturnOrdersService.VendorConsolidationCompleteResult completeVendorShipment(
            List<Id> workOrderIds
        ) {
            // Force a DmlException so the controller DmlException catch is covered.
            insert new Account();
            return null;
        }
    }

    @IsTest
    static void testGetVendorWorkOrders_WhenAuraThrows_Rethrows() {
        ConsolidateVendorShipmentController.clientOverride = new AuraThrowingClient();
        Boolean threw = false;
        Test.startTest();
        try {
            ConsolidateVendorShipmentController.getVendorWorkOrders();
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testGetVendorWorkOrders_WhenUnexpectedThrows_WrapsAura() {
        ConsolidateVendorShipmentController.clientOverride = new GenericThrowingClient();
        Boolean threw = false;
        Test.startTest();
        try {
            ConsolidateVendorShipmentController.getVendorWorkOrders();
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(
                e.getMessage().contains('Error loading vendor work orders') ||
                    e.getMessage().contains('Script-thrown exception'),
                e.getMessage()
            );
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testCompleteShipment_WhenAuraThrows_Rethrows() {
        WorkOrder wo = [
            SELECT Id
            FROM WorkOrder
            WHERE SubStatus__c = :WO_SUB_STATUS_SHIP_TO_VENDOR
            LIMIT 1
        ];
        ConsolidateVendorShipmentController.clientOverride = new AuraThrowingClient();
        Boolean threw = false;
        Test.startTest();
        try {
            ConsolidateVendorShipmentController.completeShipment(new List<Id>{ wo.Id });
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testCompleteShipment_WhenUnexpectedThrows_WrapsAura() {
        WorkOrder wo = [
            SELECT Id
            FROM WorkOrder
            WHERE SubStatus__c = :WO_SUB_STATUS_SHIP_TO_VENDOR
            LIMIT 1
        ];
        ConsolidateVendorShipmentController.clientOverride = new GenericThrowingClient();
        Boolean threw = false;
        Test.startTest();
        try {
            ConsolidateVendorShipmentController.completeShipment(new List<Id>{ wo.Id });
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(
                e.getMessage().contains('Error creating vendor return order') ||
                    e.getMessage().contains('Script-thrown exception'),
                e.getMessage()
            );
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testCompleteShipment_WhenDmlThrows_WrapsAura() {
        WorkOrder wo = [
            SELECT Id
            FROM WorkOrder
            WHERE SubStatus__c = :WO_SUB_STATUS_SHIP_TO_VENDOR
            LIMIT 1
        ];
        ConsolidateVendorShipmentController.clientOverride = new DmlThrowingClient();
        Boolean threw = false;
        Test.startTest();
        try {
            ConsolidateVendorShipmentController.completeShipment(new List<Id>{ wo.Id });
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(
                e.getMessage().contains('Error creating vendor return order') ||
                    e.getMessage().contains('Script-thrown exception'),
                e.getMessage()
            );
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }
}