/**
 * @description GW-6017 - Finish Review Work Order on the CRSS debrief.
 *              Blocks while a Do Not Use (P0) line still needs a return order and lists
 *              Product Serviced lines without a Mobile Device Picture.
 */
public without sharing class WoDebriefCrssReviewController {
	private static final String LINE_TYPE_PRODUCT_SERVICED = 'Product Serviced';
	private static final String LINE_STATUS_CANCELED = 'Canceled';

	/**
	 * @description GW-6017 - Result of Finish Review Work Order.
	 */
	public class WorkOrderReviewResult {
		/** @description True when no line is waiting for a return order. */
		@AuraEnabled public Boolean canFinish;
		/** @description Lines still marked Send to Repair Center. */
		@AuraEnabled public List<String> returnOrderLines;
		/** @description Product Serviced lines without a Mobile Device Picture. */
		@AuraEnabled public List<String> linesMissingPictures;
		/** @description True when Work Order Review Done was checked. */
		@AuraEnabled public Boolean reviewDone;
	}

	/**
	 * @description GW-6017 - Checks the CRSS work order before the service report.
	 *              When no line is waiting for a return order, Work Order Review Done is checked,
	 *              unless a line has no picture and the technician has not chosen to continue.
	 * @param workOrderId CRSS Work Order Id
	 * @param continueWithoutPictures True when the technician chose to finish without the missing pictures
	 * @return Review result
	 */
	@AuraEnabled
	public static WorkOrderReviewResult checkWorkOrderReview(Id workOrderId, Boolean continueWithoutPictures) {
		if (workOrderId == null) {
			throw handledException('Work order could not be identified.');
		}
		List<WorkOrderLineItem> lines = [
			SELECT Id, LineItemNumber, SendToRepairCenter__c, Asset.Name, Asset.SerialNumber
			FROM WorkOrderLineItem
			WHERE WorkOrderId = :workOrderId
				AND LineType__c = :LINE_TYPE_PRODUCT_SERVICED
				AND Status != :LINE_STATUS_CANCELED
			ORDER BY LineItemNumber
		];
		Set<Id> linesWithPictures = linesWithMobileDevicePictures(lines);

		WorkOrderReviewResult result = new WorkOrderReviewResult();
		result.returnOrderLines = new List<String>();
		result.linesMissingPictures = new List<String>();
		for (WorkOrderLineItem line : lines) {
			if (line.SendToRepairCenter__c == true) {
				result.returnOrderLines.add(lineLabel(line));
			}
			if (!linesWithPictures.contains(line.Id)) {
				result.linesMissingPictures.add(lineLabel(line));
			}
		}
		result.canFinish = result.returnOrderLines.isEmpty();
		result.reviewDone = result.canFinish
			&& (result.linesMissingPictures.isEmpty() || continueWithoutPictures == true);
		if (result.reviewDone) {
			try {
				update new WorkOrder(Id = workOrderId, WorkOrderReviewDone__c = true);
			} catch (DmlException ex) {
				throw handledException(ex.getDmlMessage(0));
			}
		}
		return result;
	}

	/**
	 * @description GW-6017 - Lines that have at least one Mobile Device Picture.
	 * @param lines Product Serviced lines
	 * @return Line Ids with a picture
	 */
	private static Set<Id> linesWithMobileDevicePictures(List<WorkOrderLineItem> lines) {
		Set<Id> lineIds = new Map<Id, WorkOrderLineItem>(lines).keySet();
		Set<Id> withPictures = new Set<Id>();
		if (lineIds.isEmpty()) {
			return withPictures;
		}
		for (ContentDocumentLink link : [
			SELECT LinkedEntityId
			FROM ContentDocumentLink
			WHERE LinkedEntityId IN :lineIds
				AND ContentDocument.Title IN :WoDebriefIMSchildWOController.PICTURE_TITLES
		]) {
			withPictures.add(link.LinkedEntityId);
		}
		return withPictures;
	}

	/**
	 * @description GW-6017 - Line number with the asset serial number or name.
	 * @param line Product Serviced line
	 * @return Label shown in the review dialog
	 */
	private static String lineLabel(WorkOrderLineItem line) {
		String assetLabel = String.isNotBlank(line.Asset?.SerialNumber)
			? line.Asset.SerialNumber
			: (String.isNotBlank(line.Asset?.Name) ? line.Asset.Name : 'No asset');
		String lineNumber = String.isNotBlank(line.LineItemNumber) ? line.LineItemNumber : '';
		return String.isBlank(lineNumber) ? assetLabel : 'Line ' + lineNumber + ' - ' + assetLabel;
	}

	/**
	 * @description Aura exception whose message is returned to the LWC.
	 * @param message Message shown in the debrief
	 * @return Exception to throw
	 */
	private static AuraHandledException handledException(String message) {
		AuraHandledException ex = new AuraHandledException(message);
		ex.setMessage(message);
		return ex;
	}
}