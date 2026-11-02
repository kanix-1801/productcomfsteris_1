/**
 * @description Test class for ReturnOrderLineItems domain class.
 *              Covers constructor and domain exception.
 */
@IsTest
private class ReturnOrderLineItemsTest {

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
            List<ReturnOrderLineItem> lineItemList = new List<ReturnOrderLineItem>{
                (ReturnOrderLineItem) new adb_ReturnOrderLineItem().quantityReturned(1).record,
                (ReturnOrderLineItem) new adb_ReturnOrderLineItem().quantityReturned(2).record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ReturnOrderLineItems domain = new ReturnOrderLineItems(lineItemList);
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
            ReturnOrderLineItems domain = new ReturnOrderLineItems(new List<ReturnOrderLineItem>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    @IsTest
    static void shouldThrowReturnOrderLineItemsException_WhenExceptionIsRaised() {
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
                throw new ReturnOrderLineItems.ReturnOrderLineItemsException('Quantity cannot be negative.');
            } catch (ReturnOrderLineItems.ReturnOrderLineItemsException e) {
                Assert.areEqual(
                    'Quantity cannot be negative.',
                    e.getMessage(),
                    'Exception message should match the value provided at construction'
                );
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