/**
 * @description GW-5102 - Selector for EmailInboundRoute__mdt routing records.
 */
public with sharing class EmailInboundRouteSelector {
    @TestVisible
    private static List<EmailInboundRoute__mdt> routeOverride;

    /**
     * @description Returns active inbound email routes ordered by Priority then DeveloperName.
     * @return Active EmailInboundRoute__mdt rows
     */
    public static List<EmailInboundRoute__mdt> selectActiveRoutes() {
        if (Test.isRunningTest() && routeOverride != null) {
            return routeOverride;
        }

        return [
            SELECT
                Id,
                MasterLabel,
                DeveloperName,
                IsActive__c,
                ProcessorClassName__c,
                SubjectContains__c,
                ToAddressContains__c,
                RecordKeyRegex__c,
                TargetObjectApiName__c,
                Priority__c
            FROM EmailInboundRoute__mdt
            WHERE IsActive__c = TRUE
            ORDER BY Priority__c ASC NULLS LAST, DeveloperName ASC
        ];
    }
}