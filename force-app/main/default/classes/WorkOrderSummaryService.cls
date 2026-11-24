/**
 * @author Uptima
 * @date 2026-11-13
 * @group Repair Center
 * @description GW-5287 process service for View Work Order Summary.
 *              Resolves a scanned Device/Instrument Work Order to its parent hierarchy
 *              and assembles the summary DTO. Queries Selectors / SoqlQueryBuilder directly.
 */
public with sharing class WorkOrderSummaryService {
	private static final String INVALID_INPUT_MESSAGE =
		'The input provided is invalid.  Please provide a valid Id for a Device or Instrument Work Order.';
	private static final String RT_DEVICES = 'RepairCenterDevices';
	private static final String RT_INSTRUMENTS = 'RepairCenterInstruments';
	private static final String TYPE_RACK = 'Rack';
	private static final String TYPE_TECHNICIAN = 'Technician';
	private static final String LINE_TYPE_PRODUCT_SERVICED = 'Product Serviced';

	private static final List<String> RESOLVE_FIELDS = new List<String>{
		'Id',
		'WorkOrderNumber',
		'ParentWorkOrderId',
		'RecordType.DeveloperName'
	};

	private static final List<String> PARENT_FIELDS = new List<String>{
		'Id',
		'WorkOrderNumber',
		'QuantityReceived__c',
		'ScheduledShipDate__c',
		'ShipComplete__c',
		'IsPriorityRepair__c',
		'ReturnOrderId',
		'ReturnOrder.ReturnOrderNumber',
		'ReturnOrder__c',
		'ReturnOrder__r.ReturnOrderNumber',
		'RecordType.DeveloperName'
	};

	private static final List<String> CHILD_FIELDS = new List<String>{
		'Id',
		'WorkOrderNumber',
		'Status',
		'SubStatus__c',
		'QuantityReceived__c',
		'RepairCategory__c',
		'TurnTime__c',
		'ScheduledShipDate__c',
		'Rack__c',
		'Rack__r.Name',
		'AssetId',
		'Asset.SerialNumber',
		'Asset.ModelCalculated__c',
		'Asset.Product2.ProductCode',
		'Asset.Product2.ProductLine__c',
		'Asset.Product2.SubProductLine__c',
		'Asset.Product2.DeviceType__c'
	};

	private static final List<String> INSTRUMENT_LINE_FIELDS = new List<String>{
		'Id',
		'WorkOrderId',
		'Quantity',
		'Product2.ProductCode',
		'Product2.SubProductLine__c',
		'Product2.DeviceType__c'
	};

	/**
	 * @description GW-5287 - Loads the Work Order Summary for a scanned Id or Number.
	 * @param workOrderInput Work Order Id or WorkOrderNumber
	 * @return Summary workspace DTO
	 */
	public static WorkOrderSummaryWorkspace getSummary(String workOrderInput) {
		Logger.setScenario('Work Order Summary');
		if (String.isBlank(workOrderInput)) {
			throw new WorkOrderSummaryServiceException(INVALID_INPUT_MESSAGE);
		}
		WorkOrder scanned = resolveScannedWorkOrder(workOrderInput.trim());
		if (scanned == null || !isAllowedRecordType(scanned.RecordType?.DeveloperName)) {
			throw new WorkOrderSummaryServiceException(INVALID_INPUT_MESSAGE);
		}

		Id parentId = scanned.ParentWorkOrderId != null ? scanned.ParentWorkOrderId : scanned.Id;
		WorkOrder parent = queryParent(parentId);
		if (parent == null || !isAllowedRecordType(parent.RecordType?.DeveloperName)) {
			throw new WorkOrderSummaryServiceException(INVALID_INPUT_MESSAGE);
		}

		List<WorkOrder> children = queryChildren(parent.Id);
		return buildWorkspace(
			parent,
			children,
			mapOpenAssignments(children),
			mapInstrumentLines(children)
		);
	}

	private static WorkOrder resolveScannedWorkOrder(String workOrderInput) {
		if (PlatformUtilities.isSalesforceId(workOrderInput)) {
			List<WorkOrder> byId = (List<WorkOrder>) new WorkOrdersSelector()
				.selectFields(RESOLVE_FIELDS)
				.whereEquals('Id', workOrderInput)
				.limitTo(1)
				.execute();
			if (!byId.isEmpty()) {
				return byId[0];
			}
		}

		List<WorkOrder> byNumber = (List<WorkOrder>) new WorkOrdersSelector()
			.selectFields(RESOLVE_FIELDS)
			.whereEquals('WorkOrderNumber', workOrderInput)
			.limitTo(5)
			.execute();
		if (byNumber.isEmpty()) {
			return null;
		}
		for (WorkOrder candidate : byNumber) {
			if (isAllowedRecordType(candidate.RecordType?.DeveloperName)) {
				return candidate;
			}
		}
		return byNumber[0];
	}

	private static WorkOrder queryParent(Id parentId) {
		List<WorkOrder> rows = (List<WorkOrder>) new WorkOrdersSelector()
			.selectFields(PARENT_FIELDS)
			.whereEquals('Id', parentId)
			.limitTo(1)
			.execute();
		return rows.isEmpty() ? null : rows[0];
	}

	private static List<WorkOrder> queryChildren(Id parentId) {
		return (List<WorkOrder>) new WorkOrdersSelector()
			.selectFields(CHILD_FIELDS)
			.whereEquals('ParentWorkOrderId', parentId)
			.orderBy('WorkOrderNumber')
			.execute();
	}

	/**
	 * @description GW-5287 - Resolves Current Technician / Current Rack from open WO Assignment
	 *              History (EndDateTime__c null). Open Technician rows populate Current Technician.
	 *              Open Rack rows populate Current Rack and do not set Current Technician. When no
	 *              open history exists for the child, falls back to Work Order Rack__c.
	 * @param children Child Work Orders (must include Rack__c / Rack__r.Name)
	 * @return Map of child Work Order Id to assignment display values
	 */
	private static Map<Id, AssignmentDisplay> mapOpenAssignments(List<WorkOrder> children) {
		Map<Id, AssignmentDisplay> result = new Map<Id, AssignmentDisplay>();
		if (children.isEmpty()) {
			return result;
		}

		Set<Id> workOrderIds = new Set<Id>();
		Set<Id> workOrdersWithOpenHistory = new Set<Id>();
		for (WorkOrder child : children) {
			workOrderIds.add(child.Id);
			result.put(child.Id, new AssignmentDisplay());
		}

		List<WOAssignmentHistory__c> openRows =
			WOAssignmentHistoriesSelector.selectOpenByWorkOrderIds(workOrderIds);

		for (WOAssignmentHistory__c row : openRows) {
			AssignmentDisplay display = result.get(row.WorkOrder__c);
			workOrdersWithOpenHistory.add(row.WorkOrder__c);
			if (TYPE_TECHNICIAN.equals(row.Type__c) && String.isBlank(display.currentTechnician)) {
				display.currentTechnician = row.Technician__r?.Name;
			} else if (TYPE_RACK.equals(row.Type__c) && String.isBlank(display.currentLocation)) {
				display.currentLocation = row.Rack__r?.Name;
			}
		}

		for (WorkOrder child : children) {
			if (workOrdersWithOpenHistory.contains(child.Id) || child.Rack__c == null) {
				continue;
			}
			result.get(child.Id).currentLocation = child.Rack__r?.Name;
		}
		return result;
	}

	private static Map<Id, List<InstrumentLineRow>> mapInstrumentLines(List<WorkOrder> children) {
		Map<Id, List<InstrumentLineRow>> result = new Map<Id, List<InstrumentLineRow>>();
		if (children.isEmpty()) {
			return result;
		}

		List<Id> workOrderIdsWithoutAsset = new List<Id>();
		for (WorkOrder child : children) {
			result.put(child.Id, new List<InstrumentLineRow>());
			if (child.AssetId == null) {
				workOrderIdsWithoutAsset.add(child.Id);
			}
		}
		if (workOrderIdsWithoutAsset.isEmpty()) {
			return result;
		}

		List<WorkOrderLineItem> lines = (List<WorkOrderLineItem>) new WorkOrderLineItemsSelector()
			.selectFields(INSTRUMENT_LINE_FIELDS)
			.whereField('WorkOrderId', 'IN', workOrderIdsWithoutAsset)
			.whereEquals('LineType__c', LINE_TYPE_PRODUCT_SERVICED)
			.whereEquals('IsAccessory__c', false)
			.orderBy('LineItemNumber')
			.execute();

		for (WorkOrderLineItem line : lines) {
			result.get(line.WorkOrderId).add(toInstrumentLineRow(line));
		}
		return result;
	}

	private static InstrumentLineRow toInstrumentLineRow(WorkOrderLineItem line) {
		InstrumentLineRow row = new InstrumentLineRow();
		row.itemNumber = line.Product2?.ProductCode;
		row.subProductLine = line.Product2?.SubProductLine__c;
		row.deviceType = line.Product2?.DeviceType__c;
		row.quantity = line.Quantity;
		return row;
	}

	private static WorkOrderSummaryWorkspace buildWorkspace(
		WorkOrder parent,
		List<WorkOrder> children,
		Map<Id, AssignmentDisplay> assignmentByWorkOrderId,
		Map<Id, List<InstrumentLineRow>> instrumentLinesByWorkOrderId
	) {
		WorkOrderSummaryWorkspace workspace = new WorkOrderSummaryWorkspace();
		workspace.parentWorkOrderId = parent.Id;
		workspace.parentWorkOrderNumber = parent.WorkOrderNumber;
		workspace.parentRecordTypeDeveloperName = parent.RecordType?.DeveloperName;
		workspace.returnOrderNumber = resolveReturnOrderNumber(parent);
		workspace.scheduledShipDate = parent.ScheduledShipDate__c;
		workspace.quantityReceived = parent.QuantityReceived__c;
		workspace.shipComplete = parent.ShipComplete__c == true;
		workspace.priorityRepair = parent.IsPriorityRepair__c == true;
		workspace.statusCounts = buildStatusCounts(children);
		workspace.totalChildWorkOrders = children.size();
		workspace.children = new List<ChildWorkOrderSummary>();

		for (WorkOrder child : children) {
			ChildWorkOrderSummary childSummary = new ChildWorkOrderSummary();
			childSummary.workOrderId = child.Id;
			childSummary.workOrderNumber = child.WorkOrderNumber;
			childSummary.status = child.Status;
			childSummary.subStatus = child.SubStatus__c;
			childSummary.quantityReceived = child.QuantityReceived__c;
			childSummary.repairCategory = child.RepairCategory__c;
			childSummary.turnTime = child.TurnTime__c;
			childSummary.scheduledShipDate = child.ScheduledShipDate__c;

			AssignmentDisplay assignment = assignmentByWorkOrderId.get(child.Id);
			childSummary.currentTechnician = assignment.currentTechnician;
			childSummary.currentLocation = assignment.currentLocation;

			if (child.AssetId != null) {
				childSummary.hasAsset = true;
				childSummary.assetRows = new List<AssetRow>{ buildAssetRow(child) };
			} else {
				childSummary.hasAsset = false;
				childSummary.instrumentRows = instrumentLinesByWorkOrderId.get(child.Id);
			}
			workspace.children.add(childSummary);
		}
		return workspace;
	}

	private static AssetRow buildAssetRow(WorkOrder child) {
		AssetRow row = new AssetRow();
		row.serialNumber = child.Asset?.SerialNumber;
		row.model = child.Asset?.ModelCalculated__c;
		row.itemNumber = child.Asset?.Product2?.ProductCode;
		row.productLine = child.Asset?.Product2?.ProductLine__c;
		row.subProductLine = child.Asset?.Product2?.SubProductLine__c;
		row.deviceType = child.Asset?.Product2?.DeviceType__c;
		return row;
	}

	private static List<StatusCount> buildStatusCounts(List<WorkOrder> children) {
		Map<String, Integer> countsByStatus = new Map<String, Integer>();
		for (WorkOrder child : children) {
			String statusKey = String.isBlank(child.Status) ? 'Unknown' : child.Status;
			Integer currentCount = countsByStatus.containsKey(statusKey)
				? countsByStatus.get(statusKey)
				: 0;
			countsByStatus.put(statusKey, currentCount + 1);
		}

		List<StatusCount> statusCounts = new List<StatusCount>();
		for (String statusKey : countsByStatus.keySet()) {
			StatusCount statusCount = new StatusCount();
			statusCount.status = statusKey;
			statusCount.count = countsByStatus.get(statusKey);
			statusCounts.add(statusCount);
		}
		return statusCounts;
	}

	private static String resolveReturnOrderNumber(WorkOrder parent) {
		if (String.isNotBlank(parent.ReturnOrder?.ReturnOrderNumber)) {
			return parent.ReturnOrder.ReturnOrderNumber;
		}
		if (String.isNotBlank(parent.ReturnOrder__r?.ReturnOrderNumber)) {
			return parent.ReturnOrder__r.ReturnOrderNumber;
		}
		return null;
	}

	private static Boolean isAllowedRecordType(String developerName) {
		return RT_DEVICES.equals(developerName) || RT_INSTRUMENTS.equals(developerName);
	}

	private class AssignmentDisplay {
		public String currentTechnician;
		public String currentLocation;
	}

	/**
	 * @description GW-5287 - Summary workspace returned to the LWC.
	 */
	public class WorkOrderSummaryWorkspace {
		@AuraEnabled public Id parentWorkOrderId;
		@AuraEnabled public String parentWorkOrderNumber;
		@AuraEnabled public String parentRecordTypeDeveloperName;
		@AuraEnabled public String returnOrderNumber;
		@AuraEnabled public Date scheduledShipDate;
		@AuraEnabled public Decimal quantityReceived;
		@AuraEnabled public Boolean shipComplete;
		@AuraEnabled public Boolean priorityRepair;
		@AuraEnabled public Integer totalChildWorkOrders;
		@AuraEnabled public List<StatusCount> statusCounts;
		@AuraEnabled public List<ChildWorkOrderSummary> children;
	}

	/**
	 * @description GW-5287 - Child Work Order section of the summary.
	 */
	public class ChildWorkOrderSummary {
		@AuraEnabled public Id workOrderId;
		@AuraEnabled public String workOrderNumber;
		@AuraEnabled public String status;
		@AuraEnabled public String subStatus;
		@AuraEnabled public Decimal quantityReceived;
		@AuraEnabled public String repairCategory;
		@AuraEnabled public String currentTechnician;
		@AuraEnabled public String currentLocation;
		@AuraEnabled public Decimal turnTime;
		@AuraEnabled public Date scheduledShipDate;
		@AuraEnabled public Boolean hasAsset;
		@AuraEnabled public List<AssetRow> assetRows;
		@AuraEnabled public List<InstrumentLineRow> instrumentRows;
	}

	/**
	 * @description GW-5287 - Pie chart status segment.
	 */
	public class StatusCount {
		@AuraEnabled public String status;
		@AuraEnabled public Integer count;
	}

	/**
	 * @description GW-5287 - Asset Information table row.
	 */
	public class AssetRow {
		@AuraEnabled public String serialNumber;
		@AuraEnabled public String itemNumber;
		@AuraEnabled public String productLine;
		@AuraEnabled public String subProductLine;
		@AuraEnabled public String deviceType;
		@AuraEnabled public String model;
	}

	/**
	 * @description GW-5287 - Instrument Information table row.
	 */
	public class InstrumentLineRow {
		@AuraEnabled public String itemNumber;
		@AuraEnabled public String subProductLine;
		@AuraEnabled public String deviceType;
		@AuraEnabled public Decimal quantity;
	}

	/**
	 * @description GW-5287 - Business exception for Work Order Summary.
	 */
	public class WorkOrderSummaryServiceException extends Exception {
	}
}