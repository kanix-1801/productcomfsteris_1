/**
 * @description Domain Builder for the Product2 SObject.
 *              Provides a fluent API for creating test Product2 records.
 */
@IsTest
public class adb_Product2 extends adb_DomainBuilder {

    /**
     * @description Constructs a Product2 builder with reasonable defaults.
     */
    public adb_Product2() {
        super(Product2.SObjectType);
        set(Product2.Name, 'Test Product ' + String.valueOf(Math.random()).substring(0, 8));
        set(Product2.IsActive, true);
    }

    /**
     * @description Sets the Product Name.
     * @param value The name value.
     * @return This builder instance.
     */
    public adb_Product2 name(String value) {
        return (adb_Product2) set(Product2.Name, value);
    }

    /**
     * @description Sets the Product Code.
     * @param value The product code value.
     * @return This builder instance.
     */
    public adb_Product2 productCode(String value) {
        return (adb_Product2) set(Product2.ProductCode, value);
    }

    /**
     * @description Sets the Description.
     * @param value The description value.
     * @return This builder instance.
     */
    public adb_Product2 description(String value) {
        return (adb_Product2) set(Product2.Description, value);
    }

    /**
     * @description Sets the IsActive flag.
     * @param value The active flag value.
     * @return This builder instance.
     */
    public adb_Product2 isActive(Boolean value) {
        return (adb_Product2) set(Product2.IsActive, value);
    }

    /**
     * @description Sets the Family.
     * @param value The family picklist value.
     * @return This builder instance.
     */
    public adb_Product2 family(String value) {
        return (adb_Product2) set(Product2.Family, value);
    }

    /**
     * @description Sets the Stock Keeping Unit.
     * @param value The SKU value.
     * @return This builder instance.
     */
    public adb_Product2 stockKeepingUnit(String value) {
        return (adb_Product2) set(Product2.StockKeepingUnit, value);
    }

    /**
     * @description Sets ProductType__c.
     * @param value Product type picklist value.
     * @return This builder instance.
     */
    public adb_Product2 productType(String value) {
        return (adb_Product2) set(Product2.ProductType__c, value);
    }

    /**
     * @description Sets ProductLine__c.
     * @param value Product line value.
     * @return This builder instance.
     */
    public adb_Product2 productLine(String value) {
        return (adb_Product2) set(Product2.ProductLine__c, value);
    }

    /**
     * @description Sets Manufacturer__c.
     * @param value Manufacturer value.
     * @return This builder instance.
     */
    public adb_Product2 manufacturer(String value) {
        return (adb_Product2) set(Product2.Manufacturer__c, value);
    }

    /**
     * @description Sets Model__c.
     * @param value Model value.
     * @return This builder instance.
     */
    public adb_Product2 model(String value) {
        return (adb_Product2) set(Product2.Model__c, value);
    }

    /**
     * @description Sets EvalDisplayScreen__c.
     * @param value Eval display screen value (e.g. Y/N).
     * @return This builder instance.
     */
    public adb_Product2 evalDisplayScreen(String value) {
        return (adb_Product2) set(Product2.EvalDisplayScreen__c, value);
    }

    /**
     * @description Sets EvalRank__c.
     * @param value Eval rank value.
     * @return This builder instance.
     */
    public adb_Product2 evalRank(String value) {
        return (adb_Product2) set(Product2.EvalRank__c, value);
    }

    /**
     * @description Sets EvalCategory__c.
     * @param value Eval category value.
     * @return This builder instance.
     */
    public adb_Product2 evalCategory(String value) {
        return (adb_Product2) set(Product2.EvalCategory__c, value);
    }

    /**
     * @description Sets SubProductLine__c.
     * @param value Sub product line value.
     * @return This builder instance.
     */
    public adb_Product2 subProductLine(String value) {
        return (adb_Product2) set(Product2.SubProductLine__c, value);
    }

    /**
     * @description Sets Condition__c.
     * @param value Condition value.
     * @return This builder instance.
     */
    public adb_Product2 condition(String value) {
        return (adb_Product2) set(Product2.Condition__c, value);
    }
}