/**
 * @description Domain Builder for the CustomerPreference__c SObject.
 *              Provides a fluent API for creating test CustomerPreference__c records.
 */
@IsTest
public class adb_CustomerPreference extends adb_DomainBuilder {
    /**
     * @description Constructs a CustomerPreference__c builder with reasonable defaults.
     */
    public adb_CustomerPreference() {
        super(CustomerPreference__c.SObjectType);
        set(
            CustomerPreference__c.Name,
            'Test Preference ' + String.valueOf(Math.random()).substring(0, 8)
        );
        set(CustomerPreference__c.StartDate__c, Date.today().addDays(-1));
        set(CustomerPreference__c.EndDate__c, Date.today().addDays(30));
    }

    /**
     * @description Sets the Name.
     * @param value The name value.
     * @return This builder instance.
     */
    public adb_CustomerPreference name(String value) {
        return (adb_CustomerPreference) set(CustomerPreference__c.Name, value);
    }

    /**
     * @description Sets RecordType by DeveloperName.
     * @param developerName RecordType DeveloperName.
     * @return This builder instance.
     */
    public adb_CustomerPreference setRecordType(String developerName) {
        super.recordType(developerName);
        return this;
    }

    /**
     * @description Sets PreferenceType__c.
     * @param value Preference type picklist value.
     * @return This builder instance.
     */
    public adb_CustomerPreference preferenceType(String value) {
        return (adb_CustomerPreference) set(CustomerPreference__c.PreferenceType__c, value);
    }

    /**
     * @description Sets PreferenceValue__c.
     * @param value Preference value text.
     * @return This builder instance.
     */
    public adb_CustomerPreference preferenceValue(String value) {
        return (adb_CustomerPreference) set(CustomerPreference__c.PreferenceValue__c, value);
    }

    /**
     * @description Sets ProductLine__c.
     * @param value Product line value (null for all product lines).
     * @return This builder instance.
     */
    public adb_CustomerPreference productLine(String value) {
        return (adb_CustomerPreference) set(CustomerPreference__c.ProductLine__c, value);
    }

    /**
     * @description Sets StartDate__c.
     * @param value Start date.
     * @return This builder instance.
     */
    public adb_CustomerPreference startDate(Date value) {
        return (adb_CustomerPreference) set(CustomerPreference__c.StartDate__c, value);
    }

    /**
     * @description Sets EndDate__c.
     * @param value End date.
     * @return This builder instance.
     */
    public adb_CustomerPreference endDate(Date value) {
        return (adb_CustomerPreference) set(CustomerPreference__c.EndDate__c, value);
    }

    /**
     * @description Sets the Account lookup relationship.
     * @param accountBuilder The adb_Account builder instance.
     * @return This builder instance.
     */
    public adb_CustomerPreference account(adb_Account accountBuilder) {
        setParent(CustomerPreference__c.Account__c, accountBuilder);
        return this;
    }
}