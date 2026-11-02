/**
 * @author PSL
 * @date 11-18-2025
 * @description Test class for CreateSubCaseScheduleBatch batch class
 */
@IsTest
private class CreateSubCaseScheduleBatchTest {
/*
    @IsTest
    static void testExecuteSchedulesBatch() {
        Test.startTest();
        new CreateSubCaseScheduleBatch().execute(null);
        Test.stopTest();

        Integer jobCount = [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex'];
        System.assertEquals(2, jobCount, 'Batch job should be scheduled');
    }*/
    @IsTest
    static void testExecuteSchedulesBatch() {
        Test.startTest();
        new CreateSubCaseScheduleBatch().execute(null);
        Test.stopTest();

        Integer jobCount = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'CreateSubCaseBatch'
        ];

        System.assertEquals(
            1, jobCount,
            'CreateSubCaseBatch should be queued exactly once.'
        );
    }


    @IsTest
    static void testGetScopeOverride() {
        Integer scope = CreateSubCaseScheduleBatch.getScopeFromCmdt(150);
        System.assertEquals(150, scope);
    }

    @IsTest
    static void testGetScopeDefault() {
        Integer scope = CreateSubCaseScheduleBatch.getScopeFromCmdt(null);
        System.assertEquals(20, scope);
    }
}