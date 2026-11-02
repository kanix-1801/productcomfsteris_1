/**
 * @author Uptima Development Team
 * @date 2026-09-03
 * @group Selectors
 * @description Selector class for ServiceResource SOQL used by Repair Center flows.
 *              Queries use SoqlQueryBuilder.
 */
public with sharing class ServiceResourcesSelector extends SoqlQueryBuilder {
    /**
     * @description Binds this selector to ServiceResource for SoqlQueryBuilder queries.
     */
    public ServiceResourcesSelector() {
        this.objectName = 'ServiceResource';
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
        return (List<ServiceResource>) new ServiceResourcesSelector()
            .selectFields(new List<String>{ 'Id', 'RepairCenter__c', 'RepairCenter__r.Name' })
            .whereEquals('RelatedRecordId', userId)
            .whereEquals('IsActive', true)
            .whereField('RepairCenter__c', '!=', null)
            .orderByDesc('LastModifiedDate')
            .limitTo(1)
            .execute();
    }
}