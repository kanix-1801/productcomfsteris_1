/**
 * @description GW-3164 - Domain Builder for the WorkOrder SObject.
 *              Provides a fluent API for creating test WorkOrder records.
 *              Use in the GIVEN section of SETUP / GIVEN / WHEN / THEN test methods.
 */
@IsTest
public class adb_WorkOrder extends adb_DomainBuilder {

    /**
     * @description GW-3164 - Constructs a WorkOrder builder with reasonable defaults.
     */
    public adb_WorkOrder() {
        super(WorkOrder.SObjectType);
        set(WorkOrder.Subject, 'Test Work Order ' + String.valueOf(Math.random()).substring(0, 8));
        set(WorkOrder.Status, 'New');
        set(WorkOrder.Priority, 'Medium');
    }

    /**
     * @description GW-3164 - Sets the Work Order Subject.
     * @param value The subject value.
     * @return This builder instance.
     */
    public adb_WorkOrder subject(String value) {
        return (adb_WorkOrder) set(WorkOrder.Subject, value);
    }

    /**
     * @description GW-3164 - Sets the Work Order Status.
     * @param value The status picklist value.
     * @return This builder instance.
     */
    public adb_WorkOrder status(String value) {
        return (adb_WorkOrder) set(WorkOrder.Status, value);
    }

    /**
     * @description GW-3164 - Sets the Work Order Priority.
     * @param value The priority picklist value.
     * @return This builder instance.
     */
    public adb_WorkOrder priority(String value) {
        return (adb_WorkOrder) set(WorkOrder.Priority, value);
    }

    /**
     * @description GW-3164 - Sets the Description.
     * @param value The description value.
     * @return This builder instance.
     */
    public adb_WorkOrder description(String value) {
        return (adb_WorkOrder) set(WorkOrder.Description, value);
    }

    /**
     * @description GW-3164 - Sets the Start Date.
     * @param value The start date value.
     * @return This builder instance.
     */
    public adb_WorkOrder startDate(DateTime value) {
        return (adb_WorkOrder) set(WorkOrder.StartDate, value);
    }

    /**
     * @description GW-3164 - Sets the End Date.
     * @param value The end date value.
     * @return This builder instance.
     */
    public adb_WorkOrder endDate(DateTime value) {
        return (adb_WorkOrder) set(WorkOrder.EndDate, value);
    }

    /**
     * @description GW-3164 - Sets the Duration.
     * @param value The duration value.
     * @return This builder instance.
     */
    public adb_WorkOrder duration(Decimal value) {
        return (adb_WorkOrder) set(WorkOrder.Duration, value);
    }

    /**
     * @description GW-3164 - Sets the Duration Type.
     * @param value The duration type picklist value (e.g., 'Hours', 'Minutes').
     * @return This builder instance.
     */
    public adb_WorkOrder durationType(String value) {
        return (adb_WorkOrder) set(WorkOrder.DurationType, value);
    }

    /**
     * @description GW-3164 - Sets the related Account lookup.
     * @param account The parent Account builder.
     * @return This builder instance.
     */
    public adb_WorkOrder account(adb_Account account) {
        setParent(WorkOrder.AccountId, account);
        return this;
    }

    /**
     * @description GW-3164 - Sets the related Contact lookup.
     * @param contact The parent Contact builder.
     * @return This builder instance.
     */
    public adb_WorkOrder contact(adb_Contact contact) {
        setParent(WorkOrder.ContactId, contact);
        return this;
    }

    /**
     * @description GW-3164 - Sets TurnTime__c (business days used for scheduled ship date).
     * @param value Turn time in days.
     * @return This builder instance.
     */
    public adb_WorkOrder turnTime(Decimal value) {
        return (adb_WorkOrder) set(WorkOrder.TurnTime__c, value);
    }

    /**
     * @description GW-3164 - Sets DateReadyforRepair__c.
     * @param value Ready-for-repair datetime.
     * @return This builder instance.
     */
    public adb_WorkOrder dateReadyforRepair(Datetime value) {
        return (adb_WorkOrder) set(WorkOrder.DateReadyforRepair__c, value);
    }

    /**
     * @description GW-3164 - Sets ScheduledShipDate__c.
     * @param value Scheduled ship date.
     * @return This builder instance.
     */
    public adb_WorkOrder scheduledShipDate(Date value) {
        return (adb_WorkOrder) set(WorkOrder.ScheduledShipDate__c, value);
    }

    /**
     * @description GW-3164 - Sets the Repair Center Location lookup.
     * @param repairCenter The repair center Location builder.
     * @return This builder instance.
     */
    public adb_WorkOrder repairCenter(adb_Location repairCenter) {
        setParent(WorkOrder.RepairCenter__c, repairCenter);
        return this;
    }

    /**
     * @description GW-3913 / GW-3096 - Sets RecordType by DeveloperName.
     * @param developerName RecordType DeveloperName.
     * @return This builder instance.
     */
    public adb_WorkOrder setRecordType(String developerName) {
        super.recordType(developerName);
        return this;
    }

    /**
     * @description GW-3913 / GW-3096 - Sets the related Asset lookup.
     * @param asset The parent Asset builder.
     * @return This builder instance.
     */
    public adb_WorkOrder asset(adb_Asset asset) {
        setParent(WorkOrder.AssetId, asset);
        return this;
    }

    /**
     * @description GW-3913 / GW-3096 - Sets the parent Work Order lookup.
     * @param parent The parent Work Order builder.
     * @return This builder instance.
     */
    public adb_WorkOrder parentWorkOrder(adb_WorkOrder parent) {
        setParent(WorkOrder.ParentWorkOrderId, parent);
        return this;
    }

    /**
     * @description GW-3913 / GW-3096 - Sets Pricebook2Id.
     * @param value Pricebook Id.
     * @return This builder instance.
     */
    public adb_WorkOrder pricebook2Id(Id value) {
        return (adb_WorkOrder) set(WorkOrder.Pricebook2Id, value);
    }

    /**
     * @description GW-3913 / GW-3096 - Sets ActualShipDate__c.
     * @param value Actual ship date.
     * @return This builder instance.
     */
    public adb_WorkOrder actualShipDate(Date value) {
        return (adb_WorkOrder) set(WorkOrder.ActualShipDate__c, value);
    }

    /**
     * @description GW-3913 / GW-3096 - Sets Evaluator__c.
     * @param value Evaluator User Id.
     * @return This builder instance.
     */
    public adb_WorkOrder evaluator(Id value) {
        return (adb_WorkOrder) set(WorkOrder.Evaluator__c, value);
    }

    // --- START RELEVANT TO GW-4637 ---
    /**
     * @description GW-4637 - Sets WorkOrderType__c.
     * @param value Work Order Type picklist value.
     * @return This builder instance.
     */
    public adb_WorkOrder workOrderType(String value) {
        return (adb_WorkOrder) set(WorkOrder.WorkOrderType__c, value);
    }

    /**
     * @description GW-4637 - Sets ReturnOrder__c.
     * @param value Return Order Id.
     * @return This builder instance.
     */
    public adb_WorkOrder returnOrderId(Id value) {
        return (adb_WorkOrder) set(WorkOrder.ReturnOrder__c, value);
    }
    // --- END RELEVANT TO GW-4637 ---
}