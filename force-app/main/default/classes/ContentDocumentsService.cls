/**
 * @description Service class for ContentDocument business operations.
 *              Entry point for all ContentDocument-related transactions.
 *              Performs DML directly — no Unit of Work.
 *
 *              NOTE: ContentDocument records cannot be inserted directly. They are
 *              created implicitly when inserting a ContentVersion. Use
 *              ContentVersionsService.createContentVersions() to initiate document creation,
 *              then query the resulting ContentDocumentId for linking.
 */
public with sharing class ContentDocumentsService {
    @TestVisible
    private interface IContentDocumentsSelector {
        List<ContentDocument> selectById(Set<Id> contentDocumentIds);
        List<ContentDocument> selectOwnedByCreatedBy(Id contentDocumentId, Id createdById);
    }

    private class DefaultContentDocumentsSelector implements IContentDocumentsSelector {
        public List<ContentDocument> selectById(Set<Id> contentDocumentIds) {
            return ContentDocumentsSelector.selectById(contentDocumentIds);
        }

        public List<ContentDocument> selectOwnedByCreatedBy(
            Id contentDocumentId,
            Id createdById
        ) {
            return ContentDocumentsSelector.selectOwnedByCreatedBy(
                contentDocumentId,
                createdById
            );
        }
    }

    @TestVisible
    private static IContentDocumentsSelector selectorOverride;

    private static IContentDocumentsSelector selector() {
        return selectorOverride == null
            ? new DefaultContentDocumentsSelector()
            : selectorOverride;
    }

    /**
     * @description Updates existing ContentDocument records.
     * @param contentDocuments List of ContentDocument records to update.
     * @throws ContentDocumentsServiceException when the operation fails.
     */
    public static void updateContentDocuments(List<ContentDocument> contentDocuments) {
        if (contentDocuments == null || contentDocuments.isEmpty()) {
            return;
        }
        Logger.setScenario('Content Document Management');
        try {
            ContentDocuments domain = new ContentDocuments(contentDocuments);
            // domain.validate();
            update contentDocuments;
        } catch (ContentDocuments.ContentDocumentsException e) {
            Logger.error(new LogMessage('ContentDocumentsService.updateContentDocuments: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new ContentDocumentsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ContentDocumentsService.updateContentDocuments: Unexpected error.', e);
            Logger.saveLog();
            throw new ContentDocumentsServiceException('An unexpected error occurred while updating ContentDocument records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes ContentDocument records by their Ids.
     * @param contentDocumentIds Set of ContentDocument Ids to delete.
     * @throws ContentDocumentsServiceException when the operation fails.
     */
    public static void deleteContentDocuments(Set<Id> contentDocumentIds) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Content Document Management');
        try {
            List<ContentDocument> contentDocumentList = selector().selectById(contentDocumentIds);
            if (contentDocumentList.isEmpty()) {
                return;
            }
            delete contentDocumentList;
        } catch (Exception e) {
            Logger.error('ContentDocumentsService.deleteContentDocuments: Unexpected error.', e);
            Logger.saveLog();
            throw new ContentDocumentsServiceException('An unexpected error occurred while deleting ContentDocument records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves ContentDocument records by their Ids.
     * @param contentDocumentIds Set of ContentDocument Ids to retrieve.
     * @return List of ContentDocument records.
     * @throws ContentDocumentsServiceException when the operation fails.
     */
    public static List<ContentDocument> getContentDocumentsById(Set<Id> contentDocumentIds) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return new List<ContentDocument>();
        }
        try {
            return selector().selectById(contentDocumentIds);
        } catch (Exception e) {
            Logger.error('ContentDocumentsService.getContentDocumentsById: Unexpected error.', e);
            Logger.saveLog();
            throw new ContentDocumentsServiceException('An unexpected error occurred while retrieving ContentDocument records.', e);
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Returns a ContentDocument owned by CreatedById for Device Evaluation
     *              staged-photo delete, or null when not found.
     * @param contentDocumentId ContentDocument Id
     * @param createdById Owning User Id
     * @return ContentDocument or null
     * @throws ContentDocumentsServiceException when the operation fails
     */
    public static ContentDocument getOwnedDocumentForDeviceEvaluation(
        Id contentDocumentId,
        Id createdById
    ) {
        if (contentDocumentId == null || createdById == null) {
            return null;
        }
        try {
            List<ContentDocument> documents = selector().selectOwnedByCreatedBy(
                contentDocumentId,
                createdById
            );
            return documents.isEmpty() ? null : documents[0];
        } catch (Exception e) {
            Logger.error(
                'ContentDocumentsService.getOwnedDocumentForDeviceEvaluation: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ContentDocumentsServiceException(
                'An unexpected error occurred while retrieving an owned ContentDocument for Device Evaluation.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Deletes a staged ContentDocument owned by the current user
     *              when it is not linked to a non-User record.
     * @param contentDocumentId ContentDocument Id
     * @throws ContentDocumentsServiceException for validation / unexpected failures
     * @throws DmlException when underlying DML fails
     */
    public static void deleteStagedPhotoForDeviceEvaluation(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw new ContentDocumentsServiceException('File is required.');
        }
        ContentDocument ownedDocument = getOwnedDocumentForDeviceEvaluation(
            contentDocumentId,
            UserInfo.getUserId()
        );
        if (ownedDocument == null) {
            throw new ContentDocumentsServiceException(
                'Staged photo was not found or has already been removed.'
            );
        }
        for (
            ContentDocumentLink link : ContentDocumentLinksService.getLinkedEntityIdsByContentDocumentId(
                contentDocumentId
            )
        ) {
            String linkedId = String.valueOf(link.LinkedEntityId);
            if (linkedId != null && !linkedId.startsWith('005')) {
                throw new ContentDocumentsServiceException(
                    'This photo is already attached to a record and cannot be removed here.'
                );
            }
        }
        deleteContentDocumentsRethrowDml(new Set<Id>{ ownedDocument.Id });
    }

    private static void deleteContentDocumentsRethrowDml(Set<Id> contentDocumentIds) {
        try {
            deleteContentDocuments(contentDocumentIds);
        } catch (ContentDocumentsServiceException e) {
            if (e.getCause() instanceof DmlException) {
                throw (DmlException) e.getCause();
            }
            throw e;
        }
    }

    /**
     * @description Thrown when a ContentDocument service operation fails.
     */
    public class ContentDocumentsServiceException extends Exception {}
}