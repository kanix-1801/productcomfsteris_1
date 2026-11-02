/**
 * @description Domain Builder for the RepairCenterRoutingRule__c SObject.
 *              Provides a fluent API for creating test RepairCenterRoutingRule__c records.
 */
@IsTest
public class adb_RepairCenterRoutingRule extends adb_DomainBuilder {

    /**
     * @description Constructs a RepairCenterRoutingRule__c builder with reasonable defaults.
     *              Name is an Auto Number field and cannot be set.
     */
    public adb_RepairCenterRoutingRule() {
        super(RepairCenterRoutingRule__c.SObjectType);
        set(RepairCenterRoutingRule__c.Model__c, 'Test Model ' + String.valueOf(Math.random()).substring(0, 8));
    }

    /**
     * @description Sets the Model.
     * @param value The model value.
     * @return This builder instance.
     */
    public adb_RepairCenterRoutingRule model(String value) {
        return (adb_RepairCenterRoutingRule) set(RepairCenterRoutingRule__c.Model__c, value);
    }
}