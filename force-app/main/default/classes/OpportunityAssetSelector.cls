/**
 * @author Vinay Soni
 * @date 2026/11/25
 * @group IMS Asset Assignment
 * @description GW-6456 - Selector for OpportunityAsset__c (Inventory Tool rows: one per device uploaded against an
 *              Opportunity, grouped by InventoryGroup__c). Queries run in USER_MODE.
 */
public with sharing class OpportunityAssetSelector extends SoqlQueryBuilder {

	/**
	 * @description Binds this selector to OpportunityAsset__c for SoqlQueryBuilder queries.
	 */
	public OpportunityAssetSelector() {
		this.objectName = 'OpportunityAsset__c';
	}

	/**
	 * @description Inventory groups on an opportunity with their device counts and latest upload date.
	 *              Aliases: groupName, deviceCount, uploadedOn. A blank group comes back with groupName = null.
	 * @param opportunityId Opportunity Id
	 * @return One AggregateResult per group, ordered by group name (blank last)
	 */
	public static List<AggregateResult> selectGroupCounts(Id opportunityId) {
		return [
			SELECT InventoryGroup__c groupName, COUNT(Id) deviceCount, MAX(CreatedDate) uploadedOn
			FROM OpportunityAsset__c
			WHERE Opportunity__c = :opportunityId AND Asset__c != null
			WITH USER_MODE
			GROUP BY InventoryGroup__c
			ORDER BY InventoryGroup__c NULLS LAST
		];
	}

	/**
	 * @description Asset Ids of the devices in the given groups.
	 * @param opportunityId Opportunity Id
	 * @param groupNames Group names as stored; null stands for the blank group
	 * @return Asset Ids (no duplicates)
	 */
	public static Set<Id> selectAssetIdsByGroups(Id opportunityId, Set<String> groupNames) {
		Set<Id> assetIds = new Set<Id>();
		if (opportunityId == null || groupNames == null || groupNames.isEmpty()) {
			return assetIds;
		}
		Set<String> named = new Set<String>(groupNames);
		Boolean includeBlank = named.remove(null);
		List<OpportunityAsset__c> rows = includeBlank
			? [
				SELECT Asset__c FROM OpportunityAsset__c
				WHERE Opportunity__c = :opportunityId AND Asset__c != null
					AND (InventoryGroup__c IN :named OR InventoryGroup__c = null)
				WITH USER_MODE
			]
			: [
				SELECT Asset__c FROM OpportunityAsset__c
				WHERE Opportunity__c = :opportunityId AND Asset__c != null AND InventoryGroup__c IN :named
				WITH USER_MODE
			];
		for (OpportunityAsset__c row : rows) {
			assetIds.add(row.Asset__c);
		}
		return assetIds;
	}

	/**
	 * @description One page of a group's devices (Asset Ids), for the group preview panel.
	 * @param opportunityId Opportunity Id
	 * @param groupName Group name as stored; null is the blank group
	 * @param pageSize Rows per page
	 * @param offset Rows to skip (SOQL caps OFFSET at 2,000)
	 * @return Asset Ids in serial number order
	 */
	public static List<Id> selectGroupPageAssetIds(Id opportunityId, String groupName, Integer pageSize, Integer offset) {
		List<Id> assetIds = new List<Id>();
		for (OpportunityAsset__c row : [
			SELECT Asset__c FROM OpportunityAsset__c
			WHERE Opportunity__c = :opportunityId AND InventoryGroup__c = :groupName AND Asset__c != null
			WITH USER_MODE
			ORDER BY Asset__r.SerialNumber NULLS LAST, Id
			LIMIT :pageSize OFFSET :offset
		]) {
			assetIds.add(row.Asset__c);
		}
		return assetIds;
	}
}