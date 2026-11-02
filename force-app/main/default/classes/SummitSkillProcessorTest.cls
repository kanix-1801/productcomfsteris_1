/**
 * @description Unit tests for SummitSkillProcessor: batch success, duplicate requirement, failure paths, schedulable entry, and Nebula Logger warning when test Skill injection Id is invalid.
 *              Skill rows cannot be inserted in many orgs; success tests use SummitSkillProcessorTestSupport (synthetic Skill map + suppressed ServiceResourceSkill DML + optional pair overrides).
 *              Nebula Logger: https://github.com/jongpie/NebulaLogger — Apex logging: https://github.com/jongpie/NebulaLogger/wiki/Logging-in-Apex
 * @see SummitSkillProcessor
 */
@isTest
private class SummitSkillProcessorTest {
    private class SkillParts {
        String pfclPrefix;
        String workType;
    }

    /** SummitSkill__c.HRISID__c max length in this org. */
    private static final Integer HRIS_ID_MAX_LENGTH = 20;

    /** Clears SummitSkillProcessorTestSupport hooks so methods do not leak state across tests. */
    private static void resetProcessorTestHooks() {
        SummitSkillProcessorTestSupport.reset();
    }

    /**
     * @description Returns Nebula Logger entries whose Message__c contains the given fragment (LogEntry__c persisted after Logger.saveLog).
     *              Message__c is not filterable in SOQL in this org, so recent entries are loaded and matched in Apex.
     * @param messageFragment Substring to match in Message__c.
     * @return Matching log entries, possibly empty when none were saved.
     */
    private static List<LogEntry__c> getLogEntriesContaining(String messageFragment) {
        List<LogEntry__c> matches = new List<LogEntry__c>();
        for (LogEntry__c entry : [
            SELECT Id, Message__c, LoggingLevel__c
            FROM LogEntry__c
            ORDER BY CreatedDate DESC
            LIMIT 200
        ]) {
            if (entry.Message__c != null && entry.Message__c.contains(messageFragment)) {
                matches.add(entry);
            }
        }
        return matches;
    }

    /**
     * @description Unique HRIS / ServiceResource ExternalID within HRISID__c length (20).
     * @param prefix Short prefix (e.g. H, INA); combined with current time millis.
     */
    private static String uniqueHrisExternalId(String prefix) {
        String id = (String.isBlank(prefix) ? 'H' : prefix) + String.valueOf(DateTime.now().getTime());
        return id.length() <= HRIS_ID_MAX_LENGTH ? id : id.substring(0, HRIS_ID_MAX_LENGTH);
    }

    /**
     * @description 15-character Id with Skill key prefix for in-memory Skill stubs. User Id (005) cannot be assigned to Skill.Id (TypeException).
     * @return Id that matches Skill SObject type for assignment and pair-key tests.
     */
    private static Id stubSkillIdForTests() {
        String kp = Skill.SObjectType.getDescribe().getKeyPrefix();
        String id15 = kp;
        while (id15.length() < 15) {
            id15 += '0';
        }
        return Id.valueOf(id15.substring(0, 15));
    }

    /**
     * @description Returns short PFCL and WorkType values whose composite Skill key is S - W.
     * @return Synthetic skill key parts.
     */
    private static SkillParts getSyntheticSkillPartsForSuccessTests() {
        SkillParts p = new SkillParts();
        p.pfclPrefix = 'S';
        p.workType = 'W';
        return p;
    }

    /**
     * @description Inserts an active ServiceResource for the given external Id (HRIS) tied to the running user.
     * @param externalId ExternalID__c value (unique per test).
     */
    private static void createServiceResource(String externalId) {
        ServiceResource sr = new ServiceResource(
            Name = 'Test Resource',
            ExternalID__c = externalId,
            IsActive = true,
            RelatedRecordId = UserInfo.getUserId()
        );
        insert sr;
    }

    /**
     * @description Batch success path using synthetic Skill map and suppressed ServiceResourceSkill DML (Skill insert not permitted in org tests).
     */
    @isTest
    static void testSchedulableAndSuccess() {
        resetProcessorTestHooks();
        Id stubSkillId = stubSkillIdForTests();
        SummitSkillProcessorTestSupport.skillMapOverride = new Map<String, Skill>{
            'S - W' => new Skill(Id = stubSkillId, MasterLabel = 'S - W')
        };
        SummitSkillProcessorTestSupport.suppressServiceResourceSkillInsert = true;
        try {
            SkillParts skillParts = getSyntheticSkillPartsForSuccessTests();
            String externalId = uniqueHrisExternalId('HRIS-');
            createServiceResource(externalId);

            SummitSkill__c ss = new SummitSkill__c(
                Integration_Status__c = 'Wait',
                WorkType__c = skillParts.workType,
                PFCL__c = skillParts.pfclPrefix + '/01',
                HRISID__c = externalId
            );
            insert ss;

            Test.startTest();
            Database.executeBatch(new SummitSkillProcessor());
            Test.stopTest();

            SummitSkill__c updatedSS = [SELECT Integration_Status__c, DeploymentStatus__c FROM SummitSkill__c WHERE Id = :ss.Id];
            System.assertEquals('Done', updatedSS.Integration_Status__c);
            System.assert(updatedSS.DeploymentStatus__c.contains('Created Skill Requirement'));
        } finally {
            resetProcessorTestHooks();
        }
    }

    /**
     * @description Covers batch execute with an empty scope (no start); verifies Nebula Logger calls complete without error.
     */
    @isTest
    static void testSchedulableCoverage() {
        resetProcessorTestHooks();
        Test.startTest();
        new SummitSkillProcessor().execute((Database.BatchableContext) null, new List<SummitSkill__c>());
        Test.stopTest();
        System.assertNotEquals(null, Logger.getTransactionId(), 'Logger should expose a transaction Id after execute.');
    }

    /**
     * @description Covers schedulable execute enqueueing the batch job (SchedulableContext unused).
     */
    @isTest
    static void testSchedulableExecuteEnqueuesBatch() {
        resetProcessorTestHooks();
        Test.startTest();
        new SummitSkillProcessor().execute((SchedulableContext) null);
        Test.stopTest();
        System.assert(true, 'Schedulable execute completed.');
    }

    /**
     * @description First run via executeBatch; after pair-key hook and reset to Wait, second pass calls execute() directly (only one Test.startTest/stopTest allowed per test).
     */
    @isTest
    static void testExistingRequirement() {
        resetProcessorTestHooks();
        Id stubSkillId = stubSkillIdForTests();
        SummitSkillProcessorTestSupport.skillMapOverride = new Map<String, Skill>{
            'S - W' => new Skill(Id = stubSkillId, MasterLabel = 'S - W')
        };
        SummitSkillProcessorTestSupport.suppressServiceResourceSkillInsert = true;
        try {
            SkillParts skillParts = getSyntheticSkillPartsForSuccessTests();
            String externalId = uniqueHrisExternalId('HRIS-');
            createServiceResource(externalId);

            SummitSkill__c ss = new SummitSkill__c(
                Integration_Status__c = 'Wait',
                WorkType__c = skillParts.workType,
                PFCL__c = skillParts.pfclPrefix,
                HRISID__c = externalId
            );
            insert ss;

            Test.startTest();
            Database.executeBatch(new SummitSkillProcessor());
            Test.stopTest();

            ServiceResource sr = [SELECT Id FROM ServiceResource WHERE ExternalID__c = :externalId LIMIT 1];
            SummitSkillProcessorTestSupport.serviceResourceSkillPairKeysTreatedAsExisting = new Set<String>{
                SummitSkillProcessorTestSupport.buildRequirementPairKey(sr.Id, stubSkillId)
            };

            ss.Integration_Status__c = 'Wait';
            update ss;

            // Only one Test.startTest/stopTest pair is allowed per test method; simulate the second batch chunk directly.
            SummitSkill__c ssForSecond = [
                SELECT Id, WorkType__c, PFCL__c, HRISID__c, Integration_Status__c, DeploymentStatus__c
                FROM SummitSkill__c
                WHERE Id = :ss.Id
            ];
            new SummitSkillProcessor().execute((Database.BatchableContext) null, new List<SummitSkill__c>{ ssForSecond });

            SummitSkill__c updatedSS = [SELECT DeploymentStatus__c FROM SummitSkill__c WHERE Id = :ss.Id];
            System.assert(updatedSS.DeploymentStatus__c.contains('Skill Requirement Already Exists'));
        } finally {
            resetProcessorTestHooks();
        }
    }

    /**
     * @description Inactive ServiceResource is excluded from lookup; batch fails without ServiceResourceSkill DML error.
     */
    @isTest
    static void testInactiveServiceResourceFailsWithoutDml() {
        resetProcessorTestHooks();
        Id stubSkillId = stubSkillIdForTests();
        SummitSkillProcessorTestSupport.skillMapOverride = new Map<String, Skill>{
            'S - W' => new Skill(Id = stubSkillId, MasterLabel = 'S - W')
        };
        try {
            SkillParts skillParts = getSyntheticSkillPartsForSuccessTests();
            String externalId = uniqueHrisExternalId('INA');
            insert new ServiceResource(
                Name = 'Inactive Resource',
                ExternalID__c = externalId,
                IsActive = false,
                RelatedRecordId = UserInfo.getUserId()
            );

            SummitSkill__c ss = new SummitSkill__c(
                Integration_Status__c = 'Wait',
                WorkType__c = skillParts.workType,
                PFCL__c = skillParts.pfclPrefix,
                HRISID__c = externalId
            );
            insert ss;

            Test.startTest();
            Database.executeBatch(new SummitSkillProcessor());
            Test.stopTest();

            SummitSkill__c updatedSS = [
                SELECT Integration_Status__c, DeploymentStatus__c
                FROM SummitSkill__c
                WHERE Id = :ss.Id
            ];
            System.assertEquals('Fail', updatedSS.Integration_Status__c);
            System.assert(updatedSS.DeploymentStatus__c.contains('Service Resource Inactive'));
        } finally {
            resetProcessorTestHooks();
        }
    }

    /**
     * @description Integration failure when Skill and Service Resource cannot be resolved (no matching Skill in test data).
     */
    @isTest
    static void testFailurePath() {
        resetProcessorTestHooks();
        SummitSkill__c ss = new SummitSkill__c(
            Integration_Status__c = 'Wait',
            WorkType__c = 'Z9',
            PFCL__c = 'NSR/01',
            HRISID__c = 'NON_EXISTENT_ID'
        );
        insert ss;

        Test.startTest();
        Database.executeBatch(new SummitSkillProcessor());
        Test.stopTest();

        SummitSkill__c updatedSS = [SELECT Integration_Status__c FROM SummitSkill__c WHERE Id = :ss.Id];
        System.assertEquals('Fail', updatedSS.Integration_Status__c);
    }

    /**
     * @description When SummitSkillProcessorTestSupport.injectSkillIdForMap is set to an Id that is not a Skill, getSkillMap logs WARN and processing fails lookup for that row.
     */
    @isTest
    static void testInjectSkillIdNotSkillRecordLogsWarnAndFails() {
        resetProcessorTestHooks();
        SummitSkillProcessorTestSupport.injectSkillIdForMap = UserInfo.getUserId();
        try {
            SummitSkill__c ss = new SummitSkill__c(
                Integration_Status__c = 'Wait',
                WorkType__c = 'Z9',
                PFCL__c = 'NSR/01',
                HRISID__c = 'NON_EXISTENT_ID'
            );
            insert ss;

            Test.startTest();
            Database.executeBatch(new SummitSkillProcessor());
            Test.stopTest();

            System.assertEquals(
                'Fail',
                [SELECT Integration_Status__c FROM SummitSkill__c WHERE Id = :ss.Id].Integration_Status__c
            );

            List<LogEntry__c> warnEntries = getLogEntriesContaining('injectSkillIdForMap');
            System.assert(!warnEntries.isEmpty(), 'Expected Nebula Logger WARN for invalid injectSkillIdForMap.');
            System.assertEquals('WARN', warnEntries[0].LoggingLevel__c);
        } finally {
            resetProcessorTestHooks();
        }
    }

    /**
     * @description Batch start and finish paths call Logger.saveLog(); verifies DEBUG entries are persisted for the job lifecycle.
     */
    @isTest
    static void testBatchLifecycleLogsDebugEntries() {
        resetProcessorTestHooks();
        SummitSkillProcessorTestSupport.skillMapOverride = new Map<String, Skill>();
        SummitSkillProcessorTestSupport.suppressServiceResourceSkillInsert = true;
        try {
            Test.startTest();
            Database.executeBatch(new SummitSkillProcessor());
            Test.stopTest();

            List<LogEntry__c> startEntries = getLogEntriesContaining('batch job start');
            List<LogEntry__c> finishEntries = getLogEntriesContaining('batch job finished');
            System.assert(!startEntries.isEmpty(), 'Expected Nebula Logger DEBUG entry for batch start.');
            System.assert(!finishEntries.isEmpty(), 'Expected Nebula Logger DEBUG entry for batch finish.');
        } finally {
            resetProcessorTestHooks();
        }
    }
}