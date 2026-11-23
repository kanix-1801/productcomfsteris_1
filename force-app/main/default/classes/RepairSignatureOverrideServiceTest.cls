/**
 * @description GW-5310 tests for Repair Coordinator signature override.
 */
@IsTest
private class RepairSignatureOverrideServiceTest {
	@IsTest
	static void loadRejectsBlankUnknownAndUnsupportedWorkOrders() {
		OverrideFixture fixture = createFixture('GW5310-BAD');
		WorkOrder otherWorkOrder = new WorkOrder(
			Subject = 'GW5310 Other',
			Status = 'Repair',
			AccountId = fixture.customer.Id,
			RecordTypeId = recordTypeId(WorkOrder.SObjectType, 'RepairCenterOther'),
			RepairCenter__c = fixture.repairCenter.Id
		);
		insert otherWorkOrder;

		assertOverrideError('', 'required');
		assertOverrideError('NOT-A-WORK-ORDER', 'does not represent a valid Work Order');
		assertOverrideError(otherWorkOrder.Id, 'does not represent a valid Work Order');
		assertOverrideError(fixture.deviceWorkOrder.Id, 'does not contain signatures');
	}

	@IsTest
	static void deviceTableAddAndRemoveSignature() {
		OverrideFixture fixture = createFixture('GW5310-DEV');
		insertSignature(fixture.deviceWorkOrder.Id, fixture.repairLine.Id, fixture.otherUser);

		Test.startTest();
		RepairSignatureOverrideService.OverrideWorkspace loaded =
			RepairCoordinatorActionsController.loadSignatureOverride(
				fixture.deviceWorkOrder.WorkOrderNumber
			);
		RepairSignatureOverrideService.OverrideWorkspace added =
			RepairSignatureOverrideService.addSignature(
				fixture.deviceWorkOrder.Id,
				fixture.repairLine.Id,
				UserInfo.getUserId()
			);
		List<RepairSignatureOverrideService.TechnicianOption> technicians =
			RepairSignatureOverrideService.searchTechnicians(
				fixture.deviceWorkOrder.Id,
				UserInfo.getLastName()
			);
		Boolean duplicateRejected = false;
		try {
			RepairSignatureOverrideService.addSignature(
				fixture.deviceWorkOrder.Id,
				fixture.repairLine.Id,
				UserInfo.getUserId()
			);
		} catch (RepairSignatureOverrideService.SignatureOverrideException e) {
			duplicateRejected = e.getMessage().contains('already signed');
		}
		RepairSignatureOverrideService.removeSignature(
			fixture.deviceWorkOrder.Id,
			added.rows[0].signatures[0].id
		);
		Test.stopTest();

		Assert.areEqual('device', loaded.tableLayout);
		Assert.areEqual(fixture.deviceWorkOrder.WorkOrderNumber, loaded.workOrderNumber);
		Assert.areEqual(1, loaded.rows.size());
		Assert.areEqual('Leak Test', loaded.rows[0].category);
		Assert.areEqual('SC.GW5310-DEV', loaded.rows[0].itemNumber);
		Assert.areEqual('Minor fluid removed', loaded.rows[0].description);
		Assert.areEqual(fixture.otherUser.Name, loaded.rows[0].signatures[0].userName);

		Assert.areEqual(2, added.rows[0].signatures.size());
		RepairCenterTeamMember__c created = [
			SELECT
				Name,
				Person__c,
				WorkOrder__c,
				ParentWorkOrder__c,
				WorkOrderLineItem__c,
				Type__c,
				RecordType.DeveloperName
			FROM RepairCenterTeamMember__c
			WHERE WorkOrder__c = :fixture.deviceWorkOrder.Id AND Person__c = :UserInfo.getUserId()
		];
		Assert.areEqual(UserInfo.getName().left(80), created.Name);
		Assert.areEqual(fixture.deviceWorkOrder.Id, created.WorkOrder__c);
		Assert.areEqual(fixture.repairLine.Id, created.WorkOrderLineItem__c);
		Assert.areEqual('Work Order Line', created.Type__c);
		Assert.areEqual('RepairCenter', created.RecordType.DeveloperName);
		Assert.isNull(created.ParentWorkOrder__c);
		Assert.areEqual(
			UserInfo.getUserId(),
			[SELECT AssignedResourceUser__c FROM WorkOrderLineItem WHERE Id = :fixture.repairLine.Id]
			.AssignedResourceUser__c
		);
		Assert.isTrue(containsUser(technicians, UserInfo.getUserId()));
		Assert.isFalse(containsUser(technicians, fixture.outsideUser.Id));
		Assert.isTrue(duplicateRejected, 'A second signature for the same technician should be rejected.');
	}

	@IsTest
	static void instrumentTableUsesParentItemAndRejectsTechnicianOutsideCenter() {
		OverrideFixture fixture = createFixture('GW5310-INS');
		insertSignature(fixture.instrumentWorkOrder.Id, fixture.instrumentRepairLine.Id, fixture.otherUser);

		Test.startTest();
		RepairSignatureOverrideService.OverrideWorkspace loaded =
			RepairSignatureOverrideService.loadWorkPerformed(fixture.instrumentWorkOrder.Id);
		Boolean rejected = false;
		try {
			RepairSignatureOverrideService.addSignature(
				fixture.instrumentWorkOrder.Id,
				fixture.instrumentRepairLine.Id,
				fixture.outsideUser.Id
			);
		} catch (RepairSignatureOverrideService.SignatureOverrideException e) {
			rejected = e.getMessage().contains('Repair Center');
		}
		Boolean removedLast = false;
		try {
			RepairSignatureOverrideService.removeSignature(
				fixture.instrumentWorkOrder.Id,
				loaded.rows[0].signatures[0].id
			);
		} catch (RepairSignatureOverrideService.SignatureOverrideException e) {
			removedLast = e.getMessage().contains('does not contain signatures');
		}
		Test.stopTest();

		Assert.areEqual('instrument', loaded.tableLayout);
		Assert.areEqual('IN.GW5310-INS', loaded.rows[0].itemNumber);
		Assert.areEqual('Arm Board', loaded.rows[0].productName);
		Assert.areEqual('2', loaded.rows[0].quantity);
		Assert.areEqual('Color coded', loaded.rows[0].repairDescription);
		Assert.areEqual('Waiting for Approval', loaded.rows[0].status);
		Assert.isTrue(rejected);
		Assert.isTrue(removedLast);
		Assert.areEqual(
			0,
			RepairCenterTeamMembersSelector.countByWorkOrderId(fixture.instrumentWorkOrder.Id)
		);
	}

	@IsTest
	static void workPerformedOmitsObservationCodes() {
		OverrideFixture fixture = createFixture('GW5310-TYPE');
		insertSignature(fixture.deviceWorkOrder.Id, fixture.repairLine.Id, fixture.otherUser);
		Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
		insertRepairCodeLine(
			fixture.deviceWorkOrder.Id,
			repairCodeRtId,
			'SP.GW5310-TYPE',
			'Special Pricing',
			'Special rate',
			'Pricing'
		);
		insertRepairCodeLine(
			fixture.deviceWorkOrder.Id,
			repairCodeRtId,
			'SV.GW5310-TYPE',
			'Service Code',
			'Service performed',
			'Angulation'
		);
		insertRepairCodeLine(
			fixture.deviceWorkOrder.Id,
			repairCodeRtId,
			'OC.GW5310-TYPE',
			'Observation Code',
			'Angulation out of Spec',
			'Angulation'
		);

		Test.startTest();
		RepairSignatureOverrideService.OverrideWorkspace loaded =
			RepairSignatureOverrideService.loadWorkPerformed(fixture.deviceWorkOrder.Id);
		Test.stopTest();

		Set<String> itemNumbers = new Set<String>();
		for (RepairSignatureOverrideService.WorkPerformedRow row : loaded.rows) {
			itemNumbers.add(row.itemNumber);
		}
		Assert.areEqual(3, loaded.rows.size());
		Assert.isTrue(itemNumbers.contains('SC.GW5310-TYPE'));
		Assert.isTrue(itemNumbers.contains('SP.GW5310-TYPE'));
		Assert.isTrue(itemNumbers.contains('SV.GW5310-TYPE'));
		Assert.isFalse(itemNumbers.contains('OC.GW5310-TYPE'));
	}

	private static void insertRepairCodeLine(
		Id workOrderId,
		Id repairCodeRtId,
		String productCode,
		String lineType,
		String description,
		String category
	) {
		Product2 product = new Product2(
			Name = description,
			ProductCode = productCode,
			Description = description,
			EvalCategory__c = category,
			ProductType__c = lineType,
			IsActive = true
		);
		insert product;
		PricebookEntry entry = new PricebookEntry(
			Pricebook2Id = Test.getStandardPricebookId(),
			Product2Id = product.Id,
			UnitPrice = 1,
			IsActive = true
		);
		insert entry;
		WorkOrderLineItem lineItem = new WorkOrderLineItem(
			WorkOrderId = workOrderId,
			RecordTypeId = repairCodeRtId,
			PricebookEntryId = entry.Id,
			Quantity = 1,
			Status = 'Approved',
			LineType__c = lineType
		);
		lineItem.put('Product__c', product.Id);
		insert lineItem;
	}

	private static void assertOverrideError(String scanValue, String expectedFragment) {
		Boolean threw = false;
		try {
			RepairSignatureOverrideService.loadWorkPerformed(scanValue);
		} catch (RepairSignatureOverrideService.SignatureOverrideException e) {
			threw = e.getMessage().contains(expectedFragment);
		}
		Assert.isTrue(threw, 'Expected error containing ' + expectedFragment);
	}

	private static Boolean containsUser(
		List<RepairSignatureOverrideService.TechnicianOption> options,
		Id userId
	) {
		for (RepairSignatureOverrideService.TechnicianOption option : options) {
			if (option.userId == userId) {
				return true;
			}
		}
		return false;
	}

	private static void insertSignature(Id workOrderId, Id lineItemId, User person) {
		RepairCenterTeamMember__c signature = new RepairCenterTeamMember__c(
			Name = person.Name.left(80),
			Person__c = person.Id,
			WorkOrder__c = workOrderId,
			WorkOrderLineItem__c = lineItemId,
			Type__c = 'Work Order Line',
			RecordTypeId = recordTypeId(RepairCenterTeamMember__c.SObjectType, 'RepairCenter')
		);
		insert signature;
	}

	private static Id recordTypeId(Schema.SObjectType objectType, String developerName) {
		Id recordTypeId = objectType.getDescribe()
			.getRecordTypeInfosByDeveloperName()
			.get(developerName)
			?.getRecordTypeId();
		Assert.isNotNull(recordTypeId, developerName + ' record type is required.');
		return recordTypeId;
	}

	private class OverrideFixture {
		Account customer;
		Schema.Location repairCenter;
		Schema.Location otherCenter;
		User otherUser;
		User outsideUser;
		WorkOrder deviceWorkOrder;
		WorkOrder instrumentWorkOrder;
		WorkOrderLineItem repairLine;
		WorkOrderLineItem instrumentRepairLine;
	}

	private static OverrideFixture createFixture(String key) {
		List<User> users = [
			SELECT Id, Name
			FROM User
			WHERE IsActive = TRUE AND Id != :UserInfo.getUserId() AND UserType = 'Standard'
			ORDER BY LastName
			LIMIT 2
		];
		Assert.isTrue(users.size() == 2, 'Two other standard users are required.');

		OverrideFixture fixture = new OverrideFixture();
		fixture.otherUser = users[0];
		fixture.outsideUser = users[1];
		fixture.customer = new Account(
			Name = key + ' Customer',
			SystemID__c = key.left(15),
			SourceSystemID__c = key,
			OrgIDs__c = '82'
		);
		insert fixture.customer;

		fixture.repairCenter = new Schema.Location(
			Name = key + ' Repair Center',
			LocationType = 'Repair Center'
		);
		fixture.otherCenter = new Schema.Location(
			Name = key + ' Other Center',
			LocationType = 'Repair Center'
		);
		insert new List<Schema.Location>{ fixture.repairCenter, fixture.otherCenter };

		insertServiceResource(UserInfo.getUserId(), fixture.repairCenter.Id, key + ' Current');
		insertServiceResource(fixture.outsideUser.Id, fixture.otherCenter.Id, key + ' Outside');

		Id devicesRtId = recordTypeId(WorkOrder.SObjectType, 'RepairCenterDevices');
		Id instrumentsRtId = recordTypeId(WorkOrder.SObjectType, 'RepairCenterInstruments');
		fixture.deviceWorkOrder = new WorkOrder(
			Subject = key + ' Device',
			Status = 'Repair',
			AccountId = fixture.customer.Id,
			RecordTypeId = devicesRtId,
			RepairCenter__c = fixture.repairCenter.Id,
			Pricebook2Id = Test.getStandardPricebookId()
		);
		fixture.instrumentWorkOrder = new WorkOrder(
			Subject = key + ' Instrument',
			Status = 'Repair',
			AccountId = fixture.customer.Id,
			RecordTypeId = instrumentsRtId,
			RepairCenter__c = fixture.repairCenter.Id,
			Pricebook2Id = Test.getStandardPricebookId()
		);
		insert new List<WorkOrder>{ fixture.deviceWorkOrder, fixture.instrumentWorkOrder };
		fixture.deviceWorkOrder = [
			SELECT Id, WorkOrderNumber
			FROM WorkOrder
			WHERE Id = :fixture.deviceWorkOrder.Id
		];

		Product2 repairProduct = new Product2(
			Name = 'Color coded',
			ProductCode = 'SC.' + key,
			Description = 'Minor fluid removed',
			EvalCategory__c = 'Leak Test',
			ProductType__c = 'Category Code',
			IsActive = true
		);
		Product2 instrumentProduct = new Product2(
			Name = 'Arm Board',
			ProductCode = 'IN.' + key,
			ProductType__c = 'Category Code',
			IsActive = true
		);
		insert new List<Product2>{ repairProduct, instrumentProduct };
		PricebookEntry repairEntry = new PricebookEntry(
			Pricebook2Id = Test.getStandardPricebookId(),
			Product2Id = repairProduct.Id,
			UnitPrice = 1,
			IsActive = true
		);
		PricebookEntry instrumentEntry = new PricebookEntry(
			Pricebook2Id = Test.getStandardPricebookId(),
			Product2Id = instrumentProduct.Id,
			UnitPrice = 1,
			IsActive = true
		);
		insert new List<PricebookEntry>{ repairEntry, instrumentEntry };

		Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
		Id productServicedRtId = recordTypeId(WorkOrderLineItem.SObjectType, 'ProductServiced');
		Assert.isNotNull(repairCodeRtId, 'Repair Code record type is required.');

		fixture.repairLine = new WorkOrderLineItem(
			WorkOrderId = fixture.deviceWorkOrder.Id,
			RecordTypeId = repairCodeRtId,
			PricebookEntryId = repairEntry.Id,
			Quantity = 1,
			Status = 'Approved',
			LineType__c = 'Category Code'
		);
		fixture.repairLine.put('Product__c', repairProduct.Id);

		WorkOrderLineItem parentLine = new WorkOrderLineItem(
			WorkOrderId = fixture.instrumentWorkOrder.Id,
			RecordTypeId = productServicedRtId,
			PricebookEntryId = instrumentEntry.Id,
			Quantity = 2,
			Status = 'Approved'
		);
		parentLine.put('Product__c', instrumentProduct.Id);
		insert new List<WorkOrderLineItem>{ fixture.repairLine, parentLine };

		fixture.instrumentRepairLine = new WorkOrderLineItem(
			WorkOrderId = fixture.instrumentWorkOrder.Id,
			RecordTypeId = repairCodeRtId,
			ParentWorkOrderLineItemId = parentLine.Id,
			PricebookEntryId = repairEntry.Id,
			Quantity = 1,
			Status = 'Waiting for Approval',
			LineType__c = 'Category Code'
		);
		fixture.instrumentRepairLine.put('Product__c', repairProduct.Id);
		insert fixture.instrumentRepairLine;
		return fixture;
	}

	private static void insertServiceResource(Id userId, Id repairCenterId, String name) {
		List<ServiceResource> existing = ServiceResourcesSelector.selectActiveByRelatedRecordIds(
			new Set<Id>{ userId }
		);
		if (!existing.isEmpty()) {
			ServiceResource resource = existing[0];
			resource.IsActive = true;
			resource.put('RepairCenter__c', repairCenterId);
			update resource;
			return;
		}
		Schema.Location resourceLocation = new Schema.Location(
			Name = name + ' Location',
			LocationType = 'Repair Center',
			IsInventoryLocation = true,
			IsMobile = true
		);
		insert resourceLocation;
		ServiceResource resource = new ServiceResource(
			Name = name,
			RelatedRecordId = userId,
			LocationId = resourceLocation.Id,
			IsActive = true,
			ResourceType = 'T'
		);
		insert resource;
		resource.put('RepairCenter__c', repairCenterId);
		update resource;
	}
}