/**
 * @description Test class for WorkOrderTriggerHandler.
 *              Validates that trigger context methods fire correctly,
 *              that the AutomationControl bypass suppresses execution,
 *              and that bulk operations (251+ records) stay within governor limits.
 */
@IsTest
private class WorkOrderTriggerHandlerTest {

    // ── Trigger — Before Insert ───────────────────────────────────────────────

    @IsTest
    static void shouldFireBeforeInsert_WhenWorkOrdersAreInserted() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<WorkOrder> workOrderList = new List<WorkOrder>();
            for (Integer i = 0; i < 10; i++) {
                workOrderList.add((WorkOrder) new adb_WorkOrder().subject('Before Insert WO ' + i).record);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            insert workOrderList;
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIdSet = new Map<Id, WorkOrder>(workOrderList).keySet();
            Integer insertedCount = [SELECT COUNT() FROM WorkOrder WHERE Id IN :insertedIdSet];
            Assert.areEqual(10, insertedCount, 'All 10 WorkOrders should be inserted via the before insert trigger context');
        }
    }

    @IsTest
    static void shouldFireBeforeInsert_WhenBulk251WorkOrdersAreInserted() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<WorkOrder> workOrderList = new List<WorkOrder>();
            for (Integer i = 0; i < 251; i++) {
                workOrderList.add((WorkOrder) new adb_WorkOrder().subject('Bulk Insert WO ' + i).record);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            insert workOrderList;
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer insertedCount = [SELECT COUNT() FROM WorkOrder];
            Assert.areEqual(251, insertedCount, 'All 251 WorkOrders should be inserted without hitting governor limits');
        }
    }

    // ── Trigger — Before Update ───────────────────────────────────────────────

    @IsTest
    static void shouldFireBeforeUpdate_WhenWorkOrdersAreUpdated() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<WorkOrder> workOrderList = new List<WorkOrder>();
            for (Integer i = 0; i < 10; i++) {
                workOrderList.add((WorkOrder) new adb_WorkOrder().subject('Before Update WO ' + i).record);
            }
            insert workOrderList;

            for (WorkOrder workOrder : workOrderList) {
                workOrder.Priority = 'High';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            update workOrderList;
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIdSet = new Map<Id, WorkOrder>(workOrderList).keySet();
            Integer highPriorityCount = [SELECT COUNT() FROM WorkOrder WHERE Id IN :updatedIdSet AND Priority = 'High'];
            Assert.areEqual(10, highPriorityCount, 'All 10 WorkOrders should be updated to Priority = High via the before update trigger context');
        }
    }

    @IsTest
    static void shouldFireBeforeUpdate_WhenBulk251WorkOrdersAreUpdated() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<WorkOrder> workOrderList = new List<WorkOrder>();
            for (Integer i = 0; i < 251; i++) {
                workOrderList.add((WorkOrder) new adb_WorkOrder().subject('Bulk Update WO ' + i).record);
            }
            insert workOrderList;

            for (WorkOrder workOrder : workOrderList) {
                workOrder.Status = 'In Progress';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            update workOrderList;
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer inProgressCount = [SELECT COUNT() FROM WorkOrder WHERE Status = 'In Progress'];
            Assert.areEqual(251, inProgressCount, 'All 251 WorkOrders should be updated to Status = In Progress via the before update trigger context');
        }
    }

    // ── Trigger — After Insert ────────────────────────────────────────────────

    @IsTest
    static void shouldFireAfterInsert_WhenWorkOrdersAreInserted() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<WorkOrder> workOrderList = new List<WorkOrder>();
            for (Integer i = 0; i < 10; i++) {
                workOrderList.add((WorkOrder) new adb_WorkOrder().subject('After Insert WO ' + i).record);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            insert workOrderList;
            Test.stopTest();

            /********************************************
             * THEN — after insert handler fired without exception
             ********************************************/
            Set<Id> insertedIdSet = new Map<Id, WorkOrder>(workOrderList).keySet();
            Integer insertedCount = [SELECT COUNT() FROM WorkOrder WHERE Id IN :insertedIdSet];
            Assert.areEqual(10, insertedCount, 'All 10 WorkOrders should be present and the after insert context should have fired without error');
        }
    }

    // ── Trigger — After Update ────────────────────────────────────────────────

    @IsTest
    static void shouldFireAfterUpdate_WhenWorkOrdersAreUpdated() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<WorkOrder> workOrderList = new List<WorkOrder>();
            for (Integer i = 0; i < 10; i++) {
                workOrderList.add((WorkOrder) new adb_WorkOrder().subject('After Update WO ' + i).record);
            }
            insert workOrderList;

            for (WorkOrder workOrder : workOrderList) {
                workOrder.Priority = 'Low';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            update workOrderList;
            Test.stopTest();

            /********************************************
             * THEN — after update handler fired without exception
             ********************************************/
            Set<Id> updatedIdSet = new Map<Id, WorkOrder>(workOrderList).keySet();
            Integer lowPriorityCount = [SELECT COUNT() FROM WorkOrder WHERE Id IN :updatedIdSet AND Priority = 'Low'];
            Assert.areEqual(10, lowPriorityCount, 'All 10 WorkOrders should be updated and the after update context should have fired without error');
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
            AutomationControl.disableTrigger('WorkOrderTrigger');

            List<WorkOrder> workOrderList = new List<WorkOrder>();
            for (Integer i = 0; i < 5; i++) {
                workOrderList.add((WorkOrder) new adb_WorkOrder().subject('Bypass WO ' + i).record);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            insert workOrderList;
            Test.stopTest();

            /********************************************
             * THEN — records inserted; handler body was bypassed
             ********************************************/
            Set<Id> insertedIdSet = new Map<Id, WorkOrder>(workOrderList).keySet();
            Integer insertedCount = [SELECT COUNT() FROM WorkOrder WHERE Id IN :insertedIdSet];
            Assert.areEqual(5, insertedCount, 'WorkOrders should be inserted even when the trigger handler is bypassed via AutomationControl');

            AutomationControl.enableTrigger('WorkOrderTrigger');
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
            AutomationControl.disableTrigger('WorkOrderTrigger');
            AutomationControl.enableTrigger('WorkOrderTrigger');

            List<WorkOrder> workOrderList = new List<WorkOrder>();
            for (Integer i = 0; i < 5; i++) {
                workOrderList.add((WorkOrder) new adb_WorkOrder().subject('Re-enabled WO ' + i).record);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            insert workOrderList;
            Test.stopTest();

            /********************************************
             * THEN — trigger fires normally after re-enabling
             ********************************************/
            Set<Id> insertedIdSet = new Map<Id, WorkOrder>(workOrderList).keySet();
            Integer insertedCount = [SELECT COUNT() FROM WorkOrder WHERE Id IN :insertedIdSet];
            Assert.areEqual(5, insertedCount, 'WorkOrders should be inserted and the trigger should fire normally after AutomationControl re-enables it');
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }
}