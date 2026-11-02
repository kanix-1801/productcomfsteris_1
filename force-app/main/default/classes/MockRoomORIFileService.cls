/**
 * @author PWC Developer
 * @date 2026/10/09
 *
 * @group Mock Room / ORI Request
 *
 * @description
 * GC-3483 - Attaches files chosen on the intake screen after the request is created.
 */
public without sharing class MockRoomORIFileService {

    /**
     * @description Links uploaded files to the new Mock Room / ORI request.
     * @param requests Flow requests. Each document id list is comma-separated.
     */
    public static void linkFiles(List<MockRoomORIFileController.FileLinkRequest> requests) {
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (MockRoomORIFileController.FileLinkRequest requestRow : requests) {
            if (requestRow == null || requestRow.requestId == null || String.isBlank(requestRow.documentIds)) {
                continue;
            }
            for (String documentId : requestRow.documentIds.split(',')) {
                if (String.isBlank(documentId)) {
                    continue;
                }
                links.add(new ContentDocumentLink(
                    ContentDocumentId = documentId.trim(),
                    LinkedEntityId = requestRow.requestId,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                ));
            }
        }
        if (!links.isEmpty()) {
            insert links;
        }
    }
}