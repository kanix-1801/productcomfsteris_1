/**
 * @description GW-3164 - Domain Builder for the OperatingHoursHoliday junction SObject.
 */
@IsTest
public class adb_OperatingHoursHoliday extends adb_DomainBuilder {

    /**
     * @description GW-3164 - Constructs an OperatingHoursHoliday builder.
     */
    public adb_OperatingHoursHoliday() {
        super(OperatingHoursHoliday.SObjectType);
    }

    /**
     * @description GW-3164 - Sets the Operating Hours parent.
     * @param operatingHours Operating Hours builder.
     * @return This builder instance.
     */
    public adb_OperatingHoursHoliday operatingHours(adb_OperatingHours operatingHours) {
        setParent(OperatingHoursHoliday.OperatingHoursId, operatingHours);
        return this;
    }

    /**
     * @description GW-3164 - Sets the Holiday parent.
     * @param holiday Holiday builder.
     * @return This builder instance.
     */
    public adb_OperatingHoursHoliday holiday(adb_Holiday holiday) {
        setParent(OperatingHoursHoliday.HolidayId, holiday);
        return this;
    }
}