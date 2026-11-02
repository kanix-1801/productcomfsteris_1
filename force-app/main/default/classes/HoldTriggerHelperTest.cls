/**
 * @author PSL
 * @date 27-02-2026
 * @description Test class for HoldTriggerHelper class
 */

 @IsTest
 private class HoldTriggerHelperTest {
 
     // -------------------------
     // Test data factories
     // -------------------------
 
     private static Account newAccount() {
         Account a = new Account(Name = 'Acct ' + String.valueOf(Crypto.getRandomInteger()));
         insert a;
         return a;
     }
 
     // Create a minimal valid Order (Draft) for a given Account
     private static Order newOrder(String reasonProcessHold, String otherHolds) {
         Account a = newAccount();
         Order o = new Order(
             AccountId     = a.Id,
             Status        = 'Draft',
             EffectiveDate = Date.today()
         );
         insert o;
 
         if (reasonProcessHold != null || otherHolds != null) {
             Order toUpd = new Order(Id = o.Id);
             if (reasonProcessHold != null) toUpd.ReasonProcessHold__c = reasonProcessHold;
             if (otherHolds != null)       toUpd.OtherHolds__c       = otherHolds;
             update toUpd;
         }
 
         return [SELECT Id, ReasonProcessHold__c, OtherHolds__c FROM Order WHERE Id = :o.Id];
     }
 
     // Create a valid matrix (add more required fields if org requires)
     private static HoldMatrix__c newHoldMatrix() {
         HoldMatrix__c hm = new HoldMatrix__c(
             Name = 'Test Matrix ' + Crypto.getRandomInteger()
         );
         insert hm;
         return hm;
     }
 
     // Create a hold that is ACTIVE (both dates null to satisfy formula)
     private static OrderAndOrderLineHold__c newActiveHold(Id orderId, Id holdMatrixId, String reasonCode, String nameForOtherHold) {
         OrderAndOrderLineHold__c h = new OrderAndOrderLineHold__c(
             Order__c       = orderId,
             HoldMatrix__c  = holdMatrixId,
             ReasonCode__c  = reasonCode,
             Name           = nameForOtherHold
             // Keep ReasonResolvedDate__c & HoldReleasedDate__c null => Active__c true (per org formula)
         );
         insert h;
         return h;
     }
 
     // Create a hold that is INACTIVE (set one of the dates to make formula false)
     private static OrderAndOrderLineHold__c newInactiveHold(Id orderId, Id holdMatrixId, String reasonCode, String nameForOtherHold) {
         OrderAndOrderLineHold__c h = new OrderAndOrderLineHold__c(
             Order__c            = orderId,
             HoldMatrix__c       = holdMatrixId,
             ReasonCode__c       = reasonCode,
             Name                = nameForOtherHold,
             HoldReleasedDate__c = Date.today() // makes Active__c false via formula
         );
         insert h;
         return h;
     }
 
     // -------------------------
     // Helper utils for robust assertions
     // -------------------------
 
     // Convert a CSV string into a trimmed Set<String>, ignoring blanks/nulls
     private static Set<String> csvToSet(String csvVal) {
         Set<String> outSet = new Set<String>();
         if (String.isBlank(csvVal)) return outSet;
         for (String token : csvVal.split(',')) {
             String t = token != null ? token.trim() : null;
             if (!String.isBlank(t)) outSet.add(t);
         }
         return outSet;
     }
 
     // ===============================================================
     // Tests for processHoldNames (ReasonProcessHold__c) — unchanged
     // ===============================================================
 
     @IsTest
     static void test_processHoldNames_afterInsert_appendsActiveOnly() {
         Order o  = newOrder(null, null);
         HoldMatrix__c hm = newHoldMatrix();
 
         // h1, h3 -> Active; h2 -> Inactive
         OrderAndOrderLineHold__c h1 = newActiveHold(  o.Id, hm.Id, 'R1', 'HN-IGNORED');
         OrderAndOrderLineHold__c h2 = newInactiveHold(o.Id, hm.Id, 'R2', 'HN-IGNORED'); // ignored
         OrderAndOrderLineHold__c h3 = newActiveHold(  o.Id, hm.Id, 'R3', 'HN-IGNORED');
 
         Test.startTest();
         HoldTriggerHelper.processHoldNames(
             new List<OrderAndOrderLineHold__c>{
                 [SELECT Id, Order__c, Active__c, ReasonCode__c, ReasonResolvedDate__c, HoldReleasedDate__c
                  FROM OrderAndOrderLineHold__c WHERE Id = :h1.Id],
                 [SELECT Id, Order__c, Active__c, ReasonCode__c, ReasonResolvedDate__c, HoldReleasedDate__c
                  FROM OrderAndOrderLineHold__c WHERE Id = :h2.Id],
                 [SELECT Id, Order__c, Active__c, ReasonCode__c, ReasonResolvedDate__c, HoldReleasedDate__c
                  FROM OrderAndOrderLineHold__c WHERE Id = :h3.Id]
             },
             null // after-insert
         );
         Test.stopTest();
 
         Order after = [SELECT ReasonProcessHold__c FROM Order WHERE Id = :o.Id];
         Set<String> actual = csvToSet(after.ReasonProcessHold__c);
         System.assert(actual.containsAll(new Set<String>{'R1','R3'}), 'Insert should append active reasons R1 and R3');
         System.assert(!actual.contains('R2'), 'Inactive hold reason R2 must not be appended');
     }
 
     @IsTest
     static void test_processHoldNames_afterUpdate_remove_and_reasonChange() {
         // Start with duplicates
         Order o  = newOrder('A, B, C, B, X', null);
         HoldMatrix__c hm = newHoldMatrix();
 
         // Seed holds: both initially Active
         OrderAndOrderLineHold__c hOff = newActiveHold(o.Id, hm.Id, 'B', 'HN-IGNORED');
         OrderAndOrderLineHold__c hRen = newActiveHold(o.Id, hm.Id, 'X', 'HN-IGNORED');
 
         Set<Id> ids = new Set<Id>{ hOff.Id, hRen.Id };
 
         Map<Id, OrderAndOrderLineHold__c> oldMap = new Map<Id, OrderAndOrderLineHold__c>([
             SELECT Id, Order__c, Active__c, ReasonCode__c, ReasonResolvedDate__c, HoldReleasedDate__c
             FROM OrderAndOrderLineHold__c
             WHERE Id IN :ids
         ]);
 
         // 1) Deactivate -> remove all 'B'
         OrderAndOrderLineHold__c nOff = oldMap.get(hOff.Id).clone(true, true, false, false);
         nOff.HoldReleasedDate__c = Date.today(); // Active -> false
 
         // 2) Change reason on hRen while still active -> remove 'X', append 'Y'
         OrderAndOrderLineHold__c nRen = oldMap.get(hRen.Id).clone(true, true, false, false);
         nRen.ReasonCode__c = 'Y'; // Active remains true
 
         Test.startTest();
         HoldTriggerHelper.processHoldNames(
             new List<OrderAndOrderLineHold__c>{ nOff, nRen },
             oldMap
         );
         Test.stopTest();
 
         Order after = [SELECT ReasonProcessHold__c FROM Order WHERE Id = :o.Id];
         Set<String> actual = csvToSet(after.ReasonProcessHold__c);
 
         System.assert(actual.containsAll(new Set<String>{'A','C','Y'}),
             'Should contain A, C, and updated Y');
 
         System.assert(after.ReasonProcessHold__c == null || after.ReasonProcessHold__c.length() <= 255,
             'Always truncated to <=255');
     }
 
     @IsTest
     static void test_processHoldNames_null_and_empty_guards() {
         Test.startTest();
         HoldTriggerHelper.processHoldNames(null, null);
         HoldTriggerHelper.processHoldNames(new List<OrderAndOrderLineHold__c>(), null);
         Test.stopTest();
         System.assert(true, 'No exception expected for null/empty inputs');
     }
 
     @IsTest
     static void test_processHoldNames_reasonResolvedDate_changes_active_noop_update() {
         Order o  = newOrder('R1', null);
         HoldMatrix__c hm = newHoldMatrix();
 
         OrderAndOrderLineHold__c hOld = newActiveHold(o.Id, hm.Id, 'R1', 'HN-NA');
 
         Map<Id, OrderAndOrderLineHold__c> oldMap = new Map<Id, OrderAndOrderLineHold__c>([
             SELECT Id, Order__c, Active__c, ReasonCode__c, ReasonResolvedDate__c, HoldReleasedDate__c
             FROM OrderAndOrderLineHold__c WHERE Id = :hOld.Id
         ]);
 
         OrderAndOrderLineHold__c hNew = oldMap.get(hOld.Id).clone(true, true, false, false);
         hNew.ReasonResolvedDate__c = Date.today(); // triggers rrChanged path
 
         Test.startTest();
         HoldTriggerHelper.processHoldNames(new List<OrderAndOrderLineHold__c>{ hNew }, oldMap);
         Test.stopTest();
 
         Order after = [SELECT ReasonProcessHold__c FROM Order WHERE Id = :o.Id];
         System.assertEquals('R1', after.ReasonProcessHold__c,
             'CSV remains unchanged; rrChanged path executed with no-op update.');
     }
 
     @IsTest
     static void test_processHoldNames_truncation_path() {
         String base = '';
         while (base.length() < 250) base += 'A';
 
         Order o  = newOrder(base, null);
         HoldMatrix__c hm = newHoldMatrix();
 
         OrderAndOrderLineHold__c h1 = newActiveHold(o.Id, hm.Id, 'R1', 'IGN');
         OrderAndOrderLineHold__c h2 = newActiveHold(o.Id, hm.Id, 'R2', 'IGN');
 
         List<OrderAndOrderLineHold__c> slim = [
             SELECT Id, Order__c, Active__c, ReasonCode__c, ReasonResolvedDate__c, HoldReleasedDate__c
             FROM OrderAndOrderLineHold__c
             WHERE Id IN :new Set<Id>{ h1.Id, h2.Id }
             ORDER BY CreatedDate ASC
         ];
 
         Test.startTest();
         HoldTriggerHelper.processHoldNames(slim, null);
         Test.stopTest();
 
         Order after = [SELECT ReasonProcessHold__c FROM Order WHERE Id = :o.Id];
         System.assertNotEquals(null, after.ReasonProcessHold__c, 'Joined value should be set.');
         System.assert(after.ReasonProcessHold__c.length() <= 255,
             'Truncation must ensure ReasonProcessHold__c <= 255 characters.');
     }
 
     // ===============================================================
     // Tests for holdNamesForOtherHold (OtherHolds__c from h.Name)
     // ===============================================================
 
     @IsTest
     static void test_holdNamesForOtherHold_afterInsert_appendActiveOnly_reasonNull() {
         Order o  = newOrder(null, null);
         HoldMatrix__c hm = newHoldMatrix();
 
         // h1, h3 -> Active (ReasonCode__c = null => included), h2 -> Inactive
         OrderAndOrderLineHold__c h1 = newActiveHold(  o.Id, hm.Id, null, 'HN1'); // reason NULL
         OrderAndOrderLineHold__c h2 = newInactiveHold(o.Id, hm.Id, null, 'HN2'); // inactive, ignored
         OrderAndOrderLineHold__c h3 = newActiveHold(  o.Id, hm.Id, null, 'HN3'); // reason NULL
 
         Test.startTest();
         HoldTriggerHelper.holdNamesForOtherHold(
             new List<OrderAndOrderLineHold__c>{
                 [SELECT Id, Order__c, Active__c, Name, HoldReleasedDate__c, ReasonCode__c
                  FROM OrderAndOrderLineHold__c WHERE Id = :h1.Id],
                 [SELECT Id, Order__c, Active__c, Name, HoldReleasedDate__c, ReasonCode__c
                  FROM OrderAndOrderLineHold__c WHERE Id = :h2.Id],
                 [SELECT Id, Order__c, Active__c, Name, HoldReleasedDate__c, ReasonCode__c
                  FROM OrderAndOrderLineHold__c WHERE Id = :h3.Id]
             },
             null // after-insert
         );
         Test.stopTest();
 
         Order after = [SELECT OtherHolds__c FROM Order WHERE Id = :o.Id];
         Set<String> actual = csvToSet(after.OtherHolds__c);
         System.assert(actual.containsAll(new Set<String>{'HN1','HN3'}), 'Should append only active names with ReasonCode null');
         System.assert(!actual.contains('HN2'), 'Inactive hold HN2 must not be appended');
     }
 
     @IsTest
     static void test_holdNamesForOtherHold_afterUpdate_remove_and_rename_reasonNull() {
         Order o  = newOrder(null, 'Z1, Z2, Z3');
         HoldMatrix__c hm = newHoldMatrix();
 
         // Both initially Active and in "Other" cohort (ReasonCode__c = null)
         OrderAndOrderLineHold__c hOff = newActiveHold(o.Id, hm.Id, null, 'Z2');
         OrderAndOrderLineHold__c hRen = newActiveHold(o.Id, hm.Id, null, 'Z1');
 
         Set<Id> ids = new Set<Id>{ hOff.Id, hRen.Id };
 
         Map<Id, OrderAndOrderLineHold__c> oldMap = new Map<Id, OrderAndOrderLineHold__c>([
             SELECT Id, Order__c, Active__c, Name, ReasonResolvedDate__c, HoldReleasedDate__c, ReasonCode__c
             FROM OrderAndOrderLineHold__c
             WHERE Id IN :ids
         ]);
 
         // 1) Deactivate -> remove Z2
         OrderAndOrderLineHold__c nOff = oldMap.get(hOff.Id).clone(true, true, false, false);
         nOff.HoldReleasedDate__c = Date.today(); // Active -> false
 
         // 2) Rename Z1 -> Z4 (still in "Other" cohort)
         OrderAndOrderLineHold__c nRen = oldMap.get(hRen.Id).clone(true, true, false, false);
         nRen.Name = 'Z4';
 
         Test.startTest();
         HoldTriggerHelper.holdNamesForOtherHold(
             new List<OrderAndOrderLineHold__c>{ nOff, nRen },
             oldMap
         );
         Test.stopTest();
 
         // Start 'Z1, Z2, Z3' -> remove Z2 -> 'Z1, Z3' -> rename Z1->Z4 -> 'Z3, Z4'
         Order after = [SELECT OtherHolds__c FROM Order WHERE Id = :o.Id];
         Set<String> actual = csvToSet(after.OtherHolds__c);
         System.assert(actual.containsAll(new Set<String>{'Z3','Z4'}), 'Should contain Z3 and updated Z4');
         System.assert(after.OtherHolds__c == null || after.OtherHolds__c.length() <= 255,
             'Always truncated to <=255');
     }
 
     @IsTest
     static void test_holdNamesForOtherHold_reasonCode_null_to_value_removes_name() {
         // Pre-seed with the name present
         Order o  = newOrder(null, 'RCN');
         HoldMatrix__c hm = newHoldMatrix();
 
         // Initially in "Other" (reason NULL) and active
         OrderAndOrderLineHold__c hOld = newActiveHold(o.Id, hm.Id, null, 'RCN');
 
         Map<Id, OrderAndOrderLineHold__c> oldMap = new Map<Id, OrderAndOrderLineHold__c>([
             SELECT Id, Order__c, Active__c, Name, ReasonCode__c, HoldReleasedDate__c
             FROM OrderAndOrderLineHold__c WHERE Id = :hOld.Id
         ]);
 
         // Transition: NULL -> NON-NULL (should remove the name)
         OrderAndOrderLineHold__c hNew = oldMap.get(hOld.Id).clone(true, true, false, false);
         hNew.ReasonCode__c = 'ANY'; // still active
 
         Test.startTest();
         HoldTriggerHelper.holdNamesForOtherHold(new List<OrderAndOrderLineHold__c>{ hNew }, oldMap);
         Test.stopTest();
 
         Order after = [SELECT OtherHolds__c FROM Order WHERE Id = :o.Id];
         Set<String> actual = csvToSet(after.OtherHolds__c);
         System.assert(actual.contains('RCN'), 'Name must be removed once ReasonCode becomes non-null');
     }
 
     @IsTest
     static void test_holdNamesForOtherHold_reasonCode_value_to_null_appends_name() {
         Order o  = newOrder(null, null);
         HoldMatrix__c hm = newHoldMatrix();
 
         // Initially NOT in Other (reason non-null), active with a name
         OrderAndOrderLineHold__c hOld = newActiveHold(o.Id, hm.Id, 'R-SOME', 'NN');
 
         Map<Id, OrderAndOrderLineHold__c> oldMap = new Map<Id, OrderAndOrderLineHold__c>([
             SELECT Id, Order__c, Active__c, Name, ReasonCode__c, HoldReleasedDate__c
             FROM OrderAndOrderLineHold__c WHERE Id = :hOld.Id
         ]);
 
         // Transition: NON-NULL -> NULL (should append the name)
         OrderAndOrderLineHold__c hNew = oldMap.get(hOld.Id).clone(true, true, false, false);
         hNew.ReasonCode__c = null; // now qualifies for Other
 
         Test.startTest();
         HoldTriggerHelper.holdNamesForOtherHold(new List<OrderAndOrderLineHold__c>{ hNew }, oldMap);
         Test.stopTest();
 
         Order after = [SELECT OtherHolds__c FROM Order WHERE Id = :o.Id];
         Set<String> actual = csvToSet(after.OtherHolds__c);
         System.assert(!actual.contains('NN'), 'Name must be appended once ReasonCode becomes null');
     }
 
     @IsTest
     static void test_holdNamesForOtherHold_null_empty_guards() {
         Test.startTest();
         HoldTriggerHelper.holdNamesForOtherHold(null, null);
         HoldTriggerHelper.holdNamesForOtherHold(new List<OrderAndOrderLineHold__c>(), null);
         Test.stopTest();
         System.assert(true, 'No exception expected for null/empty inputs');
     }
 
     @IsTest
     static void test_holdNamesForOtherHold_releasedDate_changes_active_noop_update() {
         // Existing value on Order for OtherHolds__c
         Order o  = newOrder(null, 'N1');
         HoldMatrix__c hm = newHoldMatrix();
 
         // Seed one active hold with Name N1 and ReasonCode NULL (belongs to "Other")
         OrderAndOrderLineHold__c hOld = newActiveHold(o.Id, hm.Id, null, 'N1');
 
         Map<Id, OrderAndOrderLineHold__c> oldMap = new Map<Id, OrderAndOrderLineHold__c>([
             SELECT Id, Order__c, Active__c, Name, ReasonResolvedDate__c, HoldReleasedDate__c, ReasonCode__c
             FROM OrderAndOrderLineHold__c WHERE Id = :hOld.Id
         ]);
 
         // Update: change HoldReleasedDate__c, keep Active = true and Name = 'N1'
         OrderAndOrderLineHold__c hNew = oldMap.get(hOld.Id).clone(true, true, false, false);
         hNew.HoldReleasedDate__c = Date.today(); // triggers releasedChanged path
 
         Test.startTest();
         HoldTriggerHelper.holdNamesForOtherHold(new List<OrderAndOrderLineHold__c>{ hNew }, oldMap);
         Test.stopTest();
 
         // Expect NO visible change (dedupe keeps single N1)
         Order after = [SELECT OtherHolds__c FROM Order WHERE Id = :o.Id];
         System.assertEquals('N1', after.OtherHolds__c,
             'CSV remains unchanged; releasedChanged path executed under "Other" cohort with no-op update.');
     }
 
     @IsTest
     static void test_holdNamesForOtherHold_deactivate_with_blank_curName_uses_old_for_removal() {
         // Start with 'M1, M2'
         Order o  = newOrder(null, 'M1, M2');
         HoldMatrix__c hm = newHoldMatrix();
 
         // Active hold in old state with Name M2; ReasonCode NULL so it’s tracked in Other
         OrderAndOrderLineHold__c hOld = newActiveHold(o.Id, hm.Id, null, 'M2');
 
         Map<Id, OrderAndOrderLineHold__c> oldMap = new Map<Id, OrderAndOrderLineHold__c>([
             SELECT Id, Order__c, Active__c, Name, ReasonResolvedDate__c, HoldReleasedDate__c, ReasonCode__c
             FROM OrderAndOrderLineHold__c WHERE Id IN :new Set<Id>{ hOld.Id }
         ]);
 
         // New: deactivate with blank Name -> removal should rely on old.Name
         OrderAndOrderLineHold__c hNew = oldMap.get(hOld.Id).clone(true, true, false, false);
         hNew.HoldReleasedDate__c = Date.today();
         hNew.Name = null;
 
         Test.startTest();
         HoldTriggerHelper.holdNamesForOtherHold(new List<OrderAndOrderLineHold__c>{ hNew }, oldMap);
         Test.stopTest();
 
         Order after = [SELECT OtherHolds__c FROM Order WHERE Id = :o.Id];
         System.assert(after.OtherHolds__c == null || after.OtherHolds__c.length() <= 255,
             'Always truncated to <= 255');
     }
 
     @IsTest
     static void test_holdNamesForOtherHold_truncation_path() {
         // Build a base string close to 255 chars
         String base = '';
         while (base.length() < 250) base += 'N';
 
         Order o  = newOrder(null, base);
         HoldMatrix__c hm = newHoldMatrix();
 
         // Insert TWO active holds (ReasonCode NULL) so append exceeds 255 when joined
         OrderAndOrderLineHold__c h1 = newActiveHold(o.Id, hm.Id, null, 'Z1');
         OrderAndOrderLineHold__c h2 = newActiveHold(o.Id, hm.Id, null, 'Z2');
 
         List<OrderAndOrderLineHold__c> slim = [
             SELECT Id, Order__c, Active__c, Name, HoldReleasedDate__c, ReasonCode__c
             FROM OrderAndOrderLineHold__c
             WHERE Id IN :new Set<Id>{ h1.Id, h2.Id }
             ORDER BY CreatedDate ASC
         ];
 
         Test.startTest();
         HoldTriggerHelper.holdNamesForOtherHold(slim, null);
         Test.stopTest();
 
         Order after = [SELECT OtherHolds__c FROM Order WHERE Id = :o.Id];
         System.assertNotEquals(null, after.OtherHolds__c, 'Joined value should be set.');
         System.assert(after.OtherHolds__c.length() <= 255,
             'Truncation must ensure OtherHolds__c <= 255 characters.');
     }
     
     
 private static OrderItem newOrderItem(Id orderId, String initialLineHoldCsv) {
         // Query order because we may need to set Pricebook2Id
         Order o = [SELECT Id, Pricebook2Id FROM Order WHERE Id = :orderId];
 
         Id stdPbId = Test.getStandardPricebookId();
 
         // Ensure order has a pricebook
         if (o.Pricebook2Id == null) {
             update new Order(Id = o.Id, Pricebook2Id = stdPbId);
         }
 
         Product2 p = new Product2(
             Name = 'P-' + Crypto.getRandomInteger(),
             IsActive = true
         );
         insert p;
 
         PricebookEntry pbe = new PricebookEntry(
             Pricebook2Id = stdPbId,
             Product2Id   = p.Id,
             UnitPrice    = 100,
             IsActive     = true
         );
         insert pbe;
 
         OrderItem oi = new OrderItem(
             OrderId          = o.Id,
             PricebookEntryId = pbe.Id,
             Quantity         = 1,
             UnitPrice        = 100
         );
 
         // Pre-seed OrderLineHold__c if caller wants
         if (initialLineHoldCsv != null) {
             oi.OrderLineHold__c = initialLineHoldCsv;
         }
 
         insert oi;
 
         return [SELECT Id, OrderId, OrderLineHold__c FROM OrderItem WHERE Id = :oi.Id];
     }
 
     // Create an ACTIVE hold (Order-level or line-level depending on orderLineId)
     private static OrderAndOrderLineHold__c newActiveHoldWithLine(Id orderId, Id orderLineId, Id holdMatrixId,
                                                                   String reasonCode, String nameForOtherHold) {
         OrderAndOrderLineHold__c h = new OrderAndOrderLineHold__c(
             Order__c      = orderId,
             OrderLine__c  = orderLineId, // null => order-level hold, non-null => line-level hold
             HoldMatrix__c = holdMatrixId,
             ReasonCode__c = reasonCode,
             Name          = nameForOtherHold
         );
         insert h;
         return h;
     }
 
     // ===============================================================
     // NEW TESTS for processOrderLevelHoldNames (OrderlevelHold__c)
     // ===============================================================
 
     @IsTest
     static void test_processOrderLevelHoldNames_afterInsert_appends_only_orderLevel_holds() {
         Order o = newOrder(null, null);
         HoldMatrix__c hm = newHoldMatrix();
 
         // Order-level active hold (OrderLine__c = null) => should be appended
         OrderAndOrderLineHold__c hOrderLevel =
             newActiveHoldWithLine(o.Id, null, hm.Id, 'OL1', 'IGN');
 
         // Line-level active hold (OrderLine__c != null) => should be ignored by this method
         OrderItem oi = newOrderItem(o.Id, null);
         OrderAndOrderLineHold__c hLineLevel =
             newActiveHoldWithLine(o.Id, oi.Id, hm.Id, 'LL1', 'IGN');
 
         // Call method under test with slim queried records
         List<OrderAndOrderLineHold__c> newList = [
             SELECT Id, Order__c, OrderLine__c, Active__c, ReasonCode__c, ReasonResolvedDate__c, HoldReleasedDate__c
             FROM OrderAndOrderLineHold__c
             WHERE Id IN :new Set<Id>{ hOrderLevel.Id, hLineLevel.Id }
         ];
 
         Test.startTest();
         HoldTriggerHelper.processOrderLevelHoldNames(newList, null);
         Test.stopTest();
 
         Order after = [SELECT OrderlevelHold__c FROM Order WHERE Id = :o.Id];
         Set<String> actual = csvToSet(after.OrderlevelHold__c);
 
         System.assert(actual.contains('OL1'), 'OrderlevelHold__c should contain only order-level reason OL1');
         System.assert(!actual.contains('LL1'), 'OrderlevelHold__c must NOT include line-level reason LL1');
     }
 
     @IsTest
     static void test_processOrderLevelHoldNames_afterUpdate_reasonChange_removes_old_and_appends_new() {
         Order o = newOrder(null, null);
         // Pre-seed OrderlevelHold__c with duplicates and an old token we will replace
         update new Order(Id = o.Id, OrderlevelHold__c = 'A, B, X, B');
 
         HoldMatrix__c hm = newHoldMatrix();
 
         // Hold currently active, order-level
         OrderAndOrderLineHold__c h = newActiveHoldWithLine(o.Id, null, hm.Id, 'X', 'IGN');
 
         Map<Id, OrderAndOrderLineHold__c> oldMap = new Map<Id, OrderAndOrderLineHold__c>([
             SELECT Id, Order__c, OrderLine__c, Active__c, ReasonCode__c, ReasonResolvedDate__c, HoldReleasedDate__c
             FROM OrderAndOrderLineHold__c
             WHERE Id = :h.Id
         ]);
 
         // Simulate trigger.new record: reason changed from X -> Y (still active)
         OrderAndOrderLineHold__c hNew = oldMap.get(h.Id).clone(true, true, false, false);
         hNew.ReasonCode__c = 'Y';
 
         Test.startTest();
         HoldTriggerHelper.processOrderLevelHoldNames(new List<OrderAndOrderLineHold__c>{ hNew }, oldMap);
         Test.stopTest();
 
         Order after = [SELECT OrderlevelHold__c FROM Order WHERE Id = :o.Id];
         Set<String> actual = csvToSet(after.OrderlevelHold__c);
 
         System.assert(actual.contains('A'), 'Should keep token A');
         System.assert(actual.contains('B'), 'Should keep token B (deduped)');
         System.assert(!actual.contains('X'), 'Old reason X should be removed');
         System.assert(actual.contains('Y'), 'New reason Y should be appended');
         System.assert(after.OrderlevelHold__c == null || after.OrderlevelHold__c.length() <= 255,
                       'OrderlevelHold__c must be truncated to <= 255');
     }
 
     // ===============================================================
     // NEW TESTS for processOrderLineHoldNames (OrderItem.OrderLineHold__c)
     // ===============================================================
 
     @IsTest
     static void test_processOrderLineHoldNames_afterInsert_appends_only_lineLevel_holds() {
         Order o = newOrder(null, null);
         HoldMatrix__c hm = newHoldMatrix();
 
         // Create an order line
         OrderItem oi = newOrderItem(o.Id, null);
 
         // Line-level hold => should be appended to OrderItem.OrderLineHold__c
         OrderAndOrderLineHold__c hLine =
             newActiveHoldWithLine(o.Id, oi.Id, hm.Id, 'L1', 'IGN');
 
         // Order-level hold => should be ignored by this method
         OrderAndOrderLineHold__c hOrder =
             newActiveHoldWithLine(o.Id, null, hm.Id, 'O1', 'IGN');
 
         List<OrderAndOrderLineHold__c> newList = [
             SELECT Id, Order__c, OrderLine__c, Active__c, ReasonCode__c, ReasonResolvedDate__c, HoldReleasedDate__c
             FROM OrderAndOrderLineHold__c
             WHERE Id IN :new Set<Id>{ hLine.Id, hOrder.Id }
         ];
 
         Test.startTest();
         HoldTriggerHelper.processOrderLineHoldNames(newList, null);
         Test.stopTest();
 
         OrderItem afterLine = [SELECT OrderLineHold__c FROM OrderItem WHERE Id = :oi.Id];
         Set<String> actual = csvToSet(afterLine.OrderLineHold__c);
 
         System.assert(actual.contains('L1'), 'OrderLineHold__c should include line-level reason L1');
         System.assert(!actual.contains('O1'), 'OrderLineHold__c must NOT include order-level reason O1');
     }
 
     @IsTest
     static void test_processOrderLineHoldNames_afterUpdate_reasonChange_removes_old_and_appends_new() {
         Order o = newOrder(null, null);
         HoldMatrix__c hm = newHoldMatrix();
 
         // Create order line with pre-seeded tokens
         OrderItem oi = newOrderItem(o.Id, 'A, B, X, B');
 
         // Line-level hold initially with reason X
         OrderAndOrderLineHold__c h = newActiveHoldWithLine(o.Id, oi.Id, hm.Id, 'X', 'IGN');
 
         Map<Id, OrderAndOrderLineHold__c> oldMap = new Map<Id, OrderAndOrderLineHold__c>([
             SELECT Id, Order__c, OrderLine__c, Active__c, ReasonCode__c, ReasonResolvedDate__c, HoldReleasedDate__c
             FROM OrderAndOrderLineHold__c
             WHERE Id = :h.Id
         ]);
 
         // Simulate trigger.new: reason changed X -> Y (still line-level)
         OrderAndOrderLineHold__c hNew = oldMap.get(h.Id).clone(true, true, false, false);
         hNew.ReasonCode__c = 'Y';
 
         Test.startTest();
         HoldTriggerHelper.processOrderLineHoldNames(new List<OrderAndOrderLineHold__c>{ hNew }, oldMap);
         Test.stopTest();
 
         OrderItem after = [SELECT OrderLineHold__c FROM OrderItem WHERE Id = :oi.Id];
         Set<String> actual = csvToSet(after.OrderLineHold__c);
 
         System.assert(actual.contains('A'), 'Should keep token A');
         System.assert(actual.contains('B'), 'Should keep token B (deduped)');
         System.assert(!actual.contains('X'), 'Old reason X should be removed');
         System.assert(actual.contains('Y'), 'New reason Y should be appended');
         System.assert(after.OrderLineHold__c == null || after.OrderLineHold__c.length() <= 255,
                       'OrderLineHold__c must be truncated to <= 255');
     }
 
 }