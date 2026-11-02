/**
 * @description Domain Builder for the ProductRelatedMaterial SObject.
 *              Provides a fluent API for creating test ProductRelatedMaterial records.
 */
@IsTest
public class adb_ProductRelatedMaterial extends adb_DomainBuilder {

    /**
     * @description Constructs a ProductRelatedMaterial builder with reasonable defaults.
     */
    public adb_ProductRelatedMaterial() {
        super(ProductRelatedMaterial.SObjectType);
        set(ProductRelatedMaterial.Name, 'Test Related Material ' + String.valueOf(Math.random()).substring(0, 8));
        set(ProductRelatedMaterial.QuantityPerProductUnit, 1);
    }

    /**
     * @description Sets the Quantity Per Product Unit.
     * @param value The quantity value.
     * @return This builder instance.
     */
    public adb_ProductRelatedMaterial quantityPerProductUnit(Decimal value) {
        return (adb_ProductRelatedMaterial) set(ProductRelatedMaterial.QuantityPerProductUnit, value);
    }

    /**
     * @description Sets the related Product2 lookup (ProductId).
     * @param product The parent Product2 builder.
     * @return This builder instance.
     */
    public adb_ProductRelatedMaterial product(adb_Product2 product) {
        setParent(ProductRelatedMaterial.ProductId, product);
        return this;
    }

    /**
     * @description Sets the related component Product2 lookup (ProductComponentId).
     * @param productComponent The parent Product2 builder.
     * @return This builder instance.
     */
    public adb_ProductRelatedMaterial productComponent(adb_Product2 productComponent) {
        setParent(ProductRelatedMaterial.ProductComponentId, productComponent);
        return this;
    }

    /**
     * @description Sets the related ServiceBOM__c lookup.
     * @param serviceBom The parent ServiceBOM__c builder.
     * @return This builder instance.
     */
    public adb_ProductRelatedMaterial serviceBom(adb_ServiceBOM serviceBom) {
        setParent(ProductRelatedMaterial.ServiceBOM__c, serviceBom);
        return this;
    }

    /**
     * @description Sets ComponentSequence__c.
     * @param value Component sequence.
     * @return This builder instance.
     */
    public adb_ProductRelatedMaterial componentSequence(Decimal value) {
        return (adb_ProductRelatedMaterial) set(
            ProductRelatedMaterial.ComponentSequence__c,
            value
        );
    }

    /**
     * @description Sets the Name.
     * @param value Related material name.
     * @return This builder instance.
     */
    public adb_ProductRelatedMaterial name(String value) {
        return (adb_ProductRelatedMaterial) set(ProductRelatedMaterial.Name, value);
    }
}