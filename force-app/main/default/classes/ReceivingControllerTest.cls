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
        adb_ReturnOrderLineItem lineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        lineBuilder.setParent(ReturnOrderLineItem.Product2Id, productBuilder);
        lineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        lineBuilder.persist();
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
            .get('RepairCenterOther')
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
}