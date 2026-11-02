/**
 * @author PSL
 * @date 11-18-2025
 * @description Scheduled class to execute CreateSubCaseBatch
 */
public with sharing class CreateSubCaseScheduleBatch implements Schedulable {

    /**
     * @description Schedulable interface method
     * @param sc Schedulable context
     */
    public void execute(SchedulableContext sc) {
        Integer scope = getScopeFromCmdt(null);
        Database.executeBatch(new CreateSubCaseBatch(), scope);
    }

    /**
     * Retrieves batch size from Custom Metadata, with fallback logic
     * @param overrideScope Optional override for batch size
     * @return Batch size to use for execution
     */
    @TestVisible
    private static Integer getScopeFromCmdt(Integer overrideScope) {
        if (overrideScope != null && overrideScope > 0) {
            return overrideScope;
        }

        // Default scope if CMDT missing or invalid
        Integer defaultScope = 200;

        try {
            // Query the CMDT record for CreateSubCaseBatch
            // Field name: Size__c (from metadata file)
            CBMBatchSetting__mdt setting =
                [SELECT DeveloperName, MasterLabel, Size__c
                 FROM CBMBatchSetting__mdt
                 WHERE DeveloperName = 'CreateSubCaseBatch'
                 LIMIT 1];

            if (setting != null && setting.Size__c != null && setting.Size__c > 0) {
                return Integer.valueOf(setting.Size__c);
            }
        } catch (Exception e) {
            // Log warning and fall back to default
            System.debug(LoggingLevel.WARN, 'CreateSubCaseSchedule: Failed to read batch size from CMDT: ' + e.getMessage());
        }

        return defaultScope;
    }
}