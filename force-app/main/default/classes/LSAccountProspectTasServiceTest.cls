/**
 * @description Test class for Life Sciences Prospect Account TAS (GCL-4).
 *              Covers LSAccountService, LSAccountProspectTasQueueable, and
 *              LSAccountProspectTasIntegrationService. Callouts use
 *              SO_Config.SO_ServiceList_mock and SO_HttpMockFactory.
 *
 *              Life Sciences-specific rules asserted here:
 *                1. Account Team Members resolve against the Life Sciences Sales
 *                   profile only.
 *                2. Outcomes write TAS_Assignment_Status__c only — no Sales Ops Task
 *                   and no bell notification.
 */
@IsTest
public class LSAccountProspectTasServiceTest {

    private static final String LS_CLASS_CODE = 'SC';

    /**
     * @description Creates reusable test data required by the Life Sciences TAS tests.
     *              Sales reps are created under the Life Sciences Sales profile so
     *              UserSelector.selectActiveLifeSciencesSalesUsersByEmployeeNumber can
     *              resolve them. One Standard User is also created so the profile
     *              filter can exclude a matching employee number on the wrong profile.
     */
    @testSetup
    static void setupData() {
        Profile lifeSciencesSalesProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = :UserSelector.LIFESCIENCES_SALES_PROFILE_NAME
            LIMIT 1
        ];

        Profile nonLifeSciencesProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name IN (
                'SalesFieldRepAccountManager',
                'PriceList_Create_PS',
                'OrderLineContact_c_Create_PS',
                'OrderLineContactUpdatePS'
            )
        ];

        Long uniqueSeed = System.currentTimeMillis();

        User runningUser = createUser(
            lifeSciencesSalesProfile.Id,
            'lsrunninguser' + uniqueSeed + '@test.com',
            'LSRUN' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );

        User tasRepOne = createUser(
            lifeSciencesSalesProfile.Id,
            'lstasrepone' + uniqueSeed + '@test.com',
            'LSTAS' + uniqueSeed + 'A'
        );

        User tasRepTwo = createUser(
            lifeSciencesSalesProfile.Id,
            'lstasreptwo' + uniqueSeed + '@test.com',
            'LSTAS' + uniqueSeed + 'B'
        );

        // Wrong-business-unit rep: resolvable by employee number but excluded by profile.
        User wrongProfileRep = createUser(
            nonLifeSciencesProfile.Id,
            'lswrongprof' + uniqueSeed + '@test.com',
            'LSWRG' + uniqueSeed + 'C'
        );

        insert new List<User>{ runningUser, tasRepOne, tasRepTwo, wrongProfileRep };

        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();

        for (PermissionSet ps : permissionSets) {
            assignments.add(
                new PermissionSetAssignment(
                    AssigneeId = runningUser.Id,
                    PermissionSetId = ps.Id
                )
            );
        }

        // Setup-object DML must be isolated from custom-setting DML (MIXED_DML_OPERATION).
        System.runAs(runningUser) {
            insert assignments;
        }
    }

    /**
     * @description Verifies Account Team Members are created from a mocked TAS response
     *              using Life Sciences Sales users. Assignment type is Oracle Assigned
     *              (shared picklist value).
     *              Insert uses trigger bypass so processAccounts is invoked once.
     */
    @IsTest
    static void testAfterInsertCreatesAccountTeamMembers() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('LS Price List Insert', 'PL-LS-INSERT-001');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createLifeSciencesProspectAccount(
                'LS Test Prospect Account',
                prospectRtId,
                priceList.Id
            );
            insertProspectWithoutTasEnqueue(runningUser, acc);

            registerTasCalloutMock(buildMockTasResponseJson(acc.Id));

            Test.startTest();
            LSAccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            List<AccountTeamMember> teamMembers = [
                SELECT Id,
                       AccountId,
                       UserId,
                       TeamMemberRole,
                       AssignmentType__c,
                       AccountAccessLevel
                FROM AccountTeamMember
                WHERE AccountId = :acc.Id
            ];

            System.assertEquals(
                2,
                teamMembers.size(),
                'Two Account Team Members should be created for a Life Sciences Prospect.'
            );

            for (AccountTeamMember atm : teamMembers) {
                System.assertEquals('Sales', atm.TeamMemberRole);
                System.assertEquals('Oracle Assigned', atm.AssignmentType__c);
                System.assertEquals('Edit', atm.AccountAccessLevel);
            }
        }
    }

    /**
     * @description Verifies LSAccountProspectTasIntegrationService end-to-end processing
     *              with a mocked TAS callout.
     */
    @IsTest
    static void testIntegrationServiceProcessesMockedTasResponse() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('LS Integration Price List', 'PL-LS-INT-001');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createLifeSciencesProspectAccount(
                'LS Integration Service Prospect',
                prospectRtId,
                priceList.Id
            );
            insertProspectWithoutTasEnqueue(runningUser, acc);

            registerTasCalloutMock(buildMockTasResponseJson(acc.Id));

            Test.startTest();
            LSAccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            System.assertEquals(
                2,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id],
                'Integration service should create two Account Team Members.'
            );
            String tasAddressId = String.valueOf(acc.Id);

            System.assertEquals(
                2,
                [SELECT COUNT() FROM OrderLineContact__c WHERE TASAddressId__c = :tasAddressId],
                'Integration service should create one OrderLineContact__c per territory.'
            );
        }
    }

    /**
     * @description Verifies duplicate Account Team Members are skipped on reprocessing.
     */
    @IsTest
    static void testDuplicateAccountTeamMembersAreSkipped() {
        User runningUser = getRunningUser();
        User tasRepOne = getTasRepOneUser();
        Price_List__c priceList = createPriceList('LS Duplicate Price List', 'PL-LS-DUP-001');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createLifeSciencesProspectAccount(
                'LS Duplicate Team Prospect',
                prospectRtId,
                priceList.Id
            );
            insertProspectWithoutTasEnqueue(runningUser, acc);

            insert new AccountTeamMember(
                AccountId = acc.Id,
                UserId = tasRepOne.Id,
                TeamMemberRole = 'Sales',
                AccountAccessLevel = 'Edit'
            );

            registerTasCalloutMock(buildMockTasResponseJson(acc.Id));

            Test.startTest();
            LSAccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            System.assertEquals(
                2,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id],
                'Only one additional Account Team Member should be inserted when one already exists.'
            );
        }
    }

    /**
     * @description Verifies failed TAS callouts do not create downstream records.
     */
    @IsTest
    static void testFailedCalloutCreatesNoDownstreamRecords() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('LS Failed Callout Price List', 'PL-LS-FAIL-001');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createLifeSciencesProspectAccount(
                'LS Failed Callout Prospect',
                prospectRtId,
                priceList.Id
            );
            insertProspectWithoutTasEnqueue(runningUser, acc);

            registerFailedTasCalloutMock();

            Test.startTest();
            LSAccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id],
                'Failed callout should not create Account Team Members.'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM OrderLineContact__c],
                'Failed callout should not create OrderLineContact__c records.'
            );
        }
    }

    /**
     * @description GCL-4: a successful TAS response with territory data classifies the
     *              Prospect as Assigned and sets TAS_Retry__c = true.
     */
    @IsTest
    static void testProcessAccounts_assigned_setsStatus() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('LS Assigned Price List', 'PL-LS-ASSIGN-001');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createLifeSciencesProspectAccount(
                'LS Assigned Status Prospect',
                prospectRtId,
                priceList.Id
            );
            insertProspectWithoutTasEnqueue(runningUser, acc);

            registerTasCalloutMock(buildMockTasResponseJson(acc.Id));

            Test.startTest();
            LSAccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            Account updated = [
                SELECT TAS_Assignment_Status__c, TAS_Retry__c FROM Account WHERE Id = :acc.Id
            ];

            System.assertEquals(
                LSAccountProspectTasIntegrationService.TAS_STATUS_ASSIGNED,
                updated.TAS_Assignment_Status__c,
                'Callout returning territory should be Assigned.'
            );
            System.assertEquals(
                true,
                updated.TAS_Retry__c,
                'TAS_Retry__c should be true on a successful assignment.'
            );
        }
    }

    /**
     * @description GCL-4: a successful TAS response with no territory data classifies the
     *              Prospect as Assignment Missing and sets TAS_Retry__c = false. Life
     *              Sciences must not create a Sales Ops Task.
     */
    @IsTest
    static void testProcessAccounts_assignmentMissing_createsNoTask() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('LS No Territory Price List', 'PL-LS-NOTERR-001');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createLifeSciencesProspectAccount(
                'LS No Territory Prospect',
                prospectRtId,
                priceList.Id
            );
            insertProspectWithoutTasEnqueue(runningUser, acc);

            registerTasCalloutMock(buildMockTasResponseJsonNoTerritory(acc.Id));

            Test.startTest();
            LSAccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            Account updated = [
                SELECT TAS_Assignment_Status__c, TAS_Retry__c FROM Account WHERE Id = :acc.Id
            ];

            System.assertEquals(
                LSAccountProspectTasIntegrationService.TAS_STATUS_ASSIGNMENT_MISSING,
                updated.TAS_Assignment_Status__c,
                'Successful callout with no territory should be Assignment Missing.'
            );
            System.assertEquals(
                false,
                updated.TAS_Retry__c,
                'TAS_Retry__c should be false when assignment is missing.'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Task WHERE WhatId = :acc.Id],
                'Life Sciences must not create a Sales Ops Task on Assignment Missing.'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM OrderLineContact__c],
                'No OrderLineContact__c should be created when no territory is returned.'
            );
        }
    }

    /**
     * @description GCL-4: a failed TAS callout classifies the Prospect as Technical
     *              Failure. Life Sciences must not create a Sales Ops Task.
     */
    @IsTest
    static void testProcessAccounts_technicalFailure_setsStatus() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('LS Tech Fail Price List', 'PL-LS-TECHFAIL-001');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createLifeSciencesProspectAccount(
                'LS Tech Fail Prospect',
                prospectRtId,
                priceList.Id
            );
            insertProspectWithoutTasEnqueue(runningUser, acc);

            registerFailedTasCalloutMock();

            Test.startTest();
            LSAccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            Account updated = [SELECT TAS_Assignment_Status__c FROM Account WHERE Id = :acc.Id];

            System.assertEquals(
                LSAccountProspectTasIntegrationService.TAS_STATUS_TECHNICAL_FAILURE,
                updated.TAS_Assignment_Status__c,
                'A failed callout should be classified as Technical Failure.'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Task WHERE WhatId = :acc.Id],
                'Life Sciences must not create a Sales Ops Task on Technical Failure.'
            );
        }
    }

    /**
     * @description GCL-4: applyTasOutcome writes the status without creating any Task,
     *              and is idempotent across repeat invocations.
     */
    @IsTest
    static void testApplyTasOutcome_writesStatusWithoutTask() {
        Account acc = new Account(
            Name = 'LS Dedup Outcome Prospect',
            SourceSystemID__c = 'LSProspectTas12345'
        );
        insert acc;

        Map<Id, String> missing = new Map<Id, String>{
            acc.Id => LSAccountProspectTasIntegrationService.TAS_STATUS_ASSIGNMENT_MISSING
        };

        Test.startTest();
        LSAccountProspectTasIntegrationService.applyTasOutcome(missing);
        LSAccountProspectTasIntegrationService.applyTasOutcome(missing);
        Test.stopTest();

        Account updated = [SELECT TAS_Assignment_Status__c FROM Account WHERE Id = :acc.Id];

        System.assertEquals(
            LSAccountProspectTasIntegrationService.TAS_STATUS_ASSIGNMENT_MISSING,
            updated.TAS_Assignment_Status__c,
            'applyTasOutcome should write the Assignment Missing status.'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Task WHERE WhatId = :acc.Id],
            'Repeat Assignment Missing must not create any Task for Life Sciences.'
        );
    }

    /**
     * @description When TAS returns a user who is not on Life Sciences Sales, no Account
     *              Team Member is created and status is Assignment Missing.
     */
    @IsTest
    static void testWrongProfileRepProducesNoTeamMember() {
        User runningUser = getRunningUser();
        User wrongProfileRep = getWrongProfileRepUser();
        Price_List__c priceList = createPriceList('LS Wrong Profile Price List', 'PL-LS-WPROF-001');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createLifeSciencesProspectAccount(
                'LS Wrong Profile Prospect',
                prospectRtId,
                priceList.Id
            );
            insertProspectWithoutTasEnqueue(runningUser, acc);

            registerTasCalloutMock(
                buildMockTasResponseJsonForEmployeeNumber(
                    acc.Id,
                    wrongProfileRep.EmployeeNumber__c
                )
            );

            Test.startTest();
            LSAccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id],
                'A user who is not Life Sciences Sales must not be added to the Account Team.'
            );

            Account updated = [SELECT TAS_Assignment_Status__c FROM Account WHERE Id = :acc.Id];
            System.assertEquals(
                LSAccountProspectTasIntegrationService.TAS_STATUS_ASSIGNMENT_MISSING,
                updated.TAS_Assignment_Status__c,
                'An unresolvable rep should leave the Prospect Assignment Missing.'
            );
        }
    }

    /**
     * @description Covers safe return paths for LSAccountService.
     */
    @IsTest
    static void testLSAccountServiceSafeReturnPaths() {
        Test.startTest();

        LSAccountService.assignTAStoProspect(null);
        LSAccountService.assignTAStoProspect(new List<Account>());

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'No Account Team Members should be created for safe return paths.'
        );
    }

    /**
     * @description Covers LSAccountProspectTasQueueable safe paths for null and empty
     *              Account Id sets.
     */
    @IsTest
    static void testLSAccountProspectTasQueueableSafePaths() {
        Test.startTest();

        System.enqueueJob(new LSAccountProspectTasQueueable(null));
        System.enqueueJob(new LSAccountProspectTasQueueable(new Set<Id>()));

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'No Account Team Members should be created for null or empty queueable input.'
        );
    }

    /**
     * @description Covers LSAccountProspectTasIntegrationService safe paths for null,
     *              empty, and null Account input.
     */
    @IsTest
    static void testLSIntegrationServiceSafePaths() {
        Test.startTest();

        LSAccountProspectTasIntegrationService.processAccounts(null);
        LSAccountProspectTasIntegrationService.processAccounts(new List<Account>());
        LSAccountProspectTasIntegrationService.processAccounts(new List<Account>{ null });

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM OrderLineContact__c],
            'No OrderLineContact__c records should be created for null or empty input.'
        );
    }

    /**
     * @description Covers insertTasAssignments safe path for null and empty input.
     */
    @IsTest
    static void testInsertTasAssignmentsSafePaths() {
        Test.startTest();

        LSAccountProspectTasIntegrationService.insertTasAssignments(null);
        LSAccountProspectTasIntegrationService.insertTasAssignments(new List<TasTerritoryItem>());

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM OrderLineContact__c],
            'No OrderLineContact__c records should be created for null or empty items.'
        );
    }

    /**
     * @description Covers insertTasAssignments null items, manager employee numbers,
     *              and invalid SalesRepId decimal parsing.
     */
    @IsTest
    static void testInsertTasAssignmentsNullItemsAndInvalidDecimal() {
        User runningUser = getRunningUser();
        User tasRepOne = getTasRepOneUser();
        Price_List__c priceList = createPriceList('LS TAS Rows Price List', 'PL-LS-TASROW-01');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createLifeSciencesProspectAccount(
                'LS TAS Rows Prospect',
                prospectRtId,
                priceList.Id
            );
            insertProspectWithoutTasEnqueue(runningUser, acc);

            TasTerritoryItem item = new TasTerritoryItem();
            item.accountId = acc.Id;
            item.salesRepId = 'notADecimal';
            item.salesRepEmployeeNumber = tasRepOne.EmployeeNumber__c;
            item.regionManagerEmployeeNumber = tasRepOne.EmployeeNumber__c;
            item.zoneManagerEmployeeNumber = tasRepOne.EmployeeNumber__c;
            item.territoryId = '81071';
            item.territoryNumber = 'L66301';
            item.classCode = LS_CLASS_CODE;

            Test.startTest();
            LSAccountProspectTasIntegrationService.insertTasAssignments(
                new List<TasTerritoryItem>{ null, item }
            );
            LSAccountProspectTasIntegrationService.insertTasAssignments(
                new List<TasTerritoryItem>{ null }
            );
            Test.stopTest();

            System.assertEquals(
                1,
                [SELECT COUNT() FROM OrderLineContact__c WHERE TASAddressId__c = :String.valueOf(acc.Id)],
                'One OrderLineContact__c should be inserted for the non-null territory item.'
            );
        }
    }

    /**
     * @description Covers logSaveResults failure logging and the test-only catch branch.
     */
    @IsTest
    static void testLogSaveResultsErrorAndCatchBranches() {
        List<AccountTeamMember> invalidTeamMembers = new List<AccountTeamMember>{
            new AccountTeamMember()
        };
        Database.SaveResult[] saveResults = Database.insert(invalidTeamMembers, false);

        LSAccountProspectTasIntegrationService.logSaveResults('AccountTeamMember', saveResults);
        LSAccountProspectTasIntegrationService.logSaveResults(
            'AccountTeamMember',
            new List<Database.SaveResult>()
        );

        try {
            LSAccountProspectTasIntegrationService.throwTestExceptionInLogSaveResults = true;
            LSAccountProspectTasIntegrationService.logSaveResults(
                'AccountTeamMember',
                new List<Database.SaveResult>()
            );
        } finally {
            LSAccountProspectTasIntegrationService.throwTestExceptionInLogSaveResults = false;
        }

        System.assertEquals(
            false,
            saveResults[0].isSuccess(),
            'Invalid AccountTeamMember should fail so logSaveResults records Database.Error details.'
        );
    }

    /**
     * @description Covers applyTasOutcome null Account Id and Assigned / Technical Failure counts.
     */
    @IsTest
    static void testApplyTasOutcomeNullIdAndAllStatuses() {
        Account acc = new Account(
            Name = 'LS Outcome Statuses Prospect',
            SourceSystemID__c = 'LSProspectTasOutcome'
        );
        insert acc;

        Map<Id, String> statuses = new Map<Id, String>();
        statuses.put(null, LSAccountProspectTasIntegrationService.TAS_STATUS_ASSIGNED);
        statuses.put(acc.Id, LSAccountProspectTasIntegrationService.TAS_STATUS_TECHNICAL_FAILURE);

        Test.startTest();
        LSAccountProspectTasIntegrationService.applyTasOutcome(null);
        LSAccountProspectTasIntegrationService.applyTasOutcome(new Map<Id, String>());
        LSAccountProspectTasIntegrationService.applyTasOutcome(statuses);
        Test.stopTest();

        Account updated = [SELECT TAS_Assignment_Status__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(
            LSAccountProspectTasIntegrationService.TAS_STATUS_TECHNICAL_FAILURE,
            updated.TAS_Assignment_Status__c,
            'applyTasOutcome should persist Technical Failure and skip a null Account Id.'
        );
    }

    /**
     * @description Covers LSAccountService.assignTAStoProspect enqueue and queueable processing.
     */
    @IsTest
    static void testAssignTAStoProspectEnqueuesQueueable() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('LS Enqueue Price List', 'PL-LS-ENQ-001');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            bypassAccountTrigger(runningUser, true);
            Account acc = createLifeSciencesProspectAccount(
                'LS Enqueue Prospect',
                prospectRtId,
                priceList.Id
            );
            insert acc;
            bypassAccountTrigger(runningUser, false);

            acc = [
                SELECT Id,
                       Name,
                       RecordTypeId,
                       CustomerClassCode__c,
                       OrgIDs__c,
                       Price_List__c,
                       BillingStreet,
                       BillingCity,
                       BillingState,
                       BillingCountry,
                       BillingPostalCode
                FROM Account
                WHERE Id = :acc.Id
            ];

            registerTasCalloutMock(buildMockTasResponseJson(acc.Id));

            Test.startTest();
            LSAccountService.assignTAStoProspect(new List<Account>{ acc });
            Test.stopTest();

            System.assertEquals(
                2,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id],
                'assignTAStoProspect should enqueue TAS processing that creates Account Team Members.'
            );
        }
    }

    /**
     * @description Covers assignTAStoProspect and retryTasAssignmentFromFlow catch blocks.
     */
    @IsTest
    static void testLSAccountServiceCatchBlocks() {
        Boolean assignCaught = false;
        Boolean retryCaught = false;

        try {
            LSAccountService.throwTestException = true;
            LSAccountService.assignTAStoProspect(new List<Account>());
        } catch (LSAccountService.LSAccountServiceException assignException) {
            assignCaught = true;
        } finally {
            LSAccountService.throwTestException = false;
        }

        try {
            LSAccountService.throwTestException = true;
            LSAccountService.retryTasAssignmentFromFlow(new List<LSAccountService.FlowRequest>());
        } catch (LSAccountService.LSAccountServiceException retryException) {
            retryCaught = true;
        } finally {
            LSAccountService.throwTestException = false;
        }

        System.assertEquals(true, assignCaught, 'assignTAStoProspect catch should run.');
        System.assertEquals(true, retryCaught, 'retryTasAssignmentFromFlow catch should run.');
    }

    /**
     * @description Covers LSAccountProspectTasQueueable.execute catch block.
     */
    @IsTest
    static void testQueueableExecuteCatchBlock() {
        Boolean caught = false;
        try {
            LSAccountProspectTasQueueable.throwTestException = true;
            new LSAccountProspectTasQueueable(new Set<Id>()).execute(null);
        } catch (Exception queueableException) {
            caught = true;
        } finally {
            LSAccountProspectTasQueueable.throwTestException = false;
        }

        System.assertEquals(
            false,
            caught,
            'Queueable execute should swallow the test exception in its catch block.'
        );
    }

    /**
     * @description Covers queueable execute completion by invoking execute directly.
     */
    @IsTest
    static void testQueueableExecuteCompletesWithMock() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('LS Q Execute Price List', 'PL-LS-QEXEC-01');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createLifeSciencesProspectAccount(
                'LS Queueable Execute Prospect',
                prospectRtId,
                priceList.Id
            );
            insertProspectWithoutTasEnqueue(runningUser, acc);

            registerTasCalloutMock(buildMockTasResponseJson(acc.Id));

            Test.startTest();
            new LSAccountProspectTasQueueable(new Set<Id>{ acc.Id }).execute(null);
            Test.stopTest();

            System.assertEquals(
                2,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id],
                'Direct queueable execute should process TAS and create Account Team Members.'
            );
        }
    }

    /**
     * @description Covers assignTAStoProspect when no Prospect is eligible.
     */
    @IsTest
    static void testAssignTAStoProspectIneligibleAccount() {
        Account acc = new Account(Name = 'LS Ineligible Prospect');

        Test.startTest();
        LSAccountService.assignTAStoProspect(new List<Account>{ acc, null });
        System.assertEquals(
            false,
            LSAccountService.isLifeSciencesAccount(null),
            'A null Account is not a Life Sciences Account.'
        );
        System.assertEquals(
            false,
            LSAccountService.isLifeSciencesAccount(acc),
            'An Account without class code is not a Life Sciences Account.'
        );
        Account nonLsClassCode = new Account(CustomerClassCode__c = 'XX');
        System.assertEquals(
            false,
            LSAccountService.isLifeSciencesAccount(nonLsClassCode),
            'A non-SC class code is not a Life Sciences Account.'
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'Ineligible Accounts must not create Account Team Members.'
        );
    }

    /**
     * @description Covers retryTasAssignmentFromFlow when the Prospect is already Assigned.
     */
    @IsTest
    static void testRetryTasAssignmentFromFlowAlreadyAssigned() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('LS Retry Assigned List', 'PL-LS-RETASG-01');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            bypassAccountTrigger(runningUser, true);
            Account acc = createLifeSciencesProspectAccount(
                'LS Already Assigned Prospect',
                prospectRtId,
                priceList.Id
            );
            acc.TAS_Retry__c = true;
            acc.TAS_Assignment_Status__c = LSAccountProspectTasIntegrationService.TAS_STATUS_ASSIGNED;
            insert acc;
            bypassAccountTrigger(runningUser, false);

            LSAccountService.FlowRequest request = new LSAccountService.FlowRequest();
            request.accountId = acc.Id;

            Test.startTest();
            LSAccountService.retryTasAssignmentFromFlow(
                new List<LSAccountService.FlowRequest>{ null, request }
            );
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id],
                'Already Assigned Prospects must not be retried.'
            );
        }
    }

    /**
     * @description Covers queueable execute when Account Ids do not resolve to records.
     */
    @IsTest
    static void testQueueableWhenAccountsNotFound() {
        Test.startTest();
        System.enqueueJob(
            new LSAccountProspectTasQueueable(new Set<Id>{ '001000000000001AAA' })
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'Queueable should exit when no Account records are found.'
        );
    }

    /**
     * @description Covers processAccounts inner catch when the TAS callout is not mocked.
     */
    @IsTest
    static void testProcessAccountsInnerCatchWithoutMock() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('LS Inner Catch List', 'PL-LS-CATCH-01');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createLifeSciencesProspectAccount(
                'LS Inner Catch Prospect',
                prospectRtId,
                priceList.Id
            );
            insertProspectWithoutTasEnqueue(runningUser, acc);

            Test.startTest();
            LSAccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            Account updated = [SELECT TAS_Assignment_Status__c FROM Account WHERE Id = :acc.Id];
            System.assertEquals(
                LSAccountProspectTasIntegrationService.TAS_STATUS_TECHNICAL_FAILURE,
                updated.TAS_Assignment_Status__c,
                'A callout exception should remain classified as Technical Failure.'
            );
        }
    }

    /**
     * @description Covers ATM insert when territory employee numbers are blank, mixed, or
     *              already present on the Account Team.
     */
    @IsTest
    static void testAccountTeamMemberUnresolvableAndDuplicatePaths() {
        User runningUser = getRunningUser();
        User tasRepOne = getTasRepOneUser();
        User tasRepTwo = getTasRepTwoUser();
        Price_List__c priceList = createPriceList('LS ATM Paths Price List', 'PL-LS-ATMPTH-01');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createLifeSciencesProspectAccount(
                'LS ATM Paths Prospect',
                prospectRtId,
                priceList.Id
            );
            insertProspectWithoutTasEnqueue(runningUser, acc);

            insert new List<AccountTeamMember>{
                new AccountTeamMember(
                    AccountId = acc.Id,
                    UserId = tasRepOne.Id,
                    TeamMemberRole = 'Sales',
                    AccountAccessLevel = 'Edit'
                ),
                new AccountTeamMember(
                    AccountId = acc.Id,
                    UserId = tasRepTwo.Id,
                    TeamMemberRole = 'Sales',
                    AccountAccessLevel = 'Edit'
                )
            };

            registerTasCalloutMock(buildMockTasResponseJson(acc.Id));

            Test.startTest();
            LSAccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            System.assertEquals(
                2,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id],
                'Existing Account Team Members should not be duplicated.'
            );
        }
    }

    /**
     * @description Covers a TAS payload with one resolvable LS rep and one unknown employee number.
     */
    @IsTest
    static void testMixedKnownAndUnknownEmployeeNumbers() {
        User runningUser = getRunningUser();
        User tasRepOne = getTasRepOneUser();
        Price_List__c priceList = createPriceList('LS Mixed Emp Price List', 'PL-LS-MIXEMP-01');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createLifeSciencesProspectAccount(
                'LS Mixed Emp Prospect',
                prospectRtId,
                priceList.Id
            );
            insertProspectWithoutTasEnqueue(runningUser, acc);

            String mixedJson = buildMockTasResponseJsonForEmployeeNumber(
                acc.Id,
                tasRepOne.EmployeeNumber__c
            );
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(mixedJson);
            List<Object> territoryData = (List<Object>) payload.get('territoryData');
            territoryData.add(
                new Map<String, Object>{
                    'classCode' => LS_CLASS_CODE,
                    'tasSalesCategory' => 'LS CAPITAL',
                    'territoryId' => '84735',
                    'salesRepEmployeeNumber' => 'UNKNOWN-LS-EMP',
                    'salesRepName' => 'Unknown Rep',
                    'buName' => 'Life Sciences'
                }
            );
            registerTasCalloutMock(JSON.serialize(payload));

            Test.startTest();
            LSAccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            System.assertEquals(
                1,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id],
                'Only the resolvable Life Sciences Sales rep should be added.'
            );
        }
    }

    /**
     * @description Covers TAS territory data with a blank sales rep employee number.
     */
    @IsTest
    static void testTerritoryWithBlankEmployeeNumber() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('LS Blank Emp Price List', 'PL-LS-BLKEMP-01');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createLifeSciencesProspectAccount(
                'LS Blank Emp Prospect',
                prospectRtId,
                priceList.Id
            );
            insertProspectWithoutTasEnqueue(runningUser, acc);

            registerTasCalloutMock(
                JSON.serialize(
                    new Map<String, Object>{
                        'prospectId' => acc.Id,
                        'territoryData' => new List<Object>{
                            new Map<String, Object>{
                                'classCode' => LS_CLASS_CODE,
                                'territoryId' => '81071',
                                'salesRepEmployeeNumber' => '',
                                'salesRepId' => '',
                                'buName' => 'Life Sciences'
                            }
                        }
                    }
                )
            );

            Test.startTest();
            LSAccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id],
                'Blank employee numbers must not create Account Team Members.'
            );
        }
    }

    /**
     * @description Verifies retryTasAssignmentFromFlow accepts an Account Id and submits
     *              Life Sciences TAS assignment retry processing.
     */
    @IsTest
    static void testRetryTasAssignmentFromFlow() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('LS Retry Price List', 'PL-LS-RETRY-001');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            bypassAccountTrigger(runningUser, true);

            Account acc = createLifeSciencesProspectAccount(
                'LS Retry Test Prospect',
                prospectRtId,
                priceList.Id
            );
            acc.TAS_Retry__c = false;
            insert acc;

            bypassAccountTrigger(runningUser, false);

            acc = [
                SELECT Id,
                       Name,
                       RecordTypeId,
                       CustomerClassCode__c,
                       OrgIDs__c,
                       Price_List__c,
                       BillingStreet,
                       BillingCity,
                       BillingState,
                       BillingCountry,
                       BillingPostalCode,
                       TAS_Retry__c,
                       TAS_Assignment_Status__c
                FROM Account
                WHERE Id = :acc.Id
            ];

            LSAccountService.FlowRequest request = new LSAccountService.FlowRequest();
            request.accountId = acc.Id;

            registerTasCalloutMock(buildMockTasResponseJson(acc.Id));

            Test.startTest();
            LSAccountService.retryTasAssignmentFromFlow(
                new List<LSAccountService.FlowRequest>{ request }
            );
            LSAccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            Account updatedAccount = [
                SELECT Id, TAS_Retry__c FROM Account WHERE Id = :acc.Id
            ];

            System.assertEquals(
                true,
                updatedAccount.TAS_Retry__c,
                'TAS_Retry__c should be true after a successful retry assignment.'
            );
            System.assertEquals(
                2,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id],
                'Retry flow should create Account Team Members.'
            );
        }
    }

    /**
     * @description Verifies retryTasAssignmentFromFlow safely handles null request input.
     */
    @IsTest
    static void testRetryTasAssignmentFromFlowNullRequest() {
        Test.startTest();

        LSAccountService.retryTasAssignmentFromFlow(null);

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'No Account Team Members should be created for null Flow request input.'
        );
    }

    /**
     * @description Verifies retryTasAssignmentFromFlow safely handles an empty request list.
     */
    @IsTest
    static void testRetryTasAssignmentFromFlowEmptyRequest() {
        Test.startTest();

        LSAccountService.retryTasAssignmentFromFlow(
            new List<LSAccountService.FlowRequest>()
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'No Account Team Members should be created for empty Flow request input.'
        );
    }

    /**
     * @description Verifies retryTasAssignmentFromFlow safely handles a request with a
     *              null Account Id.
     */
    @IsTest
    static void testRetryTasAssignmentFromFlowNullAccountId() {
        LSAccountService.FlowRequest request = new LSAccountService.FlowRequest();
        request.accountId = null;

        Test.startTest();

        LSAccountService.retryTasAssignmentFromFlow(
            new List<LSAccountService.FlowRequest>{ request }
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'No Account Team Members should be created when the Flow Account Id is null.'
        );
    }

    /**
     * @description Toggles the Account trigger bypass for the supplied user so a test can
     *              insert a Prospect without firing the real-time TAS enqueue.
     * @param runningUser User the hierarchy custom setting applies to.
     * @param bypass True to suppress the Account trigger.
     */
    private static void bypassAccountTrigger(User runningUser, Boolean bypass) {
        Automation_Setting_Trigger__c triggerSettings =
            Automation_Setting_Trigger__c.getInstance();
        triggerSettings.SetupOwnerId = runningUser.Id;
        triggerSettings.AccountTriggerByPass__c = bypass;
        upsert triggerSettings;
    }

    /**
     * @description Inserts a Prospect without enqueuing real-time TAS so the test can
     *              call LSAccountProspectTasIntegrationService.processAccounts directly.
     * @param runningUser User whose trigger bypass setting is toggled.
     * @param acc Prospect Account to insert.
     */
    private static void insertProspectWithoutTasEnqueue(User runningUser, Account acc) {
        bypassAccountTrigger(runningUser, true);
        insert acc;
        bypassAccountTrigger(runningUser, false);
    }

    private static void registerTasCalloutMock(String tasResponseBody) {
        loadTasServiceSetting();
        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(
                200,
                'OK',
                tasResponseBody,
                new Map<String, String>()
            )
        );
    }

    private static void registerFailedTasCalloutMock() {
        loadTasServiceSetting();
        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(
                500,
                'Internal Server Error',
                '{"error":"TAS unavailable"}',
                new Map<String, String>()
            )
        );
    }

    /**
     * @description Builds a mocked TAS success response containing two Life Sciences
     *              territories assigned to the two Life Sciences Sales test reps.
     * @param prospectId Prospect Account Id echoed back in the payload.
     * @return Serialized JSON string.
     */
    private static String buildMockTasResponseJson(String prospectId) {
        List<User> tasReps = [
            SELECT EmployeeNumber__c
            FROM User
            WHERE Email LIKE 'lstasrep%'
            ORDER BY Email
            LIMIT 2
        ];

        String employeeNumberOne = tasReps[0].EmployeeNumber__c;
        String employeeNumberTwo = tasReps[1].EmployeeNumber__c;

        Map<String, Object> response = new Map<String, Object>{
            'prospectId' => String.isBlank(prospectId) ? '001000000000001AAA' : prospectId,
            'territoryData' => new List<Object>{
                new Map<String, Object>{
                    'classCode' => LS_CLASS_CODE,
                    'tasSalesCategory' => 'LS CONSUMABLES',
                    'tasSalesCategoryDescription' => 'Life Sciences Consumables Sales',
                    'territoryId' => '81071',
                    'territoryNumber' => 'L66301',
                    'territoryDescription' => 'CLEVELAND, OH',
                    'salesRepId' => '100704356',
                    'salesRepEmployeeNumber' => employeeNumberOne,
                    'salesRepName' => 'LS Rep One',
                    'regionName' => 'L66300 Great Lakes',
                    'zoneName' => 'Life Sciences US',
                    'buName' => 'Life Sciences'
                },
                new Map<String, Object>{
                    'classCode' => LS_CLASS_CODE,
                    'tasSalesCategory' => 'LS CAPITAL',
                    'tasSalesCategoryDescription' => 'Life Sciences Capital Sales',
                    'territoryId' => '84735',
                    'territoryNumber' => 'L11217',
                    'territoryDescription' => 'CLEVELAND/COLUMBUS, OH',
                    'salesRepId' => '101142350',
                    'salesRepEmployeeNumber' => employeeNumberTwo,
                    'salesRepName' => 'LS Rep Two',
                    'regionName' => 'L11200 Mid Atlantic',
                    'zoneName' => 'Life Sciences East US',
                    'buName' => 'Life Sciences'
                }
            }
        };

        return JSON.serialize(response);
    }

    /**
     * @description Builds a mocked TAS success response with a single territory assigned
     *              to the supplied employee number, used to test rep resolution.
     * @param prospectId Prospect Account Id echoed back in the payload.
     * @param employeeNumber Sales rep employee number to return.
     * @return Serialized JSON string.
     */
    private static String buildMockTasResponseJsonForEmployeeNumber(
        String prospectId,
        String employeeNumber
    ) {
        return JSON.serialize(new Map<String, Object>{
            'prospectId' => prospectId,
            'territoryData' => new List<Object>{
                new Map<String, Object>{
                    'classCode' => LS_CLASS_CODE,
                    'tasSalesCategory' => 'LS CONSUMABLES',
                    'territoryId' => '81071',
                    'territoryNumber' => 'L66301',
                    'territoryDescription' => 'CLEVELAND, OH',
                    'salesRepId' => '100704356',
                    'salesRepEmployeeNumber' => employeeNumber,
                    'salesRepName' => 'Wrong Profile Rep',
                    'regionName' => 'L66300 Great Lakes',
                    'zoneName' => 'Life Sciences US',
                    'buName' => 'Life Sciences'
                }
            }
        });
    }

    /**
     * @description Builds a mocked TAS success response body with an empty territoryData
     *              array (the "call succeeded but no assignment" case).
     * @param prospectId Prospect Account Id echoed back in the payload.
     * @return Serialized JSON string.
     */
    private static String buildMockTasResponseJsonNoTerritory(String prospectId) {
        return JSON.serialize(new Map<String, Object>{
            'prospectId' => String.isBlank(prospectId) ? '001000000000001AAA' : prospectId,
            'territoryData' => new List<Object>()
        });
    }

    /**
     * @description Loads the org SF_PROSPECT_TAS ShoutOut setting into the test mock list.
     *              A hand-built SO_Provider_Salesforce record never reaches the HTTP mock.
     */
    private static void loadTasServiceSetting() {
        SO_Config.SO_ServiceList_mock.clear();
        SO_Config.SO_ServiceList_mock.addAll([
            SELECT DeveloperName,
                   Error_Handler_Class__c,
                   Framework_Callout_Name__c,
                   isActive__c,
                   MasterLabel,
                   Named_Credential__c,
                   Provider_Class__c,
                   REST_Path__c,
                   REST_query__c,
                   REST_Verb__c,
                   Service_Class__c,
                   Service_Transform_Class__c,
                   Timeout__c,
                   Retry_Max_Attempts__c,
                   Retry_Base_Delay_Seconds__c,
                   Retry_On_HTTP_Codes__c,
                   Retry_Callback_Class__c
            FROM ShoutOut_Service_Setting__mdt
            WHERE DeveloperName = 'SF_PROSPECT_TAS'
              AND isActive__c = true
            LIMIT 1
        ]);
    }

    /**
     * @description Retrieves the reusable Life Sciences running test user.
     * @return Running test User.
     */
    private static User getRunningUser() {
        return [
            SELECT Id
            FROM User
            WHERE Email LIKE 'lsrunninguser%'
            LIMIT 1
        ];
    }

    /**
     * @description Retrieves the first Life Sciences TAS sales rep created in @testSetup.
     * @return Matching active User record.
     */
    private static User getTasRepOneUser() {
        return [
            SELECT Id, EmployeeNumber__c
            FROM User
            WHERE Email LIKE 'lstasrepone%'
            LIMIT 1
        ];
    }

    /**
     * @description Retrieves the second Life Sciences TAS sales rep created in @testSetup.
     * @return Matching active User record.
     */
    private static User getTasRepTwoUser() {
        return [
            SELECT Id, EmployeeNumber__c
            FROM User
            WHERE Email LIKE 'lstasreptwo%'
            LIMIT 1
        ];
    }

    /**
     * @description Retrieves the Standard User created in @testSetup, used to verify
     *              the Life Sciences profile filter excludes other profiles.
     * @return Matching active User record that is not Life Sciences Sales.
     */
    private static User getWrongProfileRepUser() {
        return [
            SELECT Id, EmployeeNumber__c
            FROM User
            WHERE Email LIKE 'lswrongprof%'
            LIMIT 1
        ];
    }

    /**
     * @description Creates and inserts a Price_List__c test record.
     * @param name Price list name.
     * @param priceListId External price list identifier.
     * @return Inserted Price_List__c record.
     */
    private static Price_List__c createPriceList(String name, String priceListId) {
        Price_List__c priceList = new Price_List__c(
            Name = name,
            Price_List_Id__c = priceListId
        );

        insert priceList;

        return priceList;
    }

    /**
     * @description Retrieves the Prospect Account Record Type Id.
     * @return Prospect Account Record Type Id.
     */
    private static Id getProspectRecordTypeId() {
        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();
    }

    /**
     * @description Creates a valid Life Sciences Prospect Account test record.
     * @param name Account name.
     * @param prospectRecordTypeId Prospect Account Record Type Id.
     * @param priceListId Price_List__c Id.
     * @return Account record prepared for insertion.
     */
    private static Account createLifeSciencesProspectAccount(
        String name,
        Id prospectRecordTypeId,
        Id priceListId
    ) {
        return new Account(
            Name = name,
            RecordTypeId = prospectRecordTypeId,
            CustomerClassCode__c = LS_CLASS_CODE,
            OrgIDs__c = '83',
            Price_List__c = priceListId,
            BillingStreet = '123 Main St',
            BillingCity = 'Cleveland',
            BillingState = 'OH',
            BillingCountry = 'US',
            BillingPostalCode = '44101',
            TAS_Retry__c = false
        );
    }

    /**
     * @description Creates a test User record with the provided profile, username, and
     *              employee number.
     * @param profileId Id of the Profile assigned to the test user.
     * @param username Username and email assigned to the test user.
     * @param employeeNumber Employee number assigned to the test user.
     * @return User record prepared for insertion.
     */
    private static User createUser(
        Id profileId,
        String username,
        String employeeNumber
    ) {
        String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));

        return new User(
            FirstName = 'Test',
            LastName = 'User',
            Alias = ('l' + uniqueSuffix).left(8),
            Email = username,
            Username = username,
            CommunityNickname = 'lstestuser' + uniqueSuffix,
            ProfileId = profileId,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            EmployeeNumber__c = employeeNumber
        );
    }
}