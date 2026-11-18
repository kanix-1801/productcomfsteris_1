/**
 * @description Selector for RepairCenterTeamMember__c used by Device Evaluation Work Performed.
 */
public with sharing class RepairCenterTeamMembersSelector {
	/**
	 * @description Work Performed signatures for a Work Order (Type = Work Order Line).
	 */
	public static List<RepairCenterTeamMember__c> selectWorkOrderLineSignatures(Id workOrderId) {
		if (workOrderId == null) {
			return new List<RepairCenterTeamMember__c>();
		}
		return [
			SELECT
				Id,
				Name,
				Person__c,
				Person__r.Name,
				WorkOrderLineItem__c,
				WorkOrderLineItem__r.Product2Id
			FROM RepairCenterTeamMember__c
			WHERE WorkOrder__c = :workOrderId
				AND Type__c = 'Work Order Line'
			WITH USER_MODE
			ORDER BY CreatedDate ASC
		];
	}

	/**
	 * @description Single signature scoped to the Work Order, or null.
	 */
	public static RepairCenterTeamMember__c selectByIdForWorkOrder(Id recordId, Id workOrderId) {
		if (recordId == null || workOrderId == null) {
			return null;
		}
		List<RepairCenterTeamMember__c> rows = [
			SELECT Id, WorkOrder__c, Person__c, WorkOrderLineItem__c
			FROM RepairCenterTeamMember__c
			WHERE Id = :recordId
				AND WorkOrder__c = :workOrderId
			WITH USER_MODE
			LIMIT 1
		];
		return rows.isEmpty() ? null : rows[0];
	}

	/**
	 * @description GW-3400 - Signature Ids linked to Work Order Line Items (delete dependents).
	 * @param lineItemIds WorkOrderLineItem Ids
	 * @return Matching RepairCenterTeamMember__c rows (Id only)
	 */
	public static List<RepairCenterTeamMember__c> selectIdsByWorkOrderLineItemIds(Set<Id> lineItemIds) {
		if (lineItemIds == null || lineItemIds.isEmpty()) {
			return new List<RepairCenterTeamMember__c>();
		}
		return (List<RepairCenterTeamMember__c>) SoqlQueryBuilder.fromObject(
				'RepairCenterTeamMember__c'
			)
			.selectFields(new List<String>{ 'Id' })
			.whereField('WorkOrderLineItem__c', 'IN', new List<Id>(lineItemIds))
			.execute();
	}

	/**
	 * @description GW-5310 - Count of Repair Center Team Members on a Work Order.
	 * @param workOrderId Work Order Id
	 * @return Team Member count
	 */
	public static Integer countByWorkOrderId(Id workOrderId) {
		if (workOrderId == null) {
			return 0;
		}
		return SoqlQueryBuilder.fromObject('RepairCenterTeamMember__c')
			.whereEquals('WorkOrder__c', workOrderId)
			.countSystemMode();
	}

	/**
	 * @description GW-5310 - Work Order Line signatures for signature override.
	 * @param workOrderId Work Order Id
	 * @return Team Member rows, oldest first
	 */
	public static List<RepairCenterTeamMember__c> selectWorkOrderLineSignaturesForOverride(
		Id workOrderId
	) {
		if (workOrderId == null) {
			return new List<RepairCenterTeamMember__c>();
		}
		return (List<RepairCenterTeamMember__c>) SoqlQueryBuilder.fromObject(
				'RepairCenterTeamMember__c'
			)
			.selectFields(
				new List<String>{
					'Id',
					'Name',
					'Person__c',
					'Person__r.Name',
					'WorkOrderLineItem__c'
				}
			)
			.whereEquals('WorkOrder__c', workOrderId)
			.whereEquals('Type__c', 'Work Order Line')
			.orderBy('CreatedDate')
			.executeSystemMode();
	}

	/**
	 * @description GW-5310 - One signature on a Work Order for coordinator removal.
	 * @param recordId Team Member Id
	 * @param workOrderId Work Order Id
	 * @return Matching Team Member, or null
	 */
	public static RepairCenterTeamMember__c selectByIdForOverride(Id recordId, Id workOrderId) {
		if (recordId == null || workOrderId == null) {
			return null;
		}
		List<RepairCenterTeamMember__c> rows = (List<RepairCenterTeamMember__c>) SoqlQueryBuilder.fromObject(
				'RepairCenterTeamMember__c'
			)
			.selectFields(new List<String>{ 'Id', 'Person__c', 'WorkOrderLineItem__c' })
			.whereEquals('Id', recordId)
			.whereEquals('WorkOrder__c', workOrderId)
			.limitTo(1)
			.executeSystemMode();
		return rows.isEmpty() ? null : rows[0];
	}
}