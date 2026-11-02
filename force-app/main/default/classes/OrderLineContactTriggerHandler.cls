/**
 * @author PSL
 * @date 02-06-2026
 * @description Trigger handler for OrderLineContact__c records. Delegates to the helper to compute and
 *              populate Sales Rep-related names and manager name fields during insert, update, and delete contexts.
 *              GC-3278 - TAS team access before trigger delegates to TASService.
 */
public class OrderLineContactTriggerHandler extends TriggerHandler{
    
    /**
     * @description Constructor - optionally configure recursion control
     */
    public OrderLineContactTriggerHandler() {
        super();
        
    }

    protected override void afterDelete(){
        if (!AutomationControl.isTriggerEnabled('OrderLineContactTrigger')) return;
        OrderLineContactTriggerHelper.processOrders((List<OrderLineContact__c>) Trigger.old,null,true);
        OrderLineContactTriggerHelper.processOrderLines((List<OrderLineContact__c>) Trigger.old,null,true);
    }
   
    protected override void afterInsert(){
        if (!AutomationControl.isTriggerEnabled('OrderLineContactTrigger')) return;
        OrderLineContactTriggerHelper.processOrders((List<OrderLineContact__c>) Trigger.new,null,false);
        OrderLineContactTriggerHelper.processOrderLines((List<OrderLineContact__c>) Trigger.new,null,false);
    }
    
    protected override void afterUpdate(){
        if (!AutomationControl.isTriggerEnabled('OrderLineContactTrigger')) return;
        OrderLineContactTriggerHelper.processOrders((List<OrderLineContact__c>) Trigger.new,(Map<Id, OrderLineContact__c>) Trigger.oldMap,false);
        OrderLineContactTriggerHelper.processOrderLines((List<OrderLineContact__c>) Trigger.new,(Map<Id, OrderLineContact__c>) Trigger.oldMap,false);
    }

     /**GC-3158
     * Handles before insert trigger events for OrderLineContact__c records.
     * Guards against recursive execution via TriggerControl, then delegates
     * pre-insert processing to TASService.
     * @author Suraj Thapliyal
     */
    @TestVisible
    protected override void beforeInsert() {
        if (!TriggerControl.enterBeforeInsert(OrderLineContact__c.SObjectType)) {
            return;
        }

        TASService.processBeforeInsert((List<OrderLineContact__c>) Trigger.new);
    }

    /**
     * Handles before update trigger events for OrderLineContact__c records.
     * Guards against recursive execution via TriggerControl, then delegates
     * pre-update processing to TASService.
     * @author Suraj Thapliyal
     */
    @TestVisible
    protected override void beforeUpdate() {
        if (!TriggerControl.enterBeforeUpdate(OrderLineContact__c.SObjectType)) {
            return;
        }

        TASService.processBeforeUpdate(
            (List<OrderLineContact__c>) Trigger.new,
            (Map<Id, OrderLineContact__c>) Trigger.oldMap
        );
    }
}