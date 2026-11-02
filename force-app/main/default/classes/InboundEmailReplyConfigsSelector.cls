/**
 * @description GW-5102 - Selector for InboundEmailReplyConfig__mdt keyword records.
 */
public with sharing class InboundEmailReplyConfigsSelector {
    public static final String REPAIR_CENTER_QUOTE = 'RepairCenterQuote';

    @TestVisible
    private static InboundEmailReplyConfig__mdt configOverride;

    /**
     * @description Loads the Repair Center Quote inbound reply keyword config.
     * @return Matching Custom Metadata row, or null
     */
    public static InboundEmailReplyConfig__mdt selectRepairCenterQuote() {
        if (Test.isRunningTest() && configOverride != null) {
            return configOverride;
        }

        List<InboundEmailReplyConfig__mdt> rows = [
            SELECT
                DeveloperName,
                MasterLabel,
                ApproveKeywordList__c,
                RejectKeywordList__c,
                ApproveKeywords__c,
                RejectKeywords__c
            FROM InboundEmailReplyConfig__mdt
            WHERE DeveloperName = :REPAIR_CENTER_QUOTE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }
}