/**
 * @description Trigger handler for the WorkOrder SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 */
public with sharing class WorkOrderTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     *              Delegates to Domain for defaults and validation.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('WorkOrderTrigger')) {
            return;
        }
        WorkOrders domain = new WorkOrders((List<WorkOrder>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     *              Delegates to Domain for validation.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('WorkOrderTrigger')) {
            return;
        }
        WorkOrders domain = new WorkOrders((List<WorkOrder>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes after insert logic.
     *              Delegates to Service for cross-object operations.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('WorkOrderTrigger')) {
            return;
        }
        // Set<Id> workOrderIds = new Map<Id, WorkOrder>((List<WorkOrder>) Trigger.new).keySet();
        // WorkOrdersService.handleNewWorkOrders(workOrderIds);
    }

    /**
     * @description Executes after update logic.
     *              Delegates to Service for cross-object operations.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('WorkOrderTrigger')) {
            return;
        }
        // Set<Id> workOrderIds = new Map<Id, WorkOrder>((List<WorkOrder>) Trigger.new).keySet();
        // WorkOrdersService.handleUpdatedWorkOrders(workOrderIds);
    }
}