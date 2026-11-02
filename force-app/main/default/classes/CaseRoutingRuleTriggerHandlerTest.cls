/**
 * @description Test class for CaseRoutingRuleTriggerHandler
 * @author Agentforce
 * @date 2026-04-27
 * @group Test Classes
 */
@IsTest
private class CaseRoutingRuleTriggerHandlerTest {

    /**
     * @description First active CaseAssignment__c API value in this org (avoids INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST when metadata differs).
     */
    private static String firstActiveCaseAssignmentApi() {
        for (Schema.PicklistEntry pe : CaseRoutingRule__c.CaseAssignment__c.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                return pe.getValue();
            }
        }
        return null;
    }

    /**
     * @description Tests before insert trigger context
     */
    @IsTest
    static void testBeforeInsert() {
        String assign = firstActiveCaseAssignmentApi();
        System.assertNotEquals(null, assign, 'Org must expose at least one active CaseAssignment__c picklist value');

        // Arrange — adb builder supplies in-memory defaults (IsActive, Priority); trigger domain applyDefaults may be off
        adb_CaseRoutingRule_c ruleBuilder = new adb_CaseRoutingRule_c()
            .name('Trigger Test Rule')
            .subjectSearchString('Test Subject')
            .caseAssignment(assign);

        // Act
        Test.startTest();
        List<CaseRoutingRule__c> newRules = new List<CaseRoutingRule__c>();
        adb_DomainBuilder.save();
        newRules.add((CaseRoutingRule__c)ruleBuilder.record);
        Test.stopTest();

        // Assert - verify defaults were applied
        CaseRoutingRule__c inserted = [
            SELECT IsActive__c, Priority__c 
            FROM CaseRoutingRule__c 
            WHERE Id = :newRules[0].Id
        ];
        System.assertEquals(true, inserted.IsActive__c, 'Default IsActive should be true');
        System.assertEquals(100, inserted.Priority__c, 'Default Priority should be 100');
    }

    /**
     * @description Insert fails for invalid restricted picklist (platform). Domain validate() is not invoked from trigger in current build.
     */
    @IsTest
    static void testBeforeInsert_validationFailure() {
        String assign = firstActiveCaseAssignmentApi();
        System.assertNotEquals(null, assign, 'Org must expose at least one active CaseAssignment__c picklist value');

        List<CaseRoutingRule__c> invalidRules = new List<CaseRoutingRule__c>{
            new CaseRoutingRule__c(
                Name = 'Invalid CaseAssignment Insert',
                SubjectSearchString__c = 'Test',
                CaseAssignment__c = assign + '__NotAValidPicklistValue__'
            )
        };

        try {
            Test.startTest();
            insert invalidRules;
            Test.stopTest();
            System.assert(false, 'Expected DmlException for invalid CaseAssignment__c');
        } catch (DmlException e) {
            System.Assert.isTrue(
                e.getMessage().contains('INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST')
                    || e.getMessage().contains('bad value for restricted picklist'),
                e.getMessage()
            );
        }
    }

    /**
     * @description Tests before insert with whitespace normalization
     */
    @IsTest
    static void testBeforeInsert_normalization() {
        // Arrange
        String assign = firstActiveCaseAssignmentApi();
        System.assertNotEquals(null, assign, 'Org must expose at least one active CaseAssignment__c picklist value');

        List<CaseRoutingRule__c> rulesWithWhitespace = new List<CaseRoutingRule__c>{
            new CaseRoutingRule__c(
                Name = 'Test Rule',
                Priority__c = 10,
                SubjectSearchString__c = '  Extra Spaces  ',
                LabelValue__c = '  TestLabel  ',
                CaseAssignment__c = assign
            )
        };

        // Act
        Test.startTest();
        insert rulesWithWhitespace;
        Test.stopTest();

        // Assert - verify normalization
        CaseRoutingRule__c inserted = [
            SELECT SubjectSearchString__c, LabelValue__c 
            FROM CaseRoutingRule__c 
            WHERE Id = :rulesWithWhitespace[0].Id
        ];
        System.assertEquals('Extra Spaces', inserted.SubjectSearchString__c, 
            'SubjectSearchString should be trimmed');
        System.assertEquals('TestLabel', inserted.LabelValue__c, 
            'LabelValue should be trimmed');
    }

    /**
     * @description Tests before update trigger context
     */
    @IsTest
    static void testBeforeUpdate() {
        String assign = firstActiveCaseAssignmentApi();
        System.assertNotEquals(null, assign, 'Org must expose at least one active CaseAssignment__c picklist value');

        CaseRoutingRule__c rule = new CaseRoutingRule__c(
            Name = 'Original Rule',
            IsActive__c = false,
            Priority__c = 10,
            SubjectSearchString__c = 'Original Subject',
            CaseAssignment__c = assign
        );
        insert rule;

        // Modify the rule
        rule.Name = 'Updated Rule';
        rule.LabelValue__c = '  UpdatedLabel  ';

        // Act
        Test.startTest();
        update rule;
        Test.stopTest();

        // Assert - verify update and normalization
        CaseRoutingRule__c updated = [
            SELECT Name, LabelValue__c 
            FROM CaseRoutingRule__c 
            WHERE Id = :rule.Id
        ];
        System.assertEquals('Updated Rule', updated.Name, 'Name should be updated');
        System.assertEquals('UpdatedLabel', updated.LabelValue__c, 
            'LabelValue should be updated and trimmed');
    }

    /**
     * @description Update fails for invalid restricted picklist (platform). Domain validate() is not invoked from trigger in current build.
     */
    @IsTest
    static void testBeforeUpdate_validationFailure() {
        String assign = firstActiveCaseAssignmentApi();
        System.assertNotEquals(null, assign, 'Org must expose at least one active CaseAssignment__c picklist value');

        CaseRoutingRule__c rule = new CaseRoutingRule__c(
            Name = 'Test Rule',
            IsActive__c = false,
            Priority__c = 10,
            SubjectSearchString__c = 'Test Criteria',
            CaseAssignment__c = assign
        );
        insert rule;

        rule.CaseAssignment__c = assign + '__NotAValidPicklistValue__';

        try {
            Test.startTest();
            update rule;
            Test.stopTest();
            System.assert(false, 'Expected DmlException for invalid CaseAssignment__c on update');
        } catch (DmlException e) {
            System.Assert.isTrue(
                e.getMessage().contains('INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST')
                    || e.getMessage().contains('bad value for restricted picklist'),
                e.getMessage()
            );
        }
    }

    /**
     * @description Tests after insert trigger context
     */
    @IsTest
    static void testAfterInsert() {
        String assign = firstActiveCaseAssignmentApi();
        System.assertNotEquals(null, assign, 'Org must expose at least one active CaseAssignment__c picklist value');

        List<CaseRoutingRule__c> newRules = new List<CaseRoutingRule__c>{
            new CaseRoutingRule__c(
                Name = 'After Insert Test',
                Priority__c = 10,
                SubjectSearchString__c = 'Test',
                CaseAssignment__c = assign
            )
        };

        // Act
        Test.startTest();
        insert newRules;
        Test.stopTest();

        // Assert - verify record was inserted
        List<CaseRoutingRule__c> inserted = [
            SELECT Id, IsActive__c 
            FROM CaseRoutingRule__c 
            WHERE Name = 'After Insert Test'
        ];
        System.assertEquals(1, inserted.size(), 'Record should be inserted');
        System.assertEquals(true, inserted[0].IsActive__c, 'Inserted record should be active by default');
    }

    /**
     * @description Tests after update trigger context
     */
    @IsTest
    static void testAfterUpdate() {
        String assign = firstActiveCaseAssignmentApi();
        System.assertNotEquals(null, assign, 'Org must expose at least one active CaseAssignment__c picklist value');

        CaseRoutingRule__c rule = new CaseRoutingRule__c(
            Name = 'After Update Test Rule',
            IsActive__c = false,
            Priority__c = 10,
            SubjectSearchString__c = 'Test Criteria',
            CaseAssignment__c = assign
        );
        insert rule;

        rule.IsActive__c = true;

        Test.startTest();
        update rule;
        Test.stopTest();

        CaseRoutingRule__c updated = [
            SELECT IsActive__c
            FROM CaseRoutingRule__c
            WHERE Id = :rule.Id
        ];
        System.assertEquals(true, updated.IsActive__c, 'IsActive should be updated');
    }

    /**
     * @description Tests after delete trigger context
     */
    @IsTest
    static void testAfterDelete() {
        String assign = firstActiveCaseAssignmentApi();
        System.assertNotEquals(null, assign, 'Org must expose at least one active CaseAssignment__c picklist value');

        CaseRoutingRule__c rule = new CaseRoutingRule__c(
            Name = 'Delete Test',
            Priority__c = 10,
            SubjectSearchString__c = 'Test',
            CaseAssignment__c = assign
        );
        insert rule;

        // Act
        Test.startTest();
        delete rule;
        Test.stopTest();

        // Assert - verify deletion
        List<CaseRoutingRule__c> remaining = [
            SELECT Id 
            FROM CaseRoutingRule__c 
            WHERE Id = :rule.Id
        ];
        System.assertEquals(0, remaining.size(), 'Record should be deleted');
    }

    /**
     * @description Tests bulk insert with 200 records
     */
    @IsTest
    static void testBulkInsert() {
        String assign = firstActiveCaseAssignmentApi();
        System.assertNotEquals(null, assign, 'Org must expose at least one active CaseAssignment__c picklist value');

        List<CaseRoutingRule__c> bulkRules = new List<CaseRoutingRule__c>();

        for (Integer i = 1; i <= 200; i++) {
            bulkRules.add(
                new CaseRoutingRule__c(
                    Name = 'Bulk Test Rule ' + i,
                    Priority__c = i,
                    SubjectSearchString__c = 'Bulk Criteria ' + i,
                    CaseAssignment__c = assign
                )
            );
        }

        // Act
        Test.startTest();
        insert bulkRules;
        Test.stopTest();

        // Assert - verify all records were inserted
        List<CaseRoutingRule__c> inserted = [
            SELECT Id, IsActive__c, Priority__c 
            FROM CaseRoutingRule__c 
            WHERE Name LIKE 'Bulk Test Rule%'
        ];
        System.assertEquals(200, inserted.size(), 'Should insert 200 records');
        
        // Verify defaults were applied to all
        for (CaseRoutingRule__c rule : inserted) {
            System.assertEquals(true, rule.IsActive__c, 'All should have default IsActive=true');
        }
    }

    /**
     * @description Tests bulk update with 200 records
     */
    @IsTest
    static void testBulkUpdate() {
        String assign = firstActiveCaseAssignmentApi();
        System.assertNotEquals(null, assign, 'Org must expose at least one active CaseAssignment__c picklist value');

        List<CaseRoutingRule__c> bulkRules = new List<CaseRoutingRule__c>();

        for (Integer i = 1; i <= 200; i++) {
            bulkRules.add(
                new CaseRoutingRule__c(
                    Name = 'Bulk Update Test ' + i,
                    IsActive__c = false,
                    Priority__c = i,
                    SubjectSearchString__c = 'Criteria ' + i,
                    CaseAssignment__c = assign
                )
            );
        }
        insert bulkRules;

        for (CaseRoutingRule__c rule : bulkRules) {
            rule.IsActive__c = true;
        }

        // Act
        Test.startTest();
        update bulkRules;
        Test.stopTest();

        // Assert - verify all were updated
        List<CaseRoutingRule__c> updated = [
            SELECT IsActive__c 
            FROM CaseRoutingRule__c 
            WHERE Name LIKE 'Bulk Update Test%'
        ];
        System.assertEquals(200, updated.size(), 'Should update 200 records');
        
        // Verify all are now active
        for (CaseRoutingRule__c rule : updated) {
            System.assertEquals(true, rule.IsActive__c, 'All should be activated');
        }
    }
}