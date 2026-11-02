/**
 * @description Domain Builder for the ReturnOrderLineItem SObject.
 *              Provides a fluent API for creating test ReturnOrderLineItem records.
 */
@IsTest
public class adb_ReturnOrderLineItem extends adb_DomainBuilder {

    /**
     * @description Constructs a ReturnOrderLineItem builder with reasonable defaults.
     */
    public adb_ReturnOrderLineItem() {
        super(ReturnOrderLineItem.SObjectType);
        set(ReturnOrderLineItem.QuantityReturned, 1);
    }

    /**
     * @description Sets the Quantity Returned.
     * @param value The quantity returned value.
     * @return This builder instance.
     */
    public adb_ReturnOrderLineItem quantityReturned(Decimal value) {
        return (adb_ReturnOrderLineItem) set(ReturnOrderLineItem.QuantityReturned, value);
    }

    /**
     * @description Sets the Quantity Rejected.
     * @param value The quantity rejected value.
     * @return This builder instance.
     */
    public adb_ReturnOrderLineItem quantityRejected(Decimal value) {
        return (adb_ReturnOrderLineItem) set(ReturnOrderLineItem.QuantityRejected, value);
    }

    /**
     * @description Sets the Reason For Return.
     * @param value The reason for return picklist value.
     * @return This builder instance.
     */
    public adb_ReturnOrderLineItem reasonForReturn(String value) {
        return (adb_ReturnOrderLineItem) set(ReturnOrderLineItem.ReasonForReturn, value);
    }

    /**
     * @description Sets the Description.
     * @param value The description value.
     * @return This builder instance.
     */
    public adb_ReturnOrderLineItem description(String value) {
        return (adb_ReturnOrderLineItem) set(ReturnOrderLineItem.Description, value);
    }

    /**
     * @description Sets the related ReturnOrder lookup.
     * @param returnOrder The parent ReturnOrder builder.
     * @return This builder instance.
     */
    public adb_ReturnOrderLineItem returnOrder(adb_ReturnOrder returnOrder) {
        setParent(ReturnOrderLineItem.ReturnOrderId, returnOrder);
        return this;
    }
}