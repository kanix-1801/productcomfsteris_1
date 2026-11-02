/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Tests for AsyncApexJobsSelector.
 * @group Platform
 * @see AsyncApexJobsSelector
 */
@IsTest
private class AsyncApexJobsSelectorTest {
    /**
     * @description The query runs and finds no active batch job when none was started.
     */
    @IsTest
    static void testQueryReturnsNoRowsForUnknownIds() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: no batch job has been started

            // WHEN
            Test.startTest();
            List<AsyncApexJob> rows = AsyncApexJobsSelector.selectActiveBatchJobsByClassName(
                'ServiceAppointmentRealignmentBatch'
            );
            Test.stopTest();

            // THEN
            Assert.isTrue(rows.isEmpty(), 'No rows expected');
        }
    }

    /**
     * @description Missing inputs return an empty list without querying.
     */
    @IsTest
    static void testBlankInputsReturnEmptyList() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: null, empty or blank inputs

            // WHEN
            Test.startTest();
            List<AsyncApexJob> blank1 = AsyncApexJobsSelector.selectActiveBatchJobsByClassName(null);
            List<AsyncApexJob> blank2 = AsyncApexJobsSelector.selectActiveBatchJobsByClassName(' ');
            Test.stopTest();

            // THEN
            Assert.isTrue(blank1.isEmpty(), 'Missing input should return no rows');
            Assert.isTrue(blank2.isEmpty(), 'Missing input should return no rows');
        }
    }
}