/**
 * @description Test class for CaseRoutingRulesSelector
 * @author Agentforce
 * @date 2026-04-27
 * @group Test Classes
 */
@IsTest
private class CaseRoutingRulesSelectorTest {
    /**
     * @description Test setup method to create test data using Domain Builder
     */
    @TestSetup
    static void setupTestData() {
        String primary = primaryCaseAssignmentMatchingOrigin();
        String secondary = secondaryCaseAssignmentApi(primary);
        List<adb_CaseRoutingRule_c> activeRules = new List<adb_CaseRoutingRule_c>();
        for (Integer i = 1; i <= 5; i++) {
            activeRules.add(
                new adb_CaseRoutingRule_c()
                    .name('Active Rule ' + i)
                    .isActive(true)
                    .priority(i * 10)
                    .subjectSearchString('Test Subject ' + i)
                    .caseAssignment(primary)
            );
        }
           
        // Create inactive rules using Domain Builder
        List<adb_CaseRoutingRule_c> inactiveRules = new List<adb_CaseRoutingRule_c>();
        for (Integer i = 1; i <= 3; i++) {
            inactiveRules.add(
                new adb_CaseRoutingRule_c()
                    .name('Inactive Rule ' + i)
                    .isActive(false)
                    .priority(100 + i)
                    .descriptionSearchString('Test Description ' + i)
                    .caseAssignment(secondary)
            );
        }
        adb_DomainBuilder.save();
    }

    /**
     * @description Tests selectById with valid Ids
     */
    @IsTest
    static void testSelectById_withValidIds() {
        // Arrange
        List<CaseRoutingRule__c> allRules = [SELECT Id FROM CaseRoutingRule__c LIMIT 3];
        Set<Id> ruleIds = new Map<Id, CaseRoutingRule__c>(allRules).keySet();

        // Act
        Test.startTest();
        List<CaseRoutingRule__c> results = CaseRoutingRulesSelector.selectById(ruleIds);
        Test.stopTest();

        // Assert
        System.assertEquals(3, results.size(), 'Should return 3 records');
        System.assertNotEquals(null, results[0].Name, 'Name should be populated');
    }

    /**
     * @description Tests selectById with null input
     */
    @IsTest
    static void testSelectById_withNullInput() {
        // Act
        Test.startTest();
        List<CaseRoutingRule__c> results = CaseRoutingRulesSelector.selectById(null);
        Test.stopTest();

        // Assert
        System.assertEquals(0, results.size(), 'Should return empty list for null input');
    }

    /**
     * @description Tests selectById with empty set
     */
    @IsTest
    static void testSelectById_withEmptySet() {
        // Act
        Test.startTest();
        List<CaseRoutingRule__c> results = CaseRoutingRulesSelector.selectById(new Set<Id>());
        Test.stopTest();

        // Assert
        System.assertEquals(0, results.size(), 'Should return empty list for empty set');
    }

    /**
     * @description Tests selectActiveRules returns only active records
     */
    @IsTest
    static void testSelectActiveRules() {
        // Act
        Test.startTest();
        List<CaseRoutingRule__c> results = CaseRoutingRulesSelector.selectActiveRules();
        Test.stopTest();

        // Assert
        System.assertEquals(5, results.size(), 'Should return 5 active rules');
        
        // Verify all are active
        for (CaseRoutingRule__c rule : results) {
            System.assertEquals(true, rule.IsActive__c, 'All records should be active');
        }
        
        // Verify ordering by priority
        for (Integer i = 0; i < results.size() - 1; i++) {
            System.assert(results[i].Priority__c <= results[i + 1].Priority__c, 
                'Records should be ordered by priority ascending');
        }
    }

    /**
     * @description Tests selectByActiveStatus with true
     */
    @IsTest
    static void testSelectByActiveStatus_active() {
        // Act
        Test.startTest();
        List<CaseRoutingRule__c> results = CaseRoutingRulesSelector.selectByActiveStatus(true);
        Test.stopTest();

        // Assert
        System.assertEquals(5, results.size(), 'Should return 5 active rules');
        for (CaseRoutingRule__c rule : results) {
            System.assertEquals(true, rule.IsActive__c, 'All records should be active');
        }
    }

    /**
     * @description Tests selectByActiveStatus with false
     */
    @IsTest
    static void testSelectByActiveStatus_inactive() {
        // Act
        Test.startTest();
        List<CaseRoutingRule__c> results = CaseRoutingRulesSelector.selectByActiveStatus(false);
        Test.stopTest();

        // Assert
        System.assertEquals(3, results.size(), 'Should return 3 inactive rules');
        for (CaseRoutingRule__c rule : results) {
            System.assertEquals(false, rule.IsActive__c, 'All records should be inactive');
        }
    }

    /**
     * @description Tests selectAll with limit
     */
    @IsTest
    static void testSelectAll() {
        // Act
        Test.startTest();
        List<CaseRoutingRule__c> results = CaseRoutingRulesSelector.selectAll();
        Test.stopTest();

        // Assert
        System.assertEquals(8, results.size(), 'Should return all 8 test records');
    }

    /**
     * @description Jira GW-1279 — Resolves a CaseAssignment__c API value that matches an active Case.Origin (routing test helper).
     */
    private static String primaryCaseAssignmentMatchingOrigin() {
        Set<String> origins = new Set<String>();
        for (Schema.PicklistEntry pe : Case.Origin.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                origins.add(pe.getValue());
            }
        }
        for (Schema.PicklistEntry pe : CaseRoutingRule__c.CaseAssignment__c.getDescribe().getPicklistValues()) {
            if (pe.isActive() && origins.contains(pe.getValue())) {
                return pe.getValue();
            }
        }
        for (Schema.PicklistEntry pe : CaseRoutingRule__c.CaseAssignment__c.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                return pe.getValue();
            }
        }
        return 'Email';
    }

    /**
     * @description Jira GW-1279 — Returns a different active CaseAssignment__c than primary when one exists (routing test helper).
     */
    private static String secondaryCaseAssignmentApi(String primary) {
        for (Schema.PicklistEntry pe : CaseRoutingRule__c.CaseAssignment__c.getDescribe().getPicklistValues()) {
            if (pe.isActive() && pe.getValue() != primary) {
                return pe.getValue();
            }
        }
        return primary;
    }

    /**
     * @description Jira GW-1279 — selectActiveCRRsByAssignment with valid case assignments (active rules only)
     */
    @IsTest
    static void testSelectActiveCRRsByAssignment_withValidAssignments() {
        // Arrange
        String primary = primaryCaseAssignmentMatchingOrigin();
        String secondary = secondaryCaseAssignmentApi(primary);
        Set<String> caseAssignments = new Set<String>{ primary, secondary };

        // Act
        Test.startTest();
        List<CaseRoutingRule__c> results = CaseRoutingRulesSelector.selectActiveCRRsByAssignment(caseAssignments);
        Test.stopTest();

        // Assert — only active rules whose CaseAssignment__c is in the set (inactive rules excluded)
        System.assertEquals(5, results.size(), 'Should return 5 active rules for primary assignment');
        for (CaseRoutingRule__c rule : results) {
            System.assertEquals(true, rule.IsActive__c, 'Selector returns active rules only');
            System.assert(caseAssignments.contains(rule.CaseAssignment__c),
                'Case assignment should be in the filter set');
        }
    }

    /**
     * @description Jira GW-1279 — selectActiveCRRsByAssignment with null input
     */
    @IsTest
    static void testSelectActiveCRRsByAssignment_withNullInput() {
        // Act
        Test.startTest();
        List<CaseRoutingRule__c> results = CaseRoutingRulesSelector.selectActiveCRRsByAssignment(null);
        Test.stopTest();

        // Assert
        System.assertEquals(0, results.size(), 'Should return empty list for null input');
    }

    /**
     * @description Jira GW-1279 — selectActiveCRRsByAssignment with empty set
     */
    @IsTest
    static void testSelectActiveCRRsByAssignment_withEmptySet() {
        Test.startTest();
        List<CaseRoutingRule__c> results = CaseRoutingRulesSelector.selectActiveCRRsByAssignment(new Set<String>());
        Test.stopTest();
        System.assertEquals(0, results.size(), 'Should return empty list for empty set');
    }
}