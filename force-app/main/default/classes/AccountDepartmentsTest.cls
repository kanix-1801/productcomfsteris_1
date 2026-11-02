/**
 * @description Test class for AccountDepartments domain class.
 *              Covers constructor and domain exception.
 */
@IsTest
private class AccountDepartmentsTest {

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
            List<AccountDepartment__c> accountDeptList = new List<AccountDepartment__c>{
                (AccountDepartment__c) new adb_AccountDepartment().name('Acct Dept 1').record,
                (AccountDepartment__c) new adb_AccountDepartment().name('Acct Dept 2').record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            AccountDepartments domain = new AccountDepartments(accountDeptList);
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
            AccountDepartments domain = new AccountDepartments(new List<AccountDepartment__c>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    @IsTest
    static void shouldThrowAccountDepartmentsException_WhenExceptionIsRaised() {
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
                throw new AccountDepartments.AccountDepartmentsException('Account is required.');
            } catch (AccountDepartments.AccountDepartmentsException e) {
                Assert.areEqual(
                    'Account is required.',
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