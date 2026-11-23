/**
 * @author Sagar Anand
 * @date 2026-11-05
 * @description GW-2707: Aura entry point for the techDistrictAlignment LWC (technician-to-district realignment).
 *              Relays requests to TechDistrictAlignmentService; errors are handled (and logged) here only.
 * @group Field Service
 * @see TechDistrictAlignmentService
 */
public with sharing class TechDistrictAlignmentController {
	/**
	 * @description Ensures the template file exists in Salesforce Files and returns its download URL.
	 * @return Relative Salesforce Files download URL.
	 * @throws AuraHandledException When the template cannot be resolved.
	 */
	@AuraEnabled
	public static String getTemplateDownloadUrl() {
		try {
			Id documentId = TechDistrictAlignmentService.ensureTemplateDocumentId();
			return TechDistrictAlignmentService.DOWNLOAD_URL_PREFIX + documentId;
		} catch (Exception e) {
			throw toAuraException(e);
		}
	}

	/**
	 * @description Returns the download URL of the running user's latest error file.
	 * @return Relative Salesforce Files download URL.
	 * @throws AuraHandledException When the user has no error file yet.
	 */
	@AuraEnabled
	public static String getErrorFileDownloadUrl() {
		try {
			Id documentId = TechDistrictAlignmentService.errorFileDocumentId();
			if (documentId == null) {
				throw PlatformUtilities.buildAuraException(Label.TDA_NoErrorFile);
			}
			return TechDistrictAlignmentService.DOWNLOAD_URL_PREFIX + documentId;
		} catch (Exception e) {
			throw toAuraException(e);
		}
	}

	/**
	 * @description Processes an uploaded Excel file into territory, Territory Manager and Service Territory
	 *              Member changes for the next fiscal year.
	 * @param contentDocumentId Salesforce Files document Id from lightning-file-upload.
	 * @return Counts, skip messages and the error file Id.
	 * @throws AuraHandledException When the file cannot be processed.
	 */
	@AuraEnabled
	public static TechDistrictAlignmentService.ProcessResult processUpload(Id contentDocumentId) {
		try {
			return TechDistrictAlignmentService.processUpload(contentDocumentId);
		} catch (Exception e) {
			throw toAuraException(e);
		}
	}

	/**
	 * @description User-facing messages (AuraHandledException) pass through; anything else is logged first.
	 */
	private static AuraHandledException toAuraException(Exception e) {
		if (e instanceof AuraHandledException) {
			return (AuraHandledException) e;
		}
		Logger.error('Tech District Alignment failed', e).addTags(TechDistrictAlignmentService.LOG_TAGS);
		Logger.saveLog();
		return PlatformUtilities.buildAuraException(PlatformUtilities.resolveExceptionMessage(e));
	}
}