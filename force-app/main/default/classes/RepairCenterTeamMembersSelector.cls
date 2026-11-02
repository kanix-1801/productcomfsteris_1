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
                WorkOrderLineItem__r.Product__c,
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
}