/**
 * @description Test class for the ProductRequests domain class.
 *              Covers constructor, domain exception message, and cause-chain wrapping.
 */
@IsTest
private class ProductRequestsTest {

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
            List<ProductRequest> productRequestList = new List<ProductRequest>{
                (ProductRequest) new adb_ProductRequest().record,
                (ProductRequest) new adb_ProductRequest().record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRequests domain = new ProductRequests(productRequestList);
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
            ProductRequests domain = new ProductRequests(new List<ProductRequest>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    // ── Domain Exception ──────────────────────────────────────────────────────

    @IsTest
    static void shouldThrowProductRequestsException_WhenExceptionIsRaised() {
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
                throw new ProductRequests.ProductRequestsException('Validation failed: Destination is required.');
            } catch (ProductRequests.ProductRequestsException e) {
                Assert.areEqual(
                    'Validation failed: Destination is required.',
                    e.getMessage(),
                    'Exception message should match the value provided at construction'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void shouldPreserveCause_WhenProductRequestsExceptionWrapsAnother() {
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
                throw new ProductRequests.ProductRequestsException('Outer message', innerException);
            } catch (ProductRequests.ProductRequestsException e) {
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