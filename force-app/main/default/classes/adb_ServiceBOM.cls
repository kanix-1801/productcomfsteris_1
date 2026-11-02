/**
 * @description Domain Builder for the ServiceBOM__c SObject.
 *              Provides a fluent API for creating test ServiceBOM__c records.
 */
@IsTest
public class adb_ServiceBOM extends adb_DomainBuilder {

    /**
     * @description Constructs a ServiceBOM__c builder with reasonable defaults.
     */
    public adb_ServiceBOM() {
        super(ServiceBOM__c.SObjectType);
        set(ServiceBOM__c.Name, 'Test Service BOM ' + String.valueOf(Math.random()).substring(0, 8));
    }

    /**
     * @description Sets the Name.
     * @param value The name value.
     * @return This builder instance.
     */
    public adb_ServiceBOM name(String value) {
        return (adb_ServiceBOM) set(ServiceBOM__c.Name, value);
    }

    /**
     * @description Sets the External Id.
     * @param value The external id value.
     * @return This builder instance.
     */
    public adb_ServiceBOM externalId(String value) {
        return (adb_ServiceBOM) set(ServiceBOM__c.ExternalID__c, value);
    }

    /**
     * @description Sets the Type.
     * @param value The type picklist value.
     * @return This builder instance.
     */
    public adb_ServiceBOM type(String value) {
        return (adb_ServiceBOM) set(ServiceBOM__c.Type__c, value);
    }

    /**
     * @description Sets the related PFCL lookup.
     * @param pfcl The parent PFCL__c builder.
     * @return This builder instance.
     */
    public adb_ServiceBOM pfcl(adb_PFCL pfcl) {
        setParent(ServiceBOM__c.PFCL__c, pfcl);
        return this;
    }
}