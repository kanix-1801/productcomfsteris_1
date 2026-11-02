/**
 * @date 2026/07/28
 *
 * @group Account Management
 *
 * @description
 * Unit tests for DynamicPageAccessResolver and DynamicPageAccessRuleSelector.
 * GC-3183
 */
@IsTest(SeeAllData=false)
private class DynamicPageAccessResolverTest {

    /**
     * @description
     * Resets test mocks before each test method runs.
     */
    private static void resetMocks() {
        DynamicPageAccessResolver.mockAccessLevel = null;
        DynamicPageAccessResolver.mockIsAccountTeamMember = null;
        DynamicPageAccessRuleSelector.mockRule = null;
    }

    /**
     * @description
     * Builds an in-memory access rule metadata record for testing.
     *
     * @param strategy AccessStrategy__c value.
     * @param strategyParameter Optional StrategyParameter__c value.
     * @return Mock access rule metadata record.
     */
    private static DynamicPageAccessRule__mdt buildRule(
        String strategy,
        String strategyParameter
    ) {
        DynamicPageAccessRule__mdt rule = new DynamicPageAccessRule__mdt();
        rule.PageName__c = 'Customer360';
        rule.ObjectAPIName__c = 'Account';
        rule.AccessStrategy__c = strategy;
        rule.BaseAccessValue__c = 'Base';
        rule.FullAccessValue__c = 'Full';
        rule.StrategyParameter__c = strategyParameter;
        return rule;
    }

    /**
     * @description
     * Verifies that Account Team members receive Full access for the AccountTeamMember strategy.
     */
    @IsTest
    static void testAccountTeamMemberStrategyReturnsFullAccess() {
        resetMocks();
        Account testAccount = new Account(
            Name = 'Access Rule Test Account',
            SourceSystemID__c = 'TEST-ACCESS-RULE-001'
        );
        insert testAccount;

        DynamicPageAccessRuleSelector.mockRule = buildRule(
            DynamicPageAccessResolver.STRATEGY_ACCOUNT_TEAM_MEMBER,
            null
        );
        DynamicPageAccessResolver.mockIsAccountTeamMember = true;

        Test.startTest();
        String accessLevel = DynamicPageAccessResolver.resolveAccessLevel(
            testAccount.Id,
            'Account',
            'Customer360'
        );
        Test.stopTest();

        System.assertEquals('Full', accessLevel);
    }

    /**
     * @description
     * Verifies that non-team members receive Base access for the AccountTeamMember strategy.
     */
    @IsTest
    static void testAccountTeamMemberStrategyReturnsBaseAccess() {
        resetMocks();
        Account testAccount = new Account(
            Name = 'Access Rule Test Account Base',
            SourceSystemID__c = 'TEST-ACCESS-RULE-002'
        );
        insert testAccount;

        DynamicPageAccessRuleSelector.mockRule = buildRule(
            DynamicPageAccessResolver.STRATEGY_ACCOUNT_TEAM_MEMBER,
            null
        );
        DynamicPageAccessResolver.mockIsAccountTeamMember = false;

        Test.startTest();
        String accessLevel = DynamicPageAccessResolver.resolveAccessLevel(
            testAccount.Id,
            'Account',
            'Customer360'
        );
        Test.stopTest();

        System.assertEquals('Base', accessLevel);
    }

    /**
     * @description
     * Verifies that AlwaysFull returns the configured Full access value.
     */
    @IsTest
    static void testAlwaysFullStrategy() {
        resetMocks();
        DynamicPageAccessRuleSelector.mockRule = buildRule(
            DynamicPageAccessResolver.STRATEGY_ALWAYS_FULL,
            null
        );

        Test.startTest();
        String accessLevel = DynamicPageAccessResolver.resolveAccessLevel(
            null,
            'Account',
            'Customer360'
        );
        Test.stopTest();

        System.assertEquals('Full', accessLevel);
    }

    /**
     * @description
     * Verifies that AlwaysBase returns the configured Base access value.
     */
    @IsTest
    static void testAlwaysBaseStrategy() {
        resetMocks();
        DynamicPageAccessRuleSelector.mockRule = buildRule(
            DynamicPageAccessResolver.STRATEGY_ALWAYS_BASE,
            null
        );

        Test.startTest();
        String accessLevel = DynamicPageAccessResolver.resolveAccessLevel(
            null,
            'Account',
            'Customer360'
        );
        Test.stopTest();

        System.assertEquals('Base', accessLevel);
    }

    /**
     * @description
     * Verifies that missing access rules default to Base access.
     */
    @IsTest
    static void testMissingRuleDefaultsToBase() {
        resetMocks();

        Test.startTest();
        String accessLevel = DynamicPageAccessResolver.resolveAccessLevel(
            null,
            'Account',
            'UnknownPage'
        );
        Test.stopTest();

        System.assertEquals('Base', accessLevel);
    }

    /**
     * @description
     * Verifies that AccountTeamMember strategy returns Base for non-Account objects.
     */
    @IsTest
    static void testAccountTeamMemberStrategyRequiresAccountObject() {
        resetMocks();
        Account testAccount = new Account(
            Name = 'Access Rule Test Account Object',
            SourceSystemID__c = 'TEST-ACCESS-RULE-003'
        );
        insert testAccount;

        DynamicPageAccessRuleSelector.mockRule = buildRule(
            DynamicPageAccessResolver.STRATEGY_ACCOUNT_TEAM_MEMBER,
            null
        );
        DynamicPageAccessResolver.mockIsAccountTeamMember = true;

        Test.startTest();
        String accessLevel = DynamicPageAccessResolver.resolveAccessLevel(
            testAccount.Id,
            'Contact',
            'Customer360'
        );
        Test.stopTest();

        System.assertEquals('Base', accessLevel);
    }

    /**
     * @description
     * Verifies CustomPermission strategy returns Base when StrategyParameter__c is blank.
     */
    @IsTest
    static void testCustomPermissionStrategyWithoutParameterReturnsBase() {
        resetMocks();
        DynamicPageAccessRuleSelector.mockRule = buildRule(
            DynamicPageAccessResolver.STRATEGY_CUSTOM_PERMISSION,
            null
        );

        Test.startTest();
        String accessLevel = DynamicPageAccessResolver.resolveAccessLevel(
            null,
            'Account',
            'Customer360'
        );
        Test.stopTest();

        System.assertEquals('Base', accessLevel);
    }

    /**
     * @description
     * Verifies CustomPermission strategy returns Base when permission is not assigned.
     */
    @IsTest
    static void testCustomPermissionStrategyWithUnknownPermissionReturnsBase() {
        resetMocks();
        DynamicPageAccessRuleSelector.mockRule = buildRule(
            DynamicPageAccessResolver.STRATEGY_CUSTOM_PERMISSION,
            'DynamicPageElement_FakePermission'
        );

        Test.startTest();
        String accessLevel = DynamicPageAccessResolver.resolveAccessLevel(
            null,
            'Account',
            'Customer360'
        );
        Test.stopTest();

        System.assertEquals('Base', accessLevel);
    }

    /**
     * @description
     * Verifies an unknown strategy value defaults to Base access.
     */
    @IsTest
    static void testUnknownStrategyReturnsBase() {
        resetMocks();
        DynamicPageAccessRule__mdt rule = buildRule('UnsupportedStrategy', null);
        DynamicPageAccessRuleSelector.mockRule = rule;

        Test.startTest();
        String accessLevel = DynamicPageAccessResolver.resolveAccessLevel(
            null,
            'Account',
            'Customer360'
        );
        Test.stopTest();

        System.assertEquals('Base', accessLevel);
    }

    /**
     * @description
     * Verifies custom Base and Full access labels from metadata are returned.
     */
    @IsTest
    static void testCustomAccessValueLabelsAreReturned() {
        resetMocks();
        DynamicPageAccessRule__mdt rule = buildRule(
            DynamicPageAccessResolver.STRATEGY_ALWAYS_FULL,
            null
        );
        rule.BaseAccessValue__c = 'Limited';
        rule.FullAccessValue__c = 'Expanded';
        DynamicPageAccessRuleSelector.mockRule = rule;

        Test.startTest();
        String accessLevel = DynamicPageAccessResolver.resolveAccessLevel(
            null,
            'Account',
            'Customer360'
        );
        Test.stopTest();

        System.assertEquals('Expanded', accessLevel);
    }

    /**
     * @description
     * Verifies evaluateStrategy returns false for unsupported strategy names.
     */
    @IsTest
    static void testEvaluateStrategyUnknownStrategyReturnsFalse() {
        resetMocks();

        Test.startTest();
        Boolean qualifies = DynamicPageAccessResolver.evaluateStrategy(
            'UnsupportedStrategy',
            null,
            null,
            'Account'
        );
        Test.stopTest();

        System.assertEquals(false, qualifies);
    }

    /**
     * @description
     * Verifies deployed access rule metadata can be queried without mocks.
     */
    @IsTest
    static void testGetAccessRuleReturnsDeployedMetadata() {
        resetMocks();

        Test.startTest();
        DynamicPageAccessRule__mdt rule =
            DynamicPageAccessRuleSelector.getAccessRule('Customer360', 'Account');
        Test.stopTest();

        System.assertNotEquals(null, rule);
        System.assertEquals('AccountTeamMember', rule.AccessStrategy__c);
    }

    /**
     * @description
     * Verifies unknown page/object combinations return null from the selector.
     */
    @IsTest
    static void testGetAccessRuleReturnsNullForUnknownPage() {
        resetMocks();

        Test.startTest();
        DynamicPageAccessRule__mdt rule =
            DynamicPageAccessRuleSelector.getAccessRule('UnknownPage', 'Account');
        Test.stopTest();

        System.assertEquals(null, rule);
    }

    /**
     * @description
     * Verifies Account Team membership is resolved through live SOQL when no test mock is set.
     */
    @IsTest
    static void testAccountTeamMemberLiveQueryWithoutMock() {
        resetMocks();

        Account testAccount = new Account(
            Name = 'Access Rule Live Team Account',
            SourceSystemID__c = 'TEST-ACCESS-RULE-LIVE-001'
        );
        insert testAccount;

        insert new AccountTeamMember(
            AccountId = testAccount.Id,
            UserId = UserInfo.getUserId(),
            TeamMemberRole = getActiveTeamMemberRole(),
            AccountAccessLevel = 'Edit',
            OpportunityAccessLevel = 'Read',
            CaseAccessLevel = 'Read'
        );

        DynamicPageAccessRuleSelector.mockRule = buildRule(
            DynamicPageAccessResolver.STRATEGY_ACCOUNT_TEAM_MEMBER,
            null
        );

        Test.startTest();
        String accessLevel = DynamicPageAccessResolver.resolveAccessLevel(
            testAccount.Id,
            'Account',
            'Customer360'
        );
        Test.stopTest();

        System.assertEquals('Full', accessLevel);
    }

    /**
     * @description
     * Verifies blank Base and Full access labels fall back to defaults from metadata rule.
     */
    @IsTest
    static void testBlankAccessValueLabelsUseDefaults() {
        resetMocks();
        DynamicPageAccessRule__mdt rule = buildRule(
            DynamicPageAccessResolver.STRATEGY_ALWAYS_BASE,
            null
        );
        rule.BaseAccessValue__c = '';
        rule.FullAccessValue__c = '';
        DynamicPageAccessRuleSelector.mockRule = rule;

        Test.startTest();
        String accessLevel = DynamicPageAccessResolver.resolveAccessLevel(
            null,
            'Account',
            'Customer360'
        );
        Test.stopTest();

        System.assertEquals('Base', accessLevel);
    }

    /**
     * @description
     * Returns the first active Account Team Member role from the org picklist.
     */
    private static String getActiveTeamMemberRole() {
        for (Schema.PicklistEntry entry : AccountTeamMember.TeamMemberRole.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return 'Account Manager';
    }
}