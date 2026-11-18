/**
 * @description GW-4378 - Photos tab for Device Evaluation and Instrument Evaluation.
 */
public with sharing class EvaluationPhotosController {
	/**
	 * @description Photo row returned to the Photos tab.
	 */
	public class EvaluationPhotoRow {
		@AuraEnabled public Id contentDocumentId;
		@AuraEnabled public Id contentVersionId;
		@AuraEnabled public String title;
		@AuraEnabled public String fileExtension;
		@AuraEnabled public String fileType;
		@AuraEnabled public Datetime lastModifiedDate;
		@AuraEnabled public String downloadUrl;
		@AuraEnabled public String thumbnailUrl;
		@AuraEnabled public String imageDownloadUrl;
		@AuraEnabled public Boolean isImage;
		@AuraEnabled public Id linkedEntityId;
		@AuraEnabled public String sourceLabel;
		@AuraEnabled public Boolean isOptional;
	}

	/**
	 * @description GW-4378 - Photos linked to the Work Order and its line items.
	 * @param workOrderId Child Work Order Id
	 * @return Photo rows
	 */
	@AuraEnabled
	public static List<EvaluationPhotoRow> getPhotos(Id workOrderId) {
		try {
			return mapRows(EvaluationPhotosService.getPhotos(workOrderId));
		} catch (Exception e) {
			throw toAuraException(e, 'Unable to load photos.');
		}
	}

	/**
	 * @description GW-4378 - Saves a photo on the child Work Order. Title is [date] TBD.
	 * @param workOrderId Child Work Order Id
	 * @param base64Data File payload
	 * @param fileName Optional original file name
	 * @return Saved photo row
	 */
	@AuraEnabled
	public static EvaluationPhotoRow capturePhoto(
		Id workOrderId,
		String base64Data,
		String fileName
	) {
		try {
			return mapRow(EvaluationPhotosService.capturePhoto(workOrderId, base64Data, fileName));
		} catch (Exception e) {
			throw toAuraException(e, 'Unable to save photo.');
		}
	}

	/**
	 * @description GW-4378 - Renames a photo.
	 * @param contentDocumentId ContentDocument Id
	 * @param newTitle New title
	 * @return Updated photo fields
	 */
	@AuraEnabled
	public static EvaluationPhotoRow renamePhoto(Id contentDocumentId, String newTitle) {
		try {
			return mapRow(EvaluationPhotosService.renamePhoto(contentDocumentId, newTitle));
		} catch (Exception e) {
			throw toAuraException(e, 'Unable to rename photo.');
		}
	}

	/**
	 * @description GW-4378 - Deletes a photo from the Work Order or line item it is linked to.
	 * @param workOrderId Child Work Order Id
	 * @param linkedEntityId Work Order or Work Order Line Item Id
	 * @param contentDocumentId ContentDocument Id
	 */
	@AuraEnabled
	public static void deletePhoto(Id workOrderId, Id linkedEntityId, Id contentDocumentId) {
		try {
			EvaluationPhotosService.deletePhoto(workOrderId, linkedEntityId, contentDocumentId);
		} catch (Exception e) {
			throw toAuraException(e, 'Unable to delete photo.');
		}
	}

	private static List<EvaluationPhotoRow> mapRows(List<EvaluationPhotosService.PhotoRow> rows) {
		List<EvaluationPhotoRow> mapped = new List<EvaluationPhotoRow>();
		if (rows == null) {
			return mapped;
		}
		for (EvaluationPhotosService.PhotoRow row : rows) {
			mapped.add(mapRow(row));
		}
		return mapped;
	}

	private static EvaluationPhotoRow mapRow(EvaluationPhotosService.PhotoRow row) {
		EvaluationPhotoRow mapped = new EvaluationPhotoRow();
		if (row == null) {
			return mapped;
		}
		mapped.contentDocumentId = row.contentDocumentId;
		mapped.contentVersionId = row.contentVersionId;
		mapped.title = row.title;
		mapped.fileExtension = row.fileExtension;
		mapped.fileType = row.fileType;
		mapped.lastModifiedDate = row.lastModifiedDate;
		mapped.downloadUrl = row.downloadUrl;
		mapped.thumbnailUrl = row.thumbnailUrl;
		mapped.imageDownloadUrl = row.imageDownloadUrl;
		mapped.isImage = row.isImage;
		mapped.linkedEntityId = row.linkedEntityId;
		mapped.sourceLabel = row.sourceLabel;
		mapped.isOptional = row.isOptional;
		return mapped;
	}

	private static AuraHandledException toAuraException(Exception e, String fallback) {
		if (e instanceof AuraHandledException) {
			return (AuraHandledException) e;
		}
		String message = e.getMessage();
		if (e instanceof DmlException) {
			message = ((DmlException) e).getDmlMessage(0);
		}
		if (String.isBlank(message)) {
			message = fallback;
		}
		return PlatformUtilities.buildAuraException(message);
	}
}