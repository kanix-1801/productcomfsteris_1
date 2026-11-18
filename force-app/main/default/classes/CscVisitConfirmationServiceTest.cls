/**
 * @author Divya Sree
 * @date 14-10-2026
 * @description #GC-3563 AC1 Tests confirmation email recipients and the calendar event.
 */
@IsTest(SeeAllData=false)
private class CscVisitConfirmationServiceTest {
    private static final String LOCATION = 'Customer Solution Center (Mentor, OH)';
    private static final String ATTENDEE_LAST_NAME = 'CSCConfirmAttendee';
    private static final String ADDED_LAST_NAME = 'CSCConfirmAdded';

    /**
     * @description Turns off unrelated visit validation and creates the account team user.
     */
    @TestSetup
    static void setup() {
        insert new Automation_Setting_Validation_Rule__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            disableAll__c = true
        );

        User attendee = buildUser('CSC', ATTENDEE_LAST_NAME);
        User addedLater = buildUser('CSC', ADDED_LAST_NAME);
        insert new List<User>{ attendee, addedLater };

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Account facility = new Account(
                Name = 'CSC Confirm Facility',
                SourceSystemID__c = 'CSC3563' + String.valueOf(DateTime.now().getTime())
            );
            insert facility;
            insert new AccountTeamMember(
                AccountId = facility.Id,
                UserId = attendee.Id,
                TeamMemberRole = activeTeamRole(),
                AccountAccessLevel = 'Edit',
                OpportunityAccessLevel = 'Edit',
                CaseAccessLevel = 'Read',
                ContactAccessLevel = 'Read',
                AssignmentType__c = activeAssignmentType()
            );
            Opportunity visitOpportunity = new Opportunity(
                Name = 'CSC Confirm Opportunity',
                AccountId = facility.Id,
                StageName = 'Discovery',
                CloseDate = Date.today().addDays(30),
                Pricebook2Id = Test.getStandardPricebookId()
            );
            Schema.RecordTypeInfo healthcareRecordType = Schema.SObjectType.Opportunity
                .getRecordTypeInfosByDeveloperName()
                .get('Healthcare_Sales');
            if (healthcareRecordType != null) {
                visitOpportunity.RecordTypeId = healthcareRecordType.getRecordTypeId();
            }
            insert visitOpportunity;
        }
    }

    /**
     * @description Confirming a visit emails the account team and attendee once
     *              and creates an all-day event for that attendee.
     */
    @IsTest
    static void confirmationSendsOneEmailAndCreatesEvent() {
        User attendee = attendeeUser();
        CSC_Visit_Request__c visit = insertRequestedVisit(attendee.Id);
        Date confirmedDate = Date.today().addDays(10);

        Test.startTest();
        visit.Status__c = CscVisitConfirmationService.STATUS_CONFIRMED;
        visit.Confirmed_Date__c = confirmedDate;
        update visit;
        Test.stopTest();

        Event calendarEvent = [
            SELECT Subject, ActivityDate, IsAllDayEvent, DurationInMinutes, WhatId, OwnerId, Description
            FROM Event
            WHERE WhatId = :visit.Id
        ];
        System.assertEquals(confirmedDate, calendarEvent.ActivityDate);
        System.assertEquals(true, calendarEvent.IsAllDayEvent);
        System.assertEquals(1440, calendarEvent.DurationInMinutes);
        System.assertEquals(UserInfo.getUserId(), calendarEvent.OwnerId);
        System.assert(calendarEvent.Subject.contains('CSC Confirm Facility'));
        System.assert(calendarEvent.Description.contains('Product Evaluation'));

        List<EventRelation> invitees = [
            SELECT RelationId
            FROM EventRelation
            WHERE EventId = :calendarEvent.Id
              AND IsInvitee = true
              AND RelationId = :attendee.Id
        ];
        System.assertEquals(1, invitees.size(), 'STERIS attendee should receive the calendar invite');

        Set<String> recipients = new Set<String>();
        for (String email : CscVisitConfirmationService.lastEmailsSent) {
            recipients.add(email.toLowerCase());
        }
        System.assertEquals(
            CscVisitConfirmationService.lastEmailsSent.size(),
            recipients.size(),
            'Each confirmation address is used once'
        );
        System.assert(recipients.contains(attendee.Email.toLowerCase()));
    }

    /**
     * @description #GC-3650 A Salesforce Assigned account team member and that
     *              member's manager both receive the confirmation email.
     */
    @IsTest
    static void salesforceAssignedMemberAndManagerReceiveConfirmation() {
        User manager = buildUser('CSC', 'GC3650Manager');
        insert manager;
        User member = buildUser('CSC', 'GC3650Member');
        member.ManagerId = manager.Id;
        insert member;

        Account facility = [SELECT Id FROM Account WHERE Name = 'CSC Confirm Facility' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new AccountTeamMember(
                AccountId = facility.Id,
                UserId = member.Id,
                TeamMemberRole = activeTeamRole(),
                AccountAccessLevel = 'Edit',
                OpportunityAccessLevel = 'Edit',
                CaseAccessLevel = 'Read',
                ContactAccessLevel = 'Read',
                AssignmentType__c = 'Salesforce Assigned'
            );
        }

        CscVisitConfirmationService.lastEmailsSent.clear();
        Test.startTest();
        confirmVisit(attendeeUser().Id);
        Test.stopTest();

        Set<String> recipients = new Set<String>();
        for (String email : CscVisitConfirmationService.lastEmailsSent) {
            recipients.add(email.toLowerCase());
        }
        System.assert(
            recipients.contains(member.Email.toLowerCase()),
            'Salesforce Assigned account team member is included.'
        );
        System.assert(
            recipients.contains(manager.Email.toLowerCase()),
            'Manager of a Salesforce Assigned account team member is included.'
        );
    }

    /**
     * @description A requested visit does not send a calendar invite.
     */
    @IsTest
    static void requestedVisitDoesNotCreateEvent() {
        CSC_Visit_Request__c visit = insertRequestedVisit(attendeeUser().Id);

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Event WHERE WhatId = :visit.Id],
            'Calendar invite waits until the visit is Confirmed'
        );
        System.assertEquals(0, CscVisitConfirmationService.lastEmailsSent.size());
    }

    /**
     * @description Editing a confirmed visit does not send a second email or event.
     */
    @IsTest
    static void laterEditDoesNotSendAnotherEmail() {
        CSC_Visit_Request__c visit = confirmVisit(attendeeUser().Id);
        Integer emailsAfterConfirm = CscVisitConfirmationService.lastEmailsSent.size();

        Test.startTest();
        visit.PrimaryObjective__c = 'Updated objective after confirmation';
        update visit;
        Test.stopTest();

        System.assertEquals(emailsAfterConfirm, CscVisitConfirmationService.lastEmailsSent.size());
        System.assertEquals(1, [SELECT COUNT() FROM Event WHERE WhatId = :visit.Id]);
    }

    /**
     * @description Moving the confirmed date updates the event and does not email again.
     */
    @IsTest
    static void confirmedDateChangeUpdatesEventOnly() {
        CSC_Visit_Request__c visit = confirmVisit(attendeeUser().Id);
        Integer emailsAfterConfirm = CscVisitConfirmationService.lastEmailsSent.size();
        Date movedDate = Date.today().addDays(12);

        Test.startTest();
        visit.Confirmed_Date__c = movedDate;
        visit.Primary_Requested_Date__c = movedDate;
        update visit;
        Test.stopTest();

        Event calendarEvent = [SELECT ActivityDate FROM Event WHERE WhatId = :visit.Id];
        System.assertEquals(movedDate, calendarEvent.ActivityDate);
        System.assertEquals(emailsAfterConfirm, CscVisitConfirmationService.lastEmailsSent.size());
    }

    /**
     * @description An attendee added after confirmation is invited on the existing event.
     */
    @IsTest
    static void attendeeAddedAfterConfirmationIsInvited() {
        User attendee = attendeeUser();
        User addedLater = addedUser();
        CSC_Visit_Request__c visit = confirmVisit(attendee.Id);
        Integer emailsAfterConfirm = CscVisitConfirmationService.lastEmailsSent.size();

        Test.startTest();
        CSCVisitAttendee__c addedAttendee = new CSCVisitAttendee__c(
            CSCVisit__c = visit.Id,
            STERISAttendee__c = addedLater.Id
        );
        insert addedAttendee;
        addedAttendee.STERISAttendee__c = addedLater.Id;
        update addedAttendee;
        Test.stopTest();

        Id calendarEventId = [SELECT Id FROM Event WHERE WhatId = :visit.Id LIMIT 1].Id;
        List<EventRelation> invitees = [
            SELECT RelationId
            FROM EventRelation
            WHERE EventId = :calendarEventId
              AND IsInvitee = true
              AND RelationId = :addedLater.Id
        ];
        System.assertEquals(1, invitees.size());
        System.assertEquals(emailsAfterConfirm, CscVisitConfirmationService.lastEmailsSent.size());

        delete addedAttendee;
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM EventRelation
                WHERE EventId = :calendarEventId
                  AND IsInvitee = true
                  AND RelationId = :addedLater.Id
            ]
        );
    }

    /**
     * @description A confirmed visit with no account or attendees still saves.
     *              GC-3302 availability tests insert this shape of record.
     */
    @IsTest
    static void confirmedVisitWithoutStakeholdersStillSaves() {
        Date confirmedDate = Date.today().addDays(3);
        Test.startTest();
        Id visitOpportunityId = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'CSC Confirm Opportunity'
            LIMIT 1
        ].Id;
        CSC_Visit_Request__c visit = new CSC_Visit_Request__c(
            Opportunity__c = visitOpportunityId,
            VisitLocation__c = LOCATION,
            Status__c = CscVisitConfirmationService.STATUS_CONFIRMED,
            Primary_Requested_Date__c = confirmedDate,
            Backup_Requested_Date__c = Date.today().addDays(4),
            Confirmed_Date__c = confirmedDate
        );
        insert visit;
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Event WHERE WhatId = :visit.Id AND IsChild = false]);
    }

    /**
     * @description One Day is the active agenda value and blocks one calendar day.
     *              Two Day is not an active Visit Agenda / Duration value.
     */
    @IsTest
    static void oneDayAgendaUsesOneCalendarDay() {
        User attendee = attendeeUser();
        CSC_Visit_Request__c visit = insertRequestedVisit(attendee.Id);
        visit.VisitAgendaDuration__c = 'One Day';
        update visit;

        visit.Status__c = CscVisitConfirmationService.STATUS_CONFIRMED;
        visit.Confirmed_Date__c = Date.today().addDays(10);
        update visit;

        Event calendarEvent = [
            SELECT DurationInMinutes
            FROM Event
            WHERE WhatId = :visit.Id
              AND IsChild = false
        ];
        System.assertEquals(1440, calendarEvent.DurationInMinutes);
    }

    /**
     * @description AC2. Cancelling a confirmed visit emails the stakeholders and deletes the calendar event.
     */
    @IsTest
    static void cancellationEmailsStakeholdersAndRemovesEvent() {
        User attendee = attendeeUser();
        CSC_Visit_Request__c visit = confirmVisit(attendee.Id);
        Integer emailsAfterConfirm = CscVisitConfirmationService.lastEmailsSent.size();

        Test.startTest();
        visit.Status__c = CscVisitConfirmationService.STATUS_CANCELLED;
        update visit;
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Event WHERE WhatId = :visit.Id]);
        System.assert(
            CscVisitConfirmationService.lastEmailsSent.size() > emailsAfterConfirm,
            'Cancellation should email the requester, account team, and attendee'
        );
    }

    /**
     * @description Postponement is owned by the calendar story. This story does not
     *              email stakeholders or change the calendar event.
     */
    @IsTest
    static void postponementDoesNotNotifyOrChangeTheEvent() {
        CSC_Visit_Request__c visit = confirmVisit(attendeeUser().Id);
        Integer emailsAfterConfirm = CscVisitConfirmationService.lastEmailsSent.size();

        Test.startTest();
        visit.Status__c = CscVisitConfirmationService.STATUS_POSTPONED;
        update visit;
        Test.stopTest();

        Event calendarEvent = [SELECT Subject FROM Event WHERE WhatId = :visit.Id AND IsChild = false];
        System.assert(!calendarEvent.Subject.contains('Postponed'));
        System.assertEquals(emailsAfterConfirm, CscVisitConfirmationService.lastEmailsSent.size());
    }

    /**
     * @description AC2 applies only when the prior status is Requested or Confirmed.
     */
    @IsTest
    static void draftCancellationDoesNotNotify() {
        CSC_Visit_Request__c visit = insertRequestedVisit(attendeeUser().Id);
        visit.Status__c = CscVisitConfirmationService.STATUS_REQUESTED;
        update visit;
        visit.Status__c = 'Draft';
        update visit;
        CscVisitConfirmationService.lastEmailsSent.clear();

        visit.Status__c = CscVisitConfirmationService.STATUS_CANCELLED;
        update visit;

        System.assertEquals(0, CscVisitConfirmationService.lastEmailsSent.size());
    }

    /**
     * @description AC5. The VR/AR team is emailed once, at Approved, and not again at Confirmed.
     */
    @IsTest
    static void vrArApprovalEmailsConfiguredPlanningTeamOnce() {
        CscVisitConfirmationService.vrArTeamEmailsOverride = 'vrar-team@example.com';
        CSC_Visit_Request__c visit = insertRequestedVisit(attendeeUser().Id);
        visit.PlanningSessionType__c = CscVisitConfirmationService.SESSION_VR;
        visit.Confirmed_Date__c = visit.Primary_Requested_Date__c;
        visit.Status__c = CscVisitConfirmationService.STATUS_APPROVED;
        update visit;

        Integer vrEmails = 0;
        for (String email : CscVisitConfirmationService.lastEmailsSent) {
            if (email == 'vrar-team@example.com') {
                vrEmails++;
            }
        }
        System.assertEquals(1, vrEmails);

        visit.Status__c = CscVisitConfirmationService.STATUS_CONFIRMED;
        visit.Confirmed_Date__c = visit.Primary_Requested_Date__c;
        update visit;

        vrEmails = 0;
        for (String email : CscVisitConfirmationService.lastEmailsSent) {
            if (email == 'vrar-team@example.com') {
                vrEmails++;
            }
        }
        System.assertEquals(1, vrEmails);
    }

    /**
     * @description The visit trigger adds the requestor as a STERIS attendee,
     *              and the attendee trigger syncs that attendee onto the confirmed event.
     */
    @IsTest
    static void requestorBecomesAttendee() {
        CSC_Visit_Request__c visit = confirmVisit(attendeeUser().Id);
        Id requestorId = UserInfo.getUserId();

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM CSCVisitAttendee__c
                WHERE CSCVisit__c = :visit.Id
                  AND STERISAttendee__c = :requestorId
            ]
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Event WHERE WhatId = :visit.Id AND IsChild = false]
        );

        CscVisitAttendeeService.syncAttendees(null);
        CscVisitAttendeeService.syncAttendees(new Set<Id>());
        CscVisitAttendeeService.handleAfterSave(null, null);
        CscVisitAttendeeService.addDefaultRequestors(new List<CSC_Visit_Request__c>());
        CscVisitAttendeeService.addDefaultRequestors(
            new List<CSC_Visit_Request__c>{
                new CSC_Visit_Request__c(VisitRequestor__c = requestorId)
            }
        );
    }

    /**
     * @description Covers the visit status emails and the extra confirmation recipients.
     */
    @IsTest
    static void emailServiceCoversStatusAndConfirmationRecipients() {
        String stamp = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User orcUser = buildUser('CSC', 'ORC' + stamp);
        User imsUser = buildUser('CSC', 'IMS' + stamp);
        User osvUser = buildUser('CSC', 'OSV' + stamp);
        User pdmUser = buildUser('CSC', 'PDM' + stamp);
        insert new List<User>{ orcUser, imsUser, osvUser, pdmUser };

        Account facility = [SELECT Id FROM Account WHERE Name = 'CSC Confirm Facility' LIMIT 1];
        List<CSC_Visit_Request__c> visits = new List<CSC_Visit_Request__c>{
            nonCscVisit(facility.Id, CscVisitRequestSelector.REQUEST_ORC),
            nonCscVisit(facility.Id, CscVisitRequestSelector.REQUEST_IMS),
            nonCscVisit(facility.Id, CscVisitRequestSelector.REQUEST_OSV),
            new CSC_Visit_Request__c(
                AccountFacility__c = facility.Id,
                VisitType__c = CscVisitRequestSelector.REQUEST_CSC,
                Status__c = CscVisitRequestSelector.STATUS_APPROVED,
                PlanningDesignRequired__c = 'No',
                VisitLocation__c = LOCATION,
                Primary_Requested_Date__c = Date.today().addDays(10),
                Backup_Requested_Date__c = Date.today().addDays(11),
                Visit_Purpose__c = 'Product Evaluation',
                PrimaryObjective__c = 'Review the installed equipment',
                VisitAgendaDuration__c = 'One Day',
                VisitRequestor__c = UserInfo.getUserId()
            )
        };
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Account pdmAccount = new Account(
                Name = 'CSC PDM Account ' + stamp,
                SourceSystemID__c = 'CSC3650' + stamp
            );
            insert pdmAccount;
            Opportunity pdmOpportunity = new Opportunity(
                Name = 'CSC PDM Opportunity ' + stamp,
                AccountId = pdmAccount.Id,
                StageName = 'Discovery',
                CloseDate = Date.today().addDays(30),
                Pricebook2Id = Test.getStandardPricebookId()
            );
            Schema.RecordTypeInfo healthcareRecordType = Schema.SObjectType.Opportunity
                .getRecordTypeInfosByDeveloperName()
                .get('Healthcare_Sales');
            if (healthcareRecordType != null) {
                pdmOpportunity.RecordTypeId = healthcareRecordType.getRecordTypeId();
            }
            insert pdmOpportunity;
            visits[3].Opportunity__c = pdmOpportunity.Id;
            insert visits;
            insert new List<TeamMember__c>{
                teamMember(visits[0].Id, orcUser.Id),
                teamMember(visits[1].Id, imsUser.Id),
                teamMember(visits[2].Id, osvUser.Id)
            };
            insert new AccountTeamMember(
                AccountId = pdmAccount.Id,
                UserId = pdmUser.Id,
                TeamMemberRole = activeTeamRole(),
                AccountAccessLevel = 'Edit',
                OpportunityAccessLevel = 'Edit',
                CaseAccessLevel = 'Read',
                ContactAccessLevel = 'Read',
                AssignmentType__c = 'Salesforce Assigned',
                TerritoryCode__c = Label.CSC_PDM_Territory_Code,
                SalesCategoryCode__c = 'SURG SPT'
            );
        }

        CscVisitEmailService.lastTeamRecipientIds.clear();
        Test.startTest();
        CscVisitEmailService.notifyAfterSave(null, null);
        CscVisitEmailService.notifyAfterSave(new List<CSC_Visit_Request__c>(), null);
        CscVisitEmailService.notifyAfterSave(new List<CSC_Visit_Request__c>{ null }, null);
        CscVisitEmailService.notifyAfterSave(
            changedVisits(visits, CscVisitRequestSelector.STATUS_REQUESTED, 'No'),
            priorVisits(visits, CscVisitRequestSelector.STATUS_DRAFT, 'No')
        );

        CscVisitEmailService.notifyAfterSave(
            changedVisits(visits, CscVisitRequestSelector.STATUS_POSTPONED, 'No'),
            priorVisits(visits, CscVisitRequestSelector.STATUS_REQUESTED, 'No')
        );
        CscVisitEmailService.notifyAfterSave(
            changedVisits(visits, CscVisitRequestSelector.STATUS_CANCELLED, 'No'),
            priorVisits(visits, CscVisitRequestSelector.STATUS_REQUESTED, 'No')
        );

        Schema.RecordTypeInfo blockType = Schema.SObjectType.CSC_Visit_Request__c
            .getRecordTypeInfosByDeveloperName()
            .get(CscVisitRequestSelector.RECORD_TYPE_BLOCK);
        if (blockType != null) {
            CSC_Visit_Request__c blocked = visits[0].clone(true, true, true, true);
            blocked.RecordTypeId = blockType.getRecordTypeId();
            blocked.Status__c = CscVisitRequestSelector.STATUS_REQUESTED;
            CscVisitEmailService.notifyAfterSave(
                new List<CSC_Visit_Request__c>{ blocked },
                priorVisits(new List<CSC_Visit_Request__c>{ visits[0] }, CscVisitRequestSelector.STATUS_DRAFT, 'No')
            );
        }

        CscVisitEmailService.notifyAfterSave(
            changedVisits(
                new List<CSC_Visit_Request__c>{ visits[3] },
                CscVisitRequestSelector.STATUS_CONFIRMED,
                'Yes'
            ),
            priorVisits(
                new List<CSC_Visit_Request__c>{ visits[3] },
                CscVisitRequestSelector.STATUS_APPROVED,
                'No'
            )
        );

        CSC_Visit_Request__c confirmed = visits[3].clone(true, true, true, true);
        confirmed.Status__c = CscVisitRequestSelector.STATUS_CONFIRMED;
        confirmed.PlanningDesignRequired__c = 'No';
        CSC_Visit_Request__c planningOn = confirmed.clone(true, true, true, true);
        planningOn.PlanningDesignRequired__c = 'Yes';
        CscVisitEmailService.notifyAfterSave(
            new List<CSC_Visit_Request__c>{ planningOn },
            new Map<Id, CSC_Visit_Request__c>{ visits[3].Id => confirmed }
        );
        System.assert(
            new Set<Id>(CscVisitEmailService.lastTeamRecipientIds).contains(orcUser.Id),
            'ORC team member receives the requested notice.'
        );
        CscVisitEmailService.additionalConfirmationRecipients(null, null, null);
        CscVisitEmailService.additionalConfirmationRecipients(
            new List<CSC_Visit_Request__c>(),
            null,
            null
        );
        Test.stopTest();
    }

    /**
     * @description Inserts a requested visit with one STERIS attendee.
     * @param attendeeUserId STERIS attendee user Id.
     * @return CSC_Visit_Request__c requested visit.
     */
    private static CSC_Visit_Request__c insertRequestedVisit(Id attendeeUserId) {
        Account facility = [SELECT Id FROM Account WHERE Name = 'CSC Confirm Facility' LIMIT 1];
        Opportunity visitOpportunity = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'CSC Confirm Opportunity'
            LIMIT 1
        ];
        CSC_Visit_Request__c visit = new CSC_Visit_Request__c(
            AccountFacility__c = facility.Id,
            Opportunity__c = visitOpportunity.Id,
            VisitLocation__c = LOCATION,
            Status__c = 'Requested',
            Primary_Requested_Date__c = Date.today().addDays(10),
            Backup_Requested_Date__c = Date.today().addDays(11),
            Visit_Purpose__c = 'Product Evaluation',
            PrimaryObjective__c = 'Review the installed equipment',
            VisitAgendaDuration__c = 'One Day',
            VisitRequestor__c = UserInfo.getUserId()
        );
        insert visit;
        insert new CSCVisitAttendee__c(
            CSCVisit__c = visit.Id,
            STERISAttendee__c = attendeeUserId
        );
        return visit;
    }

    /**
     * @description Confirms a requested visit on its primary date.
     * @param attendeeUserId STERIS attendee user Id.
     * @return CSC_Visit_Request__c confirmed visit.
     */
    private static CSC_Visit_Request__c confirmVisit(Id attendeeUserId) {
        CSC_Visit_Request__c visit = insertRequestedVisit(attendeeUserId);
        visit.Status__c = CscVisitConfirmationService.STATUS_CONFIRMED;
        visit.Confirmed_Date__c = visit.Primary_Requested_Date__c;
        update visit;
        return visit;
    }

    /**
     * @description Account team user who is also the initial STERIS attendee.
     * @return User attendee user.
     */
    private static User attendeeUser() {
        return [SELECT Id, Email FROM User WHERE LastName = :ATTENDEE_LAST_NAME LIMIT 1];
    }

    /**
     * @description User added to the visit after confirmation.
     * @return User additional attendee.
     */
    private static User addedUser() {
        return [SELECT Id, Email FROM User WHERE LastName = :ADDED_LAST_NAME LIMIT 1];
    }

    /**
     * @description Builds a unique active user.
     * @param firstName User first name.
     * @param lastName User last name.
     * @return User unsaved user.
     */
    private static User buildUser(String firstName, String lastName) {
        String token = lastName + String.valueOf(DateTime.now().getTime());
        return new User(
            FirstName = firstName,
            LastName = lastName,
            Email = token + '@example.com',
            Username = token + '@example.com',
            Alias = (lastName.right(3) + String.valueOf(Math.mod(Crypto.getRandomInteger(), 100000))).left(8),
            CommunityNickname = token.left(40),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = UserInfo.getProfileId()
        );
    }

    /**
     * @description First active Account Team role.
     * @return String role value.
     */
    private static String activeTeamRole() {
        for (Schema.PicklistEntry entry : AccountTeamMember.TeamMemberRole.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return 'Sales Rep';
    }

    /**
     * @description First active assignment type.
     * @return String assignment type value.
     */
    private static String activeAssignmentType() {
        for (Schema.PicklistEntry entry : AccountTeamMember.AssignmentType__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static CSC_Visit_Request__c nonCscVisit(Id facilityId, String visitType) {
        return new CSC_Visit_Request__c(
            AccountFacility__c = facilityId,
            VisitType__c = visitType,
            Status__c = CscVisitRequestSelector.STATUS_DRAFT,
            VisitLocation__c = LOCATION,
            Primary_Requested_Date__c = Date.today().addDays(10),
            Backup_Requested_Date__c = Date.today().addDays(11),
            Visit_Purpose__c = 'Product Evaluation',
            PrimaryObjective__c = 'Review the installed equipment',
            VisitAgendaDuration__c = 'One Day',
            VisitRequestor__c = UserInfo.getUserId()
        );
    }

    private static TeamMember__c teamMember(Id visitId, Id userId) {
        return new TeamMember__c(
            CSCVisitRequest__c = visitId,
            User__c = userId,
            AccessLevel__c = 'Read'
        );
    }

    private static List<CSC_Visit_Request__c> changedVisits(
        List<CSC_Visit_Request__c> visits,
        String status,
        String planning
    ) {
        List<CSC_Visit_Request__c> changed = new List<CSC_Visit_Request__c>();
        for (CSC_Visit_Request__c visit : visits) {
            CSC_Visit_Request__c currentVisit = visit.clone(true, true, true, true);
            currentVisit.Status__c = status;
            currentVisit.PlanningDesignRequired__c = planning;
            if (status == CscVisitRequestSelector.STATUS_CONFIRMED) {
                currentVisit.Confirmed_Date__c = Date.today().addDays(10);
            }
            changed.add(currentVisit);
        }
        return changed;
    }

    private static Map<Id, CSC_Visit_Request__c> priorVisits(
        List<CSC_Visit_Request__c> visits,
        String status,
        String planning
    ) {
        Map<Id, CSC_Visit_Request__c> prior = new Map<Id, CSC_Visit_Request__c>();
        for (CSC_Visit_Request__c visit : visits) {
            CSC_Visit_Request__c previousVisit = visit.clone(true, true, true, true);
            previousVisit.Status__c = status;
            previousVisit.PlanningDesignRequired__c = planning;
            prior.put(visit.Id, previousVisit);
        }
        return prior;
    }
}