/**
 * @author Abhishek Mishra
 * @date 23-10-2026
 * @description #GC-3518 Bell and email for ORC, IMS, and OSV Team Members.
 *              #GC-3562 Email for a confirmed CSC visit Account Team, managers,
 *              visit queue, and Planning and Design PDMs.
 *              without sharing so the user saving the visit can reach Account
 *              Team members, managers, and queue users they do not own.
 */
public without sharing class CscVisitNotificationService {
    public static final String NOTIFICATION_TYPE = 'Visit_Team_Status_Update';

    @TestVisible
    private static List<Id> lastNotifiedUserIds = new List<Id>();
    @TestVisible
    private static List<Id> lastEmailedUserIds = new List<Id>();
    @TestVisible
    private static List<Id> lastStakeholderIds = new List<Id>();
    @TestVisible
    private static List<Id> lastPdmIds = new List<Id>();

    private static Id cachedNotificationTypeId;
    private static Boolean notificationTypeLoaded = false;
    private static Boolean hasLogEntries = false;
    private static final String CLASS_NAME = 'CscVisitNotificationService';
    private static final String QUEUE_NAME = 'CSC_Visit_Request_Queue';
    private static final String PLANNING_YES = 'Yes';
    private static final Integer EMAILS_PER_SEND = 100;
    private static final Integer MAX_SEND_CALLS = 10;

    /**
     * @description Runs the Team Member notice and the CSC stakeholder emails.
     * @param visits Saved visit records.
     * @param oldVisits Prior visit records. Null on insert.
     */
    public static void notifyAfterSave(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        if (isTriggerBypassed() || visits == null || visits.isEmpty()) {
            return;
        }
        try {
            List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
            messages.addAll(teamMemberEmails(visits, oldVisits));
            messages.addAll(cscStakeholderEmails(visits, oldVisits));
            sendEmails(messages);
        } catch (Exception notificationError) {
            logError(CLASS_NAME + '.notifyAfterSave', notificationError);
        } finally {
            if (hasLogEntries) {
                Logger.saveLog();
                hasLogEntries = false;
            }
        }
    }

    /**
     * @description #GC-3518 Bell and email for ORC, IMS, and OSV Team Members.
     *              Bells stay one per visit because each notification has its own target record.
     * @param visits Saved visit records.
     * @param oldVisits Prior visit records. Null on insert.
     * @return List<Messaging.SingleEmailMessage> emails for one send call.
     */
    private static List<Messaging.SingleEmailMessage> teamMemberEmails(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        Map<Id, String> noticeByVisit = teamNoticesFor(visits, oldVisits);
        if (noticeByVisit.isEmpty()) {
            return messages;
        }

        Map<Id, CSC_Visit_Request__c> visitsById = new Map<Id, CSC_Visit_Request__c>([
            SELECT Id, Name, VisitType__c, AccountFacility__r.Name
            FROM CSC_Visit_Request__c
            WHERE Id IN :noticeByVisit.keySet()
        ]);
        Map<Id, Set<String>> usersByVisit = teamUsersByVisit(noticeByVisit.keySet());
        Id notificationTypeId = notificationTypeId();

        for (Id visitId : noticeByVisit.keySet()) {
            CSC_Visit_Request__c visit = visitsById.get(visitId);
            Set<String> userIds = usersByVisit.get(visitId);
            if (visit == null || userIds == null || userIds.isEmpty()) {
                continue;
            }
            for (String userId : userIds) {
                lastNotifiedUserIds.add((Id) userId);
            }
            String notice = noticeByVisit.get(visitId);
            sendBell(visit, userIds, notice, notificationTypeId);
            messages.addAll(teamEmailsFor(visit, userIds, notice));
        }
        return messages;
    }

    /**
     * @description #GC-3562 Emails the Account Team once for confirmation and Planning and Design.
     * @param visits Saved visit records.
     * @param oldVisits Prior visit records. Null on insert.
     * @return List<Messaging.SingleEmailMessage> emails for one send call.
     */
    private static List<Messaging.SingleEmailMessage> cscStakeholderEmails(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        Id blockTypeId = blockDateRecordTypeId();
        List<CSC_Visit_Request__c> confirmedVisits = new List<CSC_Visit_Request__c>();
        List<CSC_Visit_Request__c> planningVisits = new List<CSC_Visit_Request__c>();

        for (CSC_Visit_Request__c visit : visits) {
            if (visit == null || visit.Id == null || !isCscVisit(visit, blockTypeId)) {
                continue;
            }
            CSC_Visit_Request__c priorVisit = oldVisits == null ? null : oldVisits.get(visit.Id);
            Boolean becameConfirmed = visit.Status__c == CscVisitRequestSelector.STATUS_CONFIRMED
                && (priorVisit == null || priorVisit.Status__c != CscVisitRequestSelector.STATUS_CONFIRMED);
            Boolean planningRequired = visit.PlanningDesignRequired__c == PLANNING_YES;
            Boolean planningTurnedOn = planningRequired
                && visit.Status__c == CscVisitRequestSelector.STATUS_CONFIRMED
                && priorVisit != null
                && priorVisit.PlanningDesignRequired__c != PLANNING_YES;
            if (becameConfirmed) {
                confirmedVisits.add(visit);
            }
            if (planningRequired && (becameConfirmed || planningTurnedOn)) {
                planningVisits.add(visit);
            }
        }
        if (confirmedVisits.isEmpty() && planningVisits.isEmpty()) {
            return messages;
        }

        List<CSC_Visit_Request__c> visitsToRead = new List<CSC_Visit_Request__c>();
        visitsToRead.addAll(confirmedVisits);
        visitsToRead.addAll(planningVisits);
        Map<Id, Opportunity> opportunityById = opportunitiesFor(visitsToRead);
        Map<Id, List<AccountTeamMember>> membersByAccount = membersByAccount(opportunityById.values());
        Set<Id> queueIds = confirmedVisits.isEmpty() ? new Set<Id>() : queueUserIds();

        if (!confirmedVisits.isEmpty()) {
            messages.addAll(stakeholderEmails(confirmedVisits, opportunityById, membersByAccount, queueIds));
        }
        if (!planningVisits.isEmpty()) {
            messages.addAll(pdmEmails(planningVisits, opportunityById, membersByAccount));
        }
        return messages;
    }

    private static Map<Id, String> teamNoticesFor(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        Map<Id, String> noticeByVisit = new Map<Id, String>();
        for (CSC_Visit_Request__c visit : visits) {
            if (visit.Id == null || !CscVisitRequestSelector.isNonCscRequest(visit.VisitType__c)) {
                continue;
            }
            CSC_Visit_Request__c priorVisit = oldVisits == null ? null : oldVisits.get(visit.Id);
            String notice = teamNoticeFor(visit, priorVisit);
            if (notice != null) {
                noticeByVisit.put(visit.Id, notice);
            }
        }
        return noticeByVisit;
    }

    private static String teamNoticeFor(
        CSC_Visit_Request__c visit,
        CSC_Visit_Request__c priorVisit
    ) {
        String priorStatus = priorVisit == null ? null : priorVisit.Status__c;
        if (visit.Status__c == CscVisitRequestSelector.STATUS_REQUESTED
            && priorStatus != CscVisitRequestSelector.STATUS_REQUESTED
        ) {
            return 'Requested';
        }
        if (visit.Status__c == CscVisitRequestSelector.STATUS_CONFIRMED
            && priorStatus != CscVisitRequestSelector.STATUS_CONFIRMED
        ) {
            return 'Confirmed';
        }
        if (visit.Status__c == CscVisitRequestSelector.STATUS_CONFIRMED
            && priorVisit != null
            && priorStatus == CscVisitRequestSelector.STATUS_CONFIRMED
            && priorVisit.Confirmed_Date__c != visit.Confirmed_Date__c
        ) {
            return 'Confirmed date updated';
        }
        if (visit.Status__c == CscVisitRequestSelector.STATUS_POSTPONED
            && priorStatus != CscVisitRequestSelector.STATUS_POSTPONED
        ) {
            return 'Postponed';
        }
        if (visit.Status__c == CscVisitRequestSelector.STATUS_CANCELLED
            && priorStatus != CscVisitRequestSelector.STATUS_CANCELLED
        ) {
            return 'Cancelled';
        }
        return null;
    }

    private static Map<Id, Set<String>> teamUsersByVisit(Set<Id> visitIds) {
        Map<Id, Set<String>> usersByVisit = new Map<Id, Set<String>>();
        for (TeamMember__c member : [
            SELECT CSCVisitRequest__c, User__c
            FROM TeamMember__c
            WHERE CSCVisitRequest__c IN :visitIds
              AND User__c != null
              AND User__r.IsActive = true
        ]) {
            if (!usersByVisit.containsKey(member.CSCVisitRequest__c)) {
                usersByVisit.put(member.CSCVisitRequest__c, new Set<String>());
            }
            usersByVisit.get(member.CSCVisitRequest__c).add(String.valueOf(member.User__c));
        }
        return usersByVisit;
    }

    private static void sendBell(
        CSC_Visit_Request__c visit,
        Set<String> userIds,
        String notice,
        Id notificationTypeId
    ) {
        if (notificationTypeId == null) {
            return;
        }
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(notificationTypeId);
            notification.setTargetId(visit.Id);
            notification.setTitle(limitText(requestTypeLabel(visit.VisitType__c) + ' ' + notice, 250));
            notification.setBody(limitText(teamBody(visit, notice), 750));
            notification.send(userIds);
        } catch (Exception bellError) {
            logError(CLASS_NAME + '.sendBell: visitId=' + visit.Id, bellError);
        }
    }

    private static List<Messaging.SingleEmailMessage> teamEmailsFor(
        CSC_Visit_Request__c visit,
        Set<String> userIds,
        String notice
    ) {
        String subject = limitText(requestTypeLabel(visit.VisitType__c) + ' ' + notice, 250);
        String body = teamBody(visit, notice);
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (String userId : userIds) {
            lastEmailedUserIds.add((Id) userId);
            messages.add(emailFor((Id) userId, subject, body));
        }
        return messages;
    }

    private static List<Messaging.SingleEmailMessage> stakeholderEmails(
        List<CSC_Visit_Request__c> visits,
        Map<Id, Opportunity> opportunityById,
        Map<Id, List<AccountTeamMember>> membersByAccount,
        Set<Id> queueIds
    ) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        lastStakeholderIds.clear();

        for (CSC_Visit_Request__c visit : visits) {
            Opportunity opportunityRecord = opportunityById.get(visit.Opportunity__c);
            if (opportunityRecord == null || opportunityRecord.AccountId == null) {
                continue;
            }
            Set<Id> recipientIds = new Set<Id>();
            for (AccountTeamMember member : membersFor(membersByAccount, opportunityRecord.AccountId)) {
                if (member.AssignmentType__c != Label.CSC_Oracle_Assigned_Assignment_Type
                    || member.UserId == null
                    || member.User == null
                    || !member.User.IsActive
                ) {
                    continue;
                }
                recipientIds.add(member.UserId);
                if (member.User.ManagerId != null && member.User.Manager != null && member.User.Manager.IsActive) {
                    recipientIds.add(member.User.ManagerId);
                }
            }
            recipientIds.addAll(queueIds);
            lastStakeholderIds.addAll(recipientIds);
            messages.addAll(emailsFor(
                recipientIds,
                'CSC Visit Confirmed: ' + visit.Name,
                stakeholderBody(visit, opportunityRecord)
            ));
        }
        return messages;
    }

    private static List<Messaging.SingleEmailMessage> pdmEmails(
        List<CSC_Visit_Request__c> visits,
        Map<Id, Opportunity> opportunityById,
        Map<Id, List<AccountTeamMember>> membersByAccount
    ) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        Set<String> salesCategories = salesCategories();
        String territoryCode = Label.CSC_PDM_Territory_Code;
        lastPdmIds.clear();

        for (CSC_Visit_Request__c visit : visits) {
            Opportunity opportunityRecord = opportunityById.get(visit.Opportunity__c);
            if (opportunityRecord == null || opportunityRecord.AccountId == null) {
                continue;
            }
            Set<Id> recipientIds = new Set<Id>();
            for (AccountTeamMember member : membersFor(membersByAccount, opportunityRecord.AccountId)) {
                if (member.UserId == null || member.User == null || !member.User.IsActive) {
                    continue;
                }
                if (member.TerritoryCode__c == territoryCode
                    && matchesSalesCategory(member.SalesCategoryCode__c, salesCategories)
                ) {
                    recipientIds.add(member.UserId);
                }
            }
            lastPdmIds.addAll(recipientIds);
            messages.addAll(emailsFor(
                recipientIds,
                'CSC Visit Planning and Design: ' + visit.Name,
                pdmBody(visit, opportunityRecord)
            ));
        }
        return messages;
    }

    private static Boolean isCscVisit(CSC_Visit_Request__c visit, Id blockTypeId) {
        return visit.RecordTypeId != blockTypeId
            && !CscVisitRequestSelector.isNonCscRequest(visit.VisitType__c);
    }

    private static Id blockDateRecordTypeId() {
        Schema.RecordTypeInfo blockType = Schema.SObjectType.CSC_Visit_Request__c
            .getRecordTypeInfosByDeveloperName()
            .get(CscVisitRequestSelector.RECORD_TYPE_BLOCK);
        return blockType == null ? null : blockType.getRecordTypeId();
    }

    private static Map<Id, Opportunity> opportunitiesFor(List<CSC_Visit_Request__c> visits) {
        Set<Id> opportunityIds = new Set<Id>();
        for (CSC_Visit_Request__c visit : visits) {
            if (visit.Opportunity__c != null) {
                opportunityIds.add(visit.Opportunity__c);
            }
        }
        if (opportunityIds.isEmpty()) {
            return new Map<Id, Opportunity>();
        }
        return new Map<Id, Opportunity>([
            SELECT Id, Name, AccountId, Account.Name
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ]);
    }

    private static Map<Id, List<AccountTeamMember>> membersByAccount(List<Opportunity> opportunities) {
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opportunityRecord : opportunities) {
            if (opportunityRecord.AccountId != null) {
                accountIds.add(opportunityRecord.AccountId);
            }
        }
        Map<Id, List<AccountTeamMember>> membersByAccount = new Map<Id, List<AccountTeamMember>>();
        if (accountIds.isEmpty()) {
            return membersByAccount;
        }
        for (AccountTeamMember member : [
            SELECT AccountId, UserId, AssignmentType__c, TerritoryCode__c, SalesCategoryCode__c,
                User.IsActive, User.ManagerId, User.Manager.IsActive
            FROM AccountTeamMember
            WHERE AccountId IN :accountIds
            AND User.IsActive = true
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

    private static Set<Id> queueUserIds() {
        Set<Id> userIds = new Set<Id>();
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
            AND DeveloperName = :QUEUE_NAME
            LIMIT 1
        ];
        if (queues.isEmpty()) {
            return userIds;
        }
        Set<Id> nestedGroupIds = new Set<Id>();
        for (GroupMember member : [
            SELECT UserOrGroupId
            FROM GroupMember
            WHERE GroupId = :queues[0].Id
        ]) {
            collectMember(member.UserOrGroupId, userIds, nestedGroupIds);
        }
        if (!nestedGroupIds.isEmpty()) {
            for (GroupMember member : [
                SELECT UserOrGroupId
                FROM GroupMember
                WHERE GroupId IN :nestedGroupIds
            ]) {
                if (member.UserOrGroupId != null
                    && member.UserOrGroupId.getSObjectType() == User.SObjectType
                ) {
                    userIds.add(member.UserOrGroupId);
                }
            }
        }
        return activeUserIds(userIds);
    }

    private static void collectMember(Id memberId, Set<Id> userIds, Set<Id> nestedGroupIds) {
        if (memberId == null) {
            return;
        }
        if (memberId.getSObjectType() == User.SObjectType) {
            userIds.add(memberId);
        } else if (memberId.getSObjectType() == Group.SObjectType) {
            nestedGroupIds.add(memberId);
        }
    }

    private static Set<Id> activeUserIds(Set<Id> userIds) {
        Set<Id> activeIds = new Set<Id>();
        if (userIds.isEmpty()) {
            return activeIds;
        }
        for (User recipient : [
            SELECT Id
            FROM User
            WHERE Id IN :userIds
            AND IsActive = true
            AND Email != null
        ]) {
            activeIds.add(recipient.Id);
        }
        return activeIds;
    }

    private static Set<String> salesCategories() {
        Set<String> categories = new Set<String>();
        for (String value : Label.CSC_PDM_Sales_Categories.split(';')) {
            if (String.isNotBlank(value)) {
                categories.add(value.trim());
            }
        }
        return categories;
    }

    private static Boolean matchesSalesCategory(String fieldValue, Set<String> expectedCategories) {
        if (String.isBlank(fieldValue) || expectedCategories.isEmpty()) {
            return false;
        }
        for (String value : fieldValue.split(';')) {
            if (expectedCategories.contains(value.trim())) {
                return true;
            }
        }
        return false;
    }

    private static List<Messaging.SingleEmailMessage> emailsFor(
        Set<Id> recipientIds,
        String subject,
        String body
    ) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Id recipientId : recipientIds) {
            messages.add(emailFor(recipientId, subject, body));
        }
        return messages;
    }

    private static Messaging.SingleEmailMessage emailFor(Id recipientId, String subject, String body) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(recipientId);
        message.setSaveAsActivity(false);
        message.setSubject(subject);
        message.setPlainTextBody(body);
        return message;
    }

    private static String stakeholderBody(CSC_Visit_Request__c visit, Opportunity opportunityRecord) {
        return 'CSC visit ' + visit.Name
            + ' is confirmed for ' + String.valueOf(visit.Confirmed_Date__c) + '.'
            + '\nAccount: ' + opportunityRecord.Account.Name
            + '\nOpportunity: ' + opportunityRecord.Name
            + '\nThis notice is for the account team, their managers, and the CSC visit administrators.';
    }

    private static String pdmBody(CSC_Visit_Request__c visit, Opportunity opportunityRecord) {
        return 'CSC visit ' + visit.Name
            + ' requires Planning and Design.'
            + '\nConfirmed Date: ' + String.valueOf(visit.Confirmed_Date__c)
            + '\nAccount: ' + opportunityRecord.Account.Name
            + '\nOpportunity: ' + opportunityRecord.Name
            + '\nThis notice is informational. No Salesforce task or approval is required.';
    }

    private static void sendEmails(List<Messaging.SingleEmailMessage> messages) {
        if (messages.isEmpty()) {
            return;
        }
        logInfo(CLASS_NAME + '.sendEmails: recipientCount=' + messages.size() + ', ' + recipientSummary(messages));
        Integer sentCalls = 0;
        Integer index = 0;
        while (index < messages.size() && sentCalls < MAX_SEND_CALLS) {
            List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
            while (index < messages.size() && batch.size() < EMAILS_PER_SEND) {
                batch.add(messages[index]);
                index++;
            }
            deliver(batch);
            sentCalls++;
        }
        if (index < messages.size()) {
            logError(
                CLASS_NAME + '.sendEmails: invocation limit reached, unsentCount='
                + (messages.size() - index)
            );
        }
    }

    private static void deliver(List<Messaging.SingleEmailMessage> batch) {
        try {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(batch, false);
            List<String> failures = new List<String>();
            for (Integer resultIndex = 0; resultIndex < results.size(); resultIndex++) {
                if (results[resultIndex].isSuccess()) {
                    continue;
                }
                String detail = results[resultIndex].getErrors().isEmpty()
                    ? 'Email was rejected'
                    : results[resultIndex].getErrors()[0].getMessage();
                failures.add(String.valueOf(batch[resultIndex].getTargetObjectId()) + ' ' + detail);
            }
            if (!failures.isEmpty()) {
                logError(CLASS_NAME + '.sendEmails: ' + String.join(failures, '; '));
            }
        } catch (Exception emailError) {
            logError(CLASS_NAME + '.sendEmails', emailError);
        }
    }

    private static String recipientSummary(List<Messaging.SingleEmailMessage> messages) {
        List<String> recipients = new List<String>();
        for (Messaging.SingleEmailMessage message : messages) {
            recipients.add(message.getSubject() + ' -> ' + message.getTargetObjectId());
        }
        String summary = String.join(recipients, '; ');
        return summary.length() <= 4000 ? summary : summary.substring(0, 4000);
    }

    private static Id notificationTypeId() {
        if (!notificationTypeLoaded) {
            notificationTypeLoaded = true;
            List<CustomNotificationType> types = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = :NOTIFICATION_TYPE
                LIMIT 1
            ];
            cachedNotificationTypeId = types.isEmpty() ? null : types[0].Id;
        }
        return cachedNotificationTypeId;
    }

    private static String teamBody(CSC_Visit_Request__c visit, String notice) {
        String accountName = visit.AccountFacility__r == null ? null : visit.AccountFacility__r.Name;
        String text = requestTypeLabel(visit.VisitType__c) + ' ' + visit.Name;
        if (String.isNotBlank(accountName)) {
            text += ' - ' + accountName;
        }
        return text + ' is ' + notice + '.';
    }

    private static String requestTypeLabel(String requestType) {
        if (requestType == CscVisitRequestSelector.REQUEST_ORC) {
            return 'ORC Visit';
        }
        if (requestType == CscVisitRequestSelector.REQUEST_IMS) {
            return 'IMS Visit';
        }
        if (requestType == CscVisitRequestSelector.REQUEST_OSV) {
            return 'OSV Visit';
        }
        return 'CSC Visit';
    }

    private static String limitText(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }

    private static void logInfo(String message) {
        Logger.info(message);
        hasLogEntries = true;
    }

    private static void logError(String message) {
        Logger.error(message);
        hasLogEntries = true;
    }

    private static void logError(String message, Exception error) {
        Logger.error(message, error);
        hasLogEntries = true;
    }

    private static Boolean isTriggerBypassed() {
        Automation_Setting_Trigger__c triggerSetting = Automation_Setting_Trigger__c.getInstance();
        return triggerSetting != null && triggerSetting.disableAll__c;
    }
}