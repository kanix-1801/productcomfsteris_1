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

    @IsTest
    static void assignedOpportunityOnAnotherAccountReturnsToTheOriginalRep() {
        User originalRep = insertUser('orig2');
        User coverageRep = insertUser('cov2');
        stopTemporaryAccessFlows(UserInfo.getUserId());
        insert new Automation_Setting_Validation_Rule__c(SetupOwnerId = UserInfo.getUserId(), disableAll__c = true);
        Account covered = new Account(Name = 'GCL103 Covered Two');
        Account other = new Account(Name = 'GCL103 Other Two');
        insert new List<Account>{ covered, other };

        Id equipmentRecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('LSEquipmentService').getRecordTypeId();
        Opportunity assignedOpportunity = new Opportunity(
            Name = 'GCL103 Assigned Closed',
            AccountId = other.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            OwnerId = coverageRep.Id,
            RecordTypeId = equipmentRecordTypeId
        );
        Opportunity unrelatedOpportunity = new Opportunity(
            Name = 'GCL103 Unrelated',
            AccountId = other.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today().addDays(3),
            OwnerId = coverageRep.Id,
            RecordTypeId = equipmentRecordTypeId
        );
        insert new List<Opportunity>{ assignedOpportunity, unrelatedOpportunity };
        Task taskOnAssignedOpportunity = new Task(
            Subject = 'GCL103 On Assigned Opp',
            WhatId = assignedOpportunity.Id,
            OwnerId = coverageRep.Id,
            Status = 'Completed'
        );
        insert taskOnAssignedOpportunity;

        TemporaryAccessException__c request = new TemporaryAccessException__c(
            Requester__c = originalRep.Id,
            CoverageRep__c = coverageRep.Id,
            ExceptionCategory__c = 'PTO',
            StartDate__c = Date.today(),
            EndDate__c = Date.today().addDays(1)
        );
        insert request;
        insert new List<TAE_AssignedRecord__c>{
            new TAE_AssignedRecord__c(TemporaryAccessException__c = request.Id, Account__c = covered.Id),
            new TAE_AssignedRecord__c(TemporaryAccessException__c = request.Id, Opportunity__c = assignedOpportunity.Id)
        };

        LSTemporaryAccessReassignmentService.reassignOnExpiry(
            new List<TemporaryAccessException__c>{ request },
            new Set<Id>{ request.Id }
        );

        System.assertEquals(originalRep.Id, [SELECT OwnerId FROM Opportunity WHERE Id = :assignedOpportunity.Id].OwnerId);
        System.assertEquals(coverageRep.Id, [SELECT OwnerId FROM Opportunity WHERE Id = :unrelatedOpportunity.Id].OwnerId);
        System.assertEquals(originalRep.Id, [SELECT OwnerId FROM Task WHERE Id = :taskOnAssignedOpportunity.Id].OwnerId);
    }

    @IsTest
    static void handbackIgnoresPositionInFunnelRuleAndRestoresTheSwitch() {
        User originalRep = insertUser('orig3');
        User coverageRep = insertUser('cov3');
        stopTemporaryAccessFlows(UserInfo.getUserId());
        Automation_Setting_Validation_Rule__c setupSwitch =
            new Automation_Setting_Validation_Rule__c(SetupOwnerId = UserInfo.getUserId(), disableAll__c = true);
        insert setupSwitch;
        Account covered = new Account(Name = 'GCL103 Covered Three');
        insert covered;
        Opportunity closedWon = new Opportunity(
            Name = 'GCL103 Closed Won No Funnel',
            AccountId = covered.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            OwnerId = coverageRep.Id,
            RecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
                .get('LSEquipmentService').getRecordTypeId()
        );
        insert closedWon;
        TemporaryAccessException__c request = new TemporaryAccessException__c(
            Requester__c = originalRep.Id,
            CoverageRep__c = coverageRep.Id,
            ExceptionCategory__c = 'PTO',
            StartDate__c = Date.today(),
            EndDate__c = Date.today().addDays(1)
        );
        insert request;
        insert new TAE_AssignedRecord__c(TemporaryAccessException__c = request.Id, Account__c = covered.Id);
        delete setupSwitch;

        LSTemporaryAccessReassignmentService.reassignOnExpiry(
            new List<TemporaryAccessException__c>{ request },
            new Set<Id>{ request.Id }
        );

        System.assertEquals(originalRep.Id, [SELECT OwnerId FROM Opportunity WHERE Id = :closedWon.Id].OwnerId);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Automation_Setting_Validation_Rule__c WHERE SetupOwnerId = :UserInfo.getUserId()],
            'The temporary validation switch must be removed after the handback.'
        );
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