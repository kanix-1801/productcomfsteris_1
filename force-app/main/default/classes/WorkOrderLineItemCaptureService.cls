/**
 * @description GW-1505 / GW-1506 — attaches microscope capture images to Work Order Line Item records as Files.
 * @author STERIS
 */
public with sharing class WorkOrderLineItemCaptureService {

    /**
     * @description User-facing validation errors. Prefer this over AuraHandledException when the
     * same Apex transaction will catch the exception — AuraHandledException.getMessage() often
     * returns only "Script-thrown exception" when caught in Apex.
     */
    public class CaptureUserFacingException extends Exception {
    }

    private static final Integer MAX_BASE64_LENGTH = 6000000;
    private static final Integer MAX_IMAGE_BYTES = 4500000;
    private static final Integer MAX_ANNOTATION_LOAD_BYTES = 900000;
    private static final String CONTENT_LINK_SHARE_TYPE_VIEWER = 'V';
    private static final String CONTENT_LINK_VISIBILITY_ALL_USERS = 'AllUsers';
    private static final String THUMBNAIL_RENDITION = 'THUMB120BY90';

    private static final Set<String> ANNOTATABLE_EXTENSIONS = new Set<String>{
        'png',
        'jpg',
        'jpeg',
        'gif',
        'webp'
    };

    private static final Set<String> ALLOWED_IMAGE_CATEGORIES = new Set<String>{
        'Beyond Repair',
        'Fixable'
    };

    private static final String BEYOND_REPAIR_CATEGORY = 'Beyond Repair';

    private static final Set<String> ALLOWED_BEYOND_REPAIR_REASONS = new Set<String>{
        'Pitting',
        'Shortening',
        'Unsafe for Continued Use',
        'Cracked in a Critical Area',
        'Cracked Box Lock',
        'Exceeded Useful Life'
    };

    /**
     * @description Result returned to LWC after a successful file attach.
     */
    public class MicroscopeCaptureResult {
        @AuraEnabled
        public Boolean success { get; set; }
        @AuraEnabled
        public String message { get; set; }
        @AuraEnabled
        public Id contentDocumentId { get; set; }
        @AuraEnabled
        public String fileName { get; set; }
    }

    /**
     * @description Summary row for an image file linked to a WOLI that can be opened in the annotator.
     */
    public class AnnotatableFileSummary {
        @AuraEnabled
        public Id contentDocumentId { get; set; }
        @AuraEnabled
        public String title { get; set; }
        @AuraEnabled
        public String fileExtension { get; set; }
        @AuraEnabled
        public Datetime createdDate { get; set; }
        @AuraEnabled
        public String category { get; set; }
        @AuraEnabled
        public String beyondRepairReason { get; set; }
        @AuraEnabled
        public Id contentVersionId { get; set; }
        @AuraEnabled
        public Integer contentSize { get; set; }
        @AuraEnabled
        public String ownerName { get; set; }
        @AuraEnabled
        public String thumbnailUrl { get; set; }
        @AuraEnabled
        public String imageDownloadUrl { get; set; }
    }

    /**
     * @description Image payload for Fabric.js annotation (data URL).
     */
    public class ImageFileForAnnotation {
        @AuraEnabled
        public Id contentDocumentId { get; set; }
        @AuraEnabled
        public String fileName { get; set; }
        @AuraEnabled
        public String base64DataUrl { get; set; }
        @AuraEnabled
        public String category { get; set; }
        @AuraEnabled
        public String beyondRepairReason { get; set; }
    }

    /**
     * @description GW-1505 / GW-1506 — Saves a microscope image onto the WOLI with an optional Category on ContentVersion.
     * @param workOrderLineItemId Parent WOLI Id from the record page
     * @param base64Image Base64-encoded image (optional data-URL prefix is stripped)
     * @param fileName Suggested file name (extension added when missing)
     * @param category Optional ContentVersion.Category__c (Beyond Repair or Fixable)
     * @param beyondRepairReason Optional ContentVersion.BeyondRepairReason__c when Category is Beyond Repair
     * @return Capture result for UI feedback
     */
    @AuraEnabled
    public static MicroscopeCaptureResult saveMicroscopeImage(
        Id workOrderLineItemId,
        String base64Image,
        String fileName,
        String category,
        String beyondRepairReason
    ) {
        try {
            String validationError = validateSaveInputs(workOrderLineItemId, base64Image, fileName);
            if (validationError != null) {
                return buildFailureResult(validationError);
            }
            String categoryError = validateImageCategory(category);
            if (categoryError != null) {
                return buildFailureResult(categoryError);
            }
            String beyondRepairReasonError = validateBeyondRepairReason(category, beyondRepairReason);
            if (beyondRepairReasonError != null) {
                return buildFailureResult(beyondRepairReasonError);
            }
            String securityError = resolveSecurityError();
            if (securityError != null) {
                return buildFailureResult(securityError);
            }

            WorkOrderLineItem lineItem = queryLineItem(workOrderLineItemId);
            if (lineItem == null) {
                return buildFailureResult('Work Order Line Item was not found.');
            }
            String resolvedFileName = resolveFileName(fileName, lineItem);
            Blob imageBlob = decodeBase64Image(base64Image);
            if (imageBlob == null) {
                return buildFailureResult('Image data is not valid base64.');
            }
            if (imageBlob.size() == 0) {
                return buildFailureResult('Image data is empty after decoding.');
            }
            if (imageBlob.size() > MAX_IMAGE_BYTES) {
                return buildFailureResult(
                    'Image is too large to attach. Capture at a lower resolution and try again.'
                );
            }

            return insertImageOnLineItem(
                workOrderLineItemId,
                imageBlob,
                resolvedFileName,
                category,
                beyondRepairReason
            );
        } catch (CaptureUserFacingException e) {
            Logger.error('WorkOrderLineItemCaptureService.saveMicroscopeImage validation', e);
            return buildFailureResult(e.getMessage());
        } catch (DmlException e) {
            Logger.error('WorkOrderLineItemCaptureService.saveMicroscopeImage DML', e);
            return buildFailureResult(resolveDmlMessage(e));
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemCaptureService.saveMicroscopeImage failed', e);
            String detail = e.getMessage();
            return buildFailureResult(
                String.isNotBlank(detail)
                    ? detail
                    : 'Could not attach microscope image. Please try again or contact support.'
            );
        } finally {
            flushLogger();
        }
    }

    /**
     * @description GW-1505 / GW-1506 — Links an uploaded file version to a WOLI after REST multipart upload from LWC.
     * @param workOrderLineItemId Parent WOLI Id
     * @param contentVersionId Id returned from ContentVersion REST insert
     * @return Capture result for UI feedback
     */
    @AuraEnabled
    public static MicroscopeCaptureResult linkContentDocumentFromVersion(
        Id workOrderLineItemId,
        Id contentVersionId
    ) {
        try {
            if (workOrderLineItemId == null) {
                return buildFailureResult('Work Order Line Item Id is required.');
            }
            if (contentVersionId == null) {
                return buildFailureResult('Content Version Id is required.');
            }
            String securityError = resolveSecurityError();
            if (securityError != null) {
                return buildFailureResult(securityError);
            }
            if (queryLineItem(workOrderLineItemId) == null) {
                return buildFailureResult('Work Order Line Item was not found.');
            }

            List<ContentVersion> versions = [
                SELECT ContentDocumentId, Title, PathOnClient
                FROM ContentVersion
                WHERE Id = :contentVersionId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (versions.isEmpty() || versions[0].ContentDocumentId == null) {
                return buildFailureResult('Uploaded file version was not found.');
            }

            ContentVersion version = versions[0];
            linkContentDocumentToLineItem(workOrderLineItemId, version.ContentDocumentId);

            MicroscopeCaptureResult result = new MicroscopeCaptureResult();
            result.success = true;
            result.contentDocumentId = version.ContentDocumentId;
            result.fileName = String.isNotBlank(version.PathOnClient)
                ? version.PathOnClient
                : version.Title;
            result.message = 'Image attached to Work Order Line Item.';
            return result;
        } catch (AuraHandledException e) {
            Logger.error('WorkOrderLineItemCaptureService.linkContentDocumentFromVersion validation', e);
            return buildFailureResult(e.getMessage());
        } catch (DmlException e) {
            Logger.error('WorkOrderLineItemCaptureService.linkContentDocumentFromVersion DML', e);
            return buildFailureResult(resolveDmlMessage(e));
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemCaptureService.linkContentDocumentFromVersion failed', e);
            return buildFailureResult('Could not link the uploaded file to this Work Order Line Item.');
        } finally {
            flushLogger();
        }
    }

    /**
     * @description GW-1506 — Returns the Apex request session Id (mobile troubleshooting only). This Id is not valid
     * as a REST Bearer token on Field Service mobile (HTTP 401 Session expired or invalid). LWC REST calls must use
     * credentials:include.
     * @return Active user session Id for the current Apex request
     */
    @AuraEnabled
    public static String getRestSessionId() {
        return UserInfo.getSessionId();
    }

    /**
     * @description GW-1506 — Permission and access checks for troubleshooting mobile upload failures.
     * @param workOrderLineItemId WOLI context (optional)
     * @return Multi-line diagnostic summary
     */
    @AuraEnabled
    public static String diagnoseMicroscopeCaptureAccess(Id workOrderLineItemId) {
        List<String> lines = new List<String>();
        lines.add('WorkOrderLineItem read: ' + WorkOrderLineItem.SObjectType.getDescribe().isAccessible());
        lines.add('WorkOrderLineItem edit: ' + WorkOrderLineItem.SObjectType.getDescribe().isUpdateable());
        lines.add('ContentVersion create: ' + ContentVersion.SObjectType.getDescribe().isCreateable());
        lines.add('ContentDocumentLink create: ' + ContentDocumentLink.SObjectType.getDescribe().isCreateable());
        if (workOrderLineItemId != null) {
            List<WorkOrderLineItem> rows = [
                SELECT Id
                FROM WorkOrderLineItem
                WHERE Id = :workOrderLineItemId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            lines.add('WOLI record visible: ' + !rows.isEmpty());
        }
        return String.join(lines, '\n');
    }

    /**
     * @description GW-1505 — Updates Category__c on the latest ContentVersion for an image on the WOLI.
     * @param workOrderLineItemId Parent WOLI Id
     * @param contentDocumentId ContentDocument to categorize
     * @param category Picklist value, or blank to clear
     * @param beyondRepairReason Beyond Repair Reason when Category is Beyond Repair
     * @return Result for UI feedback
     */
    @AuraEnabled
    public static MicroscopeCaptureResult updateMicroscopeImageCategory(
        Id workOrderLineItemId,
        Id contentDocumentId,
        String category,
        String beyondRepairReason
    ) {
        try {
            if (workOrderLineItemId == null) {
                return buildFailureResult('Work Order Line Item Id is required.');
            }
            if (contentDocumentId == null) {
                return buildFailureResult('File selection is required.');
            }
            String categoryError = validateImageCategory(category);
            if (categoryError != null) {
                return buildFailureResult(categoryError);
            }
            String beyondRepairReasonError = validateBeyondRepairReason(category, beyondRepairReason);
            if (beyondRepairReasonError != null) {
                return buildFailureResult(beyondRepairReasonError);
            }
            String securityError = resolveCategoryUpdateSecurityError();
            if (securityError != null) {
                return buildFailureResult(securityError);
            }
            assertFileLinkedToLineItem(workOrderLineItemId, contentDocumentId);

            List<ContentVersion> versions = [
                SELECT Id, Title, PathOnClient, Category__c, BeyondRepairReason__c
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (versions.isEmpty()) {
                return buildFailureResult('File version was not found.');
            }

            ContentVersion version = versions[0];
            version.Category__c = String.isBlank(category) ? null : category.trim();
            version.BeyondRepairReason__c = resolveStoredBeyondRepairReason(category, beyondRepairReason);
            update version;

            MicroscopeCaptureResult result = new MicroscopeCaptureResult();
            result.success = true;
            result.contentDocumentId = contentDocumentId;
            result.fileName = String.isNotBlank(version.PathOnClient)
                ? version.PathOnClient
                : version.Title;
            result.message = String.isBlank(category)
                ? 'Category cleared.'
                : 'Category saved.';
            return result;
        } catch (AuraHandledException e) {
            Logger.error('WorkOrderLineItemCaptureService.updateMicroscopeImageCategory validation', e);
            return buildFailureResult(e.getMessage());
        } catch (DmlException e) {
            Logger.error('WorkOrderLineItemCaptureService.updateMicroscopeImageCategory DML', e);
            return buildFailureResult(resolveDmlMessage(e));
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemCaptureService.updateMicroscopeImageCategory failed', e);
            return buildFailureResult('Could not update the image category.');
        } finally {
            flushLogger();
        }
    }

    /**
     * @description GW-1505 / GW-1506 — Removes a file from the WOLI and deletes the ContentDocument when unlinked.
     * @param workOrderLineItemId Parent WOLI Id
     * @param contentDocumentId ContentDocument to delete
     * @return Result for UI feedback
     */
    @AuraEnabled
    public static MicroscopeCaptureResult deleteMicroscopeImageFile(
        Id workOrderLineItemId,
        Id contentDocumentId
    ) {
        try {
            if (workOrderLineItemId == null) {
                return buildFailureResult('Work Order Line Item Id is required.');
            }
            if (contentDocumentId == null) {
                return buildFailureResult('File selection is required.');
            }
            String securityError = resolveDeleteSecurityError();
            if (securityError != null) {
                return buildFailureResult(securityError);
            }
            assertFileLinkedToLineItem(workOrderLineItemId, contentDocumentId);

            List<ContentDocumentLink> links = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :workOrderLineItemId AND ContentDocumentId = :contentDocumentId
                WITH SECURITY_ENFORCED
            ];
            if (links.isEmpty()) {
                return buildFailureResult('The selected file is not attached to this Work Order Line Item.');
            }

            delete links;

            List<ContentDocumentLink> remainingLinks = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :contentDocumentId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (remainingLinks.isEmpty()) {
                delete [SELECT Id FROM ContentDocument WHERE Id = :contentDocumentId WITH SECURITY_ENFORCED];
            }

            MicroscopeCaptureResult result = new MicroscopeCaptureResult();
            result.success = true;
            result.contentDocumentId = contentDocumentId;
            result.message = 'File deleted.';
            return result;
        } catch (AuraHandledException e) {
            Logger.error('WorkOrderLineItemCaptureService.deleteMicroscopeImageFile validation', e);
            return buildFailureResult(e.getMessage());
        } catch (DmlException e) {
            Logger.error('WorkOrderLineItemCaptureService.deleteMicroscopeImageFile DML', e);
            return buildFailureResult(resolveDmlMessage(e));
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemCaptureService.deleteMicroscopeImageFile failed', e);
            return buildFailureResult('Could not delete the selected file.');
        } finally {
            flushLogger();
        }
    }

    /**
     * @description GW-1505 — Lists all files linked to the WOLI with latest ContentVersion Category.
     * @param workOrderLineItemId WOLI record Id from the Lightning page
     * @return Files newest first (empty when none or input invalid)
     */
    @AuraEnabled
    public static List<AnnotatableFileSummary> listWorkOrderLineItemFiles(Id workOrderLineItemId) {
        return listLinkedFileSummaries(workOrderLineItemId, false);
    }

    /**
     * @description GW-1505 — Returns a Salesforce file thumbnail URL for the WOLI file list.
     * Uses the same-origin renditionDownload servlet URL used by standard Files thumbnails.
     * @param workOrderLineItemId Parent WOLI Id from the Lightning page
     * @param contentDocumentId Linked ContentDocument Id
     * @return thumbnail URL, or null when the file is not a supported image
     */
    @AuraEnabled
    public static String getImageThumbnailDataUrl(Id workOrderLineItemId, Id contentDocumentId) {
        try {
            if (workOrderLineItemId == null || contentDocumentId == null) {
                return null;
            }
            enforceReadSecurity();
            assertFileLinkedToLineItem(workOrderLineItemId, contentDocumentId);

            List<ContentVersion> versions = [
                SELECT ContentDocumentId, FileExtension, Id
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (versions.isEmpty()) {
                return null;
            }

            return resolveThumbnailUrl(versions[0], versions[0].FileExtension);
        } catch (AuraHandledException e) {
            Logger.error('WorkOrderLineItemCaptureService.getImageThumbnailDataUrl validation', e);
            return null;
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemCaptureService.getImageThumbnailDataUrl failed', e);
            return null;
        } finally {
            flushLogger();
        }
    }

    /**
     * @description GW-1505 — Batch thumbnail URL lookup for the WOLI file list.
     * @param workOrderLineItemId Parent WOLI Id from the Lightning page
     * @param contentDocumentIds Linked ContentDocument Ids to resolve
     * @return Map of ContentDocument Id to thumbnail URL
     */
    @AuraEnabled
    public static Map<String, String> getImageThumbnailDataUrls(
        Id workOrderLineItemId,
        List<Id> contentDocumentIds
    ) {
        Map<String, String> thumbnailsByDocumentId = new Map<String, String>();
        if (workOrderLineItemId == null || contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return thumbnailsByDocumentId;
        }

        Set<Id> uniqueDocumentIds = new Set<Id>(contentDocumentIds);
        for (Id contentDocumentId : uniqueDocumentIds) {
            if (contentDocumentId == null) {
                continue;
            }
            String thumbnailUrl = getImageThumbnailDataUrl(workOrderLineItemId, contentDocumentId);
            if (String.isNotBlank(thumbnailUrl)) {
                thumbnailsByDocumentId.put(String.valueOf(contentDocumentId), thumbnailUrl);
            }
        }
        return thumbnailsByDocumentId;
    }

    /**
     * @description GW-1505 / GW-1506 — Lists image files on the WOLI that can be opened in the annotator.
     * @param workOrderLineItemId WOLI record Id from the Lightning page
     * @return Image files newest first (empty when none or input invalid)
     */
    @AuraEnabled
    public static List<AnnotatableFileSummary> listAnnotatableImageFiles(Id workOrderLineItemId) {
        return listLinkedFileSummaries(workOrderLineItemId, true);
    }

    private static List<AnnotatableFileSummary> listLinkedFileSummaries(
        Id workOrderLineItemId,
        Boolean imagesOnly
    ) {
        try {
            if (workOrderLineItemId == null) {
                return new List<AnnotatableFileSummary>();
            }
            enforceReadSecurity();

            List<ContentDocumentLink> links = [
                SELECT
                    ContentDocumentId,
                    ContentDocument.Title,
                    ContentDocument.FileExtension,
                    ContentDocument.CreatedDate,
                    ContentDocument.Owner.Name
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :workOrderLineItemId
                WITH SECURITY_ENFORCED
                ORDER BY ContentDocument.CreatedDate DESC
            ];

            Set<Id> documentIds = new Set<Id>();
            for (ContentDocumentLink link : links) {
                if (!imagesOnly || isAnnotatableExtension(link.ContentDocument.FileExtension)) {
                    documentIds.add(link.ContentDocumentId);
                }
            }

            Map<Id, ContentVersion> latestVersionByDocumentId =
                loadLatestVersionsByDocumentId(documentIds);

            List<AnnotatableFileSummary> summaries = new List<AnnotatableFileSummary>();
            for (ContentDocumentLink link : links) {
                if (imagesOnly && !isAnnotatableExtension(link.ContentDocument.FileExtension)) {
                    continue;
                }
                ContentVersion latestVersion = latestVersionByDocumentId.get(link.ContentDocumentId);
                AnnotatableFileSummary summary = new AnnotatableFileSummary();
                summary.contentDocumentId = link.ContentDocumentId;
                summary.title = link.ContentDocument.Title;
                summary.fileExtension = normalizeExtension(link.ContentDocument.FileExtension);
                summary.createdDate = link.ContentDocument.CreatedDate;
                summary.ownerName = link.ContentDocument.Owner.Name;
                if (latestVersion != null) {
                    summary.contentVersionId = latestVersion.Id;
                    summary.category = latestVersion.Category__c;
                    summary.beyondRepairReason = latestVersion.BeyondRepairReason__c;
                    summary.contentSize = latestVersion.ContentSize;
                    summary.thumbnailUrl = resolveThumbnailUrl(latestVersion, summary.fileExtension);
                    summary.imageDownloadUrl = resolveImageDownloadUrl(latestVersion, summary.fileExtension);
                }
                summaries.add(summary);
            }
            return summaries;
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemCaptureService.listLinkedFileSummaries failed', e);
            return new List<AnnotatableFileSummary>();
        } finally {
            flushLogger();
        }
    }

    /**
     * @description GW-1505 / GW-1506 — Returns an image file on the WOLI as a base64 data URL for Fabric.js.
     * @param workOrderLineItemId WOLI that must own the file link
     * @param contentDocumentId ContentDocument to annotate
     * @return Data URL and file metadata for the annotator
     */
    @AuraEnabled
    public static ImageFileForAnnotation getImageFileForAnnotation(
        Id workOrderLineItemId,
        Id contentDocumentId
    ) {
        try {
            if (workOrderLineItemId == null) {
                throw new AuraHandledException('Work Order Line Item Id is required.');
            }
            if (contentDocumentId == null) {
                throw new AuraHandledException('File selection is required.');
            }
            enforceReadSecurity();
            assertFileLinkedToLineItem(workOrderLineItemId, contentDocumentId);

            List<ContentVersion> versions = [
                SELECT Title, FileExtension, FileType, VersionData, ContentSize, Category__c, BeyondRepairReason__c
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (versions.isEmpty()) {
                throw new AuraHandledException('File version was not found.');
            }

            ContentVersion version = versions[0];
            if (!isAnnotatableExtension(version.FileExtension)) {
                throw new AuraHandledException('Only PNG, JPEG, GIF, or WebP images can be annotated.');
            }

            Integer contentSize = version.ContentSize != null
                ? version.ContentSize
                : (version.VersionData == null ? 0 : version.VersionData.size());
            if (contentSize > MAX_ANNOTATION_LOAD_BYTES) {
                throw new AuraHandledException(
                    'Image is too large to open in the mobile annotator. Attach a smaller image or annotate before upload.'
                );
            }

            ImageFileForAnnotation payload = new ImageFileForAnnotation();
            payload.contentDocumentId = contentDocumentId;
            payload.fileName = version.Title;
            payload.category = version.Category__c;
            payload.beyondRepairReason = version.BeyondRepairReason__c;
            String mimeType = resolveMimeType(version.FileType, version.FileExtension);
            String encodedBody = EncodingUtil.base64Encode(version.VersionData);
            payload.base64DataUrl = 'data:' + mimeType + ';base64,' + encodedBody;
            return payload;
        } catch (AuraHandledException e) {
            Logger.error('WorkOrderLineItemCaptureService.getImageFileForAnnotation validation', e);
            throw e;
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemCaptureService.getImageFileForAnnotation failed', e);
            throw new AuraHandledException('Could not load the selected file for annotation.');
        } finally {
            flushLogger();
        }
    }

    private static String validateSaveInputs(Id workOrderLineItemId, String base64Image, String fileName) {
        if (workOrderLineItemId == null) {
            return 'Work Order Line Item Id is required.';
        }
        if (String.isBlank(base64Image)) {
            return 'Image data is required.';
        }
        if (base64Image.length() > MAX_BASE64_LENGTH) {
            return 'Image is too large. Capture at a lower resolution and try again.';
        }
        if (String.isBlank(fileName)) {
            return 'File name is required.';
        }
        return null;
    }

    private static String resolveSecurityError() {
        String readError = resolveReadSecurityError();
        if (readError != null) {
            return readError;
        }
        if (!WorkOrderLineItem.SObjectType.getDescribe().isUpdateable()) {
            return 'You need Edit access on Work Order Line Items to attach files. Assign Microscope Capture User or ask your admin.';
        }
        if (!ContentVersion.SObjectType.getDescribe().isCreateable()) {
            return 'You do not have permission to upload files.';
        }
        if (!ContentDocumentLink.SObjectType.getDescribe().isCreateable()) {
            return 'You do not have permission to link files to records.';
        }
        return null;
    }

    private static String resolveCategoryUpdateSecurityError() {
        String readError = resolveReadSecurityError();
        if (readError != null) {
            return readError;
        }
        if (!ContentVersion.SObjectType.getDescribe().isUpdateable()) {
            return 'You do not have permission to update files.';
        }
        if (!Schema.sObjectType.ContentVersion.fields.Category__c.isUpdateable()) {
            return 'You do not have permission to update the Category field on files.';
        }
        if (!Schema.sObjectType.ContentVersion.fields.BeyondRepairReason__c.isUpdateable()) {
            return 'You do not have permission to update the Beyond Repair Reason field on files.';
        }
        return null;
    }

    private static String resolveDeleteSecurityError() {
        String readError = resolveReadSecurityError();
        if (readError != null) {
            return readError;
        }
        if (!ContentDocumentLink.SObjectType.getDescribe().isDeletable()) {
            return 'You do not have permission to remove files from records.';
        }
        if (!ContentDocument.SObjectType.getDescribe().isDeletable()) {
            return 'You do not have permission to delete files.';
        }
        return null;
    }

    private static String validateImageCategory(String category) {
        if (String.isBlank(category)) {
            return null;
        }
        if (!ALLOWED_IMAGE_CATEGORIES.contains(category.trim())) {
            return 'Category must be Beyond Repair or Fixable.';
        }
        return null;
    }

    private static String validateBeyondRepairReason(String category, String beyondRepairReason) {
        String normalizedCategory = String.isBlank(category) ? null : category.trim();
        String normalizedReason = String.isBlank(beyondRepairReason) ? null : beyondRepairReason.trim();

        if (BEYOND_REPAIR_CATEGORY.equals(normalizedCategory)) {
            if (normalizedReason == null) {
                return 'Beyond Repair Reason is required when Category is Beyond Repair.';
            }
            if (!ALLOWED_BEYOND_REPAIR_REASONS.contains(normalizedReason)) {
                return 'Beyond Repair Reason is not valid for the selected Category.';
            }
            return null;
        }

        if (normalizedReason != null) {
            return 'Beyond Repair Reason can only be set when Category is Beyond Repair.';
        }
        return null;
    }

    private static String resolveStoredBeyondRepairReason(String category, String beyondRepairReason) {
        String normalizedCategory = String.isBlank(category) ? null : category.trim();
        if (!BEYOND_REPAIR_CATEGORY.equals(normalizedCategory)) {
            return null;
        }
        return String.isBlank(beyondRepairReason) ? null : beyondRepairReason.trim();
    }

    private static String resolveThumbnailUrl(ContentVersion version, String fileExtension) {
        if (version == null || !isAnnotatableExtension(fileExtension)) {
            return null;
        }
        return buildOrgDomainUrl(
            '/sfc/servlet.shepherd/version/renditionDownload?rendition=' +
            THUMBNAIL_RENDITION +
            '&versionId=' +
            version.Id +
            '&operationContext=CHATTER&contentId=' +
            version.ContentDocumentId
        );
    }

    private static String resolveImageDownloadUrl(ContentVersion version, String fileExtension) {
        if (version == null || !isAnnotatableExtension(fileExtension)) {
            return null;
        }
        return buildOrgDomainUrl('/sfc/servlet.shepherd/version/download/' + version.Id);
    }

    private static String buildOrgDomainUrl(String path) {
        if (String.isBlank(path)) {
            return null;
        }
        String normalizedPath = path.startsWith('/') ? path : '/' + path;
        if (Test.isRunningTest()) {
            return normalizedPath;
        }
        return URL.getOrgDomainUrl().toExternalForm() + normalizedPath;
    }

    private static Map<Id, ContentVersion> loadLatestVersionsByDocumentId(Set<Id> contentDocumentIds) {
        Map<Id, ContentVersion> versionByDocumentId = new Map<Id, ContentVersion>();
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return versionByDocumentId;
        }
        for (ContentVersion version : [
            SELECT ContentDocumentId, Category__c, BeyondRepairReason__c, FileExtension, Id, ContentSize
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds AND IsLatest = true
            WITH SECURITY_ENFORCED
        ]) {
            versionByDocumentId.put(version.ContentDocumentId, version);
        }
        return versionByDocumentId;
    }

    private static void flushLogger() {
        try {
            Logger.saveLog();
        } catch (Exception logError) {
            // Do not fail the user transaction when Nebula Logger persistence is unavailable.
        }
    }

    private static String resolveReadSecurityError() {
        if (!WorkOrderLineItem.SObjectType.getDescribe().isAccessible()) {
            return 'You do not have access to Work Order Line Items.';
        }
        if (!ContentDocument.SObjectType.getDescribe().isAccessible()) {
            return 'You do not have access to files.';
        }
        if (!ContentVersion.SObjectType.getDescribe().isAccessible()) {
            return 'You do not have access to file versions.';
        }
        return null;
    }

    private static void enforceReadSecurity() {
        String readError = resolveReadSecurityError();
        if (readError != null) {
            throwAuraUserMessage(readError);
        }
    }

    private static void assertFileLinkedToLineItem(Id workOrderLineItemId, Id contentDocumentId) {
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :workOrderLineItemId AND ContentDocumentId = :contentDocumentId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (links.isEmpty()) {
            throw new AuraHandledException('The selected file is not attached to this Work Order Line Item.');
        }
    }

    private static Boolean isAnnotatableExtension(String fileExtension) {
        return !String.isBlank(fileExtension)
            && ANNOTATABLE_EXTENSIONS.contains(fileExtension.trim().toLowerCase());
    }

    private static String normalizeExtension(String fileExtension) {
        return String.isBlank(fileExtension) ? '' : fileExtension.trim().toLowerCase();
    }

    private static String resolveMimeType(String fileType, String fileExtension) {
        String extension = normalizeExtension(fileExtension);
        if (extension == 'png') {
            return 'image/png';
        }
        if (extension == 'jpg' || extension == 'jpeg') {
            return 'image/jpeg';
        }
        if (extension == 'gif') {
            return 'image/gif';
        }
        if (extension == 'webp') {
            return 'image/webp';
        }
        if (!String.isBlank(fileType) && fileType.contains('/')) {
            return fileType.toLowerCase();
        }
        return 'image/png';
    }

    private static WorkOrderLineItem queryLineItem(Id workOrderLineItemId) {
        List<WorkOrderLineItem> rows = [
            SELECT Id, LineItemNumber
            FROM WorkOrderLineItem
            WHERE Id = :workOrderLineItemId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Inserts the file, then links it to the WOLI via ContentDocumentLink (no FirstPublishLocationId).
     */
    private static MicroscopeCaptureResult insertImageOnLineItem(
        Id workOrderLineItemId,
        Blob imageBlob,
        String resolvedFileName,
        String category,
        String beyondRepairReason
    ) {
        ContentVersion version = new ContentVersion();
        version.Title = resolvedFileName;
        version.PathOnClient = resolvedFileName;
        version.VersionData = imageBlob;
        if (String.isNotBlank(category)) {
            version.Category__c = category.trim();
        }
        version.BeyondRepairReason__c = resolveStoredBeyondRepairReason(category, beyondRepairReason);
        insert version;

        version = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (version.ContentDocumentId == null) {
            return buildFailureResult(
                'File was created but could not be linked to the Work Order Line Item.'
            );
        }

        linkContentDocumentToLineItem(workOrderLineItemId, version.ContentDocumentId);

        MicroscopeCaptureResult result = new MicroscopeCaptureResult();
        result.success = true;
        result.contentDocumentId = version.ContentDocumentId;
        result.fileName = resolvedFileName;
        result.message = 'Image attached to Work Order Line Item.';
        Logger.info(
            new LogMessage(
                'Microscope image attached to WOLI {0} as {1}',
                workOrderLineItemId,
                resolvedFileName
            )
        );
        return result;
    }

    private static void linkContentDocumentToLineItem(Id workOrderLineItemId, Id contentDocumentId) {
        List<ContentDocumentLink> existingLinks = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE
                LinkedEntityId = :workOrderLineItemId
                AND ContentDocumentId = :contentDocumentId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!existingLinks.isEmpty()) {
            return;
        }

        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = workOrderLineItemId,
            ShareType = CONTENT_LINK_SHARE_TYPE_VIEWER,
            Visibility = CONTENT_LINK_VISIBILITY_ALL_USERS
        );
    }

    private static void throwAuraUserMessage(String message) {
        throw new AuraHandledException(
            String.isNotBlank(message) ? message : 'Could not complete the microscope image upload.'
        );
    }

    private static String resolveFileName(String fileName, WorkOrderLineItem lineItem) {
        String trimmed = fileName.trim();
        String sanitized = trimmed.replaceAll('[^a-zA-Z0-9._-]', '_');
        if (String.isBlank(sanitized)) {
            sanitized = 'Microscope_Capture';
        }
        if (!hasAllowedImageExtension(sanitized.toLowerCase())) {
            sanitized += '.jpg';
        }
        if (sanitized.length() > 200) {
            Integer extensionIndex = sanitized.lastIndexOf('.');
            String extension = extensionIndex > -1 ? sanitized.substring(extensionIndex) : '.jpg';
            Integer baseLength = 200 - extension.length();
            if (baseLength < 1) {
                baseLength = 1;
            }
            sanitized = sanitized.substring(0, baseLength) + extension;
        }
        return sanitized;
    }

    private static Boolean hasAllowedImageExtension(String lowerFileName) {
        return lowerFileName.endsWith('.png')
            || lowerFileName.endsWith('.jpg')
            || lowerFileName.endsWith('.jpeg')
            || lowerFileName.endsWith('.gif')
            || lowerFileName.endsWith('.webp');
    }

    private static MicroscopeCaptureResult buildFailureResult(String message) {
        MicroscopeCaptureResult result = new MicroscopeCaptureResult();
        result.success = false;
        result.message = String.isNotBlank(message)
            ? message
            : 'Could not attach microscope image.';
        return result;
    }

    private static String resolveDmlMessage(DmlException e) {
        if (e == null) {
            return 'Could not attach microscope image.';
        }
        if (e.getNumDml() > 0 && String.isNotBlank(e.getDmlMessage(0))) {
            return e.getDmlMessage(0);
        }
        return String.isNotBlank(e.getMessage())
            ? e.getMessage()
            : 'Could not attach microscope image.';
    }

    private static Blob decodeBase64Image(String base64Image) {
        String payload = base64Image.trim();
        Integer commaIndex = payload.indexOf(',');
        if (commaIndex > -1) {
            payload = payload.substring(commaIndex + 1);
        }
        try {
            return EncodingUtil.base64Decode(payload);
        } catch (Exception e) {
            return null;
        }
    }
}