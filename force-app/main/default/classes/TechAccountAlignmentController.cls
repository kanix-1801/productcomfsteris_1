/**
 * @description GW-2710 - Aura entry point for Tech Account Alignment mass technician assignment.
 */
public with sharing class TechAccountAlignmentController {
    /**
     * @description Ensures the template file exists in Salesforce Files and returns its download URL.
     * @return Relative Salesforce Files download URL.
     */
    @AuraEnabled
    public static String getTemplateDownloadUrl() {
        Id documentId = TechAccountAlignmentService.ensureTemplateDocumentId();
        return '/sfc/servlet.shepherd/document/download/' + documentId;
    }

    /**
     * @description Processes an uploaded CSV/Excel file into AddressResourcePreference records.
     * @param contentDocumentId Salesforce Files document Id from lightning-file-upload.
     * @return Counts and skip messages for the processed file.
     */
    @AuraEnabled
    public static TechAccountAlignmentService.ProcessResult processUpload(Id contentDocumentId) {
        return TechAccountAlignmentService.processUpload(contentDocumentId);
    }
}