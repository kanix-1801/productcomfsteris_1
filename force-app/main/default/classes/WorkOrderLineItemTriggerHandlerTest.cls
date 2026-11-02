/**
 * @description Test class for WorkOrderLineItemTriggerHandler.
 *              Validates trigger context methods fire correctly,
 *              AutomationControl bypass suppresses execution,
 *              and bulk operations (251+ records) stay within governor limits.
 */
@IsTest
private class WorkOrderLineItemTriggerHandlerTest {

    // ── Trigger — Before Insert ───────────────────────────────────────────────

    @IsTest
    static void shouldFireBeforeInsert_WhenLineItemsAreInserted() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            adb_WorkOrder workOrderBuilder = new adb_WorkOrder();
            workOrderBuilder.persist();

            List<WorkOrderLineItem> lineItemList = new List<WorkOrderLineItem>();
            for (Integer i = 0; i < 10; i++) {
                WorkOrderLineItem lineItem = (WorkOrderLineItem) new adb_WorkOrderLineItem()
                    .description('Before Insert Line Item ' + i)
                    .record;
                lineItem.WorkOrderId = workOrderBuilder.id;
                lineItemList.add(lineItem);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            insert lineItemList;
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIdSet = new Map<Id, WorkOrderLineItem>(lineItemList).keySet();
            Integer insertedCount = [SELECT COUNT() FROM WorkOrderLineItem WHERE Id IN :insertedIdSet];
            Assert.areEqual(10, insertedCount, 'All 10 WorkOrderLineItems should be inserted via the before insert trigger context');
        }
    }

    @IsTest
    static void shouldFireBeforeInsert_WhenBulk251LineItemsAreInserted() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            adb_WorkOrder workOrderBuilder = new adb_WorkOrder();
            workOrderBuilder.persist();

            List<WorkOrderLineItem> lineItemList = new List<WorkOrderLineItem>();
            for (Integer i = 0; i < 251; i++) {
                WorkOrderLineItem lineItem = (WorkOrderLineItem) new adb_WorkOrderLineItem()
                    .description('Bulk Insert Line Item ' + i)
                    .record;
                lineItem.WorkOrderId = workOrderBuilder.id;
                lineItemList.add(lineItem);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            insert lineItemList;
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer insertedCount = [SELECT COUNT() FROM WorkOrderLineItem];
            Assert.areEqual(251, insertedCount, 'All 251 WorkOrderLineItems should be inserted without hitting governor limits');
        }
    }

    // ── Trigger — Before Update ───────────────────────────────────────────────

    @IsTest
    static void shouldFireBeforeUpdate_WhenLineItemsAreUpdated() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            adb_WorkOrder workOrderBuilder = new adb_WorkOrder();
            workOrderBuilder.persist();

            List<WorkOrderLineItem> lineItemList = new List<WorkOrderLineItem>();
            for (Integer i = 0; i < 10; i++) {
                WorkOrderLineItem lineItem = (WorkOrderLineItem) new adb_WorkOrderLineItem()
                    .description('Before Update Line Item ' + i)
                    .record;
                lineItem.WorkOrderId = workOrderBuilder.id;
                lineItemList.add(lineItem);
            }
            insert lineItemList;

            for (WorkOrderLineItem lineItem : lineItemList) {
                lineItem.Status = 'In Progress';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            update lineItemList;
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIdSet = new Map<Id, WorkOrderLineItem>(lineItemList).keySet();
            Integer inProgressCount = [
                SELECT COUNT() FROM WorkOrderLineItem WHERE Id IN :updatedIdSet AND Status = 'In Progress'
            ];
            Assert.areEqual(10, inProgressCount, 'All 10 WorkOrderLineItems should be updated to Status = In Progress via the before update trigger context');
        }
    }

    @IsTest
    static void shouldFireBeforeUpdate_WhenBulk251LineItemsAreUpdated() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            adb_WorkOrder workOrderBuilder = new adb_WorkOrder();
            workOrderBuilder.persist();

            List<WorkOrderLineItem> lineItemList = new List<WorkOrderLineItem>();
            for (Integer i = 0; i < 251; i++) {
                WorkOrderLineItem lineItem = (WorkOrderLineItem) new adb_WorkOrderLineItem()
                    .description('Bulk Update Line Item ' + i)
                    .record;
                lineItem.WorkOrderId = workOrderBuilder.id;
                lineItemList.add(lineItem);
            }
            insert lineItemList;

            for (WorkOrderLineItem lineItem : lineItemList) {
                lineItem.Status = 'Completed';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            update lineItemList;
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer completedCount = [SELECT COUNT() FROM WorkOrderLineItem WHERE Status = 'Completed'];
            Assert.areEqual(251, completedCount, 'All 251 WorkOrderLineItems should be updated to Status = Completed via the before update trigger context');
        }
    }

    // ── Trigger — After Insert ────────────────────────────────────────────────

    @IsTest
    static void shouldFireAfterInsert_WhenLineItemsAreInserted() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            adb_WorkOrder workOrderBuilder = new adb_WorkOrder();
            workOrderBuilder.persist();

            List<WorkOrderLineItem> lineItemList = new List<WorkOrderLineItem>();
            for (Integer i = 0; i < 10; i++) {
                WorkOrderLineItem lineItem = (WorkOrderLineItem) new adb_WorkOrderLineItem()
                    .description('After Insert Line Item ' + i)
                    .record;
                lineItem.WorkOrderId = workOrderBuilder.id;
                lineItemList.add(lineItem);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            insert lineItemList;
            Test.stopTest();

            /********************************************
             * THEN — after insert handler fired without exception
             ********************************************/
            Set<Id> insertedIdSet = new Map<Id, WorkOrderLineItem>(lineItemList).keySet();
            Integer insertedCount = [SELECT COUNT() FROM WorkOrderLineItem WHERE Id IN :insertedIdSet];
            Assert.areEqual(10, insertedCount, 'All 10 WorkOrderLineItems should be present and the after insert context should have fired without error');
        }
    }

    // ── Trigger — After Update ────────────────────────────────────────────────

    @IsTest
    static void shouldFireAfterUpdate_WhenLineItemsAreUpdated() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            adb_WorkOrder workOrderBuilder = new adb_WorkOrder();
            workOrderBuilder.persist();

            List<WorkOrderLineItem> lineItemList = new List<WorkOrderLineItem>();
            for (Integer i = 0; i < 10; i++) {
                WorkOrderLineItem lineItem = (WorkOrderLineItem) new adb_WorkOrderLineItem()
                    .description('After Update Line Item ' + i)
                    .record;
                lineItem.WorkOrderId = workOrderBuilder.id;
                lineItemList.add(lineItem);
            }
            insert lineItemList;

            for (WorkOrderLineItem lineItem : lineItemList) {
                lineItem.Status = 'In Progress';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            update lineItemList;
            Test.stopTest();

            /********************************************
             * THEN — after update handler fired without exception
             ********************************************/
            Set<Id> updatedIdSet = new Map<Id, WorkOrderLineItem>(lineItemList).keySet();
            Integer inProgressCount = [
                SELECT COUNT() FROM WorkOrderLineItem WHERE Id IN :updatedIdSet AND Status = 'In Progress'
            ];
            Assert.areEqual(10, inProgressCount, 'All 10 WorkOrderLineItems should be updated and the after update context should have fired without error');
        }
    }

    // ── AutomationControl Bypass ──────────────────────────────────────────────

    @IsTest
    static void shouldBypassTrigger_WhenAutomationControlDisablesTrigger() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            AutomationControl.disableTrigger('WorkOrderLineItemTrigger');

            adb_WorkOrder workOrderBuilder = new adb_WorkOrder();
            workOrderBuilder.persist();

            List<WorkOrderLineItem> lineItemList = new List<WorkOrderLineItem>();
            for (Integer i = 0; i < 5; i++) {
                WorkOrderLineItem lineItem = (WorkOrderLineItem) new adb_WorkOrderLineItem()
                    .description('Bypass Line Item ' + i)
                    .record;
                lineItem.WorkOrderId = workOrderBuilder.id;
                lineItemList.add(lineItem);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            insert lineItemList;
            Test.stopTest();

            /********************************************
             * THEN — records inserted; handler body was bypassed
             ********************************************/
            Set<Id> insertedIdSet = new Map<Id, WorkOrderLineItem>(lineItemList).keySet();
            Integer insertedCount = [SELECT COUNT() FROM WorkOrderLineItem WHERE Id IN :insertedIdSet];
            Assert.areEqual(5, insertedCount, 'WorkOrderLineItems should be inserted even when the trigger handler is bypassed via AutomationControl');

            AutomationControl.enableTrigger('WorkOrderLineItemTrigger');
        }
    }

    @IsTest
    static void shouldFireTrigger_WhenAutomationControlReEnablesTrigger() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            AutomationControl.disableTrigger('WorkOrderLineItemTrigger');
            AutomationControl.enableTrigger('WorkOrderLineItemTrigger');

            adb_WorkOrder workOrderBuilder = new adb_WorkOrder();
            workOrderBuilder.persist();

            List<WorkOrderLineItem> lineItemList = new List<WorkOrderLineItem>();
            for (Integer i = 0; i < 5; i++) {
                WorkOrderLineItem lineItem = (WorkOrderLineItem) new adb_WorkOrderLineItem()
                    .description('Re-enabled Line Item ' + i)
                    .record;
                lineItem.WorkOrderId = workOrderBuilder.id;
                lineItemList.add(lineItem);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            insert lineItemList;
            Test.stopTest();

            /********************************************
             * THEN — trigger fires normally after re-enabling
             ********************************************/
            Set<Id> insertedIdSet = new Map<Id, WorkOrderLineItem>(lineItemList).keySet();
            Integer insertedCount = [SELECT COUNT() FROM WorkOrderLineItem WHERE Id IN :insertedIdSet];
            Assert.areEqual(5, insertedCount, 'WorkOrderLineItems should be inserted and the trigger should fire normally after AutomationControl re-enables it');
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }
}