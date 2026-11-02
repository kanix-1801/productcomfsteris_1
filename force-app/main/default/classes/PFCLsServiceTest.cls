/**
 * @description Test class for PFCLsService.
 *              Covers create, update, delete, and retrieval operations
 *              across positive, negative, bulk, and empty-input scenarios.
 */
@IsTest
private class PFCLsServiceTest {

    @TestSetup
    static void setupTestData() {
        // Build and persist 10 PFCLs
        List<PFCL__c> pfclList = new List<PFCL__c>();
        for (Integer i = 0; i < 10; i++) {
            pfclList.add(newPfcl('Test PFCL ' + i));
        }
        insert pfclList;
    }

    // ── createPFCLs ─────────────────────────────────────────────────────────

    @IsTest
    static void shouldCreatePFCLs_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<PFCL__c> pfclList = new List<PFCL__c>{
                newPfcl('New PFCL 1'),
                newPfcl('New PFCL 2')
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            PFCLsService.createPFCLs(pfclList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIds = new Map<Id, PFCL__c>(pfclList).keySet();
            List<PFCL__c> insertedList = [SELECT Id FROM PFCL__c WHERE Id IN :insertedIds];
            Assert.areEqual(2, insertedList.size(), 'createPFCLs should insert all 2 PFCLs');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreatePFCLsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM PFCL__c];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            PFCLsService.createPFCLs(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM PFCL__c];
            Assert.areEqual(countBefore, countAfter, 'createPFCLs with null should not insert any records');
        }
    }

    // ── updatePFCLs ─────────────────────────────────────────────────────────

    @IsTest
    static void shouldUpdatePFCLs_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<PFCL__c> pfclList = [SELECT Id, Description__c FROM PFCL__c LIMIT 3];
            for (PFCL__c pfcl : pfclList) {
                pfcl.Description__c = 'Updated Description';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            PFCLsService.updatePFCLs(pfclList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIds = new Map<Id, PFCL__c>(pfclList).keySet();
            List<PFCL__c> updatedList = [SELECT Id, Description__c FROM PFCL__c WHERE Id IN :updatedIds];
            for (PFCL__c pfcl : updatedList) {
                Assert.areEqual('Updated Description', pfcl.Description__c, 'Description should be updated');
            }
        }
    }

    @IsTest
    static void shouldDoNothing_WhenUpdatePFCLsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            PFCLsService.updatePFCLs(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(true, 'updatePFCLs with null should complete without error');
        }
    }

    // ── deletePFCLs ─────────────────────────────────────────────────────────

    @IsTest
    static void shouldDeletePFCLs_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> pfclIdSet = new Map<Id, PFCL__c>([SELECT Id FROM PFCL__c LIMIT 3]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            PFCLsService.deletePFCLs(pfclIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM PFCL__c WHERE Id IN :pfclIdSet];
            Assert.areEqual(0, remainingCount, 'deletePFCLs should delete all specified PFCLs');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeletePFCLsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM PFCL__c];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            PFCLsService.deletePFCLs(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM PFCL__c];
            Assert.areEqual(countBefore, countAfter, 'deletePFCLs with null should not delete any records');
        }
    }

    // ── getPFCLsById ────────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnPFCLs_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> pfclIdSet = new Map<Id, PFCL__c>([SELECT Id FROM PFCL__c]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<PFCL__c> resultList = PFCLsService.getPFCLsById(pfclIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(10, resultList.size(), 'getPFCLsById should return all 10 PFCLs');
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
            List<PFCL__c> resultList = PFCLsService.getPFCLsById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getPFCLsById with null should return an empty list');
        }
    }

    @IsTest
    static void shouldPropagateDmlFailureOnCreateAndUpdate() {
        PFCL__c existing = [SELECT Id FROM PFCL__c LIMIT 1];
        Boolean createThrew = false;
        try {
            PFCLsService.createPFCLs(
                new List<PFCL__c>{ new PFCL__c(Id = existing.Id, Name = 'Should Not Insert') }
            );
        } catch (DmlException e) {
            createThrew = true;
        }
        Boolean updateThrew = false;
        try {
            PFCLsService.updatePFCLs(
                new List<PFCL__c>{
                    new PFCL__c(
                        Id = (Id) (PFCL__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001'),
                        Name = 'Invalid'
                    )
                }
            );
        } catch (DmlException e) {
            updateThrew = true;
        }
        PFCLsService.createPFCLs(new List<PFCL__c>());
        PFCLsService.updatePFCLs(new List<PFCL__c>());
        PFCLsService.deletePFCLs(new Set<Id>());
        PFCLsService.deletePFCLs(new Set<Id>{ UserInfo.getUserId() });
        Assert.isTrue(createThrew, 'Insert with an existing Id should throw DmlException');
        Assert.isTrue(updateThrew, 'Update with a non-PFCL Id should throw DmlException');
    }

    private static PFCL__c newPfcl(String name) {
        Id esRtId = Schema.SObjectType.PFCL__c.getRecordTypeInfosByDeveloperName()
            .get('ESPFCL')
            ?.getRecordTypeId();
        return new PFCL__c(Name = name, RecordTypeId = esRtId);
    }
}