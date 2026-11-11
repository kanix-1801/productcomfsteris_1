/**
 * @description Selector class for the RepairCenterRoutingRule__c SObject.
 *              Centralizes all SOQL queries for RepairCenterRoutingRules.
 *              Queries use SoqlQueryBuilder (USER_MODE).
 */
public with sharing class RepairCenterRoutingRulesSelector {

    private static final List<String> BASE_FIELDS = new List<String>{
        'Id',
        'Name',
        'OwnerId',
        'CreatedDate',
        'LastModifiedDate'
    };

    /**
     * @description Retrieves RepairCenterRoutingRule__c records by their Ids.
     * @param ids Set of RepairCenterRoutingRule__c Ids to query.
     * @return List of RepairCenterRoutingRule__c records matching the given Ids.
     */
    public static List<RepairCenterRoutingRule__c> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<RepairCenterRoutingRule__c>();
        }
        return (List<RepairCenterRoutingRule__c>) SoqlQueryBuilder.fromObject(
                'RepairCenterRoutingRule__c'
            )
            .selectFields(BASE_FIELDS)
            .whereField('Id', 'IN', new List<Id>(ids))
            .execute();
    }

    /**
     * @description Retrieves RepairCenterRoutingRule__c records ordered by name.
     *              Preserves prior selectAllActive behavior (no IsActive filter in original SOQL).
     * @return List of RepairCenterRoutingRule__c records.
     */
    public static List<RepairCenterRoutingRule__c> selectAllActive() {
        return (List<RepairCenterRoutingRule__c>) SoqlQueryBuilder.fromObject(
                'RepairCenterRoutingRule__c'
            )
            .selectFields(BASE_FIELDS)
            .orderBy('Name')
            .execute();
    }

    private static final List<String> CREATE_RETURN_ORDER_ROUTING_FIELDS = new List<String>{
        'Id',
        'OperatingUnit__c',
        'ProductLine__c',
        'SubProductLine__c',
        'Manufacturer__c',
        'DeviceType__c',
        'Model__c',
        'ShipState__c',
        'RepairCenter__c',
        'RepairCenter__r.Name',
        'MaxItemsPerReturn__c'
    };

    /**
     * @description GW-1509 - Routing rules for one operating unit (Create Return Order).
     * @param operatingUnit OperatingUnit__c value
     * @return Matching RepairCenterRoutingRule__c rows
     */
    public static List<RepairCenterRoutingRule__c> selectByOperatingUnitForCreateReturnOrder(
        String operatingUnit
    ) {
        if (String.isBlank(operatingUnit)) {
            return new List<RepairCenterRoutingRule__c>();
        }
        return (List<RepairCenterRoutingRule__c>) SoqlQueryBuilder.fromObject(
                'RepairCenterRoutingRule__c'
            )
            .selectFields(CREATE_RETURN_ORDER_ROUTING_FIELDS)
            .whereEquals('OperatingUnit__c', operatingUnit)
            .execute();
    }

}