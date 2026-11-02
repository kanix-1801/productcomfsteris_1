/**
 * @description Test class for WorkOrderLineItems domain class.
 *              Covers constructor, domain exception instantiation, and cause-chain preservation.
 */
@IsTest
private class WorkOrderLineItemsTest {

    // ── Constructor ───────────────────────────────────────────────────────────

    @IsTest
    static void shouldConstructDomain_WhenValidRecordListProvided() {
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

            List<WorkOrderLineItem> lineItemList = new List<WorkOrderLineItem>{
                (WorkOrderLineItem) new adb_WorkOrderLineItem()
                    .workOrder(workOrderBuilder)
                    .record,
                (WorkOrderLineItem) new adb_WorkOrderLineItem()
                    .workOrder(workOrderBuilder)
                    .record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrderLineItems domain = new WorkOrderLineItems(lineItemList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from a valid record list');
        }
    }

    @IsTest
    static void shouldConstructDomain_WhenEmptyListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrderLineItems domain = new WorkOrderLineItems(new List<WorkOrderLineItem>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    // ── Domain Exception ──────────────────────────────────────────────────────

    @IsTest
    static void shouldThrowWorkOrderLineItemsException_WhenExceptionIsRaised() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN / THEN
             ********************************************/
            Test.startTest();
            try {
                throw new WorkOrderLineItems.WorkOrderLineItemsException('Validation failed: WorkOrder is required.');
            } catch (WorkOrderLineItems.WorkOrderLineItemsException e) {
                Assert.areEqual(
                    'Validation failed: WorkOrder is required.',
                    e.getMessage(),
                    'Exception message should match the value provided at construction'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void shouldPreserveCause_WhenWorkOrderLineItemsExceptionWrapsAnother() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Exception innerException = new IllegalArgumentException('inner cause');

            /********************************************
             * WHEN / THEN
             ********************************************/
            Test.startTest();
            try {
                throw new WorkOrderLineItems.WorkOrderLineItemsException('Outer message', innerException);
            } catch (WorkOrderLineItems.WorkOrderLineItemsException e) {
                Assert.areEqual('Outer message', e.getMessage(), 'Outer exception message should be preserved');
                Assert.isNotNull(e.getCause(), 'Cause chain should be preserved');
            }
            Test.stopTest();
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }
}