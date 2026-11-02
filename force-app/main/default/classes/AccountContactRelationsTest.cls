/**
 * @description Test class for AccountContactRelations domain class.
 *              Covers constructor and domain exception.
 */
@IsTest
private class AccountContactRelationsTest {

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
            List<AccountContactRelation> relationList = new List<AccountContactRelation>{
                (AccountContactRelation) new adb_AccountContactRelation().isActive(true).record,
                (AccountContactRelation) new adb_AccountContactRelation().isActive(true).record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            AccountContactRelations domain = new AccountContactRelations(relationList);
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
            AccountContactRelations domain = new AccountContactRelations(new List<AccountContactRelation>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    @IsTest
    static void shouldThrowAccountContactRelationsException_WhenExceptionIsRaised() {
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
                throw new AccountContactRelations.AccountContactRelationsException('Roles are required.');
            } catch (AccountContactRelations.AccountContactRelationsException e) {
                Assert.areEqual(
                    'Roles are required.',
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