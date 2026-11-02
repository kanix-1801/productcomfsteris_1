/**
 * @description Service class for ContentVersion business operations.
 *              Entry point for all ContentVersion-related transactions.
 *              Performs DML directly — no Unit of Work.
 *
 *              NOTE: Inserting a ContentVersion automatically creates the parent ContentDocument.
 *              After insert, re-query the ContentVersion records to obtain ContentDocumentId
 *              for use when creating ContentDocumentLink records.
 */
 public with sharing class ContentVersionsService {
    private static final List<String> BASE_FIELDS = new List<String>{
        'Id',
        'ContentDocumentId',
        'Title',
        'PathOnClient',
        'VersionNumber',
        'FileType',
        'FileExtension',
        'ContentSize',
        'Description',
        'IsMajorVersion',
        'IsLatest',
        'OwnerId',
        'CreatedDate',
        'LastModifiedDate'
    };

    private static final List<String> DEVICE_EVALUATION_FILE_FIELDS = new List<String>{
        'Id',
        'ContentDocumentId',
        'Title',
        'FileExtension',
        'FileType',
        'PathOnClient',
        'LastModifiedDate'
    };

    @TestVisible
    private interface IContentVersionsSelector {
        List<ContentVersion> selectById(Set<Id> contentVersionIds);
        List<ContentVersion> selectLatestForDeviceEvaluationRename(Id contentDocumentId);
        List<ContentVersion> selectForDeviceEvaluationFileRowById(Id contentVersionId);
        List<ContentVersion> selectLatestForDeviceEvaluationByDocumentIds(
            Set<Id> contentDocumentIds
        );
        List<ContentVersion> selectLatestByContentDocumentIdsAndTitle(
            Set<Id> contentDocumentIds,
            String titleContains
        );
        List<ContentVersion> selectVersionDataById(Id contentVersionId);
    }

    private class DefaultContentVersionsSelector implements IContentVersionsSelector {
        public List<ContentVersion> selectById(Set<Id> contentVersionIds) {
            if (contentVersionIds == null || contentVersionIds.isEmpty()) {
                return new List<ContentVersion>();
            }
            return (List<ContentVersion>) new ContentVersionsSelector()
                .selectFields(BASE_FIELDS)
                .whereIn('Id', new List<Id>(contentVersionIds))
                .execute();
        }

        public List<ContentVersion> selectLatestForDeviceEvaluationRename(
            Id contentDocumentId
        ) {
            if (contentDocumentId == null) {
                return new List<ContentVersion>();
            }
            List<String> fields = new List<String>(DEVICE_EVALUATION_FILE_FIELDS);
            fields.add('ContentDocument.CreatedById');
            return asList(
                new ContentVersionsSelector()
                    .selectFields(fields)
                    .whereEquals('ContentDocumentId', contentDocumentId)
                    .whereEquals('IsLatest', true)
                    .first()
            );
        }

        public List<ContentVersion> selectForDeviceEvaluationFileRowById(
            Id contentVersionId
        ) {
            if (contentVersionId == null) {
                return new List<ContentVersion>();
            }
            return asList(
                new ContentVersionsSelector()
                    .selectFields(DEVICE_EVALUATION_FILE_FIELDS)
                    .whereEquals('Id', contentVersionId)
                    .first()
            );
        }

        public List<ContentVersion> selectLatestForDeviceEvaluationByDocumentIds(
            Set<Id> contentDocumentIds
        ) {
            if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
                return new List<ContentVersion>();
            }
            return (List<ContentVersion>) new ContentVersionsSelector()
                .selectFields(DEVICE_EVALUATION_FILE_FIELDS)
                .whereIn('ContentDocumentId', new List<Id>(contentDocumentIds))
                .whereEquals('IsLatest', true)
                .orderByDesc('LastModifiedDate')
                .execute();
        }

        public List<ContentVersion> selectLatestByContentDocumentIdsAndTitle(
            Set<Id> contentDocumentIds,
            String titleContains
        ) {
            if (
                contentDocumentIds == null ||
                contentDocumentIds.isEmpty() ||
                String.isBlank(titleContains)
            ) {
                return new List<ContentVersion>();
            }
            String titleLike = '%' + titleContains.trim() + '%';
            return asList(
                new ContentVersionsSelector()
                    .selectFields(new List<String>{ 'Id', 'Title', 'CreatedDate' })
                    .whereIn('ContentDocumentId', new List<Id>(contentDocumentIds))
                    .whereField('Title', 'LIKE', titleLike)
                    .orderByDesc('CreatedDate')
                    .first()
            );
        }

        public List<ContentVersion> selectVersionDataById(Id contentVersionId) {
            if (contentVersionId == null) {
                return new List<ContentVersion>();
            }
            return asList(
                new ContentVersionsSelector()
                    .selectField('VersionData')
                    .whereEquals('Id', contentVersionId)
                    .first()
            );
        }
    }

    @TestVisible
    private static IContentVersionsSelector selectorOverride;

    private static IContentVersionsSelector selector() {
        return selectorOverride == null
            ? new DefaultContentVersionsSelector()
            : selectorOverride;
    }

    private static List<ContentVersion> asList(SObject row) {
        if (row == null) {
            return new List<ContentVersion>();
        }
        return new List<ContentVersion>{ (ContentVersion) row };
    }

    /**
     * @description Creates new ContentVersion records.
     *              The platform automatically creates parent ContentDocument records on insert.
     * @param contentVersions List of ContentVersion records to create.
     * @return List of inserted ContentVersion records with ContentDocumentId populated.
     * @throws ContentVersionsServiceException when the operation fails.
     */
    public static List<ContentVersion> createContentVersions(List<ContentVersion> contentVersions) {
        if (contentVersions == null || contentVersions.isEmpty()) {
            return new List<ContentVersion>();
        }
        Logger.setScenario('Content Version Management');
        try {
            ContentVersions domain = new ContentVersions(contentVersions);
            // domain.applyDefaults();
            // domain.validate();
            insert contentVersions;
            // Re-query to obtain the platform-generated ContentDocumentId
            Set<Id> insertedIds = new Map<Id, ContentVersion>(contentVersions).keySet();
            return selector().selectById(insertedIds);
        } catch (ContentVersions.ContentVersionsException e) {
            Logger.error(new LogMessage('ContentVersionsService.createContentVersions: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new ContentVersionsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ContentVersionsService.createContentVersions: Unexpected error.', e);
            Logger.saveLog();
            throw new ContentVersionsServiceException('An unexpected error occurred while creating ContentVersion records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves ContentVersion records by their Ids.
     * @param contentVersionIds Set of ContentVersion Ids to retrieve.
     * @return List of ContentVersion records.
     * @throws ContentVersionsServiceException when the operation fails.
     */
    public static List<ContentVersion> getContentVersionsById(Set<Id> contentVersionIds) {
        if (contentVersionIds == null || contentVersionIds.isEmpty()) {
            return new List<ContentVersion>();
        }
        try {
            return selector().selectById(contentVersionIds);
        } catch (Exception e) {
            Logger.error('ContentVersionsService.getContentVersionsById: Unexpected error.', e);
            Logger.saveLog();
            throw new ContentVersionsServiceException('An unexpected error occurred while retrieving ContentVersion records.', e);
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Updates ContentVersion records (e.g. Device Evaluation rename).
     * @param contentVersions List of ContentVersion records to update
     * @throws ContentVersionsServiceException when the operation fails
     */
    public static void updateContentVersions(List<ContentVersion> contentVersions) {
        if (contentVersions == null || contentVersions.isEmpty()) {
            return;
        }
        Logger.setScenario('Content Version Management');
        try {
            ContentVersions domain = new ContentVersions(contentVersions);
            // domain.validate();
            update contentVersions;
        } catch (ContentVersions.ContentVersionsException e) {
            Logger.error(
                new LogMessage(
                    'ContentVersionsService.updateContentVersions: Validation failed. {0}',
                    e.getMessage()
                ),
                e
            );
            Logger.saveLog();
            throw new ContentVersionsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ContentVersionsService.updateContentVersions: Unexpected error.', e);
            Logger.saveLog();
            throw new ContentVersionsServiceException(
                'An unexpected error occurred while updating ContentVersion records.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Returns latest ContentVersion for rename, or null when not found.
     * @param contentDocumentId ContentDocument Id
     * @return ContentVersion or null
     * @throws ContentVersionsServiceException when the operation fails
     */
    public static ContentVersion getLatestForDeviceEvaluationRename(Id contentDocumentId) {
        if (contentDocumentId == null) {
            return null;
        }
        try {
            List<ContentVersion> versions =
                selector().selectLatestForDeviceEvaluationRename(contentDocumentId);
            return versions.isEmpty() ? null : versions[0];
        } catch (Exception e) {
            Logger.error(
                'ContentVersionsService.getLatestForDeviceEvaluationRename: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ContentVersionsServiceException(
                'An unexpected error occurred while retrieving ContentVersion for Device Evaluation rename.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Returns a ContentVersion for Device Evaluation file row, or null.
     * @param contentVersionId ContentVersion Id
     * @return ContentVersion or null
     * @throws ContentVersionsServiceException when the operation fails
     */
    public static ContentVersion getForDeviceEvaluationFileRow(Id contentVersionId) {
        if (contentVersionId == null) {
            return null;
        }
        try {
            List<ContentVersion> versions =
                selector().selectForDeviceEvaluationFileRowById(contentVersionId);
            return versions.isEmpty() ? null : versions[0];
        } catch (Exception e) {
            Logger.error(
                'ContentVersionsService.getForDeviceEvaluationFileRow: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ContentVersionsServiceException(
                'An unexpected error occurred while retrieving ContentVersion for Device Evaluation file row.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Returns latest ContentVersions for Device Evaluation file listing.
     * @param contentDocumentIds ContentDocument Ids
     * @return Matching ContentVersion records
     * @throws ContentVersionsServiceException when the operation fails
     */
    public static List<ContentVersion> getLatestForDeviceEvaluationByDocumentIds(
        Set<Id> contentDocumentIds
    ) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return new List<ContentVersion>();
        }
        try {
            return selector().selectLatestForDeviceEvaluationByDocumentIds(
                contentDocumentIds
            );
        } catch (Exception e) {
            Logger.error(
                'ContentVersionsService.getLatestForDeviceEvaluationByDocumentIds: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ContentVersionsServiceException(
                'An unexpected error occurred while retrieving latest ContentVersions for Device Evaluation.',
                e
            );
        }
    }

    /**
     * @description GW-1206 - Returns the newest ContentVersion whose title contains the given text.
     * @param contentDocumentIds ContentDocument Ids to search
     * @param titleContains Text that must appear in the file title
     * @return The newest matching ContentVersion, or an empty list
     * @throws ContentVersionsServiceException when the operation fails
     */
     public static List<ContentVersion> getLatestByContentDocumentIdsAndTitle(
        Set<Id> contentDocumentIds,
        String titleContains
    ) {
        if (
            contentDocumentIds == null ||
            contentDocumentIds.isEmpty() ||
            String.isBlank(titleContains)
        ) {
            return new List<ContentVersion>();
        }
        try {
            return selector().selectLatestByContentDocumentIdsAndTitle(
                contentDocumentIds,
                titleContains
            );
        } catch (Exception e) {
            Logger.error(
                'ContentVersionsService.getLatestByContentDocumentIdsAndTitle: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ContentVersionsServiceException(
                'An unexpected error occurred while retrieving the latest ContentVersion by title.',
                e
            );
        }
    }

    /**
     * @description GW-4189 - Latest PDF ContentVersions for Repair Center document email title checks.
     * @param contentDocumentIds ContentDocument Ids
     * @return Latest PDF versions, empty when the set is null or empty
     * @throws ContentVersionsServiceException when the operation fails
     */
    public static List<ContentVersion> selectLatestPdfsByContentDocumentIds(
        Set<Id> contentDocumentIds
    ) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return new List<ContentVersion>();
        }
        try {
            return ContentVersionsSelector.selectLatestPdfsByContentDocumentIds(
                contentDocumentIds
            );
        } catch (Exception e) {
            Logger.error(
                'ContentVersionsService.selectLatestPdfsByContentDocumentIds: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ContentVersionsServiceException(
                'An unexpected error occurred while retrieving latest PDF ContentVersions.',
                e
            );
        }
    }

    /**
     * @description GW-1206 - Returns VersionData for one ContentVersion.
     * @param contentVersionId ContentVersion Id
     * @return The file body, or an empty list when the Id is null
     * @throws ContentVersionsServiceException when the operation fails
     */
    public static List<ContentVersion> getVersionDataById(Id contentVersionId) {
        if (contentVersionId == null) {
            return new List<ContentVersion>();
        }
        try {
            return selector().selectVersionDataById(contentVersionId);
        } catch (Exception e) {
            Logger.error(
                'ContentVersionsService.getVersionDataById: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ContentVersionsServiceException(
                'An unexpected error occurred while retrieving ContentVersion file data.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Result of staging a Device Evaluation photo.
     */
    public class StagedPhotoResult {
        public ContentVersion version;
        public Id productId;
        public String productCode;
        public String productName;
    }

    /**
     * @description GW-3913 / GW-3096 - Stages a photo/file for a repair-code Product (no WO/WOLI link).
     * @param productId Repair-code Product Id
     * @param base64Data File payload (optionally data-URL prefixed)
     * @param fileName Optional file name
     * @return Staged photo result with ContentVersion and product labels
     * @throws ContentVersionsServiceException for validation / unexpected failures
     * @throws DmlException when underlying DML fails
     */
    public static StagedPhotoResult stagePhotoForDeviceEvaluation(
        Id productId,
        String base64Data,
        String fileName
    ) {
        if (productId == null) {
            throw new ContentVersionsServiceException('Repair code product is required.');
        }
        if (String.isBlank(base64Data)) {
            throw new ContentVersionsServiceException('File data is required.');
        }

        String resolvedFileName = String.isBlank(fileName)
            ? 'DeviceEval-' + Datetime.now().format('yyyyMMdd-HHmmss') + '.jpg'
            : fileName.trim();
        if (!resolvedFileName.toLowerCase().contains('.')) {
            resolvedFileName += '.jpg';
        }

        String payload = base64Data;
        Integer commaIndex = payload.indexOf(',');
        if (payload.startsWith('data:') && commaIndex > -1) {
            payload = payload.substring(commaIndex + 1);
        }

        ContentVersion version = new ContentVersion();
        version.Title = resolvedFileName.contains('.')
            ? resolvedFileName.substring(0, resolvedFileName.lastIndexOf('.'))
            : resolvedFileName;
        version.PathOnClient = resolvedFileName;
        version.VersionData = EncodingUtil.base64Decode(payload);

        List<ContentVersion> createdVersions = createContentVersionsRethrowDml(
            new List<ContentVersion>{ version }
        );
        ContentVersion inserted = getForDeviceEvaluationFileRow(
            createdVersions.isEmpty() ? null : createdVersions[0].Id
        );
        if (inserted == null) {
            throw new ContentVersionsServiceException(
                'Unable to stage photo: staged file could not be loaded.'
            );
        }

        StagedPhotoResult result = new StagedPhotoResult();
        result.version = inserted;
        result.productId = productId;
        Product2 product = ProductsService.getProductLabelsById(productId);
        if (product != null) {
            result.productCode = product.ProductCode;
            result.productName = String.isNotBlank(product.Description)
                ? product.Description
                : product.Name;
        }
        return result;
    }

    /**
     * @description GW-3913 / GW-3096 - Renames a staged/linked evaluation photo Title for the current user.
     * @param contentDocumentId ContentDocument Id
     * @param newTitle New title (extension stripped)
     * @return Refreshed ContentVersion for file row mapping
     * @throws ContentVersionsServiceException for validation / unexpected failures
     * @throws DmlException when underlying DML fails
     */
    public static ContentVersion renamePhotoForDeviceEvaluation(
        Id contentDocumentId,
        String newTitle
    ) {
        if (contentDocumentId == null) {
            throw new ContentVersionsServiceException('File is required.');
        }
        if (String.isBlank(newTitle)) {
            throw new ContentVersionsServiceException('Photo title is required.');
        }
        String cleanedTitle = newTitle.trim();
        if (cleanedTitle.contains('.')) {
            cleanedTitle = cleanedTitle.substringBeforeLast('.');
        }
        if (String.isBlank(cleanedTitle)) {
            throw new ContentVersionsServiceException('Photo title is required.');
        }

        ContentVersion latestVersion = getLatestForDeviceEvaluationRename(contentDocumentId);
        if (
            latestVersion == null ||
            latestVersion.ContentDocument.CreatedById != UserInfo.getUserId()
        ) {
            throw new ContentVersionsServiceException('Photo was not found or cannot be renamed.');
        }

        ContentVersion toUpdate = new ContentVersion();
        toUpdate.Id = latestVersion.Id;
        toUpdate.Title = cleanedTitle;
        updateContentVersionsRethrowDml(new List<ContentVersion>{ toUpdate });

        ContentVersion refreshed = getForDeviceEvaluationFileRow(latestVersion.Id);
        if (refreshed == null) {
            throw new ContentVersionsServiceException(
                'Unable to rename photo: updated file could not be loaded.'
            );
        }
        return refreshed;
    }

    private static List<ContentVersion> createContentVersionsRethrowDml(
        List<ContentVersion> contentVersions
    ) {
        try {
            return createContentVersions(contentVersions);
        } catch (ContentVersionsServiceException e) {
            if (e.getCause() instanceof DmlException) {
                throw (DmlException) e.getCause();
            }
            throw e;
        }
    }

    private static void updateContentVersionsRethrowDml(List<ContentVersion> contentVersions) {
        try {
            updateContentVersions(contentVersions);
        } catch (ContentVersionsServiceException e) {
            if (e.getCause() instanceof DmlException) {
                throw (DmlException) e.getCause();
            }
            throw e;
        }
    }

    /**
     * @description Thrown when a ContentVersion service operation fails.
     */
    public class ContentVersionsServiceException extends Exception {}
}