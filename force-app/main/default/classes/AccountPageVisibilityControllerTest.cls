/**
 * @author Vinay
 * @date 2026/06/05
 *
 * @group Account Management
 *
 * @description
 * Test class for AccountPageVisibilityController, AccountPageVisibilityService,
 * and AccountPageVisibilitySelector. Validates Full and Base access levels,
 * input validation, and Account Team Member selector behavior.
 */
@IsTest(SeeAllData=false)
private class AccountPageVisibilityControllerTest {

    /**
     * @description
     * Creates test Account data shared across all test methods.
     */
    @TestSetup
    static void setupData() {
        Account testAccount = new Account(Name = 'Test Account', SourceSystemID__c = 'TEST-ORACLE-001');
        insert testAccount;
    }

    /**
     * @description
     * Returns the current running user for System.runAs context in tests.
     *
     * @return User record representing the current test context user.
     */
    private static User getContextUser() {
        return new User(Id = UserInfo.getUserId());
    }

    /**
     * @description
     * Retrieves the test Account created during TestSetup.
     *
     * @return Account record used as test input.
     */
    private static Account getTestAccount() {
        return [
            SELECT Id
            FROM Account
            WHERE Name = 'Test Account'
            LIMIT 1
        ];
    }

    /**
     * @description
     * Builds mock Account Page Visibility custom metadata records for testing.
     *
     * @param accessLevel Access level value to assign to the mock config (e.g. Full or Base).
     * @return List containing a single mock visibility configuration record.
     */
    private static List<Account_Page_Visibility_Config__mdt> buildMockConfigs(String accessLevel) {
        Account_Page_Visibility_Config__mdt config = new Account_Page_Visibility_Config__mdt();
        config.Access_Level__c = accessLevel;
        config.PageName__c = 'Account_Record_Page';
        config.Element_Type__c = 'Tab';
        config.TabAPIName__c = 'Details';
        config.ComponentAPIName__c = 'AccountDetails';
        config.IsVisible__c = true;
        config.DisplayOrder__c = 1;

        return new List<Account_Page_Visibility_Config__mdt>{ config };
    }

    /**
     * @description
     * Resets selector mock variables to null before each test execution.
     */
    private static void resetMocks() {
        AccountPageVisibilitySelector.mockIsTeamMember = null;
        AccountPageVisibilitySelector.mockConfigs = null;
    }

    /**
     * @description
     * Verifies that Full access level and visibility configs are returned
     * when the current user is an Account Team Member.
     */
    @IsTest
    static void testGetVisibilityConfigFullAccess() {
        /********************************************
        * SETUP
        ********************************************/
        resetMocks();
        User contextUser = getContextUser();
        Account testAccount = getTestAccount();

        AccountPageVisibilitySelector.mockIsTeamMember = true;
        AccountPageVisibilitySelector.mockConfigs = buildMockConfigs('Full');

        /********************************************
        * WHEN
        ********************************************/
        AccountPageVisibilityService.VisibilityResponse response;

        Test.startTest();
        System.runAs(contextUser) {
            response = AccountPageVisibilityController.getVisibilityConfig(
                testAccount.Id,
                'Account_Record_Page'
            );
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals('Full', response.accessLevel);
        System.assertEquals(1, response.configs.size());
        System.assertEquals('Tab', response.configs[0].elementType);
        System.assertEquals('Details', response.configs[0].tabApiName);
        System.assertEquals('AccountDetails', response.configs[0].componentApiName);
        System.assertEquals(true, response.configs[0].isVisible);
        System.assertEquals(1, response.configs[0].displayOrder);
    }

    /**
     * @description
     * Verifies that Base access level and visibility configs are returned
     * when the current user is not an Account Team Member.
     */
    @IsTest
    static void testGetVisibilityConfigBaseAccess() {
        /********************************************
        * SETUP
        ********************************************/
        resetMocks();
        User contextUser = getContextUser();
        Account testAccount = getTestAccount();

        AccountPageVisibilitySelector.mockIsTeamMember = false;
        AccountPageVisibilitySelector.mockConfigs = buildMockConfigs('Base');

        /********************************************
        * WHEN
        ********************************************/
        AccountPageVisibilityService.VisibilityResponse response;

        Test.startTest();
        System.runAs(contextUser) {
            response = AccountPageVisibilityController.getVisibilityConfig(
                testAccount.Id,
                'Account_Record_Page'
            );
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals('Base', response.accessLevel);
        System.assertEquals(1, response.configs.size());
        System.assertEquals('Tab', response.configs[0].elementType);
    }

    /**
     * @description
     * Verifies that an AuraHandledException is thrown when Account Id is null.
     */
    @IsTest
    static void testMissingAccountIdThrowsError() {
        resetMocks();
        User contextUser = getContextUser();

        Boolean threw = false;

        Test.startTest();
        System.runAs(contextUser) {
            try {
                AccountPageVisibilityController.getVisibilityConfig(
                    null,
                    'Account_Record_Page'
                );
            } catch (AuraHandledException ex) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assert(threw, 'Expected AuraHandledException for missing Account Id.');
    }

    /**
     * @description
     * Verifies that an AuraHandledException is thrown when page name is blank.
     */
    @IsTest
    static void testBlankPageNameThrowsError() {
        resetMocks();
        User contextUser = getContextUser();
        Account testAccount = getTestAccount();

        Boolean threw = false;

        Test.startTest();
        System.runAs(contextUser) {
            try {
                AccountPageVisibilityController.getVisibilityConfig(
                    testAccount.Id,
                    ''
                );
            } catch (AuraHandledException ex) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assert(threw, 'Expected AuraHandledException for blank page name.');
    }

    /**
     * @description
     * Verifies that isCurrentUserAccountTeamMember returns true when
     * the current user is inserted as an Account Team Member.
     */
    @IsTest
    static void testSelectorCurrentUserIsAccountTeamMember() {
        /********************************************
        * SETUP
        ********************************************/
        resetMocks();
        User contextUser = getContextUser();
        Account testAccount = getTestAccount();

        insert new AccountTeamMember(
            AccountId = testAccount.Id,
            UserId = UserInfo.getUserId(),
            TeamMemberRole = 'Sales Rep',
            AccountAccessLevel = 'Edit',
            OpportunityAccessLevel = 'Read',
            CaseAccessLevel = 'None'
        );

        /********************************************
        * WHEN
        ********************************************/
        Boolean result;

        Test.startTest();
        System.runAs(contextUser) {
            result = AccountPageVisibilitySelector.isCurrentUserAccountTeamMember(
                testAccount.Id
            );
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(true, result);
    }

    /**
     * @description
     * Verifies that isCurrentUserAccountTeamMember returns false when
     * the current user is not an Account Team Member for the Account.
     */
    @IsTest
    static void testSelectorCurrentUserIsNotAccountTeamMember() {
        /********************************************
        * SETUP
        ********************************************/
        resetMocks();
        User contextUser = getContextUser();
        Account testAccount = getTestAccount();

        /********************************************
        * WHEN
        ********************************************/
        Boolean result;

        Test.startTest();
        System.runAs(contextUser) {
            result = AccountPageVisibilitySelector.isCurrentUserAccountTeamMember(
                testAccount.Id
            );
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(false, result);
    }
}