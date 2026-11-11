/**
 * @author PWC Developer
 * @date 2026/07/27
 *
 * @group Product Sub-Group Detail
 *
 * @description GC-3129 Trigger handler for Quote Line Item insert, update, delete,
 *              and undelete events. Delegates business logic to QuoteLineItemService.
 */
public with sharing class QuoteLineItemTriggerHandler extends TriggerHandler {
    /**
     * @description Runs Product Sub-Group Detail and forecast notification logic after insert.
     */
    public override void afterInsert() {
        QuoteLineItemService.handleAfterInsert((List<QuoteLineItem>) Trigger.new);
        QuoteLineItemOrderCloseService.handleAfterSave((List<QuoteLineItem>) Trigger.new, null);
        // GW-4777 / GW-5676 - Contract Adjustments (Model Qty, Inc/Exc) from the line's coverage JSON
        ContractModifierService.syncAdjustmentsFromQuoteLines((List<QuoteLineItem>) Trigger.new, null);
    }
    
    /**
     * @description Runs Product Sub-Group Detail and forecast notification logic before insert.
     */
    public override void beforeInsert() {
        QuoteLineItemService.handleBeforeInsert((List<QuoteLineItem>) Trigger.new);
    }

    /**
     * @description Runs Product Sub-Group Detail and forecast notification logic after update.
     */
    public override void afterUpdate() {
        QuoteLineItemService.handleAfterUpdate((List<QuoteLineItem>) Trigger.new, (Map<Id, QuoteLineItem>) Trigger.oldMap);
        QuoteLineItemOrderCloseService.handleAfterSave(
            (List<QuoteLineItem>) Trigger.new,
            (Map<Id, QuoteLineItem>) Trigger.oldMap
        );
        // GW-4777 / GW-5676 - Contract Adjustments (Model Qty, Inc/Exc) from the line's coverage JSON
        ContractModifierService.syncAdjustmentsFromQuoteLines((List<QuoteLineItem>) Trigger.new, (Map<Id, QuoteLineItem>) Trigger.oldMap);
    }

    /**
     * @description Runs Product Sub-Group Detail and forecast notification logic after delete.
     */
    public override void afterDelete() {
        QuoteLineItemService.handleAfterDelete((List<QuoteLineItem>) Trigger.old);
    }

    /**
     * @description Runs Product Sub-Group Detail and forecast notification logic after undelete.
     */
    public override void afterUndelete() {
        QuoteLineItemService.handleAfterUndelete((List<QuoteLineItem>) Trigger.new);
    }
}