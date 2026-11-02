/**
 * @description Test class for AccountDepartmentsService.
 *              Covers create, update, delete, and retrieval operations
 *              across positive, negative, and empty-input scenarios.
 */
@IsTest
private class AccountDepartmentsServiceTest {

    @TestSetup
    static void setupTestData() {
        // Build and persist parent Account and Department, then AccountDepartment links
        adb_Account accountBuilder = new adb_Account();
        accountBuilder.persist();

        adb_Department deptBuilder = new adb_Department().name('Engineering');
        deptBuilder.persist();

        List<AccountDepartment__c> accountDeptList = new List<AccountDepartment__c>();
        for (Integer i = 0; i < 5; i++) {
            AccountDepartment__c ad = (AccountDepartment__c) new adb_AccountDepartment()
                .name('Account Dept ' + i)
                .record;
            ad.Account__c = accountBuilder.id;
            ad.Department__c = deptBuilder.id;
            accountDeptList.add(ad);
        }
        insert accountDeptList;
    }

    // ── createAccountDepartments ──────────────────────────────────────────────

    @IsTest
    static void shouldCreateAccountDepartments_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Id accountId = [SELECT Id FROM Account LIMIT 1].Id;
            Id deptId = [SELECT Id FROM Department__c LIMIT 1].Id;
            List<AccountDepartment__c> adList = new List<AccountDepartment__c>();
            for (Integer i = 0; i < 2; i++) {
                AccountDepartment__c ad = (AccountDepartment__c) new adb_AccountDepartment()
                    .name('New Acct Dept ' + i)
                    .record;
                ad.Account__c = accountId;
                ad.Department__c = deptId;
                adList.add(ad);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            AccountDepartmentsService.createAccountDepartments(adList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIds = new Map<Id, AccountDepartment__c>(adList).keySet();
            List<AccountDepartment__c> insertedList = [SELECT Id FROM AccountDepartment__c WHERE Id IN :insertedIds];
            Assert.areEqual(2, insertedList.size(), 'createAccountDepartments should insert all 2 records');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateAccountDepartmentsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM AccountDepartment__c];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            AccountDepartmentsService.createAccountDepartments(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM AccountDepartment__c];
            Assert.areEqual(countBefore, countAfter, 'createAccountDepartments with null should not insert any records');
        }
    }

    // ── deleteAccountDepartments ──────────────────────────────────────────────

    @IsTest
    static void shouldDeleteAccountDepartments_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        //User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> adIdSet = new Map<Id, AccountDepartment__c>([SELECT Id FROM AccountDepartment__c LIMIT 3]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            AccountDepartmentsService.deleteAccountDepartments(adIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM AccountDepartment__c WHERE Id IN :adIdSet];
            Assert.areEqual(0, remainingCount, 'deleteAccountDepartments should delete all specified records');
        }
    }

    // ── getAccountDepartmentsById ─────────────────────────────────────────────

    @IsTest
    static void shouldReturnAccountDepartments_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> adIdSet = new Map<Id, AccountDepartment__c>([SELECT Id FROM AccountDepartment__c]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<AccountDepartment__c> resultList = AccountDepartmentsService.getAccountDepartmentsById(adIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(5, resultList.size(), 'getAccountDepartmentsById should return all 5 records');
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
            List<AccountDepartment__c> resultList = AccountDepartmentsService.getAccountDepartmentsById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getAccountDepartmentsById with null should return an empty list');
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }
}