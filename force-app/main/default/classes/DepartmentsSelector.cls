/**
 * @description Selector class for the Department__c SObject.
 *              Centralizes all SOQL queries for Departments.
 *              Queries use SoqlQueryBuilder (USER_MODE).
 */
public with sharing class DepartmentsSelector {

    private static final List<String> BASE_FIELDS = new List<String>{
        'Id',
        'Name',
        'OwnerId',
        'CreatedDate',
        'LastModifiedDate'
    };

    /**
     * @description Retrieves Department__c records by their Ids.
     * @param ids Set of Department__c Ids to query.
     * @return List of Department__c records matching the given Ids.
     */
    public static List<Department__c> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<Department__c>();
        }
        return (List<Department__c>) SoqlQueryBuilder.fromObject('Department__c')
            .selectFields(BASE_FIELDS)
            .whereField('Id', 'IN', new List<Id>(ids))
            .execute();
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
        return (List<Department__c>) SoqlQueryBuilder.fromObject('Department__c')
            .selectFields(BASE_FIELDS)
            .whereField('Name', 'IN', new List<String>(names))
            .orderBy('Name')
            .execute();
    }

    /**
     * @description GW-1509 - Departments by Id for Create Return Order picklists and summaries.
     * @param departmentIds Department__c Ids
     * @param orderByName When true, order by Name ASC
     * @return Matching Department__c rows
     */
    public static List<Department__c> selectNamesByIds(Set<Id> departmentIds, Boolean orderByName) {
        if (departmentIds == null || departmentIds.isEmpty()) {
            return new List<Department__c>();
        }
        SoqlQueryBuilder builder = SoqlQueryBuilder.fromObject('Department__c')
            .selectFields(new List<String>{ 'Id', 'Name' })
            .whereField('Id', 'IN', new List<Id>(departmentIds));
        if (orderByName == true) {
            builder.orderBy('Name');
        }
        return (List<Department__c>) builder.execute();
    }

}