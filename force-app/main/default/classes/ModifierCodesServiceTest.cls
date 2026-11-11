/**
 * @description GW-3458 - Modifier Codes save, cascade, inheritance, and dropdown filters.
 */
@IsTest
private class ModifierCodesServiceTest {
    @IsTest
    static void shouldBuildDeviceAndInstrumentTables() {
        Fixture fixture = new Fixture().persist();
        WorkOrderLineItem accessory = fixture.line(ModifierCodesService.LINE_PRODUCT_SERVICED, null);
        accessory.IsAccessory__c = true;
        accessory.ProductCodeWoli__c = 'ACC';
        insert accessory;

        ModifierCodesService.Workspace deviceWorkspace = ModifierCodesService.getWorkspace(
            fixture.workOrderId,
            'device'
        );
        ModifierCodesService.Workspace instrumentWorkspace = ModifierCodesService.getWorkspace(
            fixture.workOrderId,
            ModifierCodesService.VARIANT_INSTRUMENT
        );

        Assert.areEqual(1, deviceWorkspace.items.size(), 'Accessory product lines stay off the item table.');
        Assert.areEqual('SN-1', deviceWorkspace.items[0].serialNumber);
        Assert.areEqual(3, deviceWorkspace.services.size(), 'Service and category lines both display.');
        Assert.isTrue(deviceWorkspace.showOrderReference);
        Assert.areEqual(1, instrumentWorkspace.groups.size());
        Assert.areEqual(3, instrumentWorkspace.groups[0].services.size());
        Assert.isFalse(instrumentWorkspace.showOrderReference);
        Assert.isTrue(instrumentWorkspace.groups[0].title.contains('IN.1'));
    }

    @IsTest
    static void shouldCascadeItemAndServiceModifierWithoutOverwritingADifferentOne() {
        Fixture fixture = new Fixture().persist();
        PricingModifier__c shared = fixture.modifier('Shared', ModifierCodesService.LEVEL_ITEM_AND_SERVICE, true);
        PricingModifier__c other = fixture.modifier('Other', ModifierCodesService.LEVEL_SERVICE, true);
        update new WorkOrderLineItem(Id = fixture.serviceId, PricingModifier__c = other.Id, PricingModifierName__c = 'Other');

        ModifierCodesService.saveModifier(fixture.request(fixture.itemId, shared.Id, true));

        Map<Id, WorkOrderLineItem> saved = reload(new Set<Id>{ fixture.itemId, fixture.serviceId, fixture.categoryId });
        Assert.areEqual(shared.Id, saved.get(fixture.itemId).PricingModifier__c);
        Assert.areEqual(10, saved.get(fixture.itemId).PricingModifierValue__c);
        Assert.areEqual('Shared', saved.get(fixture.itemId).PricingModifierName__c);
        Assert.areEqual(other.Id, saved.get(fixture.serviceId).PricingModifier__c, 'A different service modifier stays.');
        Assert.areEqual(null, saved.get(fixture.categoryId).PricingModifier__c, 'Category lines are not inherited.');
    }

    @IsTest
    static void shouldApplyItemAndServiceModifierToBlankServiceCodes() {
        Fixture fixture = new Fixture().persist();
        PricingModifier__c shared = fixture.modifier('Shared', ModifierCodesService.LEVEL_ITEM_AND_SERVICE, true);

        ModifierCodesService.saveModifier(fixture.request(fixture.itemId, shared.Id, true));

        WorkOrderLineItem service = WorkOrderLineItemsSelector.selectForModifierUpdate(fixture.serviceId)[0];
        Assert.areEqual(shared.Id, service.PricingModifier__c);
        Assert.areEqual('TECHNICIAN', service.ModifierReasonCode__c);
        Assert.areEqual(fixture.priorWorkOrderId, service.OrderReference__c);
    }

    @IsTest
    static void shouldLeaveServicesAloneWhenTheItemModifierIsItemOnly() {
        Fixture fixture = new Fixture().persist();
        PricingModifier__c itemOnly = fixture.modifier('Item Only', ModifierCodesService.LEVEL_ITEM, true);

        ModifierCodesService.saveModifier(fixture.request(fixture.itemId, itemOnly.Id, true));

        WorkOrderLineItem service = WorkOrderLineItemsSelector.selectForModifierUpdate(fixture.serviceId)[0];
        Assert.areEqual(null, service.PricingModifier__c);
    }

    @IsTest
    static void shouldRemoveInheritedModifiersAndKeepADifferentServiceModifier() {
        Fixture fixture = new Fixture().persist();
        PricingModifier__c shared = fixture.modifier('Shared', ModifierCodesService.LEVEL_ITEM_AND_SERVICE, true);
        PricingModifier__c other = fixture.modifier('Other', ModifierCodesService.LEVEL_SERVICE, true);
        ModifierCodesService.saveModifier(fixture.request(fixture.itemId, shared.Id, true));
        ModifierCodesService.saveModifier(fixture.request(fixture.serviceId, other.Id, true));

        ModifierCodesService.removeModifier(fixture.itemId);

        Map<Id, WorkOrderLineItem> saved = reload(new Set<Id>{ fixture.itemId, fixture.blankServiceId, fixture.serviceId });
        Assert.areEqual(null, saved.get(fixture.itemId).PricingModifier__c);
        Assert.areEqual(null, saved.get(fixture.blankServiceId).PricingModifier__c);
        Assert.areEqual(other.Id, saved.get(fixture.serviceId).PricingModifier__c);
    }

    @IsTest
    static void shouldNotCascadeAServiceModifier() {
        Fixture fixture = new Fixture().persist();
        PricingModifier__c serviceModifier = fixture.modifier('Service Only', ModifierCodesService.LEVEL_SERVICE, true);

        ModifierCodesService.saveModifier(fixture.request(fixture.blankServiceId, serviceModifier.Id, true));

        WorkOrderLineItem sibling = WorkOrderLineItemsSelector.selectForModifierUpdate(fixture.serviceId)[0];
        Assert.areEqual(null, sibling.PricingModifier__c);
    }

    @IsTest
    static void shouldRejectADiscountedServiceAndAWrongModifierLevel() {
        Fixture fixture = new Fixture().persist();
        update new WorkOrderLineItem(Id = fixture.blankServiceId, CategoryCodeDiscount__c = 15);
        PricingModifier__c serviceModifier = fixture.modifier('Service Only', ModifierCodesService.LEVEL_SERVICE, true);

        try {
            ModifierCodesService.saveModifier(fixture.request(fixture.blankServiceId, serviceModifier.Id, true));
            Assert.fail('A discounted service should not accept a new modifier.');
        } catch (ModifierCodesService.ModifierCodesException expected) {
            Assert.isTrue(expected.getMessage().contains('category code discount'));
        }

        try {
            ModifierCodesService.saveModifier(fixture.request(fixture.itemId, serviceModifier.Id, true));
            Assert.fail('A service-only modifier should not apply to an item.');
        } catch (ModifierCodesService.ModifierCodesException expected) {
            Assert.isTrue(expected.getMessage().contains('not available'));
        }
    }

    @IsTest
    static void shouldRejectAnOrderReferenceFromAnotherAsset() {
        Fixture fixture = new Fixture().persist();
        PricingModifier__c itemOnly = fixture.modifier('Item Only', ModifierCodesService.LEVEL_ITEM, true);
        ModifierCodesService.SaveRequest request = fixture.request(fixture.itemId, itemOnly.Id, true);
        request.orderReferenceId = fixture.otherAssetWorkOrderId;

        try {
            ModifierCodesService.saveModifier(request);
            Assert.fail('An order reference from another asset should be rejected.');
        } catch (ModifierCodesService.ModifierCodesException expected) {
            Assert.isTrue(expected.getMessage().contains('Order Reference'));
        }
    }

    @IsTest
    static void shouldListActiveModifiersAndShippedWorkOrdersByCompletion() {
        Fixture fixture = new Fixture().persist();
        fixture.modifier('Item Choice', ModifierCodesService.LEVEL_ITEM, true);
        fixture.modifier('Hidden', ModifierCodesService.LEVEL_ITEM, false);
        fixture.modifier('Service Choice', ModifierCodesService.LEVEL_SERVICE, true);

        List<ModifierCodesService.PickOption> itemOptions = ModifierCodesService.getPricingModifierOptions('item');
        List<String> itemLabels = new List<String>();
        for (ModifierCodesService.PickOption option : itemOptions) {
            itemLabels.add(option.label);
        }
        Assert.isTrue(itemLabels.contains('Item Choice'));
        Assert.isFalse(itemLabels.contains('Hidden'));
        Assert.isFalse(itemLabels.contains('Service Choice'));

        List<ModifierCodesService.PickOption> priorOrders = ModifierCodesService.getPriorWorkOrders(fixture.assetId);
        Assert.areEqual(2, priorOrders.size());
        Assert.areEqual(fixture.newerCompletionWorkOrderId, (Id) priorOrders[0].value);
    }

    @IsTest
    static void shouldInheritWhenAServiceCodeIsCreated() {
        Fixture fixture = new Fixture().persist();
        PricingModifier__c shared = fixture.modifier('Shared', ModifierCodesService.LEVEL_ITEM_AND_SERVICE, true);
        ModifierCodesService.saveModifier(fixture.request(fixture.itemId, shared.Id, false));

        WorkOrderLineItem created = (WorkOrderLineItem) new adb_WorkOrderLineItem().record;
        created.WorkOrderId = fixture.workOrderId;
        created.ParentWorkOrderLineItemId = fixture.itemId;
        created.LineType__c = ModifierCodesService.LINE_SERVICE_CODE;
        created.RecordTypeId = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCode')
            .getRecordTypeId();
        WorkOrderLineItemsService.createLineItems(new List<WorkOrderLineItem>{ created });

        WorkOrderLineItem saved = WorkOrderLineItemsSelector.selectForModifierUpdate(created.Id)[0];
        Assert.areEqual(shared.Id, saved.PricingModifier__c);
    }

    @IsTest
    static void shouldSurfaceAMissingWorkOrderFromTheController() {
        try {
            ModifierCodesController.getWorkspace(null, 'device');
            Assert.fail('A missing work order should be reported.');
        } catch (AuraHandledException expected) {
            Assert.isTrue(String.isNotBlank(expected.getMessage()));
        }
    }

    private static Map<Id, WorkOrderLineItem> reload(Set<Id> lineIds) {
        Map<Id, WorkOrderLineItem> linesById = new Map<Id, WorkOrderLineItem>();
        for (Id lineId : lineIds) {
            linesById.put(lineId, WorkOrderLineItemsSelector.selectForModifierUpdate(lineId)[0]);
        }
        return linesById;
    }

    private class Fixture {
        Id workOrderId;
        Id assetId;
        Id itemId;
        Id serviceId;
        Id blankServiceId;
        Id categoryId;
        Id priorWorkOrderId;
        Id newerCompletionWorkOrderId;
        Id otherAssetWorkOrderId;

        Fixture persist() {
            adb_Account accountBuilder = new adb_Account();
            adb_Asset assetBuilder = new adb_Asset().account(accountBuilder).name('Scope').serialNumber('SN-1');
            adb_Asset otherAssetBuilder = new adb_Asset().account(accountBuilder).name('Other');
            adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
                .account(accountBuilder)
                .asset(assetBuilder)
                .subject('Modifier Eval')
                .setRecordType('RepairCenterDevices');
            adb_WorkOrder olderBuilder = new adb_WorkOrder()
                .account(accountBuilder)
                .asset(assetBuilder)
                .subject('Older Completion')
                .setRecordType('RepairCenterDevices')
                .actualShipDate(Date.today().addDays(-1));
            adb_WorkOrder newerBuilder = new adb_WorkOrder()
                .account(accountBuilder)
                .asset(assetBuilder)
                .subject('Newer Completion')
                .setRecordType('RepairCenterDevices')
                .actualShipDate(Date.today().addDays(-10));
            adb_WorkOrder unshippedBuilder = new adb_WorkOrder()
                .account(accountBuilder)
                .asset(assetBuilder)
                .subject('Unshipped')
                .setRecordType('RepairCenterDevices');
            adb_WorkOrder otherAssetWorkOrderBuilder = new adb_WorkOrder()
                .account(accountBuilder)
                .asset(otherAssetBuilder)
                .subject('Other Asset')
                .setRecordType('RepairCenterDevices')
                .actualShipDate(Date.today());
            accountBuilder.persist();

            this.workOrderId = workOrderBuilder.id;
            this.assetId = assetBuilder.id;
            this.priorWorkOrderId = olderBuilder.id;
            this.newerCompletionWorkOrderId = newerBuilder.id;
            this.otherAssetWorkOrderId = otherAssetWorkOrderBuilder.id;
            update new List<WorkOrder>{
                new WorkOrder(Id = olderBuilder.id, CompletedTimestamp__c = Datetime.now().addDays(-5)),
                new WorkOrder(Id = newerBuilder.id, CompletedTimestamp__c = Datetime.now())
            };

            WorkOrderLineItem item = line(ModifierCodesService.LINE_PRODUCT_SERVICED, null);
            item.SerialNumber__c = 'SN-1';
            item.ProductCodeWoli__c = 'IN.1';
            item.ProductDescription__c = 'Biter Repair';
            item.Model__c = 'M1';
            insert item;
            this.itemId = item.Id;

            WorkOrderLineItem service = line(ModifierCodesService.LINE_SERVICE_CODE, item.Id);
            service.ProductCodeWoli__c = 'SC.1';
            service.ProductDescription__c = 'Clean';
            insert service;
            this.serviceId = service.Id;

            WorkOrderLineItem blankService = line(ModifierCodesService.LINE_SERVICE_CODE, item.Id);
            blankService.ProductCodeWoli__c = 'SC.2';
            insert blankService;
            this.blankServiceId = blankService.Id;

            WorkOrderLineItem category = line(ModifierCodesService.LINE_CATEGORY_CODE, item.Id);
            category.ProductCodeWoli__c = 'CC.1';
            insert category;
            this.categoryId = category.Id;
            return this;
        }

        WorkOrderLineItem line(String lineType, Id parentId) {
            WorkOrderLineItem lineItem = (WorkOrderLineItem) new adb_WorkOrderLineItem().record;
            lineItem.WorkOrderId = this.workOrderId;
            lineItem.LineType__c = lineType;
            lineItem.ParentWorkOrderLineItemId = parentId;
            String recordTypeName = lineType == ModifierCodesService.LINE_PRODUCT_SERVICED
                ? 'ProductServiced'
                : 'RepairCode';
            lineItem.RecordTypeId = Schema.SObjectType.WorkOrderLineItem
                .getRecordTypeInfosByDeveloperName()
                .get(recordTypeName)
                .getRecordTypeId();
            return lineItem;
        }

        PricingModifier__c modifier(String name, String level, Boolean active) {
            PricingModifier__c pricingModifier = new PricingModifier__c(
                Name = name,
                ModifierLevel__c = level,
                ModifierValue__c = 10,
                Active__c = active,
                ModifierType__c = 'Percentage'
            );
            insert pricingModifier;
            return pricingModifier;
        }

        ModifierCodesService.SaveRequest request(Id lineId, Id modifierId, Boolean applyOrderReference) {
            ModifierCodesService.SaveRequest saveRequest = new ModifierCodesService.SaveRequest();
            saveRequest.workOrderLineItemId = lineId;
            saveRequest.pricingModifierId = modifierId;
            saveRequest.modifierReasonCode = 'TECHNICIAN';
            saveRequest.orderReferenceId = this.priorWorkOrderId;
            saveRequest.applyOrderReference = applyOrderReference;
            return saveRequest;
        }
    }
}