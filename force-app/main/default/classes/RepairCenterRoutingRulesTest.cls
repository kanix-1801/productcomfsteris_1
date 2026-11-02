/**
 * @description Test class for RepairCenterRoutingRules domain class.
 *              Covers constructor and domain exception.
 */
@IsTest
private class RepairCenterRoutingRulesTest {

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
            List<RepairCenterRoutingRule__c> ruleList = new List<RepairCenterRoutingRule__c>{
                (RepairCenterRoutingRule__c) new adb_RepairCenterRoutingRule().model('Rule A').record,
                (RepairCenterRoutingRule__c) new adb_RepairCenterRoutingRule().model('Rule B').record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            RepairCenterRoutingRules domain = new RepairCenterRoutingRules(ruleList);
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
            RepairCenterRoutingRules domain = new RepairCenterRoutingRules(new List<RepairCenterRoutingRule__c>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    @IsTest
    static void shouldThrowRepairCenterRoutingRulesException_WhenExceptionIsRaised() {
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
                throw new RepairCenterRoutingRules.RepairCenterRoutingRulesException('Name is required.');
            } catch (RepairCenterRoutingRules.RepairCenterRoutingRulesException e) {
                Assert.areEqual(
                    'Name is required.',
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