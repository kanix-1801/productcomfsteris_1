/**
 * @description Domain Builder for the WorkOrderLineItem SObject.
 *              Provides a fluent API for creating test WorkOrderLineItem records.
 *              Use in the GIVEN section of SETUP / GIVEN / WHEN / THEN test methods.
 */
@IsTest
public class adb_WorkOrderLineItem extends adb_DomainBuilder {

    /**
     * @description Constructs a WorkOrderLineItem builder with reasonable defaults.
     */
    public adb_WorkOrderLineItem() {
        super(WorkOrderLineItem.SObjectType);
        set(WorkOrderLineItem.Status, 'New');
    }

    /**
     * @description Sets the Status.
     * @param value The status picklist value.
     * @return This builder instance.
     */
    public adb_WorkOrderLineItem status(String value) {
        return (adb_WorkOrderLineItem) set(WorkOrderLineItem.Status, value);
    }

    /**
     * @description Sets the Description.
     * @param value The description value.
     * @return This builder instance.
     */
    public adb_WorkOrderLineItem description(String value) {
        return (adb_WorkOrderLineItem) set(WorkOrderLineItem.Description, value);
    }

    /**
     * @description Sets the Duration.
     * @param value The duration value.
     * @return This builder instance.
     */
    public adb_WorkOrderLineItem duration(Decimal value) {
        return (adb_WorkOrderLineItem) set(WorkOrderLineItem.Duration, value);
    }

    /**
     * @description Sets the Duration Type.
     * @param value The duration type picklist value (e.g., 'Hours', 'Minutes').
     * @return This builder instance.
     */
    public adb_WorkOrderLineItem durationType(String value) {
        return (adb_WorkOrderLineItem) set(WorkOrderLineItem.DurationType, value);
    }

    /**
     * @description Sets the Quantity.
     * @param value The quantity value.
     * @return This builder instance.
     */
    public adb_WorkOrderLineItem quantity(Decimal value) {
        return (adb_WorkOrderLineItem) set(WorkOrderLineItem.Quantity, value);
    }

    /**
     * @description Sets the Unit Price.
     * @param value The unit price value.
     * @return This builder instance.
     */
    public adb_WorkOrderLineItem unitPrice(Decimal value) {
        return (adb_WorkOrderLineItem) set(WorkOrderLineItem.UnitPrice, value);
    }

    /**
     * @description Sets the Discount percentage.
     * @param value The discount percentage value.
     * @return This builder instance.
     */
    public adb_WorkOrderLineItem discount(Decimal value) {
        return (adb_WorkOrderLineItem) set(WorkOrderLineItem.Discount, value);
    }

    /**
     * @description Sets the related WorkOrder lookup (master-detail).
     * @param workOrder The parent WorkOrder builder.
     * @return This builder instance.
     */
    public adb_WorkOrderLineItem workOrder(adb_WorkOrder workOrder) {
        setParent(WorkOrderLineItem.WorkOrderId, workOrder);
        return this;
    }
}