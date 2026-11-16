/**
 * @author Uptima
 * @date 2026-11-13
 * @group Repair Center
 * @description GW-5287 thin LWC controller for View Work Order Summary.
 */
public with sharing class ViewWorkOrderSummaryController {
	/**
	 * @description GW-5287 - Loads the Work Order Summary workspace for a scanned input.
	 * @param workOrderInput Work Order Id or WorkOrderNumber
	 * @return Summary workspace
	 */
	@AuraEnabled
	public static WorkOrderSummaryService.WorkOrderSummaryWorkspace getSummary(
		String workOrderInput
	) {
		try {
			return WorkOrderSummaryService.getSummary(workOrderInput);
		} catch (WorkOrderSummaryService.WorkOrderSummaryServiceException e) {
			throw buildAuraException(e.getMessage());
		} catch (Exception e) {
			Logger.error('ViewWorkOrderSummaryController.getSummary failed.', e);
			Logger.saveLog();
			throw buildAuraException(e.getMessage());
		}
	}

	private static AuraHandledException buildAuraException(String message) {
		AuraHandledException auraException = new AuraHandledException(message);
		auraException.setMessage(message);
		return auraException;
	}
}