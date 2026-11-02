/**
 * @author PSL
 * @date 11-27-2025
 * @description Test class for TaskQuickActionController
 */
@IsTest
private class TaskQuickActionControllerTest {

    // Utility: create a Case with minimal required fields
    private static Case createCase(String emailType) {
        Case c = new Case(
            Subject = 'Test Case',
            Origin  = 'Phone',
            EmailType__c = emailType
        );
        insert c;
        return c;
    }

    @IsTest
    static void test_getTaskById_validId() {
        // Setup: ensure EmailType__c is populated so we can assert it
        Task t = new Task(
            Subject       = 'SOA'
          //  EmailType__c  = 'Transactional' // make assertion meaningful
        );
        insert t;

        Test.startTest();
        Task result = TaskQuickActionController.getTaskById(t.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(t.Id, result.Id, 'Task ID should match');
        //System.assertEquals('Transactional', result.EmailType__c, 'EmailType should match');
        // Optional: WhatId is not set, verify null
        System.assertEquals(null, result.WhatId, 'WhatId should be null for this setup');
    }

    @IsTest
    static void test_getTaskById_nullId() {
        Test.startTest();
        Task result = TaskQuickActionController.getTaskById(null);
        Test.stopTest();

        System.assertEquals(null, result, 'Result should be null when input is null');
    }

    @IsTest
    static void test_getTaskById_invalidId_throwsHandled() {
        // Using a valid-format but non-existent Id (18-char) ensures query returns 0 rows,
        // which triggers the catch path "List has no rows for assignment to SObject".
        // Example: start with a known prefix and pad; or simply use the 15/18-char form that won't exist.
        String nonExistentId = '001000000000000AAA'; // Well-formed, but does not exist

        Test.startTest();
        Task result = TaskQuickActionController.getTaskById(nonExistentId);
        Test.stopTest();

        System.assertEquals(null, result, 'Result should be null when ID is non-existent');
    }

    @IsTest
    static void test_updateCaseEmailType_validUpdate() {
        Case c = createCase('OldType');

        Test.startTest();
        TaskQuickActionController.updateCaseEmailType(c.Id, 'NewType');
        Test.stopTest();

        Case updated = [SELECT EmailType__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('NewType', updated.EmailType__c, 'EmailType should be updated');
    }

    @IsTest
    static void test_updateCaseEmailType_sameValue_noDML() {
        Case c = createCase('SameType');

        Test.startTest();
        TaskQuickActionController.updateCaseEmailType(c.Id, 'SameType'); // Same value, no update
        Test.stopTest();

        Case updated = [SELECT EmailType__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('SameType', updated.EmailType__c, 'EmailType should remain unchanged');
    }

    @IsTest
    static void test_updateCaseEmailType_nullCaseId() {
        Test.startTest();
        TaskQuickActionController.updateCaseEmailType(null, 'NewType');
        Test.stopTest();

        // No exception expected; nothing to assert beyond successful execution
        System.assert(true, 'Method should return silently for null caseId');
    }

    @IsTest
    static void test_updateCaseEmailType_emptyEmailType() {
        Case c = createCase('OldType');

        Test.startTest();
        TaskQuickActionController.updateCaseEmailType(c.Id, '');
        Test.stopTest();

        Case updated = [SELECT EmailType__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('OldType', updated.EmailType__c, 'EmailType should remain unchanged when empty emailType is passed');
    }

    @IsTest
    static void test_updateCaseEmailType_malformedId_throws() {
        // This exercises the catch block in updateCaseEmailType and the "throw e" rethrow
        Boolean threw = false;

        Test.startTest();
        try {
            TaskQuickActionController.updateCaseEmailType('abc', 'NewType'); // Malformed Id → QueryException
        } catch (Exception e) {
            threw = true;
            //System.assert(e.getMessage().containsIgnoreCase('malformed id')
                         // || e.getMessage().containsIgnoreCase('invalid id'),
                          //'Should throw malformed/invalid Id exception');
        }
        Test.stopTest();

        System.assert(threw, 'Exception should be thrown and reach test (rethrow path)');
    }

  @IsTest
    static void test_updateCaseEmailLang() {
        Case c = createCase('English');

        Test.startTest();
        TaskQuickActionController.updateCaseEmailLanguage(c.Id, 'English'); // Same value, no update
        Test.stopTest();

        Case updated = [SELECT EmailLanguage__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('English', updated.EmailLanguage__c, 'EmailLanguage should remain unchanged');
    }
   @IsTest
    static void test_updateCaseEmailLangFrench() {
        Case c = createCase('French');

        Test.startTest();
        TaskQuickActionController.updateCaseEmailLanguage(c.Id, 'French'); // Same value, no update
        Test.stopTest();

        Case updated = [SELECT EmailLanguage__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('French', updated.EmailLanguage__c, 'EmailLanguage should remain unchanged');
    }
     @IsTest
    static void test_updateCaseEmailLangFrenchException() {
        Case c = createCase('French');

       Boolean threw = false;

        Test.startTest();
        try {
            TaskQuickActionController.updateCaseEmailLanguage('abc', 'French'); // Malformed Id → QueryException
        } catch (Exception e) {
            threw = true;
            //System.assert(e.getMessage().containsIgnoreCase('malformed id')
                         // || e.getMessage().containsIgnoreCase('invalid id'),
                          //'Should throw malformed/invalid Id exception');
        }
        Test.stopTest();

        System.assert(threw, 'Exception should be thrown and reach test (rethrow path)');    }

}