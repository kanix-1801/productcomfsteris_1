/**
 * @description Test class for RepairCenterRoutingRulesService.
 *              Covers create, update, delete, and retrieval operations
 *              across positive, negative, bulk, and empty-input scenarios.
 */
@IsTest
private class RepairCenterRoutingRulesServiceTest {

    @TestSetup
    static void setupTestData() {
        // Build and persist 10 routing rules
        List<RepairCenterRoutingRule__c> ruleList = new List<RepairCenterRoutingRule__c>();
        for (Integer i = 0; i < 10; i++) {
            ruleList.add((RepairCenterRoutingRule__c) new adb_RepairCenterRoutingRule().model('Routing Rule ' + i).record);
        }
        insert ruleList;
    }

    // ── createRepairCenterRoutingRules ────────────────────────────────────────

    @IsTest
    static void shouldCreateRepairCenterRoutingRules_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<RepairCenterRoutingRule__c> ruleList = new List<RepairCenterRoutingRule__c>{
                (RepairCenterRoutingRule__c) new adb_RepairCenterRoutingRule().model('New Rule 1').record,
                (RepairCenterRoutingRule__c) new adb_RepairCenterRoutingRule().model('New Rule 2').record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            RepairCenterRoutingRulesService.createRepairCenterRoutingRules(ruleList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIds = new Map<Id, RepairCenterRoutingRule__c>(ruleList).keySet();
            List<RepairCenterRoutingRule__c> insertedList = [SELECT Id FROM RepairCenterRoutingRule__c WHERE Id IN :insertedIds];
            Assert.areEqual(2, insertedList.size(), 'createRepairCenterRoutingRules should insert all 2 rules');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateRepairCenterRoutingRulesCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM RepairCenterRoutingRule__c];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            RepairCenterRoutingRulesService.createRepairCenterRoutingRules(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM RepairCenterRoutingRule__c];
            Assert.areEqual(countBefore, countAfter, 'createRepairCenterRoutingRules with null should not insert any records');
        }
    }

    // ── updateRepairCenterRoutingRules ────────────────────────────────────────

    @IsTest
    static void shouldUpdateRepairCenterRoutingRules_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<RepairCenterRoutingRule__c> ruleList = [SELECT Id, Model__c FROM RepairCenterRoutingRule__c LIMIT 3];
            for (RepairCenterRoutingRule__c r : ruleList) {
                r.Model__c = 'Updated ' + r.Model__c;
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            RepairCenterRoutingRulesService.updateRepairCenterRoutingRules(ruleList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIds = new Map<Id, RepairCenterRoutingRule__c>(ruleList).keySet();
            List<RepairCenterRoutingRule__c> updatedList = [SELECT Id, Model__c FROM RepairCenterRoutingRule__c WHERE Id IN :updatedIds];
            for (RepairCenterRoutingRule__c r : updatedList) {
                Assert.isTrue(r.Model__c.startsWith('Updated'), 'Model__c should start with Updated');
            }
        }
    }

    // ── deleteRepairCenterRoutingRules ────────────────────────────────────────

    @IsTest
    static void shouldDeleteRepairCenterRoutingRules_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> ruleIdSet = new Map<Id, RepairCenterRoutingRule__c>([SELECT Id FROM RepairCenterRoutingRule__c LIMIT 3]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            RepairCenterRoutingRulesService.deleteRepairCenterRoutingRules(ruleIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM RepairCenterRoutingRule__c WHERE Id IN :ruleIdSet];
            Assert.areEqual(0, remainingCount, 'deleteRepairCenterRoutingRules should delete all specified rules');
        }
    }

    // ── getRepairCenterRoutingRulesById ───────────────────────────────────────

    @IsTest
    static void shouldReturnRepairCenterRoutingRules_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> ruleIdSet = new Map<Id, RepairCenterRoutingRule__c>([SELECT Id FROM RepairCenterRoutingRule__c]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<RepairCenterRoutingRule__c> resultList = RepairCenterRoutingRulesService.getRepairCenterRoutingRulesById(ruleIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(10, resultList.size(), 'getRepairCenterRoutingRulesById should return all 10 rules');
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
            List<RepairCenterRoutingRule__c> resultList = RepairCenterRoutingRulesService.getRepairCenterRoutingRulesById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getRepairCenterRoutingRulesById with null should return an empty list');
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }
}