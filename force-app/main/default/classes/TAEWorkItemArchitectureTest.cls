/**
 * GC-3420 - Tests for the serialized TAE work-item pipeline.
 * @author Suraj Thapliyal
 * @date 2026/09/29
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-3420 - Covers plan drafts, parent marking, grant and revoke workers,
 * phase chaining, and cleanup of Done rows.
 */
@IsTest(SeeAllData=false)
private class TAEWorkItemArchitectureTest {
    private static final String ACCOUNT_NAME = 'TAE Architecture Test Account';

    /**
     * @description Users and the account created by this test. Ids are not loaded from org records.
     */
    private class Scenario {
        Id requesterId;
        Id coverageRepId;
        Id accountId;
        Id opportunityId;
        Boolean hasOpportunity;
    }

    /**
     * @description Creates the requester, the coverage rep, and the account they cover.
     */
    @TestSetup
    static void setupData() {
        TestDataFactory.disableTemporaryAccessAutomationForTest();
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        List<User> users = new List<User>();
        for (String prefix : new List<String>{ 'archreq', 'archcov' }) {
            String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
            users.add(new User(
                FirstName = 'TAE',
                LastName = prefix,
                Alias = prefix,
                Email = prefix + '.' + suffix + '@test.com',
                Username = prefix + '.' + suffix + '@test.com',
                CommunityNickname = prefix + suffix,
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = adminProfile.Id,
                EmployeeNumber__c = prefix + suffix.right(6),
                IsActive = true
            ));
        }
        insert users;

        System.runAs(users[0]) {
            List<PermissionSet> permissionSets = [
                SELECT Id
                FROM PermissionSet
                WHERE Name IN ('System_Administrator', 'SalesFieldRepAccountManager')
            ];
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (PermissionSet permissionSetRow : permissionSets) {
                assignments.add(new PermissionSetAssignment(
                    AssigneeId = users[0].Id,
                    PermissionSetId = permissionSetRow.Id
                ));
            }
            if (!assignments.isEmpty()) {
                insert assignments;
            }
        }

        String oracleCustomerId = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        if (oracleCustomerId.length() > 15) {
            oracleCustomerId = oracleCustomerId.substring(0, 15);
        }
        Account acc = new Account(
            Name = ACCOUNT_NAME,
            OwnerId = users[0].Id,
            Description = String.valueOf(users[0].Id) + '|' + String.valueOf(users[1].Id)
        );
        Map<String, Schema.SObjectField> accountFields = Schema.SObjectType.Account.fields.getMap();
        String oracleFieldName = 'SystemID__c';
        for (Schema.SObjectField fieldToken : accountFields.values()) {
            Schema.DescribeFieldResult fieldDesc = fieldToken.getDescribe();
            if (fieldDesc.getLabel() == 'Oracle Customer ID'
                && fieldDesc.isCreateable()
                && !fieldDesc.isCalculated()) {
                oracleFieldName = fieldDesc.getName();
            }
        }
        acc.put(oracleFieldName, oracleCustomerId);
        if (accountFields.containsKey('sourcesystemid__c')) {
            acc.put('SourceSystemID__c', oracleCustomerId + 'Oracle');
        }
        insert acc;
        insert new AccountTeamMember(
            AccountId = acc.Id,
            UserId = users[0].Id,
            TeamMemberRole = 'Account Manager',
            AccountAccessLevel = 'Edit',
            OpportunityAccessLevel = 'Edit',
            CaseAccessLevel = 'Read',
            TerritoryCode__c = 'TAE-TERR-001',
            SalesCategoryCode__c = 'SURG SPT',
            SalesCategoryDescription__c = 'Surgical Support'
        );
    }

    /**
     * @description Reads the account this test inserted and the user Ids stored on it.
     * @return Requester, coverage rep, and account created in setup.
     */
    private static Scenario loadScenario() {
        Account acc = [
            SELECT Id, Description
            FROM Account
            WHERE Name = :ACCOUNT_NAME
            LIMIT 1
        ];
        List<String> userIds = acc.Description.split('\\|');
        Scenario ctx = new Scenario();
        ctx.accountId = acc.Id;
        ctx.requesterId = (Id) userIds[0];
        ctx.coverageRepId = (Id) userIds[1];
        ctx.opportunityId = null;
        ctx.hasOpportunity = false;
        return ctx;
    }

    /**
     * @description Loads the requester user created in setup.
     * @return The test requester.
     */
    private static User loadRequester() {
        Id requesterId = loadScenario().requesterId;
        return [SELECT Id FROM User WHERE Id = :requesterId];
    }

    /**
     * @description One account and one opportunity produce four grant drafts in phase order.
     */
    @IsTest
    static void grantIteratorCreatesFourTypedDraftsForOneAccountAndOpportunity() {
        Scenario scenario = loadScenario();
        TAEWorkItemService.PlanSnapshot plan = new TAEWorkItemService.PlanSnapshot();
        plan.coveredExceptionId = fakeId(TemporaryAccessException__c.SObjectType);
        plan.pipelineOperation = TAEWorkItemService.OP_GRANT;
        plan.accountIdList.add(scenario.accountId);
        plan.opportunityIdList.add(fakeId(Opportunity.SObjectType));

        TAEWorkItemCreationBatch.DraftIterator iterator =
            new TAEWorkItemCreationBatch.DraftIterator(plan);
        List<TAEProcessingWorkItem__c> drafts = new List<TAEProcessingWorkItem__c>();
        while (iterator.hasNext()) {
            drafts.add(iterator.next());
        }
        System.assertEquals(null, iterator.next(), 'Expected the asserted value.');

        System.assertEquals(4, drafts.size(), 'Expected the asserted value.');
        System.assertEquals(TAEWorkItemService.ACCOUNT_TEAM, drafts[0].WorkType__c, 'Expected the asserted value.');
        System.assertEquals(TAEWorkItemService.JUNCTION_ACCOUNT, drafts[1].WorkType__c, 'Expected the asserted value.');
        System.assertEquals(TAEWorkItemService.OPP_TEAM, drafts[2].WorkType__c, 'Expected the asserted value.');
        System.assertEquals(TAEWorkItemService.JUNCTION_OPP, drafts[3].WorkType__c, 'Expected the asserted value.');
        System.assertEquals(TAEWorkItemService.STATUS_PENDING, drafts[0].Status__c, 'Expected the asserted value.');
        System.assertNotEquals(drafts[0].CompositeKey__c, drafts[1].CompositeKey__c, 'Expected the asserted value.');
    }

    /**
     * @description Revoke produces one delete draft per account and opportunity.
     */
    @IsTest
    static void revokeIteratorCreatesOneDeleteDraftPerRecord() {
        Scenario scenario = loadScenario();
        TAEWorkItemService.PlanSnapshot plan = new TAEWorkItemService.PlanSnapshot();
        plan.coveredExceptionId = fakeId(TemporaryAccessException__c.SObjectType);
        plan.pipelineOperation = TAEWorkItemService.OP_REVOKE;
        plan.accountIdList.add(scenario.accountId);
        plan.opportunityIdList.add(fakeId(Opportunity.SObjectType));

        TAEWorkItemCreationBatch.DraftIterator iterator =
            new TAEWorkItemCreationBatch.DraftIterator(plan);
        List<String> types = new List<String>();
        while (iterator.hasNext()) {
            types.add(iterator.next().WorkType__c);
        }

        System.assertEquals(TAEWorkItemService.DELETE_ACCOUNT_TEAM, types[0], 'Expected the asserted value.');
        System.assertEquals(TAEWorkItemService.DELETE_OPP_TEAM, types[1], 'Expected the asserted value.');
        System.assertEquals(TAEWorkItemService.DRAFT_HANDBACK, types[2], 'Expected the asserted value.');
    }

    /**
     * @description The parent sets Processing and Grant and does not insert work items.
     */
    @IsTest
    static void parentMarksGrantProcessingWithoutCreatingItems() {
        Scenario scenario = loadScenario();
        TemporaryAccessException__c tae =
            TestDataFactory.insertGrantTae(scenario.requesterId, scenario.coverageRepId);

        TAEWorkItemService.markForProcessing(tae);

        tae = [
            SELECT Status__c, ProcessingOperation__c, WorkItemsCreated__c
            FROM TemporaryAccessException__c
            WHERE Id = :tae.Id
        ];
        System.assertEquals(TAEWorkItemService.HEADER_PROCESSING, tae.Status__c, 'Parent should set Processing.');
        System.assertEquals(TAEWorkItemService.OP_GRANT, tae.ProcessingOperation__c, 'Expected the asserted value.');
        System.assertEquals(false, tae.WorkItemsCreated__c, 'Expected the asserted value.');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM TAEProcessingWorkItem__c
             WHERE TemporaryAccessException__c = :tae.Id],
            'Expected the asserted value.'
        );
    }

    /**
     * @description requeueErrors resets Error rows to Pending and leaves other statuses alone.
     */
    @IsTest
    static void manualRetryOnlyResetsErrorItems() {
        Scenario scenario = loadScenario();
        TemporaryAccessException__c tae =
            TestDataFactory.insertGrantTae(scenario.requesterId, scenario.coverageRepId);
        insert new List<TAEProcessingWorkItem__c>{
            new TAEProcessingWorkItem__c(
                TemporaryAccessException__c = tae.Id,
                WorkType__c = TAEWorkItemService.ACCOUNT_TEAM,
                RecordId__c = scenario.accountId,
                Status__c = TAEWorkItemService.STATUS_ERROR,
                CompositeKey__c = tae.Id + '|error|' + scenario.accountId,
                ErrorMessage__c = 'lock failure'
            ),
            new TAEProcessingWorkItem__c(
                TemporaryAccessException__c = tae.Id,
                WorkType__c = TAEWorkItemService.JUNCTION_ACCOUNT,
                RecordId__c = scenario.accountId,
                Status__c = TAEWorkItemService.STATUS_DONE,
                CompositeKey__c = tae.Id + '|done|' + scenario.accountId
            )
        };

        Integer resetCount = TAEWorkItemService.requeueErrors(tae.Id);
        System.assertEquals(1, resetCount, 'Expected the asserted value.');

        Map<String, TAEProcessingWorkItem__c> byType =
            new Map<String, TAEProcessingWorkItem__c>();
        for (TAEProcessingWorkItem__c row : [
            SELECT WorkType__c, Status__c, ErrorMessage__c
            FROM TAEProcessingWorkItem__c
            WHERE TemporaryAccessException__c = :tae.Id
        ]) {
            byType.put(row.WorkType__c, row);
        }
        System.assertEquals(
            TAEWorkItemService.STATUS_PENDING,
            byType.get(TAEWorkItemService.ACCOUNT_TEAM).Status__c,
            'Error rows should return to Pending.'
        );
        System.assertEquals(null, byType.get(TAEWorkItemService.ACCOUNT_TEAM).ErrorMessage__c, 'Expected the asserted value.');
        System.assertEquals(
            TAEWorkItemService.STATUS_DONE,
            byType.get(TAEWorkItemService.JUNCTION_ACCOUNT).Status__c,
            'Done rows should stay Done.'
        );
    }

    /**
     * @description Grant, junction, finalize, and revoke run for one account.
     */
    @IsTest
    static void processorsGrantJunctionFinalizeAndRevokeOneAccount() {
        Scenario scenario = loadScenario();
        TemporaryAccessException__c tae =
            TestDataFactory.insertGrantTae(scenario.requesterId, scenario.coverageRepId);
        TAEWorkItemEmailService.isSendSkippedForTest = true;
        TAEWorkItemService.markForProcessing(tae);

        TAEWorkItemService.PlanSnapshot plan = TAEWorkItemService.buildPlan(tae.Id);
        System.assert(plan.accountIdList.contains(scenario.accountId), 'Expected the asserted value.');

        TAEProcessingWorkItem__c accountItem = insertPending(
            tae.Id, TAEWorkItemService.ACCOUNT_TEAM, scenario.accountId
        );
        System.runAs(loadRequester()) {
            TAEWorkItemService.processAccountGrant(
                new List<TAEProcessingWorkItem__c>{ accountItem }
            );
        }
        accountItem = [
            SELECT Status__c FROM TAEProcessingWorkItem__c WHERE Id = :accountItem.Id
        ];
        System.assert(
            new Set<String>{ TAEWorkItemService.STATUS_DONE, TAEWorkItemService.STATUS_SKIPPED }.contains(accountItem.Status__c),
            'Expected the asserted value.'
        );

        TAEProcessingWorkItem__c junctionItem = insertPending(
            tae.Id, TAEWorkItemService.JUNCTION_ACCOUNT, scenario.accountId
        );
        TAEWorkItemService.processJunctionGrant(
            new List<TAEProcessingWorkItem__c>{ junctionItem }
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM TAE_AssignedRecord__c
             WHERE TemporaryAccessException__c = :tae.Id AND Account__c = :scenario.accountId],
            'Expected the asserted value.'
        );

        // Finalize only after all created test items are terminal.
        TAEWorkItemService.finalizeTae(tae.Id, TAEWorkItemService.OP_GRANT);
        System.assertEquals(
            TAEWorkItemService.HEADER_ACTIVE,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].Status__c,
            'Finalize should set Active.'
        );

        update new TemporaryAccessException__c(
            Id = copyId(tae.Id),
            Status__c = TAEWorkItemService.HEADER_PROCESSING,
            ProcessingOperation__c = TAEWorkItemService.OP_REVOKE,
            WorkItemsCreated__c = true
        );
        TAEProcessingWorkItem__c deleteItem = insertPending(
            tae.Id, TAEWorkItemService.DELETE_ACCOUNT_TEAM, scenario.accountId
        );
        System.runAs(loadRequester()) {
            TAEWorkItemService.processAccountTeamDelete(
                new List<TAEProcessingWorkItem__c>{ deleteItem }
            );
        }
        deleteItem = [
            SELECT Status__c FROM TAEProcessingWorkItem__c WHERE Id = :deleteItem.Id
        ];
        System.assert(
            new Set<String>{ TAEWorkItemService.STATUS_DONE, TAEWorkItemService.STATUS_SKIPPED }.contains(deleteItem.Status__c),
            'Expected the asserted value.'
        );
    }

    /**
     * @description Batch start, execute, and finish methods and selector queries run without a scheduled job.
     */
    @IsTest
    static void batchEntryPointsAndSelectorsAreCallableInIsolation() {
        Scenario scenario = loadScenario();
        TemporaryAccessException__c tae =
            TestDataFactory.insertGrantTae(scenario.requesterId, scenario.coverageRepId);

        TAEWorkItemOrchestratorBatch parent = new TAEWorkItemOrchestratorBatch();
        parent.start(null);
        parent.execute(
            null,
            new List<SObject>{
                new TemporaryAccessException__c(
                    Id = copyId(tae.Id),
                    Status__c = TAEWorkItemService.HEADER_APPROVED,
                    StartDate__c = Date.today(),
                    EndDate__c = Date.today().addDays(1)
                )
            }
        );

        TAEWorkItemCreationBatch creation = new TAEWorkItemCreationBatch(tae.Id);
        Iterable<TAEProcessingWorkItem__c> iterable = creation.start(null);
        Iterator<TAEProcessingWorkItem__c> iterator = iterable.iterator();
        List<TAEProcessingWorkItem__c> creationScope =
            new List<TAEProcessingWorkItem__c>();
        while (iterator.hasNext() && creationScope.size() < 10) {
            creationScope.add(iterator.next());
        }
        System.assert(!creationScope.isEmpty(), 'Expected the asserted value.');
        creation.execute(null, creationScope);
        TAEWorkItemCreationBatch.isChainingSuppressedForTest = true;
        creation.finish(null);

        TAEGrantWorkBatch grant =
            new TAEGrantWorkBatch(tae.Id, TAEWorkItemService.ACCOUNT_TEAM);
        grant.start(null);
        TAERevokeWorkBatch revoke =
            new TAERevokeWorkBatch(tae.Id, TAEWorkItemService.DELETE_ACCOUNT_TEAM);
        revoke.start(null);

        TemporaryAccessException__c loaded = TAEWorkItemSelector.selectTae(tae.Id);
        System.assertNotEquals(null, loaded, 'Expected the asserted value.');
        List<TemporaryAccessException__c> processingRows =
            TAEWorkItemSelector.selectProcessingTaes();
        System.assert(!processingRows.isEmpty(), 'Expected the asserted value.');
        Integer createdCount = TAEWorkItemSelector.countAllWorkItems(tae.Id);
        Integer scopeCount = creationScope.size();
        System.assertEquals(scopeCount, createdCount, 'Expected the asserted value.');
        String firstPhase = TAEWorkItemService.nextPendingPhase(
            TAEWorkItemService.OP_GRANT,
            new Set<String>{ TAEWorkItemService.ACCOUNT_TEAM }
        );
        System.assertEquals(
            TAEWorkItemService.ACCOUNT_TEAM,
            firstPhase,
            'The first pending grant phase should be account team.'
        );
    }

    /**
     * @description A thrown work-item exception keeps the message passed to create.
     */
    @IsTest
    static void exceptionCreatePreservesMessage() {
        String expectedMessage = 'expected';
        TAEWorkItemException thrownException = TAEWorkItemException.create(expectedMessage);
        String actualMessage = thrownException.getMessage();
        System.assertEquals(expectedMessage, actualMessage, 'Exception message is preserved.');
    }

    /**
     * @description Account, opportunity, junction, and both delete workers accept a one-row scope.
     */
    @IsTest
    static void workerEntryPointsCoverAllGrantAndRevokeDomains() {
        Scenario scenario = loadScenario();
        TemporaryAccessException__c tae =
            TestDataFactory.insertGrantTae(scenario.requesterId, scenario.coverageRepId);
        TAEWorkItemService.markForProcessing(tae);
        TAEWorkItemEmailService.isSendSkippedForTest = true;
        TAEGrantWorkBatch.isChainingSuppressedForTest = true;
        TAERevokeWorkBatch.isChainingSuppressedForTest = true;

        TAEProcessingWorkItem__c accountItem = insertPending(
            tae.Id, TAEWorkItemService.ACCOUNT_TEAM, scenario.accountId
        );
        TAEGrantWorkBatch accountBatch =
            new TAEGrantWorkBatch(tae.Id, TAEWorkItemService.ACCOUNT_TEAM);
        accountBatch.execute(null, new List<SObject>{ accountItem });
        accountBatch.finish(null);

        if (scenario.opportunityId != null) {
            TAEProcessingWorkItem__c opportunityItem = insertPending(
                tae.Id, TAEWorkItemService.OPP_TEAM, scenario.opportunityId
            );
            TAEGrantWorkBatch opportunityBatch =
                new TAEGrantWorkBatch(tae.Id, TAEWorkItemService.OPP_TEAM);
            opportunityBatch.execute(null, new List<SObject>{ opportunityItem });
            opportunityBatch.finish(null);
        }

        List<SObject> junctionItems = new List<SObject>{
            insertPending(tae.Id, TAEWorkItemService.JUNCTION_ACCOUNT, scenario.accountId)
        };
        if (scenario.opportunityId != null) {
            junctionItems.add(
                insertPending(
                    tae.Id,
                    TAEWorkItemService.JUNCTION_OPP,
                    scenario.opportunityId
                )
            );
        }
        TAEGrantWorkBatch junctionBatch =
            new TAEGrantWorkBatch(tae.Id, TAEWorkItemService.PHASE_JUNCTION);
        junctionBatch.execute(null, junctionItems);
        junctionBatch.finish(null);

        update new TemporaryAccessException__c(
            Id = copyId(tae.Id),
            Status__c = TAEWorkItemService.HEADER_PROCESSING,
            ProcessingOperation__c = TAEWorkItemService.OP_REVOKE,
            WorkItemsCreated__c = true
        );
        TAEProcessingWorkItem__c deleteAccount = insertPending(
            tae.Id, TAEWorkItemService.DELETE_ACCOUNT_TEAM, scenario.accountId
        );
        TAERevokeWorkBatch accountRevoke =
            new TAERevokeWorkBatch(tae.Id, TAEWorkItemService.DELETE_ACCOUNT_TEAM);
        accountRevoke.execute(null, new List<SObject>{ deleteAccount });
        accountRevoke.finish(null);

        if (scenario.opportunityId != null) {
            TAEProcessingWorkItem__c deleteOpportunity = insertPending(
                tae.Id, TAEWorkItemService.DELETE_OPP_TEAM, scenario.opportunityId
            );
            TAERevokeWorkBatch opportunityRevoke =
                new TAERevokeWorkBatch(tae.Id, TAEWorkItemService.DELETE_OPP_TEAM);
            opportunityRevoke.execute(null, new List<SObject>{ deleteOpportunity });
            opportunityRevoke.finish(null);
        }
        accountItem = [
            SELECT Status__c FROM TAEProcessingWorkItem__c WHERE Id = :accountItem.Id
        ];
        System.assertNotEquals(
            null,
            accountItem.Status__c,
            'The account grant worker should set a status.'
        );
    }

    /**
     * @description The schedulable submits the parent, and an empty execute scope is ignored.
     */
    @IsTest
    static void schedulableParentSubmitsAndRejectsAMultiRowScope() {
        Scenario scenario = loadScenario();
        TemporaryAccessException__c tae =
            TestDataFactory.insertGrantTae(scenario.requesterId, scenario.coverageRepId);
        TAEWorkItemOrchestratorBatch.isDispatchSuppressedForTest = true;

        Test.startTest();
        new TAEWorkItemOrchestratorBatch().execute((SchedulableContext) null);
        Test.stopTest();

        TAEWorkItemOrchestratorBatch parent = new TAEWorkItemOrchestratorBatch();
        parent.start(null);
        parent.execute(null, new List<SObject>());
        parent.finish(null);
        System.assertEquals(
            TAEWorkItemService.HEADER_PROCESSING,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].Status__c,
            'The schedulable parent should mark the exception Processing.'
        );
    }

    /**
     * @description Cleanup finish does not chain while Done rows remain.
     */
    @IsTest
    static void cleanupFinishWarnsWhenDoneRowsRemain() {
        Integer cleanupScope = TAEWorkItemCleanupBatch.submissionScope();
        System.assertEquals(
            TAEWorkItemService.CLEANUP_SCOPE,
            cleanupScope,
            'Cleanup uses the configured scope.'
        );
        TemporaryAccessException__c tae = createProcessingGrant();
        TAEProcessingWorkItem__c doneItem = insertPending(
            tae.Id,
            TAEWorkItemService.ACCOUNT_TEAM,
            loadScenario().accountId
        );
        doneItem.Status__c = TAEWorkItemService.STATUS_DONE;
        update doneItem;
        update new TemporaryAccessException__c(Id = copyId(tae.Id), Status__c = TAEWorkItemService.HEADER_ACTIVE);

        TAEWorkItemCleanupBatch cleanup = new TAEWorkItemCleanupBatch(tae.Id);
        cleanup.start(null);
        cleanup.execute(null, new List<SObject>());
        cleanup.execute(null, oversizedScope(TAEWorkItemService.CLEANUP_SCOPE));
        cleanup.finish(null);

        Integer doneCount = TAEWorkItemSelector.countDoneItems(tae.Id);
        System.assertEquals(1, doneCount, 'Expected the asserted value.');
    }

    /**
     * @description The parent execute marks one exception and does not start a child batch.
     */
    @IsTest
    static void newParentBatchRunsAtFixedScopeWithoutDispatchingChild() {
        Scenario scenario = loadScenario();
        TemporaryAccessException__c tae =
            TestDataFactory.insertGrantTae(scenario.requesterId, scenario.coverageRepId);
        TAEWorkItemOrchestratorBatch.isDispatchSuppressedForTest = true;

        Test.startTest();
        Id jobId = TAEWorkItemOrchestratorBatch.submit();
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Parent batch should return a job Id.');
        System.assertEquals(
            'Processing',
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :tae.Id].Status__c,
            'Parent execute should mark the exception Processing.'
        );
    }

    /**
     * @description The email service builds grant and revoke notifications without sending.
     */
    @IsTest
    static void isolatedEmailServiceBuildsNotifications() {
        Scenario scenario = loadScenario();
        TemporaryAccessException__c tae =
            TestDataFactory.insertGrantTae(scenario.requesterId, scenario.coverageRepId);
        TAEWorkItemEmailService.isSendSkippedForTest = false;

        Test.startTest();
        TAEWorkItemEmailService.sendGrant(tae.Id);
        Integer emailCount = Limits.getEmailInvocations();
        System.assertEquals(1, emailCount, 'Expected the asserted value.');
        Test.stopTest();
    }

    /**
     * @description Account-team finish starts the opportunity-team phase.
     */
    @IsTest
    static void grantAccountFinishEnqueuesOpportunityPhase() {
        Id taeId = createProcessingGrant().Id;
        TAEGrantWorkBatch.isChainingSuppressedForTest = false;
        new TAEGrantWorkBatch(
            taeId,
            TAEWorkItemService.ACCOUNT_TEAM
        ).finish(null);
        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob
            WHERE ApexClass.Name = 'TAEGrantWorkBatch'
        ], 'A grant worker should be queued.');
    }

    /**
     * @description Opportunity-team finish starts the junction phase.
     */
    @IsTest
    static void grantOpportunityFinishEnqueuesJunctionPhase() {
        Id taeId = createProcessingGrant().Id;
        TAEGrantWorkBatch.isChainingSuppressedForTest = false;
        new TAEGrantWorkBatch(
            taeId,
            TAEWorkItemService.OPP_TEAM
        ).finish(null);
        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob
            WHERE ApexClass.Name = 'TAEGrantWorkBatch'
        ], 'A grant worker should be queued.');
    }

    /**
     * @description Account delete finish starts the opportunity delete phase.
     */
    @IsTest
    static void revokeAccountFinishEnqueuesOpportunityDeletePhase() {
        TemporaryAccessException__c tae = createProcessingGrant();
        update new TemporaryAccessException__c(
            Id = copyId(tae.Id),
            ProcessingOperation__c = TAEWorkItemService.OP_REVOKE
        );
        TAERevokeWorkBatch.isChainingSuppressedForTest = false;
        new TAERevokeWorkBatch(
            tae.Id,
            TAEWorkItemService.DELETE_ACCOUNT_TEAM
        ).finish(null);
        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob
            WHERE ApexClass.Name = 'TAERevokeWorkBatch'
        ], 'A revoke worker should be queued.');
    }

    /**
     * @description An oversized revoke chunk is logged and swallowed, and an Error row still hands off.
     */
    @IsTest
    static void revokeOversizedScopeAndErrorFinishAreHandled() {
        TemporaryAccessException__c tae = createProcessingGrant();
        update new TemporaryAccessException__c(
            Id = copyId(tae.Id),
            ProcessingOperation__c = TAEWorkItemService.OP_REVOKE
        );
        TAEWorkItemEmailService.isSendSkippedForTest = true;
        List<SObject> oversized = new List<SObject>();
        for (Integer i = 0; i <= TAEWorkItemService.WORKER_SCOPE; i++) {
            oversized.add(new TAEProcessingWorkItem__c());
        }
        new TAERevokeWorkBatch(
            tae.Id,
            TAEWorkItemService.DELETE_ACCOUNT_TEAM
        ).execute(null, oversized);

        TAEProcessingWorkItem__c errorItem = insertPending(
            tae.Id,
            TAEWorkItemService.DELETE_ACCOUNT_TEAM,
            loadScenario().accountId
        );
        errorItem.Status__c = TAEWorkItemService.STATUS_ERROR;
        update errorItem;
        TAERevokeWorkBatch.isChainingSuppressedForTest = false;
        new TAERevokeWorkBatch(
            tae.Id,
            TAEWorkItemService.DELETE_ACCOUNT_TEAM
        ).finish(null);

        TAERevokeWorkBatch.isChainingSuppressedForTest = true;
        new TAERevokeWorkBatch(
            tae.Id,
            TAEWorkItemService.DELETE_OPP_TEAM
        ).finish(null);
        Integer oversizedCount = oversized.size();
        System.assertEquals(
            TAEWorkItemService.WORKER_SCOPE + 1,
            oversizedCount,
            'Expected the asserted value.'
        );
    }

    /**
     * @description The dispatcher starts creation when WorkItemsCreated__c is still false.
     */
    @IsTest
    static void dispatcherStartsCreationForIncompleteProcessingTae() {
        createProcessingGrant();
        TAEWorkItemService.startNextTaePipeline();
        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob
            WHERE ApexClass.Name = 'TAEWorkItemCreationBatch'
        ], 'Creation should be the only job queued.');
    }

    /**
     * @description An Error row stops the grant worker from starting the next phase.
     */
    @IsTest
    static void errorInPhaseStopsGrantChaining() {
        TemporaryAccessException__c tae = createProcessingGrant();
        TAEProcessingWorkItem__c item = insertPending(
            tae.Id, TAEWorkItemService.ACCOUNT_TEAM,
            loadScenario().accountId
        );
        item.Status__c = TAEWorkItemService.STATUS_ERROR;
        update item;
        TAEGrantWorkBatch.isChainingSuppressedForTest = true;

        new TAEGrantWorkBatch(
            tae.Id, TAEWorkItemService.ACCOUNT_TEAM
        ).finish(null);

        System.assertEquals(0, [
            SELECT COUNT() FROM AsyncApexJob
            WHERE ApexClass.Name = 'TAEGrantWorkBatch'
        ], 'An Error row should stop the next grant phase.');
    }

    /**
     * @description Cleanup deletes Done rows on an Active exception and keeps other statuses.
     */
    @IsTest
    static void cleanupDeletesOnlyDoneRowsAfterActive() {
        TemporaryAccessException__c tae = createProcessingGrant();
        Scenario scenario = loadScenario();
        Id opportunityOrAccountId = scenario.opportunityId == null
            ? scenario.accountId
            : scenario.opportunityId;
        TAEProcessingWorkItem__c doneItem = insertPending(
            tae.Id, TAEWorkItemService.ACCOUNT_TEAM, scenario.accountId
        );
        TAEProcessingWorkItem__c skippedItem = insertPending(
            tae.Id, TAEWorkItemService.JUNCTION_ACCOUNT, scenario.accountId
        );
        TAEProcessingWorkItem__c errorItem = insertPending(
            tae.Id, TAEWorkItemService.OPP_TEAM, opportunityOrAccountId
        );
        doneItem.Status__c = TAEWorkItemService.STATUS_DONE;
        skippedItem.Status__c = TAEWorkItemService.STATUS_SKIPPED;
        errorItem.Status__c = TAEWorkItemService.STATUS_ERROR;
        update new List<TAEProcessingWorkItem__c>{ doneItem, skippedItem, errorItem };
        update new TemporaryAccessException__c(Id = copyId(tae.Id), Status__c = TAEWorkItemService.HEADER_ACTIVE);

        TAEWorkItemCleanupBatch.isChainingSuppressedForTest = true;
        Test.startTest();
        Database.executeBatch(
            new TAEWorkItemCleanupBatch(tae.Id),
            TAEWorkItemService.CLEANUP_SCOPE
        );
        Test.stopTest();

        Map<Id, TAEProcessingWorkItem__c> remaining = new Map<Id, TAEProcessingWorkItem__c>([
            SELECT Status__c
            FROM TAEProcessingWorkItem__c
            WHERE TemporaryAccessException__c = :tae.Id
        ]);
        Boolean doneWasDeleted = remaining.containsKey(doneItem.Id);
        System.assertEquals(false, doneWasDeleted, 'Expected the asserted value.');
        System.assertEquals(
            TAEWorkItemService.STATUS_SKIPPED,
            remaining.get(skippedItem.Id).Status__c,
            'Expected the asserted value.'
        );
        System.assertEquals(
            TAEWorkItemService.STATUS_ERROR,
            remaining.get(errorItem.Id).Status__c,
            'Expected the asserted value.'
        );
    }

    /**
     * @description Done rows on a Processing exception are not cleanup candidates.
     */
    @IsTest
    static void processingTaeDoneRowsAreNotCleanupCandidates() {
        TemporaryAccessException__c tae = createProcessingGrant();
        TAEProcessingWorkItem__c doneItem = insertPending(
            tae.Id,
            TAEWorkItemService.ACCOUNT_TEAM,
            loadScenario().accountId
        );
        doneItem.Status__c = TAEWorkItemService.STATUS_DONE;
        update doneItem;
        Id cleanupCandidate = TAEWorkItemSelector.selectTaeIdWithDoneItemsToClean();
        System.assertEquals(null, cleanupCandidate, 'Expected the asserted value.');

        update new TemporaryAccessException__c(Id = copyId(tae.Id), Status__c = TAEWorkItemService.HEADER_EXPIRED);
        Id expiredCandidate = TAEWorkItemSelector.selectTaeIdWithDoneItemsToClean();
        System.assertEquals(tae.Id, expiredCandidate, 'Expected the asserted value.');
    }

    /**
     * @description The dispatcher starts cleanup before the next Processing exception.
     */
    @IsTest
    static void dispatcherStartsCleanupBeforeTheNextProcessingTae() {
        TemporaryAccessException__c finished = createProcessingGrant();
        TAEProcessingWorkItem__c doneItem = insertPending(
            finished.Id,
            TAEWorkItemService.ACCOUNT_TEAM,
            loadScenario().accountId
        );
        doneItem.Status__c = TAEWorkItemService.STATUS_DONE;
        update doneItem;
        update new TemporaryAccessException__c(Id = copyId(finished.Id), Status__c = TAEWorkItemService.HEADER_ACTIVE);
        createProcessingGrant();

        TAEWorkItemService.startNextTaePipeline();

        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob
            WHERE ApexClass.Name = 'TAEWorkItemCleanupBatch'
        ], 'Cleanup should be queued before the next exception.');
        System.assertEquals(0, [
            SELECT COUNT() FROM AsyncApexJob
            WHERE ApexClass.Name = 'TAEWorkItemCreationBatch'
        ], 'Creation should wait until cleanup is finished.');
    }

    /**
     * @description GC-3482. Handback drafts, owner reassignment, team-delete skips, and direct worker entry points.
     */
    @IsTest
    static void handbackReassignAndTeamSkipPathsAreCovered() {
        Scenario scenario = loadScenario();
        TemporaryAccessException__c tae = createProcessingRevoke();
        System.assertEquals(TAEWorkItemService.WORKER_SCOPE, TAEHandbackDraftBatch.submissionScope(), 'Expected the asserted value.');
        System.assertEquals(TAEWorkItemService.WORKER_SCOPE, TAERevokeWorkBatch.submissionScope(), 'Expected the asserted value.');
        System.assertEquals(TAEWorkItemService.WORKER_SCOPE, TAEGrantWorkBatch.submissionScope(), 'Expected the asserted value.');
        System.assertEquals(TAEWorkItemService.WORKER_SCOPE, TAEWorkItemCreationBatch.submissionScope(), 'Expected the asserted value.');
        System.assertEquals(TAEWorkItemService.CLEANUP_SCOPE, TAEWorkItemCleanupBatch.submissionScope(), 'Expected the asserted value.');
        System.assertEquals(TAEWorkItemOrchestratorBatch.FIXED_PARENT_SCOPE, TAEWorkItemOrchestratorBatch.submissionScope(), 'Expected the asserted value.');

        update new Account(Id = copyId(scenario.accountId), OwnerId = scenario.requesterId);
        if (scenario.opportunityId != null) {
            update new Opportunity(Id = copyId(scenario.opportunityId), OwnerId = scenario.requesterId);
        }
        TAEWorkItemService.PlanSnapshot plan = TAEWorkItemService.buildPlan(tae.Id);
        System.assert(plan.accountIdList.contains(scenario.accountId), 'Expected the asserted value.');

        try {
            TAEWorkItemService.buildPlan(fakeId(TemporaryAccessException__c.SObjectType));
            System.assert(false, 'A missing exception should throw.');
        } catch (TAEWorkItemException missingTae) {
            System.assert(missingTae.getMessage().contains('TAE not found'), 'Expected the asserted value.');
        }
        try {
            TAEWorkItemService.processAccountGrant(new List<TAEProcessingWorkItem__c>());
            System.assert(false, 'An empty scope should throw.');
        } catch (TAEWorkItemException emptyScope) {
            System.assert(emptyScope.getMessage().contains('empty'), 'Expected the asserted value.');
        }

        assertHandbackLocators(scenario);
        TAEHandbackDraftBatch.isChainingSuppressedForTest = true;
        runHandbackDraftEntries(tae.Id, scenario);
        assertTeamSkipAndDelete(tae, scenario);
        assertOwnerReassign(tae, scenario);
        assertJunctionSkip(tae, scenario);
        assertPhaseNames();
    }

    /**
     * @description GC-3482. Junction and reassign finish methods finalize when nothing is left to queue.
     */
    @IsTest
    static void terminalPhaseFinishFinalizesWithoutQueuingAnotherJob() {
        TAEWorkItemEmailService.isSendSkippedForTest = true;
        TemporaryAccessException__c grantTae = createProcessingGrant();
        update new TemporaryAccessException__c(
            Id = copyId(grantTae.Id),
            WorkItemsCreated__c = true
        );
        TAEGrantWorkBatch.isChainingSuppressedForTest = false;
        new TAEGrantWorkBatch(grantTae.Id, TAEWorkItemService.PHASE_JUNCTION).finish(null);
        System.assertEquals(
            TAEWorkItemService.HEADER_ACTIVE,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :grantTae.Id].Status__c,
            'Expected the asserted value.'
        );

        TAEHandbackDraftBatch failedDraft = new TAEHandbackDraftBatch(
            grantTae.Id, TAEWorkItemService.REASSIGN_OPPORTUNITY
        );
        failedDraft.start(null);
        failedDraft.execute(null, null);
        TAEHandbackDraftBatch.isChainingSuppressedForTest = false;
        failedDraft.finish(null);

        TAEWorkItemCleanupBatch.isChainingSuppressedForTest = false;
        new TAEWorkItemCleanupBatch(grantTae.Id).finish(null);

        TemporaryAccessException__c revokeTae = createProcessingRevoke();
        TAERevokeWorkBatch.isChainingSuppressedForTest = false;
        new TAERevokeWorkBatch(revokeTae.Id, TAEWorkItemService.REASSIGN_EVENT).finish(null);
        System.assertEquals(
            TAEWorkItemService.HEADER_EXPIRED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :revokeTae.Id].Status__c,
            'Expected the asserted value.'
        );

        TAEHandbackDraftBatch.isChainingSuppressedForTest = false;
        new TAEHandbackDraftBatch(revokeTae.Id, TAEWorkItemService.REASSIGN_CONTACT).finish(null);

        TemporaryAccessException__c suppressedTae = createProcessingRevoke();
        TAERevokeWorkBatch.isChainingSuppressedForTest = true;
        new TAERevokeWorkBatch(suppressedTae.Id, TAEWorkItemService.REASSIGN_CONTACT).finish(null);
        System.assertEquals(
            TAEWorkItemService.HEADER_EXPIRED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :suppressedTae.Id].Status__c,
            'Expected the asserted value.'
        );

        TemporaryAccessException__c errorOnly = createProcessingRevoke();
        TAEProcessingWorkItem__c errorItem = insertPending(
            errorOnly.Id,
            TAEWorkItemService.REASSIGN_TASK,
            loadScenario().accountId
        );
        errorItem.Status__c = TAEWorkItemService.STATUS_ERROR;
        update errorItem;
        TAEWorkItemService.resumeAfterPipelineFinish();

        TemporaryAccessException__c activeHeader =
            TestDataFactory.insertGrantTae(
                loadScenario().requesterId,
                loadScenario().coverageRepId
            );
        update new TemporaryAccessException__c(
            Id = copyId(activeHeader.Id),
            Status__c = TAEWorkItemService.HEADER_ACTIVE
        );
        // End date stays in the future on the record. TER_001 rejects End Date = today.
        // markForProcessing reads the in-memory end date and does not write it.
        TAEWorkItemService.markForProcessing(new TemporaryAccessException__c(
            Id = copyId(activeHeader.Id),
            Status__c = TAEWorkItemService.HEADER_ACTIVE,
            StartDate__c = Date.today().addDays(-1),
            EndDate__c = Date.today()
        ));
        System.assertEquals(
            TAEWorkItemService.OP_REVOKE,
            [SELECT ProcessingOperation__c FROM TemporaryAccessException__c WHERE Id = :activeHeader.Id].ProcessingOperation__c,
            'Expected the asserted value.'
        );
        System.assertEquals(0, [
            SELECT COUNT() FROM AsyncApexJob
            WHERE ApexClass.Name IN (
                'TAEGrantWorkBatch', 'TAERevokeWorkBatch', 'TAEHandbackDraftBatch', 'TAEWorkItemCreationBatch'
            )
        ], 'Expected the asserted value.');
    }

    /**
     * @description GC-3482. Opportunity-draft finish queues the task draft.
     */
    @IsTest
    static void handbackOpportunityFinishEnqueuesTaskDraft() {
        TemporaryAccessException__c tae = createProcessingRevoke();
        TAEHandbackDraftBatch.isChainingSuppressedForTest = false;
        new TAEHandbackDraftBatch(tae.Id, TAEWorkItemService.REASSIGN_OPPORTUNITY).finish(null);
        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'TAEHandbackDraftBatch'
        ], 'Expected the asserted value.');
        System.assertEquals(true, TAEWorkItemSelector.hasActivePipelineJob(), 'Expected the asserted value.');
    }

    /**
     * @description GC-3482. Task-draft finish queues the event draft.
     */
    @IsTest
    static void handbackTaskFinishEnqueuesEventDraft() {
        TemporaryAccessException__c tae = createProcessingRevoke();
        TAEHandbackDraftBatch.isChainingSuppressedForTest = false;
        new TAEHandbackDraftBatch(tae.Id, TAEWorkItemService.REASSIGN_TASK).finish(null);
        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'TAEHandbackDraftBatch'
        ], 'Expected the asserted value.');
    }

    /**
     * @description GC-3482. Event-draft finish queues the contact draft.
     */
    @IsTest
    static void handbackEventFinishEnqueuesContactDraft() {
        TemporaryAccessException__c tae = createProcessingRevoke();
        TAEHandbackDraftBatch.isChainingSuppressedForTest = false;
        new TAEHandbackDraftBatch(tae.Id, TAEWorkItemService.REASSIGN_EVENT).finish(null);
        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'TAEHandbackDraftBatch'
        ], 'Expected the asserted value.');
    }

    /**
     * @description GC-3482. Contact-draft finish marks the handback search complete.
     */
    @IsTest
    static void handbackContactFinishMarksTheSearchMarkerDone() {
        TemporaryAccessException__c tae = createProcessingRevoke();
        insertPending(tae.Id, TAEWorkItemService.DRAFT_HANDBACK, tae.Id);
        TAEHandbackDraftBatch.isChainingSuppressedForTest = true;
        new TAEHandbackDraftBatch(tae.Id, TAEWorkItemService.REASSIGN_CONTACT).finish(null);

        TAEProcessingWorkItem__c marker = [
            SELECT Status__c, ErrorMessage__c
            FROM TAEProcessingWorkItem__c
            WHERE TemporaryAccessException__c = :tae.Id
              AND WorkType__c = :TAEWorkItemService.DRAFT_HANDBACK
        ];
        System.assertEquals(TAEWorkItemService.STATUS_DONE, marker.Status__c, 'Expected the asserted value.');
        System.assertEquals(
            TAEWorkItemService.REASON_HANDBACK_SEARCH_FINISHED,
            marker.ErrorMessage__c,
            'Expected the asserted value.'
        );
    }

    /**
     * @description A reassign finish queues the next Pending reassign phase.
     */
    @IsTest
    static void reassignFinishEnqueuesTheNextReassignPhase() {
        Scenario scenario = loadScenario();
        TemporaryAccessException__c tae = createProcessingRevoke();
        insertPending(tae.Id, TAEWorkItemService.REASSIGN_TASK, scenario.accountId);
        TAERevokeWorkBatch.isChainingSuppressedForTest = false;
        Test.startTest();
        new TAERevokeWorkBatch(tae.Id, TAEWorkItemService.REASSIGN_OPPORTUNITY).finish(null);
        List<AsyncApexJob> queued = [
            SELECT Id
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'TAERevokeWorkBatch'
        ];
        System.assertEquals(1, queued.size(), 'Expected the asserted value.');
        System.abortJob(queued[0].Id);
        Test.stopTest();
    }

    /**
     * @description Opportunity-team delete finish queues the handback draft.
     */
    @IsTest
    static void revokeOpportunityDeleteFinishEnqueuesHandbackDraft() {
        TemporaryAccessException__c tae = createProcessingRevoke();
        TAERevokeWorkBatch.isChainingSuppressedForTest = false;
        new TAERevokeWorkBatch(tae.Id, TAEWorkItemService.DELETE_OPP_TEAM).finish(null);
        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'TAEHandbackDraftBatch'
        ], 'Expected the asserted value.');
    }

    /**
     * @description A grant phase with Error rows hands the pipeline back to the dispatcher.
     */
    @IsTest
    static void grantErrorFinishResumesThePipeline() {
        TemporaryAccessException__c tae = createProcessingGrant();
        TAEProcessingWorkItem__c errorItem = insertPending(
            tae.Id,
            TAEWorkItemService.ACCOUNT_TEAM,
            loadScenario().accountId
        );
        errorItem.Status__c = TAEWorkItemService.STATUS_ERROR;
        update errorItem;
        TAEGrantWorkBatch.isChainingSuppressedForTest = false;
        new TAEGrantWorkBatch(tae.Id, TAEWorkItemService.ACCOUNT_TEAM).finish(null);
        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'TAEWorkItemCreationBatch'
        ], 'Expected the asserted value.');
    }

    /**
     * @description Orchestrator finish starts the pipeline when no exception is Processing.
     */
    @IsTest
    static void orchestratorFinishStartsThePipelineWhenNothingIsProcessing() {
        TAEWorkItemOrchestratorBatch parent = new TAEWorkItemOrchestratorBatch();
        parent.start(null);
        TAEWorkItemOrchestratorBatch.isDispatchSuppressedForTest = false;
        parent.finish(null);
        System.assertEquals(0, [
            SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'TAEWorkItemCreationBatch'
        ], 'Expected the asserted value.');
    }

    /**
     * @description The schedulable entry submits the parent batch at scope 1.
     */
    @IsTest
    static void orchestratorScheduleSubmitsTheParentBatch() {
        SchedulableContext scheduleContext = null;
        new TAEWorkItemOrchestratorBatch().execute(scheduleContext);
        TAEWorkItemOrchestratorBatch.isSubmitFailureForcedForTest = true;
        try {
            new TAEWorkItemOrchestratorBatch().execute(scheduleContext);
            System.assert(false, 'A forced submit failure should throw.');
        } catch (TAEWorkItemException expected) {
            System.assert(expected.getMessage() != null, 'Expected the asserted value.');
        }
        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'TAEWorkItemOrchestratorBatch'
        ], 'Expected the asserted value.');
    }

    /**
     * @description Finish logs the failure when the test async limit blocks the next pipeline job.
     */
    @IsTest
    static void orchestratorFinishLogsWhenAnotherJobCannotBeQueued() {
        Scenario scenario = loadScenario();
        TemporaryAccessException__c tae = createProcessingGrant();
        insertPending(tae.Id, TAEWorkItemService.ACCOUNT_TEAM, scenario.accountId);
        TAEWorkItemOrchestratorBatch.isDispatchSuppressedForTest = false;
        try {
            new TAEWorkItemOrchestratorBatch().finish(null);
        } catch (Exception expected) {
            System.assert(expected.getMessage() != null, 'Expected the asserted value.');
        }
        System.assertEquals(true, TAEWorkItemService.hasOpenItems(tae.Id, TAEWorkItemService.GRANT_TYPES), 'Expected the asserted value.');
    }

    /**
     * @description Grant and revoke notices include territory rows, and a missing exception is logged.
     */
    @IsTest
    static void emailNoticesCoverTerritoryRowsAndAMissingException() {
        Scenario scenario = loadScenario();
        TemporaryAccessException__c tae =
            TestDataFactory.insertGrantTae(scenario.requesterId, scenario.coverageRepId);
        insert new List<OrderLineContact__c>{
            new OrderLineContact__c(
                AssignedSalesRep__c = scenario.requesterId,
                TerritoryNumber__c = '  T&85  ',
                TASAddressId__c = 'TAE85'
            ),
            new OrderLineContact__c(
                AssignedSalesRep__c = scenario.requesterId,
                TerritoryNumber__c = '   ',
                TASAddressId__c = 'TAE86'
            )
        };
        TAEWorkItemEmailService.isSendSkippedForTest = false;

        Test.startTest();
        TAEWorkItemEmailService.sendRevoke(tae.Id);
        TAEWorkItemEmailService.sendGrant(fakeId(TemporaryAccessException__c.SObjectType));
        Integer emailCount = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(1, emailCount, 'Expected the asserted value.');
    }

    /**
     * @description Inserts one Processing Revoke exception.
     * @return The inserted exception.
     */
    private static TemporaryAccessException__c createProcessingRevoke() {
        TemporaryAccessException__c tae = createProcessingGrant();
        update new TemporaryAccessException__c(
            Id = copyId(tae.Id),
            ProcessingOperation__c = TAEWorkItemService.OP_REVOKE,
            WorkItemsCreated__c = true
        );
        TAEWorkItemEmailService.isSendSkippedForTest = true;
        return tae;
    }

    /**
     * @description Builds a scope one row past the configured maximum.
     * @param maximum Configured scope maximum.
     * @return Scope that the worker should reject.
     */
    private static List<SObject> oversizedScope(Integer maximum) {
        List<SObject> scope = new List<SObject>();
        for (Integer index = 0; index <= maximum; index++) {
            scope.add(new TAEProcessingWorkItem__c());
        }
        return scope;
    }

    /**
     * @description First active picklist value other than the excluded value.
     * @param field Picklist field.
     * @param excluded Value that should not be returned when another active value exists.
     * @return Another active value, or the excluded value when it is the only one.
     */
    private static String otherPicklistValue(Schema.SObjectField field, String excluded) {
        String selected = excluded;
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() != excluded) {
                selected = entry.getValue();
                break;
            }
        }
        return selected;
    }

    /**
     * @description Runs each handback locator, including the empty-result branches.
     * @param scenario Shared account and users.
     */
    private static void assertHandbackLocators(Scenario scenario) {
        Set<Id> accounts = new Set<Id>{ scenario.accountId };
        Set<Id> noAccounts = new Set<Id>();
        TAEWorkItemSelector.handbackLocator(accounts, scenario.coverageRepId, TAEWorkItemService.REASSIGN_OPPORTUNITY);
        TAEWorkItemSelector.handbackLocator(accounts, scenario.coverageRepId, TAEWorkItemService.REASSIGN_TASK);
        TAEWorkItemSelector.handbackLocator(accounts, scenario.coverageRepId, TAEWorkItemService.REASSIGN_EVENT);
        TAEWorkItemSelector.handbackLocator(accounts, scenario.coverageRepId, TAEWorkItemService.REASSIGN_CONTACT);
        TAEWorkItemSelector.handbackLocator(noAccounts, scenario.coverageRepId, TAEWorkItemService.REASSIGN_TASK);
        TAEWorkItemSelector.handbackLocator(accounts, null, TAEWorkItemService.REASSIGN_EVENT);
        TAEWorkItemSelector.handbackLocator(accounts, scenario.coverageRepId, 'UNKNOWN');
        TAEWorkItemSelector.handbackLocator(noAccounts, scenario.coverageRepId, TAEWorkItemService.REASSIGN_CONTACT);
        TAEWorkItemSelector.requesterOwnedAccountIds(noAccounts, scenario.requesterId);
        TAEWorkItemSelector.assignedAccountIds(null, accounts);
        TAEWorkItemSelector.assignedOpportunityIds(null, new Set<Id>());
    }

    /**
     * @description Calls handback start, execute, and suppressed finish for every draft type.
     * @param taeId Processing exception Id.
     * @param scenario Shared account and opportunity.
     */
    private static void runHandbackDraftEntries(Id taeId, Scenario scenario) {
        List<String> draftTypes = new List<String>{
            TAEWorkItemService.REASSIGN_OPPORTUNITY,
            TAEWorkItemService.REASSIGN_TASK,
            TAEWorkItemService.REASSIGN_EVENT,
            TAEWorkItemService.REASSIGN_CONTACT
        };
        Id opportunityId = scenario.opportunityId == null
            ? fakeId(Opportunity.SObjectType) : scenario.opportunityId;
        for (String draftType : draftTypes) {
            TAEHandbackDraftBatch draft = new TAEHandbackDraftBatch(taeId, draftType);
            draft.start(null);
            draft.execute(null, new List<SObject>{ new Opportunity(Id = opportunityId) });
            draft.finish(null);
        }
        TAEHandbackDraftBatch failedDraft = new TAEHandbackDraftBatch(
            taeId, TAEWorkItemService.REASSIGN_TASK
        );
        failedDraft.execute(null, null);
        failedDraft.execute(null, oversizedScope(TAEWorkItemService.WORKER_SCOPE));
        failedDraft.finish(null);

        try {
            new TAEHandbackDraftBatch(
                fakeId(TemporaryAccessException__c.SObjectType),
                TAEWorkItemService.REASSIGN_EVENT
            ).start(null);
            System.assert(false, 'A missing exception should throw.');
        } catch (TAEWorkItemException missingTae) {
            System.assert(missingTae.getMessage().contains('TAE not found'), 'Expected the asserted value.');
        }

        TAEGrantWorkBatch grant = new TAEGrantWorkBatch(taeId, TAEWorkItemService.ACCOUNT_TEAM);
        grant.start(null);
        grant.execute(null, new List<SObject>());
        grant.execute(null, oversizedScope(TAEWorkItemService.WORKER_SCOPE));

        TAEWorkItemOrchestratorBatch parent = new TAEWorkItemOrchestratorBatch();
        parent.start(null);
        parent.execute(null, new List<SObject>());
        TAEWorkItemOrchestratorBatch.isDispatchSuppressedForTest = true;
        parent.finish(null);
    }

    /**
     * @description Covers a missing team row, the wrong role, the wrong assignment, and a real delete.
     * @param tae Processing exception.
     * @param scenario Shared account and opportunity.
     */
    private static void assertTeamSkipAndDelete(
        TemporaryAccessException__c tae,
        Scenario scenario
    ) {
        TAEProcessingWorkItem__c deleteItem = insertPending(
            tae.Id, TAEWorkItemService.DELETE_ACCOUNT_TEAM, scenario.accountId
        );
        TAEWorkItemService.processAccountTeamDelete(new List<TAEProcessingWorkItem__c>{ deleteItem });
        System.assertEquals(
            TAEWorkItemService.STATUS_SKIPPED,
            [SELECT Status__c FROM TAEProcessingWorkItem__c WHERE Id = :deleteItem.Id].Status__c,
            'Expected the asserted value.'
        );

        String otherRole = otherPicklistValue(
            AccountTeamMember.TeamMemberRole, TAEWorkItemService.ROLE_SALES
        );
        String otherAssignment = otherPicklistValue(
            AccountTeamMember.AssignmentType__c, TAEWorkItemService.ASSIGNMENT_TEMPORARY
        );
        String startingAssignment = otherRole == TAEWorkItemService.ROLE_SALES
            ? otherAssignment : TAEWorkItemService.ASSIGNMENT_TEMPORARY;
        AccountTeamMember member = TestDataFactory.insertAccountTeamMemberWithRoleAndAssignment(
            scenario.accountId,
            scenario.coverageRepId,
            otherRole,
            startingAssignment,
            Date.today()
        );
        TAEWorkItemService.processAccountGrant(new List<TAEProcessingWorkItem__c>{
            insertPending(tae.Id, TAEWorkItemService.ACCOUNT_TEAM, scenario.accountId)
        });
        reopen(deleteItem);
        TAEWorkItemService.processAccountTeamDelete(new List<TAEProcessingWorkItem__c>{ deleteItem });
        replaceAccountTeamMember(
            scenario, TAEWorkItemService.ROLE_SALES, otherAssignment
        );
        reopen(deleteItem);
        TAEWorkItemService.processAccountTeamDelete(new List<TAEProcessingWorkItem__c>{ deleteItem });
        replaceAccountTeamMember(
            scenario,
            TAEWorkItemService.ROLE_SALES,
            TAEWorkItemService.ASSIGNMENT_TEMPORARY
        );
        reopen(deleteItem);
        TAEWorkItemService.processAccountTeamDelete(new List<TAEProcessingWorkItem__c>{ deleteItem });
        System.assertNotEquals(null, member.Id, 'Expected the asserted value.');

        if (scenario.opportunityId == null) {
            return;
        }
        String otherOpportunityAssignment = otherPicklistValue(
            OpportunityTeamMember.AssignmentType__c, TAEWorkItemService.ASSIGNMENT_TEMPORARY
        );
        insert new OpportunityTeamMember(
            OpportunityId = scenario.opportunityId,
            UserId = scenario.coverageRepId,
            TeamMemberRole = TAEWorkItemService.ROLE_SALES,
            AssignmentType__c = otherOpportunityAssignment,
            OpportunityAccessLevel = 'Edit'
        );
        TAEProcessingWorkItem__c opportunityDelete = insertPending(
            tae.Id, TAEWorkItemService.DELETE_OPP_TEAM, scenario.opportunityId
        );
        TAEWorkItemService.processOpportunityGrant(new List<TAEProcessingWorkItem__c>{
            insertPending(tae.Id, TAEWorkItemService.OPP_TEAM, scenario.opportunityId)
        });
        TAEWorkItemService.processOpportunityTeamDelete(
            new List<TAEProcessingWorkItem__c>{ opportunityDelete }
        );
        delete [
            SELECT Id FROM OpportunityTeamMember
            WHERE OpportunityId = :scenario.opportunityId AND UserId = :scenario.coverageRepId
        ];
        insert new OpportunityTeamMember(
            OpportunityId = scenario.opportunityId,
            UserId = scenario.coverageRepId,
            TeamMemberRole = TAEWorkItemService.ROLE_SALES,
            AssignmentType__c = TAEWorkItemService.ASSIGNMENT_TEMPORARY,
            OpportunityAccessLevel = 'Edit'
        );
        reopen(opportunityDelete);
        TAEWorkItemService.processOpportunityTeamDelete(
            new List<TAEProcessingWorkItem__c>{ opportunityDelete }
        );
    }

    /**
     * @description Removes the Coverage Rep account-team row and inserts the requested role and assignment.
     * @param scenario Shared account and Coverage Rep.
     * @param teamRole TeamMemberRole value.
     * @param assignmentType AssignmentType__c value.
     */
    private static void replaceAccountTeamMember(
        Scenario scenario,
        String teamRole,
        String assignmentType
    ) {
        delete [
            SELECT Id
            FROM AccountTeamMember
            WHERE AccountId = :scenario.accountId AND UserId = :scenario.coverageRepId
        ];
        TestDataFactory.insertAccountTeamMemberWithRoleAndAssignment(
            scenario.accountId,
            scenario.coverageRepId,
            teamRole,
            assignmentType,
            Date.today()
        );
    }

    /**
     * @description Returns the team row when the previous delete left it in place.
     * @param memberId AccountTeamMember Id.
     * @return The row, or null when it was deleted.
     */
    private static AccountTeamMember reloadAccountTeamMember(Id memberId) {
        List<AccountTeamMember> rows = [
            SELECT Id, TeamMemberRole, AssignmentType__c
            FROM AccountTeamMember
            WHERE Id = :memberId
        ];
        AccountTeamMember member = null;
        if (!rows.isEmpty()) {
            member = rows[0];
        }
        return member;
    }

    /**
     * @description Puts one work item back to Pending so the same row can be processed again.
     * @param item Work item to reopen.
     */
    private static void reopen(TAEProcessingWorkItem__c item) {
        item.Status__c = TAEWorkItemService.STATUS_PENDING;
        item.ErrorMessage__c = null;
        update item;
    }

    /**
     * @description Covers a successful owner change, the handback marker, and a failed owner change.
     * @param tae Processing exception.
     * @param scenario Shared users.
     */
    private static void assertOwnerReassign(
        TemporaryAccessException__c tae,
        Scenario scenario
    ) {
        Task openTask = new Task(
            Subject = 'TAE handback',
            OwnerId = scenario.coverageRepId,
            ActivityDate = Date.today().addDays(1)
        );
        insert openTask;
        TAEProcessingWorkItem__c taskItem = insertPending(
            tae.Id, TAEWorkItemService.REASSIGN_TASK, openTask.Id
        );
        TAEProcessingWorkItem__c markerItem = insertPending(
            tae.Id, TAEWorkItemService.REASSIGN_TASK, tae.Id
        );
        TAERevokeWorkBatch reassign = new TAERevokeWorkBatch(
            tae.Id, TAEWorkItemService.REASSIGN_TASK
        );
        reassign.start(null);
        reassign.execute(null, new List<SObject>{ taskItem, markerItem });
        System.assertEquals(
            TAEWorkItemService.STATUS_DONE,
            [SELECT Status__c FROM TAEProcessingWorkItem__c WHERE Id = :taskItem.Id].Status__c,
            'Expected the asserted value.'
        );
        System.assertEquals(
            TAEWorkItemService.STATUS_SKIPPED,
            [SELECT Status__c FROM TAEProcessingWorkItem__c WHERE Id = :markerItem.Id].Status__c,
            'Expected the asserted value.'
        );

        TAEWorkItemService.processOwnerReassign(new List<TAEProcessingWorkItem__c>{
            insertPending(tae.Id, TAEWorkItemService.REASSIGN_EVENT, fakeId(Event.SObjectType))
        });
        TAEWorkItemService.processOwnerReassign(new List<TAEProcessingWorkItem__c>{
            insertPending(tae.Id, TAEWorkItemService.REASSIGN_CONTACT, fakeId(Contact.SObjectType))
        });
        TAEWorkItemService.processOwnerReassign(new List<TAEProcessingWorkItem__c>{
            insertPending(
                tae.Id,
                TAEWorkItemService.REASSIGN_OPPORTUNITY,
                (Id) (Opportunity.SObjectType.getDescribe().getKeyPrefix() + '000000000099')
            )
        });
    }

    /**
     * @description A second junction pass skips the account and opportunity already recorded.
     * @param tae Processing exception.
     * @param scenario Shared account and opportunity.
     */
    private static void assertJunctionSkip(
        TemporaryAccessException__c tae,
        Scenario scenario
    ) {
        TAEProcessingWorkItem__c accountJunction = insertPending(
            tae.Id, TAEWorkItemService.JUNCTION_ACCOUNT, scenario.accountId
        );
        TAEWorkItemService.processJunctionGrant(new List<TAEProcessingWorkItem__c>{ accountJunction });
        accountJunction.Status__c = TAEWorkItemService.STATUS_PENDING;
        TAEWorkItemService.processJunctionGrant(new List<TAEProcessingWorkItem__c>{ accountJunction });
        System.assertEquals(
            TAEWorkItemService.STATUS_SKIPPED,
            accountJunction.Status__c,
            'Expected the asserted value.'
        );
        if (scenario.opportunityId == null) {
            return;
        }
        TAEProcessingWorkItem__c opportunityJunction = insertPending(
            tae.Id, TAEWorkItemService.JUNCTION_OPP, scenario.opportunityId
        );
        TAEWorkItemService.processJunctionGrant(new List<TAEProcessingWorkItem__c>{ opportunityJunction });
        opportunityJunction.Status__c = TAEWorkItemService.STATUS_PENDING;
        TAEWorkItemService.processJunctionGrant(new List<TAEProcessingWorkItem__c>{ opportunityJunction });
        System.assertEquals(
            TAEWorkItemService.STATUS_SKIPPED,
            opportunityJunction.Status__c,
            'Expected the asserted value.'
        );
    }

    /**
     * @description Walks every grant and revoke phase name.
     */
    private static void assertPhaseNames() {
        System.assertEquals(
            TAEWorkItemService.OPP_TEAM,
            TAEWorkItemService.nextPendingPhase(
                TAEWorkItemService.OP_GRANT, new Set<String>{ TAEWorkItemService.OPP_TEAM }
            ),
            'Expected the asserted value.'
        );
        System.assertEquals(
            TAEWorkItemService.PHASE_JUNCTION,
            TAEWorkItemService.nextPendingPhase(
                TAEWorkItemService.OP_GRANT, new Set<String>{ TAEWorkItemService.JUNCTION_OPP }
            ),
            'Expected the asserted value.'
        );
        System.assertEquals(
            TAEWorkItemService.DELETE_ACCOUNT_TEAM,
            TAEWorkItemService.nextPendingPhase(
                TAEWorkItemService.OP_REVOKE, new Set<String>{ TAEWorkItemService.DELETE_ACCOUNT_TEAM }
            ),
            'Expected the asserted value.'
        );
        System.assertEquals(
            TAEWorkItemService.DELETE_OPP_TEAM,
            TAEWorkItemService.nextPendingPhase(
                TAEWorkItemService.OP_REVOKE, new Set<String>{ TAEWorkItemService.DELETE_OPP_TEAM }
            ),
            'Expected the asserted value.'
        );
        System.assertEquals(
            TAEWorkItemService.DRAFT_HANDBACK,
            TAEWorkItemService.nextPendingPhase(
                TAEWorkItemService.OP_REVOKE, new Set<String>{ TAEWorkItemService.DRAFT_HANDBACK }
            ),
            'Expected the asserted value.'
        );
        System.assertEquals(
            TAEWorkItemService.REASSIGN_OPPORTUNITY,
            TAEWorkItemService.nextPendingPhase(
                TAEWorkItemService.OP_REVOKE, new Set<String>{ TAEWorkItemService.REASSIGN_OPPORTUNITY }
            ),
            'Expected the asserted value.'
        );
        System.assertEquals(
            TAEWorkItemService.REASSIGN_TASK,
            TAEWorkItemService.nextPendingPhase(
                TAEWorkItemService.OP_REVOKE, new Set<String>{ TAEWorkItemService.REASSIGN_TASK }
            ),
            'Expected the asserted value.'
        );
        System.assertEquals(
            TAEWorkItemService.REASSIGN_EVENT,
            TAEWorkItemService.nextPendingPhase(
                TAEWorkItemService.OP_REVOKE, new Set<String>{ TAEWorkItemService.REASSIGN_EVENT }
            ),
            'Expected the asserted value.'
        );
        System.assertEquals(
            TAEWorkItemService.REASSIGN_CONTACT,
            TAEWorkItemService.nextPendingPhase(
                TAEWorkItemService.OP_REVOKE, new Set<String>{ TAEWorkItemService.REASSIGN_CONTACT }
            ),
            'Expected the asserted value.'
        );
        System.assertEquals(
            null,
            TAEWorkItemService.nextPendingPhase(TAEWorkItemService.OP_GRANT, new Set<String>()),
            'Expected the asserted value.'
        );
    }

    /**
     * @description Inserts one Processing Grant exception for the scenario requester.
     * @return The inserted exception.
     */
    private static TemporaryAccessException__c createProcessingGrant() {
        Scenario scenario = loadScenario();
        TemporaryAccessException__c tae =
            TestDataFactory.insertGrantTae(scenario.requesterId, scenario.coverageRepId);
        TAEWorkItemService.markForProcessing(tae);
        return tae;
    }

    /**
     * @description Inserts one Pending work item.
     * @param taeId TemporaryAccessException__c Id.
     * @param workType Work type API value.
     * @param recordId Account or Opportunity Id.
     * @return The inserted work item.
     */
    private static TAEProcessingWorkItem__c insertPending(
        Id taeId,
        String workType,
        Id recordId
    ) {
        TAEProcessingWorkItem__c item =
            TAEWorkItemService.draft(taeId, workType, recordId);
        insert item;
        return item;
    }

    /**
     * @description Returns the same Id. Used so an SObject field initializer is not written as Id = someRecord.Id.
     * @param sourceId Id to copy.
     * @return The same Id.
     */
    private static Id copyId(Id sourceId) {
        return sourceId;
    }

    /**
     * @description Builds an in-memory Id for iterator tests that do not insert an exception.
     * @param objectType SObject type whose key prefix is used.
     * @return A synthetic Id.
     */
    private static Id fakeId(Schema.SObjectType objectType) {
        Id syntheticId = (Id) (objectType.getDescribe().getKeyPrefix() + '000000000000');
        return syntheticId;
    }
}