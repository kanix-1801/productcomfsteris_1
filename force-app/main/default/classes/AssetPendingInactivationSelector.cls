/**
 * @description GW-2459 - Queries Assets pending inactivation and their open Work Orders
 *              or active contract lines. The pending-Asset locator uses AssetsSelector.
 *              Open Work Orders and active contract lines use static SOQL: queryWithBinds
 *              cannot bind a List of Object in an IN clause. Queries run in system mode
 *              so an open Work Order or contract line still blocks inactivation when the
 *              running user cannot see that record.
 * @author STERIS
 * @see AssetPendingInactivationService
 */
public without sharing class AssetPendingInactivationSelector {

	/**
	 * @description Returns Assets whose Status is Pending Inactivation.
	 * @return QueryLocator of pending-inactivation Assets
	 */
	public static Database.QueryLocator selectPendingInactivationQueryLocator() {
		DynamicSoqlQuery.PreparedQuery query = new AssetsSelector()
			.selectFields(new List<String>{ 'Id', 'Status' })
			.whereEquals('Status', AssetPendingInactivationService.STATUS_PENDING_INACTIVATION)
			.build();
		return Database.getQueryLocatorWithBinds(query.soql, query.binds, AccessLevel.SYSTEM_MODE);
	}

	/**
	 * @description Returns Asset Ids that have at least one open Work Order.
	 *              Completed, Canceled, and Closed are treated as closed even when
	 *              WorkOrder.IsClosed is still false.
	 * @param assetIdSet Asset Ids to inspect
	 * @return Asset Ids with an open Work Order
	 */
	public static Set<Id> selectAssetIdsWithOpenWorkOrders(Set<Id> assetIdSet) {
		Set<Id> openWorkOrderAssetIdSet = new Set<Id>();
		if (assetIdSet == null || assetIdSet.isEmpty()) {
			return openWorkOrderAssetIdSet;
		}

		Set<String> closedStatuses = AssetPendingInactivationService.CLOSED_WORK_ORDER_STATUSES;
		for (WorkOrder workOrderRecord : [
			SELECT AssetId
			FROM WorkOrder
			WHERE AssetId IN :assetIdSet
				AND IsClosed = false
				AND Status NOT IN :closedStatuses
			WITH SYSTEM_MODE
		]) {
			openWorkOrderAssetIdSet.add(workOrderRecord.AssetId);
		}
		return openWorkOrderAssetIdSet;
	}

	/**
	 * @description Returns Asset Ids that have at least one active Contract Line Item.
	 * @param assetIdSet Asset Ids to inspect
	 * @return Asset Ids with an active contract line
	 */
	public static Set<Id> selectAssetIdsWithActiveContractLines(Set<Id> assetIdSet) {
		Set<Id> activeContractAssetIdSet = new Set<Id>();
		if (assetIdSet == null || assetIdSet.isEmpty()) {
			return activeContractAssetIdSet;
		}

		for (ContractLineItem contractLine : [
			SELECT AssetId
			FROM ContractLineItem
			WHERE AssetId IN :assetIdSet
				AND Status = 'Active'
			WITH SYSTEM_MODE
		]) {
			activeContractAssetIdSet.add(contractLine.AssetId);
		}
		return activeContractAssetIdSet;
	}
}