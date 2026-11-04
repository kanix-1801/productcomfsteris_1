/**
 * @author PWC Developer
 * @date 2026/06/15
 *
 * @group Temporary Access Exception
 *
 * @description
 * Tests for Temporary Access Exception batch, service, selector, email, and exception classes.
 * Covers grant/revoke team access, batch error handling, flex-queue guard, schedulable entry point,
 * notifications, and TemporaryAccessException__c validation rules TER_002 and TER_003
 * (TER_001 is inactive, so End Date of today is allowed).
 * GC-3352 - Grant ATM insert copies TerritoryCode__c, SalesCategoryCode__c, and
 * SalesCategoryDescription__c from the requester AccountTeamMember.
 */
@IsTest(SeeAllData=false)
private class TemporaryAccessExceptionTest {

    private static final Integer BULK_ROW_COUNT = 25;
    private static final String VR_MSG_JUSTIFICATION_REQUIRED =
        'Business Justification is required when Exception Category is Other.';
    private static final String VR_MSG_START_DATE_NOT_PAST =
        'Start Date cannot be in the past. Please select today or a future date.';

    /**
     * @description
     * Creates users, account, opportunity, and requester team memberships via the test data factory.
     * Requester is assigned SalesFieldRepAccountManager and System_Administrator permission sets directly.
     *
     * @return void
     */
    @TestSetup
    static void setupData() {
        TestDataFactory.setupBaseScenario();
    }

    /**
     * @description
     * GC-3179 - Modified: clears testBatchSizeOverride for BatchProcessConfig__mdt batch-size tests.
     * Resets batch and email test hooks between test methods.
     *
     * @return void
     */
    private static void resetBatchFlags() {
        TemporaryAccessExceptionBatch.throwInStart = false;
        TemporaryAccessExceptionBatch.throwInExecute = false;
        TemporaryAccessExceptionBatch.throwInFinish = false;
        TemporaryAccessExceptionBatch.startCatchCount = 0;
        TemporaryAccessExceptionBatch.executeCatchCount = 0;
        TemporaryAccessExceptionBatch.finishCatchCount = 0;
        TemporaryAccessExceptionBatch.skipFlexQueueCheckForTest = false;
        TemporaryAccessExceptionBatch.testFlexQueueHoldingCountOverride = null;
        TemporaryAccessExceptionBatch.testBatchSizeOverride = null;
        resetEmailFlags();
        resetServiceTestFlags();
    }

    /**
     * @description
     * Clears service-layer test hooks between test methods.
     *
     * @return void
     */
    private static void resetServiceTestFlags() {
        TemporaryAccessExceptionService.testOnlyForceCommonReadSecurityFailure = false;
        TemporaryAccessExceptionService.testOnlyForceGrantSecurityFailure = false;
        TemporaryAccessExceptionService.testOnlyForceRevokeSecurityFailure = false;
    }

    /**
     * @description
     * Clears email-service test hooks between test methods.
     *
     * @return void
     */
    private static void resetEmailFlags() {
        TemporaryAccessExceptionEmailService.skipSendForTest = false;
        TemporaryAccessExceptionEmailService.testOnly_simulateSendFailure = false;
        TemporaryAccessExceptionEmailService.testOnly_emailChunkSizeOverride = null;
        BatchProcessConfigSelector.testOnly_resetCache();
    }

    /**
     * @description
     * Counts TemporaryAccessException__c rows eligible for nightly batch processing.
     *
     * @return Number of rows the batch start() locator would return
     */
    private static Integer countEligibleTaeRows() {
        Date today = Date.today();
        return [
            SELECT COUNT()
            FROM TemporaryAccessException__c
            WHERE Requester__c != null
              AND CoverageRep__c != null
              AND (
                  (Status__c = :TemporaryAccessExceptionSelector.STATUS_APPROVED AND StartDate__c = :today)
                  OR (Status__c = :TemporaryAccessExceptionSelector.STATUS_ACTIVE AND EndDate__c = :today)
              )
        ];
    }

    /**
     * @description
     * Sets test batch scope to eligible row count so only one execute runs in @IsTest.
     *
     * @return Scope size passed to Database.executeBatch (minimum 1)
     */
    private static Integer resolveTestBatchScope() {
        return Math.max(1, countEligibleTaeRows());
    }

    /**
     * @description
     * Running user for System.runAs — the requester created in @TestSetup.
     *
     * @return Active requester User
     */
    private static User getRunAsUser() {
        return TestDataFactory.getRequester();
    }

    private static TemporaryAccessExceptionSelector.RevokeTeamMemberCriteria buildRevokeTeamMemberCriteria(
        Set<Id> recordIds,
        Set<Id> coverageRepIds
    ) {
        TemporaryAccessExceptionSelector.RevokeTeamMemberCriteria criteria =
            new TemporaryAccessExceptionSelector.RevokeTeamMemberCriteria();
        criteria.recordIds = recordIds;
        criteria.coverageRepIds = coverageRepIds;
        criteria.teamMemberRole = TemporaryAccessExceptionService.TEAM_MEMBER_ROLE_SALES;
        criteria.assignmentType = TemporaryAccessExceptionService.ASSIGNMENT_TYPE_TEMPORARY_ASSIGNMENT;
        return criteria;
    }

    /**
     * @description Ensures TER validation rules are active in test context when org/user bypass flags are set.
     */
    private static void enableTemporaryAccessValidationRulesForTest(Id userId) {
        try {
            Automation_Setting_Global__c globalSettings = Automation_Setting_Global__c.getOrgDefaults();
            if (globalSettings == null || globalSettings.Id == null) {
                globalSettings = new Automation_Setting_Global__c(
                    SetupOwnerId = UserInfo.getOrganizationId()
                );
            }
            globalSettings.disableAll__c = false;
            upsert globalSettings;

            Automation_Setting_Validation_Rule__c orgSettings =
                Automation_Setting_Validation_Rule__c.getOrgDefaults();
            if (orgSettings == null || orgSettings.Id == null) {
                orgSettings = new Automation_Setting_Validation_Rule__c(
                    SetupOwnerId = UserInfo.getOrganizationId()
                );
            }
            orgSettings.disableAll__c = false;
            orgSettings.EndDateMustBeAFutureDate__c = false;
            orgSettings.StartDateCannotBeInPast__c = false;
            orgSettings.JustificationRequired__c = false;
            upsert orgSettings;

            if (userId != null) {
                Automation_Setting_Validation_Rule__c userSettings =
                    Automation_Setting_Validation_Rule__c.getInstance(userId);
                if (userSettings == null || userSettings.Id == null) {
                    userSettings = new Automation_Setting_Validation_Rule__c(SetupOwnerId = userId);
                }
                userSettings.disableAll__c = false;
                userSettings.EndDateMustBeAFutureDate__c = false;
                userSettings.StartDateCannotBeInPast__c = false;
                userSettings.JustificationRequired__c = false;
                upsert userSettings;
            }
        } catch (Exception e) {
            // Hierarchy custom settings optional in some orgs
        }
    }

    /**
     * @description
     * Runs the temporary access exception batch synchronously in test context.
     *
     * @return AsyncApexJob Id for the batch run
     */
    private static Id runBatch() {
        return Database.executeBatch(
            new TemporaryAccessExceptionBatch(),
            resolveTestBatchScope()
        );
    }

    private static Integer countTemporaryAssignmentAtm(Id accountId, Id userId) {
        return [
            SELECT COUNT()
            FROM AccountTeamMember
            WHERE AccountId = :accountId
              AND UserId = :userId
              AND TeamMemberRole = :TemporaryAccessExceptionService.TEAM_MEMBER_ROLE_SALES
              AND AssignmentType__c = :TemporaryAccessExceptionService.ASSIGNMENT_TYPE_TEMPORARY_ASSIGNMENT
        ];
    }

    private static Integer countTemporaryAssignmentOtm(Id opportunityId, Id userId) {
        if (opportunityId == null) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM OpportunityTeamMember
            WHERE OpportunityId = :opportunityId
              AND UserId = :userId
              AND TeamMemberRole = :TemporaryAccessExceptionService.TEAM_MEMBER_ROLE_SALES
              AND AssignmentType__c = :TemporaryAccessExceptionService.ASSIGNMENT_TYPE_TEMPORARY_ASSIGNMENT
        ];
    }

    private static void assertOtmCountIfPresent(
        TestDataFactory.ScenarioContext ctx,
        Id userId,
        Integer expected,
        String message
    ) {
        if (ctx.hasOpportunity == true && ctx.opportunityId != null) {
            System.assertEquals(expected, countTemporaryAssignmentOtm(ctx.opportunityId, userId), message);
        }
    }

    private static Integer countAssignedRecordsForTae(Id taeId) {
        return [
            SELECT COUNT()
            FROM TAE_AssignedRecord__c
            WHERE TemporaryAccessException__c = :taeId
        ];
    }

    private static void assertAssignedRecordShape(Id taeId) {
        TemporaryAccessException__c tae = [
            SELECT Requester__c
            FROM TemporaryAccessException__c
            WHERE Id = :taeId
            LIMIT 1
        ];

        Set<Id> expectedAccountIds = new Set<Id>();
        for (AccountTeamMember atm : [
            SELECT AccountId
            FROM AccountTeamMember
            WHERE UserId = :tae.Requester__c
        ]) {
            expectedAccountIds.add(atm.AccountId);
        }
        for (Account acc : [
            SELECT Id
            FROM Account
            WHERE OwnerId = :tae.Requester__c
        ]) {
            expectedAccountIds.add(acc.Id);
        }

        Set<Id> expectedOpportunityIds = new Set<Id>();
        for (OpportunityTeamMember otm : [
            SELECT OpportunityId
            FROM OpportunityTeamMember
            WHERE UserId = :tae.Requester__c
        ]) {
            expectedOpportunityIds.add(otm.OpportunityId);
        }
        for (Opportunity opp : [
            SELECT Id
            FROM Opportunity
            WHERE OwnerId = :tae.Requester__c
        ]) {
            expectedOpportunityIds.add(opp.Id);
        }

        List<TAE_AssignedRecord__c> rows = [
            SELECT Account__c, Opportunity__c
            FROM TAE_AssignedRecord__c
            WHERE TemporaryAccessException__c = :taeId
        ];
        System.assertEquals(
            expectedAccountIds.size() + expectedOpportunityIds.size(),
            rows.size(),
            'Assigned record count should match requester team access scope'
        );

        Set<Id> foundAccountIds = new Set<Id>();
        Set<Id> foundOpportunityIds = new Set<Id>();
        for (TAE_AssignedRecord__c row : rows) {
            if (row.Account__c != null) {
                System.assertEquals(null, row.Opportunity__c, 'Account row should not populate Opportunity__c');
                foundAccountIds.add(row.Account__c);
            }
            if (row.Opportunity__c != null) {
                System.assertEquals(null, row.Account__c, 'Opportunity row should not populate Account__c');
                foundOpportunityIds.add(row.Opportunity__c);
            }
        }
        System.assertEquals(expectedAccountIds, foundAccountIds, 'Assigned Account rows should match grant scope');
        System.assertEquals(
            expectedOpportunityIds,
            foundOpportunityIds,
            'Assigned Opportunity rows should match grant scope'
        );
    }

    /**
     * @description
     * Returns persisted Status__c for a TemporaryAccessException__c row created in test context.
     *
     * @param taeId TemporaryAccessException__c Id
     * @return Status__c value from the database
     */
    private static String queryTaeStatusById(Id taeId) {
        return [
            SELECT Status__c
            FROM TemporaryAccessException__c
            WHERE Id = :taeId
            LIMIT 1
        ].Status__c;
    }

    /**
     * @description
     * Returns Status__c for the Active row matching requester and coverage rep in test context.
     *
     * @param ctx Scenario context from TestDataFactory
     * @return Active Status__c value
     */
    private static String queryActiveTaeStatusForContext(TestDataFactory.ScenarioContext ctx) {
        List<TemporaryAccessException__c> rows = [
            SELECT Status__c
            FROM TemporaryAccessException__c
            WHERE Requester__c = :ctx.requesterId
              AND CoverageRep__c = :ctx.coverageRepId
              AND Status__c = :TemporaryAccessExceptionSelector.STATUS_ACTIVE
            LIMIT 1
        ];
        System.assertEquals(1, rows.size(), 'Expected one Active TemporaryAccessException__c row');
        return rows[0].Status__c;
    }

    /**
     * @description
     * Loads TemporaryAccessException__c fields required by email notification builders.
     *
     * @param taeId TemporaryAccessException__c Id
     * @return Row with email template fields populated
     */
    private static TemporaryAccessException__c queryTaeForEmailNotifications(Id taeId) {
        return [
            SELECT Id, Name, Requester__c, CoverageRep__c, EndDate__c
            FROM TemporaryAccessException__c
            WHERE Id = :taeId
            LIMIT 1
        ];
    }

    /**
     * @description
     * Returns preloaded territory Ids for one requester, matching the service bulk email path.
     *
     * @param requesterId TemporaryAccessException__c.Requester__c Id
     * @param territoryIdsByRequesterId Map loaded via TemporaryAccessExceptionSelector
     * @return Sorted unique territory numbers, or an empty list when none exist
     */
    private static List<String> resolveTerritoryIdsForRequester(
        Id requesterId,
        Map<Id, List<String>> territoryIdsByRequesterId
    ) {
        if (requesterId == null || territoryIdsByRequesterId == null) {
            return new List<String>();
        }
        List<String> territoryIds = territoryIdsByRequesterId.get(requesterId);
        return territoryIds == null ? new List<String>() : territoryIds;
    }

    /**
     * @description
     * Builds one grant or revoke notification request with preloaded territory context.
     *
     * @param tae TemporaryAccessException__c row for the email body
     * @param isGrant True for grant notifications; false for revoke notifications
     * @param territoryIdsByRequesterId Bulk-loaded territory map for requesters
     * @return Notification payload for sendBulkNotifications
     */
    private static TemporaryAccessExceptionEmailService.NotificationRequest buildEmailNotificationRequest(
        TemporaryAccessException__c tae,
        Boolean isGrant,
        Map<Id, List<String>> territoryIdsByRequesterId
    ) {
        TemporaryAccessExceptionEmailService.NotificationRequest request =
            new TemporaryAccessExceptionEmailService.NotificationRequest();
        request.taeRow = tae;
        request.isGrant = isGrant;
        request.territoryIds = resolveTerritoryIdsForRequester(
            tae.Requester__c,
            territoryIdsByRequesterId
        );
        return request;
    }

    /**
     * @description
     * Asserts no email invocations occurred in the current governor limit window.
     *
     * @param message Assertion failure message
     * @return void
     */
    private static void assertNoEmailInvocations(String message) {
        System.assertEquals(0, Limits.getEmailInvocations(), message);
    }

    /**
     * @description
     * Asserts a DML operation was blocked by a field custom validation rule.
     *
     * @param error Thrown DmlException
     * @param fieldToken Expected field that failed validation
     * @param optionalMessageFragment Optional substring expected in the error message
     * @return void
     */
    private static void assertFieldValidationFailure(
        DmlException error,
        Schema.SObjectField fieldToken,
        String optionalMessageFragment
    ) {
        System.assertEquals(
            StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION,
            error.getDmlType(0),
            'Expected field custom validation failure: ' + error.getMessage()
        );
        Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
        System.assert(
            error.getDmlFieldNames(0).contains(fieldDescribe.getName()),
            'Expected validation on ' + fieldDescribe.getName() + '. Actual fields: ' + error.getDmlFieldNames(0)
        );
        if (String.isNotBlank(optionalMessageFragment)) {
            System.assert(
                error.getMessage().contains(optionalMessageFragment),
                'Expected validation message fragment. Actual: ' + error.getMessage()
            );
        }
    }

    /**
     * @description
     * Builds multiple notification requests for email chunking coverage.
     *
     * @param tae TemporaryAccessException__c row
     * @param ctx Scenario context from TestDataFactory
     * @param requestCount Number of requests to build
     * @return Notification request list
     */
    private static List<TemporaryAccessExceptionEmailService.NotificationRequest> buildChunkNotificationRequests(
        TemporaryAccessException__c tae,
        TestDataFactory.ScenarioContext ctx,
        Integer requestCount
    ) {
        List<TemporaryAccessExceptionEmailService.NotificationRequest> requests =
            new List<TemporaryAccessExceptionEmailService.NotificationRequest>();
        for (Integer requestIndex = 0; requestIndex < requestCount; requestIndex++) {
            TemporaryAccessExceptionEmailService.NotificationRequest request =
                new TemporaryAccessExceptionEmailService.NotificationRequest();
            request.taeRow = tae;
            request.isGrant = (Math.mod(requestIndex, 2) == 0);
            requests.add(request);
        }
        return requests;
    }

    // --- Exception ---

    /**
     * @description
     * Verifies TemporaryAccessExceptionException can be thrown and caught with a message.
     *
     * @return void
     */
    @IsTest
    static void testExceptionTypeMessageAndThrow() {
        /********************************************
        * SETUP
        ********************************************/
        String expectedMessage = 'Temporary access security failure';

        /********************************************
        * WHEN / THEN
        ********************************************/
        Boolean threw = false;
        try {
            throwTemporaryAccessException(expectedMessage);
        } catch (TemporaryAccessExceptionException e) {
            threw = true;
            System.assertEquals(expectedMessage, e.getMessage());
        }

        System.assert(threw, 'TemporaryAccessExceptionException should be throwable');
    }

    private static void throwTemporaryAccessException(String expectedMessage) {
        throw new TemporaryAccessExceptionException(expectedMessage);
    }

    // --- Selector ---

    /**
     * @description
     * Verifies grant and revoke scenario helper methods.
     *
     * @return void
     */
    @IsTest
    static void testSelectorScenarioHelpers() {
        /********************************************
        * GIVEN
        ********************************************/
        TemporaryAccessException__c grantRow = TestDataFactory.buildGrantTae(
            UserInfo.getUserId(),
            UserInfo.getUserId()
        );
        TemporaryAccessException__c revokeRow = TestDataFactory.buildRevokeTae(
            UserInfo.getUserId(),
            UserInfo.getUserId()
        );
        revokeRow = TestDataFactory.prepareRevokeRowForProcessing(revokeRow);

        /********************************************
        * WHEN / THEN
        ********************************************/
        System.assert(TemporaryAccessExceptionSelector.isGrantScenario(grantRow));
        System.assert(TemporaryAccessExceptionSelector.isRevokeScenario(revokeRow));
        System.assert(!TemporaryAccessExceptionSelector.isGrantScenario(null));
        System.assert(!TemporaryAccessExceptionSelector.isRevokeScenario(null));
        System.assert(!TemporaryAccessExceptionSelector.isGrantScenario(revokeRow));
        System.assert(!TemporaryAccessExceptionSelector.isRevokeScenario(grantRow));
    }

    /**
     * @description
     * Verifies composite key builders for account and opportunity team members.
     *
     * @return void
     */
    @IsTest
    static void testSelectorBuildTeamKeys() {
        /********************************************
        * GIVEN
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        Id accountId = ctx.accountId;
        Id userId = ctx.coverageRepId;

        /********************************************
        * WHEN
        ********************************************/
        String accountKey = TemporaryAccessExceptionSelector.buildAccountTeamKey(accountId, userId);

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(String.valueOf(accountId) + '|' + String.valueOf(userId), accountKey);

        String oppPrefix = Opportunity.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix();
        Id syntheticOpportunityId = (Id) (oppPrefix + '000000000000');
        String syntheticOpportunityKey = TemporaryAccessExceptionSelector.buildOpportunityTeamKey(
            syntheticOpportunityId,
            userId
        );
        System.assertEquals(
            String.valueOf(syntheticOpportunityId) + '|' + String.valueOf(userId),
            syntheticOpportunityKey
        );

        if (ctx.hasOpportunity == true && ctx.opportunityId != null) {
            String opportunityKey = TemporaryAccessExceptionSelector.buildOpportunityTeamKey(
                ctx.opportunityId,
                userId
            );
            System.assertEquals(
                String.valueOf(ctx.opportunityId) + '|' + String.valueOf(userId),
                opportunityKey
            );
        }
    }

    /**
     * @description
     * Verifies selector methods return empty collections for null or empty input.
     *
     * @return void
     */
    @IsTest
    static void testSelectorEmptyInputReturnsEmpty() {
        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            System.assertEquals(0, TemporaryAccessExceptionSelector.selectRequesterAccountTeamMembers(null).size());
            System.assertEquals(0, TemporaryAccessExceptionSelector.selectRequesterAccountTeamMembers(new Set<Id>()).size());
            System.assertEquals(0, TemporaryAccessExceptionSelector.selectRequesterOpportunityTeamMembers(null).size());
            System.assertEquals(0, TemporaryAccessExceptionSelector.selectRequesterOwnedAccounts(new Set<Id>()).size());
            System.assertEquals(0, TemporaryAccessExceptionSelector.selectRequesterOwnedOpportunities(new Set<Id>()).size());
            System.assertEquals(0, TemporaryAccessExceptionSelector.selectExistingCoverageRepAccountTeamKeys(null, null).size());
            System.assertEquals(0, TemporaryAccessExceptionSelector.selectExistingCoverageRepOpportunityTeamKeys(null, null).size());
            System.assertEquals(0, TemporaryAccessExceptionSelector.selectTemporaryAssignmentAccountTeamMembersForRevoke(null).size());
            System.assertEquals(0, TemporaryAccessExceptionSelector.selectTemporaryAssignmentOpportunityTeamMembersForRevoke(null).size());
            System.assertEquals(0, TemporaryAccessExceptionSelector.selectUsersById(null).size());
            System.assertEquals(0, TemporaryAccessExceptionSelector.selectAccountsById(null).size());
            System.assertEquals(0, TemporaryAccessExceptionSelector.selectOpportunitiesById(null).size());
            System.assertEquals(
                0,
                TemporaryAccessExceptionSelector.selectExistingCoverageRepOpportunityTeamKeys(
                    new Set<Id>(),
                    new Set<Id>{ UserInfo.getUserId() }
                ).size()
            );
        }
    }

    /**
     * @description
     * Verifies processing query locator returns eligible rows and loads related selector data.
     *
     * @return void
     */
    @IsTest
    static void testSelectorGetProcessingQueryLocatorAndRelatedQueries() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TestDataFactory.insertGrantTae(ctx.requesterId, ctx.coverageRepId);
        ctx = TestDataFactory.getScenarioContext();

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(1, countEligibleTaeRows());

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            Database.QueryLocator locator = TemporaryAccessExceptionSelector.getProcessingQueryLocator();
            System.assertNotEquals(null, locator);

            Set<Id> requesterIds = new Set<Id>{ ctx.requesterId };
            System.assert(
                TemporaryAccessExceptionSelector.selectRequesterAccountTeamMembers(requesterIds).size() > 0
            );
            if (ctx.opportunityId != null) {
                System.assert(
                    TemporaryAccessExceptionSelector.selectRequesterOpportunityTeamMembers(requesterIds).size() > 0
                );
                Map<Id, Opportunity> opportunitiesById = TemporaryAccessExceptionSelector.selectOpportunitiesById(
                    new Set<Id>{ ctx.opportunityId }
                );
                System.assertEquals(1, opportunitiesById.size());
            }
            System.assertEquals(
                0,
                TemporaryAccessExceptionSelector.selectRequesterOwnedAccounts(requesterIds).size()
            );
            System.assertEquals(
                0,
                TemporaryAccessExceptionSelector.selectRequesterOwnedOpportunities(requesterIds).size()
            );

            Map<Id, User> usersById = TemporaryAccessExceptionSelector.selectUsersById(
                new Set<Id>{ ctx.requesterId, ctx.coverageRepId }
            );
            Map<Id, Account> accountsById = TemporaryAccessExceptionSelector.selectAccountsById(
                new Set<Id>{ ctx.accountId }
            );

            /********************************************
            * THEN
            ********************************************/
            System.assertEquals(2, usersById.size());
            System.assertEquals(1, accountsById.size());
        }
    }

    // --- Service: scope and routing ---

    /**
     * @description
     * Verifies process handles null or empty scope without error.
     *
     * @return void
     */
    @IsTest
    static void testServiceProcessEmptyScope() {
        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(null);
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>());
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM AccountTeamMember
                WHERE TeamMemberRole = :TemporaryAccessExceptionService.TEAM_MEMBER_ROLE_SALES
                  AND AssignmentType__c = :TemporaryAccessExceptionService.ASSIGNMENT_TYPE_TEMPORARY_ASSIGNMENT
            ]
        );
    }

    /**
     * @description
     * Verifies grant processing adds Temporary Coverage Rep team members and activates the row.
     *
     * @return void
     */
    @IsTest
    static void testServiceGrantScenarioActivatesAndAddsTeamMembers() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();

        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));
        assertOtmCountIfPresent(ctx, ctx.coverageRepId, 0, 'No opportunity team member expected before grant');

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ tae });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));
        AccountTeamMember grantedAtm = [
            SELECT TerritoryCode__c, SalesCategoryCode__c, SalesCategoryDescription__c
            FROM AccountTeamMember
            WHERE AccountId = :ctx.accountId
              AND UserId = :ctx.coverageRepId
              AND TeamMemberRole = :TemporaryAccessExceptionService.TEAM_MEMBER_ROLE_SALES
              AND AssignmentType__c = :TemporaryAccessExceptionService.ASSIGNMENT_TYPE_TEMPORARY_ASSIGNMENT
            LIMIT 1
        ];
        System.assertEquals(
            TestDataFactory.REQUESTER_TERRITORY_CODE,
            grantedAtm.TerritoryCode__c,
            'GC-3352 TerritoryCode__c should copy from the requester AccountTeamMember'
        );
        System.assertEquals(
            TestDataFactory.REQUESTER_SALES_CATEGORY_CODE,
            grantedAtm.SalesCategoryCode__c,
            'GC-3352 SalesCategoryCode__c should copy from the requester AccountTeamMember'
        );
        System.assertEquals(
            TestDataFactory.REQUESTER_SALES_CATEGORY_DESCRIPTION,
            grantedAtm.SalesCategoryDescription__c,
            'GC-3352 SalesCategoryDescription__c should copy from the requester AccountTeamMember'
        );
        assertOtmCountIfPresent(
            ctx,
            ctx.coverageRepId,
            1,
            'Opportunity team member should be created with temporary assignment shape'
        );
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_ACTIVE,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].Status__c
        );
    }

    /**
     * @description
     * Verifies revoke processing removes Temporary Coverage Rep team members and expires the row.
     *
     * @return void
     */
    @IsTest
    static void testServiceRevokeScenarioExpiresAndRemovesTeamMembers() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TestDataFactory.seedTemporaryCoverageRepTeamMembers(ctx);

        TemporaryAccessException__c tae = TestDataFactory.prepareRevokeRowForProcessing(
            TestDataFactory.insertRevokeTae(ctx.requesterId, ctx.coverageRepId)
        );

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(1, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));
        assertOtmCountIfPresent(ctx, ctx.coverageRepId, 1, 'Coverage rep OTM should exist before revoke');

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ tae });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(0, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));
        assertOtmCountIfPresent(ctx, ctx.coverageRepId, 0, 'Coverage rep OTM should be removed after revoke');
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_EXPIRED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].Status__c
        );
    }

    /**
     * @description
     * Verifies revoke deletes only Sales + Temporary Assignment rows and leaves other memberships intact.
     *
     * @return void
     */
    @IsTest
    static void testServiceRevokeDeletesOnlyMatchingRoleAndAssignmentType() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();

        TestDataFactory.insertAccountTeamMemberWithRoleAndAssignment(
            ctx.accountId,
            ctx.coverageRepId,
            TemporaryAccessExceptionService.TEAM_MEMBER_ROLE_SALES,
            'Oracle Assigned',
            Date.today()
        );

        TemporaryAccessException__c tae = TestDataFactory.prepareRevokeRowForProcessing(
            TestDataFactory.insertRevokeTae(ctx.requesterId, ctx.coverageRepId)
        );

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));
        System.assertEquals(
            1,
            [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :ctx.accountId AND UserId = :ctx.coverageRepId]
        );

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ tae });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(0, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));
        System.assertEquals(
            1,
            [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :ctx.accountId AND UserId = :ctx.coverageRepId],
            'Sales membership with non-temporary assignment type should not be deleted'
        );
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_EXPIRED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].Status__c
        );
    }

    /**
     * @description
     * Verifies revoke still expires the row when no Temporary Coverage Rep memberships exist.
     *
     * @return void
     */
    @IsTest
    static void testServiceRevokeWithNoTeamMembersStillExpires() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();

        TemporaryAccessException__c tae = TestDataFactory.prepareRevokeRowForProcessing(
            TestDataFactory.insertRevokeTae(ctx.requesterId, ctx.coverageRepId)
        );

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ tae });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_EXPIRED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].Status__c
        );
    }

    /**
     * @description
     * Verifies grant remains idempotent when coverage rep is already on the team.
     *
     * @return void
     */
    @IsTest
    static void testServiceIdempotentWhenCoverageRepAlreadyOnTeam() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TestDataFactory.seedTemporaryCoverageRepTeamMembers(ctx);

        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(1, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ tae });
            tae.Status__c = TemporaryAccessExceptionSelector.STATUS_APPROVED;
            tae.StartDate__c = Date.today();
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ tae });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            1,
            countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId),
            'Second pass should remain idempotent'
        );
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_ACTIVE,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].Status__c
        );
    }

    /**
     * @description
     * GC-3333 - Verifies successful grant inserts TAE_AssignedRecord__c audit rows.
     *
     * @return void
     */
    @IsTest
    static void testServiceGrantCreatesAssignedRecords() {
        TestDataFactory.ScenarioContext ctx = TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );

        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ tae });
        }

        assertAssignedRecordShape(tae.Id);
    }

    /**
     * @description
     * GC-3333 - Verifies assigned record inserts remain idempotent on repeated grant processing.
     *
     * @return void
     */
    @IsTest
    static void testServiceGrantAssignedRecordsIdempotent() {
        TestDataFactory.ScenarioContext ctx = TestDataFactory.getScenarioContext();
        TestDataFactory.seedTemporaryCoverageRepTeamMembers(ctx);

        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );

        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ tae });
            Integer assignedCountAfterFirstGrant = countAssignedRecordsForTae(tae.Id);
            tae.Status__c = TemporaryAccessExceptionSelector.STATUS_APPROVED;
            tae.StartDate__c = Date.today();
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ tae });
            System.assertEquals(
                assignedCountAfterFirstGrant,
                countAssignedRecordsForTae(tae.Id),
                'Assigned record count should remain idempotent across grant passes'
            );
        }
    }

    /**
     * @description
     * GC-3333 - Verifies revoke processing does not delete assigned audit rows.
     *
     * @return void
     */
    @IsTest
    static void testServiceRevokeLeavesAssignedRecords() {
        TestDataFactory.ScenarioContext ctx = TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );

        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ tae });
        }

        Integer assignedCountAfterGrant = countAssignedRecordsForTae(tae.Id);
        System.assert(assignedCountAfterGrant > 0, 'Grant should create assigned records before revoke');

        TemporaryAccessException__c revokeRow = TestDataFactory.prepareRevokeRowForProcessing(
            [
                SELECT Id, Name, StartDate__c, EndDate__c, Status__c, Requester__c, CoverageRep__c
                FROM TemporaryAccessException__c
                WHERE Id = :tae.Id
                LIMIT 1
            ]
        );

        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ revokeRow });
        }

        System.assertEquals(
            assignedCountAfterGrant,
            countAssignedRecordsForTae(tae.Id),
            'Revoke should not delete assigned audit rows'
        );
    }

    /**
     * @description
     * Verifies non-eligible rows are ignored by the service.
     *
     * @return void
     */
    @IsTest
    static void testServiceIgnoresNonEligibleRows() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();

        TemporaryAccessException__c tae = TestDataFactory.buildGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );
        tae.Status__c = 'Draft';
        insert tae;
        if ([SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].Status__c != 'Draft') {
            update new TemporaryAccessException__c(Id = tae.Id, Status__c = 'Draft');
        }

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ tae });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            'Draft',
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].Status__c
        );
        System.assertEquals(0, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));
    }

    /**
     * @description
     * Verifies mixed grant and revoke rows process in a single service call.
     *
     * @return void
     */
    @IsTest
    static void testServiceMixedGrantAndRevokeInOneCall() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TestDataFactory.seedTemporaryCoverageRepTeamMembers(ctx);

        TemporaryAccessException__c grantTae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );
        TemporaryAccessException__c revokeTae = TestDataFactory.prepareRevokeRowForProcessing(
            TestDataFactory.insertRevokeTae(ctx.requesterId, ctx.coverageRepId)
        );

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(
                new List<TemporaryAccessException__c>{ grantTae, revokeTae }
            );
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_ACTIVE,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :grantTae.Id].Status__c
        );
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_EXPIRED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :revokeTae.Id].Status__c
        );
    }

    // --- Email service ---

    /**
     * @description
     * Verifies bulk notification entry points handle null and empty request lists.
     *
     * @return void
     */
    @IsTest
    static void testEmailServiceEmptyAndNullRequests() {
        /********************************************
        * SETUP
        ********************************************/
        resetEmailFlags();
        Integer emailInvocationsBefore = Limits.getEmailInvocations();

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionEmailService.sendBulkNotifications(null, new Map<Id, User>());
            TemporaryAccessExceptionEmailService.sendBulkNotifications(
                new List<TemporaryAccessExceptionEmailService.NotificationRequest>(),
                new Map<Id, User>()
            );
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            emailInvocationsBefore,
            Limits.getEmailInvocations(),
            'Null and empty email request lists should not invoke Messaging.sendEmail'
        );
    }

    /**
     * @description
     * Verifies skipSendForTest bypasses Messaging.sendEmail while building notifications.
     *
     * @return void
     */
    @IsTest
    static void testEmailServiceSkipSendForTest() {
        /********************************************
        * SETUP
        ********************************************/
        resetEmailFlags();
        TemporaryAccessExceptionEmailService.skipSendForTest = true;

        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );
        tae = queryTaeForEmailNotifications(tae.Id);

        TemporaryAccessExceptionEmailService.NotificationRequest request =
            new TemporaryAccessExceptionEmailService.NotificationRequest();
        request.taeRow = tae;
        request.isGrant = true;

        Map<Id, User> usersById = TemporaryAccessExceptionSelector.selectUsersById(
            new Set<Id>{ ctx.requesterId, ctx.coverageRepId }
        );

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionEmailService.sendBulkNotifications(
                new List<TemporaryAccessExceptionEmailService.NotificationRequest>{ request },
                usersById
            );
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(true, TemporaryAccessExceptionEmailService.skipSendForTest);
        assertNoEmailInvocations('skipSendForTest branch should complete without send');
        resetEmailFlags();
    }

    /**
     * @description
     * Verifies grant and revoke notification payloads send via sendBulkNotifications.
     *
     * @return void
     */
    @IsTest
    static void testEmailServiceSendGrantAndRevokeNotification() {
        /********************************************
        * SETUP
        ********************************************/
        resetEmailFlags();
        TemporaryAccessExceptionEmailService.skipSendForTest = true;

        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );
        tae = queryTaeForEmailNotifications(tae.Id);

        Map<Id, User> usersById = TemporaryAccessExceptionSelector.selectUsersById(
            new Set<Id>{ ctx.requesterId, ctx.coverageRepId }
        );
        Map<Id, List<String>> territoryIdsByRequesterId =
            TemporaryAccessExceptionSelector.selectDistinctTerritoryIdsByAssignedSalesRep(
                new Set<Id>{ tae.Requester__c }
            );

        TemporaryAccessExceptionEmailService.NotificationRequest grantRequest =
            buildEmailNotificationRequest(tae, true, territoryIdsByRequesterId);
        TemporaryAccessExceptionEmailService.NotificationRequest revokeRequest =
            buildEmailNotificationRequest(tae, false, territoryIdsByRequesterId);

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionEmailService.sendBulkNotifications(
                new List<TemporaryAccessExceptionEmailService.NotificationRequest>{
                    grantRequest,
                    revokeRequest
                },
                usersById
            );
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(TemporaryAccessExceptionEmailService.SUBJECT_GRANT, 'Temporary Coverage Access Granted');
        System.assertEquals(TemporaryAccessExceptionEmailService.SUBJECT_REVOKE, 'Temporary Coverage Access Revoked');
        resetEmailFlags();
    }

    /**
     * @description
     * Verifies Messaging.sendEmail path executes when skipSendForTest is false.
     *
     * @return void
     */
    @IsTest
    static void testEmailServiceSendBulkNotificationsExecutesSendPath() {
        /********************************************
        * SETUP
        ********************************************/
        resetEmailFlags();

        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );
        tae = queryTaeForEmailNotifications(tae.Id);

        TemporaryAccessExceptionEmailService.NotificationRequest request =
            new TemporaryAccessExceptionEmailService.NotificationRequest();
        request.taeRow = tae;
        request.isGrant = true;

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionEmailService.sendBulkNotifications(
                new List<TemporaryAccessExceptionEmailService.NotificationRequest>{ request },
                TemporaryAccessExceptionSelector.selectUsersById(
                    new Set<Id>{ ctx.requesterId, ctx.coverageRepId }
                )
            );
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertNotEquals(null, tae.Id, 'TAE row should remain persisted after send path');
    }

    // --- Batch and schedulable ---

    /**
     * @description
     * Verifies submitBatch returns a job Id when flex-queue guard is bypassed in test.
     *
     * @return void
     */
    @IsTest
    static void testSubmitBatchQueuesJobWhenFlexQueueCheckSkipped() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();
        TemporaryAccessExceptionBatch.skipFlexQueueCheckForTest = true;

        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TestDataFactory.insertGrantTae(ctx.requesterId, ctx.coverageRepId);

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(1, countEligibleTaeRows());

        /********************************************
        * WHEN
        ********************************************/
        Id jobId;
        Test.startTest();
        System.runAs(getRunAsUser()) {
            jobId = TemporaryAccessExceptionBatch.submitBatch();
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertNotEquals(null, jobId);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE JobType = 'BatchApex'
                  AND ApexClass.Name = 'TemporaryAccessExceptionBatch'
            ]
        );
        resetBatchFlags();
    }

    /**
     * @description
     * Verifies submitBatch throws when flex queue is at capacity.
     *
     * @return void
     */
    @IsTest
    static void testSubmitBatchThrowsWhenFlexQueueFull() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();
        TemporaryAccessExceptionBatch.testFlexQueueHoldingCountOverride =
            TemporaryAccessExceptionBatch.FLEX_QUEUE_MAX_BATCH_JOBS;

        /********************************************
        * WHEN / THEN
        ********************************************/
        Boolean threw = false;
        try {
            TemporaryAccessExceptionBatch.submitBatch();
        } catch (TemporaryAccessExceptionException e) {
            threw = true;
            System.assert(e.getMessage().contains('flex queue'), e.getMessage());
        }
        System.assert(threw, 'submitBatch should throw when flex queue is full');
        resetBatchFlags();
    }

    /**
     * @description
     * Verifies grant processing end-to-end through the batch.
     *
     * @return void
     */
    @IsTest
    static void testBatchGrantEndToEnd() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();

        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TestDataFactory.insertGrantTae(ctx.requesterId, ctx.coverageRepId);

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));

        /********************************************
        * WHEN
        ********************************************/
        Id jobId;
        Test.startTest();
        System.runAs(getRunAsUser()) {
            jobId = runBatch();
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertNotEquals(null, jobId);
        System.assertEquals(1, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_ACTIVE,
            queryActiveTaeStatusForContext(ctx)
        );
    }

    /**
     * @description
     * Verifies batch locator excludes Active rows whose EndDate is not today.
     * Revoke rows are inserted with a future EndDate (TER_001); service revoke tests use
     * prepareRevokeRowForProcessing in memory because EndDate = today is blocked on DML.
     *
     * @return void
     */
    @IsTest
    static void testBatchSkipsRevokeRowsWhenEndDateNotToday() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();

        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TestDataFactory.seedTemporaryCoverageRepTeamMembers(ctx);
        TestDataFactory.insertRevokeTae(ctx.requesterId, ctx.coverageRepId);

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, countEligibleTaeRows());
        System.assertEquals(1, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(getRunAsUser()) {
            runBatch();
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_ACTIVE,
            queryActiveTaeStatusForContext(ctx)
        );
    }

    /**
     * @description
     * Verifies bulk grant rows process within a single test execute invocation.
     *
     * @return void
     */
    @IsTest
    static void testBatchProcessesBulkGrantInSingleTestExecute() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();

        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();

        TestDataFactory.insertGrantTaeBulk(
            ctx.requesterId,
            ctx.coverageRepId,
            BULK_ROW_COUNT
        );

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(getRunAsUser()) {
            runBatch();
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            BULK_ROW_COUNT,
            [
                SELECT COUNT()
                FROM TemporaryAccessException__c
                WHERE Status__c = :TemporaryAccessExceptionSelector.STATUS_ACTIVE
            ],
            'Batch should activate all bulk grant rows within the single test execute invocation'
        );
    }

    /**
     * @description
     * Verifies execute exceptions are caught without failing the test run.
     *
     * @return void
     */
    @IsTest
    static void testBatchExecuteHandlesExceptionWithoutRethrow() {
        try {
            /********************************************
            * SETUP
            ********************************************/
            resetBatchFlags();

            TestDataFactory.ScenarioContext ctx =
                TestDataFactory.getScenarioContext();
            TestDataFactory.insertGrantTae(ctx.requesterId, ctx.coverageRepId);
            TemporaryAccessExceptionBatch.throwInExecute = true;

            /********************************************
            * GIVEN
            ********************************************/
            System.assertEquals(0, TemporaryAccessExceptionBatch.executeCatchCount);

            /********************************************
            * WHEN
            ********************************************/
            Id jobId;
            Test.startTest();
            System.runAs(getRunAsUser()) {
                jobId = runBatch();
            }
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            System.assertNotEquals(null, jobId);
            System.assert(TemporaryAccessExceptionBatch.executeCatchCount > 0, 'Execute errors should be caught');
            System.assertEquals(0, TemporaryAccessExceptionBatch.finishCatchCount);
        } finally {
            resetBatchFlags();
        }
    }

    /**
     * @description
     * Verifies finish exceptions are caught without failing the test run.
     *
     * @return void
     */
    @IsTest
    static void testBatchFinishHandlesExceptionWithoutRethrow() {
        try {
            /********************************************
            * SETUP
            ********************************************/
            resetBatchFlags();

            TestDataFactory.ScenarioContext ctx =
                TestDataFactory.getScenarioContext();
            TestDataFactory.insertGrantTae(ctx.requesterId, ctx.coverageRepId);
            TemporaryAccessExceptionBatch.throwInFinish = true;

            /********************************************
            * GIVEN
            ********************************************/
            System.assertEquals(0, TemporaryAccessExceptionBatch.finishCatchCount);

            /********************************************
            * WHEN
            ********************************************/
            Id jobId;
            Test.startTest();
            System.runAs(getRunAsUser()) {
                jobId = runBatch();
            }
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            System.assertNotEquals(null, jobId);
            System.assert(TemporaryAccessExceptionBatch.finishCatchCount > 0, 'Finish errors should be caught');
            System.assertEquals(0, TemporaryAccessExceptionBatch.executeCatchCount);
        } finally {
            resetBatchFlags();
        }
    }

    /**
     * @description
     * Verifies start returns the processing query locator for eligible rows.
     *
     * @return void
     */
    @IsTest
    static void testBatchStartReturnsProcessingQueryLocator() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();

        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TestDataFactory.insertGrantTae(ctx.requesterId, ctx.coverageRepId);

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(1, countEligibleTaeRows());

        /********************************************
        * WHEN
        ********************************************/
        Database.QueryLocator locator;
        System.runAs(getRunAsUser()) {
            locator = new TemporaryAccessExceptionBatch().start(null);
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertNotEquals(null, locator);
        System.assertEquals(0, TemporaryAccessExceptionBatch.startCatchCount);
        resetBatchFlags();
    }

    /**
     * @description
     * Verifies start exceptions are logged and rethrown.
     *
     * @return void
     */
    @IsTest
    static void testBatchStartThrows() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();
        TemporaryAccessExceptionBatch.throwInStart = true;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, TemporaryAccessExceptionBatch.startCatchCount);

        /********************************************
        * WHEN / THEN
        ********************************************/
        Boolean threw = false;
        try {
            System.runAs(getRunAsUser()) {
                new TemporaryAccessExceptionBatch().start(null);
            }
            System.assert(false, 'Expected start to throw');
        } catch (Exception e) {
            threw = true;
            System.assertNotEquals(null, e);
        }

        System.assert(threw, 'start() should rethrow after logging');
        System.assertEquals(1, TemporaryAccessExceptionBatch.startCatchCount);
        resetBatchFlags();
    }

    /**
     * @description
     * Verifies Schedulable execute queues exactly one TemporaryAccessExceptionBatch job.
     *
     * @return void
     */
    @IsTest
    static void testSchedulableExecuteQueuesSingleBatchJob() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();
        TemporaryAccessExceptionBatch.skipFlexQueueCheckForTest = true;

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(getRunAsUser()) {
            new TemporaryAccessExceptionBatch().execute(null);
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE JobType = 'BatchApex'
                  AND ApexClass.Name = 'TemporaryAccessExceptionBatch'
            ],
            'Schedulable should queue one batch job'
        );
        resetBatchFlags();
    }

    /**
     * @description
     * Verifies Schedulable execute processes grant rows end-to-end.
     *
     * @return void
     */
    @IsTest
    static void testSchedulableExecuteProcessesGrantEndToEnd() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();
        TemporaryAccessExceptionBatch.skipFlexQueueCheckForTest = true;

        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TestDataFactory.insertGrantTae(ctx.requesterId, ctx.coverageRepId);

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(getRunAsUser()) {
            new TemporaryAccessExceptionBatch().execute(null);
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_ACTIVE,
            queryActiveTaeStatusForContext(ctx)
        );
        resetBatchFlags();
    }

    // --- Service coverage (exception paths and logDmlErrors) ---

    /**
     * @description
     * Verifies logDmlErrors handles null and failed DML error lists.
     *
     * @return void
     */
    @IsTest
    static void testServiceLogDmlErrorsPaths() {
        /********************************************
        * SETUP
        ********************************************/
        resetServiceTestFlags();

        /********************************************
        * WHEN
        ********************************************/
        TemporaryAccessExceptionService.testOnlyInvokeLogDmlErrors();

        /********************************************
        * THEN
        ********************************************/
        System.assert(Limits.getDmlStatements() > 0, 'logDmlErrors should exercise DML error handling');
    }

    /**
     * @description
     * Verifies process skips work when common read security check fails.
     *
     * @return void
     */
    @IsTest
    static void testServiceSkipsWhenCommonReadSecurityFails() {
        /********************************************
        * SETUP
        ********************************************/
        resetServiceTestFlags();
        TemporaryAccessExceptionService.testOnlyForceCommonReadSecurityFailure = true;

        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_APPROVED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].Status__c
        );

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ tae });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_APPROVED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].Status__c,
            'Grant should not run when common read security fails'
        );
        System.assertEquals(0, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));

        resetServiceTestFlags();
    }

    /**
     * @description
     * Verifies process skips grant when grant security check fails.
     *
     * @return void
     */
    @IsTest
    static void testServiceSkipsGrantWhenGrantSecurityFails() {
        /********************************************
        * SETUP
        ********************************************/
        resetServiceTestFlags();
        TemporaryAccessExceptionService.testOnlyForceGrantSecurityFailure = true;

        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ tae });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_APPROVED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].Status__c
        );
        System.assertEquals(0, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));
        System.assertEquals(
            0,
            countAssignedRecordsForTae(tae.Id),
            'Failed grant should not create assigned audit rows'
        );

        resetServiceTestFlags();
    }

    /**
     * @description
     * Verifies process skips revoke when revoke security check fails.
     *
     * @return void
     */
    @IsTest
    static void testServiceSkipsRevokeWhenRevokeSecurityFails() {
        /********************************************
        * SETUP
        ********************************************/
        resetServiceTestFlags();
        TemporaryAccessExceptionService.testOnlyForceRevokeSecurityFailure = true;

        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TestDataFactory.seedTemporaryCoverageRepTeamMembers(ctx);

        TemporaryAccessException__c tae = TestDataFactory.prepareRevokeRowForProcessing(
            TestDataFactory.insertRevokeTae(ctx.requesterId, ctx.coverageRepId)
        );

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ tae });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_ACTIVE,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].Status__c
        );
        System.assertEquals(1, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));

        resetServiceTestFlags();
    }

    /**
     * @description
     * Verifies selector returns existing coverage rep team keys after seeding team members.
     *
     * @return void
     */
    @IsTest
    static void testSelectorExistingCoverageRepKeys() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TestDataFactory.seedTemporaryCoverageRepTeamMembers(ctx);

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            Set<String> accountKeys = TemporaryAccessExceptionSelector.selectExistingCoverageRepAccountTeamKeys(
                new Set<Id>{ ctx.accountId },
                new Set<Id>{ ctx.coverageRepId }
            );

            /********************************************
            * THEN
            ********************************************/
            System.assert(
                accountKeys.contains(
                    TemporaryAccessExceptionSelector.buildAccountTeamKey(ctx.accountId, ctx.coverageRepId)
                )
            );
        }
    }

    /**
     * @description
     * Verifies email service skips send when no recipient emails can be resolved.
     *
     * @return void
     */
    @IsTest
    static void testEmailServiceSkipsWhenNoRecipients() {
        /********************************************
        * SETUP
        ********************************************/
        resetEmailFlags();
        TemporaryAccessExceptionEmailService.skipSendForTest = false;

        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );
        tae = queryTaeForEmailNotifications(tae.Id);

        TemporaryAccessExceptionEmailService.NotificationRequest request =
            new TemporaryAccessExceptionEmailService.NotificationRequest();
        request.taeRow = tae;
        request.isGrant = true;

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionEmailService.sendBulkNotifications(
                new List<TemporaryAccessExceptionEmailService.NotificationRequest>{ request },
                new Map<Id, User>()
            );
        }

        /********************************************
        * THEN
        ********************************************/
        assertNoEmailInvocations('No-recipient path should complete without send');
        resetEmailFlags();
    }

    /**
     * @description
     * GC-3179 - Modified: verifies resolveBatchSize() matches BatchProcessConfig__mdt for this batch.
     * Verifies batch class exposes expected constants for scheduling and flex-queue guard.
     *
     * @return void
     */
    @IsTest
    static void testBatchConstants() {
        System.assertEquals(100, TemporaryAccessExceptionBatch.DEFAULT_BATCH_SIZE);
        System.assertEquals(100, TemporaryAccessExceptionBatch.FLEX_QUEUE_MAX_BATCH_JOBS);
        System.assertEquals('0 0 1 * * ?', TemporaryAccessExceptionBatch.SCHEDULE_CRON_DAILY_1AM);
        System.assertEquals(
            'Temporary Access Exception Team Access',
            TemporaryAccessExceptionBatch.SCHEDULE_JOB_NAME
        );
        BatchProcessConfig__mdt batchConfig = [
            SELECT BatchSize__c
            FROM BatchProcessConfig__mdt
            WHERE BatchClassName__c = 'TemporaryAccessExceptionBatch'
              AND IsActive__c = TRUE
            LIMIT 1
        ];
        System.assertEquals(
            batchConfig.BatchSize__c.intValue(),
            TemporaryAccessExceptionBatch.resolveBatchSize()
        );
    }

    /**
     * @description
     * Verifies selector revoke queries and owned-record lookups return data in scope.
     *
     * @return void
     */
    @IsTest
    static void testSelectorRevokeQueriesAndOwnedRecords() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TestDataFactory.seedTemporaryCoverageRepTeamMembers(ctx);

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            List<SObject> accountRevokeRows =
                TemporaryAccessExceptionSelector.selectTemporaryAssignmentAccountTeamMembersForRevoke(
                    buildRevokeTeamMemberCriteria(
                        new Set<Id>{ ctx.accountId },
                        new Set<Id>{ ctx.coverageRepId }
                    )
                );

            update new Account(Id = ctx.accountId, OwnerId = ctx.requesterId);

            Set<Id> requesterIds = new Set<Id>{ ctx.requesterId };
            List<Account> ownedAccounts =
                TemporaryAccessExceptionSelector.selectRequesterOwnedAccounts(requesterIds);

            /********************************************
            * THEN
            ********************************************/
            System.assert(accountRevokeRows.size() > 0, 'Expected seeded account team member for revoke query');
            System.assert(ownedAccounts.size() > 0, 'Expected requester-owned account after owner update');
        }
    }

    /**
     * @description
     * Verifies grant processing uses account-owner scope when requester owns the account.
     *
     * @return void
     */
    @IsTest
    static void testServiceGrantViaAccountOwnerPath() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();

        System.runAs(getRunAsUser()) {
            delete [
                SELECT Id
                FROM AccountTeamMember
                WHERE AccountId = :ctx.accountId
                  AND UserId = :ctx.requesterId
            ];
            update new Account(Id = ctx.accountId, OwnerId = ctx.requesterId);
        }

        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(new List<TemporaryAccessException__c>{ tae });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));
        AccountTeamMember ownerPathAtm = [
            SELECT TerritoryCode__c, SalesCategoryCode__c, SalesCategoryDescription__c
            FROM AccountTeamMember
            WHERE AccountId = :ctx.accountId
              AND UserId = :ctx.coverageRepId
              AND TeamMemberRole = :TemporaryAccessExceptionService.TEAM_MEMBER_ROLE_SALES
              AND AssignmentType__c = :TemporaryAccessExceptionService.ASSIGNMENT_TYPE_TEMPORARY_ASSIGNMENT
            LIMIT 1
        ];
        System.assertEquals(null, ownerPathAtm.TerritoryCode__c, 'GC-3352 owner-only grant has no requester ATM to copy');
        System.assertEquals(null, ownerPathAtm.SalesCategoryCode__c, 'GC-3352 owner-only grant has no requester ATM to copy');
        System.assertEquals(
            null,
            ownerPathAtm.SalesCategoryDescription__c,
            'GC-3352 owner-only grant has no requester ATM to copy'
        );
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_ACTIVE,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].Status__c
        );
    }

    /**
     * @description
     * Verifies process grant/revoke paths no-op when rows lack requester or coverage rep lookups.
     *
     * @return void
     */
    @IsTest
    static void testServiceEmptyPlansWhenLookupsMissing() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();

        TemporaryAccessException__c grantTae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );
        TemporaryAccessException__c revokeTae = TestDataFactory.prepareRevokeRowForProcessing(
            TestDataFactory.insertRevokeTae(ctx.requesterId, ctx.coverageRepId)
        );
        grantTae.Requester__c = null;
        revokeTae.CoverageRep__c = null;

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionService.process(
                new List<TemporaryAccessException__c>{ grantTae, revokeTae }
            );
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_APPROVED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :grantTae.Id].Status__c
        );
        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_ACTIVE,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :revokeTae.Id].Status__c
        );
        System.assertEquals(0, countTemporaryAssignmentAtm(ctx.accountId, ctx.coverageRepId));
    }

    /**
     * @description
     * Verifies partial DML failure helpers exercise insert, delete, and update error logging.
     *
     * @return void
     */
    @IsTest
    static void testServicePartialDmlFailurePaths() {
        /********************************************
        * SETUP
        ********************************************/
        resetServiceTestFlags();

        /********************************************
        * WHEN
        ********************************************/
        TemporaryAccessExceptionService.testOnlyInvokePartialInsertFailure();
        TemporaryAccessExceptionService.testOnlyInvokePartialDeleteFailure();
        TemporaryAccessExceptionService.testOnlyInvokeUpdateStatusesFailure();
        TemporaryAccessExceptionService.testOnlyInvokeOpportunityCoveragePaths();

        /********************************************
        * THEN
        ********************************************/
        System.assert(Limits.getDmlStatements() > 0, 'Partial DML failure paths should exercise DML handling');
    }

    /**
     * @description
     * Verifies email service logs simulated send failures and chunks messages using configured chunk size.
     *
     * @return void
     */
    @IsTest
    static void testEmailServiceSimulatedFailureAndChunking() {
        /********************************************
        * SETUP
        ********************************************/
        resetEmailFlags();
        TemporaryAccessExceptionEmailService.testOnly_simulateSendFailure = true;
        TemporaryAccessExceptionEmailService.testOnly_emailChunkSizeOverride = 10;

        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );
        tae = queryTaeForEmailNotifications(tae.Id);

        Map<Id, User> usersById = TemporaryAccessExceptionSelector.selectUsersById(
            new Set<Id>{ ctx.requesterId, ctx.coverageRepId }
        );

        List<TemporaryAccessExceptionEmailService.NotificationRequest> requests =
            buildChunkNotificationRequests(tae, ctx, 11);

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionEmailService.sendBulkNotifications(requests, usersById);
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(11, requests.size(), 'Chunking test should build more than one send chunk');
        resetEmailFlags();
    }

    /**
     * @description
     * Verifies grant/revoke HTML bodies complete without sending when skipSendForTest is enabled.
     *
     * @return void
     */
    @IsTest
    static void testEmailServiceHtmlBodyAndLinkedRecordPaths() {
        /********************************************
        * SETUP
        ********************************************/
        resetEmailFlags();
        TemporaryAccessExceptionEmailService.skipSendForTest = true;

        TestDataFactory.ScenarioContext ctx = TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(ctx.requesterId, ctx.coverageRepId);
        tae = queryTaeForEmailNotifications(tae.Id);

        User requester = [
            SELECT Id, Email, Name, IsActive
            FROM User
            WHERE Id = :ctx.requesterId
        ];
        Map<Id, User> requesterOnlyUsers = new Map<Id, User>{ ctx.requesterId => requester };

        TemporaryAccessExceptionEmailService.NotificationRequest revokeEmpty =
            new TemporaryAccessExceptionEmailService.NotificationRequest();
        revokeEmpty.taeRow = tae;
        revokeEmpty.isGrant = false;

        TemporaryAccessExceptionEmailService.NotificationRequest grantRequest =
            new TemporaryAccessExceptionEmailService.NotificationRequest();
        grantRequest.taeRow = tae;
        grantRequest.isGrant = true;

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionEmailService.sendBulkNotifications(
                new List<TemporaryAccessExceptionEmailService.NotificationRequest>{
                    revokeEmpty,
                    grantRequest
                },
                requesterOnlyUsers
            );
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(true, TemporaryAccessExceptionEmailService.skipSendForTest);
        assertNoEmailInvocations('Grant/revoke HTML branches should complete without send');
        resetEmailFlags();
    }

    /**
     * @description
     * Verifies recipient filtering, null mail skipping in bulk, and non-grant isGrant values.
     *
     * @return void
     */
    @IsTest
    static void testEmailServiceRecipientFilteringAndBulkNullMail() {
        /********************************************
        * SETUP
        ********************************************/
        resetEmailFlags();
        TemporaryAccessExceptionEmailService.skipSendForTest = true;

        TestDataFactory.ScenarioContext ctx = TestDataFactory.getScenarioContext();
        TemporaryAccessException__c noRecipientTae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );
        TemporaryAccessException__c validTae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );

        noRecipientTae = queryTaeForEmailNotifications(noRecipientTae.Id);
        validTae = queryTaeForEmailNotifications(validTae.Id);

        User requester = [
            SELECT Id, Email, Name, IsActive
            FROM User
            WHERE Id = :ctx.requesterId
        ];
        User inactiveCoverageRep = new User(
            Id = ctx.coverageRepId,
            Email = 'inactive.cov@test.com',
            IsActive = false
        );
        User blankEmailCoverageRep = new User(
            Id = ctx.coverageRepId,
            Email = '',
            IsActive = true
        );

        TemporaryAccessExceptionEmailService.NotificationRequest noRecipients =
            new TemporaryAccessExceptionEmailService.NotificationRequest();
        noRecipients.taeRow = noRecipientTae;
        noRecipients.isGrant = true;

        TemporaryAccessExceptionEmailService.NotificationRequest revokeStyleRequest =
            new TemporaryAccessExceptionEmailService.NotificationRequest();
        revokeStyleRequest.taeRow = validTae;
        revokeStyleRequest.isGrant = null;

        Map<Id, User> usersWithBlankCoverageEmail = new Map<Id, User>{
            ctx.requesterId => requester,
            ctx.coverageRepId => blankEmailCoverageRep
        };
        Map<Id, User> usersWithInactiveCoverageRep = new Map<Id, User>{
            ctx.requesterId => requester,
            ctx.coverageRepId => inactiveCoverageRep
        };

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionEmailService.sendBulkNotifications(
                new List<TemporaryAccessExceptionEmailService.NotificationRequest>{
                    noRecipients,
                    revokeStyleRequest
                },
                new Map<Id, User>()
            );

            TemporaryAccessExceptionEmailService.sendBulkNotifications(
                new List<TemporaryAccessExceptionEmailService.NotificationRequest>{ revokeStyleRequest },
                usersWithBlankCoverageEmail
            );

            revokeStyleRequest.isGrant = true;
            TemporaryAccessExceptionEmailService.sendBulkNotifications(
                new List<TemporaryAccessExceptionEmailService.NotificationRequest>{ revokeStyleRequest },
                usersWithInactiveCoverageRep
            );
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM TemporaryAccessException__c
                WHERE Id IN :new Set<Id>{ noRecipientTae.Id, validTae.Id }
            ],
            'Recipient filtering test should retain both inserted rows'
        );
        resetEmailFlags();
    }

    /**
     * @description
     * Verifies real Messaging.sendEmail failure paths log formatted errors through the service.
     *
     * @return void
     */
    @IsTest
    static void testEmailServiceLogsFailedSendResults() {
        /********************************************
        * SETUP
        ********************************************/
        resetEmailFlags();
        TemporaryAccessExceptionEmailService.testOnly_simulateSendFailure = false;

        TestDataFactory.ScenarioContext ctx = TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(ctx.requesterId, ctx.coverageRepId);
        tae = queryTaeForEmailNotifications(tae.Id);

        TemporaryAccessExceptionEmailService.NotificationRequest request =
            new TemporaryAccessExceptionEmailService.NotificationRequest();
        request.taeRow = tae;
        request.isGrant = true;

        Map<Id, User> usersById = TemporaryAccessExceptionSelector.selectUsersById(
            new Set<Id>{ ctx.requesterId, ctx.coverageRepId }
        );

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(getRunAsUser()) {
            TemporaryAccessExceptionEmailService.sendBulkNotifications(
                new List<TemporaryAccessExceptionEmailService.NotificationRequest>{ request },
                usersById
            );
            TemporaryAccessExceptionEmailService.testOnly_invokeFailedSendResultLogging();
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertNotEquals(null, request.taeRow.Id, 'Send path should retain notification source row');
        resetEmailFlags();
    }

    /**
     * @description
     * Verifies schedulable execute logs and rethrows when flex queue capacity is exceeded.
     *
     * @return void
     */
    @IsTest
    static void testSchedulableExecuteRethrowsWhenFlexQueueFull() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();
        TemporaryAccessExceptionBatch.testFlexQueueHoldingCountOverride =
            TemporaryAccessExceptionBatch.FLEX_QUEUE_MAX_BATCH_JOBS;

        /********************************************
        * WHEN / THEN
        ********************************************/
        Boolean threw = false;
        try {
            new TemporaryAccessExceptionBatch().execute(null);
        } catch (TemporaryAccessExceptionException e) {
            threw = true;
            System.assert(e.getMessage().contains('flex queue is full'));
        }
        System.assert(threw, 'Schedulable execute should rethrow flex-queue capacity errors');
        resetBatchFlags();
    }

    /**
     * @description
     * Verifies assertFlexQueueHasCapacity queries live Holding job count when no test override is set.
     *
     * @return void
     */
    @IsTest
    static void testBatchAssertFlexQueueUsesLiveHoldingCount() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();

        /********************************************
        * WHEN
        ********************************************/
        Integer holdingCount = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
              AND Status = 'Holding'
        ];
        System.assert(
            holdingCount < TemporaryAccessExceptionBatch.FLEX_QUEUE_MAX_BATCH_JOBS,
            'Flex queue should have capacity before assertFlexQueueHasCapacity runs'
        );
        TemporaryAccessExceptionBatch.assertFlexQueueHasCapacity();
        resetBatchFlags();
    }

    /**
     * @description
     * Verifies temporary assignment account revoke selector queries execute for synthetic inputs.
     *
     * @return void
     */
    @IsTest
    static void testSelectorTemporaryAssignmentRevokeQueryPaths() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        String accountPrefix = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix();
        Id syntheticAccountId = (Id) (accountPrefix + '000000000001');

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            System.assertEquals(
                0,
                TemporaryAccessExceptionSelector.selectTemporaryAssignmentAccountTeamMembersForRevoke(
                    buildRevokeTeamMemberCriteria(
                        new Set<Id>{ syntheticAccountId },
                        new Set<Id>{ ctx.coverageRepId }
                    )
                ).size()
            );
        }
    }

    // --- Validation rules (GC-2580) ---

    /**
     * @description
     * Verifies an End Date of today is not blocked now that TER_001 is inactive in the org.
     *
     * @return void
     */
    @IsTest
    static void testValidationEndDateTodayIsAllowed() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.buildGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );
        tae.EndDate__c = Date.today();

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            enableTemporaryAccessValidationRulesForTest(UserInfo.getUserId());
            insert tae;
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            Date.today(),
            [SELECT EndDate__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].EndDate__c,
            'End Date of today should be saved when TER_001 is inactive'
        );
    }

    /**
     * @description
     * Verifies TER_002 requires Business Justification when Exception Category is Other.
     *
     * @return void
     */
    @IsTest
    static void testValidationJustificationRequiredWhenOther() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        String otherCategory = TestDataFactory.resolveOtherExceptionCategoryValue();
        System.assertNotEquals(null, otherCategory, 'Other Exception Category must exist in org metadata');

        TemporaryAccessException__c tae = TestDataFactory.buildGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );
        tae.ExceptionCategory__c = otherCategory;
        tae.BusinessJustification__c = '   ';

        /********************************************
        * WHEN / THEN
        ********************************************/
        Boolean blocked = false;
        System.runAs(getRunAsUser()) {
            enableTemporaryAccessValidationRulesForTest(UserInfo.getUserId());
            try {
                insert tae;
            } catch (DmlException error) {
                blocked = true;
                assertFieldValidationFailure(
                    error,
                    TemporaryAccessException__c.BusinessJustification__c,
                    VR_MSG_JUSTIFICATION_REQUIRED
                );
            }
        }
        System.assert(blocked, 'TER_002 should block Other category without Business Justification');
    }

    /**
     * @description
     * Verifies TER_002 allows insert when Exception Category is Other and justification is provided.
     *
     * @return void
     */
    @IsTest
    static void testValidationJustificationAllowedWhenOtherWithText() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        String otherCategory = TestDataFactory.resolveOtherExceptionCategoryValue();
        System.assertNotEquals(null, otherCategory, 'Other Exception Category must exist in org metadata');

        TemporaryAccessException__c tae = TestDataFactory.buildGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );
        tae.ExceptionCategory__c = otherCategory;
        tae.BusinessJustification__c = 'Coverage required during territory transition.';

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            insert tae;
        }

        /********************************************
        * THEN
        ********************************************/
        TemporaryAccessException__c persisted = [
            SELECT ExceptionCategory__c, BusinessJustification__c
            FROM TemporaryAccessException__c
            WHERE Id = :tae.Id
            LIMIT 1
        ];
        System.assertEquals(otherCategory, persisted.ExceptionCategory__c);
        System.assertEquals(
            'Coverage required during territory transition.',
            persisted.BusinessJustification__c
        );
    }

    /**
     * @description
     * Verifies TER_003 blocks Start Date in the past.
     *
     * @return void
     */
    @IsTest
    static void testValidationStartDateNotPast() {
        /********************************************
        * SETUP
        ********************************************/
        TestDataFactory.ScenarioContext ctx =
            TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.buildGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );
        tae.StartDate__c = Date.today().addDays(-1);

        /********************************************
        * WHEN / THEN
        ********************************************/
        Boolean blocked = false;
        System.runAs(getRunAsUser()) {
            enableTemporaryAccessValidationRulesForTest(UserInfo.getUserId());
            try {
                insert tae;
            } catch (DmlException error) {
                blocked = true;
                assertFieldValidationFailure(
                    error,
                    TemporaryAccessException__c.StartDate__c,
                    VR_MSG_START_DATE_NOT_PAST
                );
            }
        }
        System.assert(blocked, 'TER_003 should block Start Date in the past');
    }
}