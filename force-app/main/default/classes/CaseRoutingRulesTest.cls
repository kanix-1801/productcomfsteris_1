/**
 * @description Test class for CaseRoutingRules domain class
 * @author Agentforce
 * @date 2026-04-27
 * @group Test Classes
 */
@IsTest
private class CaseRoutingRulesTest {
        
    /**
     * @description Tests getRecords method
     */
    @IsTest
    static void testGetRecords() {
        // Arrange
        List<CaseRoutingRule__c> rules = new List<CaseRoutingRule__c>{
            new CaseRoutingRule__c(
                Name = 'Test Rule',
                Priority__c = 10,
                SubjectSearchString__c = 'Test',
                CaseAssignment__c = 'Loaners'
            )
        };
        CaseRoutingRules domain = new CaseRoutingRules(rules);

        // Act
        Test.startTest();
        List<CaseRoutingRule__c> retrievedRules = domain.getRecords();
        Test.stopTest();

        // Assert
        System.assertEquals(1, retrievedRules.size(), 'Should return 1 record');
        System.assertEquals('Test Rule', retrievedRules[0].Name, 'Name should match');
    }
}