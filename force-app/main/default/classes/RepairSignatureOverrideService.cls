/**
 * GW-5310 Repair Coordinator signature override.
 *
 * @description Loads Work Performed rows and adds or removes Repair Center Team Member signatures.
 */
public with sharing class RepairSignatureOverrideService {
	private static final String RECORD_TYPE_DEVICES = 'RepairCenterDevices';
	private static final String RECORD_TYPE_INSTRUMENTS = 'RepairCenterInstruments';
	private static final String LAYOUT_DEVICE = 'device';
	private static final String LAYOUT_INSTRUMENT = 'instrument';
	private static final String INVALID_WORK_ORDER_MESSAGE =
		'The scanned value does not represent a valid Work Order.  Please scan a new ID and try again.';
	private static final String NO_SIGNATURES_MESSAGE =
		'The selected Work Order does not contain signatures for override.';
	private static final String TECHNICIAN_REQUIRED_MESSAGE = 'Technician is required.';
	private static final String TECHNICIAN_NOT_AT_CENTER_MESSAGE =
		'Select a technician assigned to this Work Order\'s Repair Center.';

	/**
	 * @description GW-5310 - Resolves a scanned Work Order and its Work Performed rows.
	 * @param scanValue Work Order Id or Work Order Number
	 * @return Work Performed table for a Device or Instrument Work Order
	 */
	public static OverrideWorkspace loadWorkPerformed(String scanValue) {
		if (String.isBlank(scanValue)) {
			throw new SignatureOverrideException('Scan Barcode is required.');
		}
		WorkOrder workOrder = WorkOrdersSelector.selectForSignatureOverrideByIdOrNumber(
			scanValue.trim()
		);
		if (!isSupportedWorkOrder(workOrder)) {
			throw new SignatureOverrideException(INVALID_WORK_ORDER_MESSAGE);
		}
		if (RepairCenterTeamMembersSelector.countByWorkOrderId(workOrder.Id) == 0) {
			throw new SignatureOverrideException(NO_SIGNATURES_MESSAGE);
		}
		return buildWorkspace(workOrder);
	}

	/**
	 * @description GW-5310 - Adds a technician signature and returns the refreshed table.
	 * @param workOrderId Work Order Id
	 * @param workOrderLineItemId Repair Code line Id
	 * @param technicianUserId Technician User Id
	 * @return Refreshed Work Performed table
	 */
	public static OverrideWorkspace addSignature(
		Id workOrderId,
		Id workOrderLineItemId,
		Id technicianUserId
	) {
		WorkOrder workOrder = requireSupportedWorkOrder(workOrderId);
		if (technicianUserId == null) {
			throw new SignatureOverrideException(TECHNICIAN_REQUIRED_MESSAGE);
		}
		ServiceResource technician = ServiceResourcesSelector.selectActiveByRepairCenterAndUser(
			workOrder.RepairCenter__c,
			technicianUserId
		);
		if (technician == null) {
			throw new SignatureOverrideException(TECHNICIAN_NOT_AT_CENTER_MESSAGE);
		}
		String technicianName = technician.RelatedRecord == null
			? null
			: technician.RelatedRecord.Name;
		try {
			RepairCenterTeamMembersService.addSignatureForTechnician(
				workOrder.Id,
				workOrderLineItemId,
				technicianUserId,
				technicianName
			);
		} catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
			throw new SignatureOverrideException(e.getMessage());
		}
		return buildWorkspace(workOrder);
	}

	/**
	 * @description GW-5310 - Removes a signature and returns the refreshed table.
	 *              Removing the last signature raises the no-signature validation.
	 * @param workOrderId Work Order Id
	 * @param signatureId Repair Center Team Member Id
	 * @return Refreshed Work Performed table
	 */
	public static OverrideWorkspace removeSignature(Id workOrderId, Id signatureId) {
		WorkOrder workOrder = requireSupportedWorkOrder(workOrderId);
		try {
			RepairCenterTeamMembersService.removeSignatureForOverride(workOrder.Id, signatureId);
		} catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
			throw new SignatureOverrideException(e.getMessage());
		}
		if (RepairCenterTeamMembersSelector.countByWorkOrderId(workOrder.Id) == 0) {
			throw new SignatureOverrideException(NO_SIGNATURES_MESSAGE);
		}
		return buildWorkspace(workOrder);
	}

	/**
	 * @description GW-5310 - Technicians with an active Service Resource at the Work Order Repair Center.
	 * @param workOrderId Work Order Id
	 * @param searchTerm Name search text. Blank returns the first matches.
	 * @return Technician choices
	 */
	public static List<TechnicianOption> searchTechnicians(Id workOrderId, String searchTerm) {
		WorkOrder workOrder = requireSupportedWorkOrder(workOrderId);
		if (workOrder.RepairCenter__c == null) {
			return new List<TechnicianOption>();
		}
		String likeTerm = '%' + escapeLike(searchTerm) + '%';
		List<TechnicianOption> options = new List<TechnicianOption>();
		Set<Id> seenUserIds = new Set<Id>();
		for (
			ServiceResource resource : ServiceResourcesSelector.selectActiveByRepairCenterAndName(
				workOrder.RepairCenter__c,
				likeTerm
			)
		) {
			if (resource.RelatedRecordId == null || seenUserIds.contains(resource.RelatedRecordId)) {
				continue;
			}
			seenUserIds.add(resource.RelatedRecordId);
			TechnicianOption option = new TechnicianOption();
			option.userId = resource.RelatedRecordId;
			option.name = resource.RelatedRecord == null
				? null
				: resource.RelatedRecord.Name;
			options.add(option);
		}
		return options;
	}

	/**
	 * @description GW-5310 - Work Performed payload for the coordinator screen.
	 */
	public class OverrideWorkspace {
		/** GW-5310 - Work Order Id. */
		@AuraEnabled public Id workOrderId { get; set; }
		/** GW-5310 - Work Order Number. */
		@AuraEnabled public String workOrderNumber { get; set; }
		/** GW-5310 - device or instrument. */
		@AuraEnabled public String tableLayout { get; set; }
		/** GW-5310 - Repair Code rows. */
		@AuraEnabled public List<WorkPerformedRow> rows { get; set; }
	}

	/**
	 * @description GW-5310 - One Repair Code row in Work Performed.
	 */
	public class WorkPerformedRow {
		/** GW-5310 - Repair Code Work Order Line Item Id. */
		@AuraEnabled public Id workOrderLineItemId { get; set; }
		/** GW-5310 - Device eval category. */
		@AuraEnabled public String category { get; set; }
		/** GW-5310 - Product code for the device repair code, or the instrument item. */
		@AuraEnabled public String itemNumber { get; set; }
		/** GW-5310 - Instrument product name. */
		@AuraEnabled public String productName { get; set; }
		/** GW-5310 - Instrument quantity. */
		@AuraEnabled public String quantity { get; set; }
		/** GW-5310 - Device repair-code description. */
		@AuraEnabled public String description { get; set; }
		/** GW-5310 - Instrument repair-code name. */
		@AuraEnabled public String repairDescription { get; set; }
		/** GW-5310 - Instrument line status. */
		@AuraEnabled public String status { get; set; }
		/** GW-5310 - Signatures on this line. */
		@AuraEnabled public List<SignatureChip> signatures { get; set; }
	}

	/**
	 * @description GW-5310 - One technician signature.
	 */
	public class SignatureChip {
		/** GW-5310 - Team Member Id. */
		@AuraEnabled public Id id { get; set; }
		/** GW-5310 - Technician name. */
		@AuraEnabled public String userName { get; set; }
	}

	/**
	 * @description GW-5310 - Technician lookup choice.
	 */
	public class TechnicianOption {
		/** GW-5310 - User Id. */
		@AuraEnabled public Id userId { get; set; }
		/** GW-5310 - User name. */
		@AuraEnabled public String name { get; set; }
	}

	/**
	 * @description GW-5310 - Business-friendly exception for signature override.
	 */
	public class SignatureOverrideException extends Exception {
	}

	private static OverrideWorkspace buildWorkspace(WorkOrder workOrder) {
		Boolean isDevice = workOrder.RecordType.DeveloperName == RECORD_TYPE_DEVICES;
		Map<Id, List<SignatureChip>> signaturesByLine = signaturesByLineItem(workOrder.Id);
		List<WorkPerformedRow> rows = new List<WorkPerformedRow>();
		for (
			WorkOrderLineItem lineItem : WorkOrderLineItemsSelector.selectRepairCodesForSignatureOverride(
				workOrder.Id,
				WorkOrderLineItemsService.getRepairCodeRecordTypeId()
			)
		) {
			rows.add(toRow(lineItem, isDevice, signaturesByLine.get(lineItem.Id)));
		}
		sortRows(rows, isDevice);

		OverrideWorkspace workspace = new OverrideWorkspace();
		workspace.workOrderId = workOrder.Id;
		workspace.workOrderNumber = workOrder.WorkOrderNumber;
		workspace.tableLayout = isDevice ? LAYOUT_DEVICE : LAYOUT_INSTRUMENT;
		workspace.rows = rows;
		return workspace;
	}

	private static WorkOrder requireSupportedWorkOrder(Id workOrderId) {
		WorkOrder workOrder = workOrderId == null
			? null
			: WorkOrdersSelector.selectForSignatureOverrideByIdOrNumber(String.valueOf(workOrderId));
		if (!isSupportedWorkOrder(workOrder)) {
			throw new SignatureOverrideException(INVALID_WORK_ORDER_MESSAGE);
		}
		return workOrder;
	}

	private static Boolean isSupportedWorkOrder(WorkOrder workOrder) {
		if (workOrder == null || workOrder.RecordType == null) {
			return false;
		}
		String developerName = workOrder.RecordType.DeveloperName;
		return developerName == RECORD_TYPE_DEVICES || developerName == RECORD_TYPE_INSTRUMENTS;
	}

	private static Map<Id, List<SignatureChip>> signaturesByLineItem(Id workOrderId) {
		Map<Id, List<SignatureChip>> signaturesByLine = new Map<Id, List<SignatureChip>>();
		for (
			RepairCenterTeamMember__c signature : RepairCenterTeamMembersSelector.selectWorkOrderLineSignaturesForOverride(
				workOrderId
			)
		) {
			if (signature.WorkOrderLineItem__c == null) {
				continue;
			}
			if (!signaturesByLine.containsKey(signature.WorkOrderLineItem__c)) {
				signaturesByLine.put(
					signature.WorkOrderLineItem__c,
					new List<SignatureChip>()
				);
			}
			SignatureChip chip = new SignatureChip();
			chip.id = signature.Id;
			chip.userName = signature.Person__r != null &&
				String.isNotBlank(signature.Person__r.Name)
				? signature.Person__r.Name
				: signature.Name;
			signaturesByLine.get(signature.WorkOrderLineItem__c).add(chip);
		}
		return signaturesByLine;
	}

	private static WorkPerformedRow toRow(
		WorkOrderLineItem lineItem,
		Boolean isDevice,
		List<SignatureChip> signatures
	) {
		WorkPerformedRow row = new WorkPerformedRow();
		row.workOrderLineItemId = lineItem.Id;
		row.signatures = signatures == null ? new List<SignatureChip>() : signatures;
		if (isDevice) {
			row.category = firstNonBlank(
				lineItem.Product__r?.EvalCategory__c,
				lineItem.Product2?.EvalCategory__c
			);
			row.itemNumber = firstNonBlank(
				lineItem.Product__r?.ProductCode,
				lineItem.Product2?.ProductCode
			);
			row.description = firstNonBlank(
				firstNonBlank(lineItem.Product__r?.Description, lineItem.Product2?.Description),
				firstNonBlank(lineItem.Product__r?.Name, lineItem.Product2?.Name)
			);
			return row;
		}

		WorkOrderLineItem parentLine = lineItem.ParentWorkOrderLineItem;
		row.itemNumber = firstNonBlank(
			parentLine?.Product__r?.ProductCode,
			parentLine?.Product2?.ProductCode
		);
		row.productName = firstNonBlank(
			parentLine?.Product__r?.Name,
			parentLine?.Product2?.Name
		);
		row.quantity = formatQuantity(
			parentLine == null ? lineItem.Quantity : parentLine.Quantity
		);
		row.repairDescription = firstNonBlank(
			firstNonBlank(lineItem.Product__r?.Name, lineItem.Product2?.Name),
			firstNonBlank(lineItem.Product__r?.ProductCode, lineItem.Product2?.ProductCode)
		);
		row.status = lineItem.Status;
		return row;
	}

	private static void sortRows(List<WorkPerformedRow> rows, Boolean isDevice) {
		rows.sort(new RowComparator(isDevice));
	}

	private static String formatQuantity(Decimal quantity) {
		if (quantity == null) {
			return '';
		}
		return quantity.stripTrailingZeros().toPlainString();
	}

	private static String firstNonBlank(String preferred, String fallback) {
		return String.isNotBlank(preferred) ? preferred : fallback;
	}

	private static String escapeLike(String searchTerm) {
		String value = String.isBlank(searchTerm) ? '' : searchTerm.trim();
		return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
	}

	/**
	 * @description GW-5310 - Orders device rows by category and instruments by item number.
	 */
	private class RowComparator implements System.Comparator<WorkPerformedRow> {
		private final Boolean isDevice;

		private RowComparator(Boolean isDevice) {
			this.isDevice = isDevice;
		}

		public Integer compare(WorkPerformedRow left, WorkPerformedRow right) {
			String leftKey = isDevice
				? sortKey(left?.category, left?.itemNumber)
				: sortKey(left?.itemNumber, left?.repairDescription);
			String rightKey = isDevice
				? sortKey(right?.category, right?.itemNumber)
				: sortKey(right?.itemNumber, right?.repairDescription);
			return leftKey.toLowerCase().compareTo(rightKey.toLowerCase());
		}

		private String sortKey(String first, String second) {
			return (first == null ? '' : first) + '|' + (second == null ? '' : second);
		}
	}
}