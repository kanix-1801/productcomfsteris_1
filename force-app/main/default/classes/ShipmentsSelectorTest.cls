/**
 * @author Sagar Anand
 * @date 2026-11-05
 * @group Shipment Tracking
 * @description GW-6358 - Tests for ShipmentsSelector.
 * @see ShipmentsSelector
 */
@IsTest
private class ShipmentsSelectorTest {
	/**
	 * @description Shipments of a Return Order are returned oldest first; null or empty input returns none.
	 */
	@IsTest
	static void testSelectByReturnOrderIds() {
		Account vendor = new Account(
			Name = 'GW6358 Selector Vendor',
			SystemID__c = 'LEG-GW6358-SEL',
			SourceSystemID__c = 'TEST-ORACLE-GW6358-SEL',
			OrgIDs__c = '82'
		);
		Database.insert(vendor, AccessLevel.SYSTEM_MODE);
		Schema.Location repairCenter = new Schema.Location(Name = 'GW6358 Selector RC', LocationType = 'Repair Center');
		Database.insert(repairCenter, AccessLevel.SYSTEM_MODE);
		ReturnOrder returnOrderRecord = new ReturnOrder(
			AccountId = vendor.Id,
			Status = 'Submitted',
			DestinationLocationId = repairCenter.Id,
			OperatingUnit__c = '82',
			ReturnOrderType__c = 'Serialized'
		);
		Database.insert(returnOrderRecord, AccessLevel.SYSTEM_MODE);
		Shipment firstShipment = new Shipment(ReturnOrderId = returnOrderRecord.Id, ShipToName = 'STERIS', TrackingNumber = 'FIRST');
		Database.insert(firstShipment, AccessLevel.SYSTEM_MODE);
		Shipment secondShipment = new Shipment(ReturnOrderId = returnOrderRecord.Id, ShipToName = 'STERIS', TrackingNumber = 'SECOND');
		Database.insert(secondShipment, AccessLevel.SYSTEM_MODE);

		Test.startTest();
		List<Shipment> shipments = ShipmentsSelector.selectByReturnOrderIds(new Set<Id>{ returnOrderRecord.Id });
		List<Shipment> nullInput = ShipmentsSelector.selectByReturnOrderIds(null);
		List<Shipment> emptyInput = ShipmentsSelector.selectByReturnOrderIds(new Set<Id>());
		Test.stopTest();

		Assert.areEqual(2, shipments.size(), 'Both shipments should be returned');
		Assert.areEqual('FIRST', shipments[0].TrackingNumber, 'Oldest shipment first');
		Assert.areEqual(returnOrderRecord.Id, shipments[0].ReturnOrderId, 'Return Order Id should be selected');
		Assert.isTrue(nullInput.isEmpty(), 'Null input');
		Assert.isTrue(emptyInput.isEmpty(), 'Empty input');
	}
}