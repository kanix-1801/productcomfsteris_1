/**
 * @description Selector class for the ContentVersion SObject.
 *              Centralizes all SOQL queries for ContentVersions.
 *              Enforces security via WITH SECURITY_ENFORCED.
 */
public with sharing class ContentVersionsSelector extends SoqlQueryBuilder {
    /**
     * @description GW-4189 - Binds this selector to ContentVersion for SoqlQueryBuilder queries.
     */
    public ContentVersionsSelector() {
        this.objectName = 'ContentVersion';
    }


    private static final String BASE_FIELDS =
        'Id, ContentDocumentId, Title, PathOnClient, VersionNumber, ' +
        'FileType, FileExtension, ContentSize, Description, IsMajorVersion, ' +
        'IsLatest, OwnerId, CreatedDate, LastModifiedDate';


    /****************************************************************************************
     * ADDITIVES FOR DEVICE EVALUATION (GW-3913 / GW-3096)
     * Methods below this banner were added for Repair Center LWC Batch 9 (not Dev baseline).
     ****************************************************************************************/

    /** GW-3913 / GW-3096 - Device Evaluation file UI fields. */
    private static final String DEVICE_EVALUATION_FILE_FIELDS =
        'Id, ContentDocumentId, Title, FileExtension, FileType, PathOnClient, LastModifiedDate';

    /**
     * @description Retrieves ContentVersion records by their Ids.
     * @param ids Set of ContentVersion Ids to query.
     * @return List of ContentVersion records matching the given Ids.
     */
    public static List<ContentVersion> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ContentVersion>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ContentVersion' +
            ' WHERE Id IN :ids' +
            ' WITH SECURITY_ENFORCED'
        );
    }

    /**
     * @description Retrieves the latest ContentVersion records for given ContentDocument Ids.
     * @param contentDocumentIds Set of ContentDocument Ids to query.
     * @return List of latest ContentVersion records for the given documents.
     */
    public static List<ContentVersion> selectLatestByContentDocumentId(Set<Id> contentDocumentIds) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return new List<ContentVersion>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ContentVersion' +
            ' WHERE ContentDocumentId IN :contentDocumentIds' +
            ' AND IsLatest = true' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY CreatedDate DESC'
        );
    }

    /**
     * @description GW-4189 - Latest PDF ContentVersions for the given ContentDocument Ids.
     * @param contentDocumentIds ContentDocument Ids to query
     * @return Latest PDF versions, empty when the set is null or empty
     */
    public static List<ContentVersion> selectLatestPdfsByContentDocumentIds(
        Set<Id> contentDocumentIds
    ) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return new List<ContentVersion>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ContentVersion' +
            ' WHERE ContentDocumentId IN :contentDocumentIds' +
            ' AND IsLatest = true' +
            ' AND FileType = \'PDF\'' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY CreatedDate DESC'
        );
    }

    /**
     * @description GW-3913 / GW-3096 - Selects a ContentVersion for Device Evaluation file row
     *              (USER_MODE, LIMIT 1).
     * @param contentVersionId ContentVersion Id
     * @return Matching ContentVersion records
     */
    public static List<ContentVersion> selectForDeviceEvaluationFileRowById(Id contentVersionId) {
        if (contentVersionId == null) {
            return new List<ContentVersion>();
        }
        return Database.query(
            'SELECT ' +
            DEVICE_EVALUATION_FILE_FIELDS +
            ' FROM ContentVersion' +
            ' WHERE Id = :contentVersionId' +
            ' WITH USER_MODE' +
            ' LIMIT 1'
        );
    }

    /**
     * @description GW-3913 / GW-3096 - Selects latest ContentVersion for rename, including
     *              ContentDocument.CreatedById (USER_MODE, LIMIT 1).
     * @param contentDocumentId ContentDocument Id
     * @return Matching ContentVersion records
     */
    public static List<ContentVersion> selectLatestForDeviceEvaluationRename(Id contentDocumentId) {
        if (contentDocumentId == null) {
            return new List<ContentVersion>();
        }
        return [
            SELECT
                Id,
                ContentDocumentId,
                Title,
                FileExtension,
                FileType,
                PathOnClient,
                LastModifiedDate,
                ContentDocument.CreatedById
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
                AND IsLatest = true
            WITH USER_MODE
            LIMIT 1
        ];
    }

    /**
     * @description GW-3913 / GW-3096 - Selects latest ContentVersions for Device Evaluation file listing.
     * @param contentDocumentIds ContentDocument Ids
     * @return Matching ContentVersion records ordered by LastModifiedDate DESC
     */
    public static List<ContentVersion> selectLatestForDeviceEvaluationByDocumentIds(
        Set<Id> contentDocumentIds
    ) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return new List<ContentVersion>();
        }
        return Database.query(
            'SELECT ' +
            DEVICE_EVALUATION_FILE_FIELDS +
            ' FROM ContentVersion' +
            ' WHERE ContentDocumentId IN :contentDocumentIds' +
            ' AND IsLatest = true' +
            ' ORDER BY LastModifiedDate DESC'
        );
    }

    /**
     * @description GW-2710 - Latest version of one uploaded file, including the body.
     *              Separate from the Set overload so the alignment upload can read VersionData.
     * @param contentDocumentId Salesforce Files document Id.
     * @return Latest version, or an empty list.
     */
    public static List<ContentVersion> selectLatestForAlignmentUpload(Id contentDocumentId) {
        if (contentDocumentId == null) {
            return new List<ContentVersion>();
        }
        return [
            SELECT Id, Title, FileExtension, PathOnClient, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
                AND IsLatest = TRUE
            LIMIT 1
        ];
    }

    /**
     * @description GW-2710 - ContentDocument Id for a ContentVersion that was just inserted.
     * @param contentVersionId ContentVersion Id.
     * @return The version row, or an empty list.
     */
    public static List<ContentVersion> selectDocumentIdByVersionId(Id contentVersionId) {
        if (contentVersionId == null) {
            return new List<ContentVersion>();
        }
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];
    }
}