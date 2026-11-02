/**
 * @author PSL
 * @date 12-10-2025
 * @description Controller for handling reply threads (internal/external) for cases
 */
public with sharing class ReplyThreadInternalExternalController {
    public Id caseId { get; set; }
    public String threadType { get; set; }

    
	@TestVisible private static Boolean SIMULATE_RESOLVE_INTERNAL_ERROR = false;
    @TestVisible private static Boolean SIMULATE_GET_LATEST_EMAIL_ERROR = false;

    private EmailMessage latest;
	
    /**
     * @description Determines if the thread is internal or external
     * @return True if internal, false if external
     */
    @TestVisible
    private Boolean resolveInternal() {
        try {
            if (threadType==null) {
                ErrorLogger.logMessage('threadType is null', 'ReplyThreadInternalExternalController', 'resolveInternal', ErrorLogger.Level.WARN);
                return true;
            }
            if (threadType=='Internal'){
                return true;
            }else if(threadType=='External'){
                return False;
            }
            ErrorLogger.logMessage('Unknown threadType: ' + threadType, 'ReplyThreadInternalExternalController', 'resolveInternal', ErrorLogger.Level.WARN);
            return true;
        } catch (Exception e) {
            ErrorLogger.logException(e, 'ReplyThreadInternalExternalController', 'resolveInternal');
            return true;
        }
    }

    /**
     * @description Gets the latest email message for the case
     * @return EmailMessage object or null if not found
     */
    public EmailMessage getLatestEmail() {
        try {
            if (latest != null) return latest;
            if (caseId == null) return null;

            Boolean isInternal = resolveInternal();
            
            system.debug('isInternal +++'+isInternal);

            List<EmailMessage> emails = [
                SELECT Id, Subject,
                       FromName, FromAddress,
                       ToAddress, CcAddress, BccAddress,
                       CreatedDate, MessageDate,
                       TextBody, HtmlBody
                FROM EmailMessage
                WHERE ParentId = :caseId
                  AND IsInternal__c = :isInternal
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            latest = emails.isEmpty() ? null : emails[0];
            return latest;
        } catch (Exception e) {
            ErrorLogger.logException(e, 'ReplyThreadInternalExternalController', 'getLatestEmail');
            return null;
        }
    }

    /**
     * @description Gets the display format for the email sender
     * @return Formatted sender string
     */
    public String getFromDisplay() {
        EmailMessage em = getLatestEmail();
        if (em == null) return '';
        return String.isNotBlank(em.FromName)
            ? em.FromName + ' [' + safe(em.FromAddress) + ']'
            : safe(em.FromAddress);
    }
    
    
    /**
     * @description Gets the subject of the latest email
     * @return Email subject or empty string
     */
    public String getSubject() {
            EmailMessage em = getLatestEmail();
            return (em != null && em.Subject != null) ? em.Subject : '';
        }


    /**
     * @description Gets the formatted sent date of the latest email
     * @return Formatted sent date string
     */
    public String getSentFormatted() {
        EmailMessage em = getLatestEmail();
        if (em == null) return '';
        Datetime sent = (em.MessageDate != null) ? em.MessageDate : em.CreatedDate;
        return formatLocal(sent);
    }

    /**
     * @description Checks if there is a latest email to display
     * @return True if latest email exists, false otherwise
     */
    public boolean getTitle() {
        EmailMessage em = getLatestEmail();
        return em != null ? true : false;
    }

    /**
     * @description Gets the display format for the email To addresses
     * @return Formatted To addresses string
     */
    public String getToDisplay()  { return normalizeAddresses(getLatestEmail() == null ? null : getLatestEmail().ToAddress); }
    /**
     * @description Gets the display format for the email CC addresses
     * @return Formatted CC addresses string
     */
    public String getCcDisplay()  { return normalizeAddresses(getLatestEmail() == null ? null : getLatestEmail().CcAddress); }
    /**
     * @description Gets the display format for the email BCC addresses
     * @return Formatted BCC addresses string
     */
    public String getBccDisplay() { return normalizeAddresses(getLatestEmail() == null ? null : getLatestEmail().BccAddress); }

    /**
     * @description Gets the HTML body of the latest email
     * @return HTML body content or empty string
     */
    public String getBodyHtml() {
        EmailMessage em = getLatestEmail();
        if (em == null) return '';
        if (String.isNotBlank(em.HtmlBody)) return em.HtmlBody;
        if (String.isNotBlank(em.TextBody)) {
            return '<pre style="font-family:inherit; white-space:pre-wrap;">' + escapeHtml(em.TextBody) + '</pre>';
        }
        return '';
    }

    /**
     * @description Formats a datetime object to local format
     * @param dt Datetime object to format
     * @return Formatted datetime string
     */
    private String formatLocal(Datetime dt) {
        if (dt == null) return '';
        return dt.format('MM/dd/yyyy, hh:mm a', UserInfo.getTimeZone().getID());
    }

    /**
     * @description Normalizes email addresses by splitting and trimming
     * @param addresses String of email addresses separated by semicolons
     * @return Normalized addresses string
     */
    private String normalizeAddresses(String addresses) {
        if (String.isBlank(addresses)) return '';
        List<String> parts = new List<String>();
        for (String s : addresses.split(';')) {
            String t = s == null ? '' : s.trim();
            if (t != '') parts.add(t);
        }
        return String.join(parts, ', ');
    }

    /**
     * @description Escapes HTML characters in a string
     * @param s String to escape
     * @return Escaped string
     */
    private String escapeHtml(String s) {
        if (s == null) return '';
        s = s.replace('&', '&');
        s = s.replace('<', '<');
        s = s.replace('>', '>');
        return s;
    }

    /**
     * @description Safely returns a string or empty string if null
     * @param s String to check
     * @return Original string or empty string if null
     */
    private String safe(String s) {
        return s == null ? '' : s;
    }
}