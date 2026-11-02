/**
 * @description Selector class for the Department__c SObject.
 *              Centralizes all SOQL queries for Departments.
 *              Enforces security via WITH SECURITY_ENFORCED.
 */
public with sharing class DepartmentsSelector {

    private static final String BASE_FIELDS =
        'Id, Name, OwnerId, CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves Department__c records by their Ids.
     * @param ids Set of Department__c Ids to query.
     * @return List of Department__c records matching the given Ids.
     */
    public static List<Department__c> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<Department__c>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM Department__c' +
            ' WHERE Id IN :ids' +
            ' WITH SECURITY_ENFORCED'
        );
    }

    /**
     * @description Retrieves Department__c records by Name.
     * @param names Set of Names to filter by.
     * @return List of Department__c records matching the given Names.
     */
    public static List<Department__c> selectByName(Set<String> names) {
        if (names == null || names.isEmpty()) {
            return new List<Department__c>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM Department__c' +
            ' WHERE Name IN :names' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY Name ASC'
        );
    }
}