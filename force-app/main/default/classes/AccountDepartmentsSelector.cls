/**
 * @description Selector class for the AccountDepartment__c SObject.
 *              Centralizes all SOQL queries for AccountDepartments.
 *              Enforces security via WITH SECURITY_ENFORCED.
 */
public with sharing class AccountDepartmentsSelector {

    private static final String BASE_FIELDS =
        'Id, Name, Account__c, Department__c, CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves AccountDepartment__c records by their Ids.
     * @param ids Set of AccountDepartment__c Ids to query.
     * @return List of AccountDepartment__c records matching the given Ids.
     */
    public static List<AccountDepartment__c> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<AccountDepartment__c>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM AccountDepartment__c' +
            ' WHERE Id IN :ids' +
            ' WITH SECURITY_ENFORCED'
        );
    }

    /**
     * @description Retrieves AccountDepartment__c records by Account Id.
     * @param accountIds Set of Account Ids to filter by.
     * @return List of AccountDepartment__c records for the given Accounts.
     */
    public static List<AccountDepartment__c> selectByAccountId(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<AccountDepartment__c>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM AccountDepartment__c' +
            ' WHERE Account__c IN :accountIds' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY CreatedDate ASC'
        );
    }

    /**
     * @description Retrieves AccountDepartment__c records by Department Id.
     * @param departmentIds Set of Department__c Ids to filter by.
     * @return List of AccountDepartment__c records for the given Departments.
     */
    public static List<AccountDepartment__c> selectByDepartmentId(Set<Id> departmentIds) {
        if (departmentIds == null || departmentIds.isEmpty()) {
            return new List<AccountDepartment__c>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM AccountDepartment__c' +
            ' WHERE Department__c IN :departmentIds' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY CreatedDate ASC'
        );
    }
}