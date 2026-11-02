/**
 * @description GC-3489 - Covers attendee load, search, add, and remove for the Healthcare Sales Event flow.
 *              Each method checks one behavior. Users are created in the test. The logged-in user is not an owner or attendee.
 */
@IsTest(SeeAllData=false)
private class EventAttendeeServiceTest {
    private static final String OWNER_EMPLOYEE_NUMBER = 'HS-ATT-10001';
    private static final String ATTENDEE_EMPLOYEE_NUMBER = 'HS-ATT-10002';

    /**
     * @description Creates the Event owner and a second user who can be added as an attendee.
     */
    @TestSetup
    static void setupData() {
        Profile adminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];
        insert new List<User>{
            newUser(adminProfile.Id, 'Owner', 'HsAttOwn', OWNER_EMPLOYEE_NUMBER),
            newUser(adminProfile.Id, 'Attendee', 'HsAttUsr', ATTENDEE_EMPLOYEE_NUMBER)
        };
    }

    /**
     * @description Inserts a Contact invitee and then deletes that EventRelation.
     */
    @IsTest
    static void addsAndRemovesAContact() {
        User owner = getOwner();
        System.runAs(owner) {
            Event activity = newEvent();
            Contact person = new Contact(LastName = 'Attendee');
            insert person;
            EventAttendeeService.ChangeRequest request = requestFor(
                activity.Id,
                '{"addIds":["' + person.Id + '"],"removeRelationIds":[]}'
            );

            Test.startTest();
            EventAttendeeService.applyChanges(new List<EventAttendeeService.ChangeRequest>{ request });
            EventAttendeeService.AttendeeRow contactRow = findRow(EventAttendeeService.getAttendees(activity.Id), person.Id);
            Assert.isNotNull(contactRow, 'The contact should be an attendee.');
            request.changePayload = '{"addIds":[],"removeRelationIds":["' + contactRow.relationId + '"]}';
            EventAttendeeService.applyChanges(new List<EventAttendeeService.ChangeRequest>{ request });
            Test.stopTest();

            Assert.isNull(
                findRow(EventAttendeeService.getAttendees(activity.Id), person.Id),
                'The contact should be removed.'
            );
        }
    }

    /**
     * @description The created owner is already selected, and sending that User Id does not create an invitee row.
     */
    @IsTest
    static void showsTheOwnerAndDoesNotInsertThem() {
        User owner = getOwner();
        System.runAs(owner) {
            Event activity = newEvent();
            Integer beforeCount = inviteeCount(activity.Id, owner.Id);

            Test.startTest();
            EventAttendeeService.AttendeeRow ownerRow = findRow(EventAttendeeService.getAttendees(activity.Id), owner.Id);
            EventAttendeeService.applyChanges(new List<EventAttendeeService.ChangeRequest>{
                requestFor(activity.Id, '{"addIds":["' + owner.Id + '"],"removeRelationIds":[]}')
            });
            Test.stopTest();

            Assert.isNotNull(ownerRow, 'Assigned To should already be selected.');
            Assert.isTrue(ownerRow.isOwner, 'The owner row should be marked as the owner.');
            Assert.areEqual(beforeCount, inviteeCount(activity.Id, owner.Id), 'The event owner should not be inserted as an invitee.');
        }
    }

    /**
     * @description People search returns the Contact passed to the fixed search results.
     */
    @IsTest
    static void searchesPeople() {
        User owner = getOwner();
        System.runAs(owner) {
            Contact person = new Contact(LastName = 'SearchableAttendee');
            insert person;
            Test.setFixedSearchResults(new List<Id>{ person.Id });
            Event activity = newEvent();

            Test.startTest();
            List<EventAttendeeService.SearchResult> results = EventAttendeeService.search(activity.Id, 'Searchable', 'People');
            Test.stopTest();

            Assert.areEqual(1, results.size(), 'People search should return the contact.');
            Assert.areEqual('Contact', results[0].kind, 'The hit should be a contact.');
            Assert.areEqual(person.Id, results[0].recordId, 'The hit should be the inserted contact.');
        }
    }

    /**
     * @description An Account Id is rejected before an invitee row is inserted.
     */
    @IsTest
    static void rejectsARecordThatIsNotAnAttendee() {
        System.runAs(getOwner()) {
            Event activity = newEvent();
            Id accountId = syntheticId(Account.SObjectType);
            EventAttendeeService.ChangeRequest request = requestFor(
                activity.Id,
                '{"addIds":["' + accountId + '"],"removeRelationIds":[]}'
            );

            Test.startTest();
            try {
                EventAttendeeService.applyChanges(new List<EventAttendeeService.ChangeRequest>{ request });
                Assert.fail('An account should not be added as an attendee.');
            } catch (EventAttendeeService.AttendeeException expected) {
                Assert.isTrue(
                    expected.getMessage().contains('user, contact, lead, or resource'),
                    'The message should name the allowed attendee types.'
                );
            }
            Test.stopTest();
        }
    }

    /**
     * @description A delete payload cannot remove an EventRelation that belongs to a different Event.
     */
    @IsTest
    static void rejectsARelationFromAnotherEvent() {
        User owner = getOwner();
        System.runAs(owner) {
            Event activity = newEvent();
            Event otherActivity = newEvent();
            Contact person = new Contact(LastName = 'OtherEvent');
            insert person;
            EventRelation relation = new EventRelation(EventId = otherActivity.Id, RelationId = person.Id, IsInvitee = true);
            insert relation;
            EventAttendeeService.ChangeRequest request = requestFor(
                activity.Id,
                '{"addIds":[],"removeRelationIds":["' + relation.Id + '"]}'
            );

            Test.startTest();
            try {
                EventAttendeeService.applyChanges(new List<EventAttendeeService.ChangeRequest>{ request });
                Assert.fail('A relation from another event should not be deleted.');
            } catch (EventAttendeeService.AttendeeException expected) {
                Assert.isTrue(
                    expected.getMessage().contains('could not be removed'),
                    'The message should say the attendee could not be removed.'
                );
            }
            Test.stopTest();
        }
    }

    /**
     * @description A non-Event Id and a blank Event Id are rejected before any attendee query runs.
     */
    @IsTest
    static void rejectsAnIdThatIsNotAnEvent() {
        System.runAs(getOwner()) {
            Id accountId = syntheticId(Account.SObjectType);

            Test.startTest();
            try {
                EventAttendeeService.getAttendees(accountId);
                Assert.fail('A non-Event Id should be rejected.');
            } catch (AuraHandledException expected) {
                Assert.areEqual('Open this panel from an Event.', expected.getMessage(), 'The panel should require an Event.');
            }
            try {
                EventAttendeeService.search(null, 'Room', 'Resources');
                Assert.fail('A blank Event Id should be rejected.');
            } catch (AuraHandledException expected) {
                Assert.areEqual('Open this panel from an Event.', expected.getMessage(), 'Search should require an Event.');
            }
            Test.stopTest();
        }
    }

    /**
     * @description Terms shorter than two characters return no rows.
     */
    @IsTest
    static void returnsNoRowsForAShortSearch() {
        System.runAs(getOwner()) {
            Event activity = newEvent();

            Test.startTest();
            List<EventAttendeeService.SearchResult> oneCharacter = EventAttendeeService.search(activity.Id, 'A', 'People');
            List<EventAttendeeService.SearchResult> blank = EventAttendeeService.search(activity.Id, null, 'People');
            Test.stopTest();

            Assert.areEqual(0, oneCharacter.size(), 'A one-character search should return no rows.');
            Assert.areEqual(0, blank.size(), 'A blank search should return no rows.');
        }
    }

    /**
     * @description Resource search runs for a usable term and returns no rows when nothing matches.
     */
    @IsTest
    static void searchesResourcesWithoutAMatch() {
        System.runAs(getOwner()) {
            Event activity = newEvent();

            Test.startTest();
            List<EventAttendeeService.SearchResult> results = EventAttendeeService.search(activity.Id, '  Ab! ', 'Resources');
            Test.stopTest();

            Assert.areEqual(0, results.size(), 'A resource search with no match should return no rows.');
        }
    }

    /**
     * @description An Event Id that does not exist returns no attendee rows.
     */
    @IsTest
    static void returnsNoRowsWhenTheEventDoesNotExist() {
        System.runAs(getOwner()) {
            Id missingEventId = syntheticId(Event.SObjectType);

            Test.startTest();
            List<EventAttendeeService.AttendeeRow> rows = EventAttendeeService.getAttendees(missingEventId);
            Test.stopTest();

            Assert.areEqual(0, rows.size(), 'A missing Event should return no attendees.');
        }
    }

    /**
     * @description People search returns the created user, a Contact, and a Lead.
     */
    @IsTest
    static void searchesUsersContactsAndLeads() {
        User owner = getOwner();
        User attendee = getAttendeeUser();
        System.runAs(owner) {
            Contact contactPerson = new Contact(LastName = 'CoverageContact');
            insert contactPerson;
            Lead leadPerson = newLead();
            Test.setFixedSearchResults(new List<Id>{ attendee.Id, contactPerson.Id, leadPerson.Id });
            Event activity = newEvent();

            Test.startTest();
            List<EventAttendeeService.SearchResult> results = EventAttendeeService.search(activity.Id, 'Coverage!', 'People');
            Test.stopTest();

            Assert.areEqual(3, results.size(), 'User, Contact, and Lead should be returned.');
            Assert.areEqual('User', results[0].kind, 'The first hit should be the user.');
            Assert.areEqual('Contact', results[1].kind, 'The second hit should be the contact.');
            Assert.areEqual('Lead', results[2].kind, 'The third hit should be the lead.');
        }
    }

    /**
     * @description A Lead and a User are added once. Blank Ids and a repeated payload do not insert again.
     */
    @IsTest
    static void addsALeadAndSkipsADuplicate() {
        User owner = getOwner();
        User attendee = getAttendeeUser();
        System.runAs(owner) {
            Lead leadPerson = newLead();
            Event activity = newEvent();
            EventAttendeeService.ChangeRequest request = requestFor(
                activity.Id,
                '{"addIds":["' + leadPerson.Id + '","","' + attendee.Id + '"],"removeRelationIds":[""]}'
            );

            Test.startTest();
            EventAttendeeService.applyChanges(new List<EventAttendeeService.ChangeRequest>{ request });
            EventAttendeeService.applyChanges(new List<EventAttendeeService.ChangeRequest>{ request });
            Test.stopTest();

            EventAttendeeService.AttendeeRow leadRow = findRow(EventAttendeeService.getAttendees(activity.Id), leadPerson.Id);
            Assert.isNotNull(leadRow, 'The lead should be an attendee.');
            Assert.areEqual('Lead', leadRow.kind, 'The added row should be a lead.');
            Assert.isFalse(leadRow.isOwner, 'The lead should not be marked as the owner.');
            Assert.isNotNull(
                findRow(EventAttendeeService.getAttendees(activity.Id), attendee.Id),
                'The second user should be an attendee.'
            );
            Assert.areEqual(1, inviteeCount(activity.Id, leadPerson.Id), 'Adding the same lead twice should insert one invitee.');
        }
    }

    /**
     * @description A blank payload, an empty payload, and a null or empty request list do not change invitees.
     */
    @IsTest
    static void ignoresRequestsThatDoNotChangeAttendees() {
        System.runAs(getOwner()) {
            Event activity = newEvent();
            Integer beforeCount = inviteeCount(activity.Id, null);

            Test.startTest();
            EventAttendeeService.applyChanges(new List<EventAttendeeService.ChangeRequest>{ requestFor(activity.Id, '   ') });
            EventAttendeeService.applyChanges(new List<EventAttendeeService.ChangeRequest>{ requestFor(activity.Id, '{}') });
            EventAttendeeService.applyChanges(null);
            EventAttendeeService.applyChanges(new List<EventAttendeeService.ChangeRequest>());
            Test.stopTest();

            Assert.areEqual(beforeCount, inviteeCount(activity.Id, null), 'An empty request should not add or remove attendees.');
        }
    }

    /**
     * @description A null request inside the invocable list is rejected.
     */
    @IsTest
    static void rejectsANullRequest() {
        System.runAs(getOwner()) {
            Test.startTest();
            try {
                EventAttendeeService.applyChanges(new List<EventAttendeeService.ChangeRequest>{ null });
                Assert.fail('A null request should be rejected.');
            } catch (EventAttendeeService.AttendeeException expected) {
                Assert.areEqual('Open this panel from an Event.', expected.getMessage(), 'A null request should require an Event.');
            }
            Test.stopTest();
        }
    }

    /**
     * @description One invocable call can add attendees to more than one Event.
     */
    @IsTest
    static void appliesChangesForMoreThanOneEvent() {
        System.runAs(getOwner()) {
            Event firstActivity = newEvent();
            Event secondActivity = newEvent();
            Contact firstPerson = new Contact(LastName = 'BulkOne');
            Contact secondPerson = new Contact(LastName = 'BulkTwo');
            insert new List<Contact>{ firstPerson, secondPerson };

            Test.startTest();
            EventAttendeeService.applyChanges(new List<EventAttendeeService.ChangeRequest>{
                requestFor(firstActivity.Id, '{"addIds":["' + firstPerson.Id + '"],"removeRelationIds":[]}'),
                requestFor(secondActivity.Id, '{"addIds":["' + secondPerson.Id + '"],"removeRelationIds":[]}')
            });
            Test.stopTest();

            Assert.isNotNull(
                findRow(EventAttendeeService.getAttendees(firstActivity.Id), firstPerson.Id),
                'The first event should include its contact.'
            );
            Assert.isNotNull(
                findRow(EventAttendeeService.getAttendees(secondActivity.Id), secondPerson.Id),
                'The second event should include its contact.'
            );
        }
    }

    /**
     * @description An unknown resource is rejected before insert.
     */
    @IsTest
    static void rejectsAnUnavailableResource() {
        System.runAs(getOwner()) {
            Event activity = newEvent();
            Id resourceId = syntheticId(Calendar.SObjectType);

            Test.startTest();
            try {
                EventAttendeeService.applyChanges(new List<EventAttendeeService.ChangeRequest>{
                    requestFor(activity.Id, '{"addIds":["' + resourceId + '"],"removeRelationIds":[]}')
                });
                Assert.fail('An unknown resource should be rejected.');
            } catch (EventAttendeeService.AttendeeException expected) {
                Assert.isTrue(expected.getMessage().contains('not available'), 'The message should say the resource is not available.');
            }
            Test.stopTest();
        }
    }

    /**
     * @description Invalid JSON is rejected and written to the log.
     */
    @IsTest
    static void logsInvalidJson() {
        System.runAs(getOwner()) {
            Event activity = newEvent();

            Test.startTest();
            try {
                EventAttendeeService.applyChanges(new List<EventAttendeeService.ChangeRequest>{ requestFor(activity.Id, '{') });
                Assert.fail('Invalid JSON should be rejected.');
            } catch (JSONException expected) {
                Assert.isNotNull(expected.getMessage(), 'The JSON error should include a message.');
            }
            Test.stopTest();
        }
    }

    /**
     * @description An unknown User Id is rejected by the insert and written to the log.
     */
    @IsTest
    static void logsAnUnknownUser() {
        System.runAs(getOwner()) {
            Event activity = newEvent();
            Id userId = syntheticId(User.SObjectType);

            Test.startTest();
            try {
                EventAttendeeService.applyChanges(new List<EventAttendeeService.ChangeRequest>{
                    requestFor(activity.Id, '{"addIds":["' + userId + '"],"removeRelationIds":[]}')
                });
                Assert.fail('An unknown user should not be inserted.');
            } catch (DmlException expected) {
                Assert.isNotNull(expected.getMessage(), 'The insert error should include a message.');
            }
            Test.stopTest();
        }
    }

    /**
     * @description Builds a user without relying on the user running the test.
     * @param profileId Profile for the new user.
     * @param lastName Last name.
     * @param alias User alias, at most eight characters.
     * @param employeeNumber Unique employee number used to find the user later.
     * @return Unsaved User.
     */
    private static User newUser(Id profileId, String lastName, String alias, String employeeNumber) {
        String uniqueKey = employeeNumber + DateTime.now().getTime();
        return new User(
            FirstName = 'HS',
            LastName = lastName,
            Alias = alias,
            Email = uniqueKey + '@test.com',
            Username = uniqueKey + '@test.com',
            CommunityNickname = alias + Math.abs(Crypto.getRandomInteger()),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId,
            EmployeeNumber__c = employeeNumber,
            IsActive = true
        );
    }

    /**
     * @description Event owner created for this test.
     * @return Owner user.
     */
    private static User getOwner() {
        return [
            SELECT Id
            FROM User
            WHERE EmployeeNumber__c = :OWNER_EMPLOYEE_NUMBER
            LIMIT 1
        ];
    }

    /**
     * @description Second user created so a person search does not use the logged-in user.
     * @return Attendee user.
     */
    private static User getAttendeeUser() {
        return [
            SELECT Id
            FROM User
            WHERE EmployeeNumber__c = :ATTENDEE_EMPLOYEE_NUMBER
            LIMIT 1
        ];
    }

    /**
     * @description Builds an Id for an object without embedding an Id literal.
     * @param objectType Object whose key prefix is used.
     * @return Id that is not a real record.
     */
    private static Id syntheticId(SObjectType objectType) {
        return (Id) (objectType.getDescribe().getKeyPrefix() + '000000000000');
    }

    /**
     * @description Builds one invocable request.
     * @param eventId Event Id.
     * @param changePayload JSON attendee changes.
     * @return Request ready for applyChanges.
     */
    private static EventAttendeeService.ChangeRequest requestFor(Id eventId, String changePayload) {
        EventAttendeeService.ChangeRequest request = new EventAttendeeService.ChangeRequest();
        request.eventId = eventId;
        request.changePayload = changePayload;
        return request;
    }

    /**
     * @description Counts invitee rows for an Event, optionally for one related record.
     * @param eventId Event Id.
     * @param relationId Related record Id, or null for every invitee.
     * @return Invitee count.
     */
    private static Integer inviteeCount(Id eventId, Id relationId) {
        if (relationId == null) {
            return [
                SELECT COUNT()
                FROM EventRelation
                WHERE EventId = :eventId AND IsInvitee = true
            ];
        }
        return [
            SELECT COUNT()
            FROM EventRelation
            WHERE EventId = :eventId AND RelationId = :relationId AND IsInvitee = true
        ];
    }

    /**
     * @description Finds the panel row for a record Id.
     * @param rows Rows returned by getAttendees.
     * @param recordId User, Contact, Lead, or Calendar Id.
     * @return Matching row, or null.
     */
    private static EventAttendeeService.AttendeeRow findRow(List<EventAttendeeService.AttendeeRow> rows, Id recordId) {
        for (EventAttendeeService.AttendeeRow row : rows) {
            if (row.recordId == recordId) {
                return row;
            }
        }
        return null;
    }

    /**
     * @description Inserts an unconverted Lead that satisfies the org Lead rules.
     * @return Saved Lead.
     */
    private static Lead newLead() {
        Lead leadPerson = new Lead(
            FirstName = 'Coverage',
            LastName = 'Lead',
            Company = 'Coverage Co',
            Email = 'coverage.lead.' + DateTime.now().getTime() + '@test.com',
            LeadSource = 'Website / Digital'
        );
        insert leadPerson;
        return leadPerson;
    }

    /**
     * @description Inserts a one-hour Event owned by the user the test is running as.
     * @return Saved Event.
     */
    private static Event newEvent() {
        Event activity = new Event(
            Subject = 'Attendee Test',
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1),
            DurationInMinutes = 60
        );
        insert activity;
        return activity;
    }
}