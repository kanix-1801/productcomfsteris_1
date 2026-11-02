/**
 * @description GW-3164 - Domain Builder for the Holiday SObject.
 */
@IsTest
public class adb_Holiday extends adb_DomainBuilder {

    /**
     * @description GW-3164 - Constructs a Holiday builder with today's ActivityDate.
     */
    public adb_Holiday() {
        super(Holiday.SObjectType);
        String uniquePart = String.valueOf(Math.random()).substring(0, 8);
        set(Holiday.Name, 'Test Holiday ' + uniquePart);
        set(Holiday.ActivityDate, Date.today());
    }

    /**
     * @description GW-3164 - Sets the Holiday Name.
     * @param value Name value.
     * @return This builder instance.
     */
    public adb_Holiday name(String value) {
        return (adb_Holiday) set(Holiday.Name, value);
    }

    /**
     * @description GW-3164 - Sets ActivityDate.
     * @param value Holiday date.
     * @return This builder instance.
     */
    public adb_Holiday activityDate(Date value) {
        return (adb_Holiday) set(Holiday.ActivityDate, value);
    }
}