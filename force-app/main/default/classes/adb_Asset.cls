/**
 * @description Domain Builder for the Asset SObject.
 *              Provides a fluent API for creating test Asset records.
 */
@IsTest
public class adb_Asset extends adb_DomainBuilder {

    /**
     * @description Constructs an Asset builder with reasonable defaults.
     */
    public adb_Asset() {
        super(Asset.SObjectType);
        set(Asset.Name, 'Test Asset ' + String.valueOf(Math.random()).substring(0, 8));
        set(Asset.Status, 'Purchased');
        set(Asset.Quantity, 1);
    }

    /**
     * @description Sets the Asset Name.
     * @param value The name value.
     * @return This builder instance.
     */
    public adb_Asset name(String value) {
        return (adb_Asset) set(Asset.Name, value);
    }

    /**
     * @description Sets the Status.
     * @param value The status picklist value.
     * @return This builder instance.
     */
    public adb_Asset status(String value) {
        return (adb_Asset) set(Asset.Status, value);
    }

    /**
     * @description Sets the Quantity.
     * @param value The quantity value.
     * @return This builder instance.
     */
    public adb_Asset quantity(Decimal value) {
        return (adb_Asset) set(Asset.Quantity, value);
    }

    /**
     * @description Sets the Serial Number.
     * @param value The serial number value.
     * @return This builder instance.
     */
    public adb_Asset serialNumber(String value) {
        return (adb_Asset) set(Asset.SerialNumber, value);
    }

    /**
     * @description Sets the Install Date.
     * @param value The install date value.
     * @return This builder instance.
     */
    public adb_Asset installDate(Date value) {
        return (adb_Asset) set(Asset.InstallDate, value);
    }

    /**
     * @description Sets the Purchase Date.
     * @param value The purchase date value.
     * @return This builder instance.
     */
    public adb_Asset purchaseDate(Date value) {
        return (adb_Asset) set(Asset.PurchaseDate, value);
    }

    /**
     * @description Sets the Description.
     * @param value The description value.
     * @return This builder instance.
     */
    public adb_Asset description(String value) {
        return (adb_Asset) set(Asset.Description, value);
    }

    /**
     * @description Sets the Price.
     * @param value The price value.
     * @return This builder instance.
     */
    public adb_Asset price(Decimal value) {
        return (adb_Asset) set(Asset.Price, value);
    }

    /**
     * @description Sets the related Account lookup.
     * @param account The parent Account builder.
     * @return This builder instance.
     */
    public adb_Asset account(adb_Account account) {
        setParent(Asset.AccountId, account);
        return this;
    }

    /**
     * @description Sets the related Contact lookup.
     * @param contact The parent Contact builder.
     * @return This builder instance.
     */
    public adb_Asset contact(adb_Contact contact) {
        setParent(Asset.ContactId, contact);
        return this;
    }

    /**
     * @description Sets the related Product2 lookup.
     * @param product The parent Product2 builder.
     * @return This builder instance.
     */
    public adb_Asset product(adb_Product2 product) {
        setParent(Asset.Product2Id, product);
        return this;
    }
}