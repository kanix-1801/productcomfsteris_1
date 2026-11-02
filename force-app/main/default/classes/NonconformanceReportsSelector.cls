/**
 * @author Uptima
 * @date 2026-09-21
 * @group Repair Center
 * @description Selector for NonconformanceReport__c records.
 */
public with sharing class NonconformanceReportsSelector {
    /**
     * @description GW-5497 / GW-5845 - Loads all NCR headers for a Work Order, number ascending.
     * @param workOrderId Work Order Id
     * @return Related NCR headers
     */
    public static List<NonconformanceReport__c> selectByWorkOrderId(Id workOrderId) {
        if (workOrderId == null) {
            return new List<NonconformanceReport__c>();
        }
        return [
            SELECT
                Id,
                Name,
                WorkOrder__c,
                WorkOrderLineItem__c,
                Account__c,
                Account__r.Name,
                RepairCenter__c,
                RepairCenter__r.Name,
                Department__c,
                Department__r.Name,
                NCRType__c,
                NCRStatus__c,
                Asset__c,
                SerialNumber__c,
                Product__c,
                Product__r.Name,
                ProductLine__c,
                Model__c,
                Manufacturer__c,
                WorkOrderLineItem__r.LineItemNumber,
                CreatedDate
            FROM NonconformanceReport__c
            WHERE WorkOrder__c = :workOrderId
            WITH USER_MODE
            ORDER BY Name ASC
        ];
    }

    /**
     * @description Loads NCR headers by Id in user mode.
     * @param reportIds Nonconformance Report Ids
     * @return Matching NCR headers
     */
    public static List<NonconformanceReport__c> selectById(Set<Id> reportIds) {
        if (reportIds == null || reportIds.isEmpty()) {
            return new List<NonconformanceReport__c>();
        }
        return [
            SELECT Id, Name
            FROM NonconformanceReport__c
            WHERE Id IN :reportIds
            WITH USER_MODE
        ];
    }
}