/**
 * @description Domain Builder for the PricebookEntry SObject.
 *              Provides a fluent API for creating test PricebookEntry records.
 */
@IsTest
public class adb_PricebookEntry extends adb_DomainBuilder {
    /**
     * @description Constructs a PricebookEntry builder with reasonable defaults.
     */
    public adb_PricebookEntry() {
        super(PricebookEntry.SObjectType);
        set(PricebookEntry.Pricebook2Id, Test.getStandardPricebookId());
        set(PricebookEntry.UnitPrice, 1);
        set(PricebookEntry.IsActive, true);
    }

    /**
     * @description Sets Pricebook2Id.
     * @param value Pricebook Id.
     * @return This builder instance.
     */
    public adb_PricebookEntry pricebook2Id(Id value) {
        return (adb_PricebookEntry) set(PricebookEntry.Pricebook2Id, value);
    }

    /**
     * @description Sets the related Product2 lookup.
     * @param product The parent Product2 builder.
     * @return This builder instance.
     */
    public adb_PricebookEntry product(adb_Product2 product) {
        setParent(PricebookEntry.Product2Id, product);
        return this;
    }

    /**
     * @description Sets UnitPrice.
     * @param value Unit price.
     * @return This builder instance.
     */
    public adb_PricebookEntry unitPrice(Decimal value) {
        return (adb_PricebookEntry) set(PricebookEntry.UnitPrice, value);
    }

    /**
     * @description Sets IsActive.
     * @param value Active flag.
     * @return This builder instance.
     */
    public adb_PricebookEntry isActive(Boolean value) {
        return (adb_PricebookEntry) set(PricebookEntry.IsActive, value);
    }
}