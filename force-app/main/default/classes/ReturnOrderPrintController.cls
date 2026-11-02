/**
 * @author Uptima Development Team
 * @date 2026-08-04
 * @description Retrieves the latest RO Form and Shipping Label attached to a Return Order.
 *              Converts the files to Base64 for use by the LWC.
 *              Checks whether either required document is missing.
 *              Returns the missing document names when applicable.
 *              Used to prepare Return Order documents for printing.
 */
public with sharing class ReturnOrderPrintController {
    
    private static final String FILE_TYPE_RO_FORM = 'RO Form';
    private static final String FILE_TYPE_SHIPPING_LABEL = 'Shipping Label';

    // Retrieves the required Return Order documents and returns them
    // to the LWC as Base64-encoded file data.
    @AuraEnabled(cacheable=false)
    public static PrintDocumentWrapper getPrintDocuments(Id returnOrderId) {

        // Find the latest RO Form and Shipping Label attached to the Return Order.
        Id roFormId = getLatestFile(returnOrderId, FILE_TYPE_RO_FORM);
        Id shippingLabelId = getLatestFile(returnOrderId, FILE_TYPE_SHIPPING_LABEL);

        // Keep track of any required documents that could not be found.
        List<String> missingDocuments = new List<String>();

        if (roFormId == null) {
            //missingDocuments.add('RO Form');
            missingDocuments.add(FILE_TYPE_RO_FORM);
        }

        if (shippingLabelId == null) {
            //missingDocuments.add('Shipping Label');
            missingDocuments.add(FILE_TYPE_SHIPPING_LABEL);
        }

        // If either required document is missing, return the list of
        // missing documents instead of attempting to retrieve file data.
        if (!missingDocuments.isEmpty()) {
            return new PrintDocumentWrapper(
                null,
                null,
                missingDocuments
            );
        }

        // Both documents were found, so retrieve their file contents
        // and convert them to Base64 for use by the LWC.
        return new PrintDocumentWrapper(
            getFileBase64(roFormId),
            getFileBase64(shippingLabelId),
            null
        );
    }

    /**
     * Finds the most recently created ContentVersion matching the
     * requested file name and linked to the specified Return Order.
     */
    private static Id getLatestFile(
        Id returnOrderId,
        String fileName
    ) {

        // A Return Order Id is required to find the related files.
        if (returnOrderId == null) {
            return null;
        }

        // Find all files linked to the Return Order through ContentDocumentLink.
        List<ContentDocumentLink> links =
            ContentDocumentLinksSelector.selectByLinkedEntityId(
                new Set<Id>{ returnOrderId }
            );

        // If no files are linked to the Return Order, there is nothing to search.
        if (links.isEmpty()) {
            return null;
        }

        // Store the ContentDocument Ids so we can search for their
        // corresponding ContentVersion records.
        Set<Id> documentIds = new Set<Id>();

        for (ContentDocumentLink link : links) {
            documentIds.add(link.ContentDocumentId);
        }

        // Find the most recently created version of a file whose title
        // contains the requested file name (for example, "RO Form").
        List<ContentVersion> files =
            ContentVersionsService.getLatestByContentDocumentIdsAndTitle(
                documentIds,
                fileName
            );

        // If no matching file was found, return null.
        if (files.isEmpty()) {
            return null;
        }

        // Return the ContentVersion Id of the most recently created file.
        return files[0].Id;
    }

    /**
     * Retrieves the file body from ContentVersion and converts it
     * to Base64 so the file can be passed from Apex to the LWC.
     */
    private static String getFileBase64(
        Id contentVersionId
    ) {

        // Retrieve the binary file data stored in VersionData.
        List<ContentVersion> versions =
            ContentVersionsService.getVersionDataById(contentVersionId);

        // Convert the binary file data into a Base64 string that
        // can be transferred and processed by the LWC.
        return EncodingUtil.base64Encode(
            versions[0].VersionData
        );
    }

    // Wrapper class used to return both document files and
    // any missing-document information to the LWC.
    public class PrintDocumentWrapper {

        // Base64-encoded RO Form returned to the LWC.
        @AuraEnabled
        public String roFormBase64 { get; set; }

        // Base64-encoded Shipping Label returned to the LWC.
        @AuraEnabled
        public String shippingLabelBase64 { get; set; }

        // Names of any required documents that could not be found.
        @AuraEnabled
        public List<String> missingDocuments { get; set; }

        // Initializes the wrapper with the document data
        // and any missing document information.
        public PrintDocumentWrapper(
            String roFormBase64,
            String shippingLabelBase64,
            List<String> missingDocuments
        ) {

            this.roFormBase64 =
                roFormBase64;

            this.shippingLabelBase64 =
                shippingLabelBase64;

            this.missingDocuments =
                missingDocuments;
        }
    }
}