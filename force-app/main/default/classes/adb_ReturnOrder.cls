/**
 * @description Domain Builder for the ReturnOrder SObject.
 *              Provides a fluent API for creating test ReturnOrder records.
 */
@IsTest
public class adb_ReturnOrder extends adb_DomainBuilder {

    /**
     * @description Constructs a ReturnOrder builder with reasonable defaults.
     */
    public adb_ReturnOrder() {
        super(ReturnOrder.SObjectType);
        set(ReturnOrder.Status, 'Draft');
    }

    /**
     * @description Sets the Status.
     * @param value The status picklist value.
     * @return This builder instance.
     */
    public adb_ReturnOrder status(String value) {
        return (adb_ReturnOrder) set(ReturnOrder.Status, value);
    }

    /**
     * @description Sets the Description.
     * @param value The description value.
     * @return This builder instance.
     */
    public adb_ReturnOrder description(String value) {
        return (adb_ReturnOrder) set(ReturnOrder.Description, value);
    }

    /**
     * @description Sets the related Account lookup.
     * @param account The parent Account builder.
     * @return This builder instance.
     */
    public adb_ReturnOrder account(adb_Account account) {
        setParent(ReturnOrder.AccountId, account);
        return this;
    }

    /**
     * @description Sets the related Contact lookup.
     * @param contact The parent Contact builder.
     * @return This builder instance.
     */
    public adb_ReturnOrder contact(adb_Contact contact) {
        setParent(ReturnOrder.ContactId, contact);
        return this;
    }
}