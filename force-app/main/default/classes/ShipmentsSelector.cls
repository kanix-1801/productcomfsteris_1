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
}