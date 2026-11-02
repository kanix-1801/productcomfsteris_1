/**
 * @description Service class for ContentDocumentLink business operations.
 *              Entry point for all ContentDocumentLink-related transactions.
 *              Performs DML directly — no Unit of Work.
 */
public with sharing class ContentDocumentLinksService {
    @TestVisible
    private interface IContentDocumentLinksSelector {
        List<ContentDocumentLink> selectById(Set<Id> linkIds);
        List<ContentDocumentLink> selectByLinkedEntityIdsLimited(
            Set<Id> linkedEntityIds,
            Integer rowLimit
        );
        List<ContentDocumentLink> selectByDocumentsAndLinkedEntities(
            Set<Id> documentIds,
            Set<Id> linkedEntityIds
        );
        Integer countByLinkedEntityIds(Set<Id> linkedEntityIds);
        List<ContentDocumentLink> selectLinkedEntityIdsByContentDocumentId(
            Id contentDocumentId
        );
    }

    private class DefaultContentDocumentLinksSelector
        implements IContentDocumentLinksSelector {
        public List<ContentDocumentLink> selectById(Set<Id> linkIds) {
            return ContentDocumentLinksSelector.selectById(linkIds);
        }

        public List<ContentDocumentLink> selectByLinkedEntityIdsLimited(
            Set<Id> linkedEntityIds,
            Integer rowLimit
        ) {
            return ContentDocumentLinksSelector.selectByLinkedEntityIdsLimited(
                linkedEntityIds,
                rowLimit
            );
        }

        public List<ContentDocumentLink> selectByDocumentsAndLinkedEntities(
            Set<Id> documentIds,
            Set<Id> linkedEntityIds
        ) {
            return ContentDocumentLinksSelector.selectByDocumentsAndLinkedEntities(
                documentIds,
                linkedEntityIds
            );
        }

        public Integer countByLinkedEntityIds(Set<Id> linkedEntityIds) {
            return ContentDocumentLinksSelector.countByLinkedEntityIds(linkedEntityIds);
        }

        public List<ContentDocumentLink> selectLinkedEntityIdsByContentDocumentId(
            Id contentDocumentId
        ) {
            return ContentDocumentLinksSelector.selectLinkedEntityIdsByContentDocumentId(
                contentDocumentId
            );
        }
    }

    @TestVisible
    private static IContentDocumentLinksSelector selectorOverride;

    private static IContentDocumentLinksSelector selector() {
        return selectorOverride == null
            ? new DefaultContentDocumentLinksSelector()
            : selectorOverride;
    }

    /**
     * @description GW-3913 / GW-3096 - Staged photo assignment (domain; not controller DTO).
     */
    public class StagedPhotoAssignment {
        public Id contentDocumentId;
        public Id productId;
    }

    /**
     * @description GW-3913 / GW-3096 - File row data for Device Evaluation (domain; not LWC DTO).
     */
    public class DeviceEvaluationFileData {
        public Id contentDocumentId;
        public Id contentVersionId;
        public String title;
        public String fileExtension;
        public String fileType;
        public Datetime lastModifiedDate;
        public String downloadUrl;
        public String thumbnailUrl;
        public String imageDownloadUrl;
        public Boolean isImage;
        public Id productId;
        public String productCode;
        public String productName;
        /** Linked entity (e.g. Product Serviced WOLI) when loaded by entity Id. */
        public Id linkedEntityId;
    }

    /**
     * @description Creates new ContentDocumentLink records with validation.
     * @param links List of ContentDocumentLink records to create.
     * @throws ContentDocumentLinksServiceException when the operation fails.
     */
    public static void createContentDocumentLinks(List<ContentDocumentLink> links) {
        if (links == null || links.isEmpty()) {
            return;
        }
        Logger.setScenario('Content Document Link Management');
        try {
            ContentDocumentLinks domain = new ContentDocumentLinks(links);
            // domain.applyDefaults();
            // domain.validate();
            insert links;
        } catch (ContentDocumentLinks.ContentDocumentLinksException e) {
            Logger.error(new LogMessage('ContentDocumentLinksService.createContentDocumentLinks: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new ContentDocumentLinksServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ContentDocumentLinksService.createContentDocumentLinks: Unexpected error.', e);
            Logger.saveLog();
            throw new ContentDocumentLinksServiceException('An unexpected error occurred while creating ContentDocumentLink records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes ContentDocumentLink records by their Ids.
     * @param linkIds Set of ContentDocumentLink Ids to delete.
     * @throws ContentDocumentLinksServiceException when the operation fails.
     */
    public static void deleteContentDocumentLinks(Set<Id> linkIds) {
        if (linkIds == null || linkIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Content Document Link Management');
        try {
            List<ContentDocumentLink> linkList = selector().selectById(linkIds);
            if (linkList.isEmpty()) {
                return;
            }
            delete linkList;
        } catch (Exception e) {
            Logger.error('ContentDocumentLinksService.deleteContentDocumentLinks: Unexpected error.', e);
            Logger.saveLog();
            throw new ContentDocumentLinksServiceException('An unexpected error occurred while deleting ContentDocumentLink records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves ContentDocumentLink records by their Ids.
     * @param linkIds Set of ContentDocumentLink Ids to retrieve.
     * @return List of ContentDocumentLink records.
     * @throws ContentDocumentLinksServiceException when the operation fails.
     */
    public static List<ContentDocumentLink> getContentDocumentLinksById(Set<Id> linkIds) {
        if (linkIds == null || linkIds.isEmpty()) {
            return new List<ContentDocumentLink>();
        }
        try {
            return selector().selectById(linkIds);
        } catch (Exception e) {
            Logger.error('ContentDocumentLinksService.getContentDocumentLinksById: Unexpected error.', e);
            Logger.saveLog();
            throw new ContentDocumentLinksServiceException('An unexpected error occurred while retrieving ContentDocumentLink records.', e);
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Returns ContentDocumentLinks for linked entities (limited).
     * @param linkedEntityIds Linked entity Ids
     * @param rowLimit Maximum rows
     * @return Matching ContentDocumentLink records
     * @throws ContentDocumentLinksServiceException when the operation fails
     */
    public static List<ContentDocumentLink> getLinksByLinkedEntityIdsLimited(
        Set<Id> linkedEntityIds,
        Integer rowLimit
    ) {
        if (linkedEntityIds == null || linkedEntityIds.isEmpty() || rowLimit == null || rowLimit <= 0) {
            return new List<ContentDocumentLink>();
        }
        try {
            return selector().selectByLinkedEntityIdsLimited(
                linkedEntityIds,
                rowLimit
            );
        } catch (Exception e) {
            Logger.error(
                'ContentDocumentLinksService.getLinksByLinkedEntityIdsLimited: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ContentDocumentLinksServiceException(
                'An unexpected error occurred while retrieving ContentDocumentLink records for Device Evaluation.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Returns existing links for documents and linked entities.
     * @param docIds ContentDocument Ids
     * @param linkedEntityIds Linked entity Ids
     * @return Matching ContentDocumentLink records
     * @throws ContentDocumentLinksServiceException when the operation fails
     */
    public static List<ContentDocumentLink> getLinksByDocumentsAndLinkedEntities(
        Set<Id> docIds,
        Set<Id> linkedEntityIds
    ) {
        if (
            docIds == null ||
            docIds.isEmpty() ||
            linkedEntityIds == null ||
            linkedEntityIds.isEmpty()
        ) {
            return new List<ContentDocumentLink>();
        }
        try {
            return selector().selectByDocumentsAndLinkedEntities(
                docIds,
                linkedEntityIds
            );
        } catch (Exception e) {
            Logger.error(
                'ContentDocumentLinksService.getLinksByDocumentsAndLinkedEntities: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ContentDocumentLinksServiceException(
                'An unexpected error occurred while retrieving ContentDocumentLink records by document and entity.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Counts ContentDocumentLinks for linked entities.
     * @param linkedEntityIds Linked entity Ids
     * @return Count of matching links
     * @throws ContentDocumentLinksServiceException when the operation fails
     */
    public static Integer countLinksByLinkedEntityIds(Set<Id> linkedEntityIds) {
        if (linkedEntityIds == null || linkedEntityIds.isEmpty()) {
            return 0;
        }
        try {
            return selector().countByLinkedEntityIds(linkedEntityIds);
        } catch (Exception e) {
            Logger.error(
                'ContentDocumentLinksService.countLinksByLinkedEntityIds: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ContentDocumentLinksServiceException(
                'An unexpected error occurred while counting ContentDocumentLink records.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Returns LinkedEntityIds for a ContentDocument.
     * @param contentDocumentId ContentDocument Id
     * @return Matching ContentDocumentLink records
     * @throws ContentDocumentLinksServiceException when the operation fails
     */
    public static List<ContentDocumentLink> getLinkedEntityIdsByContentDocumentId(
        Id contentDocumentId
    ) {
        if (contentDocumentId == null) {
            return new List<ContentDocumentLink>();
        }
        try {
            return selector().selectLinkedEntityIdsByContentDocumentId(
                contentDocumentId
            );
        } catch (Exception e) {
            Logger.error(
                'ContentDocumentLinksService.getLinkedEntityIdsByContentDocumentId: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ContentDocumentLinksServiceException(
                'An unexpected error occurred while retrieving ContentDocumentLink linked entities.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - True when any Repair Code WOLI on the Work Order has files.
     * @param workOrderId Parent Work Order Id
     * @return True when at least one ContentDocumentLink exists on Repair Code WOLIs
     * @throws ContentDocumentLinksServiceException when the operation fails
     */
    public static Boolean repairCodeWolisHaveFilesForDeviceEvaluation(Id workOrderId) {
        if (workOrderId == null) {
            return false;
        }
        try {
            Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
            if (repairCodeRtId == null) {
                return false;
            }
            Set<Id> woliIds = new Set<Id>();
            for (
                WorkOrderLineItem lineItem : WorkOrderLineItemsService.getRepairCodeIds(
                    workOrderId,
                    repairCodeRtId
                )
            ) {
                woliIds.add(lineItem.Id);
            }
            if (woliIds.isEmpty()) {
                return false;
            }
            return countLinksByLinkedEntityIds(woliIds) > 0;
        } catch (ContentDocumentLinksServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                'ContentDocumentLinksService.repairCodeWolisHaveFilesForDeviceEvaluation: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ContentDocumentLinksServiceException(
                'An unexpected error occurred while checking Repair Code WOLI files.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Photos already linked to Repair Code WOLIs.
     * @param workOrderId Parent Work Order Id
     * @return File data rows (empty when none)
     * @throws ContentDocumentLinksServiceException when the operation fails
     */
    public static List<DeviceEvaluationFileData> getRepairCodeWoliFilesForDeviceEvaluation(
        Id workOrderId
    ) {
        List<DeviceEvaluationFileData> rows = new List<DeviceEvaluationFileData>();
        if (workOrderId == null) {
            return rows;
        }
        try {
            Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
            if (repairCodeRtId == null) {
                return rows;
            }
            Map<Id, Id> productIdByWoliId = new Map<Id, Id>();
            Map<Id, String> productCodeByProductId = new Map<Id, String>();
            Map<Id, String> productNameByProductId = new Map<Id, String>();
            for (
                WorkOrderLineItem lineItem : WorkOrderLineItemsService.getRepairCodeLinesWithProduct(
                    workOrderId,
                    repairCodeRtId
                )
            ) {
                productIdByWoliId.put(lineItem.Id, lineItem.Product__c);
                if (lineItem.Product__r != null) {
                    productCodeByProductId.put(lineItem.Product__c, lineItem.Product__r.ProductCode);
                    productNameByProductId.put(
                        lineItem.Product__c,
                        String.isNotBlank(lineItem.Product__r.Description)
                            ? lineItem.Product__r.Description
                            : lineItem.Product__r.Name
                    );
                }
            }
            if (productIdByWoliId.isEmpty()) {
                return rows;
            }
            rows = queryFilesForLinkedEntities(productIdByWoliId.keySet(), productIdByWoliId);
            for (DeviceEvaluationFileData row : rows) {
                if (row.productId != null && productCodeByProductId.containsKey(row.productId)) {
                    row.productCode = productCodeByProductId.get(row.productId);
                }
                if (row.productId != null && productNameByProductId.containsKey(row.productId)) {
                    row.productName = productNameByProductId.get(row.productId);
                }
            }
            return rows;
        } catch (ContentDocumentLinksServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                'ContentDocumentLinksService.getRepairCodeWoliFilesForDeviceEvaluation: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ContentDocumentLinksServiceException(
                'An unexpected error occurred while retrieving Repair Code WOLI files.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Links staged photos to Repair Code WOLIs for selected Products.
     * @param workOrderId Parent Work Order Id
     * @param stagedPhotos Staged document-to-product assignments
     * @param selectedProductIds Selected repair-code Product Ids
     * @throws ContentDocumentLinksServiceException when the operation fails
     * @throws DmlException when underlying DML fails (unwrapped for Aura savepoints)
     */
    public static void attachStagedPhotosToWolisForDeviceEvaluation(
        Id workOrderId,
        List<StagedPhotoAssignment> stagedPhotos,
        Set<Id> selectedProductIds
    ) {
        if (
            workOrderId == null ||
            stagedPhotos == null ||
            stagedPhotos.isEmpty() ||
            selectedProductIds == null ||
            selectedProductIds.isEmpty()
        ) {
            return;
        }
        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        if (repairCodeRtId == null) {
            return;
        }

        Map<Id, Id> woliIdByProductId = new Map<Id, Id>();
        for (
            WorkOrderLineItem lineItem : WorkOrderLineItemsService.getRepairCodeByWorkOrderAndProducts(
                workOrderId,
                repairCodeRtId,
                selectedProductIds
            )
        ) {
            if (lineItem.Product__c != null && !woliIdByProductId.containsKey(lineItem.Product__c)) {
                woliIdByProductId.put(lineItem.Product__c, lineItem.Id);
            }
        }
        if (woliIdByProductId.isEmpty()) {
            return;
        }

        Set<Id> documentIds = new Set<Id>();
        for (StagedPhotoAssignment assignment : stagedPhotos) {
            if (assignment != null && assignment.contentDocumentId != null) {
                documentIds.add(assignment.contentDocumentId);
            }
        }
        Set<String> existingLinkKeys = new Set<String>();
        if (!documentIds.isEmpty()) {
            for (
                ContentDocumentLink existingLink : getLinksByDocumentsAndLinkedEntities(
                    documentIds,
                    new Set<Id>(woliIdByProductId.values())
                )
            ) {
                existingLinkKeys.add(
                    String.valueOf(existingLink.ContentDocumentId) +
                    ':' +
                    String.valueOf(existingLink.LinkedEntityId)
                );
            }
        }

        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        for (StagedPhotoAssignment assignment : stagedPhotos) {
            if (
                assignment == null ||
                assignment.contentDocumentId == null ||
                assignment.productId == null ||
                !selectedProductIds.contains(assignment.productId)
            ) {
                continue;
            }
            Id woliId = woliIdByProductId.get(assignment.productId);
            if (woliId == null) {
                continue;
            }
            String linkKey =
                String.valueOf(assignment.contentDocumentId) + ':' + String.valueOf(woliId);
            if (existingLinkKeys.contains(linkKey)) {
                continue;
            }
            existingLinkKeys.add(linkKey);
            ContentDocumentLink link = new ContentDocumentLink();
            link.ContentDocumentId = assignment.contentDocumentId;
            link.LinkedEntityId = woliId;
            link.ShareType = 'V';
            link.Visibility = 'AllUsers';
            linksToInsert.add(link);
        }
        if (!linksToInsert.isEmpty()) {
            createContentDocumentLinksRethrowDml(linksToInsert);
        }
    }

    /**
     * @description GW-3400 - Files already linked to the given entities (e.g. Product Serviced WOLIs).
     * @param linkedEntityIds Linked entity Ids
     * @return File rows with linkedEntityId populated (empty when none)
     * @throws ContentDocumentLinksServiceException when the operation fails
     */
    public static List<DeviceEvaluationFileData> getFilesForLinkedEntities(Set<Id> linkedEntityIds) {
        if (linkedEntityIds == null || linkedEntityIds.isEmpty()) {
            return new List<DeviceEvaluationFileData>();
        }
        try {
            return queryFilesForLinkedEntities(linkedEntityIds, null);
        } catch (ContentDocumentLinksServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                'ContentDocumentLinksService.getFilesForLinkedEntities: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ContentDocumentLinksServiceException(
                'An unexpected error occurred while retrieving linked files.',
                e
            );
        }
    }

    /**
     * @description GW-3400 - Links staged ContentDocuments to a Product Serviced WOLI
     *              (Instrument Evaluation: photos belong to the item + code-set entry).
     * @param linkedEntityId Product Serviced WorkOrderLineItem Id
     * @param contentDocumentIds Staged ContentDocument Ids
     */
    public static void attachDocumentsToLinkedEntity(
        Id linkedEntityId,
        List<Id> contentDocumentIds
    ) {
        if (linkedEntityId == null || contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return;
        }
        Set<Id> documentIds = new Set<Id>();
        for (Id contentDocumentId : contentDocumentIds) {
            if (contentDocumentId != null) {
                documentIds.add(contentDocumentId);
            }
        }
        if (documentIds.isEmpty()) {
            return;
        }

        Set<String> existingLinkKeys = new Set<String>();
        for (
            ContentDocumentLink existingLink : getLinksByDocumentsAndLinkedEntities(
                documentIds,
                new Set<Id>{ linkedEntityId }
            )
        ) {
            existingLinkKeys.add(
                String.valueOf(existingLink.ContentDocumentId) +
                ':' +
                String.valueOf(existingLink.LinkedEntityId)
            );
        }

        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        for (Id contentDocumentId : documentIds) {
            String linkKey =
                String.valueOf(contentDocumentId) + ':' + String.valueOf(linkedEntityId);
            if (existingLinkKeys.contains(linkKey)) {
                continue;
            }
            existingLinkKeys.add(linkKey);
            ContentDocumentLink link = new ContentDocumentLink();
            link.ContentDocumentId = contentDocumentId;
            link.LinkedEntityId = linkedEntityId;
            link.ShareType = 'V';
            link.Visibility = 'AllUsers';
            linksToInsert.add(link);
        }
        if (!linksToInsert.isEmpty()) {
            createContentDocumentLinksRethrowDml(linksToInsert);
        }
    }

    /**
     * @description GW-3400 - Removes a ContentDocument from a Product Serviced WOLI. Deletes the
     *              ContentDocument when no remaining non-User links exist.
     * @param linkedEntityId Product Serviced WorkOrderLineItem Id
     * @param contentDocumentId ContentDocument Id
     */
    public static void removeDocumentFromLinkedEntity(
        Id linkedEntityId,
        Id contentDocumentId
    ) {
        if (linkedEntityId == null || contentDocumentId == null) {
            throw new ContentDocumentLinksServiceException(
                'Linked entity and file are required.'
            );
        }

        List<ContentDocumentLink> links = getLinksByDocumentsAndLinkedEntities(
            new Set<Id>{ contentDocumentId },
            new Set<Id>{ linkedEntityId }
        );
        if (links.isEmpty()) {
            throw new ContentDocumentLinksServiceException(
                'The selected photo is not attached to this evaluation item.'
            );
        }

        Set<Id> linkIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            linkIds.add(link.Id);
        }
        deleteContentDocumentLinks(linkIds);

        Boolean hasNonUserLink = false;
        for (
            ContentDocumentLink remaining :
            getLinkedEntityIdsByContentDocumentId(contentDocumentId)
        ) {
            String linkedId = String.valueOf(remaining.LinkedEntityId);
            if (linkedId != null && !linkedId.startsWith('005')) {
                hasNonUserLink = true;
                break;
            }
        }
        if (!hasNonUserLink) {
            ContentDocumentsService.deleteContentDocuments(new Set<Id>{ contentDocumentId });
        }
    }

    private static List<DeviceEvaluationFileData> queryFilesForLinkedEntities(
        Set<Id> linkedEntityIds,
        Map<Id, Id> productIdByLinkedEntityId
    ) {
        List<DeviceEvaluationFileData> rows = new List<DeviceEvaluationFileData>();
        if (linkedEntityIds == null || linkedEntityIds.isEmpty()) {
            return rows;
        }

        Map<Id, Id> linkedEntityByDocumentId = new Map<Id, Id>();
        for (
            ContentDocumentLink link : getLinksByLinkedEntityIdsLimited(linkedEntityIds, 200)
        ) {
            if (
                link.ContentDocumentId != null &&
                !linkedEntityByDocumentId.containsKey(link.ContentDocumentId)
            ) {
                linkedEntityByDocumentId.put(link.ContentDocumentId, link.LinkedEntityId);
            }
        }
        if (linkedEntityByDocumentId.isEmpty()) {
            return rows;
        }

        Map<Id, ContentVersion> latestByDocumentId = new Map<Id, ContentVersion>();
        for (
            ContentVersion version : ContentVersionsService.getLatestForDeviceEvaluationByDocumentIds(
                linkedEntityByDocumentId.keySet()
            )
        ) {
            if (!latestByDocumentId.containsKey(version.ContentDocumentId)) {
                latestByDocumentId.put(version.ContentDocumentId, version);
            }
        }

        for (Id documentId : linkedEntityByDocumentId.keySet()) {
            ContentVersion version = latestByDocumentId.get(documentId);
            if (version == null) {
                continue;
            }
            DeviceEvaluationFileData row = toFileData(version);
            Id linkedEntityId = linkedEntityByDocumentId.get(documentId);
            row.linkedEntityId = linkedEntityId;
            if (productIdByLinkedEntityId != null && linkedEntityId != null) {
                row.productId = productIdByLinkedEntityId.get(linkedEntityId);
            }
            rows.add(row);
        }
        return rows;
    }

    /**
     * @description GW-3913 / GW-3096 - Maps a ContentVersion to Device Evaluation file data.
     */
    public static DeviceEvaluationFileData toFileData(ContentVersion version) {
        DeviceEvaluationFileData row = new DeviceEvaluationFileData();
        if (version == null) {
            return row;
        }
        row.contentDocumentId = version.ContentDocumentId;
        row.contentVersionId = version.Id;
        row.title = version.Title;
        row.fileExtension = resolveFileExtension(version);
        row.fileType = version.FileType;
        row.lastModifiedDate = version.LastModifiedDate;
        row.downloadUrl = '/sfc/servlet.shepherd/document/download/' + version.ContentDocumentId;
        row.isImage =
            isImageExtension(row.fileExtension) || isImageExtension(version.FileType);
        if (String.isBlank(row.fileExtension) && row.isImage == true && String.isNotBlank(version.FileType)) {
            row.fileExtension = version.FileType.toLowerCase();
        }
        row.imageDownloadUrl = '/sfc/servlet.shepherd/version/download/' + version.Id;
        if (row.isImage == true) {
            row.thumbnailUrl =
                '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480' +
                '&versionId=' +
                version.Id +
                '&operationContext=CHATTER&contentId=' +
                version.ContentDocumentId;
        }
        return row;
    }

    private static String resolveFileExtension(ContentVersion version) {
        if (version == null) {
            return null;
        }
        if (String.isNotBlank(version.FileExtension)) {
            return version.FileExtension;
        }
        if (String.isNotBlank(version.PathOnClient) && version.PathOnClient.contains('.')) {
            return version.PathOnClient.substringAfterLast('.');
        }
        if (String.isNotBlank(version.Title) && version.Title.contains('.')) {
            return version.Title.substringAfterLast('.');
        }
        // FileType is JPG/PNG/etc when Salesforce detected an image without PathOnClient extension.
        if (String.isNotBlank(version.FileType) && isImageExtension(version.FileType)) {
            return version.FileType.toLowerCase();
        }
        return version.FileType;
    }

    private static Boolean isImageExtension(String fileExtension) {
        if (String.isBlank(fileExtension)) {
            return false;
        }
        String normalized = fileExtension.trim().toLowerCase();
        return normalized == 'png' ||
            normalized == 'jpg' ||
            normalized == 'jpeg' ||
            normalized == 'gif' ||
            normalized == 'webp' ||
            normalized == 'bmp';
    }

    private static void createContentDocumentLinksRethrowDml(List<ContentDocumentLink> links) {
        try {
            createContentDocumentLinks(links);
        } catch (ContentDocumentLinksServiceException e) {
            if (e.getCause() instanceof DmlException) {
                throw (DmlException) e.getCause();
            }
            throw e;
        }
    }

    /**
     * @description GW-4189 - Loads Content Document Links for the Repair Center document email queueable.
     * @param linkIds ContentDocumentLink Ids to reload.
     * @return Matching links, or an empty list when no Ids are provided.
     */
    public static List<ContentDocumentLink> selectForRepairCenterDocumentEmail(List<Id> linkIds) {
        if (linkIds == null || linkIds.isEmpty()) {
            return new List<ContentDocumentLink>();
        }
        SoqlQueryBuilder query = new ContentDocumentLinksSelector()
            .selectFields(new List<String>{ 'Id', 'ContentDocumentId', 'LinkedEntityId' });
        List<String> idFilterNumbers = new List<String>();
        Integer filterNumber = 1;
        for (Id linkId : linkIds) {
            if (linkId == null) {
                continue;
            }
            query.whereEquals('Id', linkId);
            idFilterNumbers.add(String.valueOf(filterNumber));
            filterNumber++;
        }
        if (idFilterNumbers.isEmpty()) {
            return new List<ContentDocumentLink>();
        }
        if (idFilterNumbers.size() > 1) {
            query.withFilterLogic(String.join(idFilterNumbers, ' OR '));
        }
        return (List<ContentDocumentLink>) query.execute();
    }

    /**
     * @description Thrown when a ContentDocumentLink service operation fails.
     */
    public class ContentDocumentLinksServiceException extends Exception {}
}