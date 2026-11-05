/**
 * @author Uptima Development Team
 * @date 2026-09-03
 * @group Selectors
 * @description Selector class for ServiceResource SOQL used by Repair Center flows.
 */
public with sharing class ServiceResourcesSelector extends SoqlQueryBuilder {
    /**
     * @description Binds this selector to ServiceResource for SoqlQueryBuilder queries.
     */
    public ServiceResourcesSelector() {
        super('ServiceResource');
    }

    /**
     * @description Active Service Resource for the user with a Repair Center assigned.
     * @param userId RelatedRecordId (typically the running user)
     * @return Most recently modified matching ServiceResource, or empty list
     */
    public static List<ServiceResource> selectActiveWithRepairCenterByUserId(Id userId) {
        if (userId == null) {
            return new List<ServiceResource>();
        }
        return [
            SELECT Id, RepairCenter__c
            FROM ServiceResource
            WHERE
                RelatedRecordId = :userId
                AND IsActive = TRUE
                AND RepairCenter__c != NULL
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
    }

    /**
     * @description GW-2710 - Active Service Resources for the technician User Ids in an alignment file.
     * @param userIds RelatedRecordId values from the upload.
     * @return Matching active Service Resources.
     */
    public static List<ServiceResource> selectActiveByRelatedRecordIds(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return new List<ServiceResource>();
        }
        List<String> relatedRecordIds = new List<String>();
        for (Id userId : userIds) {
            relatedRecordIds.add(userId);
        }
        return (List<ServiceResource>) new ServiceResourcesSelector()
            .selectFields(new List<String>{ 'Id', 'Name', 'RelatedRecordId', 'IsActive' })
            .whereEquals('IsActive', true)
            .whereIn('RelatedRecordId', relatedRecordIds)
            .execute();
    }
}