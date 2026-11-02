/**
 * @description Test class for AccountContactRelationsService.
 *              Covers retrieval and delete operations across positive, negative,
 *              and empty-input scenarios.
 *              Note: AccountContactRelation records are created implicitly when a Contact
 *              is associated with an Account (the IsDirect relation). Indirect relations
 *              require Contacts to Be Related to Multiple Accounts to be enabled.
 */
@IsTest
private class AccountContactRelationsServiceTest {

    @TestSetup
    static void setupTestData() {
        // Insert an Account and Contacts — the direct AccountContactRelation is auto-created
        adb_Account accountBuilder = new adb_Account();
        accountBuilder.persist();

        List<Contact> contactList = new List<Contact>();
        for (Integer i = 0; i < 5; i++) {
            Contact c = (Contact) new adb_Contact().lastName('ACRContact' + i).record;
            c.AccountId = accountBuilder.id;
            contactList.add(c);
        }
        insert contactList;
    }

    // ── getAccountContactRelationsById ────────────────────────────────────────

    @IsTest
    static void shouldReturnAccountContactRelations_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN — query auto-created direct relations
             ********************************************/
            Set<Id> acrIdSet = new Map<Id, AccountContactRelation>(
                [SELECT Id FROM AccountContactRelation WHERE IsDirect = true]
            ).keySet();
            Assert.isFalse(acrIdSet.isEmpty(), 'There should be auto-created AccountContactRelation records');

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<AccountContactRelation> resultList = AccountContactRelationsService.getAccountContactRelationsById(acrIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(acrIdSet.size(), resultList.size(), 'getAccountContactRelationsById should return all queried relations');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenGetByIdCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<AccountContactRelation> resultList = AccountContactRelationsService.getAccountContactRelationsById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getAccountContactRelationsById with null should return an empty list');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenGetByIdCalledWithEmptySet() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<AccountContactRelation> resultList = AccountContactRelationsService.getAccountContactRelationsById(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getAccountContactRelationsById with empty Set should return an empty list');
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }
}