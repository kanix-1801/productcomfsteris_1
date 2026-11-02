/**
 * @author PWC Developer
 * @date 2026/07/23
 *
 * @group Product Sub-Group Detail
 *
 * @description GC-3129 Trigger handler for Opportunity Line Item insert, update, delete,
 *              and undelete events. Delegates business logic to OpportunityLineItemService.
 */
public with sharing class OpportunityLineItemTriggerHandler extends TriggerHandler {
    /**
     * @description Runs Product Sub-Group Detail recalculation after insert.
     */
    public override void afterInsert() {
        OpportunityLineItemService.handleAfterInsert((List<OpportunityLineItem>) Trigger.new);
    }

    /**
     * @description Runs Product Sub-Group Detail recalculation after update.
     */
    public override void afterUpdate() {
        OpportunityLineItemService.handleAfterUpdate(
            (List<OpportunityLineItem>) Trigger.new,
            (Map<Id, OpportunityLineItem>) Trigger.oldMap
        );
    }

    /**
     * @description Runs Product Sub-Group Detail recalculation after delete.
     */
    public override void afterDelete() {
        OpportunityLineItemService.handleAfterDelete((List<OpportunityLineItem>) Trigger.old);
    }

    /**
     * @description Runs Product Sub-Group Detail recalculation after undelete.
     */
    public override void afterUndelete() {
        runAfterUndelete((List<OpportunityLineItem>) Trigger.new);
    }

    @TestVisible
    private void runAfterUndelete(List<OpportunityLineItem> lineItems) {
        OpportunityLineItemService.handleAfterUndelete(lineItems);
    }
}