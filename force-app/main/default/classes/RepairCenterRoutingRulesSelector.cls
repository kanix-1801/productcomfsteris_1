/**
 * @description Selector class for the RepairCenterRoutingRule__c SObject.
 *              Centralizes all SOQL queries for RepairCenterRoutingRules.
 *              Enforces security via WITH SECURITY_ENFORCED.
 */
public with sharing class RepairCenterRoutingRulesSelector {

    private static final String BASE_FIELDS =
        'Id, Name, OwnerId, CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves RepairCenterRoutingRule__c records by their Ids.
     * @param ids Set of RepairCenterRoutingRule__c Ids to query.
     * @return List of RepairCenterRoutingRule__c records matching the given Ids.
     */
    public static List<RepairCenterRoutingRule__c> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<RepairCenterRoutingRule__c>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM RepairCenterRoutingRule__c' +
            ' WHERE Id IN :ids' +
            ' WITH SECURITY_ENFORCED'
        );
    }

    /**
     * @description Retrieves all active RepairCenterRoutingRule__c records ordered by priority.
     * @return List of active RepairCenterRoutingRule__c records.
     */
    public static List<RepairCenterRoutingRule__c> selectAllActive() {
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM RepairCenterRoutingRule__c' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY Name ASC'
        );
    }
}