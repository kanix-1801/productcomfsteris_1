/**
 * @description Domain Builder for the Contact SObject.
 *              Provides a fluent API for creating test Contact records.
 *              Use in the GIVEN section of SETUP / GIVEN / WHEN / THEN test methods.
 */
@IsTest
public class adb_Contact extends adb_DomainBuilder {

    /**
     * @description Constructs a Contact builder with reasonable defaults.
     */
    public adb_Contact() {
        super(Contact.SObjectType);
        set(Contact.LastName, 'TestContact ' + String.valueOf(Math.random()).substring(0, 8));
    }

    /**
     * @description Sets the Contact First Name.
     * @param value The first name value.
     * @return This builder instance.
     */
    public adb_Contact firstName(String value) {
        return (adb_Contact) set(Contact.FirstName, value);
    }

    /**
     * @description Sets the Contact Last Name.
     * @param value The last name value.
     * @return This builder instance.
     */
    public adb_Contact lastName(String value) {
        return (adb_Contact) set(Contact.LastName, value);
    }

    /**
     * @description Sets the Contact Email.
     * @param value The email value.
     * @return This builder instance.
     */
    public adb_Contact email(String value) {
        return (adb_Contact) set(Contact.Email, value);
    }

    /**
     * @description Sets the Contact Phone.
     * @param value The phone value.
     * @return This builder instance.
     */
    public adb_Contact phone(String value) {
        return (adb_Contact) set(Contact.Phone, value);
    }

    /**
     * @description Sets the Contact Title.
     * @param value The title value.
     * @return This builder instance.
     */
    public adb_Contact title(String value) {
        return (adb_Contact) set(Contact.Title, value);
    }

    /**
     * @description Sets the Contact Department.
     * @param value The department value.
     * @return This builder instance.
     */
    public adb_Contact department(String value) {
        return (adb_Contact) set(Contact.Department, value);
    }

    /**
     * @description Sets the related Account lookup.
     * @param account The parent Account builder.
     * @return This builder instance.
     */
    public adb_Contact account(adb_Account account) {
        setParent(Contact.AccountId, account);
        return this;
    }
}