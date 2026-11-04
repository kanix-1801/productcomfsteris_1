/**
 * @description GW-2706 - Aura entry point for District Zone Alignment (district to zone territory assignment).
 */
public with sharing class DistrictZoneAlignmentController {
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
                throw buildAuraException('Unable to resolve the District Zone Alignment template.');
            }
            return DistrictZoneAlignmentService.DOWNLOAD_URL_PREFIX + DistrictZoneAlignmentService.ensureTemplateDocumentId();
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
                throw buildAuraException('Unable to resolve the District Zone Alignment error file.');
            }
            Id documentId = DistrictZoneAlignmentService.errorFileDocumentId();
            if (documentId == null) {
                throw buildAuraException('No error file yet. Upload a file and click Start Upload first.');
            }
            return DistrictZoneAlignmentService.DOWNLOAD_URL_PREFIX + documentId;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    /**
     * @description Processes an uploaded CSV/Excel file into district Service Territory creates and updates.
     * @param contentDocumentId Salesforce Files document Id from lightning-file-upload.
     * @return Counts, skip messages and the error file Id.
     */
    @AuraEnabled
    public static DistrictZoneAlignmentService.ProcessResult processUpload(Id contentDocumentId) {
        try {
            if (throwTestException) {
                throw buildAuraException('Unable to process the District Zone Alignment file.');
            }
            return DistrictZoneAlignmentService.processUpload(contentDocumentId);
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