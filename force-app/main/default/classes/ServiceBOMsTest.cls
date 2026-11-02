/**
 * @description Test class for ServiceBOMs domain class.
 *              Covers constructor and domain exception.
 */
@IsTest
private class ServiceBOMsTest {

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
            List<ServiceBOM__c> serviceBomList = new List<ServiceBOM__c>{
                (ServiceBOM__c) new adb_ServiceBOM().name('BOM A').record,
                (ServiceBOM__c) new adb_ServiceBOM().name('BOM B').record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ServiceBOMs domain = new ServiceBOMs(serviceBomList);
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
            ServiceBOMs domain = new ServiceBOMs(new List<ServiceBOM__c>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    @IsTest
    static void shouldThrowServiceBOMsException_WhenExceptionIsRaised() {
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
                throw new ServiceBOMs.ServiceBOMsException('Service BOM Name is required.');
            } catch (ServiceBOMs.ServiceBOMsException e) {
                Assert.areEqual(
                    'Service BOM Name is required.',
                    e.getMessage(),
                    'Exception message should match the value provided at construction'
                );
            }
            Test.stopTest();
        }
    }
}