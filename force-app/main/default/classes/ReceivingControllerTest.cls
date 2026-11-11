/**
 * @description Thin controller tests for ReceivingController (GW-5492).
 */
@IsTest
private class ReceivingControllerTest {
    @TestSetup
    static void setupTestData() {
        adb_Account accountBuilder = new adb_Account().name('GW5492 Controller Account');
        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        returnOrderBuilder.recordType('CustomerReturn');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Serialized');

        adb_Product2 productBuilder = new adb_Product2()
            .name('GW5492 Controller Product')
            .isActive(true);
        Product2 product = (Product2) productBuilder.persist();
        ensureReceivingPricebooksForProduct(product.Id);

        adb_ReturnOrderLineItem lineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        lineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        lineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        lineBuilder.persist();
    }

    /**
     * @description Seeds Standard + IMS Service Pricebook entries for finish receiving.
     * @param productId Product that will be received onto a Work Order
     */
    private static void ensureReceivingPricebooksForProduct(Id productId) {
        ReceivingFinishService.resetDefaultPricebookCacheForTest();
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);
        Integer standardCount = [
            SELECT COUNT()
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPricebookId
            AND Product2Id = :productId
        ];
        if (standardCount == 0) {
            insert new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id = productId,
                UnitPrice = 1,
                IsActive = true
            );
        }

        List<Pricebook2> servicePricebooks = [
            SELECT Id
            FROM Pricebook2
            WHERE Name = 'IMS Service Pricebook'
            AND IsActive = TRUE
            LIMIT 1
        ];
        Id servicePricebookId;
        if (servicePricebooks.isEmpty()) {
            Pricebook2 servicePricebook = new Pricebook2(
                Name = 'IMS Service Pricebook',
                IsActive = true
            );
            insert servicePricebook;
            servicePricebookId = servicePricebook.Id;
        } else {
            servicePricebookId = servicePricebooks[0].Id;
        }

        Integer serviceCount = [
            SELECT COUNT()
            FROM PricebookEntry
            WHERE Pricebook2Id = :servicePricebookId
            AND Product2Id = :productId
        ];
        if (serviceCount == 0) {
            insert new PricebookEntry(
                Pricebook2Id = servicePricebookId,
                Product2Id = productId,
                UnitPrice = 1,
                IsActive = true
            );
        }
    }

    @IsTest
    static void testResolveScanInput_delegates() {
        ReturnOrder returnOrder = [
            SELECT Id, ReturnOrderNumber
            FROM ReturnOrder
            LIMIT 1
        ];

        Test.startTest();
        ReceivingService.ScanResolveResult result =
            ReceivingController.resolveScanInput(returnOrder.ReturnOrderNumber);
        Test.stopTest();

        Assert.areEqual(returnOrder.Id, result.returnOrderId);
    }

    @IsTest
    static void testSaveWorkOrderQuantityReceived_delegates() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id instrumentsRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterInstruments')
            .getRecordTypeId();
        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Controller Save Qty',
            AccountId = accountRecord.Id,
            RecordTypeId = instrumentsRecordTypeId,
            QuantityReceived__c = 5
        );
        insert workOrder;

        Test.startTest();
        ReceivingController.saveWorkOrderQuantityReceived(workOrder.Id, 6);
        Test.stopTest();

        WorkOrder refreshed = [
            SELECT QuantityReceived__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual(6, refreshed.QuantityReceived__c);
    }

    @IsTest
    static void testGetReceivingShellContext_delegates() {
        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder LIMIT 1];

        Test.startTest();
        ReceivingService.ReceivingShellContext context =
            ReceivingController.getReceivingShellContext(returnOrder.Id);
        Test.stopTest();

        Assert.areEqual(returnOrder.Id, context.returnOrderId);
    }

    @IsTest
    static void testResolveScanInput_error_asAuraHandled() {
        Boolean threw = false;
        Test.startTest();
        try {
            ReceivingController.resolveScanInput('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw);
    }

    @IsTest
    static void testStageModFormPhoto_delegates() {
        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder LIMIT 1];
        String tinyPngBase64 =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

        Test.startTest();
        ReceivingService.ModFormPhoto photo = ReceivingController.stageModFormPhoto(
            returnOrder.Id,
            tinyPngBase64,
            'ModForm-controller.png'
        );
        Test.stopTest();

        Assert.isNotNull(photo.contentDocumentId);
    }

    @IsTest
    static void testRenameModFormPhoto_delegates() {
        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder LIMIT 1];
        String tinyPngBase64 =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
        ReceivingService.ModFormPhoto photo = ReceivingController.stageModFormPhoto(
            returnOrder.Id,
            tinyPngBase64,
            'ModForm-rename-ctrl.png'
        );

        Test.startTest();
        ReceivingService.ModFormPhoto renamed = ReceivingController.renameModFormPhoto(
            returnOrder.Id,
            photo.contentDocumentId,
            'Controller Renamed Title'
        );
        Test.stopTest();

        Assert.areEqual('Controller Renamed Title', renamed.title);
    }

    @IsTest
    static void testStageReceivingPhoto_delegates() {
        String tinyPngBase64 =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

        Test.startTest();
        ReceivingService.ModFormPhoto photo = ReceivingController.stageReceivingPhoto(
            tinyPngBase64,
            'Receive-controller.png'
        );
        ReceivingController.deleteReceivingPhoto(photo.contentDocumentId);
        Test.stopTest();

        Assert.isNotNull(photo.contentDocumentId);
        Integer remaining = [
            SELECT COUNT()
            FROM ContentDocument
            WHERE Id = :photo.contentDocumentId
        ];
        Assert.areEqual(0, remaining);
    }

    @IsTest
    static void testGetRepairCenterOptions_delegates() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Controller Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        Test.startTest();
        List<ReceivingService.PicklistOption> options =
            ReceivingController.getRepairCenterOptions();
        Test.stopTest();

        Assert.isFalse(options.isEmpty());
    }

    @IsTest
    static void testCanCreateNewOrder_delegates() {
        Test.startTest();
        Boolean canCreate = ReceivingController.canCreateNewOrder();
        Test.stopTest();

        Assert.isFalse(canCreate);
    }

    @IsTest
    static void testBuildCreateOrderPlan_delegates() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'DUN-NORTHAMPTON (UK)',
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert repairCenter;

        ServiceResource resource = new ServiceResource(
            Name = 'GW5996 Controller Plan Resource',
            RelatedRecordId = UserInfo.getUserId(),
            LocationId = repairCenter.Id,
            IsActive = true,
            ResourceType = 'T'
        );
        insert resource;
        resource.put('RepairCenter__c', repairCenter.Id);
        update resource;

        String headerJson = JSON.serialize(
            new Map<String, Object>{
                'accountId' => String.valueOf(UserInfo.getUserId()),
                'operatingUnit' => '82',
                'salesRepId' => String.valueOf(UserInfo.getUserId())
            }
        );
        String itemsJson = JSON.serialize(
            new List<Object>{
                new Map<String, Object>{
                    'key' => 'item-1',
                    'productLine' => 'MOBILE VAN',
                    'customerPo' => 'PO-A',
                    'shipToAccountId' => String.valueOf(UserInfo.getUserId()),
                    'serialNumber' => 'SN-A',
                    'model' => 'MODEL-A'
                }
            }
        );

        Test.startTest();
        List<ReceivingService.CreateOrderGroup> groups = ReceivingController.buildCreateOrderPlan(
            headerJson,
            itemsJson
        );
        Test.stopTest();

        Assert.areEqual(1, groups.size());
        Assert.areEqual(1, groups[0].lineCount);
        Assert.areEqual(repairCenter.Id, groups[0].repairCenterId);
    }

    @IsTest
    static void testGetInternalAccountOptions_delegates() {
        adb_Account internalAccountBuilder = new adb_Account()
            .name('GW5492 Controller Internal Account')
            .systemId('LEG5492INT2');
        internalAccountBuilder.set(Account.Type, 'I');
        internalAccountBuilder.set(Account.OrgIDs__c, '82');
        internalAccountBuilder.persist();

        Test.startTest();
        List<ReceivingService.PicklistOption> options =
            ReceivingController.getInternalAccountOptions();
        Test.stopTest();

        Assert.isFalse(options.isEmpty());
    }

    @IsTest
    static void testGetVendorAccountOptions_delegates() {
        adb_Account vendorAccountBuilder = new adb_Account()
            .name('GW5492 Controller Vendor Account')
            .systemId('LEG5492VEN1');
        vendorAccountBuilder.set(Account.Type, 'Vendor');
        vendorAccountBuilder.set(Account.OrgIDs__c, '82');
        vendorAccountBuilder.persist();

        Test.startTest();
        List<ReceivingService.PicklistOption> options =
            ReceivingController.getVendorAccountOptions();
        Test.stopTest();

        Assert.isFalse(options.isEmpty());
    }

    @IsTest
    static void testFinishReceivingItem_delegates() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Controller Finish RC',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder LIMIT 1];
        update new ReturnOrder(Id = returnOrder.Id, DestinationLocationId = repairCenter.Id);
        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            LIMIT 1
        ];

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = returnOrder.Id;
        request.lineItemId = lineItem.Id;
        request.disinfected = 'Clean';
        request.quantityReceived = 1;

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingController.finishReceivingItem(JSON.serialize(request));
        Test.stopTest();

        Assert.isTrue(result.hasWorkOrderCreated);
        Assert.isNotNull(result.workOrderId);
    }

    @IsTest
    static void testApplySerialOverride_delegates() {
        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            LIMIT 1
        ];
        update new ReturnOrderLineItem(Id = lineItem.Id, SerialNumber__c = '05141306');

        Test.startTest();
        ReceivingService.OverrideSerialResult result = ReceivingController.applySerialOverride(
            lineItem.Id,
            '99999999'
        );
        Test.stopTest();

        Assert.isFalse(result.lineUpdated);
        Assert.areEqual('05141306', result.serialNumber);
    }

    @IsTest
    static void testApplyWorkOrderSerialOverride_nullLineItem_throwsAuraHandled() {
        // Setup
        Boolean threw = false;

        // When
        Test.startTest();
        try {
            ReceivingController.applyWorkOrderSerialOverride(null, '05141399', null, null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw, 'Service exception should surface as AuraHandledException');
    }

    @IsTest
    static void testSubmitWorkOrderRerunResiTest_nullWorkOrder_throwsAuraHandled() {
        // Setup
        Boolean threw = false;

        // When
        Test.startTest();
        try {
            ReceivingController.submitWorkOrderRerunResiTest(null, null, true, 'Clean', 1, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw, 'Service exception should surface as AuraHandledException');
    }

    @IsTest
    static void testReprintWorkOrderTravelTag_nullWorkOrder_throwsAuraHandled() {
        // Setup
        Boolean threw = false;

        // When
        Test.startTest();
        try {
            ReceivingController.reprintWorkOrderTravelTag(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw, 'Service exception should surface as AuraHandledException');
    }

    @IsTest
    static void testGetWorkOrderReceivingShellContext_delegates() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id devicesRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices')
            .getRecordTypeId();
        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Controller WO',
            AccountId = accountRecord.Id,
            RecordTypeId = devicesRecordTypeId
        );
        insert workOrder;

        Test.startTest();
        ReceivingService.ReceivingShellContext context =
            ReceivingController.getWorkOrderReceivingShellContext(workOrder.Id);
        Test.stopTest();

        Assert.areEqual(workOrder.Id, context.workOrderId);
        Assert.areEqual('WorkOrder', context.pathType);
    }

    @IsTest
    static void testSubmitVendorWorkOrderReceiving_delegates() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id otherRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterVendor')
            .getRecordTypeId();
        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Controller Vendor WO',
            AccountId = accountRecord.Id,
            RecordTypeId = otherRecordTypeId
        );
        insert workOrder;

        Test.startTest();
        ReceivingController.submitVendorWorkOrderReceiving(workOrder.Id);
        Test.stopTest();

        WorkOrder updated = [SELECT Status FROM WorkOrder WHERE Id = :workOrder.Id];
        Assert.areEqual('Receive from Vendor', updated.Status);
    }

    @IsTest
    static void testFinishReceivingItem_blankJson_throwsAuraHandled() {
        Boolean threw = false;
        Test.startTest();
        try {
            ReceivingController.finishReceivingItem('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Blank finish JSON should throw AuraHandledException');
    }

    @IsTest
    static void testDeleteAndRenameModFormPhoto_delegates() {
        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder LIMIT 1];
        String tinyPngBase64 =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
        ReceivingService.ModFormPhoto photo = ReceivingController.stageModFormPhoto(
            returnOrder.Id,
            tinyPngBase64,
            'ModForm-delete-ctrl.png'
        );

        Test.startTest();
        ReceivingController.deleteModFormPhoto(returnOrder.Id, photo.contentDocumentId);
        Test.stopTest();

        Integer remaining = [
            SELECT COUNT()
            FROM ContentDocument
            WHERE Id = :photo.contentDocumentId
        ];
        Assert.areEqual(0, remaining);
    }

    @IsTest
    static void testRenameAndAttachReceivingPhoto_delegates() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id devicesRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices')
            .getRecordTypeId();
        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5492 Controller Attach Photo',
            AccountId = accountRecord.Id,
            RecordTypeId = devicesRecordTypeId
        );
        insert workOrder;

        String tinyPngBase64 =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
        ReceivingService.ModFormPhoto staged = ReceivingController.stageReceivingPhoto(
            tinyPngBase64,
            'Receive-rename-ctrl.png'
        );

        Test.startTest();
        ReceivingService.ModFormPhoto renamed = ReceivingController.renameReceivingPhoto(
            staged.contentDocumentId,
            'Controller Receive Title'
        );
        ReceivingController.attachReceivingPhotos(
            workOrder.Id,
            new List<Id>{ staged.contentDocumentId }
        );
        Test.stopTest();

        Assert.areEqual('Controller Receive Title', renamed.title);
        Integer links = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :workOrder.Id
              AND ContentDocumentId = :staged.contentDocumentId
        ];
        Assert.areEqual(1, links);
    }

    @IsTest
    static void testControllerMethods_errorPaths_asAuraHandled() {
        Boolean shellThrew = false;
        Boolean qtyThrew = false;
        Boolean woShellThrew = false;
        Boolean vendorThrew = false;
        Boolean deleteModThrew = false;
        Boolean attachThrew = false;
        Boolean deletePhotoThrew = false;
        Boolean renamePhotoThrew = false;
        Boolean serialThrew = false;
        Boolean planThrew = false;
        Boolean submitThrew = false;
        Boolean createWoThrew = false;

        Test.startTest();
        try {
            ReceivingController.getReceivingShellContext(null);
        } catch (AuraHandledException e) {
            shellThrew = true;
        }
        try {
            ReceivingController.saveWorkOrderQuantityReceived(null, 1);
        } catch (AuraHandledException e) {
            qtyThrew = true;
        }
        try {
            ReceivingController.getWorkOrderReceivingShellContext(null);
        } catch (AuraHandledException e) {
            woShellThrew = true;
        }
        try {
            ReceivingController.submitVendorWorkOrderReceiving(null);
        } catch (AuraHandledException e) {
            vendorThrew = true;
        }
        try {
            ReceivingController.deleteModFormPhoto(null, null);
        } catch (AuraHandledException e) {
            deleteModThrew = true;
        }
        try {
            ReceivingController.attachReceivingPhotos(null, null);
        } catch (AuraHandledException e) {
            attachThrew = true;
        }
        try {
            ReceivingController.deleteReceivingPhoto(null);
        } catch (AuraHandledException e) {
            deletePhotoThrew = true;
        }
        try {
            ReceivingController.renameReceivingPhoto(null, 'Title');
        } catch (AuraHandledException e) {
            renamePhotoThrew = true;
        }
        try {
            ReceivingController.applySerialOverride(null, '01');
        } catch (AuraHandledException e) {
            serialThrew = true;
        }
        try {
            ReceivingController.buildCreateOrderPlan(null, null);
        } catch (AuraHandledException e) {
            planThrew = true;
        }
        try {
            ReceivingController.submitCreateOrder(null, null);
        } catch (AuraHandledException e) {
            submitThrew = true;
        }
        try {
            ReceivingController.createWorkOrdersForCreateOrder(null);
        } catch (AuraHandledException e) {
            createWoThrew = true;
        }
        Test.stopTest();

        Assert.isTrue(shellThrew);
        Assert.isTrue(qtyThrew);
        Assert.isTrue(woShellThrew);
        Assert.isTrue(vendorThrew);
        Assert.isTrue(deleteModThrew);
        Assert.isTrue(attachThrew);
        Assert.isTrue(deletePhotoThrew);
        Assert.isTrue(renamePhotoThrew);
        Assert.isTrue(serialThrew);
        Assert.isTrue(planThrew);
        Assert.isTrue(submitThrew);
        Assert.isTrue(createWoThrew);
    }

}