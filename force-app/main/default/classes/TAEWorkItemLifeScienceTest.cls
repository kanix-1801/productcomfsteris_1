@IsTest
private class TAEWorkItemLifeScienceTest {

    @IsTest
    static void lifeScienceRevokeHandsOwnershipBackAndExpires() {
        Profile lsProfile = lifeScienceProfile();
        User submitter = insertUser(lsProfile.Id, 'lsFin');
        User requester = insertUser(lsProfile.Id, 'lsOwn');
        stopTemporaryAccessFlows(submitter.Id);
        Id coverageId = UserInfo.getUserId();
        giveManager(coverageId, insertUser(lsProfile.Id, 'lsMgr').Id);

        Account covered = new Account(Name = 'TAE LS Covered');
        Contact coveredContact = new Contact(LastName = 'TAE LS', OwnerId = coverageId);
        Task completedTask = new Task(
            Subject = 'TAE LS Done',
            OwnerId = coverageId,
            Status = 'Completed',
            ActivityDate = Date.today()
        );
        System.runAs(new User(Id = coverageId)) {
            insert new Automation_Setting_Validation_Rule__c(
                SetupOwnerId = coverageId,
                disableAll__c = true
            );
            insert covered;
            coveredContact.AccountId = covered.Id;
            insert coveredContact;
            completedTask.WhatId = covered.Id;
            insert completedTask;
        }

        TemporaryAccessException__c request = newRequest(requester.Id, coverageId);
        System.runAs(submitter) {
            insert request;
        }
        System.runAs(new User(Id = coverageId)) {
            insert new TAE_AssignedRecord__c(
                TemporaryAccessException__c = request.Id,
                Account__c = covered.Id
            );
        }

        Integer expiredEmailsSent;
        Test.startTest();
        System.runAs(new User(Id = coverageId)) {
            TAEWorkItemService.finalizeTae(request.Id, TAEWorkItemService.OP_REVOKE);
            expiredEmailsSent = Limits.getEmailInvocations();
        }
        Test.stopTest();

        System.assertEquals(
            TAEWorkItemService.HEADER_EXPIRED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :request.Id].Status__c,
            'Life Science revoke should expire the request'
        );
        System.assertEquals(requester.Id, [SELECT OwnerId FROM Contact WHERE Id = :coveredContact.Id].OwnerId);
        System.assertEquals(requester.Id, [SELECT OwnerId FROM Task WHERE Id = :completedTask.Id].OwnerId);
        System.assertEquals(coverageId, [SELECT CreatedById FROM Task WHERE Id = :completedTask.Id].CreatedById);
        System.assert(expiredEmailsSent > 0, 'Life Science expired email should be sent');
    }

    @IsTest
    static void lifeScienceGrantBecomesActiveWithoutHealthcareEmail() {
        Profile lsProfile = lifeScienceProfile();
        User submitter = insertUser(lsProfile.Id, 'lsGrn');
        User requester = insertUser(lsProfile.Id, 'lsReq');
        stopTemporaryAccessFlows(submitter.Id);
        stopTemporaryAccessFlows(UserInfo.getUserId());
        giveManager(UserInfo.getUserId(), insertUser(lifeScienceProfile().Id, 'lsMgr').Id);

        TemporaryAccessException__c request = newRequest(requester.Id, UserInfo.getUserId());
        System.runAs(submitter) {
            insert request;
        }

        Integer emailsSent;
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TAEWorkItemService.finalizeTae(request.Id, TAEWorkItemService.OP_GRANT);
            emailsSent = Limits.getEmailInvocations();
        }
        Test.stopTest();

        System.assertEquals(
            TAEWorkItemService.HEADER_ACTIVE,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :request.Id].Status__c,
            'Life Science grant should activate the request'
        );
        System.assert(emailsSent > 0, 'Life Science grant should send Temporary Coverage Access Granted');
    }

    @IsTest
    static void healthcareGrantStillSendsTheHealthcareEmail() {
        User requester = insertUser(nonLifeScienceProfileId(), 'hcReq');
        stopTemporaryAccessFlows(UserInfo.getUserId());
        TemporaryAccessException__c request = newRequest(requester.Id, UserInfo.getUserId());
        insert request;

        Integer emailsSent;
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TAEWorkItemService.finalizeTae(request.Id, TAEWorkItemService.OP_GRANT);
            emailsSent = Limits.getEmailInvocations();
        }
        Test.stopTest();

        System.assertEquals(
            TAEWorkItemService.HEADER_ACTIVE,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :request.Id].Status__c,
            'Healthcare grant should still become Active'
        );
        System.assert(emailsSent > 0, 'Healthcare grant should still send the Healthcare email');
    }

    private static TemporaryAccessException__c newRequest(Id requesterId, Id coverageRepId) {
        return new TemporaryAccessException__c(
            Requester__c = requesterId,
            CoverageRep__c = coverageRepId,
            ExceptionCategory__c = 'PTO',
            StartDate__c = Date.today().addDays(1),
            EndDate__c = Date.today().addDays(4)
        );
    }

    /** The Coverage Rep's manager receives the Life Science emails, so the test coverage rep needs one. */
    private static void giveManager(Id userId, Id managerId) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = userId, ManagerId = managerId);
        }
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
        return [
            SELECT Id
            FROM Profile
            WHERE Name = :LSTemporaryAccessExceptionEmailService.LIFE_SCIENCE_SALES_PROFILE
            LIMIT 1
        ];
    }

    private static Id nonLifeScienceProfileId() {
        Profile running = [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId()];
        if (running.Name != LSTemporaryAccessExceptionEmailService.LIFE_SCIENCE_SALES_PROFILE) {
            return running.Id;
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
            Username = token + '@taels.test'
        );
        insert user;
        if (profileId == lifeScienceProfile().Id) {
            insert new PermissionSetAssignment(
                AssigneeId = user.Id,
                PermissionSetGroupId = lifeSciencePermissionSetGroupId()
            );
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