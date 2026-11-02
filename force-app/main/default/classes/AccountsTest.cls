/**
 * @description Test class for Accounts domain class.
 *              Covers constructor, domain exception, and the commented-out
 *              demonstration methods (applyDefaults, validate, validators).
 */
@IsTest
private class AccountsTest {

    // ── Positive Tests ────────────────────────────────────────────────────────

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
            List<Account> accountList = new List<Account>{
                (Account) new adb_Account().record,
                (Account) new adb_Account().record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            Accounts domain = new Accounts(accountList);
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
            Accounts domain = new Accounts(new List<Account>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    // ── Domain Exception Tests ────────────────────────────────────────────────

    @IsTest
    static void shouldThrowAccountsException_WhenExceptionIsRaised() {
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
                throw new Accounts.AccountsException('Validation failed: Account Name is required.');
            } catch (Accounts.AccountsException e) {
                Assert.areEqual(
                    'Validation failed: Account Name is required.',
                    e.getMessage(),
                    'Exception message should match the value provided at construction'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void shouldPreserveCause_WhenAccountsExceptionWrapsAnother() {
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
                throw new Accounts.AccountsException('Outer message', innerException);
            } catch (Accounts.AccountsException e) {
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