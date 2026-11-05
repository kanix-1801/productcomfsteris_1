/**
 * @author PWC Developer
 * @date 2026/06/15
 *
 * @group Temporary Access Exception
 *
 * @description
 * Test data factory for Temporary Access Exception batch, service, and email tests.
 * Centralizes user, account, opportunity, team member, and TemporaryAccessException__c creation.
 * TemporaryAccessException__c builders satisfy validation rules TER_001 through TER_003 (GC-2580).
 * GC-3345 - AccountTeamMember test seeds set OpportunityAccessLevel to Edit.
 */
@IsTest(SeeAllData=false)
public class TestDataFactory {

    public static final String EMP_REQUESTER = 'TAE-REQ-10001';
    public static final String EMP_COVERAGE_REP = 'TAE-COV-10002';
    public static final String ACCOUNT_NAME = 'TAE Team Access Account';
    public static final String OPP_NAME = 'TAE Team AccessinsertOverlayTestUser Opportunity';
    public static final String REQUESTER_TEAM_ROLE = 'Account Manager';
    public static final String REQUESTER_TERRITORY_CODE = 'TAE-TERR-001';
    public static final String REQUESTER_SALES_CATEGORY_CODE = 'SURG SPT';
    public static final String REQUESTER_SALES_CATEGORY_DESCRIPTION = 'Surgical Support';

    private static String cachedOracleCustomerIdField;

    /**
     * @description
     * Holds Ids for the standard grant/revoke test scenario created by setupBaseScenario.
     */
    public class ScenarioContext {
        public Id requesterId;
        public Id coverageRepId;
        public Id accountId;
        public Id opportunityId;
        public Boolean hasOpportunity;
    }

    /**
     * @description
     * Creates requester, coverage rep, account, opportunity, and requester team memberships.
     * Assigns System_Administrator and SalesFieldRepAccountManager directly to the requester
     * (TASServiceTest pattern). Replaces PSG assignment so tests fail clearly when PS are missing.
     *
     * @return ScenarioContext with core record Ids for tests
     * @example
     * TestDataFactory.setupBaseScenario();
     */
    public static ScenarioContext setupBaseScenario() {
        disableTemporaryAccessAutomationForTest();

        User requester = insertUser('TAE', 'Requester', 'taereq', EMP_REQUESTER);
        User coverageRep = insertUser('TAE', 'CoverageRep', 'taecov', EMP_COVERAGE_REP);

        System.runAs(requester) {
            assignFieldRepTestPermissionSets(requester.Id);
        }

        ScenarioContext ctx = new ScenarioContext();
        ctx.requesterId = requester.Id;
        ctx.coverageRepId = coverageRep.Id;
        ctx.hasOpportunity = false;

        // Non-setup DML after permission set assignment — mirrors OLC @TestSetup ordering
        Account acc = newCustomerAccount(ACCOUNT_NAME);
        insert acc;
        ctx.accountId = acc.Id;

        insert new AccountTeamMember(
            AccountId = acc.Id,
            UserId = requester.Id,
            TeamMemberRole = REQUESTER_TEAM_ROLE,
            AccountAccessLevel = 'Edit',
            OpportunityAccessLevel = 'Edit', // GC-3345
            CaseAccessLevel = 'Read',
            TerritoryCode__c = REQUESTER_TERRITORY_CODE,
            SalesCategoryCode__c = REQUESTER_SALES_CATEGORY_CODE,
            SalesCategoryDescription__c = REQUESTER_SALES_CATEGORY_DESCRIPTION
        );

        ctx.opportunityId = tryInsertOpportunityTeamSetup(acc.Id, requester.Id, ctx);

        return ctx;
    }

    /**
     * @description
     * Alias for setupBaseScenario — both use direct field-rep permission set assignment.
     *
     * @return ScenarioContext with core record Ids for tests
     */
    public static ScenarioContext setupFieldRepScenario() {
        return setupBaseScenario();
    }

    /**
     * @description
     * Attempts to create an Opportunity and requester OTM; returns null when org automation blocks insert.
     */
    private static Id tryInsertOpportunityTeamSetup(Id accountId, Id requesterId, ScenarioContext ctx) {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Opportunity'
              AND IsActive = true
        ];

        List<String> stageCandidates = new List<String>{
            'Qualification',
            'Discovery',
            'Evaluate',
            'Proposal',
            'Commit',
            'Negotiation',
            'Prospecting'
        };

        List<OpportunityInsertCandidate> candidates = buildOpportunityInsertCandidates(recordTypes, stageCandidates);
        for (OpportunityInsertCandidate candidate : candidates) {
            Id opportunityId = tryInsertOpportunityCandidate(
                accountId,
                requesterId,
                ctx,
                candidate.stageName,
                candidate.recordTypeId
            );
            if (opportunityId != null) {
                return opportunityId;
            }
        }

        return null;
    }

    private class OpportunityInsertCandidate {
        Id recordTypeId;
        String stageName;

        OpportunityInsertCandidate(Id recordTypeId, String stageName) {
            this.recordTypeId = recordTypeId;
            this.stageName = stageName;
        }
    }

    private static List<OpportunityInsertCandidate> buildOpportunityInsertCandidates(
        List<RecordType> recordTypes,
        List<String> stageCandidates
    ) {
        List<OpportunityInsertCandidate> candidates = new List<OpportunityInsertCandidate>();
        if (recordTypes.isEmpty()) {
            for (String stageName : stageCandidates) {
                candidates.add(new OpportunityInsertCandidate(null, stageName));
            }
            return candidates;
        }

        for (RecordType recordType : recordTypes) {
            for (String stageName : stageCandidates) {
                candidates.add(new OpportunityInsertCandidate(recordType.Id, stageName));
            }
        }
        return candidates;
    }

    private static Id tryInsertOpportunityCandidate(
        Id accountId,
        Id requesterId,
        ScenarioContext ctx,
        String stageName,
        Id recordTypeId
    ) {
        try {
            Opportunity opp = new Opportunity(
                Name = OPP_NAME,
                AccountId = accountId,
                StageName = stageName,
                CloseDate = Date.today().addDays(30)
            );
            if (recordTypeId != null) {
                opp.RecordTypeId = recordTypeId;
            }
            populateForecastConfidenceIfPossible(opp);
            insert opp;

            insert new OpportunityTeamMember(
                OpportunityId = opp.Id,
                UserId = requesterId,
                TeamMemberRole = REQUESTER_TEAM_ROLE,
                OpportunityAccessLevel = 'Edit'
            );

            ctx.hasOpportunity = true;
            return opp.Id;
        } catch (Exception e) {
            // Flow "Opportunity Stage to FCL" may set an invalid ForecastConfidenceLevel__c in this org
            return null;
        }
    }

    private static void populateForecastConfidenceIfPossible(Opportunity opp) {
        try {
            Schema.DescribeFieldResult forecastDescribe =
                Opportunity.ForecastConfidenceLevel__c.getDescribe();
            if (!forecastDescribe.getPicklistValues().isEmpty()) {
                opp.put(
                    'ForecastConfidenceLevel__c',
                    forecastDescribe.getPicklistValues()[0].getValue()
                );
            }
        } catch (Exception e) {
            // Optional in some orgs
        }
    }

    /**
     * @description
     * Builds a grant-scenario TemporaryAccessException__c row (Approved + StartDate = today).
     * StartDate and EndDate satisfy TER_001 and TER_003; Exception Category avoids Other per TER_002.
     *
     * @param requesterId Requester__c lookup
     * @param coverageRepId CoverageRep__c lookup
     * @return TemporaryAccessException__c instance ready for insert
     */
    public static TemporaryAccessException__c buildGrantTae(Id requesterId, Id coverageRepId) {
        TemporaryAccessException__c tae = new TemporaryAccessException__c(
            Requester__c = requesterId,
            CoverageRep__c = coverageRepId,
            Status__c = TAEWorkItemService.HEADER_APPROVED,
            StartDate__c = Date.today(),
            EndDate__c = Date.today().addDays(30)
        );
        populateOptionalTaeFields(tae);
        return tae;
    }

    /**
     * @description
     * Builds an Active TemporaryAccessException__c row that can be inserted in test context.
     * StartDate is today (TER_003) and EndDate is in the future (TER_001). Call
     * prepareRevokeRowForProcessing before service.process for revoke eligibility in memory.
     * updateEndDateToTodayForBatch cannot persist EndDate = today while TER_001 is active.
     *
     * @param requesterId Requester__c lookup
     * @param coverageRepId CoverageRep__c lookup
     * @return TemporaryAccessException__c instance ready for insert
     */
    public static TemporaryAccessException__c buildRevokeTae(Id requesterId, Id coverageRepId) {
        TemporaryAccessException__c tae = new TemporaryAccessException__c(
            Requester__c = requesterId,
            CoverageRep__c = coverageRepId,
            Status__c = TAEWorkItemService.HEADER_ACTIVE,
            StartDate__c = Date.today(),
            EndDate__c = Date.today().addDays(30)
        );
        populateOptionalTaeFields(tae);
        return tae;
    }

    /**
     * @description
     * Disables Temporary Access Exception approval orchestration flows in test context
     * via Automation_Setting_Flow__c hierarchy custom settings.
     *
     * @return void
     */
    public static void disableTemporaryAccessAutomationForTest() {
        try {
            Automation_Setting_Flow__c flowSettings = Automation_Setting_Flow__c.getOrgDefaults();
            if (flowSettings == null || flowSettings.Id == null) {
                flowSettings = new Automation_Setting_Flow__c(
                    SetupOwnerId = UserInfo.getOrganizationId()
                );
            }
            flowSettings.TemporaryAccessApprovalProcess__c = true;
            upsert flowSettings;
        } catch (Exception e) {
            // Automation_Setting_Flow__c optional in some orgs
        }
    }

    /**
     * @description
     * Inserts a grant-scenario row and ensures Approved status persists for batch and selector tests.
     *
     * @param requesterId Requester__c lookup
     * @param coverageRepId CoverageRep__c lookup
     * @return Inserted TemporaryAccessException__c row with processing fields populated
     */
    public static TemporaryAccessException__c insertGrantTae(Id requesterId, Id coverageRepId) {
        TemporaryAccessException__c tae = buildGrantTae(requesterId, coverageRepId);
        insert tae;
        ensurePersistedStatus(tae.Id, TAEWorkItemService.HEADER_APPROVED);
        return queryProcessingTaeById(tae.Id);
    }

    /**
     * @description
     * Inserts multiple grant-scenario rows for bulk batch coverage.
     *
     * @param requesterId Requester__c lookup
     * @param coverageRepId CoverageRep__c lookup
     * @param rowCount Number of rows to insert
     * @return Inserted TemporaryAccessException__c rows with processing fields populated
     */
    public static List<TemporaryAccessException__c> insertGrantTaeBulk(
        Id requesterId,
        Id coverageRepId,
        Integer rowCount
    ) {
        List<TemporaryAccessException__c> rows = new List<TemporaryAccessException__c>();
        for (Integer i = 0; i < rowCount; i++) {
            rows.add(buildGrantTae(requesterId, coverageRepId));
        }
        insert rows;

        Set<Id> rowIds = new Map<Id, TemporaryAccessException__c>(rows).keySet();
        ensurePersistedStatusBulk(rowIds, TAEWorkItemService.HEADER_APPROVED);
        return queryProcessingTaeByIds(rowIds);
    }

    /**
     * @description
     * Inserts an Active revoke-scenario row and ensures Active status persists for service tests.
     *
     * @param requesterId Requester__c lookup
     * @param coverageRepId CoverageRep__c lookup
     * @return Inserted TemporaryAccessException__c row with processing fields populated
     */
    public static TemporaryAccessException__c insertRevokeTae(Id requesterId, Id coverageRepId) {
        TemporaryAccessException__c tae = buildRevokeTae(requesterId, coverageRepId);
        insert tae;
        ensurePersistedStatus(tae.Id, TAEWorkItemService.HEADER_ACTIVE);
        return queryProcessingTaeById(tae.Id);
    }

    /**
     * @description
     * Aligns an inserted revoke row with the nightly revoke selector (EndDate = today) in memory.
     * Does not perform DML; TER_001 blocks persisting EndDate = today on update.
     *
     * @param tae Inserted TemporaryAccessException__c row
     * @return Same row with EndDate__c set to today for service.process
     */
    public static TemporaryAccessException__c prepareRevokeRowForProcessing(TemporaryAccessException__c tae) {
        tae.EndDate__c = Date.today();
        return tae;
    }

    /**
     * @description
     * Updates an inserted Active row so the batch locator selects it for revoke processing.
     * Will fail with TER_001 when End Date Must Be a Future Date validation is active.
     *
     * @param taeId TemporaryAccessException__c Id
     * @return Updated row from the database
     */
    public static TemporaryAccessException__c updateEndDateToTodayForBatch(Id taeId) {
        update new TemporaryAccessException__c(
            Id = taeId,
            EndDate__c = Date.today()
        );
        return [
            SELECT Id, Name, StartDate__c, EndDate__c, Status__c, Requester__c, CoverageRep__c
            FROM TemporaryAccessException__c
            WHERE Id = :taeId
        ];
    }

    /**
     * @description
     * Inserts Temporary Coverage Rep account team membership for revoke and idempotency tests.
     *
     * @param accountId Account Id
     * @param coverageRepId Coverage rep user Id
     * @return Inserted AccountTeamMember
     */
    public static AccountTeamMember insertAccountTeamMemberWithRoleAndAssignment(
        Id accountId,
        Id userId,
        String teamMemberRole,
        String assignmentType,
        Date expiryDate
    ) {
        AccountTeamMember atm = new AccountTeamMember(
            AccountId = accountId,
            UserId = userId,
            TeamMemberRole = teamMemberRole,
            AssignmentType__c = assignmentType,
            ExpiryDate__c = expiryDate,
            AccountAccessLevel = 'Edit',
            OpportunityAccessLevel = 'Edit', // GC-3345
            CaseAccessLevel = 'Read'
        );
        insert atm;
        return atm;
    }


    /**
     * @description
     * Inserts temporary assignment account team membership for revoke and idempotency tests.
     *
     * @param accountId Account Id
     * @param coverageRepId Coverage rep user Id
     * @param expiryDate ExpiryDate__c value; defaults to today when null
     * @return Inserted AccountTeamMember
     */
    public static AccountTeamMember insertTemporaryCoverageRepAccountTeamMember(
        Id accountId,
        Id coverageRepId,
        Date expiryDate
    ) {
        AccountTeamMember atm = new AccountTeamMember(
            AccountId = accountId,
            UserId = coverageRepId,
            TeamMemberRole = TAEWorkItemService.ROLE_SALES,
            AssignmentType__c = TAEWorkItemService.ASSIGNMENT_TEMPORARY,
            ExpiryDate__c = expiryDate != null ? expiryDate : Date.today(),
            AccountAccessLevel = 'Edit',
            OpportunityAccessLevel = 'Edit', // GC-3345
            CaseAccessLevel = 'Read'
        );
        insert atm;
        return atm;
    }

    /**
     * @description
     * Inserts Temporary Coverage Rep opportunity team membership for revoke and idempotency tests.
     *
     * @param opportunityId Opportunity Id
     * @param coverageRepId Coverage rep user Id
     * @return Inserted OpportunityTeamMember
     */
    public static OpportunityTeamMember insertTemporaryCoverageRepOpportunityTeamMember(
        Id opportunityId,
        Id coverageRepId
    ) {
        return insertTemporaryCoverageRepOpportunityTeamMember(opportunityId, coverageRepId, null);
    }

    /**
     * @description
     * Inserts temporary assignment opportunity team membership for revoke and idempotency tests.
     *
     * @param opportunityId Opportunity Id
     * @param coverageRepId Coverage rep user Id
     * @param expiryDate ExpiryDate__c value; defaults to today when null
     * @return Inserted OpportunityTeamMember
     */
    public static OpportunityTeamMember insertTemporaryCoverageRepOpportunityTeamMember(
        Id opportunityId,
        Id coverageRepId,
        Date expiryDate
    ) {
        OpportunityTeamMember otm = new OpportunityTeamMember(
            OpportunityId = opportunityId,
            UserId = coverageRepId,
            TeamMemberRole = TAEWorkItemService.ROLE_SALES,
            AssignmentType__c = TAEWorkItemService.ASSIGNMENT_TEMPORARY,
            ExpiryDate__c = expiryDate != null ? expiryDate : Date.today(),
            OpportunityAccessLevel = 'Edit'
        );
        insert otm;
        return otm;
    }

    /**
     * @description
     * Seeds Temporary Coverage Rep memberships on the standard account and opportunity.
     *
     * @param ctx ScenarioContext from setupBaseScenario
     * @return void
     */
    public static void seedTemporaryCoverageRepTeamMembers(ScenarioContext ctx) {
        insertTemporaryCoverageRepAccountTeamMember(ctx.accountId, ctx.coverageRepId, Date.today());
        if (ctx.hasOpportunity == true && ctx.opportunityId != null) {
            insertTemporaryCoverageRepOpportunityTeamMember(ctx.opportunityId, ctx.coverageRepId, Date.today());
        }
    }

    /**
     * @description
     * Returns the requester user created in setupBaseScenario.
     *
     * @return Active User with EmployeeNumber__c = EMP_REQUESTER
     */
    public static User getRequester() {
        return [
            SELECT Id, Email, Name, IsActive
            FROM User
            WHERE EmployeeNumber__c = :EMP_REQUESTER
            LIMIT 1
        ];
    }

    /**
     * @description
     * Returns the coverage rep user created in setupBaseScenario.
     *
     * @return Active User with EmployeeNumber__c = EMP_COVERAGE_REP
     */
    public static User getCoverageRep() {
        return [
            SELECT Id, Email, Name, IsActive
            FROM User
            WHERE EmployeeNumber__c = :EMP_COVERAGE_REP
            LIMIT 1
        ];
    }

    /**
     * @description
     * Returns the standard test account from setupBaseScenario.
     *
     * @return Account Id wrapper
     */
    public static Account getTestAccount() {
        return [SELECT Id, OwnerId FROM Account WHERE Name = :ACCOUNT_NAME LIMIT 1];
    }

    /**
     * @description
     * Returns the standard test opportunity from setupBaseScenario.
     *
     * @return Opportunity Id wrapper
     */
    public static Opportunity getTestOpportunity() {
        return [SELECT Id, OwnerId FROM Opportunity WHERE Name = :OPP_NAME LIMIT 1];
    }

    /**
     * @description
     * Reloads ScenarioContext Ids from persisted setup data.
     *
     * @return ScenarioContext with current record Ids
     */
    public static ScenarioContext getScenarioContext() {
        ScenarioContext ctx = new ScenarioContext();
        ctx.requesterId = getRequester().Id;
        ctx.coverageRepId = getCoverageRep().Id;
        ctx.accountId = getTestAccount().Id;

        List<Opportunity> opps = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :OPP_NAME
            LIMIT 1
        ];
        ctx.hasOpportunity = !opps.isEmpty();
        ctx.opportunityId = ctx.hasOpportunity ? opps[0].Id : null;
        return ctx;
    }

    private static User insertUser(String firstName, String lastName, String aliasPrefix, String employeeNumber) {
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));

        User userRecord = new User(
            FirstName = firstName,
            LastName = lastName,
            Alias = (aliasPrefix + suffix).left(8),
            Email = aliasPrefix + '.' + suffix + '@test.com',
            Username = aliasPrefix + '.' + suffix + '@test.com',
            CommunityNickname = aliasPrefix + 'nick' + suffix,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = stdProfile.Id,
            EmployeeNumber__c = employeeNumber,
            IsActive = true
        );
        insert userRecord;
        return userRecord;
    }

    private static void assignSystemAdministratorPermissionSet(Id userId) {
        try {
            List<PermissionSet> permissionSets = [
                SELECT Id
                FROM PermissionSet
                WHERE Name = 'System_Administrator'
                LIMIT 1
            ];
            if (permissionSets.isEmpty()) {
                return;
            }
            insert new PermissionSetAssignment(
                AssigneeId = userId,
                PermissionSetId = permissionSets[0].Id
            );
        } catch (Exception e) {
            // Permission set optional in some orgs
        }
    }

    private static void assignFieldRepPermissionSetGroup(Id userId) {
        try {
            List<PermissionSetGroup> permissionSetGroups = [
                SELECT Id, Status
                FROM PermissionSetGroup
                WHERE DeveloperName = 'SalesFieldRepAccountManagerPSG'
                LIMIT 1
            ];
            if (permissionSetGroups.isEmpty()) {
                return;
            }
            
            // Force the group to "Updated" so assignments are allowed in test context
            Test.calculatePermissionSetGroup(permissionSetGroups[0].Id);

            insert new PermissionSetAssignment(
                AssigneeId = userId,
                PermissionSetGroupId = permissionSetGroups[0].Id
            );
        } catch (Exception e) {
            // Permission set group optional in some orgs
        }
    }

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

    private static User insertHealthcareSalesUser(
        String firstName,
        String lastName,
        String aliasPrefix,
        String employeeNumber,
        Id profileId
    ) {
        String uniqueSeed = String.valueOf(DateTime.now().getTime());
        User userRecord = new User(
            FirstName = firstName,
            LastName = lastName,
            Alias = aliasPrefix,
            Email = aliasPrefix + '.' + uniqueSeed + '@test.com',
            Username = aliasPrefix + '.' + uniqueSeed + '@test.com',
            CommunityNickname = aliasPrefix + 'nick' + Math.abs(Crypto.getRandomInteger()),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId,
            EmployeeNumber__c = employeeNumber,
            IsActive = true
        );
        insert userRecord;
        return userRecord;
    }

    private static void assignFieldRepTestPermissionSets(Id userId) {
        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name IN (
                'System_Administrator',
                'SalesFieldRepAccountManager'
            )
        ];

        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSet ps : permissionSets) {
            assignments.add(new PermissionSetAssignment(
                AssigneeId = userId,
                PermissionSetId = ps.Id
            ));
        }
        if (!assignments.isEmpty()) {
            insert assignments;
        }
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

    private static String uniqueSystemId15() {
        String value = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return value.length() <= 15 ? value : value.substring(0, 15);
    }

    private static void populateOptionalTaeFields(TemporaryAccessException__c tae) {
        String defaultCategory = resolveDefaultExceptionCategory();
        if (defaultCategory != null) {
            tae.ExceptionCategory__c = defaultCategory;
        }

        try {
            tae.BusinessJustification__c = 'Test business justification';
        } catch (Exception e) {
            // Optional in some orgs
        }
    }

    /**
     * @description
     * Returns the first active Exception Category picklist value other than Other (TER_002).
     *
     * @return Picklist API value safe for test inserts, or null when unavailable
     */
    private static String resolveDefaultExceptionCategory() {
        try {
            for (Schema.PicklistEntry entry :
                TemporaryAccessException__c.ExceptionCategory__c.getDescribe().getPicklistValues()) {
                if (entry.isActive() && entry.getValue() != 'Other') {
                    return entry.getValue();
                }
            }
        } catch (Exception e) {
            // Optional in some orgs
        }
        return null;
    }

    /**
     * @description
     * Returns the Other Exception Category picklist value when active in the org.
     *
     * @return Other category API value, or null when unavailable
     */
    public static String resolveOtherExceptionCategoryValue() {
        for (Schema.PicklistEntry entry :
            TemporaryAccessException__c.ExceptionCategory__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == 'Other') {
                return entry.getValue();
            }
        }
        return null;
    }

    private static TemporaryAccessException__c queryProcessingTaeById(Id taeId) {
        return [
            SELECT Id, Name, Status__c, StartDate__c, EndDate__c, Requester__c, CoverageRep__c
            FROM TemporaryAccessException__c
            WHERE Id = :taeId
        ];
    }

    private static List<TemporaryAccessException__c> queryProcessingTaeByIds(Set<Id> taeIds) {
        return [
            SELECT Id, Name, Status__c, StartDate__c, EndDate__c, Requester__c, CoverageRep__c
            FROM TemporaryAccessException__c
            WHERE Id IN :taeIds
        ];
    }

    private static void ensurePersistedStatus(Id taeId, String expectedStatus) {
        TemporaryAccessException__c persisted = [
            SELECT Id, Status__c
            FROM TemporaryAccessException__c
            WHERE Id = :taeId
            LIMIT 1
        ];
        if (persisted.Status__c != expectedStatus) {
            update new TemporaryAccessException__c(
                Id = taeId,
                Status__c = expectedStatus
            );
        }
    }

    private static void ensurePersistedStatusBulk(Set<Id> taeIds, String expectedStatus) {
        List<TemporaryAccessException__c> corrections = new List<TemporaryAccessException__c>();
        for (TemporaryAccessException__c persisted : [
            SELECT Id, Status__c
            FROM TemporaryAccessException__c
            WHERE Id IN :taeIds
        ]) {
            if (persisted.Status__c != expectedStatus) {
                corrections.add(new TemporaryAccessException__c(
                    Id = persisted.Id,
                    Status__c = expectedStatus
                ));
            }
        }
        if (!corrections.isEmpty()) {
            update corrections;
        }
    }

    // -------------------------------------------------------------------------
    // Overlay Assignment test data
    // -------------------------------------------------------------------------

    public static final String OVERLAY_TERRITORY_001 = 'TERR-001';
    public static final String OVERLAY_TERRITORY_002 = 'TERR-002';
    public static final String OVERLAY_CUSTOMER_ACCOUNT = 'Test Customer Account';
    public static final String OVERLAY_CUSTOMER_ACCOUNT_2 = 'Test Customer Account2';
    public static final String OVERLAY_PROSPECT_ACCOUNT = 'Test Prospect Account3';
    public static final String OVERLAY_OPP_A = 'Overlay Test Opportunity A';
    public static final String OVERLAY_OPP_B = 'Overlay Test Opportunity B';

    /**
     * @description
     * Creates accounts, contacts, TAS rows, and opportunities
     * for Overlay Assignment controller tests.
     */
    public static void setupOverlayAssignmentBaseScenario() {
        List<Account> accountList = new List<Account>{
            buildOverlayAccount(OVERLAY_CUSTOMER_ACCOUNT, 'A-001', getOverlayAccountTypeValue(0), '1234', 'Tas Addr 001'),
            buildOverlayAccount(OVERLAY_CUSTOMER_ACCOUNT_2, 'A-002', getOverlayAccountTypeValue(0), '5678', 'Tas Addr 003'),
            buildOverlayAccount(OVERLAY_PROSPECT_ACCOUNT, 'P-003', getOverlayAccountTypeValue(1), '9012', 'Tas Addr 004')
        };
        insert accountList;

        Map<String, Account> accountByNameMap = new Map<String, Account>();
        for (Account accountRecord : accountList) {
            accountByNameMap.put(accountRecord.Name, accountRecord);
        }

        List<Contact> contactList = new List<Contact>{
            new Contact(
                LastName = 'Test Customer Contact',
                AccountId = accountByNameMap.get(OVERLAY_CUSTOMER_ACCOUNT).Id
            ),
            new Contact(
                LastName = 'Test Customer Contact2',
                AccountId = accountByNameMap.get(OVERLAY_CUSTOMER_ACCOUNT_2).Id
            )
        };
        insert contactList;

        insert new List<OrderLineContact__c>{
            buildOverlayOrderLineContact('Tas Addr 001', OVERLAY_TERRITORY_001, 'North Region'),
            buildOverlayOrderLineContact('Tas Addr 002', OVERLAY_TERRITORY_001, 'North Region'),
            buildOverlayOrderLineContact('Tas Addr 003', OVERLAY_TERRITORY_001, 'North Region'),
            buildOverlayOrderLineContact('Tas Addr 004', OVERLAY_TERRITORY_002, 'South Region'),
            buildOverlayOrderLineContact('Tas Addr 005', null, 'Skipped North Region')
        };

        insertOverlayOpportunities(accountByNameMap, contactList);
    }

    /**
     * @description
     * Creates an active overlay test user and assigns SalesCustomerOpsSalesSupportSalesAdminPSG.
     *
     * @param firstName User first name
     * @param lastName User last name
     * @return Inserted User with permission set group assignment
     */
    public static User insertOverlayTestUser(String firstName, String lastName) {
        User overlayUser = buildOverlayTestUser(firstName, lastName);
        insert overlayUser;
        assignSalesCustomerOpsPermissionSetGroup(overlayUser.Id);
        return overlayUser;
    }

    /**
     * @description
     * Returns an Account created by setupOverlayAssignmentBaseScenario.
     *
     * @param accountName Account Name value
     * @return Matching Account record
     */
    public static Account getOverlayAccountByName(String accountName) {
        return [
            SELECT Id, Name, AccountNumber, Type
            FROM Account
            WHERE Name = :accountName
            LIMIT 1
        ];
    }

    /**
     * @description
     * Returns an active Account Type picklist value for overlay test data.
     *
     * @param indexValue Zero-based index into active picklist values
     * @return Picklist API value, or null when none are active
     */
    public static String getOverlayAccountTypeValue(Integer indexValue) {
        List<Schema.PicklistEntry> picklistEntryList = Account.Type.getDescribe().getPicklistValues();
        List<String> activeValueList = new List<String>();

        for (Schema.PicklistEntry picklistEntry : picklistEntryList) {
            if (picklistEntry.isActive()) {
                activeValueList.add(picklistEntry.getValue());
            }
        }

        if (activeValueList.isEmpty()) {
            return null;
        }

        Integer safeIndex = Math.min(indexValue, activeValueList.size() - 1);
        return activeValueList[safeIndex];
    }

    private static Account buildOverlayAccount(
        String accountName,
        String accountNumber,
        String accountType,
        String sourceSystemId,
        String oracleAddressId
    ) {
        Account accountRecord = new Account(
            Name = accountName,
            AccountNumber = accountNumber,
            Type = accountType
        );

        try {
            accountRecord.put('SourceSystemID__c', sourceSystemId);
        } catch (Exception e) {
            // SourceSystemID__c optional in some orgs
        }

        try {
            accountRecord.put('OracleAddressId__c', oracleAddressId);
        } catch (Exception e) {
            // OracleAddressId__c optional in some orgs
        }

        return accountRecord;
    }

    private static OrderLineContact__c buildOverlayOrderLineContact(
        String tasAddressId,
        String territoryId,
        String territoryDescription
    ) {
        OrderLineContact__c orderLineContact = new OrderLineContact__c();
        orderLineContact.TASAddressId__c = tasAddressId;
        orderLineContact.TerritoryID__c = territoryId;
        orderLineContact.TerritoryDescription__c = territoryDescription;
        orderLineContact.TerritoryNumber__c = String.isBlank(territoryId) ? null : territoryId.right(3);
        orderLineContact.BusinessUnit__c = 'Test Business Unit';
        orderLineContact.TASZone__c = 'Test Zone';
       // orderLineContact.ZoneName__c = 'Test Zone Name';
        orderLineContact.RegionName__c = 'Test Region';
        // GC-3352 - Source coverage fields copied onto overlay AccountTeamMember when matched.
        orderLineContact.TAS_Sales_Category__c = 'SURG SPT';
        orderLineContact.SalesCategoryDescription__c = 'Surgical Support';
        return orderLineContact;
    }

    private static void insertOverlayOpportunities(
        Map<String, Account> accountByNameMap,
        List<Contact> contactList
    ) {
        List<Opportunity> opportunityList = new List<Opportunity>{
            buildOverlayOpportunity(
                OVERLAY_OPP_A,
                accountByNameMap.get(OVERLAY_CUSTOMER_ACCOUNT).Id,
                contactList[0].Id
            ),
            buildOverlayOpportunity(
                OVERLAY_OPP_B,
                accountByNameMap.get(OVERLAY_CUSTOMER_ACCOUNT_2).Id,
                contactList[1].Id
            )
        };

        for (Opportunity opportunityRecord : opportunityList) {
            if (!tryInsertOverlayOpportunity(opportunityRecord)) {
                // Org automation may block Opportunity insert; overlay tests degrade without OTM assertions
            }
        }
    }

    private static Opportunity buildOverlayOpportunity(String opportunityName, Id accountId, Id contactId) {
        Opportunity opportunityRecord = new Opportunity(
            Name = opportunityName,
            AccountId = accountId,
            StageName = 'Discovery',
            PrimaryContact__c = contactId,
            CloseDate = Date.today().addDays(30),
            Probability = 10,
            Amount = 100,
            Type = 'Extension'
        );
        populateForecastConfidenceIfPossible(opportunityRecord);
        return opportunityRecord;
    }

    private static Boolean tryInsertOverlayOpportunity(Opportunity opportunityRecord) {
        List<String> stageCandidates = new List<String>{
            opportunityRecord.StageName,
            'Qualification',
            'Evaluate',
            'Proposal',
            'Commit',
            'Negotiation',
            'Prospecting'
        };

        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Opportunity'
              AND IsActive = true
        ];

        if (!recordTypes.isEmpty()) {
            for (RecordType recordType : recordTypes) {
                if (tryInsertOverlayOpportunityCandidate(opportunityRecord, stageCandidates, recordType.Id)) {
                    return true;
                }
            }
        }

        return tryInsertOverlayOpportunityCandidate(opportunityRecord, stageCandidates, null);
    }

    private static Boolean tryInsertOverlayOpportunityCandidate(
        Opportunity opportunityTemplate,
        List<String> stageCandidates,
        Id recordTypeId
    ) {
        for (String stageName : stageCandidates) {
            try {
                Opportunity opportunityRecord = opportunityTemplate.clone(false, true, false, false);
                opportunityRecord.StageName = stageName;
                if (recordTypeId != null) {
                    opportunityRecord.RecordTypeId = recordTypeId;
                }
                populateForecastConfidenceIfPossible(opportunityRecord);
                insert opportunityRecord;
                return true;
            } catch (Exception e) {
                // Flow "Opportunity Stage to FCL" may set an invalid ForecastConfidenceLevel__c in this org
            }
        }

        return false;
    }

    private static User buildOverlayTestUser(String firstName, String lastName) {
        Profile profileRecord = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        String uniqueValue = String.valueOf(System.currentTimeMillis());

        return new User(
            FirstName = firstName,
            LastName = lastName,
            Alias = firstName.left(2).toLowerCase() + lastName.left(2).toLowerCase(),
            Email = firstName.toLowerCase() + '.' + lastName.toLowerCase() + uniqueValue + '@example.com',
            Username = firstName.toLowerCase() + '.' + lastName.toLowerCase() + uniqueValue + '@example.com',
            CommunityNickname = firstName + lastName + uniqueValue,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileRecord.Id,
            EmployeeNumber__c = 'EMP' + uniqueValue.right(6),
            IsActive = true
        );
    }

    @TestVisible
    private static void assignSalesCustomerOpsPermissionSetGroup(Id userId) {
        List<PermissionSetGroup> psGroups = [
            SELECT Id, Status
            FROM PermissionSetGroup
            WHERE DeveloperName = 'SalesCustomerOpsSalesSupportSalesAdminPSG'
            LIMIT 1
        ];
        if (psGroups.isEmpty()) {
            return;
        }
        
        // Force the group to "Updated" so assignments are allowed in test context
        Test.calculatePermissionSetGroup(psGroups[0].Id);
        
        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetGroupId = psGroups[0].Id
        );
    }

    // -------------------------------------------------------------------------
    // Competitive Installed Base test data (GC-2860)
    // -------------------------------------------------------------------------

    public static final String CIB_GRANDPARENT_A_NAME = 'CIB Grandparent A';
    public static final String CIB_PARENT_A_NAME = 'CIB Customer Parent A';
    public static final String CIB_PARENT_B_NAME = 'CIB Customer Parent B';
    public static final String CIB_FACILITY_A1_NAME = 'CIB Facility A1';
    public static final String CIB_FACILITY_A2_NAME = 'CIB Facility A2';
    public static final String CIB_FACILITY_B1_NAME = 'CIB Facility B1';
    public static final String CIB_FACILITY_STANDALONE_NAME = 'CIB Facility Standalone';
    public static final String CIB_IDN_ACCOUNT_NAME = 'CIB IDN Account';
    public static final String CIB_GPO_ACCOUNT_NAME = 'CIB GPO Account';
    public static final String CIB_UNRELATED_ACCOUNT_NAME = 'CIB Unrelated Account';

    public static final String CIB_FACILITY_A1_ORACLE_ID = 'CIB-ORACLE-A1';
    public static final String CIB_FACILITY_A2_ORACLE_ID = 'CIB-ORACLE-A2';
    public static final String CIB_FACILITY_B1_ORACLE_ID = 'CIB-ORACLE-B1';
    public static final String CIB_FACILITY_STANDALONE_ORACLE_ID = 'CIB-ORACLE-STANDALONE';

    public static final String CIB_COMPETITOR_ALPHA = 'Competitor Alpha';
    public static final String CIB_COMPETITOR_BETA = 'Competitor Beta';

    public static final String CIB_SOURCE_GRANDPARENT_A = 'CIB-GRAND-A';
    public static final String CIB_SOURCE_PARENT_A = 'CIB-PARENT-A';
    public static final String CIB_SOURCE_PARENT_B = 'CIB-PARENT-B';
    public static final String CIB_SOURCE_FACILITY_A1 = 'CIB-FAC-A1';
    public static final String CIB_SOURCE_FACILITY_A2 = 'CIB-FAC-A2';
    public static final String CIB_SOURCE_FACILITY_B1 = 'CIB-FAC-B1';
    public static final String CIB_SOURCE_FACILITY_STANDALONE = 'CIB-FAC-STANDALONE';
    public static final String CIB_SOURCE_IDN = 'CIB-IDN-001';
    public static final String CIB_SOURCE_GPO = 'CIB-GPO-001';
    public static final String CIB_SOURCE_UNRELATED = 'CIB-UNRELATED';

    /**
     * @description Holds Ids for the competitive installed base hierarchy test scenario.
     */
    public class CompetitiveInstalledBaseScenarioContext {
        public Id grandparentAId;
        public Id parentAId;
        public Id parentBId;
        public Id facilityA1Id;
        public Id facilityA2Id;
        public Id facilityB1Id;
        public Id facilityStandaloneId;
        public Id idnAccountId;
        public Id gpoAccountId;
        public Id unrelatedAccountId;
    }

    /**
     * @description Creates facility, parent, grandparent, IDN, GPO, AAR, and competitive asset test data.
     * @return CompetitiveInstalledBaseScenarioContext with record Ids for assertions.
     */
    public static CompetitiveInstalledBaseScenarioContext setupCompetitiveInstalledBaseScenario() {
        CompetitiveInstalledBaseScenarioContext scenarioContext = new CompetitiveInstalledBaseScenarioContext();
        Id competitiveAssetRecordTypeId = getCompetitiveAssetRecordTypeId();

        Account grandparentA = buildCibAccount(
            CIB_GRANDPARENT_A_NAME,
            CIB_SOURCE_GRANDPARENT_A,
            null,
            null
        );
        Account parentA = buildCibAccount(CIB_PARENT_A_NAME, CIB_SOURCE_PARENT_A, null, null);
        Account parentB = buildCibAccount(CIB_PARENT_B_NAME, CIB_SOURCE_PARENT_B, null, null);
        Account idnAccount = buildCibAccount(CIB_IDN_ACCOUNT_NAME, CIB_SOURCE_IDN, 'IDN', null);
        Account gpoAccount = buildCibAccount(CIB_GPO_ACCOUNT_NAME, CIB_SOURCE_GPO, 'GPO', null);
        Account unrelatedAccount = buildCibAccount(
            CIB_UNRELATED_ACCOUNT_NAME,
            CIB_SOURCE_UNRELATED,
            null,
            null
        );

        insert new List<Account>{ grandparentA, parentA, parentB, idnAccount, gpoAccount, unrelatedAccount };

        parentA.ParentId = grandparentA.Id;
        update parentA;

        Account facilityA1 = buildCibAccount(
            CIB_FACILITY_A1_NAME,
            CIB_SOURCE_FACILITY_A1,
            null,
            CIB_FACILITY_A1_ORACLE_ID
        );
        facilityA1.ParentId = parentA.Id;

        Account facilityA2 = buildCibAccount(
            CIB_FACILITY_A2_NAME,
            CIB_SOURCE_FACILITY_A2,
            null,
            CIB_FACILITY_A2_ORACLE_ID
        );
        facilityA2.ParentId = parentA.Id;

        Account facilityB1 = buildCibAccount(
            CIB_FACILITY_B1_NAME,
            CIB_SOURCE_FACILITY_B1,
            null,
            CIB_FACILITY_B1_ORACLE_ID
        );
        facilityB1.ParentId = parentB.Id;

        Account facilityStandalone = buildCibAccount(
            CIB_FACILITY_STANDALONE_NAME,
            CIB_SOURCE_FACILITY_STANDALONE,
            null,
            CIB_FACILITY_STANDALONE_ORACLE_ID
        );

        insert new List<Account>{ facilityA1, facilityA2, facilityB1, facilityStandalone };

        insert new List<AccountAccountRelationship__c>{
            buildCibAffiliation(idnAccount.Id, parentA.Id),
            buildCibAffiliation(idnAccount.Id, parentB.Id),
            buildCibAffiliation(gpoAccount.Id, parentA.Id),
            buildCibAffiliation(gpoAccount.Id, parentB.Id)
        };

        Product2 productAlpha = buildCibProduct('CIB Product Alpha', 'CIB-PROD-ALPHA', CIB_COMPETITOR_ALPHA);
        Product2 productBeta = buildCibProduct('CIB Product Beta', 'CIB-PROD-BETA', CIB_COMPETITOR_BETA);
        insert new List<Product2>{ productAlpha, productBeta };

        insert new List<Asset>{
            buildCibCompetitiveAsset(
                'CIB Asset A1',
                facilityA1.Id,
                productAlpha.Id,
                competitiveAssetRecordTypeId,
                'CIB-SN-A1',
                1000
            ),
            buildCibCompetitiveAsset(
                'CIB Asset A2',
                facilityA2.Id,
                productBeta.Id,
                competitiveAssetRecordTypeId,
                'CIB-SN-A2',
                2000
            ),
            buildCibCompetitiveAsset(
                'CIB Asset B1',
                facilityB1.Id,
                productAlpha.Id,
                competitiveAssetRecordTypeId,
                'CIB-SN-B1',
                1500
            ),
            buildCibCompetitiveAsset(
                'CIB Asset Standalone',
                facilityStandalone.Id,
                productAlpha.Id,
                competitiveAssetRecordTypeId,
                'CIB-SN-STANDALONE',
                500
            )
        };

        scenarioContext.grandparentAId = grandparentA.Id;
        scenarioContext.parentAId = parentA.Id;
        scenarioContext.parentBId = parentB.Id;
        scenarioContext.facilityA1Id = facilityA1.Id;
        scenarioContext.facilityA2Id = facilityA2.Id;
        scenarioContext.facilityB1Id = facilityB1.Id;
        scenarioContext.facilityStandaloneId = facilityStandalone.Id;
        scenarioContext.idnAccountId = idnAccount.Id;
        scenarioContext.gpoAccountId = gpoAccount.Id;
        scenarioContext.unrelatedAccountId = unrelatedAccount.Id;

        return scenarioContext;
    }

    /**
     * @description Creates a System Administrator user with System_Administrator permission set
     *              assigned for competitive installed base tests.
     * @param firstName User first name.
     * @param lastName User last name.
     * @return Inserted sys admin user for System.runAs.
     */
    public static User insertCompetitiveInstalledBaseSysAdminTestUser(String firstName, String lastName) {
        String uniqueValue = String.valueOf(System.currentTimeMillis());
        Profile systemAdminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        User sysAdminUser = new User(
            FirstName = firstName,
            LastName = lastName,
            Alias = (firstName.left(2) + lastName.left(2)).left(8),
            Email = firstName.toLowerCase() + '.' + lastName.toLowerCase() + uniqueValue + '@example.com',
            Username = firstName.toLowerCase() + '.' + lastName.toLowerCase() + uniqueValue + '@example.com',
            CommunityNickname = firstName + lastName + uniqueValue,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = systemAdminProfile.Id,
            EmployeeNumber__c = 'EMP' + uniqueValue.right(6),
            IsActive = true
        );
        insert sysAdminUser;

        System.runAs(sysAdminUser) {
            assignSystemAdministratorPermissionSet(sysAdminUser.Id);
        }

        return sysAdminUser;
    }

    /**
     * @description Creates a Healthcare Sales user with SalesCustomerOpsSalesSupportSalesAdminPSG
     *              and supporting permission sets for competitive installed base tests.
     *              Constituent permission sets are assigned directly because PSG calculation
     *              is not always applied during unit test execution.
     * @param firstName User first name.
     * @param lastName User last name.
     * @return Inserted sales rep user for System.runAs.
     */
    public static User insertCompetitiveInstalledBaseTestUser(String firstName, String lastName) {
        User salesRepUser = buildHealthcareSalesTestUser(firstName, lastName);
        insert salesRepUser;

        assignSalesCustomerOpsPermissionSetGroup(salesRepUser.Id);
        assignPermissionSetByName(salesRepUser.Id, 'SalesCustomerOpsSalesSupportSalesAdmin');
        assignPermissionSetByName(salesRepUser.Id, 'SalesFieldRepAccountManager');

        return salesRepUser;
    }

    private static User buildHealthcareSalesTestUser(String firstName, String lastName) {
        Profile healthcareSalesProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = :UserSelector.HEALTHCARE_SALES_PROFILE_NAME
            LIMIT 1
        ];
        String uniqueValue = String.valueOf(System.currentTimeMillis());

        return new User(
            FirstName = firstName,
            LastName = lastName,
            Alias = (firstName.left(2) + lastName.left(2)).left(8),
            Email = firstName.toLowerCase() + '.' + lastName.toLowerCase() + uniqueValue + '@example.com',
            Username = firstName.toLowerCase() + '.' + lastName.toLowerCase() + uniqueValue + '@example.com',
            CommunityNickname = firstName + lastName + uniqueValue,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = healthcareSalesProfile.Id,
            EmployeeNumber__c = 'EMP' + uniqueValue.right(6),
            IsActive = true
        );
    }

    private static void assignPermissionSetByName(Id userId, String permissionSetName) {
        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :permissionSetName
            LIMIT 1
        ];

        if (permissionSets.isEmpty()) {
            return;
        }

        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetId = permissionSets[0].Id
        );
    }

    /**
     * @description Returns an Account Id from the competitive installed base scenario by SourceSystemID__c.
     * @param sourceSystemId SourceSystemID__c value.
     * @return Matching Account Id.
     */
    public static Id getCompetitiveInstalledBaseAccountIdBySourceSystemId(String sourceSystemId) {
        return [
            SELECT Id
            FROM Account
            WHERE SourceSystemID__c = :sourceSystemId
            LIMIT 1
        ]
        .Id;
    }

    private static Id getCompetitiveAssetRecordTypeId() {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Asset'
              AND DeveloperName = 'Competitive_Asset'
            LIMIT 1
        ]
        .Id;
    }

    private static Account buildCibAccount(
        String accountName,
        String sourceSystemId,
        String accountType,
        String oracleAddressId
    ) {
        Account accountRecord = new Account(Name = accountName);

        try {
            accountRecord.put('SourceSystemID__c', sourceSystemId);
        } catch (Exception e) {
            // SourceSystemID__c optional in some orgs
        }

        if (String.isNotBlank(accountType)) {
            accountRecord.Type = accountType;
        }

        if (String.isNotBlank(oracleAddressId)) {
            try {
                accountRecord.put('OracleAddressId__c', oracleAddressId);
            } catch (Exception e) {
                // OracleAddressId__c optional in some orgs
            }
        }

        return accountRecord;
    }

    private static AccountAccountRelationship__c buildCibAffiliation(Id parentAccountId, Id childAccountId) {
        return new AccountAccountRelationship__c(
            ParentAccount__c = parentAccountId,
            ChildAccount__c = childAccountId
        );
    }

    private static Product2 buildCibProduct(String productName, String productCode, String manufacturerName) {
        return new Product2(
            Name = productName,
            ProductCode = productCode,
            IsActive = true,
            Manufacturer__c = manufacturerName
        );
    }

    private static Asset buildCibCompetitiveAsset(
        String assetName,
        Id accountId,
        Id productId,
        Id recordTypeId,
        String serialNumber,
        Decimal assetValue
    ) {
        return new Asset(
            Name = assetName,
            AccountId = accountId,
            Product2Id = productId,
            SerialNumber = serialNumber,
            AssetValue__c = assetValue,
            RecordTypeId = recordTypeId,
            Status = 'Installed'
        );
    }

    public static final String LB_ACCOUNT_NAME = 'Lost Business Product Account';
    public static final String LB_ACCOUNT_SOURCE_ID = 'LB-GC3574-001';
    public static final String LB_ORIGINATING_OPPORTUNITY = 'Lost Business Originating Opportunity';
    public static final String LB_OTHER_OPPORTUNITY = 'Lost Business Other Opportunity';
    public static final String LB_LOST_OPPORTUNITY = 'Lost Business Target Opportunity';
    public static final String LB_UNPRICED_OPPORTUNITY = 'Lost Business Unpriced Opportunity';
    public static final String LB_CUSTOM_OPPORTUNITY = 'Lost Business Custom Pricebook Opportunity';
    public static final String LB_CUSTOM_PRICEBOOK = 'LB-3574 Custom Price Book';
    public static final String LB_PRODUCT_A_NAME = 'Lost Business Detergent';
    public static final String LB_PRODUCT_A_CODE = 'LB-3574-1001';
    public static final String LB_PRODUCT_B_NAME = 'Lost Business Wipe';
    public static final String LB_PRODUCT_B_CODE = 'LB-3574-1002';
    public static final String LB_PRODUCT_C_NAME = 'Lost Business Indicator';
    public static final String LB_PRODUCT_C_CODE = 'LB-3574-1003';
    public static final String LB_INACTIVE_PRODUCT_NAME = 'Lost Business Retired Kit';
    public static final String LB_INACTIVE_PRODUCT_CODE = 'LB-3574-9999';
    public static final String LB_UNPRICED_PRODUCT_NAME = 'Lost Business Unpriced Kit';
    public static final String LB_UNPRICED_PRODUCT_CODE = 'LB-NOPRICE-3574';
    public static final String LB_OPPORTUNITY_RECORD_TYPE = 'Healthcare_Sales';

    /**
     * @description
     * GC-3574 - Ids for the Lost Business product scenario created by setupLostBusinessProductScenario.
     */
    public class LostBusinessProductContext {
        public Id accountId;
        public Id contactId;
        public Id standardPricebookId;
        public Id customPricebookId;
        public Id originatingOpportunityId;
        public Id otherOpportunityId;
        public Id lostOpportunityId;
        public Id unpricedOpportunityId;
        public Id customPricebookOpportunityId;
        public Id productAId;
        public Id productBId;
        public Id productCId;
        public Id inactiveProductId;
        public Id productWithoutPriceId;
        public Id standardEntryAId;
        public Id standardEntryCId;
        public Id customEntryAId;
        public Id originatingLineAId;
        public Id originatingLineBId;
        public Id otherLineId;
        public Id customPricebookLineId;
    }

    /**
     * @description
     * GC-3574 - Creates the account, price books, products, opportunities, and originating lines
     * used by Lost Business product tests.
     *
     * @return Context with the inserted record Ids.
     * @example
     * TestDataFactory.setupLostBusinessProductScenario();
     */
    public static LostBusinessProductContext setupLostBusinessProductScenario() {
        Account testAccount = new Account(
            Name = LB_ACCOUNT_NAME,
            SourceSystemID__c = LB_ACCOUNT_SOURCE_ID
        );
        insert testAccount;

        Contact testContact = new Contact(
            LastName = 'Lost Business Contact',
            AccountId = testAccount.Id
        );
        insert testContact;

        Id standardPricebookId = Test.getStandardPricebookId();
        Pricebook2 customPricebook = new Pricebook2(Name = LB_CUSTOM_PRICEBOOK, IsActive = true);
        insert customPricebook;

        Product2 productA = new Product2(Name = LB_PRODUCT_A_NAME, ProductCode = LB_PRODUCT_A_CODE, IsActive = true);
        Product2 productB = new Product2(Name = LB_PRODUCT_B_NAME, ProductCode = LB_PRODUCT_B_CODE, IsActive = true);
        Product2 productC = new Product2(Name = LB_PRODUCT_C_NAME, ProductCode = LB_PRODUCT_C_CODE, IsActive = true);
        Product2 inactiveProduct = new Product2(
            Name = LB_INACTIVE_PRODUCT_NAME,
            ProductCode = LB_INACTIVE_PRODUCT_CODE,
            IsActive = false
        );
        Product2 productWithoutPrice = new Product2(
            Name = LB_UNPRICED_PRODUCT_NAME,
            ProductCode = LB_UNPRICED_PRODUCT_CODE,
            IsActive = true
        );
        insert new List<Product2>{ productA, productB, productC, inactiveProduct, productWithoutPrice };

        List<PricebookEntry> standardEntries = new List<PricebookEntry>{
            buildLostBusinessPricebookEntry(standardPricebookId, productA.Id, 25),
            buildLostBusinessPricebookEntry(standardPricebookId, productB.Id, 25),
            buildLostBusinessPricebookEntry(standardPricebookId, productC.Id, 25)
        };
        insert standardEntries;
        insert buildLostBusinessPricebookEntry(customPricebook.Id, productA.Id, 55);

        String consumptionFrequency = firstActiveOpportunityLinePicklistValue(
            OpportunityLineItem.ConsumptionFrequency__c
        );
        Opportunity originatingOpportunity = buildLostBusinessOpportunity(
            LB_ORIGINATING_OPPORTUNITY,
            testAccount.Id,
            testContact.Id,
            standardPricebookId
        );
        Opportunity otherOpportunity = buildLostBusinessOpportunity(
            LB_OTHER_OPPORTUNITY,
            testAccount.Id,
            testContact.Id,
            standardPricebookId
        );
        Opportunity lostOpportunity = buildLostBusinessOpportunity(
            LB_LOST_OPPORTUNITY,
            testAccount.Id,
            testContact.Id,
            standardPricebookId
        );
        Opportunity unpricedOpportunity = buildLostBusinessOpportunity(
            LB_UNPRICED_OPPORTUNITY,
            testAccount.Id,
            testContact.Id,
            null
        );
        Opportunity customOpportunity = buildLostBusinessOpportunity(
            LB_CUSTOM_OPPORTUNITY,
            testAccount.Id,
            testContact.Id,
            customPricebook.Id
        );
        insert new List<Opportunity>{
            originatingOpportunity,
            otherOpportunity,
            lostOpportunity,
            unpricedOpportunity,
            customOpportunity
        };

        Map<String, PricebookEntry> standardEntryByProductId = new Map<String, PricebookEntry>();
        for (PricebookEntry pricebookEntry : [
            SELECT Id, Product2Id, Pricebook2Id
            FROM PricebookEntry
            WHERE Product2Id IN :new Set<Id>{ productA.Id, productB.Id, productC.Id }
        ]) {
            standardEntryByProductId.put(
                String.valueOf(pricebookEntry.Pricebook2Id) + String.valueOf(pricebookEntry.Product2Id),
                pricebookEntry
            );
        }

        Id standardEntryAId = standardEntryByProductId.get(String.valueOf(standardPricebookId) + String.valueOf(productA.Id)).Id;
        Id standardEntryBId = standardEntryByProductId.get(String.valueOf(standardPricebookId) + String.valueOf(productB.Id)).Id;
        Id standardEntryCId = standardEntryByProductId.get(String.valueOf(standardPricebookId) + String.valueOf(productC.Id)).Id;
        Id customEntryAId = standardEntryByProductId.get(String.valueOf(customPricebook.Id) + String.valueOf(productA.Id)).Id;

        List<OpportunityLineItem> lineItemList = new List<OpportunityLineItem>{
            buildLostBusinessLine(originatingOpportunity.Id, standardEntryAId, 10, 40, consumptionFrequency, 'SKU-1001'),
            buildLostBusinessLine(originatingOpportunity.Id, standardEntryBId, 4, 15, consumptionFrequency, null),
            buildLostBusinessLine(otherOpportunity.Id, standardEntryCId, 1, 25, null, null),
            buildLostBusinessLine(customOpportunity.Id, customEntryAId, 2, 55, consumptionFrequency, 'SKU-CUSTOM')
        };
        insert lineItemList;

        return loadLostBusinessProductContext();
    }

    /**
     * @description
     * GC-3574 - Reloads the Lost Business product scenario. Test setup results are not kept in memory
     * between test methods, so each test loads the inserted Ids again.
     *
     * @return Context with the scenario record Ids.
     * @example
     * TestDataFactory.loadLostBusinessProductContext();
     */
    public static LostBusinessProductContext loadLostBusinessProductContext() {
        LostBusinessProductContext context = new LostBusinessProductContext();
        context.standardPricebookId = Test.getStandardPricebookId();
        context.accountId = [SELECT Id FROM Account WHERE Name = :LB_ACCOUNT_NAME LIMIT 1].Id;
        context.contactId = [SELECT Id FROM Contact WHERE AccountId = :context.accountId LIMIT 1].Id;
        context.customPricebookId = [SELECT Id FROM Pricebook2 WHERE Name = :LB_CUSTOM_PRICEBOOK LIMIT 1].Id;

        Map<String, Id> opportunityIdByName = new Map<String, Id>();
        for (Opportunity opportunityRecord : [
            SELECT Id, Name
            FROM Opportunity
            WHERE AccountId = :context.accountId
        ]) {
            opportunityIdByName.put(opportunityRecord.Name, opportunityRecord.Id);
        }

        context.originatingOpportunityId = opportunityIdByName.get(LB_ORIGINATING_OPPORTUNITY);
        context.otherOpportunityId = opportunityIdByName.get(LB_OTHER_OPPORTUNITY);
        context.lostOpportunityId = opportunityIdByName.get(LB_LOST_OPPORTUNITY);
        context.unpricedOpportunityId = opportunityIdByName.get(LB_UNPRICED_OPPORTUNITY);
        context.customPricebookOpportunityId = opportunityIdByName.get(LB_CUSTOM_OPPORTUNITY);

        Map<String, Id> productIdByCode = new Map<String, Id>();
        for (Product2 product : [
            SELECT Id, ProductCode
            FROM Product2
            WHERE ProductCode IN :lostBusinessProductCodes()
        ]) {
            productIdByCode.put(product.ProductCode, product.Id);
        }

        context.productAId = productIdByCode.get(LB_PRODUCT_A_CODE);
        context.productBId = productIdByCode.get(LB_PRODUCT_B_CODE);
        context.productCId = productIdByCode.get(LB_PRODUCT_C_CODE);
        context.inactiveProductId = productIdByCode.get(LB_INACTIVE_PRODUCT_CODE);
        context.productWithoutPriceId = productIdByCode.get(LB_UNPRICED_PRODUCT_CODE);

        for (PricebookEntry pricebookEntry : [
            SELECT Id, Product2Id, Pricebook2Id
            FROM PricebookEntry
            WHERE Product2Id IN :productIdByCode.values()
        ]) {
            if (pricebookEntry.Pricebook2Id == context.standardPricebookId && pricebookEntry.Product2Id == context.productAId) {
                context.standardEntryAId = pricebookEntry.Id;
            }
            if (pricebookEntry.Pricebook2Id == context.standardPricebookId && pricebookEntry.Product2Id == context.productCId) {
                context.standardEntryCId = pricebookEntry.Id;
            }
            if (pricebookEntry.Pricebook2Id == context.customPricebookId && pricebookEntry.Product2Id == context.productAId) {
                context.customEntryAId = pricebookEntry.Id;
            }
        }

        for (OpportunityLineItem lineItem : [
            SELECT Id, OpportunityId, PricebookEntryId
            FROM OpportunityLineItem
            WHERE Opportunity.AccountId = :context.accountId
        ]) {
            if (lineItem.OpportunityId == context.originatingOpportunityId && lineItem.PricebookEntryId == context.standardEntryAId) {
                context.originatingLineAId = lineItem.Id;
            } else if (lineItem.OpportunityId == context.originatingOpportunityId) {
                context.originatingLineBId = lineItem.Id;
            } else if (lineItem.OpportunityId == context.otherOpportunityId) {
                context.otherLineId = lineItem.Id;
            } else if (lineItem.OpportunityId == context.customPricebookOpportunityId) {
                context.customPricebookLineId = lineItem.Id;
            }
        }

        return context;
    }

    private static Set<String> lostBusinessProductCodes() {
        return new Set<String>{
            LB_PRODUCT_A_CODE,
            LB_PRODUCT_B_CODE,
            LB_PRODUCT_C_CODE,
            LB_INACTIVE_PRODUCT_CODE,
            LB_UNPRICED_PRODUCT_CODE
        };
    }

    private static Opportunity buildLostBusinessOpportunity(
        String opportunityName,
        Id accountId,
        Id contactId,
        Id pricebookId
    ) {
        return new Opportunity(
            Name = opportunityName,
            AccountId = accountId,
            RecordTypeId = Schema.SObjectType.Opportunity
                .getRecordTypeInfosByDeveloperName()
                .get(LB_OPPORTUNITY_RECORD_TYPE)
                .getRecordTypeId(),
            StageName = 'Discovery',
            ForecastConfidenceLevel__c = 'Pipeline',
            Type = 'New Business',
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = contactId,
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pricebookId
        );
    }

    private static PricebookEntry buildLostBusinessPricebookEntry(Id pricebookId, Id productId, Decimal unitPrice) {
        PricebookEntry pricebookEntry = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = productId,
            UnitPrice = unitPrice,
            IsActive = true
        );

        if (UserInfo.isMultiCurrencyOrganization()) {
            pricebookEntry.CurrencyIsoCode = UserInfo.getDefaultCurrency();
        }

        return pricebookEntry;
    }

    private static OpportunityLineItem buildLostBusinessLine(
        Id opportunityId,
        Id pricebookEntryId,
        Decimal quantity,
        Decimal unitPrice,
        String consumptionFrequency,
        String productSku
    ) {
        OpportunityLineItem lineItem = new OpportunityLineItem(
            OpportunityId = opportunityId,
            PricebookEntryId = pricebookEntryId,
            Quantity = quantity,
            UnitPrice = unitPrice
        );

        if (String.isNotBlank(consumptionFrequency)) {
            lineItem.ConsumptionFrequency__c = consumptionFrequency;
        }

        if (String.isNotBlank(productSku)) {
            lineItem.Product_Number_SKU__c = productSku;
        }

        return lineItem;
    }

    private static String firstActiveOpportunityLinePicklistValue(Schema.SObjectField picklistField) {
        for (Schema.PicklistEntry picklistEntry : picklistField.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }
}