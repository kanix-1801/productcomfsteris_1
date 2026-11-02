/**
 * @description Trigger handler for the WorkOrderLineItem SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 */
public with sharing class WorkOrderLineItemTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     *              Delegates to Domain for defaults and validation.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('WorkOrderLineItemTrigger')) {
            return;
        }
        WorkOrderLineItems domain = new WorkOrderLineItems((List<WorkOrderLineItem>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     *              Delegates to Domain for validation.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('WorkOrderLineItemTrigger')) {
            return;
        }
        WorkOrderLineItems domain = new WorkOrderLineItems((List<WorkOrderLineItem>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes after insert logic.
     *              Delegates to Service for cross-object operations.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('WorkOrderLineItemTrigger')) {
            return;
        }
        // Set<Id> lineItemIds = new Map<Id, WorkOrderLineItem>((List<WorkOrderLineItem>) Trigger.new).keySet();
        // WorkOrderLineItemsService.handleNewLineItems(lineItemIds);
    }

    /**
     * @description Executes after update logic.
     *              Delegates to Service for cross-object operations.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('WorkOrderLineItemTrigger')) {
            return;
        }
        // Set<Id> lineItemIds = new Map<Id, WorkOrderLineItem>((List<WorkOrderLineItem>) Trigger.new).keySet();
        // WorkOrderLineItemsService.handleUpdatedLineItems(lineItemIds);
    }
}