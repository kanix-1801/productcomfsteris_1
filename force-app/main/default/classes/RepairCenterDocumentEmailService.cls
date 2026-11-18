/**
 * @description GW-4189 / GW-3591: Enqueues Repair Center customer email after a
 *              Design Document PDF is linked to a Quote or Work Order.
 *              GW-5695: On a Work Order only the Order Acknowledgement PDF sends the email, so
 *              Service Delivery Reports, Delivery Notes and other PDFs no longer go out as an Order Acknowledgement.
 */
public with sharing class RepairCenterDocumentEmailService {
	@TestVisible
	private static final Pattern QUOTE_DOC_GEN_TITLE_PATTERN = Pattern.compile(
		'^(\\d+-.*-V\\d+|RepairCenterQuote-.+|0Q0.+)$'
	);

	/**
	 * @description After a Repair Center doc-gen PDF is linked to a Quote or Work Order,
	 *              enqueue email send so the PDF is committed before the email goes out.
	 * @param links Newly inserted ContentDocumentLink records.
	 */
	public static void handleNewContentDocumentLinks(List<ContentDocumentLink> links) {
		if (links == null || links.isEmpty()) {
			return;
		}

		List<ContentDocumentLink> candidateLinks = new List<ContentDocumentLink>();
		Set<Id> contentDocumentIds = new Set<Id>();
		for (ContentDocumentLink link : links) {
			if (
				link == null ||
				link.Id == null ||
				link.LinkedEntityId == null ||
				link.ContentDocumentId == null ||
				!isSupportedLinkedEntity(link.LinkedEntityId)
			) {
				continue;
			}
			candidateLinks.add(link);
			contentDocumentIds.add(link.ContentDocumentId);
		}
		if (candidateLinks.isEmpty()) {
			return;
		}

		Map<Id, String> titleByContentDocumentId = getLatestPdfTitlesByContentDocumentId(
			contentDocumentIds
		);
		Map<Id, String> orderAcknowledgementTitleByWorkOrderId = selectOrderAcknowledgementTitles(candidateLinks);
		List<Id> eligibleLinkIds = new List<Id>();
		for (ContentDocumentLink link : candidateLinks) {
			String title = titleByContentDocumentId.get(link.ContentDocumentId);
			if (isRepairCenterDocGenTitle(title, link.LinkedEntityId, orderAcknowledgementTitleByWorkOrderId.get(link.LinkedEntityId))) {
				eligibleLinkIds.add(link.Id);
			}
		}
		if (eligibleLinkIds.isEmpty()) {
			return;
		}
		System.enqueueJob(new SendRepairCenterDocumentEmailQueueable(eligibleLinkIds));
	}

	/**
	 * @description True when the linked entity is a Quote or Work Order.
	 * @param linkedEntityId Linked entity Id from ContentDocumentLink.
	 * @return True when Quote or Work Order.
	 */
	public static Boolean isSupportedLinkedEntity(Id linkedEntityId) {
		if (linkedEntityId == null) {
			return false;
		}
		Schema.SObjectType linkedType = linkedEntityId.getSObjectType();
		return linkedType == Quote.SObjectType || linkedType == WorkOrder.SObjectType;
	}

	/**
	 * @description True when the file should send the customer email: a Quote doc-gen PDF, or on a Work Order
	 *              exactly the Order Acknowledgement PDF. GW-5695 - Work Orders also get Service Delivery Reports
	 *              (-SDR), Delivery Notes (-DN) and other PDFs; matching on a title prefix sent those as an Order Acknowledgement.
	 * @param title Latest ContentVersion Title.
	 * @param linkedEntityId Quote or Work Order Id.
	 * @param orderAcknowledgementTitle Expected Order Acknowledgement title for the Work Order (WorkOrderNumber-AccountNumber).
	 * @return True when the file should trigger customer email.
	 */
	@TestVisible
	public static Boolean isRepairCenterDocGenTitle(String title, Id linkedEntityId, String orderAcknowledgementTitle) {
		if (String.isBlank(title) || linkedEntityId == null) {
			return false;
		}
		Schema.SObjectType linkedType = linkedEntityId.getSObjectType();
		if (linkedType == Quote.SObjectType) {
			return QUOTE_DOC_GEN_TITLE_PATTERN.matcher(title).matches();
		}
		return linkedType == WorkOrder.SObjectType && String.isNotBlank(orderAcknowledgementTitle) && title.equals(orderAcknowledgementTitle);
	}

	/**
	 * @description GW-5695 - Builds the Order Acknowledgement file title for each linked Work Order, using the same
	 *              WorkOrderNumber-AccountNumber naming as RepairCenterDocGenService.buildWorkOrderDocumentFileTitle.
	 * @param links Candidate links to Quotes or Work Orders.
	 * @return Work Order Id to expected Order Acknowledgement title. Empty when no Work Orders are linked.
	 */
	private static Map<Id, String> selectOrderAcknowledgementTitles(List<ContentDocumentLink> links) {
		Map<Id, String> titleByWorkOrderId = new Map<Id, String>();
		// Typed as List<Id>: a List<Object> bind fails against the Id column.
		List<Id> workOrderIds = new List<Id>();
		for (ContentDocumentLink link : links) {
			if (link.LinkedEntityId.getSObjectType() == WorkOrder.SObjectType) {
				workOrderIds.add(link.LinkedEntityId);
			}
		}
		if (workOrderIds.isEmpty()) {
			return titleByWorkOrderId;
		}
		List<WorkOrder> workOrders = (List<WorkOrder>) new WorkOrdersSelector()
			.selectFields(new List<String>{ 'Id', 'WorkOrderNumber', 'Account.AccountNumber' })
			.whereIn('Id', workOrderIds)
			.execute();
		for (WorkOrder workOrderRecord : workOrders) {
			String accountNumber = workOrderRecord.Account?.AccountNumber == null ? '' : workOrderRecord.Account.AccountNumber;
			titleByWorkOrderId.put(workOrderRecord.Id, workOrderRecord.WorkOrderNumber + '-' + accountNumber);
		}
		return titleByWorkOrderId;
	}

	private static Map<Id, String> getLatestPdfTitlesByContentDocumentId(
		Set<Id> contentDocumentIds
	) {
		Map<Id, String> titleByContentDocumentId = new Map<Id, String>();
		if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
			return titleByContentDocumentId;
		}
		for (
			ContentVersion version : ContentVersionsService.selectLatestPdfsByContentDocumentIds(
				contentDocumentIds
			)
		) {
			if (!titleByContentDocumentId.containsKey(version.ContentDocumentId)) {
				titleByContentDocumentId.put(version.ContentDocumentId, version.Title);
			}
		}
		return titleByContentDocumentId;
	}
}