/**
 * @description Domain Builder for the PFCL__c SObject.
 *              Provides a fluent API for creating test PFCL__c records.
 */
@IsTest
public class adb_PFCL extends adb_DomainBuilder {

    /**
     * @description Constructs a PFCL__c builder with reasonable defaults.
     */
    public adb_PFCL() {
        super(PFCL__c.SObjectType);
        set(PFCL__c.Name, 'Test PFCL ' + String.valueOf(Math.random()).substring(0, 8));
    }

    /**
     * @description Sets the Name.
     * @param value The name value.
     * @return This builder instance.
     */
    public adb_PFCL name(String value) {
        return (adb_PFCL) set(PFCL__c.Name, value);
    }

    /**
     * @description Sets the PFCL external id field.
     * @param value The PFCL code value.
     * @return This builder instance.
     */
    public adb_PFCL pfcl(String value) {
        return (adb_PFCL) set(PFCL__c.PFCL__c, value);
    }

    /**
     * @description Sets the Description.
     * @param value The description value.
     * @return This builder instance.
     */
    public adb_PFCL description(String value) {
        return (adb_PFCL) set(PFCL__c.Description__c, value);
    }

    /**
     * @description Sets the Device Type.
     * @param value The device type value.
     * @return This builder instance.
     */
    public adb_PFCL deviceType(String value) {
        return (adb_PFCL) set(PFCL__c.DeviceType__c, value);
    }

    /**
     * @description Sets the Manufacturer.
     * @param value The manufacturer value.
     * @return This builder instance.
     */
    public adb_PFCL manufacturer(String value) {
        return (adb_PFCL) set(PFCL__c.Manufacturer__c, value);
    }

    /**
     * @description Sets the Model.
     * @param value The model value.
     * @return This builder instance.
     */
    public adb_PFCL model(String value) {
        return (adb_PFCL) set(PFCL__c.Model__c, value);
    }

    /**
     * @description Sets the CalibrationRequired flag.
     * @param value The calibration required flag value.
     * @return This builder instance.
     */
    public adb_PFCL calibrationRequired(Boolean value) {
        return (adb_PFCL) set(PFCL__c.CalibrationRequired__c, value);
    }

    /**
     * @description Sets the parent PFCL lookup.
     * @param parent The parent PFCL__c builder.
     * @return This builder instance.
     */
    public adb_PFCL parent(adb_PFCL parent) {
        return (adb_PFCL) setParent(PFCL__c.Parent__c, parent);
    }
}