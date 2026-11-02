/**
 * @date 2026/07/28
 *
 * @group Account Management
 *
 * @description
 * Resolves the effective DynamicPageElement access level for a record page using
 * DynamicPageAccessRule__mdt configuration. Supports Account Team membership,
 * static Base/Full access, and custom permission strategies.
 *
 * @see DynamicPageAccessRuleSelector
 * @see DynamicPageElementService
 * GC-3183
 */
public with sharing class DynamicPageAccessResolver {

    /** @description Default access level returned when no rule is configured. */
    public static final String DEFAULT_BASE_ACCESS = 'Base';

    /** @description Default access level returned when Full criteria are met. */
    public static final String DEFAULT_FULL_ACCESS = 'Full';

    /** @description Strategy that grants Full access to Account Team members. */
    public static final String STRATEGY_ACCOUNT_TEAM_MEMBER = 'AccountTeamMember';

    /** @description Strategy that always returns the configured Base access value. */
    public static final String STRATEGY_ALWAYS_BASE = 'AlwaysBase';

    /** @description Strategy that always returns the configured Full access value. */
    public static final String STRATEGY_ALWAYS_FULL = 'AlwaysFull';

    /** @description Strategy that checks a custom permission from StrategyParameter__c. */
    public static final String STRATEGY_CUSTOM_PERMISSION = 'CustomPermission';

    /**
     * @description
     * Test-only override that bypasses rule lookup and strategy evaluation.
     */
    @TestVisible
    private static String mockAccessLevel;

    /**
     * @description
     * Test-only override for AccountTeamMember strategy evaluation.
     */
    @TestVisible
    private static Boolean mockIsAccountTeamMember;

    /**
     * @description
     * Resolves the access level value used to filter DynamicPageElement metadata.
     *
     * @param recordId Record Id from the Lightning page context.
     * @param objectApiName SObject API name for the record page.
     * @param pageName PageName__c value for the metadata-driven page.
     * @return Access level string such as Base or Full.
     */
    public static String resolveAccessLevel(Id recordId, String objectApiName, String pageName) {
        if (Test.isRunningTest() && mockAccessLevel != null) {
            return mockAccessLevel;
        }

        DynamicPageAccessRule__mdt rule =
            DynamicPageAccessRuleSelector.getAccessRule(pageName, objectApiName);

        String baseAccessValue = DEFAULT_BASE_ACCESS;
        String fullAccessValue = DEFAULT_FULL_ACCESS;
        String strategy = STRATEGY_ALWAYS_BASE;

        if (rule != null) {
            baseAccessValue = String.isNotBlank(rule.BaseAccessValue__c)
                ? rule.BaseAccessValue__c
                : DEFAULT_BASE_ACCESS;
            fullAccessValue = String.isNotBlank(rule.FullAccessValue__c)
                ? rule.FullAccessValue__c
                : DEFAULT_FULL_ACCESS;
            strategy = rule.AccessStrategy__c;
        }

        Boolean hasFullAccess = evaluateStrategy(strategy, rule, recordId, objectApiName);
        return hasFullAccess ? fullAccessValue : baseAccessValue;
    }

    /**
     * @description
     * Evaluates whether the current user qualifies for Full access for the configured strategy.
     *
     * @param strategy AccessStrategy__c value from metadata.
     * @param rule Access rule metadata record, may be null when no rule exists.
     * @param recordId Record Id from the Lightning page context.
     * @param objectApiName SObject API name for the record page.
     * @return TRUE when Full access criteria are met; otherwise FALSE.
     */
    @TestVisible
    private static Boolean evaluateStrategy(
        String strategy,
        DynamicPageAccessRule__mdt rule,
        Id recordId,
        String objectApiName
    ) {
        if (strategy == STRATEGY_ALWAYS_FULL) {
            return true;
        }

        if (strategy == STRATEGY_ALWAYS_BASE) {
            return false;
        }

        if (strategy == STRATEGY_ACCOUNT_TEAM_MEMBER) {
            return isCurrentUserAccountTeamMember(recordId, objectApiName);
        }

        if (strategy == STRATEGY_CUSTOM_PERMISSION) {
            return hasConfiguredCustomPermission(rule);
        }

        return false;
    }

    /**
     * @description
     * Determines whether the current user is an Account Team member for the supplied Account.
     *
     * @param recordId Account record Id.
     * @param objectApiName SObject API name for the record page.
     * @return TRUE when the user is on the Account Team; otherwise FALSE.
     */
    @TestVisible
    private static Boolean isCurrentUserAccountTeamMember(Id recordId, String objectApiName) {
        if (recordId == null || objectApiName != 'Account') {
            return false;
        }

        if (Test.isRunningTest() && mockIsAccountTeamMember != null) {
            return mockIsAccountTeamMember;
        }

        return ![
            SELECT Id
            FROM AccountTeamMember
            WHERE AccountId = :recordId
              AND UserId = :UserInfo.getUserId()
            LIMIT 1
        ].isEmpty();
    }

    /**
     * @description
     * Checks whether the current user has the custom permission configured on the access rule.
     *
     * @param rule Access rule metadata record.
     * @return TRUE when the configured custom permission is assigned; otherwise FALSE.
     */
    @TestVisible
    private static Boolean hasConfiguredCustomPermission(DynamicPageAccessRule__mdt rule) {
        if (rule == null || String.isBlank(rule.StrategyParameter__c)) {
            return false;
        }

        return FeatureManagement.checkPermission(rule.StrategyParameter__c);
    }
}