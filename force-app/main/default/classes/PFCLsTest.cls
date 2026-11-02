/**
 * @description Test class for PFCLs domain class.
 *              Covers constructor and domain exception.
 */
@IsTest
private class PFCLsTest {

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
            List<PFCL__c> pfclList = new List<PFCL__c>{
                (PFCL__c) new adb_PFCL().name('PFCL A').record,
                (PFCL__c) new adb_PFCL().name('PFCL B').record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            PFCLs domain = new PFCLs(pfclList);
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
            PFCLs domain = new PFCLs(new List<PFCL__c>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    @IsTest
    static void shouldThrowPFCLsException_WhenExceptionIsRaised() {
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
                throw new PFCLs.PFCLsException('PFCL Name is required.');
            } catch (PFCLs.PFCLsException e) {
                Assert.areEqual(
                    'PFCL Name is required.',
                    e.getMessage(),
                    'Exception message should match the value provided at construction'
                );
            }
            Test.stopTest();
        }
    }
}