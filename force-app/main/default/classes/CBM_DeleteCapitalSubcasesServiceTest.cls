/**
* @author PSL
* @date 19-03-2026
* @description Test class for CBM_DeleteCapitalSubcasesService class
*/

@IsTest
public class CBM_DeleteCapitalSubcasesServiceTest {
    
    /* --------------------------------------------------------
* Test Data Setup
* -------------------------------------------------------- */
    @TestSetup
    static void setupData() {
        
        /* Create Account (MANDATORY) */
        Account acc = new Account(
            Name = 'Test Account'
        );
        insert acc;
        
        /*  Get Record Type */
        RecordType capitalSubcaseRT = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Case'
            AND DeveloperName = 'Capital_Line_Sub_Case'
            LIMIT 1
        ];
        
        /*  Create Parent Case with Account */
        Case parentCase = new Case(
            Subject = 'Parent Case',
            Status = 'New',
            AccountId = acc.Id
        );
        insert parentCase;
        
        /*Create Order with Account (REQUIRED BY SFDC) */
        Order orderRec = new Order(
            Name = 'Test Order',
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today()
        );
        insert orderRec;
        
        /* Link Order to Parent Case */
        parentCase.Order__c = orderRec.Id;
        update parentCase;
        
        /* Create Capital Subcases WITH Account */
        List<Case> subcases = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            subcases.add(new Case(
                ParentId = parentCase.Id,
                RecordTypeId = capitalSubcaseRT.Id,
                Subject = 'Capital Subcase ' + i,
                Status = 'New',
                AccountId = acc.Id
            ));
        }
        insert subcases;
        
        /* Create Tasks */
        List<Task> tasks = new List<Task>();
        
        tasks.add(new Task(
            Subject = 'Parent Case Task',
            WhatId = parentCase.Id,
            Status = 'Not Started'
        ));
        
        tasks.add(new Task(
            Subject = 'Order Task',
            WhatId = orderRec.Id,
            Status = 'Not Started'
        ));
        
        for (Case c : subcases) {
            tasks.add(new Task(
                Subject = 'Subcase Task',
                WhatId = c.Id,
                Status = 'Not Started'
            ));
        }
        
        insert tasks;
    }
    /* --------------------------------------------------------
* Test: getCapitalSubcaseRows
* -------------------------------------------------------- */
    @IsTest
    static void testGetCapitalSubcaseRows() {
        
        Case parentCase = [
            SELECT Id
            FROM Case
            WHERE ParentId = NULL
            LIMIT 1
        ];
        
        Test.startTest();
        List<CBM_DeleteCapitalSubcasesService.SubcaseRow> rows =
            CBM_DeleteCapitalSubcasesService.getCapitalSubcaseRows(parentCase.Id);
        Test.stopTest();
        
        System.assertEquals(3, rows.size(),
                            'Should return all Capital Line Subcases');
        
        for (CBM_DeleteCapitalSubcasesService.SubcaseRow row : rows) {
            System.assertNotEquals(null, row.id);
            System.assertNotEquals(null, row.caseNumber);
            System.assertNotEquals(null, row.createdDate);
            System.assertNotEquals(null, row.recordUrl);
            System.assert(row.taskCount >= 1,
                          'Each subcase should have at least one task');
        }
    }
    
    /* --------------------------------------------------------
* Test: getCapitalSubcaseRows with NULL input
* -------------------------------------------------------- */
    @IsTest
    static void testGetCapitalSubcaseRows_NullParent() {
        Test.startTest();
        List<CBM_DeleteCapitalSubcasesService.SubcaseRow> rows =
            CBM_DeleteCapitalSubcasesService.getCapitalSubcaseRows(null);
        Test.stopTest();
        
        System.assertEquals(0, rows.size(),
                            'Null Parent Case Id should return empty list');
    }
    
    /* --------------------------------------------------------
* Test: deleteAllCapitalSubcases (Happy Path)
* -------------------------------------------------------- */
    @IsTest
    static void testDeleteAllCapitalSubcases() {
        
        Case parentCase = [
            SELECT Id, isCapitalSubCaseDeleted__c
            FROM Case
            WHERE ParentId = NULL
            LIMIT 1
        ];
        
        Test.startTest();
        String result =
            CBM_DeleteCapitalSubcasesService.deleteAllCapitalSubcases(
                parentCase.Id,
                'Test cleanup'
            );
        Test.stopTest();
        
        System.assert(result.contains('Deleted'),
                      'Return message should confirm deletion');
        
        // Verify Subcases deleted
        Integer subcaseCount = [
            SELECT COUNT()
            FROM Case
            WHERE ParentId = :parentCase.Id
        ];
        System.assertEquals(0, subcaseCount,
                            'All Capital Line Subcases should be deleted');
        
        // Verify Tasks deleted
        Integer taskCount = [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :parentCase.Id
        ];
        System.assertEquals(0, taskCount,
                            'Related Tasks should be deleted');
        
        // Verify Parent Case updated
        parentCase = [
            SELECT isCapitalSubCaseDeleted__c
            FROM Case
            WHERE Id = :parentCase.Id
        ];
        System.assertEquals(true, parentCase.isCapitalSubCaseDeleted__c,
                            'Parent case flag should be updated');
    }
    
    /* --------------------------------------------------------
* Test: deleteAllCapitalSubcases when no subcases exist
* -------------------------------------------------------- */
    @IsTest
    static void testDeleteAllCapitalSubcases_NoSubcases() {
        
        Case newParent = new Case(
            Subject = 'No Subcases Parent',
            Status = 'New'
        );
        insert newParent;
        
        Test.startTest();
        String result =
            CBM_DeleteCapitalSubcasesService.deleteAllCapitalSubcases(
                newParent.Id,
                'Nothing to delete'
            );
        Test.stopTest();
        
        System.assertEquals(
            'No Capital Line Subcases found to delete.',
            result
        );
    }
    
}