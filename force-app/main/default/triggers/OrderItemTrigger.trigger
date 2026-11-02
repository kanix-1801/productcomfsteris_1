// Trigger: OrderItemTrigger.trigger
trigger OrderItemTrigger on OrderItem (after update) {
    Set<Id> orderIds = new Set<Id>();
    for (OrderItem oi : Trigger.new) {
        if (oi.OrderId != null) orderIds.add(oi.OrderId);
    }
    if (!orderIds.isEmpty()) {
        CBMCaseAutoCloserHandler.evaluateOrders(orderIds);
    }
}