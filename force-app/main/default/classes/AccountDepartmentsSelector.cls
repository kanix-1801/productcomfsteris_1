/**
 * @description Selector class for the AccountDepartment__c SObject.
 *              Centralizes all SOQL queries for AccountDepartments.
 *              Queries use SoqlQueryBuilder (USER_MODE).
 */
public with sharing class AccountDepartmentsSelector {

    private static final List<String> BASE_FIELDS = new List<String>{
        'Id',
        'Name',
        'Account__c',
        'Department__c',
        'CreatedDate',
        'LastModifiedDate'
    };

    /**
     * @description Retrieves AccountDepartment__c records by their Ids.
     * @param ids Set of AccountDepartment__c Ids to query.
     * @return List of AccountDepartment__c records matching the given Ids.
     */
    public static List<AccountDepartment__c> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<AccountDepartment__c>();
        }
        return (List<AccountDepartment__c>) SoqlQueryBuilder.fromObject('AccountDepartment__c')
            .selectFields(BASE_FIELDS)
            .whereField('Id', 'IN', new List<Id>(ids))
            .execute();
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
        return (List<AccountDepartment__c>) SoqlQueryBuilder.fromObject('AccountDepartment__c')
            .selectFields(BASE_FIELDS)
            .whereField('Account__c', 'IN', new List<Id>(accountIds))
            .orderBy('CreatedDate')
            .execute();
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
        return (List<AccountDepartment__c>) SoqlQueryBuilder.fromObject('AccountDepartment__c')
            .selectFields(BASE_FIELDS)
            .whereField('Department__c', 'IN', new List<Id>(departmentIds))
            .orderBy('CreatedDate')
            .execute();
    }

    /**
     * @description GW-1509 - Account departments for Create Return Order department picklist.
     * @param accountId Account Id
     * @return Matching AccountDepartment__c rows
     */
    public static List<AccountDepartment__c> selectDepartmentsForCreateReturnOrder(Id accountId) {
        if (accountId == null) {
            return new List<AccountDepartment__c>();
        }
        return (List<AccountDepartment__c>) SoqlQueryBuilder.fromObject('AccountDepartment__c')
            .selectFields(new List<String>{ 'Department__c', 'Department__r.Name' })
            .whereEquals('Account__c', accountId)
            .whereField('Department__c', '!=', null)
            .orderBy('Department__r.Name', false, true)
            .execute();
    }

}