/**
 * @description Tests for ServiceBOMsSelector companion class (coverage for CBMQA dry-run).
 */
@IsTest
private class ServiceBOMsSelectorTest {
    @TestSetup
    static void setupData() {
        /********************************************
         * SETUP
         ********************************************/
        PFCL__c pfcl = new PFCL__c(Name = 'SBOM-PFCL-001');
        insert pfcl;

        ServiceBOM__c bom = new ServiceBOM__c(Name = 'SBOM-001', PFCL__c = pfcl.Id);
        insert bom;
    }

    @IsTest
    static void testSelectById_WhenNullEmptyOrMatch_ReturnsExpected() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        ServiceBOM__c bom = [SELECT Id FROM ServiceBOM__c LIMIT 1];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<ServiceBOM__c> nullResult = ServiceBOMsSelector.selectById(null);
            List<ServiceBOM__c> emptyResult = ServiceBOMsSelector.selectById(new Set<Id>());
            List<ServiceBOM__c> matchResult = ServiceBOMsSelector.selectById(new Set<Id>{ bom.Id });
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, nullResult.size());
            Assert.areEqual(0, emptyResult.size());
            Assert.areEqual(1, matchResult.size());
            Assert.areEqual(bom.Id, matchResult[0].Id);
        }
    }

    @IsTest
    static void testSelectByPFCLId_WhenNullEmptyOrMatch_ReturnsExpected() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        ServiceBOM__c bom = [SELECT Id, PFCL__c FROM ServiceBOM__c LIMIT 1];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<ServiceBOM__c> nullResult = ServiceBOMsSelector.selectByPFCLId(null);
            List<ServiceBOM__c> emptyResult = ServiceBOMsSelector.selectByPFCLId(new Set<Id>());
            List<ServiceBOM__c> matchResult = ServiceBOMsSelector.selectByPFCLId(
                new Set<Id>{ bom.PFCL__c }
            );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, nullResult.size());
            Assert.areEqual(0, emptyResult.size());
            Assert.isTrue(matchResult.size() >= 1);
            Assert.areEqual(bom.Id, matchResult[0].Id);
        }
    }
}