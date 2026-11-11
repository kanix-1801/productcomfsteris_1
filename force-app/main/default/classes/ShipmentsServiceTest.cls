/**
 * @author Sagar Anand
 * @date 2026-11-05
 * @group Shipment Tracking
 * @description GW-6358 - Tests for ShipmentsService and the flow Shipment - After Save - Map Fedex Status.
 * @see ShipmentsService
 */
@IsTest
private class ShipmentsServiceTest {
	private static final String TRACKING_NUMBER = '794900006358';

	@TestSetup
	static void setupData() {
		// Shipment and Work Order Shipment access for the user-mode DML in ShipmentsService
		assignPermissionSetIfNeeded('ProcessReturnOrders');
		assignPermissionSetIfNeeded('ManageWorkOrders');
		System.runAs(new User(Id = UserInfo.getUserId())) {
			createTestData();
		}
	}

	private static void createTestData() {
		Account vendor = new Account(
			Name = 'GW6358 Shipment Vendor',
			SystemID__c = 'LEG-GW6358-V',
			SourceSystemID__c = 'TEST-ORACLE-GW6358-V',
			OrgIDs__c = '82'
		);
		Database.insert(vendor, AccessLevel.SYSTEM_MODE);

		Schema.Location repairCenter = new Schema.Location(Name = 'GW6358 RC', LocationType = 'Repair Center');
		Database.insert(repairCenter, AccessLevel.SYSTEM_MODE);

		ReturnOrder returnOrderRecord = new ReturnOrder(
			AccountId = vendor.Id,
			Status = 'Submitted',
			DestinationLocationId = repairCenter.Id,
			OperatingUnit__c = '82',
			ReturnOrderType__c = 'Serialized'
		);
		Database.insert(returnOrderRecord, AccessLevel.SYSTEM_MODE);

		WorkOrder parentWorkOrder = new WorkOrder(
			Subject = 'GW6358 Parent WO',
			Status = 'Received',
			AccountId = vendor.Id,
			Pricebook2Id = Test.getStandardPricebookId()
		);
		Database.insert(parentWorkOrder, AccessLevel.SYSTEM_MODE);

		Id otherRecordTypeId = getWorkOrderRecordTypeId('RepairCenterOther');
		Id vendorRecordTypeId = getWorkOrderRecordTypeId('RepairCenterVendor');
		List<WorkOrder> childWorkOrders = new List<WorkOrder>{
			new WorkOrder(
				Subject = 'GW6358 Child WO',
				Status = 'Received',
				AccountId = vendor.Id,
				RecordTypeId = otherRecordTypeId,
				ParentWorkOrderId = parentWorkOrder.Id,
				Pricebook2Id = Test.getStandardPricebookId()
			),
			new WorkOrder(
				Subject = 'GW6358 Vendor WO',
				Status = 'Received',
				AccountId = vendor.Id,
				RecordTypeId = vendorRecordTypeId != null ? vendorRecordTypeId : otherRecordTypeId,
				ParentWorkOrderId = parentWorkOrder.Id,
				Pricebook2Id = Test.getStandardPricebookId()
			)
		};
		Database.insert(childWorkOrders, AccessLevel.SYSTEM_MODE);
	}

	/**
	 * @description A FedEx Shipment is built with the Created status, FedEx carrier and tracking URL.
	 */
	@IsTest
	static void testBuildFedExShipment() {
		ReturnOrder returnOrderRecord = getReturnOrder();
		WorkOrder parentWorkOrder = getParentWorkOrder();

		Test.startTest();
		Shipment shipment = ShipmentsService.buildFedExShipment(
			returnOrderRecord.Id,
			parentWorkOrder.Id,
			TRACKING_NUMBER,
			'Vendor Name'
		);
		Shipment noTracking = ShipmentsService.buildFedExShipment(returnOrderRecord.Id, null, null, null);
		Test.stopTest();

		Assert.areEqual(returnOrderRecord.Id, shipment.ReturnOrderId, 'Return Order');
		Assert.areEqual(parentWorkOrder.Id, shipment.WorkOrder__c, 'Parent Work Order');
		Assert.areEqual(ShipmentsService.STATUS_CREATED, shipment.Status, 'Status');
		Assert.areEqual(ShipmentsService.CARRIER_FEDEX, shipment.Carrier__c, 'Carrier');
		Assert.areEqual(TRACKING_NUMBER, shipment.TrackingNumber, 'Tracking Number');
		Assert.areEqual(ShipmentsService.FEDEX_TRACKING_URL + TRACKING_NUMBER, shipment.TrackingUrl, 'Tracking URL');
		Assert.areEqual('Vendor Name', shipment.ShipToName, 'Ship To Name');
		Assert.isNull(noTracking.TrackingUrl, 'No URL without a tracking number');
		Assert.areEqual(ShipmentsService.DEFAULT_SHIP_TO_NAME, noTracking.ShipToName, 'Default Ship To Name');
	}

	/**
	 * @description Shipments are created, Work Orders are linked, and the first tracking number is returned.
	 */
	@IsTest
	static void testCreateLinkAndInitialTrackingNumber() {
		ReturnOrder returnOrderRecord = getReturnOrder();
		List<WorkOrder> childWorkOrders = getChildWorkOrders();

		Test.startTest();
		Shipment firstShipment = ShipmentsService.buildFedExShipment(returnOrderRecord.Id, null, TRACKING_NUMBER, null);
		ShipmentsService.createShipments(new List<Shipment>{ firstShipment });
		ShipmentsService.createShipments(
			new List<Shipment>{ ShipmentsService.buildFedExShipment(returnOrderRecord.Id, null, 'LATER', null) }
		);
		Map<Id, Id> shipmentIdByWorkOrderIdMap = new Map<Id, Id>();
		for (WorkOrder workOrderRecord : childWorkOrders) {
			shipmentIdByWorkOrderIdMap.put(workOrderRecord.Id, firstShipment.Id);
		}
		ShipmentsService.linkWorkOrdersToShipments(shipmentIdByWorkOrderIdMap);
		Map<Id, String> trackingNumberByReturnOrderIdMap = ShipmentsService.getInitialTrackingNumberByReturnOrderId(
			new Set<Id>{ returnOrderRecord.Id }
		);
		Test.stopTest();

		Assert.areEqual(TRACKING_NUMBER, trackingNumberByReturnOrderIdMap.get(returnOrderRecord.Id), 'First shipment');
		for (WorkOrder workOrderRecord : [SELECT Shipment__c FROM WorkOrder WHERE Id IN :shipmentIdByWorkOrderIdMap.keySet()]) {
			Assert.areEqual(firstShipment.Id, workOrderRecord.Shipment__c, 'Work Order should look up to the shipment');
		}
		Assert.isTrue(ShipmentsService.getInitialTrackingNumberByReturnOrderId(null).isEmpty(), 'Null input');
	}

	/**
	 * @description Empty input does nothing; failed DML is returned as ShipmentsServiceException.
	 */
	@IsTest
	static void testEmptyInputAndFailures() {
		String createMessage;
		String linkMessage;

		Test.startTest();
		ShipmentsService.createShipments(null);
		ShipmentsService.createShipments(new List<Shipment>());
		ShipmentsService.linkWorkOrdersToShipments(null);
		ShipmentsService.linkWorkOrdersToShipments(new Map<Id, Id>());
		try {
			// ShipToName is required
			ShipmentsService.createShipments(new List<Shipment>{ new Shipment(TrackingNumber = TRACKING_NUMBER) });
		} catch (ShipmentsService.ShipmentsServiceException e) {
			createMessage = e.getMessage();
		}
		try {
			Id missingWorkOrderId = WorkOrder.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
			ShipmentsService.linkWorkOrdersToShipments(new Map<Id, Id>{ missingWorkOrderId => null });
		} catch (ShipmentsService.ShipmentsServiceException e) {
			linkMessage = e.getMessage();
		}
		Test.stopTest();

		Assert.isTrue(createMessage.startsWith('Unable to create the shipment records.'), 'Create failure: ' + createMessage);
		Assert.isTrue(linkMessage.startsWith('Unable to link the Work Orders'), 'Link failure: ' + linkMessage);
		Assert.areEqual(0, [SELECT COUNT() FROM Shipment], 'No shipment should be created');
	}

	/**
	 * @description Flow: a new Created shipment changes nothing; Label_created sets the Return Order to
	 *              Created and the Work Orders to Ship (Ship to Vendor for vendor Work Orders).
	 */
	@IsTest
	static void testFlowMapsLabelCreatedStatus() {
		ReturnOrder returnOrderRecord = getReturnOrder();
		Shipment shipment = createLinkedShipment(returnOrderRecord.Id);
		Assert.areEqual('Submitted', getReturnOrder().Status, 'Created has no mapping, so nothing changes');

		Test.startTest();
		shipment.Status = 'Label_created';
		Database.update(shipment, AccessLevel.SYSTEM_MODE);
		Test.stopTest();

		Assert.areEqual('Created', getReturnOrder().Status, 'Return Order Status');
		Id vendorRecordTypeId = getWorkOrderRecordTypeId('RepairCenterVendor');
		for (WorkOrder workOrderRecord : getChildWorkOrders()) {
			String expectedStatus = vendorRecordTypeId != null && workOrderRecord.RecordTypeId == vendorRecordTypeId
				? 'Ship to Vendor'
				: 'Ship';
			Assert.areEqual(expectedStatus, workOrderRecord.Status, 'Work Order Status for ' + workOrderRecord.Subject);
		}
	}

	/**
	 * @description Flow: Label_expired cancels the Return Order with the FedEx cancel reason and cancels
	 *              the Work Orders.
	 */
	@IsTest
	static void testFlowMapsLabelExpiredStatus() {
		ReturnOrder returnOrderRecord = getReturnOrder();
		Shipment shipment = createLinkedShipment(returnOrderRecord.Id);

		Test.startTest();
		shipment.Status = 'Label_expired';
		Database.update(shipment, AccessLevel.SYSTEM_MODE);
		Test.stopTest();

		ReturnOrder refreshed = getReturnOrder();
		Assert.areEqual('Canceled', refreshed.Status, 'Return Order Status');
		Assert.areEqual('Fedex Label Expired', refreshed.CancelReason__c, 'Cancel Reason');
		for (WorkOrder workOrderRecord : getChildWorkOrders()) {
			Assert.areEqual('Canceled', workOrderRecord.Status, 'Work Order Status for ' + workOrderRecord.Subject);
		}
	}

	private static Shipment createLinkedShipment(Id returnOrderId) {
		Shipment shipment = ShipmentsService.buildFedExShipment(returnOrderId, getParentWorkOrder().Id, TRACKING_NUMBER, null);
		Database.insert(shipment, AccessLevel.SYSTEM_MODE);
		List<WorkOrder> childWorkOrders = getChildWorkOrders();
		for (WorkOrder workOrderRecord : childWorkOrders) {
			workOrderRecord.Shipment__c = shipment.Id;
		}
		Database.update(childWorkOrders, AccessLevel.SYSTEM_MODE);
		return shipment;
	}

	private static ReturnOrder getReturnOrder() {
		return [SELECT Id, Status, CancelReason__c FROM ReturnOrder LIMIT 1];
	}

	private static WorkOrder getParentWorkOrder() {
		return [SELECT Id FROM WorkOrder WHERE Subject = 'GW6358 Parent WO' LIMIT 1];
	}

	private static List<WorkOrder> getChildWorkOrders() {
		return [SELECT Id, Subject, Status, RecordTypeId FROM WorkOrder WHERE ParentWorkOrderId != null ORDER BY Subject];
	}

	private static void assignPermissionSetIfNeeded(String permissionSetName) {
		List<PermissionSet> permissionSets = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1];
		if (permissionSets.isEmpty()) {
			return;
		}
		List<PermissionSetAssignment> existingAssignments = [
			SELECT Id
			FROM PermissionSetAssignment
			WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :permissionSets[0].Id
			LIMIT 1
		];
		if (existingAssignments.isEmpty()) {
			new adb_PermissionSetAssignment()
				.assigneeId(UserInfo.getUserId())
				.permissionSetId(permissionSets[0].Id)
				.persist();
		}
	}

	private static Id getWorkOrderRecordTypeId(String developerName) {
		Schema.RecordTypeInfo info = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName().get(developerName);
		return info == null ? null : info.getRecordTypeId();
	}
}