/**
 * @author Sagar Anand
 * @date 2026-10-19
 * @group Field Service Mobile
 * @description GW-359 — Aura controller for the woliPhotoCapture LWC (Field Service mobile).
 *              Serves the two online-only reads behind "Annotate existing file".
 *              Reusable file access goes through the existing ContentDocumentLinksService and
 *              ContentVersionsService methods (unchanged). Logic specific to this component stays here:
 *              which file types can be annotated, the size limit, sort order, building the data URL, and
 *              reading the file body (VersionData), which no existing service returns (read through
 *              SoqlQueryBuilder, USER_MODE). Photo capture itself is saved through LDS, not Apex.
 * @see ContentDocumentLinksService
 * @see ContentVersionsService
 * @see SoqlQueryBuilder
 */
public with sharing class WoliMicroscopeCaptureMobileCtrl {
    @TestVisible
    private static final String LOG_SCENARIO = 'WOLI Photo Capture';
    @TestVisible
    private static final String ERROR_LIST_FILES = 'Unable to load the image files on this Work Order Line Item.';
    @TestVisible
    private static final String ERROR_LOAD_FILE = 'Unable to load the selected file for annotation.';
    @TestVisible
    private static final String ERROR_IDS_REQUIRED = 'Work Order Line Item and file are required.';
    @TestVisible
    private static final String ERROR_NOT_LINKED = 'The selected file is not attached to this Work Order Line Item.';
    @TestVisible
    private static final String ERROR_VERSION_NOT_FOUND = 'File version was not found.';
    @TestVisible
    private static final String ERROR_NOT_IMAGE = 'Only PNG, JPEG, GIF, or WebP images can be annotated.';
    @TestVisible
    private static final String ERROR_TOO_LARGE =
        'Image is too large to open in the mobile annotator. Attach a smaller image or annotate before upload.';

    /** @description Largest image (bytes) loaded into the mobile annotator; keeps heap and payload small. */
    @TestVisible
    private static final Integer MAX_ANNOTATION_IMAGE_BYTES = 900000;
    private static final String DEFAULT_IMAGE_MIME_TYPE = 'image/png';
    /** @description File types the annotator can open, mapped to their MIME type for the data URL. */
    private static final Map<String, String> MIME_TYPE_BY_EXTENSION = new Map<String, String>{
        'png' => 'image/png',
        'jpg' => 'image/jpeg',
        'jpeg' => 'image/jpeg',
        'gif' => 'image/gif',
        'webp' => 'image/webp'
    };

    /**
     * @description One image file on the line item, as an option for the LWC's file picker.
     *              Sorted newest first.
     */
    public class ImageFile implements Comparable {
        /** @description ContentDocument Id (combobox value). */
        @AuraEnabled
        public Id contentDocumentId { get; set; }
        /** @description File title (combobox label). */
        @AuraEnabled
        public String title { get; set; }
        /** @description Sort key only; not sent to the LWC. */
        @TestVisible
        private Datetime lastModifiedDate;

        /**
         * @description Newest first; files without a date go last.
         * @param other ImageFile to compare with
         * @return Negative when this file is newer
         */
        public Integer compareTo(Object other) {
            Datetime otherDate = ((ImageFile) other).lastModifiedDate;
            if (lastModifiedDate == otherDate) {
                return 0;
            }
            if (lastModifiedDate == null) {
                return 1;
            }
            if (otherDate == null) {
                return -1;
            }
            return lastModifiedDate > otherDate ? -1 : 1;
        }
    }

    /**
     * @description An image loaded for the Fabric.js annotation editor.
     */
    public class AnnotationImage {
        /** @description ContentDocument Id of the source file. */
        @AuraEnabled
        public Id contentDocumentId { get; set; }
        /** @description File title; used to name the annotated copy. */
        @AuraEnabled
        public String fileName { get; set; }
        /** @description Image as a data URL (data:<mime>;base64,<body>). */
        @AuraEnabled
        public String base64DataUrl { get; set; }
    }

    /**
     * @description Thrown for a request this component can't serve (wrong file, not an image, too large).
     *              The message is shown to the user.
     */
    private class PhotoCaptureValidationException extends Exception {
    }

    /**
     * @description Lists the image files (PNG, JPEG, GIF, WebP) on the Work Order Line Item that can be
     *              opened in the annotator, newest first. Reuses ContentDocumentLinksService.getFilesForLinkedEntities
     *              (which returns at most the 200 most recently linked files).
     * @param workOrderLineItemId Work Order Line Item Id from the quick action
     * @return Image files; empty when there are none or the Id is null
     * @throws AuraHandledException when the files can't be loaded
     * @example
     * List<WoliMicroscopeCaptureMobileCtrl.ImageFile> files =
     *     WoliMicroscopeCaptureMobileCtrl.listAnnotatableImageFiles(workOrderLineItemId);
     */
    @AuraEnabled
    public static List<ImageFile> listAnnotatableImageFiles(Id workOrderLineItemId) {
        try {
            List<ImageFile> imageFileList = new List<ImageFile>();
            if (workOrderLineItemId == null) {
                return imageFileList;
            }
            List<ContentDocumentLinksService.DeviceEvaluationFileData> fileList =
                ContentDocumentLinksService.getFilesForLinkedEntities(new Set<Id>{ workOrderLineItemId });
            for (ContentDocumentLinksService.DeviceEvaluationFileData file : fileList) {
                if (isAnnotatableExtension(file.fileExtension)) {
                    imageFileList.add(toImageFile(file));
                }
            }
            imageFileList.sort();
            return imageFileList;
        } catch (ContentDocumentLinksService.ContentDocumentLinksServiceException e) {
            // Already logged by the service
            throw toAuraHandledException(ERROR_LIST_FILES);
        } catch (Exception e) {
            logError('listAnnotatableImageFiles', workOrderLineItemId, e);
            throw toAuraHandledException(ERROR_LIST_FILES);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Returns one image file on the Work Order Line Item as a data URL for the Fabric.js
     *              annotator. Checks that the file is linked to
     *              the line item, is an image the annotator can open, and is small enough to load, before
     *              reading the file body.
     * @param workOrderLineItemId Work Order Line Item that must own the file link
     * @param contentDocumentId ContentDocument to annotate
     * @return The image and its metadata
     * @throws AuraHandledException with a user-facing message when the file can't be loaded
     * @example
     * WoliMicroscopeCaptureMobileCtrl.AnnotationImage image =
     *     WoliMicroscopeCaptureMobileCtrl.getImageFileForAnnotation(workOrderLineItemId, contentDocumentId);
     */
    @AuraEnabled
    public static AnnotationImage getImageFileForAnnotation(Id workOrderLineItemId, Id contentDocumentId) {
        try {
            ContentVersion latestVersion = getValidatedLatestVersion(workOrderLineItemId, contentDocumentId);
            ContentVersion details = queryAnnotationDetails(latestVersion.Id);
            return toAnnotationImage(contentDocumentId, latestVersion, details);
        } catch (PhotoCaptureValidationException e) {
            logWarning('getImageFileForAnnotation', workOrderLineItemId, e.getMessage());
            throw toAuraHandledException(e.getMessage());
        } catch (ContentDocumentLinksService.ContentDocumentLinksServiceException e) {
            // Already logged by the service
            throw toAuraHandledException(ERROR_LOAD_FILE);
        } catch (ContentVersionsService.ContentVersionsServiceException e) {
            // Already logged by the service
            throw toAuraHandledException(ERROR_LOAD_FILE);
        } catch (Exception e) {
            logError('getImageFileForAnnotation', workOrderLineItemId, e);
            throw toAuraHandledException(ERROR_LOAD_FILE);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Runs this component's checks with the existing services and returns the latest version.
     * @param workOrderLineItemId Work Order Line Item that must own the file link
     * @param contentDocumentId ContentDocument to annotate
     * @return Latest ContentVersion (Id, Title, FileExtension, FileType)
     * @throws PhotoCaptureValidationException when a check fails
     */
    private static ContentVersion getValidatedLatestVersion(Id workOrderLineItemId, Id contentDocumentId) {
        if (workOrderLineItemId == null || contentDocumentId == null) {
            throw new PhotoCaptureValidationException(ERROR_IDS_REQUIRED);
        }
        List<ContentDocumentLink> linkList = ContentDocumentLinksService.getLinksByDocumentsAndLinkedEntities(
            new Set<Id>{ contentDocumentId },
            new Set<Id>{ workOrderLineItemId }
        );
        if (linkList.isEmpty()) {
            throw new PhotoCaptureValidationException(ERROR_NOT_LINKED);
        }

        List<ContentVersion> latestList = ContentVersionsService.getLatestForDeviceEvaluationByDocumentIds(
            new Set<Id>{ contentDocumentId }
        );
        if (latestList.isEmpty()) {
            throw new PhotoCaptureValidationException(ERROR_VERSION_NOT_FOUND);
        }
        ContentVersion latestVersion = latestList[0];
        if (!isAnnotatableExtension(latestVersion.FileExtension)) {
            throw new PhotoCaptureValidationException(ERROR_NOT_IMAGE);
        }

        List<ContentVersion> sizedList = ContentVersionsService.getContentVersionsById(new Set<Id>{ latestVersion.Id });
        if (
            !sizedList.isEmpty() &&
            sizedList[0].ContentSize != null &&
            sizedList[0].ContentSize > MAX_ANNOTATION_IMAGE_BYTES
        ) {
            throw new PhotoCaptureValidationException(ERROR_TOO_LARGE);
        }
        return latestVersion;
    }

    /**
     * @description Reads the fields only this component needs (no existing service returns them), after the
     *              size check so the body is never loaded for a file that is too large.
     *              Runs through SoqlQueryBuilder (USER_MODE: CRUD, FLS and sharing enforced).
     * @param contentVersionId ContentVersion Id
     * @return ContentVersion with VersionData
     * @throws PhotoCaptureValidationException when the version or its body can't be read
     */
    private static ContentVersion queryAnnotationDetails(Id contentVersionId) {
        ContentVersion details = (ContentVersion) SoqlQueryBuilder.fromObject('ContentVersion')
            .selectFields(new List<String>{ 'Id', 'VersionData' })
            .whereEquals('Id', contentVersionId)
            .first();
        if (details == null || details.VersionData == null) {
            throw new PhotoCaptureValidationException(ERROR_VERSION_NOT_FOUND);
        }
        return details;
    }

    private static ImageFile toImageFile(ContentDocumentLinksService.DeviceEvaluationFileData file) {
        ImageFile imageFile = new ImageFile();
        imageFile.contentDocumentId = file.contentDocumentId;
        imageFile.title = file.title;
        imageFile.lastModifiedDate = file.lastModifiedDate;
        return imageFile;
    }

    private static AnnotationImage toAnnotationImage(
        Id contentDocumentId,
        ContentVersion latestVersion,
        ContentVersion details
    ) {
        AnnotationImage image = new AnnotationImage();
        image.contentDocumentId = contentDocumentId;
        image.fileName = latestVersion.Title;
        image.base64DataUrl =
            'data:' +
            resolveMimeType(latestVersion.FileType, latestVersion.FileExtension) +
            ';base64,' +
            EncodingUtil.base64Encode(details.VersionData);
        return image;
    }

    /**
     * @description Whether the annotator can open a file with this extension (PNG, JPEG, GIF, WebP).
     * @param fileExtension File extension, any case
     * @return True for annotatable images
     */
    private static Boolean isAnnotatableExtension(String fileExtension) {
        return String.isNotBlank(fileExtension) &&
            MIME_TYPE_BY_EXTENSION.containsKey(fileExtension.trim().toLowerCase());
    }

    /**
     * @description MIME type for the data URL: by file extension, else the version's FileType when it is
     *              already a MIME type, else PNG.
     * @param fileType ContentVersion.FileType
     * @param fileExtension ContentVersion.FileExtension
     * @return MIME type, e.g. image/png
     */
    @TestVisible
    private static String resolveMimeType(String fileType, String fileExtension) {
        String extension = String.isBlank(fileExtension) ? '' : fileExtension.trim().toLowerCase();
        if (MIME_TYPE_BY_EXTENSION.containsKey(extension)) {
            return MIME_TYPE_BY_EXTENSION.get(extension);
        }
        return String.isNotBlank(fileType) && fileType.contains('/') ? fileType.toLowerCase() : DEFAULT_IMAGE_MIME_TYPE;
    }

    /**
     * @description Logs an unexpected error at ERROR level, linked to the Work Order Line Item.
     *              Saved by Logger.saveLog() in the caller's finally block.
     * @param methodName Controller method that failed
     * @param workOrderLineItemId Work Order Line Item the request was for
     * @param error Exception that was caught
     */
    @TestVisible
    private static void logError(String methodName, Id workOrderLineItemId, Exception error) {
        Logger.setScenario(LOG_SCENARIO);
        Logger.error(
                new LogMessage(
                    'WoliMicroscopeCaptureMobileCtrl.{0} failed for Work Order Line Item {1}: {2}',
                    methodName,
                    workOrderLineItemId,
                    error.getMessage()
                ),
                error
            )
            .setRecord(workOrderLineItemId)
            .addTag('WorkOrderLineItem')
            .addTag('ContentVersion');
    }

    /**
     * @description Logs a rejected request at WARN level (invalid data that stops the request).
     *              Saved by Logger.saveLog() in the caller's finally block.
     * @param methodName Controller method
     * @param workOrderLineItemId Work Order Line Item the request was for
     * @param message Message returned to the user
     */
    private static void logWarning(String methodName, Id workOrderLineItemId, String message) {
        Logger.setScenario(LOG_SCENARIO);
        Logger.warn(
                new LogMessage(
                    'WoliMicroscopeCaptureMobileCtrl.{0} rejected for Work Order Line Item {1}: {2}',
                    methodName,
                    workOrderLineItemId,
                    message
                )
            )
            .setRecord(workOrderLineItemId)
            .addTag('WorkOrderLineItem')
            .addTag('ContentVersion');
    }

    /**
     * @description Builds an AuraHandledException whose message is readable both in the LWC and in Apex.
     * @param message User-facing message
     * @return Exception to throw to the LWC
     */
    @TestVisible
    private static AuraHandledException toAuraHandledException(String message) {
        AuraHandledException auraException = new AuraHandledException(message);
        auraException.setMessage(message);
        return auraException;
    }
}