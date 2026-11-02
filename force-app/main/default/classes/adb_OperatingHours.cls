/**
 * @description GW-3164 - Domain Builder for the OperatingHours SObject.
 *              Provides a fluent API for creating test Operating Hours records.
 */
@IsTest
public class adb_OperatingHours extends adb_DomainBuilder {

    /**
     * @description GW-3164 - Constructs an OperatingHours builder with America/New_York timezone.
     */
    public adb_OperatingHours() {
        super(OperatingHours.SObjectType);
        String uniquePart = String.valueOf(Math.random()).substring(0, 8);
        set(OperatingHours.Name, 'Test OH ' + uniquePart);
        set(OperatingHours.TimeZone, 'America/New_York');
    }

    /**
     * @description GW-3164 - Sets the Operating Hours Name.
     * @param value Name value.
     * @return This builder instance.
     */
    public adb_OperatingHours name(String value) {
        return (adb_OperatingHours) set(OperatingHours.Name, value);
    }

    /**
     * @description GW-3164 - Sets the TimeZone Sid key (e.g. America/New_York).
     * @param value TimeZone value.
     * @return This builder instance.
     */
    public adb_OperatingHours timeZone(String value) {
        return (adb_OperatingHours) set(OperatingHours.TimeZone, value);
    }
}