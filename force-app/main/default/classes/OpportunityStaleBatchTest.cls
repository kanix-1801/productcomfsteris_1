/**
 * @author Chandini Singarapu
 * @date 2026/06/09
 *
 * @group Opportunity Stale Management
 *
 * @description
 * Tests for Opportunity stale evaluation batch and schedulable processing.
 * Covers stale determination based on activity history, stage movement,
 * latest Task/Event activity dates, stale threshold configuration,
 * stale reason assignment, field updates, batch execution, and schedulable execution.
 */
@IsTest(SeeAllData=false)
private class OpportunityStaleBatchTest {

    private static final String TARGET_STAGE_PROPOSAL = 'Proposal';
    private static final String TARGET_STAGE_COMMIT = 'Commit';

    /**
     * @description
     * Creates baseline Account test data used by all Opportunity stale evaluation tests.
     * Populates required customer validation fields including SourceSystemID__c
     * and Oracle Customer ID fields when available.
     *
     * @return void
     * @example
     * Shared @TestSetup data for all test methods in this class.
     */
    @TestSetup
    static void setupData() {
        String uniqueId = String.valueOf(Math.abs(Crypto.getRandomInteger()));

            Account acc = new Account(
                Name = 'Opportunity Stale Test Account'
            );
        
            // Required by Customer Account validation rules
            try {
                acc.put('SourceSystemID__c', uniqueId + 'Oracle');
            } catch (Exception e) {
                // Field may not exist in some environments
            }
        
            // Oracle Customer ID requirement used in many Customer account validations
            try {
                acc.put('SystemID__c', uniqueId.left(15));
            } catch (Exception e) {
                // Field may not exist in some environments
            }

    	insert acc;
    }

    /**
     * @description
     * Returns the shared test Account created during @TestSetup.
     *
     * @return Account used for Opportunity test records
     */
    private static Account getTestAccount() {
        return [
            SELECT Id
            FROM Account
            WHERE Name = 'Opportunity Stale Test Account'
            LIMIT 1
        ];
    }

    /**
     * @description
     * Returns an Opportunity stale configuration record for a supported
     * target stage (Proposal or Commit).
     *
     * @return OpportunityStaleConfigSettings__mdt configuration record
     */
    private static OpportunityStaleConfigSettings__mdt getAnyTargetConfig() {
        List<OpportunityStaleConfigSettings__mdt> configs = [
            SELECT BusinessType__c,
                   Stage__c,
                   StaleDaysThreshold__c
            FROM OpportunityStaleConfigSettings__mdt
            WHERE Stage__c IN (:TARGET_STAGE_PROPOSAL, :TARGET_STAGE_COMMIT)
            LIMIT 1
        ];

        System.assert(
            !configs.isEmpty(),
            'Test requires OpportunityStaleConfigSettings__mdt for Proposal or Commit stage.'
        );

        return configs[0];
    }

    /**
     * @description
     * Returns the Opportunity Record Type Id matching the supplied
     * developer name from stale configuration metadata.
     *
     * @param developerName Opportunity Record Type Developer Name
     * @return Record Type Id
     */
    private static Id getOpportunityRecordTypeId(String developerName) {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Opportunity'
              AND DeveloperName = :developerName
            LIMIT 1
        ];

        System.assert(
            !recordTypes.isEmpty(),
            'No Opportunity RecordType found for DeveloperName: ' + developerName
        );

        return recordTypes[0].Id;
    }

    /**
     * @description
     * Creates an Opportunity test record configured for stale evaluation scenarios.
     *
     * @param name Opportunity name
     * @param stageName Opportunity stage
     * @param recordTypeId Opportunity record type Id
     * @param closeDate Opportunity close date
     * @param lastStageChangeDate Last stage movement date
     * @return Opportunity instance ready for insert
     */
    private static Opportunity buildOpportunity(
        String name,
        String stageName,
        Id recordTypeId,
        Date closeDate,
        Date lastStageChangeDate
    ) {
        Opportunity opp = new Opportunity(
            Name = name,
            AccountId = getTestAccount().Id,
            StageName = stageName,
            CloseDate = closeDate,
            RecordTypeId = recordTypeId,
            Proposal_Quote_Sent_Date__c = closeDate,
            NextStep = 'Test',
            ForecastCategoryName = 'Commit'
        );

        opp.LastStageChangeDate__c = lastStageChangeDate;
        return opp;
    }

    /**
     * @description
     * Executes the Opportunity stale batch using a scope size large enough
     * to process all open Opportunities within a single test execution.
     *
     * @return AsyncApexJob Id for the batch run
     */
    private static Id runBatch() {
        Integer scopeSize = Math.max(1, [
            SELECT COUNT()
            FROM Opportunity
            WHERE IsClosed = false
        ]);

        return Database.executeBatch(new OpportunityStaleBatch(), scopeSize);
    }

    /**
     * @description
     * Verifies Opportunities are marked stale when no qualifying activity exists
     * and stage movement exceeds the configured stale threshold.
     *
     * @return void
     */
    @IsTest
    static void testMarksStaleWhenNoActivityAndNoStageMovement() {
        
        OpportunityStaleConfigSettings__mdt config = getAnyTargetConfig();
        Integer thresholdDays = Integer.valueOf(config.StaleDaysThreshold__c);
        Id oppRecordTypeId = getOpportunityRecordTypeId(config.BusinessType__c);

        Opportunity opp = buildOpportunity(
            'Stale - No Activity And No Stage Movement',
            config.Stage__c,
            oppRecordTypeId,
            Date.today().addDays(30),
            Date.today().addDays(-thresholdDays)
        );
        insert opp;

        Test.startTest();
        Id jobId = runBatch();
        Test.stopTest();

        System.assertNotEquals(null, jobId);

        Opportunity result = [
            SELECT isStaleOpportunity__c,
                   StaleReason__c,
                   LastQualifyingActivityDate__c,
                   DaysSinceLastActivity__c,
                   DaysSinceLastStageChange__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals(true, result.isStaleOpportunity__c);
        System.assertEquals(
            'No Recent Activity and No Stage Movement',
            result.StaleReason__c
        );
        System.assertEquals(null, result.LastQualifyingActivityDate__c);
        System.assertEquals(null, result.DaysSinceLastActivity__c);
        System.assertEquals(thresholdDays, result.DaysSinceLastStageChange__c);
    }

    /**
     * @description
     * Verifies Opportunities are marked stale for inactivity when the latest
     * qualifying activity exceeds the configured threshold while stage movement
     * remains within threshold limits.
     *
     * @return void
     */
    @IsTest
    static void testMarksStaleByActivityOnly() {

        OpportunityStaleConfigSettings__mdt config = getAnyTargetConfig();
        Integer thresholdDays = Integer.valueOf(config.StaleDaysThreshold__c);
        Id oppRecordTypeId = getOpportunityRecordTypeId(config.BusinessType__c);

        Opportunity opp = buildOpportunity(
            'Stale - Activity Only',
            config.Stage__c,
            oppRecordTypeId,
            Date.today().addDays(30),
            Date.today()
        );
        insert opp;

        insert new Task(
            WhatId = opp.Id,
            Subject = 'Old qualifying task',
            Status = 'Completed',
            Priority = 'Normal',
            ActivityDate = Date.today().addDays(-thresholdDays)
        );

        Test.startTest();
        runBatch();
        Test.stopTest();

        Opportunity result = [
            SELECT isStaleOpportunity__c,
                   StaleReason__c,
                   LastQualifyingActivityDate__c,
                   DaysSinceLastActivity__c,
                   DaysSinceLastStageChange__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals(true, result.isStaleOpportunity__c);
        System.assertEquals('No Recent Activity', result.StaleReason__c);
        System.assertEquals(Date.today().addDays(-thresholdDays), result.LastQualifyingActivityDate__c);
        System.assertEquals(thresholdDays, result.DaysSinceLastActivity__c);
        System.assertEquals(0, result.DaysSinceLastStageChange__c);
    }
    
    /**
     * @description
     * Verifies Opportunities are marked stale for lack of stage movement when
     * stage aging exceeds the configured threshold while recent activity exists.
     *
     * @return void
     */
    @IsTest
    static void testMarksStaleByStageOnly() {

        OpportunityStaleConfigSettings__mdt config = getAnyTargetConfig();
        Integer thresholdDays = Integer.valueOf(config.StaleDaysThreshold__c);
        Id oppRecordTypeId = getOpportunityRecordTypeId(config.BusinessType__c);

        Opportunity opp = buildOpportunity(
            'Stale - Stage Only',
            config.Stage__c,
            oppRecordTypeId,
            Date.today().addDays(30),
            Date.today().addDays(-thresholdDays)
        );
        insert opp;

        insert new Event(
            WhatId = opp.Id,
            Subject = 'Recent qualifying event',
            ActivityDate = Date.today(),
            StartDateTime = DateTime.now(),
            EndDateTime = DateTime.now().addHours(1)
        );

        Test.startTest();
        runBatch();
        Test.stopTest();

        Opportunity result = [
            SELECT isStaleOpportunity__c,
                   StaleReason__c,
                   LastQualifyingActivityDate__c,
                   DaysSinceLastActivity__c,
                   DaysSinceLastStageChange__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals(true, result.isStaleOpportunity__c);
        System.assertEquals('No Stage Movement', result.StaleReason__c);
        System.assertEquals(Date.today(), result.LastQualifyingActivityDate__c);
        System.assertEquals(0, result.DaysSinceLastActivity__c);
        System.assertEquals(thresholdDays, result.DaysSinceLastStageChange__c);
    }

    /**
     * @description
     * Verifies Opportunities remain active when both qualifying activity
     * and stage movement occur within configured threshold limits.
     *
     * @return void
     */
    @IsTest
    static void testDoesNotMarkStaleWhenActivityAndStageAreRecent() {

        OpportunityStaleConfigSettings__mdt config = getAnyTargetConfig();
        Id oppRecordTypeId = getOpportunityRecordTypeId(config.BusinessType__c);

        Opportunity opp = buildOpportunity(
            'Not Stale - Recent Activity And Stage',
            config.Stage__c,
            oppRecordTypeId,
            Date.today().addDays(30),
            Date.today()
        );
        insert opp;

        insert new Task(
            WhatId = opp.Id,
            Subject = 'Recent qualifying task',
            Status = 'Completed',
            Priority = 'Normal',
            ActivityDate = Date.today()
        );

        Test.startTest();
        runBatch();
        Test.stopTest();

        Opportunity result = [
            SELECT isStaleOpportunity__c,
                   StaleReason__c,
                   LastQualifyingActivityDate__c,
                   DaysSinceLastActivity__c,
                   DaysSinceLastStageChange__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals(false, result.isStaleOpportunity__c);
        System.assertEquals(null, result.StaleReason__c);
        System.assertEquals(Date.today(), result.LastQualifyingActivityDate__c);
        System.assertEquals(0, result.DaysSinceLastActivity__c);
        System.assertEquals(0, result.DaysSinceLastStageChange__c);
    }

    /**
     * @description
     * Verifies the latest qualifying activity date is derived from the most
     * recent Task or Event related to the Opportunity.
     *
     * @return void
     */
    @IsTest
    static void testLatestActivityDateUsesMostRecentTaskOrEvent() {

        OpportunityStaleConfigSettings__mdt config = getAnyTargetConfig();
        Id oppRecordTypeId = getOpportunityRecordTypeId(config.BusinessType__c);

        Opportunity opp = buildOpportunity(
            'Latest Activity Date Test',
            config.Stage__c,
            oppRecordTypeId,
            Date.today().addDays(30),
            Date.today()
        );
        insert opp;

        insert new Task(
            WhatId = opp.Id,
            Subject = 'Older task',
            Status = 'Completed',
            Priority = 'Normal',
            ActivityDate = Date.today().addDays(-5)
        );

        insert new Event(
            WhatId = opp.Id,
            Subject = 'Newer event',
            ActivityDate = Date.today().addDays(-1),
            StartDateTime = DateTime.now().addDays(-1),
            EndDateTime = DateTime.now().addDays(-1).addHours(1)
        );

        Test.startTest();
        runBatch();
        Test.stopTest();

        Opportunity result = [
            SELECT LastQualifyingActivityDate__c,
                   DaysSinceLastActivity__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals(Date.today().addDays(-1), result.LastQualifyingActivityDate__c);
        System.assertEquals(1, result.DaysSinceLastActivity__c);
    }

    /**
     * @description
     * Verifies schedulable execution submits the Opportunity stale batch
     * and processes Opportunity records successfully.
     *
     * @return void
	 */
    @IsTest
    static void testSchedulableExecuteQueuesBatch() {
        /********************************************
        * SETUP
        ********************************************/
        OpportunityStaleConfigSettings__mdt config = getAnyTargetConfig();
        Id oppRecordTypeId = getOpportunityRecordTypeId(config.BusinessType__c);

        Opportunity opp = buildOpportunity(
            'Schedulable Batch Test',
            config.Stage__c,
            oppRecordTypeId,
            Date.today().addDays(30),
            Date.today()
        );
        insert opp;

        insert new Task(
            WhatId = opp.Id,
            Subject = 'Recent task',
            Status = 'Completed',
            Priority = 'Normal',
            ActivityDate = Date.today()
        );
        
        Test.startTest();
        new OpportunityStaleBatch().execute(null);
        Test.stopTest();

        Opportunity result = [
            SELECT isStaleOpportunity__c,
                   StaleReason__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals(false, result.isStaleOpportunity__c);
        System.assertEquals(null, result.StaleReason__c);
    }
}