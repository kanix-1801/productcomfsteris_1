/**
 * @description Domain Builder for the Pricebook2 SObject.
 *              Provides a fluent API for creating test Pricebook2 records.
 */
@IsTest
public class adb_Pricebook2 extends adb_DomainBuilder {

    /**
     * @description Constructs a Pricebook2 builder with reasonable defaults.
     */
    public adb_Pricebook2() {
        super(Pricebook2.SObjectType);
        set(Pricebook2.Name, 'Test Pricebook ' + String.valueOf(Math.random()).substring(0, 8));
        set(Pricebook2.IsActive, true);
    }

    /**
     * @description Sets the Pricebook Name.
     * @param value The name value.
     * @return This builder instance.
     */
    public adb_Pricebook2 name(String value) {
        return (adb_Pricebook2) set(Pricebook2.Name, value);
    }

    /**
     * @description Sets IsActive.
     * @param value Active flag.
     * @return This builder instance.
     */
    public adb_Pricebook2 isActive(Boolean value) {
        return (adb_Pricebook2) set(Pricebook2.IsActive, value);
    }
}