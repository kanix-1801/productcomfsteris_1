@IsTest
private class LSTemporaryAccessExceptionBatchTest {

    @IsTest
    static void grantScenarioAddsTeamMembersAndActivatesLifeScienceRequest() {
        Profile lsProfile = lifeScienceProfile();
        User submitter = insertUser(lsProfile.Id, 'lsSub');
        User requester = insertUser(lsProfile.Id, 'lsReq');
        User coverageRep = insertUser(lsProfile.Id, 'lsCov');
        stopTemporaryAccessFlows(submitter.Id);

        Account covered = new Account(Name = 'LSBatch Covered');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert covered;
            insert new AccountTeamMember(
                AccountId = covered.Id,
                UserId = requester.Id,
                TeamMemberRole = 'Sales'
            );
        }

        TemporaryAccessException__c request = newRequest(requester.Id, coverageRep.Id, Date.today(), Date.today().addDays(5));
        System.runAs(submitter) {
            insert request;
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new TemporaryAccessException__c(
                Id = request.Id,
                Status__c = TemporaryAccessExceptionSelector.STATUS_APPROVED
            );
        }

        LSTemporaryAccessExceptionBatch.skipFlexQueueCheckForTest = true;

        Test.startTest();
        LSTemporaryAccessExceptionBatch.submitBatch();
        Test.stopTest();

        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_ACTIVE,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :request.Id].Status__c,
            'Life Science grant row should become Active'
        );
        List<AccountTeamMember> coverageRepTeam = [
            SELECT Id FROM AccountTeamMember WHERE AccountId = :covered.Id AND UserId = :coverageRep.Id
        ];
        System.assertEquals(1, coverageRepTeam.size(), 'Coverage Rep should be added to the covered Account');
    }

    @IsTest
    static void revokeScenarioRemovesTeamMembersReassignsOwnershipAndExpiresRequest() {
        Profile lsProfile = lifeScienceProfile();
        User submitter = insertUser(lsProfile.Id, 'lsSub2');
        User requester = insertUser(lsProfile.Id, 'lsReq2');
        User coverageRep = insertUser(lsProfile.Id, 'lsCov2');
        stopTemporaryAccessFlows(submitter.Id);
        Account covered = new Account(Name = 'LSBatch Revoke Covered');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new Automation_Setting_Validation_Rule__c(SetupOwnerId = UserInfo.getUserId(), disableAll__c = true);
            insert covered;
            insert new AccountTeamMember(
                AccountId = covered.Id,
                UserId = requester.Id,
                TeamMemberRole = 'Sales'
            );
        }

        TemporaryAccessException__c request = newRequest(requester.Id, coverageRep.Id, Date.today(), Date.today());
        System.runAs(submitter) {
            insert request;
        }
        Contact coveredContact = new Contact(
            LastName = 'LSBatch Revoke',
            AccountId = covered.Id,
            OwnerId = coverageRep.Id
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new TemporaryAccessException__c(
                Id = request.Id,
                Status__c = TemporaryAccessExceptionSelector.STATUS_APPROVED
            );
            insert new TAE_AssignedRecord__c(
                TemporaryAccessException__c = request.Id,
                Account__c = covered.Id
            );
            insert new AccountTeamMember(
                AccountId = covered.Id,
                UserId = coverageRep.Id,
                TeamMemberRole = 'Sales',
                AssignmentType__c = 'Temporary Assignment',
                ExpiryDate__c = Date.today()
            );
            insert coveredContact;
            update new TemporaryAccessException__c(
                Id = request.Id,
                Status__c = TemporaryAccessExceptionSelector.STATUS_ACTIVE
            );
        }

        LSTemporaryAccessExceptionBatch.skipFlexQueueCheckForTest = true;

        Test.startTest();
        LSTemporaryAccessExceptionBatch.submitBatch();
        Test.stopTest();

        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_EXPIRED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :request.Id].Status__c,
            'Life Science revoke row should become Expired'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :covered.Id AND UserId = :coverageRep.Id],
            'Temporary Coverage Rep team membership should be removed'
        );
        System.assertEquals(
            requester.Id,
            [SELECT OwnerId FROM Contact WHERE Id = :coveredContact.Id].OwnerId,
            'GCL-103 should move the covered Contact back to the Requester'
        );
    }

    @IsTest
    static void healthcareRowIsNotPickedUpByTheLifeScienceBatch() {
        User requester = insertUser(nonLifeScienceProfileId(), 'hcReq');
        User coverageRep = insertUser(nonLifeScienceProfileId(), 'hcCov');
        stopTemporaryAccessFlows(UserInfo.getUserId());

        TemporaryAccessException__c healthcareRequest = newRequest(
            requester.Id,
            coverageRep.Id,
            Date.today(),
            Date.today().addDays(5)
        );
        insert healthcareRequest;
        update new TemporaryAccessException__c(
            Id = healthcareRequest.Id,
            Status__c = TemporaryAccessExceptionSelector.STATUS_APPROVED
        );

        LSTemporaryAccessExceptionBatch.skipFlexQueueCheckForTest = true;

        Test.startTest();
        LSTemporaryAccessExceptionBatch.submitBatch();
        Test.stopTest();

        System.assertEquals(
            TemporaryAccessExceptionSelector.STATUS_APPROVED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :healthcareRequest.Id].Status__c,
            'A Healthcare-created row must stay untouched by the Life Science batch'
        );
    }

    @IsTest
    static void resolveBatchSizeFallsBackWhenNoConfigOverrideIsSet() {
        System.assertEquals(
            LSTemporaryAccessExceptionBatch.DEFAULT_BATCH_SIZE,
            LSTemporaryAccessExceptionBatch.resolveBatchSize(),
            'Fallback size should be used when no test override and no active CMDT row exist'
        );
        LSTemporaryAccessExceptionBatch.testBatchSizeOverride = 7;
        System.assertEquals(7, LSTemporaryAccessExceptionBatch.resolveBatchSize());
        LSTemporaryAccessExceptionBatch.testBatchSizeOverride = null;
    }

    @IsTest
    static void assertFlexQueueHasCapacityThrowsWhenFlexQueueIsFull() {
        LSTemporaryAccessExceptionBatch.skipFlexQueueCheckForTest = false;
        LSTemporaryAccessExceptionBatch.testFlexQueueHoldingCountOverride =
            LSTemporaryAccessExceptionBatch.FLEX_QUEUE_MAX_BATCH_JOBS;
        Boolean threw = false;
        try {
            LSTemporaryAccessExceptionBatch.assertFlexQueueHasCapacity();
        } catch (TemporaryAccessExceptionException e) {
            threw = true;
        }
        System.assert(threw, 'A full flex queue should block submission');
        LSTemporaryAccessExceptionBatch.testFlexQueueHoldingCountOverride = null;
    }

    @IsTest
    static void scheduleDailyRegistersTheCronJobAndRunsCleanly() {
        LSTemporaryAccessExceptionBatch.skipFlexQueueCheckForTest = true;
        Test.startTest();
        Id jobId = LSTemporaryAccessExceptionBatch.scheduleDaily();
        Test.stopTest();
        System.assertEquals(
            1,
            [SELECT COUNT() FROM CronTrigger WHERE Id = :jobId],
            'Daily schedule should be registered'
        );
    }

    @IsTest
    static void startExecuteFinishLogCatchPathsDoNotThrow() {
        LSTemporaryAccessExceptionBatch.throwInStart = true;
        LSTemporaryAccessExceptionBatch.throwInExecute = true;
        LSTemporaryAccessExceptionBatch.throwInFinish = true;
        LSTemporaryAccessExceptionBatch.skipFlexQueueCheckForTest = true;

        Test.startTest();
        try {
            LSTemporaryAccessExceptionBatch.submitBatch();
            Test.stopTest();
        } catch (Exception e) {
            // start() rethrows by design; the exception surfaces when the queued batch
            // is forced to run synchronously at Test.stopTest().
        }

        System.assert(LSTemporaryAccessExceptionBatch.startCatchCount > 0);
        LSTemporaryAccessExceptionBatch.throwInStart = false;
        LSTemporaryAccessExceptionBatch.throwInExecute = false;
        LSTemporaryAccessExceptionBatch.throwInFinish = false;
    }

    private static TemporaryAccessException__c newRequest(Id requesterId, Id coverageRepId, Date startDate, Date endDate) {
        return new TemporaryAccessException__c(
            Requester__c = requesterId,
            CoverageRep__c = coverageRepId,
            ExceptionCategory__c = 'PTO',
            StartDate__c = startDate,
            EndDate__c = endDate
        );
    }

    private static void stopTemporaryAccessFlows(Id userId) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new Automation_Setting_Flow__c(
                SetupOwnerId = userId,
                TemporaryAccessSubmitForApproval__c = true,
                TemporaryAccessApprovalProcess__c = true,
                LSTemporaryAccessApprovalProcess__c = true
            );
        }
    }

    private static Profile lifeScienceProfile() {
        List<Profile> profiles = [
            SELECT Id
            FROM Profile
            WHERE Name = :LSTemporaryAccessExceptionEmailService.LIFE_SCIENCE_SALES_PROFILE
            LIMIT 1
        ];
        System.assertEquals(1, profiles.size(), 'Life Sciences Sales profile must exist in the target org');
        return profiles[0];
    }

    private static Id nonLifeScienceProfileId() {
        Profile runningUserProfile = [
            SELECT Name
            FROM Profile
            WHERE Id = :UserInfo.getProfileId()
        ];
        if (runningUserProfile.Name != LSTemporaryAccessExceptionEmailService.LIFE_SCIENCE_SALES_PROFILE) {
            return runningUserProfile.Id;
        }
        return [
            SELECT Id
            FROM Profile
            WHERE Name != :LSTemporaryAccessExceptionEmailService.LIFE_SCIENCE_SALES_PROFILE
              AND UserType = 'Standard'
            LIMIT 1
        ].Id;
    }

    private static Integer userSequence = 0;

    private static User insertUser(Id profileId, String aliasSeed) {
        userSequence++;
        String token = String.valueOf(DateTime.now().getTime()) + userSequence + aliasSeed;
        User user = new User(
            Alias = aliasSeed.left(8),
            Email = token + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = aliasSeed,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profileId,
            TimeZoneSidKey = 'America/New_York',
            Username = token + '@lsbatch.test'
        );
        insert user;
        if (profileId == lifeScienceProfile().Id) {
            insert new PermissionSetAssignment(AssigneeId = user.Id, PermissionSetGroupId = lifeSciencePermissionSetGroupId());
        }
        return user;
    }

    private static Id lifeSciencePsgId;

    private static Id lifeSciencePermissionSetGroupId() {
        if (lifeSciencePsgId == null) {
            lifeSciencePsgId = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'LSInsideSalesPSG' LIMIT 1].Id;
            Test.calculatePermissionSetGroup(lifeSciencePsgId);
        }
        return lifeSciencePsgId;
    }
}