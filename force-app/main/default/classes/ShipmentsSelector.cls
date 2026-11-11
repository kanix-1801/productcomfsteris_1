/**
 * @author Sagar Anand
 * @date 2026-11-05
 * @group Shipment Tracking
 * @description GW-6358 - Selector for Shipment, the carrier shipments of Return Orders and Work Orders.
 *              Queries run in USER_MODE through SoqlQueryBuilder.
 * @see ShipmentsService
 */
public with sharing class ShipmentsSelector extends SoqlQueryBuilder {
	/**
	 * @description Creates a selector for the Shipment object.
	 * @example
	 * List<Shipment> shipments = (List<Shipment>) new ShipmentsSelector()
	 *     .selectField('Id')
	 *     .whereEquals('ReturnOrderId', returnOrderId)
	 *     .execute();
	 */
	public ShipmentsSelector() {
		this.objectName = 'Shipment';
	}

	/**
	 * @description GW-6358 - Selects the Shipments of the given Return Orders, oldest first.
	 * @param returnOrderIdSet Return Order Ids
	 * @return Shipments with Id, ReturnOrderId, TrackingNumber and CreatedDate (empty for null or empty input)
	 * @example
	 * List<Shipment> shipments = ShipmentsSelector.selectByReturnOrderIds(new Set<Id>{ returnOrderId });
	 */
	public static List<Shipment> selectByReturnOrderIds(Set<Id> returnOrderIdSet) {
		if (returnOrderIdSet == null || returnOrderIdSet.isEmpty()) {
			return new List<Shipment>();
		}
		List<String> returnOrderIdList = new List<String>();
		for (Id returnOrderId : returnOrderIdSet) {
			returnOrderIdList.add(returnOrderId);
		}
		return (List<Shipment>) new ShipmentsSelector()
			.selectFields(new List<String>{ 'Id', 'ReturnOrderId', 'TrackingNumber', 'CreatedDate' })
			.whereIn('ReturnOrderId', returnOrderIdList)
			.orderBy('CreatedDate', false, true)
			.orderBy('Id', false, true)
			.execute();
	}
}