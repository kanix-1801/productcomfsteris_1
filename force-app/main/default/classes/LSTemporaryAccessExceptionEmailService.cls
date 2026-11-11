/**
 * GCL-95 - Life Science emails for TemporaryAccessException__c.
 * Healthcare notifications stay in TemporaryAccessExceptionEmailService.
 * A request is Life Science when Created By user's profile is Life Sciences Sales,
 * the same profile that starts the Life Science approval flow.
 *
 * Templates already in the LS Temporary Access folder:
 * LS_Temporary_Access_Granted, LS_Temporary_Access_Rejected, LS_Temporary_Access_Expired,
 * LS_Temporary_Access_Coverage_Granted, LS_Temporary_Access_Coverage_Revoked.
 * No request Word file was supplied, so the approval-needed email uses the built-in body.
 */
public without sharing class LSTemporaryAccessExceptionEmailService {

    public static final String LIFE_SCIENCE_SALES_PROFILE = 'Life Sciences Sales';
    public static final String TYPE_APPROVAL_NEEDED = 'ApprovalNeeded';
    public static final String TYPE_APPROVED = 'Approved';
    public static final String TYPE_REJECTED = 'Rejected';
    public static final String TYPE_EXPIRED = 'Expired';
    public static final String TYPE_EXPIRING = 'Expiring';
    public static final String TYPE_COVERAGE_GRANTED = 'CoverageGranted';
    public static final String TYPE_COVERAGE_REVOKED = 'CoverageRevoked';
    public static final String TYPE_REMINDER = 'Reminder';

    public static final String SUBJECT_APPROVAL_NEEDED = 'Action Required: Temporary Salesforce Access Approval Needed';
    public static final String SUBJECT_GRANTED = 'Temporary Salesforce Access Granted';
    public static final String SUBJECT_REJECTED = 'Temporary Salesforce Access Rejected';
    public static final String SUBJECT_EXPIRED = 'Temporary Salesforce Access has Expired';
    public static final String SUBJECT_EXPIRING = 'Temporary Salesforce Access Expiring';
    public static final String SUBJECT_COVERAGE_GRANTED = 'Temporary Coverage Access Granted';
    public static final String SUBJECT_COVERAGE_REVOKED = 'Temporary Coverage Access Revoked';
    public static final String SUBJECT_REMINDER = 'Reminder: Action Required: Temporary Salesforce Access Approval Needed';

    private static final String TEMPLATE_APPROVAL_NEEDED = 'LS_Temporary_Access_Approval_Needed';
    private static final String TEMPLATE_GRANTED = 'LS_Temporary_Access_Granted';
    private static final String TEMPLATE_REJECTED = 'LS_Temporary_Access_Rejected';
    private static final String TEMPLATE_EXPIRED = 'LS_Temporary_Access_Expired';
    private static final String TEMPLATE_EXPIRING = 'LS_Temporary_Access_Expiring';
    private static final String TEMPLATE_COVERAGE_GRANTED = 'LS_Temporary_Access_Coverage_Granted';
    private static final String TEMPLATE_COVERAGE_REVOKED = 'LS_Temporary_Access_Coverage_Revoked';

    @TestVisible
    private static Boolean skipSendForTest = false;

    /**
     * Set true only while the nightly batch updates Status to Active or Expired.
     * The record-triggered flow still runs, but this stops a second email and
     * keeps the batch inside the email-invocation limit. The batch sends those
     * emails in one call after the update.
     */
    public static Boolean suppressInvocableSend = false;

    private static Map<String, Id> templateIdByDeveloperName;
    private static Map<Id, User> delegatedApproversById = new Map<Id, User>();
    @TestVisible
    private static Boolean fromAddressLoaded = false;
    @TestVisible
    private static Id fromAddressId;

    public class NotificationInput {
        @InvocableVariable(required=true label='Temporary Access Exception Id')
        public String temporaryAccessExceptionId;
        @InvocableVariable(required=true label='Notification Type')
        public String notificationType;
    }

    public class ComposedNotification {
        public Id toUserId;
        public List<String> ccAddresses;
        public String subject;
        public String htmlBody;
    }

    /**
     * Called by LS_Temporary_Access_Send_Notification from the Life Science approval flow.
     * Exceptions are logged and not rethrown so a mail failure does not stop approval.
     */
    @InvocableMethod(
        label='Send LS Temporary Access Notification'
        description='GCL-95. Sends the Life Science approval-needed, granted, or rejected email.'
        category='Life Science'
    )
    public static void sendNotification(List<NotificationInput> inputs) {
        if (suppressInvocableSend) {
            return;
        }
        try {
            if (inputs == null || inputs.isEmpty()) {
                return;
            }
            Map<String, List<Id>> idsByType = new Map<String, List<Id>>();
            for (NotificationInput input : inputs) {
                if (input == null || String.isBlank(input.temporaryAccessExceptionId) || String.isBlank(input.notificationType)) {
                    continue;
                }
                if (!idsByType.containsKey(input.notificationType)) {
                    idsByType.put(input.notificationType, new List<Id>());
                }
                idsByType.get(input.notificationType).add((Id) input.temporaryAccessExceptionId);
            }
            for (String notificationType : idsByType.keySet()) {
                send(idsByType.get(notificationType), notificationType);
            }
        } catch (Exception e) {
            Logger.error('LSTemporaryAccessExceptionEmailService.sendNotification', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * Nightly batch, start date. Renders LS_Temporary_Access_Coverage_Granted.
     */
    public static void sendCoverageGranted(List<Id> temporaryAccessExceptionIds) {
        send(temporaryAccessExceptionIds, TYPE_COVERAGE_GRANTED);
    }

    /**
     * Nightly batch, end date. Renders LS_Temporary_Access_Expired.
     */
    public static void sendExpired(List<Id> temporaryAccessExceptionIds) {
        send(temporaryAccessExceptionIds, TYPE_EXPIRED);
    }

    /**
     * Nightly batch, end date. Renders LS_Temporary_Access_Coverage_Revoked.
     */
    public static void sendCoverageRevoked(List<Id> temporaryAccessExceptionIds) {
        send(temporaryAccessExceptionIds, TYPE_COVERAGE_REVOKED);
    }

    /**
     * GCL-102 AC5. Reminder to the Rep Needing Coverage's manager and Delegated Approver.
     */
    public static void sendReminder(List<Id> temporaryAccessExceptionIds) {
        send(temporaryAccessExceptionIds, TYPE_REMINDER);
    }

    /**
     * @return Ids whose Created By user is on the Life Sciences Sales profile.
     *         Healthcare rows are not returned, so their existing emails are unchanged.
     */
    public static Set<Id> filterLifeScienceRequestIds(Set<Id> temporaryAccessExceptionIds) {
        Set<Id> lifeScienceIds = new Set<Id>();
        if (temporaryAccessExceptionIds == null || temporaryAccessExceptionIds.isEmpty()) {
            return lifeScienceIds;
        }
        for (TemporaryAccessException__c row : [
            SELECT Id
            FROM TemporaryAccessException__c
            WHERE Id IN :temporaryAccessExceptionIds
              AND CreatedBy.Profile.Name = :LIFE_SCIENCE_SALES_PROFILE
        ]) {
            lifeScienceIds.add(row.Id);
        }
        return lifeScienceIds;
    }

    /** Builds the emails for one notification type without sending them. */
    @TestVisible
    private static List<ComposedNotification> buildNotifications(List<Id> temporaryAccessExceptionIds, String notificationType) {
        List<ComposedNotification> notifications = new List<ComposedNotification>();
        if (temporaryAccessExceptionIds == null || temporaryAccessExceptionIds.isEmpty() || String.isBlank(notificationType)) {
            return notifications;
        }
        Map<String, Id> templateIds = loadTemplateIds();
        String templateName = templateDeveloperName(notificationType);
        Id templateId = templateName == null ? null : templateIds.get(templateName);

        List<TemporaryAccessException__c> rows = queryRows(new Set<Id>(temporaryAccessExceptionIds));
        loadDelegatedApprovers(rows);
        Map<Id, List<String>> territoryNumbersByRequestId = safeTerritoryNumbersByRequest(rows);
        for (TemporaryAccessException__c row : rows) {
            List<String> territoryNumbers = territoryNumbersByRequestId.containsKey(row.Id)
                ? territoryNumbersByRequestId.get(row.Id)
                : new List<String>();
            List<ComposedNotification> rowNotifications = compose(row, notificationType, territoryNumbers);
            if (templateId != null) {
                applyTemplate(rowNotifications, templateId, row.Id);
            }
            for (ComposedNotification notification : rowNotifications) {
                notification.htmlBody = applyTerritoryNumbers(notification.htmlBody, territoryNumbers);
            }
            notifications.addAll(rowNotifications);
        }
        return notifications;
    }

    /** Sends the composed emails. Skipped in tests when skipSendForTest is true. */
    private static void send(List<Id> temporaryAccessExceptionIds, String notificationType) {
        List<ComposedNotification> notifications = buildNotifications(temporaryAccessExceptionIds, notificationType);
        if (notifications.isEmpty()) {
            return;
        }
        if (Test.isRunningTest() && skipSendForTest) {
            return;
        }
        Id orgWideFromId = noReplyOrgWideEmailId();
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (ComposedNotification notification : notifications) {
            if (notification.toUserId == null || String.isBlank(notification.subject) || String.isBlank(notification.htmlBody)) {
                continue;
            }
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTargetObjectId(notification.toUserId);
            mail.setTreatTargetObjectAsRecipient(true);
            mail.setSubject(notification.subject);
            mail.setHtmlBody(notification.htmlBody);
            mail.setSaveAsActivity(false);
            if (notification.ccAddresses != null && !notification.ccAddresses.isEmpty()) {
                mail.setCcAddresses(notification.ccAddresses);
            }
            if (orgWideFromId != null) {
                mail.setOrgWideEmailAddressId(orgWideFromId);
            }
            messages.add(mail);
        }
        if (messages.isEmpty()) {
            return;
        }
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages, false);
        logSendResults(messages, results);
    }

    /**
     * The approval flow sends this email from a background step, which runs as
     * Automated Process. That user has no email address, so Salesforce drops the
     * message unless a verified org-wide From address is set.
     */
    private static Id noReplyOrgWideEmailId() {
        if (fromAddressLoaded) {
            return fromAddressId;
        }
        fromAddressLoaded = true;
        Id displayNameMatch;
        for (OrgWideEmailAddress row : [
            SELECT Id, Address, DisplayName
            FROM OrgWideEmailAddress
            WHERE IsVerified = true
              AND IsAllowAllProfiles = true
              AND (Address = 'no-reply@steris.com' OR DisplayName = 'no-reply@steris.com')
        ]) {
            if (row.Address == 'no-reply@steris.com') {
                fromAddressId = row.Id;
                return fromAddressId;
            }
            if (displayNameMatch == null && row.DisplayName == 'no-reply@steris.com') {
                displayNameMatch = row.Id;
            }
        }
        fromAddressId = displayNameMatch;
        if (fromAddressId == null) {
            Logger.warn(
                'LSTemporaryAccessExceptionEmailService: no verified no-reply org-wide email address. ' +
                'Life Science emails sent by the approval flow will not be delivered.'
            );
        }
        return fromAddressId;
    }

    /** Logs each failed send. A failed result does not throw when allOrNone is false. */
    private static void logSendResults(
        List<Messaging.SingleEmailMessage> messages,
        Messaging.SendEmailResult[] results
    ) {
        if (results == null) {
            return;
        }
        Boolean failed = false;
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i] != null && results[i].isSuccess()) {
                continue;
            }
            failed = true;
            Id toUserId = messages != null && i < messages.size() ? messages[i].getTargetObjectId() : null;
            Logger.error(
                'LSTemporaryAccessExceptionEmailService.send failed toUserId=' + toUserId + ' ' +
                formatSendErrors(results[i])
            );
        }
        if (failed) {
            Logger.saveLog();
        }
    }

    private static String formatSendErrors(Messaging.SendEmailResult result) {
        if (result == null || result.getErrors().isEmpty()) {
            return 'Unknown error';
        }
        List<String> details = new List<String>();
        for (Messaging.SendEmailError error : result.getErrors()) {
            details.add(String.valueOf(error.getStatusCode()) + ' ' + error.getMessage());
        }
        return String.join(details, '; ');
    }

    /** Loads the request fields used by every Life Science email. */
    private static List<TemporaryAccessException__c> queryRows(Set<Id> temporaryAccessExceptionIds) {
        return [
            SELECT Id, Name, StartDate__c, EndDate__c, Duration__c, ExceptionCategory__c,
                   BusinessJustification__c, ApprovalComments__c, RequesterName__c, CoverageRepName__c,
                   Requester__c, CoverageRep__c, CreatedById,
                   Requester__r.Email, Requester__r.IsActive, Requester__r.ManagerId,
                   Requester__r.Manager.FirstName, Requester__r.Manager.Email, Requester__r.Manager.IsActive,
                   Requester__r.Manager.DelegatedApproverId,
                   CoverageRep__r.Email, CoverageRep__r.IsActive,
                   CoverageRep__r.ManagerId, CoverageRep__r.Manager.FirstName,
                   CoverageRep__r.Manager.Email, CoverageRep__r.Manager.IsActive,
                   CoverageRep__r.Manager.DelegatedApproverId,
                   CreatedBy.Email, CreatedBy.IsActive, CreatedBy.FirstName, CreatedBy.Name
            FROM TemporaryAccessException__c
            WHERE Id IN :temporaryAccessExceptionIds
        ];
    }

    /** Chooses the recipient list and body for one notification type. */
    private static List<ComposedNotification> compose(
        TemporaryAccessException__c row,
        String notificationType,
        List<String> territoryNumbers
    ) {
        if (notificationType == TYPE_APPROVAL_NEEDED) {
            return composeApproval(row, territoryNumbers, false);
        }
        if (notificationType == TYPE_APPROVED) {
            return composeForPersonas(row, SUBJECT_GRANTED, grantedBody(row, territoryNumbers));
        }
        if (notificationType == TYPE_REJECTED) {
            return composeForPersonas(row, SUBJECT_REJECTED, rejectedBody(row, territoryNumbers));
        }
        if (notificationType == TYPE_EXPIRED) {
            return composeForPersonas(row, SUBJECT_EXPIRED, expiredBody(row, territoryNumbers));
        }
        if (notificationType == TYPE_REMINDER) {
            return composeApproval(row, territoryNumbers, true);
        }
        if (notificationType == TYPE_EXPIRING) {
            return composeForPersonas(row, SUBJECT_EXPIRING, expiringBody(row, territoryNumbers));
        }
        if (notificationType == TYPE_COVERAGE_GRANTED) {
            return composeForPersonas(row, SUBJECT_COVERAGE_GRANTED, coverageGrantedBody(row, territoryNumbers));
        }
        if (notificationType == TYPE_COVERAGE_REVOKED) {
            return composeForPersonas(row, SUBJECT_COVERAGE_REVOKED, coverageRevokedBody(row, territoryNumbers));
        }
        Logger.warn(
            'LSTemporaryAccessExceptionEmailService.compose: unknown notificationType=' + notificationType +
            ' taeId=' + row.Id
        );
        return new List<ComposedNotification>();
    }

    /**
     * Every Life Science template uses the same people.
     * To: the Coverage Rep's manager.
     * CC: the Rep Needing Coverage, the Coverage Rep, and Created By when that user is
     * neither of those two. The 7-day reminder uses the same list.
     */
    private static List<ComposedNotification> composeApproval(
        TemporaryAccessException__c row,
        List<String> territoryNumbers,
        Boolean reminderOnly
    ) {
        User approver = row.CoverageRep__r == null ? null : row.CoverageRep__r.Manager;
        return composeForPersonas(
            row,
            reminderOnly ? SUBJECT_REMINDER : SUBJECT_APPROVAL_NEEDED,
            approvalNeededBody(row, approver, territoryNumbers)
        );
    }

    /** Sends one email to the Coverage Rep's manager and copies the request personas. */
    private static List<ComposedNotification> composeForPersonas(
        TemporaryAccessException__c row,
        String subject,
        String htmlBody
    ) {
        if (managerUserId(row.CoverageRep__r) == null) {
            Logger.warn(
                'LSTemporaryAccessExceptionEmailService: no active manager on the Coverage Rep, so no email was addressed. ' +
                'subject=' + subject + ' taeId=' + row.Id
            );
        }
        return deliver(
            new List<Recipient>{ managerRecipient(row.CoverageRep__r) },
            personaCopies(row),
            subject,
            htmlBody
        );
    }

    /** Rep Needing Coverage, Coverage Rep, and Created By when that user is a different person. */
    private static List<Recipient> personaCopies(TemporaryAccessException__c row) {
        List<Recipient> copies = new List<Recipient>{
            userRecipient(row.Requester__c, row.Requester__r),
            userRecipient(row.CoverageRep__c, row.CoverageRep__r)
        };
        if (row.CreatedById != null && row.CreatedById != row.Requester__c && row.CreatedById != row.CoverageRep__c) {
            copies.add(userRecipient(row.CreatedById, row.CreatedBy));
        }
        return copies;
    }

    /** Sends one email per To recipient and copies the remaining people. */
    private static List<ComposedNotification> deliver(
        List<Recipient> toRecipients,
        List<Recipient> copyRecipients,
        String subject,
        String htmlBody
    ) {
        List<ComposedNotification> notifications = new List<ComposedNotification>();
        Set<Id> seen = new Set<Id>();
        for (Recipient recipient : toRecipients) {
            if (!isActiveRecipient(recipient) || seen.contains(recipient.userId)) {
                continue;
            }
            seen.add(recipient.userId);
            ComposedNotification notification = new ComposedNotification();
            notification.toUserId = recipient.userId;
            notification.subject = subject;
            notification.htmlBody = htmlBody;
            notification.ccAddresses = ccAddresses(recipient.email, copyRecipients);
            notifications.add(notification);
        }
        return notifications;
    }

    private class Recipient {
        Id userId;
        String email;
        Boolean isActive;
    }

    /** Wraps a user as an email recipient. */
    private static Recipient userRecipient(Id userId, User user) {
        Recipient value = new Recipient();
        value.userId = userId;
        value.email = user == null ? null : user.Email;
        value.isActive = user != null && user.IsActive == true;
        return value;
    }

    /** Wraps the rep's active manager as an email recipient. */
    private static Recipient managerRecipient(User rep) {
        Recipient value = new Recipient();
        value.userId = managerUserId(rep);
        value.email = managerEmail(rep);
        value.isActive = value.userId != null;
        return value;
    }

    /** True when the recipient is an active user with an email address. */
    private static Boolean isActiveRecipient(Recipient recipient) {
        return recipient != null && recipient.userId != null && recipient.isActive == true && String.isNotBlank(recipient.email);
    }

    /** Returns the rep's manager Id when that manager is active. */
    private static Id managerUserId(User rep) {
        if (rep == null || rep.ManagerId == null || rep.Manager == null || rep.Manager.IsActive != true) {
            return null;
        }
        return rep.ManagerId;
    }

    /** Returns the active manager's email address. */
    private static String managerEmail(User rep) {
        return managerUserId(rep) == null ? null : rep.Manager.Email;
    }

    /** Builds the CC list, skipping the To address and duplicate addresses. */
    private static List<String> ccAddresses(String toEmail, List<Recipient> recipients) {
        List<String> addresses = new List<String>();
        Set<String> seen = new Set<String>();
        String toKey = String.isBlank(toEmail) ? null : toEmail.toLowerCase();
        for (Recipient recipient : recipients) {
            if (!isActiveRecipient(recipient)) {
                continue;
            }
            String key = recipient.email.toLowerCase();
            if (key == toKey || seen.contains(key)) {
                continue;
            }
            seen.add(key);
            addresses.add(recipient.email);
        }
        return addresses;
    }

    /** Replaces the built-in subject and body with the stored email template. */
    private static void applyTemplate(List<ComposedNotification> notifications, Id templateId, Id whatId) {
        if (notifications.isEmpty()) {
            return;
        }
        try {
            Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
                templateId,
                notifications[0].toUserId,
                whatId
            );
            for (ComposedNotification notification : notifications) {
                if (String.isNotBlank(rendered.getSubject())) {
                    notification.subject = rendered.getSubject();
                }
                if (String.isNotBlank(rendered.getHtmlBody())) {
                    notification.htmlBody = absoluteRecordLinks(rendered.getHtmlBody(), whatId);
                }
            }
        } catch (Exception e) {
            Logger.warn(
                'LSTemporaryAccessExceptionEmailService.applyTemplate: using built-in body for taeId=' +
                whatId + ' ' + e.getMessage()
            );
        }
    }

    /**
     * $Api.Partner_Server_URL_500 can be blank when the nightly batch renders a template,
     * which leaves href="<record Id>". Those links are rewritten to the full record URL.
     */
    @TestVisible
    private static String absoluteRecordLinks(String htmlBody, Id whatId) {
        if (String.isBlank(htmlBody) || whatId == null) {
            return htmlBody;
        }
        String fullUrl = 'href="' + recordUrl(whatId) + '"';
        return htmlBody
            .replace('href="' + String.valueOf(whatId) + '"', fullUrl)
            .replace('href="/' + String.valueOf(whatId) + '"', fullUrl);
    }

    /** Loads the Life Science email template Ids once per transaction. */
    private static Map<String, Id> loadTemplateIds() {
        if (templateIdByDeveloperName == null) {
            templateIdByDeveloperName = new Map<String, Id>();
            for (EmailTemplate template : [
                SELECT Id, DeveloperName
                FROM EmailTemplate
                WHERE DeveloperName IN :new Set<String>{
                    TEMPLATE_APPROVAL_NEEDED, TEMPLATE_GRANTED, TEMPLATE_REJECTED, TEMPLATE_EXPIRED,
                    TEMPLATE_EXPIRING, TEMPLATE_COVERAGE_GRANTED, TEMPLATE_COVERAGE_REVOKED
                }
            ]) {
                templateIdByDeveloperName.put(template.DeveloperName, template.Id);
            }
        }
        return templateIdByDeveloperName;
    }

    /** Returns the template name for a notification type, or null when Apex builds the body. */
    private static String templateDeveloperName(String notificationType) {
        if (notificationType == TYPE_APPROVAL_NEEDED || notificationType == TYPE_REMINDER) {
            return TEMPLATE_APPROVAL_NEEDED;
        }
        if (notificationType == TYPE_APPROVED) {
            return TEMPLATE_GRANTED;
        }
        if (notificationType == TYPE_REJECTED) {
            return TEMPLATE_REJECTED;
        }
        if (notificationType == TYPE_EXPIRED) {
            return TEMPLATE_EXPIRED;
        }
        if (notificationType == TYPE_EXPIRING) {
            return TEMPLATE_EXPIRING;
        }
        if (notificationType == TYPE_COVERAGE_GRANTED) {
            return TEMPLATE_COVERAGE_GRANTED;
        }
        if (notificationType == TYPE_COVERAGE_REVOKED) {
            return TEMPLATE_COVERAGE_REVOKED;
        }
        return null;
    }

    /** Builds the approval-request body, including the 7-day reminder. */
    private static String approvalNeededBody(
        TemporaryAccessException__c row,
        User approver,
        List<String> territoryNumbers
    ) {
        String approverName = approver == null ? '' : approver.FirstName;
        return '<p>' + escapeHtml(approverName) + ',</p>' +
            '<p>A request has been submitted for temporary Salesforce access and requires your approval.</p>' +
            '<p>To approve or reject, please review the request <a href="' + recordUrl(row.Id) + '">here</a>.</p>' +
            detailTable(row, 'Created By', createdByName(row), territoryNumbers) +
            supportFooter();
    }

    /** Builds the body for the email sent three days before the End Date. */
    private static String expiringBody(TemporaryAccessException__c row, List<String> territoryNumbers) {
        return '<p>' + escapeHtml(coverageManagerFirstName(row)) + ',</p>' +
            '<p>Temporary Salesforce access is expiring in 3 days for the below request.</p>' +
            '<p>If coverage needs to be extended, please <a href="' + recordUrl(row.Id) + '">submit a new request</a>.</p>' +
            detailTable(row, 'Created By', createdByName(row), territoryNumbers) +
            supportFooter();
    }

    /** Returns the active user named in the manager's Delegated Approver field. */
    private static Recipient delegatedApproverRecipient(User approver) {
        Recipient value = new Recipient();
        if (approver == null || approver.DelegatedApproverId == null) {
            return value;
        }
        User delegate = delegatedApproversById.get(approver.DelegatedApproverId);
        if (delegate == null || delegate.IsActive != true) {
            return value;
        }
        value.userId = delegate.Id;
        value.email = delegate.Email;
        value.isActive = true;
        return value;
    }

    /**
     * User.DelegatedApproverId can point to a User or a Group and has no SOQL relationship,
     * so delegate users are loaded separately. Group delegates are not copied.
     */
    private static void loadDelegatedApprovers(List<TemporaryAccessException__c> rows) {
        Set<Id> delegateIds = new Set<Id>();
        for (TemporaryAccessException__c row : rows) {
            Id delegateId = row.CoverageRep__r == null || row.CoverageRep__r.Manager == null
                ? null
                : row.CoverageRep__r.Manager.DelegatedApproverId;
            if (delegateId != null && delegateId.getSObjectType() == User.SObjectType) {
                delegateIds.add(delegateId);
            }
        }
        delegatedApproversById = delegateIds.isEmpty()
            ? new Map<Id, User>()
            : new Map<Id, User>([SELECT Id, Email, IsActive FROM User WHERE Id IN :delegateIds]);
    }

    /** Builds the Temporary Salesforce Access Granted body. */
    private static String grantedBody(TemporaryAccessException__c row, List<String> territoryNumbers) {
        return '<p>' + escapeHtml(coverageManagerFirstName(row)) + ',</p>' +
            '<p>Temporary Salesforce access has been approved for the following request:</p>' +
            detailTable(row, 'Created By', createdByName(row), territoryNumbers) +
            '<p>Access will automatically expire on ' + formatDate(row.EndDate__c) +
            ' unless an extension is requested <a href="' + recordUrl(row.Id) + '">here</a>.</p>' +
            supportFooter();
    }

    /** Builds the Temporary Salesforce Access Rejected body. */
    private static String rejectedBody(TemporaryAccessException__c row, List<String> territoryNumbers) {
        return '<p>' + escapeHtml(coverageManagerFirstName(row)) + ',</p>' +
            '<p>Temporary Salesforce access has been rejected for the following request:</p>' +
            detailTable(row, 'Created By', createdByName(row), territoryNumbers) +
            '<p>Please reach out to your manager with any questions or concerns.</p>' +
            supportFooter();
    }

    /** Builds the Temporary Salesforce Access has Expired body. */
    private static String expiredBody(TemporaryAccessException__c row, List<String> territoryNumbers) {
        return '<p>' + escapeHtml(coverageManagerFirstName(row)) + ',</p>' +
            '<p>Temporary coverage access has expired and access has been removed for the following request:</p>' +
            detailTable(row, 'Request Created By', createdByName(row), territoryNumbers) +
            supportFooter();
    }

    /** Builds the Temporary Coverage Access Granted body. */
    private static String coverageGrantedBody(TemporaryAccessException__c row, List<String> territoryNumbers) {
        return '<p>Hi,</p>' +
            '<p>Based on the Temporary Access Exception: ' + escapeHtml(row.Name) +
            ' approval initiated by Requester: ' + escapeHtml(row.RequesterName__c) +
            ' for Coverage Rep: ' + escapeHtml(row.CoverageRepName__c) + '</p>' +
            '<p>Expiry Date: ' + formatDate(row.EndDate__c) + '</p>' +
            territorySection(true, territoryNumbers) +
            '<p>Temporary coverage access has been granted and will remain active until the expiry date above.</p>' +
            '<p>Please contact the Life Sciences Sales support team at lsprojects@steris.com with any questions.</p>' +
            '<p>Thanks</p>';
    }

    /** Builds the Temporary Coverage Access Revoked body. */
    private static String coverageRevokedBody(TemporaryAccessException__c row, List<String> territoryNumbers) {
        return '<p>Hi,</p>' +
            '<p>Based on the Temporary Access Exception: ' + escapeHtml(row.Name) +
            ' approval initiated by Requester: ' + escapeHtml(row.RequesterName__c) +
            ' for Coverage Rep: ' + escapeHtml(row.CoverageRepName__c) + '</p>' +
            '<p>Expiry Date: ' + formatDate(row.EndDate__c) + '</p>' +
            territorySection(false, territoryNumbers) +
            '<p>Temporary coverage access has been revoked due to the expiration of the Temporary Access Exception request mentioned above.</p>' +
            '<p>Please contact the Life Sciences Sales support team at lsprojects@steris.com with any questions.</p>' +
            '<p>Thanks</p>';
    }

    /** Builds the request detail table, including Territory Number(s). */
    private static String detailTable(
        TemporaryAccessException__c row,
        String createdByLabel,
        String createdByName,
        List<String> territoryNumbers
    ) {
        return '<table border="1" cellpadding="6" cellspacing="0">' +
            rowHtml('Temporary Request ID', '<a href="' + recordUrl(row.Id) + '">' + escapeHtml(row.Name) + '</a>') +
            rowHtml('Rep Needing Coverage', escapeHtml(row.RequesterName__c)) +
            rowHtml('Coverage Rep', escapeHtml(row.CoverageRepName__c)) +
            rowHtml(createdByLabel, escapeHtml(createdByName)) +
            rowHtml('Exception Category', escapeHtml(row.ExceptionCategory__c)) +
            rowHtml('Business Justification', escapeHtml(row.BusinessJustification__c)) +
            rowHtml('Start Date', formatDate(row.StartDate__c)) +
            rowHtml('End Date', formatDate(row.EndDate__c)) +
            rowHtml('Coverage Duration', row.Duration__c == null ? '' : String.valueOf(row.Duration__c.intValue())) +
            rowHtml('Territory Number(s)', territoryListText(territoryNumbers)) +
            '</table>';
    }

    /**
     * Territory Number is OrderLineContact__c.TerritoryNumber__c. Life Science rows on a covered
     * account usually have a blank Assigned Sales Rep, so the account is taken from
     * TAE_AssignedRecord__c and matched to OrderLineContact__c.TASAddressId__c. Rows whose
     * Assigned Sales Rep is the Rep Needing Coverage are included as well.
     */
    private static Map<Id, List<String>> territoryNumbersByRequest(List<TemporaryAccessException__c> rows) {
        Map<Id, Set<String>> numbersByRequest = new Map<Id, Set<String>>();
        Map<Id, Id> requesterByRequest = new Map<Id, Id>();
        Set<Id> requestIds = new Set<Id>();
        for (TemporaryAccessException__c row : rows) {
            if (row.Id == null) {
                continue;
            }
            requestIds.add(row.Id);
            numbersByRequest.put(row.Id, new Set<String>());
            if (row.Requester__c != null) {
                requesterByRequest.put(row.Id, row.Requester__c);
            }
        }

        Map<String, Set<Id>> requestIdsByAccountKey = new Map<String, Set<Id>>();
        if (!requestIds.isEmpty()) {
            for (TAE_AssignedRecord__c assigned : queryAssignedRecords(requestIds)) {
                Id accountId = assigned.Account__c;
                if (accountId == null && assigned.Opportunity__r != null) {
                    accountId = assigned.Opportunity__r.AccountId;
                }
                if (accountId != null) {
                    addAccountKey(requestIdsByAccountKey, accountId, assigned.TemporaryAccessException__c);
                }
            }
        }
        if (!requestIdsByAccountKey.isEmpty()) {
            for (OrderLineContact__c assignment : queryTerritoryByAddressIds(requestIdsByAccountKey.keySet())) {
                addTerritoryNumber(
                    numbersByRequest,
                    requestIdsByAccountKey.get(assignment.TASAddressId__c),
                    assignment.TerritoryNumber__c
                );
            }
        }

        Map<Id, Set<Id>> requestIdsByRequester = new Map<Id, Set<Id>>();
        for (Id requestId : requesterByRequest.keySet()) {
            Id requesterId = requesterByRequest.get(requestId);
            if (!requestIdsByRequester.containsKey(requesterId)) {
                requestIdsByRequester.put(requesterId, new Set<Id>());
            }
            requestIdsByRequester.get(requesterId).add(requestId);
        }
        if (!requestIdsByRequester.isEmpty()) {
            for (OrderLineContact__c assignment : queryTerritoryByRepIds(requestIdsByRequester.keySet())) {
                addTerritoryNumber(
                    numbersByRequest,
                    requestIdsByRequester.get(assignment.AssignedSalesRep__c),
                    assignment.TerritoryNumber__c
                );
            }
        }

        Map<Id, List<String>> sortedByRequest = new Map<Id, List<String>>();
        for (Id requestId : numbersByRequest.keySet()) {
            List<String> territoryNumbers = new List<String>(numbersByRequest.get(requestId));
            territoryNumbers.sort();
            sortedByRequest.put(requestId, territoryNumbers);
        }
        return sortedByRequest;
    }

    private static List<TAE_AssignedRecord__c> queryAssignedRecords(Set<Id> requestIds) {
        return [
            SELECT TemporaryAccessException__c, Account__c, Opportunity__r.AccountId
            FROM TAE_AssignedRecord__c
            WHERE TemporaryAccessException__c IN :requestIds
        ];
    }

    private static List<OrderLineContact__c> queryTerritoryByAddressIds(Set<String> addressIds) {
        return [
            SELECT TASAddressId__c, TerritoryNumber__c
            FROM OrderLineContact__c
            WHERE TASAddressId__c IN :addressIds
              AND TerritoryNumber__c != null
        ];
    }

    private static List<OrderLineContact__c> queryTerritoryByRepIds(Set<Id> repIds) {
        return [
            SELECT AssignedSalesRep__c, TerritoryNumber__c
            FROM OrderLineContact__c
            WHERE AssignedSalesRep__c IN :repIds
              AND TerritoryNumber__c != null
        ];
    }

    /**
     * Territory numbers are supporting detail. If the lookup fails, log it and still send the email
     * without territory rows, so the approval notice is not lost.
     */
    private static Map<Id, List<String>> safeTerritoryNumbersByRequest(List<TemporaryAccessException__c> rows) {
        try {
            return territoryNumbersByRequest(rows);
        } catch (Exception e) {
            Logger.error('LSTemporaryAccessExceptionEmailService.territoryNumbersByRequest', e);
            return new Map<Id, List<String>>();
        }
    }

    /** Indexes a covered account by both its 15-character and 18-character Id. */
    private static void addAccountKey(Map<String, Set<Id>> requestIdsByAccountKey, Id accountId, Id requestId) {
        String accountKey = String.valueOf(accountId);
        List<String> keys = new List<String>{ accountKey, accountKey.left(15) };
        for (String key : keys) {
            if (!requestIdsByAccountKey.containsKey(key)) {
                requestIdsByAccountKey.put(key, new Set<Id>());
            }
            requestIdsByAccountKey.get(key).add(requestId);
        }
    }

    /** Adds one distinct territory number to each related request. */
    private static void addTerritoryNumber(
        Map<Id, Set<String>> numbersByRequest,
        Set<Id> requestIds,
        String territoryNumber
    ) {
        if (requestIds == null || String.isBlank(territoryNumber)) {
            return;
        }
        String trimmed = territoryNumber.trim();
        if (String.isBlank(trimmed)) {
            return;
        }
        for (Id requestId : requestIds) {
            if (!numbersByRequest.containsKey(requestId)) {
                numbersByRequest.put(requestId, new Set<String>());
            }
            numbersByRequest.get(requestId).add(trimmed);
        }
    }

    @TestVisible
    private static String applyTerritoryNumbers(String htmlBody, List<String> territoryNumbers) {
        if (htmlBody == null) {
            return null;
        }
        return htmlBody
            .replace('{{LS_TERRITORY_ROWS}}', territoryTableRows(territoryNumbers))
            .replace('{{LS_TERRITORY_NUMBERS}}', territoryListText(territoryNumbers));
    }

    /** Builds the territory table used when the email template is not applied. */
    private static String territorySection(Boolean isGrant, List<String> territoryNumbers) {
        String action = isGrant ? 'assigned' : 'revoked';
        return '<p>The following Territory Number(s) have been ' + action + ':</p>' +
            '<table border="1" cellpadding="6" cellspacing="0">' +
            '<tr><th>S.No</th><th>Territory Number</th></tr>' +
            territoryTableRows(territoryNumbers) +
            '</table>';
    }

    /** Builds one table row per territory number. */
    private static String territoryTableRows(List<String> territoryNumbers) {
        if (territoryNumbers == null || territoryNumbers.isEmpty()) {
            return '';
        }
        String rows = '';
        Integer serialNumber = 1;
        for (String territoryNumber : territoryNumbers) {
            rows += '<tr><td style="text-align:left;">' + serialNumber + '</td><td style="text-align:left;">' +
                escapeHtml(territoryNumber) + '</td></tr>';
            serialNumber++;
        }
        return rows;
    }

    /** Joins territory numbers for the single Territory Number(s) cell. */
    private static String territoryListText(List<String> territoryNumbers) {
        if (territoryNumbers == null || territoryNumbers.isEmpty()) {
            return '';
        }
        List<String> escaped = new List<String>();
        for (String territoryNumber : territoryNumbers) {
            escaped.add(escapeHtml(territoryNumber));
        }
        return String.join(escaped, ', ');
    }

    /** Builds one label and value row for a detail table. */
    private static String rowHtml(String label, String value) {
        return '<tr><td>' + label + '</td><td>' + value + '</td></tr>';
    }

    /** Builds the Life Sciences support footer. */
    private static String supportFooter() {
        return '<p>This message was auto-generated by Salesforce. If you need further assistance, please reach out to <a href="mailto:lsprojects@steris.com">lsprojects@steris.com</a></p>';
    }

    /** Returns the Coverage Rep's manager first name, the person every template is sent to. */
    private static String coverageManagerFirstName(TemporaryAccessException__c row) {
        if (row.CoverageRep__r == null || row.CoverageRep__r.Manager == null) {
            return '';
        }
        return row.CoverageRep__r.Manager.FirstName;
    }

    /** Returns the Created By user's full name. */
    private static String createdByName(TemporaryAccessException__c row) {
        return row.CreatedBy == null ? '' : row.CreatedBy.Name;
    }

    /** Returns the Lightning-relative record URL. */
    private static String recordUrl(Id recordId) {
        return URL.getOrgDomainUrl().toExternalForm() + '/' + recordId;
    }

    /** Formats a date as d-MMM-yyyy. */
    private static String formatDate(Date value) {
        if (value == null) {
            return '';
        }
        return Datetime.newInstance(value.year(), value.month(), value.day()).format('d-MMM-yyyy');
    }

    /** Escapes HTML characters in a value written into an email body. */
    private static String escapeHtml(String value) {
        if (value == null) {
            return '';
        }
        return value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
    }
}