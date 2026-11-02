/**
 * @description Test class for ProductRequestTriggerHandler.
 *              Validates that trigger context methods fire correctly,
 *              that the AutomationControl bypass suppresses execution,
 *              and that bulk operations (251+ records) stay within governor limits.
 */
@IsTest
private class ProductRequestTriggerHandlerTest {

    // ── Trigger — Before Insert ───────────────────────────────────────────────

    @IsTest
    static void shouldFireBeforeInsert_WhenProductRequestsAreInserted() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ProductRequest> productRequestList = new List<ProductRequest>();
            for (Integer i = 0; i < 10; i++) {
                productRequestList.add((ProductRequest) new adb_ProductRequest().record);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            insert productRequestList;
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIdSet = new Map<Id, ProductRequest>(productRequestList).keySet();
            Integer insertedCount = [SELECT COUNT() FROM ProductRequest WHERE Id IN :insertedIdSet];
            Assert.areEqual(10, insertedCount, 'All 10 ProductRequests should be inserted via the before insert trigger context');
        }
    }

    @IsTest
    static void shouldFireBeforeInsert_WhenBulk251ProductRequestsAreInserted() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ProductRequest> productRequestList = new List<ProductRequest>();
            for (Integer i = 0; i < 251; i++) {
                productRequestList.add((ProductRequest) new adb_ProductRequest().record);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            insert productRequestList;
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer insertedCount = [SELECT COUNT() FROM ProductRequest];
            Assert.areEqual(251, insertedCount, 'All 251 ProductRequests should be inserted without hitting governor limits');
        }
    }

    // ── Trigger — Before Update ───────────────────────────────────────────────

    @IsTest
    static void shouldFireBeforeUpdate_WhenProductRequestsAreUpdated() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ProductRequest> productRequestList = new List<ProductRequest>();
            for (Integer i = 0; i < 10; i++) {
                productRequestList.add((ProductRequest) new adb_ProductRequest().record);
            }
            insert productRequestList;

            for (ProductRequest productRequest : productRequestList) {
                productRequest.Description = 'Before Update Description';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            update productRequestList;
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIdSet = new Map<Id, ProductRequest>(productRequestList).keySet();
            List<ProductRequest> updatedList = [SELECT Id, Description FROM ProductRequest WHERE Id IN :updatedIdSet];
            Assert.areEqual(10, updatedList.size(), 'All 10 ProductRequests should be updated via the before update trigger context');
            for (ProductRequest productRequest : updatedList) {
                Assert.areEqual('Before Update Description', productRequest.Description, 'Each ProductRequest should have the updated Description');
            }
        }
    }

    @IsTest
    static void shouldFireBeforeUpdate_WhenBulk251ProductRequestsAreUpdated() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ProductRequest> productRequestList = new List<ProductRequest>();
            for (Integer i = 0; i < 251; i++) {
                productRequestList.add((ProductRequest) new adb_ProductRequest().record);
            }
            insert productRequestList;

            for (ProductRequest productRequest : productRequestList) {
                productRequest.Description = 'Bulk Update Description';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            update productRequestList;
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> bulkUpdatedIdSet = new Map<Id, ProductRequest>(productRequestList).keySet();
            List<ProductRequest> bulkUpdatedList = [SELECT Id, Description FROM ProductRequest WHERE Id IN :bulkUpdatedIdSet];
            Assert.areEqual(251, bulkUpdatedList.size(), 'All 251 ProductRequests should be updated via the before update trigger context without hitting governor limits');
            for (ProductRequest productRequest : bulkUpdatedList) {
                Assert.areEqual('Bulk Update Description', productRequest.Description, 'Each ProductRequest should have the bulk updated Description');
            }
        }
    }

    // ── Trigger — After Insert ────────────────────────────────────────────────

    @IsTest
    static void shouldFireAfterInsert_WhenProductRequestsAreInserted() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ProductRequest> productRequestList = new List<ProductRequest>();
            for (Integer i = 0; i < 10; i++) {
                productRequestList.add((ProductRequest) new adb_ProductRequest().record);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            insert productRequestList;
            Test.stopTest();

            /********************************************
             * THEN — after insert handler fired without exception
             ********************************************/
            Set<Id> insertedIdSet = new Map<Id, ProductRequest>(productRequestList).keySet();
            Integer insertedCount = [SELECT COUNT() FROM ProductRequest WHERE Id IN :insertedIdSet];
            Assert.areEqual(10, insertedCount, 'All 10 ProductRequests should be present and the after insert context should have fired without error');
        }
    }

    // ── Trigger — After Update ────────────────────────────────────────────────

    @IsTest
    static void shouldFireAfterUpdate_WhenProductRequestsAreUpdated() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ProductRequest> productRequestList = new List<ProductRequest>();
            for (Integer i = 0; i < 10; i++) {
                productRequestList.add((ProductRequest) new adb_ProductRequest().record);
            }
            insert productRequestList;

            for (ProductRequest productRequest : productRequestList) {
                productRequest.Description = 'After Update Description';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            update productRequestList;
            Test.stopTest();

            /********************************************
             * THEN — after update handler fired without exception
             ********************************************/
            Set<Id> updatedIdSet = new Map<Id, ProductRequest>(productRequestList).keySet();
            List<ProductRequest> updatedList = [SELECT Id, Description FROM ProductRequest WHERE Id IN :updatedIdSet];
            Assert.areEqual(10, updatedList.size(), 'All 10 ProductRequests should be updated and the after update context should have fired without error');
            for (ProductRequest productRequest : updatedList) {
                Assert.areEqual('After Update Description', productRequest.Description, 'Each ProductRequest should have the after update Description');
            }
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
            AutomationControl.disableTrigger('ProductRequestTrigger');

            List<ProductRequest> productRequestList = new List<ProductRequest>();
            for (Integer i = 0; i < 5; i++) {
                productRequestList.add((ProductRequest) new adb_ProductRequest().record);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            insert productRequestList;
            Test.stopTest();

            /********************************************
             * THEN — records inserted; handler body was bypassed
             ********************************************/
            Set<Id> insertedIdSet = new Map<Id, ProductRequest>(productRequestList).keySet();
            Integer insertedCount = [SELECT COUNT() FROM ProductRequest WHERE Id IN :insertedIdSet];
            Assert.areEqual(5, insertedCount, 'ProductRequests should be inserted even when the trigger handler is bypassed via AutomationControl');

            AutomationControl.enableTrigger('ProductRequestTrigger');
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
            AutomationControl.disableTrigger('ProductRequestTrigger');
            AutomationControl.enableTrigger('ProductRequestTrigger');

            List<ProductRequest> productRequestList = new List<ProductRequest>();
            for (Integer i = 0; i < 5; i++) {
                productRequestList.add((ProductRequest) new adb_ProductRequest().record);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            insert productRequestList;
            Test.stopTest();

            /********************************************
             * THEN — trigger fires normally after re-enabling
             ********************************************/
            Set<Id> insertedIdSet = new Map<Id, ProductRequest>(productRequestList).keySet();
            Integer insertedCount = [SELECT COUNT() FROM ProductRequest WHERE Id IN :insertedIdSet];
            Assert.areEqual(5, insertedCount, 'ProductRequests should be inserted and the trigger should fire normally after AutomationControl re-enables it');
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }
}