/**
 * @author Uptima
 * @date 2026-11-13
 * @group Repair Center
 * @description GW-5287 thin LWC controller for View Work Order Summary.
 */
public with sharing class ViewWorkOrderSummaryController {
	@TestVisible
	private interface ISummaryClient {
		WorkOrderSummaryService.WorkOrderSummaryWorkspace getSummary(String workOrderInput);
	}

	private class DefaultClient implements ISummaryClient {
		public WorkOrderSummaryService.WorkOrderSummaryWorkspace getSummary(String workOrderInput) {
			return WorkOrderSummaryService.getSummary(workOrderInput);
		}
	}

	@TestVisible
	private static ISummaryClient clientOverride;

	private static ISummaryClient client() {
		return clientOverride == null ? new DefaultClient() : clientOverride;
	}

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
			return client().getSummary(workOrderInput);
		} catch (WorkOrderSummaryService.WorkOrderSummaryServiceException e) {
			throw PlatformUtilities.buildAuraException(e.getMessage());
		} catch (Exception e) {
			Logger.error('ViewWorkOrderSummaryController.getSummary failed.', e);
			throw PlatformUtilities.buildAuraException(e.getMessage());
		} finally {
			Logger.saveLog();
		}
	}
}