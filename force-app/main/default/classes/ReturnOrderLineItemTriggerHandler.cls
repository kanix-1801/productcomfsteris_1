/**
 * @description Trigger handler for the ReturnOrderLineItem SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 */
public with sharing class ReturnOrderLineItemTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('ReturnOrderLineItemTrigger')) {
            return;
        }
        ReturnOrderLineItems domain = new ReturnOrderLineItems((List<ReturnOrderLineItem>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('ReturnOrderLineItemTrigger')) {
            return;
        }
        ReturnOrderLineItems domain = new ReturnOrderLineItems((List<ReturnOrderLineItem>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes after insert logic.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('ReturnOrderLineItemTrigger')) {
            return;
        }
        // Set<Id> lineItemIds = new Map<Id, ReturnOrderLineItem>((List<ReturnOrderLineItem>) Trigger.new).keySet();
        // ReturnOrderLineItemsService.handleNewReturnOrderLineItems(lineItemIds);
    }

    /**
     * @description Executes after update logic.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('ReturnOrderLineItemTrigger')) {
            return;
        }
        // Set<Id> lineItemIds = new Map<Id, ReturnOrderLineItem>((List<ReturnOrderLineItem>) Trigger.new).keySet();
        // ReturnOrderLineItemsService.handleUpdatedReturnOrderLineItems(lineItemIds);
    }
}