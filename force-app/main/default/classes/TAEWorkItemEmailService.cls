/**
 * GC-3420 - Email for a completed work-item grant or revoke.
 * @author Suraj Thapliyal
 * @date 2026/09/29
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-3420 - Sends the same HTML notice as TemporaryAccessExceptionEmailService
 * after finalize sets the exception to Active or Expired.
 * Recipients are the Requester and the Coverage Rep. The body includes the
 * request link, names, expiry date, territory-number table, and support contact.
 * Both recipients share one HTML body. Messages go out in one Messaging.sendEmail
 * call per 100, and only while an email invocation remains. Internal users are
 * addressed with setTargetObjectId, so the daily external-email limit is not used.
 * A send failure is logged and does not stop the pipeline.
 * This class does not call TemporaryAccessExceptionEmailService.
 * Tests set isSendSkippedForTest so Messaging.sendEmail is not called.
 */
public with sharing class TAEWorkItemEmailService {
    /**
     * @description Subject used when coverage access is granted.
     */
    public static final String SUBJECT_GRANT = 'Temporary Coverage Access Granted';
    /**
     * @description Subject used when coverage access is revoked.
     */
    public static final String SUBJECT_REVOKE = 'Temporary Coverage Access Revoked';

    private static final String SUPPORT_EMAIL = Label.TAE_HealthcareSalesSupportEmail;
    private static final String EMAIL_FONT_STYLE =
        'font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#333333;line-height:1.35;';
    private static final String EMAIL_SECTION_PADDING = 'padding:0 0 8px 0;margin:0;';
    private static final String EMAIL_BOLD_STYLE = 'font-weight:bold;';
    private static final String EMAIL_LINK_STYLE = 'color:#0176d3;text-decoration:underline;';
    private static final String EMAIL_TABLE_STYLE = 'border-collapse:collapse;margin:8px 0 0 0;';
    private static final String EMAIL_TH_STYLE =
        'border:1px solid #dddbda;padding:6px 8px;background-color:#f3f2f2;text-align:left;' +
        EMAIL_BOLD_STYLE;
    private static final String EMAIL_TD_STYLE = 'border:1px solid #dddbda;padding:6px 8px;';
    private static final String GRANT_ACTION =
        'Temporary coverage access has been granted and will remain active until the expiry date above.';
    private static final String REVOKE_ACTION =
        'Temporary coverage access has been revoked due to the expiration of the Temporary Access Exception request mentioned above.';
    private static final String TERRITORY_ASSIGNED = 'assigned';
    private static final String TERRITORY_REVOKED = 'revoked';
    private static final String DISPLAY_NOT_AVAILABLE = 'N/A';
    /**
     * @description Platform maximum of SingleEmailMessage rows in one sendEmail call.
     */
    private static final Integer EMAIL_CHUNK_SIZE = 100;

    /**
     * @description When true, the notice is not sent. Tests set this. Production leaves it false.
     */
    @TestVisible
    private static Boolean isSendSkippedForTest = false;

    /**
     * @description Emails the Requester and Coverage Rep that coverage access was granted.
     * @param exceptionId TemporaryAccessException__c to describe in the body.
     */
    public static void sendGrant(Id exceptionId) {
        NoticeCopy copy = new NoticeCopy();
        copy.subject = SUBJECT_GRANT;
        copy.actionParagraph = GRANT_ACTION;
        copy.territoryAction = TERRITORY_ASSIGNED;
        sendNotice(exceptionId, copy);
    }

    /**
     * @description Emails the Requester and Coverage Rep that coverage access was revoked.
     * @param exceptionId TemporaryAccessException__c to describe in the body.
     */
    public static void sendRevoke(Id exceptionId) {
        NoticeCopy copy = new NoticeCopy();
        copy.subject = SUBJECT_REVOKE;
        copy.actionParagraph = REVOKE_ACTION;
        copy.territoryAction = TERRITORY_REVOKED;
        sendNotice(exceptionId, copy);
    }

    /**
     * @description Subject, closing sentence, and territory verb for one notice.
     */
    private class NoticeCopy {
        String subject;
        String actionParagraph;
        String territoryAction;
    }

    /**
     * @description Builds one HTML email per active recipient and sends them together.
     * @param exceptionId TemporaryAccessException__c to describe in the body.
     * @param copy Subject and sentences for a grant or a revoke.
     */
    private static void sendNotice(Id exceptionId, NoticeCopy copy) {
        TemporaryAccessException__c header = TAEWorkItemSelector.selectTae(exceptionId);
        if (header == null) {
            Logger.warn('TAEWorkItemEmailService.sendNotice: exception was not found ' + exceptionId);
        } else if (isSendSkippedForTest) {
            Logger.info('TAEWorkItemEmailService.sendNotice: send skipped for test ' + exceptionId);
        } else {
            Map<Id, User> usersById = selectUsers(header);
            List<Id> recipientIds = activeRecipientIds(header, usersById);
            if (recipientIds.isEmpty()) {
                Logger.info('TAEWorkItemEmailService.sendNotice: no email sent for ' + exceptionId);
            } else {
                NoticeContext context = new NoticeContext();
                context.header = header;
                context.requester = usersById.get(header.Requester__c);
                context.coverageRep = usersById.get(header.CoverageRep__c);
                context.copy = copy;
                context.territoryIds = territoryNumbers(header.Requester__c);
                String htmlBody = buildHtmlBody(context);
                List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
                for (Id recipientId : recipientIds) {
                    messages.add(buildMessage(recipientId, copy.subject, htmlBody));
                }
                sendInChunks(messages, exceptionId);
            }
        }
        Logger.saveLog();
    }

    /**
     * @description Loads the Requester and Coverage Rep for names and recipient checks.
     * @param header Exception whose user lookups are loaded.
     * @return User Id to User.
     */
    private static Map<Id, User> selectUsers(TemporaryAccessException__c header) {
        Set<Id> userIds = new Set<Id>{ header.Requester__c, header.CoverageRep__c };
        userIds.remove(null);
        Map<Id, User> usersById = new Map<Id, User>();
        if (!userIds.isEmpty()) {
            usersById = new Map<Id, User>([
                SELECT Id, Name, Email, IsActive
                FROM User
                WHERE Id IN :userIds
                WITH SYSTEM_MODE
            ]);
        }
        return usersById;
    }

    /**
     * @description Active users with an email address. The same person is included once.
     * @param header Exception being described.
     * @param usersById Requester and Coverage Rep records.
     * @return Recipient User Ids.
     */
    private static List<Id> activeRecipientIds(
        TemporaryAccessException__c header,
        Map<Id, User> usersById
    ) {
        Set<Id> recipientIds = new Set<Id>();
        addRecipient(recipientIds, usersById.get(header.Requester__c));
        addRecipient(recipientIds, usersById.get(header.CoverageRep__c));
        List<Id> recipients = new List<Id>(recipientIds);
        return recipients;
    }

    /**
     * @description Adds a user when the user is active and has an email address.
     * @param recipientIds Accumulator of User Ids.
     * @param recipient User to evaluate.
     */
    private static void addRecipient(Set<Id> recipientIds, User recipient) {
        if (recipient != null && recipient.IsActive && String.isNotBlank(recipient.Email)) {
            recipientIds.add(recipient.Id);
        }
    }

    /**
     * @description Distinct territory numbers for the Requester, sorted alphabetically.
     * One aggregate row is returned per territory, so order-line volume does not fill the query-row limit.
     * @param requesterId Requester user Id, the rep needing coverage.
     * @return TerritoryNumber__c values. Empty when the Requester has none.
     */
    private static List<String> territoryNumbers(Id requesterId) {
        Set<String> territoryNumbers = new Set<String>();
        if (requesterId != null) {
            for (AggregateResult row : [
                SELECT TerritoryNumber__c territoryNumber
                FROM OrderLineContact__c
                WHERE AssignedSalesRep__c = :requesterId
                  AND TerritoryNumber__c != null
                WITH SYSTEM_MODE
                GROUP BY TerritoryNumber__c
            ]) {
                String territoryNumber = (String) row.get('territoryNumber');
                if (territoryNumber != null) {
                    territoryNumber = territoryNumber.trim();
                }
                if (String.isNotBlank(territoryNumber)) {
                    territoryNumbers.add(territoryNumber);
                }
            }
        }
        List<String> sortedNumbers = new List<String>(territoryNumbers);
        sortedNumbers.sort();
        return sortedNumbers;
    }

    /**
     * @description Sends the prepared messages in platform-sized chunks.
     * Stops when the transaction has no email invocations left, and logs a failed chunk without throwing.
     * @param messages One message per recipient. The HTML body is already shared.
     * @param exceptionId TemporaryAccessException__c named in the log.
     */
    private static void sendInChunks(List<Messaging.SingleEmailMessage> messages, Id exceptionId) {
        Integer index = 0;
        Integer sentCount = 0;
        while (index < messages.size()) {
            Integer remainingInvocations =
                Limits.getLimitEmailInvocations() - Limits.getEmailInvocations();
            if (remainingInvocations <= 0) {
                Logger.warn(
                    'TAEWorkItemEmailService.sendNotice: email invocation limit reached, skipped ' +
                    (messages.size() - index) + ' notice(s) for ' + exceptionId
                );
                break;
            }
            Integer endIndex = index + EMAIL_CHUNK_SIZE;
            if (endIndex > messages.size()) {
                endIndex = messages.size();
            }
            List<Messaging.SingleEmailMessage> chunk = new List<Messaging.SingleEmailMessage>();
            for (Integer cursor = index; cursor < endIndex; cursor++) {
                chunk.add(messages[cursor]);
            }
            sentCount += sendChunk(chunk, exceptionId);
            index = endIndex;
        }
        Logger.info(
            'TAEWorkItemEmailService.sendNotice: sent ' + sentCount +
            ' notice(s) for ' + exceptionId
        );
    }

    /**
     * @description Sends one chunk. A platform exception is logged so finalize can continue the pipeline.
     * @param chunk At most EMAIL_CHUNK_SIZE messages.
     * @param exceptionId TemporaryAccessException__c named in the log.
     * @return Messages the platform accepted.
     */
    private static Integer sendChunk(List<Messaging.SingleEmailMessage> chunk, Id exceptionId) {
        Integer accepted = 0;
        try {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(chunk, false);
            for (Messaging.SendEmailResult result : results) {
                if (result.isSuccess()) {
                    accepted++;
                } else {
                    Logger.error(
                        'TAEWorkItemEmailService.sendNotice: send failed for ' + exceptionId +
                        ' ' + formatSendErrors(result)
                    );
                }
            }
        } catch (Exception sendError) {
            Logger.error('TAEWorkItemEmailService.sendNotice: ' + exceptionId, sendError);
        }
        return accepted;
    }

    /**
     * @description Formats the platform errors from one failed message.
     * @param result Send result for one recipient.
     * @return Status code and message text.
     */
    private static String formatSendErrors(Messaging.SendEmailResult result) {
        List<String> messages = new List<String>();
        for (Messaging.SendEmailError sendError : result.getErrors()) {
            messages.add(sendError.getStatusCode() + ': ' + sendError.getMessage());
        }
        String detail = 'Unknown error';
        if (!messages.isEmpty()) {
            detail = String.join(messages, '; ');
        }
        return detail;
    }

    /**
     * @description Builds one HTML message for an internal user.
     * @param recipientId User who receives the notice.
     * @param subject Email subject.
     * @param htmlBody HTML body matching the previous TAE notice.
     * @return Message ready to send.
     */
    private static Messaging.SingleEmailMessage buildMessage(
        Id recipientId,
        String subject,
        String htmlBody
    ) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(recipientId);
        message.setTreatTargetObjectAsRecipient(true);
        message.setSaveAsActivity(false);
        message.setSubject(subject);
        message.setHtmlBody(htmlBody);
        return message;
    }

    /**
     * @description Values needed to render one HTML notice.
     */
    private class NoticeContext {
        TemporaryAccessException__c header;
        User requester;
        User coverageRep;
        NoticeCopy copy;
        List<String> territoryIds;
    }

    /**
     * @description Builds the HTML body: greeting, request link, names, expiry, territories, and support.
     * @param context Exception, users, sentences, and territory numbers.
     * @return HTML email body.
     */
    private static String buildHtmlBody(NoticeContext context) {
        TemporaryAccessException__c header = context.header;
        User requester = context.requester;
        User coverageRep = context.coverageRep;
        NoticeCopy copy = context.copy;
        List<String> territoryIds = context.territoryIds;
        String requesterName = requester == null ? DISPLAY_NOT_AVAILABLE : requester.Name;
        String coverageRepName = coverageRep == null ? DISPLAY_NOT_AVAILABLE : coverageRep.Name;
        String recordUrl = URL.getOrgDomainUrl().toExternalForm() +
            '/lightning/r/TemporaryAccessException__c/' + header.Id + '/view';
        String nameLink = '<a href="' + escapeHtml(recordUrl) + '" style="' + EMAIL_LINK_STYLE + '">' +
            escapeHtml(header.Name) + '</a>';

        String html = '<html><body style="margin:0;padding:0;">';
        html += '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="' +
            EMAIL_FONT_STYLE + '">';
        html += emailSection('Hi,');
        html += emailSection(
            'Based on the <span style="' + EMAIL_BOLD_STYLE + '">Temporary Access Exception:</span> ' +
            nameLink +
            ' approval initiated by <span style="' + EMAIL_BOLD_STYLE + '">Requester:</span> ' +
            escapeHtml(requesterName) +
            ' for <span style="' + EMAIL_BOLD_STYLE + '">Coverage Rep:</span> ' +
            escapeHtml(coverageRepName)
        );
        html += emailSection(
            '<span style="' + EMAIL_BOLD_STYLE + '">Expiry Date:</span> ' +
            escapeHtml(formatExpiryDate(header.EndDate__c))
        );
        String territorySection = buildTerritorySection(copy.territoryAction, territoryIds);
        if (String.isNotBlank(territorySection)) {
            html += emailSection(territorySection);
        }
        html += emailSection(escapeHtml(copy.actionParagraph));
        html += emailSection(buildSupportSection());
        html += emailSectionWithoutGap('Thanks');
        html += '</table></body></html>';
        return html;
    }

    /**
     * @description Territory heading and table. Omitted when the Requester has no territory numbers.
     * @param territoryAction assigned or revoked.
     * @param territoryIds Sorted territory numbers.
     * @return HTML section, or null when the list is empty.
     */
    private static String buildTerritorySection(String territoryAction, List<String> territoryIds) {
        String section = null;
        if (territoryIds != null && !territoryIds.isEmpty()) {
            section = 'The following <span style="' + EMAIL_BOLD_STYLE + '">Territory Number(s)</span> have been ' +
                territoryAction + ':' + buildTerritoryTable(territoryIds);
        }
        return section;
    }

    /**
     * @description Two-column table of serial number and territory number.
     * @param territoryIds Territory numbers in display order.
     * @return HTML table.
     */
    private static String buildTerritoryTable(List<String> territoryIds) {
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
     * @description Support paragraph with a mailto link to the Healthcare Sales mailbox.
     * @return HTML section.
     */
    private static String buildSupportSection() {
        String mailtoUrl = 'mailto:' + SUPPORT_EMAIL;
        return 'For assistance related to temporary coverage, please contact the Healthcare Sales support mailbox at ' +
            '<a href="' + escapeHtml(mailtoUrl) + '" style="' + EMAIL_LINK_STYLE + '">' +
            escapeHtml(SUPPORT_EMAIL) + '</a>.';
    }

    /**
     * @description Wraps one paragraph with the standard gap underneath.
     * @param content HTML for the paragraph.
     * @return Table row fragment.
     */
    private static String emailSection(String content) {
        return '<tr><td style="' + EMAIL_SECTION_PADDING + EMAIL_FONT_STYLE + '">' + content + '</td></tr>';
    }

    /**
     * @description Wraps the closing line with no gap underneath.
     * @param content HTML for the paragraph.
     * @return Table row fragment.
     */
    private static String emailSectionWithoutGap(String content) {
        return '<tr><td style="padding:0;margin:0;' + EMAIL_FONT_STYLE + '">' + content + '</td></tr>';
    }

    /**
     * @description Formats the exception end date as d-MMM-yy, for example 13-Jul-26.
     * @param expiryDate TemporaryAccessException__c.EndDate__c.
     * @return Formatted date, or N/A when the date is blank.
     */
    private static String formatExpiryDate(Date expiryDate) {
        String formatted = DISPLAY_NOT_AVAILABLE;
        if (expiryDate != null) {
            formatted = Datetime.newInstance(
                expiryDate.year(),
                expiryDate.month(),
                expiryDate.day()
            ).format('d-MMM-yy');
        }
        return formatted;
    }

    /**
     * @description Escapes text placed into the HTML body.
     * @param value Raw text.
     * @return HTML-safe text.
     */
    private static String escapeHtml(String value) {
        String safeValue = '';
        if (value != null) {
            safeValue = value.escapeHtml4();
        }
        return safeValue;
    }
}