/**
 * @author Suraj Thapliyal
 * @date 2026/08/14
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-3333 - Tests for TAEAssignedRecordService paginated UI queries.
 */
@IsTest(SeeAllData=false)
private class TAEAssignedRecordServiceTest {

    /**
     * @description Creates base TAE test data via the shared factory.
     *
     * @return void
     */
    @TestSetup
    static void setupData() {
        TestDataFactory.setupBaseScenario();
    }

    /**
     * @description Verifies null TAE Id returns an empty page result.
     *
     * @return void
     */
    @IsTest
    static void testNullTaeIdReturnsEmptyPage() {
        Test.startTest();
        TAEAssignedRecordService.AssignedRecordsPageResult result =
            TAEAssignedRecordService.getAssignedRecordsForUi(
                null,
                TAEAssignedRecordService.RECORD_TYPE_ACCOUNT,
                null,
                1,
                10,
                TAEAssignedRecordService.SORT_DIRECTION_ASC
            );
        Test.stopTest();

        System.assertEquals(0, result.totalRecords, 'Null TAE Id should return zero total records');
        System.assertEquals(0, result.records.size(), 'Null TAE Id should return no rows');
    }

    /**
     * @description Verifies invalid record type raises an AuraHandledException.
     *
     * @return void
     */
    @IsTest
    static void testInvalidRecordTypeThrows() {
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            TestDataFactory.getRequester().Id,
            TestDataFactory.getCoverageRep().Id
        );

        Boolean threw = false;
        Test.startTest();
        try {
            TAEAssignedRecordService.getAssignedRecordsForUi(
                tae.Id,
                'Invalid',
                null,
                1,
                10,
                TAEAssignedRecordService.SORT_DIRECTION_ASC
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Invalid record type should throw AuraHandledException');
    }

    /**
     * @description Verifies account assignments are returned with pagination metadata.
     *
     * @return void
     */
    @IsTest
    static void testGetAssignedAccountsReturnsPagedRows() {
        TestDataFactory.ScenarioContext ctx = TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );

        insert new TAE_AssignedRecord__c(
            TemporaryAccessException__c = tae.Id,
            Account__c = ctx.accountId
        );

        Test.startTest();
        TAEAssignedRecordService.AssignedRecordsPageResult result =
            TAEAssignedRecordService.getAssignedRecordsForUi(
                tae.Id,
                TAEAssignedRecordService.RECORD_TYPE_ACCOUNT,
                null,
                1,
                10,
                TAEAssignedRecordService.SORT_DIRECTION_ASC
            );
        Test.stopTest();

        System.assertEquals(1, result.totalRecords, 'Expected one assigned account row');
        System.assertEquals(1, result.records.size(), 'Expected one account DTO');
        System.assertEquals(ctx.accountId, result.records[0].id, 'Expected assigned Account Id in DTO');
        System.assertNotEquals(null, result.records[0].assignedRecordId, 'Expected junction row Id');
    }

    /**
     * @description Verifies account name search filters assigned rows server-side.
     *
     * @return void
     */
    @IsTest
    static void testAccountNameSearchFiltersResults() {
        TestDataFactory.ScenarioContext ctx = TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );
        Account testAccount = [SELECT Id, Name FROM Account WHERE Id = :ctx.accountId LIMIT 1];

        insert new TAE_AssignedRecord__c(
            TemporaryAccessException__c = tae.Id,
            Account__c = ctx.accountId
        );

        String matchingTerm = testAccount.Name.left(3);

        Test.startTest();
        TAEAssignedRecordService.AssignedRecordsPageResult matchingResult =
            TAEAssignedRecordService.getAssignedRecordsForUi(
                tae.Id,
                TAEAssignedRecordService.RECORD_TYPE_ACCOUNT,
                matchingTerm,
                1,
                10,
                TAEAssignedRecordService.SORT_DIRECTION_ASC
            );
        TAEAssignedRecordService.AssignedRecordsPageResult nonMatchingResult =
            TAEAssignedRecordService.getAssignedRecordsForUi(
                tae.Id,
                TAEAssignedRecordService.RECORD_TYPE_ACCOUNT,
                'zzzz-no-match-zzzz',
                1,
                10,
                TAEAssignedRecordService.SORT_DIRECTION_ASC
            );
        Test.stopTest();

        System.assertEquals(1, matchingResult.totalRecords, 'Matching search should return one row');
        System.assertEquals(0, nonMatchingResult.totalRecords, 'Non-matching search should return zero rows');
    }

    /**
     * @description Verifies helper normalization methods.
     *
     * @return void
     */
    @IsTest
    static void testNormalizationHelpers() {
        System.assertEquals(
            TAEAssignedRecordService.RECORD_TYPE_ACCOUNT,
            TAEAssignedRecordService.normalizeRecordType('account')
        );
        System.assertEquals(null, TAEAssignedRecordService.normalizeRecordType('Bad'));
        System.assertEquals(25, TAEAssignedRecordService.normalizePageSize(null));
        System.assertEquals(100, TAEAssignedRecordService.normalizePageSize(500));
        System.assertEquals(2, TAEAssignedRecordService.computeTotalPages(11, 10));
        System.assertEquals(
            TAEAssignedRecordService.SORT_DIRECTION_DESC,
            TAEAssignedRecordService.normalizeSortDirection('desc')
        );
    }
}