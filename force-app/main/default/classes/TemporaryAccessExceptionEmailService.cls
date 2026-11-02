/**
 * @author Suraj Thapliyal
 * @date 2026/06/15
 * @description GC-2580 - Builds and sends Apex HTML emails for Temporary Access Exception grant and revoke events.
 *              GC-3189 - Territory Number table and updated email body layout (expiry date, support contact).
 *              No Email Templates are required; notifications include basic request context only.
 *              Internal recipients (User records) are addressed via setTargetObjectId to reduce daily single-email usage.
 */
public with sharing class TemporaryAccessExceptionEmailService {

    public static final String SUBJECT_GRANT = 'Temporary Coverage Access Granted';
    public static final String SUBJECT_REVOKE = 'Temporary Coverage Access Revoked';
    private static final String SUPPORT_EMAIL = Label.TAE_HealthcareSalesSupportEmail;

    // GC-3189 - HTML email layout and styling constants
    private static final String EMAIL_FONT_STYLE =
        'font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#333333;line-height:1.35;';
    private static final String EMAIL_SECTION_PADDING = 'padding:0 0 8px 0;margin:0;';
    private static final String EMAIL_BOLD_STYLE = 'font-weight:bold;';
    private static final String EMAIL_LINK_STYLE = 'color:#0176d3;text-decoration:underline;';
    private static final String EMAIL_TABLE_STYLE = 'border-collapse:collapse;margin:8px 0 0 0;';
    private static final String EMAIL_TH_STYLE =
        'border:1px solid #dddbda;padding:6px 8px;background-color:#f3f2f2;text-align:left;' + EMAIL_BOLD_STYLE;
    private static final String EMAIL_TD_STYLE = 'border:1px solid #dddbda;padding:6px 8px;';

    private static final Integer DEFAULT_EMAIL_CHUNK_SIZE = 100;
    private static final Integer PLATFORM_MAX_EMAIL_CHUNK_SIZE = 100;
	private static final String TAE_BATCH_CLASS_NAME = 'TemporaryAccessExceptionBatch';
    
    @TestVisible
    private static Boolean skipSendForTest = false;

    @TestVisible
    private static Boolean testOnly_simulateSendFailure = false;

    @TestVisible
    private static Integer testOnly_emailChunkSizeOverride;

    /**
     * @description One composed email paired with its source TemporaryAccessException__c Id for logging.
     */
    private class EmailSendItem {
        Messaging.SingleEmailMessage message;
        Id taeId;
    }

    /**
     * @description Input for one grant or revoke notification email.
     */
    public class NotificationRequest {
        public TemporaryAccessException__c taeRow;
        public Boolean isGrant;
        /** GC-3189 - Distinct TerritoryID__c values for Rep Needing Coverage (Requester__c), sorted alphabetically. */
        public List<String> territoryIds;
    }

    /**
     * @description GC-3179 - Modified: builds one SingleEmailMessage per recipient via buildEmailMessages().
     * @param requests Notification payloads for successfully processed rows; null or empty lists are ignored.
     * @param usersById Preloaded User records keyed by Id (from TemporaryAccessExceptionSelector.selectUsersById).
     * @return void
     */
    public static void sendBulkNotifications(
        List<NotificationRequest> requests,
        Map<Id, User> usersById
    ) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        String orgBaseUrl = URL.getOrgDomainUrl().toExternalForm();
        List<EmailSendItem> sendItems = new List<EmailSendItem>();

        for (NotificationRequest request : requests) {
            for (Messaging.SingleEmailMessage mail : buildEmailMessages(
                request,
                usersById,
                orgBaseUrl
            )) {
                EmailSendItem item = new EmailSendItem();
                item.message = mail;
                item.taeId = request.taeRow.Id;
                sendItems.add(item);
            }
        }

        if (sendItems.isEmpty()) {
            return;
        }

        if (Test.isRunningTest() && skipSendForTest) {
            Logger.debug(
                'TemporaryAccessExceptionEmailService.sendBulkNotifications: skipped send for test, count=' +
                sendItems.size()
            );
            return;
        }

        sendEmailInChunks(sendItems);
    }

    /**
     * @description GC-3179 - Modified: uses setTargetObjectId and setTreatTargetObjectAsRecipient for internal users.
     * @param request Notification payload for one TemporaryAccessException__c row.
     * @param usersById Preloaded User records keyed by Id.
     * @param orgBaseUrl Org domain URL for Lightning record links.
     * @return SingleEmailMessage instances ready to send (empty when no recipients exist).
     */
    private static List<Messaging.SingleEmailMessage> buildEmailMessages(
        NotificationRequest request,
        Map<Id, User> usersById,
        String orgBaseUrl
    ) {
        List<Id> recipientUserIds = resolveRecipientUserIds(request.taeRow, usersById);
        if (recipientUserIds.isEmpty()) {
            Logger.warn(
                'TemporaryAccessExceptionEmailService.buildEmailMessages: no recipients for taeId=' +
                request.taeRow.Id
            );
            return new List<Messaging.SingleEmailMessage>();
        }

        Boolean isGrant = request.isGrant == true;
        String subject = isGrant ? SUBJECT_GRANT : SUBJECT_REVOKE;

        User requester = usersById.get(request.taeRow.Requester__c);
        User coverageRep = usersById.get(request.taeRow.CoverageRep__c);

        String htmlBody = buildHtmlBody(
            isGrant,
            request.taeRow,
            requester,
            coverageRep,
            orgBaseUrl,
            request.territoryIds
        );

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Id recipientUserId : recipientUserIds) {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTargetObjectId(recipientUserId);
            mail.setTreatTargetObjectAsRecipient(true);
            mail.setSubject(subject);
            mail.setHtmlBody(htmlBody);
            mail.setSaveAsActivity(false);
            messages.add(mail);
        }
        return messages;
    }

    /**
     * @description GC-3179 - Reads EmailChunkSize__c from active BatchProcessConfig__mdt for TAE batch emails.
     * @return Configured chunk size capped at platform max, or DEFAULT_EMAIL_CHUNK_SIZE when config is absent or invalid.
     */
    private static Integer resolveEmailChunkSize() {
        if (Test.isRunningTest() && testOnly_emailChunkSizeOverride != null) {
            return testOnly_emailChunkSizeOverride;
        }

        BatchProcessConfig__mdt config = BatchProcessConfigSelector.selectActiveByBatchClassName(
			TAE_BATCH_CLASS_NAME
        );
        if (config != null && config.EmailChunkSize__c != null) {
            Integer configuredSize = config.EmailChunkSize__c.intValue();
            if (configuredSize > 0) {
                return Math.min(configuredSize, PLATFORM_MAX_EMAIL_CHUNK_SIZE);
            }
            Logger.warn(
                'TemporaryAccessExceptionEmailService.resolveEmailChunkSize: invalid EmailChunkSize__c=' +
                configuredSize + '; using fallback=' + DEFAULT_EMAIL_CHUNK_SIZE
            );
        } else {
            Logger.warn(
                'TemporaryAccessExceptionEmailService.resolveEmailChunkSize: no active BatchProcessConfig__mdt; using fallback=' +
                DEFAULT_EMAIL_CHUNK_SIZE
            );
        }
        return DEFAULT_EMAIL_CHUNK_SIZE;
    }

    /**
     * @description Sends email items in chunks per BatchProcessConfig__mdt EmailChunkSize__c and logs per-message results.
     * @param sendItems Composed emails paired with their TemporaryAccessException__c Ids.
     * @return void
     */
    private static void sendEmailInChunks(List<EmailSendItem> sendItems) {
        Integer emailChunkSize = resolveEmailChunkSize();
        List<Messaging.SingleEmailMessage> chunk = new List<Messaging.SingleEmailMessage>();
        List<Id> chunkTaeIds = new List<Id>();

        for (EmailSendItem item : sendItems) {
            chunk.add(item.message);
            chunkTaeIds.add(item.taeId);

            if (chunk.size() == emailChunkSize) {
                sendChunkAndLog(chunk, chunkTaeIds);
                chunk.clear();
                chunkTaeIds.clear();
            }
        }

        if (!chunk.isEmpty()) {
            sendChunkAndLog(chunk, chunkTaeIds);
        }
    }

    /**
     * @description Sends one chunk and logs success or failure for each message.
     * @param chunk Up to configured email chunk size messages to send.
     * @param taeIds TemporaryAccessException__c Ids aligned to each message in the chunk.
     * @return void
     */
    private static void sendChunkAndLog(
        List<Messaging.SingleEmailMessage> chunk,
        List<Id> taeIds
    ) {
        if (Test.isRunningTest() && testOnly_simulateSendFailure) {
            for (Integer i = 0; i < chunk.size(); i++) {
                logSendResult(taeIds[i], null);
            }
            return;
        }

        Messaging.SendEmailResult[] results = Messaging.sendEmail(chunk, false);

        for (Integer i = 0; i < results.size(); i++) {
            logSendResult(taeIds[i], results[i]);
        }
    }

    /**
     * @description Logs the outcome of a single email send attempt.
     * @param taeId TemporaryAccessException__c Id associated with the message.
     * @param result Send result from Messaging.sendEmail.
     * @return void
     */
    private static void logSendResult(Id taeId, Messaging.SendEmailResult result) {
        if (result != null && result.isSuccess()) {
            Logger.debug(
                'TemporaryAccessExceptionEmailService.sendBulkNotifications: sent for taeId=' + taeId
            );
            return;
        }

        String errorDetail = result == null ? 'Unknown error' : formatSendErrors(result);
        Logger.error(
            'TemporaryAccessExceptionEmailService.sendBulkNotifications: send failed for taeId=' +
            taeId + ' ' + errorDetail
        );
    }

    /**
     * @description Formats all SendEmailError entries from a failed send result.
     * @param result Send result from Messaging.sendEmail.
     * @return Semicolon-delimited status code and message pairs.
     */
    private static String formatSendErrors(Messaging.SendEmailResult result) {
        if (result.getErrors().isEmpty()) {
            return 'Unknown error';
        }

        List<String> messages = new List<String>();
        for (Messaging.SendEmailError err : result.getErrors()) {
            messages.add(err.getStatusCode() + ': ' + err.getMessage());
        }
        return String.join(messages, '; ');
    }

    /**
     * @description GC-3179 - Modified: resolves User Ids for setTargetObjectId instead of toAddresses.
     * @param taeRow TemporaryAccessException__c row.
     * @param usersById Preloaded User records keyed by Id.
     * @return List of active User Ids with email (deduplicated).
     */
    private static List<Id> resolveRecipientUserIds(
        TemporaryAccessException__c taeRow,
        Map<Id, User> usersById
    ) {
        Set<Id> recipientUserIds = new Set<Id>();

        addRecipientUserId(recipientUserIds, usersById.get(taeRow.Requester__c));
        addRecipientUserId(recipientUserIds, usersById.get(taeRow.CoverageRep__c));

        return new List<Id>(recipientUserIds);
    }

    /**
     * @description GC-3179 - Modified: supports User Id recipients
     *  for setTargetObjectId email delivery.
     * @param recipientUserIds Accumulator set for User Ids.
     * @param user User record to evaluate.
     * @return void
     */
    private static void addRecipientUserId(Set<Id> recipientUserIds, User user) {
        if (user != null && user.IsActive && String.isNotBlank(user.Email)) {
            recipientUserIds.add(user.Id);
        }
    }

    /**
     * @description GC-3189 - Builds the HTML email body with requester, coverage rep, territory, and expiry date context.
     * @param isGrant True for grant notifications; false for revoke notifications.
     * @param taeRow TemporaryAccessException__c row.
     * @param requester Requester user (may be null).
     * @param coverageRep Coverage rep user (may be null).
     * @param orgBaseUrl Org domain URL for Lightning record links.
     * @param territoryIds Distinct TerritoryID__c values for Rep Needing Coverage; may be empty.
     * @return HTML string for the email body.
     */
    private static String buildHtmlBody(
        Boolean isGrant,
        TemporaryAccessException__c taeRow,
        User requester,
        User coverageRep,
        String orgBaseUrl,
        List<String> territoryIds
    ) {
        String requesterName = requester != null ? requester.Name : 'N/A';
        String coverageRepName = coverageRep != null ? coverageRep.Name : 'N/A';
        String expiryDateDisplay = formatExpiryDate(taeRow.EndDate__c);
        String actionParagraph = isGrant == true
            ? 'Temporary coverage access has been granted and will remain active until the expiry date above.'
            : 'Temporary coverage access has been revoked due to the expiration of the Temporary Access Exception request mentioned above.';

        String taeRecordUrl = orgBaseUrl + '/lightning/r/TemporaryAccessException__c/' + taeRow.Id + '/view';
        String taeNameLink = '<a href="' + escapeHtml(taeRecordUrl) + '" style="' + EMAIL_LINK_STYLE + '">' +
            escapeHtml(taeRow.Name) +
            '</a>';

        String html = '<html><body style="margin:0;padding:0;">';
        html += '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="' +
            EMAIL_FONT_STYLE + '">';
        html += emailSection('Hi,');
        html += emailSection(
            'Based on the <span style="' + EMAIL_BOLD_STYLE + '">Temporary Access Exception:</span> ' +
            taeNameLink +
            ' approval initiated by <span style="' + EMAIL_BOLD_STYLE + '">Requester:</span> ' +
            escapeHtml(requesterName) +
            ' for <span style="' + EMAIL_BOLD_STYLE + '">Coverage Rep:</span> ' +
            escapeHtml(coverageRepName)
        );
        html += emailSection(
            '<span style="' + EMAIL_BOLD_STYLE + '">Expiry Date:</span> ' +
            escapeHtml(expiryDateDisplay)
        );
        String territorySection = buildTerritoryIdSection(isGrant, territoryIds);
        if (String.isNotBlank(territorySection)) {
            html += emailSection(territorySection);
        }
        html += emailSection(escapeHtml(actionParagraph));
        html += emailSection(buildSupportContactSection());
        html += emailSection('Thanks', false);
        html += '</table></body></html>';
        return html;
    }

    /**
     * @description GC-3189 - Builds the Territory Number section with a two-column table when values exist.
     * @param isGrant True for grant notifications; false for revoke notifications.
     * @param territoryIds Sorted unique TerritoryID__c external Ids for Rep Needing Coverage.
     * @return HTML section content, or null when no territory Ids are available.
     */
    private static String buildTerritoryIdSection(Boolean isGrant, List<String> territoryIds) {
        if (territoryIds == null || territoryIds.isEmpty()) {
            return null;
        }

        String territoryAction = isGrant == true ? 'assigned' : 'revoked';
        String section = 'The following <span style="' + EMAIL_BOLD_STYLE + '">Territory Number(s)</span> have been ' +
            territoryAction + ':';
        section += buildTerritoryNumberTable(territoryIds);
        return section;
    }

    /**
     * @description GC-3189 - Builds a two-column HTML table listing territory numbers with serial numbers.
     * @param territoryIds Territory numbers to display in table row order.
     * @return HTML table markup.
     */
    private static String buildTerritoryNumberTable(List<String> territoryIds) {
        String table = '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="' +
            EMAIL_TABLE_STYLE + EMAIL_FONT_STYLE + '">';
        table += '<tr>';
        table += '<th style="' + EMAIL_TH_STYLE + 'width:60px;text-align:center;">S.No</th>';
        table += '<th style="' + EMAIL_TH_STYLE + '">Territory Number</th>';
        table += '</tr>';

        Integer serialNumber = 1;
        for (String territoryId : territoryIds) {
            table += '<tr>';
            table += '<td style="' + EMAIL_TD_STYLE + 'text-align:center;">' + serialNumber + '</td>';
            table += '<td style="' + EMAIL_TD_STYLE + '">' + escapeHtml(territoryId) + '</td>';
            table += '</tr>';
            serialNumber++;
        }

        table += '</table>';
        return table;
    }

    /**
     * @description GC-3189 - Builds the Healthcare Sales support contact paragraph for grant and revoke emails.
     * @return HTML section content with a mailto link to the support mailbox.
     */
    private static String buildSupportContactSection() {
        String mailtoUrl = 'mailto:' + SUPPORT_EMAIL;
        return 'For assistance related to temporary coverage, please contact the Healthcare Sales support mailbox at ' +
            '<a href="' + escapeHtml(mailtoUrl) + '" style="' + EMAIL_LINK_STYLE + '">' +
            escapeHtml(SUPPORT_EMAIL) +
            '</a>.';
    }

    /**
     * @description GC-3189 - Wraps one email paragraph row with consistent spacing.
     * @param content HTML-safe section content.
     * @param addBottomSpacing True to add a single line gap after the section.
     * @return Table row fragment.
     */
    private static String emailSection(String content, Boolean addBottomSpacing) {
        String padding = addBottomSpacing == true ? EMAIL_SECTION_PADDING : 'padding:0;margin:0;';
        return '<tr><td style="' + padding + EMAIL_FONT_STYLE + '">' + content + '</td></tr>';
    }

    private static String emailSection(String content) {
        return emailSection(content, true);
    }

    /**
     * @description GC-3189 - Formats the TAE end date for display in notification emails (for example, 13-Jul-26).
     * @param expiryDate TemporaryAccessException__c.EndDate__c value.
     * @return Date string in d-MMM-yy format, or N/A when null.
     */
    private static String formatExpiryDate(Date expiryDate) {
        if (expiryDate == null) {
            return 'N/A';
        }
        return Datetime.newInstance(
            expiryDate.year(),
            expiryDate.month(),
            expiryDate.day()
        ).format('d-MMM-yy');
    }

    /**
     * @description GC-3189 -
     * Test-only entry to exercise expiry date formatting for notification emails.
     * @param expiryDate TemporaryAccessException__c.EndDate__c value.
     * @return Formatted date string.
     */
    @TestVisible
    private static String testOnly_formatExpiryDate(Date expiryDate) {
        return formatExpiryDate(expiryDate);
    }

    /**
     * @description Escapes HTML special characters for safe email body composition.
     * @param value Raw string value.
     * @return HTML-escaped string.
     */
    private static String escapeHtml(String value) {
        if (value == null) {
            return '';
        }
        return value.escapeHtml4();
    }

    /** GC-3189 - Test-only entry to exercise territory section HTML without sending email. */
    @TestVisible
    private static String testOnly_buildTerritoryIdSection(Boolean isGrant, List<String> territoryIds) {
        return buildTerritoryIdSection(isGrant, territoryIds);
    }

    /**
     * @description GC-3189 -
     * Test-only entry to exercise HTML territory rendering without sending email.
     * @param request Notification payload including territoryIds.
     * @param usersById Preloaded User records keyed by Id.
     * @return HTML email body string.
     */
    @TestVisible
    private static String testOnly_buildHtmlBodyForRequest(
        NotificationRequest request,
        Map<Id, User> usersById
    ) {
        return buildHtmlBody(
            request.isGrant == true,
            request.taeRow,
            usersById.get(request.taeRow.Requester__c),
            usersById.get(request.taeRow.CoverageRep__c),
            URL.getOrgDomainUrl().toExternalForm(),
            request.territoryIds
        );
    }

    /**
     * @description
     * Test-only entry to exercise logSendResult and formatSendErrors for failed sends.
     * @return void
     */
    @TestVisible
    private static void testOnly_invokeFailedSendResultLogging() {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setSubject('Temporary Access Exception Test');
        mail.setHtmlBody('<p>Test</p>');

        for (Messaging.SendEmailResult result : Messaging.sendEmail(
            new List<Messaging.SingleEmailMessage>{ mail },
            false
        )) {
            logSendResult(UserInfo.getUserId(), result);
        }
    }
}