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
                PrimaryCustomerContact__c = testContact.Id,
                CustomerLocationType__c = 'Customer Site',
                ExactProposedLocation__c = 'Confirmed Room',
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
        System.assertEquals(
            'GC-3483 Calendar Account',
            data.events[0].accountName,
            'Expected the customer name on the calendar entry.'
        );
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

    @IsTest
    static void getCalendarKeepsBackupToOneDayUntilConfirmed() {
        Account testAccount = [
            SELECT Id
            FROM Account
            WHERE Name = 'GC-3483 Calendar Account'
            LIMIT 1
        ];
        Opportunity capitalOpportunity = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'GC-3483 Calendar Opportunity'
            LIMIT 1
        ];
        Contact testContact = [
            SELECT Id
            FROM Contact
            WHERE LastName = 'GC-3483 Calendar Contact'
            LIMIT 1
        ];
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
        Date pendingPrimary = Date.today().addDays(20);
        Date pendingBackup = Date.today().addDays(30);
        Date confirmedBackupStart = Date.today().addDays(40);
        Date confirmedPrimaryStart = Date.today().addDays(60);

        MockRoomOrORIRequest__c pendingRequest = new MockRoomOrORIRequest__c(
            Opportunity__c = capitalOpportunity.Id,
            Account__c = testAccount.Id,
            RecordTypeId = mockRoomTypeId,
            Status__c = 'Draft',
            Requestor__c = salesUser.Id,
            CustomerLocationType__c = 'Customer Site',
            ExactProposedLocation__c = 'Duration Room',
            PrimaryRequestedDate__c = pendingPrimary,
            BackupRequestedDate__c = pendingBackup,
            EventDurationDays__c = 5
        );
        MockRoomOrORIRequest__c confirmedBackup = new MockRoomOrORIRequest__c(
            Opportunity__c = capitalOpportunity.Id,
            Account__c = testAccount.Id,
            RecordTypeId = mockRoomTypeId,
            Status__c = 'Approved',
            PrimaryCustomerContact__c = testContact.Id,
            CustomerLocationType__c = 'Customer Site',
            ExactProposedLocation__c = 'Confirmed Backup Room',
            PrimaryRequestedDate__c = Date.today().addDays(50),
            BackupRequestedDate__c = confirmedBackupStart,
            ConfirmedDateSelection__c = 'Backup',
            EventDurationDays__c = 5
        );
        MockRoomOrORIRequest__c confirmedPrimary = new MockRoomOrORIRequest__c(
            Opportunity__c = capitalOpportunity.Id,
            Account__c = testAccount.Id,
            RecordTypeId = mockRoomTypeId,
            Status__c = 'Approved',
            PrimaryCustomerContact__c = testContact.Id,
            CustomerLocationType__c = 'Customer Site',
            ExactProposedLocation__c = 'Confirmed Primary Room',
            PrimaryRequestedDate__c = confirmedPrimaryStart,
            BackupRequestedDate__c = Date.today().addDays(66),
            ConfirmedDateSelection__c = 'Primary',
            EventDurationDays__c = 5
        );
        insert new List<MockRoomOrORIRequest__c>{ pendingRequest, confirmedBackup, confirmedPrimary };

        System.runAs(salesUser) {
            Test.startTest();
            MockRoomORICalendarController.CalendarData data = MockRoomORICalendarController.getCalendar(
                Date.today(),
                Date.today().addDays(70),
                null
            );
            Test.stopTest();

            Integer pendingPrimaryDays = 0;
            Integer pendingBackupDays = 0;
            Integer confirmedBackupDays = 0;
            Integer confirmedPrimaryDays = 0;
            for (MockRoomORICalendarController.CalendarEvent eventRow : data.events) {
                if (eventRow.requestId == pendingRequest.Id && eventRow.dateRole == 'Primary') {
                    pendingPrimaryDays++;
                }
                if (eventRow.requestId == pendingRequest.Id && eventRow.dateRole == 'Backup') {
                    pendingBackupDays++;
                }
                if (eventRow.requestId == confirmedBackup.Id && eventRow.dateRole == 'Confirmed') {
                    confirmedBackupDays++;
                }
                if (eventRow.requestId == confirmedPrimary.Id && eventRow.dateRole == 'Confirmed') {
                    confirmedPrimaryDays++;
                }
            }
            System.assertEquals(5, pendingPrimaryDays, 'The primary date should cover the event duration.');
            System.assertEquals(1, pendingBackupDays, 'A backup requested date should stay one day.');
            System.assertEquals(
                5,
                confirmedBackupDays,
                'Confirming the backup date should cover the event duration from that date.'
            );
            System.assertEquals(
                5,
                confirmedPrimaryDays,
                'Confirming the primary date should cover the event duration from that date.'
            );
        }
    }
}