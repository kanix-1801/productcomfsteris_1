/**
 * @author PSL
 * @date 02-06-2026
 * @description Helper class for creating Tasks related to Orders, Order Lines, and Holds based on TaskSLAConfig metadata.
 *              Provides methods for task creation, owner resolution, SLA calculation, and formula evaluation.
 */
public class OrderLineContactTriggerHelper {

    private  class Acc {
        public List<String> amApp  = new List<String>();
        public List<String> amRem  = new List<String>();
        public List<String> ipmApp = new List<String>();
        public List<String> ipmRem = new List<String>();
        public List<String> asmApp = new List<String>();
        public List<String> asmRem = new List<String>();
    }

    private  class Bucket {
        public Boolean isAM;
        public Boolean isIPM;
        public Boolean isASM;
        public Bucket(Boolean a, Boolean i, Boolean s) {
            this.isAM = a;
            this.isIPM = i;
            this.isASM = s;
        }
    }

    /**
     * Reconciles UNIQUE, comma-separated Sales Rep names on Order based on OrderLineContact__c rows.
     *
     * Entry:
     *   After Insert : salesRepNames(Trigger.new,  null,           false)
     *   After Update : salesRepNames(Trigger.new,  Trigger.oldMap, false)
     *   After Delete : salesRepNames(Trigger.old,  null,           true)
     *
     * Buckets:
     *  - Order.SalesRepsAM__c  : CreateSubcase__c == 'yes - Capital line'
     *  - Order.SalesRepsIPM__c : CreateSubcase__c == 'yes - Service Installation'
     *  - Order.SalesRepsASM__c : ASM will be when the TAS category of the order line is GI SERVICE, SERVICE, SURG SRV, PRL SRV, CRC SRV. 
     */
    public static void salesRepNames(List<OrderLineContact__c> scope,
                                     Map<Id, OrderLineContact__c> oldMap,
                                     Boolean isDelete) {

        if ((scope == null || scope.isEmpty()) && (oldMap == null || oldMap.isEmpty())) {
            return;
        }

        // ------------ Accumulators per Order ------------
        Map<Id, Acc> byOrder = new Map<Id, Acc>();

        // ------------ Collect ids for hydration ------------
        Set<Id> repIds  = new Set<Id>();
        Set<Id> lineIds = new Set<Id>();

        for (OrderLineContact__c r : scope) {
            if (r != null) {
                if (r.SalesRep__c != null) {
                    repIds.add(r.SalesRep__c);
                }
                if (r.OrderLine__c != null) {
                    lineIds.add(r.OrderLine__c);
                }
            }
        }

        if (!isDelete && oldMap != null && !oldMap.isEmpty()) {
            for (OrderLineContact__c o : oldMap.values()) {
                if (o != null) {
                    if (o.SalesRep__c != null) {
                        repIds.add(o.SalesRep__c);
                    }
                    if (o.OrderLine__c != null) {
                        lineIds.add(o.OrderLine__c);
                    }
                }
            }
        }

        // ------------ Hydrate Contacts and Order Lines ------------
        Map<Id, Contact> reps;
        if (repIds.isEmpty()) {
            reps = new Map<Id, Contact>();
        } else {
            reps = new Map<Id, Contact>([
                SELECT Id, Name
                FROM Contact
                WHERE Id IN :repIds
            ]);
        }

    Map<Id, Orderitem> lines;
        if (lineIds.isEmpty()) {
            lines = new Map<Id, Orderitem>();
        } else {
            lines = new Map<Id, Orderitem>([
                SELECT Id, OrderId, CreateSubcase__c, TASSalesCategory__c, product2.SalesCategory__c
                FROM Orderitem
                WHERE Id IN :lineIds
            ]);
        }

        // ------------ Classify into appends/removals ------------
        for (OrderLineContact__c cur : scope) {
            Id curRepId = cur.SalesRep__c;
            Id curLineId = cur.OrderLine__c;
            String curName = (curRepId != null && reps.containsKey(curRepId)) ? reps.get(curRepId).Name : null;
            Orderitem curLine = (curLineId != null) ? lines.get(curLineId) : null;
            Id curOrderId = (curLine != null) ? curLine.OrderId : null;

            OrderLineContact__c oldR = (!isDelete && oldMap != null) ? oldMap.get(cur.Id) : null;
            Id oldRepId = (oldR != null) ? oldR.SalesRep__c : null;
            Id oldLineId = (oldR != null) ? oldR.orderLine__C : null;
            String oldName = (oldRepId != null && reps.containsKey(oldRepId)) ? reps.get(oldRepId).Name : null;
            Orderitem oldLine = (oldLineId != null) ? lines.get(oldLineId) : null;
            Id oldOrderId = (oldLine != null) ? oldLine.OrderId : null;

            Bucket bCur = bucketFor(curLine);
            Bucket bOld = bucketFor(oldLine);

            if (isDelete) {
                // After delete → remove using the old snapshot (cur here is Trigger.old)
                queueRemove(byOrder, curOrderId, 'AM',  curName, bCur.isAM);
                queueRemove(byOrder, curOrderId, 'IPM', curName, bCur.isIPM);
                queueRemove(byOrder, curOrderId, 'ASM', curName, bCur.isASM);
            } else {
                Boolean isUpdateCtx = (oldR != null);

                if (!isUpdateCtx) {
                    // After insert → append only
                    queueAppend(byOrder, curOrderId, 'AM',  curName, bCur.isAM);
                    queueAppend(byOrder, curOrderId, 'IPM', curName, bCur.isIPM);
                    queueAppend(byOrder, curOrderId, 'ASM', curName, bCur.isASM);
                } else {
                    Boolean repChanged  = (oldRepId != curRepId);
                    Boolean lineChanged = (oldLineId != curLineId);

                    // If lookups changed or are now null → remove from OLD order/buckets
                    if (repChanged || lineChanged || curRepId == null || curLineId == null) {
                        queueRemove(byOrder, oldOrderId, 'AM',  oldName, bOld.isAM);
                        queueRemove(byOrder, oldOrderId, 'IPM', oldName, bOld.isIPM);
                        queueRemove(byOrder, oldOrderId, 'ASM', oldName, bOld.isASM);
                    }

                    // If lookups are present now → append to NEW order/buckets
                    if (curRepId != null && curLineId != null) {
                        queueAppend(byOrder, curOrderId, 'AM',  curName, bCur.isAM);
                        queueAppend(byOrder, curOrderId, 'IPM', curName, bCur.isIPM);
                        queueAppend(byOrder, curOrderId, 'ASM', curName, bCur.isASM);
                    }

                    // Same rep & same line, but eligibility changed → move between buckets
                    if (!repChanged && !lineChanged && curRepId != null && curLineId != null) {
                        if (bOld.isAM && !bCur.isAM) {
                            queueRemove(byOrder, curOrderId, 'AM', curName, true);
                        }
                        if (!bOld.isAM && bCur.isAM) {
                            queueAppend(byOrder, curOrderId, 'AM', curName, true);
                        }

                        if (bOld.isIPM && !bCur.isIPM) {
                            queueRemove(byOrder, curOrderId, 'IPM', curName, true);
                        }
                        if (!bOld.isIPM && bCur.isIPM) {
                            queueAppend(byOrder, curOrderId, 'IPM', curName, true);
                        }

                        if (bOld.isASM && !bCur.isASM) {
                            queueRemove(byOrder, curOrderId, 'ASM', curName, true);
                        }
                        if (!bOld.isASM && bCur.isASM) {
                            queueAppend(byOrder, curOrderId, 'ASM', curName, true);
                        }
                    }
                }
            }
        }

        // ------------ Gather impacted orders ------------
        Set<Id> impacted = new Set<Id>();
        for (Id ordId : byOrder.keySet()) {
            Acc a = byOrder.get(ordId);
            if (a != null) {
                if (!a.amApp.isEmpty() || !a.amRem.isEmpty()
                 || !a.ipmApp.isEmpty() || !a.ipmRem.isEmpty()
                 || !a.asmApp.isEmpty() || !a.asmRem.isEmpty()) {
                    if (ordId != null) {
                        impacted.add(ordId);
                    }
                }
            }
        }

        if (impacted.isEmpty()) {
            return;
        }

        // ------------ Pull Orders ------------
        Map<Id, Order> orders = new Map<Id, Order>([
            SELECT Id, SalesRepsAM__c, SalesRepsIPM__c, SalesRepsASM__c
            FROM Order
            WHERE Id IN :impacted
        ]);

        // ------------ Apply removals then appends (unique) ------------
        for (Id ordId : impacted) {
            Order ord = orders.get(ordId);
            if (ord == null) {
                continue;
            }

            Acc a = byOrder.get(ordId);

            String amOld  = safe(ord.SalesRepsAM__c);
            String ipmOld = safe(ord.SalesRepsIPM__c);
            String asmOld = safe(ord.SalesRepsASM__c);

            String amNew  = amendUnique(amOld,  a.amRem,  a.amApp);
            String ipmNew = amendUnique(ipmOld, a.ipmRem, a.ipmApp);
            String asmNew = amendUnique(asmOld, a.asmRem, a.asmApp);

            if (amNew != amOld || ipmNew != ipmOld || asmNew != asmOld) {
                Order updateOrder = ordersToUpdateMap.containsKey(ordId) ? ordersToUpdateMap.get(ordId) : new Order(Id = ordId);
                updateOrder.SalesRepsAM__c = amNew;
                updateOrder.SalesRepsIPM__c = ipmNew;
                updateOrder.SalesRepsASM__c = asmNew;
                ordersToUpdateMap.put(ordId,updateOrder);
            }
        }
    }

    // ---------- Bucket evaluation ----------
    private static Bucket bucketFor(OrderItem line) {
        if (line == null) {
            return new Bucket(false, false, false);
        }
    
        Boolean am  = (line.CreateSubcase__c == 'yes - Capital line');
        Boolean ipm = (line.CreateSubcase__c == 'yes - Service Installation');
    
        Boolean asm = new Set<String>{
            'GI SERVICE',
            'SERVICE',
            'SURG SRV',
            'PRL SRV',
            'CRC SRV'
        }.contains(line.TASSalesCategory__c);
    
        return new Bucket(am, ipm, asm);
    }

    private static void queueAppend(Map<Id, Acc> byOrder, Id ordId, String fld, String name, Boolean eligible) {
        if (ordId == null || String.isBlank(name) || !eligible) {
            return;
        }
        Acc a = byOrder.get(ordId);
        if (a == null) {
            a = new Acc();
            byOrder.put(ordId, a);
        }
        name = name.trim();
        if (fld == 'AM') {
            a.amApp.add(name);
        } else if (fld == 'IPM') {
            a.ipmApp.add(name);
        } else if (fld == 'ASM') {
            a.asmApp.add(name);
        }
    }

    private static void queueRemove(Map<Id, Acc> byOrder, Id ordId, String fld, String name, Boolean eligible) {
        if (ordId == null || String.isBlank(name) || !eligible) {
            return;
        }
        Acc a = byOrder.get(ordId);
        if (a == null) {
            a = new Acc();
            byOrder.put(ordId, a);
        }
        name = name.trim();
        if (fld == 'AM') {
            a.amRem.add(name);
        } else if (fld == 'IPM') {
            a.ipmRem.add(name);
        } else if (fld == 'ASM') {
            a.asmRem.add(name);
        }
    }

    private static String amendUnique(String current, List<String> toRemove, List<String> toAppend) {
        // Start with existing tokens, de-dupe (case-insensitive), order-preserved
        List<String> base = splitTokens(current);
        List<String> uniq = new List<String>();
        Set<String> seenKeys = new Set<String>();

        for (String t : base) {
            if (!String.isBlank(t)) {
                String key = norm(t);
                if (!seenKeys.contains(key)) {
                    uniq.add(t.trim());
                    seenKeys.add(key);
                }
            }
        }

        // Removal keys (case-insensitive)
        Set<String> remKeys = new Set<String>();
        if (toRemove != null) {
            for (String r : toRemove) {
                if (!String.isBlank(r)) {
                    remKeys.add(norm(r));
                }
            }
        }

        // Remove any that match by normalized key
        if (!remKeys.isEmpty()) {
            List<String> kept = new List<String>();
            Set<String> keptKeys = new Set<String>();
            for (String t : uniq) {
                String key = norm(t);
                if (!remKeys.contains(key)) {
                    kept.add(t);
                    keptKeys.add(key);
                }
            }
            uniq = kept;
            seenKeys = keptKeys;
        }

        // Append new names if not already present by normalized key
        if (toAppend != null) {
            for (String a : toAppend) {
                if (!String.isBlank(a)) {
                    String key = norm(a);
                    if (!seenKeys.contains(key)) {
                        uniq.add(a.trim());
                        seenKeys.add(key);
                    }
                }
            }
        }

        String joined = uniq.isEmpty() ? '' : String.join(uniq, ', ');
        if (joined != null && joined.length() > 255) {
            joined = joined.substring(0, 255);
        }
        return joined;
    }

    private static String norm(String s) {
        return (s == null) ? '' : s.trim().toLowerCase();
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
     * @description Returns empty string for null input to simplify concatenation logic.
     * @param s Input string
     * @return Non-null string
     */
    private static String safe(String s) {
        return (s == null) ? '' : s;
    }
    
    
/**
     * @description Aggregates RegionName__c from OrderLineContact__c into Order.Region__c
     *              but ONLY for contacts whose parent OrderItem (OrderLine__c) has
     *              CreateSubcase__c == 'Yes - Capital Line'.
     *              Handles insert/update/delete, removes duplicates, preserves first-seen order,
     *              truncates to 255 chars, and updates only when Order.Region__c actually changes.
     *
     * @param scope   Trigger scope list (Trigger.new for insert/update, Trigger.old for delete)
     * @param oldMap  Trigger.oldMap for update, null for insert/delete
     * @param isDelete true when called from after delete
     */
    public static void aggregateOrderRegions(List<OrderLineContact__c> scope,
                                             Map<Id, OrderLineContact__c> oldMap,
                                             Boolean isDelete) {
       
        if (scope == null || scope.isEmpty()) {
            return;
        }

        final String CAPITAL_FLAG = 'Yes - Capital Line';
        final Integer MAX_LEN = 255;

        // 1) Collect impacted Order Ids (both new and old parents when changed)
        Set<Id> impactedOrderIds = new Set<Id>();
        for (OrderLineContact__c c : scope) {
            if (c == null) {
                continue;
            }
            if (!isDelete) {
                if (c.Order__c != null) {
                    impactedOrderIds.add(c.Order__c);
                }
                if (oldMap != null) {
                    OrderLineContact__c oldRec = oldMap.get(c.Id);
                    if (oldRec != null) {
                        if (oldRec.Order__c != null) {
                            impactedOrderIds.add(oldRec.Order__c);
                        }
                    }
                }
            } else {
                // delete path: scope == Trigger.old
                if (c.Order__c != null) {
                    impactedOrderIds.add(c.Order__c);
                }
            }
        }

        if (impactedOrderIds.isEmpty()) {
            return;
        }

        // 2) For all impacted orders, pull only qualifying OLCs:
        //    - RegionName__c not blank
        //    - OrderLine__r.CreateSubcase__c == 'Yes - Capital Line'
        //    We will initialize every impacted order with an empty list to allow clearing.
        Map<Id, List<String>> regionsByOrder = new Map<Id, List<String>>();
        for (Id ordId : impactedOrderIds) {
            regionsByOrder.put(ordId, new List<String>());
        }

        List<OrderLineContact__c> qualifyingContacts = [
            SELECT Id,
                   Order__c,
                   OrderLine__c,
                   RegionName__c,
                   OrderLine__r.CreateSubcase__c
            FROM OrderLineContact__c
            WHERE Order__c IN :impactedOrderIds
              AND RegionName__c != null
              AND OrderLine__c != null
              AND OrderLine__r.CreateSubcase__c = :CAPITAL_FLAG
        ];

        // 3) Build unique, ordered region lists per Order
        for (OrderLineContact__c olc : qualifyingContacts) {
            if (olc == null) {
                continue;
            }
            if (olc.Order__c == null) {
                continue;
            }
            String region = (olc.RegionName__c == null) ? null : olc.RegionName__c.trim();
            if (String.isBlank(region)) {
                continue;
            }

            List<String> bucket = regionsByOrder.get(olc.Order__c);
            if (bucket == null) {
                bucket = new List<String>();
                regionsByOrder.put(olc.Order__c, bucket);
            }

            // ensure uniqueness while preserving first-seen order
            Boolean seen = false;
            for (String existing : bucket) {
                if (existing != null) {
                    if (existing.equalsIgnoreCase(region)) {
                        seen = true;
                        break;
                    }
                }
            }
            if (!seen) {
                bucket.add(region);
            }
        }

        // 4) Read current Orders to compare old vs new
        Map<Id, Order> ordersById = new Map<Id, Order>([
            SELECT Id, Region__c
            FROM Order
            WHERE Id IN :impactedOrderIds
        ]);

        for (Id ordId : impactedOrderIds) {
            List<String> tokens = regionsByOrder.get(ordId);
            if (tokens == null) {
                tokens = new List<String>();
            }

            // Join with ", "
            String joined = (tokens.isEmpty()) ? '' : String.join(tokens, ', ');

            // Truncate to 255
            if (joined != null) {
                if (joined.length() > MAX_LEN) {
                    joined = joined.substring(0, MAX_LEN);
                }
            } else {
                joined = '';
            }

            Order ord = ordersById.get(ordId);
            String current = (ord != null && ord.Region__c != null) ? ord.Region__c : '';

            if (current == null) {
                current = '';
            }

            if (!current.equals(joined)) {
                Order updateOrder = ordersToUpdateMap.containsKey(ordId) ? ordersToUpdateMap.get(ordId) : new Order(Id = ordId);
                updateOrder.Region__c = joined;
                ordersToUpdateMap.put(ordId,updateOrder);
            }
        }
    }
    
    
    
	 /**
     * @description Aggregates TASZone__c and TerritoryID__c from OrderLineContact__c into
     *              OrderItem.TASZone__c and OrderItem.TerritoryID__c
     *              but ONLY for contacts whose parent OrderItem (OrderLine__c) has
     *              CreateSubcase__c == 'Yes - Capital Line'.
     *              Handles insert/update/delete, removes duplicates, preserves first-seen order,
     *              truncates to 255 chars, and updates only when OrderItem fields actually change.
     *
     * @param scope    Trigger scope list (Trigger.new for insert/update, Trigger.old for delete)
     * @param oldMap   Trigger.oldMap for update, null for insert/delete
     * @param isDelete true when called from after delete
     */
    public static void aggregateOrderItemZonesTerritories(List<OrderLineContact__c> scope,
                                                         Map<Id, OrderLineContact__c> oldMap,
                                                         Boolean isDelete) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        final String CAPITAL_FLAG = 'Yes - Capital Line';
        final Integer MAX_LEN = 255;

        Set<Id> impactedOrderItemIds = new Set<Id>();

        // Collect impacted OrderItem Ids from new and old records
        for (OrderLineContact__c olc : scope) {
            if (olc == null) {
                continue;
            }

            if (!isDelete) {
                if (olc.OrderLine__c != null) {
                    impactedOrderItemIds.add(olc.OrderLine__c);
                }

                if (oldMap != null && oldMap.containsKey(olc.Id)) {
                    OrderLineContact__c oldRec = oldMap.get(olc.Id);
                    if (oldRec != null && oldRec.OrderLine__c != null) {
                        impactedOrderItemIds.add(oldRec.OrderLine__c);
                    }
                }
            } else {
                if (olc.OrderLine__c != null) {
                    impactedOrderItemIds.add(olc.OrderLine__c);
                }
            }
        }

        if (impactedOrderItemIds.isEmpty()) {
            return;
        }

        // Buckets
        Map<Id, String> latestZoneByOrderItem = new Map<Id, String>();
        Map<Id, String> latestRegionByOrderItem = new Map<Id, String>();
        Map<Id, String> latestSalesRepByOrderItem = new Map<Id, String>();
        Map<Id, String> latestTerritoryByOrderItem = new Map<Id, String>();

        // Query all qualifying OLC records for impacted OrderItems.
        // Sorted latest first so first non-blank value can be used.
        List<OrderLineContact__c> qualifyingOLCs = [
            SELECT Id,
                OrderLine__c,
                RegionName__c,
                TASZone__c,
                TerritoryID__c,
                SalesRep__c,
                SalesRep__r.FirstName,
                SalesRep__r.LastName,
                LastModifiedDate,
                CreatedDate,
                OrderLine__r.CreateSubcase__c
            FROM OrderLineContact__c
            WHERE OrderLine__c IN :impactedOrderItemIds
            AND OrderLine__c != null
            AND OrderLine__r.CreateSubcase__c = :CAPITAL_FLAG
            ORDER BY OrderLine__c ASC, CreatedDate DESC
        ];

        // Build latest values and unique territory list
        for (OrderLineContact__c olc : qualifyingOLCs) {
            if (olc == null || olc.OrderLine__c == null) {
                continue;
            }

            Id orderItemId = olc.OrderLine__c;

            // Latest non-blank TAS Zone
            if (!latestZoneByOrderItem.containsKey(orderItemId)
                && !String.isBlank(olc.TASZone__c)) {
                latestZoneByOrderItem.put(orderItemId, olc.TASZone__c.trim());
            }

            // Latest non-blank Region
            if (!latestRegionByOrderItem.containsKey(orderItemId)
                && !String.isBlank(olc.RegionName__c)) {
                latestRegionByOrderItem.put(orderItemId, olc.RegionName__c.trim());
            }

            // Latest non-blank Sales Rep full name
            if (!latestSalesRepByOrderItem.containsKey(orderItemId)
                && olc.SalesRep__c != null) {

                String firstName = olc.SalesRep__r != null ? olc.SalesRep__r.FirstName : null;
                String lastName  = olc.SalesRep__r != null ? olc.SalesRep__r.LastName : null;

                String fullName = buildFullName(firstName, lastName);

                if (!String.isBlank(fullName)) {
                    latestSalesRepByOrderItem.put(orderItemId, fullName);
                }
            }

            // Latest non-blank Territory
            if (!latestTerritoryByOrderItem.containsKey(orderItemId)
                && !String.isBlank(olc.TerritoryID__c)) {
                latestTerritoryByOrderItem.put(orderItemId, olc.TerritoryID__c.trim());
            }
        }

        Map<Id, OrderItem> currentItems = new Map<Id, OrderItem>([
            SELECT Id,
                Region__c,
                Sales_Rep__c,
                TASZone__c,
                TerritoryID__c
            FROM OrderItem
            WHERE Id IN :impactedOrderItemIds
        ]);

        for (Id orderItemId : impactedOrderItemIds) {
            OrderItem existingItem = currentItems.get(orderItemId);
            if (existingItem == null) {
                continue;
            }

            String newRegion = latestRegionByOrderItem.containsKey(orderItemId)
                ? latestRegionByOrderItem.get(orderItemId)
                : '';

            String newSalesRep = latestSalesRepByOrderItem.containsKey(orderItemId)
                ? latestSalesRepByOrderItem.get(orderItemId)
                : '';

            String newZone = latestZoneByOrderItem.containsKey(orderItemId)
                ? latestZoneByOrderItem.get(orderItemId)
                : '';

            String newTerritory = latestTerritoryByOrderItem.containsKey(orderItemId)
                ? latestTerritoryByOrderItem.get(orderItemId)
                : '';

            if (newRegion.length() > MAX_LEN) {
                newRegion = newRegion.substring(0, MAX_LEN);
            }
            if (newSalesRep.length() > MAX_LEN) {
                newSalesRep = newSalesRep.substring(0, MAX_LEN);
            }
            if (newZone.length() > MAX_LEN) {
                newZone = newZone.substring(0, MAX_LEN);
            }
            if (newTerritory.length() > MAX_LEN) {
                newTerritory = newTerritory.substring(0, MAX_LEN);
            }

            if (
                safe(existingItem.Region__c) != newRegion ||
                safe(existingItem.Sales_Rep__c) != newSalesRep ||
                safe(existingItem.TASZone__c) != newZone ||
                safe(existingItem.TerritoryID__c) != newTerritory
            ) {
                OrderItem updateOrderLine = linesToUpdateMap.containsKey(orderItemId) ? linesToUpdateMap.get(orderItemId) : new OrderItem(Id = orderItemId);
                updateOrderLine.Region__c = newRegion;
                updateOrderLine.Sales_Rep__c = newSalesRep;
                updateOrderLine.TASZone__c = newZone;
                updateOrderLine.TerritoryID__c = newTerritory;
                linesToUpdateMap.put(orderItemId,updateOrderLine);
            }
        }
    }

    private static String buildFullName(String firstName, String lastName) {
        String f = String.isBlank(firstName) ? '' : firstName.trim();
        String l = String.isBlank(lastName) ? '' : lastName.trim();

        return String.isBlank(f)
            ? l
            : String.isBlank(l)
                ? f
                : f + ' ' + l;
    }

    public static Map<Id, Order> ordersToUpdateMap = new Map<Id, Order>();
    public static Map<Id, OrderItem> linesToUpdateMap = new Map<Id, OrderItem>();

    public static void processOrders(List<OrderLineContact__c> scope,
                                                         Map<Id, OrderLineContact__c> oldMap,
                                                         Boolean isDelete) {
                                                            salesRepNames(scope,oldMap,isDelete);
                                                            aggregateOrderRegions(scope,oldMap,isDelete);
                                                            if (!ordersToUpdateMap.isEmpty()) {
                                                                update ordersToUpdateMap.values();
                                                            }
                                                         }

    public static void processOrderLines(List<OrderLineContact__c> scope,
                                                         Map<Id, OrderLineContact__c> oldMap,
                                                         Boolean isDelete) {
                                                            aggregateOrderItemZonesTerritories(scope,oldMap,isDelete);
                                                            if (!linesToUpdateMap.isEmpty()) {
                                                                update linesToUpdateMap.values();
                                                            }
                                                         }


}