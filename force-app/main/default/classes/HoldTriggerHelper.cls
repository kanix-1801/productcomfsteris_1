/**
 * @author PSL
 * @date 02-06-2026
 * @description Helper class to reconcile Order-level hold summary fields from OrderAndOrderLineHold__c activity.
 *              Computes and updates:
 *                - ReasonProcessHold__c with unique, comma-separated ReasonCode__c values
 *                - OtherHolds__c with unique, comma-separated Hold Name values
 *              Handles insert/update transitions (e.g., Active toggles, reason/name changes, release date changes),
 *              applies removals then appends, de-duplicates while preserving order, truncates to field length, and
 *              performs selective DML only when values change.
 */
public class HoldTriggerHelper {

    /**
     * @description Reconciles Order.ReasonProcessHold__c from OrderAndOrderLineHold__c changes.
     *              Removes reasons when deactivated/changed, appends active current reasons, de-duplicates, truncates,
     *              and updates only when value differs.
     * @param newList New list from trigger context
     * @param oldMap Old map from trigger context; null on insert
     * @return void
     */
    public static void processHoldNames(List<OrderAndOrderLineHold__c> newList,
                                        Map<Id, OrderAndOrderLineHold__c> oldMap) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        Boolean isInsert = (oldMap == null);

        Set<Id> impactedOrderIds = new Set<Id>();
        Map<Id, List<String>> toAppendByOrder = new Map<Id, List<String>>();
        Map<Id, List<String>> toRemoveByOrder = new Map<Id, List<String>>();

        for (OrderAndOrderLineHold__c h : newList) {
            if (h == null || h.Order__c == null) {
                continue;
            }

            String curReason = String.isBlank(h.ReasonCode__c) ? null : h.ReasonCode__c.trim();
            OrderAndOrderLineHold__c oldH = isInsert ? null : oldMap.get(h.Id);

            if (isInsert) {
                if (h.Active__c == true && curReason != null) {
                    impactedOrderIds.add(h.Order__c);

                    List<String> app = toAppendByOrder.get(h.Order__c);
                    if (app == null) {
                        app = new List<String>();
                        toAppendByOrder.put(h.Order__c, app);
                    }
                    app.add(curReason);
                }
            } else {

                Boolean activeTurnedOff = (oldH != null && oldH.Active__c == true && h.Active__c == false);
                if (activeTurnedOff) {
                    String reasonToRemove = curReason;
                    if (String.isBlank(reasonToRemove) && oldH != null && !String.isBlank(oldH.ReasonCode__c)) {
                        reasonToRemove = oldH.ReasonCode__c.trim();
                    }
                    if (!String.isBlank(reasonToRemove)) {
                        impactedOrderIds.add(h.Order__c);

                        List<String> rem = toRemoveByOrder.get(h.Order__c);
                        if (rem == null) {
                            rem = new List<String>();
                            toRemoveByOrder.put(h.Order__c, rem);
                        }
                        rem.add(reasonToRemove);
                    }
                }

                Boolean reasonChanged = (oldH != null && h.ReasonCode__c != oldH.ReasonCode__c);
                if (reasonChanged) {
                    if (oldH != null && !String.isBlank(oldH.ReasonCode__c)) {
                        impactedOrderIds.add(h.Order__c);

                        List<String> rem = toRemoveByOrder.get(h.Order__c);
                        if (rem == null) {
                            rem = new List<String>();
                            toRemoveByOrder.put(h.Order__c, rem);
                        }
                        rem.add(oldH.ReasonCode__c.trim());
                    }
                    if (h.Active__c == true && curReason != null) {
                        impactedOrderIds.add(h.Order__c);

                        List<String> app = toAppendByOrder.get(h.Order__c);
                        if (app == null) {
                            app = new List<String>();
                            toAppendByOrder.put(h.Order__c, app);
                        }
                        app.add(curReason);
                    }
                } else {
                    Boolean rrChanged = (oldH != null && h.ReasonResolvedDate__c != oldH.ReasonResolvedDate__c);
                    if (rrChanged && h.Active__c == true && curReason != null) {
                        impactedOrderIds.add(h.Order__c);

                        List<String> app = toAppendByOrder.get(h.Order__c);
                        if (app == null) {
                            app = new List<String>();
                            toAppendByOrder.put(h.Order__c, app);
                        }
                        app.add(curReason);
                    }
                }

            }
        }

        if (impactedOrderIds.isEmpty()) {
            return;
        }

        Map<Id, Order> orders = new Map<Id, Order>([
            SELECT Id, ReasonProcessHold__c
            FROM Order
            WHERE Id IN :impactedOrderIds
        ]);

        List<Order> toUpdate = new List<Order>();

        for (Id ordId : impactedOrderIds) {
            Order ord = orders.get(ordId);
            String current = (ord != null && ord.ReasonProcessHold__c != null) ? ord.ReasonProcessHold__c : '';

            List<String> tokens = splitTokens(current);

            List<String> removeList = toRemoveByOrder.get(ordId);
            if (removeList != null && !removeList.isEmpty()) {
                Set<String> removeSet = new Set<String>();
                for (String r : removeList) {
                    if (!String.isBlank(r)) {
                        removeSet.add(r);
                    }
                }
                if (!removeSet.isEmpty()) {
                    List<String> kept = new List<String>();
                    for (String t : tokens) {
                        String tt = (t == null) ? null : t.trim();
                        if (String.isBlank(tt)) {
                            continue;
                        }
                        if (!removeSet.contains(tt)) {
                            kept.add(tt);
                        }
                    }
                    tokens = kept;
                }
            }

            List<String> appendList = toAppendByOrder.get(ordId);
            if (appendList != null && !appendList.isEmpty()) {
                for (String a : appendList) {
                    if (!String.isBlank(a)) {
                        tokens.add(a.trim());
                    }
                }
            }

            Set<String> seen = new Set<String>();
            List<String> uniqueTokens = new List<String>();
            for (String t : tokens) {
                String tt = (t == null) ? null : t.trim();
                if (String.isBlank(tt)) continue;
                if (!seen.contains(tt)) {
                    seen.add(tt);
                    uniqueTokens.add(tt);
                }
            }
            tokens = uniqueTokens;
            

            String joined = tokens.isEmpty() ? '' : String.join(tokens, ', ');
            if (joined != null && joined.length() > 255) {
                joined = joined.substring(0, 255);
            }

            String oldVal = (ord != null && ord.ReasonProcessHold__c != null) ? ord.ReasonProcessHold__c : '';
            if (oldVal == null) oldVal = '';
            if (joined == null) joined = '';

            if (oldVal != joined) {
                toUpdate.add(new Order(Id = ordId, ReasonProcessHold__c = joined));
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private static List<String> splitTokens(String s) {
        List<String> out = new List<String>();
        if (String.isBlank(s)) {
            return out;
        }
        for (String part : s.split(',')) {
            String t = (part == null) ? null : part.trim();
            if (!String.isBlank(t)) {
                out.add(t);
            }
        }
        return out;
    }

    /**
     * @description Reconciles Order.OtherHolds__c from OrderAndOrderLineHold__c changes using Hold Name.
     *              Removes names when deactivated/changed, appends active current names, de-duplicates, truncates,
     *              and updates only when value differs.
     * @param newList New list from trigger context
     * @param oldMap Old map from trigger context; null on insert
     * @return void
     */
    public static void holdNamesForOtherHold(List<OrderAndOrderLineHold__c> newList,
                                             Map<Id, OrderAndOrderLineHold__c> oldMap) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        Boolean isInsert = (oldMap == null);

        Set<Id> impactedOrderIds = new Set<Id>();
        Map<Id, List<String>> toAppendByOrder = new Map<Id, List<String>>();
        Map<Id, List<String>> toRemoveByOrder = new Map<Id, List<String>>();

        for (OrderAndOrderLineHold__c h : newList) {
            if (h == null || h.Order__c == null) {
                continue;
            }

            String curHoldName = String.isBlank(h.name) ? null : h.name.trim();
            OrderAndOrderLineHold__c oldH = isInsert ? null : oldMap.get(h.Id);

            if (isInsert) {
                if (h.Active__c == true && curHoldName != null && h.ReasonCode__c == null) {
                    impactedOrderIds.add(h.Order__c);

                    List<String> app = toAppendByOrder.get(h.Order__c);
                    if (app == null) {
                        app = new List<String>();
                        toAppendByOrder.put(h.Order__c, app);
                    }
                    app.add(curHoldName);
                }
            } else {

                Boolean activeTurnedOff = (oldH != null && oldH.Active__c == true && h.Active__c == false);
                if (activeTurnedOff) {
                    String nameToRemove = curHoldName;
                    if (String.isBlank(nameToRemove) && oldH != null && !String.isBlank(oldH.name)) {
                        nameToRemove = oldH.name.trim();
                    }
                    if (!String.isBlank(nameToRemove)) {
                        impactedOrderIds.add(h.Order__c);

                        List<String> rem = toRemoveByOrder.get(h.Order__c);
                        if (rem == null) {
                            rem = new List<String>();
                            toRemoveByOrder.put(h.Order__c, rem);
                        }
                        rem.add(nameToRemove);
                    }
                }

                Boolean nameChanged = (oldH != null && h.name != oldH.name );
                if (nameChanged) {
                    if (oldH != null && !String.isBlank(oldH.name) && h.ReasonCode__c == null) {
                        impactedOrderIds.add(h.Order__c);

                        List<String> rem = toRemoveByOrder.get(h.Order__c);
                        if (rem == null) {
                            rem = new List<String>();
                            toRemoveByOrder.put(h.Order__c, rem);
                        }
                        rem.add(oldH.name.trim());
                    }
                    if (h.Active__c == true && curHoldName != null && h.ReasonCode__c == null) {
                        impactedOrderIds.add(h.Order__c);

                        List<String> app = toAppendByOrder.get(h.Order__c);
                        if (app == null) {
                            app = new List<String>();
                            toAppendByOrder.put(h.Order__c, app);
                        }
                        app.add(curHoldName);
                    }
                } else {
                    Boolean releasedChanged = (oldH != null && h.HoldReleasedDate__c != oldH.HoldReleasedDate__c);
                    if (releasedChanged && h.Active__c == true && curHoldName != null && h.ReasonCode__c == null) {
                        impactedOrderIds.add(h.Order__c);

                        List<String> app = toAppendByOrder.get(h.Order__c);
                        if (app == null) {
                            app = new List<String>();
                            toAppendByOrder.put(h.Order__c, app);
                        }
                        app.add(curHoldName);
                    }
                }

            }
        }

        if (impactedOrderIds.isEmpty()) {
            return;
        }

        Map<Id, Order> orders = new Map<Id, Order>([
            SELECT Id, OtherHolds__c
            FROM Order
            WHERE Id IN :impactedOrderIds
        ]);

        List<Order> toUpdate = new List<Order>();

        for (Id ordId : impactedOrderIds) {
            Order ord = orders.get(ordId);
            String current = (ord != null && ord.OtherHolds__c != null) ? ord.OtherHolds__c : '';

            List<String> tokens = splitTokens(current);

            List<String> removeList = toRemoveByOrder.get(ordId);
            if (removeList != null && !removeList.isEmpty()) {
                Set<String> removeSet = new Set<String>();
                for (String r : removeList) {
                    if (!String.isBlank(r)) {
                        removeSet.add(r);
                    }
                }
                if (!removeSet.isEmpty()) {
                    List<String> kept = new List<String>();
                    for (String t : tokens) {
                        String tt = (t == null) ? null : t.trim();
                        if (String.isBlank(tt)) {
                            continue;
                        }
                        if (!removeSet.contains(tt)) {
                            kept.add(tt);
                        }
                    }
                    tokens = kept;
                }
            }

            List<String> appendList = toAppendByOrder.get(ordId);
            if (appendList != null && !appendList.isEmpty()) {
                for (String a : appendList) {
                    if (!String.isBlank(a)) {
                        tokens.add(a.trim());
                    }
                }
            }

            Set<String> seen = new Set<String>();
            List<String> uniqueTokens = new List<String>();
            for (String t : tokens) {
                String tt = (t == null) ? null : t.trim();
                if (String.isBlank(tt)) continue;
                if (!seen.contains(tt)) {
                    seen.add(tt);
                    uniqueTokens.add(tt);
                }
            }
            tokens = uniqueTokens;
            // ==================================================================

            String joined = tokens.isEmpty() ? '' : String.join(tokens, ', ');
            if (joined != null && joined.length() > 255) {
                joined = joined.substring(0, 255);
            }

            String oldVal = (ord != null && ord.OtherHolds__c != null) ? ord.OtherHolds__c : '';
            if (oldVal == null) oldVal = '';
            if (joined == null) joined = '';

            if (oldVal != joined) {
                toUpdate.add(new Order(Id = ordId, OtherHolds__c = joined));
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
    
    
    
    /**
     * @description Reconciles Order.OrderlevelHold__c from OrderAndOrderLineHold__c changes,
     *              but ONLY for Order-level holds (OrderLine__c == null).
     *              Removes reasons when deactivated/changed, appends active current reasons, de-duplicates, truncates,
     *              and updates only when value differs.
     * @param newList New list from trigger context
     * @param oldMap  Old map from trigger context; null on insert
     */
    public static void processOrderLevelHoldNames(List<OrderAndOrderLineHold__c> newList,
                                                 Map<Id, OrderAndOrderLineHold__c> oldMap) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        Boolean isInsert = (oldMap == null);

        Set<Id> impactedOrderIds = new Set<Id>();
        Map<Id, List<String>> toAppendByOrder = new Map<Id, List<String>>();
        Map<Id, List<String>> toRemoveByOrder = new Map<Id, List<String>>();

        for (OrderAndOrderLineHold__c h : newList) {
            if (h == null || h.Order__c == null) {
                continue;
            }

           
            if (h.OrderLine__c != null) {
                continue;
            }

            String curReason = String.isBlank(h.ReasonCode__c) ? null : h.ReasonCode__c.trim();
            OrderAndOrderLineHold__c oldH = isInsert ? null : oldMap.get(h.Id);

            if (isInsert) {
                if (h.Active__c == true && curReason != null) {
                    impactedOrderIds.add(h.Order__c);

                    List<String> app = toAppendByOrder.get(h.Order__c);
                    if (app == null) {
                        app = new List<String>();
                        toAppendByOrder.put(h.Order__c, app);
                    }
                    app.add(curReason);
                }
            } else {
                Boolean activeTurnedOff = (oldH != null && oldH.Active__c == true && h.Active__c == false);
                if (activeTurnedOff) {
                    String reasonToRemove = curReason;
                    if (String.isBlank(reasonToRemove) && oldH != null && !String.isBlank(oldH.ReasonCode__c)) {
                        reasonToRemove = oldH.ReasonCode__c.trim();
                    }
                    if (!String.isBlank(reasonToRemove)) {
                        impactedOrderIds.add(h.Order__c);

                        List<String> rem = toRemoveByOrder.get(h.Order__c);
                        if (rem == null) {
                            rem = new List<String>();
                            toRemoveByOrder.put(h.Order__c, rem);
                        }
                        rem.add(reasonToRemove);
                    }
                }

                Boolean reasonChanged = (oldH != null && h.ReasonCode__c != oldH.ReasonCode__c);
                if (reasonChanged) {
                    if (oldH != null && !String.isBlank(oldH.ReasonCode__c)) {
                        impactedOrderIds.add(h.Order__c);

                        List<String> rem = toRemoveByOrder.get(h.Order__c);
                        if (rem == null) {
                            rem = new List<String>();
                            toRemoveByOrder.put(h.Order__c, rem);
                        }
                        rem.add(oldH.ReasonCode__c.trim());
                    }
                    if (h.Active__c == true && curReason != null) {
                        impactedOrderIds.add(h.Order__c);

                        List<String> app = toAppendByOrder.get(h.Order__c);
                        if (app == null) {
                            app = new List<String>();
                            toAppendByOrder.put(h.Order__c, app);
                        }
                        app.add(curReason);
                    }
                } else {
                    Boolean rrChanged = (oldH != null && h.ReasonResolvedDate__c != oldH.ReasonResolvedDate__c);
                    if (rrChanged && h.Active__c == true && curReason != null) {
                        impactedOrderIds.add(h.Order__c);

                        List<String> app = toAppendByOrder.get(h.Order__c);
                        if (app == null) {
                            app = new List<String>();
                            toAppendByOrder.put(h.Order__c, app);
                        }
                        app.add(curReason);
                    }
                }
            }
        }

        if (impactedOrderIds.isEmpty()) {
            return;
        }

        
        Integer maxLen = 255;

        Map<Id, Order> orders = new Map<Id, Order>([
            SELECT Id, OrderlevelHold__c
            FROM Order
            WHERE Id IN :impactedOrderIds
        ]);

        List<Order> toUpdate = new List<Order>();

        for (Id ordId : impactedOrderIds) {
            Order ord = orders.get(ordId);
            String current = (ord != null && ord.OrderlevelHold__c != null) ? ord.OrderlevelHold__c : '';

            List<String> tokens = splitTokens(current);

            List<String> removeList = toRemoveByOrder.get(ordId);
            if (removeList != null && !removeList.isEmpty()) {
                Set<String> removeSet = new Set<String>();
                for (String r : removeList) {
                    if (!String.isBlank(r)) {
                        removeSet.add(r.trim());
                    }
                }
                if (!removeSet.isEmpty()) {
                    List<String> kept = new List<String>();
                    for (String t : tokens) {
                        String tt = (t == null) ? null : t.trim();
                        if (String.isBlank(tt)) continue;
                        if (!removeSet.contains(tt)) {
                            kept.add(tt);
                        }
                    }
                    tokens = kept;
                }
            }

            List<String> appendList = toAppendByOrder.get(ordId);
            if (appendList != null && !appendList.isEmpty()) {
                for (String a : appendList) {
                    if (!String.isBlank(a)) {
                        tokens.add(a.trim());
                    }
                }
            }

            // de-dupe preserving order
            Set<String> seen = new Set<String>();
            List<String> uniqueTokens = new List<String>();
            for (String t : tokens) {
                String tt = (t == null) ? null : t.trim();
                if (String.isBlank(tt)) continue;
                if (!seen.contains(tt)) {
                    seen.add(tt);
                    uniqueTokens.add(tt);
                }
            }
            tokens = uniqueTokens;

            String joined = tokens.isEmpty() ? '' : String.join(tokens, ', ');
            if (joined != null && joined.length() > maxLen) {
                joined = joined.substring(0, maxLen);
            }

            String oldVal = (ord != null && ord.OrderlevelHold__c != null) ? ord.OrderlevelHold__c : '';
            if (oldVal == null) oldVal = '';
            if (joined == null) joined = '';

            if (oldVal != joined) {
                toUpdate.add(new Order(Id = ordId, OrderlevelHold__c = joined));
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    
    
    /**
         * @description Reconciles OrderItem.OrderLineHold__c from OrderAndOrderLineHold__c changes,
         *              but ONLY for Order-line holds (OrderLine__c != null).
         *              Removes reasons when deactivated/changed, appends active current reasons, de-duplicates, truncates,
         *              and updates only when value differs.
         * @param newList New list from trigger context
         * @param oldMap  Old map from trigger context; null on insert
         */

    
	public static void processOrderLineHoldNames(List<OrderAndOrderLineHold__c> newList,
                                                Map<Id, OrderAndOrderLineHold__c> oldMap) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        Boolean isInsert = (oldMap == null);

        Set<Id> impactedOrderLineIds = new Set<Id>();
        Map<Id, List<String>> toAppendByLine = new Map<Id, List<String>>();
        Map<Id, List<String>> toRemoveByLine = new Map<Id, List<String>>();

        for (OrderAndOrderLineHold__c h : newList) {
            if (h == null) continue;

            
            if (h.OrderLine__c == null) continue;

            String curReason = String.isBlank(h.ReasonCode__c) ? null : h.ReasonCode__c.trim();
            OrderAndOrderLineHold__c oldH = isInsert ? null : oldMap.get(h.Id);

            if (isInsert) {
                if (h.Active__c == true && curReason != null) {
                    impactedOrderLineIds.add(h.OrderLine__c);

                    List<String> app = toAppendByLine.get(h.OrderLine__c);
                    if (app == null) {
                        app = new List<String>();
                        toAppendByLine.put(h.OrderLine__c, app);
                    }
                    app.add(curReason);
                }
            } else {
                // ---- remove when Active turned off ----
                Boolean activeTurnedOff = (oldH != null && oldH.Active__c == true && h.Active__c == false);
                if (activeTurnedOff) {
                    String reasonToRemove = curReason;
                    if (String.isBlank(reasonToRemove) && oldH != null && !String.isBlank(oldH.ReasonCode__c)) {
                        reasonToRemove = oldH.ReasonCode__c.trim();
                    }
                    if (!String.isBlank(reasonToRemove)) {
                        impactedOrderLineIds.add(h.OrderLine__c);

                        List<String> rem = toRemoveByLine.get(h.OrderLine__c);
                        if (rem == null) {
                            rem = new List<String>();
                            toRemoveByLine.put(h.OrderLine__c, rem);
                        }
                        rem.add(reasonToRemove);
                    }
                }

                // ---- reason changed: remove old, maybe append new ----
                Boolean reasonChanged = (oldH != null && h.ReasonCode__c != oldH.ReasonCode__c);
                if (reasonChanged) {
                    if (oldH != null && !String.isBlank(oldH.ReasonCode__c)) {
                        impactedOrderLineIds.add(h.OrderLine__c);

                        List<String> rem = toRemoveByLine.get(h.OrderLine__c);
                        if (rem == null) {
                            rem = new List<String>();
                            toRemoveByLine.put(h.OrderLine__c, rem);
                        }
                        rem.add(oldH.ReasonCode__c.trim());
                    }
                    if (h.Active__c == true && curReason != null) {
                        impactedOrderLineIds.add(h.OrderLine__c);

                        List<String> app = toAppendByLine.get(h.OrderLine__c);
                        if (app == null) {
                            app = new List<String>();
                            toAppendByLine.put(h.OrderLine__c, app);
                        }
                        app.add(curReason);
                    }
                } else {
                    // ---- resolved date changed: append (existing behavior) ----
                    Boolean rrChanged = (oldH != null && h.ReasonResolvedDate__c != oldH.ReasonResolvedDate__c);
                    if (rrChanged && h.Active__c == true && curReason != null) {
                        impactedOrderLineIds.add(h.OrderLine__c);

                        List<String> app = toAppendByLine.get(h.OrderLine__c);
                        if (app == null) {
                            app = new List<String>();
                            toAppendByLine.put(h.OrderLine__c, app);
                        }
                        app.add(curReason);
                    }
                }
            }
        }

        if (impactedOrderLineIds.isEmpty()) {
            return;
        }

        // ✅ safer than hardcoding: uses actual field length
        Integer maxLen = 255;

        Map<Id, OrderItem> lines = new Map<Id, OrderItem>([
            SELECT Id, OrderLineHold__c
            FROM OrderItem
            WHERE Id IN :impactedOrderLineIds
        ]);

        List<OrderItem> toUpdate = new List<OrderItem>();

        for (Id lineId : impactedOrderLineIds) {
            OrderItem oi = lines.get(lineId);
            String current = (oi != null && oi.OrderLineHold__c != null) ? oi.OrderLineHold__c : '';

            List<String> tokens = splitTokens(current);

            // ---- remove tokens ----
            List<String> removeList = toRemoveByLine.get(lineId);
            if (removeList != null && !removeList.isEmpty()) {
                Set<String> removeSet = new Set<String>();
                for (String r : removeList) {
                    if (!String.isBlank(r)) {
                        removeSet.add(r.trim());
                    }
                }
                if (!removeSet.isEmpty()) {
                    List<String> kept = new List<String>();
                    for (String t : tokens) {
                        String tt = (t == null) ? null : t.trim();
                        if (String.isBlank(tt)) continue;
                        if (!removeSet.contains(tt)) {
                            kept.add(tt);
                        }
                    }
                    tokens = kept;
                }
            }

            // ---- append tokens ----
            List<String> appendList = toAppendByLine.get(lineId);
            if (appendList != null && !appendList.isEmpty()) {
                for (String a : appendList) {
                    if (!String.isBlank(a)) {
                        tokens.add(a.trim());
                    }
                }
            }

            // ---- de-dupe preserving order ----
            Set<String> seen = new Set<String>();
            List<String> uniqueTokens = new List<String>();
            for (String t : tokens) {
                String tt = (t == null) ? null : t.trim();
                if (String.isBlank(tt)) continue;
                if (!seen.contains(tt)) {
                    seen.add(tt);
                    uniqueTokens.add(tt);
                }
            }
            tokens = uniqueTokens;

            String joined = tokens.isEmpty() ? '' : String.join(tokens, ', ');
            if (joined != null && joined.length() > maxLen) {
                joined = joined.substring(0, maxLen);
            }

            String oldVal = (oi != null && oi.OrderLineHold__c != null) ? oi.OrderLineHold__c : '';
            if (oldVal == null) oldVal = '';
            if (joined == null) joined = '';

            if (oldVal != joined) {
                toUpdate.add(new OrderItem(Id = lineId, OrderLineHold__c = joined));
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    

}