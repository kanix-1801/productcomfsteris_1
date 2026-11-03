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

    public static final String SUBJECT_APPROVAL_NEEDED = 'Action Required: Temporary Salesforce Access Approval Needed';
    public static final String SUBJECT_GRANTED = 'Temporary Salesforce Access Granted';
    public static final String SUBJECT_REJECTED = 'Temporary Salesforce Access Rejected';
    public static final String SUBJECT_EXPIRED = 'Temporary Salesforce Access has Expired';
    public static final String SUBJECT_EXPIRING = 'Temporary Salesforce Access Expiring';
    public static final String SUBJECT_COVERAGE_GRANTED = 'Temporary Coverage Access Granted';
    public static final String SUBJECT_COVERAGE_REVOKED = 'Temporary Coverage Access Revoked';

    private static final String TEMPLATE_GRANTED = 'LS_Temporary_Access_Granted';
    private static final String TEMPLATE_REJECTED = 'LS_Temporary_Access_Rejected';
    private static final String TEMPLATE_EXPIRED = 'LS_Temporary_Access_Expired';
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
        for (TemporaryAccessException__c row : rows) {
            List<ComposedNotification> rowNotifications = compose(row, notificationType);
            if (templateId != null) {
                applyTemplate(rowNotifications, templateId, row.Id);
            }
            notifications.addAll(rowNotifications);
        }
        return notifications;
    }

    private static void send(List<Id> temporaryAccessExceptionIds, String notificationType) {
        List<ComposedNotification> notifications = buildNotifications(temporaryAccessExceptionIds, notificationType);
        if (notifications.isEmpty()) {
            return;
        }
        if (Test.isRunningTest() && skipSendForTest) {
            return;
        }
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
            messages.add(mail);
        }
        if (messages.isEmpty()) {
            return;
        }
        Messaging.sendEmail(messages, false);
    }

    private static List<TemporaryAccessException__c> queryRows(Set<Id> temporaryAccessExceptionIds) {
        return [
            SELECT Id, Name, StartDate__c, EndDate__c, Duration__c, ExceptionCategory__c,
                   BusinessJustification__c, ApprovalComments__c, RequesterName__c, CoverageRepName__c,
                   Requester__c, CoverageRep__c, CreatedById,
                   Requester__r.Email, Requester__r.IsActive, Requester__r.ManagerId,
                   Requester__r.Manager.FirstName, Requester__r.Manager.Email, Requester__r.Manager.IsActive,
                   Requester__r.Manager.DelegatedApproverId,
                   CoverageRep__r.Email, CoverageRep__r.IsActive,
                   CoverageRep__r.ManagerId, CoverageRep__r.Manager.Email, CoverageRep__r.Manager.IsActive,
                   CreatedBy.Email, CreatedBy.IsActive, CreatedBy.FirstName, CreatedBy.Name
            FROM TemporaryAccessException__c
            WHERE Id IN :temporaryAccessExceptionIds
        ];
    }

    private static List<ComposedNotification> compose(TemporaryAccessException__c row, String notificationType) {
        if (notificationType == TYPE_APPROVAL_NEEDED) {
            return composeApprovalNeeded(row);
        }
        if (notificationType == TYPE_APPROVED) {
            return composeCreatedByEmail(row, SUBJECT_GRANTED, grantedBody(row), true);
        }
        if (notificationType == TYPE_REJECTED) {
            return composeCreatedByEmail(row, SUBJECT_REJECTED, rejectedBody(row), true);
        }
        if (notificationType == TYPE_EXPIRED) {
            return composeCreatedByEmail(row, SUBJECT_EXPIRED, expiredBody(row), false);
        }
        if (notificationType == TYPE_EXPIRING) {
            return composeCreatedByEmail(row, SUBJECT_EXPIRING, expiringBody(row), false);
        }
        if (notificationType == TYPE_COVERAGE_GRANTED) {
            return composeRepEmails(row, SUBJECT_COVERAGE_GRANTED, coverageGrantedBody(row));
        }
        if (notificationType == TYPE_COVERAGE_REVOKED) {
            return composeRepEmails(row, SUBJECT_COVERAGE_REVOKED, coverageRevokedBody(row));
        }
        Logger.warn(
            'LSTemporaryAccessExceptionEmailService.compose: unknown notificationType=' + notificationType +
            ' taeId=' + row.Id
        );
        return new List<ComposedNotification>();
    }

    /**
     * GCL-95 AC1. To the approver, the Rep Needing Coverage's manager.
     * CC Created By, Rep Needing Coverage, Coverage Rep, and that manager's
     * Delegated Approver when one is active. Each person is included once.
     */
    private static List<ComposedNotification> composeApprovalNeeded(TemporaryAccessException__c row) {
        Id approverId = managerUserId(row.Requester__r);
        if (approverId == null) {
            Logger.warn('LSTemporaryAccessExceptionEmailService.composeApprovalNeeded: no manager for taeId=' + row.Id);
            return new List<ComposedNotification>();
        }
        User approver = row.Requester__r.Manager;
        ComposedNotification notification = new ComposedNotification();
        notification.toUserId = approverId;
        notification.subject = SUBJECT_APPROVAL_NEEDED;
        notification.htmlBody = approvalNeededBody(row, approver);
        notification.ccAddresses = ccAddresses(
            approver.Email,
            standardCopies(row, approver)
        );
        return new List<ComposedNotification>{ notification };
    }

    /**
     * Word templates. To Created By.
     * Granted and Rejected CC: Coverage Rep Manager, Rep Needing Coverage, Coverage Rep.
     * Expired CC: Rep Needing Coverage, Coverage Rep, Coverage Rep Manager.
     */
    private static List<ComposedNotification> composeCreatedByEmail(
        TemporaryAccessException__c row,
        String subject,
        String htmlBody,
        Boolean coverageManagerFirst
    ) {
        if (row.CreatedBy == null || row.CreatedBy.IsActive != true) {
            Logger.warn('LSTemporaryAccessExceptionEmailService.composeCreatedByEmail: creator is inactive for taeId=' + row.Id);
            return new List<ComposedNotification>();
        }
        List<Recipient> copies = coverageManagerFirst
            ? new List<Recipient>{
                managerRecipient(row.CoverageRep__r),
                userRecipient(row.Requester__c, row.Requester__r),
                userRecipient(row.CoverageRep__c, row.CoverageRep__r)
            }
            : new List<Recipient>{
                userRecipient(row.Requester__c, row.Requester__r),
                userRecipient(row.CoverageRep__c, row.CoverageRep__r),
                managerRecipient(row.CoverageRep__r)
            };
        copies.add(delegatedApproverRecipient(row.Requester__r == null ? null : row.Requester__r.Manager));
        ComposedNotification notification = new ComposedNotification();
        notification.toUserId = row.CreatedById;
        notification.subject = subject;
        notification.htmlBody = htmlBody;
        notification.ccAddresses = ccAddresses(row.CreatedBy.Email, copies);
        return new List<ComposedNotification>{ notification };
    }

    /**
     * Coverage PDF templates. One email each to the Rep Needing Coverage and the Coverage Rep,
     * the same people the Healthcare grant and revoke emails use.
     */
    private static List<ComposedNotification> composeRepEmails(
        TemporaryAccessException__c row,
        String subject,
        String htmlBody
    ) {
        List<ComposedNotification> notifications = new List<ComposedNotification>();
        Set<Id> seen = new Set<Id>();
        addDirect(notifications, seen, row.Requester__c, row.Requester__r, subject, htmlBody);
        addDirect(notifications, seen, row.CoverageRep__c, row.CoverageRep__r, subject, htmlBody);
        return notifications;
    }

    private static List<ComposedNotification> emailOtherParties(List<Recipient> parties, String htmlBody, String subject) {
        List<Recipient> activeParties = new List<Recipient>();
        Set<String> seen = new Set<String>();
        for (Recipient party : parties) {
            if (!isActiveRecipient(party)) {
                continue;
            }
            String key = party.email.toLowerCase();
            if (seen.contains(key)) {
                continue;
            }
            seen.add(key);
            activeParties.add(party);
        }
        if (activeParties.isEmpty()) {
            return new List<ComposedNotification>();
        }
        ComposedNotification notification = new ComposedNotification();
        notification.toUserId = activeParties[0].userId;
        notification.subject = subject;
        notification.htmlBody = htmlBody;
        notification.ccAddresses = new List<String>();
        for (Integer index = 1; index < activeParties.size(); index++) {
            notification.ccAddresses.add(activeParties[index].email);
        }
        return new List<ComposedNotification>{ notification };
    }

    private static void addDirect(
        List<ComposedNotification> notifications,
        Set<Id> seen,
        Id userId,
        User user,
        String subject,
        String htmlBody
    ) {
        if (userId == null || user == null || user.IsActive != true || seen.contains(userId)) {
            return;
        }
        seen.add(userId);
        ComposedNotification notification = new ComposedNotification();
        notification.toUserId = userId;
        notification.subject = subject;
        notification.htmlBody = htmlBody;
        notification.ccAddresses = new List<String>();
        notifications.add(notification);
    }

    private class Recipient {
        Id userId;
        String email;
        Boolean isActive;
    }

    private static Recipient userRecipient(Id userId, User user) {
        Recipient value = new Recipient();
        value.userId = userId;
        value.email = user == null ? null : user.Email;
        value.isActive = user != null && user.IsActive == true;
        return value;
    }

    private static Recipient managerRecipient(User rep) {
        Recipient value = new Recipient();
        value.userId = managerUserId(rep);
        value.email = managerEmail(rep);
        value.isActive = value.userId != null;
        return value;
    }

    private static Boolean isActiveRecipient(Recipient recipient) {
        return recipient != null && recipient.userId != null && recipient.isActive == true && String.isNotBlank(recipient.email);
    }

    private static Id managerUserId(User rep) {
        if (rep == null || rep.ManagerId == null || rep.Manager == null || rep.Manager.IsActive != true) {
            return null;
        }
        return rep.ManagerId;
    }

    private static String managerEmail(User rep) {
        return managerUserId(rep) == null ? null : rep.Manager.Email;
    }

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

    private static Map<String, Id> loadTemplateIds() {
        if (templateIdByDeveloperName == null) {
            templateIdByDeveloperName = new Map<String, Id>();
            for (EmailTemplate template : [
                SELECT Id, DeveloperName
                FROM EmailTemplate
                WHERE DeveloperName IN :new Set<String>{
                    TEMPLATE_GRANTED, TEMPLATE_REJECTED, TEMPLATE_EXPIRED,
                    TEMPLATE_COVERAGE_GRANTED, TEMPLATE_COVERAGE_REVOKED
                }
            ]) {
                templateIdByDeveloperName.put(template.DeveloperName, template.Id);
            }
        }
        return templateIdByDeveloperName;
    }

    private static String templateDeveloperName(String notificationType) {
        if (notificationType == TYPE_APPROVED) {
            return TEMPLATE_GRANTED;
        }
        if (notificationType == TYPE_REJECTED) {
            return TEMPLATE_REJECTED;
        }
        if (notificationType == TYPE_EXPIRED) {
            return TEMPLATE_EXPIRED;
        }
        if (notificationType == TYPE_COVERAGE_GRANTED) {
            return TEMPLATE_COVERAGE_GRANTED;
        }
        if (notificationType == TYPE_COVERAGE_REVOKED) {
            return TEMPLATE_COVERAGE_REVOKED;
        }
        return null;
    }

    private static String approvalNeededBody(TemporaryAccessException__c row, User approver) {
        String approverName = approver == null ? '' : approver.FirstName;
        return '<p>' + escapeHtml(approverName) + ',</p>' +
            '<p>A request for temporary Salesforce access needs your review. Approve or reject the request.</p>' +
            detailBlock(row);
    }

    private static String expiringBody(TemporaryAccessException__c row) {
        return '<p>Hi ' + escapeHtml(createdByFirstName(row)) + ',</p>' +
            '<p>Temporary access is expiring in 3 days for the request below.</p>' +
            detailTable(row, 'Created By', createdByName(row)) +
            supportFooter();
    }

    private static List<Recipient> standardCopies(TemporaryAccessException__c row, User approver) {
        return new List<Recipient>{
            userRecipient(row.CreatedById, row.CreatedBy),
            userRecipient(row.Requester__c, row.Requester__r),
            userRecipient(row.CoverageRep__c, row.CoverageRep__r),
            delegatedApproverRecipient(approver)
        };
    }

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
            Id delegateId = row.Requester__r == null || row.Requester__r.Manager == null
                ? null
                : row.Requester__r.Manager.DelegatedApproverId;
            if (delegateId != null && delegateId.getSObjectType() == User.SObjectType) {
                delegateIds.add(delegateId);
            }
        }
        delegatedApproversById = delegateIds.isEmpty()
            ? new Map<Id, User>()
            : new Map<Id, User>([SELECT Id, Email, IsActive FROM User WHERE Id IN :delegateIds]);
    }

    private static String grantedBody(TemporaryAccessException__c row) {
        return '<p>Hi ' + escapeHtml(createdByFirstName(row)) + ',</p>' +
            '<p>Temporary Salesforce access has been approved for the following request:</p>' +
            detailTable(row, 'Created By', createdByName(row)) +
            '<p>Access will automatically expire on ' + formatDate(row.EndDate__c) + ' unless an extension is requested.</p>' +
            supportFooter();
    }

    private static String rejectedBody(TemporaryAccessException__c row) {
        return '<p>Hi ' + escapeHtml(createdByFirstName(row)) + ',</p>' +
            '<p>Temporary Salesforce access has been rejected for the following request:</p>' +
            detailTable(row, 'Created By', createdByName(row)) +
            '<p>Please reach out to your manager with any questions or concerns.</p>' +
            supportFooter();
    }

    private static String expiredBody(TemporaryAccessException__c row) {
        return '<p>Hi ' + escapeHtml(createdByFirstName(row)) + ',</p>' +
            '<p>Temporary coverage access has expired and access has been removed for the following request:</p>' +
            detailTable(row, 'Request Created By', createdByName(row)) +
            supportFooter();
    }

    private static String coverageGrantedBody(TemporaryAccessException__c row) {
        return '<p>Hi,</p>' +
            '<p>Based on the Temporary Access Exception: ' + escapeHtml(row.Name) +
            ' approval initiated by Requester: ' + escapeHtml(row.RequesterName__c) +
            ' for Coverage Rep: ' + escapeHtml(row.CoverageRepName__c) + '</p>' +
            '<p>Expiry Date: ' + formatDate(row.EndDate__c) + '</p>' +
            '<p>Temporary coverage access has been granted and will remain active until the expiry date above.</p>' +
            '<p>Please contact the Life Sciences Sales support team at lsprojects@steris.com with any questions.</p>' +
            '<p>Thanks</p>';
    }

    private static String coverageRevokedBody(TemporaryAccessException__c row) {
        return '<p>Hi,</p>' +
            '<p>Based on the Temporary Access Exception: ' + escapeHtml(row.Name) +
            ' approval initiated by Requester: ' + escapeHtml(row.RequesterName__c) +
            ' for Coverage Rep: ' + escapeHtml(row.CoverageRepName__c) + '</p>' +
            '<p>Expiry Date: ' + formatDate(row.EndDate__c) + '</p>' +
            '<p>Temporary coverage access has been revoked due to the expiration of the Temporary Access Exception request mentioned above.</p>' +
            '<p>Please contact the Life Sciences Sales support team at lsprojects@steris.com with any questions.</p>' +
            '<p>Thanks</p>';
    }

    private static String detailBlock(TemporaryAccessException__c row) {
        String link = recordUrl(row.Id);
        return '<p>Temporary Access Exception: <a href="' + link + '">' + escapeHtml(row.Name) + '</a></p>' +
            '<p>Rep Needing Coverage: ' + escapeHtml(row.RequesterName__c) + '</p>' +
            '<p>Coverage Rep: ' + escapeHtml(row.CoverageRepName__c) + '</p>' +
            '<p>Start Date: ' + formatDate(row.StartDate__c) + '</p>' +
            '<p>End Date: ' + formatDate(row.EndDate__c) + '</p>' +
            '<p>Coverage Duration (Days): ' + (row.Duration__c == null ? '' : String.valueOf(row.Duration__c.intValue())) + '</p>' +
            '<p>Exception Category: ' + escapeHtml(row.ExceptionCategory__c) + '</p>' +
            '<p>Business Justification: ' + escapeHtml(row.BusinessJustification__c) + '</p>';
    }

    private static String detailTable(TemporaryAccessException__c row, String createdByLabel, String createdByName) {
        return '<table border="1" cellpadding="6" cellspacing="0">' +
            rowHtml('Temporary Request ID', '<a href="' + recordUrl(row.Id) + '">' + escapeHtml(row.Name) + '</a>') +
            rowHtml('Rep Needing Coverage', escapeHtml(row.RequesterName__c)) +
            rowHtml('Coverage Rep', escapeHtml(row.CoverageRepName__c)) +
            rowHtml(createdByLabel, escapeHtml(createdByName)) +
            rowHtml('Exception Category', escapeHtml(row.ExceptionCategory__c)) +
            rowHtml('Business Justification', escapeHtml(row.BusinessJustification__c)) +
            rowHtml('Start Date', formatDate(row.StartDate__c)) +
            rowHtml('End Date', formatDate(row.EndDate__c)) +
            rowHtml('Duration (Days)', row.Duration__c == null ? '' : String.valueOf(row.Duration__c.intValue())) +
            rowHtml('Territory Number(s)', '') +
            '</table>';
    }

    private static String rowHtml(String label, String value) {
        return '<tr><td>' + label + '</td><td>' + value + '</td></tr>';
    }

    private static String supportFooter() {
        return '<p>If you have questions, contact <a href="mailto:lsprojects@steris.com">lsprojects@steris.com</a>.</p>';
    }

    private static String createdByFirstName(TemporaryAccessException__c row) {
        return row.CreatedBy == null ? '' : row.CreatedBy.FirstName;
    }

    private static String createdByName(TemporaryAccessException__c row) {
        return row.CreatedBy == null ? '' : row.CreatedBy.Name;
    }

    private static String recordUrl(Id recordId) {
        return URL.getOrgDomainUrl().toExternalForm() + '/' + recordId;
    }

    private static String formatDate(Date value) {
        if (value == null) {
            return '';
        }
        return Datetime.newInstance(value.year(), value.month(), value.day()).format('d-MMM-yyyy');
    }

    private static String escapeHtml(String value) {
        if (value == null) {
            return '';
        }
        return value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
    }
}