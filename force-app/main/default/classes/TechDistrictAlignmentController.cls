/**
 * @description GW-2707 - Aura entry point for Tech District Alignment (technician-to-district realignment).
 */
public with sharing class TechDistrictAlignmentController {
    @TestVisible
    private static Boolean throwTestException = false;

    /**
     * @description Ensures the template file exists in Salesforce Files and returns its download URL.
     * @return Relative Salesforce Files download URL.
     */
    @AuraEnabled
    public static String getTemplateDownloadUrl() {
        try {
            if (throwTestException) {
                throw buildAuraException('Unable to resolve the Tech District Alignment template.');
            }
            return TechDistrictAlignmentService.DOWNLOAD_URL_PREFIX + TechDistrictAlignmentService.ensureTemplateDocumentId();
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    /**
     * @description Returns the download URL of the running user's latest error file.
     * @return Relative Salesforce Files download URL.
     */
    @AuraEnabled
    public static String getErrorFileDownloadUrl() {
        try {
            if (throwTestException) {
                throw buildAuraException('Unable to resolve the Tech District Alignment error file.');
            }
            Id documentId = TechDistrictAlignmentService.errorFileDocumentId();
            if (documentId == null) {
                throw buildAuraException('No error file yet. Upload a file and click Start Upload first.');
            }
            return TechDistrictAlignmentService.DOWNLOAD_URL_PREFIX + documentId;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    /**
     * @description Processes an uploaded CSV/Excel file into territory, Territory Manager and Service Territory
     *              Member changes for the next fiscal year.
     * @param contentDocumentId Salesforce Files document Id from lightning-file-upload.
     * @return Counts, skip messages and the error file Id.
     */
    @AuraEnabled
    public static TechDistrictAlignmentService.ProcessResult processUpload(Id contentDocumentId) {
        try {
            if (throwTestException) {
                throw buildAuraException('Unable to process the Tech District Alignment file.');
            }
            return TechDistrictAlignmentService.processUpload(contentDocumentId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    private static AuraHandledException buildAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}