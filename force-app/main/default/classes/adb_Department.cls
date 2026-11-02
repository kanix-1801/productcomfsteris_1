/**
 * @description Domain Builder for the Department__c SObject.
 *              Provides a fluent API for creating test Department__c records.
 */
@IsTest
public class adb_Department extends adb_DomainBuilder {

    /**
     * @description Constructs a Department__c builder with reasonable defaults.
     */
    public adb_Department() {
        super(Department__c.SObjectType);
        set(Department__c.Name, 'Test Department ' + String.valueOf(Math.random()).substring(0, 8));
    }

    /**
     * @description Sets the Name.
     * @param value The name value.
     * @return This builder instance.
     */
    public adb_Department name(String value) {
        return (adb_Department) set(Department__c.Name, value);
    }
}