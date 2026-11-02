/**
 * @author Uptima
 * @date 2026-08-15
 * @group Selectors
 * @description Selector class for the WOAssignmentHistory__c SObject.
 *              Centralizes SOQL for Repair Center assignment history lookups.
 */
public with sharing class WOAssignmentHistoriesSelector {
    /**
     * @description GW-3816 - Selects open assignment history rows for a Work Order and Type
     *              (End Date/Time is null). Uses SYSTEM_MODE so Assign Rack / Assign Technician
     *              scanner profiles can resolve history without full WAH FLS.
     * @param workOrderId Work Order Id
     * @param assignmentType Type__c value (e.g. Technician, Rack)
     * @return Open WO Assignment History rows; empty when inputs blank/null or none found
     * @example
     * List<WOAssignmentHistory__c> openRows =
     *     WOAssignmentHistoriesSelector.selectOpenByWorkOrderIdAndType(woId, 'Technician');
     */
    public static List<WOAssignmentHistory__c> selectOpenByWorkOrderIdAndType(
        Id workOrderId,
        String assignmentType
    ) {
        if (workOrderId == null || String.isBlank(assignmentType)) {
            return new List<WOAssignmentHistory__c>();
        }
        Map<String, Object> binds = new Map<String, Object>{
            'workOrderId' => workOrderId,
            'assignmentType' => assignmentType
        };
        return Database.queryWithBinds(
            'SELECT Id, Type__c, Technician__c, EndDateTime__c FROM WOAssignmentHistory__c ' +
                'WHERE WorkOrder__c = :workOrderId AND EndDateTime__c = NULL ' +
                'AND Type__c = :assignmentType',
            binds,
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * @description GW-3816 - Selects all open assignment history rows for a Work Order
     *              (End Date/Time is null), regardless of Type. Used by Assign Technician
     *              before creating a new Technician assignment.
     * @param workOrderId Work Order Id
     * @return Open WO Assignment History rows; empty when workOrderId is null or none found
     */
    public static List<WOAssignmentHistory__c> selectOpenByWorkOrderId(Id workOrderId) {
        if (workOrderId == null) {
            return new List<WOAssignmentHistory__c>();
        }
        Map<String, Object> binds = new Map<String, Object>{ 'workOrderId' => workOrderId };
        return Database.queryWithBinds(
            'SELECT Id, EndDateTime__c FROM WOAssignmentHistory__c ' +
                'WHERE WorkOrder__c = :workOrderId AND EndDateTime__c = NULL',
            binds,
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * @description GW-3891 - Most recent closed Technician assignment for a Work Order.
     */
    public static List<WOAssignmentHistory__c> selectMostRecentClosedByWorkOrderIdAndType(
        Id workOrderId,
        String assignmentType
    ) {
        if (workOrderId == null || String.isBlank(assignmentType)) {
            return new List<WOAssignmentHistory__c>();
        }
        return [
            SELECT Id, Technician__c, EndDateTime__c
            FROM WOAssignmentHistory__c
            WHERE WorkOrder__c = :workOrderId
                AND Type__c = :assignmentType
                AND EndDateTime__c != NULL
            WITH USER_MODE
            ORDER BY EndDateTime__c DESC
            LIMIT 1
        ];
    }
}