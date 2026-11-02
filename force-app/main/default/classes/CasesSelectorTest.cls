/**
 * @description Test class for CasesSelector
 *              Validates all query methods with proper data setup and bulk testing
 * @author STERIS
 * @date 2026-04-22
 */
@IsTest
private class CasesSelectorTest {
    
    /**
     * @description Test setup - creates test data for all tests
     */
    @TestSetup
    static void setupTestData() {
        // Create test Account (Customer validation requires Oracle Source System ID)
        Account testAccount = new Account(
            Name = 'Test Account',
            SourceSystemID__c = 'CASESEL01',
            SystemID__c = 'CASESYS02'
        );
        insert testAccount;
        
        // Create test Contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com',
            AccountId = testAccount.Id
        );
        insert testContact;
        
        // Create test Order
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            OrderNumber__c = 'ORD-12345'
        );
        insert testOrder;
        
        // Get Record Type Ids
        Id cbmCaseRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByName().get('CBM Case')?.getRecordTypeId();
        Id capitalLineRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Capital Line Sub Case')?.getRecordTypeId();
        
        // Create parent Cases (bulk - 10 parent cases)
        List<Case> parentCases = new List<Case>();
        for (Integer i = 0; i < 10; i++) {
            parentCases.add(new Case(
                Subject = 'Parent Case ' + i,
                Status = 'New',
                Origin = 'Web',
                Priority = 'Medium',
                AccountId = testAccount.Id,
                ContactId = testContact.Id,
                RecordTypeId = cbmCaseRecordTypeId,
                Order__c = testOrder.Id,
                Customer_Want_Date__c = Date.today().addDays(i)
            ));
        }
        insert parentCases;
        
        // Create child Cases (bulk - 20 child cases, 2 per parent)
        List<Case> childCases = new List<Case>();
        for (Case parentCase : parentCases) {
            for (Integer j = 0; j < 2; j++) {
                childCases.add(new Case(
                    Subject = 'Child Case for ' + parentCase.Subject + ' - ' + j,
                    Status = j == 0 ? 'New' : 'Closed',
                    Origin = 'Web',
                    Priority = 'High',
                    ParentId = parentCase.Id,
                    RecordTypeId = capitalLineRecordTypeId,
                    AccountId = testAccount.Id,
                    Customer_Want_Date__c = Date.today()
                ));
            }
        }
        insert childCases;
    }
    
    /**
     * @description Test selectById method
     */
    @IsTest
    static void testSelectById() {
        // Arrange
        List<Case> cases = [SELECT Id FROM Case WHERE ParentId = null LIMIT 5];
        Set<Id> caseIds = new Map<Id, Case>(cases).keySet();
        
        // Act
        Test.startTest();
        List<Case> results = CasesSelector.selectById(caseIds);
        Test.stopTest();
        
        // Assert
        System.Assert.areEqual(5, results.size(), 'Should return 5 cases');
        System.Assert.isNotNull(results[0].Subject, 'Subject should be populated');
        System.Assert.isNotNull(results[0].Status, 'Status should be populated');
    }
    
    /**
     * @description Test selectById with null input
     */
    @IsTest
    static void testSelectById_NullInput() {
        // Act
        Test.startTest();
        List<Case> results = CasesSelector.selectById(null);
        Test.stopTest();
        
        // Assert
        System.Assert.isTrue(results.isEmpty(), 'Should return empty list for null input');
    }
    
    /**
     * @description Test selectByIdWithExtendedFields method
     */
    @IsTest
    static void testSelectByIdWithExtendedFields() {
        // Arrange
        List<Case> cases = [SELECT Id FROM Case WHERE ParentId = null LIMIT 3];
        Set<Id> caseIds = new Map<Id, Case>(cases).keySet();
        
        // Act
        Test.startTest();
        List<Case> results = CasesSelector.selectByIdWithExtendedFields(caseIds);
        Test.stopTest();
        
        // Assert
        System.Assert.areEqual(3, results.size(), 'Should return 3 cases');
        System.Assert.isNotNull(results[0].Customer_Want_Date__c, 'Customer_Want_Date__c should be populated');
        System.Assert.isNotNull(results[0].Order__c, 'Order__c should be populated');
    }
    
    /**
     * @description Test selectByAccountIds method
     */
    @IsTest
    static void testSelectByAccountIds() {
        // Arrange
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Set<Id> accountIds = new Set<Id>{testAccount.Id};
        
        // Act
        Test.startTest();
        List<Case> results = CasesSelector.selectByAccountIds(accountIds);
        Test.stopTest();
        
        // Assert
        System.Assert.isTrue(results.size() > 0, 'Should return cases for account');
        for (Case caseRecord : results) {
            System.Assert.areEqual(testAccount.Id, caseRecord.AccountId, 'All should have correct AccountId');
        }
    }
    
    /**
     * @description Test selectByContactIds method
     */
    @IsTest
    static void testSelectByContactIds() {
        // Arrange
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        Set<Id> contactIds = new Set<Id>{testContact.Id};
        
        // Act
        Test.startTest();
        List<Case> results = CasesSelector.selectByContactIds(contactIds);
        Test.stopTest();
        
        // Assert
        System.Assert.isTrue(results.size() > 0, 'Should return cases for contact');
        for (Case caseRecord : results) {
            System.Assert.areEqual(testContact.Id, caseRecord.ContactId, 'All should have correct ContactId');
        }
    }
    
    /**
     * @description Test selectByOrderIds method
     */
    @IsTest
    static void testSelectByOrderIds() {
        // Arrange
        Order testOrder = [SELECT Id FROM Order LIMIT 1];
        Set<Id> orderIds = new Set<Id>{testOrder.Id};
        
        // Act
        Test.startTest();
        List<Case> results = CasesSelector.selectByOrderIds(orderIds);
        Test.stopTest();
        
        // Assert
        System.Assert.isTrue(results.size() > 0, 'Should return cases for order');
        for (Case caseRecord : results) {
            System.Assert.areEqual(testOrder.Id, caseRecord.Order__c, 'All should have correct Order__c');
        }
    }
    
    /**
     * @description Test selectOpenCasesByAccountIds method
     */
    @IsTest
    static void testSelectOpenCasesByAccountIds() {
        // Arrange
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Set<Id> accountIds = new Set<Id>{testAccount.Id};
        
        // Act
        Test.startTest();
        List<Case> results = CasesSelector.selectOpenCasesByAccountIds(accountIds);
        Test.stopTest();
        
        // Assert
        System.Assert.isTrue(results.size() > 0, 'Should return open cases');
        for (Case caseRecord : results) {
            System.Assert.isFalse(caseRecord.IsClosed, 'All should be open cases');
        }
    }
    
    /**
     * @description selectByIdWithExtendedFields returns empty when input is null
     */
    @IsTest
    static void testSelectByIdWithExtendedFields_NullInput() {
        Test.startTest();
        List<Case> results = CasesSelector.selectByIdWithExtendedFields(null);
        Test.stopTest();
        System.Assert.isTrue(results.isEmpty(), 'Null Id set should return empty list');
    }

    /**
     * @description selectById returns empty when the Id set is empty
     */
    @IsTest
    static void testSelectById_EmptySetInput() {
        Test.startTest();
        List<Case> results = CasesSelector.selectById(new Set<Id>());
        Test.stopTest();
        System.Assert.isTrue(results.isEmpty(), 'Should return empty list for empty set');
    }

    /**
     * @description selectByIdWithExtendedFields returns empty when the Id set is empty
     */
    @IsTest
    static void testSelectByIdWithExtendedFields_EmptySetInput() {
        Test.startTest();
        List<Case> results = CasesSelector.selectByIdWithExtendedFields(new Set<Id>());
        Test.stopTest();
        System.Assert.isTrue(results.isEmpty(), 'Should return empty list for empty set');
    }

    /**
     * @description selectByAccountIds returns empty for null or empty input
     */
    @IsTest
    static void testSelectByAccountIds_NullOrEmptyInput() {
        Test.startTest();
        List<Case> nullResult = CasesSelector.selectByAccountIds(null);
        List<Case> emptyResult = CasesSelector.selectByAccountIds(new Set<Id>());
        Test.stopTest();
        System.Assert.isTrue(nullResult.isEmpty(), 'Null account Id set should return empty list');
        System.Assert.isTrue(emptyResult.isEmpty(), 'Empty account Id set should return empty list');
    }

    /**
     * @description selectByContactIds returns empty for null or empty input
     */
    @IsTest
    static void testSelectByContactIds_NullOrEmptyInput() {
        Test.startTest();
        List<Case> nullResult = CasesSelector.selectByContactIds(null);
        List<Case> emptyResult = CasesSelector.selectByContactIds(new Set<Id>());
        Test.stopTest();
        System.Assert.isTrue(nullResult.isEmpty(), 'Null contact Id set should return empty list');
        System.Assert.isTrue(emptyResult.isEmpty(), 'Empty contact Id set should return empty list');
    }

    /**
     * @description selectByOrderIds returns empty for null or empty input
     */
    @IsTest
    static void testSelectByOrderIds_NullOrEmptyInput() {
        Test.startTest();
        List<Case> nullResult = CasesSelector.selectByOrderIds(null);
        List<Case> emptyResult = CasesSelector.selectByOrderIds(new Set<Id>());
        Test.stopTest();
        System.Assert.isTrue(nullResult.isEmpty(), 'Null order Id set should return empty list');
        System.Assert.isTrue(emptyResult.isEmpty(), 'Empty order Id set should return empty list');
    }

    /**
     * @description selectOpenCasesByAccountIds returns empty for null or empty input
     */
    @IsTest
    static void testSelectOpenCasesByAccountIds_NullOrEmptyInput() {
        Test.startTest();
        List<Case> nullResult = CasesSelector.selectOpenCasesByAccountIds(null);
        List<Case> emptyResult = CasesSelector.selectOpenCasesByAccountIds(new Set<Id>());
        Test.stopTest();
        System.Assert.isTrue(nullResult.isEmpty(), 'Null account Id set should return empty list');
        System.Assert.isTrue(emptyResult.isEmpty(), 'Empty account Id set should return empty list');
    }

    /**
     * @description selectByRecordTypeDeveloperName returns empty when developer name is blank
     */
    @IsTest
    static void testSelectByRecordTypeDeveloperName_BlankDeveloperName() {
        Test.startTest();
        List<Case> blank = CasesSelector.selectByRecordTypeDeveloperName('', 10);
        List<Case> whitespace = CasesSelector.selectByRecordTypeDeveloperName('   ', null);
        Test.stopTest();
        System.Assert.isTrue(blank.isEmpty(), 'Blank developer name should return empty list');
        System.Assert.isTrue(whitespace.isEmpty(), 'Whitespace-only developer name should return empty list');
    }

    /**
     * @description selectByRecordTypeDeveloperName returns empty when no Case record type matches the developer name
     */
    @IsTest
    static void testSelectByRecordTypeDeveloperName_NoMatchingRecordType() {
        Test.startTest();
        List<Case> results = CasesSelector.selectByRecordTypeDeveloperName('SterisSelector_NoSuchRt_Xyz12345', 50);
        Test.stopTest();
        System.Assert.isTrue(results.isEmpty(), 'Unknown developer name should return empty list');
    }

    /**
     * @description selectByRecordTypeDeveloperName returns rows for a valid developer name with LIMIT applied
     */
    @IsTest
    static void testSelectByRecordTypeDeveloperName_WithPositiveLimit() {
        String devName = developerNameForCaseRecordTypeLabel('CBM Case');
        if (String.isBlank(devName)) {
            return;
        }
        Test.startTest();
        List<Case> results = CasesSelector.selectByRecordTypeDeveloperName(devName, 3);
        Test.stopTest();
        Id expectedRt = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get(devName).getRecordTypeId();
        System.Assert.isTrue(results.size() <= 3, 'Should respect LIMIT');
        System.Assert.isTrue(results.size() > 0, 'Setup should include CBM Case rows');
        for (Case c : results) {
            System.Assert.areEqual(expectedRt, c.RecordTypeId);
        }
    }

    /**
     * @description selectByRecordTypeDeveloperName omits LIMIT when limitCount is null, zero, or negative
     */
    @IsTest
    static void testSelectByRecordTypeDeveloperName_NoLimitWhenNullOrNonPositive() {
        String devName = developerNameForCaseRecordTypeLabel('CBM Case');
        if (String.isBlank(devName)) {
            return;
        }
        Test.startTest();
        List<Case> withNullLimit = CasesSelector.selectByRecordTypeDeveloperName(devName, null);
        List<Case> withZeroLimit = CasesSelector.selectByRecordTypeDeveloperName(devName, 0);
        List<Case> withNegativeLimit = CasesSelector.selectByRecordTypeDeveloperName(devName, -5);
        Test.stopTest();
        System.Assert.isTrue(withNullLimit.size() >= 10, 'Without LIMIT should return all setup parent cases');
        System.Assert.isTrue(withZeroLimit.size() >= 10, 'Zero limit should behave as no LIMIT');
        System.Assert.isTrue(withNegativeLimit.size() >= 10, 'Negative limit should behave as no LIMIT');
    }

    /**
     * @description Resolves Case RecordType DeveloperName for a given record type label (org-specific).
     */
    private static String developerNameForCaseRecordTypeLabel(String labelName) {
        Id recordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByName().get(labelName)?.getRecordTypeId();
        if (recordTypeId == null) {
            return null;
        }
        for (Schema.RecordTypeInfo ri : Case.SObjectType.getDescribe().getRecordTypeInfos()) {
            if (ri.getRecordTypeId() == recordTypeId && ri.isAvailable()) {
                return ri.getDeveloperName();
            }
        }
        return null;
    }
}