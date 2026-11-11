/**
 * @author Sagar Anand
 * @date 2026-11-05
 * @group Shipment Tracking
 * @description GW-6358 - Service for carrier shipments (Shipment) of Return Orders and Work Orders.
 *              Tracking details are kept on Shipment records instead of fields on the Return Order
 *              and Work Order. Status updates from the carrier are mapped to the Return Order and
 *              Work Orders by the flow Shipment - After Save - Map Fedex Status.
 * @see ShipmentsSelector
 */
public with sharing class ShipmentsService {
	/** @description Status of a new Shipment, before the carrier reports a status. */
	@TestVisible
	private static final String STATUS_CREATED = 'Created';
	/** @description Carrier picklist value for FedEx shipments. */
	@TestVisible
	private static final String CARRIER_FEDEX = 'FedEx';
	/** @description FedEx tracking page; the tracking number is appended. */
	@TestVisible
	private static final String FEDEX_TRACKING_URL = 'https://www.fedex.com/fedextrack/?trknbr=';
	/** @description Shipment.ShipToName is required; used when no ship-to name is known. */
	@TestVisible
	private static final String DEFAULT_SHIP_TO_NAME = 'STERIS';
	private static final String LOG_SCENARIO = 'Shipment Tracking';

	/**
	 * @description GW-6358 - Builds a new FedEx Shipment (not inserted).
	 * @param returnOrderId Return Order the shipment belongs to
	 * @param parentWorkOrderId Parent Work Order of the Work Orders in the shipment; null when not known
	 * @param trackingNumber FedEx tracking number
	 * @param shipToName Name of the receiver; STERIS when blank
	 * @return Shipment with Status Created, Carrier FedEx and the FedEx tracking URL
	 * @example
	 * Shipment shipment = ShipmentsService.buildFedExShipment(returnOrderId, null, trackingNumber, 'STERIS');
	 */
	public static Shipment buildFedExShipment(
		Id returnOrderId,
		Id parentWorkOrderId,
		String trackingNumber,
		String shipToName
	) {
		Shipment shipment = new Shipment();
		shipment.ReturnOrderId = returnOrderId;
		shipment.WorkOrder__c = parentWorkOrderId;
		shipment.Status = STATUS_CREATED;
		shipment.Carrier__c = CARRIER_FEDEX;
		shipment.TrackingNumber = trackingNumber;
		shipment.TrackingUrl = String.isBlank(trackingNumber) ? null : FEDEX_TRACKING_URL + trackingNumber;
		shipment.ShipToName = String.isBlank(shipToName) ? DEFAULT_SHIP_TO_NAME : shipToName.left(255);
		return shipment;
	}

	/**
	 * @description GW-6358 - Inserts Shipments.
	 * @param shipmentList Shipments to insert
	 * @throws ShipmentsServiceException when the insert fails
	 * @example
	 * ShipmentsService.createShipments(new List<Shipment>{ shipment });
	 */
	public static void createShipments(List<Shipment> shipmentList) {
		if (shipmentList == null || shipmentList.isEmpty()) {
			return;
		}
		try {
			insert shipmentList;
		} catch (Exception e) {
			Logger.setScenario(LOG_SCENARIO);
			Logger.error(
					new LogMessage('ShipmentsService.createShipments failed for {0} shipments: {1}', shipmentList.size(), e.getMessage()),
					e
				)
				.addTag('Shipment');
			throw new ShipmentsServiceException('Unable to create the shipment records. ' + e.getMessage(), e);
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description GW-6358 - Links Work Orders to the Shipment they were shipped in (Shipment__c).
	 * @param shipmentIdByWorkOrderIdMap Shipment Id by Work Order Id
	 * @throws ShipmentsServiceException when the update fails
	 * @example
	 * ShipmentsService.linkWorkOrdersToShipments(new Map<Id, Id>{ workOrderId => shipmentId });
	 */
	public static void linkWorkOrdersToShipments(Map<Id, Id> shipmentIdByWorkOrderIdMap) {
		if (shipmentIdByWorkOrderIdMap == null || shipmentIdByWorkOrderIdMap.isEmpty()) {
			return;
		}
		List<WorkOrder> workOrderList = new List<WorkOrder>();
		for (Id workOrderId : shipmentIdByWorkOrderIdMap.keySet()) {
			workOrderList.add(new WorkOrder(Id = workOrderId, Shipment__c = shipmentIdByWorkOrderIdMap.get(workOrderId)));
		}
		try {
			update workOrderList;
		} catch (Exception e) {
			Logger.setScenario(LOG_SCENARIO);
			Logger.error(
					new LogMessage('ShipmentsService.linkWorkOrdersToShipments failed for {0} Work Orders: {1}', workOrderList.size(), e.getMessage()),
					e
				)
				.addTag('Shipment')
				.addTag('WorkOrder');
			throw new ShipmentsServiceException('Unable to link the Work Orders to their shipment. ' + e.getMessage(), e);
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description GW-6358 - Tracking number of the first (initial) Shipment of each Return Order.
	 * @param returnOrderIdSet Return Order Ids
	 * @return Tracking number by Return Order Id; Return Orders without a shipment are not in the map
	 * @example
	 * Map<Id, String> trackingNumberByReturnOrderIdMap =
	 *     ShipmentsService.getInitialTrackingNumberByReturnOrderId(new Set<Id>{ vendorReturnOrderId });
	 */
	public static Map<Id, String> getInitialTrackingNumberByReturnOrderId(Set<Id> returnOrderIdSet) {
		Map<Id, String> trackingNumberByReturnOrderIdMap = new Map<Id, String>();
		if (returnOrderIdSet == null || returnOrderIdSet.isEmpty()) {
			return trackingNumberByReturnOrderIdMap;
		}
		for (Shipment shipment : ShipmentsSelector.selectByReturnOrderIds(returnOrderIdSet)) {
			if (!trackingNumberByReturnOrderIdMap.containsKey(shipment.ReturnOrderId)) {
				trackingNumberByReturnOrderIdMap.put(shipment.ReturnOrderId, shipment.TrackingNumber);
			}
		}
		return trackingNumberByReturnOrderIdMap;
	}

	/**
	 * @description GW-6358 - Thrown when Shipment records can't be created or linked.
	 */
	public class ShipmentsServiceException extends Exception {
	}
}