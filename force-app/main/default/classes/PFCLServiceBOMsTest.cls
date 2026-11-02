/**
 * @description Test class for PFCLServiceBOMs domain class.
 *              Covers constructor and domain exception.
 */
@IsTest
private class PFCLServiceBOMsTest {

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
            List<PFCLServiceBOM__c> junctionList = new List<PFCLServiceBOM__c>{
                (PFCLServiceBOM__c) new adb_PFCLServiceBOM().record,
                (PFCLServiceBOM__c) new adb_PFCLServiceBOM().record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            PFCLServiceBOMs domain = new PFCLServiceBOMs(junctionList);
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
            PFCLServiceBOMs domain = new PFCLServiceBOMs(new List<PFCLServiceBOM__c>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    @IsTest
    static void shouldThrowPFCLServiceBOMsException_WhenExceptionIsRaised() {
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
                throw new PFCLServiceBOMs.PFCLServiceBOMsException('PFCL is required.');
            } catch (PFCLServiceBOMs.PFCLServiceBOMsException e) {
                Assert.areEqual(
                    'PFCL is required.',
                    e.getMessage(),
                    'Exception message should match the value provided at construction'
                );
            }
            Test.stopTest();
        }
    }
}