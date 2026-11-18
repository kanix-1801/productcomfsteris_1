/**
 * @description GW-4378 - Optional evaluation photos stored on the child Work Order,
 *              plus the combined Work Order and Work Order Line Item photo list.
 */
public with sharing class EvaluationPhotosService {
	/**
	 * @description Photo row for the evaluation Photos tab.
	 */
	public class PhotoRow {
		public Id contentDocumentId;
		public Id contentVersionId;
		public String title;
		public String fileExtension;
		public String fileType;
		public Datetime lastModifiedDate;
		public String downloadUrl;
		public String thumbnailUrl;
		public String imageDownloadUrl;
		public Boolean isImage;
		public Id linkedEntityId;
		public Id productId;
		public String productCode;
		public String productName;
		public String sourceLabel;
		public Boolean isOptional;
	}

	/**
	 * @description GW-4378 - Photos linked to the Work Order and its line items.
	 * @param workOrderId Child Work Order Id
	 * @return Photo rows, Work Order photos first
	 * @throws EvaluationPhotosServiceException when the Work Order is missing
	 */
	public static List<PhotoRow> getPhotos(Id workOrderId) {
		WorkOrder workOrder = requireWorkOrder(workOrderId);
		Map<Id, WorkOrderLineItem> linesById = linesById(workOrder.Id);
		Set<Id> linkedEntityIds = new Set<Id>{ workOrder.Id };
		linkedEntityIds.addAll(linesById.keySet());

		List<PhotoRow> rows = new List<PhotoRow>();
		for (
			ContentDocumentLinksService.DeviceEvaluationFileData fileData :
			ContentDocumentLinksService.getFilesForLinkedEntities(linkedEntityIds)
		) {
			rows.add(toPhotoRow(fileData, workOrder.Id, linesById));
		}
		rows.sort(new PhotoRowSorter());
		return rows;
	}

	/**
	 * @description GW-4378 - Saves a photo on the child Work Order and copies it to related Quotes.
	 *              The file title is [date] TBD.
	 * @param workOrderId Child Work Order Id
	 * @param base64Data File payload
	 * @param fileName Optional original file name
	 * @return Saved photo row
	 * @throws EvaluationPhotosServiceException when validation fails
	 */
	public static PhotoRow capturePhoto(Id workOrderId, String base64Data, String fileName) {
		WorkOrder workOrder = requireWorkOrder(workOrderId);
		ContentVersion version = ContentVersionsService.stageOptionalEvaluationPhoto(
			base64Data,
			fileName
		);
		ContentDocumentLinksService.attachDocumentsToLinkedEntity(
			workOrder.Id,
			new List<Id>{ version.ContentDocumentId }
		);
		linkDocumentToRelatedQuotes(workOrder, version.ContentDocumentId);

		ContentDocumentLinksService.DeviceEvaluationFileData fileData =
			ContentDocumentLinksService.toFileData(version);
		fileData.linkedEntityId = workOrder.Id;
		return toPhotoRow(fileData, workOrder.Id, new Map<Id, WorkOrderLineItem>());
	}

	/**
	 * @description GW-4378 - Renames a photo the current user created.
	 * @param contentDocumentId ContentDocument Id
	 * @param newTitle New title
	 * @return Updated file fields
	 */
	public static PhotoRow renamePhoto(Id contentDocumentId, String newTitle) {
		ContentVersion refreshed = ContentVersionsService.renamePhotoForDeviceEvaluation(
			contentDocumentId,
			newTitle
		);
		ContentDocumentLinksService.DeviceEvaluationFileData fileData =
			ContentDocumentLinksService.toFileData(refreshed);
		PhotoRow row = toPhotoRow(fileData, null, new Map<Id, WorkOrderLineItem>());
		return row;
	}

	/**
	 * @description GW-4378 - Removes a photo from the Work Order or one of its line items.
	 *              Optional Work Order photos are also removed from related Quotes.
	 * @param workOrderId Child Work Order Id
	 * @param linkedEntityId Work Order or Work Order Line Item the photo is linked to
	 * @param contentDocumentId ContentDocument Id
	 */
	public static void deletePhoto(Id workOrderId, Id linkedEntityId, Id contentDocumentId) {
		WorkOrder workOrder = requireWorkOrder(workOrderId);
		if (linkedEntityId == null || contentDocumentId == null) {
			throw new EvaluationPhotosServiceException('Photo is required.');
		}
		if (linkedEntityId != workOrder.Id && !linesById(workOrder.Id).containsKey(linkedEntityId)) {
			throw new EvaluationPhotosServiceException(
				'The selected photo is not attached to this Work Order.'
			);
		}
		if (linkedEntityId == workOrder.Id) {
			unlinkDocumentFromRelatedQuotes(workOrder, contentDocumentId);
		}
		ContentDocumentLinksService.removeDocumentFromLinkedEntity(
			linkedEntityId,
			contentDocumentId
		);
	}

	/**
	 * @description GW-4378 - Copies optional child Work Order photos onto newly created Quotes.
	 *              Quote.WorkOrder__c is the parent Work Order.
	 * @param quoteRecords Quotes from after insert
	 */
	public static void attachOptionalPhotosToQuotes(List<Quote> quoteRecords) {
		if (quoteRecords == null || quoteRecords.isEmpty()) {
			return;
		}
		Map<Id, List<Quote>> quotesByWorkOrderId = new Map<Id, List<Quote>>();
		for (Quote quoteRecord : quoteRecords) {
			if (quoteRecord == null || quoteRecord.WorkOrder__c == null || quoteRecord.Id == null) {
				continue;
			}
			if (!quotesByWorkOrderId.containsKey(quoteRecord.WorkOrder__c)) {
				quotesByWorkOrderId.put(quoteRecord.WorkOrder__c, new List<Quote>());
			}
			quotesByWorkOrderId.get(quoteRecord.WorkOrder__c).add(quoteRecord);
		}
		if (quotesByWorkOrderId.isEmpty()) {
			return;
		}

		Map<Id, Id> parentIdBySourceWorkOrderId = new Map<Id, Id>();
		for (Id workOrderId : quotesByWorkOrderId.keySet()) {
			parentIdBySourceWorkOrderId.put(workOrderId, workOrderId);
		}
		for (WorkOrder child : WorkOrdersSelector.selectChildIdsByParentIds(quotesByWorkOrderId.keySet())) {
			if (child.ParentWorkOrderId != null) {
				parentIdBySourceWorkOrderId.put(child.Id, child.ParentWorkOrderId);
			}
		}

		Map<Id, Set<Id>> quoteIdsByDocumentId = new Map<Id, Set<Id>>();
		for (
			ContentDocumentLinksService.DeviceEvaluationFileData fileData :
			ContentDocumentLinksService.getFilesForLinkedEntities(parentIdBySourceWorkOrderId.keySet())
		) {
			Id parentId = parentIdBySourceWorkOrderId.get(fileData.linkedEntityId);
			if (
				parentId == null ||
				!quotesByWorkOrderId.containsKey(parentId) ||
				fileData.description != ContentVersionsService.OPTIONAL_EVALUATION_PHOTO_DESCRIPTION
			) {
				continue;
			}
			if (!quoteIdsByDocumentId.containsKey(fileData.contentDocumentId)) {
				quoteIdsByDocumentId.put(fileData.contentDocumentId, new Set<Id>());
			}
			for (Quote quoteRecord : quotesByWorkOrderId.get(parentId)) {
				quoteIdsByDocumentId.get(fileData.contentDocumentId).add(quoteRecord.Id);
			}
		}
		linkDocuments(quoteIdsByDocumentId);
	}

	private static void linkDocumentToRelatedQuotes(WorkOrder workOrder, Id contentDocumentId) {
		Set<Id> quoteWorkOrderIds = new Set<Id>{ workOrder.Id };
		if (workOrder.ParentWorkOrderId != null) {
			quoteWorkOrderIds.add(workOrder.ParentWorkOrderId);
		}
		Set<Id> quoteIds = new Set<Id>();
		for (Quote quoteRecord : QuoteSelector.selectByWorkOrderIds(quoteWorkOrderIds)) {
			quoteIds.add(quoteRecord.Id);
		}
		if (quoteIds.isEmpty()) {
			return;
		}
		linkDocuments(new Map<Id, Set<Id>>{ contentDocumentId => quoteIds });
	}

	private static void unlinkDocumentFromRelatedQuotes(WorkOrder workOrder, Id contentDocumentId) {
		Set<Id> quoteWorkOrderIds = new Set<Id>{ workOrder.Id };
		if (workOrder.ParentWorkOrderId != null) {
			quoteWorkOrderIds.add(workOrder.ParentWorkOrderId);
		}
		Set<Id> quoteIds = new Set<Id>();
		for (Quote quoteRecord : QuoteSelector.selectByWorkOrderIds(quoteWorkOrderIds)) {
			quoteIds.add(quoteRecord.Id);
		}
		if (quoteIds.isEmpty()) {
			return;
		}
		Set<Id> linkIds = new Set<Id>();
		for (
			ContentDocumentLink link : ContentDocumentLinksService.getLinksByDocumentsAndLinkedEntities(
				new Set<Id>{ contentDocumentId },
				quoteIds
			)
		) {
			linkIds.add(link.Id);
		}
		ContentDocumentLinksService.deleteContentDocumentLinks(linkIds);
	}

	private static void linkDocuments(Map<Id, Set<Id>> entityIdsByDocumentId) {
		if (entityIdsByDocumentId == null || entityIdsByDocumentId.isEmpty()) {
			return;
		}
		Set<Id> documentIds = new Set<Id>();
		Set<Id> entityIds = new Set<Id>();
		for (Id contentDocumentId : entityIdsByDocumentId.keySet()) {
			if (contentDocumentId == null) {
				continue;
			}
			documentIds.add(contentDocumentId);
			Set<Id> linkedIds = entityIdsByDocumentId.get(contentDocumentId);
			if (linkedIds != null) {
				entityIds.addAll(linkedIds);
			}
		}
		entityIds.remove(null);
		if (documentIds.isEmpty() || entityIds.isEmpty()) {
			return;
		}

		Set<String> existingKeys = new Set<String>();
		for (
			ContentDocumentLink existingLink : ContentDocumentLinksService.getLinksByDocumentsAndLinkedEntities(
				documentIds,
				entityIds
			)
		) {
			existingKeys.add(linkKey(existingLink.ContentDocumentId, existingLink.LinkedEntityId));
		}

		List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
		for (Id contentDocumentId : documentIds) {
			for (Id entityId : entityIdsByDocumentId.get(contentDocumentId)) {
				if (entityId == null) {
					continue;
				}
				String key = linkKey(contentDocumentId, entityId);
				if (existingKeys.contains(key)) {
					continue;
				}
				existingKeys.add(key);
				ContentDocumentLink link = new ContentDocumentLink();
				link.ContentDocumentId = contentDocumentId;
				link.LinkedEntityId = entityId;
				link.ShareType = 'V';
				link.Visibility = 'AllUsers';
				linksToInsert.add(link);
			}
		}
		ContentDocumentLinksService.createContentDocumentLinks(linksToInsert);
	}

	private static String linkKey(Id contentDocumentId, Id linkedEntityId) {
		return String.valueOf(contentDocumentId) + ':' + String.valueOf(linkedEntityId);
	}

	private static WorkOrder requireWorkOrder(Id workOrderId) {
		if (workOrderId == null) {
			throw new EvaluationPhotosServiceException('Work Order is required.');
		}
		List<WorkOrder> workOrders = WorkOrdersSelector.selectParentForEvaluationPhotos(workOrderId);
		if (workOrders.isEmpty()) {
			throw new EvaluationPhotosServiceException('Work Order was not found.');
		}
		return workOrders[0];
	}

	private static Map<Id, WorkOrderLineItem> linesById(Id workOrderId) {
		return new Map<Id, WorkOrderLineItem>(
			WorkOrderLineItemsSelector.selectWithProductByWorkOrderIds(new Set<Id>{ workOrderId })
		);
	}

	private static PhotoRow toPhotoRow(
		ContentDocumentLinksService.DeviceEvaluationFileData fileData,
		Id workOrderId,
		Map<Id, WorkOrderLineItem> linesById
	) {
		PhotoRow row = new PhotoRow();
		if (fileData == null) {
			return row;
		}
		row.contentDocumentId = fileData.contentDocumentId;
		row.contentVersionId = fileData.contentVersionId;
		row.title = fileData.title;
		row.fileExtension = fileData.fileExtension;
		row.fileType = fileData.fileType;
		row.lastModifiedDate = fileData.lastModifiedDate;
		row.downloadUrl = fileData.downloadUrl;
		row.thumbnailUrl = fileData.thumbnailUrl;
		row.imageDownloadUrl = fileData.imageDownloadUrl;
		row.isImage = fileData.isImage;
		row.linkedEntityId = fileData.linkedEntityId;
		row.isOptional = workOrderId != null && fileData.linkedEntityId == workOrderId;
		if (row.isOptional == true) {
			row.sourceLabel = 'Work Order';
			return row;
		}
		WorkOrderLineItem lineItem = linesById == null ? null : linesById.get(fileData.linkedEntityId);
		if (lineItem != null && lineItem.Product2 != null) {
			row.productId = lineItem.Product2Id;
			row.productCode = lineItem.Product2.ProductCode;
			row.productName = String.isNotBlank(lineItem.Product2.Description)
				? lineItem.Product2.Description
				: lineItem.Product2.Name;
		}
		if (String.isNotBlank(row.productCode)) {
			row.sourceLabel = String.isNotBlank(row.productName)
				? row.productCode + ' — ' + row.productName
				: row.productCode;
		} else {
			row.sourceLabel = 'Work Order Line Item';
		}
		return row;
	}

	private class PhotoRowSorter implements System.Comparator<PhotoRow> {
		public Integer compare(PhotoRow left, PhotoRow right) {
			Integer leftRank = left != null && left.isOptional == true ? 0 : 1;
			Integer rightRank = right != null && right.isOptional == true ? 0 : 1;
			if (leftRank != rightRank) {
				return leftRank - rightRank;
			}
			String leftTitle = left == null || left.title == null ? '' : left.title;
			String rightTitle = right == null || right.title == null ? '' : right.title;
			return leftTitle.compareTo(rightTitle);
		}
	}

	/**
	 * @description Thrown when an evaluation photo operation fails validation.
	 */
	public class EvaluationPhotosServiceException extends Exception {}
}