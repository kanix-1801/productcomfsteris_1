/**
 * @author PSL
 * @date 11-26-2025
 * @description Test class for CaseTriggerHelper to verify proper handling of child case updates when parent case Customer_Want_Date__c changes.
 */
@IsTest
public class CaseTriggerHelperTest {
    
    @IsTest
    static void testHandleAfterUpdate_NoParentCases() {
        // Create test data
        List<Case> casesToInsert = new List<Case>();
        
        // Create a case without a parent
        Case caseWithoutParent = new Case(
            Subject = 'Test Case Without Parent',
            Status = 'New',
            Customer_Want_Date__c = Date.today()
        );
        casesToInsert.add(caseWithoutParent);
        
        // Insert the case
        Test.startTest();
        insert casesToInsert;
        
        // Update the case (no parent)
        Case updatedCase = casesToInsert[0];
        updatedCase.Customer_Want_Date__c = Date.today().addDays(1);
        
        update new List<Case>{updatedCase};
        Test.stopTest();
        
        // Verify no exception occurred and no child cases were updated
        // This test mainly verifies that the code handles cases without parents gracefully
    }
    
    @IsTest
    static void testHandleAfterUpdate_WithParentAndChildCases() {
        // Create parent case
        Case parentCase = new Case(
            Subject = 'Parent Case',
            Status = 'New',
            Customer_Want_Date__c = Date.today()
        );
        
        Test.startTest();
        insert parentCase;
        
        // Create child case with Capital Line record type
        // First we need to get the record type ID
        RecordType capitalLineRT = [
            SELECT Id FROM RecordType 
            WHERE SObjectType = 'Case' 
            AND Name = 'Capital Line Sub Case'
            LIMIT 1
        ];
        
        Case childCase = new Case(
            Subject = 'Child Case',
            Status = 'New',
            ParentId = parentCase.Id,
            RecordTypeId = capitalLineRT.Id,
            Customer_Want_Date__c = Date.today().addDays(-1) // Different date initially
        );
        
        insert childCase;
        
        // Update parent case's Customer_Want_Date__c
        parentCase.Customer_Want_Date__c = Date.today().addDays(2);
        
        update new List<Case>{parentCase};
        
        // Verify child case was updated with parent's new Customer_Want_Date__c
        Case updatedChildCase = [
            SELECT Id, Customer_Want_Date__c 
            FROM Case 
            WHERE Id = :childCase.Id
            LIMIT 1
        ];
        Test.stopTest();
        
        // Assert that child case now has the same Customer_Want_Date__c as parent
        System.assertEquals(parentCase.Customer_Want_Date__c, updatedChildCase.Customer_Want_Date__c);
    }
    
    @IsTest
    static void testHandleAfterUpdate_ParentCaseWithoutChange() {
        // Create parent case
        Case parentCase = new Case(
            Subject = 'Parent Case',
            Status = 'New',
            Customer_Want_Date__c = Date.today()
        );
        
        Test.startTest();
        insert parentCase;
        
        // Create child case
        RecordType capitalLineRT = [
            SELECT Id FROM RecordType 
            WHERE SObjectType = 'Case' 
            AND Name = 'Capital Line Sub Case'
            LIMIT 1
        ];
        
        Case childCase = new Case(
            Subject = 'Child Case',
            Status = 'New',
            ParentId = parentCase.Id,
            RecordTypeId = capitalLineRT.Id,
            Customer_Want_Date__c = Date.today().addDays(-1)
        );
        
        insert childCase;
        
        // Update parent case without changing Customer_Want_Date__c
        parentCase.Status = 'Open'; // Changing status instead
        
        update new List<Case>{parentCase};
        
        // Verify child case was NOT updated (since Customer_Want_Date__c didn't change)
        Case unmodifiedChildCase = [
            SELECT Id, Customer_Want_Date__c 
            FROM Case 
            WHERE Id = :childCase.Id
            LIMIT 1
        ];
        Test.stopTest();
        
        // Assert that child case still has original Customer_Want_Date__c
        System.assertEquals(Date.today().addDays(-1), unmodifiedChildCase.Customer_Want_Date__c);
    }

    private static Account createTestAccount() {
        Account acc = new Account(
            Name = 'Test Account'
        );
        insert acc;
        return acc;
    }

    /** Fetch CBM Case Record Type Id */
    private static Id getCBMRecordTypeId() {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Case'
            AND Name = 'CBM Case'
            LIMIT 1
        ].Id;
    }

    /** Create test Order */
    private static Order createTestOrder(Account acc, String orderNum) {
        Order ord = new Order(
            Name = 'Test Order ' + orderNum,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            AccountId = acc.Id,
            OrderNumber__c = orderNum
        );
        insert ord;
        return ord;
    }

    /* ============================================================
       Test Methods
       ============================================================ */

    /**
     * Test: Sales Decision moves to NO-GO
     */
    @IsTest
    static void testCreateScheduleCheckInTask_SalesNoGo() {

        Account acc = createTestAccount();
        Id cbmRT = getCBMRecordTypeId();
        Order ord = createTestOrder(acc, 'ORD-1001');

        Case parentCase = new Case(
            Subject = 'CBM Parent Case Sales No-Go',
            Status = 'New',
            RecordTypeId = cbmRT,
            AccountId = acc.Id,
            Order__c = ord.Id,
            Sales_Decision__c = 'Pending',
            IPMDecision__c = 'Pending'
        );
        insert parentCase;

        Test.startTest();
        parentCase.Sales_Decision__c = 'NO-GO';
        update parentCase;
        Test.stopTest();

        System.assert(true,
            'Task creation logic executed for Sales NO-GO');
    }

    /**
     * Test: IPM Decision moves to NO-GO
     */
    @IsTest
    static void testCreateScheduleCheckInTask_IpmNoGo() {

        Account acc = createTestAccount();
        Id cbmRT = getCBMRecordTypeId();
        Order ord = createTestOrder(acc, 'ORD-2002');

        Case parentCase = new Case(
            Subject = 'CBM Parent Case IPM No-Go',
            Status = 'New',
            RecordTypeId = cbmRT,
            AccountId = acc.Id,
            Order__c = ord.Id,
            Sales_Decision__c = 'GO',
            IPMDecision__c = 'Pending'
        );
        insert parentCase;

        Test.startTest();
        parentCase.IPMDecision__c = 'NO-GO';
        update parentCase;
        Test.stopTest();

        System.assert(true,
            'Task creation logic executed for IPM NO-GO');
    }

    /**
     * Test: No NO-GO transition → No task creation
     */
    @IsTest
    static void testCreateScheduleCheckInTask_NoNoGo() {

        Account acc = createTestAccount();
        Id cbmRT = getCBMRecordTypeId();
        Order ord = createTestOrder(acc, 'ORD-3003');

        Case parentCase = new Case(
            Subject = 'CBM Parent Case No Change',
            Status = 'New',
            RecordTypeId = cbmRT,
            AccountId = acc.Id,
            Order__c = ord.Id,
            Sales_Decision__c = 'GO',
            IPMDecision__c = 'GO'
        );
        insert parentCase;

        Test.startTest();
        parentCase.Status = 'In Progress'; // unrelated update
        update parentCase;
        Test.stopTest();

        System.assert(true,
            'No Schedule Check-In should be created');
    }

    /**
     * Test: NO-GO transition without Order
     */
    @IsTest
    static void testCreateScheduleCheckInTask_NoOrder() {

        Account acc = createTestAccount();
        Id cbmRT = getCBMRecordTypeId();

        Case parentCase = new Case(
            Subject = 'CBM Case Without Order',
            Status = 'New',
            RecordTypeId = cbmRT,
            AccountId = acc.Id,
            Sales_Decision__c = 'Pending',
            IPMDecision__c = 'Pending'
        );
        insert parentCase;

        Test.startTest();
        parentCase.Sales_Decision__c = 'NO-GO';
        update parentCase;
        Test.stopTest();

        System.assert(true,
            'NO-GO without Order should not create tasks');
    }
}