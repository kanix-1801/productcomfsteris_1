/**
 * @date 2026/07/28
 *
 * @group Account Management
 *
 * @description
 * Data access layer for DynamicPageAccessRule__mdt custom metadata (GC-3183).
 * Returns the access rule configured for a page and object combination.
 *
 * @see DynamicPageAccessResolver
 * @see DynamicPageAccessRule__mdt
 * GC-3183
 */
public with sharing class DynamicPageAccessRuleSelector {

    /**
     * @description
     * Test-only mock access rule returned by getAccessRule.
     */
    @TestVisible
    private static DynamicPageAccessRule__mdt mockRule;

    /**
     * @description
     * Retrieves the access rule for the provided page and object API names.
     *
     * @param pageName PageName__c value on DynamicPageElement and access rule metadata.
     * @param objectApiName SObject API name for the record page context.
     * @return Matching access rule metadata record, or null when none is configured.
     */
    public static DynamicPageAccessRule__mdt getAccessRule(String pageName, String objectApiName) {
        if (Test.isRunningTest() && mockRule != null) {
            return mockRule;
        }

        List<DynamicPageAccessRule__mdt> rules = [
            SELECT
                PageName__c,
                ObjectAPIName__c,
                AccessStrategy__c,
                BaseAccessValue__c,
                FullAccessValue__c,
                StrategyParameter__c
            FROM DynamicPageAccessRule__mdt
            WHERE PageName__c = :pageName
              AND ObjectAPIName__c = :objectApiName
            LIMIT 1
        ];

        return rules.isEmpty() ? null : rules[0];
    }
}