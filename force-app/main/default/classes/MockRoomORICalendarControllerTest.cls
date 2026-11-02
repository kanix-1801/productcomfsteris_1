/**
 * @description GC-3483. Covers the shared calendar query for events, blocks, and the request being edited.
 */
@IsTest
private class MockRoomORICalendarControllerTest {

    @TestSetup
    static void setupData() {
        Account testAccount = new Account(
            Name = 'GC-3483 Calendar Account',
            SourceSystemID__c = 'GC3483-CAL-001'
        );
        insert testAccount;

        Contact testContact = new Contact(
            LastName = 'GC-3483 Calendar Contact',
            AccountId = testAccount.Id
        );
        insert testContact;

        Opportunity capitalOpportunity = new Opportunity(
            Name = 'GC-3483 Calendar Opportunity',
            AccountId = testAccount.Id,
            RecordTypeId = Schema.SObjectType.Opportunity
                .getRecordTypeInfosByDeveloperName()
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

        Id mockRoomTypeId = Schema.SObjectType.MockRoomOrORIRequest__c
            .getRecordTypeInfosByDeveloperName()
            .get('MockRoom')
            .getRecordTypeId();
        User salesUser = [
            SELECT Id
            FROM User
            WHERE Profile.Name = 'Healthcare Sales'
            AND IsActive = true
            LIMIT 1
        ];

        insert new List<MockRoomOrORIRequest__c>{
            new MockRoomOrORIRequest__c(
                Opportunity__c = capitalOpportunity.Id,
                Account__c = testAccount.Id,
                RecordTypeId = mockRoomTypeId,
                Status__c = 'Approved',
                PrimaryRequestedDate__c = Date.today(),
                BackupRequestedDate__c = Date.today().addDays(2),
                ConfirmedDateSelection__c = 'Primary'
            ),
            new MockRoomOrORIRequest__c(
                Opportunity__c = capitalOpportunity.Id,
                Account__c = testAccount.Id,
                RecordTypeId = mockRoomTypeId,
                Status__c = 'Draft',
                Requestor__c = salesUser.Id,
                CustomerLocationType__c = 'Customer Site',
                ExactProposedLocation__c = 'Room 1',
                PrimaryRequestedDate__c = Date.today().addDays(3),
                BackupRequestedDate__c = Date.today().addDays(4)
            ),
            new MockRoomOrORIRequest__c(
                Opportunity__c = capitalOpportunity.Id,
                Account__c = testAccount.Id,
                RecordTypeId = mockRoomTypeId,
                Status__c = 'Draft',
                Requestor__c = salesUser.Id,
                PrimaryRequestedDate__c = Date.today().addDays(1)
            )
        };

        insert new MockRoomORICalendarBlock__c(
            StartDate__c = Date.today().addDays(5),
            EndDate__c = Date.today().addDays(6),
            Reason__c = 'Trade Show'
        );
    }

    @IsTest
    static void getCalendar_returnsEventsAndBlocksInRange() {
        Test.startTest();
        MockRoomORICalendarController.CalendarData data = MockRoomORICalendarController.getCalendar(
            Date.today(),
            Date.today().addDays(10),
            null
        );
        Test.stopTest();

        System.assertEquals(1, data.events.size(), 'Expected only the confirmed requested date.');
        System.assertEquals(Date.today(), data.events[0].eventDate, 'Expected the primary date that was selected.');
        System.assertEquals('Confirmed', data.events[0].dateRole);
        System.assertEquals(1, data.blocks.size(), 'Expected the trade show block.');
        System.assertEquals('Trade Show', data.blocks[0].reason);
    }

    @IsTest
    static void getCalendar_showsTheRequestorsSavedDraftOnly() {
        User salesUser = [
            SELECT Id
            FROM User
            WHERE Profile.Name = 'Healthcare Sales'
            AND IsActive = true
            LIMIT 1
        ];
        MockRoomOrORIRequest__c savedDraft = [
            SELECT Id
            FROM MockRoomOrORIRequest__c
            WHERE Status__c = 'Draft'
            AND CustomerLocationType__c != null
            LIMIT 1
        ];
        MockRoomOrORIRequest__c unfinishedDraft = [
            SELECT Id
            FROM MockRoomOrORIRequest__c
            WHERE Status__c = 'Draft'
            AND CustomerLocationType__c = null
            LIMIT 1
        ];

        System.runAs(salesUser) {
            Test.startTest();
            MockRoomORICalendarController.CalendarData data = MockRoomORICalendarController.getCalendar(
                Date.today(),
                Date.today().addDays(10),
                null
            );
            Test.stopTest();

            Set<Id> eventRequestIds = new Set<Id>();
            Set<String> draftRoles = new Set<String>();
            for (MockRoomORICalendarController.CalendarEvent eventRow : data.events) {
                eventRequestIds.add(eventRow.requestId);
                if (eventRow.requestId == savedDraft.Id) {
                    draftRoles.add(eventRow.dateRole);
                }
            }
            System.assert(eventRequestIds.contains(savedDraft.Id), 'Expected the requestor to see their saved draft.');
            System.assertEquals(
                new Set<String>{ 'Primary', 'Backup' },
                draftRoles,
                'A request that is not approved should hold both requested dates.'
            );
            System.assert(
                !eventRequestIds.contains(unfinishedDraft.Id),
                'An unfinished draft should stay off the calendar.'
            );
        }
    }

    @IsTest
    static void getCalendar_keepsTheRequestBeingEditedVisible() {
        User salesUser = [
            SELECT Id
            FROM User
            WHERE Profile.Name = 'Healthcare Sales'
            AND IsActive = true
            LIMIT 1
        ];
        MockRoomOrORIRequest__c draftRequest = [
            SELECT Id
            FROM MockRoomOrORIRequest__c
            WHERE Status__c = 'Draft'
            AND CustomerLocationType__c != null
            LIMIT 1
        ];

        System.runAs(salesUser) {
            Test.startTest();
            MockRoomORICalendarController.CalendarData data = MockRoomORICalendarController.getCalendar(
                Date.today(),
                Date.today().addDays(10),
                draftRequest.Id
            );
            Test.stopTest();

            Set<Id> eventRequestIds = new Set<Id>();
            for (MockRoomORICalendarController.CalendarEvent eventRow : data.events) {
                eventRequestIds.add(eventRow.requestId);
            }
            System.assert(
                eventRequestIds.contains(draftRequest.Id),
                'The request being edited should stay visible on the calendar.'
            );
        }
    }
}