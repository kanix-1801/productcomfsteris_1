/**
 * @description GW-2710 - Aura entry point for Tech Account Alignment mass technician assignment.
 */
public with sharing class TechAccountAlignmentController {
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
                throw buildAuraException('Unable to resolve the Tech Account Alignment template.');
            }
            Id documentId = TechAccountAlignmentService.ensureTemplateDocumentId();
            return '/sfc/servlet.shepherd/document/download/' + documentId;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    /**
     * @description Processes an uploaded CSV/Excel file into AddressResourcePreference records.
     * @param contentDocumentId Salesforce Files document Id from lightning-file-upload.
     * @return Counts and skip messages for the processed file.
     */
    @AuraEnabled
    public static TechAccountAlignmentService.ProcessResult processUpload(Id contentDocumentId) {
        try {
            if (throwTestException) {
                throw buildAuraException('Unable to process the Tech Account Alignment file.');
            }
            return TechAccountAlignmentService.processUpload(contentDocumentId);
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