/**
 * @author Suraj Thapliyal
 * @date 2026/05/24
 *
 * @group Order Line Contact
 *
 * @description
 * Tests for OrderLineContact team access batch and service.
 * GC-3278 - TAS class rename (formerly OrderLineContactTeamAccessBatchTest).
 * Covers per-row success/failure, DeltaScenario__c routing, deduplication, bulk chunk processing, and post-processing.
 * GC-3352 - Insert stamps TerritoryCode__c, SalesCategoryCode__c, and SalesCategoryDescription__c
 * from OrderLineContact__c; duplicate key remains accountId|userId.
 * GC-3345 - Test ATM helper sets OpportunityAccessLevel to Edit.
 */
@IsTest(SeeAllData=false)
private class TASTeamAccessBatchTest {

    private static final String EMP_MATCH = 'OLC-TAS-10001';
    private static final String EMP_OTHER = 'OLC-TAS-10002';
    private static final String EMP_NO_MATCH = 'OLC-TAS-NOMATCH';
    private static final String ADDR_ID = 'TAS-ADDR-9001';
    private static final String BAD_ADDR_ID = 'TAS-ADDR-MISS';           // no matching Account.OracleAddressId__c
    private static final String ADDR_ID_NO_TARGETS = 'TAS-ADDR-NOTGT';   // no Account with this Oracle address id
    private static final String ADDR_ID_ACCOUNT_ONLY = 'TAS-ADDR-ACCT'; // second account mapped by OracleAddressId__c
    // GC-3352 - Coverage values copied from OLC onto new AccountTeamMember rows.
    private static final String TEST_TERRITORY_NUMBER = 'TN-3352';
    private static final String TEST_SALES_CATEGORY_CODE = 'SURG SPT';
    private static final String TEST_SALES_CATEGORY_DESCRIPTION = 'Surgical Support';

    // Enough rows to prove bulk DML without blowing governor limits in test
    private static final Integer BULK_ROW_COUNT = 50;

    // Mirrors the batch start() locator filters
    private static final List<String> PENDING_DELTA_SCENARIOS = new List<String>{
        TASTeamAccessSelector.DELTA_INSERT_RECORD,
        TASTeamAccessSelector.DELTA_DELETE_RECORD
    };

    // Resolved once per test run — avoids repeated describe calls in newCustomerAccount
    private static String cachedOracleCustomerIdField;

    /**
     * @description
     * Creates user and account test data mapped by Account.OracleAddressId__c.
     *
     * @return void
     * @example
     * Shared @TestSetup for all methods in this class.
     */
    @TestSetup
    static void setupData() {
        Profile salesProfile = resolveHealthcareSalesProfile();

        User salesRep = new User(
            FirstName = 'OLC',
            LastName = 'SalesRep',
            Alias = 'olcsrep',
            Email = 'olc.salesrep.' + DateTime.now().getTime() + '@test.com',
            Username = 'olc.salesrep.' + DateTime.now().getTime() + '@test.com',
            CommunityNickname = 'olcnick' + Math.abs(Crypto.getRandomInteger()),
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

        Account acc = newCustomerAccount('OLC Team Access Account');
        acc.OracleAddressId__c = ADDR_ID;
        insert acc;

        Account accAccountOnly = newCustomerAccount('OLC Account Only');
        accAccountOnly.OracleAddressId__c = ADDR_ID_ACCOUNT_ONLY;
        insert accAccountOnly;
    }

    /**
     * @description
     * GC-3179 - Modified: clears testBatchSizeOverride for BatchProcessConfig__mdt batch-size tests.
     * Resets batch test hooks and error counters between test methods.
     *
     * @return void
     */
    // @TestVisible flags on the batch stick around between methods — clear them each time
    private static void resetBatchFlags() {
        TASTeamAccessBatch.isThrowInStart = false;
        TASTeamAccessBatch.isThrowInExecute = false;
        TASTeamAccessBatch.isThrowInFinish = false;
        TASTeamAccessBatch.startCatchCount = 0;
        TASTeamAccessBatch.executeCatchCount = 0;
        TASTeamAccessBatch.finishCatchCount = 0;
        TASTeamAccessBatch.isSkipFlexQueueCheckForTest = false;
        TASTeamAccessBatch.testFlexQueueHoldingCountOverride = null;
        TASTeamAccessBatch.testBatchSizeOverride = null;
        // GC-2596 - Reset delete freeze window test hooks between batch test methods.
        TASFreezeWindowUtil.testOnlyResetHooks();
        // Default non-freeze tests to NO_FREEZE so org TAS_FreezeWindow config does not skip deletes.
        TASFreezeWindowUtil.testLabelOverride = 'NO_FREEZE';
        resetServiceTestFlags();
    }

    /**
     * @description
     * Clears service-layer test hooks between test methods.
     *
     * @return void
     */
    private static void resetServiceTestFlags() {
        TASTeamAccessService.testOnly_forceCommonReadSecurityFailure = false;
        TASTeamAccessService.testOnly_forceInsertSecurityFailure = false;
        TASTeamAccessService.testOnly_forceDeleteSecurityFailure = false;
        TASTeamAccessService.testOnly_forceInvalidTeamMemberUserForTest = false;
    }

    /**
     * @description
     * Counts staging rows that match the batch query locator (same filters as selector).
     *
     * @return Number of rows the batch start() locator would return
     */
    private static Integer countPendingStagingRows() {
        Id healthcareSalesProfileId = resolveHealthcareSalesProfile().Id;

        return [
            SELECT COUNT()
            FROM OrderLineContact__c
            WHERE DeltaScenario__c IN :PENDING_DELTA_SCENARIOS
              AND AssignedSalesRep__c != null
              AND AssignedSalesRep__r.ProfileId = :healthcareSalesProfileId
              AND AssignedSalesRep__r.IsActive = true
              AND HRISSalesRepId__c != null
              AND TASAddressId__c != null
        ];
    }

    /**
     * @description
     * Sets test batch scope to pending row count so only one execute runs in @IsTest.
     *
     * @return Scope size passed to Database.executeBatch (minimum 1)
     */
    private static Integer resolveTestBatchScope() {
        // In tests you only get one executeBatch + one execute(); scope must cover all pending rows
        return Math.max(1, countPendingStagingRows());
    }

    /**
     * @description
     * Running user for System.runAs — the sales rep created in @TestSetup.
     *
     * @return Active User with EmployeeNumber__c = EMP_MATCH
     */
    private static User getRunAsUser() {
        return getSalesRep();
    }

    /**
     * @description
     * Returns a unique System ID value (max 15 characters for SystemID__c).
     *
     * @return Unique system id string
     */
    private static String uniqueSystemId15() {
        String value = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return value.length() <= 15 ? value : value.substring(0, 15);
    }

    /**
     * @description
     * Builds an Account that satisfies Customer record-type validation (Oracle Customer ID).
     *
     * @param accountName Display name for the test account
     * @return Account instance ready for insert
     * @example
     * insert newCustomerAccount('OLC Team Access Account');
     */
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
        String fieldApi = resolveOracleCustomerIdFieldApi();
        acc.put(fieldApi, oracleCustomerId);
    }

    private static String resolveOracleCustomerIdFieldApi() {
        if (cachedOracleCustomerIdField != null) {
            return cachedOracleCustomerIdField;
        }

        // Walk Account fields once — validation rule wants "Oracle Customer ID" on Customer RT
        for (Schema.SObjectField fieldToken : Schema.SObjectType.Account.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDesc = fieldToken.getDescribe();
            if (fieldDesc.getLabel() == 'Oracle Customer ID'
                && fieldDesc.isCreateable()
                && !fieldDesc.isCalculated()) {
                cachedOracleCustomerIdField = fieldDesc.getName();
                return cachedOracleCustomerIdField;
            }
        }

        // Fallback most dev sandboxes use for the same validation
        cachedOracleCustomerIdField = 'SystemID__c';
        return cachedOracleCustomerIdField;
    }

    /**
     * @description
     * Builds an OrderLineContact__c staging row for tests.
     * GC-3352 - Populates Territory Number, TAS Sales Category, and Sales Category Description
     * so insert tests can assert AccountTeamMember coverage fields.
     *
     * @param empNumber Value for HRISSalesRepId__c
     * @param addressId Value for TASAddressId__c
     * @param deltaScenario DeltaScenario__c picklist value; omitted when null
     * @return OrderLineContact__c instance ready for insert
     * @example
     * buildOlc(EMP_MATCH, ADDR_ID, TASTeamAccessSelector.DELTA_INSERT_RECORD);
     */
    private static Profile resolveHealthcareSalesProfile() {
        List<Profile> healthcareProfiles = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Healthcare Sales'
            LIMIT 1
        ];

        if (!healthcareProfiles.isEmpty()) {
            return healthcareProfiles[0];
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

    /**
     * @description
     * Builds a list of staging rows for bulk tests (single in-memory list, one insert DML).
     *
     * @param rowCount Number of rows to build
     * @param empNumber Value for HRISSalesRepId__c on each row
     * @param addressId Value for TASAddressId__c on each row
     * @param deltaScenario DeltaScenario__c picklist value on each row
     * @return List of OrderLineContact__c instances ready for insert
     */
    private static List<OrderLineContact__c> buildOlcList(
        Integer rowCount,
        String empNumber,
        String addressId,
        String deltaScenario
    ) {
        List<OrderLineContact__c> rows = new List<OrderLineContact__c>();
        for (Integer i = 0; i < rowCount; i++) {
            rows.add(buildOlc(empNumber, addressId, deltaScenario));
        }
        return rows; // caller does a single insert(rows) — keeps DML bulkified
    }

    /**
     * @description
     * Returns staging row Ids still pending the given delta scenario (bulk-friendly assertion helper).
     *
     * @param olcIds Ids to check
     * @param expectedScenario Expected DeltaScenario__c value
     * @return Count of rows matching the scenario
     */
    private static Integer countOlcsWithScenario(Set<Id> olcIds, String expectedScenario) {
        if (olcIds == null || olcIds.isEmpty()) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM OrderLineContact__c
            WHERE Id IN :olcIds
              AND DeltaScenario__c = :expectedScenario
        ];
    }

    /**
     * @description
     * Returns staging row Ids with cleared DeltaScenario__c (bulk-friendly assertion helper).
     *
     * @param olcIds Ids to check
     * @return Count of rows with null DeltaScenario__c
     */
    private static Integer countOlcsWithClearedScenario(Set<Id> olcIds) {
        if (olcIds == null || olcIds.isEmpty()) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM OrderLineContact__c
            WHERE Id IN :olcIds
              AND DeltaScenario__c = null
        ];
    }

    private static Set<Id> toIdSet(List<OrderLineContact__c> rows) {
        Set<Id> ids = new Set<Id>();
        for (OrderLineContact__c row : rows) {
            ids.add(row.Id);
        }
        return ids;
    }

    /**
     * @description
     * Runs the team access batch synchronously in test context.
     *
     * @return AsyncApexJob Id for the batch run
     * @example
     * Id jobId = runBatch();
     */
    private static Id runBatch() {
        // Pass scope here — do not rely on batch test hooks (keeps test compile-safe vs org version)
        return Database.executeBatch(
            new TASTeamAccessBatch(),
            resolveTestBatchScope()
        );
    }

    private static User getSalesRep() {
        return [SELECT Id FROM User WHERE EmployeeNumber__c = :EMP_MATCH LIMIT 1];
    }

    /**
     * @description
     * Creates a second active user for account-team scenarios (one ATM row per user per account).
     *
     * @return Inserted User with a unique EmployeeNumber__c
     */
    private static User insertOtherSalesRep() {
        Profile salesProfile = resolveHealthcareSalesProfile();
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));

        User otherRep = new User(
            FirstName = 'OLC',
            LastName = 'OtherRep',
            Alias = ('olc2' + suffix).left(8),
            Email = 'olc.other.' + suffix + '@test.com',
            Username = 'olc.other.' + suffix + '@test.com',
            CommunityNickname = 'olc2nick' + suffix,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = salesProfile.Id,
            EmployeeNumber__c = EMP_OTHER,
            IsActive = true
        );
        insert otherRep;
        assignTestPermissionSets(otherRep.Id);
        return otherRep;
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

    private static Account getTestAccount() {
        return getAccountByOracleAddressId(ADDR_ID);
    }

    private static Account getAccountByOracleAddressId(String oracleAddressId) {
        return [
            SELECT Id
            FROM Account
            WHERE OracleAddressId__c = :oracleAddressId
            LIMIT 1
        ];
    }

    private static Integer countAtmTasAssigned(Id accountId, Id userId) {
        return [
            SELECT COUNT()
            FROM AccountTeamMember
            WHERE AccountId = :accountId
              AND UserId = :userId
              AND TeamMemberRole = :TASTeamAccessService.TEAM_MEMBER_ROLE_SALES
              AND AssignmentType__c = :TASTeamAccessService.ASSIGNMENT_TYPE_ORACLE_ASSIGNED
        ];
    }

    /**
     * @description
     * Builds AccountTeamMember test data using the same access levels as production service code.
     *
     * @param accountId Account Id for the team member
     * @param userId User Id for the team member
     * @param teamMemberRole Team member role value
     * @return AccountTeamMember ready for insert
     */
    private static AccountTeamMember newTestAccountTeamMember(
        Id accountId,
        Id userId,
        String teamMemberRole
    ) {
        // Keep access levels in sync with TASTeamAccessService.buildAccountTeamMember
        return new AccountTeamMember(
            AccountId = accountId,
            UserId = userId,
            TeamMemberRole = teamMemberRole,
            AssignmentType__c = teamMemberRole == TASTeamAccessService.TEAM_MEMBER_ROLE_SALES
                ? TASTeamAccessService.ASSIGNMENT_TYPE_ORACLE_ASSIGNED
                : null,
            AccountAccessLevel = 'Edit',
            OpportunityAccessLevel = 'Edit', // GC-3345
            CaseAccessLevel = 'None' // 'Private' is not valid in our org's ATM picklist
        );
    }

    // --- Selector helpers ---

    /**
     * @description
     * Verifies delta scenario helper methods.
     *
     * @return void
     */
    @IsTest
    static void testSelectorDeltaScenarioHelpers() {
        /********************************************
        * SETUP
        ********************************************/
        /********************************************
        * GIVEN
        ********************************************/
        System.assert(
            TASTeamAccessSelector.isInsertScenario(
                TASTeamAccessSelector.DELTA_INSERT_RECORD
            )
        );

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            System.assert(
                TASTeamAccessSelector.isDeleteScenario(
                    TASTeamAccessSelector.DELTA_DELETE_RECORD
                )
            );
        }

        /********************************************
        * THEN
        ********************************************/
        System.assert(!TASTeamAccessSelector.isInsertScenario(null));
        System.assert(!TASTeamAccessSelector.isDeleteScenario(''));
    }

    /**
     * @description
     * GC-2596 - Verifies selector empty-input guards and required delete filter validation.
     *
     * @return void
     */
    @IsTest
    static void testSelectorEmptyInputGuardsAndDeleteValidation() {
        System.assertEquals(
            0,
            TASTeamAccessSelector.selectExistingAccountTeamKeys(null, null).size(),
            'Null account and user Ids should return an empty key set'
        );
        System.assertEquals(
            0,
            TASTeamAccessSelector.selectAccountTeamMembersForDelete(
                new Set<Id>(),
                new Set<Id>(),
                TASTeamAccessService.TEAM_MEMBER_ROLE_SALES,
                TASTeamAccessService.ASSIGNMENT_TYPE_ORACLE_ASSIGNED
            ).size(),
            'Empty account and user Ids should return no team members'
        );
        System.assertEquals(
            0,
            TASTeamAccessSelector.selectAccountsByOracleAddressId(null).size(),
            'Null address id set should return an empty account map'
        );
        System.assertEquals(
            0,
            TASTeamAccessSelector.selectAccountsByOracleAddressId(new Set<String>()).size(),
            'Empty address id set should return an empty account map'
        );

        Boolean threw = false;
        try {
            TASTeamAccessSelector.selectAccountTeamMembersForDelete(
                new Set<Id>{ UserInfo.getUserId() },
                new Set<Id>{ UserInfo.getUserId() },
                TASTeamAccessService.TEAM_MEMBER_ROLE_SALES,
                ''
            );
        } catch (TASTeamAccessException e) {
            threw = true;
            System.assert(
                e.getMessage().contains('AssignmentType__c'),
                'Blank assignment type should throw a validation exception'
            );
        }
        System.assert(threw, 'Blank assignment type should throw');
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
        Integer batchSize = TASTeamAccessBatch.resolveBatchSize();
        System.assert(batchSize > 0, 'Resolved batch size should be greater than zero');
    }

    /**
     * @description
     * Verifies submitBatch resolves flex-queue capacity from SOQL when test bypass is disabled.
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
            jobId = TASTeamAccessBatch.submitBatch();
        }
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'submitBatch should enqueue a job using live flex-queue count');
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
        TASTeamAccessBatch.testFlexQueueHoldingCountOverride =
            TASTeamAccessBatch.FLEX_QUEUE_MAX_BATCH_JOBS;

        Boolean threw = false;
        try {
            new TASTeamAccessBatch().execute(null);
        } catch (TASTeamAccessException e) {
            threw = true;
            System.assert(e.getMessage().contains('flex queue'), e.getMessage());
        }
        System.assert(threw, 'Schedulable execute should rethrow flex-queue capacity failures');
    }

    // --- Service: scope and empty input ---

    /**
     * @description
     * Verifies process handles null or empty scope without error.
     *
     * @return void
     */
    @IsTest
    static void testServiceProcessEmptyScope() {
        /********************************************
        * SETUP
        ********************************************/
        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember]);

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            // Should no-op without NPE — defensive guard at top of service.process
            TASTeamAccessService.process(null);
            TASTeamAccessService.process(new List<OrderLineContact__c>());
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember]);
    }

    // --- Batch: query scope ---

    /**
     * @description
     * Verifies blank DeltaScenario__c rows are not selected by the batch query.
     *
     * @return void
     */
    @IsTest
    static void testBlankDeltaScenarioExcludedFromBatch() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();
        // Null scenario — should never land in the batch locator
        insert buildOlc(EMP_MATCH, ADDR_ID, null);

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember]);

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
        // If this row were processed we'd see team members; count should stay zero
        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'Blank DeltaScenario should not be processed by batch'
        );
    }

    /**
     * @description
     * Verifies rows without AssignedSalesRep__c are excluded from the batch locator.
     *
     * @return void
     */
    @IsTest
    static void testSkipsWhenNoMatchingActiveUser() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();
        OrderLineContact__c olc = buildOlc(
            EMP_NO_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        olc.AssignedSalesRep__c = null;
        insert olc;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember]);

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
        // Row is excluded from batch locator when AssignedSalesRep__c is null
        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'Rows without AssignedSalesRep__c should not grant team access'
        );
    }

    // --- Insert scenario ---

    /**
     * @description
     * Verifies Insert Record creates team members and clears DeltaScenario__c.
     * GC-3352 - Also verifies Territory Code, Sales Category Code, and Sales Category Description
     * are copied from the staging row. Duplicate key remains accountId|userId.
     *
     * @return void
     */
    @IsTest
    static void testInsertScenarioGrantsTeamAccessAndClearsScenario() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();

        OrderLineContact__c olc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        insert olc;

        User rep = getSalesRep();
        Account acc = getTestAccount();

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, countAtmTasAssigned(acc.Id, rep.Id));

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
        System.assertEquals(
            1,
            countAtmTasAssigned(acc.Id, rep.Id),
            'Account team member should be created with Sales + Oracle Assigned'
        );

        AccountTeamMember createdTeamMember = [
            SELECT TerritoryCode__c, SalesCategoryCode__c, SalesCategoryDescription__c
            FROM AccountTeamMember
            WHERE AccountId = :acc.Id
              AND UserId = :rep.Id
              AND TeamMemberRole = :TASTeamAccessService.TEAM_MEMBER_ROLE_SALES
              AND AssignmentType__c = :TASTeamAccessService.ASSIGNMENT_TYPE_ORACLE_ASSIGNED
            LIMIT 1
        ];
        System.assertEquals(
            TEST_TERRITORY_NUMBER,
            createdTeamMember.TerritoryCode__c,
            'GC-3352 TerritoryCode__c should copy TerritoryNumber__c from OrderLineContact__c'
        );
        System.assertEquals(
            TEST_SALES_CATEGORY_CODE,
            createdTeamMember.SalesCategoryCode__c,
            'GC-3352 SalesCategoryCode__c should copy TAS_Sales_Category__c from OrderLineContact__c'
        );
        System.assertEquals(
            TEST_SALES_CATEGORY_DESCRIPTION,
            createdTeamMember.SalesCategoryDescription__c,
            'GC-3352 SalesCategoryDescription__c should copy from OrderLineContact__c'
        );

        OrderLineContact__c processed = [
            SELECT DeltaScenario__c
            FROM OrderLineContact__c
            WHERE Id = :olc.Id
        ];
        System.assertEquals(null, processed.DeltaScenario__c, 'DeltaScenario should be cleared after insert');
    }

    /**
     * @description
     * Verifies missing address leaves DeltaScenario__c unchanged.
     *
     * @return void
     */
    @IsTest
    static void testInsertSkipsWhenAddressNotFoundAndDoesNotClearScenario() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();

        // TASAddressId__c has no matching Account.OracleAddressId__c
        OrderLineContact__c olc = buildOlc(
            EMP_MATCH,
            BAD_ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        insert olc;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(
            TASTeamAccessSelector.DELTA_INSERT_RECORD,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :olc.Id].DeltaScenario__c
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
        // Leave scenario set so the row can be retried on the next run
        System.assertEquals(
            TASTeamAccessSelector.DELTA_INSERT_RECORD,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :olc.Id].DeltaScenario__c,
            'Scenario should remain when account cannot be resolved'
        );
    }

    /**
     * @description
     * Verifies account without OracleAddressId match does not clear scenario.
     *
     * @return void
     */
    @IsTest
    static void testInsertSkipsWhenAddressHasNoTargets() {
        /********************************************
        * SETUP
        ********************************************/
        // No Account.OracleAddressId__c matches this TAS address id
        OrderLineContact__c olc = buildOlc(
            EMP_MATCH,
            ADDR_ID_NO_TARGETS,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        insert olc;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(
            TASTeamAccessSelector.DELTA_INSERT_RECORD,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :olc.Id].DeltaScenario__c
        );

        /********************************************
        * WHEN
        ********************************************/
        // Direct service call — no batch/async for this negative path
        System.runAs(getRunAsUser()) {
            TASTeamAccessService.process(new List<OrderLineContact__c>{ olc });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            TASTeamAccessSelector.DELTA_INSERT_RECORD,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :olc.Id].DeltaScenario__c
        );
    }

    /**
     * @description
     * Verifies insert when a second account is mapped by OracleAddressId__c still clears scenario and creates ATM.
     *
     * @return void
     */
    @IsTest
    static void testInsertWithAccountOnlyAddress() {
        /********************************************
        * SETUP
        ********************************************/
        User rep = getSalesRep();
        Account acc = getAccountByOracleAddressId(ADDR_ID_ACCOUNT_ONLY);

        OrderLineContact__c olc = buildOlc(
            EMP_MATCH,
            ADDR_ID_ACCOUNT_ONLY,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        insert olc;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id AND UserId = :rep.Id]);

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TASTeamAccessService.process(new List<OrderLineContact__c>{ olc });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            null,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :olc.Id].DeltaScenario__c
        );
        System.assertEquals(1, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id AND UserId = :rep.Id]);
    }

    /**
     * @description
     * Verifies existing team member prevents duplicate insert and still clears scenario.
     *
     * @return void
     */
    @IsTest
    static void testServiceIdempotentWhenTeamMemberAlreadyExists() {
        /********************************************
        * SETUP
        ********************************************/
        User rep = getSalesRep();
        Account acc = getTestAccount();

        insert newTestAccountTeamMember(
            acc.Id,
            rep.Id,
            TASTeamAccessService.TEAM_MEMBER_ROLE_SALES
        );

        OrderLineContact__c olc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        insert olc;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(1, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id AND UserId = :rep.Id]);

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TASTeamAccessService.process(new List<OrderLineContact__c>{ olc });
            // Simulate a re-feed of the same staging row
            olc.DeltaScenario__c = TASTeamAccessSelector.DELTA_INSERT_RECORD;
            TASTeamAccessService.process(new List<OrderLineContact__c>{ olc });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            null,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :olc.Id].DeltaScenario__c
        );
        // Still only one ATM row — no duplicate insert
        System.assertEquals(
            1,
            [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id AND UserId = :rep.Id],
            'Second pass should remain idempotent'
        );
    }

    // --- Delete scenario ---

    /**
     * @description
     * Verifies Delete Record removes Oracle Assigned team members and deletes the staging row.
     *
     * @return void
     */
    @IsTest
    static void testDeleteScenarioRemovesTeamMembersAndStagingRow() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();
        User rep = getSalesRep();
        Account acc = getTestAccount();

        insert newTestAccountTeamMember(
            acc.Id,
            rep.Id,
            TASTeamAccessService.TEAM_MEMBER_ROLE_SALES
        );

        OrderLineContact__c olc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_DELETE_RECORD
        );
        insert olc;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(1, countAtmTasAssigned(acc.Id, rep.Id));
        System.assertEquals(1, [SELECT COUNT() FROM OrderLineContact__c WHERE Id = :olc.Id]);

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
        System.assertEquals(0, countAtmTasAssigned(acc.Id, rep.Id));
        System.assertEquals(0, [SELECT COUNT() FROM OrderLineContact__c WHERE Id = :olc.Id]);
    }

    /**
     * @description
     * Verifies delete scenario removes staging row when no team members exist to delete.
     *
     * @return void
     */
    @IsTest
    static void testDeleteScenarioWithNoTeamMembersStillDeletesStaging() {
        /********************************************
        * SETUP
        ********************************************/
        OrderLineContact__c olc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_DELETE_RECORD
        );
        insert olc;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(1, [SELECT COUNT() FROM OrderLineContact__c WHERE Id = :olc.Id]);

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TASTeamAccessService.process(new List<OrderLineContact__c>{ olc });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(0, [SELECT COUNT() FROM OrderLineContact__c WHERE Id = :olc.Id]);
    }

    /**
     * @description
     * Verifies only Sales + Oracle Assigned members are removed; other roles remain.
     *
     * @return void
     */
    @IsTest
    static void testDeleteScenarioRemovesOnlyTasAssignedRole() {
        /********************************************
        * SETUP
        ********************************************/
        User rep = getSalesRep();
        User otherRep = insertOtherSalesRep();
        Account acc = getAccountByOracleAddressId(ADDR_ID_ACCOUNT_ONLY);

        // One ATM per user per account — use two users to hold two different roles
        insert newTestAccountTeamMember(acc.Id, otherRep.Id, 'Sales Rep');
        insert newTestAccountTeamMember(
            acc.Id,
            rep.Id,
            TASTeamAccessService.TEAM_MEMBER_ROLE_SALES
        );

        OrderLineContact__c olc = buildOlc(
            EMP_MATCH,
            ADDR_ID_ACCOUNT_ONLY,
            TASTeamAccessSelector.DELTA_DELETE_RECORD
        );
        insert olc;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(2, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id]);

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TASTeamAccessService.process(new List<OrderLineContact__c>{ olc });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM AccountTeamMember
                WHERE AccountId = :acc.Id
                  AND UserId = :otherRep.Id
                  AND TeamMemberRole = 'Sales Rep'
            ],
            'Non-TAS role on the other user should remain'
        );
        System.assertEquals(0, countAtmTasAssigned(acc.Id, rep.Id), 'Oracle Assigned membership should be removed');
    }

    // --- Mixed / partial chunk ---

    /**
     * @description
     * Verifies one batch run processes both insert and delete rows by DeltaScenario__c.
     *
     * @return void
     */
    @IsTest
    static void testMixedInsertAndDeleteScenariosInOneBatch() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();
        User rep = getSalesRep();
        Account acc = getTestAccount();

        insert newTestAccountTeamMember(
            acc.Id,
            rep.Id,
            TASTeamAccessService.TEAM_MEMBER_ROLE_SALES
        );

        // Same user/address in one chunk — delete runs before insert in service.process
        OrderLineContact__c deleteOlc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_DELETE_RECORD
        );
        OrderLineContact__c insertOlc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        insert new List<OrderLineContact__c>{ deleteOlc, insertOlc };

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(1, countAtmTasAssigned(acc.Id, rep.Id));

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
        // Delete removed TAS member; insert did not re-add in same batch pass (net zero)
        System.assertEquals(0, countAtmTasAssigned(acc.Id, rep.Id));
        System.assertEquals(
            null,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :insertOlc.Id].DeltaScenario__c
        );
        System.assertEquals(0, [SELECT COUNT() FROM OrderLineContact__c WHERE Id = :deleteOlc.Id]);
    }

    /**
     * @description
     * Verifies a row that cannot resolve address does not block a valid row in the same chunk.
     *
     * @return void
     */
    @IsTest
    static void testPartialChunkOneSuccessOneFailure() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();

        OrderLineContact__c successOlc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        OrderLineContact__c failOlc = buildOlc(
            EMP_MATCH,
            BAD_ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        // One good address, one bad — same batch chunk
        insert new List<OrderLineContact__c>{ successOlc, failOlc };

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(
            TASTeamAccessSelector.DELTA_INSERT_RECORD,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :successOlc.Id].DeltaScenario__c
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
            null,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :successOlc.Id].DeltaScenario__c,
            'Valid row should be cleared'
        );
        System.assertEquals(
            TASTeamAccessSelector.DELTA_INSERT_RECORD,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :failOlc.Id].DeltaScenario__c,
            'Invalid row should remain for retry'
        );
    }

    /**
     * @description
     * Verifies service.process skips unresolvable rows and clears fully successful rows only.
     *
     * @return void
     */
    @IsTest
    static void testServiceProcessPartialChunk() {
        /********************************************
        * SETUP
        ********************************************/
        OrderLineContact__c successOlc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        OrderLineContact__c failOlc = buildOlc(
            EMP_MATCH,
            BAD_ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        insert new List<OrderLineContact__c>{ successOlc, failOlc };

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(
            TASTeamAccessSelector.DELTA_INSERT_RECORD,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :successOlc.Id].DeltaScenario__c
        );

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TASTeamAccessService.process(
                new List<OrderLineContact__c>{ successOlc, failOlc }
            );
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            null,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :successOlc.Id].DeltaScenario__c
        );
        System.assertEquals(
            TASTeamAccessSelector.DELTA_INSERT_RECORD,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :failOlc.Id].DeltaScenario__c
        );
    }

    /**
     * @description
     * Verifies unresolved AssignedSalesRep__c leaves scenario unchanged and creates no team members.
     *
     * @return void
     */
    @IsTest
    static void testServiceProcessFailsRowWhenUserNotResolved() {
        /********************************************
        * SETUP
        ********************************************/
        OrderLineContact__c olc = buildOlc(
            EMP_NO_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        insert olc;
        olc.AssignedSalesRep__c = null;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember]);

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TASTeamAccessService.process(new List<OrderLineContact__c>{ olc });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            TASTeamAccessSelector.DELTA_INSERT_RECORD,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :olc.Id].DeltaScenario__c
        );
        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember]);
    }

    // --- Bulk processing ---

    /**
     * @description
     * Verifies service.process handles a bulk insert list in one call with deduplicated team DML.
     *
     * @return void
     */
    @IsTest
    static void testServiceProcessBulkInsertClearsAllRows() {
        /********************************************
        * SETUP
        ********************************************/
        User rep = getSalesRep();
        Account acc = getTestAccount();

        // Same address + rep on every row — service should dedupe team member DML
        List<OrderLineContact__c> bulkRows = buildOlcList(
            BULK_ROW_COUNT,
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        insert bulkRows;
        Set<Id> olcIds = toIdSet(bulkRows);

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, countAtmTasAssigned(acc.Id, rep.Id));
        System.assertEquals(
            BULK_ROW_COUNT,
            countOlcsWithScenario(olcIds, TASTeamAccessSelector.DELTA_INSERT_RECORD)
        );

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TASTeamAccessService.process(bulkRows);
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            BULK_ROW_COUNT,
            countOlcsWithClearedScenario(olcIds),
            'All bulk insert rows should clear DeltaScenario__c'
        );
        System.assertEquals(
            1,
            countAtmTasAssigned(acc.Id, rep.Id),
            'Team member insert should be deduplicated across bulk rows'
        );
    }

    /**
     * @description
     * Verifies service.process bulk-deletes all delete-scenario staging rows in one pass.
     *
     * @return void
     */
    @IsTest
    static void testServiceProcessBulkDeleteRemovesAllStagingRows() {
        /********************************************
        * SETUP
        ********************************************/
        // No pre-existing team rows — delete path should still drop staging records
        List<OrderLineContact__c> bulkRows = buildOlcList(
            BULK_ROW_COUNT,
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_DELETE_RECORD
        );
        insert bulkRows;
        Set<Id> olcIds = toIdSet(bulkRows);

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(BULK_ROW_COUNT, [SELECT COUNT() FROM OrderLineContact__c WHERE Id IN :olcIds]);

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TASTeamAccessService.process(bulkRows);
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            0,
            [SELECT COUNT() FROM OrderLineContact__c WHERE Id IN :olcIds],
            'All bulk delete staging rows should be removed'
        );
    }

    /**
     * @description
     * Verifies batch clears all bulk insert rows in a single test execute (scope matches row count).
     *
     * @return void
     */
    @IsTest
    static void testBatchProcessesBulkInsertInSingleTestExecute() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();

        List<OrderLineContact__c> bulkRows = buildOlcList(
            BULK_ROW_COUNT,
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        insert bulkRows;
        Set<Id> olcIds = toIdSet(bulkRows);

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(
            BULK_ROW_COUNT,
            countOlcsWithScenario(olcIds, TASTeamAccessSelector.DELTA_INSERT_RECORD)
        );

        /********************************************
        * WHEN
        ********************************************/
        // runBatch() passes scope = pending row count so we don't hit the double-enqueue limit
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
            countOlcsWithClearedScenario(olcIds),
            'Batch should process all bulk rows within the single test execute invocation'
        );
    }

    /**
     * @description
     * Verifies bulk scope with mixed valid and invalid rows does not block successful rows.
     *
     * @return void
     */
    @IsTest
    static void testServiceBulkMixedValidAndInvalidRows() {
        /********************************************
        * SETUP
        ********************************************/
        Integer validCount = BULK_ROW_COUNT / 2;
        Integer invalidCount = BULK_ROW_COUNT - validCount; // 25 + 25 when BULK_ROW_COUNT is 50

        List<OrderLineContact__c> validRows = buildOlcList(
            validCount,
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        List<OrderLineContact__c> invalidRows = buildOlcList(
            invalidCount,
            EMP_MATCH,
            BAD_ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        List<OrderLineContact__c> allRows = new List<OrderLineContact__c>();
        allRows.addAll(validRows);
        allRows.addAll(invalidRows);
        insert allRows;

        Set<Id> validIds = toIdSet(validRows);
        Set<Id> invalidIds = toIdSet(invalidRows);

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(validCount, countOlcsWithScenario(validIds, TASTeamAccessSelector.DELTA_INSERT_RECORD));
        System.assertEquals(invalidCount, countOlcsWithScenario(invalidIds, TASTeamAccessSelector.DELTA_INSERT_RECORD));

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TASTeamAccessService.process(allRows);
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(validCount, countOlcsWithClearedScenario(validIds), 'Valid bulk rows should clear');
        System.assertEquals(
            invalidCount,
            countOlcsWithScenario(invalidIds, TASTeamAccessSelector.DELTA_INSERT_RECORD),
            'Invalid bulk rows should remain for retry'
        );
    }

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
        // Don't call real flex-queue SOQL in test — we're only proving submitBatch enqueues
        TASTeamAccessBatch.isSkipFlexQueueCheckForTest = true;
        insert buildOlc(EMP_MATCH, ADDR_ID, TASTeamAccessSelector.DELTA_INSERT_RECORD);

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(1, countPendingStagingRows());
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE JobType = 'BatchApex'
                  AND ApexClass.Name = 'TASTeamAccessBatch'
            ]
        );

        /********************************************
        * WHEN
        ********************************************/
        Id jobId;
        Test.startTest();
        System.runAs(getRunAsUser()) {
            // submitBatch() on batch class; one pending row is fine with default scope in test
            jobId = TASTeamAccessBatch.submitBatch();
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
                  AND ApexClass.Name = 'TASTeamAccessBatch'
            ]
        );
    }

    /**
     * @description
     * Verifies submitBatch throws when flex queue is at capacity (no second batch enqueue).
     *
     * @return void
     */
    @IsTest
    static void testSubmitBatchThrowsWhenFlexQueueFull() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();
        // Pretend the holding queue is already full — assertFlexQueueHasCapacity should bail early
        TASTeamAccessBatch.testFlexQueueHoldingCountOverride =
            TASTeamAccessBatch.FLEX_QUEUE_MAX_BATCH_JOBS;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(
            TASTeamAccessBatch.FLEX_QUEUE_MAX_BATCH_JOBS,
            TASTeamAccessBatch.testFlexQueueHoldingCountOverride
        );

        /********************************************
        * WHEN / THEN
        ********************************************/
        Boolean threw = false;
        try {
            // No Test.startTest — we never want a second executeBatch here
            TASTeamAccessBatch.submitBatch();
        } catch (TASTeamAccessException e) {
            threw = true;
            System.assert(e.getMessage().contains('flex queue'), e.getMessage());
        }
        System.assert(threw, 'submitBatch should throw when flex queue is full');
    }

    // --- Batch error handling ---

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
            insert buildOlc(
                EMP_MATCH,
                ADDR_ID,
                TASTeamAccessSelector.DELTA_INSERT_RECORD
            );
            TASTeamAccessBatch.isThrowInExecute = true;

            /********************************************
            * GIVEN
            ********************************************/
            System.assertEquals(0, TASTeamAccessBatch.executeCatchCount);

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
            System.assert(TASTeamAccessBatch.executeCatchCount > 0, 'Execute errors should be caught');
            System.assertEquals(0, TASTeamAccessBatch.finishCatchCount);
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
            insert buildOlc(
                EMP_MATCH,
                ADDR_ID,
                TASTeamAccessSelector.DELTA_INSERT_RECORD
            );
            TASTeamAccessBatch.isThrowInFinish = true;

            /********************************************
            * GIVEN
            ********************************************/
            System.assertEquals(0, TASTeamAccessBatch.finishCatchCount);

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
            System.assert(TASTeamAccessBatch.finishCatchCount > 0, 'Finish errors should be caught');
            System.assertEquals(0, TASTeamAccessBatch.executeCatchCount);
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
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();
        TASTeamAccessBatch.isThrowInStart = true;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, TASTeamAccessBatch.startCatchCount);

        /********************************************
        * WHEN / THEN
        ********************************************/
        Boolean threw = false;
        try {
            System.runAs(getRunAsUser()) {
                // Call start() directly — avoids a failed AsyncApexJob titled "Test start failure"
                new TASTeamAccessBatch().start(null);
            }
            System.assert(false, 'Expected start to throw');
        } catch (Exception e) {
            threw = true;
            System.assertNotEquals(null, e);
        }

        /********************************************
        * THEN
        ********************************************/
        System.assert(threw, 'start() should rethrow after logging');
        System.assertEquals(1, TASTeamAccessBatch.startCatchCount);
        System.assertEquals(0, TASTeamAccessBatch.executeCatchCount);
        System.assertEquals(0, TASTeamAccessBatch.finishCatchCount);

        resetBatchFlags();
    }

    // --- Schedulable (same class as batch) ---

    /**
     * @description
     * Verifies Schedulable execute queues exactly one TASTeamAccessBatch job.
     *
     * @return void
     */
    @IsTest
    static void testSchedulableExecuteQueuesSingleBatchJob() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();
        TASTeamAccessBatch.isSkipFlexQueueCheckForTest = true;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE JobType = 'BatchApex'
                  AND ApexClass.Name = 'TASTeamAccessBatch'
            ]
        );

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(getRunAsUser()) {
            new TASTeamAccessBatch().execute(null);
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
                  AND ApexClass.Name = 'TASTeamAccessBatch'
            ],
            'Schedulable should queue one batch job'
        );

        resetBatchFlags();
    }

    /**
     * @description
     * Verifies Schedulable execute processes Insert Record rows and clears DeltaScenario__c.
     *
     * @return void
     */
    @IsTest
    static void testSchedulableExecuteProcessesInsertScenarioEndToEnd() {
        /********************************************
        * SETUP
        ********************************************/
        resetBatchFlags();
        TASTeamAccessBatch.isSkipFlexQueueCheckForTest = true;

        OrderLineContact__c olc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        insert olc;

        User rep = getSalesRep();
        Account acc = getTestAccount();

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id AND UserId = :rep.Id]);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(getRunAsUser()) {
            new TASTeamAccessBatch().execute(null);
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            1,
            [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id AND UserId = :rep.Id],
            'Schedulable-driven batch should grant account team access'
        );
        System.assertEquals(
            null,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :olc.Id].DeltaScenario__c
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
        TASTeamAccessService.testOnly_invokeLogDmlErrors();

        /********************************************
        * THEN
        ********************************************/
        System.assert(true, 'logDmlErrors branches executed without unhandled exception');
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
        TASTeamAccessService.testOnly_forceCommonReadSecurityFailure = true;

        OrderLineContact__c olc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        insert olc;

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(
            TASTeamAccessSelector.DELTA_INSERT_RECORD,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :olc.Id].DeltaScenario__c
        );

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TASTeamAccessService.process(new List<OrderLineContact__c>{ olc });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            TASTeamAccessSelector.DELTA_INSERT_RECORD,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :olc.Id].DeltaScenario__c,
            'Insert should not run when common read security fails'
        );

        resetServiceTestFlags();
    }

    /**
     * @description
     * Verifies process skips insert when insert security check fails.
     *
     * @return void
     */
    @IsTest
    static void testServiceSkipsInsertWhenInsertSecurityFails() {
        /********************************************
        * SETUP
        ********************************************/
        resetServiceTestFlags();
        TASTeamAccessService.testOnly_forceInsertSecurityFailure = true;

        OrderLineContact__c olc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        insert olc;

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TASTeamAccessService.process(new List<OrderLineContact__c>{ olc });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            TASTeamAccessSelector.DELTA_INSERT_RECORD,
            [SELECT DeltaScenario__c FROM OrderLineContact__c WHERE Id = :olc.Id].DeltaScenario__c
        );

        resetServiceTestFlags();
    }

    /**
     * @description
     * Verifies process skips delete when delete security check fails.
     *
     * @return void
     */
    @IsTest
    static void testServiceSkipsDeleteWhenDeleteSecurityFails() {
        /********************************************
        * SETUP
        ********************************************/
        resetServiceTestFlags();
        TASTeamAccessService.testOnly_forceDeleteSecurityFailure = true;

        OrderLineContact__c olc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_DELETE_RECORD
        );
        insert olc;

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(getRunAsUser()) {
            TASTeamAccessService.process(new List<OrderLineContact__c>{ olc });
        }

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, [SELECT COUNT() FROM OrderLineContact__c WHERE Id = :olc.Id]);

        resetServiceTestFlags();
    }

    // --- GC-2596 - Deletion freeze window (Custom Label TAS_FreezeWindow) ---

    /**
     * @description
     * GC-2596 - Verifies malformed TAS_FreezeWindow label aborts batch start and logs via Nebula Logger.
     *
     * @return void
     */
    @IsTest
    static void testInvalidFreezeWindowLabelAbortsBatchStart() {
        resetBatchFlags();
        TASFreezeWindowUtil.testLabelOverride = '08/10/2026|20/10/2026';

        System.assertEquals(0, TASTeamAccessBatch.startCatchCount);

        Test.startTest();
        Boolean threw = false;
        try {
            System.runAs(getRunAsUser()) {
                new TASTeamAccessBatch().start(null);
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
        System.assertEquals(1, TASTeamAccessBatch.startCatchCount);
        System.assertEquals(0, TASTeamAccessBatch.executeCatchCount);
    }

    /**
     * @description
     * GC-2596 - Verifies Delete Record rows are not processed while the TAS freeze window is active.
     *
     * @return void
     */
    @IsTest
    static void testDeletionFreezeSkipsDeleteDuringActiveWindow() {
        resetBatchFlags();
        TASFreezeWindowUtil.testLabelOverride = '08/10/2026|08/20/2026';
        TASFreezeWindowUtil.testTodayOverride = Date.newInstance(2026, 8, 15);

        User rep = getSalesRep();
        Account acc = getTestAccount();

        insert newTestAccountTeamMember(
            acc.Id,
            rep.Id,
            TASTeamAccessService.TEAM_MEMBER_ROLE_SALES
        );

        OrderLineContact__c deleteOlc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_DELETE_RECORD
        );
        insert deleteOlc;

        Test.startTest();
        System.runAs(getRunAsUser()) {
            runBatch();
        }
        Test.stopTest();

        System.assertEquals(1, countAtmTasAssigned(acc.Id, rep.Id));
        System.assertEquals(1, [
            SELECT COUNT()
            FROM OrderLineContact__c
            WHERE Id = :deleteOlc.Id
              AND DeltaScenario__c = :TASTeamAccessSelector.DELTA_DELETE_RECORD
        ]);
    }

    /**
     * @description
     * GC-2596 - Verifies Insert Record rows still process while the TAS freeze window is active.
     *
     * @return void
     */
    @IsTest
    static void testDeletionFreezeStillProcessesInsertDuringActiveWindow() {
        resetBatchFlags();
        TASFreezeWindowUtil.testLabelOverride = '08/10/2026|08/20/2026';
        TASFreezeWindowUtil.testTodayOverride = Date.newInstance(2026, 8, 15);

        User rep = getSalesRep();
        Account acc = getTestAccount();

        OrderLineContact__c insertOlc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_INSERT_RECORD
        );
        insert insertOlc;

        Test.startTest();
        System.runAs(getRunAsUser()) {
            runBatch();
        }
        Test.stopTest();

        System.assertEquals(1, countAtmTasAssigned(acc.Id, rep.Id));
        System.assertEquals(0, [
            SELECT COUNT()
            FROM OrderLineContact__c
            WHERE Id = :insertOlc.Id
              AND DeltaScenario__c = :TASTeamAccessSelector.DELTA_INSERT_RECORD
        ]);
    }

    /**
     * @description
     * GC-2596 - Verifies Delete Record rows process normally when today is outside the freeze window.
     *
     * @return void
     */
    @IsTest
    static void testDeletionFreezeProcessesDeleteAfterWindowEnds() {
        resetBatchFlags();
        TASFreezeWindowUtil.testLabelOverride = '08/10/2026|08/20/2026';
        TASFreezeWindowUtil.testTodayOverride = Date.newInstance(2026, 8, 21);

        User rep = getSalesRep();
        Account acc = getTestAccount();

        insert newTestAccountTeamMember(
            acc.Id,
            rep.Id,
            TASTeamAccessService.TEAM_MEMBER_ROLE_SALES
        );

        OrderLineContact__c deleteOlc = buildOlc(
            EMP_MATCH,
            ADDR_ID,
            TASTeamAccessSelector.DELTA_DELETE_RECORD
        );
        insert deleteOlc;

        Test.startTest();
        System.runAs(getRunAsUser()) {
            runBatch();
        }
        Test.stopTest();

        System.assertEquals(
            0,
            countAtmTasAssigned(acc.Id, rep.Id),
            'Oracle Assigned team member should be removed after freeze window ends'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM OrderLineContact__c WHERE Id = :deleteOlc.Id],
            'Delete staging row should be removed after freeze window ends'
        );
    }

    
}