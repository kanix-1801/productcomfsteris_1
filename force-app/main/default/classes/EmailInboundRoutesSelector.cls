/**
 * @description GW-5102 - Selector for EmailInboundRoute__mdt subject-key routing.
 */
public with sharing class EmailInboundRoutesSelector {
    public static final String REPAIR_CENTER_QUOTE = 'RepairCenterQuote';

    @TestVisible
    private static EmailInboundRoute__mdt routeOverride;

    /**
     * @description Loads the active Repair Center Quote inbound route.
     * @return Matching Custom Metadata row, or null
     */
    public static EmailInboundRoute__mdt selectRepairCenterQuote() {
        if (Test.isRunningTest() && routeOverride != null) {
            return routeOverride;
        }

        List<EmailInboundRoute__mdt> rows = [
            SELECT
                DeveloperName,
                RecordKeyRegex__c,
                SubjectContains__c,
                IsActive__c
            FROM EmailInboundRoute__mdt
            WHERE DeveloperName = :REPAIR_CENTER_QUOTE
                AND IsActive__c = true
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }
}