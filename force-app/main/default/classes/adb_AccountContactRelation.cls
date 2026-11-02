/**
 * @description Domain Builder for the AccountContactRelation SObject.
 *              Provides a fluent API for creating test AccountContactRelation records.
 *              Note: AccountContactRelation records are typically created implicitly when
 *              a Contact is associated with an Account. Direct insert may require
 *              Contacts to Be Related to Multiple Accounts to be enabled in the org.
 */
@IsTest
public class adb_AccountContactRelation extends adb_DomainBuilder {

    /**
     * @description Constructs an AccountContactRelation builder with reasonable defaults.
     */
    public adb_AccountContactRelation() {
        super(AccountContactRelation.SObjectType);
        set(AccountContactRelation.IsActive, true);
    }

    /**
     * @description Sets the Roles.
     * @param value The roles value (semicolon-delimited).
     * @return This builder instance.
     */
    public adb_AccountContactRelation roles(String value) {
        return (adb_AccountContactRelation) set(AccountContactRelation.Roles, value);
    }

    /**
     * @description Sets the IsActive flag.
     * @param value The active flag value.
     * @return This builder instance.
     */
    public adb_AccountContactRelation isActive(Boolean value) {
        return (adb_AccountContactRelation) set(AccountContactRelation.IsActive, value);
    }

    /**
     * @description Sets the Start Date.
     * @param value The start date value.
     * @return This builder instance.
     */
    public adb_AccountContactRelation startDate(Date value) {
        return (adb_AccountContactRelation) set(AccountContactRelation.StartDate, value);
    }

    /**
     * @description Sets the End Date.
     * @param value The end date value.
     * @return This builder instance.
     */
    public adb_AccountContactRelation endDate(Date value) {
        return (adb_AccountContactRelation) set(AccountContactRelation.EndDate, value);
    }

    /**
     * @description Sets the related Account lookup.
     * @param account The parent Account builder.
     * @return This builder instance.
     */
    public adb_AccountContactRelation account(adb_Account account) {
        setParent(AccountContactRelation.AccountId, account);
        return this;
    }

    /**
     * @description Sets the related Contact lookup.
     * @param contact The parent Contact builder.
     * @return This builder instance.
     */
    public adb_AccountContactRelation contact(adb_Contact contact) {
        setParent(AccountContactRelation.ContactId, contact);
        return this;
    }
}