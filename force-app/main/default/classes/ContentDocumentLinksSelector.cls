/**
 * @description Selector class for the ContentDocumentLink SObject.
 *              Centralizes all SOQL queries for ContentDocumentLinks.
 *              Queries use SoqlQueryBuilder / DynamicSoqlQuery.
 */
public with sharing class ContentDocumentLinksSelector extends SoqlQueryBuilder {
    /**
     * @description GW-4189 - Binds this selector to ContentDocumentLink for SoqlQueryBuilder queries.
     */
    public ContentDocumentLinksSelector() {
        this.objectName = 'ContentDocumentLink';
    }

    private static final List<String> BASE_FIELDS = new List<String>{
        'Id',
        'ContentDocumentId',
        'LinkedEntityId',
        'ShareType',
        'Visibility',
        'IsDeleted',
        'SystemModstamp'
    };

    /**
     * @description Retrieves ContentDocumentLink records by their Ids.
     * @param ids Set of ContentDocumentLink Ids to query.
     * @return List of ContentDocumentLink records matching the given Ids.
     */
    public static List<ContentDocumentLink> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ContentDocumentLink>();
        }
        return (List<ContentDocumentLink>) SoqlQueryBuilder.fromObject('ContentDocumentLink')
            .selectFields(BASE_FIELDS)
            .whereField('Id', 'IN', new List<Id>(ids))
            .execute();
    }

    /**
     * @description Retrieves ContentDocumentLink records by LinkedEntityId.
     * @param linkedEntityIds Set of entity Ids to find document links for.
     * @return List of ContentDocumentLink records for the given entities.
     */
    public static List<ContentDocumentLink> selectByLinkedEntityId(Set<Id> linkedEntityIds) {
        if (linkedEntityIds == null || linkedEntityIds.isEmpty()) {
            return new List<ContentDocumentLink>();
        }
        return (List<ContentDocumentLink>) SoqlQueryBuilder.fromObject('ContentDocumentLink')
            .selectFields(BASE_FIELDS)
            .whereField('LinkedEntityId', 'IN', new List<Id>(linkedEntityIds))
            .execute();
    }

    /**
     * @description Retrieves ContentDocumentLink records by ContentDocumentId.
     * @param contentDocumentIds Set of ContentDocument Ids to find links for.
     * @return List of ContentDocumentLink records for the given documents.
     */
    public static List<ContentDocumentLink> selectByContentDocumentId(Set<Id> contentDocumentIds) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return new List<ContentDocumentLink>();
        }
        return (List<ContentDocumentLink>) SoqlQueryBuilder.fromObject('ContentDocumentLink')
            .selectFields(BASE_FIELDS)
            .whereField('ContentDocumentId', 'IN', new List<Id>(contentDocumentIds))
            .execute();
    }

    /****************************************************************************************
     * ADDITIVES FOR DEVICE EVALUATION (GW-3913 / GW-3096)
     * Methods below this banner were added for Repair Center LWC Batch 9 (not Dev baseline).
     ****************************************************************************************/

    /**
     * @description GW-3913 / GW-3096 - Selects ContentDocumentLinks for linked entities, newest first,
     *              capped by rowLimit (Device Evaluation file listing).
     * @param linkedEntityIds Linked entity Ids
     * @param rowLimit Maximum rows to return
     * @return Matching ContentDocumentLink records (ContentDocumentId, LinkedEntityId)
     */
    public static List<ContentDocumentLink> selectByLinkedEntityIdsLimited(
        Set<Id> linkedEntityIds,
        Integer rowLimit
    ) {
        if (linkedEntityIds == null || linkedEntityIds.isEmpty() || rowLimit == null || rowLimit <= 0) {
            return new List<ContentDocumentLink>();
        }
        return (List<ContentDocumentLink>) SoqlQueryBuilder.fromObject('ContentDocumentLink')
            .selectFields(new List<String>{ 'ContentDocumentId', 'LinkedEntityId' })
            .whereField('LinkedEntityId', 'IN', new List<Id>(linkedEntityIds))
            .orderByDesc('SystemModstamp')
            .limitTo(rowLimit)
            .execute();
    }

    /**
     * @description GW-3913 / GW-3096 - Selects existing links for documents and linked entities
     *              (Device Evaluation staged-photo attach dedupe).
     * @param docIds ContentDocument Ids
     * @param linkedEntityIds Linked entity Ids
     * @return Matching ContentDocumentLink records
     */
    public static List<ContentDocumentLink> selectByDocumentsAndLinkedEntities(
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
        return (List<ContentDocumentLink>) SoqlQueryBuilder.fromObject('ContentDocumentLink')
            .selectFields(new List<String>{ 'ContentDocumentId', 'LinkedEntityId' })
            .whereField('ContentDocumentId', 'IN', new List<Id>(docIds))
            .whereField('LinkedEntityId', 'IN', new List<Id>(linkedEntityIds))
            .execute();
    }

    /**
     * @description GW-3913 / GW-3096 - Counts ContentDocumentLinks for linked entities.
     * @param linkedEntityIds Linked entity Ids
     * @return Count of matching links
     */
    public static Integer countByLinkedEntityIds(Set<Id> linkedEntityIds) {
        if (linkedEntityIds == null || linkedEntityIds.isEmpty()) {
            return 0;
        }
        return SoqlQueryBuilder.fromObject('ContentDocumentLink')
            .whereField('LinkedEntityId', 'IN', new List<Id>(linkedEntityIds))
            .count();
    }

    /**
     * @description GW-3913 / GW-3096 - Selects LinkedEntityIds for a ContentDocument
     *              (Device Evaluation staged-photo delete guard).
     * @param contentDocumentId ContentDocument Id
     * @return Matching ContentDocumentLink records (LinkedEntityId only)
     */
    public static List<ContentDocumentLink> selectLinkedEntityIdsByContentDocumentId(
        Id contentDocumentId
    ) {
        if (contentDocumentId == null) {
            return new List<ContentDocumentLink>();
        }
        return (List<ContentDocumentLink>) SoqlQueryBuilder.fromObject('ContentDocumentLink')
            .selectFields(new List<String>{ 'LinkedEntityId' })
            .whereEquals('ContentDocumentId', contentDocumentId)
            .execute();
    }

    /**
     * @description GW-5492 - Content documents linked to one Receiving record.
     * @param linkedEntityId Return Order line or other linked record Id
     * @return Links with ContentDocumentId
     */
    public static List<ContentDocumentLink> selectByLinkedEntityIdForReceiving(Id linkedEntityId) {
        if (linkedEntityId == null) {
            return new List<ContentDocumentLink>();
        }
        return (List<ContentDocumentLink>) SoqlQueryBuilder.fromObject('ContentDocumentLink')
            .selectFields(new List<String>{ 'ContentDocumentId', 'LinkedEntityId' })
            .whereEquals('LinkedEntityId', linkedEntityId)
            .execute();
    }

    /**
     * @description GW-5492 - Links for a parent with latest version description (Mod Form detect).
     * @param linkedEntityId Linked entity Id
     * @return ContentDocumentLink rows with version description
     */
    public static List<ContentDocumentLink> selectWithVersionDescriptionByLinkedEntityId(
        Id linkedEntityId
    ) {
        if (linkedEntityId == null) {
            return new List<ContentDocumentLink>();
        }
        return (List<ContentDocumentLink>) SoqlQueryBuilder.fromObject('ContentDocumentLink')
            .selectFields(
                new List<String>{ 'ContentDocument.LatestPublishedVersion.Description' }
            )
            .whereEquals('LinkedEntityId', linkedEntityId)
            .execute();
    }
}