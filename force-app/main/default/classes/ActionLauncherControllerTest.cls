/**
 * @author PWC Developer
 * @date 2026/08/28
 *
 * @group Action Launcher
 *
 * @description
 * GC-3346 - Unit tests for ActionLauncherController, ActionLauncherService,
 * ActionLauncherSelector, and ActionLauncherException.
 */
@IsTest(SeeAllData=false)
private class ActionLauncherControllerTest {

    private static final String ACCOUNT_OBJECT = 'Account';
    private static final String CREATE_LOST_BUSINESS = 'Account.CreateLostBusinessOpportunity';
    private static final String SAMPLE_DELIVERY_TASK = 'Account.Sample_Delivery_Task';

    /**
     * @description
     * GC-3346 - Creates an Account used to resolve custom button merge fields.
     *
     * @return Test Account.
     */
    private static Account createAccount() {
        Account account = new Account(
            Name = 'Action Launcher Test Account',
            SourceSystemID__c = 'GC3346' + String.valueOf(DateTime.now().getTime())
        );
        insert account;
        return account;
    }

    /**
     * @description
     * GC-3346 - Verifies configured action order and required UI metadata.
     *
     * @return void
     */
    @IsTest
    static void testGetActionsReturnsConfiguredOrder() {
        Account account = createAccount();

        Test.startTest();
        List<ActionLauncherController.LauncherAction> actions =
            ActionLauncherController.getActions(
                account.Id,
                ACCOUNT_OBJECT,
                SAMPLE_DELIVERY_TASK + ',' + CREATE_LOST_BUSINESS
            );
        Test.stopTest();

        System.assertNotEquals(null, actions, 'Controller should always return a list.');

        // Describe results depend on org metadata, so only assert ordering when
        // both actions resolved.
        if (actions.size() == 2) {
            System.assertEquals(
                SAMPLE_DELIVERY_TASK,
                actions[0].apiName,
                'Configured order should be preserved.'
            );
            System.assertEquals(
                CREATE_LOST_BUSINESS,
                actions[1].apiName,
                'Configured order should be preserved.'
            );
        }

        for (ActionLauncherController.LauncherAction action : actions) {
            System.assert(
                String.isNotBlank(action.label),
                'Every returned action needs a label to render on the pill.'
            );
            System.assert(
                String.isNotBlank(action.actionType),
                'Every returned action needs a type so the LWC knows how to launch it.'
            );
        }
    }

    /**
     * @description
     * GC-3346 - Verifies URL custom buttons resolve merge fields.
     *
     * @return void
     */
    @IsTest
    static void testGetActionsResolvesUrlCustomButtonMergeFields() {
        Account account = createAccount();

        List<WebLink> buttons = ActionLauncherSelector.selectUrlWebLinks(
            ACCOUNT_OBJECT,
            new Set<String>{ 'CreateOpportunity' }
        );

        if (buttons.isEmpty()) {
            return;
        }

        String buttonName = ACCOUNT_OBJECT + '.' + buttons[0].Name;

        Test.startTest();
        List<ActionLauncherController.LauncherAction> actions =
            ActionLauncherController.getActions(account.Id, ACCOUNT_OBJECT, buttonName);
        Test.stopTest();

        System.assertEquals(1, actions.size(), 'The custom button should resolve as an action.');

        ActionLauncherController.LauncherAction action = actions[0];
        System.assertEquals('WebLink', action.actionType, 'Custom buttons resolve as WebLink.');
        System.assert(String.isNotBlank(action.url), 'Custom buttons must expose a URL to navigate to.');
        System.assert(
            !action.url.contains('{!'),
            'Every merge field token should be resolved or removed: ' + action.url
        );
    }

    /**
     * @description
     * GC-3346 - Verifies bare action names are qualified with the host object.
     *
     * @return void
     */
    @IsTest
    static void testGetActionsQualifiesBareNames() {
        Account account = createAccount();

        Test.startTest();
        List<ActionLauncherController.LauncherAction> actions =
            ActionLauncherController.getActions(
                account.Id,
                ACCOUNT_OBJECT,
                ' CreateLostBusinessOpportunity '
            );
        Test.stopTest();

        for (ActionLauncherController.LauncherAction action : actions) {
            System.assertEquals(
                CREATE_LOST_BUSINESS,
                action.apiName,
                'Bare names should be prefixed with the host object API name.'
            );
        }
    }

    /**
     * @description
     * GC-3346 - Verifies repeated action names are de-duplicated.
     *
     * @return void
     */
    @IsTest
    static void testGetActionsDeduplicatesNames() {
        Account account = createAccount();

        Test.startTest();
        List<ActionLauncherController.LauncherAction> actions =
            ActionLauncherController.getActions(
                account.Id,
                ACCOUNT_OBJECT,
                CREATE_LOST_BUSINESS + ',' + CREATE_LOST_BUSINESS
            );
        Test.stopTest();

        System.assert(actions.size() <= 1, 'Duplicate action names should collapse to one entry.');
    }

    /**
     * @description
     * GC-3346 - Verifies unknown action names do not prevent valid actions from loading.
     *
     * @return void
     */
    @IsTest
    static void testGetActionsSkipsUnknownNames() {
        Account account = createAccount();

        Test.startTest();
        List<ActionLauncherController.LauncherAction> actions =
            ActionLauncherController.getActions(
                account.Id,
                ACCOUNT_OBJECT,
                'Account.ThisActionDoesNotExist_XYZ,' + CREATE_LOST_BUSINESS
            );
        Test.stopTest();

        for (ActionLauncherController.LauncherAction action : actions) {
            System.assertNotEquals(
                'Account.ThisActionDoesNotExist_XYZ',
                action.apiName,
                'Unresolvable actions should be dropped, not returned.'
            );
        }
    }

    /**
     * @description
     * GC-3346 - Verifies blank action configuration returns an empty list.
     *
     * @return void
     */
    @IsTest
    static void testGetActionsReturnsEmptyListForBlankConfiguration() {
        Account account = createAccount();

        Test.startTest();
        List<ActionLauncherController.LauncherAction> blankConfig =
            ActionLauncherController.getActions(account.Id, ACCOUNT_OBJECT, '   ');
        List<ActionLauncherController.LauncherAction> nullConfig =
            ActionLauncherController.getActions(account.Id, ACCOUNT_OBJECT, null);
        Test.stopTest();

        System.assertEquals(0, blankConfig.size(), 'Blank configuration should yield no actions.');
        System.assertEquals(0, nullConfig.size(), 'Null configuration should yield no actions.');
    }

    /**
     * @description
     * GC-3346 - Verifies bare names are ignored when the host object is missing.
     *
     * @return void
     */
    @IsTest
    static void testGetActionsIgnoresBareNamesWithoutObject() {
        Account account = createAccount();

        Test.startTest();
        List<ActionLauncherController.LauncherAction> actions =
            ActionLauncherController.getActions(account.Id, null, 'CreateLostBusinessOpportunity');
        Test.stopTest();

        System.assertEquals(
            0,
            actions.size(),
            'Bare names cannot be resolved without a host object API name.'
        );
    }

    /**
     * @description
     * GC-3346 - Verifies quick action metadata can load without a record id.
     *
     * @return void
     */
    @IsTest
    static void testGetActionsToleratesMissingRecordId() {
        Test.startTest();
        List<ActionLauncherController.LauncherAction> actions =
            ActionLauncherController.getActions(null, ACCOUNT_OBJECT, CREATE_LOST_BUSINESS);
        Test.stopTest();

        System.assertNotEquals(
            null,
            actions,
            'A missing record id should not break quick action resolution.'
        );
    }

    /**
     * @description
     * GC-3346 - Verifies service failures are converted to AuraHandledException by the controller.
     *
     * @return void
     */
    @IsTest
    static void testGetActionsExceptionPath() {
        Boolean exceptionThrown = false;

        try {
            ActionLauncherService.forcedExceptionMethodName = 'getActions';

            Test.startTest();
            try {
                ActionLauncherController.getActions(
                    null,
                    ACCOUNT_OBJECT,
                    CREATE_LOST_BUSINESS
                );
            } catch (AuraHandledException exceptionValue) {
                exceptionThrown = true;
            }
            Test.stopTest();
        } finally {
            ActionLauncherService.forcedExceptionMethodName = null;
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'Controller should surface service failures as AuraHandledException.'
        );
    }

    /**
     * @description
     * GC-3346 - Verifies selector guards return empty results for invalid inputs.
     *
     * @return void
     */
    @IsTest
    static void testSelectorEmptyInputGuards() {
        System.assertEquals(
            0,
            ActionLauncherSelector.selectUrlWebLinks(null, new Set<String>()).size(),
            'Blank selector input should return an empty list.'
        );
        System.assertEquals(
            null,
            ActionLauncherSelector.selectRecordById(null, ACCOUNT_OBJECT, new Set<String>{ 'Id' }),
            'Missing record id should return no source record.'
        );
    }

    /**
     * @description
     * GC-3346 - Verifies the feature-specific exception preserves its message.
     *
     * @return void
     */
    @IsTest
    static void testExceptionTypeMessageAndThrow() {
        String expectedMessage = 'Action Launcher failure';
        Boolean exceptionThrown = false;

        try {
            throwActionLauncherException(expectedMessage);
        } catch (ActionLauncherException exceptionValue) {
            exceptionThrown = true;
            System.assertEquals(expectedMessage, exceptionValue.getMessage());
        }

        System.assert(exceptionThrown, 'ActionLauncherException should be throwable.');
    }

    private static void throwActionLauncherException(String expectedMessage) {
        throw new ActionLauncherException(expectedMessage);
    }
}