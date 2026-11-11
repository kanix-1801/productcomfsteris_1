/**
 * @author Sagar Anand
 * @date 2026-11-06
 * @group Field Service Backoffice
 * @description GW-2706: LWC entry point for District Zone Alignment. Business logic is in
 *              DistrictZoneAlignmentService.
 */
public with sharing class DistrictZoneAlignmentController {
	/**
	 * @description GW-2706: Download URL of the District Zone Alignment template.
	 * @return Relative Salesforce Files download URL.
	 * @throws AuraHandledException When the template is not available.
	 * @example
	 * String url = DistrictZoneAlignmentController.getTemplateDownloadUrl();
	 */
	@AuraEnabled
	public static String getTemplateDownloadUrl() {
		try {
			Id documentId = DistrictZoneAlignmentService.ensureTemplateDocumentId();
			return DistrictZoneAlignmentService.DOWNLOAD_URL_PREFIX + documentId;
		} catch (DistrictZoneAlignmentService.DistrictZoneAlignmentException e) {
			throw toAuraException(e.getMessage());
		}
	}

	/**
	 * @description GW-2706: Download URL of the running user's latest error file.
	 * @return Relative Salesforce Files download URL.
	 * @throws AuraHandledException When the user has no error file yet.
	 * @example
	 * String url = DistrictZoneAlignmentController.getErrorFileDownloadUrl();
	 */
	@AuraEnabled
	public static String getErrorFileDownloadUrl() {
		Id documentId;
		try {
			documentId = DistrictZoneAlignmentService.getErrorFileDocumentId();
		} catch (DistrictZoneAlignmentService.DistrictZoneAlignmentException e) {
			throw toAuraException(e.getMessage());
		}
		if (documentId == null) {
			throw toAuraException(Label.DZA_NoErrorFile);
		}
		return DistrictZoneAlignmentService.DOWNLOAD_URL_PREFIX + documentId;
	}

	/**
	 * @description GW-2706: Processes the uploaded District Zone Alignment file.
	 * @param contentDocumentId Salesforce Files document Id from lightning-file-upload.
	 * @return Counts, row errors and the error file Id.
	 * @throws AuraHandledException When the file can't be processed.
	 * @example
	 * DistrictZoneAlignmentController.processUpload(documentId);
	 */
	@AuraEnabled
	public static DistrictZoneAlignmentService.ProcessResult processUpload(Id contentDocumentId) {
		try {
			return DistrictZoneAlignmentService.processUpload(contentDocumentId);
		} catch (DistrictZoneAlignmentService.DistrictZoneAlignmentException e) {
			throw toAuraException(e.getMessage());
		}
	}

	private static AuraHandledException toAuraException(String message) {
		AuraHandledException auraException = new AuraHandledException(message);
		auraException.setMessage(message);
		return auraException;
	}
}