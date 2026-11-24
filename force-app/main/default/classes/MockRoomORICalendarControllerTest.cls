/**
* @description GC-3483. Covers the shared calendar query for events, blocks, drafts, one-day dates regardless of event duration, and the request being edited.
*/
@IsTest
private class MockRoomORICalendarControllerTest {
    
    private static final Id MOCK_ROOM_TYPE_ID = Schema.SObjectType.MockRoomOrORIRequest__c
        .getRecordTypeInfosByDeveloperName()
        .get('MockRoom')
        .getRecordTypeId();
    private static final String DRAFT = 'Draft';
    private static final String APPROVED = 'Approved';
    private static final String PRIMARY = 'Primary';
    private static final String BACKUP = 'Backup';
    private static final String CONFIRMED = 'Confirmed';
    
    @TestSetup
    static void setupData() {
        Account testAccount = new Account(Name = 'GC-3483 Calendar Account', SourceSystemID__c = 'GC3483-CAL-001');
        insert testAccount;
        Contact testContact = new Contact(LastName = 'GC-3483 Calendar Contact', AccountId = testAccount.Id);
        insert testContact;
        Opportunity capitalOpportunity = new Opportunity(
            Name = 'GC-3483 Calendar Opportunity',
            AccountId = testAccount.Id,
            RecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('Healthcare_Sales')
            .getRecordTypeId(),
            StageName = 'Discovery',
            ForecastConfidenceLevel__c = 'Pipeline',
            Type = 'New Business',
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = testContact.Id,
            CloseDate = Date.today().addDays(30)
        );
        insert capitalOpportunity;
        
        Id salesUserId = getSalesUser().Id;
        MockRoomOrORIRequest__c approvedRequest = newRequest(capitalOpportunity, null, APPROVED, Date.today(), Date.today().addDays(2));
        approvedRequest.ConfirmedDateSelection__c = PRIMARY;
        MockRoomOrORIRequest__c unfinishedDraft = newRequest(capitalOpportunity, salesUserId, DRAFT, Date.today().addDays(1), null);
        unfinishedDraft.CustomerLocationType__c = null;
        unfinishedDraft.ExactProposedLocation__c = null;
        insert new List<MockRoomOrORIRequest__c>{
            approvedRequest,
                newRequest(capitalOpportunity, salesUserId, DRAFT, Date.today().addDays(3), Date.today().addDays(4)),
                unfinishedDraft
                };
                    insert new MockRoomORICalendarBlock__c(
                        StartDate__c = Date.today().addDays(5),
                        EndDate__c = Date.today().addDays(6),
                        Reason__c = 'Trade Show'
                    );
    }
    
    @IsTest
    static void getCalendarReturnsEventsAndBlocksInRange() {
        Test.startTest();
        MockRoomORICalendarController.CalendarData data = MockRoomORICalendarController.getCalendar(Date.today(), Date.today().addDays(10), null);
        Test.stopTest();
        
        Assert.areEqual(1, data.events.size(), 'Expected only the confirmed requested date.');
        Assert.areEqual(Date.today(), data.events[0].eventDate, 'Expected the primary date that was selected.');
        Assert.areEqual(CONFIRMED, data.events[0].dateRole, 'Expected an approved request to show as confirmed.');
        Assert.areEqual('GC-3483 Calendar Account', data.events[0].accountName, 'Expected the customer name on the calendar entry.');
        Assert.areEqual(1, data.blocks.size(), 'Expected the trade show block.');
        Assert.areEqual('Trade Show', data.blocks[0].reason, 'Expected the block reason.');
        Assert.areEqual(Date.today().addDays(5), data.blocks[0].startDate, 'The block should keep its start date.');
        Assert.areEqual(Date.today().addDays(6), data.blocks[0].endDate, 'The block should keep its full range to the end date.');
    }
    
    @IsTest
    static void getCalendarShowsTheRequestorsSavedDraftOnly() {
        MockRoomOrORIRequest__c savedDraft = [SELECT Id FROM MockRoomOrORIRequest__c WHERE Status__c = :DRAFT AND CustomerLocationType__c != null LIMIT 1];
        MockRoomOrORIRequest__c unfinishedDraft = [SELECT Id FROM MockRoomOrORIRequest__c WHERE Status__c = :DRAFT AND CustomerLocationType__c = null LIMIT 1];
        
        System.runAs(getSalesUser()) {
            Test.startTest();
            MockRoomORICalendarController.CalendarData data = MockRoomORICalendarController.getCalendar(Date.today(), Date.today().addDays(10), savedDraft.Id);
            Test.stopTest();
            
            Map<String, Integer> dayCounts = countDays(data);
            Assert.areEqual(1, dayCounts.get(savedDraft.Id + PRIMARY), 'The requestor and the request being edited should see the primary date.');
            Assert.areEqual(1, dayCounts.get(savedDraft.Id + BACKUP), 'A request that is not approved should hold both requested dates.');
            Assert.isNull(dayCounts.get(unfinishedDraft.Id + PRIMARY), 'An unfinished draft should stay off the calendar.');
        }
    }
    
    @IsTest
    static void getCalendarShowsOneDayPerDateRegardlessOfEventDuration() {
        Opportunity capitalOpportunity = [SELECT Id, AccountId, PrimaryContact__c FROM Opportunity WHERE Name = 'GC-3483 Calendar Opportunity' LIMIT 1];
        User salesUser = getSalesUser();
        MockRoomOrORIRequest__c pendingRequest = newRequest(capitalOpportunity, salesUser.Id, DRAFT, Date.today().addDays(20), Date.today().addDays(30));
        MockRoomOrORIRequest__c confirmedBackup = newRequest(capitalOpportunity, null, APPROVED, Date.today().addDays(50), Date.today().addDays(40));
        confirmedBackup.ConfirmedDateSelection__c = BACKUP;
        MockRoomOrORIRequest__c confirmedPrimary = newRequest(capitalOpportunity, null, APPROVED, Date.today().addDays(60), Date.today().addDays(66));
        confirmedPrimary.ConfirmedDateSelection__c = PRIMARY;
        List<MockRoomOrORIRequest__c> requests = new List<MockRoomOrORIRequest__c>{ pendingRequest, confirmedBackup, confirmedPrimary };
            for (MockRoomOrORIRequest__c requestRecord : requests) {
                requestRecord.EventDurationDays__c = 3;
            }
        insert requests;
        
        System.runAs(salesUser) {
            Test.startTest();
            Map<String, Integer> dayCounts = countDays(
                MockRoomORICalendarController.getCalendar(Date.today(), Date.today().addDays(70), null)
            );
            Test.stopTest();
            
            Assert.areEqual(1, dayCounts.get(pendingRequest.Id + PRIMARY), 'A 3-day event should show only the primary date.');
            Assert.areEqual(1, dayCounts.get(pendingRequest.Id + BACKUP), 'A backup requested date should stay one day.');
            Assert.areEqual(1, dayCounts.get(confirmedBackup.Id + CONFIRMED), 'A confirmed backup date should show one day.');
            Assert.areEqual(1, dayCounts.get(confirmedPrimary.Id + CONFIRMED), 'A confirmed primary date should show one day.');
        }
    }
    
    @IsTest
    static void getCalendarReturnsFriendlyErrorForInvalidRange() {
        String errorMessage;
        Test.startTest();
        try {
            MockRoomORICalendarController.getCalendar(Date.today(), Date.today().addDays(-1), null);
        } catch (AuraHandledException exceptionValue) {
            errorMessage = exceptionValue.getMessage();
        }
        Test.stopTest();
        
        Assert.isNotNull(errorMessage, 'An end date before the start date should return a friendly error.');
    }
    
    private static User getSalesUser() {
        User salesUser = [SELECT Id FROM User WHERE Profile.Name = 'Healthcare Sales' AND IsActive = true LIMIT 1];
        return salesUser;
    }
    
    private static MockRoomOrORIRequest__c newRequest(Opportunity opportunityRecord, Id requestorId, String status, Date primaryDate, Date backupDate) {
        MockRoomOrORIRequest__c requestRecord = new MockRoomOrORIRequest__c(
            Opportunity__c = opportunityRecord.Id,
            Account__c = opportunityRecord.AccountId,
            RecordTypeId = MOCK_ROOM_TYPE_ID,
            Status__c = status,
            Requestor__c = requestorId,
            PrimaryCustomerContact__c = opportunityRecord.PrimaryContact__c,
            CustomerLocationType__c = 'Customer Site',
            ExactProposedLocation__c = 'Calendar Room',
            PrimaryRequestedDate__c = primaryDate,
            BackupRequestedDate__c = backupDate
        );
        return requestRecord;
    }
    
    private static Map<String, Integer> countDays(MockRoomORICalendarController.CalendarData data) {
        Map<String, Integer> dayCounts = new Map<String, Integer>();
        for (MockRoomORICalendarController.CalendarEvent eventRow : data.events) {
            String key = eventRow.requestId + eventRow.dateRole;
            dayCounts.put(key, (dayCounts.containsKey(key) ? dayCounts.get(key) : 0) + 1);
        }
        return dayCounts;
    }
}