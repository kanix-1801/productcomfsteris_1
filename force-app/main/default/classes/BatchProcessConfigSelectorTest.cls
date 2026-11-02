/**
 * @author Suraj Thapliyal
 * @date 2026/08/11
 *
 * @group Batch Process Config
 *
 * @description
 * Tests for BatchProcessConfigSelector CMDT lookup and per-transaction cache.
 */
@IsTest(SeeAllData=false)
private class BatchProcessConfigSelectorTest {

    private static final String INACTIVE_LEGACY_BATCH = 'OrderLineContactTeamAccessBatch';
    private static final String UNKNOWN_BATCH = 'NonExistentBatchClass';

    /**
     * @description
     * Clears the selector cache before each test method.
     *
     * @return void
     */
    private static void resetCache() {
        BatchProcessConfigSelector.testOnly_resetCache();
    }

    /**
     * @description
     * Verifies public batch class name constants match expected Apex class names.
     *
     * @return void
     */
    @IsTest
    static void testConstants() {
        Test.startTest();
        System.assertEquals(
            'TASTeamAccessBatch',
            BatchProcessConfigSelector.OLC_TEAM_ACCESS_BATCH_CLASS_NAME,
            'TAS batch constant should match Apex class name'
        );
        System.assertEquals(
            'LS_TASTeamAccessBatch',
            BatchProcessConfigSelector.LS_TEAM_ACCESS_BATCH_CLASS_NAME,
            'LS TAS batch constant should match Apex class name'
        );
        System.assertEquals(
            'SampleFollowUpNotificationBatch',
            BatchProcessConfigSelector.SAMPLE_FOLLOW_UP_BATCH_CLASS_NAME,
            'Sample Follow-up batch constant should match Apex class name'
        );
        Test.stopTest();
    }

    /**
     * @description
     * Verifies null, empty, and whitespace batch class names return null.
     *
     * @return void
     */
    @IsTest
    static void testBlankInput() {
        resetCache();

        Test.startTest();
        System.assertEquals(
            null,
            BatchProcessConfigSelector.selectActiveByBatchClassName(null),
            'Null batch class name should return null'
        );
        System.assertEquals(
            null,
            BatchProcessConfigSelector.selectActiveByBatchClassName(''),
            'Empty batch class name should return null'
        );
        System.assertEquals(
            null,
            BatchProcessConfigSelector.selectActiveByBatchClassName('   '),
            'Whitespace batch class name should return null'
        );
        Test.stopTest();
    }

    /**
     * @description
     * Verifies active TASTeamAccessBatch CMDT row is returned with expected fields.
     *
     * @return void
     */
    @IsTest
    static void testTasConfig() {
        resetCache();

        BatchProcessConfig__mdt expected;
        BatchProcessConfig__mdt actual;

        Test.startTest();
        expected = [
            SELECT BatchClassName__c, BatchSize__c, IsActive__c
            FROM BatchProcessConfig__mdt
            WHERE BatchClassName__c = :BatchProcessConfigSelector.OLC_TEAM_ACCESS_BATCH_CLASS_NAME
              AND IsActive__c = TRUE
            LIMIT 1
        ];
        actual = BatchProcessConfigSelector.selectActiveByBatchClassName(
            BatchProcessConfigSelector.OLC_TEAM_ACCESS_BATCH_CLASS_NAME
        );
        Test.stopTest();

        System.assertNotEquals(null, actual, 'Expected active TAS batch config');
        System.assertEquals(
            expected.BatchClassName__c,
            actual.BatchClassName__c,
            'TAS BatchClassName__c should match CMDT'
        );
        System.assertEquals(
            expected.BatchSize__c,
            actual.BatchSize__c,
            'TAS BatchSize__c should match CMDT'
        );
        System.assert(actual.IsActive__c, 'TAS config should be active');
    }

    /**
     * @description
     * Verifies inactive and unknown batch class names return null.
     *
     * @return void
     */
    @IsTest
    static void testInactiveConfig() {
        resetCache();

        Test.startTest();
        System.assertEquals(
            null,
            BatchProcessConfigSelector.selectActiveByBatchClassName(INACTIVE_LEGACY_BATCH),
            'Inactive legacy batch config should return null'
        );
        System.assertEquals(
            null,
            BatchProcessConfigSelector.selectActiveByBatchClassName(UNKNOWN_BATCH),
            'Unknown batch class name should return null'
        );
        Test.stopTest();
    }

    /**
     * @description
     * Verifies repeated lookup for the same batch class returns the cached config row.
     *
     * @return void
     */
    @IsTest
    static void testCacheHit() {
        resetCache();

        BatchProcessConfig__mdt firstLookup;
        BatchProcessConfig__mdt secondLookup;

        Test.startTest();
        firstLookup = BatchProcessConfigSelector.selectActiveByBatchClassName(
            BatchProcessConfigSelector.OLC_TEAM_ACCESS_BATCH_CLASS_NAME
        );
        secondLookup = BatchProcessConfigSelector.selectActiveByBatchClassName(
            BatchProcessConfigSelector.OLC_TEAM_ACCESS_BATCH_CLASS_NAME
        );
        Test.stopTest();

        System.assertNotEquals(null, firstLookup, 'First lookup should return TAS config');
        System.assertEquals(
            firstLookup,
            secondLookup,
            'Second lookup should return cached config'
        );
    }

    /**
     * @description
     * Verifies cache reset allows a fresh lookup after switching batch class names.
     *
     * @return void
     */
    @IsTest
    static void testResetCache() {
        resetCache();

        BatchProcessConfig__mdt tasConfig;
        BatchProcessConfig__mdt inactiveConfig;
        BatchProcessConfig__mdt tasAfterReset;

        Test.startTest();
        tasConfig = BatchProcessConfigSelector.selectActiveByBatchClassName(
            BatchProcessConfigSelector.OLC_TEAM_ACCESS_BATCH_CLASS_NAME
        );
        inactiveConfig = BatchProcessConfigSelector.selectActiveByBatchClassName(INACTIVE_LEGACY_BATCH);
        resetCache();
        tasAfterReset = BatchProcessConfigSelector.selectActiveByBatchClassName(
            BatchProcessConfigSelector.OLC_TEAM_ACCESS_BATCH_CLASS_NAME
        );
        Test.stopTest();

        System.assertNotEquals(null, tasConfig, 'TAS config should load before reset');
        System.assertEquals(null, inactiveConfig, 'Inactive legacy batch config should return null');
        System.assertNotEquals(null, tasAfterReset, 'TAS config should reload after reset');
        System.assertEquals(
            tasConfig.BatchClassName__c,
            tasAfterReset.BatchClassName__c,
            'Reloaded TAS BatchClassName__c should match original'
        );
        System.assertEquals(
            tasConfig.BatchSize__c,
            tasAfterReset.BatchSize__c,
            'Reloaded TAS BatchSize__c should match original'
        );
    }
}