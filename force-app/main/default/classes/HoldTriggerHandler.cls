/**
 * @author PSL
 * @date 02-06-2026
 * @description Trigger handler for OrderAndOrderLineHold__c events. Orchestrates post-insert/update processing by
 *              delegating to HoldTriggerHelper to reconcile Order-level summary fields:
 *                - ReasonProcessHold__c from ReasonCode__c changes
 *                - OtherHolds__c from Hold Name changes
 *              Ensures helper logic runs consistently in after context and avoids duplicate DML by deferring to the helper.
 */
public class HoldTriggerHandler {

    /**
     * @description Handles after trigger context for OrderAndOrderLineHold__c records by invoking helper routines
     *              to process hold names and compute values for other hold-related fields.
     * @param newList The list of new OrderAndOrderLineHold__c records from Trigger.new
     * @param oldMap The map of old OrderAndOrderLineHold__c records from Trigger.oldMap, keyed by Id
     * @return void
      */
    public static void afterTriggerHandler(List<OrderAndOrderLineHold__c> newList, Map<Id, OrderAndOrderLineHold__c> oldMap) {
        HoldTriggerHelper.processHoldNames(newList, oldMap);
        HoldTriggerHelper.holdNamesForOtherHold(newList, oldMap);
        HoldTriggerHelper.processOrderLevelHoldNames(newList, oldMap);
        HoldTriggerHelper.processOrderLineHoldNames(newList, oldMap);
    }

}