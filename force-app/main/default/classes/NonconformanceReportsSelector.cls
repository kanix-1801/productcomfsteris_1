/**
 * @author Uptima
 * @date 2026-09-21
 * @group Repair Center
 * @description Selector for NonconformanceReport__c records. Queries use SoqlQueryBuilder.
 */
public with sharing class NonconformanceReportsSelector extends SoqlQueryBuilder {
    private static final List<String> BY_WORK_ORDER_FIELDS = new List<String>{
        'Id',
        'Name',
        'WorkOrder__c',
        'WorkOrderLineItem__c',
        'Account__c',
        'Account__r.Name',
        'RepairCenter__c',
        'RepairCenter__r.Name',
        'Department__c',
        'Department__r.Name',
        'NCRType__c',
        'NCRStatus__c',
        'Asset__c',
        'SerialNumber__c',
        'Product__c',
        'Product__r.Name',
        'ProductLine__c',
        'Model__c',
        'Manufacturer__c',
        'WorkOrderLineItem__r.LineItemNumber',
        'CreatedDate'
    };

    /**
     * @description Binds this selector to NonconformanceReport__c for SoqlQueryBuilder queries.
     */
    public NonconformanceReportsSelector() {
        this.objectName = 'NonconformanceReport__c';
    }

    /**
     * @description GW-5497 / GW-5845 - Loads all NCR headers for a Work Order, number ascending.
     * @param workOrderId Work Order Id
     * @return Related NCR headers
     */
    public static List<NonconformanceReport__c> selectByWorkOrderId(Id workOrderId) {
        if (workOrderId == null) {
            return new List<NonconformanceReport__c>();
        }
        return (List<NonconformanceReport__c>) SoqlQueryBuilder.fromObject('NonconformanceReport__c')
            .selectFields(BY_WORK_ORDER_FIELDS)
            .whereEquals('WorkOrder__c', workOrderId)
            .orderBy('Name')
            .execute();
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
        return (List<NonconformanceReport__c>) SoqlQueryBuilder.fromObject('NonconformanceReport__c')
            .selectFields(new List<String>{ 'Id', 'Name' })
            .whereField('Id', 'IN', new List<Id>(reportIds))
            .execute();
    }
}