/**
 * @description Domain Builder for the Location SObject.
 *              Defaults to LocationType = Repair Center for Repair Center WO tests.
 *              IsInventoryLocation defaults to true so ProductItem tests can use the same builder.
 */
@IsTest
public class adb_Location extends adb_DomainBuilder {

    /**
     * @description Constructs a Location builder as a Repair Center inventory location.
     */
    public adb_Location() {
        super(Schema.Location.SObjectType);
        String uniquePart = String.valueOf(Math.random()).substring(0, 8);
        set(Schema.Location.Name, 'Test Repair Center ' + uniquePart);
        set(Schema.Location.LocationType, 'Repair Center');
        set(Schema.Location.IsInventoryLocation, true);
    }

    /**
     * @description Sets the Location Name.
     * @param value Name value.
     * @return This builder instance.
     */
    public adb_Location name(String value) {
        return (adb_Location) set(Schema.Location.Name, value);
    }

    /**
     * @description Sets LocationType.
     * @param value Location type picklist value.
     * @return This builder instance.
     */
    public adb_Location locationType(String value) {
        return (adb_Location) set(Schema.Location.LocationType, value);
    }

    /**
     * @description Sets IsInventoryLocation.
     * @param value Whether the location is an inventory location.
     * @return This builder instance.
     */
    public adb_Location isInventoryLocation(Boolean value) {
        return (adb_Location) set(Schema.Location.IsInventoryLocation, value);
    }

    /**
     * @description GW-3164 - Sets OperatingHours__c via parent builder.
     * @param operatingHours Operating Hours builder.
     * @return This builder instance.
     */
    public adb_Location operatingHours(adb_OperatingHours operatingHours) {
        setParent(Schema.Location.OperatingHours__c, operatingHours);
        return this;
    }
}