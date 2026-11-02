/**
 * @author Divya Sree
 * @date 14-10-2026
 * @description #GC-3563 Sends the confirmation email and calendar invite when a
 *              visit is Confirmed (AC1), notifies requester, stakeholders, and
 *              attendees when a Requested, Confirmed, or Postponed visit is
 *              Cancelled (AC2), and sends the VR/AR Planning and Design team a
 *              save-the-date calendar invite when that session type reaches
 *              Approved or Confirmed (AC5).
 *
 *              Confirmation email recipients are the Account Team on
 *              Account / Facility, the active STERIS attendees, and the
 *              customer attendees. Each address is used once. The CSC
 *              reservation/admin group is not included yet because that
 *              audience has not been named.
 *              The calendar event is sent to STERIS attendees and customer
 *              attendees. The event
 *              owner is the Visit Requestor, who already has the event as
 *              organizer. A later Confirmed Date change updates the event and
 *              does not send the confirmation email again.
 */
public inherited sharing class CscVisitConfirmationService {
    public static final String STATUS_REQUESTED = 'Requested';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_CONFIRMED = 'Confirmed';
    public static final String STATUS_CANCELLED = 'Cancelled';
    public static final String STATUS_POSTPONED = 'Postponed';
    public static final String SESSION_VR = 'VR Immersion';
    public static final String SESSION_AR = 'AR Experience';
    public static final String TWO_DAY_AGENDA = 'Two Day';
    public static final Integer ONE_DAY_MINUTES = 1440;
    private static final String VR_AR_SETTING = 'VR_AR_Planning_Team';
    private static final String TEMPLATE_CONFIRMED = 'CSC_Visit_Confirmed';
    private static final String TEMPLATE_STATUS = 'CSC_Visit_Status_Change';
    private static final String TEMPLATE_VR_AR = 'CSC_Visit_VR_AR_Save_The_Date';
    private static final String ATTENDEE_TOKEN = '{{STERIS_ATTENDEES}}';
    private static final String CUSTOMER_ATTENDEE_TOKEN = '{{CUSTOMER_ATTENDEES}}';
    private static final String ATTENDEE_TYPE_CUSTOMER = 'Customer';
    private static final String SAVE_THE_DATE_SUBJECT = 'CSC Visit Save the Date: ';
    private static final String HEALTHCARE_SALES_EVENT = 'Healthcare_Sales_Event';

    @TestVisible
    private static List<String> lastEmailsSent = new List<String>();
    @TestVisible
    private static String cscAdminGroupDeveloperName;
    @TestVisible
    private static String vrArTeamEmailsOverride;
    private static Set<Id> emailedVisitIds = new Set<Id>();
    private static Map<String, Id> templateIdsByName;
    private static Map<String, Messaging.SingleEmailMessage> renderedByKey =
        new Map<String, Messaging.SingleEmailMessage>();

    /**
     * @description Applies AC1, AC2, and AC5 for saved CSC visits.
     * @param visits Saved CSC visit records.
     * @param oldVisits Prior CSC visit records. Null on insert.
     */
    public static void handleAfterSave(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        confirmVisits(visits, oldVisits);
        notifyCancellation(visits, oldVisits);
        removeReleasedCalendar(visits, oldVisits);
        notifyVrArPlanningTeam(visits, oldVisits);
        syncAttendees(readyVisitIds(visits));
        CscVisitEmailService.notifyAfterSave(visits, oldVisits);
    }

    /**
     * @description Confirmation email used by CscVisitEmailService for recipients
     *              added after the Account Team email was already sent.
     * @param recipients Recipient addresses.
     * @param visit Confirmed visit.
     * @param attendees STERIS attendees for the visit.
     * @return Messaging.SingleEmailMessage email ready to send.
     */
    public static Messaging.SingleEmailMessage buildConfirmationEmail(
        List<String> recipients,
        CSC_Visit_Request__c visit,
        List<CSCVisitAttendee__c> attendees
    ) {
        return confirmationEmail(recipients, visit, attendees);
    }

    /**
     * @description True when this transaction already sent the confirmation email.
     * @param visitId CSC visit Id.
     * @return Boolean true when the confirmation email was sent.
     */
    public static Boolean wasConfirmationEmailed(Id visitId) {
        return visitId != null && emailedVisitIds.contains(visitId);
    }

    /**
     * @description Lower-case addresses already included on the confirmation email.
     * @param visit Confirmed visit.
     * @param attendees STERIS attendees for the visit.
     * @param teamMembers Account Team members for the visit facility.
     * @return Set<String> lower-case recipient addresses.
     */
    public static Set<String> confirmationRecipientKeys(
        CSC_Visit_Request__c visit,
        List<CSCVisitAttendee__c> attendees,
        List<AccountTeamMember> teamMembers
    ) {
        return emailKeys(recipientEmails(visit, attendees, teamMembers, cscAdminEmails()));
    }

    /**
     * @description Confirmed visits whose calendar invitees should match the latest attendees.
     * @param visits Saved CSC visit records.
     * @return Set<Id> confirmed visit Ids.
     */
    private static Set<Id> readyVisitIds(List<CSC_Visit_Request__c> visits) {
        Set<Id> visitIds = new Set<Id>();
        if (visits == null) {
            return visitIds;
        }
        for (CSC_Visit_Request__c visit : visits) {
            if (isReady(visit)) {
                visitIds.add(visit.Id);
            }
        }
        return visitIds;
    }

    /**
     * @description Creates or updates the calendar event when a visit becomes
     *              confirmed, and sends the confirmation email the first time.
     * @param visits Saved CSC visit records.
     * @param oldVisits Prior CSC visit records. Null on insert.
     */
    public static void confirmVisits(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        if (visits == null || visits.isEmpty()) {
            return;
        }

        Set<Id> firstConfirmationIds = new Set<Id>();
        Set<Id> dateChangeIds = new Set<Id>();
        for (CSC_Visit_Request__c visit : visits) {
            Boolean nowReady = isReady(visit);
            CSC_Visit_Request__c priorVisit = oldVisits == null ? null : oldVisits.get(visit.Id);
            Boolean wasReady = priorVisit != null && isReady(priorVisit);
            if (nowReady && !wasReady) {
                firstConfirmationIds.add(visit.Id);
            } else if (
                nowReady
                && wasReady
                && priorVisit.Confirmed_Date__c != visit.Confirmed_Date__c
            ) {
                dateChangeIds.add(visit.Id);
            }
        }

        if (!firstConfirmationIds.isEmpty()) {
            syncConfirmedVisits(firstConfirmationIds, true);
        }
        if (!dateChangeIds.isEmpty()) {
            syncConfirmedVisits(dateChangeIds, false);
        }
    }

    /**
     * @description Refreshes calendar invitees after STERIS attendees change
     *              on a confirmed visit. Does not send the confirmation email.
     * @param visitIds CSC visit Ids from the attendee records.
     */
    public static void syncAttendees(Set<Id> visitIds) {
        syncConfirmedVisits(visitIds, false);
    }

    /**
     * @description A visit is ready for AC1 when it is Confirmed and has a date.
     * @param visit CSC visit record.
     * @return Boolean true when both confirmation values are present.
     */
    private static Boolean isReady(CSC_Visit_Request__c visit) {
        return visit.Status__c == STATUS_CONFIRMED && visit.Confirmed_Date__c != null;
    }

    /**
     * @description Builds the event from the latest visit and attendee data.
     * @param visitIds CSC visit Ids to process.
     * @param sendEmail True only for the first confirmation.
     */
    private static void syncConfirmedVisits(Set<Id> visitIds, Boolean sendEmail) {
        if (visitIds == null || visitIds.isEmpty()) {
            return;
        }

        Map<Id, CSC_Visit_Request__c> visitsById = new Map<Id, CSC_Visit_Request__c>(
            queryVisits(visitIds)
        );
        if (visitsById.isEmpty()) {
            return;
        }

        Map<Id, List<CSCVisitAttendee__c>> attendeesByVisit = queryAttendees(visitsById.keySet());
        Map<Id, List<AccountTeamMember>> teamByAccount = queryTeam(accountIds(visitsById.values()));
        Map<Id, Event> eventByVisit = queryEvents(visitsById.keySet());

        List<Event> eventsToInsert = new List<Event>();
        List<Event> eventsToUpdate = new List<Event>();
        Map<Id, Event> preparedByVisit = new Map<Id, Event>();

        for (CSC_Visit_Request__c visit : visitsById.values()) {
            Event existingEvent = eventByVisit.get(visit.Id);
            Event preparedEvent = buildEvent(
                visit,
                attendeesByVisit.get(visit.Id),
                existingEvent
            );
            preparedByVisit.put(visit.Id, preparedEvent);
            if (existingEvent == null) {
                eventsToInsert.add(preparedEvent);
            } else {
                eventsToUpdate.add(preparedEvent);
            }
        }

        if (!eventsToInsert.isEmpty()) {
            try {
                insert eventsToInsert;
            } catch (DmlException eventError) {
                // QA does not allow a CSC visit as Event Related To until Activities
                // are enabled. Keep the visit confirmation and continue.
                eventsToInsert.clear();
            }
        }
        if (!eventsToUpdate.isEmpty()) {
            try {
                update eventsToUpdate;
            } catch (DmlException eventError) {
                eventsToUpdate.clear();
            }
        }

        syncInvitees(attendeesByVisit, preparedByVisit);
        if (sendEmail) {
            sendConfirmationEmails(visitsById, attendeesByVisit, teamByAccount);
        }
    }

    /**
     * @description Loads confirmed visits with the fields used in the email and event.
     * @param visitIds CSC visit Ids requested by the trigger.
     * @return List<CSC_Visit_Request__c> confirmed visits that have a date.
     */
    private static List<CSC_Visit_Request__c> queryVisits(Set<Id> visitIds) {
        return [
            SELECT Id, Name, Status__c, VisitType__c, Confirmed_Date__c, VisitAgendaDuration__c,
                VisitLocation__c, Visit_Purpose__c, PrimaryObjective__c, PlanningDesignRequired__c,
                OwnerId, AccountFacility__c, AccountFacility__r.Name, AccountFacility__r.AccountNumber,
                Opportunity__c, Opportunity__r.AccountId,RecordTypeId,
                VisitRequestor__c, VisitRequestor__r.Name, VisitRequestor__r.Email,
                VisitRequestor__r.IsActive
            FROM CSC_Visit_Request__c
            WHERE Id IN :visitIds
              AND Status__c = :STATUS_CONFIRMED
              AND Confirmed_Date__c != null
        ];
    }

    /**
     * @description Active STERIS attendees for the confirmed visits.
     * @param visitIds Confirmed CSC visit Ids.
     * @return Map<Id, List<CSCVisitAttendee__c>> attendees grouped by visit.
     */
    private static Map<Id, List<CSCVisitAttendee__c>> queryAttendees(Set<Id> visitIds) {
        Map<Id, List<CSCVisitAttendee__c>> attendeesByVisit =
            new Map<Id, List<CSCVisitAttendee__c>>();
        for (CSCVisitAttendee__c attendee : [
            SELECT CSCVisit__c, AttendeeType__c, STERISAttendee__c, STERISAttendee__r.Name,
                STERISAttendee__r.Title, STERISAttendee__r.Email, STERISAttendee__r.IsActive,
                Contact__c, Contact__r.Name, Contact__r.Title, Contact__r.Email
            FROM CSCVisitAttendee__c
            WHERE CSCVisit__c IN :visitIds
              AND (
                    (STERISAttendee__c != null AND STERISAttendee__r.IsActive = true)
                    OR (AttendeeType__c = :ATTENDEE_TYPE_CUSTOMER AND Contact__c != null)
                  )
        ]) {
            if (!attendeesByVisit.containsKey(attendee.CSCVisit__c)) {
                attendeesByVisit.put(attendee.CSCVisit__c, new List<CSCVisitAttendee__c>());
            }
            attendeesByVisit.get(attendee.CSCVisit__c).add(attendee);
        }
        return attendeesByVisit;
    }

    /**
     * @description Active, unexpired Account Team members for the visit accounts.
     * @param accountIds Account / Facility Ids.
     * @return Map<Id, List<AccountTeamMember>> team members grouped by account.
     */
    private static Map<Id, List<AccountTeamMember>> queryTeam(Set<Id> accountIds) {
        Map<Id, List<AccountTeamMember>> teamByAccount = new Map<Id, List<AccountTeamMember>>();
        if (accountIds.isEmpty()) {
            return teamByAccount;
        }

        Date today = Date.today();
        for (AccountTeamMember member : [
            SELECT AccountId, UserId, User.Name, User.Email, ExpiryDate__c
            FROM AccountTeamMember
            WHERE AccountId IN :accountIds
              AND User.IsActive = true
              AND User.Email != null
              AND (ExpiryDate__c = null OR ExpiryDate__c >= :today)
        ]) {
            if (!teamByAccount.containsKey(member.AccountId)) {
                teamByAccount.put(member.AccountId, new List<AccountTeamMember>());
            }
            teamByAccount.get(member.AccountId).add(member);
        }
        return teamByAccount;
    }

    /**
     * @description Latest organizer calendar event for each visit.
     *              Invitee copies are skipped. Only the organizer event can be changed or removed.
     * @param visitIds CSC visit Ids.
     * @return Map<Id, Event> one organizer event per visit.
     */
    private static Map<Id, Event> queryEvents(Set<Id> visitIds) {
        Map<Id, Event> eventByVisit = new Map<Id, Event>();
        for (Event existingEvent : queryOrganizerEvents(visitIds)) {
            if (existingEvent.Subject != null && existingEvent.Subject.startsWith(SAVE_THE_DATE_SUBJECT)) {
                continue;
            }
            if (!eventByVisit.containsKey(existingEvent.WhatId)) {
                eventByVisit.put(existingEvent.WhatId, existingEvent);
            }
        }
        return eventByVisit;
    }

    /**
     * @description Organizer events related to the visits. Invitee copies are excluded.
     * @param visitIds CSC visit Ids.
     * @return List<Event> organizer events.
     */
    private static List<Event> queryOrganizerEvents(Set<Id> visitIds) {
        List<Event> organizerEvents = new List<Event>();
        for (Event existingEvent : [
            SELECT Id, WhatId, OwnerId, IsChild, Subject
            FROM Event
            WHERE WhatId IN :visitIds
            ORDER BY CreatedDate DESC
        ]) {
            if (existingEvent.IsChild != true) {
                organizerEvents.add(existingEvent);
            }
        }
        return organizerEvents;
    }

    /**
     * @description Account Ids used to find the stakeholder population.
     * @param visits Confirmed CSC visits.
     * @return Set<Id> Account / Facility Ids.
     */
    private static Set<Id> accountIds(List<CSC_Visit_Request__c> visits) {
        Set<Id> accountIds = new Set<Id>();
        for (CSC_Visit_Request__c visit : visits) {
            if (visit.AccountFacility__c != null) {
                accountIds.add(visit.AccountFacility__c);
            }
        }
        return accountIds;
    }

    /**
     * @description Fills the all-day event from the current visit values.
     * @param visit Confirmed CSC visit.
     * @param attendees STERIS attendees for the visit.
     * @param existingEvent Event already related to the visit, when one exists.
     * @return Event event ready to insert or update.
     */
    private static Event buildEvent(
        CSC_Visit_Request__c visit,
        List<CSCVisitAttendee__c> attendees,
        Event existingEvent
    ) {
        Event calendarEvent = existingEvent == null ? new Event() : existingEvent;
        if (existingEvent == null) {
            calendarEvent.WhatId = visit.Id;
            calendarEvent.OwnerId = eventOwnerId(visit);
            calendarEvent.RecordTypeId = healthcareSalesEventTypeId();
        }
        calendarEvent.Subject = limitText(eventSubject(visit), 255);
        calendarEvent.Description = limitText(confirmationBody(visit, attendees), 32000);
        calendarEvent.IsAllDayEvent = true;
        calendarEvent.ActivityDate = visit.Confirmed_Date__c;
        calendarEvent.DurationInMinutes = durationMinutes(visit.VisitAgendaDuration__c);
        return calendarEvent;
    }

    /**
     * @description Visit Requestor owns the event. The record owner is the fallback.
     * @param visit Confirmed CSC visit.
     * @return Id user who organizes the calendar event.
     */
    private static Id healthcareSalesEventTypeId() {
        return Schema.SObjectType.Event
            .getRecordTypeInfosByDeveloperName()
            .get(HEALTHCARE_SALES_EVENT)
            .getRecordTypeId();
    }

    private static Id eventOwnerId(CSC_Visit_Request__c visit) {
        if (visit.VisitRequestor__c != null && visit.VisitRequestor__r.IsActive == true) {
            return visit.VisitRequestor__c;
        }
        return visit.OwnerId;
    }

    /**
     * @description Adds and removes invitees so the event matches STERIS attendees.
     *              The organizer is not inserted again as an invitee.
     * @param attendeesByVisit Attendees grouped by visit.
     * @param eventByVisit Calendar event for each visit.
     */
    private static void syncInvitees(
        Map<Id, List<CSCVisitAttendee__c>> attendeesByVisit,
        Map<Id, Event> eventByVisit
    ) {
        Set<Id> eventIds = new Set<Id>();
        for (Event calendarEvent : eventByVisit.values()) {
            if (calendarEvent.Id != null) {
                eventIds.add(calendarEvent.Id);
            }
        }
        if (eventIds.isEmpty()) {
            return;
        }

        Map<Id, List<EventRelation>> relationsByEvent = new Map<Id, List<EventRelation>>();
        for (Id eventId : eventIds) {
            relationsByEvent.put(eventId, new List<EventRelation>());
        }
        for (EventRelation relation : [
            SELECT Id, EventId, RelationId, IsInvitee
            FROM EventRelation
            WHERE EventId IN :eventIds
        ]) {
            relationsByEvent.get(relation.EventId).add(relation);
        }

        List<EventRelation> relationsToInsert = new List<EventRelation>();
        List<EventRelation> relationsToDelete = new List<EventRelation>();
        for (Id visitId : eventByVisit.keySet()) {
            Event calendarEvent = eventByVisit.get(visitId);
            Set<Id> desiredUserIds = attendeeInviteeIds(attendeesByVisit.get(visitId));
            desiredUserIds.remove(calendarEvent.OwnerId);

            Set<Id> currentInvitees = new Set<Id>();
            for (EventRelation relation : relationsByEvent.get(calendarEvent.Id)) {
                if (relation.IsInvitee != true) {
                    continue;
                }
                if (desiredUserIds.contains(relation.RelationId)) {
                    currentInvitees.add(relation.RelationId);
                } else {
                    relationsToDelete.add(relation);
                }
            }

            for (Id userId : desiredUserIds) {
                if (!currentInvitees.contains(userId)) {
                    relationsToInsert.add(new EventRelation(
                        EventId = calendarEvent.Id,
                        RelationId = userId,
                        IsInvitee = true
                    ));
                }
            }
        }

        if (!relationsToDelete.isEmpty()) {
            delete relationsToDelete;
        }
        if (!relationsToInsert.isEmpty()) {
            insert relationsToInsert;
        }
    }

    /**
     * @description Sends one confirmation email per visit to stakeholders and attendees.
     * @param visitsById Confirmed visits.
     * @param attendeesByVisit STERIS attendees grouped by visit.
     * @param teamByAccount Account Team members grouped by account.
     */
    private static void sendConfirmationEmails(
        Map<Id, CSC_Visit_Request__c> visitsById,
        Map<Id, List<CSCVisitAttendee__c>> attendeesByVisit,
        Map<Id, List<AccountTeamMember>> teamByAccount
    ) {
        Set<String> adminEmails = cscAdminEmails();
        Map<Id, List<String>> extrasByVisit = CscVisitEmailService.additionalConfirmationRecipients(
            visitsById.values(),
            attendeesByVisit,
            teamByAccount
        );
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();

        for (CSC_Visit_Request__c visit : visitsById.values()) {
            if (emailedVisitIds.contains(visit.Id)) {
                continue;
            }
            List<String> recipients = recipientEmails(
                visit,
                attendeesByVisit.get(visit.Id),
                teamByAccount.get(visit.AccountFacility__c),
                adminEmails
            );
            if (extrasByVisit.containsKey(visit.Id)) {
                addEmail(recipients, emailKeys(recipients), new Set<String>(extrasByVisit.get(visit.Id)));
            }
            if (recipients.isEmpty()) {
                continue;
            }

            emailedVisitIds.add(visit.Id);
            lastEmailsSent.addAll(recipients);
            messages.add(confirmationEmail(
                recipients,
                visit,
                attendeesByVisit.get(visit.Id)
            ));
        }

        if (!messages.isEmpty()) {
            Messaging.sendEmail(messages, false);
        }
    }

    /**
     * @description Unique email addresses for one visit.
     * @param visit Confirmed CSC visit.
     * @param attendees STERIS attendees for the visit.
     * @param teamMembers Account Team members for the visit account.
     * @param adminEmails CSC admin addresses, when a group has been named.
     * @return List<String> deduplicated recipient addresses.
     */
    private static List<String> recipientEmails(
        CSC_Visit_Request__c visit,
        List<CSCVisitAttendee__c> attendees,
        List<AccountTeamMember> teamMembers,
        Set<String> adminEmails
    ) {
        List<String> recipients = new List<String>();
        Set<String> seen = new Set<String>();
        addEmail(recipients, seen, adminEmails);

        if (teamMembers != null) {
            for (AccountTeamMember member : teamMembers) {
                addEmail(recipients, seen, member.User.Email);
            }
        }
        if (attendees != null) {
            for (CSCVisitAttendee__c attendee : attendees) {
                addEmail(recipients, seen, attendeeEmail(attendee));
            }
        }
        return recipients;
    }

    /**
     * @description Adds an address when it has not already been added.
     * @param recipients Recipient list being built.
     * @param seen Addresses already added, in lower case.
     * @param email Address to add.
     */
    private static void addEmail(List<String> recipients, Set<String> seen, String email) {
        if (String.isBlank(email)) {
            return;
        }
        String key = email.trim().toLowerCase();
        if (seen.add(key)) {
            recipients.add(email.trim());
        }
    }

    /**
     * @description Adds each address from a set.
     * @param recipients Recipient list being built.
     * @param seen Addresses already added, in lower case.
     * @param emails Addresses to add.
     */
    private static void addEmail(List<String> recipients, Set<String> seen, Set<String> emails) {
        if (emails == null) {
            return;
        }
        for (String email : emails) {
            addEmail(recipients, seen, email);
        }
    }

    /**
     * @description Active user emails in the named CSC admin public group.
     * @return Set<String> admin email addresses.
     */
    private static Set<String> cscAdminEmails() {
        Set<String> emails = new Set<String>();
        if (String.isBlank(cscAdminGroupDeveloperName)) {
            return emails;
        }

        Set<Id> userIds = new Set<Id>();
        for (GroupMember member : [
            SELECT UserOrGroupId
            FROM GroupMember
            WHERE Group.DeveloperName = :cscAdminGroupDeveloperName
        ]) {
            if (member.UserOrGroupId != null && member.UserOrGroupId.getSObjectType() == User.SObjectType) {
                userIds.add(member.UserOrGroupId);
            }
        }
        if (userIds.isEmpty()) {
            return emails;
        }

        for (User adminUser : [
            SELECT Email
            FROM User
            WHERE Id IN :userIds
              AND IsActive = true
              AND Email != null
        ]) {
            emails.add(adminUser.Email);
        }
        return emails;
    }

    /**
     * @description User Ids for active STERIS attendees.
     * @param attendees Attendee rows for one visit.
     * @return Set<Id> attendee user Ids.
     */
    private static Set<Id> attendeeUserIds(List<CSCVisitAttendee__c> attendees) {
        Set<Id> userIds = new Set<Id>();
        if (attendees == null) {
            return userIds;
        }
        for (CSCVisitAttendee__c attendee : attendees) {
            if (attendee.STERISAttendee__c != null) {
                userIds.add(attendee.STERISAttendee__c);
            }
        }
        return userIds;
    }

    /**
     * @description STERIS users and customer contacts who should receive the calendar invitation.
     * @param attendees Attendee rows for one visit.
     * @return Set<Id> user and contact Ids.
     */
    private static Set<Id> attendeeInviteeIds(List<CSCVisitAttendee__c> attendees) {
        Set<Id> inviteeIds = attendeeUserIds(attendees);
        if (attendees == null) {
            return inviteeIds;
        }
        for (CSCVisitAttendee__c attendee : attendees) {
            if (isCustomerAttendee(attendee) && String.isNotBlank(attendee.Contact__r.Email)) {
                inviteeIds.add(attendee.Contact__c);
            }
        }
        return inviteeIds;
    }

    /**
     * @description Email address for a STERIS user or a customer contact.
     * @param attendee Attendee row.
     * @return String email address, or null.
     */
    private static String attendeeEmail(CSCVisitAttendee__c attendee) {
        if (attendee == null) {
            return null;
        }
        if (isCustomerAttendee(attendee)) {
            return attendee.Contact__r.Email;
        }
        return attendee.STERISAttendee__r == null ? null : attendee.STERISAttendee__r.Email;
    }

    /**
     * @description Customer attendees are Contacts with Attendee Type Customer.
     * @param attendee Attendee row.
     * @return Boolean true when the row is a customer attendee.
     */
    private static Boolean isCustomerAttendee(CSCVisitAttendee__c attendee) {
        return attendee != null
            && attendee.AttendeeType__c == ATTENDEE_TYPE_CUSTOMER
            && attendee.Contact__c != null
            && attendee.Contact__r != null;
    }

    /**
     * @description Calendar event subject.
     * @param visit Confirmed CSC visit.
     * @return String event subject.
     */
    private static String eventSubject(CSC_Visit_Request__c visit) {
        String accountName = visit.AccountFacility__r == null
            ? null
            : visit.AccountFacility__r.Name;
        if (String.isBlank(accountName)) {
            return 'CSC Visit ' + visit.Name;
        }
        return 'CSC Visit ' + visit.Name + ' - ' + accountName;
    }

    /**
     * @description Confirmation email subject.
     * @param visit Confirmed CSC visit.
     * @return String email subject.
     */
    private static String emailSubject(CSC_Visit_Request__c visit) {
        return 'CSC Visit ' + safe(visit.Name) + ' - '
            + safe(visit.AccountFacility__r == null ? null : visit.AccountFacility__r.Name)
            + ' - Confirmed Visit Notification';
    }

    /**
     * @description Confirmation email from CSC_Visit_Confirmed. Attendee rows replace the template token.
     * @param recipients Recipient addresses.
     * @param visit Confirmed CSC visit.
     * @param attendees STERIS attendees for the visit.
     * @return Messaging.SingleEmailMessage email ready to send.
     */
    private static Messaging.SingleEmailMessage confirmationEmail(
        List<String> recipients,
        CSC_Visit_Request__c visit,
        List<CSCVisitAttendee__c> attendees
    ) {
        Messaging.SingleEmailMessage rendered = renderTemplate(visit.Id, TEMPLATE_CONFIRMED);
        String subject = emailSubject(visit);
        String plainBody = emailFallback(visit, attendees);
        String htmlBody;
        if (rendered == null) {
            htmlBody = null;
        } else {
            if (String.isNotBlank(rendered.getSubject())) {
                subject = rendered.getSubject();
            }
            htmlBody = rendered.getHtmlBody();
            if (String.isBlank(htmlBody) && rendered.getPlainTextBody() != null
                && rendered.getPlainTextBody().contains('<table')) {
                htmlBody = rendered.getPlainTextBody();
            }
            if (String.isNotBlank(rendered.getPlainTextBody()) && !rendered.getPlainTextBody().contains('<')) {
                plainBody = rendered.getPlainTextBody().replace(ATTENDEE_TOKEN, attendeeLines(attendees));
            }
        }
        if (String.isBlank(htmlBody)) {
            htmlBody = confirmationHtml(visit, attendees);
        } else {
            htmlBody = htmlBody.replace(ATTENDEE_TOKEN, sterisAttendeeRows(attendees));
            htmlBody = htmlBody.replace(CUSTOMER_ATTENDEE_TOKEN, customerAttendeeRows(attendees));
            htmlBody = htmlBody.replace('{{AGENDA_LABEL}}', html(displayAgenda(visit.VisitAgendaDuration__c)));
            htmlBody = htmlBody.replace('{{REQUESTOR_EMAIL}}', requestorEmail(visit));
        }
        return buildEmail(recipients, subject, plainBody, htmlBody);
    }

    /**
     * @description HTML confirmation body used when the stored template is still plain text.
     *              Bold lines and the attendee tables match the confirmation template.
     * @param visit Confirmed CSC visit.
     * @param attendees STERIS attendees for the visit.
     * @return String HTML email body.
     */
    private static String confirmationHtml(
        CSC_Visit_Request__c visit,
        List<CSCVisitAttendee__c> attendees
    ) {
        String requestor = html(visit.VisitRequestor__r == null ? null : visit.VisitRequestor__r.Name);
        String accountName = html(visit.AccountFacility__r == null ? null : visit.AccountFacility__r.Name);
        String whenText = html(
            (visit.Confirmed_Date__c == null ? '' : visit.Confirmed_Date__c.format())
            + ', ' + displayAgenda(visit.VisitAgendaDuration__c)
        );
        return '<p style="font-style:italic;">This message was auto-generated by Salesforce</p>'
            + '<p><b>Finalized Date for CSC Visit ' + html(visit.Name) + '</b></p>'
            + '<p><b>' + requestor + '</b>&#39;s visit for <b>' + accountName
            + '</b> has been confirmed for: <b>' + whenText + '</b></p>'
            + '<p>The following individuals have been identified as STERIS field attendees:</p>'
            + attendeeTableHtml(sterisAttendeeRows(attendees))
            + '<p>The following individuals have been identified as customer attendees:</p>'
            + attendeeTableHtml(customerAttendeeRows(attendees))
            + '<p>If you have any questions regarding this visit please contact Creator of the visit: '
            + requestor + ' [ ' + requestorEmail(visit) + ' ]</p>';
    }

    /**
     * @description One Day is shown as All Day, matching the sample confirmation email.
     * @param agenda Visit Agenda / Duration value.
     * @return String agenda text for the email.
     */
    private static String displayAgenda(String agenda) {
        return String.isBlank(agenda) || agenda == 'One Day' ? 'All Day' : agenda;
    }

    /**
     * @description Visit requestor email for the closing line of the confirmation email.
     * @param visit Confirmed CSC visit.
     * @return String escaped email address, or blank.
     */
    private static String requestorEmail(CSC_Visit_Request__c visit) {
        if (visit.VisitRequestor__r == null) {
            return '';
        }
        return html(visit.VisitRequestor__r.Email);
    }

    /**
     * @description Attendee table using the same markup as the 10-day hold email.
     * @param rows HTML rows for the table body.
     * @return String HTML table.
     */
    private static String attendeeTableHtml(String rows) {
        return '<table cellpadding="6" cellspacing="0" border="1" style="border-collapse:collapse;">'
            + '<tr style="background-color:#d9d9d9;"><th>Name</th><th>Title</th><th>Confirmed</th></tr>'
            + rows + '</table>';
    }

    /**
     * @description STERIS attendee rows for the confirmation template table.
     * @param attendees STERIS attendees for the visit.
     * @return String HTML table rows.
     */
    private static String sterisAttendeeRows(List<CSCVisitAttendee__c> attendees) {
        List<String> lines = new List<String>();
        if (attendees != null) {
            for (CSCVisitAttendee__c attendee : attendees) {
                if (attendee.STERISAttendee__r == null || String.isBlank(attendee.STERISAttendee__r.Name)) {
                    continue;
                }
                lines.add(
                    '<tr style="background-color:#eeeeee;"><td>' + html(attendee.STERISAttendee__r.Name)
                    + '</td><td>' + html(attendee.STERISAttendee__r.Title) + '</td><td>N</td></tr>'
                );
            }
        }
        lines.sort();
        if (lines.isEmpty()) {
            return '<tr style="background-color:#eeeeee;"><td colspan="3">None listed</td></tr>';
        }
        return String.join(lines, '');
    }

    /**
     * @description Customer attendee rows for the confirmation email table.
     * @param attendees Attendee rows for the visit.
     * @return String HTML table rows.
     */
    private static String customerAttendeeRows(List<CSCVisitAttendee__c> attendees) {
        List<String> lines = new List<String>();
        if (attendees != null) {
            for (CSCVisitAttendee__c attendee : attendees) {
                if (!isCustomerAttendee(attendee) || String.isBlank(attendee.Contact__r.Name)) {
                    continue;
                }
                lines.add(
                    '<tr style="background-color:#eeeeee;"><td>' + html(attendee.Contact__r.Name)
                    + '</td><td>' + html(attendee.Contact__r.Title) + '</td><td>N</td></tr>'
                );
            }
        }
        lines.sort();
        if (lines.isEmpty()) {
            return '<tr style="background-color:#eeeeee;"><td colspan="3">None listed</td></tr>';
        }
        return String.join(lines, '');
    }

    /**
     * @description Escapes attendee text placed into the template table.
     * @param value Text from the attendee.
     * @return String safe HTML text.
     */
    private static String html(String value) {
        if (value == null) {
            return '';
        }
        return value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
    }

    /**
     * @description Confirmation email text used when the template is not available.
     * @param visit Confirmed CSC visit.
     * @param attendees STERIS attendees for the visit.
     * @return String email body.
     */
    private static String emailFallback(
        CSC_Visit_Request__c visit,
        List<CSCVisitAttendee__c> attendees
    ) {
        return String.join(new List<String>{
            'Finalized Date for CSC Visit ' + safe(visit.Name),
            '',
            safe(visit.VisitRequestor__r == null ? null : visit.VisitRequestor__r.Name)
                + '\'s visit for '
                + safe(visit.AccountFacility__r == null ? null : visit.AccountFacility__r.Name)
                + ' has been confirmed for: ' + String.valueOf(visit.Confirmed_Date__c)
                + ', ' + safe(visit.VisitAgendaDuration__c) + '.',
            '',
            'Location: ' + safe(visit.VisitLocation__c),
            'Purpose: ' + safe(visit.Visit_Purpose__c),
            '',
            'The following individuals have been identified as STERIS attendees:',
            '',
            'Name',
            attendeeLines(attendees),
            '',
            'The following individuals have been identified as customer attendees:',
            '',
            'Name',
            customerAttendeeLines(attendees),
            '',
            'If you have any questions regarding this visit, contact the visit requestor: '
                + safe(visit.VisitRequestor__r == null ? null : visit.VisitRequestor__r.Name)
        }, '\n');
    }

    /**
     * @description Confirmation body from the email template, with attendee names filled in.
     * @param visit Confirmed CSC visit.
     * @param attendees STERIS attendees for the visit.
     * @return String message body.
     */
    private static String confirmationBody(
        CSC_Visit_Request__c visit,
        List<CSCVisitAttendee__c> attendees
    ) {
        String body = templateBody(visit, TEMPLATE_CONFIRMED, messageBody(visit, attendees));
        if (body != null && body.contains('<')) {
            body = messageBody(visit, attendees);
        }
        String attendeeText = attendeeLines(attendees);
        if (body.contains(ATTENDEE_TOKEN)) {
            return body.replace(ATTENDEE_TOKEN, attendeeText);
        }
        if (body == messageBody(visit, attendees)) {
            return body;
        }
        return body + '\n\nSTERIS Attendees:\n' + attendeeText;
    }

    /**
     * @description Subject from a stored text template. Uses the fallback when the template is absent.
     * @param visit CSC visit used as the template related record.
     * @param developerName Email template developer name.
     * @param fallback Subject used when the template cannot be rendered.
     * @return String email subject.
     */
    private static String templateSubject(
        CSC_Visit_Request__c visit,
        String developerName,
        String fallback
    ) {
        Messaging.SingleEmailMessage rendered = renderTemplate(visit.Id, developerName);
        if (rendered != null && String.isNotBlank(rendered.getSubject())) {
            return rendered.getSubject();
        }
        return fallback;
    }

    /**
     * @description Plain-text body from a stored text template. Uses the fallback when the template is absent.
     * @param visit CSC visit used as the template related record.
     * @param developerName Email template developer name.
     * @param fallback Body used when the template cannot be rendered.
     * @return String email body.
     */
    private static String templateBody(
        CSC_Visit_Request__c visit,
        String developerName,
        String fallback
    ) {
        Messaging.SingleEmailMessage rendered = renderTemplate(visit.Id, developerName);
        if (rendered != null && String.isNotBlank(rendered.getPlainTextBody())) {
            return rendered.getPlainTextBody();
        }
        return fallback;
    }

    /**
     * @description Renders one stored template for a visit. The running user is only
     *              the merge recipient; the sent email uses the story recipient list.
     * @param whatId CSC visit Id.
     * @param developerName Email template developer name.
     * @return Messaging.SingleEmailMessage rendered template, or null when it is not available.
     */
    private static Messaging.SingleEmailMessage renderTemplate(Id whatId, String developerName) {
        String cacheKey = developerName + ':' + whatId;
        if (renderedByKey.containsKey(cacheKey)) {
            return renderedByKey.get(cacheKey);
        }
        Id storedTemplateId = templateId(developerName);
        Messaging.SingleEmailMessage rendered;
        if (storedTemplateId == null) {
            rendered = null;
        } else {
            try {
                rendered = Messaging.renderStoredEmailTemplate(
                    storedTemplateId,
                    UserInfo.getUserId(),
                    whatId
                );
            } catch (Exception renderError) {
                rendered = null;
            }
        }
        renderedByKey.put(cacheKey, rendered);
        return rendered;
    }

    /**
     * @description Loads the three CSC visit text templates once per transaction.
     * @param developerName Email template developer name.
     * @return Id template Id, or null when the template is not in the org.
     */
    private static Id templateId(String developerName) {
        if (templateIdsByName == null) {
            templateIdsByName = new Map<String, Id>();
            for (EmailTemplate template : [
                SELECT Id, DeveloperName
                FROM EmailTemplate
                WHERE DeveloperName IN (:TEMPLATE_CONFIRMED, :TEMPLATE_STATUS, :TEMPLATE_VR_AR)
            ]) {
                templateIdsByName.put(template.DeveloperName, template.Id);
            }
        }
        return templateIdsByName.get(developerName);
    }

    /**
     * @description Sorted STERIS attendee names for the confirmation template token.
     * @param attendees STERIS attendees for the visit.
     * @return String one name per line, or a blank marker.
     */
    private static String attendeeLines(List<CSCVisitAttendee__c> attendees) {
        List<String> attendeeNames = new List<String>();
        if (attendees != null) {
            for (CSCVisitAttendee__c attendee : attendees) {
                if (attendee.STERISAttendee__r != null && String.isNotBlank(attendee.STERISAttendee__r.Name)) {
                    String line = attendee.STERISAttendee__r.Name;
                    if (String.isNotBlank(attendee.STERISAttendee__r.Title)) {
                        line += '    ' + attendee.STERISAttendee__r.Title;
                    }
                    attendeeNames.add(line);
                }
            }
        }
        attendeeNames.sort();
        if (attendeeNames.isEmpty()) {
            return 'None listed';
        }
        List<String> lines = new List<String>();
        for (String attendeeName : attendeeNames) {
            lines.add('- ' + attendeeName);
        }
        return String.join(lines, '\n');
    }

    /**
     * @description Sorted customer attendee names for the plain-text confirmation email.
     * @param attendees Attendee rows for the visit.
     * @return String one name per line, or a blank marker.
     */
    private static String customerAttendeeLines(List<CSCVisitAttendee__c> attendees) {
        List<String> attendeeNames = new List<String>();
        if (attendees != null) {
            for (CSCVisitAttendee__c attendee : attendees) {
                if (!isCustomerAttendee(attendee) || String.isBlank(attendee.Contact__r.Name)) {
                    continue;
                }
                String line = attendee.Contact__r.Name;
                if (String.isNotBlank(attendee.Contact__r.Title)) {
                    line += '    ' + attendee.Contact__r.Title;
                }
                attendeeNames.add(line);
            }
        }
        attendeeNames.sort();
        if (attendeeNames.isEmpty()) {
            return 'None listed';
        }
        List<String> lines = new List<String>();
        for (String attendeeName : attendeeNames) {
            lines.add('- ' + attendeeName);
        }
        return String.join(lines, '\n');
    }

    /**
     * @description Plain-text body used when the confirmation template is not available.
     * @param visit Confirmed CSC visit.
     * @param attendees STERIS attendees for the visit.
     * @return String message body.
     */
    private static String messageBody(
        CSC_Visit_Request__c visit,
        List<CSCVisitAttendee__c> attendees
    ) {
        List<String> lines = new List<String>{
            'Finalized Date for CSC Visit ' + safe(visit.Name),
            '',
            safe(visit.VisitRequestor__r == null ? null : visit.VisitRequestor__r.Name)
                + '\'s visit for '
                + safe(visit.AccountFacility__r == null ? null : visit.AccountFacility__r.Name)
                + ' has been confirmed for: ' + String.valueOf(visit.Confirmed_Date__c)
                + ', ' + safe(visit.VisitAgendaDuration__c) + '.',
            '',
            'Location: ' + safe(visit.VisitLocation__c),
            'Purpose: ' + safe(visit.Visit_Purpose__c),
            '',
            'The following individuals have been identified as STERIS attendees:',
            '',
            'Name',
            attendeeLines(attendees),
            '',
            'The following individuals have been identified as customer attendees:',
            '',
            'Name',
            customerAttendeeLines(attendees)
        };
        return String.join(lines, '\n');
    }

    /**
     * @description Two Day visits block two all-day calendar days. Every other agenda is one day.
     * @param agenda Visit Agenda / Duration value.
     * @return Integer duration in minutes.
     */
    private static Integer durationMinutes(String agenda) {
        return agenda == TWO_DAY_AGENDA ? ONE_DAY_MINUTES * 2 : ONE_DAY_MINUTES;
    }

    /**
     * @description Returns a blank placeholder when a visit value is empty.
     * @param value Field value.
     * @return String value or a blank marker.
     */
    private static String safe(String value) {
        return String.isBlank(value) ? '-' : value;
    }

    /**
     * @description Cuts text at the Salesforce field limit.
     * @param value Text to store or send.
     * @param maxLength Maximum characters.
     * @return String trimmed text.
     */
    private static String limitText(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }

    /**
     * @description AC2. Emails the requester, Account Team, and STERIS attendees
     *              when a Requested, Confirmed, or Postponed visit is Cancelled,
     *              and deletes the calendar event. Postponement is handled by
     *              the calendar story.
     * @param visits Saved CSC visit records.
     * @param oldVisits Prior CSC visit records. Null on insert.
     */
    private static void notifyCancellation(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        if (visits == null || visits.isEmpty() || oldVisits == null) {
            return;
        }

        Set<Id> changedIds = new Set<Id>();
        for (CSC_Visit_Request__c visit : visits) {
            CSC_Visit_Request__c priorVisit = oldVisits.get(visit.Id);
            if (priorVisit == null || visit.Status__c == priorVisit.Status__c) {
                continue;
            }
            if (isStatusNotification(priorVisit.Status__c, visit.Status__c)) {
                changedIds.add(visit.Id);
            }
        }
        if (changedIds.isEmpty()) {
            return;
        }

        Map<Id, CSC_Visit_Request__c> visitsById = new Map<Id, CSC_Visit_Request__c>(
            queryStatusVisits(changedIds)
        );
        Map<Id, List<CSCVisitAttendee__c>> attendeesByVisit = queryAttendees(visitsById.keySet());
        Map<Id, List<AccountTeamMember>> teamByAccount = queryTeam(accountIds(visitsById.values()));
        sendStatusEmails(visitsById, attendeesByVisit, teamByAccount);
        updateCalendarForStatus(visitsById);
    }

    /**
     * @description AC5. Emails the configured VR/AR Planning and Design addresses
     *              the first time a VR Immersion or AR Experience visit is Approved
     *              or Confirmed. This does not create a task or block confirmation.
     * @param visits Saved CSC visit records.
     * @param oldVisits Prior CSC visit records. Null on insert.
     */
    private static void notifyVrArPlanningTeam(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        if (visits == null || visits.isEmpty()) {
            return;
        }

        Set<Id> newlyEligibleIds = new Set<Id>();
        for (CSC_Visit_Request__c visit : visits) {
            CSC_Visit_Request__c priorVisit = oldVisits == null ? null : oldVisits.get(visit.Id);
            if (isVrArPoint(visit) && (priorVisit == null || !isVrArPoint(priorVisit))) {
                newlyEligibleIds.add(visit.Id);
            }
        }
        if (newlyEligibleIds.isEmpty()) {
            return;
        }

        List<String> teamEmails = vrArTeamEmails();
        if (teamEmails.isEmpty()) {
            return;
        }

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (CSC_Visit_Request__c visit : queryStatusVisits(newlyEligibleIds)) {
            lastEmailsSent.addAll(teamEmails);
            messages.add(buildEmail(
                teamEmails,
                templateSubject(visit, TEMPLATE_VR_AR, 'CSC Visit Save the Date: ' + eventSubject(visit)),
                saveTheDateMessage(visit),
                saveTheDateHtml(visit)
            ));
            createSaveTheDateEvent(visit, teamEmails);
        }
        sendEmails(messages);
    }

    /**
     * @description All-day save-the-date event for Planning and Design users.
     *              A failure here does not block the visit confirmation.
     * @param visit VR or AR CSC visit.
     * @param teamEmails Planning and Design addresses from the metadata record.
     */
    private static void createSaveTheDateEvent(CSC_Visit_Request__c visit, List<String> teamEmails) {
        Date inviteDate = visit.Confirmed_Date__c != null
            ? visit.Confirmed_Date__c
            : visit.Primary_Requested_Date__c;
        if (inviteDate == null) {
            return;
        }
        List<User> teamUsers = [
            SELECT Id, Email
            FROM User
            WHERE IsActive = true
              AND Email IN :teamEmails
        ];
        if (teamUsers.isEmpty()) {
            return;
        }
        Event saveTheDate = new Event();
        saveTheDate.WhatId = visit.Id;
        saveTheDate.OwnerId = saveTheDateOrganizerId(visit, teamUsers);
        saveTheDate.RecordTypeId = healthcareSalesEventTypeId();
        saveTheDate.Subject = limitText(
            SAVE_THE_DATE_SUBJECT + safe(visit.Name) + ' - '
            + safe(visit.AccountFacility__r == null ? null : visit.AccountFacility__r.Name),
            255
        );
        saveTheDate.Description = limitText(saveTheDateMessage(visit), 32000);
        saveTheDate.Location = limitText(visit.VisitLocation__c, 255);
        saveTheDate.IsAllDayEvent = true;
        saveTheDate.ActivityDate = inviteDate;
        saveTheDate.DurationInMinutes = durationMinutes(visit.VisitAgendaDuration__c);
        try {
            insert saveTheDate;
            List<EventRelation> invitees = new List<EventRelation>();
            for (User teamUser : teamUsers) {
                if (teamUser.Id == saveTheDate.OwnerId) {
                    continue;
                }
                invitees.add(new EventRelation(
                    EventId = saveTheDate.Id,
                    RelationId = teamUser.Id,
                    IsInvitee = true
                ));
            }
            if (!invitees.isEmpty()) {
                insert invitees;
            }
        } catch (DmlException exceptionValue) {
            return;
        }
    }

    /**
     * @description Organizer for the save-the-date event. Planning Team users stay
     *              invitees so Salesforce sends them the calendar invitation.
     * @param visit VR or AR CSC visit.
     * @param teamUsers Active users for the Planning Team addresses.
     * @return Id event owner.
     */
    private static Id saveTheDateOrganizerId(CSC_Visit_Request__c visit, List<User> teamUsers) {
        Id runningUserId = UserInfo.getUserId();
        for (User teamUser : teamUsers) {
            if (teamUser.Id == runningUserId) {
                if (visit.VisitRequestor__c != null && visit.VisitRequestor__c != runningUserId) {
                    return visit.VisitRequestor__c;
                }
                return visit.OwnerId == null ? runningUserId : visit.OwnerId;
            }
        }
        return runningUserId;
    }

    /**
     * @description True when a Requested, Confirmed, or Postponed visit moves to Cancelled.
     * @param priorStatus Status before this save.
     * @param newStatus Status after this save.
     * @return Boolean true when the cancellation email and calendar delete apply.
     */
    private static Boolean isStatusNotification(String priorStatus, String newStatus) {
        return newStatus == STATUS_CANCELLED
            && (priorStatus == STATUS_REQUESTED
                || priorStatus == STATUS_CONFIRMED
                || priorStatus == STATUS_POSTPONED);
    }

    /**
     * @description True when a VR/AR session has reached Approved or Confirmed.
     * @param visit CSC visit record.
     * @return Boolean true when AC5 applies.
     */
    private static Boolean isVrArPoint(CSC_Visit_Request__c visit) {
        Boolean vrArSession = visit.PlanningSessionType__c == SESSION_VR
            || visit.PlanningSessionType__c == SESSION_AR;
        Boolean approvedOrConfirmed = visit.Status__c == STATUS_APPROVED
            || visit.Status__c == STATUS_CONFIRMED;
        return vrArSession && approvedOrConfirmed;
    }

    /**
     * @description Loads visits for status and VR/AR emails.
     * @param visitIds CSC visit Ids.
     * @return List<CSC_Visit_Request__c> visit rows.
     */
    private static List<CSC_Visit_Request__c> queryStatusVisits(Set<Id> visitIds) {
        return [
            SELECT Id, Name, Status__c, Confirmed_Date__c, Primary_Requested_Date__c,
                Backup_Requested_Date__c, VisitLocation__c, VisitAgendaDuration__c,
                Visit_Purpose__c, PrimaryObjective__c, PlanningSessionType__c, OwnerId,
                AccountFacility__c, AccountFacility__r.Name, AccountFacility__r.AccountNumber,
                VisitRequestor__c, VisitRequestor__r.Name, VisitRequestor__r.Email,
                VisitRequestor__r.IsActive
            FROM CSC_Visit_Request__c
            WHERE Id IN :visitIds
        ];
    }

    /**
     * @description Sends the AC2 email to the requester, Account Team, and attendees.
     * @param visitsById Visits that were cancelled or postponed.
     * @param attendeesByVisit STERIS attendees grouped by visit.
     * @param teamByAccount Account Team members grouped by account.
     */
    private static void sendStatusEmails(
        Map<Id, CSC_Visit_Request__c> visitsById,
        Map<Id, List<CSCVisitAttendee__c>> attendeesByVisit,
        Map<Id, List<AccountTeamMember>> teamByAccount
    ) {
        Set<String> adminEmails = cscAdminEmails();
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (CSC_Visit_Request__c visit : visitsById.values()) {
            List<String> recipients = recipientEmails(
                visit,
                attendeesByVisit.get(visit.Id),
                teamByAccount.get(visit.AccountFacility__c),
                adminEmails
            );
            if (visit.VisitRequestor__r != null && visit.VisitRequestor__r.IsActive == true) {
                addEmail(recipients, emailKeys(recipients), visit.VisitRequestor__r.Email);
            }
            if (recipients.isEmpty()) {
                continue;
            }
            lastEmailsSent.addAll(recipients);
            messages.add(cancellationEmail(
                recipients,
                visit,
                cancellationSubject(visit),
                statusMessage(visit, visit.Status__c),
                cancellationHtml(visit)
            ));
        }
        sendEmails(messages);
    }

    /**
     * @description #GC-3579 Removes the calendar invite when the visit leaves Confirmed
     *              or is postponed with no date. A later sales-rep confirmation creates
     *              the invite again from Confirmed Date.
     * @param visits Saved CSC visit records.
     * @param oldVisits Prior CSC visit records. Null on insert.
     */
    private static void removeReleasedCalendar(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        if (visits == null || visits.isEmpty() || oldVisits == null) {
            return;
        }

        Set<Id> releasedIds = new Set<Id>();
        for (CSC_Visit_Request__c visit : visits) {
            CSC_Visit_Request__c priorVisit = oldVisits.get(visit.Id);
            if (priorVisit == null) {
                continue;
            }
            Boolean postponedWithDate = visit.Status__c == STATUS_POSTPONED
                && visit.Confirmed_Date__c != null;
            Boolean leftConfirmed = priorVisit.Status__c == STATUS_CONFIRMED
                && visit.Status__c != STATUS_CONFIRMED
                && !postponedWithDate;
            Boolean postponedWithoutDate = visit.Status__c == STATUS_POSTPONED
                && visit.Confirmed_Date__c == null
                && priorVisit.Status__c != STATUS_POSTPONED;
            if (leftConfirmed || postponedWithoutDate) {
                releasedIds.add(visit.Id);
            }
        }
        if (releasedIds.isEmpty()) {
            return;
        }

        List<Event> eventsToDelete = queryOrganizerEvents(releasedIds);
        if (!eventsToDelete.isEmpty()) {
            delete eventsToDelete;
        }
    }

    /**
     * @description Deletes the organizer calendar event when a visit is cancelled.
     *              Invitee copies are removed with the organizer event.
     * @param visitsById Visits that were cancelled.
     */
    private static void updateCalendarForStatus(
        Map<Id, CSC_Visit_Request__c> visitsById
    ) {
        Set<Id> cancelledVisitIds = new Set<Id>();
        for (CSC_Visit_Request__c visit : visitsById.values()) {
            if (visit.Status__c == STATUS_CANCELLED) {
                cancelledVisitIds.add(visit.Id);
            }
        }
        List<Event> eventsToDelete = queryOrganizerEvents(cancelledVisitIds);
        if (!eventsToDelete.isEmpty()) {
            delete eventsToDelete;
        }
    }

    /**
     * @description Plain-text status email. Includes the visit and its dates.
     * @param visit CSC visit record.
     * @param statusLabel Status shown in the message.
     * @return String email body.
     */
    private static String cancellationSubject(CSC_Visit_Request__c visit) {
        return 'CSC Visit # ' + safe(visit.Name) + ' has been Cancelled - Cancelled Visit Notification';
    }

    /**
     * @description Plain-text cancellation email in the sample layout.
     * @param visit CSC visit record.
     * @param statusLabel Status shown in the message.
     * @return String email body.
     */
    private static String statusMessage(CSC_Visit_Request__c visit, String statusLabel) {
        return String.join(new List<String>{
            'This message was auto-generated by Salesforce:',
            '',
            'Subject: CSC Visit # ' + safe(visit.Name) + ' has been ' + statusLabel
                + ' and removed from the CSC calendar',
            'Account #: ' + accountNumber(visit),
            'Account Name: ' + safe(visit.AccountFacility__r == null ? null : visit.AccountFacility__r.Name),
            'Status: ' + statusLabel,
            '',
            'You can access the Visit here : ' + visitLink(visit.Id)
        }, '\n');
    }

    /**
     * @description HTML cancellation email matching the Sales Connection sample.
     * @param visit Cancelled CSC visit.
     * @return String HTML email body.
     */
    private static String cancellationHtml(CSC_Visit_Request__c visit) {
        String link = visitLink(visit.Id);
        String subjectLine = 'CSC Visit # ' + safe(visit.Name)
            + ' has been Cancelled and removed from the CSC calendar';
        return '<p style="font-style:italic;">This message was auto-generated by Salesforce:</p>'
            + '<table cellpadding="6" cellspacing="0" border="1" style="border-collapse:collapse;">'
            + cancellationRow('Subject:', subjectLine)
            + cancellationRow('Account #:', accountNumber(visit))
            + cancellationRow(
                'Account Name:',
                visit.AccountFacility__r == null ? '' : visit.AccountFacility__r.Name
            )
            + cancellationRow('Status:', safe(visit.Status__c))
            + '</table>'
            + '<p>You can access the Visit here : <a href="' + html(link) + '">' + html(link) + '</a></p>';
    }

    /**
     * @description One label and value row for the cancellation table.
     * @param label Row label, including the colon.
     * @param value Row value.
     * @return String HTML table row.
     */
    private static String cancellationRow(String label, String value) {
        return '<tr><td style="background-color:#d9d9d9;"><b>' + html(label) + '</b></td><td>'
            + html(value) + '</td></tr>';
    }

    /**
     * @description Account number shown as Account # on the cancellation email.
     * @param visit CSC visit record.
     * @return String account number, or blank.
     */
    private static String accountNumber(CSC_Visit_Request__c visit) {
        if (visit.AccountFacility__r == null) {
            return '';
        }
        return safe(visit.AccountFacility__r.AccountNumber);
    }

    /**
     * @description Salesforce link for the visit record.
     * @param visitId CSC visit Id.
     * @return String Lightning record URL.
     */
    private static String visitLink(Id visitId) {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        if (baseUrl.contains('.my.salesforce.com')) {
            baseUrl = baseUrl.replace('.my.salesforce.com', '.lightning.force.com');
        }
        return baseUrl + '/lightning/r/CSC_Visit_Request__c/' + visitId + '/view';
    }

    /**
     * @description Save-the-date text used when the VR/AR template is not available.
     * @param visit VR or AR CSC visit.
     * @return String email body.
     */
    private static String saveTheDateMessage(CSC_Visit_Request__c visit) {
        return String.join(new List<String>{
            'Save the Date for CSC Visit ' + safe(visit.Name),
            '',
            safe(visit.VisitRequestor__r == null ? null : visit.VisitRequestor__r.Name)
                + '\'s ' + safe(visit.PlanningSessionType__c) + ' visit for '
                + safe(visit.AccountFacility__r == null ? null : visit.AccountFacility__r.Name) + '.',
            '',
            'Primary Requested Date: ' + String.valueOf(visit.Primary_Requested_Date__c),
            'Backup Requested Date: ' + String.valueOf(visit.Backup_Requested_Date__c),
            '',
            'You can access the Visit here : ' + visitLink(visit.Id)
        }, '\n');
    }

    /**
     * @description Save-the-date email with the same date table as the hold notice.
     *              This is the Planning and Design communication. It is not a Task.
     * @param visit VR or AR CSC visit.
     * @return String HTML email body.
     */
    private static String saveTheDateHtml(CSC_Visit_Request__c visit) {
        String requestor = html(visit.VisitRequestor__r == null ? null : visit.VisitRequestor__r.Name);
        String accountName = html(visit.AccountFacility__r == null ? null : visit.AccountFacility__r.Name);
        String link = visitLink(visit.Id);
        return '<p style="font-style:italic;">This message was auto-generated by Salesforce:</p>'
            + '<p><b>Save the Date for CSC Visit ' + html(visit.Name) + '</b></p>'
            + '<p><b>' + requestor + '</b>&#39;s <b>' + html(visit.PlanningSessionType__c)
            + '</b> visit for <b>' + accountName + '</b>.</p>'
            + '<table cellpadding="6" cellspacing="0" border="1" style="border-collapse:collapse;">'
            + '<tr style="background-color:#d9d9d9;"><th></th><th>Time</th><th>Date</th><th>Agenda</th></tr>'
            + saveTheDateRows(visit)
            + '</table>'
            + '<p>You can access the Visit here : <a href="' + html(link) + '">' + html(link) + '</a></p>';
    }

    /**
     * @description Primary and backup date rows for the VR/AR save-the-date table.
     * @param visit VR or AR CSC visit.
     * @return String HTML table rows.
     */
    private static String saveTheDateRows(CSC_Visit_Request__c visit) {
        String purpose = html(visit.Visit_Purpose__c);
        String rows = saveTheDateRow('1', visit.Primary_Requested_Date__c, purpose);
        if (visit.Backup_Requested_Date__c != null) {
            rows += saveTheDateRow('2', visit.Backup_Requested_Date__c, purpose);
        }
        return rows;
    }

    /**
     * @description One All Day row in the save-the-date table.
     * @param rowNumber Displayed row number.
     * @param visitDate Requested date.
     * @param purpose Visit purpose.
     * @return String HTML table row.
     */
    private static String saveTheDateRow(String rowNumber, Date visitDate, String purpose) {
        String dateText = visitDate == null ? '' : visitDate.format();
        return '<tr style="background-color:#eeeeee;"><td>' + rowNumber + '</td><td>All Day</td><td>'
            + html(dateText) + '</td><td>' + purpose + '</td></tr>';
    }

    /**
     * @description Cancellation email. Salesforce marks it high importance.
     * @param recipients Recipient addresses.
     * @param subject Email subject.
     * @param body Email body.
     * @return Messaging.SingleEmailMessage email ready to send.
     */
    private static Messaging.SingleEmailMessage cancellationEmail(
        List<String> recipients,
        CSC_Visit_Request__c visit,
        String subject,
        String body,
        String htmlBody
    ) {
        Messaging.SingleEmailMessage rendered = renderTemplate(visit.Id, TEMPLATE_STATUS);
        if (rendered != null && String.isNotBlank(rendered.getSubject())
            && rendered.getSubject().contains('Cancelled Visit Notification')) {
            subject = rendered.getSubject();
        }
        if (rendered != null && String.isNotBlank(rendered.getHtmlBody())
            && rendered.getHtmlBody().contains('{{VISIT_LINK}}')) {
            htmlBody = rendered.getHtmlBody()
                .replace('{{ACCOUNT_NUMBER}}', html(accountNumber(visit)))
                .replace('{{VISIT_LINK}}', html(visitLink(visit.Id)));
        }
        Messaging.SingleEmailMessage message = buildEmail(recipients, subject, body, htmlBody);
        message.setEmailPriority('High');
        return message;
    }

    /**
     * @description Builds one plain-text email.
     * @param recipients Recipient addresses.
     * @param subject Email subject.
     * @param body Email body.
     * @return Messaging.SingleEmailMessage email ready to send.
     */
    private static Messaging.SingleEmailMessage buildEmail(
        List<String> recipients,
        String subject,
        String body
    ) {
        return buildEmail(recipients, subject, body, null);
    }

    /**
     * @description Builds one email. HTML is included when the message has a table layout.
     * @param recipients Recipient addresses.
     * @param subject Email subject.
     * @param body Plain-text email body.
     * @param htmlBody HTML email body. Null for a plain-text email.
     * @return Messaging.SingleEmailMessage email ready to send.
     */
    private static Messaging.SingleEmailMessage buildEmail(
        List<String> recipients,
        String subject,
        String body,
        String htmlBody
    ) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setToAddresses(recipients);
        message.setSubject(limitText(subject, 255));
        message.setPlainTextBody(limitText(body, 32000));
        if (String.isNotBlank(htmlBody)) {
            message.setHtmlBody(limitText(htmlBody, 32000));
        }
        message.setSaveAsActivity(false);
        message.setUseSignature(false);
        return message;
    }

    /**
     * @description Sends emails when the list is not empty.
     * @param messages Emails to send.
     */
    private static void sendEmails(List<Messaging.SingleEmailMessage> messages) {
        if (messages != null && !messages.isEmpty()) {
            Messaging.sendEmail(messages, false);
        }
    }

    /**
     * @description Lower-case keys for addresses already in a recipient list.
     * @param recipients Recipient addresses.
     * @return Set<String> lower-case addresses.
     */
    private static Set<String> emailKeys(List<String> recipients) {
        Set<String> keys = new Set<String>();
        for (String email : recipients) {
            if (String.isNotBlank(email)) {
                keys.add(email.trim().toLowerCase());
            }
        }
        return keys;
    }

    /**
     * @description VR/AR Planning and Design addresses from custom metadata.
     *              Tests can supply the list through vrArTeamEmailsOverride.
     * @return List<String> email addresses.
     */
    private static List<String> vrArTeamEmails() {
        if (vrArTeamEmailsOverride != null) {
            return parseEmails(vrArTeamEmailsOverride);
        }
        List<CSC_Visit_Notification__mdt> settings = [
            SELECT To_Addresses__c
            FROM CSC_Visit_Notification__mdt
            WHERE DeveloperName = :VR_AR_SETTING
            LIMIT 1
        ];
        if (settings.isEmpty()) {
            return new List<String>();
        }
        return parseEmails(settings[0].To_Addresses__c);
    }

    /**
     * @description Splits a comma or semicolon separated address list.
     * @param raw Configured addresses.
     * @return List<String> addresses that contain @.
     */
    private static List<String> parseEmails(String raw) {
        List<String> emails = new List<String>();
        if (String.isBlank(raw)) {
            return emails;
        }
        for (String part : raw.split('[,;]')) {
            String email = part.trim();
            if (email.contains('@')) {
                emails.add(email);
            }
        }
        return emails;
    }
}