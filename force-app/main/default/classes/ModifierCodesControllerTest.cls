/**
 * @description GW-3458 - Modifier Codes tab entry points for load, save, and remove.
 */
@IsTest
private class ModifierCodesControllerTest {
	@IsTest
	static void shouldLoadTablesAndDropdowns() {
		adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
			.subject('Modifier controller');
		workOrderBuilder.persist();

		Test.startTest();
		ModifierCodesService.Workspace deviceWorkspace = ModifierCodesController.getWorkspace(
			workOrderBuilder.id,
			'device'
		);
		ModifierCodesService.Workspace instrumentWorkspace = ModifierCodesController.getWorkspace(
			workOrderBuilder.id,
			ModifierCodesService.VARIANT_INSTRUMENT
		);
		List<ModifierCodesService.PickOption> itemOptions = ModifierCodesController.getPricingModifierOptions(
			'item'
		);
		List<ModifierCodesService.PickOption> priorOrders = ModifierCodesController.getPriorWorkOrders(
			null,
			null
		);
		Test.stopTest();

		Assert.isNotNull(deviceWorkspace);
		Assert.isTrue(deviceWorkspace.showOrderReference);
		Assert.isFalse(instrumentWorkspace.showOrderReference);
		Assert.isNotNull(itemOptions);
		Assert.isTrue(
			priorOrders.isEmpty(),
			'A missing asset has no shipped work orders.'
		);
	}

	@IsTest
	static void shouldSaveAndRemoveAModifier() {
		adb_Account accountBuilder = new adb_Account();
		adb_Asset assetBuilder = new adb_Asset()
			.account(accountBuilder)
			.name('Scope')
			.serialNumber('SN-CTL');
		adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
			.account(accountBuilder)
			.asset(assetBuilder)
			.subject('Controller Eval')
			.setRecordType('RepairCenterDevices');
		accountBuilder.persist();

		WorkOrderLineItem item = (WorkOrderLineItem) new adb_WorkOrderLineItem()
			.record;
		item.WorkOrderId = workOrderBuilder.id;
		item.LineType__c = ModifierCodesService.LINE_PRODUCT_SERVICED;
		item.RecordTypeId = Schema.SObjectType.WorkOrderLineItem
			.getRecordTypeInfosByDeveloperName()
			.get('ProductServiced')
			.getRecordTypeId();
		insert item;

		PricingModifier__c pricingModifier = new PricingModifier__c(
			Name = 'Controller Item',
			ModifierLevel__c = ModifierCodesService.LEVEL_ITEM,
			ModifierValue__c = 10,
			Active__c = true,
			ModifierType__c = 'Percentage'
		);
		insert pricingModifier;

		Test.startTest();
		ModifierCodesController.saveModifier(
			item.Id,
			pricingModifier.Id,
			'TECHNICIAN',
			null,
			false
		);
		WorkOrderLineItem saved = WorkOrderLineItemsSelector.selectForModifierUpdate(
			item.Id
		)[0];
		ModifierCodesController.removeModifier(item.Id);
		Test.stopTest();

		WorkOrderLineItem cleared = WorkOrderLineItemsSelector.selectForModifierUpdate(
			item.Id
		)[0];
		Assert.areEqual(pricingModifier.Id, saved.PricingModifier__c);
		Assert.isNull(cleared.PricingModifier__c);
	}

	@IsTest
	static void shouldReportAMissingLineWhenSavingOrRemoving() {
		try {
			ModifierCodesController.saveModifier(null, null, null, null, false);
			Assert.fail('A missing line should not be saved.');
		} catch (AuraHandledException expected) {
			Assert.isTrue(
				expected.getMessage().contains('Work Order Line is required.')
			);
		}

		try {
			ModifierCodesController.removeModifier(null);
			Assert.fail('A missing line should not be removed.');
		} catch (AuraHandledException expected) {
			Assert.isTrue(expected.getMessage().contains('was not found'));
		}
	}
}