/**
 * @description Tests for PFCLsSelector companion class (coverage for CBMQA dry-run).
 */
@IsTest
private class PFCLsSelectorTest {
    private static final String PFCL_NAME = 'PFCL-SEL-001';

    @TestSetup
    static void setupData() {
        /********************************************
         * SETUP
         ********************************************/
        insert new PFCL__c(Name = PFCL_NAME, PFCL__c = PFCL_NAME);
    }

    @IsTest
    static void testSelectById_WhenNullEmptyOrMatch_ReturnsExpected() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        PFCL__c pfcl = [SELECT Id FROM PFCL__c WHERE Name = :PFCL_NAME LIMIT 1];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<PFCL__c> nullResult = PFCLsSelector.selectById(null);
            List<PFCL__c> emptyResult = PFCLsSelector.selectById(new Set<Id>());
            List<PFCL__c> matchResult = PFCLsSelector.selectById(new Set<Id>{ pfcl.Id });
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, nullResult.size());
            Assert.areEqual(0, emptyResult.size());
            Assert.areEqual(1, matchResult.size());
            Assert.areEqual(pfcl.Id, matchResult[0].Id);
        }
    }

    @IsTest
    static void testSelectByNameAndAssetPfclValues_WhenGuardsOrMatch_ReturnsExpected() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<PFCL__c> nullByName = PFCLsSelector.selectByName(null);
            List<PFCL__c> emptyByName = PFCLsSelector.selectByName(new Set<String>());
            List<PFCL__c> byName = PFCLsSelector.selectByName(new Set<String>{ PFCL_NAME });
            List<PFCL__c> nullByAsset = PFCLsSelector.selectByAssetPfclValues(null);
            List<PFCL__c> emptyByAsset = PFCLsSelector.selectByAssetPfclValues(new Set<String>());
            List<PFCL__c> byAsset = PFCLsSelector.selectByAssetPfclValues(
                new Set<String>{ PFCL_NAME }
            );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, nullByName.size());
            Assert.areEqual(0, emptyByName.size());
            Assert.isTrue(byName.size() >= 1);
            Assert.areEqual(0, nullByAsset.size());
            Assert.areEqual(0, emptyByAsset.size());
            Assert.isTrue(byAsset.size() >= 1);
        }
    }
}