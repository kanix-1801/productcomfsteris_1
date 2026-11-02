/**
 * @description Test class for DepartmentsService.
 *              Covers create, update, delete, and retrieval operations
 *              across positive, negative, bulk, and empty-input scenarios.
 */
@IsTest
private class DepartmentsServiceTest {

    @TestSetup
    static void setupTestData() {
        // Build and persist 10 Departments
        List<Department__c> departmentList = new List<Department__c>();
        for (Integer i = 0; i < 10; i++) {
            departmentList.add((Department__c) new adb_Department().name('Department ' + i).record);
        }
        insert departmentList;
    }

    // ── createDepartments ─────────────────────────────────────────────────────

    @IsTest
    static void shouldCreateDepartments_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<Department__c> departmentList = new List<Department__c>{
                (Department__c) new adb_Department().name('New Dept 1').record,
                (Department__c) new adb_Department().name('New Dept 2').record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            DepartmentsService.createDepartments(departmentList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIds = new Map<Id, Department__c>(departmentList).keySet();
            List<Department__c> insertedList = [SELECT Id FROM Department__c WHERE Id IN :insertedIds];
            Assert.areEqual(2, insertedList.size(), 'createDepartments should insert all 2 Departments');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateDepartmentsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM Department__c];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            DepartmentsService.createDepartments(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM Department__c];
            Assert.areEqual(countBefore, countAfter, 'createDepartments with null should not insert any records');
        }
    }

    // ── updateDepartments ─────────────────────────────────────────────────────

    @IsTest
    static void shouldUpdateDepartments_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<Department__c> departmentList = [SELECT Id, Name FROM Department__c LIMIT 3];
            for (Department__c d : departmentList) {
                d.Name = 'Updated ' + d.Name;
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            DepartmentsService.updateDepartments(departmentList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIds = new Map<Id, Department__c>(departmentList).keySet();
            List<Department__c> updatedList = [SELECT Id, Name FROM Department__c WHERE Id IN :updatedIds];
            for (Department__c d : updatedList) {
                Assert.isTrue(d.Name.startsWith('Updated'), 'Name should start with Updated');
            }
        }
    }

    // ── deleteDepartments ─────────────────────────────────────────────────────

    @IsTest
    static void shouldDeleteDepartments_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> departmentIdSet = new Map<Id, Department__c>([SELECT Id FROM Department__c LIMIT 3]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            DepartmentsService.deleteDepartments(departmentIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM Department__c WHERE Id IN :departmentIdSet];
            Assert.areEqual(0, remainingCount, 'deleteDepartments should delete all specified Departments');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteDepartmentsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM Department__c];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            DepartmentsService.deleteDepartments(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM Department__c];
            Assert.areEqual(countBefore, countAfter, 'deleteDepartments with null should not delete any records');
        }
    }

    // ── getDepartmentsById ────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnDepartments_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> departmentIdSet = new Map<Id, Department__c>([SELECT Id FROM Department__c]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<Department__c> resultList = DepartmentsService.getDepartmentsById(departmentIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(10, resultList.size(), 'getDepartmentsById should return all 10 Departments');
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
            List<Department__c> resultList = DepartmentsService.getDepartmentsById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getDepartmentsById with null should return an empty list');
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }
}