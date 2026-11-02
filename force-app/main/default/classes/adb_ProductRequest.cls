/**
 * @description Domain Builder for the ProductRequest SObject.
 *              Provides a fluent API for creating test ProductRequest records.
 */
@IsTest
public class adb_ProductRequest extends adb_DomainBuilder {

    /**
     * @description Constructs a ProductRequest builder with reasonable defaults.
     */
    public adb_ProductRequest() {
        super(ProductRequest.SObjectType);
        set(ProductRequest.Status, 'Draft');
    }

    /**
     * @description Sets the Status picklist value.
     * @param value The status value.
     * @return This builder instance.
     */
    public adb_ProductRequest status(String value) {
        return (adb_ProductRequest) set(ProductRequest.Status, value);
    }

    /**
     * @description Sets the Description.
     * @param value The description value.
     * @return This builder instance.
     */
    public adb_ProductRequest description(String value) {
        return (adb_ProductRequest) set(ProductRequest.Description, value);
    }

    /**
     * @description Sets the DestinationLocation lookup relationship.
     * @param location The parent Location builder.
     * @return This builder instance.
     */
    public adb_ProductRequest destinationLocation(adb_Location location) {
        return (adb_ProductRequest) setParent(ProductRequest.DestinationLocationId, location);
    }

    /**
     * @description Sets the WorkOrder lookup relationship.
     * @param workOrder The parent WorkOrder builder.
     * @return This builder instance.
     */
    public adb_ProductRequest workOrder(adb_WorkOrder workOrder) {
        return (adb_ProductRequest) setParent(ProductRequest.WorkOrderId, workOrder);
    }

    /**
     * @description Sets the WorkOrderLineItem lookup relationship.
     * @param workOrderLineItem The parent WorkOrderLineItem builder.
     * @return This builder instance.
     */
    public adb_ProductRequest workOrderLineItem(adb_WorkOrderLineItem workOrderLineItem) {
        return (adb_ProductRequest) setParent(ProductRequest.WorkOrderLineItemId, workOrderLineItem);
    }
}