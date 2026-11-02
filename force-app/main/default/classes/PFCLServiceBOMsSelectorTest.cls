/**
 * @description Tests for PFCLServiceBOMsSelector companion class (coverage for CBMQA dry-run).
 */
@IsTest
private class PFCLServiceBOMsSelectorTest {
    @IsTest
    static void testSelectGuards_WhenNullOrEmpty_ReturnsEmpty() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<PFCLServiceBOM__c> nullById = PFCLServiceBOMsSelector.selectById(null);
            List<PFCLServiceBOM__c> emptyById = PFCLServiceBOMsSelector.selectById(new Set<Id>());
            List<PFCLServiceBOM__c> nullByPfcl = PFCLServiceBOMsSelector.selectByPFCLId(null);
            List<PFCLServiceBOM__c> emptyByPfcl = PFCLServiceBOMsSelector.selectByPFCLId(new Set<Id>());
            List<PFCLServiceBOM__c> nullByBom = PFCLServiceBOMsSelector.selectByServiceBOMId(null);
            List<PFCLServiceBOM__c> emptyByBom = PFCLServiceBOMsSelector.selectByServiceBOMId(
                new Set<Id>()
            );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, nullById.size());
            Assert.areEqual(0, emptyById.size());
            Assert.areEqual(0, nullByPfcl.size());
            Assert.areEqual(0, emptyByPfcl.size());
            Assert.areEqual(0, nullByBom.size());
            Assert.areEqual(0, emptyByBom.size());
        }
    }

    @IsTest
    static void testSelectById_WhenMatch_ReturnsRowOrHandlesSecurity() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        PFCL__c pfcl = new PFCL__c(Name = 'PFCL-SBOM-JUNC-001');
        insert pfcl;
        ServiceBOM__c bom = new ServiceBOM__c(Name = 'SBOM-JUNC-001', PFCL__c = pfcl.Id);
        insert bom;
        PFCLServiceBOM__c junction = new PFCLServiceBOM__c(
            PFCL__c = pfcl.Id,
            ServiceBOM__c = bom.Id
        );
        insert junction;

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN / THEN
             ********************************************/
            // Call each selector in its own try/catch so a USER_MODE failure on
            // selectById still executes the selectByPFCLId / selectByServiceBOMId query paths.
            Test.startTest();
            invokeSelectById(new Set<Id>{ junction.Id });
            invokeSelectByPFCLId(new Set<Id>{ pfcl.Id });
            invokeSelectByServiceBOMId(new Set<Id>{ bom.Id });
            Test.stopTest();
        }
    }

    private static void invokeSelectById(Set<Id> ids) {
        try {
            List<PFCLServiceBOM__c> rows = PFCLServiceBOMsSelector.selectById(ids);
            Assert.isTrue(rows.size() >= 1);
        } catch (QueryException e) {
            assertSecurityEnforced(e);
        }
    }

    private static void invokeSelectByPFCLId(Set<Id> pfclIds) {
        try {
            List<PFCLServiceBOM__c> rows = PFCLServiceBOMsSelector.selectByPFCLId(pfclIds);
            Assert.isTrue(rows.size() >= 1);
        } catch (QueryException e) {
            assertSecurityEnforced(e);
        }
    }

    private static void invokeSelectByServiceBOMId(Set<Id> serviceBomIds) {
        try {
            List<PFCLServiceBOM__c> rows = PFCLServiceBOMsSelector.selectByServiceBOMId(
                serviceBomIds
            );
            Assert.isTrue(rows.size() >= 1);
        } catch (QueryException e) {
            assertSecurityEnforced(e);
        }
    }

    private static void assertSecurityEnforced(QueryException e) {
        // WITH USER_MODE may block when FLS is incomplete in target org.
        Assert.isTrue(
            e.getMessage().contains('Insufficient permissions') ||
                e.getMessage().contains('secure query'),
            'Unexpected query failure: ' + e.getMessage()
        );
    }
}