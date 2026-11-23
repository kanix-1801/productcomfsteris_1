/**
 * @description GW-5310 - Current Device and Instrument Repair Center Work Orders
 *              for the coordinator status screen.
 */
public with sharing class CurrentWorkOrderStatusController {
	private static final Set<String> RECORD_TYPES = new Set<String>{
		'RepairCenterDevices',
		'RepairCenterInstruments'
	};

	/**
	 * Completed stays open on IsClosed in Field Service, so it is excluded here
	 * along with Canceled and Closed.
	 */
	private static final Set<String> CLOSED_STATUSES = new Set<String>{
		'Completed',
		'Canceled',
		'Closed'
	};

	private static final Integer ROW_LIMIT = 2000;

	/**
	 * @description GW-5310 - Open Repair Center Device and Instrument Work Orders.
	 * @return Current Work Orders with number, status, and record type
	 */
	@AuraEnabled
	public static List<WorkOrder> getCurrentWorkOrderSummaries() {
		return [
			SELECT Id, WorkOrderNumber, Status, RecordType.DeveloperName, RecordType.Name
			FROM WorkOrder
			WHERE RecordType.DeveloperName IN :RECORD_TYPES AND Status NOT IN :CLOSED_STATUSES
			WITH USER_MODE
			ORDER BY RecordType.DeveloperName, WorkOrderNumber
			LIMIT :ROW_LIMIT
		];
	}
}