@IsTest
private class LSTemporaryAccessReassignmentServiceTest {

    @IsTest
    static void lifeScienceExpiryMovesOwnedRecordsBackToTheOriginalRep() {
        User originalRep = insertUser('orig');
        User coverageRep = insertUser('cov');
        stopTemporaryAccessFlows(UserInfo.getUserId());
        insert new Automation_Setting_Validation_Rule__c(SetupOwnerId = UserInfo.getUserId(), disableAll__c = true);
        Account covered = new Account(Name = 'GCL103 Covered');
        Account other = new Account(Name = 'GCL103 Other');
        insert new List<Account>{ covered, other };

        String stageName = [
            SELECT MasterLabel
            FROM OpportunityStage
            WHERE IsActive = true
              AND IsClosed = false
            ORDER BY SortOrder
            LIMIT 1
        ].MasterLabel;
        Opportunity coveredOpportunity = new Opportunity(
            Name = 'GCL103 Opp',
            AccountId = covered.Id,
            StageName = stageName,
            CloseDate = Date.today(),
            OwnerId = coverageRep.Id
        );
        Opportunity otherOpportunity = new Opportunity(
            Name = 'GCL103 Other Opp',
            AccountId = other.Id,
            StageName = stageName,
            CloseDate = Date.today().addDays(10),
            OwnerId = coverageRep.Id
        );
        insert new List<Opportunity>{ coveredOpportunity, otherOpportunity };

        Task openTask = new Task(
            Subject = 'GCL103 Open',
            WhatId = covered.Id,
            OwnerId = coverageRep.Id,
            Status = 'Not Started',
            ActivityDate = Date.today().addDays(2)
        );
        Task completedTask = new Task(
            Subject = 'GCL103 Done',
            WhatId = covered.Id,
            OwnerId = coverageRep.Id,
            Status = 'Completed',
            ActivityDate = Date.today()
        );
        insert new List<Task>{ openTask, completedTask };

        Event futureMeeting = new Event(
            Subject = 'GCL103 Meeting',
            WhatId = covered.Id,
            OwnerId = coverageRep.Id,
            StartDateTime = DateTime.now().addDays(1),
            EndDateTime = DateTime.now().addDays(1).addHours(1)
        );
        insert futureMeeting;

        Contact coveredContact = new Contact(
            LastName = 'GCL103',
            AccountId = covered.Id,
            OwnerId = coverageRep.Id
        );
        insert coveredContact;

        TemporaryAccessException__c request = new TemporaryAccessException__c(
            Requester__c = originalRep.Id,
            CoverageRep__c = coverageRep.Id,
            ExceptionCategory__c = 'PTO',
            StartDate__c = Date.today(),
            EndDate__c = Date.today().addDays(5)
        );
        insert request;
        insert new TAE_AssignedRecord__c(
            TemporaryAccessException__c = request.Id,
            Account__c = covered.Id
        );

        Test.startTest();
        LSTemporaryAccessReassignmentService.reassignOnExpiry(
            new List<TemporaryAccessException__c>{ request },
            new Set<Id>{ request.Id }
        );
        Test.stopTest();

        System.assertEquals(originalRep.Id, [SELECT OwnerId FROM Opportunity WHERE Id = :coveredOpportunity.Id].OwnerId);
        System.assertEquals(coverageRep.Id, [SELECT OwnerId FROM Opportunity WHERE Id = :otherOpportunity.Id].OwnerId);
        System.assertEquals(originalRep.Id, [SELECT OwnerId FROM Task WHERE Id = :openTask.Id].OwnerId);
        System.assertEquals(originalRep.Id, [SELECT OwnerId FROM Task WHERE Id = :completedTask.Id].OwnerId);
        System.assertEquals(originalRep.Id, [SELECT OwnerId FROM Event WHERE Id = :futureMeeting.Id].OwnerId);
        System.assertEquals(originalRep.Id, [SELECT OwnerId FROM Contact WHERE Id = :coveredContact.Id].OwnerId);
        System.assertEquals(UserInfo.getUserId(), [SELECT CreatedById FROM Task WHERE Id = :completedTask.Id].CreatedById);
    }

    private static void stopTemporaryAccessFlows(Id userId) {
        insert new Automation_Setting_Flow__c(
            SetupOwnerId = userId,
            TemporaryAccessSubmitForApproval__c = true,
            TemporaryAccessApprovalProcess__c = true
        );
    }

    private static Integer userSequence = 0;

    private static User insertUser(String aliasSeed) {
        userSequence++;
        String token = String.valueOf(DateTime.now().getTime()) + userSequence;
        User user = new User(
            Alias = aliasSeed.left(8),
            Email = token + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = aliasSeed,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'America/New_York',
            Username = token + '@gcl103.test'
        );
        insert user;
        return user;
    }
}