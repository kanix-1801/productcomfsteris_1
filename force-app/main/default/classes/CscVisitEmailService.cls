/**
 * @author Abhishek Mishra
 * @date 23-10-2026
 * @description #GC-3518 Emails ORC, IMS, and OSV Team Members when a visit is
 *              requested, postponed, or cancelled.
 *              #GC-3562 Adds Oracle Assigned Account Team members, their
 *              managers, the visit queue, and PDMs to the confirmation email.
 *              Without sharing so the user saving the visit can reach Account
 *              Team members, managers, and queue users they do not own.
 */
public without sharing class CscVisitEmailService {
    private static final String CLASS_NAME = 'CscVisitEmailService';
    private static final String QUEUE_NAME = 'CSC_Visit_Request_Queue';
    private static final String PLANNING_YES = 'Yes';
    private static final Integer EMAILS_PER_SEND = 100;
    private static final Integer MAX_SEND_CALLS = 10;

    @TestVisible
    private static List<Id> lastTeamRecipientIds = new List<Id>();
    @TestVisible
    private static List<Id> lastStakeholderRecipientIds = new List<Id>();
    @TestVisible
    private static List<Id> lastPdmRecipientIds = new List<Id>();

    private static Id cachedBlockTypeId;
    private static Boolean blockTypeLoaded = false;

    /**
     * @description Sends Team Member status emails and any confirmation emails
     *              that were not already included in the visit confirmation.
     * @param visits Saved visit records.
     * @param oldVisits Prior visit records. Null on insert.
     */
    public static void notifyAfterSave(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        if (visits == null || visits.isEmpty()) {
            return;
        }
        Boolean wroteLog = false;
        try {
            List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
            messages.addAll(teamStatusEmails(visits, oldVisits));
            messages.addAll(supplementalConfirmationEmails(visits, oldVisits));
            wroteLog = sendEmails(messages);
        } catch (Exception emailError) {
            Logger.error(CLASS_NAME + '.notifyAfterSave', emailError);
            wroteLog = true;
        } finally {
            if (wroteLog) {
                Logger.saveLog();
            }
        }
    }

    /**
     * @description Extra confirmation addresses for the first confirmation email.
     *              Team Members for ORC, IMS, and OSV. Oracle Assigned users,
     *              managers, the visit queue, and PDMs for a CSC visit.
     * @param visits Confirmed visits.
     * @param attendeesByVisit STERIS attendees already loaded for those visits.
     * @param facilityTeam Account Team already loaded for the visit facilities.
     * @return Map<Id, List<String>> extra addresses by visit Id.
     */
    public static Map<Id, List<String>> additionalConfirmationRecipients(
        List<CSC_Visit_Request__c> visits,
        Map<Id, List<CSCVisitAttendee__c>> attendeesByVisit,
        Map<Id, List<AccountTeamMember>> facilityTeam
    ) {
        return confirmationAddresses(visits, attendeesByVisit, facilityTeam, new Set<Id>());
    }

    private static List<Messaging.SingleEmailMessage> teamStatusEmails(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        Map<Id, String> noticeByVisit = new Map<Id, String>();
        for (CSC_Visit_Request__c visit : visits) {
            if (visit == null || visit.Id == null || isBlockDate(visit)
                || !CscVisitRequestSelector.isNonCscRequest(visit.VisitType__c)
            ) {
                continue;
            }
            String notice = teamNotice(visit, oldVisits == null ? null : oldVisits.get(visit.Id));
            if (notice != null) {
                noticeByVisit.put(visit.Id, notice);
            }
        }
        if (noticeByVisit.isEmpty()) {
            return messages;
        }
        Map<Id, CSC_Visit_Request__c> visitsById = new Map<Id, CSC_Visit_Request__c>(
            loadVisits(noticeByVisit.keySet())
        );
        Map<Id, List<CSCVisitAttendee__c>> attendeesByVisit = loadAttendees(visitsById.keySet());
        Map<Id, List<AccountTeamMember>> facilityTeam = loadFacilityTeam(facilityIds(visitsById.values()));
        Map<Id, List<TeamMember__c>> membersByVisit = teamMembersByVisit(visitsById.keySet());
        for (Id visitId : noticeByVisit.keySet()) {
            CSC_Visit_Request__c visit = visitsById.get(visitId);
            List<TeamMember__c> members = membersByVisit.get(visitId);
            if (visit == null || members == null || members.isEmpty()) {
                continue;
            }
            String notice = noticeByVisit.get(visitId);
            List<String> recipients = new List<String>();
            Set<String> seen = new Set<String>();
            if (notice == CscVisitConfirmationService.STATUS_CANCELLED) {
                seen.addAll(CscVisitConfirmationService.confirmationRecipientKeys(
                    visit,
                    attendeesByVisit.get(visitId),
                    facilityTeam.get(visit.AccountFacility__c)
                ));
            }
            for (TeamMember__c member : members) {
                Integer before = recipients.size();
                addEmail(recipients, seen, member.User__r.Email);
                if (recipients.size() > before) {
                    lastTeamRecipientIds.add(member.User__c);
                }
            }
            if (!recipients.isEmpty()) {
                messages.add(statusNoticeEmail(recipients, visit, notice));
            }
        }
        return messages;
    }

    private static List<Messaging.SingleEmailMessage> supplementalConfirmationEmails(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<CSC_Visit_Request__c> selected = new List<CSC_Visit_Request__c>();
        Set<Id> pdmOnlyVisitIds = new Set<Id>();
        for (CSC_Visit_Request__c visit : visits) {
            if (visit == null || visit.Id == null || isBlockDate(visit)
                || CscVisitConfirmationService.wasConfirmationEmailed(visit.Id)
            ) {
                continue;
            }
            CSC_Visit_Request__c priorVisit = oldVisits == null ? null : oldVisits.get(visit.Id);
            Boolean becameConfirmed = visit.Status__c == CscVisitConfirmationService.STATUS_CONFIRMED
                && (priorVisit == null || priorVisit.Status__c != CscVisitConfirmationService.STATUS_CONFIRMED);
            Boolean planningTurnedOn = visit.Status__c == CscVisitConfirmationService.STATUS_CONFIRMED
                && visit.PlanningDesignRequired__c == PLANNING_YES
                && priorVisit != null
                && priorVisit.Status__c == CscVisitConfirmationService.STATUS_CONFIRMED
                && priorVisit.PlanningDesignRequired__c != PLANNING_YES;
            if (!becameConfirmed && !planningTurnedOn) {
                continue;
            }
            selected.add(visit);
            if (planningTurnedOn && !becameConfirmed) {
                pdmOnlyVisitIds.add(visit.Id);
            }
        }
        if (selected.isEmpty()) {
            return messages;
        }
        Map<Id, CSC_Visit_Request__c> visitsById = new Map<Id, CSC_Visit_Request__c>(
            loadVisits(new Map<Id, CSC_Visit_Request__c>(selected).keySet())
        );
        Map<Id, List<CSCVisitAttendee__c>> attendeesByVisit = loadAttendees(visitsById.keySet());
        Map<Id, List<AccountTeamMember>> facilityTeam = loadFacilityTeam(facilityIds(visitsById.values()));
        Map<Id, List<String>> extrasByVisit = confirmationAddresses(
            visitsById.values(),
            attendeesByVisit,
            facilityTeam,
            pdmOnlyVisitIds
        );
        for (CSC_Visit_Request__c visit : visitsById.values()) {
            if (!extrasByVisit.containsKey(visit.Id)) {
                continue;
            }
            messages.add(CscVisitConfirmationService.buildConfirmationEmail(
                extrasByVisit.get(visit.Id),
                visit,
                attendeesByVisit.get(visit.Id)
            ));
        }
        return messages;
    }

    private static Map<Id, List<String>> confirmationAddresses(
        List<CSC_Visit_Request__c> visits,
        Map<Id, List<CSCVisitAttendee__c>> attendeesByVisit,
        Map<Id, List<AccountTeamMember>> facilityTeam,
        Set<Id> pdmOnlyVisitIds
    ) {
        Map<Id, List<String>> addressesByVisit = new Map<Id, List<String>>();
        if (visits == null || visits.isEmpty()) {
            return addressesByVisit;
        }
        Set<Id> visitIds = new Map<Id, CSC_Visit_Request__c>(visits).keySet();
        Map<Id, List<TeamMember__c>> membersByVisit = teamMembersByVisit(visitIds);
        Map<Id, List<AccountTeamMember>> opportunityMembers = opportunityTeam(visits);
        Set<String> queueAddresses = queueEmails();
        Set<String> categories = pdmCategories();
        for (CSC_Visit_Request__c visit : visits) {
            if (visit == null || visit.Id == null || isBlockDate(visit)) {
                continue;
            }
            Boolean onlyPdm = pdmOnlyVisitIds != null && pdmOnlyVisitIds.contains(visit.Id);
            Boolean nonCsc = CscVisitRequestSelector.isNonCscRequest(visit.VisitType__c);
            List<String> recipients = new List<String>();
            Set<String> seen = CscVisitConfirmationService.confirmationRecipientKeys(
                visit,
                attendeesByVisit == null ? null : attendeesByVisit.get(visit.Id),
                facilityTeam == null ? null : facilityTeam.get(visit.AccountFacility__c)
            );
            if (!onlyPdm && nonCsc) {
                addTeamMembers(recipients, seen, membersByVisit.get(visit.Id));
            }
            if (!onlyPdm && !nonCsc) {
                addOracleTeamAndQueue(recipients, seen, visit, opportunityMembers, queueAddresses);
            }
            if (!nonCsc && (onlyPdm || visit.PlanningDesignRequired__c == PLANNING_YES)) {
                addPdmMembers(recipients, seen, visit, opportunityMembers, categories);
            }
            if (!recipients.isEmpty()) {
                addressesByVisit.put(visit.Id, recipients);
            }
        }
        return addressesByVisit;
    }

    private static void addTeamMembers(
        List<String> recipients,
        Set<String> seen,
        List<TeamMember__c> members
    ) {
        if (members == null) {
            return;
        }
        for (TeamMember__c member : members) {
            Integer before = recipients.size();
            addEmail(recipients, seen, member.User__r.Email);
            if (recipients.size() > before) {
                lastTeamRecipientIds.add(member.User__c);
            }
        }
    }

    private static void addOracleTeamAndQueue(
        List<String> recipients,
        Set<String> seen,
        CSC_Visit_Request__c visit,
        Map<Id, List<AccountTeamMember>> opportunityMembers,
        Set<String> queueAddresses
    ) {
        if (visit.Opportunity__r != null && visit.Opportunity__r.AccountId != null) {
            for (AccountTeamMember member : membersFor(opportunityMembers, visit.Opportunity__r.AccountId)) {
                if (member.AssignmentType__c != Label.CSC_Oracle_Assigned_Assignment_Type) {
                    continue;
                }
                Integer before = recipients.size();
                addEmail(recipients, seen, member.User.Email);
                if (recipients.size() > before) {
                    lastStakeholderRecipientIds.add(member.UserId);
                }
                if (member.User.ManagerId != null && member.User.Manager != null && member.User.Manager.IsActive) {
                    before = recipients.size();
                    addEmail(recipients, seen, member.User.Manager.Email);
                    if (recipients.size() > before) {
                        lastStakeholderRecipientIds.add(member.User.ManagerId);
                    }
                }
            }
        }
        for (String queueEmail : queueAddresses) {
            addEmail(recipients, seen, queueEmail);
        }
    }

    private static void addPdmMembers(
        List<String> recipients,
        Set<String> seen,
        CSC_Visit_Request__c visit,
        Map<Id, List<AccountTeamMember>> opportunityMembers,
        Set<String> categories
    ) {
        if (visit.Opportunity__r == null || visit.Opportunity__r.AccountId == null) {
            return;
        }
        for (AccountTeamMember member : membersFor(opportunityMembers, visit.Opportunity__r.AccountId)) {
            if (member.TerritoryCode__c == Label.CSC_PDM_Territory_Code
                && matchesCategory(member.SalesCategoryCode__c, categories)
            ) {
                Integer before = recipients.size();
                addEmail(recipients, seen, member.User.Email);
                if (recipients.size() > before) {
                    lastPdmRecipientIds.add(member.UserId);
                }
            }
        }
    }

    private static String teamNotice(CSC_Visit_Request__c visit, CSC_Visit_Request__c priorVisit) {
        String priorStatus = priorVisit == null ? null : priorVisit.Status__c;
        if (visit.Status__c == CscVisitConfirmationService.STATUS_REQUESTED
            && priorStatus != CscVisitConfirmationService.STATUS_REQUESTED
        ) {
            return CscVisitConfirmationService.STATUS_REQUESTED;
        }
        if (visit.Status__c == CscVisitConfirmationService.STATUS_CANCELLED
            && priorStatus != CscVisitConfirmationService.STATUS_CANCELLED
        ) {
            return CscVisitConfirmationService.STATUS_CANCELLED;
        }
        return null;
    }

    private static Boolean sendEmails(List<Messaging.SingleEmailMessage> messages) {
        if (messages == null || messages.isEmpty()) {
            return false;
        }
        List<String> sentTo = new List<String>();
        Integer sentCalls = 0;
        for (Integer start = 0; start < messages.size() && sentCalls < MAX_SEND_CALLS; start += EMAILS_PER_SEND) {
            List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
            Integer batchEnd = Math.min(start + EMAILS_PER_SEND, messages.size());
            for (Integer index = start; index < batchEnd; index++) {
                batch.add(messages[index]);
            }
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(batch, false);
            sentCalls++;
            for (Integer index = 0; index < results.size(); index++) {
                if (batch[index].getToAddresses() != null) {
                    sentTo.addAll(batch[index].getToAddresses());
                }
                if (!results[index].isSuccess() && !results[index].getErrors().isEmpty()) {
                    Logger.error(CLASS_NAME + '.sendEmails: ' + results[index].getErrors()[0].getMessage());
                }
            }
        }
        if (sentCalls == MAX_SEND_CALLS && messages.size() > EMAILS_PER_SEND * MAX_SEND_CALLS) {
            Logger.error(CLASS_NAME + '.sendEmails: invocation limit reached');
        }
        Logger.info(CLASS_NAME + '.sendEmails: ' + String.join(sentTo, ', '));
        return true;
    }

    private static Messaging.SingleEmailMessage statusNoticeEmail(
        List<String> recipients,
        CSC_Visit_Request__c visit,
        String statusLabel
    ) {
        String kind = requestKind(visit);
        String subject = kind + ' # ' + displayValue(visit.Name) + ' has been ' + statusLabel;
        String removed = statusLabel == CscVisitConfirmationService.STATUS_CANCELLED
            ? ' and removed from the CSC calendar'
            : '';
        String subjectLine = kind + ' # ' + displayValue(visit.Name) + ' has been ' + statusLabel + removed;
        String accountName = visit.AccountFacility__r == null ? null : visit.AccountFacility__r.Name;
        String plainBody = String.join(new List<String>{
            'This message was auto-generated by Salesforce:',
            '',
            'Subject: ' + subjectLine,
            'Account #: ' + accountNumber(visit),
            'Account Name: ' + displayValue(accountName),
            'Status: ' + statusLabel,
            '',
            'You can access the Visit here : ' + visitLink(visit.Id)
        }, '\n');
        String htmlBody = '<p style="font-style:italic;">This message was auto-generated by Salesforce:</p>'
            + '<table cellpadding="6" cellspacing="0" border="1" style="border-collapse:collapse;">'
            + statusRow('Subject:', subjectLine)
            + statusRow('Account #:', accountNumber(visit))
            + statusRow('Account Name:', accountName)
            + statusRow('Status:', statusLabel)
            + '</table>'
            + '<p>You can access the Visit here : <a href="' + escapeHtml(visitLink(visit.Id)) + '">'
            + escapeHtml(visitLink(visit.Id)) + '</a></p>';
        return buildEmail(recipients, subject, plainBody, htmlBody);
    }

    private static String requestKind(CSC_Visit_Request__c visit) {
        if (visit.VisitType__c == CscVisitRequestSelector.REQUEST_ORC) {
            return 'ORC Visit';
        }
        if (visit.VisitType__c == CscVisitRequestSelector.REQUEST_IMS) {
            return 'IMS Visit';
        }
        if (visit.VisitType__c == CscVisitRequestSelector.REQUEST_OSV) {
            return 'OSV Visit';
        }
        return 'CSC Visit';
    }

    private static List<CSC_Visit_Request__c> loadVisits(Set<Id> visitIds) {
        return [
            SELECT Id, Name, Status__c, VisitType__c, Confirmed_Date__c, VisitAgendaDuration__c,
                VisitLocation__c, Visit_Purpose__c, PrimaryObjective__c, PlanningDesignRequired__c,
                AccountFacility__c, AccountFacility__r.Name, AccountFacility__r.AccountNumber,
                Opportunity__c, Opportunity__r.AccountId,
                VisitRequestor__c, VisitRequestor__r.Name, VisitRequestor__r.Email, VisitRequestor__r.IsActive
            FROM CSC_Visit_Request__c
            WHERE Id IN :visitIds
        ];
    }

    private static Map<Id, List<CSCVisitAttendee__c>> loadAttendees(Set<Id> visitIds) {
        Map<Id, List<CSCVisitAttendee__c>> attendeesByVisit = new Map<Id, List<CSCVisitAttendee__c>>();
        for (CSCVisitAttendee__c attendee : [
            SELECT CSCVisit__c, STERISAttendee__c, STERISAttendee__r.Name,
                STERISAttendee__r.Title, STERISAttendee__r.Email, STERISAttendee__r.IsActive
            FROM CSCVisitAttendee__c
            WHERE CSCVisit__c IN :visitIds
              AND STERISAttendee__c != null
              AND STERISAttendee__r.IsActive = true
        ]) {
            if (!attendeesByVisit.containsKey(attendee.CSCVisit__c)) {
                attendeesByVisit.put(attendee.CSCVisit__c, new List<CSCVisitAttendee__c>());
            }
            attendeesByVisit.get(attendee.CSCVisit__c).add(attendee);
        }
        return attendeesByVisit;
    }

    private static Map<Id, List<AccountTeamMember>> loadFacilityTeam(Set<Id> accountIds) {
        Map<Id, List<AccountTeamMember>> teamByAccount = new Map<Id, List<AccountTeamMember>>();
        if (accountIds.isEmpty()) {
            return teamByAccount;
        }
        Date today = Date.today();
        for (AccountTeamMember member : [
            SELECT AccountId, UserId, User.Email, ExpiryDate__c
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

    private static Set<Id> facilityIds(List<CSC_Visit_Request__c> visits) {
        Set<Id> accountIds = new Set<Id>();
        for (CSC_Visit_Request__c visit : visits) {
            if (visit.AccountFacility__c != null) {
                accountIds.add(visit.AccountFacility__c);
            }
        }
        return accountIds;
    }

    private static Map<Id, List<TeamMember__c>> teamMembersByVisit(Set<Id> visitIds) {
        Map<Id, List<TeamMember__c>> membersByVisit = new Map<Id, List<TeamMember__c>>();
        if (visitIds.isEmpty()) {
            return membersByVisit;
        }
        for (TeamMember__c member : [
            SELECT CSCVisitRequest__c, User__c, User__r.Email
            FROM TeamMember__c
            WHERE CSCVisitRequest__c IN :visitIds
              AND User__r.IsActive = true
              AND User__r.Email != null
        ]) {
            if (!membersByVisit.containsKey(member.CSCVisitRequest__c)) {
                membersByVisit.put(member.CSCVisitRequest__c, new List<TeamMember__c>());
            }
            membersByVisit.get(member.CSCVisitRequest__c).add(member);
        }
        return membersByVisit;
    }

    private static Map<Id, List<AccountTeamMember>> opportunityTeam(List<CSC_Visit_Request__c> visits) {
        Set<Id> accountIds = new Set<Id>();
        for (CSC_Visit_Request__c visit : visits) {
            if (visit.Opportunity__r != null && visit.Opportunity__r.AccountId != null) {
                accountIds.add(visit.Opportunity__r.AccountId);
            }
        }
        Map<Id, List<AccountTeamMember>> membersByAccount = new Map<Id, List<AccountTeamMember>>();
        if (accountIds.isEmpty()) {
            return membersByAccount;
        }
        for (AccountTeamMember member : [
            SELECT AccountId, UserId, AssignmentType__c, TerritoryCode__c, SalesCategoryCode__c,
                User.Email, User.IsActive, User.ManagerId, User.Manager.Email, User.Manager.IsActive
            FROM AccountTeamMember
            WHERE AccountId IN :accountIds
              AND User.IsActive = true
              AND User.Email != null
        ]) {
            if (!membersByAccount.containsKey(member.AccountId)) {
                membersByAccount.put(member.AccountId, new List<AccountTeamMember>());
            }
            membersByAccount.get(member.AccountId).add(member);
        }
        return membersByAccount;
    }

    private static List<AccountTeamMember> membersFor(
        Map<Id, List<AccountTeamMember>> membersByAccount,
        Id accountId
    ) {
        return membersByAccount.containsKey(accountId)
            ? membersByAccount.get(accountId)
            : new List<AccountTeamMember>();
    }

    private static Set<String> queueEmails() {
        Set<String> emails = new Set<String>();
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
            AND DeveloperName = :QUEUE_NAME
            LIMIT 1
        ];
        if (queues.isEmpty()) {
            return emails;
        }
        Set<Id> userIds = new Set<Id>();
        Set<Id> nestedGroupIds = new Set<Id>();
        collectQueueMembers(groupMembers(new Set<Id>{ queues[0].Id }), userIds, nestedGroupIds);
        if (!nestedGroupIds.isEmpty()) {
            collectQueueMembers(groupMembers(nestedGroupIds), userIds, new Set<Id>());
        }
        if (userIds.isEmpty()) {
            return emails;
        }
        for (User queueUser : [
            SELECT Email
            FROM User
            WHERE Id IN :userIds
              AND IsActive = true
              AND Email != null
        ]) {
            emails.add(queueUser.Email);
        }
        return emails;
    }

    private static List<GroupMember> groupMembers(Set<Id> groupIds) {
        return [
            SELECT UserOrGroupId
            FROM GroupMember
            WHERE GroupId IN :groupIds
        ];
    }

    private static void collectQueueMembers(
        List<GroupMember> members,
        Set<Id> userIds,
        Set<Id> nestedGroupIds
    ) {
        for (GroupMember member : members) {
            if (member.UserOrGroupId == null) {
                continue;
            }
            if (member.UserOrGroupId.getSObjectType() == User.SObjectType) {
                userIds.add(member.UserOrGroupId);
            } else if (member.UserOrGroupId.getSObjectType() == Group.SObjectType) {
                nestedGroupIds.add(member.UserOrGroupId);
            }
        }
    }

    private static Set<String> pdmCategories() {
        Set<String> categories = new Set<String>();
        for (String value : Label.CSC_PDM_Sales_Categories.split(';')) {
            if (String.isNotBlank(value)) {
                categories.add(value.trim());
            }
        }
        return categories;
    }

    private static Boolean matchesCategory(String fieldValue, Set<String> categories) {
        if (String.isBlank(fieldValue) || categories.isEmpty()) {
            return false;
        }
        for (String value : fieldValue.split(';')) {
            if (categories.contains(value.trim())) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isBlockDate(CSC_Visit_Request__c visit) {
        Id blockTypeId = blockDateRecordTypeId();
        return visit != null && blockTypeId != null && visit.RecordTypeId == blockTypeId;
    }

    private static Id blockDateRecordTypeId() {
        if (!blockTypeLoaded) {
            blockTypeLoaded = true;
            Schema.RecordTypeInfo blockType = CSC_Visit_Request__c.SObjectType.getDescribe()
                .getRecordTypeInfosByDeveloperName()
                .get(CscVisitRequestSelector.RECORD_TYPE_BLOCK);
            cachedBlockTypeId = blockType == null ? null : blockType.getRecordTypeId();
        }
        return cachedBlockTypeId;
    }

    private static void addEmail(List<String> recipients, Set<String> seen, String email) {
        if (String.isBlank(email)) {
            return;
        }
        String key = email.trim().toLowerCase();
        if (seen.add(key)) {
            recipients.add(email.trim());
        }
    }

    private static Messaging.SingleEmailMessage buildEmail(
        List<String> recipients,
        String subject,
        String plainBody,
        String htmlBody
    ) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setToAddresses(recipients);
        message.setSubject(limitText(subject, 255));
        message.setPlainTextBody(limitText(plainBody, 32000));
        message.setHtmlBody(limitText(htmlBody, 32000));
        message.setSaveAsActivity(false);
        message.setUseSignature(false);
        return message;
    }

    private static String statusRow(String label, String value) {
        return '<tr><td style="background-color:#d9d9d9;"><b>' + escapeHtml(label) + '</b></td><td>'
            + escapeHtml(value) + '</td></tr>';
    }

    private static String accountNumber(CSC_Visit_Request__c visit) {
        if (visit.AccountFacility__r == null) {
            return '';
        }
        return displayValue(visit.AccountFacility__r.AccountNumber);
    }

    private static String visitLink(Id visitId) {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        if (baseUrl.contains('.my.salesforce.com')) {
            baseUrl = baseUrl.replace('.my.salesforce.com', '.lightning.force.com');
        }
        return baseUrl + '/lightning/r/CSC_Visit_Request__c/' + visitId + '/view';
    }

    private static String displayValue(String value) {
        return String.isBlank(value) ? '-' : value;
    }

    private static String escapeHtml(String value) {
        if (value == null) {
            return '';
        }
        return value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
    }

    private static String limitText(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }
}