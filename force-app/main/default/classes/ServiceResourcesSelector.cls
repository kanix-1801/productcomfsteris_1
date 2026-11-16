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
			SELECT Id, RepairCenter__c, RepairCenter__r.Name
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

	/**
	 * @description Active Service Resources for the running user, including location and visitor address.
	 *              Truck resources are removed by the caller.
	 * @param userId RelatedRecordId of the Service Resource.
	 * @return Active Service Resources for that user.
	 * @example
	 * ServiceResourcesSelector.selectActiveByUserId(UserInfo.getUserId());
	 */
	public static List<ServiceResource> selectActiveByUserId(Id userId) {
		if (userId == null) {
			return new List<ServiceResource>();
		}
		return (List<ServiceResource>) new ServiceResourcesSelector()
			.selectFields(new List<String>{
				'Id',
				'Name',
				'LocationId',
				'Location.VisitorAddressId',
				'TechnicianType__c'
			})
			.whereEquals('RelatedRecordId', userId)
			.whereEquals('IsActive', true)
			.orderBy('Name')
			.execute();
	}

	/**
	 * @description Active Technician service resources for the given Ids.
	 *              ResourceType T is the Technician type.
	 * @param resourceIds Service Resource Ids assigned to a Work Order.
	 * @return Active Technician resources, ordered by name.
	 * @example
	 * ServiceResourcesSelector.selectActiveTechniciansByIds(resourceIds);
	 */
	public static List<ServiceResource> selectActiveTechniciansByIds(Set<Id> resourceIds) {
		if (resourceIds == null || resourceIds.isEmpty()) {
			return new List<ServiceResource>();
		}
		List<String> resourceIdList = new List<String>();
		for (Id resourceId : resourceIds) {
			resourceIdList.add(resourceId);
		}
		return (List<ServiceResource>) new ServiceResourcesSelector()
			.selectFields(new List<String>{
				'Id',
				'Name',
				'LocationId',
				'Location.VisitorAddressId',
				'TechnicianType__c'
			})
			.whereIn('Id', resourceIdList)
			.whereEquals('IsActive', true)
			.whereEquals('ResourceType', 'T')
			.orderBy('Name')
			.execute();
	}

	/**
	 * @description GW-2707 - Active Service Resources whose External ID (technician HRIS ID) matches.
	 *              Runs in USER_MODE; record access comes from the FieldServiceBackofficeTool permission set.
	 * @param externalIds Technician HRIS IDs from the Tech District Alignment file.
	 * @return Matching active Service Resources (empty when the input is missing).
	 * @example
	 * ServiceResourcesSelector.selectActiveByExternalIds(new Set<String>{ '50708' });
	 */
	public static List<ServiceResource> selectActiveByExternalIds(Set<String> externalIds) {
		if (externalIds == null || externalIds.isEmpty()) {
			return new List<ServiceResource>();
		}
		return (List<ServiceResource>) new ServiceResourcesSelector()
			.selectFields(new List<String>{ 'Id', 'Name', 'ExternalID__c', 'RelatedRecordId' })
			.whereEquals('IsActive', true)
			.whereIn('ExternalID__c', new List<String>(externalIds))
			.execute();
	}

	/**
	 * @description GW-5310 - Active Service Resources at a Repair Center whose user name matches.
	 * @param repairCenterId Work Order Repair Center Location Id
	 * @param nameLike SOQL LIKE value, including wildcards
	 * @return Matching Service Resources, limited to 20
	 */
	public static List<ServiceResource> selectActiveByRepairCenterAndName(
		Id repairCenterId,
		String nameLike
	) {
		if (repairCenterId == null || String.isBlank(nameLike)) {
			return new List<ServiceResource>();
		}
		return (List<ServiceResource>) new ServiceResourcesSelector()
			.selectFields(new List<String>{ 'Id', 'RelatedRecordId', 'RelatedRecord.Name' })
			.whereEquals('RepairCenter__c', repairCenterId)
			.whereEquals('IsActive', true)
			.whereField('RelatedRecordId', '!=', null)
			.whereField('RelatedRecord.Name', 'LIKE', nameLike)
			.orderBy('RelatedRecord.Name')
			.limitTo(20)
			.executeSystemMode();
	}

	/**
	 * @description GW-5310 - Active Service Resource for one user at a Repair Center.
	 * @param repairCenterId Work Order Repair Center Location Id
	 * @param userId Technician User Id
	 * @return Matching Service Resource, or null
	 */
	public static ServiceResource selectActiveByRepairCenterAndUser(Id repairCenterId, Id userId) {
		if (repairCenterId == null || userId == null) {
			return null;
		}
		List<ServiceResource> resources = (List<ServiceResource>) new ServiceResourcesSelector()
			.selectFields(new List<String>{ 'Id', 'RelatedRecordId', 'RelatedRecord.Name' })
			.whereEquals('RepairCenter__c', repairCenterId)
			.whereEquals('IsActive', true)
			.whereEquals('RelatedRecordId', userId)
			.limitTo(1)
			.executeSystemMode();
		return resources.isEmpty() ? null : resources[0];
	}
}