/**
 * @description Domain Builder for the ProductItem SObject.
 *              Provides a fluent API for creating test ProductItem records.
 */
@IsTest
public class adb_ProductItem extends adb_DomainBuilder {

    /**
     * @description Constructs a ProductItem builder with reasonable defaults.
     */
    public adb_ProductItem() {
        super(ProductItem.SObjectType);
        set(ProductItem.QuantityOnHand, 1);
    }

    /**
     * @description Sets the Serial Number.
     * @param value The serial number value.
     * @return This builder instance.
     */
    public adb_ProductItem serialNumber(String value) {
        return (adb_ProductItem) set(ProductItem.SerialNumber, value);
    }

    /**
     * @description Sets the Quantity On Hand.
     * @param value The quantity value.
     * @return This builder instance.
     */
    public adb_ProductItem quantityOnHand(Decimal value) {
        return (adb_ProductItem) set(ProductItem.QuantityOnHand, value);
    }

    /**
     * @description Sets the related Product2 lookup.
     * @param product The parent Product2 builder.
     * @return This builder instance.
     */
    public adb_ProductItem product2(adb_Product2 product) {
        setParent(ProductItem.Product2Id, product);
        return this;
    }

    /**
     * @description Sets the related Location lookup.
     * @param location The parent Location builder.
     * @return This builder instance.
     */
    public adb_ProductItem location(adb_Location location) {
        setParent(ProductItem.LocationId, location);
        return this;
    }
}