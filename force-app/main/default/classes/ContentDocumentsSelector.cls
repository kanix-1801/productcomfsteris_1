/**
 * @description Selector class for the ContentDocument SObject.
 *              Centralizes all SOQL queries for ContentDocuments.
 *              Enforces security via WITH SECURITY_ENFORCED.
 */
public with sharing class ContentDocumentsSelector {

    private static final String BASE_FIELDS =
        'Id, Title, FileType, FileExtension, ContentSize, Description, ' +
        'OwnerId, CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves ContentDocument records by their Ids.
     * @param ids Set of ContentDocument Ids to query.
     * @return List of ContentDocument records matching the given Ids.
     */
    public static List<ContentDocument> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ContentDocument>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ContentDocument' +
            ' WHERE Id IN :ids' +
            ' WITH SECURITY_ENFORCED'
        );
    }

    /**
     * @description Retrieves ContentDocument records linked to a given entity (e.g. Account, Case).
     * @param linkedEntityIds Set of entity Ids to find linked documents for.
     * @return List of ContentDocument records linked to the given entities.
     */
    public static List<ContentDocument> selectByLinkedEntityId(Set<Id> linkedEntityIds) {
        if (linkedEntityIds == null || linkedEntityIds.isEmpty()) {
            return new List<ContentDocument>();
        }
        // ContentDocumentLink is not supported in SOQL semi-joins; resolve document Ids first.
        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :linkedEntityIds
        ]) {
            if (link.ContentDocumentId != null) {
                contentDocumentIds.add(link.ContentDocumentId);
            }
        }
        if (contentDocumentIds.isEmpty()) {
            return new List<ContentDocument>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ContentDocument' +
            ' WHERE Id IN :contentDocumentIds' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY Title ASC'
        );
    }


    /****************************************************************************************
     * ADDITIVES FOR DEVICE EVALUATION (GW-3913 / GW-3096)
     * Methods below this banner were added for Repair Center LWC Batch 9 (not Dev baseline).
     ****************************************************************************************/

    /**
     * @description GW-3913 / GW-3096 - Selects a ContentDocument owned by CreatedById (USER_MODE, LIMIT 1).
     * @param contentDocumentId ContentDocument Id
     * @param createdById Owning User Id
     * @return Matching ContentDocument records (Id only)
     */
    public static List<ContentDocument> selectOwnedByCreatedBy(
        Id contentDocumentId,
        Id createdById
    ) {
        if (contentDocumentId == null || createdById == null) {
            return new List<ContentDocument>();
        }
        return [
            SELECT Id
            FROM ContentDocument
            WHERE Id = :contentDocumentId
                AND CreatedById = :createdById
            WITH USER_MODE
            LIMIT 1
        ];
    }

    /**
     * @description GW-2710 - ContentDocument Id and title for the supplied Ids.
     *              Classic SOQL: the backoffice user reads a file they own, and ContentDocument
     *              is not granted as object CRUD on that permission set.
     * @param contentDocumentIds Salesforce Files document Ids.
     * @return Matching documents.
     */
    public static List<ContentDocument> selectIdAndTitleByIds(Set<Id> contentDocumentIds) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return new List<ContentDocument>();
        }
        return [
            SELECT Id, Title
            FROM ContentDocument
            WHERE Id IN :contentDocumentIds
        ];
    }

    /**
     * @description GW-2710 - Newest ContentDocument with this title.
     * @param title ContentDocument title.
     * @return Matching documents, newest first.
     */
    public static List<ContentDocument> selectLatestByTitle(String title) {
        if (String.isBlank(title)) {
            return new List<ContentDocument>();
        }
        return [
            SELECT Id, Title
            FROM ContentDocument
            WHERE Title = :title
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }
}