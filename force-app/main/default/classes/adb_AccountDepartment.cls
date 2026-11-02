/**
 * @description Domain Builder for the AccountDepartment__c SObject.
 *              Provides a fluent API for creating test AccountDepartment__c records.
 */
@IsTest
public class adb_AccountDepartment extends adb_DomainBuilder {

    /**
     * @description Constructs an AccountDepartment__c builder with reasonable defaults.
     */
    public adb_AccountDepartment() {
        super(AccountDepartment__c.SObjectType);
        set(AccountDepartment__c.Name, 'Test Account Dept ' + String.valueOf(Math.random()).substring(0, 8));
    }

    /**
     * @description Sets the Name.
     * @param value The name value.
     * @return This builder instance.
     */
    public adb_AccountDepartment name(String value) {
        return (adb_AccountDepartment) set(AccountDepartment__c.Name, value);
    }

    /**
     * @description Sets the related Account lookup.
     * @param account The parent Account builder.
     * @return This builder instance.
     */
    public adb_AccountDepartment account(adb_Account account) {
        setParent(AccountDepartment__c.Account__c, account);
        return this;
    }

    /**
     * @description Sets the related Department lookup.
     * @param department The parent Department__c builder.
     * @return This builder instance.
     */
    public adb_AccountDepartment department(adb_Department department) {
        setParent(AccountDepartment__c.Department__c, department);
        return this;
    }
}