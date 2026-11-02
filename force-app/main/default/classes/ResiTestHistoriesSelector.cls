/**
 * @description Selector for ResiTestHistory__c (GW-5492 Receiving).
 */
public with sharing class ResiTestHistoriesSelector extends SoqlQueryBuilder {
    private static final List<String> BASE_FIELDS = new List<String>{
        'Id',
        'WorkOrder__c',
        'WorkOrderLineItem__c',
        'TestCompletionDate__c',
        'DisinfectionStatus__c'
    };

    /**
     * @description Binds this selector to ResiTestHistory__c.
     */
    public ResiTestHistoriesSelector() {
        this.objectName = 'ResiTestHistory__c';
    }

    /**
     * @description Loads Resi-Test History rows by Id.
     * @param ids Record Ids
     * @return Matching rows
     */
    public static List<ResiTestHistory__c> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ResiTestHistory__c>();
        }
        return (List<ResiTestHistory__c>) new ResiTestHistoriesSelector()
            .selectFields(BASE_FIELDS)
            .whereIn('Id', new List<Id>(ids))
            .execute();
    }
}