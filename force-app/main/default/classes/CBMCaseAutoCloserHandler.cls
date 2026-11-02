public without sharing class CBMCaseAutoCloserHandler {

    // Normalize variants 
    private static final Set<String> CLOSED_STATUSES    = new Set<String>{ 'closed', 'complete', 'completed' };
    private static final Set<String> CANCELLED_STATUSES = new Set<String>{ 'cancelled', 'canceled' };

    // Task statuses that indicate "open". We fetch by NOT IN ('Completed','Cancelled') below;
    // edit the query if your org uses different terminal values.
    private static final Set<String> TASK_TERMINAL = new Set<String>{ 'Completed', 'Cancelled' };

    public void evaluateAndUpdateCases(List<Case> casesBatch) {
        if (casesBatch == null || casesBatch.isEmpty()) return;

        // Collect orderIds & caseIds
        Set<Id> orderIds = new Set<Id>(); 
        Set<Id> caseIds  = new Set<Id>();
        for (Case c : casesBatch) {
            if (c == null) continue;
            if (c.Order__c != null) orderIds.add(c.Order__c);
            caseIds.add(c.Id);
        }
        if (orderIds.isEmpty()) return;

        // 1) Aggregate order line statuses per Order
        Map<Id, OrderLineStats> statsByOrder = new Map<Id, OrderLineStats>();
        for (OrderItem oi : [
            SELECT Id, OrderId, OrderLineStatus__c, OrderLineType__c
            FROM OrderItem
            WHERE OrderId IN :orderIds
        ]) {
            OrderLineStats s = statsByOrder.get(oi.OrderId);
            if (s == null) {
                s = new OrderLineStats();
                statsByOrder.put(oi.OrderId, s);
            }
            s.total++;
            String normalized = normalize(oi.OrderLineStatus__c);
            if (CLOSED_STATUSES.contains(normalized)) {
                s.closed++;
            } else if (CANCELLED_STATUSES.contains(normalized)) {
                s.cancelled++;
            } else {
                s.other++; // anything not closed/cancelled
            }
        }

        // 2) Block if there are open tasks on the case (NOT in terminal statuses)
        Map<Id, List<Task>> openTasksByCase = new Map<Id, List<Task>>();
        if (!caseIds.isEmpty()) {
            for (Task t : [
                SELECT WhatId, Status
                FROM Task
                WHERE WhatId IN :caseIds
                  AND IsDeleted = FALSE
                  AND Status NOT IN :TASK_TERMINAL
            ]) {
                if (!openTasksByCase.containsKey(t.WhatId)) {
                    openTasksByCase.put(t.WhatId, new List<Task>());
                }
                openTasksByCase.get(t.WhatId).add(t);
            }
        }
    
        // 3) Decide status updates
        List<Case> toUpdate = new List<Case>();
        
        // List of Tasks to be marked Completed
        List<Task> tasksToComplete = new List<Task>();

        for (Case c : casesBatch) {
            if (c == null || c.Order__c == null) continue;

            OrderLineStats s = statsByOrder.get(c.Order__c);
            if (s == null || s.total == 0) {
                // No lines → do nothing
                continue;
            }

            // If any non-closed/cancelled line exists → do nothing
            if (s.other > 0) continue;

            // Only closed and/or cancelled lines remain
            if (s.closed > 0) {
                // If any open tasks exist → skip
                List<Task> openCount = openTasksByCase.get(c.Id);
                if (openCount != null && openCount.size() > 0) {
                    continue;
                }

                // All closed or mix of closed+cancelled → set Closed
                if (c.Status != 'Closed') {
                    c.Status = 'Closed';
                    toUpdate.add(c);
                }
            } else if (s.cancelled == s.total) {
                // If any open tasks exist → skip
                List<Task> openCount = openTasksByCase.get(c.Id);
                if (openCount == null || openCount.size() == 0) {
                    continue;
                }
                // If any open tasks exist → mark complete
                for (Task t : openCount) {
                    t.Status = 'Completed';
                    tasksToComplete.add(t);
                }

                // All cancelled → set Cancelled
                if (c.Status != 'Cancelled') {
                    c.Status = 'Cancelled';
                    toUpdate.add(c);
                }
            }
        }

        if (!tasksToComplete.isEmpty()) {
            update tasksToComplete;
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    // Helpers
    private static String normalize(String s) { return (s == null) ? '' : s.trim().toLowerCase(); }

    private class OrderLineStats {
        Integer total = 0;
        Integer closed = 0;
        Integer cancelled = 0;
        Integer other = 0;
    }
}