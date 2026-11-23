/**
 * @author Sagar Anand
 * @date 2026-11-06
 * @group Field Service Backoffice
 * @description GW-2706: LWC entry point for District Zone Alignment. Business logic is in
 *              DistrictZoneAlignmentService, which also logs errors; here they are turned into user messages.
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
		} catch (Exception e) {
			throw toAuraException(e);
		}
	}

	/**
	 * @description GW-2706: Download URL of the running user's latest error file.
	 * @return Relative Salesforce Files download URL.
	 * @throws AuraHandledException When the user has not uploaded a file yet (no error file).
	 * @example
	 * String url = DistrictZoneAlignmentController.getErrorFileDownloadUrl();
	 */
	@AuraEnabled
	public static String getErrorFileDownloadUrl() {
		try {
			Id documentId = DistrictZoneAlignmentService.getErrorFileDocumentId();
			if (documentId == null) {
				throw PlatformUtilities.buildAuraException(Label.DZA_NoErrorFile);
			}
			return DistrictZoneAlignmentService.DOWNLOAD_URL_PREFIX + documentId;
		} catch (Exception e) {
			throw toAuraException(e);
		}
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
		} catch (Exception e) {
			throw toAuraException(e);
		}
	}

	/**
	 * @description User-facing messages (AuraHandledException) pass through; anything else (already logged by the
	 *              service) is shown as a generic message.
	 */
	private static AuraHandledException toAuraException(Exception e) {
		return e instanceof AuraHandledException
			? (AuraHandledException) e
			: PlatformUtilities.buildAuraException(Label.DZA_UnexpectedError);
	}
}