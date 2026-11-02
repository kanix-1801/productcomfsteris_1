/**
 * @author Suraj Thapliyal
 * @date 2026/07/27
 * @description GC-3179 - SOQL-only selector for BatchProcessConfig__mdt resolution.
 *              GC-3278 - TASTeamAccessBatch config lookup (formerly OrderLineContactTeamAccessBatch).
 */
public with sharing class BatchProcessConfigSelector {

    /** GC-3179 - BatchClassName__c for TASTeamAccessBatch config lookup. */
    public static final String OLC_TEAM_ACCESS_BATCH_CLASS_NAME = 'TASTeamAccessBatch';
    /** GCL-1 - BatchClassName__c for LS_TASTeamAccessBatch config lookup. */
    public static final String LS_TEAM_ACCESS_BATCH_CLASS_NAME = 'LS_TASTeamAccessBatch';
    /** GC-3226 - BatchClassName__c for SampleFollowUpNotificationBatch config lookup. */
    public static final String SAMPLE_FOLLOW_UP_BATCH_CLASS_NAME = 'SampleFollowUpNotificationBatch';

    private static String loadedBatchClassName;
    private static Boolean isConfigLoaded = false;
    private static BatchProcessConfig__mdt loadedConfig;

    private BatchProcessConfigSelector() {
    }

    /**
     * @description Returns the active BatchProcessConfig__mdt row for a batch class (cached per transaction).
     * @param batchClassName Apex batch class name (BatchClassName__c).
     * @return Active config row, or null when none exists.
     */
    public static BatchProcessConfig__mdt selectActiveByBatchClassName(String batchClassName) {
        if (String.isBlank(batchClassName)) {
            return null;
        }
        if (isConfigLoaded && loadedBatchClassName == batchClassName) {
            return loadedConfig;
        }

        List<BatchProcessConfig__mdt> configs = [
            SELECT BatchClassName__c, BatchSize__c, EmailChunkSize__c, IsActive__c
            FROM BatchProcessConfig__mdt
            WHERE BatchClassName__c = :batchClassName
              AND IsActive__c = TRUE
            LIMIT 1
        ];

        loadedBatchClassName = batchClassName;
        loadedConfig = configs.isEmpty() ? null : configs[0];
        isConfigLoaded = true;
        return loadedConfig;
    }

    /**
     * @description Clears the per-transaction config cache (test use only).
     */
    @TestVisible
    static void testOnly_resetCache() {
        loadedBatchClassName = null;
        loadedConfig = null;
        isConfigLoaded = false;
    }
}