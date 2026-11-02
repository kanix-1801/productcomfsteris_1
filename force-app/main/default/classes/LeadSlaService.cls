/**
 * @description Starts and ends Lead SLA clocks from the Lead owner and status.
 *              Queue pickup is 8 working hours, including the ultimate queue.
 *              Sales Development is 2 working hours. A user is 24 working hours,
 *              with a second reminder at 48. Reassignment stops the active clock
 *              and starts the clock for the new owner. A prior Missed clock
 *              stops its later reminder. A new queue owner gets an
 *              in-app notice. A new user owner gets an email and an in-app notice.
 *              The 24-hour and 48-hour reminders do the same for the owner, and
 *              the 48-hour reminder includes the manager. A miss does not change the owner.
 *              The first move from New to Working, Qualified, Unqualified, or Nurturing
 *              stores the qualifying-action time and later status changes leave it.
 *              A queue uses the Business Hours named for that queue. A user uses the
 *              Business Hours named for the country on the user. Each clock stores its
 *              target hours, the queue or person it was opened for, and the
 *              geography used for that clock.
 * @author      Vinay
 * @date        2026-10-14
 */
public with sharing class LeadSlaService {

    public static final String REGIONAL = 'Regional Queue';
    public static final String SALES_DEVELOPMENT = 'Sales Development';
    public static final String INDIVIDUAL = 'Individual';
    public static final String RUNNING = 'Running';
    public static final String MET = 'Met';
    public static final String STOPPED = 'Stopped';
    public static final String MISSED = 'Missed';

    @TestVisible
    private static String salesDevelopmentQueue = 'Lead_Sales_Development_Queue';
    @TestVisible
    private static String ultimateQueue = 'Lead_Ultimate_Queue';
    @TestVisible
    private static Map<String, String> testCalendarNames;
    private static final String NOTIFICATION_TYPE = 'Lead_SLA_Notice';
    private static Id leadSlaNotificationTypeId;
    private static Boolean notificationTypeLoaded = false;
    private static Boolean noticeLogNeeded = false;
    private static final Integer REGIONAL_MINUTES = 8 * 60;
    private static final Integer SALES_DEVELOPMENT_MINUTES = 2 * 60;
    private static final Integer INDIVIDUAL_MINUTES = 24 * 60;
    private static final Integer ESCALATION_MINUTES = 48 * 60;
    private static final Set<String> SATISFIED_STATUSES = new Set<String>{
        'Working', 'Qualified', 'Unqualified', 'Nurturing'
    };

    /**
     * @description Opens or closes a clock after the Lead owner or status changes.
     * @param newLeads Leads after the update.
     * @param oldLeads Leads before the update.
     */
    public static void apply(List<Lead> newLeads, Map<Id, Lead> oldLeads) {
        List<Lead> changedLeads = new List<Lead>();
        Set<Id> ownerIds = new Set<Id>();
        for (Lead leadRecord : newLeads) {
            Lead previous = oldLeads.get(leadRecord.Id);
            if (previous.OwnerId != leadRecord.OwnerId || previous.Status != leadRecord.Status || leadRecord.IsConverted) {
                changedLeads.add(leadRecord);
                ownerIds.add(leadRecord.OwnerId);
            }
        }
        if (changedLeads.isEmpty()) {
            return;
        }

        Map<Id, Lead_SLA__c> runningByLead = runningClocks(new Map<Id, Lead>(changedLeads).keySet());
        Map<Id, Group> queuesById = new Map<Id, Group>([
            SELECT DeveloperName, Name
            FROM Group
            WHERE Id IN :ownerIds
            AND Type = 'Queue'
        ]);
        Map<Id, User> usersById = new Map<Id, User>([
            SELECT Country, Name
            FROM User
            WHERE Id IN :ownerIds
        ]);
        List<Lead_SLA__c> toUpdate = new List<Lead_SLA__c>();
        List<Lead_SLA__c> toInsert = new List<Lead_SLA__c>();

        for (Lead leadRecord : changedLeads) {
            Lead previous = oldLeads.get(leadRecord.Id);
            Lead_SLA__c activeClock = runningByLead.get(leadRecord.Id);
            if (activeClock != null && closeForStatus(leadRecord, previous, activeClock)) {
                toUpdate.add(activeClock);
            }
            if (previous.OwnerId == leadRecord.OwnerId) {
                continue;
            }
            if (activeClock != null && finishPriorClock(activeClock, queuesById.get(leadRecord.OwnerId))
                && !toUpdate.contains(activeClock)) {
                toUpdate.add(activeClock);
            }
            Lead_SLA__c opened = openClock(
                leadRecord,
                queuesById.get(leadRecord.OwnerId),
                usersById.get(leadRecord.OwnerId)
            );
            if (opened != null) {
                toInsert.add(opened);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
            notifyAssignment(toInsert, new Map<Id, Lead>(changedLeads));
        }
        saveNoticeLog();
    }

    /**
     * @description Marks clocks whose working time has elapsed. Sends the individual
     *              reminders. Does not change the Lead owner.
     */
    public static void markDueClocks() {
        Datetime now = System.now();
        List<Lead_SLA__c> dueClocks = [
            SELECT Clock__c, Lead__c, ReminderSent__c
            FROM Lead_SLA__c
            WHERE Status__c = :RUNNING
            AND DueAt__c <= :now
            LIMIT 200
        ];
        List<Lead_SLA__c> individualReminders = new List<Lead_SLA__c>();
        for (Lead_SLA__c clock : dueClocks) {
            clock.Status__c = MISSED;
            if (clock.Clock__c == INDIVIDUAL && clock.ReminderSent__c != true) {
                individualReminders.add(clock);
            }
        }
        sendReminder(individualReminders, false);
        if (!dueClocks.isEmpty()) {
            update dueClocks;
        }

        List<Lead_SLA__c> escalations = [
            SELECT Lead__c, EscalationSent__c
            FROM Lead_SLA__c
            WHERE Clock__c = :INDIVIDUAL
            AND Status__c = :MISSED
            AND EscalationSent__c = false
            AND EscalationAt__c <= :now
            LIMIT 200
        ];
        sendReminder(escalations, true);
        if (!escalations.isEmpty()) {
            update escalations;
        }
        saveNoticeLog();
    }

    private static Boolean closeForStatus(Lead leadRecord, Lead previous, Lead_SLA__c activeClock) {
        if (leadRecord.IsConverted && activeClock.Status__c == RUNNING) {
            activeClock.Status__c = STOPPED;
            stopReminders(activeClock);
            return true;
        }
        if (activeClock.Clock__c != INDIVIDUAL || !SATISFIED_STATUSES.contains(leadRecord.Status)) {
            return false;
        }
        if (activeClock.FirstQualifyingActionAt__c != null) {
            return false;
        }
        activeClock.FirstQualifyingActionAt__c = System.now();
        if (activeClock.Status__c == RUNNING) {
            activeClock.Status__c = activeClock.DueAt__c != null && System.now() > activeClock.DueAt__c ? MISSED : MET;
        }
        stopReminders(activeClock);
        return true;
    }

    private static Boolean finishPriorClock(Lead_SLA__c activeClock, Group newOwnerQueue) {
        if (activeClock.Clock__c != INDIVIDUAL && newOwnerQueue == null) {
            activeClock.PickedUpAt__c = System.now();
            if (activeClock.Status__c == RUNNING) {
                activeClock.Status__c = activeClock.DueAt__c != null && System.now() > activeClock.DueAt__c
                    ? MISSED
                    : MET;
            }
            stopReminders(activeClock);
            return true;
        }
        if (activeClock.Status__c == RUNNING) {
            activeClock.Status__c = STOPPED;
            stopReminders(activeClock);
            return true;
        }
        if (activeClock.Status__c == MISSED
            && (activeClock.ReminderSent__c != true || activeClock.EscalationSent__c != true)) {
            stopReminders(activeClock);
            return true;
        }
        return false;
    }

    private static void stopReminders(Lead_SLA__c activeClock) {
        activeClock.ReminderSent__c = true;
        activeClock.EscalationSent__c = true;
    }

    private static Lead_SLA__c openClock(Lead leadRecord, Group ownerQueue, User owner) {
        if (leadRecord.IsConverted || ownerQueue == null && String.valueOf(leadRecord.OwnerId).startsWith('00G')) {
            return null;
        }
        String clockName;
        Integer minutes;
        if (ownerQueue != null && ownerQueue.DeveloperName == salesDevelopmentQueue) {
            clockName = SALES_DEVELOPMENT;
            minutes = SALES_DEVELOPMENT_MINUTES;
        } else if (ownerQueue != null && isQueuePickup(ownerQueue.DeveloperName)) {
            clockName = REGIONAL;
            minutes = REGIONAL_MINUTES;
        } else if (ownerQueue == null) {
            clockName = INDIVIDUAL;
            minutes = INDIVIDUAL_MINUTES;
        } else {
            return null;
        }
        String calendarKey = ownerQueue == null ? calendarKeyForCountry(owner) : ownerQueue.DeveloperName;
        Datetime started = System.now();
        Lead_SLA__c clock = new Lead_SLA__c(
            Lead__c = leadRecord.Id,
            Clock__c = clockName,
            Status__c = RUNNING,
            StartedAt__c = started,
            DueAt__c = dueAt(started, minutes, calendarKey),
            TargetHours__c = minutes / 60,
            QueueName__c = ownerQueue == null || String.isBlank(ownerQueue.Name) ? null : ownerQueue.Name.left(80),
            AssignedTo__c = ownerQueue == null && owner != null && String.isNotBlank(owner.Name) ? owner.Name.left(80) : null,
            Geography__c = geographyFor(ownerQueue, owner)
        );
        if (clockName == INDIVIDUAL) {
            clock.EscalationAt__c = dueAt(started, ESCALATION_MINUTES, calendarKey);
            if (SATISFIED_STATUSES.contains(leadRecord.Status)) {
                clock.FirstQualifyingActionAt__c = started;
                clock.Status__c = clock.DueAt__c != null && started > clock.DueAt__c ? MISSED : MET;
                clock.ReminderSent__c = true;
                clock.EscalationSent__c = true;
            }
        }
        return clock;
    }

    private static String geographyFor(Group ownerQueue, User owner) {
        if (ownerQueue != null) {
            String developerName = ownerQueue.DeveloperName;
            if (developerName != null && developerName.startsWith('Lead_Country_')) {
                return developerName.substring('Lead_Country_'.length()).left(80);
            }
            if (developerName == salesDevelopmentQueue) {
                return 'Sales Development';
            }
            if (developerName == ultimateQueue) {
                return 'Ultimate';
            }
            return String.isBlank(ownerQueue.Name) ? null : ownerQueue.Name.left(80);
        }
        if (owner == null || String.isBlank(owner.Country)) {
            return null;
        }
        String code = countryCodes().get(owner.Country.trim().toUpperCase());
        return (String.isBlank(code) ? owner.Country.trim() : code).left(80);
    }

    private static String calendarKeyForCountry(User owner) {
        if (owner == null || String.isBlank(owner.Country)) {
            return INDIVIDUAL;
        }
        String code = countryCodes().get(owner.Country.trim().toUpperCase());
        return String.isBlank(code) ? INDIVIDUAL : code;
    }

    private static Map<String, String> countryCodes() {
        return new Map<String, String>{
            'UK' => 'UK',
            'GB' => 'UK',
            'UNITED KINGDOM' => 'UK',
            'GREAT BRITAIN' => 'UK',
            'CA' => 'CA',
            'CANADA' => 'CA',
            'US' => 'US',
            'USA' => 'US',
            'UNITED STATES' => 'US',
            'UNITED STATES OF AMERICA' => 'US',
            'GM' => 'GM',
            'DE' => 'GM',
            'GERMANY' => 'GM',
            'FR' => 'FR',
            'FRANCE' => 'FR',
            'IT' => 'IT',
            'ITALY' => 'IT',
            'ES' => 'ES',
            'SPAIN' => 'ES',
            'PT' => 'PT',
            'PORTUGAL' => 'PT',
            'BE' => 'BE',
            'BELGIUM' => 'BE',
            'NL' => 'NL',
            'NETHERLANDS' => 'NL',
            'THE NETHERLANDS' => 'NL',
            'LU' => 'LU',
            'LUXEMBOURG' => 'LU',
            'AUS' => 'AUS',
            'AU' => 'AUS',
            'AUSTRALIA' => 'AUS',
            'NZ' => 'NZ',
            'NEW ZEALAND' => 'NZ',
            'HK' => 'HK',
            'HONG KONG' => 'HK',
            'MY' => 'MY',
            'MALAYSIA' => 'MY',
            'SG' => 'SG',
            'SINGAPORE' => 'SG',
            'BR' => 'BR',
            'BRAZIL' => 'BR',
            'MX' => 'MX',
            'MEXICO' => 'MX'
        };
    }

    private static Map<Id, Lead_SLA__c> runningClocks(Set<Id> leadIds) {
        Map<Id, Lead_SLA__c> runningByLead = new Map<Id, Lead_SLA__c>();
        for (Lead_SLA__c clock : [
            SELECT Lead__c, Clock__c, Status__c, DueAt__c, ReminderSent__c, EscalationSent__c, FirstQualifyingActionAt__c
            FROM Lead_SLA__c
            WHERE Lead__c IN :leadIds
            AND Status__c IN (:RUNNING, :MISSED)
        ]) {
            if (runningByLead.containsKey(clock.Lead__c) && clock.Status__c != RUNNING) {
                continue;
            }
            runningByLead.put(clock.Lead__c, clock);
        }
        return runningByLead;
    }

    private static Boolean isQueuePickup(String developerName) {
        return developerName == ultimateQueue
            || (developerName != null && developerName.startsWith('Lead_Country_'));
    }

    private static Datetime dueAt(Datetime started, Integer minutes, String calendarKey) {
        Id businessHoursId = businessHoursFor(calendarKey);
        if (businessHoursId == null && !Test.isRunningTest()) {
            businessHoursId = sharedBusinessHoursId();
        }
        if (businessHoursId == null) {
            return BusinessCalendar.addWorkingMinutes(started, minutes);
        }
        return BusinessHours.add(businessHoursId, started, minutes * 60L * 1000L);
    }

    private static Id sharedBusinessHoursId() {
        String businessHoursName = System.Label.LeadSlaBusinessHoursName;
        if (String.isBlank(businessHoursName)) {
            return null;
        }
        List<BusinessHours> calendars = [
            SELECT Id
            FROM BusinessHours
            WHERE Name = :businessHoursName
            AND IsActive = true
            LIMIT 1
        ];
        return calendars.isEmpty() ? null : calendars[0].Id;
    }

    private static Id businessHoursFor(String calendarKey) {
        String businessHoursName;
        if (Test.isRunningTest()) {
            businessHoursName = testCalendarNames == null ? null : testCalendarNames.get(calendarKey);
        } else {
            for (Sla_Calendar__mdt calendarRecord : [
                SELECT BusinessHoursName__c
                FROM Sla_Calendar__mdt
                WHERE CalendarKey__c = :calendarKey
                LIMIT 1
            ]) {
                businessHoursName = calendarRecord.BusinessHoursName__c;
            }
        }
        if (String.isBlank(businessHoursName)) {
            return null;
        }
        List<BusinessHours> calendars = [
            SELECT Id
            FROM BusinessHours
            WHERE Name = :businessHoursName
            AND IsActive = true
            LIMIT 1
        ];
        return calendars.isEmpty() ? null : calendars[0].Id;
    }

    private static void sendReminder(List<Lead_SLA__c> clocks, Boolean includeManager) {
        if (clocks.isEmpty()) {
            return;
        }
        Set<Id> leadIds = new Set<Id>();
        for (Lead_SLA__c clock : clocks) {
            leadIds.add(clock.Lead__c);
        }
        Map<Id, Lead> leadsById = new Map<Id, Lead>([
            SELECT Name, Company, Status, Phone, Email, Country, CountryCode, OwnerId, Owner.Email, Owner.Name
            FROM Lead
            WHERE Id IN :leadIds
        ]);
        Set<Id> ownerIds = new Set<Id>();
        for (Lead leadRecord : leadsById.values()) {
            ownerIds.add(leadRecord.OwnerId);
        }
        Map<Id, User> owners = new Map<Id, User>([
            SELECT Email, ManagerId, Manager.Email
            FROM User
            WHERE Id IN :ownerIds
        ]);
        String subject = includeManager ? 'Lead SLA second reminder' : 'Lead SLA reminder';
        String intro = includeManager
            ? 'This Lead is still open 48 working hours after it was assigned.'
            : 'This Lead is still open 24 working hours after it was assigned.';
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Lead_SLA__c> messaged = new List<Lead_SLA__c>();
        for (Lead_SLA__c clock : clocks) {
            Lead leadRecord = leadsById.get(clock.Lead__c);
            User owner = leadRecord == null ? null : owners.get(leadRecord.OwnerId);
            if (owner == null) {
                continue;
            }
            Set<String> recipientIds = new Set<String>{ String.valueOf(owner.Id) };
            if (includeManager && owner.ManagerId != null) {
                recipientIds.add(String.valueOf(owner.ManagerId));
            }
            if (sendInApp(recipientIds, leadRecord.Id, subject, noticeLine(leadRecord, intro))) {
                markNoticeSent(clock, includeManager);
            }
            if (String.isBlank(owner.Email)) {
                continue;
            }
            List<String> addresses = new List<String>{ owner.Email };
            if (includeManager && owner.Manager != null && String.isNotBlank(owner.Manager.Email)) {
                addresses.add(owner.Manager.Email);
            }
            messages.add(plainEmail(addresses, subject, leadEmailBody(leadRecord, intro)));
            messaged.add(clock);
        }
        if (messages.isEmpty()) {
            return;
        }
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages, false);
        for (Integer index = 0; index < results.size(); index++) {
            if (results[index].isSuccess()) {
                markNoticeSent(messaged[index], includeManager);
            }
        }
    }

    private static void notifyAssignment(List<Lead_SLA__c> clocks, Map<Id, Lead> leadsById) {
        Set<Id> userIds = new Set<Id>();
        for (Lead_SLA__c clock : clocks) {
            Lead leadRecord = leadsById.get(clock.Lead__c);
            if (leadRecord != null && clock.Clock__c == INDIVIDUAL) {
                userIds.add(leadRecord.OwnerId);
            }
        }
        Map<Id, User> owners = userIds.isEmpty()
            ? new Map<Id, User>()
            : new Map<Id, User>([SELECT Email FROM User WHERE Id IN :userIds]);
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Lead_SLA__c clock : clocks) {
            Lead leadRecord = leadsById.get(clock.Lead__c);
            if (leadRecord == null) {
                continue;
            }
            if (clock.Clock__c == INDIVIDUAL) {
                String subject = 'Lead assigned to you';
                String intro = 'This Lead is assigned to you. Respond within 24 working hours.';
                sendInApp(
                    new Set<String>{ String.valueOf(leadRecord.OwnerId) },
                    leadRecord.Id,
                    subject,
                    noticeLine(leadRecord, intro)
                );
                User owner = owners.get(leadRecord.OwnerId);
                if (owner != null && String.isNotBlank(owner.Email)) {
                    messages.add(plainEmail(new List<String>{ owner.Email }, subject, leadEmailBody(leadRecord, intro)));
                }
            } else {
                String hours = clock.Clock__c == SALES_DEVELOPMENT ? '2' : '8';
                sendInApp(
                    new Set<String>{ String.valueOf(leadRecord.OwnerId) },
                    leadRecord.Id,
                    'Lead assigned to your queue',
                    noticeLine(leadRecord, 'A Lead is in your queue. Pick it up within ' + hours + ' working hours.')
                );
            }
        }
        if (!messages.isEmpty()) {
            Messaging.sendEmail(messages, false);
        }
    }

    private static String noticeLine(Lead leadRecord, String intro) {
        if (leadRecord == null || String.isBlank(leadRecord.Name)) {
            return intro;
        }
        return leadRecord.Name + '. ' + intro;
    }

    private static String leadEmailBody(Lead leadRecord, String intro) {
        String country = String.isNotBlank(leadRecord.Country) ? leadRecord.Country : leadRecord.CountryCode;
        String href = leadLink(leadRecord.Id);
        String leadName = String.isBlank(leadRecord.Name) ? 'Open the Lead' : escapeHtml(leadRecord.Name);
        return '<p>' + escapeHtml(intro) + '</p>'
            + '<p>Lead: <a href="' + href + '">' + leadName + '</a><br/>'
            + 'Company: ' + escapeHtml(blankAsDash(leadRecord.Company)) + '<br/>'
            + 'Status: ' + escapeHtml(blankAsDash(leadRecord.Status)) + '<br/>'
            + 'Phone: ' + escapeHtml(blankAsDash(leadRecord.Phone)) + '<br/>'
            + 'Email: ' + escapeHtml(blankAsDash(leadRecord.Email)) + '<br/>'
            + 'Country: ' + escapeHtml(blankAsDash(country)) + '</p>'
            + '<p><a href="' + href + '">Open the Lead</a></p>';
    }

    private static String escapeHtml(String value) {
        if (value == null) {
            return '';
        }
        return value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;');
    }

    private static String blankAsDash(String value) {
        return String.isBlank(value) ? '-' : value;
    }

    private static String leadLink(Id leadId) {
        return URL.getOrgDomainUrl().toExternalForm() + '/lightning/r/Lead/' + leadId + '/view';
    }

    private static Messaging.SingleEmailMessage plainEmail(List<String> addresses, String subject, String body) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setToAddresses(addresses);
        message.setSubject(subject);
        message.setHtmlBody(body);
        message.setSaveAsActivity(false);
        return message;
    }

    private static void markNoticeSent(Lead_SLA__c clock, Boolean includeManager) {
        if (includeManager) {
            clock.EscalationSent__c = true;
        } else {
            clock.ReminderSent__c = true;
        }
    }

    private static Boolean sendInApp(Set<String> recipientIds, Id targetId, String title, String body) {
        if (recipientIds == null || recipientIds.isEmpty() || targetId == null || notificationTypeId() == null) {
            return false;
        }
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(title);
            notification.setBody(body);
            notification.setNotificationTypeId(leadSlaNotificationTypeId);
            notification.setTargetId(targetId);
            notification.send(recipientIds);
            return true;
        } catch (Exception exceptionRecord) {
            Logger.error('Lead SLA notice failed for ' + targetId + '. ' + exceptionRecord.getMessage());
            noticeLogNeeded = true;
            return false;
        }
    }

    private static Id notificationTypeId() {
        if (!notificationTypeLoaded) {
            notificationTypeLoaded = true;
            CustomNotificationType notificationType =
                TeamMemberSelector.getCustomNotificationTypeByDeveloperName(NOTIFICATION_TYPE);
            leadSlaNotificationTypeId = notificationType == null ? null : notificationType.Id;
            if (leadSlaNotificationTypeId == null) {
                Logger.warn('Lead SLA notice type Lead_SLA_Notice was not found.');
                noticeLogNeeded = true;
            }
        }
        return leadSlaNotificationTypeId;
    }

    private static void saveNoticeLog() {
        if (!noticeLogNeeded) {
            return;
        }
        noticeLogNeeded = false;
        try {
            Logger.saveLog();
        } catch (Exception exceptionRecord) {
            System.debug(LoggingLevel.ERROR, exceptionRecord.getMessage());
        }
    }
}