/**
 * @description Tests for ReceivingService (GW-5492).
 */
@IsTest
private class ReceivingServiceTest {
    @TestSetup
    static void setupTestData() {
        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Receiving Account')
            .systemId('LEG-5492');
        accountBuilder.set(Account.OrgIDs__c, '82');
        accountBuilder.set(Account.CreditStatusCode__c, 'CREDIT HOLD');

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        returnOrderBuilder.recordType('CustomerReturn');
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Serialized');

        adb_Product2 productBuilder = new adb_Product2()
            .name('GW5492 Receiving Product')
            .isActive(true);

        adb_ReturnOrderLineItem lineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        lineBuilder.setParent(ReturnOrderLineItem.Product2Id, productBuilder);
        lineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        lineBuilder.persist();
    }

    @IsTest
    static void testResolveScanInput_byReturnOrderNumber() {
        ReturnOrder returnOrder = [
            SELECT Id, ReturnOrderNumber
            FROM ReturnOrder
            LIMIT 1
        ];

        Test.startTest();
        ReceivingService.ScanResolveResult result =
            ReceivingService.resolveScanInput(returnOrder.ReturnOrderNumber);
        Test.stopTest();

        Assert.areEqual(returnOrder.Id, result.returnOrderId);
        Assert.areEqual('ReturnOrder', result.pathType);
    }

    @IsTest
    static void testGetRepairCenterOptions_returnsLocationNames() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Receiving Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        Test.startTest();
        List<ReceivingService.PicklistOption> options =
            ReceivingService.getRepairCenterOptions();
        Test.stopTest();

        Boolean found = false;
        for (ReceivingService.PicklistOption option : options) {
            if (option.value == String.valueOf(repairCenter.Id)) {
                found = true;
                Assert.areEqual('GW5492 Receiving Repair Center', option.label);
                break;
            }
        }
        Assert.isTrue(found);
    }

    @IsTest
    static void testCanCreateNewOrder_whenNoServiceResource_returnsFalse() {
        Test.startTest();
        Boolean canCreate = ReceivingService.canCreateNewOrder();
        Test.stopTest();

        Assert.isFalse(canCreate);
    }

    @IsTest
    static void testCanCreateNewOrder_whenEligibleRepairCenter_returnsTrue() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'DUN-NORTHAMPTON (UK)',
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert repairCenter;

        ServiceResource resource = new ServiceResource(
            Name = 'GW4348 Eligible Resource',
            RelatedRecordId = UserInfo.getUserId(),
            LocationId = repairCenter.Id,
            IsActive = true,
            ResourceType = 'T'
        );
        insert resource;
        resource.put('RepairCenter__c', repairCenter.Id);
        update resource;

        Test.startTest();
        Boolean canCreate = ReceivingService.canCreateNewOrder();
        Test.stopTest();

        Assert.isTrue(canCreate);
    }

    @IsTest
    static void testCanCreateNewOrder_whenIneligibleRepairCenter_returnsFalse() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'STOW',
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert repairCenter;

        ServiceResource resource = new ServiceResource(
            Name = 'GW4348 Ineligible Resource',
            RelatedRecordId = UserInfo.getUserId(),
            LocationId = repairCenter.Id,
            IsActive = true,
            ResourceType = 'T'
        );
        insert resource;
        resource.put('RepairCenter__c', repairCenter.Id);
        update resource;

        Test.startTest();
        Boolean canCreate = ReceivingService.canCreateNewOrder();
        Test.stopTest();

        Assert.isFalse(canCreate);
    }

    @IsTest
    static void testBuildCreateOrderPlan_splitsByProductLinePoAndShipTo() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'DUN-NORTHAMPTON (UK)',
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert repairCenter;

        ServiceResource resource = new ServiceResource(
            Name = 'GW5996 Plan Resource',
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

        List<Object> items = new List<Object>{
            new Map<String, Object>{
                'key' => 'item-1',
                'productLine' => 'MOBILE VAN',
                'customerPo' => 'PO-1',
                'shipToAccountId' => String.valueOf(UserInfo.getUserId()),
                'serialNumber' => 'SN-1',
                'model' => 'M1'
            },
            new Map<String, Object>{
                'key' => 'item-2',
                'productLine' => 'MOBILE VAN',
                'customerPo' => 'PO-1',
                'shipToAccountId' => String.valueOf(UserInfo.getUserId()),
                'serialNumber' => 'SN-2',
                'model' => 'M2'
            },
            new Map<String, Object>{
                'key' => 'item-3',
                'productLine' => 'RIGID SCOPE',
                'customerPo' => 'PO-1',
                'shipToAccountId' => String.valueOf(UserInfo.getUserId()),
                'serialNumber' => 'SN-3',
                'model' => 'M3'
            }
        };

        Test.startTest();
        List<ReceivingService.CreateOrderGroup> groups = ReceivingService.buildCreateOrderPlan(
            headerJson,
            JSON.serialize(items)
        );
        Test.stopTest();

        Assert.areEqual(2, groups.size());
        Assert.areEqual(repairCenter.Id, groups[0].repairCenterId);
        Assert.areEqual('DUN-NORTHAMPTON (UK)', groups[0].repairCenterName);
        Integer totalLines = 0;
        for (ReceivingService.CreateOrderGroup groupRecord : groups) {
            totalLines += groupRecord.lineCount;
            Assert.isTrue(groupRecord.displayTitle.startsWith('Order #'));
            Assert.isFalse(String.isBlank(groupRecord.lineItemsJson));
        }
        Assert.areEqual(3, totalLines);
    }

    @IsTest
    static void testBuildCreateOrderPlan_whenNoItems_throws() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'CAPITAL EQUIPMENT REPAIR CENTER',
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert repairCenter;

        ServiceResource resource = new ServiceResource(
            Name = 'GW5996 Empty Plan Resource',
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

        Boolean threw = false;
        Test.startTest();
        try {
            ReceivingService.buildCreateOrderPlan(headerJson, JSON.serialize(new List<Object>()));
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Add at least one item'));
        }
        Test.stopTest();

        Assert.isTrue(threw);
    }

    @IsTest
    static void testGetInternalAccountOptions_returnsInternalAccounts() {
        adb_Account internalAccountBuilder = new adb_Account()
            .name('GW5492 Receiving Internal Account')
            .systemId('LEG5492INT1');
        internalAccountBuilder.set(Account.Type, 'I');
        internalAccountBuilder.set(Account.OrgIDs__c, '82');
        internalAccountBuilder.set(Account.AccountNumber, 'INT-5492');
        Account internalAccount = (Account) internalAccountBuilder.persist();

        Test.startTest();
        List<ReceivingService.PicklistOption> options =
            ReceivingService.getInternalAccountOptions();
        Test.stopTest();

        Boolean found = false;
        for (ReceivingService.PicklistOption option : options) {
            if (option.value == String.valueOf(internalAccount.Id)) {
                found = true;
                Assert.areEqual(
                    'INT-5492 - GW5492 Receiving Internal Account',
                    option.label
                );
                break;
            }
        }
        Assert.isTrue(found);
    }

    @IsTest
    static void testGetVendorAccountOptions_returnsVendorAccounts() {
        adb_Account vendorAccountBuilder = new adb_Account()
            .name('GW5492 Receiving Vendor Account')
            .systemId('LEG5492VEN1');
        vendorAccountBuilder.set(Account.Type, 'Vendor');
        vendorAccountBuilder.set(Account.OrgIDs__c, '82');
        Account vendorAccount = (Account) vendorAccountBuilder.persist();

        Test.startTest();
        List<ReceivingService.PicklistOption> options =
            ReceivingService.getVendorAccountOptions();
        Test.stopTest();

        Boolean found = false;
        for (ReceivingService.PicklistOption option : options) {
            if (option.value == String.valueOf(vendorAccount.Id)) {
                found = true;
                Assert.areEqual('GW5492 Receiving Vendor Account', option.label);
                break;
            }
        }
        Assert.isTrue(found);
    }

    @IsTest
    static void testAccountSelectorReceivingQueries_useSoqlQueryBuilder() {
        Account customer = [SELECT Id, AccountNumber FROM Account LIMIT 1];
        adb_Account internalAccountBuilder = new adb_Account()
            .name('GW5492 Builder Internal Account')
            .systemId('LEG5492INT2');
        internalAccountBuilder.set(Account.Type, 'I');
        internalAccountBuilder.set(Account.OrgIDs__c, '82');
        Account internalAccount = (Account) internalAccountBuilder.persist();

        Test.startTest();
        List<Account> byId = AccountSelector.selectAccountNumberByIdForReceiving(customer.Id);
        List<Account> nullById = AccountSelector.selectAccountNumberByIdForReceiving(null);
        List<Account> internalAccounts = AccountSelector.selectInternalAccountsForReceiving();
        List<Account> vendorAccounts = AccountSelector.selectVendorAccountsForReceiving();
        Test.stopTest();

        Assert.areEqual(1, byId.size(), 'Customer Account Number should load');
        Assert.areEqual(customer.AccountNumber, byId[0].AccountNumber);
        Assert.areEqual(0, nullById.size(), 'Null Id should return empty');
        Boolean foundInternal = false;
        for (Account accountRecord : internalAccounts) {
            if (accountRecord.Id == internalAccount.Id) {
                foundInternal = true;
                break;
            }
        }
        Assert.isTrue(foundInternal, 'Internal Type=I account should be returned');
        Assert.isNotNull(vendorAccounts, 'Vendor account query should return a list');
    }

    @IsTest
    static void testResolveScanInput_byReturnOrderId() {
        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder LIMIT 1];

        Test.startTest();
        ReceivingService.ScanResolveResult result =
            ReceivingService.resolveScanInput(String.valueOf(returnOrder.Id));
        Test.stopTest();

        Assert.areEqual(returnOrder.Id, result.returnOrderId);
    }

    @IsTest
    static void testResolveScanInput_blank_throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            ReceivingService.resolveScanInput('   ');
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('required'));
        }
        Test.stopTest();
        Assert.isTrue(threw);
    }

    @IsTest
    static void testResolveScanInput_alreadyReceived_throws() {
        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder LIMIT 1];
        returnOrder.Status = 'Received';
        update returnOrder;

        Boolean threw = false;
        Test.startTest();
        try {
            ReceivingService.resolveScanInput(String.valueOf(returnOrder.Id));
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().toLowerCase().contains('already received'));
        }
        Test.stopTest();
        Assert.isTrue(threw);
    }

    @IsTest
    static void testGetReceivingShellContext_mapsIndicators() {
        ReturnOrder returnOrder = [SELECT Id, AccountId FROM ReturnOrder LIMIT 1];

        Test.startTest();
        ReceivingService.ReceivingShellContext context =
            ReceivingService.getReceivingShellContext(returnOrder.Id);
        Test.stopTest();

        Assert.areEqual(returnOrder.Id, context.returnOrderId);
        Assert.areEqual(returnOrder.AccountId, context.accountId);
        Assert.areEqual('GW5492 Receiving Account', context.accountName);
        Assert.areEqual('STERIS US', context.operatingUnit);
        Assert.areEqual('LEG-5492', context.legacyCustomerId);
        Assert.areEqual(true, context.isCreditHold);
        Assert.areEqual(UserInfo.getName(), context.receiverName);
        Assert.isNotNull(context.items);
        Assert.areEqual(1, context.items.size());
        Assert.areEqual(1, context.items[0].itemNumber);
        Assert.isTrue(context.items[0].headerTitle.startsWith('Item 1:'));
        Assert.isTrue(String.isNotBlank(context.items[0].displayTitle));
        Assert.areEqual(false, context.items[0].showOutsideVendor);
        Assert.areEqual(false, context.items[0].isVendorRequired);
        Assert.areEqual(false, context.items[0].showQuantityVerify);
        Assert.areEqual(true, context.items[0].showSerialVerify);
        Assert.areEqual(true, context.items[0].showModelVerify);
    }

    @IsTest
    static void testGetReceivingShellContext_otherNonSerialized_quantityAndVendorAlways() {
        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder LIMIT 1];
        returnOrder.ReturnOrderType__c = 'Other (Non-Serialized)';
        update returnOrder;

        Product2 product = [
            SELECT Id
            FROM Product2
            WHERE Name = 'GW5492 Receiving Product'
            LIMIT 1
        ];
        product.ProductCode = 'VI.10853';
        update product;

        ReturnOrderLineItem lineItem = [
            SELECT Id, QuantityReturned
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            LIMIT 1
        ];
        lineItem.QuantityReturned = 8;
        update lineItem;

        Test.startTest();
        ReceivingService.ReceivingShellContext context =
            ReceivingService.getReceivingShellContext(returnOrder.Id);
        Test.stopTest();

        Assert.areEqual(1, context.items.size());
        ReceivingService.ReceivingShellItem item = context.items[0];
        Assert.areEqual(true, item.showQuantityVerify);
        Assert.areEqual(false, item.showSerialVerify);
        Assert.areEqual(false, item.showModelVerify);
        Assert.areEqual(true, item.showOutsideVendor);
        Assert.areEqual(true, item.isVendorRequired);
        Assert.areEqual(false, item.isInstrumentItem);
        Assert.areEqual(8, item.quantityReturned);
        Assert.isTrue(
            item.displayTitle.startsWith('VI.10853'),
            'Non-Serialized title should lead with Product Code'
        );
        Assert.isTrue(item.headerTitle.startsWith('Item 1:'));
    }

    @IsTest
    static void testBuildBadgesForTest_allBadgeTypes() {
        Test.startTest();
        List<ReceivingService.ReceivingBadge> badges = ReceivingService.buildBadgesForTest(
            'item-1',
            true,
            true,
            true,
            true,
            true,
            true,
            2,
            new List<String>{ 'Serial Number Mismatch', 'Model Mismatch' }
        );
        Test.stopTest();

        Set<String> labels = new Set<String>();
        Map<String, String> variantByLabel = new Map<String, String>();
        for (ReceivingService.ReceivingBadge badge : badges) {
            labels.add(badge.label);
            variantByLabel.put(badge.label, badge.variant);
            Assert.isTrue(String.isNotBlank(badge.iconName));
            Assert.isTrue(String.isNotBlank(badge.key));
        }

        Assert.isTrue(labels.contains('Priority Repair'));
        Assert.isTrue(labels.contains('Repair Exchange'));
        Assert.isTrue(labels.contains('Contaminated'));
        Assert.isTrue(labels.contains('Redirect'));
        Assert.isTrue(labels.contains('Accessories (2)'));
        Assert.isTrue(labels.contains('Work Order Created'));
        Assert.isTrue(labels.contains('Repair Warranty'));
        Assert.isTrue(labels.contains('Serial Number Mismatch'));
        Assert.isTrue(labels.contains('Model Mismatch'));
        Assert.areEqual('info', variantByLabel.get('Priority Repair'));
        Assert.areEqual('alert', variantByLabel.get('Contaminated'));
        Assert.areEqual('redirect', variantByLabel.get('Redirect'));
        Assert.areEqual('complete', variantByLabel.get('Work Order Created'));
        Assert.areEqual('warning', variantByLabel.get('Serial Number Mismatch'));
    }

    @IsTest
    static void testGetReceivingShellContext_repairWarrantyBadgeFromReturnOrder() {
        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder LIMIT 1];
        returnOrder.RepairWarranty__c = 'Yes';
        update returnOrder;

        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            LIMIT 1
        ];
        lineItem.IsPriorityRepair__c = true;
        lineItem.IsRepairExchange__c = true;
        lineItem.Disinfected__c = 'No, Item is not Disinfected';
        update lineItem;

        Test.startTest();
        ReceivingService.ReceivingShellContext context =
            ReceivingService.getReceivingShellContext(returnOrder.Id);
        Test.stopTest();

        Assert.areEqual(1, context.items.size());
        Set<String> labels = new Set<String>();
        for (ReceivingService.ReceivingBadge badge : context.items[0].badges) {
            labels.add(badge.label);
        }
        Assert.isTrue(labels.contains('Priority Repair'));
        Assert.isTrue(labels.contains('Repair Exchange'));
        Assert.isTrue(labels.contains('Contaminated'));
        Assert.isTrue(labels.contains('Repair Warranty'));
    }

    @IsTest
    static void testIsVendorRequiredForAttributes_matchesActiveRules() {
        ReceivingService.vendorRequiredRulesOverride = new List<VendorRequiredProductRule__mdt>{
            new VendorRequiredProductRule__mdt(
                ProductLine__c = 'POWER SYSTEM',
                SubProductLine__c = 'DENTAL',
                DeviceType__c = null,
                IsActive__c = true
            ),
            new VendorRequiredProductRule__mdt(
                ProductLine__c = 'ULTRASOUND',
                SubProductLine__c = 'STANDARD',
                DeviceType__c = 'DOPPLER',
                IsActive__c = true
            )
        };

        Test.startTest();
        Boolean dentalRequired = ReceivingService.isVendorRequiredForAttributes(
            'POWER SYSTEM',
            'DENTAL',
            'HANDPIECE'
        );
        Boolean dopplerRequired = ReceivingService.isVendorRequiredForAttributes(
            'ULTRASOUND',
            'STANDARD',
            'DOPPLER'
        );
        Boolean noMatch = ReceivingService.isVendorRequiredForAttributes(
            'ULTRASOUND',
            'STANDARD',
            'PROBE'
        );
        Test.stopTest();

        ReceivingService.vendorRequiredRulesOverride = null;

        Assert.isTrue(dentalRequired);
        Assert.isTrue(dopplerRequired);
        Assert.isFalse(noMatch);
    }

    @IsTest
    static void testResolveScanInput_workOrderDevices_returnsWorkOrderPath() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id devicesRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices')
            .getRecordTypeId();
        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Devices Header',
            AccountId = accountRecord.Id,
            RecordTypeId = devicesRecordTypeId
        );
        insert workOrder;
        workOrder = [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];

        Test.startTest();
        ReceivingService.ScanResolveResult result =
            ReceivingService.resolveScanInput(String.valueOf(workOrder.Id));
        ReceivingService.ReceivingShellContext context =
            ReceivingService.getWorkOrderReceivingShellContext(workOrder.Id);
        Test.stopTest();

        Assert.areEqual('WorkOrder', result.pathType);
        Assert.areEqual(workOrder.Id, result.workOrderId);
        Assert.areEqual('WorkOrder', context.pathType);
        Assert.areEqual(workOrder.Id, context.workOrderId);
        Assert.areEqual('Work Order ' + workOrder.WorkOrderNumber, context.headerTitle);
        Assert.areEqual(UserInfo.getName(), context.receiverName);
        Assert.isFalse(context.isVendorWorkOrder);
        Assert.isFalse(context.shipComplete, 'Ship Complete stays hidden when the flag is false.');
        Assert.isTrue(context.items == null || context.items.isEmpty());
    }

    @IsTest
    static void testGetWorkOrderReceivingShellContext_shipCompleteTrue() {
        // Setup
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id devicesRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices')
            .getRecordTypeId();

        // Given
        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW6070 Ship Complete',
            AccountId = accountRecord.Id,
            RecordTypeId = devicesRecordTypeId,
            ShipComplete__c = true
        );
        insert workOrder;

        // When
        Test.startTest();
        ReceivingService.ReceivingShellContext context =
            ReceivingService.getWorkOrderReceivingShellContext(workOrder.Id);
        Test.stopTest();

        // Then
        Assert.isTrue(context.shipComplete, 'Ship Complete should map from the Work Order.');
        Assert.areEqual('WorkOrder', context.pathType);
    }

    @IsTest
    static void testGetWorkOrderReceivingShellContext_devicesSpecificModelTitleAndVerify() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id devicesRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices')
            .getRecordTypeId();
        Id productServicedRtId = productServicedRecordTypeId();
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Flex Scope',
            'FS.001',
            'FLEXIBLE SCOPE',
            null,
            'SCOPE',
            'GIF-H190'
        );

        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Devices Verify',
            AccountId = accountRecord.Id,
            RecordTypeId = devicesRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId(),
            IsPriorityRepair__c = true,
            RepairWarranty__c = 'Yes'
        );
        insert workOrder;

        insert new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRtId,
            LineType__c = 'Product Serviced',
            IsAccessory__c = false,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            SerialNumber__c = '05141306',
            Model__c = 'GIF-H190'
        );
        insert new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRtId,
            LineType__c = 'Product Serviced',
            IsAccessory__c = true,
            PricebookEntryId = pbe.Id,
            Quantity = 2,
            SerialNumber__c = 'ACCESSORY1'
        );

        Test.startTest();
        ReceivingService.ReceivingShellContext context =
            ReceivingService.getWorkOrderReceivingShellContext(workOrder.Id);
        Test.stopTest();

        Assert.areEqual(1, context.items.size());
        ReceivingService.ReceivingShellItem item = context.items[0];
        Assert.areEqual(
            'Item 1: FLEXIBLE SCOPE - Serial # 05141306 | Model # GIF-H190',
            item.headerTitle
        );
        Assert.isTrue(item.showSerialVerify);
        Assert.isTrue(item.showModelVerify);
        Assert.isFalse(item.showQuantityVerify);
        Assert.isFalse(item.showDisinfectedVerify);
        Assert.isTrue(item.isPriorityRepair);
        Set<String> badgeLabels = new Set<String>();
        for (ReceivingService.ReceivingBadge badge : item.badges) {
            badgeLabels.add(badge.label);
        }
        Assert.isTrue(badgeLabels.contains('Priority Repair'));
        Assert.isTrue(badgeLabels.contains('Accessories (2)'));
        Assert.isTrue(badgeLabels.contains('Repair Warranty'));
        Assert.areEqual(3, item.badges.size());
    }

    @IsTest
    static void testGetWorkOrderReceivingShellContext_devicesGenericModelTitle() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id devicesRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices')
            .getRecordTypeId();
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Generic Instrument',
            'GI.001',
            'INSTRUMENT',
            null,
            'STIRRUP',
            'ANY'
        );

        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Devices Generic',
            AccountId = accountRecord.Id,
            RecordTypeId = devicesRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert workOrder;

        insert new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRecordTypeId(),
            LineType__c = 'Product Serviced',
            IsAccessory__c = false,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            SerialNumber__c = '05141306',
            Model__c = 'ANY'
        );

        Test.startTest();
        ReceivingService.ReceivingShellContext context =
            ReceivingService.getWorkOrderReceivingShellContext(workOrder.Id);
        Test.stopTest();

        Assert.areEqual(1, context.items.size());
        Assert.areEqual(
            'Item 1: INSTRUMENT - STIRRUP | Serial # 05141306',
            context.items[0].headerTitle
        );
        Assert.isTrue(context.items[0].showSerialVerify);
        Assert.isFalse(context.items[0].showModelVerify);
    }

    @IsTest
    static void testGetWorkOrderReceivingShellContext_instrumentsNullProductQuantityVerify() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id instrumentsRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterInstruments')
            .getRecordTypeId();
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Instrument Qty Product',
            'IQ.001',
            'INSTRUMENT',
            null,
            'FORCEPS',
            'GENERIC'
        );

        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Instruments Qty',
            AccountId = accountRecord.Id,
            RecordTypeId = instrumentsRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId(),
            QuantityReceived__c = 4
        );
        insert workOrder;
        Assert.isNull(workOrder.Product__c);

        insert new List<WorkOrderLineItem>{
            new WorkOrderLineItem(
                WorkOrderId = workOrder.Id,
                RecordTypeId = productServicedRecordTypeId(),
                LineType__c = 'Product Serviced',
                IsAccessory__c = false,
                PricebookEntryId = pbe.Id,
                Quantity = 1
            ),
            new WorkOrderLineItem(
                WorkOrderId = workOrder.Id,
                RecordTypeId = productServicedRecordTypeId(),
                LineType__c = 'Product Serviced',
                IsAccessory__c = false,
                PricebookEntryId = pbe.Id,
                Quantity = 2
            )
        };

        Test.startTest();
        ReceivingService.ReceivingShellContext context =
            ReceivingService.getWorkOrderReceivingShellContext(workOrder.Id);
        Test.stopTest();

        Assert.areEqual(1, context.items.size());
        Assert.areEqual('Item 1: INSTRUMENT', context.items[0].headerTitle);
        Assert.isTrue(context.items[0].showQuantityVerify);
        Assert.isFalse(context.items[0].showSerialVerify);
        Assert.isFalse(context.items[0].showModelVerify);
        Assert.areEqual(4, context.items[0].quantityReturned);
    }

    @IsTest
    static void testSaveWorkOrderQuantityReceived_updatesQuantity() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id instrumentsRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterInstruments')
            .getRecordTypeId();
        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Save Qty',
            AccountId = accountRecord.Id,
            RecordTypeId = instrumentsRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId(),
            QuantityReceived__c = 5
        );
        insert workOrder;

        Test.startTest();
        ReceivingService.saveWorkOrderQuantityReceived(workOrder.Id, 6);
        ReceivingService.saveWorkOrderQuantityReceived(workOrder.Id, 6);
        Test.stopTest();

        WorkOrder refreshed = [
            SELECT QuantityReceived__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual(6, refreshed.QuantityReceived__c);
    }

    @IsTest
    static void testSaveWorkOrderQuantityReceived_requiresQuantity() {
        Boolean threw = false;

        Test.startTest();
        try {
            ReceivingService.saveWorkOrderQuantityReceived(null, 6);
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = e.getMessage().contains('Work Order');
        }
        Test.stopTest();

        Assert.isTrue(threw);
    }

    @IsTest
    static void testGetWorkOrderReceivingShellContext_instrumentAssetStaysPerLine() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id instrumentsRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterInstruments')
            .getRecordTypeId();
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Instrument Asset Product',
            'IA.001',
            'INSTRUMENT',
            null,
            'FORCEPS',
            'GENERIC'
        );
        Asset assetRecord = new Asset(
            Name = 'GW5968 Instrument Asset',
            SerialNumber = 'INS-100',
            Product2Id = pbe.Product2Id,
            AccountId = accountRecord.Id,
            Status = 'Purchased'
        );
        insert assetRecord;

        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Instrument Asset',
            AccountId = accountRecord.Id,
            RecordTypeId = instrumentsRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId(),
            QuantityReceived__c = 4
        );
        insert workOrder;
        insert new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRecordTypeId(),
            LineType__c = 'Product Serviced',
            IsAccessory__c = false,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            AssetId = assetRecord.Id,
            SerialNumber__c = 'INS-100'
        );

        Test.startTest();
        ReceivingService.ReceivingShellContext context =
            ReceivingService.getWorkOrderReceivingShellContext(workOrder.Id);
        Test.stopTest();

        Assert.areEqual(1, context.items.size());
        Assert.isTrue(context.items[0].showSerialVerify);
        Assert.isFalse(context.items[0].showQuantityVerify);
        Assert.areEqual(assetRecord.Id, context.items[0].assetId);
    }

    @IsTest
    static void testGetWorkOrderReceivingShellContext_instrumentsWithoutLinesUsesQuantityReceived() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id instrumentsRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterInstruments')
            .getRecordTypeId();

        WorkOrder parentWorkOrder = new WorkOrder(
            Subject = 'GW5968 Instrument Parent Qty',
            AccountId = accountRecord.Id,
            RecordTypeId = instrumentsRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId(),
            QuantityReceived__c = 6
        );
        insert parentWorkOrder;

        WorkOrder childWorkOrder = new WorkOrder(
            Subject = 'GW5968 Instrument Child Qty',
            AccountId = accountRecord.Id,
            RecordTypeId = instrumentsRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId(),
            ParentWorkOrderId = parentWorkOrder.Id,
            QuantityReceived__c = 4
        );
        insert childWorkOrder;

        Test.startTest();
        ReceivingService.ReceivingShellContext parentContext =
            ReceivingService.getWorkOrderReceivingShellContext(parentWorkOrder.Id);
        ReceivingService.ReceivingShellContext childContext =
            ReceivingService.getWorkOrderReceivingShellContext(childWorkOrder.Id);
        Test.stopTest();

        Assert.areEqual(1, parentContext.items.size());
        Assert.areEqual('Item 1: INSTRUMENT', parentContext.items[0].headerTitle);
        Assert.isTrue(parentContext.items[0].showQuantityVerify);
        Assert.isFalse(parentContext.items[0].showSerialVerify);
        Assert.isNull(parentContext.items[0].lineItemId);
        Assert.areEqual(6, parentContext.items[0].quantityReturned);

        Assert.areEqual(1, childContext.items.size());
        Assert.areEqual('Item 1: INSTRUMENT', childContext.items[0].headerTitle);
        Assert.isTrue(childContext.items[0].showQuantityVerify);
        Assert.isNull(childContext.items[0].lineItemId);
        Assert.areEqual(4, childContext.items[0].quantityReturned);
    }

    @IsTest
    static void testGetWorkOrderReceivingShellContext_vendorItemsAndSubmit() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id otherRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterOther')
            .getRecordTypeId();
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Vendor Probe',
            'VI.10853',
            'ULTRASOUND',
            'STANDARD',
            'PROBE',
            'GIF-H190'
        );

        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Vendor Verify',
            AccountId = accountRecord.Id,
            RecordTypeId = otherRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert workOrder;

        insert new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRecordTypeId(),
            LineType__c = 'Product Serviced',
            IsAccessory__c = false,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            SerialNumber__c = '05141306',
            Model__c = 'GIF-H190'
        );

        Test.startTest();
        ReceivingService.ReceivingShellContext context =
            ReceivingService.getWorkOrderReceivingShellContext(workOrder.Id);
        ReceivingService.submitVendorWorkOrderReceiving(workOrder.Id);
        Test.stopTest();

        Assert.isTrue(context.isVendorWorkOrder);
        Assert.areEqual(1, context.items.size());
        Assert.areEqual(
            'ULTRASOUND.STANDARD.PROBE - Serial # 05141306 | Model # GIF-H190',
            context.items[0].displayTitle
        );
        Assert.isFalse(context.items[0].showSerialVerify);
        Assert.isTrue(context.items[0].vendorVerifiedDefault);

        WorkOrder updated = [
            SELECT Status
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual('Receive from Vendor', updated.Status);
    }

    @IsTest
    static void testSubmitVendorWorkOrderReceiving_updatesNonOtherParentStatus() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id devicesRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices')
            .getRecordTypeId();
        Id otherRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterOther')
            .getRecordTypeId();
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Vendor Parent Probe',
            'VI.10854',
            'ULTRASOUND',
            'STANDARD',
            'PROBE',
            'GIF-H190'
        );

        WorkOrder parentWorkOrder = new WorkOrder(
            Subject = 'GW5968 Parent Devices',
            AccountId = accountRecord.Id,
            RecordTypeId = devicesRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = 'New'
        );
        insert parentWorkOrder;

        WorkOrder vendorWorkOrder = new WorkOrder(
            Subject = 'GW5968 Vendor Child',
            AccountId = accountRecord.Id,
            RecordTypeId = otherRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId(),
            ParentWorkOrderId = parentWorkOrder.Id
        );
        insert vendorWorkOrder;

        insert new WorkOrderLineItem(
            WorkOrderId = vendorWorkOrder.Id,
            RecordTypeId = productServicedRecordTypeId(),
            LineType__c = 'Product Serviced',
            IsAccessory__c = false,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            SerialNumber__c = '05141307',
            Model__c = 'GIF-H190'
        );

        Test.startTest();
        ReceivingService.submitVendorWorkOrderReceiving(vendorWorkOrder.Id);
        Test.stopTest();

        WorkOrder refreshedParent = [
            SELECT Status, SubStatus__c
            FROM WorkOrder
            WHERE Id = :parentWorkOrder.Id
        ];
        WorkOrder refreshedVendor = [
            SELECT Status
            FROM WorkOrder
            WHERE Id = :vendorWorkOrder.Id
        ];
        Assert.areEqual('Receive from Vendor', refreshedVendor.Status);
        Assert.areEqual('Received', refreshedParent.Status);
        Assert.areEqual('Receive from Vendor', refreshedParent.SubStatus__c);
    }

    @IsTest
    static void testSubmitVendorWorkOrderReceiving_skipsOtherParentStatus() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id otherRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterOther')
            .getRecordTypeId();
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Vendor Other Parent Probe',
            'VI.10855',
            'ULTRASOUND',
            'STANDARD',
            'PROBE',
            'GIF-H190'
        );

        WorkOrder parentWorkOrder = new WorkOrder(
            Subject = 'GW5968 Parent Other',
            AccountId = accountRecord.Id,
            RecordTypeId = otherRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = 'New'
        );
        insert parentWorkOrder;

        WorkOrder vendorWorkOrder = new WorkOrder(
            Subject = 'GW5968 Vendor Child Other Parent',
            AccountId = accountRecord.Id,
            RecordTypeId = otherRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId(),
            ParentWorkOrderId = parentWorkOrder.Id
        );
        insert vendorWorkOrder;

        insert new WorkOrderLineItem(
            WorkOrderId = vendorWorkOrder.Id,
            RecordTypeId = productServicedRecordTypeId(),
            LineType__c = 'Product Serviced',
            IsAccessory__c = false,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            SerialNumber__c = '05141308',
            Model__c = 'GIF-H190'
        );

        Test.startTest();
        ReceivingService.submitVendorWorkOrderReceiving(vendorWorkOrder.Id);
        Test.stopTest();

        WorkOrder refreshedParent = [
            SELECT Status, SubStatus__c
            FROM WorkOrder
            WHERE Id = :parentWorkOrder.Id
        ];
        Assert.areEqual('Received', refreshedParent.Status);
        Assert.areEqual('Receive from Vendor', refreshedParent.SubStatus__c);
    }

    @IsTest
    static void testSubmitVendorWorkOrderReceiving_receivesMatchingInboundLines() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        ReturnOrder vendorReturnOrder = [
            SELECT Id
            FROM ReturnOrder
            LIMIT 1
        ];
        Id otherRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterOther')
            .getRecordTypeId();
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Vendor Inbound Probe',
            'VI.10856',
            'ULTRASOUND',
            'STANDARD',
            'PROBE',
            'GIF-H190'
        );

        WorkOrder vendorWorkOrder = new WorkOrder(
            Subject = 'GW5968 Vendor Inbound',
            AccountId = accountRecord.Id,
            RecordTypeId = otherRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert vendorWorkOrder;
        update new WorkOrder(
            Id = vendorWorkOrder.Id,
            VendorReturnOrder__c = vendorReturnOrder.Id
        );

        WorkOrderLineItem productServiced = new WorkOrderLineItem(
            WorkOrderId = vendorWorkOrder.Id,
            RecordTypeId = productServicedRecordTypeId(),
            LineType__c = 'Product Serviced',
            IsAccessory__c = false,
            PricebookEntryId = pbe.Id,
            Quantity = 2,
            SerialNumber__c = '05141309',
            Model__c = 'GIF-H190'
        );
        insert productServiced;

        ReturnOrderLineItem inboundLine = new ReturnOrderLineItem(
            ReturnOrderId = vendorReturnOrder.Id,
            Product2Id = pbe.Product2Id,
            QuantityReturned = 2,
            Status__c = 'Created',
            LineType__c = 'Inbound',
            WorkOrderLineItem__c = productServiced.Id
        );
        ReturnOrderLineItem outboundLine = new ReturnOrderLineItem(
            ReturnOrderId = vendorReturnOrder.Id,
            Product2Id = pbe.Product2Id,
            QuantityReturned = 2,
            Status__c = 'Created',
            LineType__c = 'Outbound',
            WorkOrderLineItem__c = productServiced.Id
        );
        insert new List<ReturnOrderLineItem>{ inboundLine, outboundLine };

        Test.startTest();
        ReceivingService.submitVendorWorkOrderReceiving(vendorWorkOrder.Id);
        Test.stopTest();

        Map<Id, ReturnOrderLineItem> refreshedLines = new Map<Id, ReturnOrderLineItem>([
            SELECT Status__c, QuantityReceived, LineType__c
            FROM ReturnOrderLineItem
            WHERE Id IN :new Set<Id>{ inboundLine.Id, outboundLine.Id }
        ]);
        Assert.areEqual('Received', refreshedLines.get(inboundLine.Id).Status__c);
        Assert.areEqual(2, refreshedLines.get(inboundLine.Id).QuantityReceived);
        Assert.areEqual('Created', refreshedLines.get(outboundLine.Id).Status__c);
        Assert.areEqual(null, refreshedLines.get(outboundLine.Id).QuantityReceived);
        ReturnOrder refreshedReturnOrder = [
            SELECT Status
            FROM ReturnOrder
            WHERE Id = :vendorReturnOrder.Id
        ];
        Assert.areEqual('Received', refreshedReturnOrder.Status);
    }

    @IsTest
    static void testSubmitVendorWorkOrderReceiving_receivesInboundLinesLinkedByParentRoli() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        ReturnOrder vendorReturnOrder = [
            SELECT Id
            FROM ReturnOrder
            LIMIT 1
        ];
        Id otherRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterOther')
            .getRecordTypeId();
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Vendor Parent Link Probe',
            'VI.10857',
            'ULTRASOUND',
            'STANDARD',
            'PROBE',
            'GIF-H190'
        );

        WorkOrder vendorWorkOrder = new WorkOrder(
            Subject = 'GW5968 Vendor Parent Link',
            AccountId = accountRecord.Id,
            RecordTypeId = otherRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert vendorWorkOrder;
        update new WorkOrder(
            Id = vendorWorkOrder.Id,
            VendorReturnOrder__c = vendorReturnOrder.Id
        );

        WorkOrderLineItem productServiced = new WorkOrderLineItem(
            WorkOrderId = vendorWorkOrder.Id,
            RecordTypeId = productServicedRecordTypeId(),
            LineType__c = 'Product Serviced',
            IsAccessory__c = false,
            PricebookEntryId = pbe.Id,
            Quantity = 3
        );
        insert productServiced;

        ReturnOrderLineItem outboundLine = new ReturnOrderLineItem(
            ReturnOrderId = vendorReturnOrder.Id,
            Product2Id = pbe.Product2Id,
            QuantityReturned = 3,
            QuantityReceived = 0,
            Status__c = 'Created',
            LineType__c = 'Outbound'
        );
        insert outboundLine;
        update new WorkOrderLineItem(
            Id = productServiced.Id,
            VendorReturnOrderLineItem__c = outboundLine.Id
        );
        ReturnOrderLineItem inboundLine = new ReturnOrderLineItem(
            ReturnOrderId = vendorReturnOrder.Id,
            Product2Id = pbe.Product2Id,
            QuantityReturned = 3,
            QuantityReceived = 0,
            Status__c = 'Created',
            LineType__c = 'Inbound',
            ParentROLI__c = outboundLine.Id
        );
        insert inboundLine;

        Test.startTest();
        ReceivingService.submitVendorWorkOrderReceiving(vendorWorkOrder.Id);
        Test.stopTest();

        ReturnOrderLineItem refreshedInbound = [
            SELECT Status__c, QuantityReceived
            FROM ReturnOrderLineItem
            WHERE Id = :inboundLine.Id
        ];
        ReturnOrderLineItem refreshedOutbound = [
            SELECT Status__c, QuantityReceived
            FROM ReturnOrderLineItem
            WHERE Id = :outboundLine.Id
        ];
        ReturnOrder refreshedReturnOrder = [
            SELECT Status
            FROM ReturnOrder
            WHERE Id = :vendorReturnOrder.Id
        ];
        Assert.areEqual('Received', refreshedInbound.Status__c);
        Assert.areEqual(3, refreshedInbound.QuantityReceived);
        Assert.areEqual('Created', refreshedOutbound.Status__c);
        Assert.areEqual(0, refreshedOutbound.QuantityReceived);
        Assert.areEqual('Received', refreshedReturnOrder.Status);
    }

    @IsTest
    static void testSubmitVendorWorkOrderReceiving_leavesReturnOrderCreatedWhenInboundRemains() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        ReturnOrder vendorReturnOrder = [
            SELECT Id
            FROM ReturnOrder
            LIMIT 1
        ];
        Id otherRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterOther')
            .getRecordTypeId();
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Vendor Open Inbound Probe',
            'VI.10858',
            'ULTRASOUND',
            'STANDARD',
            'PROBE',
            'GIF-H190'
        );

        WorkOrder vendorWorkOrder = new WorkOrder(
            Subject = 'GW5968 Vendor Open Inbound',
            AccountId = accountRecord.Id,
            RecordTypeId = otherRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert vendorWorkOrder;
        update new WorkOrder(
            Id = vendorWorkOrder.Id,
            VendorReturnOrder__c = vendorReturnOrder.Id
        );

        WorkOrderLineItem productServiced = new WorkOrderLineItem(
            WorkOrderId = vendorWorkOrder.Id,
            RecordTypeId = productServicedRecordTypeId(),
            LineType__c = 'Product Serviced',
            IsAccessory__c = false,
            PricebookEntryId = pbe.Id,
            Quantity = 1
        );
        insert productServiced;

        ReturnOrderLineItem outboundLine = new ReturnOrderLineItem(
            ReturnOrderId = vendorReturnOrder.Id,
            Product2Id = pbe.Product2Id,
            QuantityReturned = 1,
            Status__c = 'Created',
            LineType__c = 'Outbound'
        );
        insert outboundLine;
        update new WorkOrderLineItem(
            Id = productServiced.Id,
            VendorReturnOrderLineItem__c = outboundLine.Id
        );
        ReturnOrderLineItem inboundLine = new ReturnOrderLineItem(
            ReturnOrderId = vendorReturnOrder.Id,
            Product2Id = pbe.Product2Id,
            QuantityReturned = 1,
            Status__c = 'Created',
            LineType__c = 'Inbound',
            ParentROLI__c = outboundLine.Id
        );
        ReturnOrderLineItem otherInboundLine = new ReturnOrderLineItem(
            ReturnOrderId = vendorReturnOrder.Id,
            Product2Id = pbe.Product2Id,
            QuantityReturned = 2,
            Status__c = 'Created',
            LineType__c = 'Inbound'
        );
        insert new List<ReturnOrderLineItem>{ inboundLine, otherInboundLine };

        Test.startTest();
        ReceivingService.submitVendorWorkOrderReceiving(vendorWorkOrder.Id);
        Test.stopTest();

        ReturnOrderLineItem refreshedOther = [
            SELECT Status__c, QuantityReceived
            FROM ReturnOrderLineItem
            WHERE Id = :otherInboundLine.Id
        ];
        ReturnOrder refreshedReturnOrder = [
            SELECT Status
            FROM ReturnOrder
            WHERE Id = :vendorReturnOrder.Id
        ];
        Assert.areEqual('Created', refreshedOther.Status__c);
        Assert.areEqual(null, refreshedOther.QuantityReceived);
        Assert.areEqual('Created', refreshedReturnOrder.Status);
    }

    @IsTest
    static void testGetWorkOrderReceivingShellContext_vendorHeaderTitle() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id otherRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterOther')
            .getRecordTypeId();
        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Vendor Header',
            AccountId = accountRecord.Id,
            RecordTypeId = otherRecordTypeId
        );
        insert workOrder;
        workOrder = [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];

        Test.startTest();
        ReceivingService.ReceivingShellContext context =
            ReceivingService.getWorkOrderReceivingShellContext(workOrder.Id);
        ReceivingService.ScanResolveResult byNumber =
            ReceivingService.resolveScanInput(workOrder.WorkOrderNumber);
        Test.stopTest();

        Assert.areEqual(
            'Vendor Work Order ' + workOrder.WorkOrderNumber,
            context.headerTitle
        );
        Assert.areEqual('RepairCenterOther', context.workOrderRecordTypeDeveloperName);
        Assert.areEqual('WorkOrder', byNumber.pathType);
        Assert.areEqual(workOrder.Id, byNumber.workOrderId);
    }

    @IsTest
    static void testResolveScanInput_nonRepairCenterWorkOrder_throws() {
        Id fieldRepairRecordTypeId = Schema.SObjectType.WorkOrder
            .getRecordTypeInfosByDeveloperName()
            .get('ESFieldRepair')
            .getRecordTypeId();
        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Non RC WO',
            RecordTypeId = fieldRepairRecordTypeId
        );
        insert workOrder;

        Boolean threw = false;
        Test.startTest();
        try {
            ReceivingService.resolveScanInput(String.valueOf(workOrder.Id));
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('Only Repair Center Work Orders'),
                e.getMessage()
            );
        }
        Test.stopTest();
        Assert.isTrue(threw);
    }

    @IsTest
    static void testStageModFormPhoto_linksToReturnOrder() {
        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder LIMIT 1];
        String tinyPngBase64 =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

        Test.startTest();
        ReceivingService.ModFormPhoto photo = ReceivingService.stageModFormPhoto(
            returnOrder.Id,
            tinyPngBase64,
            'ModForm-test.png'
        );
        Test.stopTest();

        Assert.isNotNull(photo.contentDocumentId);
        Assert.isNotNull(photo.contentVersionId);
        Assert.isTrue(String.isNotBlank(photo.title));
        Assert.isTrue(
            String.isNotBlank(photo.imageDownloadUrl),
            'imageDownloadUrl should be populated for photo preview'
        );
        Assert.isTrue(
            photo.imageDownloadUrl.contains(photo.contentVersionId),
            'imageDownloadUrl should point at the ContentVersion'
        );

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :photo.contentDocumentId AND LinkedEntityId = :returnOrder.Id
        ];
        Assert.areEqual(1, links.size());
    }

    @IsTest
    static void testRenameModFormPhoto_updatesTitle() {
        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder LIMIT 1];
        String tinyPngBase64 =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
        ReceivingService.ModFormPhoto photo = ReceivingService.stageModFormPhoto(
            returnOrder.Id,
            tinyPngBase64,
            'ModForm-rename.png'
        );

        Test.startTest();
        ReceivingService.ModFormPhoto renamed = ReceivingService.renameModFormPhoto(
            returnOrder.Id,
            photo.contentDocumentId,
            'Updated Mod Form Title'
        );
        Test.stopTest();

        Assert.areEqual('Updated Mod Form Title', renamed.title);
        Assert.areEqual(photo.contentDocumentId, renamed.contentDocumentId);
    }

    @IsTest
    static void testStageReceivingPhoto_doesNotLinkToRecord() {
        String tinyPngBase64 =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

        Test.startTest();
        ReceivingService.ModFormPhoto photo = ReceivingService.stageReceivingPhoto(
            tinyPngBase64,
            'Receive-test.png'
        );
        Test.stopTest();

        Assert.isNotNull(photo.contentDocumentId);
        Assert.areEqual('Receive-test', photo.title);
        Integer recordLinks = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :photo.contentDocumentId
            AND LinkedEntityId != :UserInfo.getUserId()
        ];
        Assert.areEqual(0, recordLinks, 'Take a Pic files stay unlinked until they are committed.');
    }

    @IsTest
    static void testAttachReceivingPhotos_linksToWorkOrderAndSkipsDuplicates() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Id devicesRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices')
            .getRecordTypeId();
        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Photo Attach',
            AccountId = accountRecord.Id,
            RecordTypeId = devicesRecordTypeId
        );
        insert workOrder;
        String tinyPngBase64 =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
        ReceivingService.ModFormPhoto photo = ReceivingService.stageReceivingPhoto(
            tinyPngBase64,
            'Receive-attach.png'
        );

        Test.startTest();
        ReceivingService.attachReceivingPhotos(
            workOrder.Id,
            new List<Id>{ photo.contentDocumentId, photo.contentDocumentId }
        );
        ReceivingService.attachReceivingPhotos(
            workOrder.Id,
            new List<Id>{ photo.contentDocumentId }
        );
        Test.stopTest();

        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :photo.contentDocumentId
                AND LinkedEntityId = :workOrder.Id
            ]
        );
    }

    @IsTest
    static void testAttachReceivingPhotos_missingWorkOrderThrows() {
        Boolean threw = false;
        try {
            ReceivingService.attachReceivingPhotos(null, new List<Id>{ UserInfo.getUserId() });
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Work Order is required'));
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testStageReceivingPhoto_blankDataThrows() {
        Boolean threw = false;
        try {
            ReceivingService.stageReceivingPhoto('   ', 'Receive-blank.png');
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('File data is required'));
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testRenameAndDeleteReceivingPhoto() {
        String tinyPngBase64 =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
        ReceivingService.ModFormPhoto photo = ReceivingService.stageReceivingPhoto(
            tinyPngBase64,
            'Receive-rename.png'
        );

        Test.startTest();
        ReceivingService.ModFormPhoto renamed = ReceivingService.renameReceivingPhoto(
            photo.contentDocumentId,
            'Updated Receive Title'
        );
        ReceivingService.deleteReceivingPhoto(photo.contentDocumentId);
        Test.stopTest();

        Assert.areEqual('Updated Receive Title', renamed.title);
        Integer remaining = [
            SELECT COUNT()
            FROM ContentDocument
            WHERE Id = :photo.contentDocumentId
        ];
        Assert.areEqual(0, remaining);
    }

    @IsTest
    static void testApplySerialOverride_updatesAssetAndLine() {
        ReturnOrderLineItem lineItem = [
            SELECT Id, Product2Id, ReturnOrder.AccountId
            FROM ReturnOrderLineItem
            LIMIT 1
        ];
        update new Product2(Id = lineItem.Product2Id, ProductCode = 'OC.FI004');
        update new ReturnOrderLineItem(Id = lineItem.Id, SerialNumber__c = '05141306');
        insert new Asset(
            Name = 'Old Asset',
            SerialNumber = '05141306',
            Product2Id = lineItem.Product2Id,
            AccountId = lineItem.ReturnOrder.AccountId,
            Status = 'Purchased'
        );

        Test.startTest();
        ReceivingService.OverrideSerialResult result = ReceivingService.applySerialOverride(
            lineItem.Id,
            '05141399'
        );
        Test.stopTest();

        Assert.isTrue(result.lineUpdated);
        Assert.isTrue(result.assetUpdated);
        Assert.areEqual('05141399', result.serialNumber);
        ReturnOrderLineItem updatedLine = [
            SELECT SerialNumber__c
            FROM ReturnOrderLineItem
            WHERE Id = :lineItem.Id
        ];
        Asset updatedAsset = [
            SELECT Name, SerialNumber
            FROM Asset
            WHERE Product2Id = :lineItem.Product2Id
        ];
        Assert.areEqual('05141399', updatedLine.SerialNumber__c);
        Assert.areEqual('05141399', updatedAsset.SerialNumber);
        Assert.areEqual('OC.FI004 - 05141399', updatedAsset.Name);
    }

    @IsTest
    static void testApplySerialOverride_tooManyCharactersDoesNotUpdate() {
        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            LIMIT 1
        ];
        update new ReturnOrderLineItem(Id = lineItem.Id, SerialNumber__c = '05141306');

        Test.startTest();
        ReceivingService.OverrideSerialResult result = ReceivingService.applySerialOverride(
            lineItem.Id,
            '99999999'
        );
        Test.stopTest();

        Assert.isFalse(result.assetUpdated);
        Assert.isFalse(result.lineUpdated);
        Assert.areEqual('05141306', result.serialNumber);
    }

    @IsTest
    static void testApplySerialOverride_blankSerialDoesNothing() {
        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            LIMIT 1
        ];

        ReceivingService.OverrideSerialResult result = ReceivingService.applySerialOverride(
            lineItem.Id,
            '   '
        );

        Assert.isFalse(result.lineUpdated);
        Assert.isFalse(result.assetUpdated);
    }

    @IsTest
    static void testApplyWorkOrderSerialOverride_nullLineItem_throws() {
        // Setup
        Boolean threw = false;

        // When
        Test.startTest();
        try {
            ReceivingService.applyWorkOrderSerialOverride(null, '05141399');
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('required'));
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw, 'Null WOLI Id should throw');
    }

    @IsTest
    static void testApplyWorkOrderSerialOverride_updatesWoliAndAsset() {
        // Setup
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Override Scope',
            'OC.FI004',
            'FLEXIBLE SCOPE',
            null,
            'SCOPE',
            'GIF-H190'
        );
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, null);
        WorkOrderLineItem woli = insertProductServicedLine(workOrder.Id, pbe.Id, '05141306');
        insert new Asset(
            Name = 'Old WO Asset',
            SerialNumber = '05141306',
            Product2Id = pbe.Product2Id,
            AccountId = accountRecord.Id,
            Status = 'Purchased'
        );

        // When
        Test.startTest();
        ReceivingService.OverrideSerialResult result =
            ReceivingService.applyWorkOrderSerialOverride(woli.Id, '05141399');
        Test.stopTest();

        // Then
        Assert.isTrue(result.lineUpdated, 'WOLI should be updated');
        Assert.isTrue(result.assetUpdated, 'Matching Asset should be updated');
        Assert.areEqual('05141399', result.serialNumber);
        Assert.areEqual(
            '05141399',
            [SELECT SerialNumber__c FROM WorkOrderLineItem WHERE Id = :woli.Id].SerialNumber__c
        );
        Asset updatedAsset = [
            SELECT Name, SerialNumber
            FROM Asset
            WHERE Product2Id = :pbe.Product2Id
        ];
        Assert.areEqual('05141399', updatedAsset.SerialNumber);
        Assert.areEqual('OC.FI004 - 05141399', updatedAsset.Name);
        Assert.areEqual(
            '05141399',
            [SELECT SerialNumber__c FROM WorkOrder WHERE Id = :workOrder.Id].SerialNumber__c
        );
    }

    @IsTest
    static void testApplyWorkOrderSerialOverride_mapsSerialAndModelToWorkOrder() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Override Model Scope',
            'OC.FI007',
            'FLEXIBLE SCOPE',
            null,
            'SCOPE',
            'GIF-H190'
        );
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, null);
        update new WorkOrder(
            Id = workOrder.Id,
            SerialNumber__c = '05141306',
            Model__c = 'GIF-H190'
        );
        WorkOrderLineItem woli = insertProductServicedLine(workOrder.Id, pbe.Id, '05141306');
        update new WorkOrderLineItem(Id = woli.Id, Model__c = 'GIF-H190');

        Test.startTest();
        ReceivingService.OverrideSerialResult result = ReceivingService.applyWorkOrderSerialOverride(
            woli.Id,
            '05141399',
            'GIF-H191'
        );
        Test.stopTest();

        Assert.isTrue(result.lineUpdated);
        WorkOrder updatedWorkOrder = [
            SELECT SerialNumber__c, Model__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        WorkOrderLineItem updatedLine = [
            SELECT SerialNumber__c, Model__c
            FROM WorkOrderLineItem
            WHERE Id = :woli.Id
        ];
        Assert.areEqual('05141399', updatedWorkOrder.SerialNumber__c);
        Assert.areEqual('GIF-H191', updatedWorkOrder.Model__c);
        Assert.areEqual('05141399', updatedLine.SerialNumber__c);
        Assert.areEqual('GIF-H191', updatedLine.Model__c);
    }

    @IsTest
    static void testApplyWorkOrderSerialOverride_oversizedSerialStillMapsModel() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Override Model Only',
            'OC.FI008',
            'FLEXIBLE SCOPE',
            null,
            'SCOPE',
            'GIF-H190'
        );
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, null);
        update new WorkOrder(
            Id = workOrder.Id,
            SerialNumber__c = '05141306',
            Model__c = 'GIF-H190'
        );
        WorkOrderLineItem woli = insertProductServicedLine(workOrder.Id, pbe.Id, '05141306');
        update new WorkOrderLineItem(Id = woli.Id, Model__c = 'GIF-H190');

        Test.startTest();
        ReceivingService.OverrideSerialResult result = ReceivingService.applyWorkOrderSerialOverride(
            woli.Id,
            '99999999',
            '11278AU1JSP'
        );
        Test.stopTest();

        Assert.isTrue(result.lineUpdated);
        Assert.isFalse(result.assetUpdated);
        Assert.areEqual('05141306', result.serialNumber);
        WorkOrder updatedWorkOrder = [
            SELECT SerialNumber__c, Model__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        WorkOrderLineItem updatedLine = [
            SELECT SerialNumber__c, Model__c
            FROM WorkOrderLineItem
            WHERE Id = :woli.Id
        ];
        Assert.areEqual('05141306', updatedWorkOrder.SerialNumber__c);
        Assert.areEqual('11278AU1JSP', updatedWorkOrder.Model__c);
        Assert.areEqual('05141306', updatedLine.SerialNumber__c);
        Assert.areEqual('11278AU1JSP', updatedLine.Model__c);
    }

    @IsTest
    static void testApplyWorkOrderSerialOverride_customerCareMovesOffContaminated() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Override Care Scope',
            'OC.FI009',
            'FLEXIBLE SCOPE',
            null,
            'SCOPE',
            'GIF-H190'
        );
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, null);
        update new WorkOrder(
            Id = workOrder.Id,
            SubStatus__c = 'Contaminated',
            Contaminated__c = true,
            SerialNumber__c = '05141306',
            Model__c = 'GIF-H190'
        );
        WorkOrderLineItem woli = insertProductServicedLine(workOrder.Id, pbe.Id, '05141306');
        update new WorkOrderLineItem(Id = woli.Id, Model__c = 'GIF-H190');

        Test.startTest();
        ReceivingService.OverrideSerialResult result = ReceivingService.applyWorkOrderSerialOverride(
            woli.Id,
            '99999999',
            'GIF-H191',
            new List<String>{ 'Serial Number Mismatch', 'Model Mismatch' },
            'Needs a call'
        );
        Test.stopTest();

        Assert.isTrue(result.lineUpdated);
        Assert.isFalse(result.assetUpdated);
        Assert.areEqual('05141306', result.serialNumber);
        WorkOrder updatedWorkOrder = [
            SELECT SubStatus__c, ReasonCode__c, CustomerCareNotes__c, SerialNumber__c, Model__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual('Customer Care', updatedWorkOrder.SubStatus__c);
        Assert.areEqual('Needs a call', updatedWorkOrder.CustomerCareNotes__c);
        Assert.isTrue(updatedWorkOrder.ReasonCode__c.contains('Serial Number Mismatch'));
        Assert.isTrue(updatedWorkOrder.ReasonCode__c.contains('Model Mismatch'));
        Assert.areEqual('05141306', updatedWorkOrder.SerialNumber__c);
        Assert.areEqual('GIF-H191', updatedWorkOrder.Model__c);
    }

    @IsTest
    static void testApplyWorkOrderSerialOverride_tooManyCharactersDoesNotUpdate() {
        // Setup
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Override Far Scope',
            'OC.FI005',
            'FLEXIBLE SCOPE',
            null,
            'SCOPE',
            'GIF-H190'
        );
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, null);
        WorkOrderLineItem woli = insertProductServicedLine(workOrder.Id, pbe.Id, '05141306');

        // When
        Test.startTest();
        ReceivingService.OverrideSerialResult result =
            ReceivingService.applyWorkOrderSerialOverride(woli.Id, '99999999');
        Test.stopTest();

        // Then
        Assert.isFalse(result.lineUpdated);
        Assert.isFalse(result.assetUpdated);
        Assert.areEqual('05141306', result.serialNumber);
        Assert.areEqual(
            '05141306',
            [SELECT SerialNumber__c FROM WorkOrderLineItem WHERE Id = :woli.Id].SerialNumber__c
        );
    }

    @IsTest
    static void testGetWorkOrderReceivingShellContext_populatesAssetAndProductIds() {
        // Setup
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Shell Ids Scope',
            'OC.FI006',
            'FLEXIBLE SCOPE',
            null,
            'SCOPE',
            'GIF-H190'
        );
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, null);
        Asset asset = new Asset(
            Name = 'GW5968 Shell Asset',
            SerialNumber = '05141306',
            Product2Id = pbe.Product2Id,
            AccountId = accountRecord.Id,
            Status = 'Purchased'
        );
        insert asset;
        WorkOrderLineItem woli = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRecordTypeId(),
            LineType__c = 'Product Serviced',
            IsAccessory__c = false,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            SerialNumber__c = '05141306',
            AssetId = asset.Id
        );
        insert woli;

        // When
        Test.startTest();
        ReceivingService.ReceivingShellContext context =
            ReceivingService.getWorkOrderReceivingShellContext(workOrder.Id);
        Test.stopTest();

        // Then
        Assert.areEqual(1, context.items.size());
        Assert.areEqual(String.valueOf(asset.Id), context.items[0].assetId);
        Assert.areEqual(String.valueOf(pbe.Product2Id), context.items[0].product2Id);
    }

    @IsTest
    static void testSubmitWorkOrderRerunResiTest_performedCreatesHistoryAndDisinfectionLine() {
        // Setup
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry servicedPbe = insertProductWithPricebookEntry(
            'GW5968 Rerun Scope',
            'RR.001',
            'FLEXIBLE SCOPE',
            null,
            'SCOPE',
            'GIF-H190'
        );
        Product2 disinfectionProduct = insertDisinfectionProduct('FLEXIBLE SCOPE', 'DIS.001');
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, servicedPbe.Product2Id);
        WorkOrderLineItem serviced = insertProductServicedLine(
            workOrder.Id,
            servicedPbe.Id,
            '05141306'
        );

        // When
        Test.startTest();
        ReceivingService.RerunResiTestResult result = ReceivingService.submitWorkOrderRerunResiTest(
            workOrder.Id,
            serviced.Id,
            true,
            'Contaminated',
            3
        );
        Test.stopTest();

        // Then
        Assert.isNotNull(result.resiTestHistoryId, 'History should be created when performed');
        Assert.isNotNull(result.disinfectionLineItemId, 'Disinfection line should be created');
        ResiTestHistory__c history = [
            SELECT WorkOrder__c, WorkOrderLineItem__c, DisinfectionStatus__c
            FROM ResiTestHistory__c
            WHERE Id = :result.resiTestHistoryId
        ];
        Assert.areEqual(workOrder.Id, history.WorkOrder__c);
        Assert.areEqual(serviced.Id, history.WorkOrderLineItem__c);
        Assert.areEqual('Contaminated', history.DisinfectionStatus__c);
        WorkOrderLineItem disinfection = [
            SELECT
                WorkOrderId,
                ParentWorkOrderLineItemId,
                Quantity,
                Status,
                LineType__c,
                Product__c,
                RepairCode__c,
                ProductCodeWoli__c,
                RecordType.DeveloperName
            FROM WorkOrderLineItem
            WHERE Id = :result.disinfectionLineItemId
        ];
        Assert.areEqual(workOrder.Id, disinfection.WorkOrderId);
        Assert.areEqual(serviced.Id, disinfection.ParentWorkOrderLineItemId);
        Assert.areEqual(3, disinfection.Quantity);
        Assert.areEqual('Approved', disinfection.Status);
        Assert.areEqual('Service Code', disinfection.LineType__c);
        Assert.areEqual(disinfectionProduct.Id, disinfection.Product__c);
        Assert.areEqual(disinfectionProduct.Id, disinfection.RepairCode__c);
        Assert.areEqual('DIS.001', disinfection.ProductCodeWoli__c);
        Assert.areEqual('RepairCode', disinfection.RecordType.DeveloperName);
        WorkOrder updatedWorkOrder = [
            SELECT SubStatus__c, Contaminated__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual('Contaminated', updatedWorkOrder.SubStatus__c);
        Assert.isTrue(updatedWorkOrder.Contaminated__c);
    }

    @IsTest
    static void testSubmitWorkOrderRerunResiTest_instrumentOrderWithoutLine() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Product2 disinfectionProduct = insertDisinfectionProduct('INSTRUMENT', 'DIS.INST');
        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Instrument Rerun',
            AccountId = accountRecord.Id,
            RecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
                .get('RepairCenterInstruments')
                .getRecordTypeId(),
            Pricebook2Id = Test.getStandardPricebookId(),
            QuantityReceived__c = 3,
            SubStatus__c = 'Contaminated',
            Contaminated__c = true
        );
        insert workOrder;

        Test.startTest();
        ReceivingService.RerunResiTestResult result = ReceivingService.submitWorkOrderRerunResiTest(
            workOrder.Id,
            null,
            true,
            'Clean',
            3
        );
        Test.stopTest();

        Assert.isNotNull(result.resiTestHistoryId);
        ResiTestHistory__c history = [
            SELECT WorkOrder__c, WorkOrderLineItem__c, DisinfectionStatus__c
            FROM ResiTestHistory__c
            WHERE Id = :result.resiTestHistoryId
        ];
        Assert.areEqual(workOrder.Id, history.WorkOrder__c);
        Assert.isNull(history.WorkOrderLineItem__c);
        Assert.areEqual('Clean', history.DisinfectionStatus__c);

        WorkOrderLineItem disinfection = [
            SELECT ParentWorkOrderLineItemId, Quantity, Product__c, LineType__c
            FROM WorkOrderLineItem
            WHERE Id = :result.disinfectionLineItemId
        ];
        Assert.isNull(disinfection.ParentWorkOrderLineItemId);
        Assert.areEqual(3, disinfection.Quantity);
        Assert.areEqual(disinfectionProduct.Id, disinfection.Product__c);
        Assert.areEqual('Service Code', disinfection.LineType__c);

        WorkOrder updatedWorkOrder = [
            SELECT SubStatus__c, Contaminated__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual('Ready for Eval', updatedWorkOrder.SubStatus__c);
        Assert.isFalse(updatedWorkOrder.Contaminated__c);
    }

    @IsTest
    static void testSubmitWorkOrderRerunResiTest_requiresLineForDevices() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, null);
        Boolean threw = false;

        Test.startTest();
        try {
            ReceivingService.submitWorkOrderRerunResiTest(workOrder.Id, null, true, 'Clean', 1);
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = e.getMessage().contains('Work Order Line Item');
        }
        Test.stopTest();

        Assert.isTrue(threw);
    }

    @IsTest
    static void testSubmitWorkOrderRerunResiTest_cleanMovesToReadyForEval() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry servicedPbe = insertProductWithPricebookEntry(
            'GW5968 Rerun Clean Scope',
            'RR.005',
            'FLEXIBLE SCOPE',
            null,
            'SCOPE',
            'GIF-H190'
        );
        insertDisinfectionProduct('FLEXIBLE SCOPE', 'DIS.005');
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, servicedPbe.Product2Id);
        update new WorkOrder(
            Id = workOrder.Id,
            SubStatus__c = 'Contaminated',
            Contaminated__c = true
        );
        WorkOrderLineItem serviced = insertProductServicedLine(
            workOrder.Id,
            servicedPbe.Id,
            '05141310'
        );

        Test.startTest();
        ReceivingService.submitWorkOrderRerunResiTest(
            workOrder.Id,
            serviced.Id,
            true,
            'Clean',
            1
        );
        Test.stopTest();

        WorkOrder updatedWorkOrder = [
            SELECT SubStatus__c, Contaminated__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual('Ready for Eval', updatedWorkOrder.SubStatus__c);
        Assert.isFalse(updatedWorkOrder.Contaminated__c);
    }

    @IsTest
    static void testSubmitWorkOrderRerunResiTest_cleanFlaggedMovesToCustomerCare() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry servicedPbe = insertProductWithPricebookEntry(
            'GW5968 Rerun Care Scope',
            'RR.006',
            'FLEXIBLE SCOPE',
            null,
            'SCOPE',
            'GIF-H190'
        );
        insertDisinfectionProduct('FLEXIBLE SCOPE', 'DIS.006');
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, servicedPbe.Product2Id);
        update new WorkOrder(
            Id = workOrder.Id,
            SubStatus__c = 'Contaminated',
            Contaminated__c = true,
            ReasonCode__c = 'Serial Number Mismatch'
        );
        WorkOrderLineItem serviced = insertProductServicedLine(
            workOrder.Id,
            servicedPbe.Id,
            '05141311'
        );

        Test.startTest();
        ReceivingService.submitWorkOrderRerunResiTest(
            workOrder.Id,
            serviced.Id,
            true,
            'Clean',
            1,
            new List<String>{ 'Model Mismatch' }
        );
        Test.stopTest();

        WorkOrder updatedWorkOrder = [
            SELECT SubStatus__c, Contaminated__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual('Customer Care', updatedWorkOrder.SubStatus__c);
        Assert.isFalse(updatedWorkOrder.Contaminated__c);
    }

    @IsTest
    static void testSubmitWorkOrderRerunResiTest_notPerformedCreatesOnlyDisinfectionLine() {
        // Setup
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry servicedPbe = insertProductWithPricebookEntry(
            'GW5968 Rerun No Test Scope',
            'RR.002',
            'FLEXIBLE SCOPE',
            null,
            'SCOPE',
            'GIF-H190'
        );
        insertDisinfectionProduct('FLEXIBLE SCOPE', 'DIS.002');
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, servicedPbe.Product2Id);
        WorkOrderLineItem serviced = insertProductServicedLine(
            workOrder.Id,
            servicedPbe.Id,
            '05141307'
        );

        // When
        Test.startTest();
        ReceivingService.RerunResiTestResult result = ReceivingService.submitWorkOrderRerunResiTest(
            workOrder.Id,
            serviced.Id,
            false,
            null,
            null
        );
        Test.stopTest();

        // Then
        Assert.isNull(result.resiTestHistoryId, 'No history when Resi-Test was not performed');
        Assert.isNotNull(result.disinfectionLineItemId);
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM ResiTestHistory__c WHERE WorkOrder__c = :workOrder.Id]
        );
        Assert.areEqual(
            1,
            [
                SELECT Quantity
                FROM WorkOrderLineItem
                WHERE Id = :result.disinfectionLineItemId
            ].Quantity,
            'Quantity should default to 1'
        );
    }

    @IsTest
    static void testSubmitWorkOrderRerunResiTest_blankItemStatusFindsDisinfectionProduct() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry servicedPbe = insertProductWithPricebookEntry(
            'GW5968 Rerun Blank Status Scope',
            'RR.004',
            'FLEXIBLE SCOPE',
            null,
            'SCOPE',
            'GIF-H190'
        );
        Product2 disinfectionProduct = new Product2(
            Name = 'GW5968 Disinfection DIS.004',
            IsActive = true,
            ProductCode = 'DIS.004',
            ProductLine__c = 'FLEXIBLE SCOPE',
            ServiceCodeType__c = 'Disinfection'
        );
        insert disinfectionProduct;
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = disinfectionProduct.Id,
            UnitPrice = 1,
            IsActive = true
        );
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, servicedPbe.Product2Id);
        WorkOrderLineItem serviced = insertProductServicedLine(
            workOrder.Id,
            servicedPbe.Id,
            '05141309'
        );

        Test.startTest();
        ReceivingService.RerunResiTestResult result = ReceivingService.submitWorkOrderRerunResiTest(
            workOrder.Id,
            serviced.Id,
            false,
            null,
            1
        );
        Test.stopTest();

        Assert.isNotNull(result.disinfectionLineItemId);
    }

    @IsTest
    static void testSubmitWorkOrderRerunResiTest_missingDisinfectionProduct_rollsBackHistory() {
        // Setup
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry servicedPbe = insertProductWithPricebookEntry(
            'GW5968 Rerun Missing Dis Scope',
            'RR.003',
            'FLEXIBLE SCOPE',
            null,
            'SCOPE',
            'GIF-H190'
        );
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, servicedPbe.Product2Id);
        WorkOrderLineItem serviced = insertProductServicedLine(
            workOrder.Id,
            servicedPbe.Id,
            '05141308'
        );
        Boolean threw = false;

        // When
        Test.startTest();
        try {
            ReceivingService.submitWorkOrderRerunResiTest(
                workOrder.Id,
                serviced.Id,
                true,
                'Clean',
                1
            );
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Disinfection'), e.getMessage());
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw, 'Missing Disinfection product should throw');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM ResiTestHistory__c WHERE WorkOrder__c = :workOrder.Id],
            'History should be rolled back with the failed disinfection line'
        );
    }

    @IsTest
    static void testSubmitWorkOrderRerunResiTest_vendorWorkOrder_throws() {
        // Setup
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        WorkOrder vendorWorkOrder = new WorkOrder(
            Subject = 'GW5968 Vendor Rerun',
            AccountId = accountRecord.Id,
            RecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
                .get('RepairCenterOther')
                .getRecordTypeId(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert vendorWorkOrder;
        PricebookEntry pbe = insertProductWithPricebookEntry(
            'GW5968 Vendor Rerun Product',
            'RR.004',
            'FLEXIBLE SCOPE',
            null,
            'SCOPE',
            'GIF-H190'
        );
        WorkOrderLineItem serviced = insertProductServicedLine(vendorWorkOrder.Id, pbe.Id, 'V1');
        Boolean threw = false;

        // When
        Test.startTest();
        try {
            ReceivingService.submitWorkOrderRerunResiTest(
                vendorWorkOrder.Id,
                serviced.Id,
                true,
                'Clean',
                1
            );
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Vendor'), e.getMessage());
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw, 'Vendor Work Order should be rejected');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM ResiTestHistory__c WHERE WorkOrder__c = :vendorWorkOrder.Id]
        );
    }

    @IsTest
    static void testSubmitWorkOrderRerunResiTest_nullWorkOrder_throws() {
        // Setup
        Boolean threw = false;

        // When
        Test.startTest();
        try {
            ReceivingService.submitWorkOrderRerunResiTest(null, null, true, 'Clean', 1);
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('required'));
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw, 'Null Work Order should throw');
    }

    @IsTest
    static void testReprintWorkOrderTravelTag_nullWorkOrder_throws() {
        // Setup
        Boolean threw = false;

        // When
        Test.startTest();
        try {
            ReceivingService.reprintWorkOrderTravelTag(null);
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('required'));
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw, 'Null Work Order should throw');
    }

    @IsTest
    static void testReprintWorkOrderTravelTag_devicesSuccess() {
        // Setup
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, null);
        insertTravelTagWorkstationPrinter('RecvTravelTag01', '10.1.1.50');
        PrinterService.testCalloutResponseMap = travelTagSuccessResponse('^XA^XZ');
        BinTagPrintQuantitiesService.testPrintQuantity = 1;

        // When
        String message;
        Test.startTest();
        try {
            message = ReceivingService.reprintWorkOrderTravelTag(workOrder.Id);
        } finally {
            resetTravelTagPrintTestHooks();
        }
        Test.stopTest();

        // Then
        Assert.isTrue(
            message != null && message.contains('RecvTravelTag01'),
            'Success message should include the mapped printer name: ' + message
        );
    }

    @IsTest
    static void testReprintWorkOrderTravelTag_vendorWorkOrder_throws() {
        // Setup
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        WorkOrder vendorWorkOrder = new WorkOrder(
            Subject = 'GW5968 Vendor Travel Tag',
            AccountId = accountRecord.Id,
            RecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
                .get('RepairCenterOther')
                .getRecordTypeId(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert vendorWorkOrder;
        Boolean threw = false;

        // When
        Test.startTest();
        try {
            ReceivingService.reprintWorkOrderTravelTag(vendorWorkOrder.Id);
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Vendor'), e.getMessage());
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw, 'Vendor Work Orders should not print Travel Tags');
    }

    @IsTest
    static void testReprintWorkOrderTravelTag_noPrinterMapped_throws() {
        // Setup
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, null);
        PrinterService.testCalloutResponseMap = travelTagSuccessResponse('^XA^XZ');
        BinTagPrintQuantitiesService.testPrintQuantity = 1;
        Boolean threw = false;

        // When
        Test.startTest();
        try {
            ReceivingService.reprintWorkOrderTravelTag(workOrder.Id);
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('TRAVEL_TAG') || e.getMessage().contains('printer'),
                e.getMessage()
            );
        } finally {
            resetTravelTagPrintTestHooks();
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw, 'Missing TRAVEL_TAG workstation mapping should throw');
    }

    @IsTest
    static void testReprintWorkOrderTravelTag_calloutFailure_throws() {
        // Setup
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        WorkOrder workOrder = insertDevicesWorkOrder(accountRecord.Id, null);
        insertTravelTagWorkstationPrinter('RecvTravelTagFail', '10.1.1.51');
        PrinterService.testCalloutResponseMap = new Map<String, Object>{
            'SO_SUCCESS' => false,
            'SERVICE_DATA' => 'printer offline',
            'SERVICE_STATUS' => 500
        };
        BinTagPrintQuantitiesService.testPrintQuantity = 1;
        Boolean threw = false;

        // When
        Test.startTest();
        try {
            ReceivingService.reprintWorkOrderTravelTag(workOrder.Id);
        } catch (ReceivingService.ReceivingServiceException e) {
            threw = true;
            Assert.isTrue(String.isNotBlank(e.getMessage()), e.getMessage());
        } finally {
            resetTravelTagPrintTestHooks();
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw, 'Failed print callout should surface as ReceivingServiceException');
    }

    @IsTest
    static void testSubmitCreateOrder_createsSerializedReturnOrder() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'GW5492 Receiving Account'
            LIMIT 1
        ];
        Contact contact = new Contact(
            FirstName = 'Recv',
            LastName = 'Create',
            Email = 'recv.create@example.com',
            AccountId = accountRecord.Id
        );
        insert contact;
        Department__c department = new Department__c(Name = 'Recv Create Surgery');
        insert department;
        PricebookEntry pricebookEntry = insertProductWithPricebookEntry(
            'Recv Create Product',
            'RECV-CREATE-1',
            'Surgical',
            null,
            null,
            'MDL-CREATE'
        );
        Id repairCenterId = insertEligibleCreateOrderResource();
        Map<String, Object> header = new Map<String, Object>{
            'accountId' => accountRecord.Id,
            'operatingUnit' => '82',
            'salesRepId' => UserInfo.getUserId()
        };
        List<Object> items = new List<Object>{
            new Map<String, Object>{
                'product2Id' => pricebookEntry.Product2Id,
                'productLine' => 'Surgical',
                'model' => 'Create Model',
                'serialNumber' => 'SN-CREATE-1',
                'departmentId' => department.Id,
                'contactId' => contact.Id,
                'disinfected' => 'Yes, Item is Disinfected',
                'reportedProblem' => 'Does not power on',
                'estimateRequired' => 'Pre-Approved',
                'customerPo' => 'PO-CREATE-1'
            }
        };

        Test.startTest();
        ReceivingService.CreateOrderSubmitResult result = ReceivingService.submitCreateOrder(
            JSON.serialize(header),
            JSON.serialize(items)
        );
        Test.stopTest();

        Assert.areEqual(1, result.returnOrderIds.size());
        Assert.areEqual(1, result.returnOrderNumbers.size());
        Assert.areEqual(result.returnOrderIds[0], result.navigationReturnOrderId);
        Assert.isTrue(String.isNotBlank(result.returnOrderNumbers[0]));

        ReturnOrder createdOrder = [
            SELECT DestinationLocationId, ReturnOrderType__c, CreationSource__c
            FROM ReturnOrder
            WHERE Id = :result.returnOrderIds[0]
        ];
        Assert.areEqual(repairCenterId, createdOrder.DestinationLocationId);
        Assert.areEqual('Serialized', createdOrder.ReturnOrderType__c);
        Assert.areEqual('Salesforce', createdOrder.CreationSource__c);
        Assert.areEqual(1, [
            SELECT COUNT()
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :createdOrder.Id
        ]);
    }

    @IsTest
    static void testSubmitCreateOrder_whenNoItems_throws() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        insertEligibleCreateOrderResource();
        Map<String, Object> header = new Map<String, Object>{
            'accountId' => accountRecord.Id,
            'operatingUnit' => '82'
        };

        Test.startTest();
        try {
            ReceivingService.submitCreateOrder(
                JSON.serialize(header),
                JSON.serialize(new List<Object>())
            );
            Assert.fail('Submit with no items should throw');
        } catch (ReceivingService.ReceivingServiceException e) {
            Assert.isTrue(e.getMessage().contains('Add at least one item'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateWorkOrdersForCreateOrder_createsParentWorkOrder() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            WHERE ReturnOrderType__c = 'Serialized'
            LIMIT 1
        ];
        ReturnOrderLineItem lineItem = [
            SELECT Product2Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            LIMIT 1
        ];
        lineItem.Model__c = 'MDL-CREATE';
        lineItem.SerialNumber__c = 'SN-CREATE-WO';
        lineItem.ProductLine__c = 'Surgical';
        lineItem.Disinfected__c = 'Yes, Item is Disinfected';
        update lineItem;
        Id standardPricebookId = Test.getStandardPricebookId();
        List<PricebookEntry> existingEntries = [
            SELECT Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPricebookId
            AND Product2Id = :lineItem.Product2Id
            LIMIT 1
        ];
        if (existingEntries.isEmpty()) {
            insert new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id = lineItem.Product2Id,
                UnitPrice = 1,
                IsActive = true
            );
        }

        Test.startTest();
        ReceivingService.CreateOrderCreatedWorkOrder created =
            ReceivingService.createWorkOrdersForCreateOrder(returnOrder.Id);
        Test.stopTest();

        Assert.isNotNull(created.workOrderId);
        Assert.isTrue(String.isNotBlank(created.workOrderNumber));
        WorkOrder createdWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Id = :created.workOrderId
        ];
        Assert.areEqual(created.workOrderId, createdWorkOrder.Id);
    }

    @IsTest
    static void testCreateWorkOrdersForCreateOrder_whenIdNull_throws() {
        Test.startTest();
        try {
            ReceivingService.createWorkOrdersForCreateOrder(null);
            Assert.fail('Null Return Order should throw');
        } catch (ReceivingService.ReceivingServiceException e) {
            Assert.isTrue(e.getMessage().contains('Return Order is required'));
        }
        Test.stopTest();
    }

    private static Id insertEligibleCreateOrderResource() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'DUN-NORTHAMPTON (UK)',
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert repairCenter;
        ServiceResource resource = new ServiceResource(
            Name = 'GW5996 Create Order Resource',
            RelatedRecordId = UserInfo.getUserId(),
            LocationId = repairCenter.Id,
            IsActive = true,
            ResourceType = 'T'
        );
        insert resource;
        resource.put('RepairCenter__c', repairCenter.Id);
        update resource;
        return repairCenter.Id;
    }

    private static void insertTravelTagWorkstationPrinter(String printerName, String ipAddress) {
        insert new WorkstationPrinter__c(
            Name = printerName,
            Active__c = true,
            User__c = UserInfo.getUserId(),
            PrinterType__c = 'TRAVEL_TAG',
            PrinterModel__c = 'GX420t',
            IPAddress__c = ipAddress
        );
    }

    private static Map<String, Object> travelTagSuccessResponse(String zpl) {
        return new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => zpl,
            'SERVICE_STATUS' => 200
        };
    }

    private static void resetTravelTagPrintTestHooks() {
        PrinterService.testCalloutResponseMap = null;
        PrinterService.lastRequestForTest = null;
        BinTagPrintQuantitiesService.testPrintQuantity = null;
    }

    private static WorkOrder insertDevicesWorkOrder(Id accountId, Id product2Id) {
        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Receiving Actions',
            AccountId = accountId,
            RecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
                .get('RepairCenterDevices')
                .getRecordTypeId(),
            Pricebook2Id = Test.getStandardPricebookId(),
            Product__c = product2Id
        );
        insert workOrder;
        return workOrder;
    }

    private static WorkOrderLineItem insertProductServicedLine(
        Id workOrderId,
        Id pricebookEntryId,
        String serialNumber
    ) {
        WorkOrderLineItem lineItem = new WorkOrderLineItem(
            WorkOrderId = workOrderId,
            RecordTypeId = productServicedRecordTypeId(),
            LineType__c = 'Product Serviced',
            IsAccessory__c = false,
            PricebookEntryId = pricebookEntryId,
            Quantity = 1,
            SerialNumber__c = serialNumber
        );
        insert lineItem;
        return lineItem;
    }

    private static Product2 insertDisinfectionProduct(String productLine, String productCode) {
        Product2 product = new Product2(
            Name = 'GW5968 Disinfection ' + productCode,
            IsActive = true,
            Status__c = 'Active',
            ProductCode = productCode,
            ProductLine__c = productLine,
            ServiceCodeType__c = 'Disinfection'
        );
        insert product;
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        return product;
    }

    private static Id productServicedRecordTypeId() {
        return Schema.SObjectType.WorkOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get('ProductServiced')
            .getRecordTypeId();
    }

    private static PricebookEntry insertProductWithPricebookEntry(
        String name,
        String productCode,
        String productLine,
        String subProductLine,
        String deviceType,
        String model
    ) {
        Product2 product = new Product2(
            Name = name,
            IsActive = true,
            ProductCode = productCode,
            ProductLine__c = productLine,
            SubProductLine__c = subProductLine,
            DeviceType__c = deviceType,
            Model__c = model
        );
        insert product;
        PricebookEntry entry = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert entry;
        return entry;
    }
}