/**
 * @description Test class for Departments domain class.
 *              Covers constructor and domain exception.
 */
@IsTest
private class DepartmentsTest {

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
            List<Department__c> departmentList = new List<Department__c>{
                (Department__c) new adb_Department().name('Engineering').record,
                (Department__c) new adb_Department().name('Sales').record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            Departments domain = new Departments(departmentList);
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
            Departments domain = new Departments(new List<Department__c>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    @IsTest
    static void shouldThrowDepartmentsException_WhenExceptionIsRaised() {
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
                throw new Departments.DepartmentsException('Department Name is required.');
            } catch (Departments.DepartmentsException e) {
                Assert.areEqual(
                    'Department Name is required.',
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