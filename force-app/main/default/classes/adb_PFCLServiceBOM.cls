/**
 * @description Domain Builder for the PFCLServiceBOM__c SObject.
 *              Provides a fluent API for creating test PFCLServiceBOM__c junction records.
 */
@IsTest
public class adb_PFCLServiceBOM extends adb_DomainBuilder {

    /**
     * @description Constructs a PFCLServiceBOM__c builder with reasonable defaults.
     */
    public adb_PFCLServiceBOM() {
        super(PFCLServiceBOM__c.SObjectType);
    }

    /**
     * @description Sets the related PFCL lookup.
     * @param pfcl The parent PFCL__c builder.
     * @return This builder instance.
     */
    public adb_PFCLServiceBOM pfcl(adb_PFCL pfcl) {
        setParent(PFCLServiceBOM__c.PFCL__c, pfcl);
        return this;
    }

    /**
     * @description Sets the related Service BOM lookup.
     * @param serviceBom The parent ServiceBOM__c builder.
     * @return This builder instance.
     */
    public adb_PFCLServiceBOM serviceBom(adb_ServiceBOM serviceBom) {
        setParent(PFCLServiceBOM__c.ServiceBOM__c, serviceBom);
        return this;
    }
}