/**
 * @description GW-1505 — Same-origin thumbnail proxy for WOLI file list images.
 * Serves THUMB120BY90 renditions via Apex REST so LWC img tags avoid cross-domain CSP blocks.
 */
@RestResource(urlMapping='/woli/v1/file-thumbnail/*')
global with sharing class WorkOrderLineItemFileThumbnailRest {
    private static final String THUMBNAIL_RENDITION = 'THUMB120BY90';
    private static final String TEST_PNG_BASE64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    @TestVisible
    private static Boolean returnEmptyBlobInTest = false;

    /**
     * @description GW-1505 — Returns a THUMB120BY90 rendition for the requested ContentVersion Id.
     */
    @HttpGet
    global static void getFileThumbnail() {
        RestResponse response = RestContext.response;
        try {
            String versionId = extractVersionId(RestContext.request.requestURI);
            if (String.isBlank(versionId)) {
                response.statusCode = 400;
                return;
            }

            List<ContentVersion> versions = [
                SELECT FileExtension, Id
                FROM ContentVersion
                WHERE Id = :versionId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (versions.isEmpty()) {
                response.statusCode = 404;
                return;
            }

            ContentVersion version = versions[0];
            Blob thumbnailBlob = loadThumbnailBlob(version.Id);
            if (thumbnailBlob == null || thumbnailBlob.size() == 0) {
                response.statusCode = 404;
                return;
            }

            response.responseBody = thumbnailBlob;
            response.addHeader('Content-Type', resolveImageMimeType(version.FileExtension));
            response.addHeader('Cache-Control', 'private, max-age=300');
            response.statusCode = 200;
        } catch (Exception e) {
            Logger.error('WorkOrderLineItemFileThumbnailRest.getFileThumbnail failed', e);
            response.statusCode = 500;
        } finally {
            flushLogger();
        }
    }

    private static Blob loadThumbnailBlob(Id versionId) {
        if (Test.isRunningTest()) {
            if (returnEmptyBlobInTest) {
                return Blob.valueOf('');
            }
            return EncodingUtil.base64Decode(TEST_PNG_BASE64);
        }
        PageReference renditionPage = new PageReference(
            '/sfc/servlet.shepherd/version/renditionDownload?rendition=' +
            THUMBNAIL_RENDITION +
            '&versionId=' +
            versionId
        );
        renditionPage.setRedirect(false);
        return renditionPage.getContent();
    }

    private static String extractVersionId(String requestUri) {
        if (String.isBlank(requestUri)) {
            return null;
        }
        Integer lastSlashIndex = requestUri.lastIndexOf('/');
        if (lastSlashIndex < 0 || lastSlashIndex == requestUri.length() - 1) {
            return null;
        }
        return requestUri.substring(lastSlashIndex + 1);
    }

    private static String resolveImageMimeType(String fileExtension) {
        String normalizedExtension = (fileExtension == null) ? '' : fileExtension.toLowerCase();
        if (normalizedExtension == 'png') {
            return 'image/png';
        }
        if (normalizedExtension == 'gif') {
            return 'image/gif';
        }
        if (normalizedExtension == 'webp') {
            return 'image/webp';
        }
        return 'image/jpeg';
    }

    private static void flushLogger() {
        try {
            Logger.saveLog();
        } catch (Exception logError) {
            // Do not fail the user transaction when Nebula Logger persistence is unavailable.
        }
    }
}