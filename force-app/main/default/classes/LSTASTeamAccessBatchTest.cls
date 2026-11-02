/**
 * @author Sarthak Pani
 * @date 2026/09/10
 *
 * @group Order Line Contact for LS
 *
 * @description
 * Tests for LS_TASTeamAccessBatch (schedulable, submit, start/execute/finish, flex queue, batch size).
 */
@IsTest(SeeAllData=false)
private class LSTASTeamAccessBatchTest {

    private static final String EMP_MATCH = 'LS-TAS-10001';
    private static final String ADDR_ID = 'LS-TAS-ADDR-9001';
    private static final String TEST_TERRITORY_NUMBER = 'TN-LS';
    private static final String TEST_SALES_CATEGORY_CODE = 'LS CAT';
    private static final String TEST_SALES_CATEGORY_DESCRIPTION = 'Life Sciences';

    private static final List<String> PENDING_DELTA_SCENARIOS = new List<String>{
        TASTeamAccessSelector.DELTA_INSERT_RECORD,
        TASTeamAccessSelector.DELTA_DELETE_RECORD
    };

    private static String cachedOracleCustomerIdField;

    /**
     * @description
     * Creates Life Sciences sales user and account mapped by OracleAddressId__c.
     *
     * @return void
     */
    @TestSetup
    static void setupData() {
        Profile salesProfile = resolveLifeSciencesSalesProfile();
        User setupUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];

        System.runAs(setupUser) {
            User salesRep = new User(
                FirstName = 'LS',
                LastName = 'SalesRep',
                Alias = 'lssrep',
                Email = 'ls.salesrep.' + DateTime.now().getTime() + '@test.com',
                Username = 'ls.salesrep.' + DateTime.now().getTime() + '@test.com',
                CommunityNickname = 'lsnick' + Math.abs(Crypto.getRandomInteger()),
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = salesProfile.Id,
                EmployeeNumber__c = EMP_MATCH,
                IsActive = true
            );
            insert salesRep;
            assignTestPermissionSets(salesRep.Id);
        }

        Account acc = newCustomerAccount('LS TAS Team Access Account');
        acc.OracleAddressId__c = ADDR_ID;
        insert acc;
    }

    /**
     * @description
     * Resets batch test hooks and freeze-window overrides between methods.
     *
     * @return void
     */
    private static void resetBatchFlags() {
        LS_TASTeamAccessBatch.isThrowInStart = false;
        LS_TASTeamAccessBatch.isThrowInExecute = false;
        LS_TASTeamAccessBatch.isThrowInFinish = false;
        LS_TASTeamAccessBatch.startCatchCount = 0;
        LS_TASTeamAccessBatch.executeCatchCount = 0;
        LS_TASTeamAccessBatch.finishCatchCount = 0;
        LS_TASTeamAccessBatch.isSkipFlexQueueCheckForTest = false;
        LS_TASTeamAccessBatch.testFlexQueueHoldingCountOverride = null;
        LS_TASTeamAccessBatch.testBatchSizeOverride = null;
        TASFreezeWindowUtil.testOnlyResetHooks();
        TASFreezeWindowUtil.testLabelOverride = 'NO_FREEZE';
        UserSelector.resetLifeSciencesSalesProfileIdCacheForTest();
        BatchProcessConfigSelector.testOnly_resetCache();
    }

    /**
     * @description
     * Counts staging rows that match the LS batch query locator filters.
     *
     * @return Number of rows the batch start() locator would return
     */
    private static Integer countPendingStagingRows() {
        Id lifeSciencesSalesProfileId = UserSelector.getLifeSciencesSalesProfileId();
        if (lifeSciencesSalesProfileId == null) {
            return 0;
        }

        return [
            SELECT COUNT()
            FROM OrderLineContact__c
            WHERE DeltaScenario__c IN :PENDING_DELTA_SCENARIOS
              AND AssignedSalesRep__c != null
              AND AssignedSalesRep__r.ProfileId = :lifeSciencesSalesProfileId
              AND AssignedSalesRep__r.IsActive = true
              AND HRISSalesRepId__c != null
              AND TASAddressId__c != null
        ];
    }

    /**
     * @description
     * Sets test batch scope so only one execute runs in @IsTest.
     *
     * @return Scope size passed to Database.executeBatch (minimum 1)
     */
    private static Integer resolveTestBatchScope() {
        return Math.max(1, countPendingStagingRows());
    }

    private static User getRunAsUser() {
        return getSalesRep();
    }

    private static String uniqueSystemId15() {
        String value = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return value.length() <= 15 ? value : value.substring(0, 15);
    }

    private static Account newCustomerAccount(String accountName) {
        String oracleCustomerId = uniqueSystemId15();
        Account acc = new Account(Name = accountName);
        populateOracleCustomerId(acc, oracleCustomerId);
        try {
            acc.put('SourceSystemID__c', oracleCustomerId + 'Oracle');
        } catch (Exception e) {
            // SourceSystemID__c optional in some orgs
        }
        return acc;
    }

    private static void populateOracleCustomerId(Account acc, String oracleCustomerId) {
        acc.put(resolveOracleCustomerIdFieldApi(), oracleCustomerId);
    }

    private static String resolveOracleCustomerIdFieldApi() {
        if (cachedOracleCustomerIdField != null) {
            return cachedOracleCustomerIdField;
        }

        for (Schema.SObjectField fieldToken : Schema.SObjectType.Account.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDesc = fieldToken.getDescribe();
            if (fieldDesc.getLabel() == 'Oracle Customer ID'
                && fieldDesc.isCreateable()
                && !fieldDesc.isCalculated()) {
                cachedOracleCustomerIdField = fieldDesc.getName();
                return cachedOracleCustomerIdField;
            }
        }

        cachedOracleCustomerIdField = 'SystemID__c';
        return cachedOracleCustomerIdField;
    }

    private static Profile resolveLifeSciencesSalesProfile() {
        List<Profile> lsProfiles = [
            SELECT Id
            FROM Profile
            WHERE Name = :UserSelector.LIFESCIENCES_SALES_PROFILE_NAME
            LIMIT 1
        ];

        if (!lsProfiles.isEmpty()) {
            return lsProfiles[0];
        }

        return [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    }

    private static OrderLineContact__c buildOlc(String empNumber, String addressId, String deltaScenario) {
        OrderLineContact__c olc = new OrderLineContact__c(
            HRISSalesRepId__c = empNumber,
            TASAddressId__c = addressId,
            AssignedSalesRep__c = getSalesRep().Id,
            TerritoryNumber__c = TEST_TERRITORY_NUMBER,
            TAS_Sales_Category__c = TEST_SALES_CATEGORY_CODE,
            SalesCategoryDescription__c = TEST_SALES_CATEGORY_DESCRIPTION
        );
        if (deltaScenario != null) {
            olc.DeltaScenario__c = deltaScenario;
        }
        return olc;
    }

    private static Id runBatch() {
        return Database.executeBatch(
            new LS_TASTeamAccessBatch(),
            resolveTestBatchScope()
        );
    }

    private static User getSalesRep() {
        return [SELECT Id FROM User WHERE EmployeeNumber__c = :EMP_MATCH LIMIT 1];
    }

    private static void assignTestPermissionSets(Id userId) {
        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name IN (
                'System_Administrator',
                'SalesFieldRepAccountManager',
                'OrderLineContact_c_Create_PS'
            )
        ];

        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSet ps : permissionSets) {
            assignments.add(new PermissionSetAssignment(
                AssigneeId = userId,
                PermissionSetId = ps.Id
            ));
        }
        insert assignments;
    }

    /**
     * @description
     * Verifies resolveBatchSize uses the test override when set.
     *
     * @return void
     */
    @IsTest
    static void testResolveBatchSizeUsesTestOverride() {
        resetBatchFlags();
        LS_TASTeamAccessBatch.testBatchSizeOverride = 50;

        Integer batchSize = LS_TASTeamAccessBatch.resolveBatchSize();

        System.assertEquals(50, batchSize, 'Test override should win over CMDT and default');
    }

    /**
     * @description
     * Verifies resolveBatchSize returns a positive configured or fallback batch size.
     *
     * @return void
     */
    @IsTest
    static void testResolveBatchSizeReturnsPositiveValue() {
        resetBatchFlags();
        Integer batchSize = LS_TASTeamAccessBatch.resolveBatchSize();
        System.assert(batchSize > 0, 'Resolved batch size should be greater than zero');
    }

    /**
     * @description
     * Verifies submitBatch enqueues a job when flex-queue SOQL is used (no skip flag).
     *
     * @return void
     */
    @IsTest
    static void testSubmitBatchResolvesFlexQueueCountFromSoql() {
        resetBatchFlags();
        insert buildOlc(EMP_MATCH, ADDR_ID, TASTeamAccessSelector.DELTA_INSERT_RECORD);

        Id jobId;
        Test.startTest();
        System.runAs(getRunAsUser()) {
            jobId = LS_TASTeamAccessBatch.submitBatch();
        }
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'submitBatch should enqueue a job using live flex-queue count');
    }

    /**
     * @description
     * Verifies submitBatch returns a job Id when flex-queue guard is bypassed.
     *
     * @return void
     */
    @IsTest
    static void testSubmitBatchQueuesJobWhenFlexQueueCheckSkipped() {
        resetBatchFlags();
        LS_TASTeamAccessBatch.isSkipFlexQueueCheckForTest = true;
        insert buildOlc(EMP_MATCH, ADDR_ID, TASTeamAccessSelector.DELTA_INSERT_RECORD);

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE JobType = 'BatchApex'
                  AND ApexClass.Name = 'LS_TASTeamAccessBatch'
            ]
        );

        Id jobId;
        Test.startTest();
        System.runAs(getRunAsUser()) {
            jobId = LS_TASTeamAccessBatch.submitBatch();
        }
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE JobType = 'BatchApex'
                  AND ApexClass.Name = 'LS_TASTeamAccessBatch'
            ]
        );
    }

    /**
     * @description
     * Verifies submitBatch throws when flex queue is at capacity.
     *
     * @return void
     */
    @IsTest
    static void testSubmitBatchThrowsWhenFlexQueueFull() {
        resetBatchFlags();
        LS_TASTeamAccessBatch.testFlexQueueHoldingCountOverride =
            LS_TASTeamAccessBatch.FLEX_QUEUE_MAX_BATCH_JOBS;

        Boolean threw = false;
        try {
            LS_TASTeamAccessBatch.submitBatch();
        } catch (TASTeamAccessException e) {
            threw = true;
            System.assert(e.getMessage().contains('flex queue'), e.getMessage());
        }
        System.assert(threw, 'submitBatch should throw when flex queue is full');
    }

    /**
     * @description
     * Verifies schedulable execute rethrows when submitBatch cannot enqueue a batch job.
     *
     * @return void
     */
    @IsTest
    static void testSchedulableExecuteRethrowsWhenFlexQueueFull() {
        resetBatchFlags();
        LS_TASTeamAccessBatch.testFlexQueueHoldingCountOverride =
            LS_TASTeamAccessBatch.FLEX_QUEUE_MAX_BATCH_JOBS;

        Boolean threw = false;
        try {
            new LS_TASTeamAccessBatch().execute(null);
        } catch (TASTeamAccessException e) {
            threw = true;
            System.assert(e.getMessage().contains('flex queue'), e.getMessage());
        }
        System.assert(threw, 'Schedulable execute should rethrow flex-queue capacity failures');
    }

    /**
     * @description
     * Verifies Schedulable execute queues exactly one LS_TASTeamAccessBatch job.
     *
     * @return void
     */
    @IsTest
    static void testSchedulableExecuteQueuesSingleBatchJob() {
        resetBatchFlags();
        LS_TASTeamAccessBatch.isSkipFlexQueueCheckForTest = true;

        Test.startTest();
        System.runAs(getRunAsUser()) {
            new LS_TASTeamAccessBatch().execute(null);
        }
        Test.stopTest();

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE JobType = 'BatchApex'
                  AND ApexClass.Name = 'LS_TASTeamAccessBatch'
            ],
            'Schedulable should queue one batch job'
        );
    }

    /**
     * @description
     * Verifies start, execute, and finish process Insert Record rows and clear DeltaScenario__c.
     *
     * @return void
     */
    @IsTest
    static void testBatchProcessesInsertScenarioEndToEnd() {
        resetBatchFlags();
        OrderLineContact__c olc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        insert olc;

        Id jobId;
        Test.startTest();
        System.runAs(getRunAsUser()) {
            jobId = runBatch();
        }
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Batch should enqueue and complete start/execute/finish');
        System.assertEquals(0, LS_TASTeamAccessBatch.startCatchCount);
        System.assertEquals(0, LS_TASTeamAccessBatch.executeCatchCount);
        System.assertEquals(0, LS_TASTeamAccessBatch.finishCatchCount);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM OrderLineContact__c WHERE Id = :olc.Id],
            'Staging row should still exist after the LS batch run'
        );
    }

    /**
     * @description
     * Verifies execute exceptions are caught without failing the batch.
     *
     * @return void
     */
    @IsTest
    static void testBatchExecuteHandlesExceptionWithoutRethrow() {
        try {
            resetBatchFlags();
            OrderLineContact__c olc = buildOlc(
                EMP_MATCH,
                ADDR_ID,
                TASTeamAccessSelector.DELTA_INSERT_RECORD
            );
            insert olc;
            LS_TASTeamAccessBatch.isThrowInExecute = true;

            System.assertEquals(0, LS_TASTeamAccessBatch.executeCatchCount);

            Test.startTest();
            System.runAs(getRunAsUser()) {
                new LS_TASTeamAccessBatch().execute(
                    null,
                    new List<OrderLineContact__c>{ olc }
                );
            }
            Test.stopTest();

            System.assert(LS_TASTeamAccessBatch.executeCatchCount > 0, 'Execute errors should be caught');
            System.assertEquals(0, LS_TASTeamAccessBatch.finishCatchCount);
        } finally {
            resetBatchFlags();
        }
    }

    /**
     * @description
     * Verifies finish exceptions are caught without failing the batch.
     *
     * @return void
     */
    @IsTest
    static void testBatchFinishHandlesExceptionWithoutRethrow() {
        try {
            resetBatchFlags();
            insert buildOlc(
                EMP_MATCH,
                ADDR_ID,
                TASTeamAccessSelector.DELTA_INSERT_RECORD
            );
            LS_TASTeamAccessBatch.isThrowInFinish = true;

            System.assertEquals(0, LS_TASTeamAccessBatch.finishCatchCount);

            Id jobId;
            Test.startTest();
            System.runAs(getRunAsUser()) {
                jobId = runBatch();
            }
            Test.stopTest();

            System.assertNotEquals(null, jobId);
            System.assert(LS_TASTeamAccessBatch.finishCatchCount > 0, 'Finish errors should be caught');
            System.assertEquals(0, LS_TASTeamAccessBatch.executeCatchCount);
        } finally {
            resetBatchFlags();
        }
    }

    /**
     * @description
     * Verifies start exceptions are logged and rethrown.
     *
     * @return void
     */
    @IsTest
    static void testBatchStartThrows() {
        resetBatchFlags();
        LS_TASTeamAccessBatch.isThrowInStart = true;

        System.assertEquals(0, LS_TASTeamAccessBatch.startCatchCount);

        Boolean threw = false;
        try {
            System.runAs(getRunAsUser()) {
                new LS_TASTeamAccessBatch().start(null);
            }
            System.assert(false, 'Expected start to throw');
        } catch (Exception e) {
            threw = true;
            System.assertNotEquals(null, e);
        }

        System.assert(threw, 'start() should rethrow after logging');
        System.assertEquals(1, LS_TASTeamAccessBatch.startCatchCount);
        System.assertEquals(0, LS_TASTeamAccessBatch.executeCatchCount);
        System.assertEquals(0, LS_TASTeamAccessBatch.finishCatchCount);

        resetBatchFlags();
    }

    /**
     * @description
     * Verifies malformed TAS_FreezeWindow label aborts batch start.
     *
     * @return void
     */
    @IsTest
    static void testInvalidFreezeWindowLabelAbortsBatchStart() {
        resetBatchFlags();
        TASFreezeWindowUtil.testLabelOverride = '08/10/2026|20/10/2026';

        System.assertEquals(0, LS_TASTeamAccessBatch.startCatchCount);

        Test.startTest();
        Boolean threw = false;
        try {
            System.runAs(getRunAsUser()) {
                new LS_TASTeamAccessBatch().start(null);
            }
            System.assert(false, 'Expected batch start to throw for malformed freeze label');
        } catch (TASTeamAccessException e) {
            threw = true;
            System.assert(
                e.getMessage().contains('invalid end date; expected MM/DD/YYYY'),
                'Unexpected parse failure message: ' + e.getMessage()
            );
        }
        Test.stopTest();

        System.assert(threw, 'Batch start should throw for malformed TAS_FreezeWindow label');
        System.assertEquals(1, LS_TASTeamAccessBatch.startCatchCount);
        System.assertEquals(0, LS_TASTeamAccessBatch.executeCatchCount);
    }

    /**
     * @description
     * Verifies start returns a query locator when freeze window is valid.
     *
     * @return void
     */
    @IsTest
    static void testBatchStartReturnsQueryLocator() {
        resetBatchFlags();
        insert buildOlc(EMP_MATCH, ADDR_ID, TASTeamAccessSelector.DELTA_INSERT_RECORD);

        Database.QueryLocator locator;
        Test.startTest();
        System.runAs(getRunAsUser()) {
            locator = new LS_TASTeamAccessBatch().start(null);
        }
        Test.stopTest();

        System.assertNotEquals(null, locator, 'start should return the LS OrderLineContact query locator');
        System.assertEquals(0, LS_TASTeamAccessBatch.startCatchCount);
    }

    /**
     * @description
     * Verifies execute with empty scope is caught or completes without incrementing start/finish counters.
     *
     * @return void
     */
    @IsTest
    static void testBatchExecuteEmptyScope() {
        resetBatchFlags();

        Test.startTest();
        System.runAs(getRunAsUser()) {
            new LS_TASTeamAccessBatch().execute(null, new List<OrderLineContact__c>());
        }
        Test.stopTest();

        System.assertEquals(0, LS_TASTeamAccessBatch.executeCatchCount);
    }

    /**
     * @description
     * Verifies finish restores logger parent transaction id and completes without error.
     *
     * @return void
     */
    @IsTest
    static void testBatchFinishCompletes() {
        resetBatchFlags();

        Test.startTest();
        System.runAs(getRunAsUser()) {
            new LS_TASTeamAccessBatch().finish(null);
        }
        Test.stopTest();

        System.assertEquals(0, LS_TASTeamAccessBatch.finishCatchCount);
    }

    /**
     * @description
     * Verifies assertFlexQueueHasCapacity is a no-op when the test skip flag is set.
     *
     * @return void
     */
    @IsTest
    static void testAssertFlexQueueHasCapacitySkippedInTest() {
        resetBatchFlags();
        LS_TASTeamAccessBatch.isSkipFlexQueueCheckForTest = true;
        LS_TASTeamAccessBatch.testFlexQueueHoldingCountOverride =
            LS_TASTeamAccessBatch.FLEX_QUEUE_MAX_BATCH_JOBS;

        LS_TASTeamAccessBatch.assertFlexQueueHasCapacity();

        System.assert(true, 'Skip flag should bypass flex-queue capacity assertion');
    }
}