/**
 * @author Oskay Taskin
 * @date 2026-07-15
 * @description Selector for WorkOrder SOQL used by Work Order debrief Allowed Unit evaluation and ship date math.
 * @group Work Order Debrief
 */
public with sharing class WorkOrderSelector {
    /** @description Work Order fields required for Allowed Unit evaluation. */
    private static final String ALLOWED_UNIT_FIELDS =
        'Id, AssetId, Asset.PFCL__c, Asset.ServiceBOM__c';

    /**
     * @description Selects Work Orders by Id for Allowed Unit evaluation.
     * @param workOrderIdSet Work Order Ids
     * @return Matching Work Order records
     */
    public static List<WorkOrder> selectByIdsForAllowedUnit(Set<Id> workOrderIdSet) {
        if (workOrderIdSet == null || workOrderIdSet.isEmpty()) {
            return new List<WorkOrder>();
        }

        return Database.query(
            'SELECT ' + ALLOWED_UNIT_FIELDS +
            ' FROM WorkOrder' +
            ' WHERE Id IN :workOrderIdSet' +
            ' WITH SECURITY_ENFORCED'
        );
    }

    /**
     * @description Selects Work Orders with Account Rate List lookup for ES debrief travel and labor pricing.
     * @param workOrderIdSet Work Order Ids
     * @return Matching Work Order records
     */
    public static List<WorkOrder> selectByIdsForRateList(Set<Id> workOrderIdSet) {
        if (workOrderIdSet == null || workOrderIdSet.isEmpty()) {
            return new List<WorkOrder>();
        }

        return [
            SELECT Id, AccountId, Account.RateList__c, RateList__c
            FROM WorkOrder
            WHERE Id IN :workOrderIdSet
        ];
    }

    /****************************************************************************************
     * ADDITIVES FOR SHIP DATE CALCULATION (GW-3918)
     ****************************************************************************************/

    /**
     * @description Queries Work Orders and related Repair Center Operating Hours.
     * @param workOrderIdSet Set of Work Order IDs
     * @return List of Work Orders
     */
    public static List<WorkOrder> selectWorkOrdersWithOperatingHours(Set<Id> workOrderIdSet) {
        return [
            SELECT Id, TurnTime__c, DateReadyforRepair__c, ScheduledShipDate__c,
                   RepairCenter__c, SubStatus__c,
                   RepairCenter__r.OperatingHours__c,
                   RepairCenter__r.OperatingHours__r.TimeZone
            FROM WorkOrder
            WHERE Id IN :workOrderIdSet
        ];
    }

    /**
     * @description Queries Holidays for given Operating Hours.
     * @param operatingHoursIdSet Set of Operating Hours IDs
     * @return List of OperatingHoursHoliday records
     */
    public static List<OperatingHoursHoliday> selectOperatingHoursHolidays(Set<Id> operatingHoursIdSet) {
        return [
            SELECT OperatingHoursId, Holiday.ActivityDate
            FROM OperatingHoursHoliday
            WHERE OperatingHoursId IN :operatingHoursIdSet
        ];
    }
}