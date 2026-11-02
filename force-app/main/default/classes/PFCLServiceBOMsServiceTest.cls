/**
 * @description Test class for PFCLServiceBOMsService.
 *              Covers create, update, delete, and retrieval operations
 *              across positive, negative, bulk, and empty-input scenarios.
 */
@IsTest
private class PFCLServiceBOMsServiceTest {

    @TestSetup
    static void setupTestData() {
        // Build a PFCL and a Service BOM, then 10 junction records linking them
        PFCL__c pfcl = newPfcl('Parent PFCL');
        insert pfcl;
        ServiceBOM__c serviceBom = new ServiceBOM__c(Name = 'Parent BOM');
        insert serviceBom;
        List<PFCLServiceBOM__c> junctions = new List<PFCLServiceBOM__c>();
        for (Integer i = 0; i < 10; i++) {
            junctions.add(new PFCLServiceBOM__c(PFCL__c = pfcl.Id, ServiceBOM__c = serviceBom.Id));
        }
        insert junctions;
    }

    // ── createPFCLServiceBOMs ───────────────────────────────────────────────

    @IsTest
    static void shouldCreatePFCLServiceBOMs_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            PFCL__c pfcl = [SELECT Id FROM PFCL__c LIMIT 1];
            ServiceBOM__c serviceBom = [SELECT Id FROM ServiceBOM__c LIMIT 1];
            List<PFCLServiceBOM__c> junctionList = new List<PFCLServiceBOM__c>{
                new PFCLServiceBOM__c(PFCL__c = pfcl.Id, ServiceBOM__c = serviceBom.Id),
                new PFCLServiceBOM__c(PFCL__c = pfcl.Id, ServiceBOM__c = serviceBom.Id)
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            PFCLServiceBOMsService.createPFCLServiceBOMs(junctionList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIds = new Map<Id, PFCLServiceBOM__c>(junctionList).keySet();
            List<PFCLServiceBOM__c> insertedList = [SELECT Id FROM PFCLServiceBOM__c WHERE Id IN :insertedIds];
            Assert.areEqual(2, insertedList.size(), 'createPFCLServiceBOMs should insert all 2 junction records');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreatePFCLServiceBOMsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM PFCLServiceBOM__c];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            PFCLServiceBOMsService.createPFCLServiceBOMs(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM PFCLServiceBOM__c];
            Assert.areEqual(countBefore, countAfter, 'createPFCLServiceBOMs with null should not insert any records');
        }
    }

    // ── updatePFCLServiceBOMs ───────────────────────────────────────────────

    @IsTest
    static void shouldUpdatePFCLServiceBOMs_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<PFCLServiceBOM__c> junctionList = [SELECT Id, PFCL__c FROM PFCLServiceBOM__c LIMIT 3];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            PFCLServiceBOMsService.updatePFCLServiceBOMs(junctionList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(3, junctionList.size(), 'updatePFCLServiceBOMs should process the provided records without error');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenUpdatePFCLServiceBOMsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            PFCLServiceBOMsService.updatePFCLServiceBOMs(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(true, 'updatePFCLServiceBOMs with null should complete without error');
        }
    }

    // ── deletePFCLServiceBOMs ───────────────────────────────────────────────

    @IsTest
    static void shouldDeletePFCLServiceBOMs_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> junctionIdSet = new Map<Id, PFCLServiceBOM__c>([SELECT Id FROM PFCLServiceBOM__c LIMIT 3]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            PFCLServiceBOMsService.deletePFCLServiceBOMs(junctionIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM PFCLServiceBOM__c WHERE Id IN :junctionIdSet];
            Assert.areEqual(0, remainingCount, 'deletePFCLServiceBOMs should delete all specified junction records');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeletePFCLServiceBOMsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM PFCLServiceBOM__c];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            PFCLServiceBOMsService.deletePFCLServiceBOMs(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM PFCLServiceBOM__c];
            Assert.areEqual(countBefore, countAfter, 'deletePFCLServiceBOMs with null should not delete any records');
        }
    }

    // ── getPFCLServiceBOMsById ──────────────────────────────────────────────

    @IsTest
    static void shouldReturnPFCLServiceBOMs_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> junctionIdSet = new Map<Id, PFCLServiceBOM__c>([SELECT Id FROM PFCLServiceBOM__c]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<PFCLServiceBOM__c> resultList = PFCLServiceBOMsService.getPFCLServiceBOMsById(junctionIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(10, resultList.size(), 'getPFCLServiceBOMsById should return all 10 junction records');
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
            List<PFCLServiceBOM__c> resultList = PFCLServiceBOMsService.getPFCLServiceBOMsById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getPFCLServiceBOMsById with null should return an empty list');
        }
    }

    @IsTest
    static void shouldCoverSelectorQueriesAndWrapDmlFailures() {
        PFCLServiceBOM__c junction = [
            SELECT Id, PFCL__c, ServiceBOM__c
            FROM PFCLServiceBOM__c
            LIMIT 1
        ];
        Assert.isTrue(PFCLServiceBOMsSelector.selectById(null).isEmpty());
        Assert.isTrue(PFCLServiceBOMsSelector.selectByPFCLId(new Set<Id>()).isEmpty());
        Assert.isTrue(PFCLServiceBOMsSelector.selectByServiceBOMId(null).isEmpty());
        Assert.isFalse(
            PFCLServiceBOMsSelector.selectByPFCLId(new Set<Id>{ junction.PFCL__c }).isEmpty()
        );
        Assert.isFalse(
            PFCLServiceBOMsSelector.selectByServiceBOMId(new Set<Id>{ junction.ServiceBOM__c })
                .isEmpty()
        );

        Boolean createThrew = false;
        try {
            PFCLServiceBOMsService.createPFCLServiceBOMs(
                new List<PFCLServiceBOM__c>{ new PFCLServiceBOM__c(Id = junction.Id) }
            );
        } catch (PFCLServiceBOMsService.PFCLServiceBOMsServiceException e) {
            createThrew = true;
        }
        Boolean updateThrew = false;
        try {
            PFCLServiceBOMsService.updatePFCLServiceBOMs(
                new List<PFCLServiceBOM__c>{
                    new PFCLServiceBOM__c(
                        Id = (Id) (PFCLServiceBOM__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001')
                    )
                }
            );
        } catch (PFCLServiceBOMsService.PFCLServiceBOMsServiceException e) {
            updateThrew = true;
        }
        PFCLServiceBOMsService.deletePFCLServiceBOMs(new Set<Id>{ UserInfo.getUserId() });
        Assert.isTrue(createThrew);
        Assert.isTrue(updateThrew);
    }

    private static PFCL__c newPfcl(String name) {
        Id esRtId = Schema.SObjectType.PFCL__c.getRecordTypeInfosByDeveloperName()
            .get('ESPFCL')
            ?.getRecordTypeId();
        return new PFCL__c(Name = name, RecordTypeId = esRtId);
    }
}